/**
 * Camada de abertura do banco — degradacao de 1a classe.
 * NUNCA lanca excecao: retorna { ok: true, db } ou { ok: false, reason }.
 *
 * Principio II (Degradar, Nunca Quebrar): o servidor DEVE operar em modo
 * degradado quando o DB esta ausente, corrompido ou com schema incompativel.
 * Principio I (Read-Only Absoluto): abre com { readonly: true } + PRAGMA
 * query_only = 1 — impossivel executar mutacao mesmo por descuido.
 * Principio VI (Snapshot que Muda): a knowledge.db pode ser reescrita/copiada
 * "por tras" pela ingestao de fim-de-onda ou por uma copia de outra maquina.
 * Uma leitura no instante em que o arquivo esta torn (parcialmente escrito)
 * lanca SQLITE_CORRUPT/BUSY/IOERR *transitorio* — NAO e corrupcao permanente.
 * Por isso a abertura faz retry curto com backoff antes de degradar (FR-005).
 *
 * Nota sobre `immutable=1` (constituicao Principio I, DSN
 * `?mode=ro&immutable=1&_busy_timeout=5000`): better-sqlite3 chama
 * `sqlite3_open_v2` SEM `SQLITE_OPEN_URI` e seu wrapper rejeita paths-URI, logo
 * `immutable=1` nao e alcancavel por esta lib. O `_busy_timeout=5000` e honrado
 * via opcao `timeout`. A robustez que `immutable=1` daria (ignorar -wal/-shm e
 * pular locking durante reescrita) e compensada pelo retry transitorio abaixo.
 *
 * Ref: research.md §Decision 1, §Decision 8; spec.md FR-002, FR-005, FR-007
 * Tasks: 3.2.1 – 3.2.5
 */
import Database from 'better-sqlite3';
import type { DegradedReason } from '@cstk-panel/shared-types';
import { DEFAULT_SCHEMA_VERSIONS } from '../config.js';

// Re-exportar DegradedReason para conveniencia dos consumers deste modulo
export type { DegradedReason };

export type OpenResult =
  | { ok: true; db: Database.Database }
  | { ok: false; reason: DegradedReason };

/** _busy_timeout=5000 (constituicao Principio I) — ja e o default da lib, explicitado. */
const BUSY_TIMEOUT_MS = 5000;
/**
 * Versoes de schema aceitas por default (FR-V3-001). A fonte de verdade em
 * runtime e o env CSTK_SCHEMA_VERSIONS (resolvido em config.ts e passado pelas
 * rotas); este default cobre chamadas diretas/de teste com 1 argumento.
 * Reusa DEFAULT_SCHEMA_VERSIONS do config para nao haver drift entre os dois
 * defaults (o bug em que este parava em v4 enquanto o config seguia ate v8).
 */
const DEFAULT_SUPPORTED_VERSIONS: readonly string[] = DEFAULT_SCHEMA_VERSIONS;
/** Tentativas de abertura+verificacao antes de degradar (resiliencia ao torn read). */
const MAX_ATTEMPTS = 3;
/** Backoff fixo entre tentativas, em ms (apenas no caminho degradado/transitorio). */
const RETRY_BACKOFF_MS = 80;

/** Resultado de UMA tentativa: carrega `transient` para decidir retry. */
type OnceResult =
  | { ok: true; db: Database.Database }
  | { ok: false; reason: DegradedReason; transient: boolean };

/**
 * Sleep SINCRONO — openDb e chamado de forma sincrona pelas rotas e
 * better-sqlite3 e sincrono. Atomics.wait bloqueia a thread sem busy-loop.
 * Apenas exercitado no caminho degradado (DB valido retorna na 1a tentativa).
 */
function sleepSync(ms: number): void {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
}

/**
 * Erros que indicam estado TRANSITORIO (arquivo sendo copiado/reescrito, lock
 * de ingestao, recuperacao de WAL) — justificam retry, NAO corrupcao definitiva.
 * `SQLITE_NOTADB` ("file is not a database") fica de fora de proposito: arquivo
 * que nao e SQLite nao se torna valido por espera.
 */
function isTransient(msg: string): boolean {
  return (
    msg.includes('SQLITE_BUSY') ||
    msg.includes('SQLITE_LOCKED') ||
    msg.includes('SQLITE_PROTOCOL') ||
    msg.includes('SQLITE_IOERR') ||
    msg.includes('SQLITE_CORRUPT') ||
    msg.includes('malformed') || // "database disk image is malformed" — torn read
    msg.includes('SQLITE_READONLY_RECOVERY') ||
    msg.includes('SQLITE_READONLY_DIRECTORY')
  );
}

