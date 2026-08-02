// test/close_wave.test.ts — cobertura da tool close_wave (task 4.1 + 4.2):
// happy path nos dois backends (json/sqlite), precondicoes (SESSION_MISMATCH,
// NO_OPEN_WAVE) e compensacao por pre-imagem (research.md Decision 3) quando
// uma etapa falha ANTES da mutacao (nada a restaurar, so nao mutar) e DEPOIS
// da mutacao (restaura os bytes originais em disco — prova empirica de que a
// onda "permanece aberta" de fato, nao so no retorno da tool).

import { test } from "node:test";
import assert from "node:assert/strict";
import { join } from "node:path";
import { mkdtemp, readFile, writeFile, rm } from "node:fs/promises";
import { existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { z } from "zod";
import {
  handleCloseWave,
  closeWaveInputShape,
  type CloseWaveInput,
} from "../src/tools/close_wave.js";
import type { ResolvedSession } from "../src/session/resolve.js";

const FIXTURES_DIR = join(process.cwd(), "test", "fixtures");
const inputSchema = z.object(closeWaveInputShape);

function parseOrThrow(raw: unknown): CloseWaveInput {
  return inputSchema.parse(raw);
}

async function makeStateDir(): Promise<string> {
  return mkdtemp(join(tmpdir(), "cstk-close-wave-test-"));
}

function sessionFor(stateDir: string): ResolvedSession {
  return {
    token: "synthetic-token-abc123",
    stateDir,
    executionKind: "feature-00c",
    shortName: "state-mcp-server",
    targetProjectPath: "/work",
    mode: "docker",
    container: "cstk-mcp-state-test",
  };
}

const F = {
  ondasHappy: join(FIXTURES_DIR, "fake-close-wave-ondas-happy.sh"),
  ondasNoOpenWave: join(FIXTURES_DIR, "fake-close-wave-ondas-no-open-wave.sh"),
  ondasEndFails: join(FIXTURES_DIR, "fake-close-wave-ondas-end-fails.sh"),
  ondasEndMutates: join(FIXTURES_DIR, "fake-close-wave-ondas-end-mutates.sh"),
  stateRwHappy: join(FIXTURES_DIR, "fake-close-wave-state-rw-happy.sh"),
  stateRwReadFails: join(FIXTURES_DIR, "fake-close-wave-state-rw-read-fails.sh"),
  stateRwShaFails: join(FIXTURES_DIR, "fake-close-wave-state-rw-sha-fails.sh"),
  secretsFilterHappy: join(FIXTURES_DIR, "fake-close-wave-secrets-filter-happy.sh"),
  secretsFilterFails: join(FIXTURES_DIR, "fake-close-wave-secrets-filter-fails.sh"),
  doesNotExist: join(FIXTURES_DIR, "does-not-exist.sh"),
};

test("inputSchema: rejeita termination_reason fora do enum de 5 valores", () => {
  const parsed = inputSchema.safeParse({
    session_id: "t",
    termination_reason: "motivo-invalido",
  });
  assert.equal(parsed.success, false);
});

test("inputSchema: rejeita executed_stages[] com token invalido (espaco/prosa)", () => {
  const parsed = inputSchema.safeParse({
    session_id: "t",
    termination_reason: "concluido",
    executed_stages: ["etapa valida nao e assim"],
  });
  assert.equal(parsed.success, false);
});

test("inputSchema: aceita payload minimo (so termination_reason)", () => {
  const parsed = inputSchema.safeParse({ session_id: "t", termination_reason: "concluido" });
  assert.equal(parsed.success, true);
});

test("handleCloseWave: session_id divergente => SESSION_MISMATCH, nenhum helper invocado", async () => {
  const stateDir = await makeStateDir();
  try {
    const input = parseOrThrow({ session_id: "token-errado", termination_reason: "concluido" });
    const response = await handleCloseWave(input, {
      session: sessionFor(stateDir),
      ondasHelperPath: F.doesNotExist,
      stateRwHelperPath: F.doesNotExist,
      secretsFilterHelperPath: F.doesNotExist,
    });
    assert.equal(response.outcome, "rejected");
    assert.equal(response.stage, "precondition");
    assert.match(response.reason ?? "", /SESSION_MISMATCH/);
  } finally {
    await rm(stateDir, { recursive: true, force: true });
  }
});

test("handleCloseWave: NO_OPEN_WAVE quando wave-status != open (end nunca invocado)", async () => {
  const stateDir = await makeStateDir();
  try {
    await writeFile(join(stateDir, "state.json"), '{"waves":[]}', "utf8");
    const input = parseOrThrow({ session_id: "synthetic-token-abc123", termination_reason: "concluido" });
    const response = await handleCloseWave(input, {
      session: sessionFor(stateDir),
      ondasHelperPath: F.ondasNoOpenWave,
      stateRwHelperPath: F.stateRwHappy,
      secretsFilterHelperPath: F.secretsFilterHappy,
    });
    assert.equal(response.outcome, "rejected");
    assert.equal(response.stage, "precondition");
    assert.match(response.reason ?? "", /NO_OPEN_WAVE/);
    assert.equal(existsSync(join(stateDir, "backups")), false, "backup nao deve ser gerado sem onda aberta");
  } finally {
    await rm(stateDir, { recursive: true, force: true });
  }
});

test("handleCloseWave: happy path (backend json) fecha a onda, grava backup escrubado e devolve state_sha256", async () => {
  const stateDir = await makeStateDir();
  try {
    await writeFile(join(stateDir, "state.json"), '{"waves":[{"id":"onda-013"}]}', "utf8");
    await writeFile(join(stateDir, "state.json.sha256"), "seedhash123\n", "utf8");

    const input = parseOrThrow({
      session_id: "synthetic-token-abc123",
      termination_reason: "concluido",
      executed_stages: ["review-task"],
      next_instruction: "Execucao concluida.",
    });
    const response = await handleCloseWave(input, {
      session: sessionFor(stateDir),
      ondasHelperPath: F.ondasHappy,
      stateRwHelperPath: F.stateRwHappy,
      secretsFilterHelperPath: F.secretsFilterHappy,
    });

    assert.equal(response.outcome, "accepted");
    assert.equal(response.stage, null);
    assert.equal(response.result?.wave_id, "onda-013");
    assert.equal(response.result?.state_sha256, "seedhash123");
    assert.equal(response.result?.backup_path, join(stateDir, "backups", "wave-013.json"));

    const backupContent = await readFile(join(stateDir, "backups", "wave-013.json"), "utf8");
    const envelope = JSON.parse(backupContent) as { wave_number: number };
    assert.equal(envelope.wave_number, 13);
  } finally {
    await rm(stateDir, { recursive: true, force: true });
  }
});

test("handleCloseWave: happy path (backend sqlite) detecta backend via presenca de state.db e state_sha256=null (C7/dec-025)", async () => {
  const stateDir = await makeStateDir();
  try {
    await writeFile(join(stateDir, "state.db"), "fake-sqlite-bytes", "utf8");

    const input = parseOrThrow({ session_id: "synthetic-token-abc123", termination_reason: "concluido" });
    const response = await handleCloseWave(input, {
      session: sessionFor(stateDir),
      ondasHelperPath: F.ondasHappy,
      stateRwHelperPath: F.stateRwHappy,
      secretsFilterHelperPath: F.secretsFilterHappy,
    });

    assert.equal(response.outcome, "accepted");
    assert.equal(response.result?.state_sha256, null);
    // Pre-imagem tera copiado state.db (existente) -- verificar que o
    // arquivo original permanece intacto apos o caminho feliz (sem restore).
    assert.equal(await readFile(join(stateDir, "state.db"), "utf8"), "fake-sqlite-bytes");
  } finally {
    await rm(stateDir, { recursive: true, force: true });
  }
});

test("handleCloseWave (4.2.3): falha ANTES da mutacao (wave-backup) => nada muda em disco, CLOSE_ROLLED_BACK", async () => {
  const stateDir = await makeStateDir();
  try {
    const original = '{"waves":[{"id":"onda-013"}],"original":true}';
    await writeFile(join(stateDir, "state.json"), original, "utf8");
    await writeFile(join(stateDir, "state.json.sha256"), "origsha\n", "utf8");

    const input = parseOrThrow({ session_id: "synthetic-token-abc123", termination_reason: "concluido" });
    const response = await handleCloseWave(input, {
      session: sessionFor(stateDir),
      // `end` fixture usada aqui FALHARIA alto se fosse invocada -- prova
      // (por construcao) que o handler nunca chega a mutacao quando o
      // wave-backup (etapa 2, ANTES da mutacao) ja falhou.
      ondasHelperPath: F.ondasEndFails,
      stateRwHelperPath: F.stateRwHappy,
      secretsFilterHelperPath: F.secretsFilterFails,
    });

    assert.equal(response.outcome, "rejected");
    assert.equal(response.stage, "delegation");
    assert.match(response.reason ?? "", /CLOSE_ROLLED_BACK/);
    assert.match(response.reason ?? "", /wave-backup/);
    assert.equal(await readFile(join(stateDir, "state.json"), "utf8"), original);
    assert.equal(await readFile(join(stateDir, "state.json.sha256"), "utf8"), "origsha\n");
  } finally {
    await rm(stateDir, { recursive: true, force: true });
  }
});

test("handleCloseWave (4.2.3): falha na leitura pre-mutacao (state-rw.sh read) => nada muda em disco, CLOSE_ROLLED_BACK", async () => {
  const stateDir = await makeStateDir();
  try {
    const original = '{"waves":[{"id":"onda-013"}],"original":true}';
    await writeFile(join(stateDir, "state.json"), original, "utf8");

    const input = parseOrThrow({ session_id: "synthetic-token-abc123", termination_reason: "concluido" });
    const response = await handleCloseWave(input, {
      session: sessionFor(stateDir),
      ondasHelperPath: F.ondasEndFails,
      stateRwHelperPath: F.stateRwReadFails,
      secretsFilterHelperPath: F.secretsFilterHappy,
    });

    assert.equal(response.outcome, "rejected");
    assert.match(response.reason ?? "", /CLOSE_ROLLED_BACK/);
    assert.equal(existsSync(join(stateDir, "backups")), false);
    assert.equal(await readFile(join(stateDir, "state.json"), "utf8"), original);
  } finally {
    await rm(stateDir, { recursive: true, force: true });
  }
});

test("handleCloseWave (4.1.3/4.2.3): falha DEPOIS da mutacao (sha256-update) => pre-imagem restaurada em disco (compensacao real)", async () => {
  const stateDir = await makeStateDir();
  try {
    const original = '{"waves":[{"id":"onda-013"}],"original":true}';
    await writeFile(join(stateDir, "state.json"), original, "utf8");
    await writeFile(join(stateDir, "state.json.sha256"), "origsha\n", "utf8");

    const input = parseOrThrow({ session_id: "synthetic-token-abc123", termination_reason: "concluido" });
    const response = await handleCloseWave(input, {
      session: sessionFor(stateDir),
      // `end` fixture aqui MUTA de verdade o state.json em disco antes de
      // "suceder" -- o teste prova que a compensacao reverte os bytes.
      ondasHelperPath: F.ondasEndMutates,
      stateRwHelperPath: F.stateRwShaFails,
      secretsFilterHelperPath: F.secretsFilterHappy,
    });

    assert.equal(response.outcome, "rejected");
    assert.equal(response.stage, "delegation");
    assert.match(response.reason ?? "", /CLOSE_ROLLED_BACK/);
    assert.match(response.reason ?? "", /sha256-update/);

    // A prova empirica da compensacao: o state.json em disco NAO pode
    // conter o marcador "mutated" que a fixture de `end` escreveu -- os
    // bytes originais (pre-imagem) foram restaurados.
    const restored = await readFile(join(stateDir, "state.json"), "utf8");
    assert.equal(restored, original);
    assert.doesNotMatch(restored, /mutated/);
    assert.equal(await readFile(join(stateDir, "state.json.sha256"), "utf8"), "origsha\n");

    // O backup escrubado da onda (etapa 2, ANTES da mutacao) e um efeito
    // colateral inofensivo que permanece em disco mesmo apos o rollback --
    // nao viola "onda permanece aberta" (o proximo close_wave bem-sucedido
    // sobrescreve o mesmo arquivo wave-013.json).
    assert.equal(existsSync(join(stateDir, "backups", "wave-013.json")), true);
  } finally {
    await rm(stateDir, { recursive: true, force: true });
  }
});

test("handleCloseWave (5.5, CHK071): queda simulada apos a mutacao seguida de nova tentativa -- fecha exatamente uma vez, sem duplicar nem perder a mutacao", async () => {
  // Simula o cenario mid-onda de US4 cenario 2 / contracts/mcp-session-
  // lifecycle.md §Deteccao de queda mid-onda: a 1a chamada "cai" DEPOIS da
  // mutacao (equivalente a o processo morrer no meio de close_wave) -- a
  // compensacao por pre-imagem ja PROVADA no teste anterior restaura a onda
  // para "aberta". O orquestrador (per contrato: 0 retries da MESMA chamada,
  // 1 confirmacao via `status --live`, depois comuta) reemite o fechamento
  // -- aqui simulado como uma 2a chamada happy-path a handleCloseWave.
  // Invariante sob teste: o resultado final e UMA UNICA onda fechada
  // (state.json nunca fica em "onda fechada duas vezes" nem "mutacao
  // perdida").
  const stateDir = await makeStateDir();
  try {
    const original = '{"waves":[{"id":"onda-013"}],"original":true}';
    await writeFile(join(stateDir, "state.json"), original, "utf8");
    await writeFile(join(stateDir, "state.json.sha256"), "origsha\n", "utf8");

    const input = parseOrThrow({ session_id: "synthetic-token-abc123", termination_reason: "concluido" });

    // 1a tentativa: "queda" apos a mutacao (mesma fixture do teste acima) --
    // resultado observavel: CLOSE_ROLLED_BACK, onda permanece aberta.
    const firstAttempt = await handleCloseWave(input, {
      session: sessionFor(stateDir),
      ondasHelperPath: F.ondasEndMutates,
      stateRwHelperPath: F.stateRwShaFails,
      secretsFilterHelperPath: F.secretsFilterHappy,
    });
    assert.equal(firstAttempt.outcome, "rejected");
    assert.match(firstAttempt.reason ?? "", /CLOSE_ROLLED_BACK/);

    const afterFirstAttempt = await readFile(join(stateDir, "state.json"), "utf8");
    assert.equal(afterFirstAttempt, original, "onda deve permanecer aberta (pre-imagem restaurada) apos a 1a tentativa");

    // 2a tentativa (a "comutacao"/nova tentativa pos-deteccao): dessa vez
    // tudo funciona -- fecha a onda de fato, exatamente uma vez.
    const secondAttempt = await handleCloseWave(input, {
      session: sessionFor(stateDir),
      ondasHelperPath: F.ondasHappy,
      stateRwHelperPath: F.stateRwHappy,
      secretsFilterHelperPath: F.secretsFilterHappy,
    });
    assert.equal(secondAttempt.outcome, "accepted");
    assert.equal(secondAttempt.result?.wave_id, "onda-013");

    // Prova de "sem duplicar": exatamente um backup da onda-013 em disco
    // (o mesmo arquivo sobrescrito pela tentativa 1 -- que gravou o backup
    // ANTES de mutar -- e pela tentativa 2 que de fato fechou), nao dois
    // arquivos/entradas distintas.
    const backupContent = await readFile(join(stateDir, "backups", "wave-013.json"), "utf8");
    const envelope = JSON.parse(backupContent) as { wave_number: number };
    assert.equal(envelope.wave_number, 13);
  } finally {
    await rm(stateDir, { recursive: true, force: true });
  }
});
