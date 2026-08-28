/**
 * Rota GET /events — eventos cross-execucao.
 * Ref: contracts/api-read.md §Cross-execucao; task 4.4.3
 */
import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { openDb } from '../db/open.js';
import { wrap, wrapDegraded } from '../lib/envelope.js';
import { loadConfig } from '../config.js';
import { safeParsePagination } from '../lib/pagination.js';
import { listCrossEvents } from '../db/queries/cross.js';
import type { Period } from '../db/queries/cross.js';

const QuerySchema = z.object({
  event_type: z.string().optional(),
  project: z.string().optional(),
  period: z.enum(['24h', '7d', '30d', 'all']).optional(),
});

export async function eventRoutes(server: FastifyInstance): Promise<void> {
  const config = loadConfig();

  server.get('/events', async (request, reply) => {
    const qResult = QuerySchema.safeParse(request.query);
    const { event_type, project, period } = qResult.success
      ? qResult.data
      : { event_type: undefined, project: undefined, period: undefined };

    const pagination = safeParsePagination(request.query as Record<string, string | undefined>);

    const openResult = openDb(config.dbPath, config.supportedSchemaVersions);
    if (!openResult.ok) return reply.status(200).send(wrapDegraded(openResult.reason, config.dbPath));

    const { db } = openResult;
    try {
      const eventFilters: import('../db/queries/cross.js').CrossEventFilters = {
        ...pagination,
        ...(event_type !== undefined ? { event_type } : {}),
        ...(project !== undefined ? { project } : {}),
        ...(period !== undefined ? { period: period as Period } : {}),
      };
      const rows = listCrossEvents(db, eventFilters);

      const data = {
        events: rows.map(r => ({
          executionId: r.execution_id,
          project: r.project,
          feature: r.feature,
          eventType: r.event_type,
          timestamp: r.timestamp,
          description: r.description,
        })),
        pagination: {
          limit: pagination.limit,
          offset: pagination.offset,
        },
      };

      return reply.status(200).send(wrap(data, {}, config.dbPath, db));
    } finally { db.close(); }
  });
}
