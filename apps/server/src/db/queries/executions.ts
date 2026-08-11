/**
 * Queries read-only para entidade executions.
 * Ref: data-model.md §Entities; contracts/api-read.md; spec.md FR-001, FR-003
 * Task 3.3.1
 *
 * Principio I (Read-Only Absoluto): apenas SELECT com prepared statements.
 * Parametros sempre via binding — nunca interpolacao de string.
 *
 * FASE 2 (new-schema): Row interface migrada pt-BR→EN snake_case (task 2.1).
 */
import type Database from 'better-sqlite3';
import { hasColumn } from '../columns.js';
import { hasAgentUsage, hasOtelUsage, hasOtelBreakdown } from './waves.js';

/**
 * Colunas de consumo real de subagente para os rollups (schema v10). Sao
 * subconsultas correlacionadas sobre `waves` porque o dado vive na onda, nao
 * na execucao — e a query externa agrupa `executions`, onde um LEFT JOIN com
 * o agregado de ondas multiplicaria as somas por linha de execucao.
 *
 * `sum()` do SQLite retorna NULL quando nenhuma linha tem valor: e isso que
 * preserva a distincao "sem medicao" x "medido e deu zero" ate a UI.
 * Base v<10 (sem as colunas) projeta NULL literal — mesmo efeito.
 */
function agentUsageRollupSelect(db: Database.Database, scope: 'project' | 'feature'): string {
  const fields: Array<[string, string]> = [
    ['agent_spawns_total', 'sum(w.agent_spawns_total)'],
    ['agent_spawns_with_usage', 'sum(w.agent_spawns_with_usage)'],
    ['agent_total_tokens', 'sum(w.agent_total_tokens)'],
    ['agent_input_tokens', 'sum(w.agent_input_tokens)'],
    ['agent_output_tokens', 'sum(w.agent_output_tokens)'],
    ['agent_cache_read_tokens', 'sum(w.agent_cache_read_tokens)'],
    ['agent_cache_creation_tokens', 'sum(w.agent_cache_creation_tokens)'],
    ['agent_tool_use_count', 'sum(w.agent_tool_use_count)'],
    ['agent_duration_ms', 'sum(w.agent_duration_ms)'],
    ['agent_waves_with_usage', 'sum(CASE WHEN w.agent_spawns_total IS NOT NULL THEN 1 ELSE 0 END)'],
    ['agent_waves_total', 'count(*)'],
  ];
  if (!hasAgentUsage(db)) {
    return fields.map(([alias]) => `NULL as ${alias}`).join(',\n        ');
  }
  const corr = scope === 'project'
    ? 'w.project = e.project'
    : 'w.project = e.project AND w.feature = e.feature';
  return fields
    .map(([alias, expr]) => `(SELECT ${expr} FROM waves w WHERE ${corr}) as ${alias}`)
    .join(',\n        ');
}

/**
 * Consumo medido por telemetria OTel para os rollups (schema v11). Mesma
 * estrategia de subconsulta correlacionada de `agentUsageRollupSelect` — e o
 * mesmo motivo: o dado vive na onda, e um JOIN multiplicaria as somas.
 *
 * Base v<11 projeta NULL literal, entao a Row tem sempre a mesma forma e o
 * mapper nao precisa saber a versao do schema.
 */
