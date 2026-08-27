/**
 * Descoberta de sessoes do Claude Code + calculo de liveness (task 2.2).
 * Ref: plan.md §Project Structure (apps/server/src/lib), research.md
 * Decisions 1, 4, 6, contracts/sessions-api.md, tasks.md FASE 2 (2.2).
 *
 * `readdirSync` + `statSync` sobre a raiz confinada de sessoes
 * (`resolveSessionsRootCandidate()` de `sessions-root.ts`), sem abrir a
 * `knowledge.db` (FR-001, FR-011 — pattern do watcher existente, instancia
 * separada; Decision 1 do research.md: a `knowledge.db` nao indexa sessoes).
 *
 * Nunca lanca (Principio II — Degradar, Nunca Quebrar): raiz ausente vira
 * `{ degraded: true, reason: 'sessions-root-missing' }`; raiz presente mas
 * ilegivel (readdir falha por permissao) vira `sessions-root-unreadable`;
 * raiz vazia vira `{ degraded: false, sessions: [] }` — distincao exigida
 * por FR-008 e pelo Constitution Check Principio II (2.2.3).
 *
 * A resolucao de QUAL `sessionId`/path corresponde a uma sessao para fins de
 * ROTEAMENTO (`GET /sessions/:sessionId/tail`) permanece responsabilidade do
 * indice em memoria do watcher (task 0.1/FASE 4) que consome este modulo —
 * este arquivo apenas produz os metadados brutos por ciclo de varredura.
 */
import {
  closeSync,
  existsSync,
  openSync,
  readdirSync,
  readSync,
  realpathSync,
  statSync,
  type Dirent,
} from 'node:fs';
import { join } from 'node:path';
import type { SessionSummaryDTO } from '@cstk-panel/shared-types';
import { isValidSessionId, normalizeSessionId, resolveSessionsRootCandidate } from './sessions-root.js';

/** Janela de liveness (Decision 6, SC-004) — 5 minutos. */
export const DEFAULT_LIVE_WINDOW_MS = 300_000;

/**
 * Teto de linhas varridas em busca do primeiro `cwd` (Decision 4 do
 * research.md): evidencia empirica (amostra de 40 arquivos reais) mostra
 * `cwd` presente dentro das 50 primeiras linhas em 100% dos casos.
 */
const CWD_SCAN_MAX_LINES = 50;

/**
 * Teto de BYTES lidos do inicio do arquivo ao procurar o `cwd` — protecao
 * defensiva adicional (nao extraida de amostra, mas decisao de engenharia
 * dentro do orcamento ja fixado por Decision 8/9 do research.md: nunca ler o
 * arquivo inteiro por sessao). 64 KiB cobre 50 linhas de JSON de sobra sem
 * risco de uma primeira linha patologicamente grande custar I/O relevante.
 */
const CWD_SCAN_MAX_BYTES = 65_536;

export type SessionScanReason = 'sessions-root-missing' | 'sessions-root-unreadable';

export type SessionScanResult =
  | { degraded: false; sessions: SessionSummaryDTO[] }
  | { degraded: true; reason: SessionScanReason };

function resolveLiveWindowMs(): number {
  const raw = process.env['CSTK_SESSION_LIVE_WINDOW_MS'];
  if (raw === undefined || raw.trim() === '') return DEFAULT_LIVE_WINDOW_MS;
  const parsed = Number(raw);
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : DEFAULT_LIVE_WINDOW_MS;
}

/**
 * Le apenas o INICIO do arquivo (nunca o arquivo inteiro — Decision 8) em
 * busca da primeira linha parseavel que carregue `.cwd` (Decision 4: primeira
 * ocorrencia, nao a ultima). Retorna `null` em qualquer falha ou ausencia —
 * nunca lanca (Principio II).
 */
