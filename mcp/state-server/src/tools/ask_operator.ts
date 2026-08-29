// tools/ask_operator.ts — tool `ask_operator`: pergunta BLOQUEANTE ao
// operador, cuja resposta vem do painel (`cstk-panel`), superficie 1 da
// human-bridge. 9a `registerTool` de `index.ts` (hoje 8).
//
// Delega para `bridge/client.ts` (unico arquivo que fala HTTP com o
// painel) + a primitiva GENERICA `state-rw.sh set --field
// '.operator_answers' --value <json-array>` (persistencia, task 2.4 —
// SEM script POSIX novo).
//
// Ref: docs/specs/human-bridge/contracts/mcp-tool-ask-operator.md
//      docs/specs/human-bridge/contracts/panel-bridge-api.md
//      docs/specs/human-bridge/data-model.md §Entity: OperatorAnswer
// Tasks: 2.2, 2.4

import { basename, join } from "node:path";
import { z } from "zod";
import {
  runHelper,
  resolveScriptsDir,
  formatToolError,
} from "../runtime/exec.js";
import { sanitizeForLlmContext } from "../runtime/sanitize.js";
import {
  matchesResolvedSession,
  type ResolvedSession,
} from "../session/resolve.js";
import {
  createBridgeClient,
  resolvePanelUrl,
  validatePanelUrl,
  BRIDGE_POLL_INTERVAL_MS,
  type BridgeClient,
  type PollInterventionOutcome,
} from "../bridge/client.js";
import {
  parseAskTimeoutMs,
  resolveClientTimeoutMs,
} from "./ask-operator-clock.js";
import { appendAskOperatorRecord } from "../audit/log.js";

const MAX_REASON_BYTES = 2048; // 2 KiB (SEC-M1)

function sanitizeHelperReason(stderr: string): string {
  return sanitizeForLlmContext(stderr, MAX_REASON_BYTES);
}

export const askOperatorInputShape = {
  session_id: z.string().min(1, "session_id obrigatorio"),
  question: z.string().min(1, "question obrigatorio"),
  kind: z.enum(["choice", "confirm", "text"]),
  // so em kind="choice" (contrato §2) — cardinalidade validada em superRefine.
  options: z.array(z.string().min(1)).nullable().optional(),
  // C-4: obrigatorio — sem ele a tool vira trava.
  default_value: z.string().min(1, "default_value obrigatorio (C-4)"),
  // Validado contra a faixa DERIVADA (R-CLOCK-4) em runtime, nunca no schema
  // (a faixa depende de CSTK_CLIENT_TOOL_TIMEOUT_MS, que so o handler conhece).
  timeout_ms: z.number().nullable().optional(),
} as const;

// EXPORTADO (nao so a `shape`) pelo MESMO motivo de record_decision.ts: o
// `.superRefine()` (options exigido/proibido conforme `kind`) precisa rodar
// DENTRO da validacao do SDK, antes do handler.
export const askOperatorInputSchema = z
  .object(askOperatorInputShape)
  .superRefine((val, ctx) => {
    if (val.kind === "choice") {
      if (!val.options || val.options.length === 0) {
        ctx.addIssue({
          code: "custom",
          path: ["options"],
          message: "options obrigatorio (>= 1 item) quando kind='choice' (contrato §2)",
        });
      }
    } else if (val.options !== undefined && val.options !== null && val.options.length > 0) {
      ctx.addIssue({
        code: "custom",
        path: ["options"],
        message: "options so e permitido quando kind='choice' (contrato §2)",
      });
    }
  });

export type AskOperatorInput = z.infer<typeof askOperatorInputSchema>;

export type AskOperatorOutcome = "accepted" | "rejected";
export type AskOperatorStage = "precondition" | "delegation" | null;

/** `absent` NAO existe nesta superficie (contrato §5) — diferenca deliberada face a `collect_optins`. */
export type AskOperatorResultOutcome = "answered" | "declined" | "timeout" | "unavailable" | "failed";

export interface AskOperatorResult {
  /** Sempre "panel" nesta superficie (invariante C-5). */
  readonly channel: "panel";
  readonly outcome: AskOperatorResultOutcome;
  readonly applied_value: string;
  readonly question_id: string;
  /** So preenchido em `kind:"text"` + `outcome:"answered"` (R-TEXT-1). */
  readonly untrusted_text: string | null;
}

export interface AskOperatorResponse {
  readonly outcome: AskOperatorOutcome;
  readonly reason: string | null;
  readonly stage: AskOperatorStage;
  readonly result: AskOperatorResult | null;
}

