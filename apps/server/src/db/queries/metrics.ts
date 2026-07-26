/**
 * Queries de metricas agregadas — 8 endpoints de metricas.
 * Ref: contracts/api-read.md §Metricas agregadas; spec.md FR-008, FR-009
 * Task 3.3.6
 *
 * Principio III (Honestidade de Metrica):
 * - toolCallsTotal = proxy de custo; NUNCA rotular como "$" ou "tokens" na UI.
 * - clarify-resolution: meta.approximate=true (taxa derivada/estimada).
 * - mix de modelos: nao tem endpoint — card "indisponivel nesta fonte" na UI.
 * - agent-usage / tokens-over-time (schema v10): tokens MEDIDOS pelo harness e
 *   persistidos por `cstk recall`. Sao dado real, nao proxy — mas AMOSTRA:
 *   spawns em background nao reportam uso. Todo consumidor recebe
 *   spawnsWithUsage/spawnsTotal junto e MUST exibir o denominador. Continua
 *   proibido converter token em "$"/USD (o painel nao conhece preco).
 *
 * Todos os filtros via binding parametrizado.
 *
 * FASE 2 (new-schema): todos os nomes pt-BR→EN snake_case (task 2.10).
 */
import type Database from 'better-sqlite3';
import { hasColumn } from '../columns.js';
import { hasAgentUsage, hasOtelUsage } from './waves.js';

export type MetricPeriod = '24h' | '7d' | '30d' | 'all';

function periodToFilter(period: MetricPeriod | undefined): string | null {
  switch (period) {
    case '24h': return "datetime('now', '-1 day')";
    case '7d':  return "datetime('now', '-7 days')";
    case '30d': return "datetime('now', '-30 days')";
    case 'all':
    default:    return null;
  }
}

// ─────────────────────────────────────────────────────────
// 1. cost-over-time — serie temporal por dia
// ─────────────────────────────────────────────────────────

export interface CostOverTimeRow {
  day: string;       // date(started_at) → 'YYYY-MM-DD'
  toolCalls: number; // proxy de custo — NUNCA rotular como "$" na UI
}

export function getCostOverTime(
  db: Database.Database,
  filters: { project?: string; period?: MetricPeriod } = {}
): CostOverTimeRow[] {
  const startedAtCol = hasColumn(db, 'executions', 'started_at') ? 'started_at' : 'rowid';
  const conditions: string[] = ["tool_calls_total IS NOT NULL"];
  const params: unknown[] = [];

  if (filters.project !== undefined) {
    conditions.push('project = ?');
    params.push(filters.project);
  }

  const pf = periodToFilter(filters.period);
  if (pf) {
    conditions.push(`${startedAtCol} >= ${pf}`);
  }

  const where = `WHERE ${conditions.join(' AND ')}`;
  return db
    .prepare(`
      SELECT date(${startedAtCol}) as day,
             sum(tool_calls_total) as toolCalls
      FROM executions
      ${where}
      GROUP BY date(${startedAtCol})
      ORDER BY day ASC
    `)
    .all(...params) as CostOverTimeRow[];
}

// ─────────────────────────────────────────────────────────
// 2. throughput-by-stage — decisoes por stage
// ─────────────────────────────────────────────────────────

export interface ThroughputByStageRow {
  stage: string;
  count: number;
}

export function getThroughputByStage(db: Database.Database): ThroughputByStageRow[] {
  const stageCol = hasColumn(db, 'decisions', 'stage') ? 'stage' : 'NULL';
  return db
    .prepare(`
      SELECT ${stageCol} as stage, count(*) as count
      FROM decisions
      WHERE ${stageCol} IS NOT NULL
      GROUP BY ${stageCol}
      ORDER BY count DESC
    `)
    .all() as ThroughputByStageRow[];
}

// ─────────────────────────────────────────────────────────
// 3. test-pass-rate — taxa de testes passando nas tasks
// ─────────────────────────────────────────────────────────

export interface TestPassRateResult {
  pass: number;
  fail: number;
  rate: number;  // 0..1
}

export function getTestPassRate(db: Database.Database): TestPassRateResult {
  const row = db
    .prepare(`
      SELECT
        sum(CASE WHEN outcome = 'pass' THEN 1 ELSE 0 END) as pass,
        sum(CASE WHEN outcome = 'fail' THEN 1 ELSE 0 END) as fail
      FROM tasks
      WHERE outcome IS NOT NULL
    `)
    .get() as { pass: number | null; fail: number | null };

  const pass = row.pass ?? 0;
  const fail = row.fail ?? 0;
  const total = pass + fail;
  const rate = total > 0 ? pass / total : 0;

  return { pass, fail, rate };
}