function otelUsageRollupSelect(db: Database.Database, scope: 'project' | 'feature'): string {
  const v11Fields: Array<[string, string]> = [
    ['otel_cost_usd', 'sum(w.otel_cost_usd)'],
    ['otel_cost_main_usd', 'sum(w.otel_cost_main_usd)'],
    ['otel_cost_subagent_usd', 'sum(w.otel_cost_subagent_usd)'],
    ['otel_total_tokens', 'sum(w.otel_total_tokens)'],
    ['otel_subagent_tokens', 'sum(w.otel_subagent_tokens)'],
    ['otel_waves_with_usage', 'sum(CASE WHEN w.otel_cost_usd IS NOT NULL THEN 1 ELSE 0 END)'],
    ['otel_waves_total', 'count(*)'],
  ];
  // Breakdown por fonte (v12) tem sonda PROPRIA: uma base pode ter as 5 colunas
  // de custo (v11) sem as 8 de breakdown. Gatear os dois juntos projetaria NULL
  // no custo so porque o breakdown falta — ou pior, quebraria a query no caso
  // inverso.
  const v12Fields: Array<[string, string]> = [
    ['otel_main_input_tokens', 'sum(w.otel_main_input_tokens)'],
    ['otel_main_output_tokens', 'sum(w.otel_main_output_tokens)'],
    ['otel_main_cache_read_tokens', 'sum(w.otel_main_cache_read_tokens)'],
    ['otel_main_cache_creation_tokens', 'sum(w.otel_main_cache_creation_tokens)'],
    ['otel_subagent_input_tokens', 'sum(w.otel_subagent_input_tokens)'],
    ['otel_subagent_output_tokens', 'sum(w.otel_subagent_output_tokens)'],
    ['otel_subagent_cache_read_tokens', 'sum(w.otel_subagent_cache_read_tokens)'],
    ['otel_subagent_cache_creation_tokens', 'sum(w.otel_subagent_cache_creation_tokens)'],
    ['otel_waves_with_main_breakdown', 'sum(CASE WHEN w.otel_main_input_tokens IS NOT NULL THEN 1 ELSE 0 END)'],
    ['otel_waves_with_subagent_breakdown', 'sum(CASE WHEN w.otel_subagent_input_tokens IS NOT NULL THEN 1 ELSE 0 END)'],
  ];
  const corr = scope === 'project'
    ? 'w.project = e.project'
    : 'w.project = e.project AND w.feature = e.feature';
  const project = (fields: Array<[string, string]>, present: boolean): string[] =>
    present
      ? fields.map(([alias, expr]) => `(SELECT ${expr} FROM waves w WHERE ${corr}) as ${alias}`)
      : fields.map(([alias]) => `NULL as ${alias}`);
  return [
    ...project(v11Fields, hasOtelUsage(db)),
    ...project(v12Fields, hasOtelBreakdown(db)),
  ].join(',\n        ');
}

/**
 * Projecao tolerante a bases v6 onde a coluna ainda tem nome pt-BR.
 * Para cada coluna renomeada: se o novo nome existir usa-o; senao projeta NULL.
 */
function executionColumnsSelect(db: Database.Database): string {
  const cols: string[] = [
    'project',
    'feature',
    hasColumn(db, 'executions', 'execution_id')   ? 'execution_id'                 : 'NULL as execution_id',
    'status',
    hasColumn(db, 'executions', 'termination_reason') ? 'termination_reason'       : 'NULL as termination_reason',
    hasColumn(db, 'executions', 'current_stage')  ? 'current_stage'                : 'NULL as current_stage',
    hasColumn(db, 'executions', 'started_at')     ? 'started_at'                   : 'NULL as started_at',
    hasColumn(db, 'executions', 'finished_at')    ? 'finished_at'                  : 'NULL as finished_at',
    hasColumn(db, 'executions', 'duration_seconds') ? 'duration_seconds'           : 'NULL as duration_seconds',
    hasColumn(db, 'executions', 'suggested_stack')  ? 'suggested_stack'            : 'NULL as suggested_stack',
    hasColumn(db, 'executions', 'waves_total')    ? 'waves_total'                  : 'NULL as waves_total',
    'tool_calls_total',
    hasColumn(db, 'executions', 'wallclock_total_seconds') ? 'wallclock_total_seconds' : 'NULL as wallclock_total_seconds',
    hasColumn(db, 'executions', 'subagents_spawned') ? 'subagents_spawned'         : 'NULL as subagents_spawned',
    hasColumn(db, 'executions', 'max_depth')      ? 'max_depth'                    : 'NULL as max_depth',
    hasColumn(db, 'executions', 'decisions_total') ? 'decisions_total'             : 'NULL as decisions_total',
    hasColumn(db, 'executions', 'human_blocks_total') ? 'human_blocks_total'       : 'NULL as human_blocks_total',
    hasColumn(db, 'executions', 'skill_suggestions_total') ? 'skill_suggestions_total' : 'NULL as skill_suggestions_total',
    hasColumn(db, 'executions', 'toolkit_issues_opened') ? 'toolkit_issues_opened' : 'NULL as toolkit_issues_opened',
    // session (schema v8 — recall-worktree-identity): NULL em bases v<8 e em execucoes sem sessao
    hasColumn(db, 'executions', 'session') ? 'session' : 'NULL as session',
  ];
  return cols.join(', ');
}