export interface AskOperatorDeps {
  readonly session: ResolvedSession;
  readonly env?: NodeJS.ProcessEnv;
  /** Override do path de `state-rw.sh` (testes). */
  readonly stateRwHelperPath?: string;
  /** Override do cliente HTTP da Ponte (testes; producao usa `createBridgeClient`). */
  readonly bridgeClient?: BridgeClient;
  /** Override de `CSTK_PANEL_URL` ja resolvida (testes). */
  readonly panelUrl?: string;
  /** Override de `client_timeout_ms` ja resolvido no BOOT (R-CLOCK-5) — evita re-ler env por chamada. */
  readonly clientTimeoutMs?: number;
  /** Override da cadencia de polling (testes — evita esperar 1500ms de verdade). */
  readonly pollIntervalMs?: number;
  /** Relogio injetavel (testes deterministicos). */
  readonly now?: () => number;
  /** `setTimeout` injetavel (testes deterministicos, sem esperar de verdade). */
  readonly sleep?: (ms: number) => Promise<void>;
}

/** Lancada quando o teto do SERVIDOR (`MCP_ASK_TIMEOUT_MS`) estoura ANTES do painel responder (R-CLOCK-3). */
export class AskOperatorServerTimeoutError extends Error {}

/**
 * Loop de polling ate o painel resolver a intervencao OU o teto do
 * SERVIDOR estourar (R-CLOCK-3: o servidor desiste ANTES do cliente,
 * lancando esta excecao — capturada por `handleAskOperator`, NUNCA deixada
 * escapar ate o SDK, para preservar C-1/C-4).
 */
export async function pollUntilResolved(
  client: BridgeClient,
  questionId: string,
  mcpAskTimeoutMs: number,
  pollIntervalMs: number,
  now: () => number,
  sleep: (ms: number) => Promise<void>,
): Promise<Exclude<PollInterventionOutcome, { kind: "open" }>> {
  const deadline = now() + mcpAskTimeoutMs;
  for (;;) {
    const polled = await client.pollIntervention(questionId);
    if (polled.kind !== "open") return polled;
    if (now() >= deadline) {
      throw new AskOperatorServerTimeoutError(
        `MCP_ASK_TIMEOUT_MS (${mcpAskTimeoutMs}ms) excedido aguardando resposta do operador (question_id=${questionId})`,
      );
    }
    await sleep(pollIntervalMs);
  }
}

/**
 * Persiste UMA entrada em `.operator_answers[]` (task 2.4): le
 * `.operator_answers // []` via `state-rw.sh get`, concatena, reescreve
 * via `state-rw.sh set` — a MESMA primitiva generica ja usada por
 * `.suggestions` (nenhum script POSIX novo, nenhuma dependencia nova,
 * Principio II segue PASS).
 *
 * Best-effort (nunca lanca): falha de leitura/escrita do state e logada em
 * 1 linha de stderr, mas NUNCA transforma a resposta do operador (ja
 * resolvida) em rejeicao de tool — mesmo racional de `audit/log.ts`
 * (degradacao de trilha nao pode reverter uma decisao real ja tomada).
 */
export async function persistOperatorAnswer(
  stateRwHelperPath: string,
  stateDir: string,
  entry: Readonly<Record<string, unknown>>,
): Promise<void> {
  try {
    const { stdout } = await runHelper(stateRwHelperPath, [
      "get",
      "--state-dir",
      stateDir,
      "--field",
      ".operator_answers // []",
    ]);
    const current: unknown = JSON.parse(stdout);
    const currentArray = Array.isArray(current) ? current : [];
    const next = [...currentArray, entry];
    await runHelper(stateRwHelperPath, [
      "set",
      "--state-dir",
      stateDir,
      "--field",
      ".operator_answers",
      "--value",
      JSON.stringify(next),
    ]);
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    process.stderr.write(
      `ask_operator: falha ao persistir .operator_answers[] (best-effort, resposta do operador preservada): ${sanitizeHelperReason(message)}\n`,
    );
  }
}