// ─────────────────────────────────────────────────────────
// 3b. test-pass-rate-series — taxa de testes passando por DIA
//     (tasks nao tem timestamp; agrupa por date(executions.started_at))
// ─────────────────────────────────────────────────────────

export interface TestPassRateSeriesRow {
  day: string;   // 'YYYY-MM-DD'
  pass: number;
  fail: number;
  rate: number;  // 0..1
}

export function getTestPassRateSeries(
  db: Database.Database,
  filters: { period?: MetricPeriod } = {}
): TestPassRateSeriesRow[] {
  const startedAtCol = hasColumn(db, 'executions', 'started_at') ? 'started_at' : 'rowid';
  const execIdCol = hasColumn(db, 'executions', 'execution_id') ? 'execution_id' : 'rowid';
  const taskExecIdCol = hasColumn(db, 'tasks', 'execution_id') ? 'execution_id' : 'rowid';
  const conditions: string[] = ['t.outcome IS NOT NULL'];
  const pf = periodToFilter(filters.period);
  if (pf) conditions.push(`e.${startedAtCol} >= ${pf}`);
  const where = `WHERE ${conditions.join(' AND ')}`;

  const rows = db
    .prepare(`
      SELECT date(e.${startedAtCol}) as day,
             sum(CASE WHEN t.outcome = 'pass' THEN 1 ELSE 0 END) as pass,
             sum(CASE WHEN t.outcome = 'fail' THEN 1 ELSE 0 END) as fail
      FROM tasks t
      JOIN executions e ON e.${execIdCol} = t.${taskExecIdCol}
      ${where}
      GROUP BY day
      ORDER BY day ASC
    `)
    .all() as { day: string | null; pass: number | null; fail: number | null }[];

  return rows
    .filter(r => r.day != null)
    .map(r => {
      const pass = r.pass ?? 0;
      const fail = r.fail ?? 0;
      const total = pass + fail;
      return { day: r.day as string, pass, fail, rate: total > 0 ? pass / total : 0 };
    });
}

// ─────────────────────────────────────────────────────────
// 4. human-latency — latencia de resolucao de bloqueios humanos
// ─────────────────────────────────────────────────────────

export interface HumanLatencyRow {
  executionId: string;
  latencySeconds: number | null;
}

export function getHumanLatency(db: Database.Database): HumanLatencyRow[] {
  const execIdCol = hasColumn(db, 'executions', 'execution_id') ? 'execution_id' : 'rowid';
  const blocksCol = hasColumn(db, 'executions', 'human_blocks_total') ? 'human_blocks_total' : '0';
  const durCol = hasColumn(db, 'executions', 'duration_seconds') ? 'duration_seconds' : 'NULL';
  // Estimar latencia como duration_seconds / human_blocks_total
  // (aproximacao — dados reais de timestamps de bloqueio nao estao no schema v2)
  return db
    .prepare(`
      SELECT ${execIdCol} as executionId,
             CASE
               WHEN ${blocksCol} > 0 AND ${durCol} IS NOT NULL
               THEN round(${durCol} / ${blocksCol}, 2)
               ELSE NULL
             END as latencySeconds
      FROM executions
      WHERE ${blocksCol} > 0
      ORDER BY latencySeconds DESC
      LIMIT 50
    `)
    .all() as HumanLatencyRow[];
}

// ─────────────────────────────────────────────────────────
// 5. clarify-resolution — taxa de perguntas respondidas autonomamente
//    meta.approximate = TRUE (Principio III — taxa derivada/estimada)
// ─────────────────────────────────────────────────────────

export interface ClarifyResolutionResult {
  totalClarifyDecisions: number;
  autonomouslyResolved: number; // score >= 2 (sem pausa humana)
  humanPaused: number;          // score = 0 (pause_humano)
  rate: number;                 // 0..1 — APPROXIMATE
}

/**
 * ATENCAO: este resultado e APPROXIMATE (Principio III).
 * A taxa e derivada contando decisoes score>=2 em stage=clarify.
 * Isso e uma estimativa — nao ha dado exato de "clarify resolvido autonomamente".
 * O caller DEVE retornar meta.approximate=true.
 */
