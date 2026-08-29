/**
 * Cadeia de scrub de segredos obrigatoria antes de servir conteudo de
 * transcript (FASE 3, task 3.1/3.2).
 * Ref: plan.md §Seguranca de Conteudo (integral), block-004/dec-030/
 * dec-032/dec-033, quickstart.md Scenario 12/12.1/12.2, tasks.md FASE 3.
 *
 * Cadeia (Opcao C com fallback, plan.md §Cadeia de scrub):
 *   passo 1 — `secrets-filter.sh scrub` do cstk, via subprocesso SEM shell,
 *             conteudo por stdin, quando o script existe/e executavel;
 *   passo 2 — redactor INTERNO minimo (este arquivo), SEMPRE roda, mesmo
 *             quando o passo 1 teve sucesso (dec-032 — encadeamento, nao
 *             fallback: o filtro do cstk nao cobre `password=`/`token=`/
 *             `secret=`/`api_key=` sem piso de 20 chars, nem blocos
 *             `BEGIN...PRIVATE KEY` — ver plan.md §Cobertura medida).
 *
 * Em NENHUM caminho, em NENHUMA condicao de erro, conteudo cru e servido
 * (Principio II). Falha do subprocesso -> descarta saida parcial, usa a
 * ENTRADA ORIGINAL como insumo do passo 2 (3.2.3). Log de falha contem
 * SOMENTE `exitCode`/`timedOut` (3.2.4) — nunca stdin/stdout/stderr.
 *
 * Anti-ReDoS (0.2.1, achado MEDIUM plan.md): todo padrao do redactor
 * interno e ancorado por linha (nunca varredura livre multi-linha), zero
 * quantificador aninhado; o bloco `BEGIN...PRIVATE KEY` e casado
 * linha-a-linha por uma maquina de estados simples (flag "dentro do
 * bloco"), nunca por um regex guloso multi-linha. Medicao empirica em
 * quickstart.md Scenario 12.1.
 */
import { execFile as execFileCb } from 'node:child_process';
import { accessSync, constants as fsConstants, statSync } from 'node:fs';
import { homedir } from 'node:os';
import { isAbsolute, join } from 'node:path';

// ---------------------------------------------------------------------------
// Passo 2 — redactor interno (SEMPRE roda; puro, sincrono, sem I/O)
// ---------------------------------------------------------------------------

/**
 * Atribuicao `password=`/`token=`/`secret=`/`api_key=` (ou `:`) SEM piso de
 * comprimento (lacuna do filtro do cstk, que exige 20+ chars — plan.md
 * §Cobertura medida). Ancorado por exigir o separador `[:=]` literal logo
 * apos a palavra-chave — prosa mencionando a palavra sem valor associado
 * (`o campo password e obrigatorio`) nunca casa (0.4/Scenario 12.2, casos
 * N1-N3). Um unico quantificador por grupo (`\s*`, `\S+`) — sem aninhamento.
 */
const ASSIGNMENT_PATTERN = /\b(password|token|secret|api_key)\s*[:=]\s*\S+/gi;

/** `Bearer <token>` — mesma cobertura do cstk, repetida para o caminho sem cstk. */
const BEARER_PATTERN = /\bBearer\s+\S+/g;

/** Chave AWS `AKIA` + 16+ alfanumericos — mesma cobertura do cstk, repetida. */
const AWS_KEY_PATTERN = /\bAKIA[A-Z0-9]{16,}\b/g;

/** Marcadores de bloco de chave privada — testados isoladamente por linha (trim de `\r`). */
const PRIVATE_KEY_BEGIN = /^-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----$/;
const PRIVATE_KEY_END = /^-----END [A-Z0-9 ]*PRIVATE KEY-----$/;

/**
 * Maquina de estados linha-a-linha (0.2.1, achado MEDIUM ReDoS): substitui
 * o bloco `BEGIN...END PRIVATE KEY` inteiro por um unico `[REDACTED]`,
 * nunca deixando uma linha do corpo sobreviver. Flag booleana "dentro do
 * bloco", set/clear em BEGIN/END — nunca um regex guloso atravessando o
 * texto inteiro.
 */