/** Handler da tool `ask_operator`. */
export async function handleAskOperator(
  input: AskOperatorInput,
  deps: AskOperatorDeps,
): Promise<AskOperatorResponse> {
  const { session, env = process.env } = deps;

  if (!matchesResolvedSession(session, input.session_id)) {
    return {
      outcome: "rejected",
      reason: formatToolError({
        code: "SESSION_MISMATCH",
        message: "session_id nao corresponde ao token de capacidade desta sessao",
      }),
      stage: "precondition",
      result: null,
    };
  }

  const clientTimeoutMs =
    deps.clientTimeoutMs ?? resolveClientTimeoutMs(env.CSTK_CLIENT_TOOL_TIMEOUT_MS).clientTimeoutMs;
  const effectiveTimeoutMs = parseAskTimeoutMs(clientTimeoutMs, input.timeout_ms ?? undefined);
  const pollIntervalMs = deps.pollIntervalMs ?? BRIDGE_POLL_INTERVAL_MS;
  const now = deps.now ?? (() => Date.now());
  const sleep = deps.sleep ?? ((ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms)));

  const panelUrl = deps.panelUrl ?? resolvePanelUrl(env);
  const validation = validatePanelUrl(panelUrl, env);
  const client = deps.bridgeClient ?? createBridgeClient(panelUrl, { env });

  let outcome: AskOperatorResultOutcome;
  let appliedValue: string;
  let untrustedText: string | null = null;
  let questionId: string;
  let auditReason: string | null = null;

  if (!validation.ok) {
    questionId = client.generateLocalQuestionId();
    outcome = "failed";
    appliedValue = input.default_value;
    auditReason = validation.reason ?? "CSTK_PANEL_URL invalida";
    process.stderr.write(`ask_operator: ${sanitizeHelperReason(auditReason)}\n`);
  } else {
    try {
      const created = await client.createIntervention({
        projectPath: session.targetProjectPath,
        project: basename(session.targetProjectPath || "") || "?",
        // "-" e o placeholder de ausencia emitido por mcp-session.sh para
        // agente-00c [VERIFICADO: cli/lib/mcp.sh:566, mesmo precedente de
        // collect_optins.ts:274-281] — vira `null` no payload HTTP (contrato §4).
        shortName: session.shortName && session.shortName !== "-" ? session.shortName : null,
        executionKind: session.executionKind,
        kind: input.kind,
        question: input.question,
        options: input.kind === "choice" ? (input.options ?? null) : null,
        defaultValue: input.default_value,
        timeoutMs: effectiveTimeoutMs,
      });

      if (created.kind !== "created") {
        // Nenhum questionId real existe ainda (a criacao nunca chegou a
        // persistir no painel) — correlator LOCAL so para a linha de
        // `.operator_answers[]` (campo NOT NULL), nunca devolvido como se
        // fosse conhecido pelo painel.
        questionId = client.generateLocalQuestionId();
        appliedValue = input.default_value;
        auditReason = created.detail;
        outcome = created.kind; // "unavailable" | "failed"
        if (created.kind === "failed") {
          process.stderr.write(`ask_operator: ${sanitizeHelperReason(created.detail)}\n`);
        }
      } else {
        questionId = created.questionId;
        try {
          const polled = await pollUntilResolved(
            client,
            questionId,
            effectiveTimeoutMs,
            pollIntervalMs,
            now,
            sleep,
          );
          switch (polled.kind) {
            case "answered":
              outcome = "answered";
              appliedValue = polled.appliedValue;
              untrustedText = polled.untrustedText;
              break;
            case "declined":
              outcome = "declined";
              appliedValue = input.default_value;
              break;
            case "expired":
              outcome = "timeout";
              appliedValue = input.default_value;
              break;
            case "not_found":
              // Contrato §5: o painel respondeu, so nao conhece o id -> `failed`, NUNCA `unavailable`.
              outcome = "failed";
              appliedValue = input.default_value;
              auditReason = `questionId desconhecido pelo painel (404): ${questionId}`;
              process.stderr.write(`ask_operator: ${sanitizeHelperReason(auditReason)}\n`);
              break;
            case "failed":
              outcome = "failed";
              appliedValue = input.default_value;
              auditReason = polled.detail;
              process.stderr.write(`ask_operator: ${sanitizeHelperReason(polled.detail)}\n`);
              break;
          }
        } catch (err) {
          appliedValue = input.default_value;
          if (err instanceof AskOperatorServerTimeoutError) {
            outcome = "timeout";
            auditReason = err.message;
          } else {
            outcome = "failed";
            auditReason = err instanceof Error ? err.message : String(err);
            process.stderr.write(`ask_operator: ${sanitizeHelperReason(auditReason)}\n`);
          }
        }
      }
    } catch (err) {
      questionId = client.generateLocalQuestionId();
      outcome = "failed";
      appliedValue = input.default_value;
      auditReason = err instanceof Error ? err.message : String(err);
      process.stderr.write(`ask_operator: ${sanitizeHelperReason(auditReason)}\n`);
    }
  }

  // R-TEXT-1: untrusted_text so existe no envelope em kind="text".
  const untrustedTextOut = input.kind === "text" ? untrustedText : null;
  const recordedAt = new Date().toISOString();

  // C-4: gravar ANTES do retorno, em TODO desfecho (inclusive answered).
  const scriptsDir = resolveScriptsDir(env);
  const stateRwHelperPath = deps.stateRwHelperPath ?? join(scriptsDir, "state-rw.sh");
  await persistOperatorAnswer(stateRwHelperPath, session.stateDir, {
    question_id: questionId,
    channel: "panel",
    outcome,
    applied_value: appliedValue,
    recorded_at: recordedAt,
    reason: auditReason,
    untrusted_text: untrustedTextOut,
    effective_timeout_ms: effectiveTimeoutMs,
  });

  // Trilha de auditoria best-effort (task 2.3) — nunca lanca, nunca bloqueia o retorno.
  await appendAskOperatorRecord({
    sessionId: session.token,
    questionId,
    channel: "panel",
    outcome,
    appliedValue,
    effectiveTimeoutMs,
    reason: auditReason,
  });

  // C-1 (herdada, intacta): nenhum desfecho e erro de tool.
  return {
    outcome: "accepted",
    reason: null,
    stage: null,
    result: {
      channel: "panel",
      outcome,
      applied_value: appliedValue,
      question_id: questionId,
      untrusted_text: untrustedTextOut,
    },
  };
}
