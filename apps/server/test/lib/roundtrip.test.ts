/**
 * 7.1 Roundtrip End-to-End real — servidor real + base real (sem mock de DB).
 * Ref: quickstart.md §Cenario 1; plan.md §Convencoes de Borda; spec.md SC-003
 * Tasks 7.1.1 – 7.1.5
 *
 * Principios constitucionais validados:
 * - Principio III (Honestidade de Metrica): toolCallsTotal presente, sem "$"/"tokens"
 * - Principio VI (Snapshot que Muda): meta.freshness populado
 * - Convencao de Borda: TODAS as chaves JSON em camelCase (nao snake_case)
 *
 * Parse de envelope com ApiEnvelopeSchema de @cstk-panel/shared-types.
 * ETag/304: segunda chamada com If-None-Match retorna 304 sem body.
 */
import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import Fastify from 'fastify';
import cors from '@fastify/cors';
import type { FastifyInstance } from 'fastify';
import { existsSync } from 'node:fs';
import { resolve, join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { RawApiEnvelopeSchema, FtsHitDTOSchema, ModelUsageResultSchema } from '@cstk-panel/shared-types';

const __dirname = dirname(fileURLToPath(import.meta.url));
const FIXTURE_DB = resolve(join(__dirname, '..', 'knowledge-fixture.db'));
const FIXTURE_EXISTS = existsSync(FIXTURE_DB);

// ─── Helper: construir servidor de teste ─────────────────────────────────────

async function buildServer(dbPath: string): Promise<FastifyInstance> {
  process.env['CSTK_KNOWLEDGE_DB'] = dbPath;

  const server = Fastify({ logger: false });
  await server.register(cors, { origin: 'http://localhost:5173', methods: ['GET', 'OPTIONS'] });

  server.addHook('onSend', async (_req, reply) => {
    void reply.header('Content-Type', 'application/json; charset=utf-8');
    void reply.header('X-Content-Type-Options', 'nosniff');
    void reply.header('X-Frame-Options', 'DENY');
    void reply.header('Cache-Control', 'no-store');
  });

  const { healthRoutes } = await import('../../src/routes/health.js');
  const { overviewRoutes } = await import('../../src/routes/overview.js');
  const { projectRoutes } = await import('../../src/routes/projects.js');
  const { featureRoutes } = await import('../../src/routes/features.js');
  const { executionRoutes } = await import('../../src/routes/executions.js');
  const { alertRoutes } = await import('../../src/routes/alerts.js');
  const { taskRoutes } = await import('../../src/routes/tasks.js');
  const { eventRoutes } = await import('../../src/routes/events.js');
  const { metricsRoutes } = await import('../../src/routes/metrics.js');
  const { searchRoutes } = await import('../../src/routes/search.js');

  await server.register(async (v1) => {
    await v1.register(healthRoutes);
    await v1.register(overviewRoutes);
    await v1.register(projectRoutes);
    await v1.register(featureRoutes);
    await v1.register(executionRoutes);
    await v1.register(alertRoutes);
    await v1.register(taskRoutes);
    await v1.register(eventRoutes);
    await v1.register(metricsRoutes);
    await v1.register(searchRoutes);
  }, { prefix: '/api/v1' });

  server.setNotFoundHandler((_req, reply) => {
    return reply.status(404).send({
      data: null,
      meta: { degraded: false, reason: null, freshness: { mtime: '', maxIngestedAt: '' }, schemaVersion: '2' },
      error: 'Not found',
    });
  });

  await server.ready();
  return server;
}

// ─── 7.1 Roundtrip E2E real ───────────────────────────────────────────────────

describe.skipIf(!FIXTURE_EXISTS)('7.1 Roundtrip E2E — GET /overview com base real', () => {
  let server: FastifyInstance;

  beforeAll(async () => {
    server = await buildServer(FIXTURE_DB);
  });
  afterAll(async () => { await server.close(); });

  // 7.1.1 — parse com ApiEnvelopeSchema de shared-types
  it('7.1.1 envelope valida contra ApiEnvelopeSchema (sem mock de DB)', async () => {
    const res = await server.inject({ method: 'GET', url: '/api/v1/overview?period=7d' });
    expect(res.statusCode).toBe(200);

    const parse = RawApiEnvelopeSchema.safeParse(res.json());
    expect(parse.success, `parse falhou: ${JSON.stringify(parse.error?.issues?.slice(0, 3))}`).toBe(true);
  });

  // 7.1.2 — convencao de borda: camelCase, nao snake_case
  it('7.1.2 todas as chaves de kpis estao em camelCase (nao snake_case)', async () => {
    const res = await server.inject({ method: 'GET', url: '/api/v1/overview' });
    expect(res.statusCode).toBe(200);

    const body = res.json<{ data: { kpis: Record<string, unknown> } }>();
    const kpis = body.data.kpis;

    // Garantir que nao ha snake_case — deve ser camelCase
    const snakeCaseKeys = Object.keys(kpis).filter((k) => k.includes('_'));
    expect(
      snakeCaseKeys,
      `Encontrado snake_case nas kpis: ${snakeCaseKeys.join(', ')}`
    ).toHaveLength(0);

    // Garantir campos camelCase especificos presentes (nao seus equivalentes snake)
    expect('toolCallsTotal' in kpis).toBe(true);
    expect('totalExecutions' in kpis).toBe(true);
    expect('activeExecutions' in kpis).toBe(true);
    // Garantir que snake_case equivalentes NAO existem
    expect('tool_calls_total' in kpis).toBe(false);
    expect('total_executions' in kpis).toBe(false);
  });

  // 7.1.3 — meta.schemaVersion reflete a versao real da fixture (v7 apos migracao new-schema) e degraded=false
  it('7.1.3 meta.schemaVersion === "7" e meta.degraded === false na base real', async () => {
    const res = await server.inject({ method: 'GET', url: '/api/v1/overview' });
    expect(res.statusCode).toBe(200);

    const body = res.json<{ meta: { schemaVersion: string; degraded: boolean } }>();
    expect(body.meta.schemaVersion).toBe('7');
    expect(body.meta.degraded).toBe(false);
  });

  // 7.1.4 — GET /search com base real, shape FtsHitDTO via safeParse
  it('7.1.4 GET /search?q=plan retorna FtsHitDTO validos via safeParse', async () => {
    const res = await server.inject({ method: 'GET', url: '/api/v1/search?q=plan&limit=5' });
    expect(res.statusCode).toBe(200);

    const body = res.json<{ data: { results: unknown[] }; meta: { degraded: boolean } }>();
    expect(body.meta.degraded).toBe(false);
    expect(Array.isArray(body.data.results)).toBe(true);

    // Cada resultado deve ser um FtsHitDTO valido
    for (const hit of body.data.results) {
      const parse = FtsHitDTOSchema.safeParse(hit);
      expect(
        parse.success,
        `FtsHitDTO safeParse falhou: ${JSON.stringify(parse.error?.issues?.slice(0, 3))}\nhit: ${JSON.stringify(hit)}`
      ).toBe(true);
    }
  });

  // 7.1.5 — ETag/304: segunda chamada com If-None-Match retorna 304 sem body
  it('7.1.5 segunda chamada com If-None-Match correto retorna 304', async () => {
    const res1 = await server.inject({ method: 'GET', url: '/api/v1/overview' });
    expect(res1.statusCode).toBe(200);

    const etag = res1.headers['etag'] as string | undefined;
    expect(etag, 'ETag deve estar presente na resposta da base real').toBeDefined();

    if (etag) {
      const res2 = await server.inject({
        method: 'GET',
        url: '/api/v1/overview',
        headers: { 'if-none-match': etag },
      });
      expect(res2.statusCode).toBe(304);
      // 304 nao deve ter body (RFC 7232)
      expect(res2.rawPayload.length).toBe(0);
    }
  });

  // Bonus: convencao de borda nos resultados de search
  it('GET /search resultados nao contem snake_case (source_id → sourceId, source_ts → sourceTs)', async () => {
    const res = await server.inject({ method: 'GET', url: '/api/v1/search?q=execute&limit=5' });
    expect(res.statusCode).toBe(200);

    const body = res.json<{ data: { results: Record<string, unknown>[] } }>();
    for (const hit of body.data.results) {
      // camelCase esperado
      expect('sourceId' in hit).toBe(true);
      expect('sourceTs' in hit).toBe(true);
      // snake_case NAO deve estar presente
      expect('source_id' in hit).toBe(false);
      expect('source_ts' in hit).toBe(false);
    }
  });
});

// ─── 7.1.5 ETag: ETag invalido nao retorna 304 ───────────────────────────────

describe.skipIf(!FIXTURE_EXISTS)('7.1.5 ETag — ETag invalido nao retorna 304', () => {
  let server: FastifyInstance;

  beforeAll(async () => {
    server = await buildServer(FIXTURE_DB);
  });
  afterAll(async () => { await server.close(); });

  it('ETag invalido (W/"0-0") nao retorna 304', async () => {
    const res = await server.inject({
      method: 'GET',
      url: '/api/v1/overview',
      headers: { 'if-none-match': 'W/"0-0"' },
    });
    // ETag errado deve retornar 200 com corpo
    expect(res.statusCode).toBe(200);
    expect(res.rawPayload.length).toBeGreaterThan(0);
  });
});

// ─── Convencao de borda em /health ───────────────────────────────────────────

describe.skipIf(!FIXTURE_EXISTS)('7.1 Convencao de borda — /health', () => {
  let server: FastifyInstance;

  beforeAll(async () => {
    server = await buildServer(FIXTURE_DB);
  });
  afterAll(async () => { await server.close(); });

  it('GET /health counts nao tem snake_case (dbReachable, quickCheck, alertSignals)', async () => {
    const res = await server.inject({ method: 'GET', url: '/api/v1/health' });
    expect(res.statusCode).toBe(200);

    const body = res.json<{ data: { counts: Record<string, unknown> } }>();
    const counts = body.data.counts;
    const snakeCaseKeys = Object.keys(counts).filter((k) => k.includes('_'));
    expect(
      snakeCaseKeys,
      `Encontrado snake_case em counts: ${snakeCaseKeys.join(', ')}`
    ).toHaveLength(0);
    expect('alertSignals' in counts).toBe(true);
    expect('alert_signals' in counts).toBe(false);
  });
});

// ─── 2.5.3 Roundtrip real — GET /metrics/model-usage (schema v12) ───────────
// Ref: contracts/model-usage-endpoint.md; tasks.md 2.5.3.
// A fixture `knowledge-fixture.db` e schema v7 (sem `wave_model_usage`), logo
// este cenario exercita o caminho DEGRADADO ('table-empty') previsto pelo
// contrato §Response 200 degradado — nao o payload medido (esse foi validado
// contra o banco real ~/.claude/cstk/knowledge.db em 2.5.1/2.5.2, fora do
// escopo de teste automatizado por depender de dado local do operador).
// Mesmo no caminho degradado, o shape (chaves + nulidade) MUST bater com o
// contrato: 100% das chaves em camelCase, validado via ModelUsageResultSchema.
describe.skipIf(!FIXTURE_EXISTS)('2.5.3 Roundtrip E2E — GET /metrics/model-usage com base real', () => {
  let server: FastifyInstance;

  beforeAll(async () => {
    server = await buildServer(FIXTURE_DB);
  });
  afterAll(async () => { await server.close(); });

  it('2.5.3.a envelope valida contra RawApiEnvelopeSchema (sem mock de DB)', async () => {
    const res = await server.inject({ method: 'GET', url: '/api/v1/metrics/model-usage?period=all' });
    expect(res.statusCode).toBe(200);

    const parse = RawApiEnvelopeSchema.safeParse(res.json());
    expect(parse.success, `parse falhou: ${JSON.stringify(parse.error?.issues?.slice(0, 3))}`).toBe(true);
  });

  it('2.5.3.b data valida contra ModelUsageResultSchema — 100% das chaves em camelCase', async () => {
    const res = await server.inject({ method: 'GET', url: '/api/v1/metrics/model-usage?period=all' });
    expect(res.statusCode).toBe(200);

    const body = res.json<{ data: unknown }>();
    const parse = ModelUsageResultSchema.safeParse(body.data);
    expect(parse.success, `ModelUsageResultSchema safeParse falhou: ${JSON.stringify(parse.error?.issues?.slice(0, 5))}`).toBe(true);
  });

  it('2.5.3.c fixture v7 (sem wave_model_usage) degrada como table-empty, nunca 0 no coverage', async () => {
    const res = await server.inject({ method: 'GET', url: '/api/v1/metrics/model-usage?period=all' });
    expect(res.statusCode).toBe(200);

    const body = res.json<{
      data: { byModel: unknown[]; byStage: unknown[]; coverage: Record<string, number | null> };
      meta: { degraded: boolean; reason: string | null };
    }>();
    expect(body.meta.degraded).toBe(true);
    expect(body.meta.reason).toBe('table-empty');
    expect(body.data.byModel).toEqual([]);
    expect(body.data.byStage).toEqual([]);
    // Invariante 1 do contrato: tabela ausente -> coverage com os 3 campos
    // null, NUNCA 0 (0 significaria "zero linhas no recorte", semantica
    // distinta de "métrica não coletada nesta base").
    expect(body.data.coverage.wavesTotal).toBeNull();
    expect(body.data.coverage.wavesWithModelUsage).toBeNull();
    expect(body.data.coverage.wavesWithOtelCost).toBeNull();
  });

  it('2.5.3.d resposta nao contem snake_case (cost_usd, total_tokens etc)', async () => {
    const res = await server.inject({ method: 'GET', url: '/api/v1/metrics/model-usage?period=all' });
    expect(res.statusCode).toBe(200);

    const body = res.json<{ data: Record<string, unknown> }>();
    const flat = JSON.stringify(body.data);
    expect(flat.includes('cost_usd')).toBe(false);
    expect(flat.includes('total_tokens')).toBe(false);
    expect(flat.includes('waves_with_model_usage')).toBe(false);
  });
});
