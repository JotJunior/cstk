// test/ask_operator.test.ts — task 2.2.6. Cobre os 5 outcomes do
// mapeamento sinal->desfecho (contrato §5), C-4 (default_value aplicado em
// TODO desfecho != answered, persistido ANTES do retorno), C-1 (nenhum
// desfecho e erro de tool) e SESSION_MISMATCH fail-closed.
//
// `bridgeClient` e injetado (fake em memoria, sem HTTP real — cobertura de
// bridge/client.ts em si vive em bridge-client.test.ts). `stateRwHelperPath`
// aponta para a fixture POSIX real que captura o `--value` do `set`.

import { test } from "node:test";
import assert from "node:assert/strict";
import { join } from "node:path";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import {
  handleAskOperator,
  askOperatorInputSchema,
  pollUntilResolved,
  AskOperatorServerTimeoutError,
  type AskOperatorInput,
} from "../src/tools/ask_operator.js";
import type {
  BridgeClient,
  CreateInterventionOutcome,
  PollInterventionOutcome,
} from "../src/bridge/client.js";
import type { ResolvedSession } from "../src/session/resolve.js";

const FIXTURES_DIR = join(process.cwd(), "test", "fixtures");
const STATE_RW_CAPTURE = join(FIXTURES_DIR, "fake-ask-operator-state-rw-captures-set.sh");

const FAKE_SESSION: ResolvedSession = {
  token: "synthetic-token-abc123",
  stateDir: "/data/state",
  executionKind: "feature-00c",
  shortName: "human-bridge",
  targetProjectPath: "/work/cstk",
  mode: "direct",
  container: "-",
};

const VALID_CHOICE_INPUT = {
  session_id: "synthetic-token-abc123",
  question: "prosseguir com o deploy?",
  kind: "choice" as const,
  options: ["sim", "nao"],
  default_value: "nao",
};

function parseOrThrow(raw: unknown): AskOperatorInput {
  return askOperatorInputSchema.parse(raw);
}

/** Cliente fake que sempre cria com sucesso e resolve o polling na 1a chamada. */
function fakeClient(overrides: Partial<BridgeClient> = {}): BridgeClient {
  return {
    generateLocalQuestionId: () => "local-q-fake",
    createIntervention: async () => ({
      kind: "created",
      questionId: "q-real-1",
      expiresAt: "2026-08-29T19:00:00Z",
    }),
    pollIntervention: async () => ({ kind: "answered", appliedValue: "sim", untrustedText: null }),
    ...overrides,
  };
}

// `runHelper` (runtime/exec.ts) invoca `execFile` SEM opcao `env` — o
// child SEMPRE herda o `process.env` REAL do processo de teste, nunca o
// objeto `env` passado como dependencia da tool (esse so alimenta a
// logica JS do handler, ex.: `resolvePanelUrl`). Por isso a fixture le
// `FAKE_SET_VALUE_FILE` do `process.env` de verdade — mesmo padrao ja
// usado por collect_optins.test.ts.
async function withCaptureFile(fn: (setValueFile: string) => Promise<void>): Promise<void> {
  const dir = await mkdtemp(join(tmpdir(), "ask-operator-test-"));
  const setValueFile = join(dir, "captured-set-values.txt");
  const original = process.env.FAKE_SET_VALUE_FILE;
  process.env.FAKE_SET_VALUE_FILE = setValueFile;
  try {
    await fn(setValueFile);
  } finally {
    if (original === undefined) delete process.env.FAKE_SET_VALUE_FILE;
    else process.env.FAKE_SET_VALUE_FILE = original;
    await rm(dir, { recursive: true, force: true });
  }
}

async function lastPersistedEntry(setValueFile: string): Promise<Record<string, unknown>> {
  const content = await readFile(setValueFile, "utf8");
  const lines = content.trim().split("\n");
  const arr = JSON.parse(lines[lines.length - 1] ?? "[]") as Array<Record<string, unknown>>;
  return arr[arr.length - 1] ?? {};
}

// --- inputSchema -------------------------------------------------------

test("inputSchema: aceita payload minimo valido (kind=choice)", () => {
  const parsed = askOperatorInputSchema.safeParse(VALID_CHOICE_INPUT);
  assert.equal(parsed.success, true);
});

