// test/collect_optins.test.ts — cobertura da tool collect_optins (task
// 3.1.6): os 6 desfechos de campo (accepted/declined/absent/timeout/
// unavailable/failed) + os 2 erros de precondicao (SESSION_MISMATCH aqui;
// TOOL_CALL_LIMIT_EXCEEDED e coberto no nivel de index.ts/call-limit.test.ts,
// compartilhado por todas as tools) + cap M6 + allowlist do mapper (3.4.2) +
// Invariante C-2 (--allow-downgrade condicional).

import { test } from "node:test";
import assert from "node:assert/strict";
import { join } from "node:path";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { z } from "zod";
import { McpError, ErrorCode } from "@modelcontextprotocol/sdk/types.js";
import {
  handleCollectOptins,
  collectOptinsInputShape,
  parseElicitTimeoutMs,
  type CollectOptinsInput,
  type ElicitationServer,
} from "../src/tools/collect_optins.js";
import type { ResolvedSession } from "../src/session/resolve.js";

const FIXTURES_DIR = join(process.cwd(), "test", "fixtures");
const inputSchema = z.object(collectOptinsInputShape);

const FEATURE_SESSION: ResolvedSession = {
  token: "synthetic-token-abc123",
  stateDir: "/data/state",
  executionKind: "feature-00c",
  shortName: "mcp-elicitation-optins",
  targetProjectPath: "/work",
  mode: "docker",
  container: "cstk-mcp-state-test",
};

const AGENTE_SESSION: ResolvedSession = { ...FEATURE_SESSION, executionKind: "agente-00c" };

function parseOrThrow(raw: unknown): CollectOptinsInput {
  return inputSchema.parse(raw);
}

function deliveryTierHelper(name: string): string {
  return join(FIXTURES_DIR, name);
}

const EMPTY_STATE_RW = deliveryTierHelper("fake-collect-optins-state-rw-empty.sh");
const COMMIT_MODE_OK = deliveryTierHelper("fake-collect-optins-commit-mode-ok.sh");
const ROADMAP_MODE_OK = deliveryTierHelper("fake-collect-optins-roadmap-mode-ok.sh");
const DELIVERY_TIER_OK = deliveryTierHelper("fake-collect-optins-delivery-tier-ok.sh");

function baseDeps(elicitationServer: ElicitationServer) {
  return {
    session: FEATURE_SESSION,
    elicitationServer,
    stateRwHelperPath: EMPTY_STATE_RW,
    commitModeHelperPath: COMMIT_MODE_OK,
    roadmapModeHelperPath: ROADMAP_MODE_OK,
    deliveryTierHelperPath: DELIVERY_TIER_OK,
  };
}

test("inputSchema: aceita payload com apenas session_id", () => {
  const parsed = inputSchema.safeParse({ session_id: "t" });
  assert.equal(parsed.success, true);
});

test("parseElicitTimeoutMs: ausente/invalido/fora-da-faixa cai no default (300000); valido dentro da faixa passa", () => {
  assert.equal(parseElicitTimeoutMs(undefined), 300000);
  assert.equal(parseElicitTimeoutMs(""), 300000);
  assert.equal(parseElicitTimeoutMs("nao-numero"), 300000);
  assert.equal(parseElicitTimeoutMs("1000"), 300000); // abaixo do MIN (5000) -> default
  assert.equal(parseElicitTimeoutMs("700000"), 300000); // acima do MAX (600000) -> default
  assert.equal(parseElicitTimeoutMs("60000"), 60000);
  assert.equal(parseElicitTimeoutMs("600000"), 600000); // teto exato, aceito
});

test("handleCollectOptins: session_id divergente => SESSION_MISMATCH, sem chamar elicitInput", async () => {
  const input = parseOrThrow({ session_id: "token-errado" });
  let called = false;
  const server: ElicitationServer = {
    getClientCapabilities: () => ({ elicitation: {} }),
    elicitInput: async () => {
      called = true;
      throw new Error("nao deveria ser chamado");
    },
  };

  const response = await handleCollectOptins(input, baseDeps(server));

  assert.equal(response.outcome, "rejected");
  assert.equal(response.stage, "precondition");
  assert.match(response.reason ?? "", /SESSION_MISMATCH/);
  assert.equal(called, false);
});

