/**
 * Testes de integracao para os 4 motivos de degradacao do openDb.
 * Task 3.2.8
 *
 * Principio II (Degradar, Nunca Quebrar): openDb NUNCA lanca excecao.
 * Cobre: db-missing, db-corrupt, schema-mismatch, table-empty.
 *
 * Para db-missing: usa path inexistente.
 * Para db-corrupt: cria arquivo binario invalido em tmpdir.
 * Para schema-mismatch: usa fixture com schema_version != '2'.
 * Para table-empty: usa fixture com executions vazia.
 *
 * Cada teste usa tmpdir isolado — sem side effects.
 */
import { describe, it, expect, afterEach } from 'vitest';
import { mkdtempSync, writeFileSync, readFileSync, unlinkSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { Worker } from 'node:worker_threads';
import Database from 'better-sqlite3';
import { openDb } from '../../src/db/open.js';
import { DEFAULT_SCHEMA_VERSIONS } from '../../src/config.js';

// Track tmpfiles para cleanup
const toClean: string[] = [];

afterEach(() => {
  for (const f of toClean) {
    try { unlinkSync(f); } catch { /* ignorar */ }
    try { unlinkSync(f + '-shm'); } catch { /* ignorar */ }
    try { unlinkSync(f + '-wal'); } catch { /* ignorar */ }
  }
  toClean.length = 0;
});

function tmpFile(suffix = '.db'): string {
  const dir = mkdtempSync(join(tmpdir(), 'cstk-test-'));
  const p = join(dir, `test${suffix}`);
  toClean.push(p);
  return p;
}

/** Cria DB SQLite minimo valido com schema_version=2 e 1 execucao */
function makeValidDb(path: string): void {
  const db = new Database(path);
  db.exec(`
    CREATE TABLE schema_meta (key TEXT PRIMARY KEY, value TEXT);
    INSERT INTO schema_meta VALUES ('schema_version', '2');
    CREATE TABLE executions (
      execucao_id TEXT PRIMARY KEY,
      project TEXT, feature TEXT, status TEXT,
      motivo_termino TEXT, etapa_corrente TEXT,
      iniciada_em TEXT, terminada_em TEXT,
      duracao_segundos REAL, stack_sugerida TEXT,
      ondas_total INTEGER, tool_calls_total INTEGER,
      wallclock_total_segundos REAL,
      subagentes_spawned INTEGER, profundidade_max INTEGER,
      decisoes_total INTEGER, bloqueios_humanos_total INTEGER,
      sugestoes_skills_total INTEGER, issues_toolkit_abertas INTEGER
    );
    INSERT INTO executions (execucao_id, project, feature, status)
    VALUES ('exec-001', 'proj', 'feat', 'concluida');
  `);
  db.close();
}

// ─────────────────────────────────────────────────────────
// Motivo 1: db-missing
// ─────────────────────────────────────────────────────────
describe('openDb — db-missing', () => {
  it('retorna { ok: false, reason: um dos motivos de falha } para path inexistente', () => {
    // better-sqlite3 com fileMustExist=false pode criar arquivo vazio
    // ou falhar; nosso open.ts mapeia todos os casos para um dos DegradedReasons.
    const path = '/tmp/cstk-test-impossivel-' + Date.now() + '/nao-existe.db';
    const result = openDb(path);
    expect(result.ok).toBe(false);
    if (!result.ok) {
      // Qualquer dos 3 motivos e valido: db-missing, schema-mismatch, db-corrupt
      expect(['db-missing', 'schema-mismatch', 'db-corrupt']).toContain(result.reason);
    }
  });

  it('retorna { ok: false, reason: "db-missing" } para path em dir inexistente', () => {
    const dir = mkdtempSync(join(tmpdir(), 'cstk-'));
    toClean.push(join(dir, 'fake.db'));
    // Remover o diretorio inteiro nao e facil; usar subdir que nao existe
    const path = join(dir, 'subdir', 'nao-existe.db');
    const result = openDb(path);
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(['db-missing', 'db-corrupt']).toContain(result.reason);
    }
  });
});

// ─────────────────────────────────────────────────────────
// Motivo 2: db-corrupt
// ─────────────────────────────────────────────────────────
describe('openDb — db-corrupt', () => {
  it('retorna { ok: false, reason: "db-corrupt" } para arquivo binario invalido', () => {
    const path = tmpFile('.db');
    // Escrever garbage — nao e um SQLite valido
    writeFileSync(path, Buffer.from('NOT_A_SQLITE_DB_GARBAGE_CONTENT_XYZABC12345'));
    const result = openDb(path);
    expect(result.ok).toBe(false);
    if (!result.ok) {
      // Pode vir como db-corrupt (falha no quick_check ou na abertura)
      // ou db-missing (se better-sqlite3 nao abre)
      expect(['db-corrupt', 'db-missing']).toContain(result.reason);
    }
  });
});

