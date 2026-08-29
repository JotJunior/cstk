/**
 * Testes da cadeia de resolucao de caminho de projeto (lib/project-root.ts):
 * CSTK_PROJECT_PATHS (operador) > executions.target_project_path da
 * knowledge.db v9 (validado) > null.
 *
 * Ref: FR-008/FR-012; research.md Decision 9 (valores da db sao UNTRUSTED);
 * follow-up zero-config do gap "projeto sem path armazenado" (cstk >= 5.19,
 * schema v9, coluna aditiva executions.target_project_path).
 */
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import Database from 'better-sqlite3';
import {
  mkdtempSync,
  mkdirSync,
  writeFileSync,
  symlinkSync,
  rmSync,
  realpathSync,
} from 'node:fs';
import { tmpdir, homedir } from 'node:os';
import { join } from 'node:path';
import {
  validateProjectRootPath,
  dbTargetProjectPath,
  resolveProjectRoot,
} from '../../src/lib/project-root.js';
import { openDb } from '../../src/db/open.js';
import { DEFAULT_SCHEMA_VERSIONS } from '../../src/config.js';

let base: string;
let savedProjectPaths: string | undefined;

beforeEach(() => {
  // realpath do tmpdir: no macOS /var -> /private/var; normaliza para que
  // caminhos criados == caminhos canonicalizados nas assercoes.
  base = mkdtempSync(join(realpathSync(tmpdir()), 'project-root-'));
  savedProjectPaths = process.env['CSTK_PROJECT_PATHS'];
  delete process.env['CSTK_PROJECT_PATHS'];
});

afterEach(() => {
  rmSync(base, { recursive: true, force: true });
  if (savedProjectPaths === undefined) delete process.env['CSTK_PROJECT_PATHS'];
  else process.env['CSTK_PROJECT_PATHS'] = savedProjectPaths;
});

/** Fixture minima de executions compativel com dbTargetProjectPath. */
function makeDb(opts: { withColumn: boolean }): Database.Database {
  const db = new Database(':memory:');
  db.exec(`CREATE TABLE executions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    project TEXT NOT NULL,
    started_at TEXT${opts.withColumn ? ',\n    target_project_path TEXT' : ''}
  )`);
  return db;
}

function insertExec(
  db: Database.Database,
  project: string,
  startedAt: string,
  path: string | null
): void {
  db.prepare(
    'INSERT INTO executions (project, started_at, target_project_path) VALUES (?, ?, ?)'
  ).run(project, startedAt, path);
}

describe('validateProjectRootPath (valor UNTRUSTED da db)', () => {
  it('aceita diretorio existente e retorna canonicalizado', () => {
    const dir = join(base, 'projeto');
    mkdirSync(dir);
    expect(validateProjectRootPath(dir)).toBe(dir);
  });

  it('resolve symlink para o alvo real (realpath)', () => {
    const target = join(base, 'alvo');
    mkdirSync(target);
    const link = join(base, 'link');
    symlinkSync(target, link);
    expect(validateProjectRootPath(link)).toBe(target);
  });

  it('rejeita caminho inexistente', () => {
    expect(validateProjectRootPath(join(base, 'nao-existe'))).toBeNull();
  });

  it('rejeita arquivo (nao-diretorio)', () => {
    const file = join(base, 'arquivo.txt');
    writeFileSync(file, 'x');
    expect(validateProjectRootPath(file)).toBeNull();
  });

  it('rejeita zonas proibidas (path-guard): /etc e ~/.claude', () => {
    // Ambos existem em macOS/linux dev; se nao existirem, realpath falha e o
    // resultado continua null — a assercao vale nos dois mundos.
    expect(validateProjectRootPath('/etc')).toBeNull();
    expect(validateProjectRootPath(join(homedir(), '.claude'))).toBeNull();
  });

  it('rejeita raiz do filesystem, vazio e nao-string', () => {
    expect(validateProjectRootPath('/')).toBeNull();
    expect(validateProjectRootPath('')).toBeNull();
    expect(validateProjectRootPath('   ')).toBeNull();
    expect(validateProjectRootPath(null)).toBeNull();
    expect(validateProjectRootPath(42)).toBeNull();
  });
});

