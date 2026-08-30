/**
 * Testes de `db/bridge.ts` — conexao rw dedicada ao store `bridge.db`.
 * Task 1.2.5
 *
 * Cobre: (a) conexao separada de `open.ts` (nenhuma query de bridge passa
 * pelo handle do corpus — o corpus continua readonly/query_only, a conexao
 * de bridge escreve livremente no PROPRIO arquivo); (b) DDL aplicado (CHECK
 * constraints rejeitam `kind`/`resolution` fora do enum fechado, indices
 * criados); (c) permissao de arquivo aplicada (dir 700 / arquivo 600,
 * best-effort).
 *
 * Cada teste usa tmpdir isolado — sem side effects entre casos.
 */
import { describe, it, expect, afterEach, vi } from 'vitest';
import { mkdtempSync, statSync, unlinkSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import Database from 'better-sqlite3';
import { openBridgeDb, resolveBridgeDbPath } from '../../src/db/bridge.js';
import { openDb } from '../../src/db/open.js';

const toClean: string[] = [];

afterEach(() => {
  for (const f of toClean) {
    try { unlinkSync(f); } catch { /* ignorar */ }
    try { unlinkSync(f + '-shm'); } catch { /* ignorar */ }
    try { unlinkSync(f + '-wal'); } catch { /* ignorar */ }
  }
  toClean.length = 0;
});

function tmpBridgeDbPath(): string {
  const dir = mkdtempSync(join(tmpdir(), 'cstk-bridge-test-'));
  const p = join(dir, 'bridge.db');
  toClean.push(p);
  return p;
}

/** Cria um corpus (knowledge.db) minimo valido, no mesmo formato usado por
 *  open.test.ts, para o cenario de conexao separada. */
function makeValidCorpus(path: string): void {
  const db = new Database(path);
  db.exec(`
    CREATE TABLE schema_meta (key TEXT PRIMARY KEY, value TEXT);
    INSERT INTO schema_meta VALUES ('schema_version', '2');
    CREATE TABLE executions (execucao_id TEXT PRIMARY KEY, project TEXT);
    INSERT INTO executions (execucao_id, project) VALUES ('exec-001', 'proj');
  `);
  db.close();
}

describe('resolveBridgeDbPath', () => {
  it('usa CSTK_BRIDGE_DB quando definida', () => {
    const prev = process.env['CSTK_BRIDGE_DB'];
    process.env['CSTK_BRIDGE_DB'] = '/tmp/custom-bridge.db';
    try {
      expect(resolveBridgeDbPath()).toBe('/tmp/custom-bridge.db');
    } finally {
      if (prev === undefined) delete process.env['CSTK_BRIDGE_DB'];
      else process.env['CSTK_BRIDGE_DB'] = prev;
    }
  });

  it('usa default ~/.claude/cstk/bridge.db quando ausente', () => {
    const prev = process.env['CSTK_BRIDGE_DB'];
    delete process.env['CSTK_BRIDGE_DB'];
    try {
      expect(resolveBridgeDbPath()).toMatch(/\.claude\/cstk\/bridge\.db$/);
    } finally {
      if (prev !== undefined) process.env['CSTK_BRIDGE_DB'] = prev;
    }
  });
});

describe('openBridgeDb — DDL', () => {
  it('cria a tabela interventions com as 14 colunas esperadas', () => {
    const path = tmpBridgeDbPath();
    const db = openBridgeDb(path);
    try {
      const cols = db.prepare('PRAGMA table_info(interventions)').all() as Array<{ name: string }>;
      const names = cols.map(c => c.name).sort();
      expect(names).toEqual(
        [
          'applied_value', 'created_at', 'default_value', 'execution_kind',
          'expires_at', 'kind', 'options_json', 'project', 'project_path',
          'question', 'question_id', 'resolution', 'resolved_at', 'short_name',
          'untrusted_text',
        ].sort(),
      );
    } finally {
      db.close();
    }
  });

  it('e idempotente — reabrir o mesmo arquivo nao falha nem duplica schema', () => {
    const path = tmpBridgeDbPath();
    const db1 = openBridgeDb(path);
    db1.close();
    const db2 = openBridgeDb(path);
    try {
      const tables = db2
        .prepare("SELECT count(*) as n FROM sqlite_master WHERE type='table' AND name='interventions'")
        .get() as { n: number };
      expect(tables.n).toBe(1);
    } finally {
      db2.close();
    }
  });

  it('cria os dois indices propostos', () => {
    const path = tmpBridgeDbPath();
    const db = openBridgeDb(path);
    try {
      const idx = db
        .prepare("SELECT name FROM sqlite_master WHERE type='index' AND name LIKE 'idx_interventions_%'")
        .all() as Array<{ name: string }>;
      const names = idx.map(r => r.name).sort();
      expect(names).toEqual(['idx_interventions_created', 'idx_interventions_open']);
    } finally {
      db.close();
    }
  });

  it('CHECK constraint rejeita kind fora do enum fechado', () => {
    const path = tmpBridgeDbPath();
    const db = openBridgeDb(path);
    try {
      const insert = () =>
        db
          .prepare(
            `INSERT INTO interventions
              (question_id, project_path, project, execution_kind, kind, question, default_value, expires_at, created_at)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
          )
          .run('q1', '/tmp/proj', 'proj', 'agente-00c', 'invalid-kind', 'texto?', 'default', '2026-01-01', '2026-01-01');
      expect(insert).toThrow(/CHECK constraint failed/);
    } finally {
      db.close();
    }
  });

  it('CHECK constraint rejeita resolution fora do enum fechado', () => {
    const path = tmpBridgeDbPath();
    const db = openBridgeDb(path);
    try {
      const insert = () =>
        db
          .prepare(
            `INSERT INTO interventions
              (question_id, project_path, project, execution_kind, kind, question, default_value, resolution, expires_at, created_at)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
          )
          .run('q2', '/tmp/proj', 'proj', 'agente-00c', 'confirm', 'texto?', 'default', 'invalid-resolution', '2026-01-01', '2026-01-01');
      expect(insert).toThrow(/CHECK constraint failed/);
    } finally {
      db.close();
    }
  });

  it('aceita valores validos do enum e persiste a linha', () => {
    const path = tmpBridgeDbPath();
    const db = openBridgeDb(path);
    try {
      db.prepare(
        `INSERT INTO interventions
          (question_id, project_path, project, execution_kind, kind, question, default_value, expires_at, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      ).run('q3', '/tmp/proj', 'proj', 'feature-00c', 'choice', 'texto?', 'default', '2026-01-01', '2026-01-01');
      const row = db.prepare('SELECT * FROM interventions WHERE question_id = ?').get('q3');
      expect(row).toBeDefined();
    } finally {
      db.close();
    }
  });
});

describe('openBridgeDb — permissoes de arquivo (best-effort)', () => {
  it('aplica 700 no diretorio e 600 no arquivo quando o SO suporta chmod', () => {
    const path = tmpBridgeDbPath();
    const db = openBridgeDb(path);
    try {
      // macOS/Linux honram chmod; nao falhar o teste em SO sem suporte real
      // (best-effort, contracts §11.4) — mas neste harness (darwin/linux CI)
      // o modo deve refletir exatamente o solicitado.
      const dirMode = statSync(join(path, '..')).mode & 0o777;
      const fileMode = statSync(path).mode & 0o777;
      expect(dirMode).toBe(0o700);
      expect(fileMode).toBe(0o600);
    } finally {
      db.close();
    }
  });
});

describe('openBridgeDb — conexao separada de open.ts (corpus)', () => {
  it('escrever na conexao de bridge NUNCA usa o handle do corpus, e o corpus segue read-only', () => {
    const corpusPath = tmpBridgeDbPath().replace('bridge.db', 'knowledge.db');
    toClean.push(corpusPath);
    makeValidCorpus(corpusPath);

    const bridgePath = tmpBridgeDbPath();

    const corpusOpen = openDb(corpusPath, ['2']);
    expect(corpusOpen.ok).toBe(true);
    if (!corpusOpen.ok) throw new Error('setup falhou');
    const corpusDb = corpusOpen.db;

    const bridgeDb = openBridgeDb(bridgePath);

    try {
      // Instancias distintas — nenhum compartilhamento de handle.
      expect(bridgeDb).not.toBe(corpusDb);

      // O corpus (aberto via open.ts) permanece read-only — tentar escrever
      // nele (ainda que fosse na tabela errada) e recusado pelo runtime.
      expect(() => corpusDb.exec("INSERT INTO executions (execucao_id, project) VALUES ('x','y')")).toThrow(
        /readonly|query_only/i,
      );

      // A conexao de bridge escreve livremente no PROPRIO arquivo.
      expect(() =>
        bridgeDb
          .prepare(
            `INSERT INTO interventions
              (question_id, project_path, project, execution_kind, kind, question, default_value, expires_at, created_at)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
          )
          .run('q-sep', '/tmp/proj', 'proj', 'agente-00c', 'text', 'texto?', 'default', '2026-01-01', '2026-01-01'),
      ).not.toThrow();
    } finally {
      corpusDb.close();
      bridgeDb.close();
    }
  });
});

