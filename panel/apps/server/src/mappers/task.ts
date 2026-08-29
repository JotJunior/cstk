/**
 * Mapper: TaskRow → TaskDTO.
 * lint_ok: INTEGER 0/1 → boolean via === 1.
 * arquivos_tocados: INTEGER → arquivosTocadosCount: number (contagem, NAO array).
 * Ref: data-model.md §Entity: Task; plan.md §Convencoes de Borda
 * Task 3.4.4
 */
import type { TaskDTO } from '@cstk-panel/shared-types';
import type { TaskRow } from '../db/queries/tasks.js';

type ValidOutcome = 'pass' | 'fail';

function toOutcome(raw: string | null): ValidOutcome | null {
  if (raw === 'pass' || raw === 'fail') return raw;
  return null;
}

export function mapTask(row: TaskRow): TaskDTO {
  return {
    wave: row.wave,
    executionId: row.execution_id,
    // title (schema v7 EN): texto livre untrusted; '' em bases v2 (query garante)
    title: row.title ?? '',
    outcome: toOutcome(row.outcome),
    testsRun: row.tests_run,
    testsPassed: row.tests_passed,
    // INTEGER 0/1 → boolean (null permanece null)
    lintOk: row.lint_ok === null ? null : row.lint_ok === 1,
    // INTEGER contagem → number (NAO array)
    touchedFilesCount: row.touched_files,
  };
}

export function mapTasks(rows: TaskRow[]): TaskDTO[] {
  return rows.map(mapTask);
}
