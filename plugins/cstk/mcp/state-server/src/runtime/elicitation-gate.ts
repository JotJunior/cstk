// runtime/elicitation-gate.ts — allowlist mecanica de quais tools podem
// obter acesso a `elicitInput` (gate owasp-security, achado L3; plan.md
// linha 343-344; docs/specs/mcp-elicitation-optins/tasks.md FASE 9, task
// 9.5.1).
//
// `server.server` [VERIFICADO: server/mcp.d.ts:18 `readonly server: Server`]
// e o `Server` BRUTO do SDK MCP — expoe capacidades muito mais amplas que
// `elicitInput` (toda a superficie de protocolo). Sem uma fronteira
// explicita, um `server.registerTool` futuro poderia ganhar acesso por
// engano (copiar/colar `elicitationServer: server.server` num handler
// novo), permitindo que QUALQUER tool dispare `elicitation/create` — nao
// so `collect_optins`, a unica que o cap M6/Invariante C-3 foi desenhado
// para governar.
//
// Este modulo e o UNICO ponto autorizado a produzir um `ElicitationServer`
// a partir do `Server` bruto: `index.ts` MUST importar
// `grantElicitationAccess` em vez de passar `server.server` diretamente a
// QUALQUER `deps` de tool. Dupla barreira (defesa em profundidade, mesmo
// espirito de SEC-H1 — nunca confiar so no tipo estatico numa fronteira de
// seguranca):
//   1. COMPILACAO — `tool` e tipado como a uniao FECHADA de
//      `ELICITATION_ALLOWED_TOOLS`; `grantElicitationAccess("record_skill", ...)`
//      e erro de tipo, nao compila.
//   2. RUNTIME — revalidado contra o mesmo array em runtime (protege contra
//      `as` / cast / chamada via variavel `string` nao literal, que
//      contornaria a barreira de compilacao).

import type {
  ElicitRequestFormParams,
  ElicitResult,
} from "@modelcontextprotocol/sdk/types.js";

export interface ElicitationServer {
  getClientCapabilities(): { readonly elicitation?: unknown } | undefined;
  elicitInput(
    params: ElicitRequestFormParams,
    options?: { readonly timeout?: number },
  ): Promise<ElicitResult>;
}

/**
 * Allowlist fechada — UNICA tool autorizada a chamar `elicitInput` hoje.
 * Adicionar uma nova tool exige tocar ESTE array explicitamente (nunca
 * silencioso) — task 9.5.1: "nenhuma das outras 7 tools existentes nem
 * futuras sem allowlist explicita".
 */
export const ELICITATION_ALLOWED_TOOLS = ["collect_optins"] as const;

export type ElicitationAllowedTool = (typeof ELICITATION_ALLOWED_TOOLS)[number];

export class ElicitationNotAllowedError extends Error {
  constructor(tool: string) {
    super(
      `elicitInput nao autorizado para a tool '${tool}' — allowlist: ${ELICITATION_ALLOWED_TOOLS.join(", ")}`,
    );
    this.name = "ElicitationNotAllowedError";
  }
}

/**
 * Unico ponto autorizado a conceder um `ElicitationServer` a partir do
 * `Server` bruto do SDK. `tool` MUST ser um literal da allowlist (barreira
 * de compilacao); revalidado contra o mesmo array em runtime (barreira que
 * sobrevive a um cast/contorno de tipo).
 */
export function grantElicitationAccess(
  tool: ElicitationAllowedTool,
  rawServer: ElicitationServer,
): ElicitationServer {
  if (!(ELICITATION_ALLOWED_TOOLS as readonly string[]).includes(tool)) {
    throw new ElicitationNotAllowedError(tool);
  }
  return rawServer;
}
