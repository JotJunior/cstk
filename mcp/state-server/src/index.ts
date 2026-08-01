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

const SERVER_NAME = "cstk-state";
const SERVER_VERSION = "0.1.0";

function toCallToolResult(response: RecordSkillResponse) {
  return {
    content: [
      {
        type: "text" as const,
        text:
          response.outcome === "accepted"
            ? `record_skill: accepted (${JSON.stringify(response.result)})`
            : `record_skill: rejected — ${response.reason ?? "motivo desconhecido"}`,
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

  server.registerTool(
    "record_skill",
    {
      title: "Record skill invocation",
      description:
        "Registra a invocacao de uma skill/gate na onda corrente da execucao (delega a state-ondas.sh record-skill).",
      inputSchema: recordSkillInputShape,
    },
    async (input) => {
      const response = await handleRecordSkill(input, { session, env });
      return toCallToolResult(response);
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
