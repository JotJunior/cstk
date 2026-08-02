// tools/register_human_block.ts — tool `register_human_block`: registra
// bloqueio humano.
//
// Delega para [VERIFICADO: global/skills/agente-00c-runtime/scripts/bloqueios.sh
// _bl_cmd_register, linhas 132-211]:
//   bloqueios.sh register --state-dir <SD> --decisao-id --pergunta
//     --contexto-para-resposta [--opcoes-recomendadas]
//
// Ref: docs/specs/state-mcp-server/contracts/mcp-tools.md §Tool: register_human_block
//
// NOTA DE CORRECAO EMPIRICA (Principio VI): o contrato [PROPOSTA] listava
// `question` como "min 1". Leitura do codigo-fonte real [VERIFICADO:
// bloqueios.sh:155-158] mostra que o helper exige `pergunta` com >= 20
// chars ("pergunta muito curta (<20 chars). Humano precisa entender sem
// releitura."), NAO min 1. Este arquivo reflete a regra verificada.

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
import { DECISION_ID_PATTERN } from "../runtime/identifiers.js";

const MAX_REASON_BYTES = 2048; // 2 KiB (SEC-M1)

function sanitizeHelperReason(stderr: string): string {
  return sanitizeForLlmContext(stderr, MAX_REASON_BYTES);
}

export const registerHumanBlockInputShape = {
  session_id: z.string().min(1, "session_id obrigatorio"),
  decision_id: z
    .string()
    .regex(DECISION_ID_PATTERN, "decision_id deve casar com ^dec-[0-9]{1,9}$"),
  // min 20 chars [VERIFICADO: bloqueios.sh:155-158].
  question: z.string().min(20, "question deve ter >= 20 chars (humano precisa entender sem releitura)"),
  context_for_answer: z.string().min(1, "context_for_answer obrigatorio"),
  recommended_options: z.array(z.string()).nullable().optional(),
} as const;

const registerHumanBlockInputSchema = z.object(registerHumanBlockInputShape);

export type RegisterHumanBlockInput = z.infer<typeof registerHumanBlockInputSchema>;

export type RegisterHumanBlockOutcome = "accepted" | "rejected";
export type RegisterHumanBlockStage = "precondition" | "delegation" | null;

export interface RegisterHumanBlockResponse {
  readonly outcome: RegisterHumanBlockOutcome;
  readonly reason: string | null;
  readonly stage: RegisterHumanBlockStage;
  readonly result: {
    readonly block_id: string;
    readonly execution_status: string;
  } | null;
}

export interface RegisterHumanBlockDeps {
  readonly session: ResolvedSession;
  readonly env?: NodeJS.ProcessEnv;
  readonly helperPath?: string;
}

/**
 * Handler da tool `register_human_block`. `execution_status` na resposta
 * e o literal `"aguardando_humano"` — nao lido de volta do state, e sim o
 * EFEITO COLATERAL VERIFICADO do proprio helper [VERIFICADO: bloqueios.sh
 * linha `.execution.status = "aguardando_humano"` no path JSON, e
 * `UPDATE execution SET status='aguardando_humano'` na MESMA transacao do
 * INSERT no path sqlite — ambos garantem o efeito sempre que o register
 * aceita, nunca uma leitura separada que poderia divergir].
 */
export async function handleRegisterHumanBlock(
  input: RegisterHumanBlockInput,
  deps: RegisterHumanBlockDeps,
): Promise<RegisterHumanBlockResponse> {
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
    deps.helperPath ?? join(resolveScriptsDir(env), "bloqueios.sh");

  const args = [
    "register",
    "--state-dir",
    session.stateDir,
    "--decisao-id",
    input.decision_id,
    "--pergunta",
    input.question,
    "--contexto-para-resposta",
    input.context_for_answer,
  ];
  if (input.recommended_options) {
    args.push("--opcoes-recomendadas", JSON.stringify(input.recommended_options));
  }

  try {
    const { stdout } = await runHelper(helperPath, args);
    const blockId = stdout.trim();
    if (!blockId) {
      return {
        outcome: "rejected",
        reason: sanitizeHelperReason(
          formatToolError({
            code: "HELPER_FAILED",
            message: "saida vazia de bloqueios.sh register (esperado block-NNN)",
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
      result: { block_id: blockId, execution_status: "aguardando_humano" },
    };
  } catch (err) {
    if (err instanceof HelperExecutionError) {
      const message = err.diagnostic?.message ?? err.stderr;
      // DECISION_NOT_FOUND [VERIFICADO: bloqueios.sh:183 (path json) e
      // _bloqueios-db.sh:159-161 (path sqlite, mapeando FOREIGN KEY
      // constraint failed para a MESMA mensagem) — nenhum envelope DIAG,
      // deteccao por substring].
      const code = message.includes("decisao_id nao existe")
        ? "DECISION_NOT_FOUND"
        : "HELPER_FAILED";
      return {
        outcome: "rejected",
        reason: sanitizeHelperReason(formatToolError({ code, message })),
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
