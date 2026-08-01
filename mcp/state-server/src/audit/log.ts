// audit/log.ts — enforcement-log.jsonl (scrub -> truncate -> serialize),
// task 2.3. Escreve o "Tool Invocation Audit Record" (FR-005/FR-006) no
// MESMO arquivo ja usado pelas guardas existentes
// (`<projeto-alvo>/.claude/enforcement-log.jsonl`), discriminado por um
// `source` proprio (`"mcp-state-tool"`) — nao um arquivo novo (Decision 6,
// research.md).
//
// Ref: docs/specs/state-mcp-server/data-model.md
//   §Entity: Tool Invocation Audit Record [PROPOSAL]
//   §Regra de sanitizacao (scrub -> truncate, ordem obrigatoria)
//      docs/specs/state-mcp-server/contracts/mcp-tools.md
//   §SEC-M1 (teto/strip do texto livre) §SEC-M3 (serializador real, nunca
//   printf/concatenacao — previne log injection / A09 forjar entradas)
//      docs/specs/_archived/2026-07-28-enforced-guards/contracts/enforcement-log.md
//   (contrato original do arquivo, multi-writer por `source`)
//      global/skills/agente-00c-runtime/hooks/pretooluse-bash-guard.sh:111-171
//   (precedente VERIFICADO: `_pbg_scrub_text` + `_pbg_write_log` — MESMA
//   ordem scrub -> cut, MESMO principio de "falha de escrita nunca aborta")
//
// Auto-atestacao (task 2.1/2.3.6, CHK057, dec-053): o operador ACEITOU
// formalmente que esta linha e escrita pelo MESMO processo que executa a
// mutacao (limite conhecido, sem testemunha externa) — coerente com o
// modelo de ameaca do container (plan.md §Seguranca: "container confiavel
// por construcao, adversario = conteudo lido pelo LLM"). Nenhum requisito
// adicional de rastreabilidade foi introduzido por essa decisao; este
// modulo nao implementa (nem simula) um watcher externo.

import { appendFile, mkdir } from "node:fs/promises";
import { dirname, join } from "node:path";
import { runHelper, resolveScriptsDir, resolveEnforcementLogPath } from "../runtime/exec.js";
import { truncateUtf8ByteBudget, truncateCodePoints, stripControlChars } from "../runtime/sanitize.js";

export type ToolInvocationOutcome = "accepted" | "rejected";
export type ToolInvocationStage = "schema" | "precondition" | "delegation" | null;

export interface ToolInvocationAuditInput {
  /** Nome da tool chamada (ex.: `record_skill`). */
  readonly tool: string;
  /** Sessao/execucao de origem (o token de capacidade — FR-005). */
  readonly sessionId: string;
  readonly outcome: ToolInvocationOutcome;
  /** `"agente-00c"` ou `"feature-00c:<short-name>"` — nomenclatura herdada do hook. */
  readonly detectedExecution: string | null;
  readonly detectedExecutionPath: string | null;
  /** Motivo acionavel; NOT NULL quando `outcome === "rejected"` (FR-009), mas o tipo aceita null para refletir o caso `accepted`. */
  readonly reason: string | null;
  readonly stage: ToolInvocationStage;
  /** Argumentos brutos recebidos pela tool (pre-scrub/truncate — ver `arguments_digest`). */
  readonly arguments: Readonly<Record<string, unknown>>;
}

export interface AppendAuditRecordDeps {
  /** Override do path do arquivo de log (testes; producao usa `resolveEnforcementLogPath`). */
  readonly logPath?: string;
  /** Override do path do helper `secrets-filter.sh` (testes). */
  readonly scrubHelperPath?: string;
  readonly env?: NodeJS.ProcessEnv;
  /** Relogio injetavel (testes deterministicos). */
  readonly now?: () => Date;
}

/** `cut -c1-500` do precedente `pretooluse-bash-guard.sh` — 500 CODE POINTS, nao bytes. */
const ARGUMENTS_DIGEST_MAX_CODE_POINTS = 500;

