// test/open_wave.test.ts — cobertura da tool open_wave: happy path
// (wave-status=none -> start), WAVE_ALREADY_OPEN (precondicao, `start`
// nunca invocado), SESSION_MISMATCH e falha de leitura da pre-condicao.

import { test } from "node:test";
import assert from "node:assert/strict";
import { join } from "node:path";
import { z } from "zod";
import {
  handleOpenWave,
  openWaveInputShape,
  type OpenWaveInput,
} from "../src/tools/open_wave.js";
import type { ResolvedSession } from "../src/session/resolve.js";

const FIXTURES_DIR = join(process.cwd(), "test", "fixtures");
const inputSchema = z.object(openWaveInputShape);

const FAKE_SESSION: ResolvedSession = {
  token: "synthetic-token-abc123",
  stateDir: "/data/state",
  executionKind: "feature-00c",
  shortName: "state-mcp-server",
  targetProjectPath: "/work",
  mode: "docker",
  container: "cstk-mcp-state-test",
};

function parseOrThrow(raw: unknown): OpenWaveInput {
  return inputSchema.parse(raw);
}

test("inputSchema: aceita payload com apenas session_id", () => {
  const parsed = inputSchema.safeParse({ session_id: "t" });
  assert.equal(parsed.success, true);
});

test("handleOpenWave: happy path (wave-status=none) delega a start e devolve wave_id", async () => {
  const input = parseOrThrow({ session_id: "synthetic-token-abc123" });

  const response = await handleOpenWave(input, {
    session: FAKE_SESSION,
    helperPath: join(FIXTURES_DIR, "fake-open-wave-status-none-then-start.sh"),
  });

  assert.equal(response.outcome, "accepted");
  assert.equal(response.stage, null);
  assert.deepEqual(response.result, { wave_id: "onda-013" });
});

test("handleOpenWave: WAVE_ALREADY_OPEN — start NUNCA e chamado quando ja ha onda aberta", async () => {
  const input = parseOrThrow({ session_id: "synthetic-token-abc123" });

  const response = await handleOpenWave(input, {
    session: FAKE_SESSION,
    helperPath: join(FIXTURES_DIR, "fake-open-wave-already-open.sh"),
  });

  assert.equal(response.outcome, "rejected");
  assert.equal(response.stage, "precondition");
  assert.match(response.reason ?? "", /WAVE_ALREADY_OPEN/);
});

test("handleOpenWave: session_id divergente => SESSION_MISMATCH, sem chamar o helper", async () => {
  const input = parseOrThrow({ session_id: "token-errado" });

  const response = await handleOpenWave(input, {
    session: FAKE_SESSION,
    helperPath: join(FIXTURES_DIR, "does-not-exist.sh"),
  });

  assert.equal(response.outcome, "rejected");
  assert.equal(response.stage, "precondition");
  assert.match(response.reason ?? "", /SESSION_MISMATCH/);
});

test("handleOpenWave: falha na leitura de wave-status => HELPER_FAILED", async () => {
  const input = parseOrThrow({ session_id: "synthetic-token-abc123" });

  const response = await handleOpenWave(input, {
    session: FAKE_SESSION,
    helperPath: join(FIXTURES_DIR, "fake-open-wave-status-fails.sh"),
  });

  assert.equal(response.outcome, "rejected");
  assert.equal(response.stage, "delegation");
  assert.match(response.reason ?? "", /HELPER_FAILED/);
});
