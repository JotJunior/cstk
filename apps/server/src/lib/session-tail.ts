/**
 * Leitura de tail por janela de bytes a partir do fim do arquivo (task 2.3).
 * Ref: plan.md §Convencoes de Borda, §Structure Decision, research.md
 * Decision 8/9/10, data-model.md Entity SessionTailEntryDTO,
 * contracts/sessions-api.md GET /sessions/:sessionId/tail, tasks.md FASE 2
 * (2.3).
 *
 * Escopo desta task: SOMENTE a mecanica de leitura + parse + normalizacao
 * de uma janela de linhas. NAO inclui: resolucao/confinamento de path
 * (`sessions-root.ts`, task 2.1 — o `confinedPath` recebido aqui JA foi
 * validado la), cadeia de scrub de segredos (FASE 3) nem composicao do
 * envelope HTTP (FASE 5, `sessionId`/`live`/`scrubMode` sao adicionados
 * pela rota).
 *
 * Ordem scrub-vs-truncamento (Decision 9, achado MEDIUM de plan.md): as
 * entradas devolvidas aqui ja vem RECORTADAS (janela de bytes do disco +
 * teto de linhas + orcamento de bytes da resposta + teto por entrada), de
 * proposito, para que a cadeia de scrub (task 3.3) rode sobre o recorte e
 * nunca sobre o arquivo inteiro. A task 3.3 e quem vai inserir o scrub
 * ANTES do corte de `textTruncated` implementado aqui (nunca truncar um
 * segredo pela metade antes de redigir) — esta task apenas garante que a
 * interface nao force uma ordem que impeca essa insercao futura.
 */
import { statSync } from 'node:fs';
import type { SessionTailEntryDTO } from '@cstk-panel/shared-types';
import { readConfinedSessionFile } from './sessions-root.js';

/**
 * Decision 8 (research.md) — janela maxima lida do disco a partir do fim do
 * arquivo. [PROPOSTA — a validar em producao]: garante que um transcript de
 * dezenas de MB nunca seja carregado inteiro so para servir as ultimas N
 * linhas.
 */
export const TAIL_READ_WINDOW_BYTES = 1_048_576; // 1 MiB

/**
 * Decision 9 (research.md) — orcamento total de bytes de TEXTO acumulado
 * entre as entradas selecionadas. [PROPOSTA — a validar em producao].
 */
export const RESPONSE_BYTE_BUDGET = 262_144; // 256 KiB

/**
 * Decision 9 (research.md) — teto de bytes por entrada individual.
 * [PROPOSTA — a validar em producao]. Uma unica linha `.jsonl` pode conter
 * megabytes (dump de arquivo em `tool_result`/`tool_use.input`); sem este
 * teto por entrada, o orcamento total (`RESPONSE_BYTE_BUDGET`) poderia ser
 * consumido por uma unica entrada.
 */
export const ENTRY_TEXT_MAX_BYTES = 8_192; // 8 KiB

export const DEFAULT_TAIL_LINES = 200;
export const MIN_TAIL_LINES = 1;
export const MAX_TAIL_LINES = 1000;

export interface SessionTailReadResult {
  /** Ordem cronologica ASCENDENTE (mais antiga primeiro) — data-model.md. */
  entries: SessionTailEntryDTO[];
  /** Valor de `lines` apos clamp (1..1000, default 200). */
  requestedLines: number;
  /** `entries.length`. */
  returnedLines: number;
  /** FR-003a — linhas malformadas puladas ao longo da janela lida. */
  skippedLines: number;
  /** `true` quando o orcamento de bytes da resposta encerrou a selecao
   *  antes do teto de linhas (FR-006). */
  truncatedByBytes: boolean;
  /** `true` quando o arquivo e maior que `TAIL_READ_WINDOW_BYTES` — existe
   *  historico anterior ao que foi lido do disco. */
  windowTruncated: boolean;
  /** ISO 8601 — `mtime` do arquivo no momento da leitura. */
  lastActivityAt: string;
}

function clampLines(raw: number | undefined): number {
  if (raw === undefined || !Number.isFinite(raw)) return DEFAULT_TAIL_LINES;
  const truncated = Math.trunc(raw);
  if (truncated < MIN_TAIL_LINES) return MIN_TAIL_LINES;
  if (truncated > MAX_TAIL_LINES) return MAX_TAIL_LINES;
  return truncated;
}

/**
 * Achatamento de `.message.content` (tipo heterogeneo observado no
 * transcript real — ora `string`, ora `array`) em `text` (plan.md
 * §Convencoes de Borda / data-model.md §Regra de achatamento). Itens de
 * conteudo com `.type` em `thinking`/`tool_use`/`tool_result` NAO
 * contribuem para `text` nesta versao (data-model.md).
 */
function flattenContent(content: unknown): string {
  if (typeof content === 'string') return content;
  if (Array.isArray(content)) {
    const parts: string[] = [];
    for (const item of content) {
      if (
        item !== null &&
        typeof item === 'object' &&
        (item as { type?: unknown }).type === 'text' &&
        typeof (item as { text?: unknown }).text === 'string'
      ) {
        parts.push((item as { text: string }).text);
      }
    }
    return parts.join('\n');
  }
  return '';
}

/**
 * Aplica o teto por entrada (Decision 9). Nesta task roda sobre o texto
 * CRU (o scrub ainda nao existe — sera inserido ANTES deste corte pela
 * task 3.3, nunca depois — ver comentario de topo do arquivo).
 */
