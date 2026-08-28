/**
 * Testes de integracao das rotas GET /sessions e GET /sessions/:sessionId/tail
 * (tasks 5.1.3, 5.2.4, 5.4.3).
 * Ref: contracts/sessions-api.md; tasks.md FASE 5.
 *
 * Servidor Fastify real (`server.inject()`), so com `sessionRoutes`
 * registrado — mesmo padrao de `test/lib/routes.test.ts`/`test/integration/*`.
 * `sessions-watcher` e alimentado por um scan REAL (`runSessionsWatcherTick()`
 * sem `scanImpl` injetado) sobre fixtures em tmpdir, para que a resolucao de
 * `sessionId` -> `(projectSlug, filePath)` exercite o indice de verdade (nao
 * um mock que mascararia um drift entre rota e watcher).
 *
 * `CSTK_SECRETS_FILTER` forcado a um path inexistente (determinismo —
 * `scrubMode: 'internal'` em toda a suite, mesma convencao de
 * session-scan.test.ts/session-tail.test.ts).
 */
import { describe, it, expect, beforeAll, afterAll, beforeEach, afterEach } from 'vitest';
import Fastify from 'fastify';
import type { FastifyInstance } from 'fastify';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync, realpathSync, utimesSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { sessionRoutes } from '../../src/routes/sessions.js';
import { runSessionsWatcherTick, resetSessionsIndexForTests } from '../../src/watchers/sessions-watcher.js';
import { resetSecretsFilterAvailabilityForTests } from '../../src/lib/secret-scrub.js';

const VALID_UUID_1 = '5f3c2e10-71a4-4b8e-9c1a-2d6f8b0a9e11';
const VALID_UUID_2 = '9a1b2c3d-4e5f-4a6b-8c7d-1234567890ab';

let base: string;
let root: string;
let server: FastifyInstance;
const ORIGINAL_ENV = { ...process.env };

function writeSession(slug: string, sessionId: string, lines: string[], mtimeMs: number): string {
  const slugDir = join(root, slug);
  mkdirSync(slugDir, { recursive: true });
  const filePath = join(slugDir, `${sessionId}.jsonl`);
  writeFileSync(filePath, lines.map((l) => `${l}\n`).join(''));
  const seconds = mtimeMs / 1000;
  utimesSync(filePath, seconds, seconds);
  return filePath;
}

beforeAll(async () => {
  server = Fastify({ logger: false });
  await server.register(async (v1) => {
    await v1.register(sessionRoutes);
  }, { prefix: '/api/v1' });
  await server.ready();
});

afterAll(async () => {
  await server.close();
});

beforeEach(() => {
  base = mkdtempSync(join(realpathSync(tmpdir()), 'sessions-route-'));
  root = join(base, 'projects');
  mkdirSync(root);
  process.env['CSTK_SESSIONS_ROOT'] = root;
  process.env['CSTK_SESSION_LIVE_WINDOW_MS'] = '300000'; // 5 min
  // Determinismo: nunca depender do secrets-filter.sh real da maquina de dev/CI.
  process.env['CSTK_SECRETS_FILTER'] = '/caminho/que/nao/existe/secrets-filter.sh';
  delete process.env['CSTK_SESSIONS_RATE_LIMIT_MAX'];
  delete process.env['CSTK_SESSIONS_RATE_LIMIT_WINDOW_MS'];
  resetSecretsFilterAvailabilityForTests();
  resetSessionsIndexForTests();
});

afterEach(() => {
  process.env = { ...ORIGINAL_ENV };
  resetSecretsFilterAvailabilityForTests();
  resetSessionsIndexForTests();
  rmSync(base, { recursive: true, force: true });
});

// ─────────────────────────────────────────────────────────
// GET /sessions (task 5.1.3)
// ─────────────────────────────────────────────────────────