/**
 * Uma tentativa de abrir+verificar knowledge.db em modo read-only estrito.
 *
 * Sequencia de verificacao:
 * 1. Abrir arquivo (ENOENT → db-missing)
 * 2. PRAGMA query_only = 1 (imutabilidade runtime)
 * 3. PRAGMA quick_check (corrupcao → db-corrupt)
 * 4. SELECT schema_version FROM schema_meta (divergencia → schema-mismatch)
 * 5. COUNT(*) FROM executions (vazio → table-empty)
 */
function tryOpenOnce(dbPath: string, supported: readonly string[]): OnceResult {
  // Passo 1: tentar abrir o arquivo
  let db: Database.Database;
  try {
    // fileMustExist: false — tratamos ENOENT manualmente via erro de abertura.
    // timeout: honra _busy_timeout=5000 da constituicao (Principio I).
    db = new Database(dbPath, {
      readonly: true,
      fileMustExist: false,
      timeout: BUSY_TIMEOUT_MS,
    });
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    // SQLITE_CANTOPEN ou ENOENT — estado permanente, sem retry.
    if (
      msg.includes('ENOENT') ||
      msg.includes('SQLITE_CANTOPEN') ||
      msg.includes('unable to open')
    ) {
      return { ok: false, reason: 'db-missing', transient: false };
    }
    // Outro erro de abertura: pode ser torn read / lock — db-corrupt, retry se transitorio.
    return { ok: false, reason: 'db-corrupt', transient: isTransient(msg) };
  }

  try {
    // Passo 2: PRAGMA query_only = 1 (FR-002)
    db.pragma('query_only = 1');

    // Passo 3: PRAGMA quick_check — integridade basica (FR-007)
    const qcRows = db.pragma('quick_check') as Array<{ quick_check: string }>;
    const qcResult = qcRows[0]?.quick_check ?? 'error';
    if (qcResult !== 'ok') {
      db.close();
      // quick_check != ok num arquivo torn e transitorio (recupera quando a copia
      // termina); num arquivo realmente corrompido persiste e degrada como db-corrupt.
      return { ok: false, reason: 'db-corrupt', transient: true };
    }

    // Passo 4: validar schema_version contra o conjunto aceito (FR-V3-001/002)
    let schemaVersion: string | undefined;
    try {
      const row = db
        .prepare("SELECT value FROM schema_meta WHERE key = 'schema_version'")
        .get() as { value: string } | undefined;
      schemaVersion = row?.value;
    } catch {
      // Tabela schema_meta inexistente (DB vazio criado agora)
      db.close();
      return { ok: false, reason: 'db-missing', transient: false };
    }

    if (schemaVersion === undefined || !supported.includes(schemaVersion)) {
      db.close();
      return { ok: false, reason: 'schema-mismatch', transient: false };
    }

    // Passo 5: verificar se executions tem pelo menos 1 linha (task 3.2.5)
    const countRow = db
      .prepare('SELECT count(*) as n FROM executions')
      .get() as { n: number };
    if (countRow.n === 0) {
      db.close();
      return { ok: false, reason: 'table-empty', transient: false };
    }

    return { ok: true, db };
  } catch (err: unknown) {
    try { db.close(); } catch { /* ignorar erro de fechamento */ }
    const msg = err instanceof Error ? err.message : String(err);
    if (msg.includes('SQLITE_CORRUPT') || msg.includes('malformed')) {
      // Torn read durante copia/reescrita — retry; se persistir, degrada como db-corrupt.
      return { ok: false, reason: 'db-corrupt', transient: true };
    }
    if (isTransient(msg)) {
      return { ok: false, reason: 'db-corrupt', transient: true };
    }
    // Erro nao-classificado (ex: SQLITE_NOTADB) — degrada como indisponivel, sem retry.
    return { ok: false, reason: 'db-missing', transient: false };
  }
}

/**
 * Abre knowledge.db em modo read-only estrito, com retry resiliente ao
 * "snapshot que muda" (Principio VI). Retorna { ok: false, reason } para
 * qualquer falha — nunca lanca.
 *
 * Estados permanentes (db-missing, schema-mismatch, table-empty) retornam de
 * imediato. Estados transitorios (torn read / lock / WAL recovery) sao
 * retentados ate MAX_ATTEMPTS com backoff curto antes de degradar.
 */
export function openDb(
  dbPath: string,
  supported: readonly string[] = DEFAULT_SUPPORTED_VERSIONS,
): OpenResult {
  let last: { reason: DegradedReason } = { reason: 'db-corrupt' };
  for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
    const result = tryOpenOnce(dbPath, supported);
    if (result.ok) return result;
    last = { reason: result.reason };
    // Sem retry para estado permanente ou na ultima tentativa.
    if (!result.transient || attempt === MAX_ATTEMPTS) {
      return { ok: false, reason: result.reason };
    }
    sleepSync(RETRY_BACKOFF_MS);
  }
  return { ok: false, reason: last.reason };
}
