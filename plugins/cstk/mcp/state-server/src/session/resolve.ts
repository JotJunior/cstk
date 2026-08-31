// session/resolve.ts — resolucao da execucao ativa por TOKEN DE CAPACIDADE
// (SEC-H3, finding HIGH do gate owasp-security).
//
// Delega INTEIRAMENTE a `mcp-session.sh resolve` (task 1.3) — nenhuma
// reimplementacao da regra de resolucao em TS. O roteamento de mutacao MUST
// ser por posse de um token, NUNCA por precedencia/heuristica de ambiente
// (a precedencia do hook PreToolUse continua valendo so para consulta
// read-only humana em `cstk mcp status` sem `--state-dir`).
//
// mcp-direct-transport (FASE 1, tasks 1.1/1.2): a resolucao deixou de
// acontecer UMA vez no boot do servidor — agora acontece a CADA chamada de
// tool, via `resolveSessionForCall`. `resolveActiveSession` continua sendo
// a primitiva de baixo nivel (uma unica tentativa de resolucao contra o
// helper, por `--project-path` OU por `--state-dir` explicito), mas quem
// decide QUAL modo usar em cada chamada agora e o cache `token -> state_dir`
// deste modulo (contracts/server-session-resolution.md §2), nao mais uma
// variavel de ambiente fixada no processo inteiro.
//
// Ref: docs/specs/state-mcp-server/contracts/mcp-session-lifecycle.md
//   §Resolucao da execucao ativa (helper mcp-session.sh) / §SEC-H3
//      global/skills/agente-00c-runtime/scripts/mcp-session.sh (task 1.3;
//      subcomando `resolve --project-path PATH [--token T|--token-file F]`)
//   docs/specs/mcp-direct-transport/contracts/server-session-resolution.md
//   §2 (resolucao por chamada) — fluxo/cache implementados abaixo.

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
  /**
   * Modo direto explicito (equivalente a `mcp-session.sh resolve --state-dir`):
   * quando fornecido, a resolucao pula o tree-walk de `--project-path` e
   * revalida DIRETO contra `<stateDir>/mcp-server.json`. Substitui a antiga
   * leitura de `CSTK_MCP_STATE_DIR` do ambiente (mcp-direct-transport FASE 1,
   * task 1.2/contracts/server-session-resolution.md §3): o valor agora vem
   * do CACHE por chamada (`resolveSessionForCall`), nunca de uma env fixa
   * para o processo inteiro — um processo passa a atender N sessoes
   * (state-dirs diferentes), nao mais 1:1.
   */
  readonly stateDir?: string;
  /** Override do path do helper (testes fora do container). Default: `<scriptsDir>/mcp-session.sh`. */
  readonly helperPath?: string;
  readonly env?: NodeJS.ProcessEnv;
}

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
 * Resolve UMA tentativa de sessao (execucao) para a qual o chamador esta
 * autorizado a mutar, dado o token de capacidade apresentado. Ate a FASE 1
 * de mcp-direct-transport era chamada UMA vez no bootstrap; agora e chamada
 * a CADA chamada de tool, via `resolveSessionForCall` (que decide se usa o
 * modo direto `stateDir` — cache hit — ou o tree-walk `projectPath` — cache
 * miss). Nunca cacheia nada por si so: cada chamada revalida do zero contra
 * o helper POSIX (fail-closed, SEC-H3).
 */
export async function resolveActiveSession(
  options: ResolveSessionOptions,
): Promise<ResolvedSession> {
  const { projectPath, token, stateDir, env = process.env } = options;
  const helperPath =
    options.helperPath ?? join(resolveScriptsDir(env), "mcp-session.sh");

  if (!stateDir && !projectPath) {
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
    // Modo direto (stateDir explicito, ex.: cache hit em resolveSessionForCall):
    // sem tree-walk, revalida so o descritor daquele state-dir. Modo
    // tree-walk (projectPath, cache miss): varre TODAS as execucoes ativas
    // sob o projeto e popula o cache do chamador em caso de sucesso.
    const locatorArgs = stateDir
      ? ["--state-dir", stateDir]
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
 * Cache de resolucao por chamada (contracts/server-session-resolution.md
 * §2.3, K-1..K-5): guarda **somente** `token -> state_dir`, escopado ao
 * processo (sem persistencia em disco), sem TTL. PROIBIDO guardar
 * `stopped_at`, o descritor inteiro, ou qualquer veredito de autorizacao —
 * cachear isso abriria uma janela em que uma execucao TERMINAL ainda
 * autorizaria mutacao (K-2). O cache e so um atalho para saber ONDE olhar;
 * quem decide SE autoriza e sempre a revalidacao integral contra o disco
 * (`resolveActiveSession` com `stateDir` explicito).
 */
export interface SessionCache {
  get(token: string): string | undefined;
  set(token: string, stateDir: string): void;
}

/** Cria um cache de resolucao vazio, escopado a UMA instancia de servidor (um `bootstrap()`). */
export function createSessionCache(): SessionCache {
  const map = new Map<string, string>();
  return {
    get: (token) => map.get(token),
    set: (token, stateDir) => {
      map.set(token, stateDir);
    },
  };
}

export type ResolveSessionForCallOptions = Omit<ResolveSessionOptions, "stateDir">;

/**
 * Resolucao por chamada (contracts/server-session-resolution.md §2.1):
 * chamada a CADA invocacao de tool, antes de qualquer mutacao.
 *
 *   - hit  (token ja visto): revalida em modo DIRETO contra o `state_dir`
 *     cacheado — NUNCA autoriza so pelo cache (A-5); se a revalidacao
 *     falhar (execucao ficou terminal, descritor sumiu, ...), a chamada e
 *     rejeitada, sem fallback silencioso para tree-walk.
 *   - miss (token novo para este processo): tree-walk via `projectPath`;
 *     em caso de sucesso, popula o cache para as proximas chamadas do MESMO
 *     token (K-5 — o miss em si nunca falha so por ser miss).
 */
export async function resolveSessionForCall(
  cache: SessionCache,
  options: ResolveSessionForCallOptions,
): Promise<ResolvedSession> {
  const cachedStateDir = options.token ? cache.get(options.token) : undefined;

  if (cachedStateDir) {
    return resolveActiveSession({ ...options, stateDir: cachedStateDir });
  }

  const session = await resolveActiveSession(options);
  if (options.token) {
    cache.set(options.token, session.stateDir);
  }
  return session;
}

/**
 * Valida que o `session_id` apresentado por uma chamada de tool casa
 * exatamente com o token da sessao resolvida NESSA MESMA chamada. Comparacao
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
