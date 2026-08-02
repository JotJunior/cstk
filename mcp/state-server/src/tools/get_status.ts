// tools/get_status.ts — tool `get_status`: consulta READ-ONLY do status do
// servidor/execucao (escopo expandido pelo operador via dec-064/block-004,
// task 3.1 — a UNICA "nao-tool" que entrou no MVP).
//
// Delega para [VERIFICADO, leituras puras, nenhuma mutacao]:
//   state-rw.sh get --state-dir <SD> --field '.execution.status'
//   state-rw.sh get --state-dir <SD> --field '.current_stage'
//   state-ondas.sh wave-status --state-dir <SD>
//   state-ondas.sh current-id  --state-dir <SD>
//   bloqueios.sh count --state-dir <SD> --pending-only
//
// Ref: docs/specs/state-mcp-server/contracts/mcp-tools.md §Tool: get_status
//      docs/specs/state-mcp-server/contracts/mcp-tools.md §Nao-tools
//      (nota de correcao: a linha "Consultar status do servidor" foi
//      promovida a tool nesta mesma task — ver dec-064)

import { join } from "node:path";
import { z } from "zod";
import { runHelper, resolveScriptsDir, HelperExecutionError } from "../runtime/exec.js";
import { sanitizeForLlmContext } from "../runtime/sanitize.js";
import {
  matchesResolvedSession,
  type ResolvedSession,
} from "../session/resolve.js";

const MAX_REASON_BYTES = 2048; // 2 KiB (SEC-M1)

function sanitizeHelperReason(stderr: string): string {
  return sanitizeForLlmContext(stderr, MAX_REASON_BYTES);
}

export const getStatusInputShape = {
  session_id: z.string().min(1, "session_id obrigatorio"),
} as const;

const getStatusInputSchema = z.object(getStatusInputShape);

export type GetStatusInput = z.infer<typeof getStatusInputSchema>;

export type GetStatusOutcome = "accepted" | "rejected";
export type GetStatusStage = "precondition" | "delegation" | null;

export interface GetStatusResult {
  readonly execution_status: string;
  readonly current_stage: string;
  readonly wave_status: string;
  readonly current_wave_id: string;
  readonly pending_human_blocks: number;
}

export interface GetStatusResponse {
  readonly outcome: GetStatusOutcome;
  readonly reason: string | null;
  readonly stage: GetStatusStage;
  readonly result: GetStatusResult | null;
}

export interface GetStatusDeps {
  readonly session: ResolvedSession;
  readonly env?: NodeJS.ProcessEnv;
  /** Override do path de `state-rw.sh`. */
  readonly stateRwHelperPath?: string;
  /** Override do path de `state-ondas.sh`. */
  readonly ondasHelperPath?: string;
  /** Override do path de `bloqueios.sh`. */
  readonly bloqueiosHelperPath?: string;
}

/** Le um campo via `state-rw.sh get --field`, devolvendo o stdout limpo (trim). */
async function readField(helperPath: string, stateDir: string, field: string): Promise<string> {
  const { stdout } = await runHelper(helperPath, [
    "get",
    "--state-dir",
    stateDir,
    "--field",
    field,
  ]);
  return stdout.trim();
}

/**
 * Handler da tool `get_status`. Puramente read-only: 5 leituras
 * independentes, nenhuma delas muta o state. Em caso de falha de QUALQUER
 * leitura, a tool rejeita com `HELPER_FAILED` citando qual leitura falhou
 * (nunca inventa um valor para o campo que nao pode ser lido — Principio VI).
 */
export async function handleGetStatus(
  input: GetStatusInput,
  deps: GetStatusDeps,
): Promise<GetStatusResponse> {
  const { session, env = process.env } = deps;

  if (!matchesResolvedSession(session, input.session_id)) {
    return {
      outcome: "rejected",
      reason: "SESSION_MISMATCH: session_id nao corresponde ao token de capacidade desta sessao",
      stage: "precondition",
      result: null,
    };
  }

  const scriptsDir = resolveScriptsDir(env);
  const stateRwHelperPath = deps.stateRwHelperPath ?? join(scriptsDir, "state-rw.sh");
  const ondasHelperPath = deps.ondasHelperPath ?? join(scriptsDir, "state-ondas.sh");
  const bloqueiosHelperPath = deps.bloqueiosHelperPath ?? join(scriptsDir, "bloqueios.sh");

  try {
    const [executionStatus, currentStage, waveStatusOut, currentWaveId, pendingOut] =
      await Promise.all([
        readField(stateRwHelperPath, session.stateDir, ".execution.status"),
        readField(stateRwHelperPath, session.stateDir, ".current_stage"),
        runHelper(ondasHelperPath, ["wave-status", "--state-dir", session.stateDir]).then(
          (r) => r.stdout.trim(),
        ),
        runHelper(ondasHelperPath, ["current-id", "--state-dir", session.stateDir]).then(
          (r) => r.stdout.trim(),
        ),
        runHelper(bloqueiosHelperPath, [
          "count",
          "--state-dir",
          session.stateDir,
          "--pending-only",
        ]).then((r) => r.stdout.trim()),
      ]);

    const pendingHumanBlocks = Number.parseInt(pendingOut, 10);
    if (!Number.isFinite(pendingHumanBlocks) || Number.isNaN(pendingHumanBlocks)) {
      return {
        outcome: "rejected",
        reason: sanitizeHelperReason(
          `HELPER_FAILED: saida inesperada de bloqueios.sh count: '${pendingOut}'`,
        ),
        stage: "delegation",
        result: null,
      };
    }

    return {
      outcome: "accepted",
      reason: null,
      stage: null,
      result: {
        execution_status: executionStatus,
        current_stage: currentStage,
        wave_status: waveStatusOut,
        current_wave_id: currentWaveId,
        pending_human_blocks: pendingHumanBlocks,
      },
    };
  } catch (err) {
    if (err instanceof HelperExecutionError) {
      return {
        outcome: "rejected",
        reason: sanitizeHelperReason(
          `HELPER_FAILED: ${err.diagnostic?.message ?? err.stderr}`,
        ),
        stage: "delegation",
        result: null,
      };
    }
    return {
      outcome: "rejected",
      reason: sanitizeHelperReason(
        `HELPER_FAILED: ${err instanceof Error ? err.message : String(err)}`,
      ),
      stage: "delegation",
      result: null,
    };
  }
}
