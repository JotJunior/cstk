// tools/record_decision.ts — tool `record_decision`: registra Decisao
// auditavel (Principio I).
//
// Delega para [VERIFICADO: global/skills/agente-00c-runtime/scripts/state-decisions.sh
// _sd_cmd_register, linhas 145-269]:
//   state-decisions.sh register --state-dir <SD> --agente A --etapa E
//     --contexto C --opcoes JSON --escolha X --justificativa J
//     [--score N] [--evidencia S] [--referencias JSON] [--artefato-originador S]
//
// Ref: docs/specs/state-mcp-server/contracts/mcp-tools.md §Tool: record_decision
//
// FR-002 no schema: as MESMAS validacoes que o helper aplica em runtime
// [VERIFICADO: state-decisions.sh:184-235] sao replicadas no `inputSchema`
// via `.superRefine()`, para que a rejeicao ocorra ANTES do handler (nenhum
// byte persiste). O helper permanece como segunda barreira (defesa em
// profundidade).

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

/** Teto de stderr reinjetado no contexto do LLM (SEC-M1). */
const MAX_REASON_BYTES = 2048; // 2 KiB

function sanitizeHelperReason(stderr: string): string {
  return sanitizeForLlmContext(stderr, MAX_REASON_BYTES);
}

// As 3 strings canonicas do BloqueioHumano pre-flight de constitution-conflict
// [VERIFICADO: state-decisions.sh:216-235]. Quando as 3 aparecem simultaneamente
// em `options_considered` e `justification_score != 0`, o helper rejeita — a
// mesma regra e imposta AQUI no schema (FR-002).
const CONSTITUTION_CONFLICT_OPTIONS = [
  "atualizar-global-via-bump-SemVer",
  "criar-feature-delta-com-sync-impact-report",
  "abortar-feature-sem-principios-proprios",
] as const;

function isConstitutionConflictOptionSet(options: readonly string[]): boolean {
  return CONSTITUTION_CONFLICT_OPTIONS.every((opt) => options.includes(opt));
}

export const recordDecisionInputShape = {
  session_id: z.string().min(1, "session_id obrigatorio"),
  agent: z.string().min(1, "agent obrigatorio"),
  stage: z.string().min(1, "stage obrigatorio"),
  // min 20 chars [VERIFICADO: state-decisions.sh:184-186].
  context: z.string().min(20, "context deve ter >= 20 chars (Principio I)"),
  options_considered: z
    .array(z.string())
    .min(1, "options_considered precisa de >= 1 item"),
  choice: z.string().min(1, "choice obrigatorio"),
  // min 20 chars [VERIFICADO: state-decisions.sh:187-189].
  rationale: z.string().min(20, "rationale deve ter >= 20 chars (Principio I)"),
  justification_score: z
    .union([z.literal(0), z.literal(1), z.literal(2), z.literal(3)])
    .nullable()
    .optional(),
  // min 20 chars quando presente [VERIFICADO: state-decisions.sh:208-215].
  evidence: z.string().min(20, "evidence deve ter >= 20 chars quando presente").nullable().optional(),
  references: z.array(z.string()).nullable().optional(),
  originating_artifact: z.string().nullable().optional(),
} as const;

// EXPORTADO (nao apenas a `shape`): `server.registerTool` aceita um
// `AnySchema` completo em `inputSchema` (nao so `ZodRawShapeCompat`) —
// [VERIFICADO: node_modules/@modelcontextprotocol/sdk/dist/esm/server/
// zod-compat.d.ts, `normalizeObjectSchema` detecta objeto ja construido].
// Isso e o que permite o `.superRefine()` (FR-002: EVIDENCE_REQUIRED,
// CONSTITUTION_CONFLICT_SCORE) rodar DENTRO da validacao do SDK, antes do
// handler — passar so a `shape` (como `record_skill.ts`/`open_wave.ts`
// fazem, por nao precisarem de regra cross-campo) perderia essas 2 regras
// silenciosamente.
export const recordDecisionInputSchema = z
  .object(recordDecisionInputShape)
  .superRefine((val, ctx) => {
    // EVIDENCE_REQUIRED [VERIFICADO: state-decisions.sh:208-215]: score==3
    // exige evidence >= 20 chars (o `.min(20)` acima ja cobre o tamanho
    // quando presente; aqui cobrimos a AUSENCIA quando score==3).
    if (val.justification_score === 3 && (val.evidence === undefined || val.evidence === null)) {
      ctx.addIssue({
        code: "custom",
        path: ["evidence"],
        message:
          "EVIDENCE_REQUIRED: justification_score == 3 exige evidence (>= 20 chars, comando + fragmento literal do output)",
      });
    }
    // CONSTITUTION_CONFLICT_SCORE [VERIFICADO: state-decisions.sh:216-235].
    if (
      isConstitutionConflictOptionSet(val.options_considered) &&
      val.justification_score !== 0
    ) {
      ctx.addIssue({
        code: "custom",
        path: ["justification_score"],
        message:
          "CONSTITUTION_CONFLICT_SCORE: options_considered contem as 3 strings canonicas de conflito com constitution — justification_score DEVE ser 0 (pause-humano)",
      });
    }
  });

