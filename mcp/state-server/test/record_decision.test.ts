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

// structural-decision-human-gate FASE 4 (task 4.3.1): R1..R3 rejeitadas no
// superRefine (barreira 1, ANTES de qualquer chamada ao helper — nenhum
// stage="delegation" e alcancado nestes cenarios). R6 depende de estado
// (INV-M4) e so e testavel via handleRecordDecision + fixture (abaixo).

test("inputSchema (R1/STRUCTURAL_CLASS_REQUIRED): opcao 'pause-humano' sem decision_class e rejeitada", () => {
  const parsed = inputSchema.safeParse({
    ...VALID_PAYLOAD,
    options_considered: ["pause-humano", "prosseguir"],
    choice: "pause-humano",
    justification_score: 0,
  });
  assert.equal(parsed.success, false);
});

test("inputSchema (R1): token 'bloqueio-humano*' avaliado pelo ROTULO quando a opcao e objeto (#141)", () => {
  const parsed = inputSchema.safeParse({
    ...VALID_PAYLOAD,
    options_considered: [{ rotulo: "bloqueio-humano-eixo-stack" }, "prosseguir"],
    choice: "bloqueio-humano-eixo-stack",
    justification_score: 0,
  });
  assert.equal(parsed.success, false);
});

test("inputSchema (R1): opcao de bloqueio humano COM decision_class presente e aceita (nao dispara R1)", () => {
  const parsed = inputSchema.safeParse({
    ...VALID_PAYLOAD,
    options_considered: ["pause-humano", "prosseguir"],
    choice: "pause-humano",
    justification_score: 0,
    decision_class: "estrutural",
    structural_axis: "stack-frameworks",
  });
  assert.equal(parsed.success, true);
});

test("inputSchema (R3/STRUCTURAL_AXIS_INVALID): decision_class=estrutural sem structural_axis e rejeitada", () => {
  const parsed = inputSchema.safeParse({
    ...VALID_PAYLOAD,
    decision_class: "estrutural",
    choice: "pause-humano",
    justification_score: 0,
  });
  assert.equal(parsed.success, false);
});

test("inputSchema (R3): decision_class fora do enum {estrutural,operacional} e rejeitada pelo proprio zod", () => {
  const parsed = inputSchema.safeParse({
    ...VALID_PAYLOAD,
    decision_class: "outra-coisa",
  });
  assert.equal(parsed.success, false);
});

test("inputSchema (R2/STRUCTURAL_REQUIRES_HUMAN_BLOCK): estrutural sem consentimento e com choice fora da familia de bloqueio e rejeitada", () => {
  const parsed = inputSchema.safeParse({
    ...VALID_PAYLOAD,
    decision_class: "estrutural",
    structural_axis: "stack-frameworks",
    choice: "usar-typescript",
    justification_score: 2,
  });
  assert.equal(parsed.success, false);
});

test("inputSchema (R2): estrutural sem consentimento e com score != 0 e rejeitada mesmo com choice de bloqueio", () => {
  const parsed = inputSchema.safeParse({
    ...VALID_PAYLOAD,
    decision_class: "estrutural",
    structural_axis: "stack-frameworks",
    choice: "pause-humano",
    justification_score: 2,
  });
  assert.equal(parsed.success, false);
});

test("inputSchema (R2): estrutural COM human_consent_block_id valido dispensa a familia de bloqueio/score 0 (R2 nao se aplica)", () => {
  const parsed = inputSchema.safeParse({
    ...VALID_PAYLOAD,
    decision_class: "estrutural",
    structural_axis: "stack-frameworks",
    choice: "usar-typescript",
    justification_score: 2,
    human_consent_block_id: "block-007",
  });
  assert.equal(parsed.success, true);
});

test("inputSchema: human_consent_block_id fora do formato block-NNN e rejeitado (INV-M4: so forma)", () => {
  const parsed = inputSchema.safeParse({
    ...VALID_PAYLOAD,
    decision_class: "estrutural",
    structural_axis: "stack-frameworks",
    choice: "usar-typescript",
    justification_score: 2,
    human_consent_block_id: "not-a-block-id",
  });
  assert.equal(parsed.success, false);
});

test("inputSchema: decisao estrutural completa e valida (classe+eixo+bloqueio) e aceita", () => {
  const parsed = inputSchema.safeParse({
    ...VALID_PAYLOAD,
    decision_class: "estrutural",
    structural_axis: "persistencia",
    choice: "usar-postgres",
    justification_score: 2,
    human_consent_block_id: "block-042",
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

// structural-decision-human-gate FASE 4 (task 4.3.1): R6 depende de estado
// (bloqueio existe? pertence a esta execucao? status=respondido? mesmo
// subject_key do eixo?) — o schema NAO le estado (INV-M4), entao so o
// helper (via classifyHelperError) pode rejeitar. Payload valido no schema
// (decision_class=estrutural + structural_axis + human_consent_block_id
// bem-formado) chega ao handler; quem rejeita e o helper fake.
const STRUCTURAL_PAYLOAD_WITH_CONSENT = {
  ...VALID_PAYLOAD,
  decision_class: "estrutural" as const,
  structural_axis: "persistencia",
  choice: "usar-postgres",
  justification_score: 2 as const,
  human_consent_block_id: "block-999",
};

test("handleRecordDecision: helper rejeita por HUMAN_CONSENT_INVALID (R6 — bloqueio inexistente/outra execucao/aguardando)", async () => {
  const input = parseOrThrow(STRUCTURAL_PAYLOAD_WITH_CONSENT);

  const response = await handleRecordDecision(input, {
    session: FAKE_SESSION,
    helperPath: join(FIXTURES_DIR, "fake-record-decision-consent-invalid.sh"),
  });

  assert.equal(response.outcome, "rejected");
  assert.equal(response.stage, "delegation");
  assert.match(response.reason ?? "", /HUMAN_CONSENT_INVALID/);
});

test("handleRecordDecision: helper rejeita por HUMAN_CONSENT_INVALID (R6 — consentimento de outro assunto)", async () => {
  const input = parseOrThrow(STRUCTURAL_PAYLOAD_WITH_CONSENT);

  const response = await handleRecordDecision(input, {
    session: FAKE_SESSION,
    helperPath: join(FIXTURES_DIR, "fake-record-decision-consent-wrong-subject.sh"),
  });

  assert.equal(response.outcome, "rejected");
  assert.equal(response.stage, "delegation");
  assert.match(response.reason ?? "", /HUMAN_CONSENT_INVALID/);
});

test("handleRecordDecision: decisao estrutural com consentimento valido delega ao helper e devolve decision_id (happy path)", async () => {
  const input = parseOrThrow(STRUCTURAL_PAYLOAD_WITH_CONSENT);

  const response = await handleRecordDecision(input, {
    session: FAKE_SESSION,
    helperPath: join(FIXTURES_DIR, "fake-record-decision-ok.sh"),
  });

  assert.equal(response.outcome, "accepted");
  assert.deepEqual(response.result, { decision_id: "dec-042" });
});
