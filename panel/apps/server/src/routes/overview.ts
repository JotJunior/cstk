/**
 * Rota GET /overview — visao geral com KPIs, alertas, execucoes em andamento.
 * Ref: contracts/api-read.md §Saude e visao geral; spec.md FR-008, FR-022
 * Task 4.1.2
 *
 * Principio III (Honestidade de Metrica):
 * - toolCallsTotal = proxy de custo; NUNCA rotular como "$" ou "tokens" na UI.
 */
import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { openDb } from '../db/open.js';
import { wrap, wrapDegraded } from '../lib/envelope.js';
import { generateETag, etagMatches } from '../lib/etag.js';
import { loadConfig } from '../config.js';
import {
  getOverviewKPIs, getRecentAlerts, getActiveExecutions,
  getModelMix, getRecentActivity, getCostSeries,
} from '../db/queries/overview.js';
import { getRollupByProject, getRollupByFeature } from '../db/queries/executions.js';
import { getAgentUsage, getOtelUsage, getOtelCostOverTime, getTokensOverTime } from '../db/queries/metrics.js';
import { normalizeStatus, mapAgentUsageResult, mapAgentUsageRollup, mapOtelUsageResult } from '../mappers/index.js';

const PeriodSchema = z.enum(['24h', '7d', '30d', 'all']).optional().default('7d');
// FR-022: filtro global de projeto. String vazia/ausente = todos os projetos.
const QuerySchema = z.object({
  period: PeriodSchema,
  project: z.string().trim().min(1).max(200).optional(),
});

type AllExecRow = {
  project: string; feature: string; execution_id: string; status: string | null;
  tool_calls_total: number | null; waves_total: number | null;
  decisions_total: number | null; started_at: string | null; finished_at: string | null;
};

function filterByPeriod(rows: AllExecRow[], period: string): AllExecRow[] {
  if (period === 'all') return rows;
  const ms = period === '24h' ? 86400_000
           : period === '7d'  ? 7 * 86400_000
           : 30 * 86400_000;
  return rows.filter(r => {
    if (!r.started_at) return false;
    return Date.now() - new Date(r.started_at).getTime() <= ms;
  });
}

