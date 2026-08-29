/**
 * Rota GET /tasks — tasks cross-execucao.
 * Ref: contracts/api-read.md §Cross-execucao; task 4.4.2
 */
import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { openDb } from '../db/open.js';
import { wrap, wrapDegraded } from '../lib/envelope.js';
import { loadConfig } from '../config.js';
import { safeParsePagination } from '../lib/pagination.js';
import { listCrossTasks } from '../db/queries/cross.js';

const QuerySchema = z.object({
  project: z.string().optional(),
  feature: z.string().optional(),
  outcome: z.enum(['pass', 'fail']).optional(),
});

export async function taskRoutes(server: FastifyInstance): Promise<void> {
  const config = loadConfig();

  server.get('/tasks', async (request, reply) => {
    const qResult = QuerySchema.safeParse(request.query);
    const { project, feature, outcome } = qResult.success
      ? qResult.data
      : { project: undefined, feature: undefined, outcome: undefined };

    const pagination = safeParsePagination(request.query as Record<string, string | undefined>);

    const openResult = openDb(config.dbPath, config.supportedSchemaVersions);
    if (!openResult.ok) return reply.status(200).send(wrapDegraded(openResult.reason, config.dbPath));

    const { db } = openResult;
    try {
      const taskFilters: import('../db/queries/cross.js').CrossTaskFilters = {
        ...pagination,
        ...(project !== undefined ? { project } : {}),
        ...(feature !== undefined ? { feature } : {}),
        ...(outcome !== undefined ? { outcome } : {}),
      };
      const rows = listCrossTasks(db, taskFilters);

      const data = {
        tasks: rows.map(r => ({
          wave: r.wave,
          executionId: r.execution_id,
          project: r.project,
          feature: r.feature,
          title: r.title,
          outcome: r.outcome,
          testsRun: r.tests_run,
          testsPassed: r.tests_passed,
          lintOk: r.lint_ok === null ? null : r.lint_ok === 1,
          touchedFilesCount: r.touched_files,
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
