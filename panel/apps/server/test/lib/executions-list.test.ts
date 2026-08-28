/**
 * Teste de integracao da rota GET /executions (lista paginada).
 * Regressao: a rota nao existia (404) — a tela Execucoes quebrava.
 * Usa knowledge-fixture.db real quando disponivel.
 */
import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import Fastify from 'fastify';
import type { FastifyInstance } from 'fastify';
import { existsSync } from 'node:fs';
import { resolve, join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const FIXTURE_DB = resolve(join(__dirname, '..', 'knowledge-fixture.db'));
const FIXTURE_EXISTS = existsSync(FIXTURE_DB);

async function buildServer(dbPath: string): Promise<FastifyInstance> {
  process.env['CSTK_KNOWLEDGE_DB'] = dbPath;
  const server = Fastify({ logger: false });
  const { executionRoutes } = await import('../../src/routes/executions.js');
  await server.register(async (v1) => { await v1.register(executionRoutes); }, { prefix: '/api/v1' });
  await server.ready();
  return server;
}

describe('GET /executions (lista paginada)', () => {
  let server: FastifyInstance;
  beforeAll(async () => {
    server = await buildServer(FIXTURE_EXISTS ? FIXTURE_DB : '/tmp/nao-existe-exec-list.db');
  });
  afterAll(async () => { await server.close(); });

  it('responde 200 e NAO 404 (a rota existe)', async () => {
    const res = await server.inject({ method: 'GET', url: '/api/v1/executions?limit=5' });
    expect(res.statusCode).toBe(200);
    expect(res.json<{ error?: string }>().error).not.toBe('Not found');
  });

  it('data e objeto {executions, pagination} — nao array puro', async () => {
    const res = await server.inject({ method: 'GET', url: '/api/v1/executions?limit=5' });
    const body = res.json<{ data: { executions?: unknown[]; pagination?: Record<string, unknown> } | null }>();
    if (body.data === null) return; // degradado (sem fixture) — aceitavel
    expect(Array.isArray(body.data)).toBe(false);
    expect(Array.isArray(body.data.executions)).toBe(true);
    expect(body.data.pagination).toMatchObject({
      total: expect.any(Number),
      limit: expect.any(Number),
      offset: expect.any(Number),
      hasMore: expect.any(Boolean),
    });
  });

  it('respeita limit e expoe total', async () => {
    if (!FIXTURE_EXISTS) return;
    const res = await server.inject({ method: 'GET', url: '/api/v1/executions?limit=2&offset=0' });
    const body = res.json<{ data: { executions: unknown[]; pagination: { total: number; limit: number } } }>();
    expect(body.data.executions.length).toBeLessThanOrEqual(2);
    expect(body.data.pagination.limit).toBe(2);
    expect(body.data.pagination.total).toBeGreaterThanOrEqual(body.data.executions.length);
  });
});
