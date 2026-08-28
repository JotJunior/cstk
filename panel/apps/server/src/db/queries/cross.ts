/**
 * Queries cross-execucao: alertas, tasks e events agregados.
 * Ref: contracts/api-read.md §Cross-execucao; spec.md FR-008, FR-009
 * Task 3.3.5
 *
 * Principio I (Read-Only Absoluto): apenas SELECT com prepared statements.
 * Todos os filtros via binding parametrizado — nunca interpolacao de string.
 *
 * Filtros suportados:
 * - alerts: type, project, feature, period (24h/7d/30d/all)
 * - tasks:  project, feature, outcome
 * - events: event_type, project, period
 *
 * FASE 2 (new-schema): todos os nomes pt-BR→EN snake_case (task 2.11).
 */
import type Database from 'better-sqlite3';
import { hasColumn } from '../columns.js';
import { titleSelect } from './tasks.js';

// ─────────────────────────────────────────────────────────
// Tipos de filtro
// ─────────────────────────────────────────────────────────

export type Period = '24h' | '7d' | '30d' | 'all';

function periodToSqlFilter(period: Period | undefined): string | null {
  switch (period) {
    case '24h': return "datetime('now', '-1 day')";
    case '7d':  return "datetime('now', '-7 days')";
    case '30d': return "datetime('now', '-30 days')";
    case 'all':
    default:    return null;
  }
}

export interface CrossAlertFilters {
  type?: string;
  project?: string;
  feature?: string;
  period?: Period;
  limit?: number;
  offset?: number;
}

export interface CrossTaskFilters {
  project?: string;
  feature?: string;
  outcome?: string;
  limit?: number;
  offset?: number;
}

export interface CrossEventFilters {
  event_type?: string;
  project?: string;
  period?: Period;
  limit?: number;
  offset?: number;
}

// ─────────────────────────────────────────────────────────
// Row shapes
// ─────────────────────────────────────────────────────────

export interface CrossAlertRow {
  execution_id: string;
  project: string;
  feature: string;
  type: string;
  subtype: string | null;
  consumed_value: number | null;
  threshold_value: number | null;
  description: string | null;
  wave: string;
}

export interface CrossTaskRow {
  wave: string;
  execution_id: string;
  project: string;
  feature: string;
  title: string;                    // schema v3; '' em bases v2 (FR-V3-005)
  outcome: string | null;
  tests_run: number | null;
  tests_passed: number | null;
  lint_ok: number | null;
  touched_files: number | null;
}

export interface CrossEventRow {
  execution_id: string;
  project: string;
  feature: string;
  event_type: string;
  timestamp: string;
  description: string | null;
}

// ─────────────────────────────────────────────────────────
// GET /alerts (cross-execucao)
// ─────────────────────────────────────────────────────────

/**
 * Lista alertas cross-execucao com filtros opcionais.
 * JOIN com executions para incluir project e feature (drill-down).
 */
export function listCrossAlerts(
  db: Database.Database,
  filters: CrossAlertFilters = {}
): CrossAlertRow[] {
  const typeCol = hasColumn(db, 'alert_signals', 'type') ? 'a.type' : "'' as type";
  const subtypeCol = hasColumn(db, 'alert_signals', 'subtype') ? 'a.subtype' : 'NULL as subtype';
  const consumedCol = hasColumn(db, 'alert_signals', 'consumed_value') ? 'a.consumed_value' : 'NULL as consumed_value';
  const thresholdCol = hasColumn(db, 'alert_signals', 'threshold_value') ? 'a.threshold_value' : 'NULL as threshold_value';
  const descCol = hasColumn(db, 'alert_signals', 'description') ? 'a.description' : 'NULL as description';
  const alertExecIdCol = hasColumn(db, 'alert_signals', 'execution_id') ? 'a.execution_id' : 'NULL as execution_id';
  const execIdCol = hasColumn(db, 'executions', 'execution_id') ? 'execution_id' : 'rowid';
  const startedCol = hasColumn(db, 'executions', 'started_at') ? 'started_at' : 'rowid';

  const conditions: string[] = [];
  const params: unknown[] = [];

  if (filters.type !== undefined) {
    conditions.push(`${hasColumn(db, 'alert_signals', 'type') ? 'a.type' : "''"}  = ?`);
    params.push(filters.type);
  }
  if (filters.project !== undefined) {
    conditions.push('e.project = ?');
    params.push(filters.project);
  }
  if (filters.feature !== undefined) {
    conditions.push('e.feature = ?');
    params.push(filters.feature);
  }

  const periodFilter = periodToSqlFilter(filters.period);
  if (periodFilter) {
    // alert_signals nao tem timestamp proprio — usar executions.started_at
    conditions.push(`e.${startedCol} >= ${periodFilter}`);
  }

  const limit = filters.limit ?? 50;
  const offset = filters.offset ?? 0;
  params.push(limit, offset);

  const where = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';

  return db
    .prepare(`
      SELECT ${alertExecIdCol}, e.project, e.feature,
             ${typeCol}, ${subtypeCol}, ${consumedCol}, ${thresholdCol},
             ${descCol}, a.wave
      FROM alert_signals a
      JOIN executions e ON e.${execIdCol} = a.${hasColumn(db, 'alert_signals', 'execution_id') ? 'execution_id' : 'rowid'}
      ${where}
      ORDER BY a.rowid DESC
      LIMIT ? OFFSET ?
    `)
    .all(...params) as CrossAlertRow[];
}

