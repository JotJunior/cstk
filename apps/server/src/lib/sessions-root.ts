/**
 * Guard de confinamento de path para leitura de sessoes do harness Claude
 * Code (`~/.claude/projects`).
 * Ref: plan.md §Project Structure (apps/server/src/lib), research.md
 * Decision 5, contracts/sessions-api.md "Guard de path (obrigatorio)",
 * tasks.md FASE 2 (2.1).
 *
 * Modelo do guard existente `project-root.ts` (raiz unica + `realpathSync`
 * + rejeicao de escape), **sem reutiliza-lo**: aquele guard lista
 * `~/.claude` como zona PROIBIDA (dec-024) — reusa-lo aqui rejeitaria 100%
 * das sessoes. Este guard e mais ESTREITO (raiz unica confinada em
 * `~/.claude/projects`), nao um afrouxamento do guard existente.
 *
 * Tres invariantes de seguranca cobertos (CHK015/CHK016/CHK017/CHK018):
 *   1. `sessionId` e SEMPRE validado como UUID via Zod ANTES de qualquer
 *      path-join — uma string arbitraria nunca alcanca `realpathSync`.
 *   2. Apos o path-join, `realpathSync` resolve o candidato e a raiz; o
 *      resultado MUST permanecer sob a raiz (rejeita `..` e symlink que
 *      escape).
 *   3. A leitura do arquivo ja confinado usa um UNICO `fd` (open -> fstat
 *      -> read -> close), nunca `existsSync` seguido de `readFileSync` em
 *      chamadas separadas (janela de TOCTOU entre checagem e leitura).
 *
 * A resolucao de QUAL `projectSlug`/arquivo corresponde a um `sessionId` e
 * responsabilidade do indice em memoria do watcher (`getSessionsIndex()`,
 * task 0.1/2.2) — este modulo NUNCA reconstroi esse mapeamento a partir de
 * dado de cliente; ele apenas guarda a etapa final de confinamento e leitura
 * do path ja resolvido pelo indice (defesa em profundidade complementar,
 * research.md Decision 7 — nenhum dos dois controles substitui o outro).
 */
import {
  realpathSync,
  statSync,
  openSync,
  fstatSync,
  readFileSync,
  closeSync,
} from 'node:fs';
import { homedir } from 'node:os';
import { join, sep } from 'node:path';
import { z } from 'zod';

const DEFAULT_SESSIONS_ROOT = join(homedir(), '.claude', 'projects');

const SESSION_ID_SCHEMA = z.string().uuid();

/**
 * Normaliza caixa do `sessionId` (CHK018) — o filesystem local pode ser
 * case-insensitive (macOS/Windows por default) e o nome de arquivo no disco
 * e sempre gravado em minusculas pelo harness. Normalizar ANTES de validar
 * e ANTES do path-join garante que `sessionId` em caixa mista resolva ao
 * mesmo arquivo que a forma canonica.
 */
export function normalizeSessionId(raw: string): string {
  return raw.trim().toLowerCase();
}

/**
 * Valida `sessionId` como UUID via Zod — MUST rodar antes de qualquer
 * path-join (CHK016). Aceita qualquer caixa (normaliza internamente antes
 * de validar); rejeita qualquer outra coisa, inclusive strings contendo
 * `..`, `/`, `\0` etc. — essas nunca chegam perto de `realpathSync`.
 */
export function isValidSessionId(raw: unknown): raw is string {
  if (typeof raw !== 'string' || raw.trim() === '') return false;
  return SESSION_ID_SCHEMA.safeParse(normalizeSessionId(raw)).success;
}

/**
 * Resolve a raiz confinada de sessoes. Ordem de resolucao (mesma familia de
 * `resolveDbPath`/`resolveWebDir` em config.ts): `CSTK_SESSIONS_ROOT`
 * (config do servidor, NUNCA do cliente) > default `~/.claude/projects`.
 * `realpathSync` resolve symlinks; raiz ausente/nao-diretorio/ilegivel ->
 * `null` (Principio II — nunca lanca).
 */
