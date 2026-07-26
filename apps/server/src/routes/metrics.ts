/**
 * Rotas de metricas agregadas — 8 endpoints.
 * Ref: contracts/api-read.md §Metricas agregadas; spec.md FR-008, FR-009
 * Task 4.4.4, 4.4.5
 *
 * Principio III (Honestidade de Metrica):
 * - cost-over-time: toolCalls como proxy; NUNCA "$"/tokens.
 * - clarify-resolution: meta.approximate=true (taxa derivada/estimada).
 * - mix de modelos: sem endpoint (card "indisponivel nesta fonte" no FE).
 */
import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { openDb } from '../db/open.js';
import { wrap, wrapDegraded } from '../lib/envelope.js';
import { loadConfig } from '../config.js';
import type { MetricPeriod } from '../db/queries/metrics.js';
import {
  getCostOverTime,
  getThroughputByStage,
  getTestPassRate,
  getTestPassRateSeries,
  getHumanLatency,
  getClarifyResolution,
  getDecisionsByScore,
  getExecutionDuration,
  getDepthSubagents,
  getModelMix,
  getModelMixByStage,
  getRecallConsultations,
  getAgentUsage,
  getTokensOverTime,
  getTokensByWave,
} from '../db/queries/metrics.js';
import type { AgentUsageFilters } from '../db/queries/metrics.js';

const PeriodSchema = z.enum(['24h', '7d', '30d', 'all']).optional();
const ProjectSchema = z.object({ project: z.string().optional() });

