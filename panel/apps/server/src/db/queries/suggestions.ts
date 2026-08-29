/**
 * Queries read-only para a entidade `suggestions` (schema v5 — recall-suggestions).
 * Espelho de `state.json.sugestoes[]`: melhorias propostas pela IA a alguma skill
 * (diagnostico + proposta + referencias). Escopo por execucao; chave natural
 * (execution_id, source_id). O painel apenas LE — a fonte canonica e o state.json.
 *
 * Tolerancia de schema (Principio II): bases v<5 NAO tem a tabela `suggestions`.
 * `hasTable` e checado antes e a query degrada para vazio, em vez de lancar.
 *
 * FASE 2 (new-schema): Row interface migrada pt-BR→EN snake_case (task 2.9).
 */
import type Database from 'better-sqlite3';
import { hasTable, hasColumn } from '../columns.js';

export interface SuggestionRow {
  execution_id: string;
  source_id: string;
  affected_skill: string | null;
  severity: string | null;
  diagnosis: string | null;
  proposal: string | null;
  /** CSV de paths (join "," na ingestao); o mapper divide em array */
  referencias: string | null;
  issue_opened: string | null;
  created_at: string | null;
}

/** True se a base expoe a tabela `suggestions` (v5+). */
export function hasSuggestions(db: Database.Database): boolean {
  return hasTable(db, 'suggestions');
}

/**
 * Lista sugestoes de uma execucao, em ordem cronologica de criacao.
 * Degrada para [] em bases v<5 (sem a tabela).
 */
export function listSuggestionsByExecution(
  db: Database.Database,
  executionId: string
): SuggestionRow[] {
  if (!hasSuggestions(db)) return [];

  const execIdCol = hasColumn(db, 'suggestions', 'execution_id') ? 'execution_id' : 'NULL as execution_id';
  const affectedSkillCol = hasColumn(db, 'suggestions', 'affected_skill') ? 'affected_skill' : 'NULL as affected_skill';
  const severityCol = hasColumn(db, 'suggestions', 'severity') ? 'severity' : 'NULL as severity';
  const diagnosisCol = hasColumn(db, 'suggestions', 'diagnosis') ? 'diagnosis' : 'NULL as diagnosis';
  const proposalCol = hasColumn(db, 'suggestions', 'proposal') ? 'proposal' : 'NULL as proposal';
  const issueOpenedCol = hasColumn(db, 'suggestions', 'issue_opened') ? 'issue_opened' : 'NULL as issue_opened';
  // `referencias` coluna de CSV de paths (mantida como `referencias` no schema v5-v7;
  // coluna nao foi renomeada — `references` seria keyword SQL, mas nao e o nome do campo).
  const referenciasCol = hasColumn(db, 'suggestions', 'referencias')
    ? 'referencias'
    : 'NULL as referencias';
  // `created_at` maps to `source_ts` in the DB (ingested as created_at field)
  const createdAtCol = hasColumn(db, 'suggestions', 'created_at')
    ? 'created_at'
    : hasColumn(db, 'suggestions', 'source_ts')
      ? 'source_ts as created_at'
      : 'NULL as created_at';

  return db
    .prepare(`
      SELECT ${execIdCol}, source_id, ${affectedSkillCol}, ${severityCol},
             ${diagnosisCol}, ${proposalCol}, ${referenciasCol},
             ${issueOpenedCol}, ${createdAtCol}
      FROM suggestions
      WHERE execution_id = ?
      ORDER BY source_ts ASC, source_id ASC
    `)
    .all(executionId) as SuggestionRow[];
}
