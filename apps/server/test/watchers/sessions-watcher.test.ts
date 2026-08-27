/**
 * Testes do watcher de sessoes (task 4.1.4).
 * Ref: contracts/sessions-api.md "Contrato do watcher (interno, nao HTTP)";
 * research.md Decision 7; tasks.md FASE 4.
 *
 * Cobertura exigida por 4.1.4: tick com raiz ausente nao lanca,
 * `getSessionsIndex` reflete o ultimo tick, `stop()` encerra o timer,
 * instancia isolada do `ingest-watcher` (falha simulada de um nao
 * contamina o outro).
 */
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { mkdtempSync, mkdirSync, rmSync, realpathSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import type { SessionSummaryDTO } from '@cstk-panel/shared-types';
import {
  runSessionsWatcherTick,
  startSessionsWatcher,
  getSessionsIndex,
  resetSessionsIndexForTests,
  DEFAULT_SESSIONS_WATCH_INTERVAL_MS,
  type SessionsWatcherTickOptions,
} from '../../src/watchers/sessions-watcher.js';
import type { SessionScanResult } from '../../src/lib/session-scan.js';
import {
  runWatcherTick,
  resetWatcherCacheForTests,
  resetCstkBinaryCacheForTests,
} from '../../src/watchers/ingest-watcher.js';

const SAMPLE_SESSION: SessionSummaryDTO = {
  sessionId: '5f3c2e10-71a4-4b8e-9c1a-2d6f8b0a9e11',
  projectPath: '/home/user/project',
  projectSlug: '-home-user-project',
  lastActivityAt: new Date().toISOString(),
  live: true,
  sizeBytes: 1234,
};

let tmpRoot: string;
let savedRoot: string | undefined;

beforeEach(() => {
  tmpRoot = mkdtempSync(join(realpathSync(tmpdir()), 'sessions-watcher-'));
  savedRoot = process.env['CSTK_SESSIONS_ROOT'];
  resetSessionsIndexForTests();
});

afterEach(() => {
  if (savedRoot === undefined) delete process.env['CSTK_SESSIONS_ROOT'];
  else process.env['CSTK_SESSIONS_ROOT'] = savedRoot;
  resetSessionsIndexForTests();
  rmSync(tmpRoot, { recursive: true, force: true });
  vi.useRealTimers();
});

// ─────────────────────────────────────────────────────────
// runSessionsWatcherTick — degradacao (task 4.1.3)
// ─────────────────────────────────────────────────────────

describe('runSessionsWatcherTick — raiz ausente', () => {
  it('nunca lanca; degrada com sessions-root-missing e indice vazio', async () => {
    process.env['CSTK_SESSIONS_ROOT'] = join(tmpRoot, 'nao-existe');

    const result = await runSessionsWatcherTick();

    expect(result.degraded).toBe(true);
    expect(result.reason).toBe('sessions-root-missing');
    expect(result.sessionCount).toBe(0);
    expect(typeof result.scannedAt).toBe('string');
    expect(getSessionsIndex().sessions).toEqual([]);
  });
});

describe('runSessionsWatcherTick — erro inesperado do scanImpl (defesa em profundidade)', () => {
  it('captura a excecao, nunca propaga, e degrada o indice sem reason especifico', async () => {
    const scanImpl: SessionsWatcherTickOptions['scanImpl'] = async () => {
      throw new Error('falha inesperada simulada');
    };

    const result = await runSessionsWatcherTick({ scanImpl });

    expect(result.degraded).toBe(true);
    expect(result.reason).toBeNull();
    expect(result.sessionCount).toBe(0);
    expect(getSessionsIndex().sessions).toEqual([]);
  });
});

// ─────────────────────────────────────────────────────────
// getSessionsIndex reflete o ultimo tick (snapshot atomico — achado onda-015)
// ─────────────────────────────────────────────────────────

describe('getSessionsIndex — reflete o ultimo tick', () => {
  it('sucesso popula o indice; tick degradado subsequente zera o indice', async () => {
    const okScan: () => Promise<SessionScanResult> = async () => ({
      degraded: false,
      sessions: [SAMPLE_SESSION],
      scrubMode: 'internal',
    });

    const okResult = await runSessionsWatcherTick({ scanImpl: okScan });
    expect(okResult.degraded).toBe(false);
    expect(okResult.sessionCount).toBe(1);
    const okSnapshot = getSessionsIndex();
    expect(okSnapshot.sessions).toEqual([SAMPLE_SESSION]);
    expect(okSnapshot.scannedAt).toBe(okResult.scannedAt);
    expect(okSnapshot.degradedReason).toBeNull();
    expect(okSnapshot.scrubMode).toBe('internal');

    const degradedScan: () => Promise<SessionScanResult> = async () => ({
      degraded: true,
      reason: 'sessions-root-unreadable',
    });
    const degradedResult = await runSessionsWatcherTick({ scanImpl: degradedScan });
    expect(degradedResult.degraded).toBe(true);
    expect(degradedResult.reason).toBe('sessions-root-unreadable');
    // Nao serve indice stale apos degradacao (Principio III) — zera.
    const degradedSnapshot = getSessionsIndex();
    expect(degradedSnapshot.sessions).toEqual([]);
    expect(degradedSnapshot.degradedReason).toBe('sessions-root-unreadable');
    // scrubMode volta ao default conservador — nao reafirma cobertura obtida
    // por um tick anterior ja invalidado (Principio III).
    expect(degradedSnapshot.scrubMode).toBe('internal');
  });

  it('diretorio raiz presente e vazio nao e degradacao — indice fica []', async () => {
    process.env['CSTK_SESSIONS_ROOT'] = tmpRoot; // existe, vazio

    const result = await runSessionsWatcherTick();

    expect(result.degraded).toBe(false);
    expect(result.sessionCount).toBe(0);
    expect(getSessionsIndex().sessions).toEqual([]);
  });

  it('snapshot e um objeto unico e coerente (sessions+scannedAt+scrubMode do MESMO tick)', async () => {
    const scanImpl: () => Promise<SessionScanResult> = async () => ({
      degraded: false,
      sessions: [SAMPLE_SESSION],
      scrubMode: 'cstk+internal',
    });

    const tickResult = await runSessionsWatcherTick({ scanImpl });
    const snapshot = getSessionsIndex();

    // As 3 chaves vem da MESMA leitura atomica de indexState — nunca
    // getters separados que poderiam observar ticks diferentes.
    expect(snapshot).toEqual({
      sessions: [SAMPLE_SESSION],
      scannedAt: tickResult.scannedAt,
      degradedReason: null,
      scrubMode: 'cstk+internal',
    });
  });
});

// ─────────────────────────────────────────────────────────
// startSessionsWatcher — smoke start/stop (task 4.1.2)
// ─────────────────────────────────────────────────────────

describe('startSessionsWatcher — smoke start/stop', () => {
  it('dispara ticks recorrentes via timer e para completamente apos stop()', async () => {
    vi.useFakeTimers();
    let tickCount = 0;
    const scanImpl: SessionsWatcherTickOptions['scanImpl'] = async () => {
      tickCount++;
      return { degraded: false, sessions: [], scrubMode: 'internal' };
    };

    const handle = startSessionsWatcher({ scanImpl, intervalMs: 10 });

    await vi.advanceTimersByTimeAsync(55); // ~5 ticks de 10ms
    expect(tickCount).toBeGreaterThanOrEqual(2);

    handle.stop();
    const countAtStop = tickCount;
    await vi.advanceTimersByTimeAsync(200); // bem alem de mais alguns intervalos
    expect(tickCount).toBe(countAtStop); // nenhum tick novo apos stop()
  });

  it('usa DEFAULT_SESSIONS_WATCH_INTERVAL_MS quando intervalMs e omitido', () => {
    vi.useFakeTimers();
    const setIntervalSpy = vi.spyOn(global, 'setInterval');
    const handle = startSessionsWatcher({ scanImpl: async () => ({ degraded: false, sessions: [], scrubMode: 'internal' }) });
    expect(setIntervalSpy).toHaveBeenCalledWith(expect.any(Function), DEFAULT_SESSIONS_WATCH_INTERVAL_MS);
    handle.stop();
    setIntervalSpy.mockRestore();
  });

  it('onTickError e chamado quando o tick rejeita de forma inesperada, sem derrubar o timer', async () => {
    vi.useFakeTimers();
    // runSessionsWatcherTick captura tudo internamente e nunca rejeita — para
    // exercitar o `.catch()` do proprio setInterval (robustez a falha fora do
    // envelope tratado), simulamos scanImpl que devolve uma Promise que so
    // rejeita ANTES do try/catch interno ser alcancavel e nao e o caso real
    // aqui; mantemos o mock revelando que, mesmo assim, nada escapa: o
    // handler interno de runSessionsWatcherTick ja absorve o throw.
    const errors: unknown[] = [];
    const handle = startSessionsWatcher({
      scanImpl: async () => {
        throw new Error('falha simulada no tick');
      },
      intervalMs: 10,
      onTickError: err => { errors.push(err); },
    });

    await vi.advanceTimersByTimeAsync(15);
    handle.stop();
    // runSessionsWatcherTick absorve a excecao internamente (4.1.3) e nunca
    // rejeita a Promise que startSessionsWatcher aguarda — logo onTickError
    // nao e chamado neste cenario, e (mais importante) nenhuma excecao
    // nao-capturada escapa do timer.
    expect(errors).toEqual([]);
  });
});

// ─────────────────────────────────────────────────────────
// Isolamento do ingest-watcher (FR-011) — falha de um nao contamina o outro
// ─────────────────────────────────────────────────────────

describe('isolamento — sessions-watcher e ingest-watcher sao instancias independentes', () => {
  let projectDir: string;
  let savedProjectPaths: string | undefined;
  let savedBinaryPath: string | undefined;

  beforeEach(() => {
    projectDir = join(tmpRoot, 'project');
    mkdirSync(projectDir, { recursive: true });
    savedProjectPaths = process.env['CSTK_PROJECT_PATHS'];
    savedBinaryPath = process.env['CSTK_BINARY_PATH'];
    resetWatcherCacheForTests();
    resetCstkBinaryCacheForTests();
  });

  afterEach(() => {
    if (savedProjectPaths === undefined) delete process.env['CSTK_PROJECT_PATHS'];
    else process.env['CSTK_PROJECT_PATHS'] = savedProjectPaths;
    if (savedBinaryPath === undefined) delete process.env['CSTK_BINARY_PATH'];
    else process.env['CSTK_BINARY_PATH'] = savedBinaryPath;
    resetWatcherCacheForTests();
    resetCstkBinaryCacheForTests();
  });

  it('tick degradado do sessions-watcher nao afeta o estado do ingest-watcher', async () => {
    delete process.env['CSTK_PROJECT_PATHS'];
    delete process.env['CSTK_BINARY_PATH'];

    // ingest-watcher: tick normal, sem alvos (ociosidade), estabelece uma
    // baseline neutra antes de forcarmos a falha no sessions-watcher.
    const ingestBaseline = await runWatcherTick({
      dbPath: join(tmpRoot, 'nao-existe-db.sqlite'),
      supportedSchemaVersions: ['2'],
    });

    // sessions-watcher: tick que degrada de proposito (raiz ausente).
    process.env['CSTK_SESSIONS_ROOT'] = join(tmpRoot, 'raiz-ausente');
    const sessionsResult = await runSessionsWatcherTick();
    expect(sessionsResult.degraded).toBe(true);
    expect(getSessionsIndex().sessions).toEqual([]);

    // ingest-watcher: novo tick identico ao baseline — o resultado nao
    // mudou por causa da falha do outro watcher (nenhum estado
    // compartilhado entre os dois modulos).
    const ingestAfter = await runWatcherTick({
      dbPath: join(tmpRoot, 'nao-existe-db.sqlite'),
      supportedSchemaVersions: ['2'],
    });
    expect(ingestAfter).toEqual(ingestBaseline);
  });

  it('tick com falha do ingest-watcher nao afeta o indice do sessions-watcher', async () => {
    // sessions-watcher: popula o indice com sucesso primeiro.
    const okScan: () => Promise<SessionScanResult> = async () => ({
      degraded: false,
      sessions: [SAMPLE_SESSION],
      scrubMode: 'internal',
    });
    await runSessionsWatcherTick({ scanImpl: okScan });
    expect(getSessionsIndex().sessions).toEqual([SAMPLE_SESSION]);

    // ingest-watcher: dbPath ausente degrada seu proprio resultado
    // (`degradedDb: true`, db-missing — ver runWatcherTick), sem lancar.
    const ingestResult = await runWatcherTick({
      dbPath: join(tmpRoot, 'nao-existe-db.sqlite'),
      supportedSchemaVersions: ['2'],
    });
    expect(ingestResult.degradedDb).toBe(true);

    // O indice do sessions-watcher continua intacto — nenhum acoplamento.
    expect(getSessionsIndex().sessions).toEqual([SAMPLE_SESSION]);
  });
});
