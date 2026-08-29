/**
 * Queries read-only para entidade retros (retrospectivas).
 * Usado no detalhe de feature (CARD-FTD-06).
 *
 * FASE 2 (new-schema): Row interface migrada pt-BR→EN snake_case (task 2.8).
 */
import type Database from 'better-sqlite3';
import { hasColumn } from '../columns.js';

export interface RetroRow {
  execution_id: string;
  text: string | null;
  wave: string;
}

/** Lista retrospectivas de uma feature (todas as execucoes), mais recentes primeiro. */
export function listRetrosByFeature(
  db: Database.Database,
  project: string,
  feature: string
): RetroRow[] {
  const execIdCol = hasColumn(db, 'retros', 'execution_id') ? 'execution_id' : 'NULL as execution_id';
  const textCol = hasColumn(db, 'retros', 'text') ? 'text' : 'NULL as text';
  return db
    .prepare(`
      SELECT ${execIdCol}, ${textCol}, wave
      FROM retros
      WHERE project = ? AND feature = ?
      ORDER BY source_ts DESC
    `)
    .all(project, feature) as RetroRow[];
}