export function getClarifyResolution(db: Database.Database): ClarifyResolutionResult {
  const stageCol = hasColumn(db, 'decisions', 'stage') ? 'stage' : 'NULL';
  const row = db
    .prepare(`
      SELECT
        count(*) as total,
        sum(CASE WHEN score >= 2 THEN 1 ELSE 0 END) as autonomous,
        sum(CASE WHEN score = 0 THEN 1 ELSE 0 END) as human_paused
      FROM decisions
      WHERE ${stageCol} = 'clarify'
    `)
    .get() as { total: number | null; autonomous: number | null; human_paused: number | null };

  const total = row.total ?? 0;
  const autonomous = row.autonomous ?? 0;
  const humanPaused = row.human_paused ?? 0;
  const rate = total > 0 ? autonomous / total : 0;

  return {
    totalClarifyDecisions: total,
    autonomouslyResolved: autonomous,
    humanPaused: humanPaused,
    rate,
  };
}

// ─────────────────────────────────────────────────────────
// 6. decisions-by-score — distribuicao de scores
// ─────────────────────────────────────────────────────────

export interface DecisionsByScoreRow {
  score: number | null;
  count: number;
}

export function getDecisionsByScore(db: Database.Database): DecisionsByScoreRow[] {
  return db
    .prepare(`
      SELECT score, count(*) as count
      FROM decisions
      GROUP BY score
      ORDER BY score ASC
    `)
    .all() as DecisionsByScoreRow[];
}

// ─────────────────────────────────────────────────────────
// 7. execution-duration — duracao por execucao
// ─────────────────────────────────────────────────────────

export interface ExecutionDurationRow {
  executionId: string;
  project: string;
  feature: string;
  durationSeconds: number | null;
  waves: number | null;
}

export function getExecutionDuration(
  db: Database.Database,
  filters: { project?: string; period?: MetricPeriod } = {}
): ExecutionDurationRow[] {
  const execIdCol = hasColumn(db, 'executions', 'execution_id') ? 'execution_id' : 'rowid';
  const durCol = hasColumn(db, 'executions', 'duration_seconds') ? 'duration_seconds' : 'NULL';
  const wavesCol = hasColumn(db, 'executions', 'waves_total') ? 'waves_total' : 'NULL';
  const startedAtCol = hasColumn(db, 'executions', 'started_at') ? 'started_at' : 'rowid';
  const conditions: string[] = [`${durCol} IS NOT NULL`];
  const params: unknown[] = [];

  if (filters.project !== undefined) {
    conditions.push('project = ?');
    params.push(filters.project);
  }

  const pf = periodToFilter(filters.period);
  if (pf) {
    conditions.push(`${startedAtCol} >= ${pf}`);
  }

  const where = `WHERE ${conditions.join(' AND ')}`;
  return db
    .prepare(`
      SELECT ${execIdCol} as executionId, project, feature,
             ${durCol} as durationSeconds, ${wavesCol} as waves
      FROM executions
      ${where}
      ORDER BY ${durCol} DESC
      LIMIT 100
    `)
    .all(...params) as ExecutionDurationRow[];
}

// ─────────────────────────────────────────────────────────
// 8. depth-subagents — profundidade e subagentes por execucao
// ─────────────────────────────────────────────────────────

export interface DepthSubagentsRow {
  executionId: string;
  project: string;
  feature: string;
  maxDepth: number | null;
  subagentsSpawned: number | null;
}

export function getDepthSubagents(db: Database.Database): DepthSubagentsRow[] {
  const execIdCol = hasColumn(db, 'executions', 'execution_id') ? 'execution_id' : 'rowid';
  const maxDepthCol = hasColumn(db, 'executions', 'max_depth') ? 'max_depth' : 'NULL';
  const subagentsCol = hasColumn(db, 'executions', 'subagents_spawned') ? 'subagents_spawned' : 'NULL';
  return db
    .prepare(`
      SELECT ${execIdCol} as executionId, project, feature,
             ${maxDepthCol} as maxDepth,
             ${subagentsCol} as subagentsSpawned
      FROM executions
      WHERE ${maxDepthCol} IS NOT NULL
         OR ${subagentsCol} IS NOT NULL
      ORDER BY ${maxDepthCol} DESC NULLS LAST
      LIMIT 100
    `)
    .all() as DepthSubagentsRow[];
}