test("handleCollectOptins: capability elicitation ausente => outcome unavailable para todos os campos, silencioso (sem elicitInput)", async () => {
  const input = parseOrThrow({ session_id: "synthetic-token-abc123" });
  let called = false;
  const server: ElicitationServer = {
    getClientCapabilities: () => undefined,
    elicitInput: async () => {
      called = true;
      throw new Error("nao deveria ser chamado");
    },
  };

  // AGENTE_SESSION (3 campos aplicaveis): feature-00c so tem atomic_commit
  // (dec-083) — o cenario de 2+ campos exercita agente-00c.
  const response = await handleCollectOptins(input, { ...baseDeps(server), session: AGENTE_SESSION });

  assert.equal(response.outcome, "accepted");
  assert.equal(response.result?.mechanism, "unavailable");
  assert.equal(called, false);
  assert.deepEqual(
    response.result?.fields.map((f) => f.outcome),
    ["unavailable", "unavailable", "unavailable"],
  );
});

test("handleCollectOptins: action=accept com os 2 campos presentes (agente-00c) => outcome accepted, escreve via commit-mode/roadmap-mode", async () => {
  const input = parseOrThrow({ session_id: "synthetic-token-abc123" });
  const server: ElicitationServer = {
    getClientCapabilities: () => ({ elicitation: {} }),
    elicitInput: async () => ({
      action: "accept",
      content: { atomic_commit: "sim", roadmap_mode: "nao", delivery_tier: "cloud-public" },
    }),
  };

  // roadmap_mode e exclusivo de agente-00c (dec-083) — usa AGENTE_SESSION.
  const response = await handleCollectOptins(input, { ...baseDeps(server), session: AGENTE_SESSION });

  assert.equal(response.outcome, "accepted");
  assert.deepEqual(response.result?.fields, [
    { field: "atomic_commit", outcome: "accepted", applied_value: "true" },
    { field: "roadmap_mode", outcome: "accepted", applied_value: "false" },
    { field: "delivery_tier", outcome: "accepted", applied_value: "cloud-public" },
  ]);
});

test("handleCollectOptins (feature-00c, dec-083): escopo restrito a SOMENTE atomic_commit — roadmap_mode/delivery_tier nao aparecem", async () => {
  const input = parseOrThrow({ session_id: "synthetic-token-abc123" });
  const server: ElicitationServer = {
    getClientCapabilities: () => ({ elicitation: {} }),
    elicitInput: async () => ({
      action: "accept",
      content: { atomic_commit: "sim", roadmap_mode: "sim", delivery_tier: "local" },
    }),
  };

  const response = await handleCollectOptins(input, baseDeps(server)); // FEATURE_SESSION (default)

  assert.equal(response.outcome, "accepted");
  assert.deepEqual(response.result?.fields, [
    { field: "atomic_commit", outcome: "accepted", applied_value: "true" },
  ]);
});

test("handleCollectOptins: action=accept com campo ausente em content (agente-00c) => outcome absent (default seguro, sem escrita)", async () => {
  const input = parseOrThrow({ session_id: "synthetic-token-abc123" });
  const server: ElicitationServer = {
    getClientCapabilities: () => ({ elicitation: {} }),
    elicitInput: async () => ({ action: "accept", content: { atomic_commit: "sim" } }),
  };

  const response = await handleCollectOptins(input, { ...baseDeps(server), session: AGENTE_SESSION });

  assert.equal(response.outcome, "accepted");
  const roadmap = response.result?.fields.find((f) => f.field === "roadmap_mode");
  assert.deepEqual(roadmap, { field: "roadmap_mode", outcome: "absent", applied_value: "false" });
});

test("handleCollectOptins: action=decline (agente-00c) => outcome declined para todos os campos, default seguro", async () => {
  const input = parseOrThrow({ session_id: "synthetic-token-abc123" });
  const server: ElicitationServer = {
    getClientCapabilities: () => ({ elicitation: {} }),
    elicitInput: async () => ({ action: "decline", content: {} }),
  };

  const response = await handleCollectOptins(input, { ...baseDeps(server), session: AGENTE_SESSION });

  assert.equal(response.outcome, "accepted");
  assert.deepEqual(
    response.result?.fields,
    [
      { field: "atomic_commit", outcome: "declined", applied_value: "false" },
      { field: "roadmap_mode", outcome: "declined", applied_value: "false" },
      { field: "delivery_tier", outcome: "declined", applied_value: "cloud-public" },
    ],
  );
});

