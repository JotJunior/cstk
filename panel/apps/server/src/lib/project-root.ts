/**
 * Resolucao do caminho raiz de um projeto observavel (FR-008 + follow-up
 * zero-config via knowledge.db v9).
 *
 * Cadeia de precedencia:
 *   1. CSTK_PROJECT_PATHS (config explicita do operador — SEMPRE vence)
 *   2. executions.target_project_path da knowledge.db (coluna aditiva do
 *      schema v9, cstk >= 5.19: o ingest persiste o
 *      `.execution.target_project_path` do state.json)
 *   3. null → consumidores degradam graciosamente (FR-012), identico ao
 *      comportamento pre-v9.
 *
 * O valor vindo da db e conteudo UNTRUSTED (Principio V — foi gravado a
 * partir de state.json escrito por execucoes de agentes). Antes de usar:
 * canonicaliza via realpath (resolve symlinks), exige diretorio existente
 * e rejeita zonas sensiveis do sistema (mesma lista do path-guard do
 * toolkit). NUNCA lanca (Principio II); qualquer falha vira null.
 */
import { realpathSync, statSync } from 'node:fs';
import { homedir, tmpdir } from 'node:os';
import { sep } from 'node:path';
import type Database from 'better-sqlite3';
import { resolveProjectPath } from '../config.js';
import { hasColumn } from '../db/columns.js';

const HOME = homedir();

/** Zonas proibidas para raiz de projeto — espelha o validate-target do
 *  path-guard do toolkit (agente-00c-runtime): `/`, /etc, /usr, /var,
 *  ~/.claude, ~/.ssh, ~/.config, ~/.aws, ~/.docker, ~/Library, ~/.gnupg. */
const FORBIDDEN_ZONES: readonly string[] = [
  '/etc',
  '/usr',
  '/var',
  `${HOME}${sep}.claude`,
  `${HOME}${sep}.ssh`,
  `${HOME}${sep}.config`,
  `${HOME}${sep}.aws`,
  `${HOME}${sep}.docker`,
  `${HOME}${sep}Library`,
  `${HOME}${sep}.gnupg`,
];

/** Cada zona + sua forma canonicalizada (no macOS, /etc e /var sao symlinks
 *  para /private/etc e /private/var — sem isso, um valor malicioso escaparia
 *  da denylist apos o realpath do candidato). Computado uma vez na carga. */
function zoneVariants(zone: string): string[] {
  try {
    const real = realpathSync(zone);
    return real === zone ? [zone] : [zone, real];
  } catch {
    return [zone]; // zona inexistente nesta maquina — mantem a forma literal
  }
}
const FORBIDDEN_ZONES_RESOLVED: readonly string[] = FORBIDDEN_ZONES.flatMap(zoneVariants);

/** Excecao: o tempdir do SO nao e zona sensivel, mas no macOS vive DENTRO de
 *  uma (/var/folders → /private/var/folders). Sem a excecao, qualquer projeto
 *  em diretorio temporario (fixtures de teste, smoke local) seria rejeitado. */
const TMP_ROOT: string | null = (() => {
  try {
    return realpathSync(tmpdir());
  } catch {
    return null;
  }
})();

function isForbiddenZone(resolved: string): boolean {
  if (resolved === '/') return true;
  if (
    TMP_ROOT !== null &&
    (resolved === TMP_ROOT || resolved.startsWith(TMP_ROOT + sep))
  ) {
    return false;
  }
  return FORBIDDEN_ZONES_RESOLVED.some(
    zone => resolved === zone || resolved.startsWith(zone + sep)
  );
}

/**
 * Valida um caminho de raiz de projeto vindo de fonte UNTRUSTED (a
 * knowledge.db). Retorna o caminho canonicalizado (realpath) quando e um
 * diretorio existente fora das zonas proibidas; null caso contrario.
 * Exportada isoladamente para o watcher, que carrega o valor bruto na
 * propria linha de `listExecutionsForWatcher` (a conexao com a db ja foi
 * fechada quando a validacao acontece).
 */
export function validateProjectRootPath(raw: unknown): string | null {
  if (typeof raw !== 'string' || raw.trim() === '') return null;
  try {
    const resolved = realpathSync(raw.trim());
    if (!statSync(resolved).isDirectory()) return null;
    if (isForbiddenZone(resolved)) return null;
    return resolved;
  } catch {
    return null;
  }
}

/**
 * Le o target_project_path da execucao mais recente do projeto na
 * knowledge.db. Tolerante a coluna ausente (db v8 de cstk antigo →
 * hasColumn false → null, mesmo contrato aditivo de db/columns.ts).
 */
export function dbTargetProjectPath(
  db: Database.Database,
  project: string
): string | null {
  try {
    if (!hasColumn(db, 'executions', 'target_project_path')) return null;
    const row = db
      .prepare(
        `SELECT target_project_path AS p
         FROM executions
         WHERE project = ?
           AND target_project_path IS NOT NULL
           AND TRIM(target_project_path) != ''
         ORDER BY started_at DESC, id DESC
         LIMIT 1`
      )
      .get(project) as { p: string } | undefined;
    return row === undefined ? null : validateProjectRootPath(row.p);
  } catch {
    return null;
  }
}

/**
 * Cadeia completa: config do operador (CSTK_PROJECT_PATHS) > knowledge.db
 * (validada) > null. `db` null (falha de abertura/schema-mismatch) degrada
 * para o comportamento pre-v9 (so env).
 */
export function resolveProjectRoot(
  db: Database.Database | null,
  project: string
): string | null {
  const fromEnv = resolveProjectPath(project);
  if (fromEnv !== null) return fromEnv;
  if (db === null) return null;
  return dbTargetProjectPath(db, project);
}
