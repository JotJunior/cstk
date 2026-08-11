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
import { hasAgentUsage, hasOtelUsage, hasOtelBreakdown, hasModelUsage, hasLooseUsage, hasPlanUsage } from './waves.js';

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
  // schema v12 — breakdown de tokens por fonte x tipo (by_source do OTel).
  // Responde o que as 5 colunas de v11 nao respondiam: quanto do token foi
  // cache read (barato, contexto relido) e quanto foi input/output novo.
  mainInputTokens: number | null;
  mainOutputTokens: number | null;
  mainCacheReadTokens: number | null;
  mainCacheCreationTokens: number | null;
  subagentInputTokens: number | null;
  subagentOutputTokens: number | null;
  subagentCacheReadTokens: number | null;
  subagentCacheCreationTokens: number | null;
  /**
   * Cobertura do breakdown em DOIS denominadores independentes — o lado main e
   * o lado subagente sao coletados separadamente e divergem na base real
   * (medido em ~/.claude/cstk/knowledge.db v14: 27 ondas com main contra 257
   * com subagente, de 1182). Fundir os dois num numero so apresentaria como
   * medido um lado que nunca foi.
   */
  wavesWithMainBreakdown: number | null;
  wavesWithSubagentBreakdown: number | null;
}

const EMPTY_OTEL_USAGE: OtelUsageResult = {
  costUsd: null,
  costMainUsd: null,
  costSubagentUsd: null,
  totalTokens: null,
  subagentTokens: null,
  wavesWithOtel: null,
  wavesTotal: null,
  mainInputTokens: null,
  mainOutputTokens: null,
  mainCacheReadTokens: null,
  mainCacheCreationTokens: null,
  subagentInputTokens: null,
  subagentOutputTokens: null,
  subagentCacheReadTokens: null,
  subagentCacheCreationTokens: null,
  wavesWithMainBreakdown: null,
  wavesWithSubagentBreakdown: null,
};