// ─────────────────────────────────────────────────────────
// 9. model-mix — DERIVADO das decisoes de roteamento (choice='model:%')
//    Intenção do roteador, NAO confirmação da harness. Dono canônico
//    do relatorio: model-routing-report.sh (FR-010 — UI rotula como derivado).
// ─────────────────────────────────────────────────────────

export interface ModelMixRow { modelo: string; n: number; }
export interface ModelMixByStageRow { stage: string; modelo: string; n: number; }

/** Mix total de modelos (donut). */
export function getModelMix(db: Database.Database): ModelMixRow[] {
  const choiceCol = hasColumn(db, 'decisions', 'choice') ? 'choice' : 'NULL';
  return db
    .prepare(`
      SELECT replace(${choiceCol}, 'model:', '') as modelo, count(*) as n
      FROM decisions
      WHERE ${choiceCol} LIKE 'model:%'
      GROUP BY modelo
      ORDER BY n DESC
    `)
    .all() as ModelMixRow[];
}

/** Mix de modelos por stage SDD (barras empilhadas). */
export function getModelMixByStage(db: Database.Database): ModelMixByStageRow[] {
  const choiceCol = hasColumn(db, 'decisions', 'choice') ? 'choice' : 'NULL';
  const stageCol = hasColumn(db, 'decisions', 'stage') ? 'stage' : 'NULL';
  return db
    .prepare(`
      SELECT ${stageCol} as stage, replace(${choiceCol}, 'model:', '') as modelo, count(*) as n
      FROM decisions
      WHERE ${choiceCol} LIKE 'model:%' AND ${stageCol} IS NOT NULL
      GROUP BY ${stageCol}, modelo
      ORDER BY ${stageCol} ASC
    `)
    .all() as ModelMixByStageRow[];
}

// ─────────────────────────────────────────────────────────
// 10. recall-consultations — consultas ao histórico (read-back loop, schema v3)
//     Evento `recall_consulted` gravado a cada `cstk recall --context` no
//     início de specify/plan, INCLUSIVE com hits=0. A `description` carrega
//     `etapa=… hits=N`. Contagem EXATA (Princípio III — não proxy/aproximada).
//     produtivas = hits>0; vazias = total - produtivas (inclui description sem
//     `hits=` parseável, que degrada para vazia sem quebrar — FR-V3-007).
// ─────────────────────────────────────────────────────────

export interface RecallConsultationsResult {
  total: number;
  produtivas: number; // hits > 0
  vazias: number;     // hits = 0 ou description sem hits parseável
}

const HITS_RE = /hits=(\d+)/;

// ─────────────────────────────────────────────────────────
// 11. agent-usage — consumo REAL de subagentes (schema v10)
//     Fonte: waves.agent_* (agregado por `cstk recall --ingest` a partir de
//     .waves[].agent_usage do state.json). Nao e proxy nem estimativa.
//     AMOSTRA: spawns sem dado de uso (background/async) entram em
//     spawnsTotal mas nao em spawnsWithUsage — o denominador acompanha o
//     total para que a UI nunca apresente parcial como completo (SC-004 do
//     cstk / Principio III do painel).
// ─────────────────────────────────────────────────────────

export interface AgentUsageResult {
  spawnsTotal: number | null;
  spawnsWithUsage: number | null;
  totalTokens: number | null;
  inputTokens: number | null;
  outputTokens: number | null;
  cacheReadTokens: number | null;
  cacheCreationTokens: number | null;
  toolUseCount: number | null;
  durationMs: number | null;
  /** ondas com metrica coletada (agent_spawns_total NAO nulo) */
  wavesWithUsage: number | null;
  /** ondas no recorte, coletadas ou nao */
  wavesTotal: number | null;
}

/** Recorte vazio/base v<10 — todos os campos null, nunca 0 (Principio III). */
const EMPTY_AGENT_USAGE: AgentUsageResult = {
  spawnsTotal: null, spawnsWithUsage: null, totalTokens: null,
  inputTokens: null, outputTokens: null, cacheReadTokens: null,
  cacheCreationTokens: null, toolUseCount: null, durationMs: null,
  wavesWithUsage: null, wavesTotal: null,
};

/** Filtros comuns das metricas de consumo (grao = onda). */
export interface AgentUsageFilters {
  project?: string;
  feature?: string;
  period?: MetricPeriod;
}

/**
 * Monta WHERE + params para consultas sobre `waves`.
 * O filtro de periodo usa `waves.started_at` (a onda tem timestamp proprio —
 * nao precisa do JOIN com executions), degradando para `source_ts` em base
 * sem a coluna.
 */
