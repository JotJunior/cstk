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
import { hasColumn, hasTable } from '../columns.js';

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

/**
 * Consumo REAL por onda (telemetria OTel do Claude Code, schema v11).
 *
 * Fonte distinta de `hasAgentUsage`: aquela vem do hook PostToolUse/Agent,
 * que so enxerga o que o spawn devolve — e o spawn do orquestrador ENVOLVE
 * a onda, entao o consumo dele nunca aparece la. Os contadores OTel sobem a
 * cada API request, entao cobrem main + subagent + auxiliary.
 *
 * Bancos v10 ou anteriores nao tem as colunas: a sonda evita o erro de
 * "no such column" e deixa a UI cair no estado honesto de "nao coletado".
 */
export function hasOtelUsage(db: Database.Database): boolean {
  return hasColumn(db, 'waves', 'otel_cost_usd');
}

/**
 * True quando a base tem a tabela `wave_model_usage` (schema v12, cstk 5.33.0).
 *
 * Grao onda x modelo — distinto de `hasOtelUsage` (grao onda). Bancos v2-v11
 * nao tem a TABELA (nao so a coluna): a sonda usa `hasTable`, nao `hasColumn`,
 * reproduzindo o mesmo padrao de degradacao (Principio II).
 * Ref: data-model.md Parte B; contracts/model-usage-endpoint.md Decision 4.
 */
export function hasModelUsage(db: Database.Database): boolean {
  return hasTable(db, 'wave_model_usage');
}

/**
 * True quando a base tem a tabela `loose_usage` (schema v13, cstk 6.6.0) —
 * consumo AVULSO de sessoes interativas, fora de qualquer execucao 00c.
 *
 * Grao processo x segmento x modelo, sem `feature`/`wave`/`execution_id` por
 * construcao (dec-005 do cstk: preencher com sentinela seria fabricar dado).
 * Vive aqui junto das demais sondas de capacidade apesar de nao ser grao-onda.
 * Ref: ../cstk/docs/specs/loose-usage-capture/data-model.md.
 */
export function hasLooseUsage(db: Database.Database): boolean {
  return hasTable(db, 'loose_usage');
}

/**
 * True quando a base tem a tabela `plan_usage` (schema v14, cstk 7.2.0) —
 * gauge `rate_limits` da CONTA (percentual consumido do plano por janela
 * `five_hour`/`seven_day`), capturado pelo hook `statusLine.command`.
 *
 * Nao e consumo de execucao: e o medidor do plano, sem
 * `feature`/`wave`/`execution_id` por construcao (mesmo racional de
 * `loose_usage`). Captura opt-in via `cstk statusline install` — tabela
 * presente e vazia significa "sem captura", nunca "plano em 0%".
 * Ref: ../cstk/docs/specs/plan-usage-capture/data-model.md.
 */
export function hasPlanUsage(db: Database.Database): boolean {
  return hasTable(db, 'plan_usage');
}

/** As 5 colunas de consumo medido por telemetria introduzidas no schema v11. */
export const OTEL_USAGE_COLUMNS = [
  'otel_cost_usd',
  'otel_cost_main_usd',
  'otel_cost_subagent_usd',
  'otel_total_tokens',
  'otel_subagent_tokens',
] as const;

export type OtelUsageColumn = (typeof OTEL_USAGE_COLUMNS)[number];

/**
 * As 8 colunas de breakdown de tokens por FONTE (main x subagente) e por TIPO
 * (input/output/cache_read/cache_creation) introduzidas no schema v12.
 *
 * Distintas das 5 de v11: aquelas dao custo e total; estas abrem QUAL parte do
 * token foi lida de cache — a diferenca entre uma onda cara e uma onda que
 * apenas releu contexto. Origem: `otel_usage.by_source.{main,subagent}`.
 *
 * Coletadas de forma INDEPENDENTE do lado main e do lado subagente: na base
 * real ha ondas com `by_source.subagent` e sem `by_source.main`. Por isso a
 * cobertura tem dois denominadores separados (ver `OtelUsageResult`), nunca um.
 */
