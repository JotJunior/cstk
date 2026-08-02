// test/register_human_block.test.ts — cobertura da tool
// register_human_block: happy path (efeito colateral execution_status
// verificado), schema (question < 20 chars, decision_id fora do padrao
// dec-N), SESSION_MISMATCH e DECISION_NOT_FOUND.

import { test } from "node:test";
import assert from "node:assert/strict";
import { join } from "node:path";
import { z } from "zod";
import {
  handleRegisterHumanBlock,
  registerHumanBlockInputShape,
  type RegisterHumanBlockInput,
} from "../src/tools/register_human_block.js";
import type { ResolvedSession } from "../src/session/resolve.js";

const FIXTURES_DIR = join(process.cwd(), "test", "fixtures");
const inputSchema = z.object(registerHumanBlockInputShape);

const FAKE_SESSION: ResolvedSession = {
  token: "synthetic-token-abc123",
  stateDir: "/data/state",
  executionKind: "feature-00c",
  shortName: "state-mcp-server",
  targetProjectPath: "/work",
  mode: "docker",
  container: "cstk-mcp-state-test",
};

const VALID_PAYLOAD = {
  session_id: "synthetic-token-abc123",
  decision_id: "dec-064",
  question: "Qual a leitura correta do carve-out para docker?",
  context_for_answer: "duas leituras possiveis, ver plan.md",
};

function parseOrThrow(raw: unknown): RegisterHumanBlockInput {
  return inputSchema.parse(raw);
}

test("inputSchema: aceita payload minimo valido", () => {
  const parsed = inputSchema.safeParse(VALID_PAYLOAD);
  assert.equal(parsed.success, true);
});

test("inputSchema: rejeita decision_id fora do padrao dec-N", () => {
  const parsed = inputSchema.safeParse({ ...VALID_PAYLOAD, decision_id: "not-a-decision" });
  assert.equal(parsed.success, false);
});

test("inputSchema (correcao empirica): rejeita question < 20 chars (helper real exige >= 20, nao min 1)", () => {
  const parsed = inputSchema.safeParse({ ...VALID_PAYLOAD, question: "curta demais" });
  assert.equal(parsed.success, false);
});

test("inputSchema: rejeita context_for_answer vazio", () => {
  const parsed = inputSchema.safeParse({ ...VALID_PAYLOAD, context_for_answer: "" });
  assert.equal(parsed.success, false);
});

test("handleRegisterHumanBlock: happy path devolve block_id + execution_status verificado", async () => {
  const input = parseOrThrow(VALID_PAYLOAD);

  const response = await handleRegisterHumanBlock(input, {
    session: FAKE_SESSION,
    helperPath: join(FIXTURES_DIR, "fake-register-human-block-ok.sh"),
  });

  assert.equal(response.outcome, "accepted");
  assert.equal(response.stage, null);
  assert.deepEqual(response.result, {
    block_id: "block-005",
    execution_status: "aguardando_humano",
  });
});

test("handleRegisterHumanBlock: session_id divergente => SESSION_MISMATCH, sem chamar o helper", async () => {
  const input = parseOrThrow({ ...VALID_PAYLOAD, session_id: "token-errado" });

  const response = await handleRegisterHumanBlock(input, {
    session: FAKE_SESSION,
    helperPath: join(FIXTURES_DIR, "does-not-exist.sh"),
  });

  assert.equal(response.outcome, "rejected");
  assert.equal(response.stage, "precondition");
  assert.match(response.reason ?? "", /SESSION_MISMATCH/);
});

test("handleRegisterHumanBlock: DECISION_NOT_FOUND quando decisao referenciada nao existe", async () => {
  const input = parseOrThrow(VALID_PAYLOAD);

  const response = await handleRegisterHumanBlock(input, {
    session: FAKE_SESSION,
    helperPath: join(FIXTURES_DIR, "fake-register-human-block-decision-not-found.sh"),
  });

  assert.equal(response.outcome, "rejected");
  assert.equal(response.stage, "delegation");
  assert.match(response.reason ?? "", /DECISION_NOT_FOUND/);
});
