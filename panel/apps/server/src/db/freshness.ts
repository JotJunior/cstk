/**
 * Informacoes de frescor do snapshot knowledge.db.
 * Ref: spec.md FR-014; Principio VI (Snapshot que Muda)
 * Task 3.2.6
 *
 * mtime: ultima modificacao do arquivo via fs.statSync (proxy de quando
 *        o cstk recall --ingest rodou pela ultima vez).
 * maxIngestedAt: max(ingested_at) FROM executions (registro mais recente
 *        na base — pode estar atras do mtime se a ingestao adicionou
 *        apenas metadados sem nova execucao).
 */
import { statSync } from 'node:fs';
import type Database from 'better-sqlite3';
import type { Freshness } from '@cstk-panel/shared-types';

/**
 * Computa Freshness para o envelope de resposta.
 * Nunca lanca — em caso de falha retorna strings vazias (degradado pelo chamador).
 */
export function computeFreshness(
  dbPath: string,
  db: Database.Database
): Freshness {
  // mtime do arquivo
  let mtime = '';
  try {
    const stat = statSync(dbPath);
    mtime = stat.mtime.toISOString();
  } catch {
    // arquivo sumiu em race condition — caller ja lida com degradacao
  }

  // max(ingested_at) das execucoes
  let maxIngestedAt = '';
  try {
    const row = db
      .prepare('SELECT max(ingested_at) as mx FROM executions')
      .get() as { mx: string | null };
    maxIngestedAt = row?.mx ?? '';
  } catch {
    // tabela pode ter sido dropada em race condition
  }

  return { mtime, maxIngestedAt };
}
