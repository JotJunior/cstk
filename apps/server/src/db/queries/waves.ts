/**
 * Queries read-only para entidade waves.
 * Ref: data-model.md §Entity: Wave; contracts/api-read.md
 * Task 3.3.2
 *
 * FASE 2 (new-schema): Row interface migrada pt-BR→EN snake_case (task 2.2).
 * schema v10 (wave-token-metrics, cstk 5.25.0): 9 colunas `agent_*` com o
 * consumo real de subagentes. Base v<10 nao tem as colunas — projetadas como
 * NULL (Principio II). NULL sempre significa "nao ha numero" (nao coletado ou
 * nao observado); nunca vira 0 na borda (Principio III).
 */
import type Database from 'better-sqlite3';
import { hasColumn } from '../columns.js';

/** As 9 colunas de consumo de subagente introduzidas no schema v10. */
export const AGENT_USAGE_COLUMNS = [
  'agent_spawns_total',
  'agent_spawns_with_usage',
  'agent_total_tokens',
  'agent_input_tokens',
  'agent_output_tokens',
  'agent_cache_read_tokens',
  'agent_cache_creation_tokens',
  'agent_tool_use_count',
  'agent_duration_ms',
] as const;

export type AgentUsageColumn = (typeof AGENT_USAGE_COLUMNS)[number];

/**
 * Projeta uma coluna v10 de `waves`, degradando para `NULL as <col>` em base
 * v<10. `prefix` qualifica a tabela em JOIN/subconsulta (ex: 'w.').
 */
export function agentUsageSelect(
  db: Database.Database,
  column: AgentUsageColumn,
  prefix = '',
): string {
  return hasColumn(db, 'waves', column)
    ? `${prefix}${column}`
    : `NULL as ${column}`;
}

/** True quando a base tem as colunas de consumo de subagente (schema >= v10). */
export function hasAgentUsage(db: Database.Database): boolean {
  return hasColumn(db, 'waves', 'agent_total_tokens');
}

export interface WaveRow {
  wave: string;
  execution_id: string;
  stages: string;        // string unica — NAO array (schema v2)
  started_at: string | null;
  finished_at: string | null;
  wallclock_seconds: number | null;
  tool_calls: number | null;
  termination_reason: string | null;
  n_stages: number | null;
  n_skills: number | null;
  /** nome da sessao de worktree de origem (schema v8); NULL fora de sessao/bases v<8 */
  session: string | null;
  // schema v10 — consumo agregado dos spawns da onda; NULL = sem numero
  agent_spawns_total: number | null;
  agent_spawns_with_usage: number | null;
  agent_total_tokens: number | null;
  agent_input_tokens: number | null;
  agent_output_tokens: number | null;
  agent_cache_read_tokens: number | null;
  agent_cache_creation_tokens: number | null;
  agent_tool_use_count: number | null;
  agent_duration_ms: number | null;
}

/** Lista ondas de uma execucao, em ordem cronologica */
export function listWavesByExecution(
  db: Database.Database,
  executionId: string
): WaveRow[] {
  const execIdCol = hasColumn(db, 'waves', 'execution_id') ? 'execution_id' : 'NULL as execution_id';
  const stagesCol = hasColumn(db, 'waves', 'stages') ? 'stages' : 'NULL as stages';
  const startedCol = hasColumn(db, 'waves', 'started_at') ? 'started_at' : 'NULL as started_at';
  const finishedCol = hasColumn(db, 'waves', 'finished_at') ? 'finished_at' : 'NULL as finished_at';
  const terminationCol = hasColumn(db, 'waves', 'termination_reason') ? 'termination_reason' : 'NULL as termination_reason';
  const nStagesCol = hasColumn(db, 'waves', 'n_stages') ? 'n_stages' : 'NULL as n_stages';
  const sessionCol = hasColumn(db, 'waves', 'session') ? 'session' : 'NULL as session';
  const usageCols = AGENT_USAGE_COLUMNS.map(c => agentUsageSelect(db, c)).join(',\n             ');
  const orderCol = hasColumn(db, 'waves', 'started_at') ? 'started_at' : 'rowid';
  return db
    .prepare(`
      SELECT wave, ${execIdCol}, ${stagesCol}, ${startedCol}, ${finishedCol},
             wallclock_seconds, tool_calls, ${terminationCol},
             ${nStagesCol}, n_skills, ${sessionCol},
             ${usageCols}
      FROM waves
      WHERE execution_id = ?
      ORDER BY ${orderCol} ASC
    `)
    .all(executionId) as WaveRow[];
}