function extractFirstCwd(filePath: string): string | null {
  let fd: number | undefined;
  try {
    fd = openSync(filePath, 'r');
    const buf = Buffer.alloc(CWD_SCAN_MAX_BYTES);
    const bytesRead = readSync(fd, buf, 0, CWD_SCAN_MAX_BYTES, 0);
    if (bytesRead <= 0) return null;
    const chunk = buf.subarray(0, bytesRead).toString('utf8');
    const lines = chunk.split('\n').slice(0, CWD_SCAN_MAX_LINES);
    for (const line of lines) {
      const trimmed = line.trim();
      if (trimmed === '') continue;
      try {
        const parsed: unknown = JSON.parse(trimmed);
        if (
          parsed !== null &&
          typeof parsed === 'object' &&
          'cwd' in parsed &&
          typeof (parsed as { cwd?: unknown }).cwd === 'string' &&
          (parsed as { cwd: string }).cwd.trim() !== ''
        ) {
          return (parsed as { cwd: string }).cwd;
        }
      } catch {
        continue; // linha malformada/cortada pelo teto de bytes — pula, nao aborta a varredura (FR-003a, mesmo espirito)
      }
    }
    return null;
  } catch {
    return null;
  } finally {
    if (fd !== undefined) {
      try {
        closeSync(fd);
      } catch {
        /* noop */
      }
    }
  }
}

/** Varre um unico diretorio-slug em busca de arquivos `<uuid>.jsonl`. */
function scanProjectDir(
  root: string,
  slug: string,
  liveWindowMs: number,
  nowMs: number
): SessionSummaryDTO[] {
  const slugPath = join(root, slug);
  let entryNames: string[];
  try {
    entryNames = readdirSync(slugPath);
  } catch {
    return []; // slug ilegivel/removido entre o readdir da raiz e este ponto — degrada localmente, nunca aborta o ciclo inteiro
  }

  const out: SessionSummaryDTO[] = [];
  for (const entryName of entryNames) {
    if (!entryName.endsWith('.jsonl')) continue;
    const rawId = entryName.slice(0, -'.jsonl'.length);
    if (!isValidSessionId(rawId)) continue; // nome fora do padrao <uuid>.jsonl — ignora (defesa em profundidade, CHK016/CHK018)

    const filePath = join(slugPath, entryName);
    let st;
    try {
      st = statSync(filePath);
    } catch {
      continue;
    }
    if (!st.isFile()) continue;

    out.push({
      sessionId: normalizeSessionId(rawId),
      projectPath: extractFirstCwd(filePath),
      projectSlug: slug,
      lastActivityAt: st.mtime.toISOString(),
      live: nowMs - st.mtimeMs <= liveWindowMs,
      sizeBytes: st.size,
    });
  }
  return out;
}

/**
 * Varre `CSTK_SESSIONS_ROOT` (ou default `~/.claude/projects`) e retorna os
 * metadados de todas as sessoes descobertas (FR-001, FR-002, FR-007).
 *
 * Distincao obrigatoria (2.2.3 / FR-008 / Constitution Check Principio II):
 *   - raiz ausente (`existsSync` falso ou `realpathSync` lanca) ->
 *     `sessions-root-missing`;
 *   - raiz presente mas `readdirSync` falha (permissao) ->
 *     `sessions-root-unreadable`;
 *   - raiz presente e vazia -> **nao-degradada**, `sessions: []`.
 *
 * Nunca lanca.
 */
export function scanSessions(): SessionScanResult {
  const candidate = resolveSessionsRootCandidate();

  if (!existsSync(candidate)) {
    return { degraded: true, reason: 'sessions-root-missing' };
  }

  let resolvedRoot: string;
  try {
    resolvedRoot = realpathSync(candidate);
  } catch {
    return { degraded: true, reason: 'sessions-root-missing' };
  }

  let rootIsDir: boolean;
  try {
    rootIsDir = statSync(resolvedRoot).isDirectory();
  } catch {
    return { degraded: true, reason: 'sessions-root-unreadable' };
  }
  if (!rootIsDir) {
    return { degraded: true, reason: 'sessions-root-missing' };
  }

  let slugEntries: Dirent[];
  try {
    slugEntries = readdirSync(resolvedRoot, { withFileTypes: true });
  } catch {
    return { degraded: true, reason: 'sessions-root-unreadable' };
  }

  const liveWindowMs = resolveLiveWindowMs();
  const nowMs = Date.now();
  const sessions: SessionSummaryDTO[] = [];
  for (const entry of slugEntries) {
    if (!entry.isDirectory()) continue;
    sessions.push(...scanProjectDir(resolvedRoot, entry.name, liveWindowMs, nowMs));
  }

  return { degraded: false, sessions };
}
