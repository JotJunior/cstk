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