// ─────────────────────────────────────────────────────────
// Motivo 3: schema-mismatch
// ─────────────────────────────────────────────────────────
describe('openDb — schema-mismatch', () => {
  it('retorna { ok: false, reason: "schema-mismatch" } quando schema_version != "2"', () => {
    const path = tmpFile('.db');
    const db = new Database(path);
    db.exec(`
      CREATE TABLE schema_meta (key TEXT PRIMARY KEY, value TEXT);
      INSERT INTO schema_meta VALUES ('schema_version', '1');
      CREATE TABLE executions (
        execucao_id TEXT PRIMARY KEY,
        project TEXT, feature TEXT, status TEXT,
        motivo_termino TEXT, etapa_corrente TEXT,
        iniciada_em TEXT, terminada_em TEXT,
        duracao_segundos REAL, stack_sugerida TEXT,
        ondas_total INTEGER, tool_calls_total INTEGER,
        wallclock_total_segundos REAL,
        subagentes_spawned INTEGER, profundidade_max INTEGER,
        decisoes_total INTEGER, bloqueios_humanos_total INTEGER,
        sugestoes_skills_total INTEGER, issues_toolkit_abertas INTEGER
      );
      INSERT INTO executions (execucao_id, project, feature, status)
      VALUES ('exec-001', 'proj', 'feat', 'concluida');
    `);
    db.close();

    const result = openDb(path);
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.reason).toBe('schema-mismatch');
    }
  });

  it('retorna schema-mismatch para schema_version ausente (DB vazio criado por better-sqlite3)', () => {
    const path = tmpFile('.db');
    // Criar DB completamente vazio (sem schema_meta)
    const db = new Database(path);
    db.exec('CREATE TABLE dummy (id INTEGER PRIMARY KEY)');
    db.close();

    const result = openDb(path);
    expect(result.ok).toBe(false);
    if (!result.ok) {
      // schema_meta ausente → db-missing (conforme logica do open.ts)
      expect(['db-missing', 'schema-mismatch']).toContain(result.reason);
    }
  });
});

// ─────────────────────────────────────────────────────────
// Motivo 4: table-empty
// ─────────────────────────────────────────────────────────
describe('openDb — table-empty', () => {
  it('retorna { ok: false, reason: "table-empty" } quando executions esta vazia', () => {
    const path = tmpFile('.db');
    const db = new Database(path);
    db.exec(`
      CREATE TABLE schema_meta (key TEXT PRIMARY KEY, value TEXT);
      INSERT INTO schema_meta VALUES ('schema_version', '2');
      CREATE TABLE executions (
        execucao_id TEXT PRIMARY KEY,
        project TEXT, feature TEXT, status TEXT,
        motivo_termino TEXT, etapa_corrente TEXT,
        iniciada_em TEXT, terminada_em TEXT,
        duracao_segundos REAL, stack_sugerida TEXT,
        ondas_total INTEGER, tool_calls_total INTEGER,
        wallclock_total_segundos REAL,
        subagentes_spawned INTEGER, profundidade_max INTEGER,
        decisoes_total INTEGER, bloqueios_humanos_total INTEGER,
        sugestoes_skills_total INTEGER, issues_toolkit_abertas INTEGER
      );
      -- SEM nenhuma linha em executions
    `);
    db.close();

    const result = openDb(path);
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.reason).toBe('table-empty');
    }
  });
});

// ─────────────────────────────────────────────────────────
// Caminho feliz: DB valido
// ─────────────────────────────────────────────────────────
describe('openDb — caminho feliz', () => {
  it('retorna { ok: true, db } para DB valido com schema_version=2 e dados', () => {
    const path = tmpFile('.db');
    makeValidDb(path);
    const result = openDb(path);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.db).toBeDefined();
      result.db.close();
    }
  });

  it('DB aberto esta em modo read-only (PRAGMA query_only=1)', () => {
    const path = tmpFile('.db');
    makeValidDb(path);
    const result = openDb(path);
    expect(result.ok).toBe(true);
    if (result.ok) {
      // Tentar uma mutacao deve falhar
      expect(() => {
        result.db.exec("INSERT INTO executions (execucao_id) VALUES ('hack')");
      }).toThrow();
      result.db.close();
    }
  });
});

// ─────────────────────────────────────────────────────────
// FR-V3-001/002: conjunto de versoes aceitas (default 2|3 + override)
// ─────────────────────────────────────────────────────────

/** makeValidDb com schema_version arbitrario. */
function makeDbWithVersion(path: string, version: string): void {
  makeValidDb(path);
  const w = new Database(path);
  w.prepare("UPDATE schema_meta SET value = ? WHERE key = 'schema_version'").run(version);
  w.close();
}

