/**
 * Testes de integracao das rotas — usa knowledge-fixture.db real.
 * Tasks 4.1.4, 4.2.4, 4.3.6, 4.4.6, 4.5.5, 4.5.6
 *
 * Principio II: todos os endpoints retornam 200 mesmo com base degradada.
 * Principio V: payloads hostis na busca → 200, nunca 5xx.
 *
 * Se a fixture nao existir ou estiver degradada, testes de rota real sao pulados
 * e apenas os testes de degradacao sao executados.
 */
import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import Fastify from 'fastify';
import cors from '@fastify/cors';
import type { FastifyInstance } from 'fastify';
import { existsSync } from 'node:fs';
import { resolve, join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const FIXTURE_DB = resolve(join(__dirname, '..', 'knowledge-fixture.db'));
const FIXTURE_EXISTS = existsSync(FIXTURE_DB);

// ─── Construtor do servidor de teste ─────────────────────────────────────────

async function buildServer(dbPath: string): Promise<FastifyInstance> {
  // Injetar path de fixture via env
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
  const { metricsRoutes } = await import('../../src/routes/metrics.js');
  const { searchRoutes } = await import('../../src/routes/search.js');
  const { taskRoutes } = await import('../../src/routes/tasks.js');
  const { memoryRoutes } = await import('../../src/routes/memories.js');

  await server.register(async (v1) => {
    await v1.register(healthRoutes);
    await v1.register(overviewRoutes);
    await v1.register(projectRoutes);
    await v1.register(featureRoutes);
    await v1.register(executionRoutes);
    await v1.register(metricsRoutes);
    await v1.register(searchRoutes);
    await v1.register(taskRoutes);
    await v1.register(memoryRoutes);
  }, { prefix: '/api/v1' });

  server.setNotFoundHandler((_req, reply) => {
    return reply.status(404).send({ data: null, meta: { degraded: false, reason: null, freshness: { mtime: '', maxIngestedAt: '' }, schemaVersion: '2' }, error: 'Not found' });
  });

  await server.ready();
  return server;
}

// ─── Testes de degradacao (sempre rodam — nao precisam de fixture) ────────────

describe('GET /health — degradacao de 1a classe', () => {
  let server: FastifyInstance;

  beforeAll(async () => {
    server = await buildServer('/tmp/nao-existe-cstk-test-' + Date.now() + '.db');
  });
  afterAll(async () => { await server.close(); });

  it('retorna 200 mesmo com DB ausente', async () => {
    const res = await server.inject({ method: 'GET', url: '/api/v1/health' });
    expect(res.statusCode).toBe(200);
  });

  it('meta.degraded=true e reason != null quando DB ausente', async () => {
    const res = await server.inject({ method: 'GET', url: '/api/v1/health' });
    // health.ts retorna shape especial com data.ok=false; meta pode ser em data ou meta
    const body = res.json<Record<string, unknown>>();
    // Aceitar body.meta.degraded=true OU body.data.ok=false (shape atual do health degradado)
    const metaDegraded = (body['meta'] as { degraded?: boolean })?.degraded;
    const dataOk = (body['data'] as { ok?: boolean })?.ok;
    expect(metaDegraded === true || dataOk === false).toBe(true);
  });
});

// ─── Testes de /search com payloads hostis (task 4.5.5 + 4.5.6) ──────────────

describe('GET /search — payloads hostis', () => {
  let server: FastifyInstance;

  beforeAll(async () => {
    // Usar fixture se disponivel, senao path degradado (search retorna {} degradado, nunca 5xx)
    const dbPath = FIXTURE_EXISTS ? FIXTURE_DB : '/tmp/nao-existe-search-test.db';
    server = await buildServer(dbPath);
  });
  afterAll(async () => { await server.close(); });

  const HOSTILE_QUERIES = [
    '") OR 1=1 --',
    "NEAR/3 (a b)",
    '"unclosed',
    "; DROP TABLE decisions; --",
    "')) OR '1'='1",
    "MATCH * FROM decisions",
  ];

  for (const q of HOSTILE_QUERIES) {
    it(`retorna 200 (nao 5xx) para query hostil: ${q.slice(0, 30)}`, async () => {
      const res = await server.inject({
        method: 'GET',
        url: `/api/v1/search?q=${encodeURIComponent(q)}`,
      });
      expect(res.statusCode).toBe(200);
    });
  }

  it('inclui pagination.hasMore (boolean) no envelope — contrato do FE', async () => {
    const res = await server.inject({ method: 'GET', url: '/api/v1/search?q=teste' });
    expect(res.statusCode).toBe(200);
    const body = res.json<{ data: { pagination: { hasMore: unknown; total: number; limit: number; offset: number } } }>();
    expect(typeof body.data.pagination.hasMore).toBe('boolean');
    expect(typeof body.data.pagination.total).toBe('number');
  });

  it('retorna 400 com mensagem descritiva para q vazio', async () => {
    const res = await server.inject({ method: 'GET', url: '/api/v1/search?q=' });
    expect(res.statusCode).toBe(400);
    const body = res.json<{ error?: string }>();
    expect(body.error).toBeDefined();
    // Nao deve expor stack trace — campo error e string descritiva
    expect(body.error).not.toContain('Error: ');
    expect(body.error).not.toContain('at ');
  });

  it('retorna 400 para q com mais de 200 chars', async () => {
    const longQ = 'a'.repeat(201);
    const res = await server.inject({ method: 'GET', url: `/api/v1/search?q=${longQ}` });
    expect(res.statusCode).toBe(400);
  });
});

// ─── Testes com fixture real (pulados se nao existir) ─────────────────────────

describe.skipIf(!FIXTURE_EXISTS)('Rotas com fixture real — GET /api/v1/*', () => {
  let server: FastifyInstance;

  beforeAll(async () => {
    server = await buildServer(FIXTURE_DB);
  });
  afterAll(async () => { await server.close(); });

  // task 4.1.4 — /overview responde campos de KPI
  it('GET /overview retorna kpis com totalExecutions', async () => {
    const res = await server.inject({ method: 'GET', url: '/api/v1/overview' });
    expect(res.statusCode).toBe(200);
    const body = res.json<{ data: { kpis: { totalExecutions: number } }; meta: { degraded: boolean } }>();
    expect(body.meta.degraded).toBe(false);
    expect(typeof body.data.kpis.totalExecutions).toBe('number');
    expect(body.data.kpis.totalExecutions).toBeGreaterThan(0);
  });

  // task 4.1.4 — /overview com period=all
  it('GET /overview?period=all responde sem erro', async () => {
    const res = await server.inject({ method: 'GET', url: '/api/v1/overview?period=all' });
    expect(res.statusCode).toBe(200);
  });

  // task 4.2.4 — /projects lista
  it('GET /projects retorna lista de projetos', async () => {
    const res = await server.inject({ method: 'GET', url: '/api/v1/projects' });
    expect(res.statusCode).toBe(200);
    const body = res.json<{ data: unknown[] }>();
    expect(Array.isArray(body.data)).toBe(true);
  });

  // task 4.2.4 — /projects/unknown retorna data:null sem degradar
  it('GET /projects/unknown retorna data:null sem meta.degraded', async () => {
    const res = await server.inject({ method: 'GET', url: '/api/v1/projects/projeto-nao-existe-xyzabc' });
    expect(res.statusCode).toBe(200);
    const body = res.json<{ data: null; meta: { degraded: boolean } }>();
    expect(body.data).toBeNull();
    expect(body.meta.degraded).toBe(false);
  });

  // task 4.3.6 — /decisions paginadas
  it('GET /executions/:id/decisions com limit=5 retorna no maximo 5 itens', async () => {
    // Pegar primeira execucao da fixture
    const overviewRes = await server.inject({ method: 'GET', url: '/api/v1/overview' });
    const overviewBody = overviewRes.json<{ data: { inProgress: { executionId: string }[]; leaderboard: { executionId: string }[] } }>();
    const execId = overviewBody.data.leaderboard[0]?.executionId ?? overviewBody.data.inProgress[0]?.executionId;

    if (!execId) return; // skip se nao ha execucoes

    const res = await server.inject({
      method: 'GET',
      url: `/api/v1/executions/${execId}/decisions?limit=5`,
    });
    expect(res.statusCode).toBe(200);
    const body = res.json<{ data: { decisions: unknown[]; pagination: { limit: number } } }>();
    expect(body.data.decisions.length).toBeLessThanOrEqual(5);
    expect(body.data.pagination.limit).toBe(5);
  });

  // GET /search resolve executionId real para hits de decisao (navegacao do FE)
  it('GET /search expoe executionId que resolve para uma execucao existente', async () => {
    const res = await server.inject({ method: 'GET', url: '/api/v1/search?q=onda&type=decision&limit=5' });
    expect(res.statusCode).toBe(200);
    const body = res.json<{ data: { results: { type: string; executionId?: string }[] } }>();
    const hit = body.data.results.find(r => r.type === 'decision');
    if (!hit) return; // fixture sem decisoes no match
    expect(typeof hit.executionId).toBe('string');
    expect(hit.executionId!.length).toBeGreaterThan(0);
    // executionId resolvido deve existir de fato em /executions/:id (nao 'nao encontrada')
    const detail = await server.inject({ method: 'GET', url: `/api/v1/executions/${encodeURIComponent(hit.executionId!)}` });
    expect(detail.statusCode).toBe(200);
    const detailBody = detail.json<{ data: unknown | null }>();
    expect(detailBody.data).not.toBeNull();
  });

  // task 4.4.6 — /metrics/clarify-resolution tem meta.approximate=true
  it('GET /metrics/clarify-resolution tem meta.approximate=true', async () => {
    const res = await server.inject({ method: 'GET', url: '/api/v1/metrics/clarify-resolution' });
    expect(res.statusCode).toBe(200);
    const body = res.json<{ meta: { approximate?: boolean } }>();
    expect(body.meta.approximate).toBe(true);
  });

  // task 4.4.6 — /metrics/cost-over-time retorna toolCalls
  it('GET /metrics/cost-over-time retorna array com campo toolCalls (nao tokens nem $)', async () => {
    const res = await server.inject({ method: 'GET', url: '/api/v1/metrics/cost-over-time' });
    expect(res.statusCode).toBe(200);
    const body = res.json<{ data: { toolCalls?: number }[] }>();
    // Se ha dados, cada item tem campo toolCalls (nao "tokens" ou "$")
    if (Array.isArray(body.data) && body.data.length > 0) {
      const item = body.data[0]!;
      expect('toolCalls' in item).toBe(true);
      expect('tokens' in item).toBe(false);
    }
  });

  // FR-V3-007 — /metrics/recall-consultations: total + split produtivas/vazias
  it('GET /metrics/recall-consultations retorna total e split (produtivas+vazias=total)', async () => {
    const res = await server.inject({ method: 'GET', url: '/api/v1/metrics/recall-consultations' });
    expect(res.statusCode).toBe(200);
    const body = res.json<{ data: { total: number; produtivas: number; vazias: number } | null; meta: { degraded: boolean } }>();
    if (body.meta.degraded || body.data === null) return; // sem fixture
    const { total, produtivas, vazias } = body.data;
    expect(produtivas + vazias).toBe(total);
    // Fixture v3 semeia 2 eventos: hits=3 (produtiva) e hits=0 (vazia).
    expect(total).toBeGreaterThanOrEqual(2);
    expect(produtivas).toBeGreaterThanOrEqual(1);
  });

  // FR-V3-009 — /tasks expoe titulo (schema v3)
  it('GET /tasks expoe campo titulo em cada item (schema v3)', async () => {
    const res = await server.inject({ method: 'GET', url: '/api/v1/tasks?limit=5' });
    expect(res.statusCode).toBe(200);
    const body = res.json<{ data: { tasks: Record<string, unknown>[] } | null }>();
    if (!body.data || body.data.tasks.length === 0) return;
    expect('title' in body.data.tasks[0]!).toBe(true);
  });

  // recall-memory-mirror — /memories degrada graciosamente em base v3 (sem a
  // tabela `memories`): 200, nao-degradado, listas vazias (Principio II).
  it('GET /memories em base v3 retorna 200 com listas vazias (sem tabela memories)', async () => {
    const res = await server.inject({ method: 'GET', url: '/api/v1/memories' });
    expect(res.statusCode).toBe(200);
    const body = res.json<{
      data: { memories: unknown[]; projects: unknown[]; pagination: { total: number } } | null;
      meta: { degraded: boolean };
    }>();
    expect(body.meta.degraded).toBe(false);
    expect(body.data).not.toBeNull();
    expect(Array.isArray(body.data!.memories)).toBe(true);
    expect(body.data!.memories.length).toBe(0);
    expect(Array.isArray(body.data!.projects)).toBe(true);
    expect(body.data!.pagination.total).toBe(0);
  });

  // ETag/304
  it('GET /overview com ETag correto retorna 304', async () => {
    const res1 = await server.inject({ method: 'GET', url: '/api/v1/overview' });
    const etag = res1.headers['etag'] as string | undefined;
    if (!etag) return; // fixture sem mtime real

    const res2 = await server.inject({
      method: 'GET',
      url: '/api/v1/overview',
      headers: { 'if-none-match': etag },
    });
    expect(res2.statusCode).toBe(304);
  });

  // task 2.3.4 — /metrics/model-usage sobre a fixture v7 (sem wave_model_usage,
  // introduzida so no schema v12): exercita o caminho degradado table-empty
  // fim-a-fim (contrato §Response 200 degradado, Decision 4).
  it("GET /metrics/model-usage sobre fixture v7: 200 degradado reason='table-empty', data com shape vazio (nao null)", async () => {
    const res = await server.inject({ method: 'GET', url: '/api/v1/metrics/model-usage?period=all' });
    expect(res.statusCode).toBe(200);
    const body = res.json<{
      data: { byModel: unknown[]; byStage: unknown[]; coverage: Record<string, unknown> } | null;
      meta: { degraded: boolean; reason: string | null; approximate?: boolean };
    }>();
    expect(body.meta.degraded).toBe(true);
    expect(body.meta.reason).toBe('table-empty');
    // Invariante: data NAO e null mesmo degradado — o shape vazio e afirmativo.
    expect(body.data).not.toBeNull();
    expect(body.data!.byModel).toEqual([]);
    expect(body.data!.byStage).toEqual([]);
    expect(body.data!.coverage).toEqual({ wavesTotal: null, wavesWithModelUsage: null, wavesWithOtelCost: null });
    // meta.approximate NAO e emitido: dado MEDIDO, mesmo degradado (contrato §Response 200).
    expect(body.meta.approximate).toBeUndefined();
  });
});

// ─── GET /metrics/model-usage sobre base v12 sintetica (task 2.3.4) ──────────
//
// A fixture v7 do repositorio nao tem `wave_model_usage` (introduzida so no
// schema v12) — o bloco acima cobre so o caminho degradado. Para exercitar o
// endpoint com dado REAL de ponta a ponta (Fastify inject real, nao so a
// query), construimos aqui uma base v12 sintetica minima com a tabela nova —
// mesma estrategia de fixture usada em test/lib/model-usage.test.ts.

describe('GET /metrics/model-usage sobre base v12 sintetica', () => {
  let server: FastifyInstance;
  let dbPath: string;

  beforeAll(async () => {
    const { mkdtempSync } = await import('node:fs');
    const { tmpdir } = await import('node:os');
    const BetterSqlite3 = (await import('better-sqlite3')).default;
    dbPath = join(mkdtempSync(join(tmpdir(), 'model-usage-route-')), 'k.db');
    const db = new BetterSqlite3(dbPath);
    db.exec(`
      CREATE TABLE schema_meta (key TEXT PRIMARY KEY, value TEXT);
      INSERT INTO schema_meta VALUES ('schema_version', '12');
      CREATE TABLE executions (
        execution_id TEXT PRIMARY KEY, project TEXT NOT NULL, feature TEXT NOT NULL,
        status TEXT, started_at TEXT
      );
      CREATE TABLE waves (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        project TEXT NOT NULL, feature TEXT NOT NULL, wave TEXT NOT NULL,
        execution_id TEXT NOT NULL, source_ts TEXT NOT NULL, source_id TEXT NOT NULL,
        stages TEXT, started_at TEXT, finished_at TEXT,
        otel_cost_usd REAL, ingested_at TEXT NOT NULL
      );
      CREATE TABLE wave_model_usage (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        project TEXT NOT NULL, feature TEXT NOT NULL, wave TEXT NOT NULL,
        execution_id TEXT NOT NULL, source_ts TEXT NOT NULL, source_id TEXT NOT NULL,
        model TEXT, cost_usd REAL, total_tokens INTEGER, ingested_at TEXT NOT NULL,
        UNIQUE(project, feature, wave, source_id)
      );
    `);
    db.prepare(`INSERT INTO executions(execution_id,project,feature,status,started_at)
                VALUES ('e1','p','f','concluida','2026-07-28T09:00:00Z')`).run();
    db.prepare(`INSERT INTO waves(project,feature,wave,execution_id,source_ts,source_id,stages,started_at,otel_cost_usd,ingested_at)
                VALUES ('p','f','onda-001','e1','2026-07-28T09:00:00Z','w1','execute-task','2026-07-28T09:00:00Z',5.0,'t')`).run();
    db.prepare(`INSERT INTO wave_model_usage(project,feature,wave,execution_id,source_ts,source_id,model,cost_usd,total_tokens,ingested_at)
                VALUES ('p','f','onda-001','e1','2026-07-28T09:00:00Z','s1','claude-sonnet-5',5.0,1000,'t')`).run();
    db.close();

    server = await buildServer(dbPath);
  });
  afterAll(async () => { await server.close(); });

  it('4 query params validos (project+feature+period=all): 200 nao-degradado com byModel real', async () => {
    const res = await server.inject({
      method: 'GET',
      url: '/api/v1/metrics/model-usage?project=p&feature=f&period=all',
    });
    expect(res.statusCode).toBe(200);
    const body = res.json<{
      data: { byModel: { model: string; costUsd: number }[]; coverage: Record<string, unknown> };
      meta: { degraded: boolean };
    }>();
    expect(body.meta.degraded).toBe(false);
    expect(body.data.byModel).toHaveLength(1);
    expect(body.data.byModel[0]?.model).toBe('claude-sonnet-5');
    expect(body.data.byModel[0]?.costUsd).toBeCloseTo(5.0, 6);
    expect(body.data.coverage).toEqual({ wavesTotal: 1, wavesWithModelUsage: 1, wavesWithOtelCost: 1 });
  });

  it("filtro project inexistente: 200 com byModel vazio (nao-degradado — 'sem dado no periodo' != 'nao coletado')", async () => {
    const res = await server.inject({
      method: 'GET',
      url: '/api/v1/metrics/model-usage?project=projeto-que-nao-existe',
    });
    expect(res.statusCode).toBe(200);
    const body = res.json<{ data: { byModel: unknown[] }; meta: { degraded: boolean } }>();
    expect(body.meta.degraded).toBe(false);
    expect(body.data.byModel).toEqual([]);
  });

  it(
    "param invalido (period fora do enum): 200 com o param IGNORADO, nao 400 " +
    '(desvio deliberado do texto de tasks.md 2.3.4 — parseUsageQuery e reuso MANDATORIO ' +
    '(contrato §Request), e ja e permissivo/degrada em vez de 400 nos irmaos otel-usage/ ' +
    'agent-usage; nenhum parser ad-hoc foi introduzido para este endpoint divergir)',
    async () => {
      const res = await server.inject({
        method: 'GET',
        url: '/api/v1/metrics/model-usage?period=1year',
      });
      expect(res.statusCode).toBe(200);
      const body = res.json<{ data: { byModel: unknown[] }; meta: { degraded: boolean } }>();
      expect(body.meta.degraded).toBe(false);
      // period invalido -> ignorado -> equivalente a period=all -> ainda ve a onda-001
      expect(body.data.byModel).toHaveLength(1);
    },
  );
});
