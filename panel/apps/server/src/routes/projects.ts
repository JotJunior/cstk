/**
 * Rotas GET /projects e GET /projects/{project}.
 * Ref: contracts/api-read.md §Projetos e features; spec.md FR-022 (drill-down)
 * Task 4.2.1
 *
 * Validacao de path params com Zod (string nao-vazia, sem traversal — FR-018).
 */
import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { openDb } from '../db/open.js';
import { wrap, wrapDegraded } from '../lib/envelope.js';
import { generateETag, etagMatches } from '../lib/etag.js';
import { loadConfig } from '../config.js';
import { getRollupByProject, getRollupByFeature, listExecutionsByProject } from '../db/queries/executions.js';
import { mapExecution, normalizeStatus, mapAgentUsageRollup, mapOtelUsageRollup } from '../mappers/index.js';

// Validacao de path param: string nao-vazia, sem traversal (FR-018)
const ProjectParamSchema = z.object({
  project: z.string().min(1).max(200).regex(/^[^/\\.<>]+$/, 'invalid project name'),
});

export async function projectRoutes(server: FastifyInstance): Promise<void> {
  const config = loadConfig();

  // GET /projects — lista todos os projetos com rollup
  server.get('/projects', async (request, reply) => {
    const openResult = openDb(config.dbPath, config.supportedSchemaVersions);
    if (!openResult.ok) {
      return reply.status(200).send(wrapDegraded(openResult.reason, config.dbPath));
    }

    const { db } = openResult;
    try {
      const rollups = getRollupByProject(db);
      const data = rollups.map(r => ({
        project: r.project,
        totalExecutions: r.total_executions,
        activeExecutions: r.active_executions,
        completedExecutions: r.completed_executions,
        abortedExecutions: r.aborted_executions,
        totalDecisions: r.total_decisions,
        totalToolCalls: r.total_tool_calls,
        totalWallclock: r.total_wallclock,
        openAlerts: r.open_alerts,
        latestExecutionAt: r.latest_execution_at,
        // consumo real de subagentes (schema v10); campos null em base v<10
        agentUsage: mapAgentUsageRollup(r),
        // consumo medido por telemetria OTel (schema v11); null em base v<11
        otelUsage: mapOtelUsageRollup(r),
      }));

      const envelope = wrap(data, {}, config.dbPath, db);
      const etag = generateETag(envelope.meta.freshness);
      const ifNoneMatch = request.headers['if-none-match'] as string | undefined;
      if (etag && etagMatches(ifNoneMatch, etag)) return reply.status(304).send();
      if (etag) void reply.header('ETag', etag);

      return reply.status(200).send(envelope);
    } finally {
      db.close();
    }
  });

  // GET /projects/:project — detalhe de um projeto com features aninhadas
  server.get('/projects/:project', async (request, reply) => {
    const paramResult = ProjectParamSchema.safeParse(request.params);
    if (!paramResult.success) {
      return reply.status(400).send({
        data: null,
        meta: { degraded: false, reason: null, freshness: { mtime: '', maxIngestedAt: '' }, schemaVersion: '2' },
        error: 'Invalid project name',
      });
    }

    const { project } = paramResult.data;
    const openResult = openDb(config.dbPath, config.supportedSchemaVersions);
    if (!openResult.ok) {
      return reply.status(200).send(wrapDegraded(openResult.reason, config.dbPath));
    }

    const { db } = openResult;
    try {
      // Verificar se projeto existe
      const rollups = getRollupByProject(db);
      const projectRollup = rollups.find(r => r.project === project);

      if (!projectRollup) {
        // Projeto inexistente != degradacao (spec: data:null, degraded:false)
        const envelope = wrap(null, {}, config.dbPath, db);
        return reply.status(200).send(envelope);
      }

      // Features do projeto
      const allFeatureRollups = getRollupByFeature(db);
      const features = allFeatureRollups.filter(r => r.project === project).map(r => ({
        feature: r.feature,
        totalExecutions: r.total_executions,
        activeExecutions: r.active_executions,
        completedExecutions: r.completed_executions,
        abortedExecutions: r.aborted_executions,
        totalToolCalls: r.total_tool_calls,
        totalWallclock: r.total_wallclock,
        totalDecisions: r.total_decisions,
        totalWaves: r.total_waves,
        totalBlocks: r.total_blocks,
        currentStage: r.current_stage,
        openAlerts: r.open_alerts,
        latestStatus: normalizeStatus(r.latest_status),
        latestExecutionAt: r.latest_execution_at,
        agentUsage: mapAgentUsageRollup(r),
        otelUsage: mapOtelUsageRollup(r),
      }));

      // Execucoes recentes do projeto
      const execRows = listExecutionsByProject(db, project);
      const executions = execRows.slice(0, 20).map(mapExecution);

      const data = {
        project,
        rollup: {
          totalExecutions: projectRollup.total_executions,
          activeExecutions: projectRollup.active_executions,
          completedExecutions: projectRollup.completed_executions,
          abortedExecutions: projectRollup.aborted_executions,
          totalDecisions: projectRollup.total_decisions,
          totalToolCalls: projectRollup.total_tool_calls,
          totalWallclock: projectRollup.total_wallclock,
          openAlerts: projectRollup.open_alerts,
          latestExecutionAt: projectRollup.latest_execution_at,
          agentUsage: mapAgentUsageRollup(projectRollup),
          otelUsage: mapOtelUsageRollup(projectRollup),
        },
        features,
        recentExecutions: executions,
      };

      const envelope = wrap(data, {}, config.dbPath, db);
      const etag = generateETag(envelope.meta.freshness);
      const ifNoneMatch = request.headers['if-none-match'] as string | undefined;
      if (etag && etagMatches(ifNoneMatch, etag)) return reply.status(304).send();
      if (etag) void reply.header('ETag', etag);

      return reply.status(200).send(envelope);
    } finally {
      db.close();
    }
  });
}