/** SEC-M1: mesmo teto aplicado ao `reason` devolvido ao contexto do LLM (record_skill.ts). */
const REASON_MAX_BYTES = 2048; // 2 KiB

function isoTimestamp(now: () => Date = () => new Date()): string {
  // toISOString() ja produz o formato `YYYY-MM-DDTHH:mm:ss.sssZ`; o
  // precedente (`date -u +%Y-%m-%dT%H:%M:%SZ`) nao carrega milissegundos —
  // removemos para bater exatamente com o formato dos outros writers.
  return now().toISOString().replace(/\.\d{3}Z$/, "Z");
}

/**
 * Aplica `secrets-filter.sh scrub` (via stdin) ao texto informado.
 * Fail-closed no espirito do precedente `_pbg_scrub_text`: qualquer falha
 * (helper ausente, exit != 0, timeout) devolve um placeholder seguro em
 * vez do texto cru sem filtro — nunca deixa um segredo potencial vazar
 * por causa de uma falha do proprio filtro.
 */
export async function scrubText(
  text: string,
  deps: Pick<AppendAuditRecordDeps, "scrubHelperPath" | "env"> = {},
): Promise<string> {
  const helperPath =
    deps.scrubHelperPath ?? join(resolveScriptsDir(deps.env), "secrets-filter.sh");
  try {
    const { stdout } = await runHelper(helperPath, ["scrub"], { stdin: text });
    return stdout;
  } catch {
    return "[secrets-filter indisponivel ou falhou - conteudo omitido por seguranca]";
  }
}

/**
 * Monta e persiste UMA linha JSONL em `enforcement-log.jsonl`. Best-effort:
 * falha ao ESCREVER a linha (fs indisponivel, mount ausente) NUNCA lanca —
 * mesmo espirito do precedente `_pbg_write_log` ("falha de escrita nunca
 * aborta o hook"). A mutacao de estado que este registro documenta ja
 * aconteceu (ou foi rejeitada) independentemente de conseguirmos persistir
 * o rastro; bloquear a resposta da tool por causa disso seria pior que o
 * gap de auditoria em si. Retorna `true` se a linha foi persistida.
 *
 * Ordem OBRIGATORIA (SEC-M3, task 2.3.2): scrub -> truncate -> serialize.
 * `reason` e `arguments_digest` sao os unicos campos de texto livre (podem
 * carregar segredo influenciado por conteudo lido pelo LLM — LLM05); os
 * demais (`source`, `timestamp`, `outcome`, `tool`, `stage`) sao
 * vocabulario fechado e NAO passam por scrub/truncate.
 */
export async function appendAuditRecord(
  input: ToolInvocationAuditInput,
  deps: AppendAuditRecordDeps = {},
): Promise<boolean> {
  try {
    const scrubbedReason =
      input.reason !== null
        ? truncateUtf8ByteBudget(
            stripControlChars(await scrubText(input.reason, deps)).trim(),
            REASON_MAX_BYTES,
          )
        : null;

    const rawDigest = JSON.stringify(input.arguments ?? {});
    const scrubbedDigest = await scrubText(rawDigest, deps);
    const argumentsDigest = truncateCodePoints(
      scrubbedDigest,
      ARGUMENTS_DIGEST_MAX_CODE_POINTS,
    );

    // Serialize (SEC-M3): JSON.stringify real, nunca printf/concatenacao —
    // um `"` ou `\n` em texto livre nao pode quebrar a linha nem forjar
    // um segundo registro.
    const line = JSON.stringify({
      source: "mcp-state-tool",
      timestamp: isoTimestamp(deps.now),
      outcome: input.outcome,
      tool: input.tool,
      session_id: input.sessionId,
      detected_execution: input.detectedExecution,
      detected_execution_path: input.detectedExecutionPath,
      reason: scrubbedReason,
      stage: input.stage,
      arguments_digest: argumentsDigest,
    });

    const logPath = deps.logPath ?? resolveEnforcementLogPath(deps.env);
    await mkdir(dirname(logPath), { recursive: true });
    await appendFile(logPath, `${line}\n`, "utf8");
    return true;
  } catch {
    return false;
  }
}
