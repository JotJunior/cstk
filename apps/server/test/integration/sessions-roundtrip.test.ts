/**
 * 8.1 Roundtrip End-to-End OBRIGATORIO das rotas de sessao — servidor real
 * (mesmo modulo `sessionRoutes` que producao registra) + watcher real
 * (`runSessionsWatcherTick()` sem `scanImpl` injetado) + filesystem real
 * (fixture ISOLADA em `tmpdir`, NUNCA `~/.claude/projects`).
 *
 * Ref: tasks.md FASE 8 (8.1.1, converge-key f09731b27d4f); contracts/
 * sessions-api.md; data-model.md Entities SessionSummaryDTO/SessionTailEntryDTO.
 *
 * Motivo (memoria migration-gates-false-green + achado da propria FASE 7):
 * `test/routes/sessions.test.ts` ja cobre servidor real + watcher real +
 * fixture real, mas nunca faz `safeParse` do payload contra o schema Zod
 * COMPARTILHADO de `@cstk-panel/shared-types` — so compara campos
 * individuais via `expect(body.data!.x).toBe(y)` com um tipo local
 * `as {...}`. Um drift de nome de campo entre o objeto emitido pela rota e o
 * schema compartilhado passaria por aquela suite inteira sem detectar nada.
 * Este arquivo fecha exatamente essa lacuna: importa
 * `SessionSummaryDTOSchema`/`SessionTailEntryDTOSchema` de
 * `@cstk-panel/shared-types` (o MESMO objeto usado pelo restante do sistema,
 * inclusive `apps/web/src/lib/hooks.ts`) e faz `safeParse` do payload de
 * resposta real — nenhuma fixture escrita a mao comparada por igualdade,
 * nenhuma type assertion no lugar do parse, nenhuma copia local do schema.
 *
 * Tambem cobre a regressao especifica da onda-014 (`readSessionTail` e
 * `scanSessions` viraram `async`): se algum caminho de chamada esquecer
 * `await`, um campo de texto do payload vira a string literal
 * `"[object Promise]"` — o unico teste desta suite que veria esse defeito
 * chegar ao cliente e o que faz `safeParse` + varredura de substring sobre
 * a resposta JSON *serializada* de verdade (nao sobre um objeto construido
 * em memoria pelo teste).
 */
import { describe, it, expect, beforeAll, afterAll, beforeEach, afterEach } from 'vitest';
import Fastify from 'fastify';
import type { FastifyInstance } from 'fastify';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync, realpathSync, utimesSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { z } from 'zod';
import {
  ApiEnvelopeSchema,
  SessionSummaryDTOSchema,
  SessionTailEntryDTOSchema,
} from '@cstk-panel/shared-types';
import { sessionRoutes } from '../../src/routes/sessions.js';
import { runSessionsWatcherTick, resetSessionsIndexForTests } from '../../src/watchers/sessions-watcher.js';
import { resetSecretsFilterAvailabilityForTests } from '../../src/lib/secret-scrub.js';

// ---------------------------------------------------------------------------
// Schemas de ENVELOPE compostos a partir dos DTOs COMPARTILHADOS importados
// acima — nunca uma copia dos campos de SessionSummaryDTO/SessionTailEntryDTO.
// Mesmo padrao de `ApiEnvelopeSchema(FeatureDocsListDTOSchema)` em
// `docs-roundtrip.test.ts`, e espelha (sem importar de `apps/web`, que nao e
// dependencia deste pacote) a composicao real ja usada pelo cliente em
// `apps/web/src/lib/hooks.ts` (`SessionsListDataSchema`/`SessionTailDataSchema`).
// ---------------------------------------------------------------------------
const SessionsListDataSchema = z.object({
  sessions: z.array(SessionSummaryDTOSchema),
  total: z.number(),
  scannedAt: z.string(),
  scrubMode: z.enum(['cstk+internal', 'internal']),
});
const SessionsListEnvelopeSchema = ApiEnvelopeSchema(SessionsListDataSchema);

