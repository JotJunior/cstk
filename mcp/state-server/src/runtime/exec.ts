// runtime/exec.ts — mapper layer (tool <-> helper POSIX).
//
// SEC-H1 (HIGH, gate owasp-security): a fronteira Node -> POSIX MUST invocar
// o helper por `execFile`/`spawn` com array de argv e `shell: false`. E
// PROIBIDO `exec()`, `execSync()`, `spawn(..., { shell: true })`, template
// string montando linha de comando, e qualquer forma de `eval`. Campos de
// texto livre (evidence, rationale, question, ...) chegam de um LLM que pode
// ter lido conteudo hostil (LLM01/ASI01/A05 Injection) — o array de argv
// elimina a classe inteira de command injection porque o valor nunca e
// interpretado por um shell.
//
// Ref: docs/specs/state-mcp-server/contracts/mcp-tools.md
//   §Controles de seguranca da fronteira Node -> POSIX (SEC-H1)
//      docs/specs/state-mcp-server/plan.md §Seguranca (SEC-H1)

import { execFile } from "node:child_process";

/** Teto de stdout/stderr por chamada de helper (defesa contra output descontrolado). */
const MAX_BUFFER_BYTES = 4 * 1024 * 1024; // 4 MiB

export interface HelperResult {
  readonly stdout: string;
  readonly stderr: string;
}

/**
 * Uma linha `DIAG|<severity>|<code>|<message>|<fix>` emitida pelos helpers
 * via `_diag.sh::diag_emit` (envelope diagnostico uniforme dos scripts
 * POSIX do runtime) [VERIFICADO:
 * global/skills/agente-00c-runtime/scripts/_diag.sh].
 */
export interface DiagnosticEnvelope {
  readonly severity: "error" | "warning";
  readonly code: string;
  readonly message: string;
  readonly fix: string;
}

export class HelperExecutionError extends Error {
  /** Codigo de saida do processo, quando conhecido (null se o proprio spawn falhou, ex.: ENOENT). */
  readonly exitCode: number | null;
  /** stderr bruto do helper (NAO truncado/scrubbed aqui — cabe ao chamador aplicar SEC-M1). */
  readonly stderr: string;
  /** Primeira linha `DIAG|...` reconhecida no stderr, se houver. */
  readonly diagnostic: DiagnosticEnvelope | null;

  constructor(
    message: string,
    exitCode: number | null,
    stderr: string,
    diagnostic: DiagnosticEnvelope | null,
  ) {
    super(message);
    this.name = "HelperExecutionError";
    this.exitCode = exitCode;
    this.stderr = stderr;
    this.diagnostic = diagnostic;
  }
}

/**
 * Extrai o primeiro envelope `DIAG|severity|code|message|fix` reconhecido no
 * stderr de um helper. Retorna `null` se nenhuma linha casar o formato
 * (helpers legados sem `_diag.sh`, ou falha antes de qualquer diag_emit).
 */
export function parseDiagnosticEnvelope(
  stderr: string,
): DiagnosticEnvelope | null {
  for (const line of stderr.split("\n")) {
    if (!line.startsWith("DIAG|")) continue;
    const parts = line.split("|");
    // DIAG|severity|code|message|fix -> 5 campos (message/fix podem
    // conter texto livre, mas diag_emit ja substitui `|` interno por `/`
    // antes de emitir, entao split("|") nunca produz mais de 5 campos).
    if (parts.length !== 5) continue;
    const [, severityRaw, code, message, fix] = parts;
    if (severityRaw !== "error" && severityRaw !== "warning") continue;
    if (code === undefined || message === undefined || fix === undefined) continue;
    return { severity: severityRaw, code, message, fix };
  }
  return null;
}

export interface RunHelperOptions {
  /**
   * Texto a escrever no stdin do helper antes de fechar o pipe (ex.:
   * `secrets-filter.sh scrub`, que le o payload a filtrar via stdin —
   * audit/log.ts). Quando omitido, o comportamento e identico ao anterior
   * (nenhuma escrita/fechamento explicito de stdin), preservando os
   * chamadores existentes (record_skill.ts, session/resolve.ts).
   */
  readonly stdin?: string;
}

/**
 * Invoca um helper POSIX por argv puro. `args` MUST ser um array literal —
 * nunca uma string interpolada. Rejeita a Promise em qualquer saida !== 0.
 */
export function runHelper(
  helperPath: string,
  args: readonly string[],
  options: RunHelperOptions = {},
): Promise<HelperResult> {
  return new Promise((resolve, reject) => {
    const child = execFile(
      helperPath,
      // Copia defensiva: garante um array literal na fronteira do child_process,
      // nunca uma string montada por concatenacao (SEC-H1).
      [...args],
      { shell: false, maxBuffer: MAX_BUFFER_BYTES, encoding: "utf8" },
      (error, stdout, stderr) => {
        if (error) {
          const exitCode =
            typeof error.code === "number" ? error.code : null;
          reject(
            new HelperExecutionError(
              `runHelper: ${helperPath} ${args.join(" ")} falhou: ${error.message}`,
              exitCode,
              stderr,
              parseDiagnosticEnvelope(stderr),
            ),
          );
          return;
        }
        resolve({ stdout, stderr });
      },
    );
    if (options.stdin !== undefined) {
      // EPIPE e possivel se o helper sair antes de consumir o stdin (ex.:
      // erro precoce de flags) — nao e um erro do CHAMADOR, o callback do
      // execFile acima ja captura o exit code/stderr real.
      child.stdin?.on("error", () => undefined);
      child.stdin?.end(options.stdin, "utf8");
    }
  });
}

