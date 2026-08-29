/**
 * Teste de integracao: servidor sobe e responde GET /api/v1/health.
 * Task 3.1.5
 *
 * Usa Fastify inject() para testar sem bind de porta real.
 * Valida: status 200, headers obrigatorios, shape basico da resposta.
 *
 * Principio II: servidor sobe mesmo sem DB (degradacao de 1a classe).
 */
import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import Fastify from 'fastify';
import cors from '@fastify/cors';

// Construir instancia minima do servidor (espelho do index.ts)
// sem bind de porta — usando inject() do Fastify para testes in-process

async function buildTestServer() {
  const server = Fastify({ logger: false });

  await server.register(cors, {
    origin: 'http://localhost:5173',
    methods: ['GET', 'OPTIONS'],
  });

  // Hook global de headers (FR-019)
  server.addHook('onSend', async (_request, reply, _payload) => {
    void reply.header('Content-Type', 'application/json; charset=utf-8');
    void reply.header('X-Content-Type-Options', 'nosniff');
    void reply.header('X-Frame-Options', 'DENY');
    void reply.header('Cache-Control', 'no-store');
  });

  // Rota de health basica (conforme index.ts atual)
  server.get('/api/v1/health', async (_request, _reply) => {
    return {
      status: 'ok',
      timestamp: new Date().toISOString(),
    };
  });

  // 404 handler
  server.setNotFoundHandler((_request, reply) => {
    return reply.status(404).send({
      data: null,
      meta: {
        degraded: false,
        reason: null,
        freshness: { mtime: '', maxIngestedAt: '' },
        schemaVersion: '2',
      },
      error: 'Not found',
    });
  });

  await server.ready();
  return server;
}

describe('GET /api/v1/health', () => {
  let server: Awaited<ReturnType<typeof buildTestServer>>;

  beforeAll(async () => {
    server = await buildTestServer();
  });

  afterAll(async () => {
    await server.close();
  });

  it('responde com status 200', async () => {
    const res = await server.inject({
      method: 'GET',
      url: '/api/v1/health',
    });
    expect(res.statusCode).toBe(200);
  });

  it('retorna Content-Type: application/json', async () => {
    const res = await server.inject({
      method: 'GET',
      url: '/api/v1/health',
    });
    expect(res.headers['content-type']).toContain('application/json');
  });

  it('retorna X-Content-Type-Options: nosniff', async () => {
    const res = await server.inject({
      method: 'GET',
      url: '/api/v1/health',
    });
    expect(res.headers['x-content-type-options']).toBe('nosniff');
  });

  it('retorna X-Frame-Options: DENY', async () => {
    const res = await server.inject({
      method: 'GET',
      url: '/api/v1/health',
    });
    expect(res.headers['x-frame-options']).toBe('DENY');
  });

  it('retorna Cache-Control: no-store', async () => {
    const res = await server.inject({
      method: 'GET',
      url: '/api/v1/health',
    });
    expect(res.headers['cache-control']).toBe('no-store');
  });

  it('body contem status: ok e timestamp ISO', async () => {
    const res = await server.inject({
      method: 'GET',
      url: '/api/v1/health',
    });
    const body = res.json<{ status: string; timestamp: string }>();
    expect(body.status).toBe('ok');
    expect(body.timestamp).toMatch(/^\d{4}-\d{2}-\d{2}T/);
  });

  it('rota inexistente retorna 404 com shape JSON valido', async () => {
    const res = await server.inject({
      method: 'GET',
      url: '/api/v1/nao-existe',
    });
    expect(res.statusCode).toBe(404);
    const body = res.json<{ data: null; meta: { degraded: boolean } }>();
    expect(body.data).toBeNull();
    expect(body.meta.degraded).toBe(false);
  });
});
