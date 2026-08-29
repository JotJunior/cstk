// index.ts — bootstrap do McpServer + transporte stdio (task 2.2.2).
//
// mcp-direct-transport (FASE 1, tasks 1.1/1.2): o servidor NAO resolve mais
// sessao no boot — as 7 tools sao registradas incondicionalmente, mesmo sem
// token algum presente (contracts/server-session-resolution.md §1, C-1..C-4).
// O fail-closed (SEC-H3) nao foi relaxado: ele so MUDOU DE LUGAR — de uma
// vez no startup para TODA chamada de tool (secao 2 do contrato). Cada
// chamada resolve sua propria sessao a partir do `session_id` apresentado
// (token de capacidade + `CSTK_MCP_PROJECT_PATH` — tree-walk no cache-miss,
// modo direto revalidado no cache-hit; ver `session/resolve.ts`). Nunca ha
// modo "autoriza sem token" — so deixou de haver modo "recusa subir sem
// token".
//
// Entrada: variaveis de ambiente injetadas pelo processo que sobe este
// processo (o launcher `mcp-launch.sh`, task 6.1/F6 — ainda nao implementado
// nesta onda). "Deliberadamente sem env com valores interpolados" no
// `.mcp.json` em si (contracts/mcp-session-lifecycle.md §cstk mcp install)
// refere-se a ENTRADA ESTATICA do `.mcp.json` — nao impede o launcher de
// setar env no processo filho que ele de fato spawna.
//   CSTK_MCP_PROJECT_PATH — path do projeto-alvo, usado no tree-walk de
//                           cache-miss de CADA chamada (mantido; nao lido
//                           mais so uma vez no boot)
//   CSTK_MCP_SCRIPTS_DIR  — override do dir de scripts; obrigatoria na
//                           pratica fora de container (default
//                           /opt/cstk/scripts nao existe no host)
//   MCP_MAX_TOOL_CALLS    — teto de chamadas por processo (inalterado)
//
// `MCP_SESSION_TOKEN` deixou de ser lida por este arquivo: o token de
// capacidade agora chega por argumento de cada chamada de tool
// (`input.session_id`), nao mais por env fixada no boot do processo
// (contracts/server-session-resolution.md §3). `mcp-session.sh` continua
// aceitando essa env como fallback proprio, mas este servidor sempre passa
// `--token` explicito — nunca depende desse fallback.

import { pathToFileURL } from "node:url";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  createSessionCache,
  resolveSessionForCall,
  SessionMismatchError,
  type ResolvedSession,
  type SessionCache,
} from "./session/resolve.js";
import { sanitizeForLlmContext } from "./runtime/sanitize.js";
import {
  recordSkillInputShape,
  handleRecordSkill,
  type RecordSkillResponse,
} from "./tools/record_skill.js";
import {
  recordDecisionInputSchema,
  handleRecordDecision,
  type RecordDecisionResponse,
} from "./tools/record_decision.js";
import {
  openWaveInputShape,
  handleOpenWave,
  type OpenWaveResponse,
} from "./tools/open_wave.js";
import {
  recordTaskInputSchema,
  handleRecordTask,
  type RecordTaskResponse,
} from "./tools/record_task.js";
import {
  registerHumanBlockInputShape,
  handleRegisterHumanBlock,
  type RegisterHumanBlockResponse,
} from "./tools/register_human_block.js";
import {
  getStatusInputShape,
  handleGetStatus,
  type GetStatusResponse,
} from "./tools/get_status.js";
import {
  closeWaveInputShape,
  handleCloseWave,
  type CloseWaveResponse,
} from "./tools/close_wave.js";
import {
  collectOptinsInputShape,
  handleCollectOptins,
  type CollectOptinsResponse,
} from "./tools/collect_optins.js";
import { grantElicitationAccess } from "./runtime/elicitation-gate.js";
import {
  askOperatorInputSchema,
  handleAskOperator,
  type AskOperatorResponse,
} from "./tools/ask_operator.js";
import { resolveAndValidateBootTimeout, BootTimeoutError } from "./tools/ask-operator-clock.js";

