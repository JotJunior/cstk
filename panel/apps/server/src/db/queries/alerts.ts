/**
 * Queries read-only para entidade alert_signals.
 * Task 3.3.4
 *
 * FASE 2 (new-schema): Row interface migrada pt-BR→EN snake_case (task 2.7).
 */
import type Database from 'better-sqlite3';
import { hasColumn } from '../columns.js';

export interface AlertRow {
  execution_id: string;
  type: string;
  subtype: string | null;
  consumed_value: number | null;
  threshold_value: number | null;
  description: string | null;
  wave: string;
}

/** Lista alertas de uma execucao */
export function listAlertsByExecution(
  db: Database.Database,
  executionId: string
): AlertRow[] {
  const execIdCol = hasColumn(db, 'alert_signals', 'execution_id') ? 'execution_id' : 'NULL as execution_id';
  const typeCol = hasColumn(db, 'alert_signals', 'type') ? 'type' : "'' as type";
  const subtypeCol = hasColumn(db, 'alert_signals', 'subtype') ? 'subtype' : 'NULL as subtype';
  const consumedCol = hasColumn(db, 'alert_signals', 'consumed_value') ? 'consumed_value' : 'NULL as consumed_value';
  const thresholdCol = hasColumn(db, 'alert_signals', 'threshold_value') ? 'threshold_value' : 'NULL as threshold_value';
  const descCol = hasColumn(db, 'alert_signals', 'description') ? 'description' : 'NULL as description';
  return db
    .prepare(`
      SELECT ${execIdCol}, ${typeCol}, ${subtypeCol}, ${consumedCol},
             ${thresholdCol}, ${descCol}, wave
      FROM alert_signals
      WHERE execution_id = ?
      ORDER BY rowid ASC
    `)
    .all(executionId) as AlertRow[];
}
