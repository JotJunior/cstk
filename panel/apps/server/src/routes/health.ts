/**
 * Rota GET /health — saude do servidor e DB.
 * Ref: contracts/api-read.md §Saude e visao geral; spec.md FR-005, FR-014
 * Task 4.1.1
 *
 * Sempre retorna 200 — mesmo degradado (Principio II).
 * meta.degraded indica o estado do DB.
 */
import { statSync } from 'node:fs';
import type { FastifyInstance } from 'fastify';
import { openDb } from '../db/open.js';
import { wrap, wrapDegraded } from '../lib/envelope.js';
import { generateETag, etagMatches } from '../lib/etag.js';
import { loadConfig } from '../config.js';

export interface HealthData {
  ok: boolean;
  dbReachable: boolean;
  quickCheck: boolean;
  /** Caminho do arquivo knowledge.db (tela Fonte de Dados). */
  path: string;
  /** Tamanho do arquivo em bytes; null se indisponivel. */
  sizeBytes: number | null;
  counts: {
    executions: number;
    waves: number;
    decisions: number;
    tasks: number;
    events: number;
    alertSignals: number;
    bloqueios: number;
    skills: number;
    retros: number;
    /** tabela `memories` (schema v4); 0 em bases v2/v3 sem a tabela. */
    memories: number;
    ftsDecisoes: number;
    ftsRetros: number;
  };
}

const EMPTY_COUNTS: HealthData['counts'] = {
  executions: 0, waves: 0, decisions: 0, tasks: 0, events: 0, alertSignals: 0,
  bloqueios: 0, skills: 0, retros: 0, memories: 0, ftsDecisoes: 0, ftsRetros: 0,
};

export async function healthRoutes(server: FastifyInstance): Promise<void> {
  const config = loadConfig();

  server.get('/health', async (request, reply) => {
    const openResult = openDb(config.dbPath, config.supportedSchemaVersions);

    if (!openResult.ok) {
      const envelope = wrapDegraded(openResult.reason, config.dbPath);
      const responseData: HealthData = {
        ok: false,
        dbReachable: false,
        quickCheck: false,
        path: config.dbPath,
        sizeBytes: null,
        counts: { ...EMPTY_COUNTS },
      };
      // Retornar shape valido mesmo degradado
      return reply.status(200).send({
        data: responseData,
        meta: envelope.meta,
      });
    }

    const { db } = openResult;
    try {
      // Contagem por tabela; tabelas opcionais sob try/catch (schemas v2 variam).
      type CountRow = { n: number };
      const countOf = (table: string): number => {
        try { return (db.prepare(`SELECT count(*) as n FROM ${table}`).get() as CountRow).n; }
        catch { return 0; }
      };

      const counts: HealthData['counts'] = {
        executions: countOf('executions'),
        waves: countOf('waves'),
        decisions: countOf('decisions'),
        tasks: countOf('tasks'),
        events: countOf('events'),
        alertSignals: countOf('alert_signals'),
        bloqueios: countOf('bloqueios'),
        skills: countOf('skills'),
        retros: countOf('retros'),
        memories: countOf('memories'),
        ftsDecisoes: countOf('fts_decisoes'),
        ftsRetros: countOf('fts_retros'),
      };

      let sizeBytes: number | null = null;
      try { sizeBytes = statSync(config.dbPath).size; } catch { /* ignorar */ }

      const data: HealthData = {
        ok: true,
        dbReachable: true,
        quickCheck: true,
        path: config.dbPath,
        sizeBytes,
        counts,
      };

      const envelope = wrap(data, {}, config.dbPath, db);

      // ETag/304
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
