/**
 * Queries read-only para entidade tasks.
 * Ref: data-model.md §Entity: Task; contracts/api-read.md
 * Task 3.3.4
 *
 * FASE 2 (new-schema): Row interface migrada pt-BR→EN snake_case (task 2.4).
 */
import type Database from 'better-sqlite3';
import { hasColumn } from '../columns.js';

export interface TaskRow {
  wave: string;
  execution_id: string;
  title: string;                    // schema v3; '' em bases v2 (FR-V3-005)
  outcome: string | null;
  tests_run: number | null;
  tests_passed: number | null;
  lint_ok: number | null;           // INTEGER 0/1 → boolean no mapper
  touched_files: number | null;     // contagem (INTEGER) — NAO array
}

/**
 * Projecao de `title` tolerante a bases v2/v6 (coluna era `titulo` antes).
 * COALESCE cobre `title` NULL (linha de base migrada ainda sem valor).
 */
export function titleSelect(db: Database.Database, prefix = ''): string {
  if (hasColumn(db, 'tasks', 'title')) {
    return `COALESCE(${prefix}title, '') as title`;
  }
  return "'' as title";
}

/**
 * Projecao de colunas renomeadas com back-compat v6.
 */
function tasksColumnsSelect(db: Database.Database, prefix = ''): string {
  const p = prefix;
  const testsRunCol = hasColumn(db, 'tasks', 'tests_run') ? `${p}tests_run` : 'NULL as tests_run';
  const testsPassedCol = hasColumn(db, 'tasks', 'tests_passed') ? `${p}tests_passed` : 'NULL as tests_passed';
  const touchedFilesCol = hasColumn(db, 'tasks', 'touched_files') ? `${p}touched_files` : 'NULL as touched_files';
  return `${testsRunCol}, ${testsPassedCol}, ${touchedFilesCol}`;
}

/** Lista tasks de uma execucao */
export function listTasksByExecution(
  db: Database.Database,
  executionId: string
): TaskRow[] {
  return db
    .prepare(`
      SELECT wave, execution_id, ${titleSelect(db)}, outcome,
             ${tasksColumnsSelect(db)},
             lint_ok
      FROM tasks
      WHERE execution_id = ?
      ORDER BY rowid ASC
    `)
    .all(executionId) as TaskRow[];
}