describe('GET /api/v1/sessions', () => {
  it('raiz ausente -> 200 degradado, reason sessions-root-missing', async () => {
    process.env['CSTK_SESSIONS_ROOT'] = join(base, 'nao-existe');
    await runSessionsWatcherTick();

    const res = await server.inject({ method: 'GET', url: '/api/v1/sessions' });
    expect(res.statusCode).toBe(200);
    const body = res.json<{ data: null; meta: { degraded: boolean; reason: string | null } }>();
    expect(body.meta.degraded).toBe(true);
    expect(body.meta.reason).toBe('sessions-root-missing');
    expect(body.data).toBeNull();
  });

  it('raiz vazia -> 200 nao-degradado, sessions: [], total: 0', async () => {
    await runSessionsWatcherTick();

    const res = await server.inject({ method: 'GET', url: '/api/v1/sessions' });
    expect(res.statusCode).toBe(200);
    const body = res.json<{ data: { sessions: unknown[]; total: number; scannedAt: string; scrubMode: string }; meta: { degraded: boolean } }>();
    expect(body.meta.degraded).toBe(false);
    expect(body.data.sessions).toEqual([]);
    expect(body.data.total).toBe(0);
    expect(typeof body.data.scannedAt).toBe('string');
    expect(body.data.scannedAt.length).toBeGreaterThan(0);
    expect(body.data.scrubMode).toBe('internal');
  });

  it('happy path: lista sessoes ordenadas por lastActivityAt desc', async () => {
    const now = Date.now();
    writeSession('slug-a', VALID_UUID_1, [`{"cwd":"/tmp/a","sessionId":"${VALID_UUID_1}"}`], now - 60_000);
    writeSession('slug-b', VALID_UUID_2, [`{"cwd":"/tmp/b","sessionId":"${VALID_UUID_2}"}`], now);
    await runSessionsWatcherTick();

    const res = await server.inject({ method: 'GET', url: '/api/v1/sessions' });
    expect(res.statusCode).toBe(200);
    const body = res.json<{ data: { sessions: { sessionId: string }[]; total: number } }>();
    expect(body.data.total).toBe(2);
    expect(body.data.sessions.map((s) => s.sessionId)).toEqual([VALID_UUID_2, VALID_UUID_1]); // mais recente primeiro
  });

  it('live=true (default) filtra apenas vivas; live=false devolve todas', async () => {
    const now = Date.now();
    writeSession('slug-a', VALID_UUID_1, [`{"cwd":"/tmp/a"}`], now); // viva
    writeSession('slug-b', VALID_UUID_2, [`{"cwd":"/tmp/b"}`], now - 10 * 60_000); // fora da janela de 5min
    await runSessionsWatcherTick();

    const liveOnly = await server.inject({ method: 'GET', url: '/api/v1/sessions' });
    const liveBody = liveOnly.json<{ data: { sessions: { sessionId: string }[]; total: number } }>();
    expect(liveBody.data.total).toBe(1);
    expect(liveBody.data.sessions[0]?.sessionId).toBe(VALID_UUID_1);

    const all = await server.inject({ method: 'GET', url: '/api/v1/sessions?live=false' });
    const allBody = all.json<{ data: { sessions: { sessionId: string }[]; total: number } }>();
    expect(allBody.data.total).toBe(2);
  });

  it('limit fora de 1..500 clampa silenciosamente (nunca 4xx)', async () => {
    const now = Date.now();
    writeSession('slug-a', VALID_UUID_1, [`{"cwd":"/tmp/a"}`], now);
    writeSession('slug-b', VALID_UUID_2, [`{"cwd":"/tmp/b"}`], now - 1000);
    await runSessionsWatcherTick();

    const zero = await server.inject({ method: 'GET', url: '/api/v1/sessions?limit=0' });
    expect(zero.statusCode).toBe(200);
    const zeroBody = zero.json<{ data: { sessions: unknown[]; total: number } }>();
    expect(zeroBody.data.sessions).toHaveLength(1); // clamp para o minimo (1)
    expect(zeroBody.data.total).toBe(2); // total nao e afetado pelo clamp de limit

    const huge = await server.inject({ method: 'GET', url: '/api/v1/sessions?limit=999999' });
    expect(huge.statusCode).toBe(200);
    const hugeBody = huge.json<{ data: { sessions: unknown[] } }>();
    expect(hugeBody.data.sessions).toHaveLength(2); // clamp para o maximo nao limita menos do que o total real

    const garbage = await server.inject({ method: 'GET', url: '/api/v1/sessions?limit=abc' });
    expect(garbage.statusCode).toBe(200); // nunca 4xx por query invalida (Principio II)
  });
});