function scrubPrivateKeyBlocks(text: string): string {
  const lines = text.split('\n');
  const out: string[] = [];
  let inBlock = false;
  for (const rawLine of lines) {
    const line = rawLine.replace(/\r$/, '');
    if (!inBlock) {
      if (PRIVATE_KEY_BEGIN.test(line)) {
        inBlock = true;
        out.push('[REDACTED]');
        continue;
      }
      out.push(rawLine);
      continue;
    }
    // inBlock === true: descarta a linha (corpo da chave); ao achar o END,
    // sai do estado, sem emitir a linha END (ja coberta pelo [REDACTED] unico).
    if (PRIVATE_KEY_END.test(line)) {
      inBlock = false;
    }
  }
  return out.join('\n');
}

/**
 * Redactor interno minimo (task 3.1.1/3.1.2). Roda SEMPRE (dec-032),
 * encadeado apos o passo 1 quando disponivel. Cobre no minimo: blocos de
 * chave privada, atribuicoes password/token/secret/api_key sem piso de
 * comprimento, Bearer tokens e chaves AWS (repetido do cstk para que o
 * caminho sem cstk continue cobrindo os 4 padroes exigidos pela resposta
 * ao block-004).
 */
export function scrubTextInternal(text: string): string {
  const withoutPrivateKeys = scrubPrivateKeyBlocks(text);
  return withoutPrivateKeys
    .split('\n')
    .map((line) =>
      line
        .replace(ASSIGNMENT_PATTERN, '$1=[REDACTED]')
        .replace(BEARER_PATTERN, 'Bearer [REDACTED]')
        .replace(AWS_KEY_PATTERN, '[REDACTED-AWS-KEY]')
    )
    .join('\n');
}

// ---------------------------------------------------------------------------
// Passo 1 — `secrets-filter.sh scrub` via subprocesso (task 3.2)
// ---------------------------------------------------------------------------

export type ScrubMode = 'cstk+internal' | 'internal';

export interface ScrubResult {
  text: string;
  scrubMode: ScrubMode;
}

/** Conteudo EXATO permitido no log de falha do subprocesso (3.2.4/Scenario 12 Ramo F). */
export interface ScrubFailureInfo {
  exitCode: number | null;
  timedOut: boolean;
}

export type ScrubFailureLogger = (info: ScrubFailureInfo) => void;

const DEFAULT_SECRETS_FILTER_TIMEOUT_MS = 2000;

/** Nunca loga stdin/stdout/stderr — apenas os dois campos fechados do contrato (3.2.4). */
const defaultFailureLogger: ScrubFailureLogger = (info) => {
  console.error(JSON.stringify({ exitCode: info.exitCode, timedOut: info.timedOut }));
};

function resolveSecretsFilterPathFromEnv(): string | null {
  const raw = process.env['CSTK_SECRETS_FILTER'];
  if (raw !== undefined && raw.trim() !== '') {
    const trimmed = raw.trim();
    // CHK013 / 3.2.2 — NUNCA resolver por PATH; caminho nao-absoluto == indisponivel.
    if (!isAbsolute(trimmed)) return null;
    return trimmed;
  }
  return join(homedir(), '.claude', 'skills', 'agente-00c-runtime', 'scripts', 'secrets-filter.sh');
}

function isExecutableFile(path: string): boolean {
  try {
    accessSync(path, fsConstants.X_OK);
    return statSync(path).isFile();
  } catch {
    return false;
  }
}

interface SecretsFilterResolution {
  available: boolean;
  path: string | null;
}

/** Cache — deteccao de disponibilidade roda UMA VEZ (3.2.5), nao por requisicao. */
let cachedResolution: SecretsFilterResolution | undefined;

