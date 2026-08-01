// tools/record_skill.ts — tool `record_skill`: registra invocacao de
// skill/gate na onda corrente.
//
// Delega para [VERIFICADO: global/skills/agente-00c-runtime/scripts/state-ondas.sh
// _so_cmd_record_skill / _so_db_record_skill]:
//   state-ondas.sh record-skill --state-dir <SD> --skill NAME
//     [--decisao-id ID] [--kind skill|gate]
//
// Ref: docs/specs/state-mcp-server/contracts/mcp-tools.md §Tool: record_skill
//
// NOTA DE CORRECAO EMPIRICA (Principio VI — nao inventar dados): o contrato
// [PROPOSTA] em mcp-tools.md descreve `result.wave_id` como campo de
// resposta. Leitura do codigo-fonte real [VERIFICADO:
// state-ondas.sh:889-954 (`_so_cmd_record_skill`) e
// _state-ondas-db.sh:311-342 (`_so_db_record_skill`)] mostra que AMBOS os
// backends (json e sqlite) imprimem em stdout a CONTAGEM de
// `skills_invoked`/`skill_invocation` da onda apos o insert (idempotente),
// nao um `wave_id`. Este arquivo reflete o comportamento verificado
// (`result.skills_invoked_count`); o contrato sera corrigido no mesmo commit
// (task 2.2 desta onda).

import { z } from "zod";
import { join } from "node:path";
import {
  runHelper,
  resolveScriptsDir,
  HelperExecutionError,
} from "../runtime/exec.js";
import { sanitizeForLlmContext } from "../runtime/sanitize.js";
import {
  matchesResolvedSession,
  type ResolvedSession,
} from "../session/resolve.js";

// SEC-M2: allowlist de identificador, NUNCA texto livre. Regex verificada
// contra a MESMA regra aplicada pelo helper a tokens de etapa
// [VERIFICADO: state-ondas.sh:228-235 `_so_is_stage_token`,
// `^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$`] — mais estrita que a tabela
// [PROPOSTA] de mcp-tools.md (`^[A-Za-z0-9._-]{1,64}$`, que permitiria um
// primeiro caractere `-` e violaria a "Regra transversal: nenhum campo de
// identificador pode comecar com -" do mesmo documento). Usamos a regra
// verificada: primeiro caractere obrigatoriamente alfanumerico.
const IDENTIFIER_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/;

// `^dec-[0-9]{1,9}$` [VERIFICADO: contracts/mcp-tools.md, formato de id
// emitido por state-decisions.sh register — mesmo formato usado nesta
// propria execucao, ex.: dec-049].
const DECISION_ID_PATTERN = /^dec-[0-9]{1,9}$/;

export const recordSkillInputShape = {
  session_id: z.string().min(1, "session_id obrigatorio"),
  skill: z
    .string()
    .regex(IDENTIFIER_PATTERN, "skill deve casar com ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$"),
  decision_id: z
    .string()
    .regex(DECISION_ID_PATTERN, "decision_id deve casar com ^dec-[0-9]{1,9}$")
    .nullable()
    .optional(),
  kind: z.enum(["skill", "gate"]).nullable().optional(),
} as const;

const recordSkillInputSchema = z.object(recordSkillInputShape);

export type RecordSkillInput = z.infer<typeof recordSkillInputSchema>;

export type RecordSkillOutcome = "accepted" | "rejected";
export type RecordSkillStage = "precondition" | "delegation" | null;

export interface RecordSkillResponse {
  readonly outcome: RecordSkillOutcome;
  readonly reason: string | null;
  readonly stage: RecordSkillStage;
  readonly result: { readonly skills_invoked_count: number } | null;
}

/** Teto de stderr reinjetado no contexto do LLM (SEC-M1). */
const MAX_REASON_BYTES = 2048; // 2 KiB

/**
 * SEC-M1: stderr do helper e DADO potencialmente influenciado por um
 * atacante (LLM05) — remove caracteres de controle e limita a 2 KiB antes
 * de devolver ao chamador. Implementacao compartilhada em
 * `runtime/sanitize.ts` (task 2.3, extraida daqui para reuso por
 * `audit/log.ts` e futuras tools de F3).
 */
function sanitizeHelperReason(stderr: string): string {
  return sanitizeForLlmContext(stderr, MAX_REASON_BYTES);
}


export interface RecordSkillDeps {
  readonly session: ResolvedSession;
  readonly env?: NodeJS.ProcessEnv;
  readonly helperPath?: string;
}

/**
 * Handler da tool `record_skill`. Validacao de forma (SEC-M2, allowlist de
 * `skill`/`decision_id`, enum fechado de `kind`) ja ocorreu no `inputSchema`
 * ANTES desta funcao ser chamada (FR-002 no schema) — o handler so trata
 * pre-condicoes (SESSION_MISMATCH) e delegacao (HELPER_FAILED/NO_OPEN_WAVE).
 */
export async function handleRecordSkill(
  input: RecordSkillInput,
  deps: RecordSkillDeps,
): Promise<RecordSkillResponse> {
  const { session, env = process.env } = deps;

  if (!matchesResolvedSession(session, input.session_id)) {
    return {
      outcome: "rejected",
      reason: "SESSION_MISMATCH: session_id nao corresponde ao token de capacidade desta sessao",
      stage: "precondition",
      result: null,
    };
  }

  const helperPath =
    deps.helperPath ?? join(resolveScriptsDir(env), "state-ondas.sh");

  // Mapper local (tool -> helper): campo ingles -> flag em portugues.
  // A tabela COMPLETA cross-tool fica centralizada em runtime/exec.ts na
  // task 3.10 (F3) — aqui e a "versao inicial" prevista pela task 2.2.4.
  const args = [
    "record-skill",
    "--state-dir",
    session.stateDir,
    "--skill",
    input.skill,
  ];
  if (input.decision_id) {
    args.push("--decisao-id", input.decision_id);
  }
  if (input.kind) {
    args.push("--kind", input.kind);
  }

  try {
    const { stdout } = await runHelper(helperPath, args);
    const count = Number.parseInt(stdout.trim(), 10);
    if (!Number.isFinite(count) || Number.isNaN(count)) {
      return {
        outcome: "rejected",
        reason: sanitizeHelperReason(
          `HELPER_FAILED: saida inesperada de state-ondas.sh record-skill: '${stdout.trim()}'`,
        ),
        stage: "delegation",
        result: null,
      };
    }
    return {
      outcome: "accepted",
      reason: null,
      stage: null,
      result: { skills_invoked_count: count },
    };
  } catch (err) {
    if (err instanceof HelperExecutionError) {
      const code = err.diagnostic?.code === "no-open-wave" ? "NO_OPEN_WAVE" : "HELPER_FAILED";
      return {
        outcome: "rejected",
        reason: sanitizeHelperReason(`${code}: ${err.diagnostic?.message ?? err.stderr}`),
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
