// test/call-limit.test.ts — SEC-L1 (LLM10): teto de chamadas de tool por
// sessao (MCP_MAX_TOOL_CALLS). Cobre: parsing/allowlist do env, rejeicao
// enumerada TOOL_CALL_LIMIT_EXCEEDED apos o teto, contagem compartilhada
// entre tools distintas e o invariante "o teto rejeita chamadas, nunca
// derruba o servidor".
//
// Invocamos o handler registrado (`_registeredTools[name].handler` —
// mesma via de introspeccao de test/index.test.ts; propriedade verificada
// em node_modules/@modelcontextprotocol/sdk/dist/esm/server/mcp.js) — o
// guard roda ANTES do handler da tool, entao a fixture de get_status so e
// tocada nas chamadas dentro do teto.

import { test } from "node:test";
import assert from "node:assert/strict";
import { join } from "node:path";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { bootstrap, parseMaxToolCalls } from "../src/index.js";

const FIXTURES_DIR = join(process.cwd(), "test", "fixtures");

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

function bootEnv(maxCalls?: string): NodeJS.ProcessEnv {
  return {
    ...process.env,
    MCP_SESSION_TOKEN: "synthetic-token-abc123",
    CSTK_MCP_PROJECT_PATH: "/work",
    CSTK_MCP_SCRIPTS_DIR: join(FIXTURES_DIR, "scripts-ok"),
    ...(maxCalls === undefined ? {} : { MCP_MAX_TOOL_CALLS: maxCalls }),
  };
}

test("parseMaxToolCalls: allowlist — inteiro positivo passa; ausente/invalido/zero caem no default", () => {
  const def = parseMaxToolCalls(undefined);
  assert.ok(def >= 1, "default deve ser positivo");
  assert.equal(parseMaxToolCalls("7"), 7);
  assert.equal(parseMaxToolCalls(""), def);
  assert.equal(parseMaxToolCalls("0"), def);
  assert.equal(parseMaxToolCalls("-5"), def);
  assert.equal(parseMaxToolCalls("abc"), def);
  assert.equal(parseMaxToolCalls("1,5"), def);
  assert.equal(parseMaxToolCalls("2e3"), def);
});

test("SEC-L1: chamada alem do teto e rejeitada com TOOL_CALL_LIMIT_EXCEEDED (contagem compartilhada entre tools)", async () => {
  const server = await bootstrap(bootEnv("2"));
  const getStatus = registeredTool(server, "get_status");
  const input = { session_id: "synthetic-token-abc123" };

  // Chamadas 1 e 2: dentro do teto — o guard deixa passar (o resultado do
  // handler em si depende da fixture; o que o teto NAO pode fazer e
  // rejeitar com o codigo de limite).
  for (let i = 0; i < 2; i += 1) {
    const res = await getStatus.handler(input);
    assert.ok(
      !(res.structuredContent.reason ?? "").includes("TOOL_CALL_LIMIT_EXCEEDED"),
      `chamada ${i + 1} dentro do teto nao pode ser rejeitada por limite`,
    );
  }

  // Chamada 3 (via OUTRA tool): excede — contador e por sessao, nao por tool.
  const openWave = registeredTool(server, "open_wave");
  const res3 = await openWave.handler({ session_id: "synthetic-token-abc123" });
  assert.equal(res3.isError, true);
  assert.equal(res3.structuredContent.outcome, "rejected");
  assert.ok(
    (res3.structuredContent.reason ?? "").includes("TOOL_CALL_LIMIT_EXCEEDED"),
    `esperado TOOL_CALL_LIMIT_EXCEEDED, obtido: ${res3.structuredContent.reason}`,
  );

  // Invariante: o servidor continua de pe e respondendo (rejeita, nao cai).
  const res4 = await getStatus.handler(input);
  assert.equal(res4.isError, true);
  assert.ok((res4.structuredContent.reason ?? "").includes("TOOL_CALL_LIMIT_EXCEEDED"));
});

test("SEC-L1: MCP_MAX_TOOL_CALLS invalido cai no default folgado (nunca desabilita nem trava em zero)", async () => {
  const server = await bootstrap(bootEnv("nao-numerico"));
  const getStatus = registeredTool(server, "get_status");
  const res = await getStatus.handler({ session_id: "synthetic-token-abc123" });
  assert.ok(
    !(res.structuredContent.reason ?? "").includes("TOOL_CALL_LIMIT_EXCEEDED"),
    "com valor invalido o default (folgado) vale — 1a chamada jamais e rejeitada por limite",
  );
});
