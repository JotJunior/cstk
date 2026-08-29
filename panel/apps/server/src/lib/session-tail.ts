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
  /** Entradas DESCARTADAS da janela: sidecar do harness (nao e conversa) ou
   *  mensagem sem nada a exibir (so `thinking`). Reportado, nunca silencioso —
   *  sem isto, "12 entradas" esconderia 300 linhas descartadas. */
  filteredEntries: number;
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
 * Tipos de linha que SAO conversa. ALLOWLIST deliberada, nunca denylist.
 *
 * O `.jsonl` do harness mistura conversa com registros de sidecar no MESMO
 * arquivo. Medido num transcript real de 636 linhas: 280 (44%) eram
 * `attachment`, `mode`, `permission-mode`, `bridge-session`, `atis-latch`,
 * `last-prompt`, `pr-link`, `ai-title` e `file-history-snapshot` — nenhum
 * deles e mensagem, e todos renderizavam como linha vazia.
 *
 * Denylist seria a escolha errada: `type` e conjunto ABERTO e "cresce sem
 * aviso" (ver data-model.md §SessionTailEntryDTO). Cada tipo novo de sidecar
 * que a Anthropic acrescentar voltaria a poluir a tela sozinho. Com allowlist,
 * o custo do desconhecido e ficar de fora — visivel em `filteredEntries`, e
 * nunca ruido silencioso.
 */
const CONVERSATION_TYPES: ReadonlySet<string> = new Set(['user', 'assistant', 'system']);

/** Chaves de input de ferramenta que valem como resumo de uma linha, em ordem
 *  de preferencia. Heuristica: cobre as ferramentas mais frequentes sem
 *  precisar conhecer o schema de cada uma. */
const TOOL_SUMMARY_KEYS = [
  'command', 'file_path', 'path', 'pattern', 'query', 'url',
  'description', 'prompt', 'skill', 'subagent_type',
] as const;

/** Teto do resumo de `tool_use`. Aplicado DEPOIS do scrub (ver
 *  `scrubAndTruncateDrafts`): cortar antes poderia partir um segredo de um
 *  jeito que ele escapasse das regras do redator. */
const TOOL_SUMMARY_MAX_BYTES = 240;

function firstStringField(input: unknown): string | null {
  if (input === null || typeof input !== 'object' || Array.isArray(input)) return null;
  const obj = input as Record<string, unknown>;
  for (const key of TOOL_SUMMARY_KEYS) {
    const v = obj[key];
    if (typeof v === 'string' && v.trim() !== '') return v;
  }
  return null;
}

/** Tamanho aproximado do retorno de uma ferramenta, so para o marcador. */
function approxSize(content: unknown): number {
  if (typeof content === 'string') return Buffer.byteLength(content, 'utf8');
  try {
    return Buffer.byteLength(JSON.stringify(content) ?? '', 'utf8');
  } catch {
    return 0;
  }
}

