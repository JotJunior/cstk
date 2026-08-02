// test/resolve.test.ts — cobertura de session/resolve.ts.
//
// Usa fixtures POSIX reais em test/fixtures/ (processos de verdade via
// execFile, nao mocks) para exercitar o caminho feliz e o fail-closed de
// SEC-H3. Assume cwd = raiz do pacote (comportamento padrao de `npm test`).

import { test } from "node:test";
import assert from "node:assert/strict";
import { join } from "node:path";
import {
  resolveActiveSession,
  matchesResolvedSession,
  SessionMismatchError,
} from "../src/session/resolve.js";

const FIXTURES_DIR = join(process.cwd(), "test", "fixtures");

test("resolveActiveSession: caminho feliz resolve os 6 campos do descritor", async () => {
  const session = await resolveActiveSession({
    projectPath: "/work",
    token: "synthetic-token-abc123",
    helperPath: join(FIXTURES_DIR, "fake-mcp-session-ok.sh"),
  });

  assert.equal(session.token, "synthetic-token-abc123");
  assert.equal(session.stateDir, "/data/state");
  assert.equal(session.executionKind, "feature-00c");
  assert.equal(session.shortName, "state-mcp-server");
  assert.equal(session.targetProjectPath, "/work");
  assert.equal(session.mode, "docker");
  assert.equal(session.container, "cstk-mcp-state-test");
});

test("resolveActiveSession: token ausente falha SEM invocar o helper (fail-closed)", async () => {
  await assert.rejects(
    () =>
      resolveActiveSession({
        projectPath: "/work",
        token: "",
        helperPath: join(FIXTURES_DIR, "fake-mcp-session-ok.sh"),
      }),
    SessionMismatchError,
  );
});

test("resolveActiveSession: projectPath ausente falha SEM invocar o helper (fail-closed)", async () => {
  await assert.rejects(
    () =>
      resolveActiveSession({
        projectPath: "",
        token: "synthetic-token-abc123",
        helperPath: join(FIXTURES_DIR, "fake-mcp-session-ok.sh"),
      }),
    SessionMismatchError,
  );
});

test("resolveActiveSession: SESSION_MISMATCH (exit 3) do helper vira SessionMismatchError, sem fallback", async () => {
  await assert.rejects(
    () =>
      resolveActiveSession({
        projectPath: "/work",
        token: "token-desconhecido",
        helperPath: join(FIXTURES_DIR, "fake-mcp-session-mismatch.sh"),
      }),
    SessionMismatchError,
  );
});

test("resolveActiveSession: CSTK_MCP_STATE_DIR presente -> usa modo direto --state-dir (dec-081), nunca --project-path", async () => {
  const session = await resolveActiveSession({
    projectPath: "/host/path/nao/existe/no/container",
    token: "synthetic-token-abc123",
    helperPath: join(FIXTURES_DIR, "fake-mcp-session-ok-container-mode.sh"),
    env: { CSTK_MCP_STATE_DIR: "/data/state" },
  });

  assert.equal(session.stateDir, "/data/state");
  assert.equal(session.executionKind, "feature-00c");
});

test("resolveActiveSession: CSTK_MCP_STATE_DIR presente dispensa projectPath (fail-closed do project-path nao se aplica no modo container)", async () => {
  const session = await resolveActiveSession({
    projectPath: "",
    token: "synthetic-token-abc123",
    helperPath: join(FIXTURES_DIR, "fake-mcp-session-ok-container-mode.sh"),
    env: { CSTK_MCP_STATE_DIR: "/data/state" },
  });

  assert.equal(session.stateDir, "/data/state");
});

test("resolveActiveSession: sem CSTK_MCP_STATE_DIR, comportamento --project-path e IDENTICO ao anterior (zero regressao)", async () => {
  const session = await resolveActiveSession({
    projectPath: "/work",
    token: "synthetic-token-abc123",
    helperPath: join(FIXTURES_DIR, "fake-mcp-session-ok.sh"),
    env: {},
  });

  assert.equal(session.stateDir, "/data/state");
  assert.equal(session.targetProjectPath, "/work");
});

test("matchesResolvedSession: compara o session_id apresentado contra o token resolvido", async () => {
  const session = await resolveActiveSession({
    projectPath: "/work",
    token: "synthetic-token-abc123",
    helperPath: join(FIXTURES_DIR, "fake-mcp-session-ok.sh"),
  });

  assert.equal(matchesResolvedSession(session, "synthetic-token-abc123"), true);
  assert.equal(matchesResolvedSession(session, "outro-token"), false);
  assert.equal(matchesResolvedSession(session, ""), false);
});