test("handleCollectOptins: action=cancel (envelope retornado) => outcome absent (discriminador vs timeout — data-model.md)", async () => {
  const input = parseOrThrow({ session_id: "synthetic-token-abc123" });
  const server: ElicitationServer = {
    getClientCapabilities: () => ({ elicitation: {} }),
    elicitInput: async () => ({ action: "cancel", content: {} }),
  };

  const response = await handleCollectOptins(input, baseDeps(server));

  assert.equal(response.outcome, "accepted");
  assert.ok(response.result?.fields.every((f) => f.outcome === "absent"));
});

test("handleCollectOptins: McpError RequestTimeout (excecao lancada) => outcome timeout, mechanism structured", async () => {
  const input = parseOrThrow({ session_id: "synthetic-token-abc123" });
  const server: ElicitationServer = {
    getClientCapabilities: () => ({ elicitation: {} }),
    elicitInput: async () => {
      throw new McpError(ErrorCode.RequestTimeout, "timed out");
    },
  };

  const response = await handleCollectOptins(input, baseDeps(server));

  assert.equal(response.outcome, "accepted");
  assert.equal(response.result?.mechanism, "structured");
  assert.ok(response.result?.fields.every((f) => f.outcome === "timeout"));
});

test("handleCollectOptins: excecao generica (nao McpError/RequestTimeout) => outcome failed, mechanism failed, 1 linha stderr", async () => {
  const input = parseOrThrow({ session_id: "synthetic-token-abc123" });
  const server: ElicitationServer = {
    getClientCapabilities: () => ({ elicitation: {} }),
    elicitInput: async () => {
      throw new Error("boom");
    },
  };
  const originalErr = console.error;
  let sawStderr = false;
  console.error = () => {
    sawStderr = true;
  };
  try {
    const response = await handleCollectOptins(input, baseDeps(server));
    assert.equal(response.outcome, "accepted");
    assert.equal(response.result?.mechanism, "failed");
    assert.ok(response.result?.fields.every((f) => f.outcome === "failed"));
    assert.equal(sawStderr, true);
  } finally {
    console.error = originalErr;
  }
});

test("handleCollectOptins (3.4.2 allowlist): content com token fora do enum nunca chega ao helper — outcome failed", async () => {
  const input = parseOrThrow({ session_id: "synthetic-token-abc123" });
  const server: ElicitationServer = {
    getClientCapabilities: () => ({ elicitation: {} }),
    elicitInput: async () => ({ action: "accept", content: { atomic_commit: "DROP TABLE" } }),
  };
  const deps = {
    ...baseDeps(server),
    // Se o valor fosse repassado ao helper, este fixture inexistente
    // faria o teste falhar por ENOENT em vez de "failed" limpo.
    commitModeHelperPath: join(FIXTURES_DIR, "does-not-exist.sh"),
  };

  const response = await handleCollectOptins(input, deps);

  const atomic = response.result?.fields.find((f) => f.field === "atomic_commit");
  assert.equal(atomic?.outcome, "failed");
});

test("handleCollectOptins (cap M6, task 3.3.1): todos os campos aplicaveis ja registrados => reused, elicitInput NAO chamado", async () => {
  const input = parseOrThrow({ session_id: "synthetic-token-abc123" });
  let called = false;
  const server: ElicitationServer = {
    getClientCapabilities: () => ({ elicitation: {} }),
    elicitInput: async () => {
      called = true;
      throw new Error("nao deveria ser chamado — cap M6");
    },
  };
  const deps = {
    ...baseDeps(server),
    stateRwHelperPath: join(FIXTURES_DIR, "fake-collect-optins-state-rw-preexisting.sh"),
  };

  const response = await handleCollectOptins(input, deps);

  // FEATURE_SESSION so tem 1 campo aplicavel (atomic_commit, dec-083) — a
  // fixture devolve registro tambem para roadmap_mode, mas esse campo nao e
  // aplicavel a feature-00c e portanto e ignorado no calculo de `reused`.
  assert.equal(called, false);
  assert.equal(response.outcome, "accepted");
  assert.deepEqual(response.result?.reused, ["atomic_commit"]);
});