/**
 * Diretorio onde os helpers POSIX do runtime estao disponiveis dentro do
 * container (bind-mount **read-only** — contracts/mcp-session-lifecycle.md
 * §Montagens). Fora do container (testes locais), sobrescrever via
 * `CSTK_MCP_SCRIPTS_DIR`.
 */
const DEFAULT_SCRIPTS_DIR = "/opt/cstk/scripts";

export function resolveScriptsDir(env: NodeJS.ProcessEnv = process.env): string {
  const override = env.CSTK_MCP_SCRIPTS_DIR;
  return override && override.length > 0 ? override : DEFAULT_SCRIPTS_DIR;
}

// ---------------------------------------------------------------------------
// Tipo de erro comum entre tools (task 3.10.4)
// ---------------------------------------------------------------------------
//
// Uniao FECHADA de todos os codigos de erro ja especificados em
// contracts/mcp-tools.md §Errors para as tools implementadas ate esta onda
// (record_skill, record_decision, open_wave, record_task,
// register_human_block, get_status, close_wave). `SESSION_MISMATCH` e
// `HELPER_FAILED` sao os 2 codigos genericos compartilhados por TODA tool
// (precondicao comum / fallback de delegacao); os demais sao especificos de
// uma tool cada. Formato serializado SEMPRE `${code}: ${message}` — decidido
// em dec-059 (criterio de "motivo acionavel", FR-009) e dec-064 (task 3.2:
// reason = stderr do helper scrubbed, nao so o codigo).

export type McpToolErrorCode =
  | "SESSION_MISMATCH"
  | "HELPER_FAILED"
  | "NO_OPEN_WAVE"
  | "WAVE_ALREADY_OPEN"
  | "WAVE_ID_NOT_FOUND"
  | "TESTS_PASSED_EXCEEDS_RUN"
  | "DECISION_NOT_FOUND"
  | "EVIDENCE_REQUIRED"
  | "TEXT_TOO_SHORT"
  | "SCORE_OUT_OF_RANGE"
  | "CONSTITUTION_CONFLICT_SCORE"
  | "INVALID_TERMINATION_REASON"
  | "INVALID_STAGE_TOKEN"
  | "CLOSE_ROLLED_BACK";

/**
 * Erro tipado comum reutilizado por todas as tools (`code` enumerado +
 * `message` de texto livre, ja escrubado pelo chamador via
 * `sanitizeForLlmContext` quando `message` vem de stderr — este modulo nao
 * aplica scrub, apenas formata). Substitui a concatenacao ad-hoc
 * `` `${code}: ${message}` `` que cada tool repetia inline antes da task
 * 3.10; o formato serializado permanece IDENTICO (dec-059/dec-064), entao
 * nenhum teste existente de string exata quebra com esta consolidacao.
 */
export interface McpToolError {
  readonly code: McpToolErrorCode;
  readonly message: string;
}

/** Serializa um `McpToolError` para o formato `reason` do contrato (dec-059). */
export function formatToolError(error: McpToolError): string {
  return `${error.code}: ${error.message}`;
}

// ---------------------------------------------------------------------------
// Tabela de mapeamento campo-ingles -> flag-portugues (task 3.10.1/3.10.3)
// ---------------------------------------------------------------------------
//
// Tabela EXPLICITA (nao ha mapeamento automatico por convencao — plan.md
// §Convencoes de Borda "Mapper layer (tool <-> helper)"). Cada tool ainda
// constroi seu proprio `args` (a logica condicional de "so anexa a flag
// quando o campo esta presente" permanece local a cada tool.ts, ja testada
// individualmente por tool — 82/82 `node:test` verdes antes desta task);
// esta tabela e o registro AUDITAVEL, cross-tool, verificado por teste de
// paridade (`test/exec-mapper-parity.test.ts`, task 3.10.3) contra o
// `inputSchema` real de cada tool, prevenindo o risco documentado em
// plan.md: "campo aceito pelo schema mas nunca repassado ao helper — falha
// em silencio" (task 3.10.2).
//
// `flag: null` marca um campo do schema que a TOOL consome para
// precondicao/validacao (ex.: `session_id` para `SESSION_MISMATCH`,
// `wave_id` de `record_task` tambem validado via `WAVE_ID_NOT_FOUND` antes
// de virar `--wave-id`) e portanto NAO tem flag 1:1 direta — presente na
// tabela mesmo assim, para que a paridade fique completa (todo campo do
// schema aparece exatamente uma vez por tool).

