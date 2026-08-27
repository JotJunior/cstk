/**
 * Watcher de descoberta de sessoes do Claude Code (FASE 4, FR-011).
 *
 * Instancia NOVA e INDEPENDENTE do `ingest-watcher.ts` — reusa apenas o
 * PADRAO (polling via `setInterval`, timer `.unref()`'d, factory
 * `start*(opts): Handle`, degradacao silenciosa nunca lanca), nunca a
 * instancia. Decisao ja tomada pelo operador (dec-013/block-003): as raizes
 * observadas (state-dirs de execucao vs `~/.claude/projects`), os ciclos de
 * vida e os modos de falha divergem — compartilhar instancia acoplaria a
 * ingestao da `knowledge.db` (funcao central do painel) a uma falha na
 * descoberta de sessoes, e vice-versa. Os dois MUST degradar em separado.
 *
 * Mantem um indice em memoria (`sessionId -> metadados`, exposto como
 * `SessionSummaryDTO[]` via `getSessionsIndex()`) para que:
 *   - `GET /api/v1/sessions` responda a partir do cache, sem varrer o disco
 *     a cada requisicao (research.md Decision 7, SC-001);
 *   - `GET /api/v1/sessions/:sessionId/tail` resolva `sessionId` por este
 *     indice, NUNCA por path reconstruido a partir do parametro do cliente
 *     (contracts/sessions-api.md "Resolucao de sessionId via indice do
 *     watcher" — o achado de seguranca MEDIUM que a FASE 4 fecha).
 *
 * Sem subprocesso (nota de simplificacao, research.md Decision 7): apenas
 * `readdirSync`/`statSync` via `scanSessions()` — o padrao do
 * `ingest-watcher` e herdado, a complexidade de subprocesso/timeout/cache de
 * binario, nao.
 *
 * Ref: contracts/sessions-api.md "Contrato do watcher (interno, nao HTTP)";
 * research.md Decision 7; tasks.md FASE 4 (4.1); plan.md §Project Structure.
 */
import type { SessionSummaryDTO } from '@cstk-panel/shared-types';
import { scanSessions, type SessionScanReason, type SessionScanResult } from '../lib/session-scan.js';
import type { ScrubMode } from '../lib/secret-scrub.js';

/**
 * Cadencia do timer (task 4.1.2). Sem subprocesso envolvido (ao contrario do
 * `ingest-watcher`), o custo por tick e apenas `readdirSync`/`statSync` sobre
 * a raiz de sessoes — 5s (mesmo default do `ingest-watcher`) mantem paridade
 * de comportamento sem introduzir polling mais agressivo do que o necessario
 * (o auto-refresh do cliente, via `refetchInterval` do react-query, e o
 * mecanismo de atualizacao do lado do front — este timer nao o duplica).
 */
export const DEFAULT_SESSIONS_WATCH_INTERVAL_MS = 5_000;

// ---------------------------------------------------------------------------
// Indice em memoria (task 4.1.1) — NUNCA persistido (Principio I)
// ---------------------------------------------------------------------------

interface SessionsIndexState {
  /** Ultimo conjunto de sessoes obtido com sucesso (ja escrubado por scanSessions). */
  sessions: SessionSummaryDTO[];
  /** true quando o ultimo tick terminou degradado (raiz ausente/ilegivel/erro inesperado). */
  degraded: boolean;
  /** motivo tipado da ultima degradacao; null quando o ultimo tick teve sucesso. */
  reason: SessionScanReason | null;
  /** ISO 8601 do instante do ultimo ciclo do watcher que alimentou o indice; null antes do 1o tick. */
  scannedAt: string | null;
  /** Qual cadeia de scrub produziu `sessions` no ultimo tick bem-sucedido
   *  (contracts/sessions-api.md `scrubMode`). `'internal'` antes do 1o tick
   *  ou apos degradacao — leitura conservadora, nunca superestima cobertura
   *  nao confirmada (Principio III/VI). */
  scrubMode: ScrubMode;
}

let indexState: SessionsIndexState = {
  sessions: [],
  degraded: false,
  reason: null,
  scannedAt: null,
  scrubMode: 'internal',
};

/**
 * Snapshot atomico e coerente do indice em memoria, lido pelas rotas (task
 * 4.1.1, contrato; achado onda-015 do ponto em aberto de `GET
 * /api/v1/sessions`). Devolve UM objeto imutavel — nunca getters separados
 * por campo — porque a rota precisa de `sessions` + `scannedAt` +
 * `scrubMode` que sejam TODOS do mesmo tick: com getters separados, um tick
 * do watcher poderia cair entre duas leituras da rota e produzir uma
 * resposta que mistura `sessions` de um ciclo com `scannedAt` de outro —
 * uma mentira sutil de frescor que o Principio III existe para impedir. Uma
 * unica leitura de `indexState` (sincrona, sem I/O) elimina essa janela.
 *
 * Um tick degradado (raiz ausente/ilegivel/erro inesperado) zera `sessions`
 * para `[]` em vez de servir dado potencialmente obsoleto/invalidado —
 * coerente com o contrato de `GET /api/v1/sessions`, que responde
 * totalmente degradado (`data: null`) quando a raiz nao esta disponivel,
 * nunca uma lista stale apresentada como fresca.
 */
