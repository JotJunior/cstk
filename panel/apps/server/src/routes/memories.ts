/**
 * Rota GET /memories — auto-memorias do Claude Code (schema v4).
 * Ref: ../claude-ai-tips/docs/specs/recall-memory-mirror/ (produtor)
 *
 * Read-only (Principio I) e best-effort (Principio II): em base v2/v3 sem a
 * tabela `memories`, retorna listas vazias — NUNCA degraded/erro (a ausencia da
 * feature nao e um defeito da base). Filtro opcional por projeto; o seletor
 * recebe a lista COMPLETA de projetos, independente do filtro corrente.
 *
 * Conteudo UNTRUSTED: `description`/`body` vem de `.md` autorados pelo operador
 * (ja scrubbed na ingestao). O FE renderiza via textContent (TextRaw), nunca HTML.
 */
import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { openDb } from '../db/open.js';
import { wrap, wrapDegraded } from '../lib/envelope.js';
import { generateETag, etagMatches } from '../lib/etag.js';
import { loadConfig } from '../config.js';
import { safeParsePagination } from '../lib/pagination.js';
import {
  listMemories,
  listMemoryProjects,
  countMemories,
  normalizeMemoryType,
} from '../db/queries/memories.js';

const QuerySchema = z.object({
  project: z.string().min(1).max(200).optional(),
});

export async function memoryRoutes(server: FastifyInstance): Promise<void> {
  const config = loadConfig();

  server.get('/memories', async (request, reply) => {
    const qResult = QuerySchema.safeParse(request.query);
    const project = qResult.success ? qResult.data.project : undefined;
    const pagination = safeParsePagination(
      request.query as Record<string, string | undefined>,
    );

    const openResult = openDb(config.dbPath, config.supportedSchemaVersions);
    if (!openResult.ok) {
      return reply.status(200).send(wrapDegraded(openResult.reason, config.dbPath));
    }

    const { db } = openResult;
    try {
      const rows = listMemories(db, {
        ...pagination,
        ...(project !== undefined ? { project } : {}),
      });
      const projects = listMemoryProjects(db);
      const total = countMemories(db, project);

      const data = {
        memories: rows.map((r) => ({
          project: r.project,
          slug: r.slug,
          type: normalizeMemoryType(r.type),
          description: r.description,
          body: r.body_scrubbed,
          path: r.path,
          indexedAt: r.indexed_at,
        })),
        projects,
        pagination: {
          total,
          limit: pagination.limit,
          offset: pagination.offset,
          hasMore: pagination.offset + rows.length < total,
        },
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
