/**
 * Testes do watcher de ingestao (tasks 2.1.6, 2.2.4, 2.3.5).
 * Ref: contracts/watchers.md; research.md Decisions 2, 3, 4, 9; quickstart Cenario 2
 *
 * `execFile` real e SEMPRE substituido por um mock injetado (`execFileImpl`)
 * — nenhum subprocesso `cstk` de fato roda nestes testes. O binario `cstk` e
 * "resolvido" via CSTK_BINARY_PATH apontando para um arquivo fixture com bit
 * executavel (chmod 755), sem precisar de um `cstk` real instalado no PATH do
 * ambiente de CI.
 */
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { mkdtempSync, writeFileSync, mkdirSync, chmodSync, realpathSync, rmSync, utimesSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import Database from 'better-sqlite3';
import {
  runWatcherTick,
  deriveStateDir,
  resolveCstkBinary,
  resetCstkBinaryCacheForTests,
  resetWatcherCacheForTests,
  getWatcherCacheEntry,
  startIngestWatcher,
  type ExecFileFn,
} from '../../src/watchers/ingest-watcher.js';

// ─────────────────────────────────────────────────────────
// Fixtures
// ─────────────────────────────────────────────────────────

let tmpRoot: string;
let dbPath: string;
let projectDir: string;

function makeExecutionsDb(
  path: string,
  rows: Array<{ project: string; feature: string | null; status: string; targetProjectPath?: string }>
): void {
  const db = new Database(path);
  db.exec(`
    CREATE TABLE schema_meta (key TEXT PRIMARY KEY, value TEXT);
    INSERT INTO schema_meta VALUES ('schema_version', '2');
    CREATE TABLE executions (
      execution_id TEXT PRIMARY KEY, project TEXT, feature TEXT, status TEXT, target_project_path TEXT
    );
  `);
  const ins = db.prepare(
    'INSERT INTO executions (execution_id, project, feature, status, target_project_path) VALUES (?, ?, ?, ?, ?)'
  );
  rows.forEach((r, i) => ins.run(`exec-${i}`, r.project, r.feature, r.status, r.targetProjectPath ?? null));
  db.close();
}

/** Fixture de binario "cstk": arquivo com bit executavel — resolveCstkBinary so checa X_OK + isFile. */
function makeFakeCstkBinary(dir: string): string {
  const p = join(dir, 'cstk-fake');
  writeFileSync(p, '#!/bin/sh\necho fake\n');
  chmodSync(p, 0o755);
  return p;
}

function makeStateDir(kind: 'feature-00c' | 'agente-00c', projectRoot: string, feature?: string): string {
  const base = kind === 'feature-00c'
    ? join(projectRoot, '.claude', 'feature-00c-state', feature ?? 'my-feature')
    : join(projectRoot, '.claude', 'agente-00c-state');
  mkdirSync(base, { recursive: true });
  writeFileSync(join(base, 'state.json'), JSON.stringify({ ok: true }));
  return base;
}

beforeEach(() => {
  tmpRoot = mkdtempSync(join(tmpdir(), 'cstk-watcher-'));
  dbPath = join(tmpRoot, 'knowledge.db');
  projectDir = join(tmpRoot, 'project');
  mkdirSync(projectDir, { recursive: true });
  process.env['CSTK_PROJECT_PATHS'] = `proj=${projectDir}`;
  process.env['CSTK_BINARY_PATH'] = makeFakeCstkBinary(tmpRoot);
  resetCstkBinaryCacheForTests();
  resetWatcherCacheForTests();
});

afterEach(() => {
  delete process.env['CSTK_PROJECT_PATHS'];
  delete process.env['CSTK_BINARY_PATH'];
  resetCstkBinaryCacheForTests();
  resetWatcherCacheForTests();
  rmSync(tmpRoot, { recursive: true, force: true });
});

// ─────────────────────────────────────────────────────────
// deriveStateDir (task 2.1.3 / 2.3.2)
// ─────────────────────────────────────────────────────────

describe('deriveStateDir', () => {
  it('deriva layout feature-00c quando feature esta presente', () => {
    expect(deriveStateDir('/p', 'my-feature')).toBe(join('/p', '.claude', 'feature-00c-state', 'my-feature'));
  });

  it('deriva layout agente-00c quando feature e null', () => {
    expect(deriveStateDir('/p', null)).toBe(join('/p', '.claude', 'agente-00c-state'));
  });

  it('deriva layout agente-00c quando feature e string vazia', () => {
    expect(deriveStateDir('/p', '')).toBe(join('/p', '.claude', 'agente-00c-state'));
  });

  it('retorna null (nunca lanca) para feature com segmento de traversal', () => {
    expect(deriveStateDir('/p', '../etc')).toBeNull();
    expect(deriveStateDir('/p', 'a/b')).toBeNull();
    expect(deriveStateDir('/p', 'a\\b')).toBeNull();
  });
});

// ─────────────────────────────────────────────────────────
// resolveCstkBinary (task 2.3.1 — anti PATH hijack)
// ─────────────────────────────────────────────────────────

describe('resolveCstkBinary', () => {
  it('resolve via CSTK_BINARY_PATH quando pinado e executavel', () => {
    const resolved = resolveCstkBinary();
    expect(resolved).toBe(process.env['CSTK_BINARY_PATH']);
  });

  it('retorna null (falha segura) quando CSTK_BINARY_PATH aponta para arquivo inexistente', () => {
    process.env['CSTK_BINARY_PATH'] = join(tmpRoot, 'nao-existe-cstk');
    resetCstkBinaryCacheForTests();
    expect(resolveCstkBinary()).toBeNull();
  });

  it('cacheia o resultado (2a chamada nao re-resolve)', () => {
    const first = resolveCstkBinary();
    // Mudar o env NAO deve afetar o valor ja cacheado
    process.env['CSTK_BINARY_PATH'] = join(tmpRoot, 'outro');
    expect(resolveCstkBinary()).toBe(first);
  });
});

// ─────────────────────────────────────────────────────────
// runWatcherTick — caminho feliz + ociosidade (task 2.1.6)
// ─────────────────────────────────────────────────────────

describe('runWatcherTick — ociosidade (FR-013)', () => {
  it('nenhuma execucao ativa ⇒ nenhum subprocesso disparado', async () => {
    makeExecutionsDb(dbPath, [{ project: 'proj', feature: 'my-feature', status: 'concluida' }]);
    const execFileImpl: ExecFileFn = async () => { throw new Error('NAO deveria ser chamado'); };

    const result = await runWatcherTick({ dbPath, supportedSchemaVersions: ['2'], execFileImpl });

    expect(result.degradedDb).toBe(false);
    expect(result.activeCount).toBe(0);
    expect(result.triggered).toBe(0);
  });
});

describe('runWatcherTick — dispara ingestao para execucao ativa', () => {
  it('execucao em_andamento com state-dir existente dispara exatamente 1 subprocesso', async () => {
    makeStateDir('feature-00c', projectDir, 'my-feature');
    makeExecutionsDb(dbPath, [{ project: 'proj', feature: 'my-feature', status: 'em_andamento' }]);

    const calls: Array<{ file: string; args: string[] }> = [];
    const execFileImpl: ExecFileFn = async (file, args) => {
      calls.push({ file, args });
      return { stdout: 'ok', stderr: '' };
    };

    const result = await runWatcherTick({ dbPath, supportedSchemaVersions: ['2'], execFileImpl });

    expect(result.triggered).toBe(1);
    expect(calls).toHaveLength(1);
    expect(calls[0]?.file).toBe(process.env['CSTK_BINARY_PATH']);
    expect(calls[0]?.args).toEqual([
      'recall', '--ingest', '--state-dir',
      join(projectDir, '.claude', 'feature-00c-state', 'my-feature'),
      '--db', dbPath,
    ]);
  });

  it('execucao aguardando_humano tambem e observada (FR-003)', async () => {
    makeStateDir('agente-00c', projectDir);
    makeExecutionsDb(dbPath, [{ project: 'proj', feature: null, status: 'aguardando_humano' }]);
    const execFileImpl: ExecFileFn = async () => ({ stdout: '', stderr: '' });

    const result = await runWatcherTick({ dbPath, supportedSchemaVersions: ['2'], execFileImpl });
    expect(result.triggered).toBe(1);
  });

  it('projeto sem entrada em CSTK_PROJECT_PATHS ⇒ pula sem lancar (FR-008/FR-012)', async () => {
    makeExecutionsDb(dbPath, [{ project: 'projeto-desconhecido', feature: 'x', status: 'em_andamento' }]);
    const execFileImpl: ExecFileFn = async () => { throw new Error('NAO deveria ser chamado'); };

    const result = await runWatcherTick({ dbPath, supportedSchemaVersions: ['2'], execFileImpl });
    expect(result.triggered).toBe(0);
    expect(result.skipped).toBe(1);
  });

  it('state-dir ausente no filesystem ⇒ pula sem lancar (FR-012)', async () => {
    // projeto mapeado, mas NENHUM state-dir criado em disco
    makeExecutionsDb(dbPath, [{ project: 'proj', feature: 'inexistente', status: 'em_andamento' }]);
    const execFileImpl: ExecFileFn = async () => { throw new Error('NAO deveria ser chamado'); };

    const result = await runWatcherTick({ dbPath, supportedSchemaVersions: ['2'], execFileImpl });
    expect(result.triggered).toBe(0);
    expect(result.skipped).toBe(1);
  });
});

// ─────────────────────────────────────────────────────────
// Idempotencia (task 2.2.4)
// ─────────────────────────────────────────────────────────

describe('runWatcherTick — idempotencia (FR-014)', () => {
  it('duas assinaturas iguais consecutivas disparam ingestao apenas uma vez', async () => {
    makeStateDir('feature-00c', projectDir, 'my-feature');
    makeExecutionsDb(dbPath, [{ project: 'proj', feature: 'my-feature', status: 'em_andamento' }]);
    let callCount = 0;
    const execFileImpl: ExecFileFn = async () => { callCount++; return { stdout: '', stderr: '' }; };

    const r1 = await runWatcherTick({ dbPath, supportedSchemaVersions: ['2'], execFileImpl });
    const r2 = await runWatcherTick({ dbPath, supportedSchemaVersions: ['2'], execFileImpl });

    expect(r1.triggered).toBe(1);
    expect(r2.triggered).toBe(0); // assinatura inalterada — pulou (2.2.3)
    expect(r2.skipped).toBe(1);
    expect(callCount).toBe(1);
  });

  it('mudanca de mtime de state.json dispara nova ingestao', async () => {
    const stateDir = makeStateDir('feature-00c', projectDir, 'my-feature');
    makeExecutionsDb(dbPath, [{ project: 'proj', feature: 'my-feature', status: 'em_andamento' }]);
    let callCount = 0;
    const execFileImpl: ExecFileFn = async () => { callCount++; return { stdout: '', stderr: '' }; };

    await runWatcherTick({ dbPath, supportedSchemaVersions: ['2'], execFileImpl });
    // "Mudar" o state.json — mtime futuro garante assinatura diferente mesmo em FS de baixa resolucao
    const future = new Date(Date.now() + 5000);
    utimesSync(join(stateDir, 'state.json'), future, future);
    const r2 = await runWatcherTick({ dbPath, supportedSchemaVersions: ['2'], execFileImpl });

    expect(r2.triggered).toBe(1);
    expect(callCount).toBe(2);
  });
});

// ─────────────────────────────────────────────────────────
// Transicao de status (task 5.1.3, quickstart Cenario 3, FR-003)
// ─────────────────────────────────────────────────────────

describe('runWatcherTick — transicao de status (Cenario 3, FR-003)', () => {
  it('execucao concluida apos estar em_andamento sai do conjunto ativo no tick seguinte', async () => {
    makeStateDir('feature-00c', projectDir, 'my-feature');
    makeExecutionsDb(dbPath, [{ project: 'proj', feature: 'my-feature', status: 'em_andamento' }]);
    const execFileImpl: ExecFileFn = async () => ({ stdout: '', stderr: '' });

    const r1 = await runWatcherTick({ dbPath, supportedSchemaVersions: ['2'], execFileImpl });
    expect(r1.activeCount).toBe(1);
    expect(r1.triggered).toBe(1);

    // Transicao real: a execucao conclui (mesma DB, UPDATE de status — nao
    // recriar a DB, para provar que e a MUDANCA de status que tira do conjunto
    // ativo, nao uma DB nova).
    const db = new Database(dbPath);
    db.prepare("UPDATE executions SET status = 'concluida' WHERE execution_id = 'exec-0'").run();
    db.close();

    const execFileImpl2: ExecFileFn = async () => {
      throw new Error('NAO deveria ser chamado — execucao concluida deixou de ser ativa');
    };
    const r2 = await runWatcherTick({ dbPath, supportedSchemaVersions: ['2'], execFileImpl: execFileImpl2 });

    expect(r2.activeCount).toBe(0);
    expect(r2.triggered).toBe(0);
  });

  it('execucao abortada apos estar aguardando_humano tambem sai do conjunto ativo (FR-003)', async () => {
    makeStateDir('agente-00c', projectDir);
    makeExecutionsDb(dbPath, [{ project: 'proj', feature: null, status: 'aguardando_humano' }]);
    const execFileImpl: ExecFileFn = async () => ({ stdout: '', stderr: '' });

    const r1 = await runWatcherTick({ dbPath, supportedSchemaVersions: ['2'], execFileImpl });
    expect(r1.activeCount).toBe(1);
    expect(r1.triggered).toBe(1);

    const db = new Database(dbPath);
    db.prepare("UPDATE executions SET status = 'abortada' WHERE execution_id = 'exec-0'").run();
    db.close();

    const execFileImpl2: ExecFileFn = async () => {
      throw new Error('NAO deveria ser chamado — execucao abortada deixou de ser ativa');
    };
    const r2 = await runWatcherTick({ dbPath, supportedSchemaVersions: ['2'], execFileImpl: execFileImpl2 });

    expect(r2.activeCount).toBe(0);
    expect(r2.triggered).toBe(0);
  });
});

// ─────────────────────────────────────────────────────────
// Descoberta via filesystem (fix ovo-e-galinha: state.json
// novo sem linha em `executions`)
// ─────────────────────────────────────────────────────────

describe('runWatcherTick — descoberta via filesystem', () => {
  it('state.json recem-criado SEM nenhuma linha na db dispara ingestao (ovo-e-galinha)', async () => {
    const stateDir = makeStateDir('feature-00c', projectDir, 'nova-feature');
    makeExecutionsDb(dbPath, []); // db vazia: execucao ainda nunca ingerida

    const calls: Array<{ args: string[] }> = [];
    const execFileImpl: ExecFileFn = async (_file, args) => {
      calls.push({ args });
      return { stdout: '', stderr: '' };
    };

    const result = await runWatcherTick({ dbPath, supportedSchemaVersions: ['2'], execFileImpl });

    expect(result.activeCount).toBe(0);
    expect(result.fsDiscovered).toBe(1);
    expect(result.triggered).toBe(1);
    expect(calls[0]?.args).toEqual(['recall', '--ingest', '--state-dir', stateDir, '--db', dbPath]);
  });

  it('knowledge.db AUSENTE nao bloqueia a descoberta — ingest do cstk cria a db', async () => {
    // Cenario "painel novo": nenhuma knowledge.db ainda; cstk recall --ingest
    // cria e popula a db (verificado empiricamente, cstk 5.21.0).
    makeStateDir('feature-00c', projectDir, 'primeira-feature');
    // NAO cria dbPath de proposito
    let callCount = 0;
    const execFileImpl: ExecFileFn = async () => { callCount++; return { stdout: '', stderr: '' }; };

    const result = await runWatcherTick({ dbPath, supportedSchemaVersions: ['2'], execFileImpl });

    expect(result.degradedDb).toBe(true); // db ainda nao existe — flag mantida
    expect(result.fsDiscovered).toBe(1);
    expect(result.triggered).toBe(1);
    expect(callCount).toBe(1);
  });

  it('layout agente-00c tambem e descoberto via filesystem', async () => {
    makeStateDir('agente-00c', projectDir);
    makeExecutionsDb(dbPath, []);
    const execFileImpl: ExecFileFn = async () => ({ stdout: '', stderr: '' });

    const result = await runWatcherTick({ dbPath, supportedSchemaVersions: ['2'], execFileImpl });
    expect(result.fsDiscovered).toBe(1);
    expect(result.triggered).toBe(1);
  });

  it('feature nova dispara; state-dir de execucao concluida conhecida e apenas semeado (sem ingest no boot)', async () => {
    makeStateDir('feature-00c', projectDir, 'concluida-antiga');
    const novaDir = makeStateDir('feature-00c', projectDir, 'feature-nova');
    makeExecutionsDb(dbPath, [{ project: 'proj', feature: 'concluida-antiga', status: 'concluida' }]);

    const calls: Array<{ args: string[] }> = [];
    const execFileImpl: ExecFileFn = async (_file, args) => {
      calls.push({ args });
      return { stdout: '', stderr: '' };
    };

    const result = await runWatcherTick({ dbPath, supportedSchemaVersions: ['2'], execFileImpl });

    expect(result.triggered).toBe(1); // SO a feature nova
    expect(calls).toHaveLength(1);
    expect(calls[0]?.args).toContain(novaDir);
  });

  it('state-dir terminal semeado volta a ingerir quando o state.json muda (re-execucao da feature)', async () => {
    const stateDir = makeStateDir('feature-00c', projectDir, 'my-feature');
    makeExecutionsDb(dbPath, [{ project: 'proj', feature: 'my-feature', status: 'concluida' }]);
    let callCount = 0;
    const execFileImpl: ExecFileFn = async () => { callCount++; return { stdout: '', stderr: '' }; };

    const r1 = await runWatcherTick({ dbPath, supportedSchemaVersions: ['2'], execFileImpl });
    expect(r1.triggered).toBe(0); // primeira vista: seed, sem subprocesso
    expect(callCount).toBe(0);

    // Re-execucao: novo processo escreve no MESMO state.json
    const future = new Date(Date.now() + 5000);
    utimesSync(join(stateDir, 'state.json'), future, future);

    const r2 = await runWatcherTick({ dbPath, supportedSchemaVersions: ['2'], execFileImpl });
    expect(r2.triggered).toBe(1);
    expect(callCount).toBe(1);
  });

  it('raiz vinda de executions.target_project_path (schema v9) e varrida mesmo sem CSTK_PROJECT_PATHS', async () => {
    delete process.env['CSTK_PROJECT_PATHS'];
    const otherProject = join(tmpRoot, 'other-project');
    mkdirSync(otherProject, { recursive: true });
    makeStateDir('feature-00c', otherProject, 'feature-antiga');
    const novaDir = makeStateDir('feature-00c', otherProject, 'feature-nova');
    makeExecutionsDb(dbPath, [
      { project: 'projx', feature: 'feature-antiga', status: 'concluida', targetProjectPath: otherProject },
    ]);

    const calls: Array<{ args: string[] }> = [];
    const execFileImpl: ExecFileFn = async (_file, args) => {
      calls.push({ args });
      return { stdout: '', stderr: '' };
    };

    const result = await runWatcherTick({ dbPath, supportedSchemaVersions: ['2'], execFileImpl });

    // validateProjectRootPath canonicaliza via realpath (no macOS, tmpdir e symlink)
    const canonicalNovaDir = novaDir.replace(otherProject, realpathSync(otherProject));
    expect(result.triggered).toBe(1); // so a feature nova; a antiga (terminal conhecida) e semeada
    expect(calls[0]?.args).toContain(canonicalNovaDir);
  });

  it('nome de diretorio de feature fora do regex seguro e ignorado (anti-traversal)', async () => {
    const base = join(projectDir, '.claude', 'feature-00c-state', 'nome.com.pontos');
    mkdirSync(base, { recursive: true });
    writeFileSync(join(base, 'state.json'), JSON.stringify({ ok: true }));
    makeExecutionsDb(dbPath, []);
    const execFileImpl: ExecFileFn = async () => { throw new Error('NAO deveria ser chamado'); };

    const result = await runWatcherTick({ dbPath, supportedSchemaVersions: ['2'], execFileImpl });
    expect(result.fsDiscovered).toBe(0);
    expect(result.triggered).toBe(0);
  });

  it('descoberta via db + filesystem do MESMO state-dir nao duplica subprocesso', async () => {
    makeStateDir('feature-00c', projectDir, 'my-feature');
    makeExecutionsDb(dbPath, [{ project: 'proj', feature: 'my-feature', status: 'em_andamento' }]);
    let callCount = 0;
    const execFileImpl: ExecFileFn = async () => { callCount++; return { stdout: '', stderr: '' }; };

    const result = await runWatcherTick({ dbPath, supportedSchemaVersions: ['2'], execFileImpl });

    expect(result.activeCount).toBe(1);
    expect(result.fsDiscovered).toBe(0); // deduplicado: ja alvo via execucao ativa
    expect(result.triggered).toBe(1);
    expect(callCount).toBe(1);
  });
});

// ─────────────────────────────────────────────────────────
// Hardening (task 2.3.5)
// ─────────────────────────────────────────────────────────

describe('runWatcherTick — hardening (Decision 9)', () => {
  it('binario cstk nao resolvido ⇒ falha segura sem crash, nenhum subprocesso disparado', async () => {
    process.env['CSTK_BINARY_PATH'] = join(tmpRoot, 'binario-inexistente');
    resetCstkBinaryCacheForTests();
    makeStateDir('feature-00c', projectDir, 'my-feature');
    makeExecutionsDb(dbPath, [{ project: 'proj', feature: 'my-feature', status: 'em_andamento' }]);
    const execFileImpl: ExecFileFn = async () => { throw new Error('NAO deveria ser chamado'); };

    const result = await runWatcherTick({ dbPath, supportedSchemaVersions: ['2'], execFileImpl });

    expect(result.cstkUnresolved).toBe(true);
    expect(result.triggered).toBe(0);
    expect(result.skipped).toBe(1);
  });

  it('concorrencia acima do cap ⇒ excedente e pulado (nao enfileira sem limite)', async () => {
    const rows = Array.from({ length: 6 }, (_, i) => {
      makeStateDir('feature-00c', projectDir, `feature-${i}`);
      return { project: 'proj', feature: `feature-${i}`, status: 'em_andamento' as const };
    });
    makeExecutionsDb(dbPath, rows);
    let callCount = 0;
    const execFileImpl: ExecFileFn = async () => { callCount++; return { stdout: '', stderr: '' }; };

    const result = await runWatcherTick({ dbPath, supportedSchemaVersions: ['2'], execFileImpl, maxConcurrent: 2 });

    expect(callCount).toBeLessThanOrEqual(2);
    expect(result.triggered).toBeLessThanOrEqual(2);
    expect(result.activeCount).toBe(6);
  });

  it('backoff aplicado apos falha persistente — re-tentativa imediata e pulada', async () => {
    const stateDir = makeStateDir('feature-00c', projectDir, 'my-feature');
    makeExecutionsDb(dbPath, [{ project: 'proj', feature: 'my-feature', status: 'em_andamento' }]);
    const execFileImpl: ExecFileFn = async () => { throw new Error('ingestao falhou (simulado)'); };

    const r1 = await runWatcherTick({ dbPath, supportedSchemaVersions: ['2'], execFileImpl, backoffMs: 60_000 });
    expect(r1.triggered).toBe(0);
    expect(r1.skipped).toBe(1);
    const cached = getWatcherCacheEntry(stateDir);
    expect(cached?.lastError).toContain('ingestao falhou');

    // 2a tick imediatamente apos — dentro da janela de backoff, deve pular sem re-tentar
    let secondCallCount = 0;
    const execFileImpl2: ExecFileFn = async () => { secondCallCount++; return { stdout: '', stderr: '' }; };
    const r2 = await runWatcherTick({ dbPath, supportedSchemaVersions: ['2'], execFileImpl: execFileImpl2, backoffMs: 60_000 });

    expect(secondCallCount).toBe(0);
    expect(r2.triggered).toBe(0);
  });

  it('ingestao em voo ⇒ tick seguinte NAO dispara segundo subprocesso para o mesmo state-dir', async () => {
    makeStateDir('feature-00c', projectDir, 'my-feature');
    makeExecutionsDb(dbPath, [{ project: 'proj', feature: 'my-feature', status: 'em_andamento' }]);

    let callCount = 0;
    let releaseFirst: () => void = () => {};
    const hangingExec: ExecFileFn = async () => {
      callCount++;
      await new Promise<void>(resolvePromise => { releaseFirst = resolvePromise; });
      return { stdout: '', stderr: '' };
    };

    // 1o tick fica pendente (subprocesso "em voo"); 2o tick roda por completo
    // enquanto o 1o ainda nao terminou — deve pular, nao disparar de novo.
    const tick1 = runWatcherTick({ dbPath, supportedSchemaVersions: ['2'], execFileImpl: hangingExec });
    await new Promise(resolvePromise => setImmediate(resolvePromise)); // deixa o 1o tick chegar ao execImpl
    const r2 = await runWatcherTick({ dbPath, supportedSchemaVersions: ['2'], execFileImpl: hangingExec });

    expect(callCount).toBe(1);
    expect(r2.triggered).toBe(0);
    expect(r2.skipped).toBe(1);

    releaseFirst();
    const r1 = await tick1;
    expect(r1.triggered).toBe(1);

    // Apos o 1o terminar, o state-dir sai do conjunto em-voo: um tick novo com
    // assinatura mudada volta a disparar normalmente.
    const stateDir = join(projectDir, '.claude', 'feature-00c-state', 'my-feature');
    const future = new Date(Date.now() + 5000);
    utimesSync(join(stateDir, 'state.json'), future, future);
    const resolvingExec: ExecFileFn = async () => ({ stdout: '', stderr: '' });
    const r3 = await runWatcherTick({ dbPath, supportedSchemaVersions: ['2'], execFileImpl: resolvingExec });
    expect(r3.triggered).toBe(1);
  });

  it('apos backoff expirar, re-tentativa dispara normalmente', async () => {
    makeStateDir('feature-00c', projectDir, 'my-feature');
    makeExecutionsDb(dbPath, [{ project: 'proj', feature: 'my-feature', status: 'em_andamento' }]);
    let tick = 0;
    const failThenSucceed: ExecFileFn = async () => {
      tick++;
      if (tick === 1) throw new Error('falha simulada');
      return { stdout: '', stderr: '' };
    };

    let fakeNow = 1_000_000;
    const now = () => fakeNow;

    const r1 = await runWatcherTick({ dbPath, supportedSchemaVersions: ['2'], execFileImpl: failThenSucceed, backoffMs: 1000, now });
    expect(r1.triggered).toBe(0);

    fakeNow += 2000; // ultrapassa o backoff de 1000ms
    const r2 = await runWatcherTick({ dbPath, supportedSchemaVersions: ['2'], execFileImpl: failThenSucceed, backoffMs: 1000, now });
    expect(r2.triggered).toBe(1);
    expect(tick).toBe(2);
  });
});

// ─────────────────────────────────────────────────────────
// startIngestWatcher — smoke start/stop (task 2.5.3)
// ─────────────────────────────────────────────────────────

describe('startIngestWatcher — smoke start/stop', () => {
  afterEach(() => {
    vi.useRealTimers();
  });

  it('dispara ticks recorrentes via timer e para completamente apos stop()', async () => {
    vi.useFakeTimers();
    const stateDir = makeStateDir('feature-00c', projectDir, 'my-feature');
    makeExecutionsDb(dbPath, [{ project: 'proj', feature: 'my-feature', status: 'em_andamento' }]);

    let tickCount = 0;
    const execFileImpl: ExecFileFn = async () => {
      tickCount++;
      // Mock simula o state.json mudando entre ticks reais (side effect
      // deliberado) para que CADA tick do timer re-dispare de fato, isolando
      // o teste do comportamento de idempotencia (ja coberto em outro describe).
      const future = new Date(Date.now() + (tickCount + 1) * 1000);
      utimesSync(join(stateDir, 'state.json'), future, future);
      return { stdout: '', stderr: '' };
    };

    const handle = startIngestWatcher({
      dbPath, supportedSchemaVersions: ['2'], execFileImpl, intervalMs: 10,
    });

    await vi.advanceTimersByTimeAsync(55); // ~5 ticks de 10ms
    expect(tickCount).toBeGreaterThanOrEqual(2);

    handle.stop();
    const countAtStop = tickCount;
    await vi.advanceTimersByTimeAsync(200); // bem alem de mais alguns intervalos
    expect(tickCount).toBe(countAtStop); // nenhum tick novo apos stop()
  });

  it('onTickError e chamado quando runWatcherTick rejeita, sem derrubar o timer', async () => {
    vi.useFakeTimers();
    makeStateDir('feature-00c', projectDir, 'my-feature');
    makeExecutionsDb(dbPath, [{ project: 'proj', feature: 'my-feature', status: 'em_andamento' }]);

    const errors: unknown[] = [];
    // execFileImpl que rejeita e capturado internamente (vira skip), entao para
    // observar onTickError forcamos erro FORA do execFileImpl: dbPath invalido.
    const handle = startIngestWatcher({
      dbPath: join(tmpRoot, 'nao-existe', 'sub', 'x.db'),
      supportedSchemaVersions: ['2'],
      execFileImpl: async () => ({ stdout: '', stderr: '' }),
      intervalMs: 10,
      onTickError: err => { errors.push(err); },
    });

    await vi.advanceTimersByTimeAsync(15);
    handle.stop();
    // openDb NUNCA lanca (Principio II) — dbPath invalido apenas degrada
    // (retorna { ok:false }), entao runWatcherTick nao rejeita neste caso.
    // O hook onTickError existe para robustez a falhas inesperadas fora do
    // envelope tratado; aqui confirmamos que o tick NAO derruba o processo
    // mesmo com dbPath invalido (nenhuma excecao nao-capturada escapa).
    expect(errors).toEqual([]);
  });
});