export const OTEL_BREAKDOWN_COLUMNS = [
  'otel_main_input_tokens',
  'otel_main_output_tokens',
  'otel_main_cache_read_tokens',
  'otel_main_cache_creation_tokens',
  'otel_subagent_input_tokens',
  'otel_subagent_output_tokens',
  'otel_subagent_cache_read_tokens',
  'otel_subagent_cache_creation_tokens',
] as const;

export type OtelBreakdownColumn = (typeof OTEL_BREAKDOWN_COLUMNS)[number];

/**
 * True quando a base tem o breakdown por fonte (schema >= v12). Sonda a coluna
 * (nao a tabela `wave_model_usage`): as duas entram na mesma migracao v11->v12,
 * mas sao dados diferentes e uma base pode ter sido tocada a mao.
 */
export function hasOtelBreakdown(db: Database.Database): boolean {
  return hasColumn(db, 'waves', 'otel_main_input_tokens');
}

/**
 * Projeta uma coluna v12 de `waves`, degradando para `NULL as <col>` em base
 * v<12 — mesmo contrato de `agentUsageSelect`/`otelUsageSelect`.
 */
export function otelBreakdownSelect(
  db: Database.Database,
  column: OtelBreakdownColumn,
  prefix = '',
): string {
  return hasColumn(db, 'waves', column)
    ? `${prefix}${column}`
    : `NULL as ${column}`;
}

/**
 * Projeta uma coluna v11 de `waves`, degradando para `NULL as <col>` em base
 * v<11 — mesmo contrato de `agentUsageSelect`, para que a Row tenha sempre a
 * mesma forma independentemente da versao do schema.
 */
export function otelUsageSelect(
  db: Database.Database,
  column: OtelUsageColumn,
  prefix = '',
): string {
  return hasColumn(db, 'waves', column)
    ? `${prefix}${column}`
    : `NULL as ${column}`;
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
  // schema v11 — consumo medido pela telemetria OTel; fonte independente das
  // colunas agent_* (cobre tambem o gasto do proprio orquestrador).
  // Custo em USD e REAL/fracionario, nao inteiro.
  otel_cost_usd: number | null;
  otel_cost_main_usd: number | null;
  otel_cost_subagent_usd: number | null;
  otel_total_tokens: number | null;
  otel_subagent_tokens: number | null;
  // schema v12 — breakdown de tokens por fonte x tipo. Os dois lados sao
  // coletados independentemente: onda com subagent preenchido e main NULL e
  // caso REAL na base, nao anomalia.
  otel_main_input_tokens: number | null;
  otel_main_output_tokens: number | null;
  otel_main_cache_read_tokens: number | null;
  otel_main_cache_creation_tokens: number | null;
  otel_subagent_input_tokens: number | null;
  otel_subagent_output_tokens: number | null;
  otel_subagent_cache_read_tokens: number | null;
  otel_subagent_cache_creation_tokens: number | null;
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
  const otelCols = OTEL_USAGE_COLUMNS.map(c => otelUsageSelect(db, c)).join(',\n             ');
  const breakdownCols = OTEL_BREAKDOWN_COLUMNS.map(c => otelBreakdownSelect(db, c)).join(',\n             ');
  const orderCol = hasColumn(db, 'waves', 'started_at') ? 'started_at' : 'rowid';
  return db
    .prepare(`
      SELECT wave, ${execIdCol}, ${stagesCol}, ${startedCol}, ${finishedCol},
             wallclock_seconds, tool_calls, ${terminationCol},
             ${nStagesCol}, n_skills, ${sessionCol},
             ${usageCols},
             ${otelCols},
             ${breakdownCols}
      FROM waves
      WHERE execution_id = ?
      ORDER BY ${orderCol} ASC
    `)
    .all(executionId) as WaveRow[];
}