export function getOtelUsage(
  db: Database.Database,
  filters: AgentUsageFilters = {},
): OtelUsageResult {
  // Banco v10 ou anterior: colunas inexistentes. Devolver vazio e mais
  // honesto (e nao quebra) do que consultar e explodir.
  if (!hasOtelUsage(db)) return { ...EMPTY_OTEL_USAGE };
  const { where, params } = waveScope(db, filters);
  // Base v11 (custo sim, breakdown por fonte nao): as 8 somas e as 2 coberturas
  // do breakdown viram NULL literal, mantendo a Row com forma unica.
  const breakdownSelect = hasOtelBreakdown(db)
    ? `
        sum(otel_main_input_tokens)             as mainInputTokens,
        sum(otel_main_output_tokens)            as mainOutputTokens,
        sum(otel_main_cache_read_tokens)        as mainCacheReadTokens,
        sum(otel_main_cache_creation_tokens)    as mainCacheCreationTokens,
        sum(otel_subagent_input_tokens)         as subagentInputTokens,
        sum(otel_subagent_output_tokens)        as subagentOutputTokens,
        sum(otel_subagent_cache_read_tokens)    as subagentCacheReadTokens,
        sum(otel_subagent_cache_creation_tokens) as subagentCacheCreationTokens,
        sum(CASE WHEN otel_main_input_tokens IS NOT NULL THEN 1 ELSE 0 END)     as wavesWithMainBreakdown,
        sum(CASE WHEN otel_subagent_input_tokens IS NOT NULL THEN 1 ELSE 0 END) as wavesWithSubagentBreakdown`
    : `
        NULL as mainInputTokens,
        NULL as mainOutputTokens,
        NULL as mainCacheReadTokens,
        NULL as mainCacheCreationTokens,
        NULL as subagentInputTokens,
        NULL as subagentOutputTokens,
        NULL as subagentCacheReadTokens,
        NULL as subagentCacheCreationTokens,
        NULL as wavesWithMainBreakdown,
        NULL as wavesWithSubagentBreakdown`;
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
        count(*)                      as wavesTotal,${breakdownSelect}
      FROM waves
      ${where}
    `)
    .get(...params) as OtelUsageResult | undefined;
  return row ?? { ...EMPTY_OTEL_USAGE };
}

/**
 * Serie diaria do custo REAL (USD) medido por OTel — schema v11.
 *
 * Dias sem NENHUMA onda coletada sao OMITIDOS (nao viram 0), mesma politica de
 * `getTokensOverTime`: a linha so existe onde houve medicao. E o unico numero
 * do painel em USD, e ele nao e derivado aqui — vem calculado pelo Claude Code.
 */
export interface OtelCostOverTimeRow {
  day: string;               // 'YYYY-MM-DD'
  costUsd: number;
  costMainUsd: number | null;
  costSubagentUsd: number | null;
  wavesWithOtel: number | null;
}

export function getOtelCostOverTime(
  db: Database.Database,
  filters: AgentUsageFilters = {},
): OtelCostOverTimeRow[] {
  if (!hasOtelUsage(db)) return [];
  const { where, params, startedCol } = waveScope(db, filters);
  const scope = where === ''
    ? 'WHERE otel_cost_usd IS NOT NULL'
    : `${where} AND otel_cost_usd IS NOT NULL`;
  return db
    .prepare(`
      SELECT substr(${startedCol}, 1, 10) as day,
             sum(otel_cost_usd)           as costUsd,
             sum(otel_cost_main_usd)      as costMainUsd,
             sum(otel_cost_subagent_usd)  as costSubagentUsd,
             count(*)                     as wavesWithOtel
      FROM waves
      ${scope}
      GROUP BY day
      HAVING day IS NOT NULL AND day != ''
      ORDER BY day ASC
    `)
    .all(...params) as OtelCostOverTimeRow[];
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

// ─────────────────────────────────────────────────────────
// 14. model-usage — custo/tokens REAIS por modelo (schema v12,
//     `wave_model_usage`, cstk 5.33.0). Grao onda x modelo — distinto de
//     otel-usage (grao onda) e de model-mix (DERIVADO de decisions.choice,
//     sem custo/tokens). Ref: contracts/model-usage-endpoint.md; data-model.md
//     Parte B; research.md Decisions 1-4.
// ─────────────────────────────────────────────────────────

/** Cardinalidade maxima de `byModel` antes do bucket agregado (FR-003(c), dec-037). */
export const MODEL_USAGE_LIMIT = 10;
/** Rotulo do bucket agregado alem do limite de cardinalidade. */
export const MODEL_USAGE_OTHERS_LABEL = '(outros)';
/** Rotulo de linhas com `model IS NULL` na origem — nunca descartadas. */
export const MODEL_USAGE_UNKNOWN_LABEL = '(desconhecido)';

export interface ModelUsageEntry {
  model: string;
  costUsd: number | null;
  totalTokens: number | null;
  waves: number;
}

export interface ModelUsageByStage {
  stage: string;
  model: string;
  costUsd: number | null;
  totalTokens: number | null;
}

export interface ModelUsageCoverage {
  wavesTotal: number | null;
  wavesWithModelUsage: number | null;
  wavesWithOtelCost: number | null;
}

export interface ModelUsageResult {
  byModel: ModelUsageEntry[];
  byStage: ModelUsageByStage[];
  coverage: ModelUsageCoverage;
}

const EMPTY_MODEL_USAGE_COVERAGE: ModelUsageCoverage = {
  wavesTotal: null,
  wavesWithModelUsage: null,
  wavesWithOtelCost: null,
};

/**
 * Monta WHERE + params para consultas diretas sobre `wave_model_usage`.
 * A tabela carrega seu proprio `project`/`feature`/`source_ts` (DDL, research.md
 * S2) — o recorte por periodo NAO precisa de JOIN com `waves`.
 */
function modelUsageScope(
  filters: AgentUsageFilters,
): { where: string; params: unknown[] } {
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
  if (pf) conditions.push(`source_ts >= ${pf}`);
  const where = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';
  return { where, params };
}

/** Soma tolerante a NULL: se todos os valores forem null, o total e null (nunca 0 fabricado). */
function sumNullable(vals: (number | null)[]): number | null {
  const present = vals.filter((v): v is number => v !== null);
  if (present.length === 0) return null;
  return present.reduce((a, b) => a + b, 0);
}

/**
 * byModel — custo/tokens agregados por modelo, ordenado por `costUsd` desc
 * com `null` por ultimo (SC-001). Acima de `MODEL_USAGE_LIMIT` modelos
 * distintos, os excedentes viram uma linha `'(outros)'` (FR-003(c), dec-037).
 *
 * Invariante 1 do contrato: `sum()` sem `coalesce` — NULL do SQLite quando
 * nenhuma linha tem valor permanece NULL (nao vira 0).
 */
export function getModelUsageByModel(
  db: Database.Database,
  filters: AgentUsageFilters = {},
): ModelUsageEntry[] {
  if (!hasModelUsage(db)) return [];
  const { where, params } = modelUsageScope(filters);
  const rows = db
    .prepare(`
      SELECT
        model,
        sum(cost_usd)                              as costUsd,
        sum(total_tokens)                           as totalTokens,
        count(DISTINCT project || feature || wave)  as waves
      FROM wave_model_usage
      ${where}
      GROUP BY model
    `)
    .all(...params) as { model: string | null; costUsd: number | null; totalTokens: number | null; waves: number }[];

  // NULL de costUsd por ultimo (SC-001); nao-nulo ordenado desc.
  rows.sort((a, b) => {
    if (a.costUsd === null && b.costUsd === null) return 0;
    if (a.costUsd === null) return 1;
    if (b.costUsd === null) return -1;
    return b.costUsd - a.costUsd;
  });

  // model IS NULL -> rotulo literal '(desconhecido)', nunca descartado (2.1.6).
  const labeled: ModelUsageEntry[] = rows.map(r => ({
    model: r.model === null ? MODEL_USAGE_UNKNOWN_LABEL : r.model,
    costUsd: r.costUsd,
    totalTokens: r.totalTokens,
    waves: r.waves,
  }));

  if (labeled.length <= MODEL_USAGE_LIMIT) return labeled;

  const top = labeled.slice(0, MODEL_USAGE_LIMIT);
  const rest = labeled.slice(MODEL_USAGE_LIMIT);
  const outros: ModelUsageEntry = {
    model: MODEL_USAGE_OTHERS_LABEL,
    costUsd: sumNullable(rest.map(r => r.costUsd)),
    totalTokens: sumNullable(rest.map(r => r.totalTokens)),
    waves: rest.reduce((acc, r) => acc + r.waves, 0),
  };
  return [...top, outros];
}

/**
 * byStage — correlaciona `wave_model_usage` com `waves` por
 * `(project, feature, wave, execution_id)` para recuperar a etapa da onda.
 *
 * Viabilidade CONFIRMADA empiricamente (nao suposta): sondagem direta sobre
 * `~/.claude/cstk/knowledge.db` (v12, 48 linhas em `wave_model_usage`) mostra
 * 48/48 linhas casando com `waves` pela chave composta — join 100% confiavel
 * no banco real. 6 dessas 48 tem `stages` vazio/NULL na origem (ondas sem
 * etapa registrada) e sao excluidas do agrupamento (regra dura do contrato:
 * nunca inventar etapa para uma onda que nao a registrou).
 */
export function getModelUsageByStage(
  db: Database.Database,
  filters: AgentUsageFilters = {},
): ModelUsageByStage[] {
  if (!hasModelUsage(db)) return [];
  const stagesCol = hasColumn(db, 'waves', 'stages') ? 'w.stages' : 'NULL';
  if (stagesCol === 'NULL') return [];

  const conditions: string[] = ["w.stages IS NOT NULL", "w.stages != ''"];
  const params: unknown[] = [];
  if (filters.project !== undefined) {
    conditions.push('wmu.project = ?');
    params.push(filters.project);
  }
  if (filters.feature !== undefined) {
    conditions.push('wmu.feature = ?');
    params.push(filters.feature);
  }
  const pf = periodToFilter(filters.period);
  if (pf) conditions.push(`wmu.source_ts >= ${pf}`);
  const where = `WHERE ${conditions.join(' AND ')}`;

  const rows = db
    .prepare(`
      SELECT ${stagesCol}       as stage,
             wmu.model           as model,
             sum(wmu.cost_usd)   as costUsd,
             sum(wmu.total_tokens) as totalTokens
      FROM wave_model_usage wmu
      JOIN waves w
        ON w.project = wmu.project AND w.feature = wmu.feature
       AND w.wave = wmu.wave AND w.execution_id = wmu.execution_id
      ${where}
      GROUP BY stage, wmu.model
      ORDER BY costUsd IS NULL, costUsd DESC
    `)
    .all(...params) as { stage: string; model: string | null; costUsd: number | null; totalTokens: number | null }[];

  return rows.map(r => ({
    stage: r.stage,
    model: r.model === null ? MODEL_USAGE_UNKNOWN_LABEL : r.model,
    costUsd: r.costUsd,
    totalTokens: r.totalTokens,
  }));
}

/**
 * coverage — 3 denominadores independentes (Decision 3 do research.md):
 * `wavesTotal` (ondas do recorte), `wavesWithModelUsage` (breakdown por
 * modelo) e `wavesWithOtelCost` (custo agregado por onda). Os 3 divergem no
 * banco real (920/36/46) — nunca fundidos num unico numero.
 */
export function getModelUsageCoverage(
  db: Database.Database,
  filters: AgentUsageFilters = {},
): ModelUsageCoverage {
  if (!hasModelUsage(db)) return { ...EMPTY_MODEL_USAGE_COVERAGE };
  const { where, params } = waveScope(db, filters);
  const otelCostCol = hasOtelUsage(db) ? 'otel_cost_usd' : null;
  const otelSelect = otelCostCol
    ? `sum(CASE WHEN ${otelCostCol} IS NOT NULL THEN 1 ELSE 0 END)`
    : 'NULL';
  const row = db
    .prepare(`
      SELECT
        count(*) as wavesTotal,
        sum(CASE WHEN EXISTS (
          SELECT 1 FROM wave_model_usage wmu
          WHERE wmu.project = waves.project AND wmu.feature = waves.feature
            AND wmu.wave = waves.wave AND wmu.execution_id = waves.execution_id
        ) THEN 1 ELSE 0 END) as wavesWithModelUsage,
        ${otelSelect} as wavesWithOtelCost
      FROM waves
      ${where}
    `)
    .get(...params) as ModelUsageCoverage | undefined;
  return row ?? { ...EMPTY_MODEL_USAGE_COVERAGE };
}

/** Agrega os 3 recortes num unico `ModelUsageResult` (corpo de `data` do endpoint). */
export function getModelUsage(
  db: Database.Database,
  filters: AgentUsageFilters = {},
): ModelUsageResult {
  return {
    byModel: getModelUsageByModel(db, filters),
    byStage: getModelUsageByStage(db, filters),
    coverage: getModelUsageCoverage(db, filters),
  };
}

// ─────────────────────────────────────────────────────────
// 15. loose-usage — consumo AVULSO de sessoes interativas (schema v13,
//     `loose_usage`, cstk 6.6.0). Grao processo x segmento x modelo — fora de
//     qualquer execucao 00c, SEM feature/wave/execution_id por construcao
//     (dec-005: preencher com sentinela seria fabricar dado). Captura e
//     OPT-IN (hook posttooluse-loose-usage): tabela presente e vazia NAO
//     significa ausencia de consumo, so ausencia de medicao.
//     Ref: ../cstk/docs/specs/loose-usage-capture/data-model.md;
//     ../cstk/docs/cstk-usage.md.
// ─────────────────────────────────────────────────────────

/** Filtros do recorte avulso — sem `feature` (a origem nao tem a dimensao). */
export interface LooseUsageFilters {
  project?: string;
  period?: MetricPeriod;
}

export interface LooseUsageProjectEntry {
  project: string;
  projectPath: string | null;
  costUsd: number | null;
  totalTokens: number | null;
  processes: number;
  segments: number;
  openSegments: number;
  lastCapturedAt: string | null;
}

export interface LooseUsageModelEntry {
  model: string;
  costUsd: number | null;
  totalTokens: number | null;
  segments: number;
}

export interface LooseUsageComparisonSide {
  costUsd: number | null;
  totalTokens: number | null;
  blendedCostPerMtok: number | null;
}

export interface LooseUsageComparison {
  loose: LooseUsageComparisonSide;
  pipeline: LooseUsageComparisonSide;
}

export interface LooseUsageCoverage {
  rowsTotal: number | null;
  segmentsTotal: number | null;
  segmentsOpen: number | null;
  processes: number | null;
  projects: number | null;
  lastCapturedAt: string | null;
}

export interface LooseUsageResult {
  byProject: LooseUsageProjectEntry[];
  byModel: LooseUsageModelEntry[];
  comparison: LooseUsageComparison;
  coverage: LooseUsageCoverage;
}

const EMPTY_LOOSE_USAGE_COVERAGE: LooseUsageCoverage = {
  rowsTotal: null,
  segmentsTotal: null,
  segmentsOpen: null,
  processes: null,
  projects: null,
  lastCapturedAt: null,
};

const EMPTY_COMPARISON_SIDE: LooseUsageComparisonSide = {
  costUsd: null,
  totalTokens: null,
  blendedCostPerMtok: null,
};

/**
 * WHERE + params sobre `loose_usage`. O recorte temporal usa `captured_at`
 * (ultima captura do segmento) — a tabela nao tem `source_ts`.
 */
function looseUsageScope(
  filters: LooseUsageFilters,
): { where: string; params: unknown[] } {
  const conditions: string[] = [];
  const params: unknown[] = [];
  if (filters.project !== undefined) {
    conditions.push('project = ?');
    params.push(filters.project);
  }
  const pf = periodToFilter(filters.period);
  if (pf) conditions.push(`captured_at >= ${pf}`);
  const where = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';
  return { where, params };
}

/**
 * byProject — rollup do consumo avulso por projeto, ordenado por `costUsd`
 * desc com `null` por ultimo. `sum()` sem coalesce (NULL permanece NULL).
 * `segment_open` conta segmentos DISTINTOS ainda abertos — o consumidor deve
 * sinalizar parcialidade (valor ainda em captura), nunca apresentar como
 * final (SC-004 do cstk).
 */
export function getLooseUsageByProject(
  db: Database.Database,
  filters: LooseUsageFilters = {},
): LooseUsageProjectEntry[] {
  if (!hasLooseUsage(db)) return [];
  const { where, params } = looseUsageScope(filters);
  const rows = db
    .prepare(`
      SELECT
        project,
        max(project_path)                     as projectPath,
        sum(cost_usd)                         as costUsd,
        sum(total_tokens)                     as totalTokens,
        count(DISTINCT process_key)           as processes,
        count(DISTINCT process_key || '/' || segment_id) as segments,
        count(DISTINCT CASE WHEN segment_open = 1
              THEN process_key || '/' || segment_id END) as openSegments,
        max(captured_at)                      as lastCapturedAt
      FROM loose_usage
      ${where}
      GROUP BY project
    `)
    .all(...params) as LooseUsageProjectEntry[];
  rows.sort((a, b) => {
    if (a.costUsd === null && b.costUsd === null) return 0;
    if (a.costUsd === null) return 1;
    if (b.costUsd === null) return -1;
    return b.costUsd - a.costUsd;
  });
  return rows;
}

/**
 * byModel — rollup por rotulo BRUTO de modelo (mesma regra do model-usage:
 * NULL vira `'(desconhecido)'`, nunca descartado; acima de
 * `MODEL_USAGE_LIMIT` modelos, excedentes viram `'(outros)'`).
 */
export function getLooseUsageByModel(
  db: Database.Database,
  filters: LooseUsageFilters = {},
): LooseUsageModelEntry[] {
  if (!hasLooseUsage(db)) return [];
  const { where, params } = looseUsageScope(filters);
  const rows = db
    .prepare(`
      SELECT
        model,
        sum(cost_usd)                                    as costUsd,
        sum(total_tokens)                                as totalTokens,
        count(DISTINCT process_key || '/' || segment_id) as segments
      FROM loose_usage
      ${where}
      GROUP BY model
    `)
    .all(...params) as { model: string | null; costUsd: number | null; totalTokens: number | null; segments: number }[];

  rows.sort((a, b) => {
    if (a.costUsd === null && b.costUsd === null) return 0;
    if (a.costUsd === null) return 1;
    if (b.costUsd === null) return -1;
    return b.costUsd - a.costUsd;
  });

  const labeled: LooseUsageModelEntry[] = rows.map(r => ({
    model: r.model === null ? MODEL_USAGE_UNKNOWN_LABEL : r.model,
    costUsd: r.costUsd,
    totalTokens: r.totalTokens,
    segments: r.segments,
  }));

  if (labeled.length <= MODEL_USAGE_LIMIT) return labeled;

  const top = labeled.slice(0, MODEL_USAGE_LIMIT);
  const rest = labeled.slice(MODEL_USAGE_LIMIT);
  const outros: LooseUsageModelEntry = {
    model: MODEL_USAGE_OTHERS_LABEL,
    costUsd: sumNullable(rest.map(r => r.costUsd)),
    totalTokens: sumNullable(rest.map(r => r.totalTokens)),
    segments: rest.reduce((acc, r) => acc + r.segments, 0),
  };
  return [...top, outros];
}

/**
 * Custo blended por Mtok — `SUM(cost_usd)/SUM(total_tokens)*1e6`. `null`
 * quando tokens e 0/NULL (divisao indefinida nunca vira 0) — formula do
 * data-model.md §ProjectUsageComparison do cstk.
 */
function blendedCostPerMtok(costUsd: number | null, totalTokens: number | null): number | null {
  if (costUsd === null || totalTokens === null || totalTokens === 0) return null;
  return (costUsd / totalTokens) * 1e6;
}

/**
 * comparison — avulso (`loose_usage`) vs pipeline (`wave_model_usage`, v12)
 * lado a lado, agregado por categoria — NUNCA join linha a linha
 * (granularidades diferentes por construcao; FR-009 do cstk). O recorte
 * temporal de cada lado usa a coluna da propria origem (`captured_at` vs
 * `source_ts`). Base sem `wave_model_usage`: lado pipeline 3x null.
 */
export function getLooseUsageComparison(
  db: Database.Database,
  filters: LooseUsageFilters = {},
): LooseUsageComparison {
  if (!hasLooseUsage(db)) {
    return { loose: { ...EMPTY_COMPARISON_SIDE }, pipeline: { ...EMPTY_COMPARISON_SIDE } };
  }
  const { where, params } = looseUsageScope(filters);
  const looseRow = db
    .prepare(`SELECT sum(cost_usd) as costUsd, sum(total_tokens) as totalTokens FROM loose_usage ${where}`)
    .get(...params) as { costUsd: number | null; totalTokens: number | null };
  const loose: LooseUsageComparisonSide = {
    costUsd: looseRow.costUsd,
    totalTokens: looseRow.totalTokens,
    blendedCostPerMtok: blendedCostPerMtok(looseRow.costUsd, looseRow.totalTokens),
  };

  if (!hasModelUsage(db)) {
    return { loose, pipeline: { ...EMPTY_COMPARISON_SIDE } };
  }
  const pipelineScope = modelUsageScope(filters);
  const pipelineRow = db
    .prepare(`SELECT sum(cost_usd) as costUsd, sum(total_tokens) as totalTokens FROM wave_model_usage ${pipelineScope.where}`)
    .get(...pipelineScope.params) as { costUsd: number | null; totalTokens: number | null };
  const pipeline: LooseUsageComparisonSide = {
    costUsd: pipelineRow.costUsd,
    totalTokens: pipelineRow.totalTokens,
    blendedCostPerMtok: blendedCostPerMtok(pipelineRow.costUsd, pipelineRow.totalTokens),
  };
  return { loose, pipeline };
}

/**
 * coverage — contadores da amostra avulsa. Tabela ausente (base v2-v12):
 * todos null, nunca 0. Tabela presente e vazia: contagens 0 legitimas
 * (captura opt-in desligada ou sem sessao avulsa no recorte).
 */
export function getLooseUsageCoverage(
  db: Database.Database,
  filters: LooseUsageFilters = {},
): LooseUsageCoverage {
  if (!hasLooseUsage(db)) return { ...EMPTY_LOOSE_USAGE_COVERAGE };
  const { where, params } = looseUsageScope(filters);
  const row = db
    .prepare(`
      SELECT
        count(*)                                         as rowsTotal,
        count(DISTINCT process_key || '/' || segment_id) as segmentsTotal,
        count(DISTINCT CASE WHEN segment_open = 1
              THEN process_key || '/' || segment_id END) as segmentsOpen,
        count(DISTINCT process_key)                      as processes,
        count(DISTINCT project)                          as projects,
        max(captured_at)                                 as lastCapturedAt
      FROM loose_usage
      ${where}
    `)
    .get(...params) as LooseUsageCoverage | undefined;
  return row ?? { ...EMPTY_LOOSE_USAGE_COVERAGE };
}

/** Agrega os 4 recortes num unico `LooseUsageResult` (corpo de `data` do endpoint). */
export function getLooseUsage(
  db: Database.Database,
  filters: LooseUsageFilters = {},
): LooseUsageResult {
  return {
    byProject: getLooseUsageByProject(db, filters),
    byModel: getLooseUsageByModel(db, filters),
    comparison: getLooseUsageComparison(db, filters),
    coverage: getLooseUsageCoverage(db, filters),
  };
}

// ─────────────────────────────────────────────────────────
// 16. plan-usage — gauge `rate_limits` da CONTA (schema v14, `plan_usage`,
//     cstk 7.2.0). Grao escopo x momento de captura, append-only, alimentado
//     pelo hook `statusLine.command` a cada render de statusline.
//
//     NAO e custo nem token: e o PERCENTUAL do plano consumido em duas janelas
//     independentes (`five_hour`, `seven_day`) mais o epoch de reset de cada
//     uma. Nunca somar/mesclar os dois escopos — sao series distintas (FR-005
//     do cstk). Captura opt-in (`cstk statusline install`): tabela presente e
//     vazia = sem medicao, jamais "plano em 0%".
//     Ref: ../cstk/docs/specs/plan-usage-capture/data-model.md.
// ─────────────────────────────────────────────────────────

/** Os dois escopos de janela do gauge — CHECK constraint da tabela de origem. */
export const PLAN_USAGE_SCOPES = ['five_hour', 'seven_day'] as const;
export type PlanUsageScope = (typeof PLAN_USAGE_SCOPES)[number];

/** Teto de pontos por escopo devolvidos na serie (os mais RECENTES). */
export const PLAN_USAGE_SERIES_LIMIT = 240;

/**
 * Filtros do gauge de plano — apenas `period`.
 *
 * SEM filtro `project`: o gauge mede a CONTA, nao o projeto. A tabela guarda
 * `project`/`project_path` (de qual sessao partiu a captura), mas recortar por
 * ele sugeriria "consumo do plano por projeto" — numero que a fonte nao
 * produz. Mesma regra que faz `loose-usage` recusar `feature`.
 */
export interface PlanUsageFilters {
  period?: MetricPeriod;
}

/** Estado corrente de UM escopo + extremos da janela consultada. */
export interface PlanUsageScopeState {
  scope: string;
  /** percentual consumido na captura mais recente; null = capturado sem valor */
  usedPercentage: number | null;
  /** epoch em SEGUNDOS do reset da janela; null = ausente na origem */
  resetsAt: number | null;
  /** ISO 8601 da captura mais recente do escopo */
  capturedAt: string | null;
  /** maior percentual observado no recorte; null quando nenhuma captura tem valor */
  peakUsedPercentage: number | null;
  /** numero de capturas do escopo no recorte (pos-throttle: so mudancas) */
  captures: number;
}

/** Um ponto da serie temporal de um escopo. */
export interface PlanUsagePoint {
  scope: string;
  capturedAt: string;
  usedPercentage: number | null;
}

export interface PlanUsageCoverage {
  rowsTotal: number | null;
  scopes: number | null;
  sessions: number | null;
  projects: number | null;
  firstCapturedAt: string | null;
  lastCapturedAt: string | null;
}

export interface PlanUsageResult {
  byScope: PlanUsageScopeState[];
  series: PlanUsagePoint[];
  coverage: PlanUsageCoverage;
  /** true quando a serie foi cortada em PLAN_USAGE_SERIES_LIMIT por escopo */
  seriesTruncated: boolean;
}

const EMPTY_PLAN_USAGE_COVERAGE: PlanUsageCoverage = {
  rowsTotal: null,
  scopes: null,
  sessions: null,
  projects: null,
  firstCapturedAt: null,
  lastCapturedAt: null,
};

/** WHERE + params sobre `plan_usage`. Recorte temporal por `captured_at`. */
function planUsageScope(
  filters: PlanUsageFilters,
): { where: string; params: unknown[] } {
  const conditions: string[] = [];
  const params: unknown[] = [];
  const pf = periodToFilter(filters.period);
  if (pf) conditions.push(`captured_at >= ${pf}`);
  const where = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';
  return { where, params };
}

/**
 * Estado corrente por escopo. "Corrente" = maior `id` do escopo no recorte —
 * a tabela e append-only com AUTOINCREMENT, e e por `id DESC` que o proprio
 * throttle do cstk le o registro anterior. Ordenar por `captured_at` seria
 * fragil: duas capturas podem cair no mesmo segundo ISO.
 */
export function getPlanUsageByScope(
  db: Database.Database,
  filters: PlanUsageFilters = {},
): PlanUsageScopeState[] {
  if (!hasPlanUsage(db)) return [];
  const { where, params } = planUsageScope(filters);
  const rows = db
    .prepare(`
      SELECT
        p.scope                                    as scope,
        p.used_percentage                          as usedPercentage,
        p.resets_at                                as resetsAt,
        p.captured_at                              as capturedAt,
        agg.peakUsedPercentage                     as peakUsedPercentage,
        agg.captures                               as captures
      FROM plan_usage p
      JOIN (
        SELECT scope,
               max(id)              as lastId,
               max(used_percentage) as peakUsedPercentage,
               count(*)             as captures
        FROM plan_usage
        ${where}
        GROUP BY scope
      ) agg ON agg.lastId = p.id
      ORDER BY p.scope ASC
    `)
    .all(...params) as PlanUsageScopeState[];
  return rows;
}

/**
 * Serie temporal por escopo, do mais ANTIGO ao mais recente (ordem de plotagem).
 *
 * O corte de `PLAN_USAGE_SERIES_LIMIT` guarda os pontos mais RECENTES de cada
 * escopo — a janela que interessa e a atual, nao o inicio do historico. Um
 * escopo truncado nunca vira "sem dado": o corte e sinalizado em
 * `seriesTruncated` para a UI dizer que a serie esta parcial.
 */
export function getPlanUsageSeries(
  db: Database.Database,
  filters: PlanUsageFilters = {},
  limitPerScope = PLAN_USAGE_SERIES_LIMIT,
): { points: PlanUsagePoint[]; truncated: boolean } {
  if (!hasPlanUsage(db)) return { points: [], truncated: false };
  const { where, params } = planUsageScope(filters);
  // row_number() por escopo: SQLite >= 3.25 (better-sqlite3 embarca 3.4x).
  const rows = db
    .prepare(`
      SELECT scope, capturedAt, usedPercentage, rn
      FROM (
        SELECT scope                as scope,
               captured_at          as capturedAt,
               used_percentage      as usedPercentage,
               row_number() OVER (PARTITION BY scope ORDER BY id DESC) as rn
        FROM plan_usage
        ${where}
      )
      WHERE rn <= ?
      ORDER BY scope ASC, capturedAt ASC
    `)
    .all(...params, limitPerScope) as Array<PlanUsagePoint & { rn: number }>;
  const truncated = rows.some(r => r.rn === limitPerScope);
  return {
    points: rows.map(({ scope, capturedAt, usedPercentage }) => ({ scope, capturedAt, usedPercentage })),
    truncated,
  };
}

/**
 * Cobertura da amostra. Tabela ausente (base v2-v13): tudo null, nunca 0.
 * Tabela presente e vazia: contagens 0 legitimas — a captura e opt-in
 * (`cstk statusline install`) e pode simplesmente nao estar ligada.
 */
export function getPlanUsageCoverage(
  db: Database.Database,
  filters: PlanUsageFilters = {},
): PlanUsageCoverage {
  if (!hasPlanUsage(db)) return { ...EMPTY_PLAN_USAGE_COVERAGE };
  const { where, params } = planUsageScope(filters);
  const row = db
    .prepare(`
      SELECT
        count(*)                    as rowsTotal,
        count(DISTINCT scope)       as scopes,
        count(DISTINCT session_id)  as sessions,
        count(DISTINCT project)     as projects,
        min(captured_at)            as firstCapturedAt,
        max(captured_at)            as lastCapturedAt
      FROM plan_usage
      ${where}
    `)
    .get(...params) as PlanUsageCoverage | undefined;
  return row ?? { ...EMPTY_PLAN_USAGE_COVERAGE };
}

/** Agrega os recortes num unico `PlanUsageResult` (corpo de `data` do endpoint). */
export function getPlanUsage(
  db: Database.Database,
  filters: PlanUsageFilters = {},
): PlanUsageResult {
  const series = getPlanUsageSeries(db, filters);
  return {
    byScope: getPlanUsageByScope(db, filters),
    series: series.points,
    coverage: getPlanUsageCoverage(db, filters),
    seriesTruncated: series.truncated,
  };
}
