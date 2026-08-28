/**
 * Helper de introspeccao de schema — tolerancia a colunas aditivas (v2→v3).
 * Ref: spec.md FR-V3-005; plan.md §Tolerancia a coluna ausente
 *
 * Uma base v2 nao tem `tasks.titulo`; um SELECT com a coluna lancaria. Em vez
 * de gateaer/quebrar (Principio II), checamos a existencia via PRAGMA e
 * projetamos `'' AS titulo` quando ausente — mantendo uma unica forma de Row.
 *
 * Cache por instancia de DB (WeakMap): PRAGMA table_info e barato, mas a
 * abertura e por-requisicao; o cache evita repetir dentro da mesma conexao.
 */
import type Database from 'better-sqlite3';

const cache = new WeakMap<Database.Database, Map<string, boolean>>();
const tableCache = new WeakMap<Database.Database, Map<string, boolean>>();

/** True se a tabela possui a coluna. Read-only; nunca lanca para tabela ausente. */
export function hasColumn(
  db: Database.Database,
  table: string,
  column: string,
): boolean {
  const key = `${table}.${column}`;
  let perDb = cache.get(db);
  if (perDb === undefined) {
    perDb = new Map<string, boolean>();
    cache.set(db, perDb);
  }
  const cached = perDb.get(key);
  if (cached !== undefined) return cached;

  let exists = false;
  try {
    // PRAGMA table_info NAO aceita binding para o nome da tabela; o nome vem de
    // literais internos (nunca de input do usuario), entao a interpolacao e segura.
    const rows = db.pragma(`table_info(${table})`) as Array<{ name: string }>;
    exists = rows.some(r => r.name === column);
  } catch {
    exists = false;
  }
  perDb.set(key, exists);
  return exists;
}

/**
 * True se a base possui a tabela. Read-only; nunca lanca.
 *
 * Uma base v2/v3 nao tem `memories` (introduzida em v4 — recall-memory-mirror);
 * consultar a tabela diretamente lancaria. As queries de memoria checam isto
 * antes e degradam para lista vazia (Principio II), em vez de quebrar.
 */
export function hasTable(db: Database.Database, table: string): boolean {
  let perDb = tableCache.get(db);
  if (perDb === undefined) {
    perDb = new Map<string, boolean>();
    tableCache.set(db, perDb);
  }
  const cached = perDb.get(table);
  if (cached !== undefined) return cached;

  let exists = false;
  try {
    const row = db
      .prepare(
        "SELECT 1 FROM sqlite_master WHERE type IN ('table','view') AND name = ?",
      )
      .get(table);
    exists = row !== undefined;
  } catch {
    exists = false;
  }
  perDb.set(table, exists);
  return exists;
}