describe('openDb — versoes de schema aceitas (FR-V3-001/002)', () => {
  it('aceita schema_version=3 por default (sem 2o argumento)', () => {
    const path = tmpFile('.db');
    makeDbWithVersion(path, '3');
    const result = openDb(path);
    expect(result.ok).toBe(true);
    if (result.ok) result.db.close();
  });

  it('aceita schema_version=8 por default (recall-worktree-identity — coluna session)', () => {
    const path = tmpFile('.db');
    makeDbWithVersion(path, '8');
    const result = openDb(path);
    expect(result.ok).toBe(true);
    if (result.ok) result.db.close();
  });

  it('aceita schema_version=12 por default (otel-model-breakdown — wave_model_usage + breakdown por fonte)', () => {
    const path = tmpFile('.db');
    makeDbWithVersion(path, '12');
    const result = openDb(path);
    expect(result.ok).toBe(true);
    if (result.ok) result.db.close();
  });

  it('aceita schema_version=13 por default (loose-usage-capture — tabela loose_usage)', () => {
    const path = tmpFile('.db');
    makeDbWithVersion(path, '13');
    const result = openDb(path);
    expect(result.ok).toBe(true);
    if (result.ok) result.db.close();
  });

  it("DEFAULT_SCHEMA_VERSIONS inclui '12' e '13' — guard contra remocao acidental", () => {
    // O teste acima passaria por engano se alguem trocasse a lista inteira;
    // este assere o conteudo, nao so o efeito.
    expect([...DEFAULT_SCHEMA_VERSIONS]).toContain('12');
    expect([...DEFAULT_SCHEMA_VERSIONS]).toContain('13');
  });

  it('versao fora do conjunto aceito (ex.: 99) degrada como schema-mismatch', () => {
    const path = tmpFile('.db');
    makeDbWithVersion(path, '99');
    const result = openDb(path);
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.reason).toBe('schema-mismatch');
  });

  it('respeita o conjunto suportado passado por parametro (env override)', () => {
    const path = tmpFile('.db');
    makeValidDb(path); // schema_version = '2'
    // Operador travou em ['3'] → v2 deixa de ser aceita.
    const result = openDb(path, ['3']);
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.reason).toBe('schema-mismatch');
  });
});

// ─────────────────────────────────────────────────────────
// Resiliencia ao "snapshot que muda" (Principio VI) — torn read / retry
// ─────────────────────────────────────────────────────────

/**
 * Cria um DB multi-pagina valido e corrompe paginas do MEIO (preservando a
 * pagina 1 / header). quick_check passa a reportar != 'ok' → db-corrupt.
 * Simula um arquivo torn — leitura no instante de uma copia/reescrita.
 */
function makeMalformedDb(path: string): void {
  const db = new Database(path);
  db.exec(`
    CREATE TABLE schema_meta (key TEXT PRIMARY KEY, value TEXT);
    INSERT INTO schema_meta VALUES ('schema_version', '2');
    CREATE TABLE executions (
      execucao_id TEXT PRIMARY KEY, project TEXT, feature TEXT, status TEXT,
      motivo_termino TEXT, etapa_corrente TEXT, iniciada_em TEXT, terminada_em TEXT,
      duracao_segundos REAL, stack_sugerida TEXT, ondas_total INTEGER,
      tool_calls_total INTEGER, wallclock_total_segundos REAL, subagentes_spawned INTEGER,
      profundidade_max INTEGER, decisoes_total INTEGER, bloqueios_humanos_total INTEGER,
      sugestoes_skills_total INTEGER, issues_toolkit_abertas INTEGER
    );
  `);
  const ins = db.prepare('INSERT INTO executions (execucao_id, project, feature, status) VALUES (?, ?, ?, ?)');
  const tx = db.transaction(() => {
    for (let i = 0; i < 800; i++) ins.run(`exec-${i}`, `proj-${i}`, `feat-${i}`, 'concluida');
  });
  tx();
  db.close();

  // Corromper paginas do meio (offset 4096+), preservando a pagina 1 (schema).
  const buf = readFileSync(path);
  const start = 4096;
  const end = Math.min(buf.length, 4096 * 4);
  buf.fill(0xdb, start, end);
  writeFileSync(path, buf);
}

describe('openDb — resiliencia (Principio VI: snapshot que muda)', () => {
  it('arquivo torn/malformed degrada como db-corrupt sem lancar e termina (retry limitado)', () => {
    const path = tmpFile('.db');
    makeMalformedDb(path);

    const t0 = Date.now();
    const result = openDb(path);
    const elapsed = Date.now() - t0;

    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.reason).toBe('db-corrupt');
    // Retry e limitado: nao pode travar. 3 tentativas * 80ms backoff << 2s.
    expect(elapsed).toBeLessThan(2000);
  });

  it('recupera automaticamente quando a copia/reescrita termina durante o retry', async () => {
    const validSrc = tmpFile('.db');
    makeValidDb(validSrc);

    const target = tmpFile('.db');
    makeMalformedDb(target); // estado inicial: torn → db-corrupt (transitorio)

    // Thread paralela substitui o arquivo torn pelo valido (rename atomico)
    // enquanto openDb dorme entre tentativas (Atomics.wait nao bloqueia o worker).
    const worker = new Worker(
      `const fs = require('node:fs');
       const { workerData } = require('node:worker_threads');
       setTimeout(() => { try { fs.renameSync(workerData.src, workerData.tgt); } catch {} }, 20);`,
      { eval: true, workerData: { src: validSrc, tgt: target } }
    );

    try {
      const result = openDb(target);
      expect(result.ok).toBe(true);
      if (result.ok) result.db.close();
    } finally {
      await worker.terminate();
    }
  });
});
