// test/record_decision.test.ts — cobertura da tool record_decision: happy
// path, rejeicoes de schema (FR-002: context/rationale < 20 chars, evidence
// ausente com score 3, constitution-conflict), SESSION_MISMATCH e a
// classificacao de erro do helper (defesa em profundidade, chamando o
// handler DIRETO sem passar pelo schema).

import { test } from "node:test";
import assert from "node:assert/strict";
import { join } from "node:path";
import {
  handleRecordDecision,
  recordDecisionInputSchema,
  type RecordDecisionInput,
} from "../src/tools/record_decision.js";
import type { ResolvedSession } from "../src/session/resolve.js";

const FIXTURES_DIR = join(process.cwd(), "test", "fixtures");
const inputSchema = recordDecisionInputSchema;

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
  agent: "agente-00c-feature-orchestrator",
  stage: "execute-task",
  context: "contexto com pelo menos vinte caracteres",
  options_considered: ["a", "b"],
  choice: "a",
  rationale: "justificativa com pelo menos vinte caracteres",
};

test("inputSchema: aceita payload minimo valido", () => {
  const parsed = inputSchema.safeParse(VALID_PAYLOAD);
  assert.equal(parsed.success, true);
});

test("inputSchema (FR-002): rejeita context < 20 chars", () => {
  const parsed = inputSchema.safeParse({ ...VALID_PAYLOAD, context: "curto" });
  assert.equal(parsed.success, false);
});

test("inputSchema (FR-002): rejeita rationale < 20 chars", () => {
  const parsed = inputSchema.safeParse({ ...VALID_PAYLOAD, rationale: "curto" });
  assert.equal(parsed.success, false);
});

test("inputSchema (FR-002): rejeita options_considered vazio", () => {
  const parsed = inputSchema.safeParse({ ...VALID_PAYLOAD, options_considered: [] });
  assert.equal(parsed.success, false);
});

// Issue #141: paridade com state-decisions.sh — opcoes estruturadas
// {rotulo, descricao} (formato do clarify-asker) sao aceitas; forma invalida
// (objeto sem rotulo, string vazia, numero) e rejeitada no schema.
test("inputSchema (#141): aceita opcoes estruturadas {rotulo, descricao} misturadas com strings", () => {
  const parsed = inputSchema.safeParse({
    ...VALID_PAYLOAD,
    options_considered: [{ rotulo: "A", descricao: "opcao A" }, "B", { label: "C" }],
  });
  assert.equal(parsed.success, true);
});

test("inputSchema (#141): rejeita objeto sem rotulo/label, string vazia e numero", () => {
  for (const bad of [[{ descricao: "sem rotulo" }], [""], [1], [null]]) {
    const parsed = inputSchema.safeParse({ ...VALID_PAYLOAD, options_considered: bad });
    assert.equal(parsed.success, false, `deveria rejeitar ${JSON.stringify(bad)}`);
  }
});

test("inputSchema (#141): objeto com rotulo igual a opcao canonica NAO dispara CONSTITUTION_CONFLICT_SCORE", () => {
  const parsed = inputSchema.safeParse({
    ...VALID_PAYLOAD,
    options_considered: [
      { rotulo: "atualizar-global-via-bump-SemVer" },
      { rotulo: "criar-feature-delta-com-sync-impact-report" },
      { rotulo: "abortar-feature-sem-principios-proprios" },
    ],
    justification_score: 2,
  });
  assert.equal(parsed.success, true);
});

test("inputSchema (EVIDENCE_REQUIRED): score 3 sem evidence e rejeitado", () => {
  const parsed = inputSchema.safeParse({ ...VALID_PAYLOAD, justification_score: 3 });
  assert.equal(parsed.success, false);
});

test("inputSchema (EVIDENCE_REQUIRED): score 3 com evidence < 20 chars e rejeitado", () => {
  const parsed = inputSchema.safeParse({
    ...VALID_PAYLOAD,
    justification_score: 3,
    evidence: "curto",
  });
  assert.equal(parsed.success, false);
});

test("inputSchema: score 3 com evidence >= 20 chars e aceito", () => {
  const parsed = inputSchema.safeParse({
    ...VALID_PAYLOAD,
    justification_score: 3,
    evidence: "comando rodado + output literal aqui",
  });
  assert.equal(parsed.success, true);
});

test("inputSchema (CONSTITUTION_CONFLICT_SCORE): as 3 opcoes canonicas com score != 0 sao rejeitadas", () => {
  const parsed = inputSchema.safeParse({
    ...VALID_PAYLOAD,
    options_considered: [
      "atualizar-global-via-bump-SemVer",
      "criar-feature-delta-com-sync-impact-report",
      "abortar-feature-sem-principios-proprios",
    ],
    justification_score: 2,
  });
  assert.equal(parsed.success, false);
});

test("inputSchema (CONSTITUTION_CONFLICT_SCORE): as 3 opcoes canonicas com score == 0 sao aceitas", () => {
  const parsed = inputSchema.safeParse({
    ...VALID_PAYLOAD,
    options_considered: [
      "atualizar-global-via-bump-SemVer",
      "criar-feature-delta-com-sync-impact-report",
      "abortar-feature-sem-principios-proprios",
    ],
    justification_score: 0,
    choice: "pause-humano",
  });
  assert.equal(parsed.success, true);
});

function parseOrThrow(raw: unknown): RecordDecisionInput {
  return inputSchema.parse(raw);
}

test("handleRecordDecision: happy path delega ao helper e devolve decision_id", async () => {
  const input = parseOrThrow(VALID_PAYLOAD);

  const response = await handleRecordDecision(input, {
    session: FAKE_SESSION,
    helperPath: join(FIXTURES_DIR, "fake-record-decision-ok.sh"),
  });

  assert.equal(response.outcome, "accepted");
  assert.equal(response.stage, null);
  assert.deepEqual(response.result, { decision_id: "dec-042" });
});

test("handleRecordDecision: session_id divergente => SESSION_MISMATCH, sem chamar o helper", async () => {
  const input = parseOrThrow({ ...VALID_PAYLOAD, session_id: "token-errado" });

  const response = await handleRecordDecision(input, {
    session: FAKE_SESSION,
    helperPath: join(FIXTURES_DIR, "does-not-exist.sh"),
  });

  assert.equal(response.outcome, "rejected");
  assert.equal(response.stage, "precondition");
  assert.match(response.reason ?? "", /SESSION_MISMATCH/);
});

test("handleRecordDecision: helper rejeita por EVIDENCE_REQUIRED (defesa em profundidade)", async () => {
  const input = parseOrThrow(VALID_PAYLOAD);

  const response = await handleRecordDecision(input, {
    session: FAKE_SESSION,
    helperPath: join(FIXTURES_DIR, "fake-record-decision-evidence-required.sh"),
  });

  assert.equal(response.outcome, "rejected");
  assert.equal(response.stage, "delegation");
  assert.match(response.reason ?? "", /EVIDENCE_REQUIRED/);
});

test("handleRecordDecision: helper rejeita por CONSTITUTION_CONFLICT_SCORE (defesa em profundidade)", async () => {
  const input = parseOrThrow(VALID_PAYLOAD);

  const response = await handleRecordDecision(input, {
    session: FAKE_SESSION,
    helperPath: join(FIXTURES_DIR, "fake-record-decision-constitution-conflict.sh"),
  });

  assert.equal(response.outcome, "rejected");
  assert.equal(response.stage, "delegation");
  assert.match(response.reason ?? "", /CONSTITUTION_CONFLICT_SCORE/);
});