export async function overviewRoutes(server: FastifyInstance): Promise<void> {
  const config = loadConfig();

  server.get('/overview', async (request, reply) => {
    const qResult = QuerySchema.safeParse(request.query);
    const period = qResult.success ? qResult.data.period : '7d';
    const project = (qResult.success ? qResult.data.project : undefined) ?? null;

    const openResult = openDb(config.dbPath, config.supportedSchemaVersions);
    if (!openResult.ok) {
      return reply.status(200).send(wrapDegraded(openResult.reason, config.dbPath));
    }

    const { db } = openResult;
    try {
      const kpis = getOverviewKPIs(db, project);
      const recentAlerts = getRecentAlerts(db, 10, project);
      const activeExecutions = getActiveExecutions(db, project);
      const projectRollups = getRollupByProject(db, project);
      const featureRollups = getRollupByFeature(db, project);
      const modelMix = getModelMix(db, project);
      const recentActivity = getRecentActivity(db, 8, project);
      const costSeries = getCostSeries(db, 14, project);
      // Consumo REAL de subagentes (schema v10) — medido, nao proxy. Vem com
      // spawnsWithUsage/spawnsTotal para a UI rotular a cobertura da amostra.
      const agentUsage = getAgentUsage(db, project !== null ? { project } : {});
      // Consumo REAL medido pela telemetria OTel (schema v11). Fonte
      // independente de agentUsage: cobre tambem o gasto do proprio
      // orquestrador, que o hook de spawn nunca enxerga.
      const otelUsage = getOtelUsage(db, project !== null ? { project } : {});
      const tokenSeries = getTokensOverTime(db, project !== null ? { project } : {})
        .map(r => r.totalTokens);
      // Serie diaria do custo REAL em USD (schema v11). Dias sem coleta nao
      // entram na serie — o sparkline so desenha onde houve medicao, senao
      // um vale de "0" mentiria sobre um dia que apenas nao foi instrumentado.
      const otelCostSeries = getOtelCostOverTime(db, project !== null ? { project } : {})
        .map(r => r.costUsd);

      // Filtrar por periodo para leaderboard
      const { hasColumn } = await import('../db/columns.js');
      const execIdCol = hasColumn(db, 'executions', 'execution_id') ? 'execution_id' : 'NULL as execution_id';
      const wavesTotalCol = hasColumn(db, 'executions', 'waves_total') ? 'waves_total' : 'NULL as waves_total';
      const decTotalCol = hasColumn(db, 'executions', 'decisions_total') ? 'decisions_total' : 'NULL as decisions_total';
      const startedAtCol = hasColumn(db, 'executions', 'started_at') ? 'started_at' : 'NULL as started_at';
      const finishedAtCol = hasColumn(db, 'executions', 'finished_at') ? 'finished_at' : 'NULL as finished_at';
      const allExecs = db
        .prepare(`
          SELECT project, feature, ${execIdCol}, status, tool_calls_total,
                 ${wavesTotalCol}, ${decTotalCol}, ${startedAtCol}, ${finishedAtCol}
          FROM executions
          WHERE (@project IS NULL OR project = @project)
          ORDER BY tool_calls_total DESC NULLS LAST
        `)
        .all({ project }) as AllExecRow[];

      const filtered = period === 'all' ? allExecs : filterByPeriod(allExecs, period);

      // Funil de etapas
      const stageCol = hasColumn(db, 'executions', 'current_stage') ? 'current_stage' : 'NULL';
      const funnelRows = db
        .prepare(`
          SELECT ${stageCol} as stage, count(*) as count
          FROM executions
          WHERE ${stageCol} IS NOT NULL
            AND (@project IS NULL OR project = @project)
          GROUP BY stage
          ORDER BY count DESC
        `)
        .all({ project }) as { stage: string; count: number }[];

      const data = {
        kpis: {
          totalExecutions: kpis.total_executions,
          activeExecutions: kpis.active_executions,
          completedExecutions: kpis.completed_executions,
          abortedExecutions: kpis.aborted_executions,
          totalWaves: kpis.total_waves,
          totalDecisions: kpis.total_decisions,
          /** proxy de custo — rotular como "proxy: tool calls" na UI */
          toolCallsTotal: kpis.total_tool_calls,
          wallclockTotal: kpis.total_wallclock,
          testsPassed: kpis.tests_passed,
          testsTotal: kpis.tests_total,
          totalProjects: kpis.total_projects,
          totalFeatures: kpis.total_features,
          /** consumo medido dos subagentes (schema v10); campos null quando
           *  a base e v<10 ou nenhuma onda do recorte tem medicao */
          agentUsage: mapAgentUsageResult(agentUsage),
          /** consumo medido pela telemetria OTel (schema v11); campos null
           *  quando a base e v<11 ou nenhuma onda do recorte foi instrumentada */
          otelUsage: mapOtelUsageResult(otelUsage),
        },
        recentAlerts: recentAlerts.map(a => ({
          executionId: a.execution_id,
          type: a.type,
          subtype: a.subtype,
          description: a.description,
          wave: a.wave,
          consumedValue: a.consumed_value,
          thresholdValue: a.threshold_value,
        })),
        inProgress: activeExecutions.map(e => ({
          executionId: e.execution_id,
          project: e.project,
          feature: e.feature,
          status: e.status,
          currentStage: e.current_stage,
          startedAt: e.started_at,
          wavesTotal: e.waves_total,
          toolCallsTotal: e.tool_calls_total,
          wallclockTotalSeconds: e.wallclock_total_seconds,
        })),
        /** mix derivado de decisoes de roteamento logadas (FR-010: nao e o
         *  relatorio canonico; UI rotula como derivado). */
        modelMix: modelMix.map(m => ({ model: m.modelo, n: m.n })),
        recentActivity: recentActivity.map(a => ({
          executionId: a.execution_id,
          project: a.project,
          feature: a.feature,
          wave: a.wave,
          eventType: a.event_type,
          timestamp: a.timestamp,
          description: a.description,
        })),
        costSeries,
        /** serie diaria de tokens medidos; dias sem medicao NAO entram como 0 */
        tokenSeries,
        /** serie diaria do custo REAL em USD (schema v11); dias sem coleta
         *  OTel NAO entram como 0 — array vazio em base v<11 */
        otelCostSeries,
        leaderboard: filtered.slice(0, 10).map(e => ({
          executionId: e.execution_id,
          project: e.project,
          feature: e.feature,
          status: e.status,
          toolCallsTotal: e.tool_calls_total,
          wavesTotal: e.waves_total,
          decisionsTotal: e.decisions_total,
        })),
        funnel: funnelRows,
        projectRollups: projectRollups.map(r => ({
          project: r.project,
          totalExecutions: r.total_executions,
          activeExecutions: r.active_executions,
          completedExecutions: r.completed_executions,
          abortedExecutions: r.aborted_executions,
          totalDecisions: r.total_decisions,
          totalToolCalls: r.total_tool_calls,
          latestExecutionAt: r.latest_execution_at,
          agentUsage: mapAgentUsageRollup(r),
        })),
        featureRollups: featureRollups.slice(0, 20).map(r => ({
          project: r.project,
          feature: r.feature,
          totalExecutions: r.total_executions,
          latestStatus: normalizeStatus(r.latest_status),
          latestExecutionAt: r.latest_execution_at,
        })),
      };

      const envelope = wrap(data, {}, config.dbPath, db);

      const etag = generateETag(envelope.meta.freshness);
      const ifNoneMatch = request.headers['if-none-match'] as string | undefined;
      if (etag && etagMatches(ifNoneMatch, etag)) {
        return reply.status(304).send();
      }
      if (etag) void reply.header('ETag', etag);

      return reply.status(200).send(envelope);
    } finally {
      db.close();
    }
  });
}
