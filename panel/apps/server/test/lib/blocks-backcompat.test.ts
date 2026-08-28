/**
 * 5.7.2 Back-compat v6: listBlocksByExecution com DB sem tabela `blocks`.
 * Ref: spec.md FR-002, FR-007; quickstart.md §Scenario D; tasks.md 5.7.2
 *
 * Verifica que a funcao retorna [] sem excecao quando a tabela `blocks`
 * nao existe no DB (v6 usava `bloqueios`). Isso e garantido pelo
 * hasTable guard em apps/server/src/db/queries/blocks.ts.
 *
 * Principio II (Degradar, Nunca Quebrar): queries para tabelas ausentes
 * nunca lancam excecao — retornam [] graciosamente.
 */
import { describe, it, expect, afterEach } from 'vitest';
import { mkdtempSync, unlinkSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import Database from 'better-sqlite3';
import { listBlocksByExecution } from '../../src/db/queries/blocks.js';

// Track tmp files for cleanup
const toClean: string[] = [];

afterEach(() => {
  for (const f of toClean) {
    try { unlinkSync(f); } catch { /* no-op */ }
    try { unlinkSync(f + '-shm'); } catch { /* no-op */ }
    try { unlinkSync(f + '-wal'); } catch { /* no-op */ }
  }
  toClean.length = 0;
});

function tmpDb(suffix = '.db'): string {
  const dir = mkdtempSync(join(tmpdir(), 'cstk-blocks-'));
  const p = join(dir, `test${suffix}`);
  toClean.push(p);
  return p;
}

// ─── 5.7.2 hasTable guard: tabela `blocks` ausente → retorna [] ──────────────

describe('5.7.2 listBlocksByExecution — back-compat v6 (sem tabela blocks)', () => {
  it('retorna [] sem excecao quando tabela blocks nao existe (v6 usava bloqueios)', () => {
    const path = tmpDb();
    const db = new Database(path);

    // DB sem tabela blocks (simula base v6)
    db.exec(`
      CREATE TABLE IF NOT EXISTS executions (
        execution_id TEXT PRIMARY KEY,
        current_stage TEXT
      );
      INSERT INTO executions (execution_id, current_stage) VALUES ('exec-v6-001', 'execute-task');
    `);

    let result: ReturnType<typeof listBlocksByExecution> | undefined;
    let error: unknown;
    try {
      result = listBlocksByExecution(db, 'exec-v6-001');
    } catch (e) {
      error = e;
    } finally {
      db.close();
    }

    expect(error, 'listBlocksByExecution nao deve lancar excecao com tabela blocks ausente').toBeUndefined();
    expect(result).toEqual([]);
  });

  it('retorna [] para execucao inexistente mesmo com tabela blocks presente e vazia', () => {
    const path = tmpDb();
    const db = new Database(path);

    // DB com tabela blocks (v7) mas sem dados
    db.exec(`
      CREATE TABLE IF NOT EXISTS blocks (
        execution_id TEXT,
        status TEXT,
        question TEXT,
        context_for_answer TEXT,
        answer TEXT,
        decision_id TEXT,
        triggered_at TEXT,
        answered_at TEXT,
        latency_seconds REAL
      );
    `);

    let result: ReturnType<typeof listBlocksByExecution> | undefined;
    let error: unknown;
    try {
      result = listBlocksByExecution(db, 'exec-inexistente');
    } catch (e) {
      error = e;
    } finally {
      db.close();
    }

    expect(error).toBeUndefined();
    expect(result).toEqual([]);
  });

  it('retorna [] sem excecao com DB completamente vazio (zero tabelas)', () => {
    const path = tmpDb();
    const db = new Database(path);
    // Nenhuma CREATE TABLE — DB vazio

    let result: ReturnType<typeof listBlocksByExecution> | undefined;
    let error: unknown;
    try {
      result = listBlocksByExecution(db, 'exec-001');
    } catch (e) {
      error = e;
    } finally {
      db.close();
    }

    expect(error).toBeUndefined();
    expect(result).toEqual([]);
  });
});

// ─── 5.7.1 BlockDTOSchema: campos EN canônicos ───────────────────────────────
// (Complementa parity.test.ts com campo question explicitamente EN)

describe('5.7.1 BlockDTOSchema — campos EN canonicos (cross-ref parity.test.ts)', () => {
  it('campo question (EN) e obrigatorio — pergunta (PT-BR) causa falha', async () => {
    const { BlockDTOSchema } = await import('@cstk-panel/shared-types');
    const ISO = '2026-01-01T00:00:00Z';

    // PT-BR: deve falhar
    const ptBrPayload = {
      executionId: 'exec-001',
      status: 'pendente',
      pergunta: 'Confirmar?',     // PT-BR — campo errado
      contextForAnswer: null,
      answer: null,
      decisionId: null,
      triggeredAt: ISO,
      answeredAt: null,
      latencySeconds: null,
    };
    const fail = BlockDTOSchema.safeParse(ptBrPayload);
    expect(fail.success).toBe(false);

    // EN: deve passar
    const enPayload = {
      executionId: 'exec-001',
      status: 'pendente',
      question: 'Confirmar?',     // EN — campo correto
      contextForAnswer: null,
      answer: null,
      decisionId: null,
      triggeredAt: ISO,
      answeredAt: null,
      latencySeconds: null,
    };
    const pass = BlockDTOSchema.safeParse(enPayload);
    expect(pass.success, `BlockDTOSchema falhou: ${JSON.stringify(pass.error?.issues?.slice(0, 3))}`).toBe(true);
  });
});
