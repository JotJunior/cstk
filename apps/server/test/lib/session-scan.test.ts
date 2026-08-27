/**
 * Testes de descoberta e liveness (lib/session-scan.ts).
 * Ref: tasks.md FASE 2 (2.2.4), FASE 3 (3.4.2), research.md Decisions 1/4/6.
 *
 * Cobertura exigida por 2.2.4: raiz ausente, raiz vazia (nao-degradada),
 * raiz com sessoes viva/nao-viva conforme a janela.
 *
 * Cobertura exigida por 3.4.2 (superficie coberta por origem do dado, nao
 * por rota): fixture com segredo embutido em `.cwd` (que vira
 * `projectPath`) confirmando que o scrub tambem roda na rota de listagem,
 * nao so em `entries[].text` da rota de tail.
 *
 * `scanSessions` e async desde a task 3.4 (o scrub de `projectPath`/
 * `projectSlug` pode invocar um subprocesso) — todo `it` que a chama e
 * `async`, e toda chamada e `await`ada. `CSTK_SECRETS_FILTER` e forcado
 * para um path inexistente em `beforeEach` para que a suite nunca
 * dependa do `secrets-filter.sh` real da maquina (determinismo entre
 * ambientes, `scrubMode: 'internal'` sempre neste arquivo).
 */
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync, realpathSync, utimesSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { scanSessions } from '../../src/lib/session-scan.js';
import { resetSecretsFilterAvailabilityForTests } from '../../src/lib/secret-scrub.js';

const VALID_UUID_1 = '5f3c2e10-71a4-4b8e-9c1a-2d6f8b0a9e11';
const VALID_UUID_2 = '9a1b2c3d-4e5f-4a6b-8c7d-1234567890ab';

let base: string;
let root: string;
let savedRoot: string | undefined;
let savedWindow: string | undefined;
let savedSecretsFilter: string | undefined;

beforeEach(() => {
  base = mkdtempSync(join(realpathSync(tmpdir()), 'session-scan-'));
  root = join(base, 'projects');
  mkdirSync(root);
  savedRoot = process.env['CSTK_SESSIONS_ROOT'];
  savedWindow = process.env['CSTK_SESSION_LIVE_WINDOW_MS'];
  savedSecretsFilter = process.env['CSTK_SECRETS_FILTER'];
  process.env['CSTK_SESSIONS_ROOT'] = root;
  // Determinismo: nunca depender do secrets-filter.sh real da maquina de
  // dev/CI — forca scrubMode: 'internal' em toda a suite (3.2.2).
  process.env['CSTK_SECRETS_FILTER'] = '/caminho/que/nao/existe/secrets-filter.sh';
  resetSecretsFilterAvailabilityForTests();
});

afterEach(() => {
  rmSync(base, { recursive: true, force: true });
  if (savedRoot === undefined) delete process.env['CSTK_SESSIONS_ROOT'];
  else process.env['CSTK_SESSIONS_ROOT'] = savedRoot;
  if (savedWindow === undefined) delete process.env['CSTK_SESSION_LIVE_WINDOW_MS'];
  else process.env['CSTK_SESSION_LIVE_WINDOW_MS'] = savedWindow;
  if (savedSecretsFilter === undefined) delete process.env['CSTK_SECRETS_FILTER'];
  else process.env['CSTK_SECRETS_FILTER'] = savedSecretsFilter;
  resetSecretsFilterAvailabilityForTests();
});

function writeSession(slug: string, sessionId: string, lines: string[], mtimeMs: number): string {
  const slugDir = join(root, slug);
  mkdirSync(slugDir, { recursive: true });
  const filePath = join(slugDir, `${sessionId}.jsonl`);
  writeFileSync(filePath, lines.map((l) => `${l}\n`).join(''));
  const seconds = mtimeMs / 1000;
  utimesSync(filePath, seconds, seconds);
  return filePath;
}

describe('scanSessions — raiz ausente/ilegivel (FR-008, 2.2.3)', () => {
  it('raiz ausente -> degraded sessions-root-missing (nunca lanca)', async () => {
    process.env['CSTK_SESSIONS_ROOT'] = join(base, 'nao-existe');
    const result = await scanSessions();
    expect(result).toEqual({ degraded: true, reason: 'sessions-root-missing' });
  });

  it('raiz aponta para arquivo (nao-diretorio) -> degraded sessions-root-missing', async () => {
    const file = join(base, 'arquivo.txt');
    writeFileSync(file, 'x');
    process.env['CSTK_SESSIONS_ROOT'] = file;
    const result = await scanSessions();
    expect(result).toEqual({ degraded: true, reason: 'sessions-root-missing' });
  });
});

describe('scanSessions — raiz vazia (2.2.3 / distincao Principio II)', () => {
  it('raiz existe e vazia -> NAO-degradada, sessions: []', async () => {
    const result = await scanSessions();
    expect(result).toEqual({ degraded: false, sessions: [] });
  });
});