export interface FieldFlagMapping {
  /** Nome da tool (arquivo `tools/<nome>.ts`). */
  readonly tool: string;
  /** Campo em ingles do `inputSchema` da tool. */
  readonly field: string;
  /** Flag em portugues do helper POSIX, ou `null` se o campo nao vira flag (consumido so pela tool). */
  readonly flag: string | null;
}

export const FIELD_TO_FLAG_TABLE: readonly FieldFlagMapping[] = [
  // record_skill -> state-ondas.sh record-skill (task 2.2)
  { tool: "record_skill", field: "session_id", flag: null },
  { tool: "record_skill", field: "skill", flag: "--skill" },
  { tool: "record_skill", field: "decision_id", flag: "--decisao-id" },
  { tool: "record_skill", field: "kind", flag: "--kind" },

  // record_decision -> state-decisions.sh register (task 3.6)
  { tool: "record_decision", field: "session_id", flag: null },
  { tool: "record_decision", field: "agent", flag: "--agente" },
  { tool: "record_decision", field: "stage", flag: "--etapa" },
  { tool: "record_decision", field: "context", flag: "--contexto" },
  { tool: "record_decision", field: "options_considered", flag: "--opcoes" },
  { tool: "record_decision", field: "choice", flag: "--escolha" },
  { tool: "record_decision", field: "rationale", flag: "--justificativa" },
  { tool: "record_decision", field: "justification_score", flag: "--score" },
  { tool: "record_decision", field: "evidence", flag: "--evidencia" },
  { tool: "record_decision", field: "references", flag: "--referencias" },
  { tool: "record_decision", field: "originating_artifact", flag: "--artefato-originador" },

  // open_wave -> state-ondas.sh start (task 3.7)
  { tool: "open_wave", field: "session_id", flag: null },

  // record_task -> state-ondas.sh record-task (task 3.8)
  { tool: "record_task", field: "session_id", flag: null },
  { tool: "record_task", field: "task_id", flag: "--task-id" },
  { tool: "record_task", field: "outcome", flag: "--outcome" },
  { tool: "record_task", field: "title", flag: "--titulo" },
  { tool: "record_task", field: "wave_id", flag: "--wave-id" },
  { tool: "record_task", field: "tests_run", flag: "--testes-rodados" },
  { tool: "record_task", field: "tests_passed", flag: "--testes-passados" },
  { tool: "record_task", field: "lint_ok", flag: "--lint-ok" },
  { tool: "record_task", field: "touched_files", flag: "--arquivos" },
  { tool: "record_task", field: "source", flag: "--origem" },
  { tool: "record_task", field: "if_absent", flag: "--if-absent" },

  // register_human_block -> bloqueios.sh register (task 3.9)
  { tool: "register_human_block", field: "session_id", flag: null },
  { tool: "register_human_block", field: "decision_id", flag: "--decisao-id" },
  { tool: "register_human_block", field: "question", flag: "--pergunta" },
  { tool: "register_human_block", field: "context_for_answer", flag: "--contexto-para-resposta" },
  { tool: "register_human_block", field: "recommended_options", flag: "--opcoes-recomendadas" },

  // get_status -> read-only, nenhum campo alem de session_id (task 3.11)
  { tool: "get_status", field: "session_id", flag: null },

  // close_wave -> state-ondas.sh end (task 4.1)
  { tool: "close_wave", field: "session_id", flag: null },
  { tool: "close_wave", field: "termination_reason", flag: "--motivo-termino" },
  { tool: "close_wave", field: "executed_stages", flag: "--add-etapa" },
  { tool: "close_wave", field: "next_scheduled_for", flag: "--proxima-agendada-para" },
  { tool: "close_wave", field: "next_instruction", flag: "--next-instruction" },
] as const;

/**
 * Path do `enforcement-log.jsonl` visto de DENTRO do container. SEC-H2
 * (contracts/mcp-session-lifecycle.md §Montagens): bind-mount do **arquivo**
 * `<projeto-alvo>/.claude/enforcement-log.jsonl` -> `/data/enforcement-log.jsonl`
 * — nunca do diretorio `.claude` inteiro (montar o diretorio daria ao
 * container escrita sobre `hooks/pretooluse-bash-guard.sh`/`settings.json`).
 * A montagem real do container e task 5.2 (F5, ainda nao implementada nesta
 * onda); esta funcao apenas prepara a interface de resolucao do path,
 * testavel isoladamente via `CSTK_MCP_ENFORCEMENT_LOG_PATH`.
 */
const DEFAULT_ENFORCEMENT_LOG_PATH = "/data/enforcement-log.jsonl";

export function resolveEnforcementLogPath(
  env: NodeJS.ProcessEnv = process.env,
): string {
  const override = env.CSTK_MCP_ENFORCEMENT_LOG_PATH;
  return override && override.length > 0 ? override : DEFAULT_ENFORCEMENT_LOG_PATH;
}