function waveScope(
  db: Database.Database,
  filters: AgentUsageFilters,
): { where: string; params: unknown[]; startedCol: string } {
  const startedCol = hasColumn(db, 'waves', 'started_at')
    ? "coalesce(started_at, source_ts)"
    : 'source_ts';
  const conditions: string[] = [];
  const params: unknown[] = [];
  if (filters.project !== undefined) {
    conditions.push('project = ?');
    params.push(filters.project);
  }
  if (filters.feature !== undefined) {
    conditions.push('feature = ?');
    params.push(filters.feature);
  }
  const pf = periodToFilter(filters.period);
  if (pf) conditions.push(`${startedCol} >= ${pf}`);
  const where = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';
  return { where, params, startedCol };
}

export function getAgentUsage(
  db: Database.Database,
  filters: AgentUsageFilters = {},
): AgentUsageResult {
  if (!hasAgentUsage(db)) return { ...EMPTY_AGENT_USAGE };
  const { where, params } = waveScope(db, filters);
  // sum() do SQLite retorna NULL quando nenhuma linha tem valor — exatamente a
  // semantica desejada ("sem dado"), por isso NAO ha coalesce aqui.
  const row = db
    .prepare(`
      SELECT
        sum(agent_spawns_total)          as spawnsTotal,
        sum(agent_spawns_with_usage)     as spawnsWithUsage,
        sum(agent_total_tokens)          as totalTokens,
        sum(agent_input_tokens)          as inputTokens,
        sum(agent_output_tokens)         as outputTokens,
        sum(agent_cache_read_tokens)     as cacheReadTokens,
        sum(agent_cache_creation_tokens) as cacheCreationTokens,
        sum(agent_tool_use_count)        as toolUseCount,
        sum(agent_duration_ms)           as durationMs,
        sum(CASE WHEN agent_spawns_total IS NOT NULL THEN 1 ELSE 0 END) as wavesWithUsage,
        count(*)                         as wavesTotal
      FROM waves
      ${where}
    `)
    .get(...params) as AgentUsageResult | undefined;
  return row ?? { ...EMPTY_AGENT_USAGE };
}

// ─────────────────────────────────────────────────────────
// 11.bis otel-usage — consumo REAL da onda (schema v11)
//
// Fonte independente de agentUsage: os contadores OTel do Claude Code sobem
// a cada API request e carregam `query_source`, entao capturam tambem o
// consumo do PROPRIO orquestrador — que o hook de spawn nunca ve, porque o
// spawn do orquestrador envolve a onda e seu tool_result chega depois do
// fechamento. Medido em campo: o subagente e 43-47% do gasto.

export interface OtelUsageResult {
  /** custo total em USD no recorte; null = nao coletado */
  costUsd: number | null;
  /** custo atribuido ao loop principal */
  costMainUsd: number | null;
  /** custo atribuido a subagentes — a fatia que agentUsage nao enxergava */
  costSubagentUsd: number | null;
  totalTokens: number | null;
  subagentTokens: number | null;
  /** ondas com metrica OTel coletada (otel_cost_usd NAO nulo) */
  wavesWithOtel: number | null;
  /** ondas no recorte, coletadas ou nao */
  wavesTotal: number | null;
}

const EMPTY_OTEL_USAGE: OtelUsageResult = {
  costUsd: null,
  costMainUsd: null,
  costSubagentUsd: null,
  totalTokens: null,
  subagentTokens: null,
  wavesWithOtel: null,
  wavesTotal: null,
};

export function getOtelUsage(
  db: Database.Database,
  filters: AgentUsageFilters = {},
): OtelUsageResult {
  // Banco v10 ou anterior: colunas inexistentes. Devolver vazio e mais
  // honesto (e nao quebra) do que consultar e explodir.
  if (!hasOtelUsage(db)) return { ...EMPTY_OTEL_USAGE };
  const { where, params } = waveScope(db, filters);
  // Sem coalesce de proposito: sum() devolve NULL quando nenhuma linha tem
  // valor, que e exatamente "nao coletado" — distinto de "coletado e zero".
  const row = db
    .prepare(`
      SELECT
        sum(otel_cost_usd)            as costUsd,
        sum(otel_cost_main_usd)       as costMainUsd,
        sum(otel_cost_subagent_usd)   as costSubagentUsd,
        sum(otel_total_tokens)        as totalTokens,
        sum(otel_subagent_tokens)     as subagentTokens,
        sum(CASE WHEN otel_cost_usd IS NOT NULL THEN 1 ELSE 0 END) as wavesWithOtel,
        count(*)                      as wavesTotal
      FROM waves
      ${where}
    `)
    .get(...params) as OtelUsageResult | undefined;
  return row ?? { ...EMPTY_OTEL_USAGE };
}