describe('dbTargetProjectPath (knowledge.db v9)', () => {
  it('retorna o caminho validado da execucao mais recente do projeto', () => {
    const oldDir = join(base, 'antigo');
    const newDir = join(base, 'novo');
    mkdirSync(oldDir);
    mkdirSync(newDir);
    const db = makeDb({ withColumn: true });
    insertExec(db, 'proj', '2026-01-01T00:00:00Z', oldDir);
    insertExec(db, 'proj', '2026-07-01T00:00:00Z', newDir);
    expect(dbTargetProjectPath(db, 'proj')).toBe(newDir);
    db.close();
  });

  it('ignora linhas NULL/vazias e de outros projetos', () => {
    const dir = join(base, 'projeto');
    mkdirSync(dir);
    const db = makeDb({ withColumn: true });
    insertExec(db, 'proj', '2026-07-02T00:00:00Z', null);
    insertExec(db, 'proj', '2026-07-03T00:00:00Z', '  ');
    insertExec(db, 'outro', '2026-07-04T00:00:00Z', dir);
    insertExec(db, 'proj', '2026-07-01T00:00:00Z', dir);
    expect(dbTargetProjectPath(db, 'proj')).toBe(dir);
    expect(dbTargetProjectPath(db, 'sem-linhas')).toBeNull();
    db.close();
  });

  it('valor invalido (dir inexistente) degrada para null', () => {
    const db = makeDb({ withColumn: true });
    insertExec(db, 'proj', '2026-07-01T00:00:00Z', join(base, 'sumiu'));
    expect(dbTargetProjectPath(db, 'proj')).toBeNull();
    db.close();
  });

  it('db v8 (coluna ausente) degrada para null sem lancar', () => {
    const db = makeDb({ withColumn: false });
    db.prepare('INSERT INTO executions (project, started_at) VALUES (?, ?)').run(
      'proj',
      '2026-07-01T00:00:00Z'
    );
    expect(dbTargetProjectPath(db, 'proj')).toBeNull();
    db.close();
  });
});

describe('resolveProjectRoot (cadeia env > db > null)', () => {
  it('CSTK_PROJECT_PATHS sempre vence a db', () => {
    const envDir = join(base, 'do-env');
    const dbDir = join(base, 'da-db');
    mkdirSync(envDir);
    mkdirSync(dbDir);
    process.env['CSTK_PROJECT_PATHS'] = `proj=${envDir}`;
    const db = makeDb({ withColumn: true });
    insertExec(db, 'proj', '2026-07-01T00:00:00Z', dbDir);
    expect(resolveProjectRoot(db, 'proj')).toBe(envDir);
    db.close();
  });

  it('sem env, cai para a db; sem db, null (comportamento pre-v9)', () => {
    const dbDir = join(base, 'da-db');
    mkdirSync(dbDir);
    const db = makeDb({ withColumn: true });
    insertExec(db, 'proj', '2026-07-01T00:00:00Z', dbDir);
    expect(resolveProjectRoot(db, 'proj')).toBe(dbDir);
    expect(resolveProjectRoot(null, 'proj')).toBeNull();
    db.close();
  });

  it('integracao: openDb aceita schema v9 e alimenta a cadeia', () => {
    const projDir = join(base, 'projeto-real');
    mkdirSync(projDir);
    const dbFile = join(base, 'knowledge.db');
    const w = new Database(dbFile);
    w.exec(`CREATE TABLE schema_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
      CREATE TABLE executions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        project TEXT NOT NULL,
        started_at TEXT,
        target_project_path TEXT
      );`);
    w.prepare("INSERT INTO schema_meta (key, value) VALUES ('schema_version', '9')").run();
    w.prepare(
      'INSERT INTO executions (project, started_at, target_project_path) VALUES (?, ?, ?)'
    ).run('proj', '2026-07-15T00:00:00Z', projDir);
    w.close();

    const opened = openDb(dbFile, [...DEFAULT_SCHEMA_VERSIONS]);
    expect(opened.ok).toBe(true);
    if (opened.ok) {
      expect(resolveProjectRoot(opened.db, 'proj')).toBe(projDir);
      opened.db.close();
    }
  });
});