// ─────────────────────────────────────────────────────────
// GET /sessions/:sessionId/tail (task 5.2.4)
// ─────────────────────────────────────────────────────────

describe('GET /api/v1/sessions/:sessionId/tail', () => {
  it('tail de sessao viva -> 200 nao-degradado com entries', async () => {
    writeSession('slug-a', VALID_UUID_1, [
      '{"type":"user","uuid":"e1","timestamp":"2026-01-01T00:00:00Z","message":{"role":"user","content":"ola"}}',
    ], Date.now());
    await runSessionsWatcherTick();

    const res = await server.inject({ method: 'GET', url: `/api/v1/sessions/${VALID_UUID_1}/tail` });
    expect(res.statusCode).toBe(200);
    const body = res.json<{
      data: { sessionId: string; entries: { text: string }[]; live: boolean; scrubMode: string } | null;
      meta: { degraded: boolean };
    }>();
    expect(body.meta.degraded).toBe(false);
    expect(body.data).not.toBeNull();
    expect(body.data!.sessionId).toBe(VALID_UUID_1);
    expect(body.data!.entries).toHaveLength(1);
    expect(body.data!.entries[0]?.text).toBe('ola');
    expect(body.data!.live).toBe(true);
    expect(body.data!.scrubMode).toBe('internal');
  });

  it('tail de sessao nao-viva (live:false) ainda serve 200 com conteudo (FR-003)', async () => {
    writeSession('slug-a', VALID_UUID_1, [
      '{"type":"user","message":{"role":"user","content":"conteudo antigo"}}',
    ], Date.now() - 10 * 60_000); // fora da janela de 5min
    await runSessionsWatcherTick();

    const res = await server.inject({ method: 'GET', url: `/api/v1/sessions/${VALID_UUID_1}/tail` });
    expect(res.statusCode).toBe(200);
    const body = res.json<{ data: { entries: { text: string }[]; live: boolean } | null; meta: { degraded: boolean } }>();
    expect(body.meta.degraded).toBe(false);
    expect(body.data!.live).toBe(false);
    expect(body.data!.entries[0]?.text).toBe('conteudo antigo');
  });

  it('sessionId bem-formado mas ausente do indice -> session-not-found (nunca 404)', async () => {
    await runSessionsWatcherTick(); // indice varrido, vazio

    const res = await server.inject({ method: 'GET', url: `/api/v1/sessions/${VALID_UUID_1}/tail` });
    expect(res.statusCode).toBe(200);
    const body = res.json<{ data: null; meta: { degraded: boolean; reason: string | null } }>();
    expect(body.meta.degraded).toBe(true);
    expect(body.meta.reason).toBe('session-not-found');
  });

  it('sessionId malformado (path traversal / nao-UUID) -> session-rejected, sem tocar o disco', async () => {
    await runSessionsWatcherTick();

    const res = await server.inject({
      method: 'GET',
      url: `/api/v1/sessions/${encodeURIComponent('../../../../etc/passwd')}/tail`,
    });
    expect(res.statusCode).toBe(200);
    const body = res.json<{ data: null; meta: { degraded: boolean; reason: string | null } }>();
    expect(body.meta.degraded).toBe(true);
    expect(body.meta.reason).toBe('session-rejected');
  });

  it('raiz ausente -> 200 degradado sessions-root-missing (mesmo com sessionId valido)', async () => {
    process.env['CSTK_SESSIONS_ROOT'] = join(base, 'nao-existe');
    await runSessionsWatcherTick();

    const res = await server.inject({ method: 'GET', url: `/api/v1/sessions/${VALID_UUID_1}/tail` });
    expect(res.statusCode).toBe(200);
    const body = res.json<{ meta: { degraded: boolean; reason: string | null } }>();
    expect(body.meta.degraded).toBe(true);
    expect(body.meta.reason).toBe('sessions-root-missing');
  });

  it('duas sessoes de projetos distintos: sessionId de uma nunca resolve conteudo da outra (CHK034)', async () => {
    writeSession('projeto-a-slug', VALID_UUID_1, [
      '{"type":"user","message":{"role":"user","content":"segredo-do-projeto-A"}}',
    ], Date.now());
    writeSession('projeto-b-slug', VALID_UUID_2, [
      '{"type":"user","message":{"role":"user","content":"segredo-do-projeto-B"}}',
    ], Date.now());
    await runSessionsWatcherTick();

    const resA = await server.inject({ method: 'GET', url: `/api/v1/sessions/${VALID_UUID_1}/tail` });
    const bodyA = resA.json<{ data: { entries: { text: string }[] } }>();
    expect(bodyA.data.entries[0]?.text).toBe('segredo-do-projeto-A');
    expect(bodyA.data.entries.some((e) => e.text.includes('projeto-B'))).toBe(false);

    const resB = await server.inject({ method: 'GET', url: `/api/v1/sessions/${VALID_UUID_2}/tail` });
    const bodyB = resB.json<{ data: { entries: { text: string }[] } }>();
    expect(bodyB.data.entries[0]?.text).toBe('segredo-do-projeto-B');
    expect(bodyB.data.entries.some((e) => e.text.includes('projeto-A'))).toBe(false);
  });

  it('lines fora de 1..1000 clampa silenciosamente (nunca 4xx)', async () => {
    const lines = Array.from({ length: 5 }, (_, i) => `{"type":"user","message":{"role":"user","content":"linha-${i}"}}`);
    writeSession('slug-a', VALID_UUID_1, lines, Date.now());
    await runSessionsWatcherTick();

    const res = await server.inject({ method: 'GET', url: `/api/v1/sessions/${VALID_UUID_1}/tail?lines=0` });
    expect(res.statusCode).toBe(200);
    const body = res.json<{ data: { requestedLines: number; returnedLines: number } }>();
    expect(body.data.requestedLines).toBe(1); // clamp para o minimo
    expect(body.data.returnedLines).toBe(1);
  });
});

