/**
 * Testes de integracao da rota GET /executions/:executionId/suggestions
 * (schema v7 EN — new-schema).
 *
 * Constroi uma base v7 minima (schema_version='7', 1 execucao, tabela
 * `suggestions` com colunas EN) em tmpdir e exercita: listagem por execucao,
 * coercao de severity/references no mapper, conteudo UNTRUSTED cru, e
 * degradacao graciosa numa base v3 SEM a tabela (Principio II → [] sem degradar).
 *
 * FASE 3 (new-schema): base migrada pt-BR→EN snake_case.
 */
import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import Fastify from 'fastify';
import cors from '@fastify/cors';
import type { FastifyInstance } from 'fastify';
import { mkdtempSync, unlinkSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import Database from 'better-sqlite3';

const toClean: string[] = [];

function tmpFile(name: string): string {
  const dir = mkdtempSync(join(tmpdir(), 'cstk-sug-'));
  const p = join(dir, name);
  toClean.push(p);
  return p;
}

/** Cria uma base v7 EN com 1 execucao e 2 sugestoes. */
function makeV7Db(path: string): void {
  const db = new Database(path);
  db.exec(`
    CREATE TABLE schema_meta (key TEXT PRIMARY KEY, value TEXT);
    INSERT INTO schema_meta VALUES ('schema_version', '7');

    CREATE TABLE executions (
      execution_id TEXT PRIMARY KEY, project TEXT, feature TEXT, status TEXT,
      ingested_at TEXT
    );
    INSERT INTO executions (execution_id, project, feature, status, ingested_at)
    VALUES ('exec-001', 'cstk', 'recall-suggestions', 'concluida', '2026-05-27T18:00:00Z');

    CREATE TABLE suggestions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      project TEXT NOT NULL, feature TEXT NOT NULL, wave TEXT NOT NULL,
      execution_id TEXT NOT NULL, source_ts TEXT NOT NULL, source_id TEXT NOT NULL,
      affected_skill TEXT, severity TEXT, diagnosis TEXT, proposal TEXT,
      referencias TEXT, issue_opened TEXT, created_at TEXT, ingested_at TEXT NOT NULL,
      UNIQUE(project, feature, wave, source_id)
    );
    INSERT INTO suggestions
      (project, feature, wave, execution_id, source_ts, source_id, affected_skill,
       severity, diagnosis, proposal, referencias, issue_opened, created_at, ingested_at)
    VALUES
      ('cstk', 'recall-suggestions', '-', 'exec-001', '2026-05-27T10:00:00Z',
       'sug-001', 'execute-task', 'aviso',
       'O gate de lint nao roda em arquivos <script>x</script> .mjs',
       'Estender o glob do lint para .mjs', 'cli/lib/recall.sh,docs/spec.md', NULL,
       '2026-05-27T10:00:00Z', '2026-05-27T18:00:00Z'),
      ('cstk', 'recall-suggestions', '-', 'exec-001', '2026-05-27T11:00:00Z',
       'sug-002', 'review-task', 'impeditiva',
       'Severidade desconhecida deve degradar para null no painel',
       'Adicionar coercao no mapper', '', 'https://gh/x/issues/42',
       '2026-05-27T11:00:00Z', '2026-05-27T18:00:00Z');
  `);
  db.close();
}

/** Base v3 SEM a tabela suggestions — exercita a tolerancia de schema. */
function makeV3Db(path: string): void {
  const db = new Database(path);
  db.exec(`
    CREATE TABLE schema_meta (key TEXT PRIMARY KEY, value TEXT);
    INSERT INTO schema_meta VALUES ('schema_version', '3');
    CREATE TABLE executions (
      execution_id TEXT PRIMARY KEY, project TEXT, feature TEXT, status TEXT,
      ingested_at TEXT
    );
    INSERT INTO executions (execution_id, project, feature, status, ingested_at)
    VALUES ('exec-001', 'cstk', 'old', 'concluida', '2026-05-27T18:00:00Z');
  `);
  db.close();
}

async function buildServer(dbPath: string): Promise<FastifyInstance> {
  process.env['CSTK_KNOWLEDGE_DB'] = dbPath;
  const server = Fastify({ logger: false });
  await server.register(cors, { origin: 'http://localhost:5173', methods: ['GET', 'OPTIONS'] });
  const { executionRoutes } = await import('../../src/routes/executions.js');
  await server.register(async (v1) => {
    await v1.register(executionRoutes);
  }, { prefix: '/api/v1' });
  await server.ready();
  return server;
}

interface SuggestionsBody {
  data: Array<{
    executionId: string;
    sourceId: string;
    affectedSkill: string | null;
    severity: string | null;
    diagnosis: string | null;
    proposal: string | null;
    referencias: string[];
    issueOpened: string | null;
    createdAt: string | null;
  }> | null;
  meta: { degraded: boolean; schemaVersion: string };
}

afterAll(() => {
  delete process.env['CSTK_KNOWLEDGE_DB'];
  for (const f of toClean) {
    try { unlinkSync(f); } catch { /* ignorar */ }
    try { unlinkSync(f + '-shm'); } catch { /* ignorar */ }
    try { unlinkSync(f + '-wal'); } catch { /* ignorar */ }
  }
});

describe('GET /executions/:id/suggestions — base v7 com tabela suggestions (EN)', () => {
  let server: FastifyInstance;
  const dbPath = tmpFile('knowledge-v7.db');

  beforeAll(async () => {
    makeV7Db(dbPath);
    server = await buildServer(dbPath);
  });
  afterAll(async () => { await server.close(); });

  it('lista as sugestoes da execucao em ordem cronologica (200, nao-degradado)', async () => {
    const res = await server.inject({ method: 'GET', url: '/api/v1/executions/exec-001/suggestions' });
    expect(res.statusCode).toBe(200);
    const body = res.json<SuggestionsBody>();
    expect(body.meta.degraded).toBe(false);
    expect(body.meta.schemaVersion).toBe('7');
    expect(body.data).not.toBeNull();
    expect(body.data!.map((s) => s.sourceId)).toEqual(['sug-001', 'sug-002']);
  });

  it('divide referencias (CSV) em array; vazio → []', async () => {
    const res = await server.inject({ method: 'GET', url: '/api/v1/executions/exec-001/suggestions' });
    const body = res.json<SuggestionsBody>();
    const s1 = body.data!.find((s) => s.sourceId === 'sug-001')!;
    const s2 = body.data!.find((s) => s.sourceId === 'sug-002')!;
    expect(s1.referencias).toEqual(['cli/lib/recall.sh', 'docs/spec.md']);
    expect(s2.referencias).toEqual([]);
  });

  it('preserva severity conhecida e mapeia issue_opened', async () => {
    const res = await server.inject({ method: 'GET', url: '/api/v1/executions/exec-001/suggestions' });
    const body = res.json<SuggestionsBody>();
    const s2 = body.data!.find((s) => s.sourceId === 'sug-002')!;
    expect(s2.severity).toBe('impeditiva');
    expect(s2.issueOpened).toBe('https://gh/x/issues/42');
    expect(body.data!.find((s) => s.sourceId === 'sug-001')!.issueOpened).toBeNull();
  });

  it('diagnosis chega cru (UNTRUSTED) — sem escapar markup', async () => {
    const res = await server.inject({ method: 'GET', url: '/api/v1/executions/exec-001/suggestions' });
    const body = res.json<SuggestionsBody>();
    const s1 = body.data!.find((s) => s.sourceId === 'sug-001')!;
    expect(s1.diagnosis).toContain('<script>x</script>');
  });
});

describe('GET /executions/:id/suggestions — base v3 SEM a tabela (Principio II)', () => {
  let server: FastifyInstance;
  const dbPath = tmpFile('knowledge-v3.db');

  beforeAll(async () => {
    makeV3Db(dbPath);
    server = await buildServer(dbPath);
  });
  afterAll(async () => { await server.close(); });

  it('retorna [] sem degradar quando a tabela suggestions nao existe', async () => {
    const res = await server.inject({ method: 'GET', url: '/api/v1/executions/exec-001/suggestions' });
    expect(res.statusCode).toBe(200);
    const body = res.json<SuggestionsBody>();
    expect(body.meta.degraded).toBe(false);
    expect(body.data).toEqual([]);
  });
});