export interface ExecutionRow {
  project: string;
  feature: string;
  execution_id: string;
  status: string | null;
  termination_reason: string | null;
  current_stage: string | null;
  started_at: string | null;
  finished_at: string | null;
  duration_seconds: number | null;
  suggested_stack: string | null;
  waves_total: number | null;
  tool_calls_total: number | null;
  wallclock_total_seconds: number | null;
  subagents_spawned: number | null;
  max_depth: number | null;
  decisions_total: number | null;
  human_blocks_total: number | null;
  skill_suggestions_total: number | null;
  toolkit_issues_opened: number | null;
  /** nome da sessao de worktree de origem (schema v8); NULL fora de sessao/bases v<8 */
  session: string | null;
}

/**
 * Consumo real de subagentes somado a partir de `waves` (schema v10).
 * Presente em ExecutionRollupRow e FeatureRollupRow. NULL em base v<10 ou
 * quando nenhuma onda do recorte tem medicao — nunca 0 (Principio III).
 */
export interface AgentUsageRollupRow {
  agent_spawns_total: number | null;
  agent_spawns_with_usage: number | null;
  agent_total_tokens: number | null;
  agent_input_tokens: number | null;
  agent_output_tokens: number | null;
  agent_cache_read_tokens: number | null;
  agent_cache_creation_tokens: number | null;
  agent_tool_use_count: number | null;
  agent_duration_ms: number | null;
  agent_waves_with_usage: number | null;
  agent_waves_total: number | null;
}

/**
 * Consumo medido por telemetria OTel somado a partir de `waves` (schema v11).
 * NULL em base v<11 ou quando nenhuma onda do recorte teve coleta — nunca 0.
 */
export interface OtelUsageRollupRow {
  otel_cost_usd: number | null;
  otel_cost_main_usd: number | null;
  otel_cost_subagent_usd: number | null;
  otel_total_tokens: number | null;
  otel_subagent_tokens: number | null;
  otel_waves_with_usage: number | null;
  otel_waves_total: number | null;
  // schema v12 — breakdown por fonte x tipo. Cobertura em dois denominadores
  // porque main e subagente sao coletados independentemente (ver waves.ts).
  otel_main_input_tokens: number | null;
  otel_main_output_tokens: number | null;
  otel_main_cache_read_tokens: number | null;
  otel_main_cache_creation_tokens: number | null;
  otel_subagent_input_tokens: number | null;
  otel_subagent_output_tokens: number | null;
  otel_subagent_cache_read_tokens: number | null;
  otel_subagent_cache_creation_tokens: number | null;
  otel_waves_with_main_breakdown: number | null;
  otel_waves_with_subagent_breakdown: number | null;
}

export interface ExecutionRollupRow extends AgentUsageRollupRow, OtelUsageRollupRow {
  project: string;
  total_executions: number;
  active_executions: number;
  completed_executions: number;
  aborted_executions: number;
  total_decisions: number;
  total_tool_calls: number | null;
  total_wallclock: number | null;
  open_alerts: number;
  latest_execution_at: string | null;
}

export interface FeatureRollupRow extends AgentUsageRollupRow, OtelUsageRollupRow {
  project: string;
  feature: string;
  total_executions: number;
  active_executions: number;
  completed_executions: number;
  aborted_executions: number;
  total_tool_calls: number | null;
  total_wallclock: number | null;
  total_decisions: number;
  total_waves: number | null;
  total_blocks: number;
  current_stage: string | null;
  open_alerts: number;
  latest_status: string | null;
  latest_execution_at: string | null;
}

