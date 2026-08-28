/**
 * Watcher de ingestao em segundo plano (US1, FR-001/FR-003/FR-004/FR-013/FR-014).
 *
 * Verifica recorrentemente execucoes agente-00c/feature-00c ativas na
 * knowledge.db E state-dirs presentes no filesystem das raizes conhecidas
 * (CSTK_PROJECT_PATHS + executions.target_project_path) — a descoberta via
 * filesystem cobre o ovo-e-galinha de `state.json` recem-criados que ainda
 * nao tem linha em `executions` (a linha so nasce na primeira ingestao).
 * DELEGA a ingestao canonica `cstk recall --ingest` via subprocesso seguro —
 * NUNCA escreve na knowledge.db, NUNCA toca `state.json` (apenas stat/readdir),
 * NUNCA roda `--reindex` (Principio I; Constitution IV Opcao B).
 *
 * Ref: research.md Decisions 2, 3, 4, 9; contracts/watchers.md; tasks.md FASE 2
 *
 * Derivacao do state-dir (Decision 3) — nota de implementacao verificada
 * empiricamente (task 2.1.3): o layout REAL em disco desta execucao
 * (`.claude/feature-00c-state/<feature>/`, sem sub-diretorio por sessao —
 * `session`/`session_name` e apenas metadado em `.execution.session_name`
 * dentro do state.json, nunca um componente de path) confirma que a derivacao
 * usa somente `projectPath` + presenca/ausencia de `feature`. `session` NAO
 * participa da composicao do path.
 */
import { execFile as execFileCb } from 'node:child_process';
import {
  accessSync,
  constants as fsConstants,
  existsSync,
  readdirSync,
  realpathSync,
  statSync,
} from 'node:fs';
import { homedir } from 'node:os';
import { delimiter as pathDelimiter, join, resolve } from 'node:path';
import type Database from 'better-sqlite3';
import { openDb } from '../db/open.js';
import {
  listExecutionsForWatcher,
  listKnownProjectRoots,
  type WatcherExecutionRow,
} from '../db/queries/executions.js';
import { listConfiguredProjectPaths, resolveProjectPath } from '../config.js';
import { validateProjectRootPath } from '../lib/project-root.js';

// ---------------------------------------------------------------------------
// Constantes / defaults configuraveis via env (task 2.1.1, 2.3.4)
// ---------------------------------------------------------------------------

/**
 * Cadencia do timer do watcher — AJUSTADA empiricamente (task 2.3.4, CHK045/CHK057).
 *
 * Medicao real (nao estimada): `time cstk recall --ingest --state-dir <SD> --db <scratch.db>`
 * contra o `state.json` desta propria feature (49015 bytes, 6 ondas, 34 decisoes,
 * 11 skills, 11 memories) em 2026-07-15 — resultado literal:
 *   "3,68s user 6,01s system 83% cpu 11,644 total"
 * ⇒ ingestao real ~11.6s, ACIMA do "~10s" que research.md Decision 5 apontava como
 * limiar para ajustar a cadencia. Orcamento (Decision 5): cadencia_watcher +
 * duracao_ingestao + polling_cliente(10s) <= 30s (SC-001). Com cadencia=10_000 o
 * PIOR CASO seria 10 + 11.6 + 10 = 31.6s (estoura o orcamento). Reduzindo a
 * cadencia para 5_000, o pior caso cai para 5 + 11.6 + 10 = 26.6s — dentro de 30s
 * com folga. (state.json maiores que o medido aqui podem reintroduzir a folga
 * apertada; CSTK_WATCH_INTERVAL_MS permite ao operador re-ajustar sem rebuild.)
 */
export const DEFAULT_WATCH_INTERVAL_MS = 5_000;
/**
 * Timeout do subprocesso `cstk recall --ingest`. Re-medicao real em 2026-07-17
 * (cstk 5.21.0, state.json de 122KB / 176 memories / 77 decisions):
 *   "16.53s user 28.47s system 85% cpu 52.499 total"
 * ⇒ ingestao real ~52.5s — o default anterior de 20s (calibrado sobre um state
 * de 49KB que levava ~11.6s) matava o subprocesso no meio e deixava o painel
 * permanentemente em `watcher-ingestion-failed`. 90s mantem ~1.7x de folga
 * sobre o medido (mesma margem da calibracao original). Ajustavel sem rebuild
 * via CSTK_INGEST_TIMEOUT_MS (ver index.ts).
 */