export async function metricsRoutes(server: FastifyInstance): Promise<void> {
  const config = loadConfig();

  // ─── GET /metrics/cost-over-time ─────────────────────────────────────────
  // Principio III: rotular como "proxy: tool calls" na UI — nunca "$" ou "tokens"
  server.get('/metrics/cost-over-time', async (request, reply) => {
    const q = z.object({ project: z.string().optional(), period: PeriodSchema }).safeParse(request.query);
    const { project, period } = q.success ? q.data : { project: undefined, period: undefined };

    const openResult = openDb(config.dbPath, config.supportedSchemaVersions);
    if (!openResult.ok) return reply.status(200).send(wrapDegraded(openResult.reason, config.dbPath));
    const { db } = openResult;
    try {
      const costFilters: { project?: string; period?: MetricPeriod } = {
        ...(project !== undefined ? { project } : {}),
        ...(period !== undefined ? { period: period as MetricPeriod } : {}),
      };
      const data = getCostOverTime(db, costFilters);
      // data.toolCalls e proxy de custo — rotular na UI como "proxy: tool calls"
      return reply.status(200).send(wrap(data, {}, config.dbPath, db));
    } finally { db.close(); }
  });

  // ─── GET /metrics/throughput-by-stage ────────────────────────────────────
  server.get('/metrics/throughput-by-stage', async (request, reply) => {
    const openResult = openDb(config.dbPath, config.supportedSchemaVersions);
    if (!openResult.ok) return reply.status(200).send(wrapDegraded(openResult.reason, config.dbPath));
    const { db } = openResult;
    try {
      const data = getThroughputByStage(db);
      return reply.status(200).send(wrap(data, {}, config.dbPath, db));
    } finally { db.close(); }
  });

  // ─── GET /metrics/test-pass-rate ─────────────────────────────────────────
  server.get('/metrics/test-pass-rate', async (request, reply) => {
    const openResult = openDb(config.dbPath, config.supportedSchemaVersions);
    if (!openResult.ok) return reply.status(200).send(wrapDegraded(openResult.reason, config.dbPath));
    const { db } = openResult;
    try {
      const data = getTestPassRate(db);
      return reply.status(200).send(wrap(data, {}, config.dbPath, db));
    } finally { db.close(); }
  });

  // ─── GET /metrics/test-pass-rate-series ──────────────────────────────────
  // Serie diaria (agrupa por date(executions.iniciada_em)) para o grafico 14d.
  server.get('/metrics/test-pass-rate-series', async (request, reply) => {
    const q = z.object({ period: PeriodSchema }).safeParse(request.query);
    const period = q.success ? q.data.period : undefined;
    const openResult = openDb(config.dbPath, config.supportedSchemaVersions);
    if (!openResult.ok) return reply.status(200).send(wrapDegraded(openResult.reason, config.dbPath));
    const { db } = openResult;
    try {
      const data = getTestPassRateSeries(db, period !== undefined ? { period: period as MetricPeriod } : {});
      return reply.status(200).send(wrap(data, {}, config.dbPath, db));
    } finally { db.close(); }
  });

  // ─── GET /metrics/human-latency ──────────────────────────────────────────
  server.get('/metrics/human-latency', async (request, reply) => {
    const openResult = openDb(config.dbPath, config.supportedSchemaVersions);
    if (!openResult.ok) return reply.status(200).send(wrapDegraded(openResult.reason, config.dbPath));
    const { db } = openResult;
    try {
      const data = getHumanLatency(db);
      return reply.status(200).send(wrap(data, {}, config.dbPath, db));
    } finally { db.close(); }
  });

  // ─── GET /metrics/clarify-resolution ─────────────────────────────────────
  // meta.approximate=TRUE (Principio III — taxa derivada/estimada)
  server.get('/metrics/clarify-resolution', async (request, reply) => {
    const openResult = openDb(config.dbPath, config.supportedSchemaVersions);
    if (!openResult.ok) return reply.status(200).send(wrapDegraded(openResult.reason, config.dbPath));
    const { db } = openResult;
    try {
      const data = getClarifyResolution(db);
      // OBRIGATORIO: approximate=true (FR-009, Principio III)
      return reply.status(200).send(wrap(data, { approximate: true }, config.dbPath, db));
    } finally { db.close(); }
  });

  // ─── GET /metrics/decisions-by-score ─────────────────────────────────────
  server.get('/metrics/decisions-by-score', async (request, reply) => {
    const openResult = openDb(config.dbPath, config.supportedSchemaVersions);
    if (!openResult.ok) return reply.status(200).send(wrapDegraded(openResult.reason, config.dbPath));
    const { db } = openResult;
    try {
      const data = getDecisionsByScore(db);
      return reply.status(200).send(wrap(data, {}, config.dbPath, db));
    } finally { db.close(); }
  });

  // ─── GET /metrics/execution-duration ─────────────────────────────────────
  server.get('/metrics/execution-duration', async (request, reply) => {
    const q = z.object({ project: z.string().optional(), period: PeriodSchema }).safeParse(request.query);
    const { project, period } = q.success ? q.data : { project: undefined, period: undefined };
    void ProjectSchema;

    const openResult = openDb(config.dbPath, config.supportedSchemaVersions);
    if (!openResult.ok) return reply.status(200).send(wrapDegraded(openResult.reason, config.dbPath));
    const { db } = openResult;
    try {
      const durFilters: { project?: string; period?: MetricPeriod } = {
        ...(project !== undefined ? { project } : {}),
        ...(period !== undefined ? { period: period as MetricPeriod } : {}),
      };
      const data = getExecutionDuration(db, durFilters);
      return reply.status(200).send(wrap(data, {}, config.dbPath, db));
    } finally { db.close(); }
  });

  // ─── GET /metrics/depth-subagents ────────────────────────────────────────
  server.get('/metrics/depth-subagents', async (request, reply) => {
    const openResult = openDb(config.dbPath, config.supportedSchemaVersions);
    if (!openResult.ok) return reply.status(200).send(wrapDegraded(openResult.reason, config.dbPath));
    const { db } = openResult;
    try {
      const data = getDepthSubagents(db);
      return reply.status(200).send(wrap(data, {}, config.dbPath, db));
    } finally { db.close(); }
  });

  // ─── GET /metrics/model-mix ──────────────────────────────────────────────
  // DERIVADO das decisoes de roteamento (escolha='model:%'). Intenção do
  // roteador, NAO confirmação da harness. Dono canônico: model-routing-report.sh
  // (FR-010 — UI rotula como derivado). meta.approximate=true.
  server.get('/metrics/model-mix', async (request, reply) => {
    const openResult = openDb(config.dbPath, config.supportedSchemaVersions);
    if (!openResult.ok) return reply.status(200).send(wrapDegraded(openResult.reason, config.dbPath));
    const { db } = openResult;
    try {
      const data = getModelMix(db);
      return reply.status(200).send(wrap(data, { approximate: true }, config.dbPath, db));
    } finally { db.close(); }
  });

  // ─── GET /metrics/model-mix-by-stage ─────────────────────────────────────
  server.get('/metrics/model-mix-by-stage', async (request, reply) => {
    const openResult = openDb(config.dbPath, config.supportedSchemaVersions);
    if (!openResult.ok) return reply.status(200).send(wrapDegraded(openResult.reason, config.dbPath));
    const { db } = openResult;
    try {
      const data = getModelMixByStage(db);
      return reply.status(200).send(wrap(data, { approximate: true }, config.dbPath, db));
    } finally { db.close(); }
  });

  // ─── GET /metrics/recall-consultations ───────────────────────────────────
  // Consultas ao histórico (read-back loop, schema v3). Contagem EXATA
  // (Princípio III — não proxy/aproximada): total + split produtivas/vazias.
  server.get('/metrics/recall-consultations', async (request, reply) => {
    const openResult = openDb(config.dbPath, config.supportedSchemaVersions);
    if (!openResult.ok) return reply.status(200).send(wrapDegraded(openResult.reason, config.dbPath));
    const { db } = openResult;
    try {
      const data = getRecallConsultations(db);
      return reply.status(200).send(wrap(data, {}, config.dbPath, db));
    } finally { db.close(); }
  });

  // ─── Metricas de consumo de subagente (schema v10) ───────────────────────
  // NAO sao proxy nem estimativa: o harness mede, o hook do cstk grava e
  // `cstk recall --ingest` agrega por onda. Por isso NAO levam
  // meta.approximate. Sao, porem, AMOSTRA — spawns em background nao reportam
  // uso — e por isso todo payload carrega spawnsTotal/spawnsWithUsage juntos.
  // Base v<10 -> campos null / array vazio, nunca zero fabricado.
  function parseUsageQuery(query: unknown): AgentUsageFilters {
    const q = z.object({
      project: z.string().trim().min(1).max(200).optional(),
      feature: z.string().trim().min(1).max(200).optional(),
      period: PeriodSchema,
    }).safeParse(query);
    if (!q.success) return {};
    const { project, feature, period } = q.data;
    return {
      ...(project !== undefined ? { project } : {}),
      ...(feature !== undefined ? { feature } : {}),
      ...(period !== undefined ? { period: period as MetricPeriod } : {}),
    };
  }

  // ─── GET /metrics/agent-usage ────────────────────────────────────────────
  server.get('/metrics/agent-usage', async (request, reply) => {
    const openResult = openDb(config.dbPath, config.supportedSchemaVersions);
    if (!openResult.ok) return reply.status(200).send(wrapDegraded(openResult.reason, config.dbPath));
    const { db } = openResult;
    try {
      const data = getAgentUsage(db, parseUsageQuery(request.query));
      return reply.status(200).send(wrap(data, {}, config.dbPath, db));
    } finally { db.close(); }
  });

  // ─── GET /metrics/tokens-over-time ───────────────────────────────────────
  // Dias sem medicao sao OMITIDOS (nao viram 0) — ver getTokensOverTime.
  server.get('/metrics/tokens-over-time', async (request, reply) => {
    const openResult = openDb(config.dbPath, config.supportedSchemaVersions);
    if (!openResult.ok) return reply.status(200).send(wrapDegraded(openResult.reason, config.dbPath));
    const { db } = openResult;
    try {
      const data = getTokensOverTime(db, parseUsageQuery(request.query));
      return reply.status(200).send(wrap(data, {}, config.dbPath, db));
    } finally { db.close(); }
  });

  // ─── GET /metrics/tokens-by-wave ─────────────────────────────────────────
  server.get('/metrics/tokens-by-wave', async (request, reply) => {
    const openResult = openDb(config.dbPath, config.supportedSchemaVersions);
    if (!openResult.ok) return reply.status(200).send(wrapDegraded(openResult.reason, config.dbPath));
    const { db } = openResult;
    try {
      const data = getTokensByWave(db, parseUsageQuery(request.query), 20);
      return reply.status(200).send(wrap(data, {}, config.dbPath, db));
    } finally { db.close(); }
  });
}