/** Lista todas as execucoes, mais recentes primeiro */
export function listExecutions(db: Database.Database): ExecutionRow[] {
  const cols = executionColumnsSelect(db);
  const orderBy = hasColumn(db, 'executions', 'started_at') ? 'started_at' : 'rowid';
  return db
    .prepare(`
      SELECT ${cols}
      FROM executions
      ORDER BY ${orderBy} DESC
    `)
    .all() as ExecutionRow[];
}

/** Projecao minima usada pelo watcher — so as colunas necessarias para derivar o state-dir. */
export interface WatcherExecutionRow {
  project: string;
  feature: string | null;
  execution_id: string;
  /** Status bruto da execucao — o watcher classifica ativa/terminal em JS. */
  status: string | null;
  /** Caminho do projeto-alvo persistido pelo ingest (schema v9, cstk >= 5.19);
   *  null em db v8 (coluna ausente) ou execucao sem o campo no state.json.
   *  UNTRUSTED — validar via validateProjectRootPath() antes de usar. */
  target_project_path: string | null;
}

/**
 * Lista TODAS as execucoes com a projecao minima do watcher de ingestao
 * (task 2.1.2, FR-001/FR-003 + descoberta via filesystem). Sem filtro de
 * status na query: o watcher precisa distinguir tres casos — execucao ativa
 * (observa via db), state-dir conhecido de execucao terminal (observa
 * mudancas via filesystem) e state-dir sem NENHUMA linha (ingestao inicial).
 * Projecao minima (sem as ~19 colunas de metricas de
 * `executionColumnsSelect`): o watcher so precisa de `project`/`feature`
 * para derivar o state-dir (Decision 3).
 */
export function listExecutionsForWatcher(db: Database.Database): WatcherExecutionRow[] {
  const featureCol = hasColumn(db, 'executions', 'feature') ? 'feature' : 'NULL as feature';
  const idCol = hasColumn(db, 'executions', 'execution_id') ? 'execution_id' : 'NULL as execution_id';
  const pathCol = hasColumn(db, 'executions', 'target_project_path')
    ? 'target_project_path'
    : 'NULL as target_project_path';
  return db
    .prepare(`
      SELECT project, ${featureCol}, ${idCol}, status, ${pathCol}
      FROM executions
    `)
    .all() as WatcherExecutionRow[];
}

/**
 * Raizes de projeto distintas ja persistidas pelo ingest (schema v9,
 * executions.target_project_path) — QUALQUER status. Alimenta a descoberta
 * via filesystem do watcher: um `state.json` de feature nova em projeto ja
 * conhecido pode existir no disco antes de qualquer linha em `executions`.
 * Valores UNTRUSTED (Principio V) — o consumidor valida via
 * validateProjectRootPath(). Nunca lanca; coluna ausente (db v8) ⇒ [].
 */
export function listKnownProjectRoots(db: Database.Database): string[] {
  try {
    if (!hasColumn(db, 'executions', 'target_project_path')) return [];
    const rows = db
      .prepare(`
        SELECT DISTINCT target_project_path AS p
        FROM executions
        WHERE target_project_path IS NOT NULL AND TRIM(target_project_path) != ''
      `)
      .all() as Array<{ p: string }>;
    return rows.map(r => r.p);
  } catch {
    return [];
  }
}

/** Busca execucao por ID */
export function getExecution(
  db: Database.Database,
  executionId: string
): ExecutionRow | undefined {
  const cols = executionColumnsSelect(db);
  const idCol = hasColumn(db, 'executions', 'execution_id') ? 'execution_id' : 'execution_id';
  return db
    .prepare(`
      SELECT ${cols}
      FROM executions
      WHERE ${idCol} = ?
    `)
    .get(executionId) as ExecutionRow | undefined;
}

/** Lista execucoes por projeto */
export function listExecutionsByProject(
  db: Database.Database,
  project: string
): ExecutionRow[] {
  const cols = executionColumnsSelect(db);
  const orderBy = hasColumn(db, 'executions', 'started_at') ? 'started_at' : 'rowid';
  return db
    .prepare(`
      SELECT ${cols}
      FROM executions
      WHERE project = ?
      ORDER BY ${orderBy} DESC
    `)
    .all(project) as ExecutionRow[];
}