test("inputSchema: kind=choice SEM options e rejeitado", () => {
  const parsed = askOperatorInputSchema.safeParse({
    ...VALID_CHOICE_INPUT,
    options: undefined,
  });
  assert.equal(parsed.success, false);
});

test("inputSchema: kind=confirm COM options e rejeitado (options so em choice)", () => {
  const parsed = askOperatorInputSchema.safeParse({
    session_id: "tok",
    question: "confirma?",
    kind: "confirm",
    options: ["yes", "no"],
    default_value: "no",
  });
  assert.equal(parsed.success, false);
});

test("inputSchema: kind=text sem options e valido", () => {
  const parsed = askOperatorInputSchema.safeParse({
    session_id: "tok",
    question: "corrija o valor:",
    kind: "text",
    default_value: "N/A",
  });
  assert.equal(parsed.success, true);
});

test("inputSchema: default_value ausente e rejeitado (C-4)", () => {
  const parsed = askOperatorInputSchema.safeParse({
    session_id: "tok",
    question: "confirma?",
    kind: "confirm",
    default_value: "",
  });
  assert.equal(parsed.success, false);
});

// --- SESSION_MISMATCH (precondicao) ------------------------------------

test("handleAskOperator: session_id divergente => SESSION_MISMATCH, sem chamar o cliente HTTP", async () => {
  let called = false;
  const client = fakeClient({
    createIntervention: async () => {
      called = true;
      return { kind: "created", questionId: "q", expiresAt: "x" };
    },
  });
  const input = parseOrThrow({ ...VALID_CHOICE_INPUT, session_id: "token-errado" });
  const res = await handleAskOperator(input, {
    session: FAKE_SESSION,
    env: {},
    bridgeClient: client,
    stateRwHelperPath: STATE_RW_CAPTURE,
  });
  assert.equal(res.outcome, "rejected");
  assert.equal(res.stage, "precondition");
  assert.ok((res.reason ?? "").startsWith("SESSION_MISMATCH:"));
  assert.equal(called, false, "cliente HTTP nao deveria ser chamado antes da resolucao de sessao");
});

// --- Os 5 outcomes do mapeamento sinal -> desfecho (contrato §5) -------

test("handleAskOperator: outcome=answered — C-1 (accepted), applied_value do operador, untrusted_text so em kind=text", async () => {
  await withCaptureFile(async (setValueFile) => {
    const client = fakeClient();
    const res = await handleAskOperator(parseOrThrow(VALID_CHOICE_INPUT), {
      session: FAKE_SESSION,
      env: {},
      bridgeClient: client,
      stateRwHelperPath: STATE_RW_CAPTURE,
    });
    assert.equal(res.outcome, "accepted");
    assert.equal(res.result?.outcome, "answered");
    assert.equal(res.result?.applied_value, "sim");
    assert.equal(res.result?.channel, "panel");
    assert.equal(res.result?.untrusted_text, null, "kind=choice nunca carrega untrusted_text");
  });
});

test("handleAskOperator: outcome=declined — C-4 aplica default_value", async () => {
  await withCaptureFile(async (setValueFile) => {
    const client = fakeClient({ pollIntervention: async () => ({ kind: "declined" }) });
    const res = await handleAskOperator(parseOrThrow(VALID_CHOICE_INPUT), {
      session: FAKE_SESSION,
      env: {},
      bridgeClient: client,
      stateRwHelperPath: STATE_RW_CAPTURE,
    });
    assert.equal(res.outcome, "accepted");
    assert.equal(res.result?.outcome, "declined");
    assert.equal(res.result?.applied_value, "nao");
  });
});

test("handleAskOperator: outcome=timeout (state=expired) — C-4 aplica default_value", async () => {
  await withCaptureFile(async (setValueFile) => {
    const client = fakeClient({ pollIntervention: async () => ({ kind: "expired" }) });
    const res = await handleAskOperator(parseOrThrow(VALID_CHOICE_INPUT), {
      session: FAKE_SESSION,
      env: {},
      bridgeClient: client,
      stateRwHelperPath: STATE_RW_CAPTURE,
    });
    assert.equal(res.outcome, "accepted");
    assert.equal(res.result?.outcome, "timeout");
    assert.equal(res.result?.applied_value, "nao");
  });
});

