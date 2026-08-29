/**
 * Queries read-only para entidade blocks (era: bloqueios).
 * Ref: data-model.md §Entity: blocks; spec.md FR-002, FR-003; contracts/api-read.md
 * Task 2.5 (new-schema): rename bloqueios→blocks, tabela SQL bloqueios→blocks,
 *   Row interface BloqueioRow→BlockRow, todos os campos pt-BR→EN snake_case.
 */
import type Database from 'better-sqlite3';
import { hasTable, hasColumn } from '../columns.js';

export interface BlockRow {
  execution_id: string;
  status: string | null;
  question: string | null;
  context_for_answer: string | null;
  answer: string | null;
  decision_id: string | null;
  triggered_at: string | null;
  answered_at: string | null;
  latency_seconds: number | null;
}

/** Lista bloqueios de uma execucao usando a tabela `blocks` (v7). */
export function listBlocksByExecution(
  db: Database.Database,
  executionId: string
): BlockRow[] {
  if (!hasTable(db, 'blocks')) return [];

  const execIdCol = hasColumn(db, 'blocks', 'execution_id') ? 'execution_id' : 'NULL as execution_id';
  const questionCol = hasColumn(db, 'blocks', 'question') ? 'question' : 'NULL as question';
  const ctxCol = hasColumn(db, 'blocks', 'context_for_answer') ? 'context_for_answer' : 'NULL as context_for_answer';
  const answerCol = hasColumn(db, 'blocks', 'answer') ? 'answer' : 'NULL as answer';
  const decIdCol = hasColumn(db, 'blocks', 'decision_id') ? 'decision_id' : 'NULL as decision_id';
  const triggeredCol = hasColumn(db, 'blocks', 'triggered_at') ? 'triggered_at' : 'NULL as triggered_at';
  const answeredCol = hasColumn(db, 'blocks', 'answered_at') ? 'answered_at' : 'NULL as answered_at';
  const latencyCol = hasColumn(db, 'blocks', 'latency_seconds') ? 'latency_seconds' : 'NULL as latency_seconds';
  const orderCol = hasColumn(db, 'blocks', 'triggered_at') ? 'triggered_at' : 'rowid';

  return db
    .prepare(`
      SELECT ${execIdCol}, status, ${questionCol}, ${ctxCol},
             ${answerCol}, ${decIdCol}, ${triggeredCol}, ${answeredCol},
             ${latencyCol}
      FROM blocks
      WHERE execution_id = ?
      ORDER BY ${orderCol} ASC
    `)
    .all(executionId) as BlockRow[];
}
