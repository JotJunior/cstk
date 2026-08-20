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
  formatToolError,
  type McpToolErrorCode,
} from "../runtime/exec.js";
import { sanitizeForLlmContext } from "../runtime/sanitize.js";
import {
  matchesResolvedSession,
  type ResolvedSession,
} from "../session/resolve.js";
import { BLOCK_ID_PATTERN } from "../runtime/identifiers.js";

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

// Issue #141: o clarify autonomo emite opcoes estruturadas {rotulo, descricao}
// (clarify-asker) e a prosa do orquestrador as passa verbatim — o helper
// shell aceita string nao-vazia OU objeto com rotulo/label nao-vazio
// [VERIFICADO: state-decisions.sh register, validacao de forma de --opcoes].
// Paridade aqui; `label`/`description` sao os aliases EN aceitos pelo report.
const decisionOptionSchema = z.union([
  z.string().min(1, "opcao (string) nao pode ser vazia"),
  z
    .object({
      rotulo: z.string().min(1).optional(),
      label: z.string().min(1).optional(),
      descricao: z.string().optional(),
      description: z.string().optional(),
    })
    .passthrough()
    .refine((o) => Boolean(o.rotulo || o.label), {
      message: "opcao estruturada exige rotulo (ou label) nao-vazio",
    }),
]);
type DecisionOption = z.infer<typeof decisionOptionSchema>;

function isConstitutionConflictOptionSet(options: readonly DecisionOption[]): boolean {
  // So strings participam da deteccao — as 3 opcoes canonicas sao strings por
  // protocolo (orchestrator.md secao 5.b); um objeto nunca casa.
  const asStrings = options.filter((o): o is string => typeof o === "string");
  return CONSTITUTION_CONFLICT_OPTIONS.every((opt) => asStrings.includes(opt));
}

// structural-decision-human-gate FASE 4 (FR-004/FR-002): mesma familia de
// token reconhecida pelo helper [VERIFICADO: state-decisions.sh
// _sd_escolha_is_bloqueio, `pause-humano|bloqueio-humano*`]. R1 avalia essa
// familia contra o ROTULO de cada opcao quando o item e objeto
// (issue #141 — clarify-asker emite {rotulo, descricao}).
function isHumanBlockFamilyToken(token: string): boolean {
  return token === "pause-humano" || token.startsWith("bloqueio-humano");
}

function optionLabel(option: DecisionOption): string | undefined {
  if (typeof option === "string") return option;
  return option.rotulo ?? option.label;
}

function optionsContainHumanBlockToken(options: readonly DecisionOption[]): boolean {
  return options.some((o) => {
    const label = optionLabel(o);
    return typeof label === "string" && isHumanBlockFamilyToken(label);
  });
}

