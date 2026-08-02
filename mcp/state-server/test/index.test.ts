// test/index.test.ts — cobertura do bootstrap (task 2.2.6): happy path
// (sessao resolvida + tool record_skill registrada) e fail-closed
// (SESSION_MISMATCH nunca sobe um servidor "vazio").
//
// `_registeredTools` e `private` apenas em tempo de compilacao TS — em
// runtime e um campo de instancia comum [VERIFICADO:
// node_modules/@modelcontextprotocol/sdk/dist/esm/server/mcp.js:19,649].
// Introspeccionamos por ele em vez de subir um client MCP completo so para
// listar tools num teste de unidade.

import { test } from "node:test";
import assert from "node:assert/strict";
import { join } from "node:path";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { bootstrap } from "../src/index.js";
import { SessionMismatchError } from "../src/session/resolve.js";

const FIXTURES_DIR = join(process.cwd(), "test", "fixtures");

function registeredToolNames(server: McpServer): string[] {
  const withPrivateAccess = server as unknown as {
    _registeredTools: Record<string, unknown>;
  };
  return Object.keys(withPrivateAccess._registeredTools);
}

test("bootstrap: sessao resolvida registra as 7 tools do MVP (F2 + F3 + get_status/dec-064 + F4 close_wave)", async () => {
  const server = await bootstrap({
    ...process.env,
    MCP_SESSION_TOKEN: "synthetic-token-abc123",
    CSTK_MCP_PROJECT_PATH: "/work",
    CSTK_MCP_SCRIPTS_DIR: join(FIXTURES_DIR, "scripts-ok"),
  });

  assert.ok(server instanceof McpServer);
  assert.deepEqual(registeredToolNames(server), [
    "record_skill",
    "record_decision",
    "open_wave",
    "record_task",
    "register_human_block",
    "get_status",
    "close_wave",
  ]);
});

test("bootstrap: SESSION_MISMATCH no startup rejeita (fail-closed) — nenhuma tool e registrada", async () => {
  await assert.rejects(
    () =>
      bootstrap({
        ...process.env,
        MCP_SESSION_TOKEN: "token-desconhecido",
        CSTK_MCP_PROJECT_PATH: "/work",
        CSTK_MCP_SCRIPTS_DIR: join(FIXTURES_DIR, "scripts-mismatch"),
      }),
    SessionMismatchError,
  );
});

test("bootstrap: token ausente rejeita ANTES de tocar o helper (fail-closed)", async () => {
  await assert.rejects(
    () =>
      bootstrap({
        ...process.env,
        MCP_SESSION_TOKEN: "",
        CSTK_MCP_PROJECT_PATH: "/work",
        CSTK_MCP_SCRIPTS_DIR: join(FIXTURES_DIR, "scripts-ok"),
      }),
    SessionMismatchError,
  );
});
