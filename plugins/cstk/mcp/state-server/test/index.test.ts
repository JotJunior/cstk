// test/index.test.ts — cobertura do bootstrap (task 1.1.4, mcp-direct-transport
// FASE 1): as tools registram INCONDICIONALMENTE, mesmo sem
// MCP_SESSION_TOKEN/CSTK_MCP_PROJECT_PATH validos — o fail-closed (SEC-H3)
// mudou de lugar (do boot para a chamada). Cobre tambem o caminho de
// rejeicao por chamada (SESSION_MISMATCH quando o token nao resolve),
// substituindo os antigos testes de rejeicao NO BOOT.
//
// `_registeredTools` e `private` apenas em tempo de compilacao TS — em
// runtime e um campo de instancia comum [VERIFICADO:
// node_modules/@modelcontextprotocol/sdk/dist/esm/server/mcp.js:19,649].
// Introspeccionamos por ele em vez de subir um client MCP completo so para
// listar tools/chamar handlers num teste de unidade.

import { test } from "node:test";
import assert from "node:assert/strict";
import { join } from "node:path";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { bootstrap } from "../src/index.js";

const FIXTURES_DIR = join(process.cwd(), "test", "fixtures");

function registeredToolNames(server: McpServer): string[] {
  const withPrivateAccess = server as unknown as {
    _registeredTools: Record<string, unknown>;
  };
  return Object.keys(withPrivateAccess._registeredTools);
}

interface RegisteredTool {
  handler: (input: Record<string, unknown>) => Promise<{
    isError: boolean;
    structuredContent: { outcome: string; reason: string | null };
  }>;
}

function registeredTool(server: McpServer, name: string): RegisteredTool {
  const withPrivateAccess = server as unknown as {
    _registeredTools: Record<string, RegisteredTool>;
  };
  const tool = withPrivateAccess._registeredTools[name];
  assert.ok(tool, `tool ${name} nao registrada`);
  return tool;
}

const ALL_NINE_TOOLS = [
  "record_skill",
  "record_decision",
  "open_wave",
  "record_task",
  "register_human_block",
  "get_status",
  "close_wave",
  "collect_optins",
  "ask_operator",
];

test("bootstrap (C-1): registra as 9 tools do MVP mesmo com sessao resolvivel (F2 + F3 + get_status/dec-064 + F4 close_wave + human-bridge ask_operator)", async () => {
  const server = await bootstrap({
    ...process.env,
    MCP_SESSION_TOKEN: "synthetic-token-abc123",
    CSTK_MCP_PROJECT_PATH: "/work",
    CSTK_MCP_SCRIPTS_DIR: join(FIXTURES_DIR, "scripts-ok"),
  });

  assert.ok(server instanceof McpServer);
  assert.deepEqual(registeredToolNames(server), ALL_NINE_TOOLS);
});

test("bootstrap (C-1/C-3, task 1.1.4): SEM MCP_SESSION_TOKEN e SEM CSTK_MCP_PROJECT_PATH, as 9 tools registram do mesmo jeito, e bootstrap() nunca lanca", async () => {
  const server = await bootstrap({
    ...process.env,
    MCP_SESSION_TOKEN: "",
    CSTK_MCP_PROJECT_PATH: "",
    CSTK_MCP_SCRIPTS_DIR: join(FIXTURES_DIR, "scripts-mismatch"),
  });

  assert.ok(server instanceof McpServer);
  assert.deepEqual(registeredToolNames(server), ALL_NINE_TOOLS);
});

test("bootstrap (C-1, defesa extra): scriptsDir apontando para helper inexistente ainda assim registra as 9 tools (a resolucao so acontece na CHAMADA)", async () => {
  const server = await bootstrap({
    ...process.env,
    MCP_SESSION_TOKEN: "qualquer-coisa",
    CSTK_MCP_PROJECT_PATH: "/nao/existe",
    CSTK_MCP_SCRIPTS_DIR: join(FIXTURES_DIR, "does-not-exist-dir"),
  });

  assert.deepEqual(registeredToolNames(server), ALL_NINE_TOOLS);
});

test("chamada (A-2, fail-closed por chamada): session_id que nao resolve para nenhuma sessao e rejeitada com SESSION_MISMATCH — tool continua registrada, servidor nao cai", async () => {
  const server = await bootstrap({
    ...process.env,
    CSTK_MCP_PROJECT_PATH: "/work",
    CSTK_MCP_SCRIPTS_DIR: join(FIXTURES_DIR, "scripts-mismatch"),
  });

  const getStatus = registeredTool(server, "get_status");
  const res = await getStatus.handler({ session_id: "token-desconhecido" });

  assert.equal(res.isError, true);
  assert.equal(res.structuredContent.outcome, "rejected");
  assert.ok(
    (res.structuredContent.reason ?? "").startsWith("SESSION_MISMATCH:"),
    `esperado prefixo SESSION_MISMATCH:, obtido: ${res.structuredContent.reason}`,
  );
});

test("chamada: session_id valido resolve e delega ao handler real (nao fica preso no envelope de precondicao)", async () => {
  const server = await bootstrap({
    ...process.env,
    CSTK_MCP_PROJECT_PATH: "/work",
    CSTK_MCP_SCRIPTS_DIR: join(FIXTURES_DIR, "scripts-ok"),
  });

  const getStatus = registeredTool(server, "get_status");
  const res = await getStatus.handler({ session_id: "synthetic-token-abc123" });

  // scripts-ok so tem mcp-session.sh (sem state-rw.sh/state-ondas.sh/
  // bloqueios.sh) — a resolucao de sessao PASSA, mas o handler real de
  // get_status falha na delegacao (HELPER_FAILED), nunca em
  // SESSION_MISMATCH: prova de que passou da barreira de precondicao.
  assert.equal(res.structuredContent.outcome, "rejected");
  assert.ok(
    !(res.structuredContent.reason ?? "").startsWith("SESSION_MISMATCH:"),
    `nao deveria ficar preso em SESSION_MISMATCH, obtido: ${res.structuredContent.reason}`,
  );
});
