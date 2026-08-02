// test/get_status.test.ts — cobertura da tool get_status (read-only,
// escopo expandido pelo operador via dec-064/block-004): happy path
// (5 leituras compostas), SESSION_MISMATCH e falha de uma das leituras.

import { test } from "node:test";
import assert from "node:assert/strict";
import { join } from "node:path";
import { z } from "zod";
import {
  handleGetStatus,
  getStatusInputShape,
  type GetStatusInput,
} from "../src/tools/get_status.js";
import type { ResolvedSession } from "../src/session/resolve.js";

const FIXTURES_DIR = join(process.cwd(), "test", "fixtures");
const inputSchema = z.object(getStatusInputShape);

const FAKE_SESSION: ResolvedSession = {
  token: "synthetic-token-abc123",
  stateDir: "/data/state",
  executionKind: "feature-00c",
  shortName: "state-mcp-server",
  targetProjectPath: "/work",
  mode: "docker",
  container: "cstk-mcp-state-test",
};

function parseOrThrow(raw: unknown): GetStatusInput {
  return inputSchema.parse(raw);
}

test("inputSchema: aceita payload com apenas session_id", () => {
  const parsed = inputSchema.safeParse({ session_id: "t" });
  assert.equal(parsed.success, true);
});

test("handleGetStatus: happy path compoe as 5 leituras read-only", async () => {
  const input = parseOrThrow({ session_id: "synthetic-token-abc123" });

  const response = await handleGetStatus(input, {
    session: FAKE_SESSION,
    stateRwHelperPath: join(FIXTURES_DIR, "fake-state-rw-get-status.sh"),
    ondasHelperPath: join(FIXTURES_DIR, "fake-state-ondas-get-status.sh"),
    bloqueiosHelperPath: join(FIXTURES_DIR, "fake-bloqueios-count-status.sh"),
  });

  assert.equal(response.outcome, "accepted");
  assert.equal(response.stage, null);
  assert.deepEqual(response.result, {
    execution_status: "em_andamento",
    current_stage: "execute-task",
    wave_status: "open",
    current_wave_id: "onda-012",
    pending_human_blocks: 0,
  });
});

test("handleGetStatus: session_id divergente => SESSION_MISMATCH, sem chamar nenhum helper", async () => {
  const input = parseOrThrow({ session_id: "token-errado" });

  const response = await handleGetStatus(input, {
    session: FAKE_SESSION,
    stateRwHelperPath: join(FIXTURES_DIR, "does-not-exist.sh"),
    ondasHelperPath: join(FIXTURES_DIR, "does-not-exist.sh"),
    bloqueiosHelperPath: join(FIXTURES_DIR, "does-not-exist.sh"),
  });

  assert.equal(response.outcome, "rejected");
  assert.equal(response.stage, "precondition");
  assert.match(response.reason ?? "", /SESSION_MISMATCH/);
});

test("handleGetStatus: falha numa das leituras => HELPER_FAILED (nunca fabrica o campo)", async () => {
  const input = parseOrThrow({ session_id: "synthetic-token-abc123" });

  const response = await handleGetStatus(input, {
    session: FAKE_SESSION,
    stateRwHelperPath: join(FIXTURES_DIR, "fake-state-rw-get-status-fails.sh"),
    ondasHelperPath: join(FIXTURES_DIR, "fake-state-ondas-get-status.sh"),
    bloqueiosHelperPath: join(FIXTURES_DIR, "fake-bloqueios-count-status.sh"),
  });

  assert.equal(response.outcome, "rejected");
  assert.equal(response.stage, "delegation");
  assert.match(response.reason ?? "", /HELPER_FAILED/);
});