export const DEFAULT_SUBPROCESS_TIMEOUT_MS = 90_000;
/** Cap de subprocessos `cstk` concorrentes por tick (Decision 9, item 3). */
export const DEFAULT_MAX_CONCURRENT = 4;
/** Backoff apos falha: pula re-tentativa para o mesmo state-dir por este intervalo. */
export const DEFAULT_BACKOFF_MS = 60_000;

/** Regex anti-traversal para `feature` vindo da knowledge.db (UNTRUSTED, Principio V).
 *  Identica a validacao de path params HTTP (`FeatureParamSchema`, routes/features.ts). */
const SAFE_SEGMENT_RE = /^[^/\\.<>]+$/;

// ---------------------------------------------------------------------------
// Cache de assinatura em memoria (task 2.2.1) — NUNCA persistido (Principio I)
// ---------------------------------------------------------------------------

export interface WatcherCacheEntry {
  /** ultima assinatura vista (mtimeMs de state.json como string) — null se state.json ilegivel */
  signature: string | null;
  /** epoch ms da ultima ingestao bem-sucedida; null se nunca */
  lastIngestAt: number | null;
  /** mensagem da ultima falha; null se nunca falhou (ou se a ultima tentativa apos a falha teve sucesso) */
  lastError: string | null;
  /** epoch ms da ultima falha; null se nunca */
  lastErrorAt: number | null;
}

const signatureCache = new Map<string, WatcherCacheEntry>();

/**
 * State-dirs com subprocesso `cstk recall --ingest` EM VOO. Os ticks do
 * setInterval nao se serializam e o cache de assinatura so e gravado quando o
 * subprocesso termina — sem esta guarda, uma ingestao mais longa que a cadencia
 * (medido: ~52.5s vs tick de 5s) faz cada tick seguinte disparar OUTRO
 * subprocesso para o mesmo state-dir (ingests concorrentes disputando a mesma
 * knowledge.db).
 */
const inFlightStateDirs = new Set<string>();

/** Leitura do cache por state-dir — consumido pelo endpoint de detalhe (task 2.4). */
export function getWatcherCacheEntry(stateDir: string): WatcherCacheEntry | undefined {
  return signatureCache.get(stateDir);
}

/** Escrita direta no cache — uso exclusivo de testes (simula estado apos falha/sucesso sem rodar um tick real). */
export function setWatcherCacheEntryForTests(stateDir: string, entry: WatcherCacheEntry): void {
  signatureCache.set(stateDir, entry);
}

/** Reset total do cache — uso exclusivo de testes (isolamento entre casos). */
export function resetWatcherCacheForTests(): void {
  signatureCache.clear();
  inFlightStateDirs.clear();
}

/**
 * Task 2.4.1 (CHK056/dec-027): true quando a ULTIMA falha registrada para o
 * state-dir e mais recente que a ultima ingestao bem-sucedida (ou quando NUNCA
 * houve sucesso). Consumido por `GET /executions/:executionId` para sinalizar
 * `meta.degraded:true` / `meta.reason:'watcher-ingestion-failed'` SEM nulificar
 * `data` — a execucao em si foi lida com sucesso da knowledge.db; apenas o
 * watcher (mecanismo de frescor em segundo plano) esta com a ultima tentativa
 * de ingestao falha para aquele state-dir especifico.
 */
export function isWatcherDegraded(entry: WatcherCacheEntry | undefined): boolean {
  if (!entry || entry.lastError === null || entry.lastErrorAt === null) return false;
  if (entry.lastIngestAt === null) return true; // falhou e nunca teve sucesso
  return entry.lastErrorAt > entry.lastIngestAt;
}

// ---------------------------------------------------------------------------
// Derivacao de state-dir (task 2.1.3, 2.3.2 — hardening anti-traversal)
// ---------------------------------------------------------------------------

function isSafeSegment(value: string): boolean {
  return SAFE_SEGMENT_RE.test(value);
}

/**
 * Deriva o state-dir de uma execucao observada (Decision 3).
 * - feature-00c (feature nao-nula/nao-vazia): `<projectPath>/.claude/feature-00c-state/<feature>/`
 * - agente-00c (feature nula/vazia): `<projectPath>/.claude/agente-00c-state/`
 *
 * `feature` e UNTRUSTED (vem da knowledge.db, Principio V): validada com o
 * MESMO regex anti-traversal aplicado aos path params HTTP ANTES de compor o
 * path (Decision 9, item 2) — nao apenas checagem de existencia depois.
 * Retorna `null` quando `feature` falha a validacao (nunca lanca, Principio II).
 */