export function resolveSessionsRoot(): string | null {
  const fromEnv = process.env['CSTK_SESSIONS_ROOT'];
  const candidate = fromEnv && fromEnv.trim() !== '' ? fromEnv.trim() : DEFAULT_SESSIONS_ROOT;
  try {
    const resolved = realpathSync(candidate);
    if (!statSync(resolved).isDirectory()) return null;
    return resolved;
  } catch {
    return null;
  }
}

/** `resolved` permanece sob `root` (identico ou subdiretorio)? Ambos ja
 *  devem vir canonicalizados (pos-`realpathSync`) — comparacao de string
 *  pura, sem I/O adicional. */
function isUnderRoot(resolved: string, root: string): boolean {
  return resolved === root || resolved.startsWith(root + sep);
}

/**
 * Resolve com seguranca o path do arquivo `.jsonl` de uma sessao, confinado
 * sob `root` (retorno de `resolveSessionsRoot()`, ja canonicalizado).
 *
 * `projectSlug` e `sessionId` sao tratados como UNTRUSTED (vem, em ultima
 * instancia, de requisicao HTTP). Ordem MUST:
 *   1. validar `sessionId` como UUID (rejeita ANTES de montar qualquer path);
 *   2. normalizar caixa;
 *   3. montar o candidato sob `root`;
 *   4. `realpathSync` do candidato — rejeita se nao existir, se `..`/symlink
 *      escapar da raiz, ou qualquer outra falha de resolucao.
 *
 * Retorna o path absoluto canonicalizado ou `null` (nunca lanca —
 * Principio II; o chamador mapeia `null` para o `DegradedReason` adequado:
 * `session-rejected` para UUID invalido/escape, `session-not-found` para
 * arquivo ausente).
 */
export function resolveConfinedSessionPath(
  root: string,
  projectSlug: string,
  sessionId: string
): string | null {
  if (!isValidSessionId(sessionId)) return null; // CHK016 — antes do path-join
  if (typeof projectSlug !== 'string' || projectSlug.trim() === '') return null;

  const normalizedId = normalizeSessionId(sessionId);
  const candidate = join(root, projectSlug, `${normalizedId}.jsonl`);

  try {
    const resolvedRoot = realpathSync(root);
    const resolvedCandidate = realpathSync(candidate);
    if (!isUnderRoot(resolvedCandidate, resolvedRoot)) return null; // escape via .. ou symlink
    if (!statSync(resolvedCandidate).isFile()) return null;
    return resolvedCandidate;
  } catch {
    return null;
  }
}

/**
 * Le o conteudo de um arquivo de sessao JA CONFINADO (path retornado por
 * `resolveConfinedSessionPath`) em uma UNICA operacao de abertura (CHK017):
 * `openSync` -> `fstatSync` (no mesmo `fd`) -> `readFileSync` (no mesmo
 * `fd`) -> `closeSync`. Nunca `existsSync` seguido de `readFileSync` em
 * chamadas separadas — essa dupla checagem abriria uma janela de TOCTOU
 * entre a confirmacao de existencia/confinamento e a leitura real (o
 * arquivo poderia ser substituido por um symlink entre as duas chamadas).
 * Retorna `null` em qualquer falha (Principio II — nunca lanca).
 */
export function readConfinedSessionFile(confinedPath: string): Buffer | null {
  let fd: number | undefined;
  try {
    fd = openSync(confinedPath, 'r');
    const stat = fstatSync(fd);
    if (!stat.isFile()) return null;
    return readFileSync(fd);
  } catch {
    return null;
  } finally {
    if (fd !== undefined) {
      try {
        closeSync(fd);
      } catch {
        /* noop — fd ja pode ter sido fechado ou nunca aberto */
      }
    }
  }
}
