/**
 * Leitura de tail por janela de bytes a partir do fim do arquivo (task 2.3).
 * Ref: plan.md §Convencoes de Borda, §Structure Decision, research.md
 * Decision 8/9/10, data-model.md Entity SessionTailEntryDTO,
 * contracts/sessions-api.md GET /sessions/:sessionId/tail, tasks.md FASE 2
 * (2.3).
 *
 * Escopo desta task: a mecanica de leitura + parse + normalizacao de uma
 * janela de linhas, agora com o WIRING da cadeia de scrub (task 3.3 —
 * `scrubTextBatch`, de `secret-scrub.ts`) entre o parse e o truncamento.
 * NAO inclui: resolucao/confinamento de path (`sessions-root.ts`, task
 * 2.1 — o `confinedPath` recebido aqui JA foi validado la), o ALGORITMO
 * de scrub em si (`secret-scrub.ts`) nem composicao do envelope HTTP
 * (FASE 5, `sessionId`/`live`/`scrubMode` sao adicionados pela rota).
 *
 * Ordem scrub-vs-truncamento (Decision 9, achado MEDIUM de plan.md, task
 * 3.3): a cadeia de scrub (`secret-scrub.ts`) roda ANTES do corte de
 * `textTruncated` implementado aqui — nunca truncar um segredo pela
 * metade antes de redigir. As entradas ja vem RECORTADAS por janela de
 * bytes do disco (`TAIL_READ_WINDOW_BYTES`) antes de chegar ao scrub, para
 * que a entrada do subprocesso seja limitada pela janela de leitura
 * (FR-006), nunca pelo arquivo inteiro (plan.md §Custo e mitigacao). Todas
 * as entradas parseadas da janela sao escrubadas em UMA UNICA invocacao de
 * subprocesso (`scrubTextBatch`, "um spawn por requisicao de tail"), e so
 * DEPOIS truncadas individualmente pelo teto por entrada.
 */
import { statSync } from 'node:fs';
import type { SessionTailEntryDTO } from '@cstk-panel/shared-types';
import { readConfinedSessionFile } from './sessions-root.js';
import { scrubTextBatch, type ScrubMode } from './secret-scrub.js';

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
  /** Qual cadeia de scrub produziu `entries[].text` (contracts/sessions-api.md
   *  `scrubMode`, achado onda-015 — antes descartado pelo chamador). Quando
   *  a janela nao tem nenhuma entrada (`entries: []`), `'internal'` e o
   *  default conservador: nenhum lote de fato passou pela cadeia. */
  scrubMode: ScrubMode;
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
 * Aplica o teto por entrada (Decision 9). Task 3.3: roda SEMPRE sobre
 * texto **ja escrubado** (o chamador — `readSessionTail` — garante a
 * ordem: scrub em lote primeiro, este corte depois; nunca truncar um
 * segredo pela metade antes de redigir — ver comentario de topo do
 * arquivo). `[REDACTED]` conta para o teto, tal como o restante do texto.
 */
function truncateEntryText(text: string): { text: string; textTruncated: boolean } {
  const buf = Buffer.from(text, 'utf8');
  if (buf.byteLength <= ENTRY_TEXT_MAX_BYTES) {
    return { text, textTruncated: false };
  }
  return { text: buf.subarray(0, ENTRY_TEXT_MAX_BYTES).toString('utf8'), textTruncated: true };
}

/** Rascunho de UMA linha `.jsonl` ja parseada, ANTES do scrub/truncamento. */
interface ParsedLineDraft {
  uuid: string | null;
  type: string;
  timestamp: string | null;
  role: string | null;
  rawText: string;
}

/**
 * Extrai os campos de UMA linha `.jsonl` ja parseada, achatando
 * `.message.content` em `rawText` — SEM aplicar scrub nem truncamento
 * (task 3.3: as duas etapas rodam depois, em lote, sobre todas as
 * entradas da janela). Conversao explicita de forma para camelCase
 * acontece aqui — unico lugar de normalizacao (plan.md §Convencoes de
 * Borda): a fonte contem `sessionId` **e** `session_id` no mesmo arquivo,
 * mas nenhum dos dois e lido aqui (o `sessionId` do DTO de resposta e eco
 * do parametro de rota, FASE 5 — nunca extraido do conteudo da linha,
 * FR-004).
 */
function parseLineDraft(parsed: Record<string, unknown>): ParsedLineDraft {
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

  return { uuid, type, timestamp, role, rawText: flattenContent(rawContent) };
}

/** Resultado do lote de scrub+truncamento das entradas da janela (achado onda-015). */
interface ScrubbedTailDrafts {
  entries: SessionTailEntryDTO[];
  scrubMode: ScrubMode;
}

/**
 * Aplica a cadeia de scrub a TODOS os rascunhos da janela em UMA UNICA
 * invocacao de subprocesso (`scrubTextBatch` — "um spawn por requisicao
 * de tail", plan.md §Custo e mitigacao), e SO DEPOIS trunca cada entrada
 * individualmente (task 3.3.1 — scrub antes do corte, nunca depois).
 *
 * Devolve tambem `scrubMode` (antes descartado aqui — achado onda-015): a
 * rota HTTP (FASE 5) precisa reportar qual cadeia de fato produziu
 * `entries[].text`, nao a cadeia usada em outro lote (ex.: o scrub de
 * `projectPath`/`projectSlug` da rota de listagem, um lote INDEPENDENTE).
 * Janela vazia (`drafts: []`) nunca invoca `scrubTextBatch` — `'internal'`
 * e a leitura conservadora, nunca afirma `'cstk+internal'` para um lote que
 * nao rodou.
 */
async function scrubAndTruncateDrafts(drafts: ParsedLineDraft[]): Promise<ScrubbedTailDrafts> {
  if (drafts.length === 0) return { entries: [], scrubMode: 'internal' };
  const { texts: scrubbedTexts, scrubMode } = await scrubTextBatch(drafts.map((d) => d.rawText));
  const entries = drafts.map((draft, i) => {
    const { text, textTruncated } = truncateEntryText(scrubbedTexts[i]!);
    return { uuid: draft.uuid, type: draft.type, timestamp: draft.timestamp, role: draft.role, text, textTruncated };
  });
  return { entries, scrubMode };
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
 *
 * Async desde a task 3.3: a cadeia de scrub (`secret-scrub.ts`) pode
 * invocar um subprocesso (`secrets-filter.sh`), por isso esta funcao
 * devolve `Promise`. Todo chamador MUST `await` — uma Promise nao
 * aguardada usada como string vira `"[object Promise]"` silenciosamente
 * em runtime.
 */
export async function readSessionTail(
  confinedPath: string,
  options: { lines?: number } = {}
): Promise<SessionTailReadResult | null> {
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
  const drafts: ParsedLineDraft[] = [];
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
    drafts.push(parseLineDraft(parsed as Record<string, unknown>));
  }

  // Scrub em lote (UM subprocesso para a janela inteira) + truncamento
  // por entrada, nesta ordem (task 3.3.1).
  const { entries: parsedEntries, scrubMode } = await scrubAndTruncateDrafts(drafts);

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
    scrubMode,
  };
}