export interface SessionsIndexSnapshot {
  sessions: SessionSummaryDTO[];
  scannedAt: string | null;
  degradedReason: SessionScanReason | null;
  scrubMode: ScrubMode;
}

export function getSessionsIndex(): SessionsIndexSnapshot {
  return {
    sessions: indexState.sessions,
    scannedAt: indexState.scannedAt,
    degradedReason: indexState.reason,
    scrubMode: indexState.scrubMode,
  };
}

/** Helper de teste, espelhando `resetWatcherCacheForTests` do ingest-watcher. */
export function resetSessionsIndexForTests(): void {
  indexState = { sessions: [], degraded: false, reason: null, scannedAt: null, scrubMode: 'internal' };
}

// ---------------------------------------------------------------------------
// Tick (task 4.1.1, 4.1.3)
// ---------------------------------------------------------------------------

export interface SessionsWatcherTickOptions {
  /** Injetavel para testes deterministicos — nunca varre o disco real na suite. */
  scanImpl?: () => Promise<SessionScanResult>;
  /** Injetavel para testes deterministicos de `scannedAt`. */
  now?: () => number;
}

export interface SessionsWatcherTickResult {
  degraded: boolean;
  reason: SessionScanReason | null;
  sessionCount: number;
  scannedAt: string;
}

/**
 * Executa UM tick do watcher. Nunca lanca (task 4.1.3, Principio II):
 * diretorio raiz ausente/ilegivel vira indice vazio + `DegradedReason`
 * tipado; qualquer erro inesperado do `scanImpl` (defesa em profundidade —
 * `scanSessions()` ja e contratualmente nao-lancante) e capturado aqui e
 * tambem degrada o indice em vez de propagar a excecao.
 */
export async function runSessionsWatcherTick(
  opts: SessionsWatcherTickOptions = {}
): Promise<SessionsWatcherTickResult> {
  const scanImpl = opts.scanImpl ?? scanSessions;
  const nowFn = opts.now ?? Date.now;
  const scannedAt = new Date(nowFn()).toISOString();

  try {
    const result = await scanImpl();
    if (result.degraded) {
      indexState = { sessions: [], degraded: true, reason: result.reason, scannedAt, scrubMode: 'internal' };
      return { degraded: true, reason: result.reason, sessionCount: 0, scannedAt };
    }
    indexState = { sessions: result.sessions, degraded: false, reason: null, scannedAt, scrubMode: result.scrubMode };
    return { degraded: false, reason: null, sessionCount: result.sessions.length, scannedAt };
  } catch {
    // Defesa em profundidade (4.1.3): mesmo que `scanImpl` viole seu proprio
    // contrato de nunca lancar, um tick deste watcher NUNCA derruba o
    // processo do servidor. Sem `DegradedReason` especifico disponivel aqui
    // (a excecao escapou da propria camada que os tipa) — `reason: null`
    // sinaliza degradacao sem inventar um motivo que nao foi observado.
    indexState = { sessions: [], degraded: true, reason: null, scannedAt, scrubMode: 'internal' };
    return { degraded: true, reason: null, sessionCount: 0, scannedAt };
  }
}

// ---------------------------------------------------------------------------
// Ciclo de vida do timer (task 4.1.2)
// ---------------------------------------------------------------------------

export interface SessionsWatcherHandle {
  stop: () => void;
}

export interface StartSessionsWatcherOptions extends SessionsWatcherTickOptions {
  intervalMs?: number;
  /** logger minimo — evita acoplar o modulo ao tipo concreto do Fastify logger */
  onTickError?: (err: unknown) => void;
}

/**
 * Inicia o timer recorrente. Retorna handle com `stop()` para shutdown
 * limpo. Instancia completamente independente do `ingest-watcher` — nenhum
 * estado, timer ou cache e compartilhado entre os dois (FR-011).
 */
export function startSessionsWatcher(opts: StartSessionsWatcherOptions = {}): SessionsWatcherHandle {
  const interval = opts.intervalMs ?? DEFAULT_SESSIONS_WATCH_INTERVAL_MS;
  const timer = setInterval(() => {
    runSessionsWatcherTick(opts).catch(err => {
      opts.onTickError?.(err);
    });
  }, interval);
  // unref: o timer deste watcher NUNCA deve, por si so, impedir o processo
  // de encerrar (mesma justificativa do ingest-watcher — testes/scripts que
  // sobem o server e finalizam sem shutdown explicito). O shutdown normal
  // do processo long-running continua coberto por
  // `server.addHook('onClose', stop)` (wiring em index.ts, FASE 5).
  timer.unref();
  return {
    stop: () => clearInterval(timer),
  };
}
