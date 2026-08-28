/**
 * Testes de integracao da rota GET /memories (schema v4 — recall-memory-mirror).
 *
 * Constroi uma base v4 minima e valida (schema_version='4', 1 execucao, tabela
 * `memories`) em tmpdir e exercita: listagem completa, filtro por projeto, lista
 * de projetos para o seletor, e que o conteudo UNTRUSTED chega cru no body.
 *
 * Principio II ja coberto em routes.test.ts (base v3 sem `memories` → vazio).
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

function tmpFile(): string {
  const dir = mkdtempSync(join(tmpdir(), 'cstk-mem-'));
  const p = join(dir, 'knowledge-v4.db');
  toClean.push(p);
  return p;
}

/** Cria uma base v4 valida com 1 execucao e 3 memorias em 2 projetos. */
function makeV4Db(path: string): void {
  const db = new Database(path);
  db.exec(`
    CREATE TABLE schema_meta (key TEXT PRIMARY KEY, value TEXT);
    INSERT INTO schema_meta VALUES ('schema_version', '4');

    CREATE TABLE executions (
      execucao_id TEXT PRIMARY KEY, project TEXT, feature TEXT, status TEXT,
      ingested_at TEXT
    );
    INSERT INTO executions (execucao_id, project, feature, status, ingested_at)
    VALUES ('exec-001', 'claude-ai-tips', 'recall', 'concluida', '2026-05-27T18:00:00Z');

    CREATE TABLE memories (
      project TEXT NOT NULL, slug TEXT NOT NULL, type TEXT NOT NULL,
      description TEXT, body_scrubbed TEXT, path TEXT, indexed_at TEXT,
      PRIMARY KEY (project, slug)
    );
    INSERT INTO memories VALUES
      ('claude-ai-tips', 'feedback_code_in_english', 'feedback',
       'Codigo em ingles obrigatorio', '# feedback\n\nuse <script>alert(1)</script> literal',
       '/x/feedback_code_in_english.md', '2026-05-27T18:00:00Z'),
      ('claude-ai-tips', 'MEMORY', 'index',
       'Indice de memorias', '- item', '/x/MEMORY.md', '2026-05-27T18:00:00Z'),
      ('cstk-panel', 'project_dashboard', 'project',
       'Dashboard read-only', 'corpo', '/y/project_dashboard.md', '2026-05-27T18:00:00Z');
  `);
  db.close();
}

async function buildServer(dbPath: string): Promise<FastifyInstance> {
  process.env['CSTK_KNOWLEDGE_DB'] = dbPath;
  const server = Fastify({ logger: false });
  await server.register(cors, { origin: 'http://localhost:5173', methods: ['GET', 'OPTIONS'] });
  const { memoryRoutes } = await import('../../src/routes/memories.js');
  await server.register(async (v1) => {
    await v1.register(memoryRoutes);
  }, { prefix: '/api/v1' });
  await server.ready();
  return server;
}

interface MemoriesBody {
  data: {
    memories: Array<{ project: string; slug: string; type: string; body: string | null }>;
    projects: string[];
    pagination: { total: number; limit: number; offset: number; hasMore: boolean };
  } | null;
  meta: { degraded: boolean; schemaVersion: string };
}

describe('GET /memories — base v4 com tabela memories', () => {
  let server: FastifyInstance;
  const dbPath = tmpFile();

  beforeAll(async () => {
    makeV4Db(dbPath);
    server = await buildServer(dbPath);
  });
  afterAll(async () => {
    await server.close();
    delete process.env['CSTK_KNOWLEDGE_DB'];
    for (const f of toClean) {
      try { unlinkSync(f); } catch { /* ignorar */ }
      try { unlinkSync(f + '-shm'); } catch { /* ignorar */ }
      try { unlinkSync(f + '-wal'); } catch { /* ignorar */ }
    }
  });

  it('lista todas as memorias (200, nao-degradado, schemaVersion=4)', async () => {
    const res = await server.inject({ method: 'GET', url: '/api/v1/memories' });
    expect(res.statusCode).toBe(200);
    const body = res.json<MemoriesBody>();
    expect(body.meta.degraded).toBe(false);
    expect(body.meta.schemaVersion).toBe('4');
    expect(body.data).not.toBeNull();
    expect(body.data!.memories.length).toBe(3);
    expect(body.data!.pagination.total).toBe(3);
  });

  it('expoe a lista COMPLETA de projetos para o seletor', async () => {
    const res = await server.inject({ method: 'GET', url: '/api/v1/memories' });
    const body = res.json<MemoriesBody>();
    expect(body.data!.projects).toEqual(['claude-ai-tips', 'cstk-panel']);
  });

  it('filtra por projeto (server-side), mantendo projects completo', async () => {
    const res = await server.inject({ method: 'GET', url: '/api/v1/memories?project=cstk-panel' });
    const body = res.json<MemoriesBody>();
    expect(body.data!.memories.length).toBe(1);
    expect(body.data!.pagination.total).toBe(1);
    expect(body.data!.memories[0]!.slug).toBe('project_dashboard');
    // seletor segue listando todos os projetos, mesmo com filtro aplicado
    expect(body.data!.projects).toEqual(['claude-ai-tips', 'cstk-panel']);
  });

  it('campo body chega cru (UNTRUSTED) — sem escapar/alterar markup', async () => {
    const res = await server.inject({ method: 'GET', url: '/api/v1/memories?project=claude-ai-tips' });
    const body = res.json<MemoriesBody>();
    const fb = body.data!.memories.find((m) => m.slug === 'feedback_code_in_english');
    expect(fb).toBeDefined();
    // O servidor entrega o conteudo literal; a defesa contra XSS e do FE (textContent).
    expect(fb!.body).toContain('<script>alert(1)</script>');
  });

  it('projeto inexistente retorna lista vazia mas sem degradar', async () => {
    const res = await server.inject({ method: 'GET', url: '/api/v1/memories?project=nao-existe' });
    expect(res.statusCode).toBe(200);
    const body = res.json<MemoriesBody>();
    expect(body.meta.degraded).toBe(false);
    expect(body.data!.memories.length).toBe(0);
    expect(body.data!.pagination.total).toBe(0);
  });
});