test("handleAskOperator: outcome=unavailable (criacao falhou) — C-4 aplica default_value, sem chamar poll", async () => {
  await withCaptureFile(async (setValueFile) => {
    let polled = false;
    const client = fakeClient({
      createIntervention: async () => ({ kind: "unavailable", detail: "ECONNREFUSED" }),
      pollIntervention: async () => {
        polled = true;
        return { kind: "open" };
      },
    });
    const res = await handleAskOperator(parseOrThrow(VALID_CHOICE_INPUT), {
      session: FAKE_SESSION,
      env: {},
      bridgeClient: client,
      stateRwHelperPath: STATE_RW_CAPTURE,
    });
    assert.equal(res.outcome, "accepted");
    assert.equal(res.result?.outcome, "unavailable");
    assert.equal(res.result?.applied_value, "nao");
    assert.equal(polled, false, "poll nao deveria ser chamado quando a criacao falhou");
  });
});

test("handleAskOperator: outcome=failed (poll 404 not_found) — C-4 aplica default_value", async () => {
  await withCaptureFile(async (setValueFile) => {
    const client = fakeClient({ pollIntervention: async () => ({ kind: "not_found" }) });
    const res = await handleAskOperator(parseOrThrow(VALID_CHOICE_INPUT), {
      session: FAKE_SESSION,
      env: {},
      bridgeClient: client,
      stateRwHelperPath: STATE_RW_CAPTURE,
    });
    assert.equal(res.outcome, "accepted");
    assert.equal(res.result?.outcome, "failed");
    assert.equal(res.result?.applied_value, "nao");
  });
});

test("handleAskOperator: outcome=failed (excecao inesperada na criacao) — nunca propaga, C-1 preservado", async () => {
  await withCaptureFile(async (setValueFile) => {
    const client = fakeClient({
      createIntervention: async () => {
        throw new Error("boom");
      },
    });
    const res = await handleAskOperator(parseOrThrow(VALID_CHOICE_INPUT), {
      session: FAKE_SESSION,
      env: {},
      bridgeClient: client,
      stateRwHelperPath: STATE_RW_CAPTURE,
    });
    assert.equal(res.outcome, "accepted");
    assert.equal(res.result?.outcome, "failed");
    assert.equal(res.result?.applied_value, "nao");
  });
});

// --- C-4: persistencia ANTES do retorno, em TODO desfecho --------------

test("handleAskOperator (C-4/task 2.4.2): .operator_answers[] persistido com os 8 campos do contrato", async () => {
  await withCaptureFile(async (setValueFile) => {
    const client = fakeClient();
    await handleAskOperator(parseOrThrow(VALID_CHOICE_INPUT), {
      session: FAKE_SESSION,
      env: {},
      bridgeClient: client,
      stateRwHelperPath: STATE_RW_CAPTURE,
      clientTimeoutMs: 300000,
    });
    const entry = await lastPersistedEntry(setValueFile);
    assert.deepEqual(
      Object.keys(entry).sort(),
      [
        "applied_value",
        "channel",
        "effective_timeout_ms",
        "outcome",
        "question_id",
        "reason",
        "recorded_at",
        "untrusted_text",
      ].sort(),
    );
    assert.equal(entry.question_id, "q-real-1");
    assert.equal(entry.channel, "panel");
    assert.equal(entry.outcome, "answered");
    assert.equal(entry.applied_value, "sim");
    assert.equal(typeof entry.effective_timeout_ms, "number");
  });
});

test("handleAskOperator (C-4): grava ANTES do retorno mesmo em outcome=unavailable (create falhou)", async () => {
  await withCaptureFile(async (setValueFile) => {
    const client = fakeClient({
      createIntervention: async () => ({ kind: "unavailable", detail: "sem conexao" }),
    });
    await handleAskOperator(parseOrThrow(VALID_CHOICE_INPUT), {
      session: FAKE_SESSION,
      env: {},
      bridgeClient: client,
      stateRwHelperPath: STATE_RW_CAPTURE,
    });
    const entry = await lastPersistedEntry(setValueFile);
    assert.equal(entry.outcome, "unavailable");
    assert.equal(entry.applied_value, "nao");
    assert.equal(typeof entry.question_id, "string");
    assert.ok((entry.question_id as string).length > 0, "questionId LOCAL ainda assim gravado (NOT NULL)");
  });
});

