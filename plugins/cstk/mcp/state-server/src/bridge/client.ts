// bridge/client.ts — UNICO arquivo do servidor MCP que fala HTTP com o
// painel (`cstk-panel`). Fronteira human-bridge, superficie 1
// (`ask_operator`).
//
// Convencao de case (panel-bridge-api.md §2): payload HTTP e SEMPRE
// camelCase; o restante do servidor MCP (envelope da tool, `.operator_answers[]`)
// e snake_case. Este arquivo e o UNICO ponto que faz essa conversao
// explicitamente — sem ORM, sem auto-mapping.
//
// Ref: docs/specs/human-bridge/contracts/panel-bridge-api.md §4/§5/§11.5
//      docs/specs/human-bridge/research.md Decision 4/5/6
// Tasks: 2.1.1 - 2.1.5

import { randomUUID } from "node:crypto";

/**
 * Timeout da chamada de CRIACAO (`POST /interventions`) — dobra como
 * detector de indisponibilidade (FR-021, contrato §4). Curto de proposito:
 * e uma chamada loopback; 5s ja e ordens de grandeza acima do normal.
 */
export const BRIDGE_CREATE_TIMEOUT_MS = 5000;

/**
 * Cadencia de polling (`GET /interventions/:questionId`). Fixo, sem
 * backoff/jitter na v1 (FR-019, research.md Decision 5).
 */
export const BRIDGE_POLL_INTERVAL_MS = 1500;

/**
 * Base URL default do painel (research.md Decision 4) — 5173 e a porta que
 * o operador de fato ve (`cstk serve` exporta `PORT` antes de subir o
 * painel); 3001 e so o fallback interno do processo Node quando ninguem
 * exporta `PORT` (nao ocorre no caminho suportado).
 */
export const DEFAULT_PANEL_URL = "http://127.0.0.1:5173";

/** Hosts aceitos SEM a variavel de opt-in (contrato §11.5). */
const LOOPBACK_HOSTS: ReadonlySet<string> = new Set(["127.0.0.1", "::1", "[::1]", "localhost"]);

/**
 * Variavel de opt-in explicito para permitir `CSTK_PANEL_URL` apontar para
 * um host fora de loopback (contrato §11.5). Ausente/vazia/qualquer valor
 * != "1" -> opt-in NAO concedido (allowlist positiva, nao blocklist).
 */
const NONLOOPBACK_OPTIN_ENV = "CSTK_PANEL_ALLOW_NONLOOPBACK";

export interface PanelUrlValidation {
  readonly ok: boolean;
  readonly reason?: string;
}

/**
 * Guard de `CSTK_PANEL_URL` fora de loopback (task 2.1.4, contrato §11.5):
 * - host loopback (`127.0.0.1`/`::1`/`localhost`) -> sempre OK, qualquer protocolo.
 * - host NAO-loopback + protocolo `http:` -> MUST NOT ser aceito EM NENHUMA
 *   HIPOTESE, mesmo com o opt-in setado.
 * - host NAO-loopback + protocolo `https:` + opt-in setado -> OK.
 * - host NAO-loopback sem opt-in -> recusado.
 */
export function validatePanelUrl(
  rawUrl: string,
  env: NodeJS.ProcessEnv = process.env,
): PanelUrlValidation {
  let parsed: URL;
  try {
    parsed = new URL(rawUrl);
  } catch {
    return { ok: false, reason: `CSTK_PANEL_URL invalida (nao e uma URL): '${rawUrl}'` };
  }

  if (LOOPBACK_HOSTS.has(parsed.hostname)) {
    return { ok: true };
  }

  if (parsed.protocol === "http:") {
    return {
      ok: false,
      reason:
        `CSTK_PANEL_URL='${rawUrl}' aponta para host nao-loopback ('${parsed.hostname}') ` +
        `via http:// — MUST NOT ser aceito em nenhuma hipotese (contrato §11.5).`,
    };
  }

  const optIn = env[NONLOOPBACK_OPTIN_ENV];
  if (optIn === "1") {
    return { ok: true };
  }

  return {
    ok: false,
    reason:
      `CSTK_PANEL_URL='${rawUrl}' aponta para host nao-loopback ('${parsed.hostname}') sem ` +
      `${NONLOOPBACK_OPTIN_ENV}=1 (contrato §11.5). Perguntas carregam contexto da execucao — ` +
      `um valor errado (typo/copy-paste) enviaria isso em claro para um host remoto.`,
  };
}

