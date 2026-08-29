/**
 * Testes de integracao das 4 rotas `/api/v1/bridge/*` (feature human-bridge).
 * Ref: docs/specs/human-bridge/contracts/panel-bridge-api.md §4/§5/§6/§7/§11.
 * Tasks: 3.1.10, 3.3.5.
 *
 * Servidor Fastify real (`server.inject()`), so com `bridgeRoutes`
 * registrado — mesmo padrao de `test/routes/sessions.test.ts`.
 * `CSTK_BRIDGE_DB` aponta para um arquivo tmp NOVO a cada teste (isolamento).
 * `CSTK_SECRETS_FILTER` forcado a um path inexistente (determinismo —
 * `scrubMode: 'internal'`, mesma convencao das outras suites de rota).
 */
import { describe, it, expect, beforeAll, afterAll, beforeEach, afterEach } from 'vitest';
import Fastify from 'fastify';
import type { FastifyInstance } from 'fastify';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { bridgeRoutes } from '../../src/routes/bridge.js';
import { resetSecretsFilterAvailabilityForTests } from '../../src/lib/secret-scrub.js';

let server: FastifyInstance;
let base: string;
let bridgeDbPath: string;
const ORIGINAL_ENV = { ...process.env };

beforeAll(async () => {
  server = Fastify({ logger: false });
  await server.register(async (v1) => {
    await v1.register(bridgeRoutes);
  }, { prefix: '/api/v1' });
  await server.ready();
});

afterAll(async () => {
  await server.close();
});

beforeEach(() => {
  base = mkdtempSync(join(tmpdir(), 'bridge-route-'));
  bridgeDbPath = join(base, 'bridge.db');
  process.env['CSTK_BRIDGE_DB'] = bridgeDbPath;
  process.env['CSTK_SECRETS_FILTER'] = '/caminho/que/nao/existe/secrets-filter.sh';
  resetSecretsFilterAvailabilityForTests();
});

afterEach(() => {
  process.env = { ...ORIGINAL_ENV };
  resetSecretsFilterAvailabilityForTests();
  rmSync(base, { recursive: true, force: true });
});

const VALID_HOST = { host: '127.0.0.1:5173' };
const VALID_ORIGIN = 'http://localhost:5173'; // default config.corsOrigin

function createBody(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    projectPath: '/tmp/proj',
    project: 'proj',
    shortName: 'human-bridge',
    executionKind: 'feature-00c',
    kind: 'choice',
    question: 'confirma?',
    options: ['a', 'b'],
    defaultValue: 'a',
    timeoutMs: 240000,
    ...overrides,
  };
}

async function create(overrides: Record<string, unknown> = {}) {
  return server.inject({
    method: 'POST',
    url: '/api/v1/bridge/interventions',
    headers: { 'content-type': 'application/json', ...VALID_HOST },
    payload: createBody(overrides),
  });
}

// ─────────────────────────────────────────────────────────
// POST /bridge/interventions — criar (§4)
// ─────────────────────────────────────────────────────────
describe('POST /api/v1/bridge/interventions', () => {
  it('caminho feliz: 201 com questionId/expiresAt/state=open', async () => {
    const res = await create();
    expect(res.statusCode).toBe(201);
    const body = res.json();
    expect(body.data.questionId).toEqual(expect.any(String));
    expect(body.data.state).toBe('open');
    expect(body.meta.degraded).toBe(false);
  });

  it('kind=choice sem options -> 400', async () => {
    const res = await create({ options: null });
    expect(res.statusCode).toBe(400);
    expect(res.json().error).toEqual(expect.any(String));
  });

  it('payload invalido (sem defaultValue) -> 400', async () => {
    const res = await create({ defaultValue: undefined });
    expect(res.statusCode).toBe(400);
  });

  it('Content-Type != application/json -> 415', async () => {
    const res = await server.inject({
      method: 'POST',
      url: '/api/v1/bridge/interventions',
      headers: { 'content-type': 'text/plain', ...VALID_HOST },
      payload: JSON.stringify(createBody()),
    });
    expect(res.statusCode).toBe(415);
  });

  it('Host nao-loopback -> 400 (contrato §11.4)', async () => {
    const res = await server.inject({
      method: 'POST',
      url: '/api/v1/bridge/interventions',
      headers: { 'content-type': 'application/json', host: 'evil.example:1234' },
      payload: createBody(),
    });
    expect(res.statusCode).toBe(400);
  });

  it('bridge.db indisponivel (dir sem permissao) -> 200 + degraded=true, sem questionId', async () => {
    // CSTK_BRIDGE_DB apontando para um path cujo diretorio pai nao pode ser
    // criado (arquivo regular no lugar de diretorio) — openBridgeDb() lanca.
    const blockerFile = join(base, 'blocker');
    rmSync(blockerFile, { force: true });
    writeFileSync(blockerFile, 'x');
    process.env['CSTK_BRIDGE_DB'] = join(blockerFile, 'bridge.db');

    const res = await create();
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.meta.degraded).toBe(true);
    expect(body.data).toBeNull();
  });

  it('question e cada elemento de options[] passam por scrub (§11.3) — Bearer token redigido', async () => {
    const res = await create({
      question: 'a chave e Bearer abc123def456?',
      options: ['Bearer abc123def456', 'b'],
    });
    expect(res.statusCode).toBe(201);
    // Le de volta via a fila para inspecionar o texto persistido.
    const queue = await server.inject({ method: 'GET', url: '/api/v1/bridge/interventions', headers: VALID_HOST });
    const body = queue.json();
    const row = body.data.interventions.find((i: { questionId: string }) => i.questionId === res.json().data.questionId);
    expect(row.question).not.toContain('abc123def456');
    expect(row.options[0]).not.toContain('abc123def456');
  });
});

