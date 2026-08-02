// session/resolve.ts — resolucao da execucao ativa por TOKEN DE CAPACIDADE
// (SEC-H3, finding HIGH do gate owasp-security).
//
// Delega INTEIRAMENTE a `mcp-session.sh resolve` (task 1.3) — nenhuma
// reimplementacao da regra de resolucao em TS. O roteamento de mutacao MUST
// ser por posse de um token, NUNCA por precedencia/heuristica de ambiente
// (a precedencia do hook PreToolUse continua valendo so para consulta
// read-only humana em `cstk mcp status` sem `--state-dir`).
//
// Ref: docs/specs/state-mcp-server/contracts/mcp-session-lifecycle.md
//   §Resolucao da execucao ativa (helper mcp-session.sh) / §SEC-H3
//      global/skills/agente-00c-runtime/scripts/mcp-session.sh (task 1.3;
//      subcomando `resolve --project-path PATH [--token T|--token-file F]`)

import { join } from "node:path";
import { resolveScriptsDir, runHelper, HelperExecutionError } from "../runtime/exec.js";

export interface ResolvedSession {
  /** Token de capacidade apresentado — a mesma sessao MUST reapresenta-lo em cada chamada de tool. */
  readonly token: string;
  readonly stateDir: string;
  readonly executionKind: string;
  readonly shortName: string;
  readonly targetProjectPath: string;
  readonly mode: string;
  readonly container: string;
}

/**
 * Rejeicao fail-closed (SEC-H3): token ausente, desconhecido, de execucao ja
 * terminal, ou saida do helper impossivel de interpretar. NUNCA cai em
 * fallback para "a execucao ativa mais provavel".
 */
export class SessionMismatchError extends Error {
  constructor(message: string, options?: { cause?: unknown }) {
    super(message, options);
    this.name = "SessionMismatchError";
  }
}

export interface ResolveSessionOptions {
  readonly projectPath: string;
  readonly token: string;
  /** Override do path do helper (testes fora do container). Default: `<scriptsDir>/mcp-session.sh`. */
  readonly helperPath?: string;
  readonly env?: NodeJS.ProcessEnv;
}

/**
 * Path do state-dir da propria execucao visto de DENTRO do container
 * (dec-081, task 5.3): quando presente, `resolveActiveSession` usa o modo
 * DIRETO de `mcp-session.sh resolve --state-dir` em vez do tree-walk
 * `--project-path`. Necessario porque dentro do container apenas
 * `/data/state` esta montado — `CSTK_MCP_PROJECT_PATH` (path do HOST) nao
 * existe como diretorio ali, entao o modo `--project-path` sempre falharia.
 * Fora do container (testes, uso direto do helper), esta env fica ausente
 * e o comportamento por `--project-path` permanece EXATAMENTE o de antes
 * (zero regressao).
 */
const CONTAINER_STATE_DIR_ENV = "CSTK_MCP_STATE_DIR";

const REQUIRED_DESCRIPTOR_FIELDS = [
  "state_dir",
  "execution_kind",
  "short_name",
  "target_project_path",
  "mode",
  "container",
] as const;

type DescriptorField = (typeof REQUIRED_DESCRIPTOR_FIELDS)[number];

function parseDescriptorLines(stdout: string): Record<string, string> {
  const fields: Record<string, string> = {};
  for (const line of stdout.split("\n")) {
    const idx = line.indexOf("=");
    if (idx === -1) continue;
    fields[line.slice(0, idx)] = line.slice(idx + 1);
  }
  return fields;
}

function requireFields(
  fields: Record<string, string>,
): Record<DescriptorField, string> {
  for (const key of REQUIRED_DESCRIPTOR_FIELDS) {
    if (!(key in fields)) {
      throw new SessionMismatchError(
        `resolveActiveSession: saida de mcp-session.sh resolve sem o campo obrigatorio '${key}'`,
      );
    }
  }
  return fields as Record<DescriptorField, string>;
}

/**
 * Resolve a sessao (execucao) para a qual este servidor esta autorizado a
 * mutar, dado o token de capacidade apresentado. Chamado UMA vez no
 * bootstrap (`index.ts`); o resultado (em especial `token`) e a base contra
 * a qual CADA chamada de tool subsequente valida seu argumento `session_id`
 * (contracts/mcp-tools.md §Argumento comum a TODAS as tools).
 */
export async function resolveActiveSession(
  options: ResolveSessionOptions,
): Promise<ResolvedSession> {
  const { projectPath, token, env = process.env } = options;
  const helperPath =
    options.helperPath ?? join(resolveScriptsDir(env), "mcp-session.sh");

  const containerStateDir = env[CONTAINER_STATE_DIR_ENV];

  if (!containerStateDir && !projectPath) {
    throw new SessionMismatchError(
      "resolveActiveSession: projectPath ausente (env CSTK_MCP_PROJECT_PATH nao definida)",
    );
  }
  if (!token) {
    throw new SessionMismatchError(
      "resolveActiveSession: token ausente (env MCP_SESSION_TOKEN nao definida)",
    );
  }

  try {
    // Modo direto (dec-081): dentro do container, CSTK_MCP_STATE_DIR
    // aponta para o mount /data/state — sem tree-walk. Fora do container
    // (env ausente), o comportamento --project-path e IDENTICO ao de
    // antes desta task.
    const locatorArgs = containerStateDir
      ? ["--state-dir", containerStateDir]
      : ["--project-path", projectPath];
    const { stdout } = await runHelper(helperPath, [
      "resolve",
      ...locatorArgs,
      "--token",
      token,
    ]);
    const fields = requireFields(parseDescriptorLines(stdout));
    return {
      token,
      stateDir: fields.state_dir,
      executionKind: fields.execution_kind,
      shortName: fields.short_name,
      targetProjectPath: fields.target_project_path,
      mode: fields.mode,
      container: fields.container,
    };
  } catch (err) {
    if (err instanceof SessionMismatchError) throw err;
    // mcp-session.sh resolve exit 3 = SESSION_MISMATCH (fail-closed); exit
    // 1/2 = erro de IO/uso. Em qualquer caso, a decisao de seguranca e a
    // mesma: nao ha sessao resolvida, nao ha fallback.
    const cause = err instanceof HelperExecutionError ? err : undefined;
    throw new SessionMismatchError(
      `resolveActiveSession: mcp-session.sh resolve falhou (SESSION_MISMATCH ou erro de I/O)${
        cause ? `: ${cause.message}` : ""
      }`,
      { cause: err },
    );
  }
}

/**
 * Valida que o `session_id` apresentado por uma chamada de tool casa
 * exatamente com o token da sessao resolvida no bootstrap. Comparacao
 * simples de string (nao ha necessidade de comparacao em tempo constante:
 * o token nunca e ecoado de volta a um chamador nao autorizado, e o
 * universo de tentativas por sessao stdio local e desprezivel — SEC-L1).
 */
export function matchesResolvedSession(
  session: ResolvedSession,
  presentedSessionId: string,
): boolean {
  return session.token === presentedSessionId;
}
