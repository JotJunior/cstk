// test/audit-log.test.ts — cobertura de audit/log.ts (task 2.3.5):
// serializacao correta com caracteres hostis, teto de 2 KiB respeitado, e
// a ordem scrub -> truncate -> serialize verificada por teste adversarial
// (nao so por leitura de codigo).
//
// Fixtures POSIX reais em test/fixtures/ (execFile de verdade, sem mocks
// JS) — mesma filosofia de test/record_skill.test.ts.

import { test } from "node:test";
import assert from "node:assert/strict";
import { join } from "node:path";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { appendAuditRecord, appendAskOperatorRecord, scrubText } from "../src/audit/log.js";

const FIXTURES_DIR = join(process.cwd(), "test", "fixtures");
const REAL_SCRUB = join(FIXTURES_DIR, "fake-secrets-filter-scrub.sh");
const FAILING_SCRUB = join(FIXTURES_DIR, "fake-secrets-filter-fails.sh");

async function withTempLogFile(
  fn: (logPath: string) => Promise<void>,
): Promise<void> {
  const dir = await mkdtemp(join(tmpdir(), "audit-log-test-"));
  try {
    await fn(join(dir, "nested", "enforcement-log.jsonl"));
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
}

async function readLastLine(logPath: string): Promise<Record<string, unknown>> {
  const content = await readFile(logPath, "utf8");
  const lines = content.trim().split("\n");
  return JSON.parse(lines[lines.length - 1] ?? "{}") as Record<string, unknown>;
}

test("scrubText: aplica o helper e devolve o stdout filtrado", async () => {
  const result = await scrubText("prefixo SECRETXYZ789 sufixo", {
    scrubHelperPath: REAL_SCRUB,
  });
  assert.match(result, /\[REDACTED\]/);
  assert.doesNotMatch(result, /SECRETXYZ789/);
});

test("scrubText: helper indisponivel/falho -> placeholder seguro, NUNCA o texto cru (fail-closed)", async () => {
  const result = await scrubText("nao deveria vazar isso", {
    scrubHelperPath: FAILING_SCRUB,
  });
  assert.doesNotMatch(result, /nao deveria vazar isso/);
  assert.match(result, /secrets-filter indisponivel ou falhou/);
});

test("scrubText: helper inexistente (ENOENT) -> placeholder seguro", async () => {
  const result = await scrubText("texto qualquer", {
    scrubHelperPath: join(FIXTURES_DIR, "does-not-exist.sh"),
  });
  assert.match(result, /secrets-filter indisponivel ou falhou/);
});

test("appendAuditRecord: happy path — linha JSONL valida com todos os campos do contrato", async () => {
  await withTempLogFile(async (logPath) => {
    const ok = await appendAuditRecord(
      {
        tool: "record_skill",
        sessionId: "synthetic-token-abc123",
        outcome: "accepted",
        detectedExecution: "feature-00c:state-mcp-server",
        detectedExecutionPath: "/data/state",
        reason: null,
        stage: null,
        arguments: { skill: "execute-task", kind: "skill" },
      },
      { logPath, scrubHelperPath: REAL_SCRUB, now: () => new Date("2026-08-01T12:00:00.000Z") },
    );
    assert.equal(ok, true);

    const entry = await readLastLine(logPath);
    assert.equal(entry.source, "mcp-state-tool");
    assert.equal(entry.timestamp, "2026-08-01T12:00:00Z");
    assert.equal(entry.outcome, "accepted");
    assert.equal(entry.tool, "record_skill");
    assert.equal(entry.session_id, "synthetic-token-abc123");
    assert.equal(entry.detected_execution, "feature-00c:state-mcp-server");
    assert.equal(entry.detected_execution_path, "/data/state");
    assert.equal(entry.reason, null);
    assert.equal(entry.stage, null);
    assert.match(entry.arguments_digest as string, /execute-task/);
  });
});

test("appendAuditRecord: caracteres hostis (\", \\n, \\t) no reason nao quebram a linha JSONL", async () => {
  await withTempLogFile(async (logPath) => {
    const hostileReason = 'motivo com "aspas", \nquebra de linha e \ttab';
    const ok = await appendAuditRecord(
      {
        tool: "record_skill",
        sessionId: "tok",
        outcome: "rejected",
        detectedExecution: "feature-00c:state-mcp-server",
        detectedExecutionPath: "/data/state",
        reason: hostileReason,
        stage: "delegation",
        arguments: { skill: "x" },
      },
      { logPath, scrubHelperPath: REAL_SCRUB },
    );
    assert.equal(ok, true);

    // A linha inteira MUST ser um unico JSON valido (o parser nao pode
    // quebrar no meio por causa das aspas/quebra de linha do payload).
    const content = await readFile(logPath, "utf8");
    const lines = content.trim().split("\n");
    assert.equal(lines.length, 1, "aspas/newline no reason nao podem gerar uma segunda linha");

    const entry = await readLastLine(logPath);
    assert.equal(entry.reason, hostileReason.trim());
  });
});

test("appendAuditRecord: reason respeita o teto de 2 KiB (SEC-M1)", async () => {
  await withTempLogFile(async (logPath) => {
    const longReason = "x".repeat(5000);
    await appendAuditRecord(
      {
        tool: "record_skill",
        sessionId: "tok",
        outcome: "rejected",
        detectedExecution: null,
        detectedExecutionPath: null,
        reason: longReason,
        stage: "delegation",
        arguments: {},
      },
      { logPath, scrubHelperPath: REAL_SCRUB },
    );

    const entry = await readLastLine(logPath);
    assert.equal(Buffer.byteLength(entry.reason as string, "utf8"), 2048);
  });
});

test("appendAuditRecord (adversarial, SEC-M3): ordem scrub -> truncate garante que um segredo na fronteira do teto de 2 KiB do reason nunca sobrevive, nem parcialmente", async () => {
  await withTempLogFile(async (logPath) => {
    // Padding de 2030 chars + o marcador "SECRETXYZ789" (12 chars) + cauda.
    // No texto ORIGINAL (pre-scrub) o marcador comeca dentro do que seria
    // um corte ingenuo em 2048 bytes. Se a ordem fosse
    // truncate-antes-de-scrub, o corte cortaria o marcador ao meio antes
    // do scrub ter a chance de casar a string completa "SECRETXYZ789" —
    // deixando um FRAGMENTO nao-redigido no resultado. Com scrub ->
    // truncate (ordem correta), o marcador inteiro e substituido por
    // "[REDACTED]" (10 chars) ANTES do corte de 2048 bytes; a cauda
    // "tail-depois-do-teto" e quem acaba sendo cortada, nao o segredo.
    const padding = "p".repeat(2030);
    const reason = padding + "SECRETXYZ789" + "tail-depois-do-teto";

    await appendAuditRecord(
      {
        tool: "record_skill",
        sessionId: "tok",
        outcome: "rejected",
        detectedExecution: null,
        detectedExecutionPath: null,
        reason,
        stage: "delegation",
        arguments: {},
      },
      { logPath, scrubHelperPath: REAL_SCRUB },
    );

    const entry = await readLastLine(logPath);
    const persistedReason = entry.reason as string;
    // Nenhum fragmento reconhecivel do segredo pode sobreviver.
    assert.doesNotMatch(persistedReason, /SECRETXYZ789/);
    assert.doesNotMatch(persistedReason, /SECRETXY/);
    assert.match(persistedReason, /\[REDACTED\]/);
  });
});

test("appendAuditRecord (adversarial, SEC-M3): ordem scrub -> truncate no arguments_digest (teto de 500 code points)", async () => {
  await withTempLogFile(async (logPath) => {
    // Mesma logica, mas para arguments_digest (teto de 500 CODE POINTS,
    // nao bytes): o marcador comeca antes da posicao 500 do JSON
    // serializado e termina depois.
    const padding = "p".repeat(490);
    await appendAuditRecord(
      {
        tool: "record_skill",
        sessionId: "tok",
        outcome: "accepted",
        detectedExecution: null,
        detectedExecutionPath: null,
        reason: null,
        stage: null,
        arguments: { note: padding + "SECRETXYZ789" },
      },
      { logPath, scrubHelperPath: REAL_SCRUB },
    );

    const entry = await readLastLine(logPath);
    const digest = entry.arguments_digest as string;
    assert.doesNotMatch(digest, /SECRETXYZ789/);
    assert.doesNotMatch(digest, /SECRETXY/);
    assert.ok(Array.from(digest).length <= 500);
  });
});

test("appendAuditRecord: teto de 500 code points do arguments_digest e respeitado em payload grande sem segredo", async () => {
  await withTempLogFile(async (logPath) => {
    await appendAuditRecord(
      {
        tool: "record_skill",
        sessionId: "tok",
        outcome: "accepted",
        detectedExecution: null,
        detectedExecutionPath: null,
        reason: null,
        stage: null,
        arguments: { note: "y".repeat(3000) },
      },
      { logPath, scrubHelperPath: REAL_SCRUB },
    );

    const entry = await readLastLine(logPath);
    assert.equal(Array.from(entry.arguments_digest as string).length, 500);
  });
});

test("appendAuditRecord: falha ao escrever (diretorio impossivel de criar) NUNCA lanca -- retorna false", async () => {
  await withTempLogFile(async (baseLogPath) => {
    // Cria um ARQUIVO regular no lugar de um componente de diretorio do
    // path, forcando mkdir(dirname, {recursive:true}) a falhar (ENOTDIR).
    const dir = await mkdtemp(join(tmpdir(), "audit-log-blocker-"));
    try {
      const blockerFile = join(dir, "blocker");
      await writeFile(blockerFile, "not a dir");
      const impossibleLogPath = join(blockerFile, "enforcement-log.jsonl");

      const ok = await appendAuditRecord(
        {
          tool: "record_skill",
          sessionId: "tok",
          outcome: "accepted",
          detectedExecution: null,
          detectedExecutionPath: null,
          reason: null,
          stage: null,
          arguments: {},
        },
        { logPath: impossibleLogPath, scrubHelperPath: REAL_SCRUB },
      );
      assert.equal(ok, false);
    } finally {
      await rm(dir, { recursive: true, force: true });
    }
  });
});

// --- appendAskOperatorRecord (human-bridge FASE 2, task 2.3.3) -------------

test("appendAskOperatorRecord: happy path — 1 linha JSONL, source proprio, todos os campos", async () => {
  await withTempLogFile(async (logPath) => {
    const ok = await appendAskOperatorRecord(
      {
        sessionId: "synthetic-token-abc123",
        questionId: "q-abc123",
        channel: "panel",
        outcome: "answered",
        appliedValue: "sim",
        effectiveTimeoutMs: 240000,
        reason: null,
      },
      { logPath, now: () => new Date("2026-08-29T18:00:00.000Z") },
    );
    assert.equal(ok, true);

    const content = await readFile(logPath, "utf8");
    assert.equal(content.trim().split("\n").length, 1, "exatamente 1 linha por resposta persistida");

    const entry = await readLastLine(logPath);
    assert.equal(entry.source, "mcp-ask-operator");
    assert.equal(entry.timestamp, "2026-08-29T18:00:00Z");
    assert.equal(entry.session_id, "synthetic-token-abc123");
    assert.equal(entry.question_id, "q-abc123");
    assert.equal(entry.channel, "panel");
    assert.equal(entry.outcome, "answered");
    assert.equal(entry.applied_value, "sim");
    assert.equal(entry.effective_timeout_ms, 240000);
    assert.equal(entry.reason, null);
  });
});

test("appendAskOperatorRecord: reason respeita o teto de 2 KiB (SEC-M1, mesmo REASON_MAX_BYTES)", async () => {
  await withTempLogFile(async (logPath) => {
    await appendAskOperatorRecord(
      {
        sessionId: "tok",
        questionId: "q-1",
        channel: "panel",
        outcome: "unavailable",
        appliedValue: "default",
        effectiveTimeoutMs: 240000,
        reason: "x".repeat(5000),
      },
      { logPath },
    );
    const entry = await readLastLine(logPath);
    assert.equal(Buffer.byteLength(entry.reason as string, "utf8"), 2048);
  });
});

test("appendAskOperatorRecord: falha ao escrever NUNCA lanca -- retorna false", async () => {
  await withTempLogFile(async (baseLogPath) => {
    const dir = await mkdtemp(join(tmpdir(), "audit-log-ask-operator-blocker-"));
    try {
      const blockerFile = join(dir, "blocker");
      await writeFile(blockerFile, "not a dir");
      const impossibleLogPath = join(blockerFile, "enforcement-log.jsonl");

      const ok = await appendAskOperatorRecord(
        {
          sessionId: "tok",
          questionId: "q-1",
          channel: "panel",
          outcome: "failed",
          appliedValue: "default",
          effectiveTimeoutMs: 240000,
          reason: null,
        },
        { logPath: impossibleLogPath },
      );
      assert.equal(ok, false);
    } finally {
      await rm(dir, { recursive: true, force: true });
    }
  });
});