function resolveSecretsFilter(): SecretsFilterResolution {
  if (cachedResolution !== undefined) return cachedResolution;
  const path = resolveSecretsFilterPathFromEnv();
  const available = path !== null && isExecutableFile(path);
  cachedResolution = { available, path: available ? path : null };
  return cachedResolution;
}

/** Deteccao de disponibilidade do script (cacheada — 3.2.5). */
export function isSecretsFilterAvailable(): boolean {
  return resolveSecretsFilter().available;
}

/** Uso exclusivo de testes — evita vazamento de cache entre casos (paridade com ingest-watcher). */
export function resetSecretsFilterAvailabilityForTests(): void {
  cachedResolution = undefined;
}

function resolveTimeoutMs(): number {
  const raw = process.env['CSTK_SECRETS_FILTER_TIMEOUT_MS'];
  if (raw === undefined || raw.trim() === '') return DEFAULT_SECRETS_FILTER_TIMEOUT_MS;
  const parsed = Number(raw);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : DEFAULT_SECRETS_FILTER_TIMEOUT_MS;
}

export interface ExecFileWithStdinResult {
  stdout: string;
}

/** Injetavel para testes deterministicos (falha/timeout — Ramo C/F do Scenario 12). */
export type ExecFileWithStdinFn = (
  file: string,
  args: string[],
  input: string,
  options: { timeoutMs: number }
) => Promise<ExecFileWithStdinResult>;

/**
 * Implementacao real — SEM shell (`execFile`, nunca `exec`), argumentos em
 * array fixo, conteudo por STDIN (nunca argv). `timeout`/`killSignal` do
 * proprio Node cobrem o teto de tempo do subprocesso (3.2.1).
 */
const defaultExecFileWithStdin: ExecFileWithStdinFn = (file, args, input, options) =>
  new Promise((resolvePromise, rejectPromise) => {
    const child = execFileCb(
      file,
      args,
      { timeout: options.timeoutMs, maxBuffer: 8 * 1024 * 1024 },
      (error, stdout) => {
        if (error) {
          rejectPromise(error);
          return;
        }
        resolvePromise({ stdout: String(stdout) });
      }
    );
    // EPIPE no stdin (processo morreu antes de consumir tudo) e reportado
    // pelo callback de exit acima via `error` — aqui apenas evita um
    // unhandled 'error' event derrubando o processo do servidor.
    child.stdin?.on('error', () => {
      /* noop — o desfecho real chega pelo callback de exit */
    });
    child.stdin?.end(input, 'utf8');
  });

export interface ScrubChainOptions {
  /** Injetavel para testes — nunca spawna processo real na suite. */
  execImpl?: ExecFileWithStdinFn;
  timeoutMs?: number;
  /** Injetavel para testes/observabilidade — default loga so os 2 campos fechados. */
  onSubprocessFailure?: ScrubFailureLogger;
}

/**
 * Cadeia completa de scrub (task 3.2). Aplica o passo 1 (quando o cstk
 * esta disponivel) seguido SEMPRE do passo 2 (dec-032). Nunca lanca
 * (Principio II) — qualquer falha do subprocesso degrada para
 * `scrubMode: 'internal'` sobre a ENTRADA ORIGINAL, nunca sobre saida
 * parcial do passo 1 (3.2.3).
 *
 * A entrada `rawText` MUST ja vir limitada pela janela de leitura do
 * chamador (FR-006, TAIL_READ_WINDOW_BYTES em session-tail.ts) — esta
 * funcao nunca le o arquivo inteiro; ela apenas processa o que recebe
 * (3.2.6).
 */