test("handleAskOperator: falha ao PERSISTIR (helper indisponivel) NUNCA vira rejeicao de tool (best-effort)", async () => {
  const client = fakeClient();
  const res = await handleAskOperator(parseOrThrow(VALID_CHOICE_INPUT), {
    session: FAKE_SESSION,
    env: {},
    bridgeClient: client,
    stateRwHelperPath: join(FIXTURES_DIR, "does-not-exist.sh"),
  });
  assert.equal(res.outcome, "accepted");
  assert.equal(res.result?.outcome, "answered");
});

// --- kind=text: untrusted_text em campo proprio (R-TEXT-1) --------------

test("handleAskOperator: kind=text + answered devolve untrusted_text em campo proprio, applied_value = token", async () => {
  await withCaptureFile(async (setValueFile) => {
    const client = fakeClient({
      pollIntervention: async () => ({
        kind: "answered",
        appliedValue: "corrected",
        untrustedText: "route.path deveria ser /v2/orders",
      }),
    });
    const input = parseOrThrow({
      session_id: "synthetic-token-abc123",
      question: "corrija o payload:",
      kind: "text",
      default_value: "N/A",
    });
    const res = await handleAskOperator(input, {
      session: FAKE_SESSION,
      env: {},
      bridgeClient: client,
      stateRwHelperPath: STATE_RW_CAPTURE,
    });
    assert.equal(res.result?.applied_value, "corrected");
    assert.equal(res.result?.untrusted_text, "route.path deveria ser /v2/orders");

    const entry = await lastPersistedEntry(setValueFile);
    assert.equal(entry.untrusted_text, "route.path deveria ser /v2/orders");
  });
});

// --- R-CLOCK-3: teto do SERVIDOR estoura ANTES do painel responder ------

test("pollUntilResolved: teto do SERVIDOR estourando lanca AskOperatorServerTimeoutError (R-CLOCK-3)", async () => {
  let ticks = 0;
  const client = fakeClient({
    pollIntervention: async () => {
      ticks += 1;
      return { kind: "open" };
    },
  });
  // Relogio fake: cada chamada de now() avanca 1000ms; deadline = 3000ms.
  let virtualNow = 0;
  const now = () => virtualNow;
  const sleep = async (ms: number) => {
    virtualNow += ms;
  };

  await assert.rejects(
    () => pollUntilResolved(client, "q-1", 3000, 1000, now, sleep),
    AskOperatorServerTimeoutError,
  );
  assert.ok(ticks >= 1);
});

test("handleAskOperator: teto do SERVIDOR estourando vira outcome=timeout (nunca propaga a excecao para o SDK)", async () => {
  await withCaptureFile(async (setValueFile) => {
    let virtualNow = 0;
    const client = fakeClient({ pollIntervention: async () => ({ kind: "open" }) });
    const res = await handleAskOperator(parseOrThrow(VALID_CHOICE_INPUT), {
      session: FAKE_SESSION,
      env: {},
      bridgeClient: client,
      stateRwHelperPath: STATE_RW_CAPTURE,
      clientTimeoutMs: 300000,
      now: () => virtualNow,
      sleep: async (ms: number) => {
        virtualNow += ms;
      },
      pollIntervalMs: 1000,
    });
    assert.equal(res.outcome, "accepted", "C-1: timeout NUNCA e erro de tool");
    assert.equal(res.result?.outcome, "timeout");
    assert.equal(res.result?.applied_value, "nao");
  });
});

// --- validatePanelUrl integrado ao handler (CSTK_PANEL_URL fora de loopback) ---

test("handleAskOperator: CSTK_PANEL_URL fora de loopback sem opt-in -> outcome=failed, sem chamar o cliente HTTP", async () => {
  await withCaptureFile(async (setValueFile) => {
    let called = false;
    const client = fakeClient({
      createIntervention: async () => {
        called = true;
        return { kind: "created", questionId: "q", expiresAt: "x" };
      },
    });
    const res = await handleAskOperator(parseOrThrow(VALID_CHOICE_INPUT), {
      session: FAKE_SESSION,
      env: {
        FAKE_SET_VALUE_FILE: setValueFile,
        CSTK_PANEL_URL: "https://painel.example.com",
      } as unknown as NodeJS.ProcessEnv,
      bridgeClient: client,
      stateRwHelperPath: STATE_RW_CAPTURE,
    });
    assert.equal(res.outcome, "accepted");
    assert.equal(res.result?.outcome, "failed");
    assert.equal(called, false);
  });
});