export const recordDecisionInputShape = {
  session_id: z.string().min(1, "session_id obrigatorio"),
  agent: z.string().min(1, "agent obrigatorio"),
  stage: z.string().min(1, "stage obrigatorio"),
  // min 20 chars [VERIFICADO: state-decisions.sh:184-186].
  context: z.string().min(20, "context deve ter >= 20 chars (Principio I)"),
  options_considered: z
    .array(decisionOptionSchema)
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
  // structural-decision-human-gate FASE 4 (FR-004), contracts/mcp-record-decision.md.
  // Enum fechado — "classe-invalida" do helper [VERIFICADO: state-decisions.sh
  // linha 373] e coberta pela propria restricao do zod (valor fora do enum
  // ja e rejeitado pelo tipo, sem precisar de regra custom em superRefine).
  decision_class: z.enum(["estrutural", "operacional"]).nullable().optional(),
  // Forma apenas (INV-M4-adjacente): a membresia no enum real de
  // `references/structural-axis-map.txt` e verificada exclusivamente pelo
  // helper (R3 completo so existe na barreira 2 — duplicar a lista de eixos
  // aqui acoplaria a tool a um arquivo de referencia que pode crescer sem
  // exigir mudanca de schema).
  structural_axis: z.string().min(1, "structural_axis nao pode ser vazio").nullable().optional(),
  // zod valida so o FORMATO (block-NNN) — nunca a autoridade (existencia,
  // execucao, status=respondido). Essa verificacao e feita pelo helper
  // contra o estado (R6, INV-M4).
  human_consent_block_id: z
    .string()
    .regex(BLOCK_ID_PATTERN, "human_consent_block_id deve casar com ^block-[0-9]{3,}$")
    .nullable()
    .optional(),
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

    // structural-decision-human-gate FASE 4 (FR-004) — replica R1/R2/R3 do
    // helper [VERIFICADO: state-decisions.sh:373-395] na barreira 1
    // (superRefine), ANTES de qualquer chamada ao helper. R6 (consentimento)
    // NAO entra aqui — depende de estado que o schema nao le (INV-M4);
    // so `classifyHelperError()` produz HUMAN_CONSENT_INVALID.

    // R1: opcoes com token da familia de bloqueio humano => decision_class
    // obrigatoria [VERIFICADO: state-decisions.sh linha 379,
    // tag [classe-obrigatoria]].
    if (optionsContainHumanBlockToken(val.options_considered) && !val.decision_class) {
      ctx.addIssue({
        code: "custom",
        path: ["decision_class"],
        message:
          "STRUCTURAL_CLASS_REQUIRED: options_considered contem token da familia de bloqueio humano (bloqueio-humano*/pause-humano) — decision_class (estrutural|operacional) e obrigatoria nesse caso",
      });
    }

    if (val.decision_class === "estrutural") {
      // R3 (forma): eixo ausente com classe estrutural [VERIFICADO:
      // state-decisions.sh linha 385, tag [eixo-invalido]]. Membresia no
      // enum real e verificada so pelo helper (comentario do campo acima).
      if (!val.structural_axis) {
        ctx.addIssue({
          code: "custom",
          path: ["structural_axis"],
          message:
            "STRUCTURAL_AXIS_INVALID: decision_class == 'estrutural' exige structural_axis (token do enum de references/structural-axis-map.txt)",
        });
      }

      // R2 (pre-dispatch quando NAO ha consentimento) [VERIFICADO:
      // state-decisions.sh linha 395, tag [estrutural-exige-bloqueio]]:
      // classe estrutural sem --consentimento exige choice da familia de
      // bloqueio humano E score 0.
      if (!val.human_consent_block_id) {
        const choiceIsHumanBlock = isHumanBlockFamilyToken(val.choice);
        if (!choiceIsHumanBlock || val.justification_score !== 0) {
          ctx.addIssue({
            code: "custom",
            path: ["choice"],
            message:
              "STRUCTURAL_REQUIRES_HUMAN_BLOCK: decisao estrutural sem human_consent_block_id valido exige choice da familia de bloqueio humano (bloqueio-humano*/pause-humano) E justification_score 0 — registre o bloqueio via register_human_block, aguarde a resposta do operador e reapresente com human_consent_block_id",
          });
        }
      }
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
      reason: formatToolError({
        code: "SESSION_MISMATCH",
        message: "session_id nao corresponde ao token de capacidade desta sessao",
      }),
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
  // structural-decision-human-gate FASE 4 (FR-004): passthrough condicional
  // — so quando o campo vier definido e nao-nulo, mesmo padrao acima.
  if (input.decision_class) {
    args.push("--classe", input.decision_class);
  }
  if (input.structural_axis) {
    args.push("--eixo", input.structural_axis);
  }
  if (input.human_consent_block_id) {
    args.push("--consentimento", input.human_consent_block_id);
  }

  try {
    const { stdout } = await runHelper(helperPath, args);
    const decisionId = stdout.trim();
    if (!decisionId) {
      return {
        outcome: "rejected",
        reason: sanitizeHelperReason(
          formatToolError({
            code: "HELPER_FAILED",
            message: "saida vazia de state-decisions.sh register (esperado dec-NNN)",
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
      result: { decision_id: decisionId },
    };
  } catch (err) {
    if (err instanceof HelperExecutionError) {
      const message = err.diagnostic?.message ?? err.stderr;
      const code = classifyHelperError(message);
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
function classifyHelperError(message: string): McpToolErrorCode {
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
  // structural-decision-human-gate FASE 4 (FR-004) — casamento pelas tags
  // literais que o helper anexa a cada mensagem R1/R2/R3/R6 [VERIFICADO:
  // state-decisions.sh linhas 373-395]. HUMAN_CONSENT_INVALID cobre os DOIS
  // desfechos de R6 que dependem so de "estado do bloqueio" (ausente/outra
  // execucao/aguardando) — [consentimento-de-outro-assunto] e um terceiro
  // desfecho de R6 (vinculo de assunto), mesmo codigo tipado (INV-M4: a
  // distincao fina fica no texto de `message`, nao no `code`).
  if (message.includes("[classe-obrigatoria]")) {
    return "STRUCTURAL_CLASS_REQUIRED";
  }
  if (message.includes("[estrutural-exige-bloqueio]")) {
    return "STRUCTURAL_REQUIRES_HUMAN_BLOCK";
  }
  if (message.includes("[eixo-invalido]") || message.includes("[classe-invalida]")) {
    return "STRUCTURAL_AXIS_INVALID";
  }
  if (
    message.includes("[consentimento-invalido]") ||
    message.includes("[consentimento-de-outro-assunto]")
  ) {
    return "HUMAN_CONSENT_INVALID";
  }
  return "HELPER_FAILED";
}