// ─────────────────────────────────────────────────────────
// 12. tokens-over-time — serie diaria de tokens medidos (schema v10)
//     Dias sem NENHUMA onda com dado sao OMITIDOS da serie (nao viram 0):
//     a linha do grafico so existe onde houve medicao.
// ─────────────────────────────────────────────────────────

export interface TokensOverTimeRow {
  day: string;               // 'YYYY-MM-DD'
  totalTokens: number;
  inputTokens: number | null;
  outputTokens: number | null;
  cacheReadTokens: number | null;
  cacheCreationTokens: number | null;
  spawnsTotal: number | null;
  spawnsWithUsage: number | null;
}

export function getTokensOverTime(
  db: Database.Database,
  filters: AgentUsageFilters = {},
): TokensOverTimeRow[] {
  if (!hasAgentUsage(db)) return [];
  const { where, params, startedCol } = waveScope(db, filters);
  const scope = where === ''
    ? 'WHERE agent_total_tokens IS NOT NULL'
    : `${where} AND agent_total_tokens IS NOT NULL`;
  return db
    .prepare(`
      SELECT substr(${startedCol}, 1, 10)   as day,
             sum(agent_total_tokens)        as totalTokens,
             sum(agent_input_tokens)        as inputTokens,
             sum(agent_output_tokens)       as outputTokens,
             sum(agent_cache_read_tokens)   as cacheReadTokens,
             sum(agent_cache_creation_tokens) as cacheCreationTokens,
             sum(agent_spawns_total)        as spawnsTotal,
             sum(agent_spawns_with_usage)   as spawnsWithUsage
      FROM waves
      ${scope}
      GROUP BY day
      HAVING day IS NOT NULL AND day != ''
      ORDER BY day ASC
    `)
    .all(...params) as TokensOverTimeRow[];
}

// ─────────────────────────────────────────────────────────
// 13. tokens-by-wave — ondas mais caras em token medido (schema v10)
// ─────────────────────────────────────────────────────────

export interface TokensByWaveRow {
  project: string;
  feature: string;
  executionId: string;
  wave: string;
  stages: string | null;
  totalTokens: number;
  spawnsTotal: number | null;
  spawnsWithUsage: number | null;
  toolCalls: number | null;
  durationMs: number | null;
}

export function getTokensByWave(
  db: Database.Database,
  filters: AgentUsageFilters = {},
  limit = 20,
): TokensByWaveRow[] {
  if (!hasAgentUsage(db)) return [];
  const { where, params } = waveScope(db, filters);
  const scope = where === ''
    ? 'WHERE agent_total_tokens IS NOT NULL'
    : `${where} AND agent_total_tokens IS NOT NULL`;
  const stagesCol = hasColumn(db, 'waves', 'stages') ? 'stages' : 'NULL as stages';
  const execIdCol = hasColumn(db, 'waves', 'execution_id') ? 'execution_id' : 'NULL';
  return db
    .prepare(`
      SELECT project, feature, ${execIdCol} as executionId, wave, ${stagesCol},
             agent_total_tokens      as totalTokens,
             agent_spawns_total      as spawnsTotal,
             agent_spawns_with_usage as spawnsWithUsage,
             tool_calls              as toolCalls,
             agent_duration_ms       as durationMs
      FROM waves
      ${scope}
      ORDER BY agent_total_tokens DESC
      LIMIT ?
    `)
    .all(...params, limit) as TokensByWaveRow[];
}

export function getRecallConsultations(db: Database.Database): RecallConsultationsResult {
  const descCol = hasColumn(db, 'events', 'description') ? 'description' : 'NULL';
  const rows = db
    .prepare(`
      SELECT ${descCol} as description
      FROM events
      WHERE event_type = 'recall_consulted'
    `)
    .all() as { description: string | null }[];

  const total = rows.length;
  let produtivas = 0;
  for (const r of rows) {
    const m = r.description ? HITS_RE.exec(r.description) : null;
    if (m && Number(m[1]) > 0) produtivas++;
  }
  return { total, produtivas, vazias: total - produtivas };
}