/** Rollup por projeto */
export function getRollupByProject(db: Database.Database, project: string | null = null): ExecutionRollupRow[] {
  const decCol = hasColumn(db, 'executions', 'decisions_total') ? 'decisions_total' : '0';
  const wallCol = hasColumn(db, 'executions', 'wallclock_total_seconds') ? 'wallclock_total_seconds' : '0';
  const startedCol = hasColumn(db, 'executions', 'started_at') ? 'started_at' : 'rowid';
  return db
    .prepare(`
      SELECT
        project,
        count(*) as total_executions,
        sum(CASE WHEN status IN ('em_andamento','aguardando_humano') THEN 1 ELSE 0 END) as active_executions,
        sum(CASE WHEN status = 'concluida' THEN 1 ELSE 0 END) as completed_executions,
        sum(CASE WHEN status = 'abortada' THEN 1 ELSE 0 END) as aborted_executions,
        sum(coalesce(${decCol}, 0)) as total_decisions,
        sum(tool_calls_total) as total_tool_calls,
        sum(${wallCol}) as total_wallclock,
        (SELECT count(*) FROM alert_signals a WHERE a.project = e.project) as open_alerts,
        max(${startedCol}) as latest_execution_at,
        ${agentUsageRollupSelect(db, 'project')},
        ${otelUsageRollupSelect(db, 'project')}
      FROM executions e
      WHERE (@project IS NULL OR e.project = @project)
      GROUP BY project
      ORDER BY project
    `)
    .all({ project }) as ExecutionRollupRow[];
}

/** Rollup por projeto+feature. Filtro opcional por project (overview escopado). */
export function getRollupByFeature(db: Database.Database, project: string | null = null): FeatureRollupRow[] {
  const decCol = hasColumn(db, 'executions', 'decisions_total') ? 'decisions_total' : '0';
  const wallCol = hasColumn(db, 'executions', 'wallclock_total_seconds') ? 'wallclock_total_seconds' : '0';
  const wavesCol = hasColumn(db, 'executions', 'waves_total') ? 'waves_total' : '0';
  const blocksCol = hasColumn(db, 'executions', 'human_blocks_total') ? 'human_blocks_total' : '0';
  const stageCol = hasColumn(db, 'executions', 'current_stage') ? 'current_stage' : 'NULL';
  const startedCol = hasColumn(db, 'executions', 'started_at') ? 'started_at' : 'rowid';
  return db
    .prepare(`
      SELECT
        project,
        feature,
        count(*) as total_executions,
        sum(CASE WHEN status IN ('em_andamento','aguardando_humano') THEN 1 ELSE 0 END) as active_executions,
        sum(CASE WHEN status = 'concluida' THEN 1 ELSE 0 END) as completed_executions,
        sum(CASE WHEN status = 'abortada' THEN 1 ELSE 0 END) as aborted_executions,
        sum(tool_calls_total) as total_tool_calls,
        sum(${wallCol}) as total_wallclock,
        sum(coalesce(${decCol}, 0)) as total_decisions,
        sum(coalesce(${wavesCol}, 0)) as total_waves,
        sum(coalesce(${blocksCol}, 0)) as total_blocks,
        (SELECT ${stageCol} FROM executions e2
         WHERE e2.project = e.project AND e2.feature = e.feature
         ORDER BY ${startedCol} DESC LIMIT 1) as current_stage,
        (SELECT status FROM executions e2
         WHERE e2.project = e.project AND e2.feature = e.feature
         ORDER BY ${startedCol} DESC LIMIT 1) as latest_status,
        (SELECT count(*) FROM alert_signals a
         WHERE a.project = e.project AND a.feature = e.feature) as open_alerts,
        max(${startedCol}) as latest_execution_at,
        ${agentUsageRollupSelect(db, 'feature')},
        ${otelUsageRollupSelect(db, 'feature')}
      FROM executions e
      WHERE (@project IS NULL OR e.project = @project)
      GROUP BY project, feature
      ORDER BY project, feature
    `)
    .all({ project }) as FeatureRollupRow[];
}
