/**
 * Rotas GET /sessions e GET /sessions/:sessionId/tail (FASE 5, task 5.1/5.2).
 * Ref: contracts/sessions-api.md; plan.md §Padroes de Seguranca e Qualidade;
 * tasks.md FASE 5.
 *
 * Superficie EXCLUSIVAMENTE GET (Constituicao 2.0.0) — nenhum verbo de
 * escrita. Estas rotas NAO abrem `knowledge.db` (`wrap(data, opts,
 * config.dbPath, null)` sempre — mesmo caminho que toda resposta degradada
 * do painel ja usa hoje); o dado vem inteiramente do indice em memoria do
 * `sessions-watcher` e da leitura direta do `.jsonl` confinado.
 *
 * Resolucao de `sessionId` (CHK015, task 0.1): SEMPRE via
 * `getSessionsIndex()` — nunca reconstrucao de path a partir do parametro de
 * cliente. UUID validado por Zod/`isValidSessionId` ANTES de qualquer
 * path-join (CHK016).
 *
 * Ausencia de dado degrada (200 + `data: null` + `DegradedReason`), nunca
 * `404` (Principio II). Excesso de requisicao responde `429` — categoria
 * distinta de "condicao de dado", nao viola o Principio II (0.5, ver
 * contracts/sessions-api.md "Nao ha respostas de erro").
 */
import type { FastifyInstance } from 'fastify';
import rateLimit from '@fastify/rate-limit';
import { z } from 'zod';
import { wrap, wrapDegraded } from '../lib/envelope.js';
import { loadConfig } from '../config.js';
import { getSessionsIndex } from '../watchers/sessions-watcher.js';
import {
  isValidSessionId,
  normalizeSessionId,
  resolveSessionsRoot,
  resolveConfinedSessionPath,
} from '../lib/sessions-root.js';
import { readSessionTail, type SessionTailReadResult } from '../lib/session-tail.js';

// ---------------------------------------------------------------------------
// Rate-limit leve (task 5.4.2, 0.5.2) — mesmo valor ja adotado em
// `search.ts` (30 req/min por IP): a rota tambem pode disparar I/O de disco
// e/ou um subprocesso por requisicao (`readSessionTail` -> cadeia de scrub),
// custo comparavel ao de uma consulta FTS. Nao e um numero novo sem fonte —
// e o mesmo valor ja em producao, reaproveitado; configuravel via env
// (contracts/sessions-api.md §Configuracao) para o operador ajustar sem
// rebuild.
// ---------------------------------------------------------------------------
const DEFAULT_SESSIONS_RATE_LIMIT_MAX = 30;
const DEFAULT_SESSIONS_RATE_LIMIT_WINDOW_MS = 60_000; // 1 minuto — mesma janela de search.ts

function resolveRateLimitMax(): number {
  const raw = process.env['CSTK_SESSIONS_RATE_LIMIT_MAX'];
  if (raw === undefined || raw.trim() === '') return DEFAULT_SESSIONS_RATE_LIMIT_MAX;
  const parsed = Number(raw);
  return Number.isFinite(parsed) && parsed > 0 ? Math.trunc(parsed) : DEFAULT_SESSIONS_RATE_LIMIT_MAX;
}

function resolveRateLimitWindowMs(): number {
  const raw = process.env['CSTK_SESSIONS_RATE_LIMIT_WINDOW_MS'];
  if (raw === undefined || raw.trim() === '') return DEFAULT_SESSIONS_RATE_LIMIT_WINDOW_MS;
  const parsed = Number(raw);
  return Number.isFinite(parsed) && parsed > 0 ? Math.trunc(parsed) : DEFAULT_SESSIONS_RATE_LIMIT_WINDOW_MS;
}

// ---------------------------------------------------------------------------
// GET /sessions — query params (Principio II: invalido -> clamp/default, nunca 4xx)
// ---------------------------------------------------------------------------
const SessionsListQuerySchema = z.object({
  live: z.string().optional(),
  limit: z.string().optional(),
});

const DEFAULT_SESSIONS_LIMIT = 100;
const MIN_SESSIONS_LIMIT = 1;
const MAX_SESSIONS_LIMIT = 500;

/** `live` default `true`; somente a string exata `'false'` desativa o filtro. */
function parseLiveParam(raw: string | undefined): boolean {
  return raw !== 'false';
}

function parseListLimitParam(raw: string | undefined): number {
  if (raw === undefined) return DEFAULT_SESSIONS_LIMIT;
  const parsed = Number(raw);
  if (!Number.isFinite(parsed)) return DEFAULT_SESSIONS_LIMIT;
  const truncated = Math.trunc(parsed);
  if (truncated < MIN_SESSIONS_LIMIT) return MIN_SESSIONS_LIMIT;
  if (truncated > MAX_SESSIONS_LIMIT) return MAX_SESSIONS_LIMIT;
  return truncated;
}

// ---------------------------------------------------------------------------
// GET /sessions/:sessionId/tail — params/query
// ---------------------------------------------------------------------------
const SessionIdParamSchema = z.object({ sessionId: z.string() });
const SessionTailQuerySchema = z.object({ lines: z.string().optional() });

/** `undefined` cai no default de `readSessionTail` (200) — clamp real acontece la. */
function parseTailLinesParam(raw: string | undefined): number | undefined {
  if (raw === undefined) return undefined;
  const parsed = Number(raw);
  return Number.isFinite(parsed) ? parsed : undefined;
}