describe('scanSessions — liveness conforme a janela (Decision 6, FR-007)', () => {
  it('sessao com atividade recente -> live: true; sessao antiga -> live: false', async () => {
    process.env['CSTK_SESSION_LIVE_WINDOW_MS'] = '300000'; // 5 min
    const now = Date.now();
    writeSession('meu-projeto', VALID_UUID_1, ['{"cwd":"/tmp/proj-a","sessionId":"' + VALID_UUID_1 + '"}'], now);
    writeSession(
      'meu-projeto',
      VALID_UUID_2,
      ['{"cwd":"/tmp/proj-b","sessionId":"' + VALID_UUID_2 + '"}'],
      now - 10 * 60 * 1000 // 10 min atras — fora da janela de 5 min
    );

    const result = await scanSessions();
    expect(result.degraded).toBe(false);
    if (result.degraded) throw new Error('unreachable');
    const bySessionId = new Map(result.sessions.map((s) => [s.sessionId, s]));
    expect(bySessionId.get(VALID_UUID_1)?.live).toBe(true);
    expect(bySessionId.get(VALID_UUID_2)?.live).toBe(false);
  });

  it('janela CSTK_SESSION_LIVE_WINDOW_MS=1 -> nenhuma sessao e vivo (Scenario 2 do quickstart)', async () => {
    process.env['CSTK_SESSION_LIVE_WINDOW_MS'] = '1';
    // mtime deliberadamente 100ms no passado — com janela de 1ms, execucao
    // sincrona no MESMO milissegundo do write daria falso-positivo de "vivo"
    // (diff 0 <= 1); um passado inequivoco torna a asserção nao-flaky.
    writeSession('meu-projeto', VALID_UUID_1, ['{"cwd":"/tmp/proj-a"}'], Date.now() - 100);

    const result = await scanSessions();
    expect(result.degraded).toBe(false);
    if (result.degraded) throw new Error('unreachable');
    expect(result.sessions.every((s) => s.live === false)).toBe(true);
  });
});

describe('scanSessions — metadados derivados (SessionSummaryDTO)', () => {
  it('deriva sessionId, projectPath (primeiro cwd), projectSlug, sizeBytes', async () => {
    const lines = [
      '{"type":"system","cwd":"/Users/jot/projeto-a","sessionId":"' + VALID_UUID_1 + '"}',
      '{"type":"user","cwd":"/Users/jot/projeto-a/sub","sessionId":"' + VALID_UUID_1 + '"}',
    ];
    writeSession('slug-do-projeto', VALID_UUID_1, lines, Date.now());

    const result = await scanSessions();
    expect(result.degraded).toBe(false);
    if (result.degraded) throw new Error('unreachable');
    expect(result.sessions).toHaveLength(1);
    const s = result.sessions[0]!;
    expect(s.sessionId).toBe(VALID_UUID_1);
    expect(s.projectPath).toBe('/Users/jot/projeto-a'); // primeira ocorrencia, nao a ultima (Decision 4)
    expect(s.projectSlug).toBe('slug-do-projeto');
    expect(s.sizeBytes).toBeGreaterThan(0);
  });

  it('sessionId em caixa mista no nome do arquivo e normalizado (CHK018)', async () => {
    writeSession('slug', VALID_UUID_1.toUpperCase(), ['{"cwd":"/tmp/x"}'], Date.now());
    const result = await scanSessions();
    expect(result.degraded).toBe(false);
    if (result.degraded) throw new Error('unreachable');
    expect(result.sessions[0]?.sessionId).toBe(VALID_UUID_1);
  });

  it('nenhuma linha traz cwd -> projectPath: null', async () => {
    writeSession('slug', VALID_UUID_1, ['{"type":"system"}'], Date.now());
    const result = await scanSessions();
    expect(result.degraded).toBe(false);
    if (result.degraded) throw new Error('unreachable');
    expect(result.sessions[0]?.projectPath).toBeNull();
  });

  it('linha malformada antes do cwd e pulada, nao aborta a extracao (mesmo espirito de FR-003a)', async () => {
    writeSession('slug', VALID_UUID_1, ['{"type":"user",', '{"cwd":"/tmp/valido"}'], Date.now());
    const result = await scanSessions();
    expect(result.degraded).toBe(false);
    if (result.degraded) throw new Error('unreachable');
    expect(result.sessions[0]?.projectPath).toBe('/tmp/valido');
  });

  it('arquivo cujo nome nao e UUID valido e ignorado (defesa em profundidade)', async () => {
    const slugDir = join(root, 'slug');
    mkdirSync(slugDir, { recursive: true });
    writeFileSync(join(slugDir, 'nao-e-uuid.jsonl'), '{}\n');
    writeFileSync(join(slugDir, `${VALID_UUID_1}.txt`), '{}\n'); // extensao errada

    const result = await scanSessions();
    expect(result.degraded).toBe(false);
    if (result.degraded) throw new Error('unreachable');
    expect(result.sessions).toHaveLength(0);
  });

  it('entrada nao-diretorio na raiz e ignorada', async () => {
    writeFileSync(join(root, 'arquivo-solto.txt'), 'x');
    writeSession('slug-valido', VALID_UUID_1, ['{"cwd":"/tmp/x"}'], Date.now());

    const result = await scanSessions();
    expect(result.degraded).toBe(false);
    if (result.degraded) throw new Error('unreachable');
    expect(result.sessions).toHaveLength(1);
  });
});

describe('scanSessions — scrub de projectPath/projectSlug (task 3.4, plan.md §Superficie coberta)', () => {
  it('segredo embutido em .cwd (rota de listagem) tambem passa pelo scrub, nao so entries[].text da rota de tail', async () => {
    writeSession(
      'slug-valido',
      VALID_UUID_1,
      ['{"cwd":"/Users/jot/projetos/password=hunter2-listing-secret"}'],
      Date.now()
    );

    const result = await scanSessions();
    expect(result.degraded).toBe(false);
    if (result.degraded) throw new Error('unreachable');
    expect(result.sessions).toHaveLength(1);
    const s = result.sessions[0]!;
    expect(s.projectPath).not.toContain('hunter2-listing-secret');
    expect(s.projectPath).toContain('[REDACTED]');
  });

  it('projectPath null (sem cwd) nao entra no lote de scrub e continua null', async () => {
    writeSession('slug', VALID_UUID_1, ['{"type":"system"}'], Date.now());
    const result = await scanSessions();
    expect(result.degraded).toBe(false);
    if (result.degraded) throw new Error('unreachable');
    expect(result.sessions[0]?.projectPath).toBeNull();
  });
});
