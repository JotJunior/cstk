/**
 * Task 5.1.3 (docs/specs/human-bridge/tasks.md FASE 5, Cenario 10 do
 * quickstart) — verificacao AUTOMATIZADA de que o afrouxamento de
 * `panel/scripts/readonly-check.sh` (task 3.1.9) esta no MESMO commit git
 * do PRIMEIRO codigo de `apps/server/src/routes/bridge.ts` — nem antes,
 * nem depois.
 *
 * Ref: `panel/apps/server/src/db/bridge.ts` (comentario de topo, "achado
 * registrado como Decisao na onda-008"): o gate de read-only ficaria mais
 * permissivo (`CREATE TABLE`/`CREATE INDEX` deixariam de reprovar fora de
 * `db/queries/**`) exatamente no commit que introduz a Ponte de
 * intervencao humana — "o estreitamento do escopo do gate ... MUST
 * acontecer no MESMO commit de `routes/bridge.ts` ... nunca antes". Uma
 * verificacao MANUAL confirmou isso (`cbe96e3`), mas nao havia checagem
 * automatizada que falhasse se um refactor futuro (ex.: cherry-pick,
 * squash malfeito) viesse a separar as duas mudancas em commits distintos.
 *
 * Isto e um teste de HISTORICO DE GIT (imutavel apos o merge): uma vez
 * verdadeiro, permanece verdadeiro para sempre — serve como documentacao
 * viva + rede de seguranca contra reescrita de historico (rebase/squash)
 * que separe as duas mudancas sem que ninguem perceba.
 */
import { describe, it, expect } from 'vitest';
import { execFileSync } from 'node:child_process';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
// test/lib -> apps/server -> apps -> panel -> <repo root>
const REPO_ROOT = join(HERE, '..', '..', '..', '..', '..');
const BRIDGE_ROUTE_PATH = 'panel/apps/server/src/routes/bridge.ts';
const READONLY_CHECK_PATH = 'panel/scripts/readonly-check.sh';

function isGitAvailable(): boolean {
  try {
    execFileSync('git', ['-C', REPO_ROOT, 'rev-parse', '--is-inside-work-tree'], {
      encoding: 'utf8',
    });
    return true;
  } catch {
    return false;
  }
}

const gitAvailable = isGitAvailable();

describe.skipIf(!gitAvailable)(
  '5.1.3 Cenario 10 — gate de read-only e o commit unico (Principio I do painel)',
  () => {
    it('o commit que PRIMEIRO adiciona routes/bridge.ts TAMBEM toca readonly-check.sh (nem antes, nem depois)', () => {
      // Todos os commits que ADICIONARAM o arquivo (--diff-filter=A), do
      // mais antigo para o mais novo. Em uso normal so ha 1; se o arquivo
      // foi removido e recriado alguma vez, o PRIMEIRO (mais antigo) e o
      // que importa para este cenario ("o primeiro codigo de bridge/").
      const addCommitsRaw = execFileSync(
        'git',
        ['-C', REPO_ROOT, 'log', '--diff-filter=A', '--format=%H', '--', BRIDGE_ROUTE_PATH],
        { encoding: 'utf8' },
      ).trim();
      const addCommits = addCommitsRaw.length > 0 ? addCommitsRaw.split('\n') : [];

      expect(
        addCommits.length,
        `esperava >=1 commit adicionando ${BRIDGE_ROUTE_PATH}, encontrei ${addCommits.length}`,
      ).toBeGreaterThanOrEqual(1);

      // `git log` lista do mais novo para o mais antigo — o ultimo item e o
      // mais antigo, ou seja, o commit do "primeiro codigo de bridge/".
      const firstBridgeCommit = addCommits[addCommits.length - 1];
      expect(firstBridgeCommit).toBeTruthy();

      const changedFiles = execFileSync(
        'git',
        ['-C', REPO_ROOT, 'show', '--name-only', '--format=', firstBridgeCommit as string],
        { encoding: 'utf8' },
      )
        .trim()
        .split('\n')
        .filter((line) => line.length > 0);

      expect(
        changedFiles,
        `o commit ${String(firstBridgeCommit)} que introduz ${BRIDGE_ROUTE_PATH} nao toca ${READONLY_CHECK_PATH} — ` +
          `o afrouxamento do gate de read-only precisa estar no MESMO commit do primeiro codigo da Ponte ` +
          `(panel/docs/constitution.md Sync Impact Report da emenda 2026-08-26)`,
      ).toContain(READONLY_CHECK_PATH);

      expect(changedFiles).toContain(BRIDGE_ROUTE_PATH);
    });

    it('o diff de readonly-check.sh NESSE commit e de fato o estreitamento de escopo p/ db/queries/** (nao um toque incidental)', () => {
      const firstBridgeCommit = execFileSync(
        'git',
        ['-C', REPO_ROOT, 'log', '--diff-filter=A', '--format=%H', '--', BRIDGE_ROUTE_PATH],
        { encoding: 'utf8' },
      )
        .trim()
        .split('\n')
        .filter((l) => l.length > 0)
        .pop();
      expect(firstBridgeCommit).toBeTruthy();

      // `git show` do arquivo, so linhas ADICIONADAS (`+`) no patch —
      // confirma que a mudanca de fato introduz o escopo restrito
      // `db/queries` (o estreitamento descrito no comentario de
      // `db/bridge.ts`), nao apenas um toque incidental/nao relacionado no
      // mesmo commit.
      const patch = execFileSync(
        'git',
        ['-C', REPO_ROOT, 'show', firstBridgeCommit as string, '--', READONLY_CHECK_PATH],
        { encoding: 'utf8' },
      );
      const addedLines = patch
        .split('\n')
        .filter((line) => line.startsWith('+') && !line.startsWith('+++'))
        .join('\n');

      expect(
        addedLines,
        `o diff de ${READONLY_CHECK_PATH} no commit ${String(firstBridgeCommit)} nao contem ` +
          `'db/queries' nas linhas adicionadas — nao parece ser o estreitamento de escopo esperado`,
      ).toContain('db/queries');
    });
  },
);