test("handleCollectOptins (C-2, dec-047): delivery_tier — rebaixamento passa --allow-downgrade; elevacao/no-op NAO passa", async () => {
  const tmpDir = mkdtempSync(join(tmpdir(), "collect-optins-argv-"));
  const argvFile = join(tmpDir, "argv.log");
  const originalEnvValue = process.env.FAKE_ARGV_FILE;
  process.env.FAKE_ARGV_FILE = argvFile;

  try {
    const input = parseOrThrow({ session_id: "synthetic-token-abc123" });
    // fixture "captures-argv" sempre devolve tier vigente = cloud-public
    // (ordinal 3); "local" (ordinal 0) e portanto um REBAIXAMENTO.
    const server: ElicitationServer = {
      getClientCapabilities: () => ({ elicitation: {} }),
      elicitInput: async () => ({
        action: "accept",
        content: { atomic_commit: "nao", roadmap_mode: "nao", delivery_tier: "local" },
      }),
    };
    const deps = {
      ...baseDeps(server),
      session: AGENTE_SESSION,
      deliveryTierHelperPath: join(FIXTURES_DIR, "fake-collect-optins-delivery-tier-captures-argv.sh"),
    };

    const response = await handleCollectOptins(input, deps);

    assert.equal(response.outcome, "accepted");
    const tierField = response.result?.fields.find((f) => f.field === "delivery_tier");
    assert.deepEqual(tierField, { field: "delivery_tier", outcome: "accepted", applied_value: "local" });

    const argvLines = readFileSync(argvFile, "utf8").trim().split("\n");
    // 1 unica chamada de `set` (delivery_tier) — deve conter --allow-downgrade.
    assert.equal(argvLines.length, 1);
    assert.match(argvLines[0] ?? "", /--allow-downgrade/);
  } finally {
    if (originalEnvValue === undefined) delete process.env.FAKE_ARGV_FILE;
    else process.env.FAKE_ARGV_FILE = originalEnvValue;
    rmSync(tmpDir, { recursive: true, force: true });
  }
});

test("handleCollectOptins (C-2, dec-047): elevacao de tier (ordinal maior) NAO passa --allow-downgrade", async () => {
  const tmpDir = mkdtempSync(join(tmpdir(), "collect-optins-argv-"));
  const argvFile = join(tmpDir, "argv.log");
  const originalEnvValue = process.env.FAKE_ARGV_FILE;
  process.env.FAKE_ARGV_FILE = argvFile;

  try {
    const input = parseOrThrow({ session_id: "synthetic-token-abc123" });
    // tier vigente do fixture = cloud-public (ordinal 3, o maior) — qualquer
    // resposta do enum e <= ordinal 3, entao usamos o proprio cloud-public
    // (ordinal igual, no-op) para provar ausencia da flag.
    const server: ElicitationServer = {
      getClientCapabilities: () => ({ elicitation: {} }),
      elicitInput: async () => ({
        action: "accept",
        content: { atomic_commit: "nao", roadmap_mode: "nao", delivery_tier: "cloud-public" },
      }),
    };
    const deps = {
      ...baseDeps(server),
      session: AGENTE_SESSION,
      deliveryTierHelperPath: join(FIXTURES_DIR, "fake-collect-optins-delivery-tier-captures-argv.sh"),
    };

    await handleCollectOptins(input, deps);

    const argvLines = readFileSync(argvFile, "utf8").trim().split("\n");
    assert.equal(argvLines.length, 1);
    assert.doesNotMatch(argvLines[0] ?? "", /--allow-downgrade/);
  } finally {
    if (originalEnvValue === undefined) delete process.env.FAKE_ARGV_FILE;
    else process.env.FAKE_ARGV_FILE = originalEnvValue;
    rmSync(tmpDir, { recursive: true, force: true });
  }
});

test("handleCollectOptins: executionKind desconhecido => nenhum campo aplicavel, mechanism unavailable, sem chamar elicitInput", async () => {
  const input = parseOrThrow({ session_id: "synthetic-token-abc123" });
  let called = false;
  const server: ElicitationServer = {
    getClientCapabilities: () => ({ elicitation: {} }),
    elicitInput: async () => {
      called = true;
      throw new Error("nao deveria ser chamado");
    },
  };
  const deps = {
    ...baseDeps(server),
    session: { ...FEATURE_SESSION, executionKind: "outro-kind-desconhecido" },
  };

  const response = await handleCollectOptins(input, deps);

  assert.equal(response.outcome, "accepted");
  assert.equal(response.result?.mechanism, "unavailable");
  assert.deepEqual(response.result?.fields, []);
  assert.equal(called, false);
});
