/**
 * Utilitario para montar ApiEnvelope<T> — envolve dados com Meta computado.
 * Ref: contracts/envelope.md; spec.md FR-023; Principio VI
 * Task 3.5.1
 *
 * Principio II (Degradar, Nunca Quebrar): wrap() aceita db=null (modo degradado)
 * e computa freshness fallback com strings vazias.
 * Principio VI (Snapshot que Muda): freshness e calculado a cada chamada.
 */
import type Database from 'better-sqlite3';
import { statSync } from 'node:fs';
import type { ApiEnvelope, Meta, Freshness } from '@cstk-panel/shared-types';
import { computeFreshness } from '../db/freshness.js';

/**
 * Le schema_meta.schema_version da base aberta (FR-V3-003). Nunca lanca —
 * fallback '2' quando ilegivel (db null/degradado ou tabela ausente em race).
 * Em modo degradado o open ja barrou versoes nao suportadas, entao o valor
 * lido aqui pertence ao conjunto aceito (ex.: '2' ou '3').
 */
function readSchemaVersion(db: Database.Database | null): string {
  if (db === null) return '2';
  try {
    const row = db
      .prepare("SELECT value FROM schema_meta WHERE key = 'schema_version'")
      .get() as { value: string } | undefined;
    return row?.value ?? '2';
  } catch {
    return '2';
  }
}

export interface WrapOptions {
  /** Se true, data sera null e degraded=true */
  degraded?: boolean;
  /** Motivo da degradacao (apenas se degraded=true) */
  reason?: string | null;
  /** Se true, alguma metrica e estimada (Principio III) */
  approximate?: boolean;
}

/**
 * Envolve dados no envelope padrao com meta computado automaticamente.
 *
 * @param data    Dados da resposta (null automaticamente se degraded=true)
 * @param opts    Opcoes de degradacao e metadados
 * @param dbPath  Path do arquivo DB (para computar mtime)
 * @param db      Instancia do banco (para max ingested_at); null em modo degradado
 */
export function wrap<T>(
  data: T | null,
  opts: WrapOptions,
  dbPath: string,
  db: Database.Database | null
): ApiEnvelope<T> {
  let freshness: Freshness;
  if (db !== null) {
    freshness = computeFreshness(dbPath, db);
  } else {
    freshness = { mtime: '', maxIngestedAt: '' };
  }

  const meta: Meta = {
    degraded: opts.degraded ?? false,
    reason: opts.reason ?? null,
    freshness,
    schemaVersion: readSchemaVersion(db),
    ...(opts.approximate ? { approximate: true } : {}),
  };

  return {
    data: opts.degraded ? null : data,
    meta,
  };
}

/**
 * Wrapper conveniente para respostas degradadas.
 */
export function wrapDegraded(
  reason: string,
  dbPath: string
): ApiEnvelope<null> {
  return wrap(null, { degraded: true, reason }, dbPath, null);
}

// ---------------------------------------------------------------------------
// wrapBridge() — envelope da Ponte (`routes/bridge.ts`), FASE 3, task 3.2.1.
//
// Deliberadamente DISTINTO de wrap(): `bridge.db` nao e o corpus (nao tem
// tabela `schema_meta`, nao e lido por `cstk recall`) e chamar wrap() aqui
// obrigaria a abrir `knowledge.db` so para preencher `freshness` — acoplando
// os dois stores e violando FR-017 (contracts/panel-bridge-api.md §3).
// wrapBridge() preserva a FORMA do envelope padrao e troca a FONTE de
// `freshness` (mtime de `bridge.db` + max(created_at, resolved_at) das
// intervencoes) e fixa `schemaVersion` num literal proprio da Ponte — nunca
// le `schema_meta` (tabela que nao existe em `bridge.db`).
// ---------------------------------------------------------------------------

/**
 * Versao de schema da Ponte — literal fixo (nao ha `schema_meta` em
 * `bridge.db`). Citado literalmente no exemplo de resposta do contrato
 * (panel-bridge-api.md §4, `"schemaVersion": "1"`).
 */
export const BRIDGE_SCHEMA_VERSION = '1';

/**
 * Computa Freshness para o envelope da Ponte.
 * Ref: panel-bridge-api.md §3 ("mtime do bridge.db + max(updated_at) das
 * intervencoes"); task 3.2.2 — nota de inconsistencia resolvida: nao existe
 * coluna `updated_at` no DDL real (data-model.md); usamos
 * `MAX(created_at, resolved_at)` POR LINHA (as duas colunas que de fato
 * existem), agregado com `MAX(...)` entre linhas.
 * Nunca lanca — falha de leitura (arquivo sumiu, tabela ausente em race)
 * degrada para strings vazias, igual a `computeFreshness` do corpus.
 */
export function computeBridgeFreshness(
  bridgeDbPath: string,
  bridgeDb: Database.Database | null
): Freshness {
  let mtime = '';
  if (bridgeDb !== null) {
    try {
      mtime = statSync(bridgeDbPath).mtime.toISOString();
    } catch {
      // arquivo sumiu em race condition — caller ja lida com degradacao
    }
  }

  let maxUpdatedAt = '';
  if (bridgeDb !== null) {
    try {
      const row = bridgeDb
        .prepare(
          "SELECT MAX(COALESCE(resolved_at, created_at), created_at) as mx FROM interventions"
        )
        .get() as { mx: string | null } | undefined;
      maxUpdatedAt = row?.mx ?? '';
    } catch {
      // tabela pode estar ausente/corrompida em race condition
    }
  }

  return { mtime, maxIngestedAt: maxUpdatedAt };
}

/**
 * Envolve dados da Ponte no envelope padrao — mesma assinatura conceitual de
 * `wrap()`, fonte de freshness/schemaVersion proprias da Ponte.
 */
export function wrapBridge<T>(
  data: T | null,
  opts: WrapOptions,
  bridgeDbPath: string,
  bridgeDb: Database.Database | null
): ApiEnvelope<T> {
  const freshness = computeBridgeFreshness(bridgeDbPath, bridgeDb);

  const meta: Meta = {
    degraded: opts.degraded ?? false,
    reason: opts.reason ?? null,
    freshness,
    schemaVersion: BRIDGE_SCHEMA_VERSION,
    ...(opts.approximate ? { approximate: true } : {}),
  };

  return {
    data: opts.degraded ? null : data,
    meta,
  };
}

/** Wrapper conveniente para respostas degradadas da Ponte (§3.1: 200, nunca 5xx). */
export function wrapBridgeDegraded(
  reason: string,
  bridgeDbPath: string
): ApiEnvelope<null> {
  return wrapBridge(null, { degraded: true, reason }, bridgeDbPath, null);
}

/** Envelope de erro de VALIDACAO (4xx) da Ponte — nao e degradacao de dado. */
export function bridgeErrorEnvelope(message: string): ApiEnvelope<null> & { error: string } {
  return {
    data: null,
    meta: {
      degraded: false,
      reason: null,
      freshness: { mtime: '', maxIngestedAt: '' },
      schemaVersion: BRIDGE_SCHEMA_VERSION,
    },
    error: message,
  };
}