export function deriveStateDir(projectPath: string, feature: string | null): string | null {
  const trimmed = feature?.trim() ?? '';
  if (trimmed === '') {
    return join(projectPath, '.claude', 'agente-00c-state');
  }
  if (!isSafeSegment(trimmed)) return null;
  return join(projectPath, '.claude', 'feature-00c-state', trimmed);
}

/** Assinatura barata de mudanca: mtimeMs de `state.json` (Decision 4 — mtime escolhido sobre sha256). */
function computeSignature(stateDir: string): string | null {
  try {
    const st = statSync(join(stateDir, 'state.json'));
    return String(st.mtimeMs);
  } catch {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Descoberta via filesystem (fix ovo-e-galinha da descoberta via db)
// ---------------------------------------------------------------------------

/**
 * Enumera state-dirs COM `state.json` presentes no disco sob uma raiz de
 * projeto, nos dois layouts canonicos (Decision 3):
 *   - `<root>/.claude/agente-00c-state/`
 *   - `<root>/.claude/feature-00c-state/<feature>/` (readdir de 1 nivel)
 *
 * Motivacao: a descoberta original do watcher consultava APENAS a tabela
 * `executions` da knowledge.db — mas a linha em `executions` so nasce na
 * PRIMEIRA ingestao. Um projeto/feature recem-iniciado tinha `state.json` no
 * disco e zero linhas na db ⇒ o watcher nunca o via ⇒ nunca ingeria ⇒ a linha
 * nunca nascia (ovo-e-galinha); o painel so "acordava" quando o proprio
 * agente rodava `cstk recall --ingest`. Esta funcao fecha o ciclo observando
 * o filesystem das raizes conhecidas (CSTK_PROJECT_PATHS +
 * executions.target_project_path de qualquer status).
 *
 * Nomes de diretorio de feature sao UNTRUSTED (conteudo do disco): filtrados
 * pelo MESMO regex anti-traversal de deriveStateDir antes de compor o path.
 * Nunca lanca (Principio II); raiz/layout ausente ⇒ contribuicao vazia.
 */
export function discoverStateDirsInRoot(projectRoot: string): string[] {
  const found: string[] = [];
  const agentDir = join(projectRoot, '.claude', 'agente-00c-state');
  if (existsSync(join(agentDir, 'state.json'))) found.push(agentDir);

  const featureBase = join(projectRoot, '.claude', 'feature-00c-state');
  try {
    for (const entry of readdirSync(featureBase, { withFileTypes: true })) {
      if (!entry.isDirectory()) continue;
      if (!isSafeSegment(entry.name)) continue;
      const dir = join(featureBase, entry.name);
      if (existsSync(join(dir, 'state.json'))) found.push(dir);
    }
  } catch {
    // feature-00c-state ausente/ilegivel — sem contribuicao deste layout
  }
  return found;
}

// ---------------------------------------------------------------------------
// Resolucao do binario `cstk` (task 2.3.1 — anti PATH-hijack, gate owasp medium)
// ---------------------------------------------------------------------------

/**
 * Verificado empiricamente (node -e com execFile('cstk',...) sem shell:true):
 * o Node resolve nomes de programa sem separador de path varrendo `PATH` (via
 * libuv/execvp) mesmo sem `shell:true`. Isso expõe risco de PATH hijack (um
 * diretorio malicioso anteposto no PATH pode sombrear o `cstk` real). Mitigacao:
 * resolver nos MESMOS diretorios do PATH explicitamente, uma vez, cacheado, e
 * sempre invocar `execFile` com o caminho ABSOLUTO resolvido — nunca o nome
 * relativo 'cstk'.
 */
let cachedCstkBinary: string | null | undefined;

function isExecutableFile(path: string): boolean {
  try {
    accessSync(path, fsConstants.X_OK);
    return statSync(path).isFile();
  } catch {
    return false;
  }
}

/** Resolve `cstk` a caminho absoluto verificado. `CSTK_BINARY_PATH` pina explicitamente (maior prioridade). */
export function resolveCstkBinary(): string | null {
  if (cachedCstkBinary !== undefined) return cachedCstkBinary;

  const pinned = process.env['CSTK_BINARY_PATH'];
  if (pinned && pinned.trim() !== '') {
    const candidate = resolve(pinned.trim());
    cachedCstkBinary = isExecutableFile(candidate) ? candidate : null;
    return cachedCstkBinary;
  }

  const pathEnv = process.env['PATH'] ?? '';
  for (const dir of pathEnv.split(pathDelimiter)) {
    if (dir.trim() === '') continue;
    const candidate = join(dir, 'cstk');
    if (isExecutableFile(candidate)) {
      cachedCstkBinary = candidate;
      return candidate;
    }
  }
  cachedCstkBinary = null;
  return null;
}

/** Uso exclusivo de testes — evita vazamento de cache entre casos. */
export function resetCstkBinaryCacheForTests(): void {
  cachedCstkBinary = undefined;
}

/**
 * env minimo passado ao subprocesso (Decision 9, item 1): PATH (o `cstk` pode
 * invocar sub-ferramentas do proprio toolkit) + HOME (resolucao de `~/.claude/...`
 * internamente ao `cstk`). NENHUMA outra variavel do processo pai e herdada.
 */
function minimalSubprocessEnv(): NodeJS.ProcessEnv {
  return {
    PATH: process.env['PATH'] ?? '',
    HOME: process.env['HOME'] ?? homedir(),
  };
}

// ---------------------------------------------------------------------------
// Subprocesso injetavel (testabilidade — task 2.1.6, 2.3.5)
// ---------------------------------------------------------------------------

export interface ExecFileResult {
  stdout: string;
  stderr: string;
}

export type ExecFileFn = (
  file: string,
  args: string[],
  options: { timeout: number; env: NodeJS.ProcessEnv; cwd: string }
) => Promise<ExecFileResult>;

/** Implementacao real — args SEMPRE em array (nunca shell-string interpolada). */
const defaultExecFile: ExecFileFn = (file, args, options) =>
  new Promise((resolvePromise, rejectPromise) => {
    execFileCb(file, args, options, (error, stdout, stderr) => {
      if (error) {
        rejectPromise(Object.assign(error, { stdout: String(stdout), stderr: String(stderr) }));
        return;
      }
      resolvePromise({ stdout: String(stdout), stderr: String(stderr) });
    });
  });

// ---------------------------------------------------------------------------
// Tick (task 2.1.2, 2.1.4, 2.1.5, 2.2.3, 2.3.3)
// ---------------------------------------------------------------------------

export interface WatcherTickOptions {
  dbPath: string;
  supportedSchemaVersions: string[];
  execFileImpl?: ExecFileFn;
  maxConcurrent?: number;
  subprocessTimeoutMs?: number;
  backoffMs?: number;
  /** injetavel para testes deterministicos de backoff */
  now?: () => number;
}

export type TickSkipReason =
  | 'project-path-unresolved'
  | 'project-path-inaccessible'
  | 'unsafe-feature-segment'
  | 'signature-unchanged'
  | 'backoff-active'
  | 'ingest-failed';

export interface WatcherTickResult {
  /** true quando a consulta a knowledge.db falhou (DB ausente/corrupto/schema) — tick ocioso, Principio II */
  degradedDb: boolean;
  /** true quando o binario `cstk` nao foi resolvido — nenhum subprocesso pode ser disparado */
  cstkUnresolved: boolean;
  /** numero de execucoes ativas encontradas na knowledge.db (antes do cap de concorrencia) */
  activeCount: number;
  /** state-dirs descobertos APENAS via filesystem nesta tick (sem execucao ativa na db) */
  fsDiscovered: number;
  /** numero de subprocessos `cstk recall --ingest` de fato disparados */
  triggered: number;
  /** numero de alvos pulados nesta tick (idempotencia, degradacao, backoff, cap, seed) */
  skipped: number;
}

/** Alvo unificado de ingestao: state-dir + modo de primeira-vista (ver seedFirst abaixo). */
interface IngestTarget {
  stateDir: string;
  /**
   * true para state-dirs descobertos via filesystem cuja(s) execucao(oes) na
   * db sao TODAS terminais: na primeira vista o watcher apenas registra a
   * assinatura corrente (sem subprocesso) e passa a ingerir SOMENTE quando o
   * state.json mudar de novo (ex.: re-execucao da mesma feature). Evita uma
   * tempestade de re-ingestoes de execucoes ja concluidas a cada boot do
   * server (o cache de assinatura e apenas em memoria — Principio I).
   */
  seedFirst: boolean;
}

/** Executa UM tick do watcher. Read-only sobre a knowledge.db; abre/fecha por tick (Principio VI). */
export async function runWatcherTick(opts: WatcherTickOptions): Promise<WatcherTickResult> {
  const openResult = openDb(opts.dbPath, opts.supportedSchemaVersions);

  let rows: WatcherExecutionRow[] = [];
  let dbRootsRaw: string[] = [];
  let degradedDb = false;
  if (openResult.ok) {
    try {
      rows = listExecutionsForWatcher(openResult.db as Database.Database);
      dbRootsRaw = listKnownProjectRoots(openResult.db as Database.Database);
    } finally {
      openResult.db.close();
    }
  } else if (openResult.reason === 'table-empty' || openResult.reason === 'db-missing') {
    // Db ainda NAO populada — exatamente o cenario ovo-e-galinha que a
    // descoberta via filesystem existe para resolver: um `state.json` novo em
    // disco e a primeira ingestao ainda nao rodou. `cstk recall --ingest` cria
    // e popula a db (verificado empiricamente: cstk 5.21.0 contra db
    // inexistente ⇒ exit 0, arquivo criado, executions populada). Prossegue
    // com rows vazias — descoberta somente via CSTK_PROJECT_PATHS.
    degradedDb = true;
  } else {
    // schema-mismatch / db-corrupt ⇒ tick ocioso por completo (Principio II):
    // ingerir contra uma db incompativel/corrompida nao ajudaria o painel a
    // ler o resultado e poderia agravar o estado.
    return { degradedDb: true, cstkUnresolved: false, activeCount: 0, fsDiscovered: 0, triggered: 0, skipped: 0 };
  }

  const activeRows = rows.filter(
    row => row.status === 'em_andamento' || row.status === 'aguardando_humano'
  );

  let skipped = 0;
  const targets: IngestTarget[] = [];
  const targeted = new Set<string>();

  // 1) Alvos vindos de execucoes ATIVAS na knowledge.db (descoberta original).
  for (const row of activeRows) {
    // Cadeia FR-008: env do operador > target_project_path da propria linha
    // (schema v9; a conexao com a db ja fechou — o valor UNTRUSTED viaja na
    // row e e validado aqui: realpath + diretorio + zonas proibidas).
    const projectPath =
      resolveProjectPath(row.project) ?? validateProjectRootPath(row.target_project_path);
    if (!projectPath) { skipped++; continue; } // FR-008/FR-012 — projeto nao mapeado

    const stateDir = deriveStateDir(projectPath, row.feature);
    if (!stateDir) { skipped++; continue; } // feature falhou anti-traversal (Decision 9)
    if (!existsSync(join(stateDir, 'state.json'))) { skipped++; continue; } // sem state.json no FS (FR-012)
    if (targeted.has(stateDir)) continue; // duas execucoes ativas no mesmo state-dir
    targeted.add(stateDir);
    targets.push({ stateDir, seedFirst: false });
  }

  // 2) State-dirs ja conhecidos da db (QUALQUER status) — classificam as
  //    descobertas do filesystem: dir conhecido-terminal ⇒ seedFirst.
  const knownStateDirs = new Set<string>();
  for (const row of rows) {
    const projectPath =
      resolveProjectPath(row.project) ?? validateProjectRootPath(row.target_project_path);
    if (!projectPath) continue;
    const stateDir = deriveStateDir(projectPath, row.feature);
    if (stateDir) knownStateDirs.add(stateDir);
  }

  // 3) Descoberta via filesystem sobre as raizes conhecidas (fix ovo-e-galinha):
  //    CSTK_PROJECT_PATHS (config do operador) + target_project_path distintos
  //    da db (UNTRUSTED ⇒ validados). Raizes deduplicadas por realpath — a
  //    mesma raiz pode chegar via env (path.resolve) e via db (realpath).
  const rootCandidates = [
    ...listConfiguredProjectPaths(),
    ...dbRootsRaw
      .map(validateProjectRootPath)
      .filter((p): p is string => p !== null),
  ];
  const seenRootReal = new Set<string>();
  let fsDiscovered = 0;
  for (const root of rootCandidates) {
    let real: string;
    try {
      real = realpathSync(root);
    } catch {
      continue; // raiz configurada mas inexistente no FS — degradacao graciosa
    }
    if (seenRootReal.has(real)) continue;
    seenRootReal.add(real);
    for (const stateDir of discoverStateDirsInRoot(root)) {
      if (targeted.has(stateDir)) continue; // ja alvo via execucao ativa
      targeted.add(stateDir);
      targets.push({ stateDir, seedFirst: knownStateDirs.has(stateDir) });
      fsDiscovered++;
    }
  }

  if (targets.length === 0) {
    // Ociosidade (FR-013, AC US1-3): NENHUM subprocesso disparado.
    return { degradedDb, cstkUnresolved: false, activeCount: activeRows.length, fsDiscovered: 0, triggered: 0, skipped };
  }

  const cstkBin = resolveCstkBinary();
  if (!cstkBin) {
    // Falha segura (Principio II): binario nao resolvido, nenhum subprocesso disparado.
    return {
      degradedDb,
      cstkUnresolved: true,
      activeCount: activeRows.length,
      fsDiscovered,
      triggered: 0,
      skipped: skipped + targets.length,
    };
  }

  const cap = opts.maxConcurrent ?? DEFAULT_MAX_CONCURRENT;
  const capped = targets.slice(0, cap); // bound de concorrencia por tick (Decision 9, item 3)
  const execImpl = opts.execFileImpl ?? defaultExecFile;
  const nowFn = opts.now ?? Date.now;
  const backoffMs = opts.backoffMs ?? DEFAULT_BACKOFF_MS;
  const timeoutMs = opts.subprocessTimeoutMs ?? DEFAULT_SUBPROCESS_TIMEOUT_MS;

  let triggered = 0;
  skipped += targets.length - capped.length; // excedentes ao cap desta tick

  await Promise.all(
    capped.map(async ({ stateDir, seedFirst }) => {
      if (inFlightStateDirs.has(stateDir)) { skipped++; return; } // ingestao anterior ainda em voo

      const cached = signatureCache.get(stateDir);
      const nowMs = nowFn();
      if (cached?.lastErrorAt !== null && cached?.lastErrorAt !== undefined && (nowMs - cached.lastErrorAt) < backoffMs) {
        skipped++; return; // backoff ativo apos falha persistente (Decision 9, item 3)
      }

      const sig = computeSignature(stateDir);
      if (sig !== null && cached?.signature === sig) {
        skipped++; return; // idempotencia (FR-014) — state.json nao mudou desde a ultima vista
      }

      if (seedFirst && cached === undefined) {
        // Primeira vista de um state-dir terminal ja conhecido: registra a
        // assinatura sem ingerir — proxima mudanca de mtime dispara normalmente.
        signatureCache.set(stateDir, { signature: sig, lastIngestAt: null, lastError: null, lastErrorAt: null });
        skipped++; return;
      }

      inFlightStateDirs.add(stateDir);
      try {
        await execImpl(cstkBin, ['recall', '--ingest', '--state-dir', stateDir, '--db', opts.dbPath], {
          timeout: timeoutMs,
          env: minimalSubprocessEnv(),
          cwd: stateDir,
        });
        signatureCache.set(stateDir, { signature: sig, lastIngestAt: nowMs, lastError: null, lastErrorAt: null });
        triggered++;
      } catch (err) {
        const message = err instanceof Error ? err.message : String(err);
        signatureCache.set(stateDir, {
          signature: cached?.signature ?? null,
          lastIngestAt: cached?.lastIngestAt ?? null,
          lastError: message,
          lastErrorAt: nowMs,
        });
        skipped++;
      } finally {
        inFlightStateDirs.delete(stateDir);
      }
    })
  );

  return { degradedDb, cstkUnresolved: false, activeCount: activeRows.length, fsDiscovered, triggered, skipped };
}

// ---------------------------------------------------------------------------
// Ciclo de vida do timer (task 2.1.1, 2.5.1, 2.5.2)
// ---------------------------------------------------------------------------

export interface WatcherHandle {
  stop: () => void;
}

export interface StartWatcherOptions extends Omit<WatcherTickOptions, 'now'> {
  intervalMs?: number;
  /** logger minimo — evita acoplar o modulo ao tipo concreto do Fastify logger */
  onTickError?: (err: unknown) => void;
}

/** Inicia o timer recorrente. Retorna handle com `stop()` para shutdown limpo (task 2.5.2). */
export function startIngestWatcher(opts: StartWatcherOptions): WatcherHandle {
  const interval = opts.intervalMs ?? DEFAULT_WATCH_INTERVAL_MS;
  const timer = setInterval(() => {
    runWatcherTick(opts).catch(err => {
      opts.onTickError?.(err);
    });
  }, interval);
  // unref: o timer do watcher NUNCA deve, por si so, impedir o processo de
  // encerrar (ex.: em testes/scripts que sobem o server e finalizam sem
  // shutdown explicito). server.addHook('onClose', stop) ainda cobre o
  // shutdown normal do processo long-running.
  timer.unref();
  return {
    stop: () => clearInterval(timer),
  };
}