export type RecordDecisionInput = z.infer<typeof recordDecisionInputSchema>;

export type RecordDecisionOutcome = "accepted" | "rejected";
export type RecordDecisionStage = "precondition" | "delegation" | null;

export interface RecordDecisionResponse {
  readonly outcome: RecordDecisionOutcome;
  readonly reason: string | null;
  readonly stage: RecordDecisionStage;
  readonly result: { readonly decision_id: string } | null;
}

export interface RecordDecisionDeps {
  readonly session: ResolvedSession;
  readonly env?: NodeJS.ProcessEnv;
  readonly helperPath?: string;
}

/**
 * Handler da tool `record_decision`. Validacao de forma (SEC contexto,
 * rationale, evidence, constitution-conflict) ja ocorreu no `inputSchema`
 * ANTES desta funcao ser chamada (FR-002 no schema) — o handler so trata
 * pre-condicoes (SESSION_MISMATCH) e delegacao (HELPER_FAILED).
 */
export async function handleRecordDecision(
  input: RecordDecisionInput,
  deps: RecordDecisionDeps,
): Promise<RecordDecisionResponse> {
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
    deps.helperPath ?? join(resolveScriptsDir(env), "state-decisions.sh");

  // Mapper local (tool -> helper): campo ingles -> flag em portugues
  // [VERIFICADO: state-decisions.sh:159-169]. Tabela COMPLETA cross-tool
  // fica centralizada em runtime/exec.ts na task 3.10.
  const args = [
    "register",
    "--state-dir",
    session.stateDir,
    "--agente",
    input.agent,
    "--etapa",
    input.stage,
    "--contexto",
    input.context,
    "--opcoes",
    JSON.stringify(input.options_considered),
    "--escolha",
    input.choice,
    "--justificativa",
    input.rationale,
  ];
  if (input.justification_score !== undefined && input.justification_score !== null) {
    args.push("--score", String(input.justification_score));
  }
  if (input.evidence) {
    args.push("--evidencia", input.evidence);
  }
  args.push("--referencias", JSON.stringify(input.references ?? []));
  if (input.originating_artifact) {
    args.push("--artefato-originador", input.originating_artifact);
  }

  try {
    const { stdout } = await runHelper(helperPath, args);
    const decisionId = stdout.trim();
    if (!decisionId) {
      return {
        outcome: "rejected",
        reason: sanitizeHelperReason(
          "HELPER_FAILED: saida vazia de state-decisions.sh register (esperado dec-NNN)",
        ),
        stage: "delegation",
        result: null,
      };
    }
    return {
      outcome: "accepted",
      reason: null,
      stage: null,
      result: { decision_id: decisionId },
    };
  } catch (err) {
    if (err instanceof HelperExecutionError) {
      const message = err.diagnostic?.message ?? err.stderr;
      const code = classifyHelperError(message);
      return {
        outcome: "rejected",
        reason: sanitizeHelperReason(`${code}: ${message}`),
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

/**
 * Classifica o stderr do helper num `Code` do contrato quando nenhum
 * envelope `DIAG|...` esta disponivel [VERIFICADO: state-decisions.sh nao
 * usa `_diag.sh`/`diag_emit` em nenhuma rejeicao de `register` — todas as
 * mensagens sao texto direto de `_sd_die`]. Defesa em profundidade: com o
 * schema (FR-002) ja bloqueando EVIDENCE_REQUIRED/TEXT_TOO_SHORT/
 * SCORE_OUT_OF_RANGE/CONSTITUTION_CONFLICT_SCORE antes do handler, este
 * caminho so e alcancado se o schema for contornado (bug) ou o helper for
 * chamado fora da tool.
 */
function classifyHelperError(message: string): string {
  if (message.includes("EXIGE --evidencia") || message.includes("--evidencia < 20")) {
    return "EVIDENCE_REQUIRED";
  }
  if (message.includes("contexto < 20 chars") || message.includes("justificativa < 20 chars")) {
    return "TEXT_TOO_SHORT";
  }
  if (message.includes("--score deve ser")) {
    return "SCORE_OUT_OF_RANGE";
  }
  if (message.includes("violacao protocolo constitution-conflict")) {
    return "CONSTITUTION_CONFLICT_SCORE";
  }
  return "HELPER_FAILED";
}
