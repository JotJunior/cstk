// test/record_task.test.ts — cobertura da tool record_task: happy path,
// NO_OPEN_WAVE (precondicao imposta pela tool, nao pelo helper —
// NOTA DE CORRECAO EMPIRICA no arquivo fonte), WAVE_ID_NOT_FOUND (CHK016),
// SESSION_MISMATCH, schema (TESTS_PASSED_EXCEEDS_RUN, touched_files
// inseguro) e a classificacao de erro do helper (defesa em profundidade).

import { test } from "node:test";
import assert from "node:assert/strict";
import { join } from "node:path";
import {
  handleRecordTask,
  recordTaskInputSchema,
  type RecordTaskInput,
} from "../src/tools/record_task.js";
import type { ResolvedSession } from "../src/session/resolve.js";

const FIXTURES_DIR = join(process.cwd(), "test", "fixtures");
const inputSchema = recordTaskInputSchema;

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
  task_id: "3.6",
  outcome: "pass" as const,
};

function parseOrThrow(raw: unknown): RecordTaskInput {
  return inputSchema.parse(raw);
}

test("inputSchema: aceita payload minimo valido", () => {
  const parsed = inputSchema.safeParse(VALID_PAYLOAD);
  assert.equal(parsed.success, true);
});

test("inputSchema (SEC-M2): rejeita task_id comecando com '-'", () => {
  const parsed = inputSchema.safeParse({ ...VALID_PAYLOAD, task_id: "-rf" });
  assert.equal(parsed.success, false);
});

test("inputSchema: rejeita outcome fora do enum pass|fail", () => {
  const parsed = inputSchema.safeParse({ ...VALID_PAYLOAD, outcome: "bogus" });
  assert.equal(parsed.success, false);
});

test("inputSchema (SEC-M2): rejeita wave_id fora do formato onda-NNN", () => {
  const parsed = inputSchema.safeParse({ ...VALID_PAYLOAD, wave_id: "wave-1" });
  assert.equal(parsed.success, false);
});

test("inputSchema (TESTS_PASSED_EXCEEDS_RUN): rejeita tests_passed > tests_run", () => {
  const parsed = inputSchema.safeParse({ ...VALID_PAYLOAD, tests_run: 3, tests_passed: 5 });
  assert.equal(parsed.success, false);
});

test("inputSchema (SEC-M2): rejeita touched_files absoluto", () => {
  const parsed = inputSchema.safeParse({ ...VALID_PAYLOAD, touched_files: ["/etc/passwd"] });
  assert.equal(parsed.success, false);
});

test("inputSchema (SEC-M2): rejeita touched_files com traversal '..'", () => {
  const parsed = inputSchema.safeParse({ ...VALID_PAYLOAD, touched_files: ["../../etc/passwd"] });
  assert.equal(parsed.success, false);
});

test("inputSchema: aceita touched_files relativo valido", () => {
  const parsed = inputSchema.safeParse({
    ...VALID_PAYLOAD,
    touched_files: ["mcp/state-server/src/tools/record_task.ts"],
  });
  assert.equal(parsed.success, true);
});

test("handleRecordTask: happy path (onda aberta) delega e devolve tasks_total_count", async () => {
  const input = parseOrThrow(VALID_PAYLOAD);

  const response = await handleRecordTask(input, {
    session: FAKE_SESSION,
    helperPath: join(FIXTURES_DIR, "fake-record-task-ondas-open-ok.sh"),
  });

  assert.equal(response.outcome, "accepted");
  assert.equal(response.stage, null);
  assert.deepEqual(response.result, { task_id: "3.6", tasks_total_count: 19 });
});

test("handleRecordTask: session_id divergente => SESSION_MISMATCH, sem chamar o helper", async () => {
  const input = parseOrThrow({ ...VALID_PAYLOAD, session_id: "token-errado" });

  const response = await handleRecordTask(input, {
    session: FAKE_SESSION,
    helperPath: join(FIXTURES_DIR, "does-not-exist.sh"),
  });

  assert.equal(response.outcome, "rejected");
  assert.equal(response.stage, "precondition");
  assert.match(response.reason ?? "", /SESSION_MISMATCH/);
});

test("handleRecordTask: NO_OPEN_WAVE — precondicao imposta pela TOOL (helper real nao checa isso)", async () => {
  const input = parseOrThrow(VALID_PAYLOAD);

  const response = await handleRecordTask(input, {
    session: FAKE_SESSION,
    helperPath: join(FIXTURES_DIR, "fake-record-task-ondas-no-open-wave.sh"),
  });

  assert.equal(response.outcome, "rejected");
  assert.equal(response.stage, "precondition");
  assert.match(response.reason ?? "", /NO_OPEN_WAVE/);
});

test("handleRecordTask: WAVE_ID_NOT_FOUND (CHK016) — wave_id explicito que nao existe", async () => {
  const input = parseOrThrow({ ...VALID_PAYLOAD, wave_id: "onda-999" });

  const response = await handleRecordTask(input, {
    session: FAKE_SESSION,
    helperPath: join(FIXTURES_DIR, "fake-record-task-ondas-open-ok.sh"),
    stateRwHelperPath: join(FIXTURES_DIR, "fake-state-rw-waves-ids.sh"),
  });

  assert.equal(response.outcome, "rejected");
  assert.equal(response.stage, "precondition");
  assert.match(response.reason ?? "", /WAVE_ID_NOT_FOUND/);
});

test("handleRecordTask: wave_id explicito que EXISTE prossegue normalmente", async () => {
  const input = parseOrThrow({ ...VALID_PAYLOAD, wave_id: "onda-002" });

  const response = await handleRecordTask(input, {
    session: FAKE_SESSION,
    helperPath: join(FIXTURES_DIR, "fake-record-task-ondas-open-ok.sh"),
    stateRwHelperPath: join(FIXTURES_DIR, "fake-state-rw-waves-ids.sh"),
  });

  assert.equal(response.outcome, "accepted");
  assert.deepEqual(response.result, { task_id: "3.6", tasks_total_count: 19 });
});

test("handleRecordTask: helper rejeita por TESTS_PASSED_EXCEEDS_RUN (defesa em profundidade)", async () => {
  const input = parseOrThrow(VALID_PAYLOAD);

  const response = await handleRecordTask(input, {
    session: FAKE_SESSION,
    helperPath: join(FIXTURES_DIR, "fake-record-task-tests-exceed.sh"),
  });

  assert.equal(response.outcome, "rejected");
  assert.equal(response.stage, "delegation");
  assert.match(response.reason ?? "", /TESTS_PASSED_EXCEEDS_RUN/);
});
