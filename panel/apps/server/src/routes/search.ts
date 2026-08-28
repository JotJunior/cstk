/**
 * Rota GET /search — busca FTS5 com rate-limit especifico.
 * Ref: contracts/search-fts.md; spec.md FR-012, FR-020; research.md §Decision 6
 * Tasks 4.5.1 – 4.5.4 + 3.5.4
 *
 * Dois layers de escaping:
 * 1. Camada FTS5: sanitizeFts() tokeniza e envolve em aspas duplas
 * 2. Camada SQL: binding parametrizado via `?` — nunca interpolacao
 *
 * Principio V (FR-012): entrada hostil → resultado valido ou vazio, NUNCA 5xx (SC-005).
 * Rate-limit: registrado APENAS nesta rota (FR-020) — 30 req/min por IP.
 */
import type { FastifyInstance } from 'fastify';
import rateLimit from '@fastify/rate-limit';
import { z } from 'zod';
import { openDb } from '../db/open.js';
import { wrap } from '../lib/envelope.js';
import { loadConfig } from '../config.js';
import { sanitizeFts } from '../lib/fts.js';

// Params de busca (search-fts.md)
const SearchQuerySchema = z.object({
  q: z
    .string()
    .min(1, 'q is required')
    .max(200, 'q too long')
    .transform(v => v.trim()),
  type: z.string().optional(),
  project: z.string().optional(),
  feature: z.string().optional(),
  limit: z
    .string()
    .optional()
    .transform(v => (v !== undefined ? parseInt(v, 10) : 20))
    .pipe(z.number().int().min(1).max(50)),
  offset: z
    .string()
    .optional()
    .transform(v => (v !== undefined ? parseInt(v, 10) : 0))
    .pipe(z.number().int().min(0)),
});

export async function searchRoutes(server: FastifyInstance): Promise<void> {
  const config = loadConfig();

  // Rate-limit APENAS nesta rota (FR-020) — 30 req/min por IP
  // Registrado como scoped plugin para nao afetar outras rotas
  await server.register(async (scoped) => {
    await scoped.register(rateLimit, {
      max: 30,
      timeWindow: '1 minute',
      skipOnError: true,
      keyGenerator: (req) => req.ip,
    });

    // GET /search
    scoped.get('/search', async (request, reply) => {
      const qResult = SearchQuerySchema.safeParse(request.query);

      if (!qResult.success) {
        // q vazio ou invalido → 400 (validacao, nao estado de dado)
        const firstError = qResult.error.errors[0];
        return reply.status(400).send({
          data: null,
          meta: {
            degraded: false,
            reason: null,
            freshness: { mtime: '', maxIngestedAt: '' },
            schemaVersion: '2',
          },
          error: firstError?.message ?? 'Invalid query params',
        });
      }

      const { q, type, project, feature, limit, offset } = qResult.data;

      // Camada 1: sanitizacao FTS5 (research.md §Decision 6)
      const ftsQuery = sanitizeFts(q);

      const openResult = openDb(config.dbPath, config.supportedSchemaVersions);
      if (!openResult.ok) {
        // DB degradado — retornar resultados vazios com meta.degraded=true
        return reply.status(200).send({
          data: { results: [], pagination: { limit, offset, total: 0, hasMore: false } },
          meta: {
            degraded: true,
            reason: openResult.reason,
            freshness: { mtime: '', maxIngestedAt: '' },
            schemaVersion: '2',
          },
        });
      }

      const { db } = openResult;
      try {
        // Camada 2: binding parametrizado — NUNCA interpolacao (search-fts.md)
        let results: {
          body: string; type: string; project: string; feature: string;
          wave: string; source_id: string; source_ts: string; rank: number;
          execution_id: string | null;
        }[] = [];

        let total = 0;

        if (ftsQuery.length > 0) {
          // Construir query com filtros opcionais via ? binding
          // Todos os parametros opcionais usam "? IS NULL OR col = ?" pattern
          try {
            results = db
              .prepare(`
                SELECT body, type, project, feature, wave,
                       source_id, source_ts, bm25(knowledge_fts) AS rank,
                       -- Resolve a execucao de origem pela chave unica (project,feature,wave,source_id)
                       -- na tabela-fonte do tipo. NULL para tipos sem vinculo (ex.: memory).
                       CASE type
                         WHEN 'decision'   THEN (SELECT execution_id FROM decisions d   WHERE d.project = knowledge_fts.project AND d.feature = knowledge_fts.feature AND d.wave = knowledge_fts.wave AND d.source_id = knowledge_fts.source_id)
                         WHEN 'block'      THEN (SELECT execution_id FROM blocks b      WHERE b.project = knowledge_fts.project AND b.feature = knowledge_fts.feature AND b.wave = knowledge_fts.wave AND b.source_id = knowledge_fts.source_id)
                         WHEN 'skill'      THEN (SELECT execution_id FROM skills s      WHERE s.project = knowledge_fts.project AND s.feature = knowledge_fts.feature AND s.wave = knowledge_fts.wave AND s.source_id = knowledge_fts.source_id)
                         WHEN 'suggestion' THEN (SELECT execution_id FROM suggestions g WHERE g.project = knowledge_fts.project AND g.feature = knowledge_fts.feature AND g.wave = knowledge_fts.wave AND g.source_id = knowledge_fts.source_id)
                       END AS execution_id
                FROM knowledge_fts
                WHERE knowledge_fts MATCH ?
                  AND (? IS NULL OR type = ?)
                  AND (? IS NULL OR project = ?)
                  AND (? IS NULL OR feature = ?)
                ORDER BY rank
                LIMIT ? OFFSET ?
              `)
              .all(
                ftsQuery,
                type ?? null, type ?? null,
                project ?? null, project ?? null,
                feature ?? null, feature ?? null,
                limit, offset
              ) as typeof results;

            // Contar total (sem limit/offset)
            const countRow = db
              .prepare(`
                SELECT count(*) as n
                FROM knowledge_fts
                WHERE knowledge_fts MATCH ?
                  AND (? IS NULL OR type = ?)
                  AND (? IS NULL OR project = ?)
                  AND (? IS NULL OR feature = ?)
              `)
              .get(
                ftsQuery,
                type ?? null, type ?? null,
                project ?? null, project ?? null,
                feature ?? null, feature ?? null
              ) as { n: number };
            total = countRow.n;
          } catch {
            // FTS5 pode falhar com queries muito hostis mesmo apos sanitizacao
            // Principio II: nunca 5xx — retornar results vazio (SC-005)
            results = [];
            total = 0;
          }
        }

        const data = {
          results: results.map(r => ({
            body: r.body,       // UNTRUSTED — FE renderiza via textContent
            type: r.type,
            project: r.project,
            feature: r.feature,
            wave: r.wave,
            sourceId: r.source_id,
            sourceTs: r.source_ts,
            rank: r.rank,
            // Omitido (undefined) quando o tipo nao tem execucao de origem
            ...(r.execution_id ? { executionId: r.execution_id } : {}),
          })),
          pagination: { limit, offset, total, hasMore: offset + results.length < total },
        };

        const envelope = wrap(data, {}, config.dbPath, db);
        return reply.status(200).send(envelope);
      } finally {
        db.close();
      }
    });
  });
}
