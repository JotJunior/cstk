/**
 * Queries read-only para entidade skills.
 * Task 3.3.4
 *
 * FASE 2 (new-schema): Row interface migrada pt-BR→EN snake_case (task 2.8).
 */
import type Database from 'better-sqlite3';
import { hasColumn } from '../columns.js';

export interface SkillRow {
  execution_id: string;
  skill_name: string;
  decision_id: string | null;
  wave: string;
}

/** Lista skills invocadas em uma execucao */
export function listSkillsByExecution(
  db: Database.Database,
  executionId: string
): SkillRow[] {
  const execIdCol = hasColumn(db, 'skills', 'execution_id') ? 'execution_id' : 'NULL as execution_id';
  const decIdCol = hasColumn(db, 'skills', 'decision_id') ? 'decision_id' : 'NULL as decision_id';
  return db
    .prepare(`
      SELECT ${execIdCol}, skill_name, ${decIdCol}, wave
      FROM skills
      WHERE execution_id = ?
      ORDER BY rowid ASC
    `)
    .all(executionId) as SkillRow[];
}