const SERVER_NAME = "cstk-state";
// F3 (task 3.6-3.9 + tool get_status/dec-064): 5 tools novas registradas —
// mudanca ADITIVA (nenhuma tool/campo existente removido ou redefinido) —
// bump MINOR conforme contracts/mcp-tools.md §Versionamento de contrato.
// F4 (task 4.1): tool `close_wave` (atomicidade, FR-003) — tambem aditiva.
// 0.4.0: teto de chamadas por sessao (SEC-L1/LLM10, pos-MVP consumado) —
// aditivo (novo codigo de erro TOOL_CALL_LIMIT_EXCEEDED + env
// MCP_MAX_TOOL_CALLS; nenhum contrato existente alterado).
// 0.5.0: close_wave ganha advance/terminal_phase (wave-close-advance FR-008)
// 0.6.0: 8a tool `collect_optins` (mcp-elicitation-optins FASE 3+4.1) —
// aditiva (nenhuma tool/campo existente removido ou redefinido).
// 0.7.0: 9a tool `ask_operator` (human-bridge FASE 2, superficie 1) —
// aditiva. Boot passa a validar a combinacao de relogios (R-CLOCK-5,
// `resolveAndValidateBootTimeout`) e recusa subir se explicitamente ilegal.
const SERVER_VERSION = "0.7.0";

// SEC-L1 (LLM10 — consumo nao-limitado): teto de chamadas de tool por
// sessao/processo. dec-093 ratificou o adiamento pos-MVP; consumado aqui.
// budget.sh orca a ONDA (tool_calls_total ~80-142 observados) do lado do
// orquestrador; este teto e a rede do lado do SERVIDOR contra loop
// desgovernado de um cliente comprometido — por isso o default e folgado
// (varias ondas na mesma sessao) e configuravel via MCP_MAX_TOOL_CALLS
// no env do launcher (mcp-launch.sh / docker run). Allowlist do valor:
// inteiro positivo; ausente/invalido ⇒ default (nunca desabilitado).
const DEFAULT_MAX_TOOL_CALLS = 2000;

export function parseMaxToolCalls(raw: string | undefined): number {
  if (raw === undefined || raw === "") return DEFAULT_MAX_TOOL_CALLS;
  if (!/^[0-9]+$/.test(raw)) return DEFAULT_MAX_TOOL_CALLS;
  const parsed = Number(raw);
  if (!Number.isSafeInteger(parsed) || parsed < 1) return DEFAULT_MAX_TOOL_CALLS;
  return parsed;
}

/** Envelope generico de resposta de tool (accepted/rejected/stage/result — contracts/mcp-tools.md). */
interface ToolEnvelope {
  readonly outcome: "accepted" | "rejected";
  readonly reason: string | null;
  readonly stage: string | null;
  readonly result: unknown;
}

function toCallToolResult(toolName: string, response: ToolEnvelope) {
  return {
    content: [
      {
        type: "text" as const,
        text:
          response.outcome === "accepted"
            ? `${toolName}: accepted (${JSON.stringify(response.result)})`
            : `${toolName}: rejected — ${response.reason ?? "motivo desconhecido"}`,
      },
    ],
    structuredContent: response as unknown as Record<string, unknown>,
    isError: response.outcome === "rejected",
  };
}

/** Teto de reason de SESSION_MISMATCH reinjetado no contexto do LLM (SEC-M1, mesmo padrao das tools). */
const MAX_SESSION_MISMATCH_REASON_BYTES = 2048; // 2 KiB

/**
 * Resolve a sessao da chamada corrente (`resolveSessionForCall`) e traduz
 * falha em rejeicao `SESSION_MISMATCH` formatada como `ToolEnvelope` — NUNCA
 * lanca para fora deste helper. Compartilhado pelos 7 wrappers de tool
 * abaixo (mcp-direct-transport FASE 1, task 1.2.5): cada chamada de CADA
 * tool resolve sua propria sessao, em vez de reusar uma sessao unica
 * resolvida no boot.
 */
async function resolveCallSession(
  cache: SessionCache,
  projectPath: string,
  env: NodeJS.ProcessEnv,
  sessionId: string,
): Promise<{ session: ResolvedSession } | { envelope: ToolEnvelope }> {
  try {
    const session = await resolveSessionForCall(cache, {
      projectPath,
      token: sessionId,
      env,
    });
    return { session };
  } catch (err) {
    const message =
      err instanceof SessionMismatchError
        ? err.message
        : err instanceof Error
          ? err.message
          : String(err);
    return {
      envelope: {
        outcome: "rejected",
        reason: `SESSION_MISMATCH: ${sanitizeForLlmContext(message, MAX_SESSION_MISMATCH_REASON_BYTES)}`,
        stage: "precondition",
        result: null,
      },
    };
  }
}