/** Contagem de alertas cross-execucao (para paginacao) */
export function countCrossAlerts(
  db: Database.Database,
  filters: Omit<CrossAlertFilters, 'limit' | 'offset'> = {}
): number {
  const execIdCol = hasColumn(db, 'executions', 'execution_id') ? 'execution_id' : 'rowid';
  const startedCol = hasColumn(db, 'executions', 'started_at') ? 'started_at' : 'rowid';
  const alertExecIdCol = hasColumn(db, 'alert_signals', 'execution_id') ? 'execution_id' : 'rowid';

  const conditions: string[] = [];
  const params: unknown[] = [];

  if (filters.type !== undefined) {
    conditions.push(`${hasColumn(db, 'alert_signals', 'type') ? 'a.type' : "''"} = ?`);
    params.push(filters.type);
  }
  if (filters.project !== undefined) {
    conditions.push('e.project = ?');
    params.push(filters.project);
  }
  if (filters.feature !== undefined) {
    conditions.push('e.feature = ?');
    params.push(filters.feature);
  }

  const periodFilter = periodToSqlFilter(filters.period);
  if (periodFilter) {
    conditions.push(`e.${startedCol} >= ${periodFilter}`);
  }

  const where = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';

  const row = db
    .prepare(`
      SELECT count(*) as n
      FROM alert_signals a
      JOIN executions e ON e.${execIdCol} = a.${alertExecIdCol}
      ${where}
    `)
    .get(...params) as { n: number };
  return row.n;
}

// ─────────────────────────────────────────────────────────
// GET /tasks (cross-execucao)
// ─────────────────────────────────────────────────────────

/**
 * Lista tasks cross-execucao com filtros opcionais.
 * JOIN com executions para incluir project e feature.
 */
export function listCrossTasks(
  db: Database.Database,
  filters: CrossTaskFilters = {}
): CrossTaskRow[] {
  const execIdCol = hasColumn(db, 'executions', 'execution_id') ? 'execution_id' : 'rowid';
  const taskExecIdCol = hasColumn(db, 'tasks', 'execution_id') ? 'execution_id' : 'rowid';
  const testsRunCol = hasColumn(db, 'tasks', 'tests_run') ? 't.tests_run' : 'NULL as tests_run';
  const testsPassedCol = hasColumn(db, 'tasks', 'tests_passed') ? 't.tests_passed' : 'NULL as tests_passed';
  const touchedCol = hasColumn(db, 'tasks', 'touched_files') ? 't.touched_files' : 'NULL as touched_files';

  const conditions: string[] = [];
  const params: unknown[] = [];

  if (filters.project !== undefined) {
    conditions.push('e.project = ?');
    params.push(filters.project);
  }
  if (filters.feature !== undefined) {
    conditions.push('e.feature = ?');
    params.push(filters.feature);
  }
  if (filters.outcome !== undefined) {
    conditions.push('t.outcome = ?');
    params.push(filters.outcome);
  }

  const limit = filters.limit ?? 50;
  const offset = filters.offset ?? 0;
  params.push(limit, offset);

  const where = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';

  return db
    .prepare(`
      SELECT t.wave, t.${taskExecIdCol} as execution_id, e.project, e.feature,
             ${titleSelect(db, 't.')},
             t.outcome, ${testsRunCol}, ${testsPassedCol},
             t.lint_ok, ${touchedCol}
      FROM tasks t
      JOIN executions e ON e.${execIdCol} = t.${taskExecIdCol}
      ${where}
      ORDER BY t.rowid ASC
      LIMIT ? OFFSET ?
    `)
    .all(...params) as CrossTaskRow[];
}

// ─────────────────────────────────────────────────────────
// GET /events (cross-execucao)
// ─────────────────────────────────────────────────────────

/**
 * Lista eventos cross-execucao com filtros opcionais.
 * JOIN com executions para incluir project e feature.
 */
export function listCrossEvents(
  db: Database.Database,
  filters: CrossEventFilters = {}
): CrossEventRow[] {
  const execIdCol = hasColumn(db, 'executions', 'execution_id') ? 'execution_id' : 'rowid';
  const evExecIdCol = hasColumn(db, 'events', 'execution_id') ? 'execution_id' : 'rowid';
  const descCol = hasColumn(db, 'events', 'description') ? 'ev.description' : 'NULL as description';

  const conditions: string[] = [];
  const params: unknown[] = [];

  if (filters.event_type !== undefined) {
    conditions.push('ev.event_type = ?');
    params.push(filters.event_type);
  }
  if (filters.project !== undefined) {
    conditions.push('e.project = ?');
    params.push(filters.project);
  }

  const periodFilter = periodToSqlFilter(filters.period);
  if (periodFilter) {
    conditions.push(`ev.timestamp >= ${periodFilter}`);
  }

  const limit = filters.limit ?? 50;
  const offset = filters.offset ?? 0;
  params.push(limit, offset);

  const where = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';

  return db
    .prepare(`
      SELECT ev.${evExecIdCol} as execution_id, e.project, e.feature,
             ev.event_type, ev.timestamp, ${descCol}
      FROM events ev
      JOIN executions e ON e.${execIdCol} = ev.${evExecIdCol}
      ${where}
      ORDER BY ev.timestamp ASC
      LIMIT ? OFFSET ?
    `)
    .all(...params) as CrossEventRow[];
}