function humanBytes(n: number): string {
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`;
  return `${(n / (1024 * 1024)).toFixed(1)} MB`;
}

interface ContentExtract {
  text: string;
  kind: 'text' | 'tool_use' | 'tool_result';
  toolName: string | null;
  /** `false` quando a mensagem nao produz entrada alguma — conteudo so
   *  `thinking`, ou vazio. O chamador DESCARTA e contabiliza. */
  renderable: boolean;
}

const NOT_RENDERABLE: ContentExtract = { text: '', kind: 'text', toolName: null, renderable: false };

/**
 * Extrai de `.message.content` (tipo heterogeneo no transcript real — ora
 * `string`, ora `array`) o texto a exibir, o que o produziu (`kind`) e o nome
 * da ferramenta quando houver.
 *
 * ANTES (ate a 0.33.x) so `type: 'text'` contribuia, por decisao explicita de
 * escopo do `data-model.md` ("nesta versao"). A medicao contra transcript real
 * mostrou o custo do adiamento: das 356 mensagens de um arquivo de 636 linhas,
 * 324 rendiam texto VAZIO — 137 `tool_use`, 137 `tool_result` e 48 `thinking`.
 * Somando os sidecars, a tela exibia 5% de conteudo util.
 *
 * Precedencia: texto > tool_use > tool_result. Uma mensagem com texto E
 * chamada de ferramenta mostra o texto — e o que o agente DISSE, e mais
 * informativo que o que ele executou em seguida.
 */
function extractContent(content: unknown): ContentExtract {
  if (typeof content === 'string') {
    return content.trim() === ''
      ? NOT_RENDERABLE
      : { text: content, kind: 'text', toolName: null, renderable: true };
  }
  if (!Array.isArray(content)) return NOT_RENDERABLE;

  const texts: string[] = [];
  let toolUse: { name: string; input: unknown } | null = null;
  let toolResult: { size: number } | null = null;

  for (const item of content) {
    if (item === null || typeof item !== 'object') continue;
    const it = item as { type?: unknown; text?: unknown; name?: unknown; input?: unknown; content?: unknown };
    if (it.type === 'text' && typeof it.text === 'string') {
      texts.push(it.text);
    } else if (it.type === 'tool_use' && toolUse === null) {
      toolUse = { name: typeof it.name === 'string' ? it.name : 'ferramenta', input: it.input };
    } else if (it.type === 'tool_result' && toolResult === null) {
      toolResult = { size: approxSize(it.content) };
    }
    // `thinking` e ignorado de proposito (decisao do operador, 2026-08-27).
  }

  const joined = texts.join('\n');
  if (joined.trim() !== '') {
    return { text: joined, kind: 'text', toolName: null, renderable: true };
  }
  if (toolUse !== null) {
    const summary = firstStringField(toolUse.input);
    return {
      // Resumo pode ser vazio: a linha ainda vale, porque o NOME da ferramenta
      // ja responde "o que a sessao esta fazendo".
      text: summary ?? '',
      kind: 'tool_use',
      toolName: toolUse.name,
      renderable: true,
    };
  }
  if (toolResult !== null) {
    // Marcador GERADO por nos — o conteudo do retorno nunca sai daqui. Alem de
    // evitar vazamento, impede que um dump de arquivo consuma o orcamento de
    // bytes da resposta inteira.
    return {
      text: `retorno de ferramenta · ${humanBytes(toolResult.size)}`,
      kind: 'tool_result',
      toolName: null,
      renderable: true,
    };
  }
  return NOT_RENDERABLE;
}

/**
 * Aplica o teto por entrada (Decision 9). Task 3.3: roda SEMPRE sobre
 * texto **ja escrubado** (o chamador — `readSessionTail` — garante a
 * ordem: scrub em lote primeiro, este corte depois; nunca truncar um
 * segredo pela metade antes de redigir — ver comentario de topo do
 * arquivo). `[REDACTED]` conta para o teto, tal como o restante do texto.
 */
function truncateEntryText(text: string, maxBytes: number = ENTRY_TEXT_MAX_BYTES): { text: string; textTruncated: boolean } {
  const buf = Buffer.from(text, 'utf8');
  if (buf.byteLength <= maxBytes) {
    return { text, textTruncated: false };
  }
  return { text: buf.subarray(0, maxBytes).toString('utf8'), textTruncated: true };
}

/** Rascunho de UMA linha `.jsonl` ja parseada, ANTES do scrub/truncamento. */
interface ParsedLineDraft {
  uuid: string | null;
  type: string;
  timestamp: string | null;
  role: string | null;
  rawText: string;
  kind: 'text' | 'tool_use' | 'tool_result';
  toolName: string | null;
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
function parseLineDraft(parsed: Record<string, unknown>): ParsedLineDraft | null {
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

  const extract = extractContent(rawContent);
  if (!extract.renderable) return null;

  return {
    uuid, type, timestamp, role,
    rawText: extract.text,
    kind: extract.kind,
    toolName: extract.toolName,
  };
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
    // Teto MENOR para o resumo de tool_use: ele e um resumo por desenho, nao
    // um corpo de mensagem. Aplicado aqui, DEPOIS do scrub — cortar antes
    // poderia partir um segredo de um jeito que escapasse das regras.
    const cap = draft.kind === 'tool_use' ? TOOL_SUMMARY_MAX_BYTES : ENTRY_TEXT_MAX_BYTES;
    const { text, textTruncated } = truncateEntryText(scrubbedTexts[i]!, cap);
    return {
      uuid: draft.uuid, type: draft.type, timestamp: draft.timestamp, role: draft.role,
      text, textTruncated, kind: draft.kind, toolName: draft.toolName,
    };
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
  let filteredEntries = 0;
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
    const obj = parsed as Record<string, unknown>;
    const lineType = typeof obj['type'] === 'string' ? (obj['type'] as string) : '';
    if (!CONVERSATION_TYPES.has(lineType)) {
      // Sidecar do harness (attachment, mode, pr-link, ...) — nao e conversa.
      filteredEntries += 1;
      continue;
    }
    const draft = parseLineDraft(obj);
    if (draft === null) {
      // Mensagem sem nada a exibir (so `thinking`, ou conteudo vazio).
      filteredEntries += 1;
      continue;
    }
    drafts.push(draft);
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
    filteredEntries,
    truncatedByBytes,
    windowTruncated,
    lastActivityAt,
    scrubMode,
  };
}
