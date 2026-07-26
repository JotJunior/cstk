/**
 * Rotas GET /features e GET /features/{project}/{feature}.
 * Ref: contracts/api-read.md §Projetos e features; spec.md FR-022
 * Task 4.2.2
 */
import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { openDb } from '../db/open.js';
import { wrap, wrapDegraded } from '../lib/envelope.js';
import { generateETag, etagMatches } from '../lib/etag.js';
import { loadConfig } from '../config.js';
import { getRollupByFeature, listExecutions } from '../db/queries/executions.js';
import { listRetrosByFeature } from '../db/queries/retros.js';
import { mapExecution, normalizeStatus, mapAgentUsageRollup } from '../mappers/index.js';

// Validacao de path params (FR-018 — sem traversal)
const FeatureParamSchema = z.object({
  project: z.string().min(1).max(200).regex(/^[^/\\.<>]+$/, 'invalid project'),
  feature: z.string().min(1).max(200).regex(/^[^/\\.<>]+$/, 'invalid feature'),
});

const FeatureQuerySchema = z.object({
  project: z.string().optional(),
  status: z.enum(['em_andamento', 'aguardando_humano', 'concluida', 'abortada']).optional(),
});

export async function featureRoutes(server: FastifyInstance): Promise<void> {
  const config = loadConfig();

  // GET /features?project=&status= — lista features com rollup
  server.get('/features', async (request, reply) => {
    const qResult = FeatureQuerySchema.safeParse(request.query);
    const { project, status } = qResult.success ? qResult.data : { project: undefined, status: undefined };

    const openResult = openDb(config.dbPath, config.supportedSchemaVersions);
    if (!openResult.ok) {
      return reply.status(200).send(wrapDegraded(openResult.reason, config.dbPath));
    }

    const { db } = openResult;
    try {
      let features = getRollupByFeature(db);

      if (project) {
        features = features.filter(f => f.project === project);
      }
      if (status) {
        // Compara o status NORMALIZADO: assim o filtro por 'concluida' tambem
        // captura linhas cujo valor cru e uma variante conhecida ('concluido').
        features = features.filter(f => normalizeStatus(f.latest_status) === status);
      }

      const data = features.map(r => ({
        project: r.project,
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
        // consumo real de subagentes (schema v10); campos null em base v<10
        agentUsage: mapAgentUsageRollup(r),
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

  // GET /features/:project/:feature — detalhe da feature com execucoes
  server.get('/features/:project/:feature', async (request, reply) => {
    const paramResult = FeatureParamSchema.safeParse(request.params);
    if (!paramResult.success) {
      return reply.status(400).send({
        data: null,
        meta: { degraded: false, reason: null, freshness: { mtime: '', maxIngestedAt: '' }, schemaVersion: '2' },
        error: 'Invalid project or feature name',
      });
    }

    const { project, feature } = paramResult.data;
    const openResult = openDb(config.dbPath, config.supportedSchemaVersions);
    if (!openResult.ok) {
      return reply.status(200).send(wrapDegraded(openResult.reason, config.dbPath));
    }

    const { db } = openResult;
    try {
      const allFeatures = getRollupByFeature(db);
      const featureRollup = allFeatures.find(r => r.project === project && r.feature === feature);

      if (!featureRollup) {
        // Inexistente != degradacao
        return reply.status(200).send(wrap(null, {}, config.dbPath, db));
      }

      // Execucoes da feature
      const allExecs = listExecutions(db);
      const executions = allExecs
        .filter(e => e.project === project && e.feature === feature)
        .map(mapExecution);

      const retros = listRetrosByFeature(db, project, feature);

      const data = {
        project,
        feature,
        retros,
        rollup: {
          totalExecutions: featureRollup.total_executions,
          activeExecutions: featureRollup.active_executions,
          completedExecutions: featureRollup.completed_executions,
          abortedExecutions: featureRollup.aborted_executions,
          totalToolCalls: featureRollup.total_tool_calls,
          totalWallclock: featureRollup.total_wallclock,
          totalDecisions: featureRollup.total_decisions,
          totalWaves: featureRollup.total_waves,
          totalBlocks: featureRollup.total_blocks,
          currentStage: featureRollup.current_stage,
          openAlerts: featureRollup.open_alerts,
          latestStatus: normalizeStatus(featureRollup.latest_status),
          latestExecutionAt: featureRollup.latest_execution_at,
          agentUsage: mapAgentUsageRollup(featureRollup),
        },
        executions,
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