// ─────────────────────────────────────────────────────────
// Rate-limit leve (task 5.4.3)
// ─────────────────────────────────────────────────────────

describe('Rate-limit leve das rotas de sessoes (task 0.5.2/5.4)', () => {
  it('excedente responde 429 (nao 200, nao 500); dentro do limite, comportamento normal', async () => {
    process.env['CSTK_SESSIONS_RATE_LIMIT_MAX'] = '2';
    process.env['CSTK_SESSIONS_RATE_LIMIT_WINDOW_MS'] = '60000';

    // Servidor dedicado: o rate-limit e configurado no registro do plugin,
    // lido de env no momento do registro — precisa de uma instancia nova
    // com as env vars acima já setadas antes do `server.register`.
    const rateLimitedServer = Fastify({ logger: false });
    await rateLimitedServer.register(async (v1) => {
      await v1.register(sessionRoutes);
    }, { prefix: '/api/v1' });
    await rateLimitedServer.ready();

    await runSessionsWatcherTick();

    const first = await rateLimitedServer.inject({ method: 'GET', url: '/api/v1/sessions' });
    const second = await rateLimitedServer.inject({ method: 'GET', url: '/api/v1/sessions' });
    const third = await rateLimitedServer.inject({ method: 'GET', url: '/api/v1/sessions' });

    expect(first.statusCode).toBe(200);
    expect(second.statusCode).toBe(200);
    expect(third.statusCode).toBe(429);

    await rateLimitedServer.close();
  });
});