// ─────────────────────────────────────────────────────────
// GET /bridge/interventions/:questionId — polling (§5)
// ─────────────────────────────────────────────────────────
describe('GET /api/v1/bridge/interventions/:questionId', () => {
  it('caminho feliz: state=open logo apos a criacao', async () => {
    const created = await create();
    const { questionId } = created.json().data;
    const res = await server.inject({ method: 'GET', url: `/api/v1/bridge/interventions/${questionId}`, headers: VALID_HOST });
    expect(res.statusCode).toBe(200);
    expect(res.json().data.state).toBe('open');
  });

  it('questionId desconhecido -> 404', async () => {
    const res = await server.inject({
      method: 'GET',
      url: `/api/v1/bridge/interventions/${'a'.repeat(24)}`,
      headers: VALID_HOST,
    });
    expect(res.statusCode).toBe(404);
  });

  it('questionId em formato invalido -> 400 (contrato §11.6)', async () => {
    const res = await server.inject({ method: 'GET', url: '/api/v1/bridge/interventions/x!!', headers: VALID_HOST });
    expect(res.statusCode).toBe(400);
  });
});

// ─────────────────────────────────────────────────────────
// GET /bridge/interventions — fila (§6)
// ─────────────────────────────────────────────────────────
describe('GET /api/v1/bridge/interventions', () => {
  it('lista intervencoes abertas ordenadas por createdAt ASC', async () => {
    await create({ question: 'primeira' });
    await create({ question: 'segunda' });
    const res = await server.inject({ method: 'GET', url: '/api/v1/bridge/interventions', headers: VALID_HOST });
    expect(res.statusCode).toBe(200);
    const { interventions } = res.json().data;
    expect(interventions.length).toBe(2);
    expect(interventions[0].question).toBe('primeira');
  });

  it('reachable=false quando projectPath nao existe mais em disco', async () => {
    await create({ projectPath: '/caminho/que/nao/existe/jamais' });
    const res = await server.inject({ method: 'GET', url: '/api/v1/bridge/interventions', headers: VALID_HOST });
    expect(res.json().data.interventions[0].reachable).toBe(false);
  });

  it('bridge.db ausente -> 200 + degraded=true + interventions vazio implicito (data:null)', async () => {
    process.env['CSTK_BRIDGE_DB'] = join(base, 'nested', 'unreachable', 'bridge.db');
    const blockerFile = join(base, 'nested');
    writeFileSync(blockerFile, 'x');
    const res = await server.inject({ method: 'GET', url: '/api/v1/bridge/interventions', headers: VALID_HOST });
    expect(res.statusCode).toBe(200);
    expect(res.json().meta.degraded).toBe(true);
  });
});

