// test/healthcheck.test.ts — cobertura de src/healthcheck.ts (task 5.3.2,
// dec-081/onda 16).
//
// Integracao real (nao mock): sobe uma instancia EFEMERA do proprio
// servidor (dist/src/index.js) como child process via StdioClientTransport
// e faz o handshake MCP `initialize` + `tools/call get_status` de ponta a
// ponta contra fixtures POSIX reais (test/fixtures/scripts-healthcheck-ok/).
// Mesmo padrao de test/index.test.ts (processos de verdade, nao mocks) —
// mas aqui exercitando o PROTOCOLO inteiro (client<->server via stdio), nao
// so a funcao `bootstrap`.

import { test } from "node:test";
import assert from "node:assert/strict";
import { join } from "node:path";
import { runHealthcheck } from "../src/healthcheck.js";

const FIXTURES_DIR = join(process.cwd(), "test", "fixtures");
const SCRIPTS_OK = join(FIXTURES_DIR, "scripts-healthcheck-ok");

function baseEnv(overrides: Record<string, string | undefined> = {}): NodeJS.ProcessEnv {
  return {
    ...process.env,
    MCP_SESSION_TOKEN: "healthcheck-test-token",
    CSTK_MCP_PROJECT_PATH: "/work",
    CSTK_MCP_STATE_DIR: "/data/state",
    CSTK_MCP_SCRIPTS_DIR: SCRIPTS_OK,
    ...overrides,
  };
}

test("runHealthcheck: handshake initialize + get_status completo contra sessao valida", async () => {
  await assert.doesNotReject(() => runHealthcheck(baseEnv()));
});

test("runHealthcheck: token divergente do descritor -> bootstrap fail-closed -> rejeita", async () => {
  await assert.rejects(() => runHealthcheck(baseEnv({ MCP_SESSION_TOKEN: "token-errado" })));
});

test("runHealthcheck: MCP_SESSION_TOKEN ausente -> rejeita ANTES de spawnar o servidor", async () => {
  await assert.rejects(
    () => runHealthcheck(baseEnv({ MCP_SESSION_TOKEN: "" })),
    /MCP_SESSION_TOKEN ausente/,
  );
});

test("runHealthcheck: nunca toca o PID1 real (isolamento) — duas sondas concorrentes nao colidem", async () => {
  // Se a sonda dependesse de docker attach ao processo real, duas sondas
  // concorrentes disputariam o MESMO stdin e uma delas fecharia o pipe da
  // outra. Como cada sonda spawna sua PROPRIA instancia efemera, ambas
  // devem completar independentemente.
  await Promise.all([runHealthcheck(baseEnv()), runHealthcheck(baseEnv())]);
});