export async function bootstrap(
  env: NodeJS.ProcessEnv = process.env,
): Promise<McpServer> {
  const projectPath = env.CSTK_MCP_PROJECT_PATH ?? "";

  // R-CLOCK-5 (human-bridge, contrato mcp-tool-ask-operator.md §4): valida a
  // combinacao de relogios da superficie `ask_operator` NO BOOT — env
  // ausente/invalida degrada para o default com 1 aviso (nunca recusa por
  // variavel OPCIONAL ausente); combinacao EXPLICITAMENTE ilegal lanca
  // `BootTimeoutError`, que propaga daqui para fora de `bootstrap()` e faz
  // o processo recusar-se a subir (tratado em `main()`).
  const { clientTimeoutMs } = resolveAndValidateBootTimeout(env);

  // mcp-direct-transport FASE 1 (C-1..C-4): as 7 tools registram
  // INCONDICIONALMENTE, independente de existir token ou de qualquer sessao
  // ja resolvida — nao ha mais resolucao no boot. O fail-closed (SEC-H3)
  // continua valendo, so que por chamada (ver `resolveCallSession` acima):
  // disponibilidade de tool nunca implicou, e continua nao implicando,
  // permissao de mutacao.
  const sessionCache = createSessionCache();

  const server = new McpServer({ name: SERVER_NAME, version: SERVER_VERSION });

  // SEC-L1: contador unico por processo. Ate mcp-direct-transport, a
  // cardinalidade era 1 processo : 1 sessao (um container por execucao);
  // apos a FASE 1, um MESMO processo pode atender N sessoes (N tokens
  // resolvidos por chamada) — o teto passou a ser por PROCESSO, nao mais
  // por execucao autonoma (contracts/server-session-resolution.md §5, T-1).
  // Excedeu ⇒ toda chamada subsequente e rejeitada com codigo enumerado — o
  // cliente (orquestrador) trata como erro de tool e comuta para o caminho
  // Bash (o teto NUNCA derruba o servidor; permanece acionavel — T-2).
  const maxToolCalls = parseMaxToolCalls(env.MCP_MAX_TOOL_CALLS);
  let toolCallsUsed = 0;
  let limitWarned = false;
  const checkCallLimit = (): ToolEnvelope | null => {
    toolCallsUsed += 1;
    if (toolCallsUsed <= maxToolCalls) return null;
    if (!limitWarned) {
      limitWarned = true;
      console.error(
        `${SERVER_NAME}: TOOL_CALL_LIMIT_EXCEEDED — teto de ${maxToolCalls} chamadas da sessao atingido (SEC-L1/LLM10); chamadas subsequentes serao rejeitadas`,
      );
    }
    return {
      outcome: "rejected",
      reason: `TOOL_CALL_LIMIT_EXCEEDED: chamada ${toolCallsUsed} excede o teto de ${maxToolCalls} por sessao (SEC-L1/LLM10). Comute para o caminho Bash; se o teto for baixo para esta execucao, ajuste MCP_MAX_TOOL_CALLS no launcher`,
      stage: null,
      result: null,
    };
  };

  server.registerTool(
    "record_skill",
    {
      title: "Record skill invocation",
      description:
        "Registra a invocacao de uma skill/gate na onda corrente da execucao (delega a state-ondas.sh record-skill).",
      inputSchema: recordSkillInputShape,
    },
    async (input) => {
      const limited = checkCallLimit();
      if (limited) return toCallToolResult("record_skill", limited);
      const resolved = await resolveCallSession(sessionCache, projectPath, env, input.session_id);
      if ("envelope" in resolved) return toCallToolResult("record_skill", resolved.envelope);
      const response: RecordSkillResponse = await handleRecordSkill(input, {
        session: resolved.session,
        env,
      });
      return toCallToolResult("record_skill", response);
    },
  );

  server.registerTool(
    "record_decision",
    {
      title: "Record auditable decision",
      description:
        "Registra uma Decisao auditavel (Principio I) na execucao corrente (delega a state-decisions.sh register).",
      inputSchema: recordDecisionInputSchema,
    },
    async (input) => {
      const limited = checkCallLimit();
      if (limited) return toCallToolResult("record_decision", limited);
      const resolved = await resolveCallSession(sessionCache, projectPath, env, input.session_id);
      if ("envelope" in resolved) return toCallToolResult("record_decision", resolved.envelope);
      const response: RecordDecisionResponse = await handleRecordDecision(input, {
        session: resolved.session,
        env,
      });
      return toCallToolResult("record_decision", response);
    },
  );

  server.registerTool(
    "open_wave",
    {
      title: "Open a new wave",
      description:
        "Abre a proxima onda da execucao corrente (delega a state-ondas.sh start; rejeita se ja houver onda aberta).",
      inputSchema: openWaveInputShape,
    },
    async (input) => {
      const limited = checkCallLimit();
      if (limited) return toCallToolResult("open_wave", limited);
      const resolved = await resolveCallSession(sessionCache, projectPath, env, input.session_id);
      if ("envelope" in resolved) return toCallToolResult("open_wave", resolved.envelope);
      const response: OpenWaveResponse = await handleOpenWave(input, {
        session: resolved.session,
        env,
      });
      return toCallToolResult("open_wave", response);
    },
  );

  server.registerTool(
    "record_task",
    {
      title: "Record task outcome",
      description:
        "Registra o outcome (pass/fail) de uma task, idempotente por task_id (delega a state-ondas.sh record-task).",
      inputSchema: recordTaskInputSchema,
    },
    async (input) => {
      const limited = checkCallLimit();
      if (limited) return toCallToolResult("record_task", limited);
      const resolved = await resolveCallSession(sessionCache, projectPath, env, input.session_id);
      if ("envelope" in resolved) return toCallToolResult("record_task", resolved.envelope);
      const response: RecordTaskResponse = await handleRecordTask(input, {
        session: resolved.session,
        env,
      });
      return toCallToolResult("record_task", response);
    },
  );

  server.registerTool(
    "register_human_block",
    {
      title: "Register human block",
      description:
        "Registra um bloqueio humano associado a uma Decisao (delega a bloqueios.sh register).",
      inputSchema: registerHumanBlockInputShape,
    },
    async (input) => {
      const limited = checkCallLimit();
      if (limited) return toCallToolResult("register_human_block", limited);
      const resolved = await resolveCallSession(sessionCache, projectPath, env, input.session_id);
      if ("envelope" in resolved) return toCallToolResult("register_human_block", resolved.envelope);
      const response: RegisterHumanBlockResponse = await handleRegisterHumanBlock(input, {
        session: resolved.session,
        env,
      });
      return toCallToolResult("register_human_block", response);
    },
  );

  server.registerTool(
    "get_status",
    {
      title: "Get server/execution status",
      description:
        "Consulta READ-ONLY do status da execucao corrente (status, etapa, onda, bloqueios pendentes) — nenhuma mutacao.",
      inputSchema: getStatusInputShape,
    },
    async (input) => {
      const limited = checkCallLimit();
      if (limited) return toCallToolResult("get_status", limited);
      const resolved = await resolveCallSession(sessionCache, projectPath, env, input.session_id);
      if ("envelope" in resolved) return toCallToolResult("get_status", resolved.envelope);
      const response: GetStatusResponse = await handleGetStatus(input, {
        session: resolved.session,
        env,
      });
      return toCallToolResult("get_status", response);
    },
  );

  server.registerTool(
    "close_wave",
    {
      title: "Close the current wave (atomic)",
      description:
        "Fecha a onda corrente atomicamente (delega a state-ondas.sh end + backup escrubado + selo de integridade; compensacao por pre-imagem em qualquer falha — a onda nunca fica parcialmente fechada).",
      inputSchema: closeWaveInputShape,
    },
    async (input) => {
      const limited = checkCallLimit();
      if (limited) return toCallToolResult("close_wave", limited);
      const resolved = await resolveCallSession(sessionCache, projectPath, env, input.session_id);
      if ("envelope" in resolved) return toCallToolResult("close_wave", resolved.envelope);
      const response: CloseWaveResponse = await handleCloseWave(input, {
        session: resolved.session,
        env,
      });
      return toCallToolResult("close_wave", response);
    },
  );

  server.registerTool(
    "collect_optins",
    {
      title: "Collect execution opt-ins",
      description:
        "Oferece UM formulario estruturado com os opt-ins de inicio de " +
        "execucao aplicaveis ao orquestrador corrente e persiste as " +
        "respostas via os helpers POSIX de escrita. Idempotente por campo " +
        "(cap M6: no maximo 1 coleta por execucao).",
      inputSchema: collectOptinsInputShape,
    },
    async (input) => {
      const limited = checkCallLimit();
      if (limited) return toCallToolResult("collect_optins", limited);
      const resolved = await resolveCallSession(sessionCache, projectPath, env, input.session_id);
      if ("envelope" in resolved) return toCallToolResult("collect_optins", resolved.envelope);
      const response: CollectOptinsResponse = await handleCollectOptins(input, {
        session: resolved.session,
        env,
        // Acesso a elicitInput/getClientCapabilities MUST vir do `Server`
        // bruto, nao do `McpServer` [VERIFICADO: server/mcp.d.ts:18 `readonly
        // server: Server`]. `grantElicitationAccess` e o UNICO ponto
        // autorizado a conceder isso (SEC L3, runtime/elicitation-gate.ts) —
        // nenhuma outra tool deve receber `server.server` diretamente.
        elicitationServer: grantElicitationAccess("collect_optins", server.server),
      });
      return toCallToolResult("collect_optins", response);
    },
  );

  server.registerTool(
    "ask_operator",
    {
      title: "Ask the operator a blocking question",
      description:
        "Pergunta BLOQUEANTE ao operador, cuja resposta chega pelo painel " +
        "(cstk-panel) — human-bridge superficie 1. Nunca e erro de tool: " +
        "declined/timeout/unavailable/failed retornam outcome accepted com " +
        "default_value aplicado (C-1/C-4).",
      inputSchema: askOperatorInputSchema,
    },
    async (input) => {
      const limited = checkCallLimit();
      if (limited) return toCallToolResult("ask_operator", limited);
      const resolved = await resolveCallSession(sessionCache, projectPath, env, input.session_id);
      if ("envelope" in resolved) return toCallToolResult("ask_operator", resolved.envelope);
      const response: AskOperatorResponse = await handleAskOperator(input, {
        session: resolved.session,
        env,
        clientTimeoutMs,
      });
      return toCallToolResult("ask_operator", response);
    },
  );

  return server;
}

