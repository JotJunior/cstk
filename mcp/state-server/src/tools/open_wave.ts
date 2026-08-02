// tools/open_wave.ts — tool `open_wave`: abre a onda corrente.
//
// Delega para [VERIFICADO: global/skills/agente-00c-runtime/scripts/state-ondas.sh
// _so_cmd_start, linhas 570-619]: `state-ondas.sh start --state-dir <SD>`
// (`start` NAO aceita `--fase`, e NAO E IDEMPOTENTE: cada chamada faz
// append em `.waves[]`).
//
// Ref: docs/specs/state-mcp-server/contracts/mcp-tools.md §Tool: open_wave

import { join } from "node:path";
import { z } from "zod";
import {
  runHelper,
  resolveScriptsDir,
  HelperExecutionError,
  formatToolError,
} from "../runtime/exec.js";
import { sanitizeForLlmContext } from "../runtime/sanitize.js";
import {
  matchesResolvedSession,
  type ResolvedSession,
} from "../session/resolve.js";

const MAX_REASON_BYTES = 2048; // 2 KiB (SEC-M1)

function sanitizeHelperReason(stderr: string): string {
  return sanitizeForLlmContext(stderr, MAX_REASON_BYTES);
}

export const openWaveInputShape = {
  session_id: z.string().min(1, "session_id obrigatorio"),
} as const;

const openWaveInputSchema = z.object(openWaveInputShape);

export type OpenWaveInput = z.infer<typeof openWaveInputSchema>;

export type OpenWaveOutcome = "accepted" | "rejected";
export type OpenWaveStage = "precondition" | "delegation" | null;

export interface OpenWaveResponse {
  readonly outcome: OpenWaveOutcome;
  readonly reason: string | null;
  readonly stage: OpenWaveStage;
  readonly result: { readonly wave_id: string } | null;
}

export interface OpenWaveDeps {
  readonly session: ResolvedSession;
  readonly env?: NodeJS.ProcessEnv;
  readonly helperPath?: string;
  /** Override do path de `state-ondas.sh` (mesmo binario que `helperPath`; testes o injetam separado por clareza). */
  readonly ondasHelperPath?: string;
}

/**
 * Handler da tool `open_wave`. `start` nao e idempotente — por isso a
 * pre-condicao `WAVE_ALREADY_OPEN` MUST ser checada via `wave-status`
 * ANTES de delegar (mesma armadilha que o Loop principal do orquestrador
 * trata hoje no passo 3.bis; a tool a torna fisicamente impossivel).
 */
export async function handleOpenWave(
  input: OpenWaveInput,
  deps: OpenWaveDeps,
): Promise<OpenWaveResponse> {
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

  const helperPath =
    deps.helperPath ?? deps.ondasHelperPath ?? join(resolveScriptsDir(env), "state-ondas.sh");

  try {
    const { stdout: statusOut } = await runHelper(helperPath, [
      "wave-status",
      "--state-dir",
      session.stateDir,
    ]);
    const status = statusOut.trim();
    if (status === "open") {
      return {
        outcome: "rejected",
        reason: formatToolError({
          code: "WAVE_ALREADY_OPEN",
          message:
            "ja existe onda aberta (state-ondas.sh start nao e idempotente — chama-lo agora duplicaria a onda)",
        }),
        stage: "precondition",
        result: null,
      };
    }
  } catch (err) {
    const message =
      err instanceof HelperExecutionError
        ? (err.diagnostic?.message ?? err.stderr)
        : err instanceof Error
          ? err.message
          : String(err);
    return {
      outcome: "rejected",
      reason: sanitizeHelperReason(
        formatToolError({ code: "HELPER_FAILED", message: `wave-status: ${message}` }),
      ),
      stage: "delegation",
      result: null,
    };
  }

  try {
    const { stdout } = await runHelper(helperPath, [
      "start",
      "--state-dir",
      session.stateDir,
    ]);
    const waveId = stdout.trim();
    if (!waveId) {
      return {
        outcome: "rejected",
        reason: sanitizeHelperReason(
          formatToolError({
            code: "HELPER_FAILED",
            message: "saida vazia de state-ondas.sh start (esperado onda-NNN)",
          }),
        ),
        stage: "delegation",
        result: null,
      };
    }
    return {
      outcome: "accepted",
      reason: null,
      stage: null,
      result: { wave_id: waveId },
    };
  } catch (err) {
    if (err instanceof HelperExecutionError) {
      return {
        outcome: "rejected",
        reason: sanitizeHelperReason(
          formatToolError({
            code: "HELPER_FAILED",
            message: err.diagnostic?.message ?? err.stderr,
          }),
        ),
        stage: "delegation",
        result: null,
      };
    }
    return {
      outcome: "rejected",
      reason: sanitizeHelperReason(
        formatToolError({
          code: "HELPER_FAILED",
          message: err instanceof Error ? err.message : String(err),
        }),
      ),
      stage: "delegation",
      result: null,
    };
  }
}
