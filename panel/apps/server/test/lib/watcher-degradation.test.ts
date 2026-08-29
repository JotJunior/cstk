/**
 * Teste de integracao: sinalizacao de degradacao do WATCHER no detalhe de
 * execucao (task 2.4.3, CHK056/dec-027).
 *
 * GET /executions/:execucaoId consulta o cache em memoria do watcher
 * (apps/server/src/watchers/ingest-watcher.ts) pelo state-dir derivado da
 * execucao; quando a ultima ingestao em background falhou (mais recente que
 * o ultimo sucesso), a resposta ganha `meta.degraded:true` /
 * `meta.reason:'watcher-ingestion-failed'` SEM nulificar `data` — a execucao
 * em si foi lida com sucesso da knowledge.db.
 *
 * GET /executions (listagem) permanece inalterada (task 2.4.2 — granularidade
 * restrita ao endpoint de detalhe).
 */
import { describe, it, expect, beforeAll, afterAll, beforeEach, afterEach } from 'vitest';
import Fastify from 'fastify';
import cors from '@fastify/cors';
import type { FastifyInstance } from 'fastify';
import { mkdtempSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import Database from 'better-sqlite3';
import {
  resetWatcherCacheForTests,
  setWatcherCacheEntryForTests,
} from '../../src/watchers/ingest-watcher.js';

let tmpRoot: string;
let dbPath: string;

function makeExecutionsDb(path: string): void {
  const db = new Database(path);
  db.exec(`
    CREATE TABLE schema_meta (key TEXT PRIMARY KEY, value TEXT);
    INSERT INTO schema_meta VALUES ('schema_version', '2');
    CREATE TABLE executions (
      execution_id TEXT PRIMARY KEY, project TEXT, feature TEXT, status TEXT,
      termination_reason TEXT, current_stage TEXT, started_at TEXT, finished_at TEXT,
      duration_seconds REAL, suggested_stack TEXT, waves_total INTEGER,
      tool_calls_total INTEGER, wallclock_total_seconds REAL, subagents_spawned INTEGER,
      max_depth INTEGER, decisions_total INTEGER, human_blocks_total INTEGER,
      skill_suggestions_total INTEGER, toolkit_issues_opened INTEGER, session TEXT
    );
    INSERT INTO executions (execution_id, project, feature, status)
    VALUES ('exec-001', 'proj', 'my-feature', 'concluida');
  `);
  db.close();
}

async function buildServer(dbPathArg: string): Promise<FastifyInstance> {
  process.env['CSTK_KNOWLEDGE_DB'] = dbPathArg;

  const server = Fastify({ logger: false });
  await server.register(cors, { origin: 'http://localhost:5173', methods: ['GET', 'OPTIONS'] });
  server.addHook('onSend', async (_req, reply) => {
    void reply.header('Content-Type', 'application/json; charset=utf-8');
  });

  const { executionRoutes } = await import('../../src/routes/executions.js');
  await server.register(async v1 => {
    await v1.register(executionRoutes);
  }, { prefix: '/api/v1' });

  server.setNotFoundHandler((_req, reply) => {
    return reply.status(404).send({ data: null, meta: { degraded: false, reason: null, freshness: { mtime: '', maxIngestedAt: '' }, schemaVersion: '2' }, error: 'Not found' });
  });

  await server.ready();
  return server;
}

describe('GET /executions/:execucaoId — sinalizacao de degradacao do watcher (task 2.4)', () => {
  let server: FastifyInstance;
  let projectDir: string;
  let stateDir: string;

  beforeAll(async () => {
    tmpRoot = mkdtempSync(join(tmpdir(), 'cstk-watcher-degr-'));
    dbPath = join(tmpRoot, 'knowledge.db');
    makeExecutionsDb(dbPath);
    projectDir = join(tmpRoot, 'project');
    stateDir = join(projectDir, '.claude', 'feature-00c-state', 'my-feature');
    process.env['CSTK_PROJECT_PATHS'] = `proj=${projectDir}`;
    server = await buildServer(dbPath);
  });

  afterAll(async () => {
    await server.close();
    delete process.env['CSTK_PROJECT_PATHS'];
    delete process.env['CSTK_KNOWLEDGE_DB'];
    rmSync(tmpRoot, { recursive: true, force: true });
  });

  beforeEach(() => {
    resetWatcherCacheForTests();
  });
  afterEach(() => {
    resetWatcherCacheForTests();
  });

  it('sem entrada no cache do watcher ⇒ meta.degraded:false (comportamento normal)', async () => {
    const res = await server.inject({ method: 'GET', url: '/api/v1/executions/exec-001' });
    expect(res.statusCode).toBe(200);
    const body = res.json<{ data: unknown; meta: { degraded: boolean; reason: string | null } }>();
    expect(body.meta.degraded).toBe(false);
    expect(body.data).not.toBeNull();
  });

  it('falha registrada e mais recente que o ultimo sucesso ⇒ meta.degraded:true + reason, data preservado', async () => {
    setWatcherCacheEntryForTests(stateDir, {
      signature: 'sig-1',
      lastIngestAt: 1000,
      lastError: 'cstk exited with code 1',
      lastErrorAt: 2000, // mais recente que lastIngestAt
    });

    const res = await server.inject({ method: 'GET', url: '/api/v1/executions/exec-001' });
    expect(res.statusCode).toBe(200);
    const body = res.json<{ data: { executionId: string } | null; meta: { degraded: boolean; reason: string | null } }>();
    expect(body.meta.degraded).toBe(true);
    expect(body.meta.reason).toBe('watcher-ingestion-failed');
    // data NAO e nulificado — a execucao foi lida com sucesso (diferente de wrapDegraded)
    expect(body.data).not.toBeNull();
    expect(body.data?.executionId).toBe('exec-001');
  });

  it('falha registrada porem ANTERIOR ao ultimo sucesso ⇒ meta.degraded:false (recuperou)', async () => {
    setWatcherCacheEntryForTests(stateDir, {
      signature: 'sig-2',
      lastIngestAt: 5000, // sucesso posterior a falha — recuperou
      lastError: 'falha antiga',
      lastErrorAt: 1000,
    });

    const res = await server.inject({ method: 'GET', url: '/api/v1/executions/exec-001' });
    const body = res.json<{ meta: { degraded: boolean } }>();
    expect(body.meta.degraded).toBe(false);
  });

  it('nunca teve sucesso (lastIngestAt null) mas ha erro registrado ⇒ meta.degraded:true', async () => {
    setWatcherCacheEntryForTests(stateDir, {
      signature: null,
      lastIngestAt: null,
      lastError: 'primeira ingestao ja falhou',
      lastErrorAt: 1000,
    });

    const res = await server.inject({ method: 'GET', url: '/api/v1/executions/exec-001' });
    const body = res.json<{ meta: { degraded: boolean; reason: string | null } }>();
    expect(body.meta.degraded).toBe(true);
    expect(body.meta.reason).toBe('watcher-ingestion-failed');
  });

  it('GET /executions (listagem) permanece inalterada mesmo com falha no cache (task 2.4.2)', async () => {
    setWatcherCacheEntryForTests(stateDir, {
      signature: 'sig-3',
      lastIngestAt: 1000,
      lastError: 'falha',
      lastErrorAt: 2000,
    });

    const res = await server.inject({ method: 'GET', url: '/api/v1/executions' });
    expect(res.statusCode).toBe(200);
    const body = res.json<{ meta: { degraded: boolean } }>();
    // A listagem nunca consulta o cache do watcher — sinal restrito ao detalhe.
    expect(body.meta.degraded).toBe(false);
  });
});