// ─────────────────────────────────────────────────────────
// POST /bridge/interventions/:questionId/answer — responder (§7)
// ─────────────────────────────────────────────────────────
describe('POST /api/v1/bridge/interventions/:questionId/answer', () => {
  async function answer(questionId: string, body: Record<string, unknown>) {
    return server.inject({
      method: 'POST',
      url: `/api/v1/bridge/interventions/${questionId}/answer`,
      headers: { 'content-type': 'application/json', ...VALID_HOST },
      payload: body,
    });
  }

  it('resolucao valida (choice) -> 200 com estado final', async () => {
    const created = await create();
    const { questionId } = created.json().data;
    const res = await answer(questionId, { resolution: 'answered', value: 'a', text: null });
    expect(res.statusCode).toBe(200);
    expect(res.json().data.state).toBe('answered');
    expect(res.json().data.appliedValue).toBe('a');
  });

  it('value fora de options -> 400 (FR-005, validacao de SERVIDOR)', async () => {
    const created = await create();
    const { questionId } = created.json().data;
    const res = await answer(questionId, { resolution: 'answered', value: 'nao-existe', text: null });
    expect(res.statusCode).toBe(400);
  });

  it('kind=confirm exige value yes|no', async () => {
    const created = await create({ kind: 'confirm', options: null });
    const { questionId } = created.json().data;
    const bad = await answer(questionId, { resolution: 'answered', value: 'talvez', text: null });
    expect(bad.statusCode).toBe(400);
    const good = await answer(questionId, { resolution: 'answered', value: 'yes', text: null });
    expect(good.statusCode).toBe(200);
  });

  it('kind=text: value e o token de desfecho, text e o conteudo (scrubbed/truncado)', async () => {
    const created = await create({ kind: 'text', options: null, question: 'digite algo' });
    const { questionId } = created.json().data;
    const res = await answer(questionId, { resolution: 'answered', value: 'ok', text: 'Bearer abc123def456' });
    expect(res.statusCode).toBe(200);
    expect(res.json().data.untrustedText).not.toContain('abc123def456');
  });

  it('text presente com kind != text -> 400', async () => {
    const created = await create();
    const { questionId } = created.json().data;
    const res = await answer(questionId, { resolution: 'answered', value: 'a', text: 'nao deveria vir aqui' });
    expect(res.statusCode).toBe(400);
  });

  it('questionId desconhecido -> 404', async () => {
    const res = await answer('a'.repeat(24), { resolution: 'declined', value: null, text: null });
    expect(res.statusCode).toBe(404);
  });

  it('FR-016/SC-006: duas respostas concorrentes — a primeira vence (200), a segunda ve 409', async () => {
    const created = await create();
    const { questionId } = created.json().data;
    const [first, second] = await Promise.all([
      answer(questionId, { resolution: 'answered', value: 'a', text: null }),
      answer(questionId, { resolution: 'answered', value: 'b', text: null }),
    ]);
    const statuses = [first.statusCode, second.statusCode].sort();
    expect(statuses).toEqual([200, 409]);
  });

  it('resposta apos ja resolvida -> 409', async () => {
    const created = await create();
    const { questionId } = created.json().data;
    await answer(questionId, { resolution: 'answered', value: 'a', text: null });
    const res = await answer(questionId, { resolution: 'declined', value: null, text: null });
    expect(res.statusCode).toBe(409);
  });

  it('resposta apos expirar (timeoutMs=1) -> 409', async () => {
    const created = await create({ timeoutMs: 1 });
    const { questionId } = created.json().data;
    await new Promise((r) => setTimeout(r, 20));
    const res = await answer(questionId, { resolution: 'answered', value: 'a', text: null });
    expect(res.statusCode).toBe(409);
  });
});

// ─────────────────────────────────────────────────────────
// §11.1/§11.2 — CORS escopado + reflexao de Origin proibida (task 3.3.5)
// ─────────────────────────────────────────────────────────
describe('CORS escopado de /bridge/* (§11.1/§11.2)', () => {
  it('preflight de /bridge/interventions aceita POST (methods inclui POST)', async () => {
    const res = await server.inject({
      method: 'OPTIONS',
      url: '/api/v1/bridge/interventions',
      headers: { origin: VALID_ORIGIN, 'access-control-request-method': 'POST' },
    });
    expect(res.statusCode).toBe(204);
    expect(res.headers['access-control-allow-methods']).toContain('POST');
  });

  it('Access-Control-Allow-Origin NUNCA reflete o header Origin da requisicao (allowlist fixa, nunca origin:true)', async () => {
    const res = await server.inject({
      method: 'OPTIONS',
      url: '/api/v1/bridge/interventions',
      headers: { origin: 'http://evil.example', 'access-control-request-method': 'POST' },
    });
    expect(res.headers['access-control-allow-origin']).not.toBe('http://evil.example');
  });
});