describe('openBridgeDb — PRAGMA quick_check (achado 6.3 da convergencia, contracts/panel-bridge-api.md:102)', () => {
  it('corrupcao que nao afeta o DDL (CREATE TABLE IF NOT EXISTS ja tem o schema) ainda assim faz openBridgeDb lancar, porque quick_check a detecta', () => {
    const path = tmpBridgeDbPath();

    // 1. cria um bridge.db valido com schema aplicado + uma linha, faz
    //    checkpoint p/ consolidar tudo no arquivo principal (sem WAL
    //    pendente que mascare a corrupcao).
    const db = openBridgeDb(path);
    db.prepare(
      `INSERT INTO interventions
        (question_id, project_path, project, execution_kind, kind, question, default_value, expires_at, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    ).run('q-corrupt', '/tmp/proj', 'proj', 'agente-00c', 'text', 'texto?', 'default', '2026-01-01', '2026-01-01');
    db.pragma('wal_checkpoint(TRUNCATE)');
    db.close();

    // 2. corrompe bytes de uma pagina de DADOS (offset 4096, alem da pagina
    //    1 de header/schema) — `CREATE TABLE IF NOT EXISTS` nao le essa
    //    pagina (o schema ja esta la), entao o DDL sozinho NAO detectaria
    //    isso (medido empiricamente: sem quick_check, `db.exec(DDL)` nao
    //    lanca aqui).
    const buf = readFileSync(path);
    for (let i = 4096; i < Math.min(buf.length, 4096 + 50); i++) buf[i] = 0xff;
    writeFileSync(path, buf);

    // 3. reabrir: com quick_check, openBridgeDb lanca (evidencia do fix).
    expect(() => openBridgeDb(path)).toThrow(/malformed|quick_check/i);
  });
});

describe('openBridgeDb — fecha o handle quando falha apos abrir (achado 6.4 da convergencia, plan.md:126)', () => {
  it('erro em pragma/quick_check/DDL apos new Database() fecha o handle antes de propagar (nunca vaza)', () => {
    const path = tmpBridgeDbPath();
    // Arquivo que nao e um SQLite valido: `new Database()` abre o handle
    // (lazy — so falha ao tocar paginas), e o primeiro `db.pragma(...)`
    // lanca "file is not a database" (medido empiricamente).
    writeFileSync(path, Buffer.from('not a valid sqlite file'.repeat(50)));

    const closeSpy = vi.spyOn(Database.prototype, 'close');
    try {
      expect(() => openBridgeDb(path)).toThrow(/not a database/i);
      expect(closeSpy).toHaveBeenCalled();
    } finally {
      closeSpy.mockRestore();
    }
  });
});
