/**
 * Queries read-only para entidade events.
 * Task 3.3.4
 *
 * FASE 2 (new-schema): Row interface migrada pt-BR→EN snake_case (task 2.6).
 */
import type Database from 'better-sqlite3';
import { hasColumn } from '../columns.js';

export interface EventRow {
  execution_id: string;
  event_type: string;
  timestamp: string;
  description: string | null;
}

/** Lista eventos de uma execucao em ordem cronologica */
export function listEventsByExecution(
  db: Database.Database,
  executionId: string
): EventRow[] {
  const execIdCol = hasColumn(db, 'events', 'execution_id') ? 'execution_id' : 'NULL as execution_id';
  const descCol = hasColumn(db, 'events', 'description') ? 'description' : 'NULL as description';
  return db
    .prepare(`
      SELECT ${execIdCol}, event_type, timestamp, ${descCol}
      FROM events
      WHERE execution_id = ?
      ORDER BY timestamp ASC
    `)
    .all(executionId) as EventRow[];
}
