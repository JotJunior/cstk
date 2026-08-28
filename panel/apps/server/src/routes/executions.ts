/**
 * Rotas de detalhe de execucao e sub-recursos.
 * Ref: contracts/api-read.md §Execucao; spec.md FR-004, FR-020; quickstart §Cenario 2
 * Tasks 4.3.1 – 4.3.6
 *
 * Endpoints:
 *   GET /executions/:execucaoId                              (detalhe)
 *   GET /executions/:execucaoId/waves                        (timeline)
 *   GET /executions/:execucaoId/decisions?wave&etapa&score&limit&offset
 *   GET /executions/:execucaoId/tasks
 *   GET /executions/:execucaoId/events
 *   GET /executions/:execucaoId/alerts
 *   GET /executions/:execucaoId/bloqueios
 *   GET /executions/:execucaoId/skills
 */
import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { openDb } from '../db/open.js';
import { wrap, wrapDegraded } from '../lib/envelope.js';
import { generateETag, etagMatches } from '../lib/etag.js';
import { loadConfig } from '../config.js';
import { resolveProjectRoot } from '../lib/project-root.js';
import { deriveStateDir, getWatcherCacheEntry, isWatcherDegraded } from '../watchers/ingest-watcher.js';
import { safeParsePagination } from '../lib/pagination.js';
import { getExecution, listExecutions } from '../db/queries/executions.js';
import { listWavesByExecution } from '../db/queries/waves.js';
import { listDecisions, countDecisions, getDecisionScoreDistribution } from '../db/queries/decisions.js';
import { listTasksByExecution } from '../db/queries/tasks.js';
import { listEventsByExecution } from '../db/queries/events.js';
import { listAlertsByExecution } from '../db/queries/alerts.js';
import { listBlocksByExecution } from '../db/queries/blocks.js';
import { listSkillsByExecution } from '../db/queries/skills.js';
import { listSuggestionsByExecution } from '../db/queries/suggestions.js';
import {
  mapExecution, mapExecutions, mapWave, mapWaves, mapDecision, mapDecisions,
  mapTask, mapTasks, mapEvent, mapEvents,
  mapAlert, mapAlerts, mapBlock, mapBlocks,
  mapSkill, mapSkills, mapSuggestions,
} from '../mappers/index.js';

// Validacao de path param (FR-018 — sem traversal)
const ExecParamSchema = z.object({
  execucaoId: z.string().min(1).max(200).regex(/^[^/\\.<>]+$/, 'invalid execucaoId'),
});

// Query params para /decisions
const DecisionQuerySchema = z.object({
  wave: z.string().optional(),
  etapa: z.string().optional(),
  score: z
    .string()
    .optional()
    .transform(v => v !== undefined ? parseInt(v, 10) : undefined)
    .pipe(z.union([z.literal(0), z.literal(1), z.literal(2), z.literal(3), z.undefined()])),
  limit: z.string().optional(),
  offset: z.string().optional(),
});