export async function scrubTranscriptText(
  rawText: string,
  options: ScrubChainOptions = {}
): Promise<ScrubResult> {
  const { available, path } = resolveSecretsFilter();

  if (!available || path === null) {
    return { text: scrubTextInternal(rawText), scrubMode: 'internal' };
  }

  const execImpl = options.execImpl ?? defaultExecFileWithStdin;
  const timeoutMs = options.timeoutMs ?? resolveTimeoutMs();
  const onFailure = options.onSubprocessFailure ?? defaultFailureLogger;

  try {
    const { stdout } = await execImpl(path, ['scrub'], rawText, { timeoutMs });
    return { text: scrubTextInternal(stdout), scrubMode: 'cstk+internal' };
  } catch (err) {
    const errObj = err as { code?: unknown; killed?: unknown };
    const exitCode = typeof errObj.code === 'number' ? errObj.code : null;
    const timedOut = errObj.killed === true;
    // 3.2.4 — SOMENTE estes dois campos. Nunca stdin/stdout/stderr do subprocesso.
    onFailure({ exitCode, timedOut });
    // 3.2.3 — descarta saida parcial; usa a ENTRADA ORIGINAL como insumo do passo 2.
    return { text: scrubTextInternal(rawText), scrubMode: 'internal' };
  }
}

// ---------------------------------------------------------------------------
// Batch — UM subprocesso por requisicao, nunca um por item (task 3.3/3.4)
// ---------------------------------------------------------------------------

export interface ScrubBatchResult {
  /** Mesma ordem/contagem da lista de entrada — 1:1 garantido mesmo no
   *  caminho defensivo de fallback (ver abaixo). */
  texts: string[];
  /** Modo agregado do lote: 'cstk+internal' somente se TODOS os itens
   *  passaram pelo passo 1 com sucesso; qualquer degradacao reporta
   *  'internal' (nunca superestima a cobertura obtida). */
  scrubMode: ScrubMode;
}

/**
 * Marcador de fronteira usado para unir varios textos em UMA UNICA
 * invocacao do subprocesso (plan.md §Custo e mitigacao — "um spawn por
 * requisicao de tail", nunca um spawn por entrada/sessao). NUL bytes +
 * string fixa: nenhum padrao de segredo dos dois passos da cadeia casa
 * ou remove esta sequencia, e a chance de colisao com conteudo real e
 * desprezivel; ainda assim ha fallback defensivo abaixo caso colida.
 */
const BATCH_JOIN_MARKER = '  CSTK-SCRUB-BATCH-BOUNDARY  ';

/**
 * Aplica a cadeia de scrub (`scrubTranscriptText`) a uma LISTA de textos
 * com uma unica invocacao de subprocesso, unindo-os por `BATCH_JOIN_MARKER`
 * e desfazendo a juncao apos o scrub. Preserva 1:1 a ordem/contagem da
 * entrada.
 *
 * Defesa (nunca deveria ocorrer): se a contagem de pedacos apos o split
 * nao bater com a contagem original de textos, cai para scrub INDIVIDUAL
 * por item (mais spawns somente neste caminho defensivo) — em nenhum caso
 * um texto e devolvido sem ter passado pela cadeia de scrub (Principio II).
 */
export async function scrubTextBatch(
  texts: string[],
  options: ScrubChainOptions = {}
): Promise<ScrubBatchResult> {
  if (texts.length === 0) return { texts: [], scrubMode: 'internal' };
  if (texts.length === 1) {
    const r = await scrubTranscriptText(texts[0]!, options);
    return { texts: [r.text], scrubMode: r.scrubMode };
  }

  const joined = texts.join(BATCH_JOIN_MARKER);
  const joinedResult = await scrubTranscriptText(joined, options);
  const parts = joinedResult.text.split(BATCH_JOIN_MARKER);
  if (parts.length === texts.length) {
    return { texts: parts, scrubMode: joinedResult.scrubMode };
  }

  // Fallback defensivo — marcador nao sobreviveu 1:1 (nao deveria ocorrer).
  const perItem = await Promise.all(texts.map((t) => scrubTranscriptText(t, options)));
  const scrubMode: ScrubMode = perItem.every((r) => r.scrubMode === 'cstk+internal')
    ? 'cstk+internal'
    : 'internal';
  return { texts: perItem.map((r) => r.text), scrubMode };
}
