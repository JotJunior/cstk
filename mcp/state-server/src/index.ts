// index.ts — bootstrap do McpServer + transporte stdio (task 2.2.2).
//
// Um container por execucao (contracts/mcp-session-lifecycle.md §Contrato
// do container). O servidor resolve, UMA vez no startup, a sessao a que
// esta ligado (token de capacidade + project-path — SEC-H3) e recusa
// subir (fail-closed) se a resolucao falhar: nao ha modo "sem sessao".
//
// Entrada: variaveis de ambiente injetadas pelo processo que sobe este
// container/processo (o launcher `mcp-launch.sh`, task 6.1/F6 — ainda nao
// implementado nesta onda). "Deliberadamente sem env com valores
// interpolados" no `.mcp.json` em si (contracts/mcp-session-lifecycle.md
// §cstk mcp install) refere-se a ENTRADA ESTATICA do `.mcp.json` — nao
// impede o launcher de setar env no processo filho que ele de fato spawna.
//   MCP_SESSION_TOKEN     — token de capacidade (mesmo nome aceito como
//                           fallback por mcp-session.sh resolve)
//   CSTK_MCP_PROJECT_PATH — path do projeto-alvo (obrigatorio; mcp-session.sh
//                           resolve nao tem fallback de env para --project-path)
//   CSTK_MCP_SCRIPTS_DIR  — override do dir de scripts (default
//                           /opt/cstk/scripts, o mount ro do container)

import { pathToFileURL } from "node:url";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { resolveActiveSession, SessionMismatchError } from "./session/resolve.js";
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

const SERVER_NAME = "cstk-state";
// F3 (task 3.6-3.9 + tool get_status/dec-064): 5 tools novas registradas —
// mudanca ADITIVA (nenhuma tool/campo existente removido ou redefinido) —
// bump MINOR conforme contracts/mcp-tools.md §Versionamento de contrato.
// F4 (task 4.1): tool `close_wave` (atomicidade, FR-003) — tambem aditiva.
// 0.4.0: teto de chamadas por sessao (SEC-L1/LLM10, pos-MVP consumado) —
// aditivo (novo codigo de erro TOOL_CALL_LIMIT_EXCEEDED + env
// MCP_MAX_TOOL_CALLS; nenhum contrato existente alterado).
// 0.5.0: close_wave ganha advance/terminal_phase (wave-close-advance FR-008)
const SERVER_VERSION = "0.5.0";

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

export async function bootstrap(
  env: NodeJS.ProcessEnv = process.env,
): Promise<McpServer> {
  const token = env.MCP_SESSION_TOKEN ?? "";
  const projectPath = env.CSTK_MCP_PROJECT_PATH ?? "";

  // Fail-closed (SEC-H3): sem sessao resolvida, o servidor nao registra
  // NENHUMA tool de mutacao. Deixar o processo subir "vazio" seria pior do
  // que recusar — o cliente MCP veria um servidor sem capacidades, e nao
  // um erro diagnosticavel.
  const session = await resolveActiveSession({ projectPath, token, env });

  const server = new McpServer({ name: SERVER_NAME, version: SERVER_VERSION });

  // SEC-L1: contador unico por processo (sessao == processo, um container
  // por execucao). Excedeu ⇒ toda chamada subsequente e rejeitada com
  // codigo enumerado — o cliente (orquestrador) trata como erro de tool e
  // comuta para o caminho Bash (o teto NUNCA derruba o servidor).
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
      const response: RecordSkillResponse = await handleRecordSkill(input, { session, env });
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
      const response: RecordDecisionResponse = await handleRecordDecision(input, { session, env });
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
      const response: OpenWaveResponse = await handleOpenWave(input, { session, env });
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
      const response: RecordTaskResponse = await handleRecordTask(input, { session, env });
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
      const response: RegisterHumanBlockResponse = await handleRegisterHumanBlock(input, {
        session,
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
      const response: GetStatusResponse = await handleGetStatus(input, { session, env });
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
      const response: CloseWaveResponse = await handleCloseWave(input, { session, env });
      return toCallToolResult("close_wave", response);
    },
  );

  return server;
}

async function main(): Promise<void> {
  let server: McpServer;
  try {
    server = await bootstrap();
  } catch (err) {
    if (err instanceof SessionMismatchError) {
      process.stderr.write(`cstk-state: ${err.message}\n`);
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