/** Resolve `CSTK_PANEL_URL` do ambiente, com o default de research.md Decision 4. */
export function resolvePanelUrl(env: NodeJS.ProcessEnv = process.env): string {
  const raw = env.CSTK_PANEL_URL;
  return raw && raw.trim() !== "" ? raw.trim() : DEFAULT_PANEL_URL;
}

// ---------------------------------------------------------------------------
// Mapper camelCase (HTTP) <-> snake_case (envelope MCP/state) — task 2.1.3.
// UNICO lugar do servidor MCP que faz essa conversao (Convencoes de Borda).
// ---------------------------------------------------------------------------

export interface CreateInterventionRequest {
  readonly projectPath: string;
  readonly project: string;
  readonly shortName: string | null;
  readonly executionKind: string;
  readonly kind: "choice" | "confirm" | "text";
  readonly question: string;
  readonly options: readonly string[] | null;
  readonly defaultValue: string;
  /** Janela EFETIVA, ja resolvida pelo servidor MCP (R-CLOCK-4/R-CLOCK-7) — nunca o valor cru pedido pelo agente. */
  readonly timeoutMs: number;
}

/** Corpo HTTP camelCase de `POST /api/v1/bridge/interventions` (contrato §4). */
function toCreateInterventionBody(req: CreateInterventionRequest): Record<string, unknown> {
  return {
    projectPath: req.projectPath,
    project: req.project,
    shortName: req.shortName,
    executionKind: req.executionKind,
    kind: req.kind,
    question: req.question,
    options: req.options,
    defaultValue: req.defaultValue,
    timeoutMs: req.timeoutMs,
  };
}

export type CreateInterventionOutcome =
  | { readonly kind: "created"; readonly questionId: string; readonly expiresAt: string }
  /** FR-021 + contrato §3.1: falha de rede, timeout, 5xx OU `200+meta.degraded=true` — todos equivalentes. */
  | { readonly kind: "unavailable"; readonly detail: string }
  /** Resposta inesperada (shape invalida, 4xx nao previsto) — nao e indisponibilidade, e bug/config. */
  | { readonly kind: "failed"; readonly detail: string };

export type PollInterventionOutcome =
  | {
      readonly kind: "answered";
      readonly appliedValue: string;
      readonly untrustedText: string | null;
    }
  | { readonly kind: "declined" }
  | { readonly kind: "expired" }
  | { readonly kind: "open" }
  /** `404` — o painel respondeu, so nao conhece o id (contrato §5: mapeia para `failed`, NUNCA `unavailable`). */
  | { readonly kind: "not_found" }
  | { readonly kind: "failed"; readonly detail: string };

export interface BridgeClientDeps {
  readonly fetchImpl?: typeof fetch;
  readonly env?: NodeJS.ProcessEnv;
  /** Gerador do correlator local usado quando a criacao falha/degrada antes de qualquer questionId real existir. */
  readonly generateLocalId?: () => string;
}

