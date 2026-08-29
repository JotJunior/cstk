// test/bridge-client.test.ts — task 2.1.5.
//
// Mocka `fetch` via injecao de dependencia (`fetchImpl`) — nenhuma chamada
// de rede real. Cobre: create com sucesso, create degradado (200+degraded),
// create com timeout/5xx, poll 404, poll expired, guard de loopback.

import { test } from "node:test";
import assert from "node:assert/strict";
import {
  createBridgeClient,
  validatePanelUrl,
  resolvePanelUrl,
  DEFAULT_PANEL_URL,
  BRIDGE_CREATE_TIMEOUT_MS,
  BRIDGE_POLL_INTERVAL_MS,
  type CreateInterventionRequest,
} from "../src/bridge/client.js";

const BASE_REQ: CreateInterventionRequest = {
  projectPath: "/abs/path/do/projeto",
  project: "cstk",
  shortName: "human-bridge",
  executionKind: "feature-00c",
  kind: "choice",
  question: "prosseguir?",
  options: ["sim", "nao"],
  defaultValue: "nao",
  timeoutMs: 240000,
};

function jsonResponse(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

test("bridge-client: constantes de relogio tem os valores do contrato", () => {
  assert.equal(BRIDGE_CREATE_TIMEOUT_MS, 5000);
  assert.equal(BRIDGE_POLL_INTERVAL_MS, 1500);
});

test("bridge-client: resolvePanelUrl usa DEFAULT_PANEL_URL quando env ausente/vazia", () => {
  assert.equal(resolvePanelUrl({}), DEFAULT_PANEL_URL);
  assert.equal(resolvePanelUrl({ CSTK_PANEL_URL: "" }), DEFAULT_PANEL_URL);
  assert.equal(resolvePanelUrl({ CSTK_PANEL_URL: "http://127.0.0.1:9999" }), "http://127.0.0.1:9999");
});

test("bridge-client: createIntervention com sucesso (201)", async () => {
  const fetchImpl = (async (url: string | URL, init?: RequestInit) => {
    assert.equal(String(url), "http://x/api/v1/bridge/interventions");
    assert.equal(init?.method, "POST");
    const body = JSON.parse(String(init?.body));
    assert.equal(body.projectPath, BASE_REQ.projectPath);
    assert.equal(body.defaultValue, "nao");
    return jsonResponse(201, {
      data: { questionId: "q-abc123", expiresAt: "2026-08-29T18:34:00Z", state: "open" },
      meta: { degraded: false, reason: null },
    });
  }) as typeof fetch;

  const client = createBridgeClient("http://x", { fetchImpl });
  const outcome = await client.createIntervention(BASE_REQ);
  assert.deepEqual(outcome, {
    kind: "created",
    questionId: "q-abc123",
    expiresAt: "2026-08-29T18:34:00Z",
  });
});

test("bridge-client: createIntervention degradado (200+meta.degraded=true) vira unavailable", async () => {
  const fetchImpl = (async () =>
    jsonResponse(200, { data: null, meta: { degraded: true, reason: "bridge_unavailable" } })) as typeof fetch;

  const client = createBridgeClient("http://x", { fetchImpl });
  const outcome = await client.createIntervention(BASE_REQ);
  assert.equal(outcome.kind, "unavailable");
  if (outcome.kind === "unavailable") {
    assert.match(outcome.detail, /bridge_unavailable/);
  }
});

test("bridge-client: createIntervention com falha de rede/timeout vira unavailable", async () => {
  const fetchImpl = (async () => {
    throw new DOMException("The operation was aborted", "AbortError");
  }) as typeof fetch;

  const client = createBridgeClient("http://x", { fetchImpl });
  const outcome = await client.createIntervention(BASE_REQ);
  assert.equal(outcome.kind, "unavailable");
});

test("bridge-client: createIntervention com 5xx vira unavailable", async () => {
  const fetchImpl = (async () => jsonResponse(503, { data: null, meta: { degraded: false } })) as typeof fetch;

  const client = createBridgeClient("http://x", { fetchImpl });
  const outcome = await client.createIntervention(BASE_REQ);
  assert.equal(outcome.kind, "unavailable");
});

test("bridge-client: createIntervention com 201 sem data.questionId vira failed", async () => {
  const fetchImpl = (async () => jsonResponse(201, { data: {}, meta: { degraded: false } })) as typeof fetch;

  const client = createBridgeClient("http://x", { fetchImpl });
  const outcome = await client.createIntervention(BASE_REQ);
  assert.equal(outcome.kind, "failed");
});

test("bridge-client: pollIntervention 404 vira not_found (nunca unavailable)", async () => {
  const fetchImpl = (async () => new Response(null, { status: 404 })) as typeof fetch;

  const client = createBridgeClient("http://x", { fetchImpl });
  const outcome = await client.pollIntervention("q-desconhecido");
  assert.deepEqual(outcome, { kind: "not_found" });
});

test("bridge-client: pollIntervention state=expired", async () => {
  const fetchImpl = (async () =>
    jsonResponse(200, {
      data: { questionId: "q-1", state: "expired", appliedValue: null, untrustedText: null, resolvedAt: null },
      meta: {},
    })) as typeof fetch;

  const client = createBridgeClient("http://x", { fetchImpl });
  const outcome = await client.pollIntervention("q-1");
  assert.deepEqual(outcome, { kind: "expired" });
});

test("bridge-client: pollIntervention state=answered com untrustedText", async () => {
  const fetchImpl = (async () =>
    jsonResponse(200, {
      data: {
        questionId: "q-1",
        state: "answered",
        appliedValue: "sim",
        untrustedText: "texto corrigido",
        resolvedAt: "2026-08-29T18:35:00Z",
      },
      meta: {},
    })) as typeof fetch;

  const client = createBridgeClient("http://x", { fetchImpl });
  const outcome = await client.pollIntervention("q-1");
  assert.deepEqual(outcome, {
    kind: "answered",
    appliedValue: "sim",
    untrustedText: "texto corrigido",
  });
});

test("bridge-client: pollIntervention state=open", async () => {
  const fetchImpl = (async () =>
    jsonResponse(200, {
      data: { questionId: "q-1", state: "open", appliedValue: null, untrustedText: null, resolvedAt: null },
      meta: {},
    })) as typeof fetch;

  const client = createBridgeClient("http://x", { fetchImpl });
  const outcome = await client.pollIntervention("q-1");
  assert.deepEqual(outcome, { kind: "open" });
});

test("bridge-client: pollIntervention state=declined", async () => {
  const fetchImpl = (async () =>
    jsonResponse(200, {
      data: { questionId: "q-1", state: "declined", appliedValue: "default", untrustedText: null, resolvedAt: "x" },
      meta: {},
    })) as typeof fetch;

  const client = createBridgeClient("http://x", { fetchImpl });
  const outcome = await client.pollIntervention("q-1");
  assert.deepEqual(outcome, { kind: "declined" });
});

// --- validatePanelUrl (task 2.1.4) -----------------------------------------

test("validatePanelUrl: loopback (127.0.0.1) sempre OK", () => {
  assert.deepEqual(validatePanelUrl("http://127.0.0.1:5173", {}), { ok: true });
});

test("validatePanelUrl: loopback (::1) sempre OK", () => {
  assert.deepEqual(validatePanelUrl("http://[::1]:5173", {}), { ok: true });
});

test("validatePanelUrl: loopback (localhost) sempre OK", () => {
  assert.deepEqual(validatePanelUrl("http://localhost:5173", {}), { ok: true });
});

test("validatePanelUrl: host remoto SEM opt-in e recusado", () => {
  const result = validatePanelUrl("https://painel.example.com", {});
  assert.equal(result.ok, false);
});

test("validatePanelUrl: host remoto com http:// e SEMPRE recusado, mesmo com opt-in", () => {
  const result = validatePanelUrl("http://painel.example.com", {
    CSTK_PANEL_ALLOW_NONLOOPBACK: "1",
  });
  assert.equal(result.ok, false);
});

test("validatePanelUrl: host remoto com https:// + opt-in explicito e aceito", () => {
  const result = validatePanelUrl("https://painel.example.com", {
    CSTK_PANEL_ALLOW_NONLOOPBACK: "1",
  });
  assert.deepEqual(result, { ok: true });
});

test("validatePanelUrl: URL invalida e recusada", () => {
  const result = validatePanelUrl("nao-e-uma-url", {});
  assert.equal(result.ok, false);
});