function truncateEntryText(text: string): { text: string; textTruncated: boolean } {
  const buf = Buffer.from(text, 'utf8');
  if (buf.byteLength <= ENTRY_TEXT_MAX_BYTES) {
    return { text, textTruncated: false };
  }
  return { text: buf.subarray(0, ENTRY_TEXT_MAX_BYTES).toString('utf8'), textTruncated: true };
}

/**
 * Normaliza UMA linha `.jsonl` ja parseada em `SessionTailEntryDTO`.
 * Conversao explicita de forma para camelCase acontece aqui — unico lugar
 * de normalizacao (plan.md §Convencoes de Borda): a fonte contem
 * `sessionId` **e** `session_id` no mesmo arquivo, mas nenhum dos dois e
 * lido aqui (o `sessionId` do DTO de resposta e eco do parametro de rota,
 * FASE 5 — nunca extraido do conteudo da linha, FR-004).
 */
function normalizeLine(parsed: Record<string, unknown>): SessionTailEntryDTO {
  const uuid = typeof parsed['uuid'] === 'string' ? (parsed['uuid'] as string) : null;
  const type = typeof parsed['type'] === 'string' ? (parsed['type'] as string) : '';
  const timestamp = typeof parsed['timestamp'] === 'string' ? (parsed['timestamp'] as string) : null;

  const message = parsed['message'];
  const hasMessage = message !== null && typeof message === 'object';
  const role =
    hasMessage && typeof (message as { role?: unknown }).role === 'string'
      ? (message as { role: string }).role
      : null;
  const rawContent = hasMessage ? (message as { content?: unknown }).content : undefined;

  const { text, textTruncated } = truncateEntryText(flattenContent(rawContent));

  return { uuid, type, timestamp, role, text, textTruncated };
}

/**
 * Le a janela mais recente do transcript `.jsonl` ja CONFINADO (path
 * devolvido por `resolveConfinedSessionPath`, task 2.1) e devolve as
 * ultimas `lines` entradas validas, respeitando o teto duplo de linhas e
 * bytes (FR-006, Decision 9). Nunca lanca (Principio II): falha de
 * stat/leitura devolve `null` — o chamador (rota, FASE 5) mapeia para o
 * `DegradedReason` apropriado.
 *
 * Independente de liveness (FR-003/dec-010 desta execucao): esta funcao
 * nao consulta `live`/mtime-freshness para decidir SE le — apenas para
 * relatar `lastActivityAt`.
 */
export function readSessionTail(
  confinedPath: string,
  options: { lines?: number } = {}
): SessionTailReadResult | null {
  let size: number;
  let lastActivityAt: string;
  try {
    const stat = statSync(confinedPath);
    if (!stat.isFile()) return null;
    size = stat.size;
    lastActivityAt = stat.mtime.toISOString();
  } catch {
    return null;
  }

  const requestedLines = clampLines(options.lines);
  const windowTruncated = size > TAIL_READ_WINDOW_BYTES;
  const tailBytes = Math.min(size, TAIL_READ_WINDOW_BYTES);

  const buf = readConfinedSessionFile(confinedPath, { tailBytes });
  if (buf === null) return null;

  const rawLines = buf.toString('utf8').split('\n');
  // A janela pode comecar no meio de uma linha (Decision 8) quando o
  // arquivo e maior que TAIL_READ_WINDOW_BYTES — descarta o primeiro
  // fragmento nesse caso (nunca tentar parsear uma linha cortada ao meio).
  if (windowTruncated && rawLines.length > 0) {
    rawLines.shift();
  }

  let skippedLines = 0;
  const parsedEntries: SessionTailEntryDTO[] = [];
  for (const line of rawLines) {
    const trimmed = line.trim();
    if (trimmed === '') continue;
    let parsed: unknown;
    try {
      parsed = JSON.parse(trimmed);
    } catch {
      skippedLines += 1; // FR-003a — pula e conta, nunca aborta
      continue;
    }
    if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
      // JSON valido mas nao e um objeto de linha (numero/string solta/array
      // no nivel raiz) — nao e o formato esperado de uma linha do
      // transcript; trata como malformada (FR-003a), nunca como entrada.
      skippedLines += 1;
      continue;
    }
    parsedEntries.push(normalizeLine(parsed as Record<string, unknown>));
  }

  // Seleciona do mais recente para o mais antigo, parando no primeiro teto
  // atingido — linhas (`requestedLines`) ou orcamento de bytes
  // (`RESPONSE_BYTE_BUDGET`) — Decision 9.
  const selectedReversed: SessionTailEntryDTO[] = [];
  let bytesAccumulated = 0;
  let truncatedByBytes = false;
  for (let i = parsedEntries.length - 1; i >= 0; i--) {
    if (selectedReversed.length >= requestedLines) break;
    const entry = parsedEntries[i]!;
    const entryBytes = Buffer.byteLength(entry.text, 'utf8');
    if (bytesAccumulated + entryBytes > RESPONSE_BYTE_BUDGET) {
      truncatedByBytes = true;
      break;
    }
    selectedReversed.push(entry);
    bytesAccumulated += entryBytes;
  }
  const entries = selectedReversed.reverse();

  return {
    entries,
    requestedLines,
    returnedLines: entries.length,
    skippedLines,
    truncatedByBytes,
    windowTruncated,
    lastActivityAt,
  };
}