export interface BridgeClient {
  createIntervention(req: CreateInterventionRequest): Promise<CreateInterventionOutcome>;
  pollIntervention(questionId: string): Promise<PollInterventionOutcome>;
  /** Correlator local (nunca do painel) para persistencia quando a criacao nunca gerou um questionId real. */
  generateLocalQuestionId(): string;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

/**
 * Constroi o cliente HTTP da Ponte. `baseUrl` MUST ja ter passado por
 * `validatePanelUrl` — este construtor nao repete a validacao (a
 * responsabilidade de recusar e do chamador, `tools/ask_operator.ts`,
 * antes mesmo de construir o cliente).
 */
export function createBridgeClient(baseUrl: string, deps: BridgeClientDeps = {}): BridgeClient {
  const fetchImpl = deps.fetchImpl ?? fetch;
  const generateLocalId = deps.generateLocalId ?? (() => randomUUID());
  const base = baseUrl.endsWith("/") ? baseUrl.slice(0, -1) : baseUrl;

  return {
    generateLocalQuestionId: generateLocalId,

    async createIntervention(req: CreateInterventionRequest): Promise<CreateInterventionOutcome> {
      let response: Response;
      try {
        response = await fetchImpl(`${base}/api/v1/bridge/interventions`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(toCreateInterventionBody(req)),
          signal: AbortSignal.timeout(BRIDGE_CREATE_TIMEOUT_MS),
        });
      } catch (err) {
        // Falha de rede/timeout (AbortError incluido) — FR-021: por si so, `unavailable`.
        return {
          kind: "unavailable",
          detail: err instanceof Error ? err.message : String(err),
        };
      }

      let parsed: unknown;
      try {
        parsed = await response.json();
      } catch (err) {
        return {
          kind: "failed",
          detail: `resposta de criacao com corpo nao-JSON (status ${response.status}): ${
            err instanceof Error ? err.message : String(err)
          }`,
        };
      }

      if (response.status >= 500) {
        return { kind: "unavailable", detail: `criacao respondeu ${response.status}` };
      }

      if (!isRecord(parsed)) {
        return { kind: "failed", detail: "resposta de criacao com shape inesperado (nao-objeto)" };
      }

      const meta = isRecord(parsed.meta) ? parsed.meta : {};
      // Contrato §3.1: 200 + meta.degraded=true (bridge.db indisponivel) e
      // EQUIVALENTE a falha de conexao para fins de outcome — mesmo com
      // status 200 (nao 5xx).
      if (meta.degraded === true) {
        const reason = typeof meta.reason === "string" ? meta.reason : "bridge_unavailable";
        return { kind: "unavailable", detail: `criacao degradada: ${reason}` };
      }

      if (response.status !== 201) {
        return {
          kind: "failed",
          detail: `criacao respondeu ${response.status} inesperado (nao-degradado, nao-5xx)`,
        };
      }

      const data = isRecord(parsed.data) ? parsed.data : null;
      const questionId = data && typeof data.questionId === "string" ? data.questionId : null;
      const expiresAt = data && typeof data.expiresAt === "string" ? data.expiresAt : null;
      if (!questionId || !expiresAt) {
        return { kind: "failed", detail: "resposta 201 sem data.questionId/data.expiresAt" };
      }

      return { kind: "created", questionId, expiresAt };
    },

    async pollIntervention(questionId: string): Promise<PollInterventionOutcome> {
      let response: Response;
      try {
        response = await fetchImpl(
          `${base}/api/v1/bridge/interventions/${encodeURIComponent(questionId)}`,
          { method: "GET", signal: AbortSignal.timeout(BRIDGE_CREATE_TIMEOUT_MS) },
        );
      } catch (err) {
        return { kind: "failed", detail: err instanceof Error ? err.message : String(err) };
      }

      if (response.status === 404) {
        // Contrato §5: o painel respondeu, so nao conhece o id -> `failed`, NUNCA `unavailable`.
        return { kind: "not_found" };
      }

      let parsed: unknown;
      try {
        parsed = await response.json();
      } catch (err) {
        return {
          kind: "failed",
          detail: `resposta de polling com corpo nao-JSON (status ${response.status}): ${
            err instanceof Error ? err.message : String(err)
          }`,
        };
      }

      if (!isRecord(parsed)) {
        return { kind: "failed", detail: "resposta de polling com shape inesperado (nao-objeto)" };
      }

      const data = isRecord(parsed.data) ? parsed.data : null;
      const state = data && typeof data.state === "string" ? data.state : null;
      if (!state) {
        return { kind: "failed", detail: "resposta de polling sem data.state" };
      }

      switch (state) {
        case "open":
          return { kind: "open" };
        case "declined":
          return { kind: "declined" };
        case "expired":
          return { kind: "expired" };
        case "answered": {
          const appliedValue =
            data && typeof data.appliedValue === "string" ? data.appliedValue : null;
          if (!appliedValue) {
            return { kind: "failed", detail: "state=answered sem data.appliedValue" };
          }
          const untrustedText =
            data && typeof data.untrustedText === "string" ? data.untrustedText : null;
          return { kind: "answered", appliedValue, untrustedText };
        }
        default:
          return { kind: "failed", detail: `data.state desconhecido: '${state}'` };
      }
    },
  };
}