export async function executionRoutes(server: FastifyInstance): Promise<void> {
  const config = loadConfig();

  // Helper: validar param e abrir DB
  function validateParam(params: unknown) {
    return ExecParamSchema.safeParse(params);
  }

  function etagReply(
    server: FastifyInstance,
    request: Parameters<typeof server.get>[1] extends (req: infer R, ...args: unknown[]) => unknown ? R : never,
    reply: Parameters<typeof server.get>[1] extends (req: unknown, rep: infer P, ...args: unknown[]) => unknown ? P : never,
    etag: string | null
  ) {
    const ifNoneMatch = (request as { headers: Record<string, string | undefined> }).headers['if-none-match'];
    if (etag && etagMatches(ifNoneMatch, etag)) return true;
    if (etag) void (reply as { header: (k: string, v: string) => void }).header('ETag', etag);
    return false;
  }
  void etagReply; // suppress unused warning — usaremos inline abaixo

  // ─── GET /executions (lista paginada) ──────────────────────────────────────
  // Rota estatica registrada ANTES da dinamica /:execucaoId.
  server.get('/executions', async (request, reply) => {
    const pagination = safeParsePagination(request.query as Record<string, string | undefined>);
    const openResult = openDb(config.dbPath, config.supportedSchemaVersions);
    if (!openResult.ok) return reply.status(200).send(wrapDegraded(openResult.reason, config.dbPath));

    const { db } = openResult;
    try {
      const all = mapExecutions(listExecutions(db));
      const total = all.length;
      const executions = all.slice(pagination.offset, pagination.offset + pagination.limit);
      const data = {
        executions,
        pagination: {
          total,
          limit: pagination.limit,
          offset: pagination.offset,
          hasMore: pagination.offset + executions.length < total,
        },
      };
      const envelope = wrap(data, {}, config.dbPath, db);
      const etag = generateETag(envelope.meta.freshness);
      const ifNoneMatch = request.headers['if-none-match'] as string | undefined;
      if (etag && etagMatches(ifNoneMatch, etag)) return reply.status(304).send();
      if (etag) void reply.header('ETag', etag);
      return reply.status(200).send(envelope);
    } finally { db.close(); }
  });

  // ─── GET /executions/:execucaoId ───────────────────────────────────────────
  server.get('/executions/:execucaoId', async (request, reply) => {
    const paramResult = validateParam(request.params);
    if (!paramResult.success) {
      return reply.status(400).send({ data: null, meta: emptyMeta(), error: 'Invalid execucaoId' });
    }

    const { execucaoId } = paramResult.data;
    const openResult = openDb(config.dbPath, config.supportedSchemaVersions);
    if (!openResult.ok) return reply.status(200).send(wrapDegraded(openResult.reason, config.dbPath));

    const { db } = openResult;
    try {
      const row = getExecution(db, execucaoId);
      if (!row) return reply.status(200).send(wrap(null, {}, config.dbPath, db));

      const envelope = wrap(mapExecution(row), {}, config.dbPath, db);

      // CHK056/dec-027 (task 2.4.1, feature state-watchers-and-docs): sinaliza
      // degradacao do WATCHER (mecanismo de frescor em 2o plano) sem nulificar
      // `data` — a execucao foi lida com sucesso da knowledge.db; apenas a
      // ultima tentativa de ingestao em background para este state-dir pode
      // ter falhado. Granularidade restrita ao detalhe (2.4.2 — a listagem
      // GET /executions permanece inalterada).
      const watcherProjectPath = resolveProjectRoot(db, row.project);
      if (watcherProjectPath) {
        const watcherStateDir = deriveStateDir(watcherProjectPath, row.feature);
        if (watcherStateDir && isWatcherDegraded(getWatcherCacheEntry(watcherStateDir))) {
          envelope.meta.degraded = true;
          envelope.meta.reason = 'watcher-ingestion-failed';
        }
      }

      const etag = generateETag(envelope.meta.freshness);
      const ifNoneMatch = request.headers['if-none-match'] as string | undefined;
      if (etag && etagMatches(ifNoneMatch, etag)) return reply.status(304).send();
      if (etag) void reply.header('ETag', etag);
      return reply.status(200).send(envelope);
    } finally { db.close(); }
  });

  // ─── GET /executions/:execucaoId/waves ────────────────────────────────────
  server.get('/executions/:execucaoId/waves', async (request, reply) => {
    const paramResult = validateParam(request.params);
    if (!paramResult.success) return reply.status(400).send({ data: null, meta: emptyMeta(), error: 'Invalid execucaoId' });

    const { execucaoId } = paramResult.data;
    const openResult = openDb(config.dbPath, config.supportedSchemaVersions);
    if (!openResult.ok) return reply.status(200).send(wrapDegraded(openResult.reason, config.dbPath));

    const { db } = openResult;
    try {
      const rows = listWavesByExecution(db, execucaoId);
      const waves = mapWaves(rows);
      const envelope = wrap(waves, {}, config.dbPath, db);
      const etag = generateETag(envelope.meta.freshness);
      const ifNoneMatch = request.headers['if-none-match'] as string | undefined;
      if (etag && etagMatches(ifNoneMatch, etag)) return reply.status(304).send();
      if (etag) void reply.header('ETag', etag);
      return reply.status(200).send(envelope);
    } finally { db.close(); }
  });

  // ─── GET /executions/:execucaoId/decisions (paginado) ─────────────────────
  server.get('/executions/:execucaoId/decisions', async (request, reply) => {
    const paramResult = validateParam(request.params);
    if (!paramResult.success) return reply.status(400).send({ data: null, meta: emptyMeta(), error: 'Invalid execucaoId' });

    const qResult = DecisionQuerySchema.safeParse(request.query);
    if (!qResult.success) {
      return reply.status(400).send({ data: null, meta: emptyMeta(), error: 'Invalid query params: ' + qResult.error.message });
    }

    const { execucaoId } = paramResult.data;
    const pagination = safeParsePagination(request.query as Record<string, string | undefined>);
    const { wave, etapa, score } = qResult.data;
    // `etapa` (query param name kept for URL back-compat) maps to `stage` in DecisionFilters
    const filters: import('../db/queries/decisions.js').DecisionFilters = {
      limit: pagination.limit,
      offset: pagination.offset,
      ...(wave !== undefined ? { wave } : {}),
      ...(etapa !== undefined ? { stage: etapa } : {}),
      ...(score !== undefined ? { score } : {}),
    };

    const openResult = openDb(config.dbPath, config.supportedSchemaVersions);
    if (!openResult.ok) return reply.status(200).send(wrapDegraded(openResult.reason, config.dbPath));

    const { db } = openResult;
    try {
      const rows = listDecisions(db, execucaoId, filters);
      const countFilters: import('../db/queries/decisions.js').DecisionFilters = {
        limit: pagination.limit,
        offset: pagination.offset,
        ...(wave !== undefined ? { wave } : {}),
        ...(etapa !== undefined ? { stage: etapa } : {}),
        ...(score !== undefined ? { score } : {}),
      };
      const total = countDecisions(db, execucaoId, countFilters);
      const decisions = mapDecisions(rows);

      const data = {
        decisions,
        pagination: {
          total,
          limit: pagination.limit,
          offset: pagination.offset,
          hasMore: pagination.offset + decisions.length < total,
        },
      };

      const envelope = wrap(data, {}, config.dbPath, db);
      const etag = generateETag(envelope.meta.freshness);
      const ifNoneMatch = request.headers['if-none-match'] as string | undefined;
      if (etag && etagMatches(ifNoneMatch, etag)) return reply.status(304).send();
      if (etag) void reply.header('ETag', etag);
      return reply.status(200).send(envelope);
    } finally { db.close(); }
  });

  // ─── GET /executions/:execucaoId/tasks ────────────────────────────────────
  server.get('/executions/:execucaoId/tasks', async (request, reply) => {
    const paramResult = validateParam(request.params);
    if (!paramResult.success) return reply.status(400).send({ data: null, meta: emptyMeta(), error: 'Invalid execucaoId' });

    const { execucaoId } = paramResult.data;
    const openResult = openDb(config.dbPath, config.supportedSchemaVersions);
    if (!openResult.ok) return reply.status(200).send(wrapDegraded(openResult.reason, config.dbPath));

    const { db } = openResult;
    try {
      const rows = listTasksByExecution(db, execucaoId);
      const tasks = mapTasks(rows);

      // pass rate
      const pass = tasks.filter(t => t.outcome === 'pass').length;
      const total = tasks.filter(t => t.outcome !== null).length;
      const passRate = total > 0 ? pass / total : null;

      const data = { tasks, passRate };
      const envelope = wrap(data, {}, config.dbPath, db);
      return reply.status(200).send(envelope);
    } finally { db.close(); }
  });

  // ─── GET /executions/:execucaoId/events ───────────────────────────────────
  server.get('/executions/:execucaoId/events', async (request, reply) => {
    const paramResult = validateParam(request.params);
    if (!paramResult.success) return reply.status(400).send({ data: null, meta: emptyMeta(), error: 'Invalid execucaoId' });

    const { execucaoId } = paramResult.data;
    const openResult = openDb(config.dbPath, config.supportedSchemaVersions);
    if (!openResult.ok) return reply.status(200).send(wrapDegraded(openResult.reason, config.dbPath));

    const { db } = openResult;
    try {
      const rows = listEventsByExecution(db, execucaoId);
      const events = mapEvents(rows);
      const envelope = wrap(events, {}, config.dbPath, db);
      return reply.status(200).send(envelope);
    } finally { db.close(); }
  });

  // ─── GET /executions/:execucaoId/alerts ───────────────────────────────────
  server.get('/executions/:execucaoId/alerts', async (request, reply) => {
    const paramResult = validateParam(request.params);
    if (!paramResult.success) return reply.status(400).send({ data: null, meta: emptyMeta(), error: 'Invalid execucaoId' });

    const { execucaoId } = paramResult.data;
    const openResult = openDb(config.dbPath, config.supportedSchemaVersions);
    if (!openResult.ok) return reply.status(200).send(wrapDegraded(openResult.reason, config.dbPath));

    const { db } = openResult;
    try {
      const rows = listAlertsByExecution(db, execucaoId);
      const alerts = mapAlerts(rows);
      const envelope = wrap(alerts, {}, config.dbPath, db);
      return reply.status(200).send(envelope);
    } finally { db.close(); }
  });

  // ─── GET /executions/:execucaoId/bloqueios ────────────────────────────────
  server.get('/executions/:execucaoId/bloqueios', async (request, reply) => {
    const paramResult = validateParam(request.params);
    if (!paramResult.success) return reply.status(400).send({ data: null, meta: emptyMeta(), error: 'Invalid execucaoId' });

    const { execucaoId } = paramResult.data;
    const openResult = openDb(config.dbPath, config.supportedSchemaVersions);
    if (!openResult.ok) return reply.status(200).send(wrapDegraded(openResult.reason, config.dbPath));

    const { db } = openResult;
    try {
      const rows = listBlocksByExecution(db, execucaoId);
      const bloqueios = mapBlocks(rows);
      const envelope = wrap(bloqueios, {}, config.dbPath, db);
      return reply.status(200).send(envelope);
    } finally { db.close(); }
  });

  // ─── GET /executions/:execucaoId/skills ───────────────────────────────────
  server.get('/executions/:execucaoId/skills', async (request, reply) => {
    const paramResult = validateParam(request.params);
    if (!paramResult.success) return reply.status(400).send({ data: null, meta: emptyMeta(), error: 'Invalid execucaoId' });

    const { execucaoId } = paramResult.data;
    const openResult = openDb(config.dbPath, config.supportedSchemaVersions);
    if (!openResult.ok) return reply.status(200).send(wrapDegraded(openResult.reason, config.dbPath));

    const { db } = openResult;
    try {
      const rows = listSkillsByExecution(db, execucaoId);
      const skills = mapSkills(rows);
      const envelope = wrap(skills, {}, config.dbPath, db);
      return reply.status(200).send(envelope);
    } finally { db.close(); }
  });

  // ─── GET /executions/:execucaoId/suggestions ──────────────────────────────
  // Sugestoes de melhoria propostas pela IA (schema v5 — recall-suggestions).
  // Bases v<5 degradam para [] (a query checa hasTable; Principio II).
  server.get('/executions/:execucaoId/suggestions', async (request, reply) => {
    const paramResult = validateParam(request.params);
    if (!paramResult.success) return reply.status(400).send({ data: null, meta: emptyMeta(), error: 'Invalid execucaoId' });

    const { execucaoId } = paramResult.data;
    const openResult = openDb(config.dbPath, config.supportedSchemaVersions);
    if (!openResult.ok) return reply.status(200).send(wrapDegraded(openResult.reason, config.dbPath));

    const { db } = openResult;
    try {
      const rows = listSuggestionsByExecution(db, execucaoId);
      const suggestions = mapSuggestions(rows);
      const envelope = wrap(suggestions, {}, config.dbPath, db);
      return reply.status(200).send(envelope);
    } finally { db.close(); }
  });

  // ─── GET /executions/:execucaoId/score-distribution ───────────────────────
  server.get('/executions/:execucaoId/score-distribution', async (request, reply) => {
    const paramResult = validateParam(request.params);
    if (!paramResult.success) return reply.status(400).send({ data: null, meta: emptyMeta(), error: 'Invalid execucaoId' });

    const { execucaoId } = paramResult.data;
    const openResult = openDb(config.dbPath, config.supportedSchemaVersions);
    if (!openResult.ok) return reply.status(200).send(wrapDegraded(openResult.reason, config.dbPath));

    const { db } = openResult;
    try {
      const data = getDecisionScoreDistribution(db, execucaoId);
      return reply.status(200).send(wrap(data, {}, config.dbPath, db));
    } finally { db.close(); }
  });
}

function emptyMeta() {
  return {
    degraded: false,
    reason: null,
    freshness: { mtime: '', maxIngestedAt: '' },
    schemaVersion: '2',
  };
}

// Re-export individual mappers used only internally (suppress unused import warning)
void mapExecution; void mapWave; void mapDecision; void mapTask; void mapEvent; void mapAlert; void mapBlock; void mapSkill;