export async function sessionRoutes(server: FastifyInstance): Promise<void> {
  const config = loadConfig();

  await server.register(async (scoped) => {
    await scoped.register(rateLimit, {
      max: resolveRateLimitMax(),
      timeWindow: resolveRateLimitWindowMs(),
      skipOnError: true,
      keyGenerator: (req) => req.ip,
    });

    // GET /sessions
    scoped.get('/sessions', async (request, reply) => {
      const qResult = SessionsListQuerySchema.safeParse(request.query);
      const { live: liveRaw, limit: limitRaw } = qResult.success ? qResult.data : {};
      const live = parseLiveParam(liveRaw);
      const limit = parseListLimitParam(limitRaw);

      const snapshot = getSessionsIndex();

      // Snapshot atomico (achado onda-015): sessions/scannedAt/scrubMode vem
      // TODOS da mesma leitura de indexState — nunca getters separados que
      // poderiam observar ticks diferentes do watcher.
      if (snapshot.degradedReason !== null) {
        return reply.status(200).send(wrapDegraded(snapshot.degradedReason, config.dbPath));
      }

      const filtered = live ? snapshot.sessions.filter((s) => s.live) : snapshot.sessions;
      const sorted = [...filtered].sort((a, b) => b.lastActivityAt.localeCompare(a.lastActivityAt));
      const total = sorted.length;
      const page = sorted.slice(0, limit);

      const data = {
        sessions: page,
        total,
        // '' (mesmo idioma de envelope.ts computeFreshness fallback) quando o
        // watcher ainda nao completou nenhum tick — nunca fabrica um horario
        // de varredura que nao ocorreu. Em operacao normal (watcher primado
        // no bootstrap, index.ts) isto e sempre uma string ISO real.
        scannedAt: snapshot.scannedAt ?? '',
        scrubMode: snapshot.scrubMode,
      };

      return reply.status(200).send(wrap(data, {}, config.dbPath, null));
    });

    // GET /sessions/:sessionId/tail
    scoped.get('/sessions/:sessionId/tail', async (request, reply) => {
      const paramsResult = SessionIdParamSchema.safeParse(request.params);
      const rawSessionId = paramsResult.success ? paramsResult.data.sessionId : '';

      // CHK016 — UUID validado ANTES de qualquer path-join. Formato invalido
      // nunca chega perto de resolveConfinedSessionPath/realpathSync.
      if (!isValidSessionId(rawSessionId)) {
        return reply.status(200).send(wrapDegraded('session-rejected', config.dbPath));
      }
      const sessionId = normalizeSessionId(rawSessionId);

      const root = resolveSessionsRoot();
      if (root === null) {
        return reply.status(200).send(wrapDegraded('sessions-root-missing', config.dbPath));
      }

      // CHK015 — resolucao EXCLUSIVAMENTE via indice do watcher; nunca um
      // path candidato montado direto do parametro do cliente.
      const snapshot = getSessionsIndex();
      const indexed = snapshot.sessions.find((s) => s.sessionId === sessionId);
      if (indexed === undefined) {
        return reply.status(200).send(wrapDegraded('session-not-found', config.dbPath));
      }

      const confinedPath = resolveConfinedSessionPath(root, indexed.projectSlug, sessionId);
      if (confinedPath === null) {
        // Guard de confinamento rejeitou (escape via .. /symlink, ou o
        // arquivo desapareceu entre o tick do watcher e esta requisicao).
        return reply.status(200).send(wrapDegraded('session-rejected', config.dbPath));
      }

      const linesQuery = SessionTailQuerySchema.safeParse(request.query);
      const lines = linesQuery.success ? parseTailLinesParam(linesQuery.data.lines) : undefined;

      let tailResult: SessionTailReadResult | null;
      try {
        tailResult = await readSessionTail(confinedPath, lines !== undefined ? { lines } : {});
      } catch {
        // Defesa em profundidade (Principio II): a cadeia de scrub
        // (`scrubTextBatch`/`scrubTranscriptText`) NUNCA deveria lancar —
        // ambas capturam falha do subprocesso internamente e caem no
        // redactor interno. Se uma excecao inesperada ainda assim escapar,
        // o servidor jamais serve texto cru: degrada.
        return reply.status(200).send(wrapDegraded('session-scrub-failed', config.dbPath));
      }

      if (tailResult === null) {
        // Arquivo confinado deixou de existir/ser legivel entre a resolucao
        // do path e a leitura (race rara) — "nao encontrado" agora.
        return reply.status(200).send(wrapDegraded('session-not-found', config.dbPath));
      }

      const data = {
        sessionId,
        entries: tailResult.entries,
        requestedLines: tailResult.requestedLines,
        returnedLines: tailResult.returnedLines,
        skippedLines: tailResult.skippedLines,
        truncatedByBytes: tailResult.truncatedByBytes,
        windowTruncated: tailResult.windowTruncated,
        // Servido independente de liveness (FR-003) — apenas informativo.
        // Reusa o valor ja calculado pelo watcher (indice), nao recomputado
        // aqui: mesma fonte de verdade que GET /sessions, no maximo um
        // ciclo de watcher (default 5s) desatualizado, aceitavel por ser
        // puramente informativo (nao gateia a resposta).
        live: indexed.live,
        lastActivityAt: tailResult.lastActivityAt,
        // scrubMode do PROPRIO lote de entries desta requisicao
        // (`readSessionTail`), NUNCA o `snapshot.scrubMode` da listagem —
        // sao duas cadeias de scrub independentes sobre lotes diferentes
        // (achado onda-015, mesmo raciocinio que motivou o snapshot atomico
        // do watcher: nunca misturar o resultado de duas operacoes
        // distintas num so campo de resposta).
        scrubMode: tailResult.scrubMode,
      };

      return reply.status(200).send(wrap(data, {}, config.dbPath, null));
    });
  });
}
