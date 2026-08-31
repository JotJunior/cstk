// test/record_skill.test.ts — cobertura da tool record_skill: happy path,
// rejeicao de schema (SEC-M2), SESSION_MISMATCH e NO_OPEN_WAVE.
//
// Usa fixtures POSIX reais (execFile de verdade) via injecao de --helperPath
// em vez de mocks — mesma filosofia de test/resolve.test.ts.

import { test } from "node:test";
import assert from "node:assert/strict";
import { join } from "node:path";
import { z } from "zod";
import {
  handleRecordSkill,
  recordSkillInputShape,
  type RecordSkillInput,
} from "../src/tools/record_skill.js";
import type { ResolvedSession } from "../src/session/resolve.js";

const FIXTURES_DIR = join(process.cwd(), "test", "fixtures");
const inputSchema = z.object(recordSkillInputShape);

const FAKE_SESSION: ResolvedSession = {
  token: "synthetic-token-abc123",
  stateDir: "/data/state",
  executionKind: "feature-00c",
  shortName: "state-mcp-server",
  targetProjectPath: "/work",
  mode: "docker",
  container: "cstk-mcp-state-test",
};

function parseOrThrow(raw: unknown): RecordSkillInput {
  return inputSchema.parse(raw);
}

test("inputSchema: aceita payload minimo valido (skill + session_id)", () => {
  const parsed = inputSchema.safeParse({
    session_id: "synthetic-token-abc123",
    skill: "record_skill",
  });
  assert.equal(parsed.success, true);
});

test("inputSchema (SEC-M2): rejeita skill comecando com '-' (nao pode ser confundido com flag)", () => {
  const parsed = inputSchema.safeParse({
    session_id: "t",
    skill: "-rf",
  });
  assert.equal(parsed.success, false);
});

test("inputSchema (SEC-M2): rejeita decision_id fora do padrao dec-N", () => {
  const parsed = inputSchema.safeParse({
    session_id: "t",
    skill: "execute-task",
    decision_id: "not-a-decision-id",
  });
  assert.equal(parsed.success, false);
});

test("inputSchema: rejeita kind fora do enum fechado skill|gate", () => {
  const parsed = inputSchema.safeParse({
    session_id: "t",
    skill: "execute-task",
    kind: "bogus",
  });
  assert.equal(parsed.success, false);
});

test("handleRecordSkill: happy path delega ao helper e devolve skills_invoked_count", async () => {
  const input = parseOrThrow({
    session_id: "synthetic-token-abc123",
    skill: "execute-task",
    kind: "skill",
  });

  const response = await handleRecordSkill(input, {
    session: FAKE_SESSION,
    helperPath: join(FIXTURES_DIR, "fake-record-skill-ok.sh"),
  });

  assert.equal(response.outcome, "accepted");
  assert.equal(response.stage, null);
  assert.deepEqual(response.result, { skills_invoked_count: 4 });
});

test("handleRecordSkill: session_id divergente do token resolvido => SESSION_MISMATCH, sem chamar o helper", async () => {
  const input = parseOrThrow({
    session_id: "token-errado",
    skill: "execute-task",
  });

  const response = await handleRecordSkill(input, {
    session: FAKE_SESSION,
    // Helper inexistente de proposito: se o codigo chegasse a invoca-lo, o
    // teste falharia por ENOENT em vez de validar o fail-closed por
    // pre-condicao.
    helperPath: join(FIXTURES_DIR, "does-not-exist.sh"),
  });

  assert.equal(response.outcome, "rejected");
  assert.equal(response.stage, "precondition");
  assert.match(response.reason ?? "", /SESSION_MISMATCH/);
});

test("handleRecordSkill: helper sem onda aberta => NO_OPEN_WAVE, com reason sanitizado", async () => {
  const input = parseOrThrow({
    session_id: "synthetic-token-abc123",
    skill: "execute-task",
  });

  const response = await handleRecordSkill(input, {
    session: FAKE_SESSION,
    helperPath: join(FIXTURES_DIR, "fake-record-skill-no-open-wave.sh"),
  });

  assert.equal(response.outcome, "rejected");
  assert.equal(response.stage, "delegation");
  assert.match(response.reason ?? "", /NO_OPEN_WAVE/);
});

test("handleRecordSkill: saida nao numerica do helper => HELPER_FAILED (defensivo)", async () => {
  const input = parseOrThrow({
    session_id: "synthetic-token-abc123",
    skill: "execute-task",
  });

  const response = await handleRecordSkill(input, {
    session: FAKE_SESSION,
    helperPath: join(FIXTURES_DIR, "fake-record-skill-garbage.sh"),
  });

  assert.equal(response.outcome, "rejected");
  assert.equal(response.stage, "delegation");
  assert.match(response.reason ?? "", /HELPER_FAILED/);
});