const SessionTailDataSchema = z.object({
  sessionId: z.string(),
  entries: z.array(SessionTailEntryDTOSchema),
  requestedLines: z.number(),
  returnedLines: z.number(),
  skippedLines: z.number(),
  truncatedByBytes: z.boolean(),
  windowTruncated: z.boolean(),
  live: z.boolean(),
  lastActivityAt: z.string(),
  scrubMode: z.enum(['cstk+internal', 'internal']),
});
const SessionTailEnvelopeSchema = ApiEnvelopeSchema(SessionTailDataSchema);

/**
 * Varredura recursiva por ocorrencia literal de `"[object Promise]"` em
 * QUALQUER string do payload — defesa contra uma Promise nao aguardada
 * silenciosamente stringificada (regressao onda-014, ver comentario de topo).
 */
function findObjectPromiseLeak(value: unknown, path = '$'): string | null {
  if (typeof value === 'string') {
    return value.includes('[object Promise]') ? path : null;
  }
  if (Array.isArray(value)) {
    for (let i = 0; i < value.length; i++) {
      const hit = findObjectPromiseLeak(value[i], `${path}[${i}]`);
      if (hit !== null) return hit;
    }
    return null;
  }
  if (value !== null && typeof value === 'object') {
    for (const [k, v] of Object.entries(value)) {
      const hit = findObjectPromiseLeak(v, `${path}.${k}`);
      if (hit !== null) return hit;
    }
  }
  return null;
}

const VALID_UUID_1 = '5f3c2e10-71a4-4b8e-9c1a-2d6f8b0a9e11';
const VALID_UUID_2 = '9a1b2c3d-4e5f-4a6b-8c7d-1234567890ab';

let base: string;
let root: string;
let server: FastifyInstance;
const ORIGINAL_ENV = { ...process.env };

/** Fixture ISOLADA em tmpdir proprio — NUNCA `~/.claude/projects` real. */
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
  // Registro do modulo de rotas REAL — nenhum mock de handler, mesmo padrao
  // de test/integration/docs-roundtrip.test.ts e test/lib/roundtrip.test.ts.
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
  base = mkdtempSync(join(realpathSync(tmpdir()), 'sessions-roundtrip-'));
  root = join(base, 'projects');
  mkdirSync(root);
  process.env['CSTK_SESSIONS_ROOT'] = root;
  process.env['CSTK_SESSION_LIVE_WINDOW_MS'] = '300000'; // 5 min
  // Determinismo (mesma convencao de test/routes/sessions.test.ts): nunca
  // depender do secrets-filter.sh real da maquina — scrubMode fica 'internal'.
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

