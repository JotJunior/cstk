/**
 * Testes de integracao da coluna `decisions.options` (schema v7 EN) na rota
 * GET /executions/:executionId/decisions.
 *
 * Constroi uma base v7 (com a coluna `options`) e uma base v6 (SEM a coluna) em
 * tmpdir, exercitando: passagem crua do JSON array de options, e degradacao
 * graciosa para `options=null` em bases v<7 (Principio II / FR-V3-005), sem
 * quebrar o SELECT.
 *
 * FASE 3 (new-schema): base migrada pt-BR→EN snake_case.
 * Back-compat: base v6 SEM a coluna `options` continua sendo suportada (degrada).
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
  const dir = mkdtempSync(join(tmpdir(), 'cstk-opt-'));
  const p = join(dir, name);
  toClean.push(p);
  return p;
}

const EXEC = `
  CREATE TABLE executions (
    execution_id TEXT PRIMARY KEY, project TEXT, feature TEXT, status TEXT,
    ingested_at TEXT
  );
  INSERT INTO executions (execution_id, project, feature, status, ingested_at)
  VALUES ('exec-001', 'cstk', 'recall', 'concluida', '2026-05-27T18:00:00Z');
`;

/** Base v7 EN com a coluna `options` e 2 decisoes. */
function makeV7Db(path: string): void {
  const db = new Database(path);
  db.exec(`
    CREATE TABLE schema_meta (key TEXT PRIMARY KEY, value TEXT);
    INSERT INTO schema_meta VALUES ('schema_version', '7');
    ${EXEC}
    CREATE TABLE decisions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      project TEXT NOT NULL, feature TEXT NOT NULL, wave TEXT NOT NULL,
      execution_id TEXT NOT NULL, source_ts TEXT NOT NULL, source_id TEXT NOT NULL,
      agent TEXT, stage TEXT, choice TEXT, options TEXT, score INTEGER,
      context TEXT, rationale TEXT, evidence TEXT, ingested_at TEXT NOT NULL,
      UNIQUE(project, feature, wave, source_id)
    );
    INSERT INTO decisions
      (project, feature, wave, execution_id, source_ts, source_id, agent, stage,
       choice, options, score, context, rationale, evidence, ingested_at)
    VALUES
      ('cstk','recall','init','exec-001','2026-05-27T10:00:00Z','dec-001',
       'orchestrator','model-routing','model:sonnet',
       '["haiku","sonnet","opus","manter-atual"]', 0,
       'Selecao de modelo','sugerido=sonnet',NULL,'2026-05-27T18:00:00Z'),
      ('cstk','recall','onda-001','exec-001','2026-05-27T11:00:00Z','dec-002',
       'orchestrator','plan','proceder',
       '[]', 2,
       'Warm-up de permissoes','operador aprovou em batch',NULL,'2026-05-27T18:00:00Z');
  `);
  db.close();
}

/** Base v6 SEM a coluna `options` — exercita a tolerancia de schema. */
function makeV6Db(path: string): void {
  const db = new Database(path);
  db.exec(`
    CREATE TABLE schema_meta (key TEXT PRIMARY KEY, value TEXT);
    INSERT INTO schema_meta VALUES ('schema_version', '6');
    ${EXEC}
    CREATE TABLE decisions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      project TEXT NOT NULL, feature TEXT NOT NULL, wave TEXT NOT NULL,
      execution_id TEXT NOT NULL, source_ts TEXT NOT NULL, source_id TEXT NOT NULL,
      agent TEXT, stage TEXT, choice TEXT, score INTEGER,
      context TEXT, rationale TEXT, evidence TEXT, ingested_at TEXT NOT NULL,
      UNIQUE(project, feature, wave, source_id)
    );
    INSERT INTO decisions
      (project, feature, wave, execution_id, source_ts, source_id, agent, stage,
       choice, score, context, rationale, evidence, ingested_at)
    VALUES
      ('cstk','recall','init','exec-001','2026-05-27T10:00:00Z','dec-001',
       'orchestrator','plan','proceder', 2,
       'ctx','just',NULL,'2026-05-27T18:00:00Z');
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

interface DecisionsBody {
  data: {
    decisions: Array<{ choice: string | null; options: string | null }>;
  } | null;
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

describe('GET /executions/:id/decisions — base v7 com coluna options (EN)', () => {
  let server: FastifyInstance;
  const dbPath = tmpFile('knowledge-v7.db');

  beforeAll(async () => {
    makeV7Db(dbPath);
    server = await buildServer(dbPath);
  });
  afterAll(async () => { await server.close(); });

  it('retorna o JSON array de options cru (200, nao-degradado)', async () => {
    const res = await server.inject({ method: 'GET', url: '/api/v1/executions/exec-001/decisions' });
    expect(res.statusCode).toBe(200);
    const body = res.json<DecisionsBody>();
    expect(body.meta.degraded).toBe(false);
    expect(body.meta.schemaVersion).toBe('7');
    const d1 = body.data!.decisions[0]!;
    expect(d1.choice).toBe('model:sonnet');
    expect(d1.options).toBe('["haiku","sonnet","opus","manter-atual"]');
  });

  it('preserva array vazio "[]" como string crua', async () => {
    const res = await server.inject({ method: 'GET', url: '/api/v1/executions/exec-001/decisions' });
    const body = res.json<DecisionsBody>();
    expect(body.data!.decisions[1]!.options).toBe('[]');
  });
});

describe('GET /executions/:id/decisions — base v6 SEM a coluna options (Principio II — back-compat)', () => {
  let server: FastifyInstance;
  const dbPath = tmpFile('knowledge-v6.db');

  beforeAll(async () => {
    makeV6Db(dbPath);
    server = await buildServer(dbPath);
  });
  afterAll(async () => { await server.close(); });

  it('degrada options para null sem quebrar o SELECT', async () => {
    const res = await server.inject({ method: 'GET', url: '/api/v1/executions/exec-001/decisions' });
    expect(res.statusCode).toBe(200);
    const body = res.json<DecisionsBody>();
    expect(body.meta.degraded).toBe(false);
    const d1 = body.data!.decisions[0]!;
    expect(d1.choice).toBe('proceder');
    expect(d1.options).toBeNull();
  });
});