async function main(): Promise<void> {
  // mcp-direct-transport FASE 1 (C-2, task 1.1.2): bootstrap() nao resolve
  // mais sessao alguma — nunca lanca `SessionMismatchError` no boot. Nao ha
  // mais o try/catch dedicado que abortava o processo com exitCode=1 quando
  // a sessao nao resolvia no startup; ausencia de token deixou de impedir o
  // processo de subir. Qualquer excecao verdadeiramente inesperada aqui cai
  // no `.catch` generico registrado abaixo, em `main().catch(...)`.
  //
  // human-bridge FASE 2 (R-CLOCK-5): `bootstrap()` PODE lancar
  // `BootTimeoutError` quando `CSTK_CLIENT_TOOL_TIMEOUT_MS` produz uma
  // combinacao EXPLICITAMENTE ilegal para `ask_operator` — o `.catch`
  // generico ja cobre esse caso (exitCode=1), mas capturamos aqui para uma
  // mensagem de diagnostico mais direta (sem stack trace irrelevante).
  let server: McpServer;
  try {
    server = await bootstrap();
  } catch (err) {
    if (err instanceof BootTimeoutError) {
      process.stderr.write(`cstk-state: recusando subir (R-CLOCK-5): ${err.message}\n`);
      process.exitCode = 1;
      return;
    }
    throw err;
  }

  const transport = new StdioServerTransport();
  await server.connect(transport);
}

// Roda apenas quando executado diretamente (nao quando importado por testes).
const isMainModule =
  process.argv[1] !== undefined &&
  import.meta.url === pathToFileURL(process.argv[1]).href;
if (isMainModule) {
  main().catch((err) => {
    process.stderr.write(`cstk-state: erro fatal: ${err instanceof Error ? err.stack ?? err.message : String(err)}\n`);
    process.exitCode = 1;
  });
}