describe('8.1 Roundtrip E2E real — GET /sessions e GET /sessions/:id/tail (OBRIGATORIO)', () => {
  // 8.1.1a — caminho feliz, GET /sessions
  it('8.1.1a GET /sessions: payload real valida contra SessionSummaryDTOSchema compartilhado', async () => {
    const now = Date.now();
    writeSession(
      'slug-a',
      VALID_UUID_1,
      [`{"cwd":"/tmp/projeto-a","sessionId":"${VALID_UUID_1}"}`],
      now - 60_000
    );
    writeSession(
      'slug-b',
      VALID_UUID_2,
      [`{"cwd":"/tmp/projeto-b","sessionId":"${VALID_UUID_2}"}`],
      now
    );
    await runSessionsWatcherTick();

    const res = await server.inject({ method: 'GET', url: '/api/v1/sessions' });
    expect(res.statusCode).toBe(200);

    // Parse do payload SERIALIZADO real (nao um objeto construido pelo
    // teste) contra o schema Zod compartilhado — nunca comparacao manual
    // campo-a-campo, nunca type assertion.
    const raw: unknown = res.json();
    const parsed = SessionsListEnvelopeSchema.safeParse(raw);
    expect(
      parsed.success,
      `parse falhou: ${JSON.stringify(parsed.error?.issues?.slice(0, 5))}`
    ).toBe(true);

    expect(findObjectPromiseLeak(raw)).toBeNull();

    const body = raw as { data: { sessions: unknown[]; total: number } };
    expect(body.data.total).toBe(2);
    expect(body.data.sessions).toHaveLength(2);
  });

  // 8.1.1b — caminho feliz, GET /sessions/:id/tail
  it('8.1.1b GET /sessions/:id/tail: payload real valida contra SessionTailEntryDTOSchema compartilhado', async () => {
    writeSession(
      'slug-a',
      VALID_UUID_1,
      [
        '{"uuid":"e1","type":"user","timestamp":"2026-01-01T00:00:00Z","message":{"role":"user","content":"ola, tudo bem?"}}',
        '{"uuid":"e2","type":"assistant","timestamp":"2026-01-01T00:00:05Z","message":{"role":"assistant","content":[{"type":"text","text":"tudo certo"}]}}',
      ],
      Date.now()
    );
    await runSessionsWatcherTick();

    const res = await server.inject({
      method: 'GET',
      url: `/api/v1/sessions/${VALID_UUID_1}/tail`,
    });
    expect(res.statusCode).toBe(200);

    const raw: unknown = res.json();
    const parsed = SessionTailEnvelopeSchema.safeParse(raw);
    expect(
      parsed.success,
      `parse falhou: ${JSON.stringify(parsed.error?.issues?.slice(0, 5))}`
    ).toBe(true);

    // Assercao explicita anti-regressao onda-014 (Promise nao aguardada).
    expect(findObjectPromiseLeak(raw)).toBeNull();

    const body = raw as { data: { sessionId: string; entries: { text: string }[] } };
    expect(body.data.sessionId).toBe(VALID_UUID_1);
    expect(body.data.entries).toHaveLength(2);
    expect(body.data.entries[0]?.text).toBe('ola, tudo bem?');
    expect(body.data.entries[1]?.text).toBe('tudo certo');
  });

  // 8.1.1c — cenario degradado (raiz ausente), GET /sessions: o degradado
  // TAMBEM respeita o envelope/contrato (data: null, meta.reason tipado).
  it('8.1.1c GET /sessions degradado (raiz ausente): envelope ainda valida contra o schema compartilhado', async () => {
    process.env['CSTK_SESSIONS_ROOT'] = join(base, 'nao-existe');
    await runSessionsWatcherTick();

    const res = await server.inject({ method: 'GET', url: '/api/v1/sessions' });
    expect(res.statusCode).toBe(200);

    const raw: unknown = res.json();
    const parsed = SessionsListEnvelopeSchema.safeParse(raw);
    expect(
      parsed.success,
      `parse falhou: ${JSON.stringify(parsed.error?.issues?.slice(0, 5))}`
    ).toBe(true);
    expect(findObjectPromiseLeak(raw)).toBeNull();

    const body = raw as { data: null; meta: { degraded: boolean; reason: string | null } };
    expect(body.data).toBeNull();
    expect(body.meta.degraded).toBe(true);
    expect(body.meta.reason).toBe('sessions-root-missing');
  });

  // 8.1.1d — cenario degradado (sessionId ausente do indice), GET /:id/tail
  it('8.1.1d GET /sessions/:id/tail degradado (session-not-found): envelope ainda valida contra o schema compartilhado', async () => {
    await runSessionsWatcherTick(); // indice varrido, vazio

    const res = await server.inject({
      method: 'GET',
      url: `/api/v1/sessions/${VALID_UUID_1}/tail`,
    });
    expect(res.statusCode).toBe(200);

    const raw: unknown = res.json();
    const parsed = SessionTailEnvelopeSchema.safeParse(raw);
    expect(
      parsed.success,
      `parse falhou: ${JSON.stringify(parsed.error?.issues?.slice(0, 5))}`
    ).toBe(true);
    expect(findObjectPromiseLeak(raw)).toBeNull();

    const body = raw as { data: null; meta: { degraded: boolean; reason: string | null } };
    expect(body.data).toBeNull();
    expect(body.meta.degraded).toBe(true);
    expect(body.meta.reason).toBe('session-not-found');
  });
});
