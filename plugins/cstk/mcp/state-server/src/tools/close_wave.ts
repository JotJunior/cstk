// tools/close_wave.ts — tool `close_wave`: fecha a onda atomicamente
// (FR-003), com compensacao por pre-imagem.
//
// Delega para [VERIFICADO]:
//   state-ondas.sh end --state-dir <SD> --motivo-termino <M>
//     [--add-etapa <token>]* [--proxima-agendada-para <ISO>]
//     [--next-instruction <texto>]
//     [--advance [--terminal-phase <fase>]]  (wave-close-advance FR-002)
//   secrets-filter.sh for-backup --wave-number <N> < (state-rw.sh read) \
//     > <state-dir>/backups/wave-<NNN>.json
//   state-rw.sh sha256-update --state-dir <SD>
//
// Ref: docs/specs/state-mcp-server/contracts/mcp-tools.md §Tool: close_wave
//      docs/specs/state-mcp-server/research.md Decision 3
//
// ORDEM (research.md Decision 3 — "Alternatives considered" ja REJEITA
// explicitamente a ordem inversa "end primeiro, backup depois": "inverte o
// risco para o lado ruim: onda fechada sem backup e a falha que a spec
// quer proibir"):
//   1. capturar pre-imagem (state.json + .sha256, OU state.db+wal+shm,
//      conforme backend — [VERIFICADO: _sr_backend em _state-rw-db.sh:42,
//      heuristica C2 por presenca de state.db])
//   2. gerar o backup ESCRUBADO da onda (secrets-filter.sh for-backup),
//      gravar em <state-dir>/backups/wave-<NNN>.json (mesmo path/formato
//      de nome do Loop principal do orquestrador, passo 8 — ver
//      global/agents/agente-00c-feature-orchestrator.md)
//   3. state-ondas.sh end -- a MUTACAO
//   4. state-rw.sh sha256-update -- selo (REDUNDANTE sob backend json:
//      `end` ja recalcula `state.json.sha256` na propria funcao
//      [VERIFICADO: state-ondas.sh `_so_cmd_end` chama `_so_update_sha` na
//      ultima linha antes do hook de retro-marco] — mantido mesmo assim
//      por paridade EXATA com o Loop principal do orquestrador e por
//      completude sob backend sqlite, onde e no-op documentado
//      [VERIFICADO: `_sr_cmd_sha256_update`, C7/dec-025: "sob SQLite nao ha
//      hash derivado a manter — a verificacao de integridade passa a ser
//      PRAGMA integrity_check"])
//   5. QUALQUER falha em 2-4: restaurar a pre-imagem, responder
//      `CLOSE_ROLLED_BACK` ("a onda permanece aberta" observavel — o
//      restore e idempotente/seguro mesmo quando a falha ocorreu ANTES da
//      mutacao, ja que restaurar bytes identicos sobre si mesmos e um
//      no-op).
//
// NOTA DE CORRECAO EMPIRICA #1 (Principio VI): `contracts/mcp-tools.md`
// descrevia a delegacao como `cat state.json | secrets-filter.sh
// for-backup` (espelhando o Loop principal do orquestrador). Isso so
// funciona sob backend `json` — sob backend `sqlite` nao ha garantia de
// `state.json` atualizado no disco. `state-rw.sh read` [VERIFICADO:
// `_sr_cmd_read`, state-rw.sh:536-558] e a via BACKEND-AGNOSTICA ja usada
// por `_so_export_snapshot` para o mesmo proposito ("Opcao A" documentada
// no cabecalho dessa funcao) — usada aqui em vez de ler `state.json`
// diretamente do disco.
//
// NOTA DE CORRECAO EMPIRICA #2 (Principio VI): `result.state_sha256` no
// contrato [PROPOSTA] era tipado como `string` (nao-nulavel). Sob backend
// sqlite nao existe `state.json.sha256` (C7/dec-025 acima) — forcar um
// valor aqui seria fabricar dado (Principio VI). Corrigido para
// `string | null`: `null` sob backend sqlite.
//
// NOTA DE CORRECAO EMPIRICA #3 (Principio VI, resolve ambiguidade entre
// research.md Decision 3 e tasks.md 4.2.3): a task 4.2.3 descrevia o teste
// de falha simulada como "interromper apos a escrita no banco e antes do
// backup" — fraseado que sugere a ordem end-entao-backup, o OPOSTO da
// ordem ja decidida e ratificada em research.md Decision 3 (que rejeita
// essa ordem explicitamente, com "Alternatives considered" documentando o
// motivo). Implementado conforme a Decision 3 ja ratificada; tasks.md foi
// atualizada nesta mesma onda para descrever o cenario de falha na ordem
// realmente implementada.

import { readFile, writeFile, copyFile, mkdir, mkdtemp, rm } from "node:fs/promises";
import { existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { z } from "zod";
import {
  runHelper,
  resolveScriptsDir,
  HelperExecutionError,
  formatToolError,
  type McpToolErrorCode,
} from "../runtime/exec.js";
import { sanitizeForLlmContext } from "../runtime/sanitize.js";
import {
  matchesResolvedSession,
  type ResolvedSession,
} from "../session/resolve.js";
import { IDENTIFIER_PATTERN } from "../runtime/identifiers.js";

const MAX_REASON_BYTES = 2048; // 2 KiB (SEC-M1)

function sanitizeHelperReason(stderr: string): string {
  return sanitizeForLlmContext(stderr, MAX_REASON_BYTES);
}

// Uniao fechada [VERIFICADO: state-ondas.sh `_so_cmd_end`, case "$_motivo"
// linhas 713-716].
const TERMINATION_REASONS = [
  "etapa_concluida_avancando",
  "threshold_proxy_atingido",
  "bloqueio_humano",
  "aborto",
  "concluido",
] as const;

export const closeWaveInputShape = {
  session_id: z.string().min(1, "session_id obrigatorio"),
  termination_reason: z.enum(TERMINATION_REASONS),
  // Cada item casa IDENTIFIER_PATTERN [VERIFICADO: `_so_is_stage_token`,
  // state-ondas.sh — mesma regex ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$].
  executed_stages: z
    .array(
      z
        .string()
        .regex(
          IDENTIFIER_PATTERN,
          "executed_stages[] deve casar com ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$",
        ),
    )
    .nullable()
    .optional(),
  next_scheduled_for: z.string().nullable().optional(),
  next_instruction: z.string().nullable().optional(),
  // wave-close-advance FR-002: avanco atomico do ponteiro no mesmo write
  // do fechamento (state-ondas.sh end --advance). So valido com
  // termination_reason=etapa_concluida_avancando — a validacao semantica
  // fica no helper (fail-closed, exit 2), paridade com o caminho Bash.
  advance: z.boolean().nullable().optional(),
  terminal_phase: z
    .string()
    .regex(
      IDENTIFIER_PATTERN,
      "terminal_phase deve casar com ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$",
    )
    .nullable()
    .optional(),
} as const;

const closeWaveInputSchema = z.object(closeWaveInputShape);

export type CloseWaveInput = z.infer<typeof closeWaveInputSchema>;

export type CloseWaveOutcome = "accepted" | "rejected";
export type CloseWaveStage = "precondition" | "delegation" | null;

export interface CloseWaveResponse {
  readonly outcome: CloseWaveOutcome;
  readonly reason: string | null;
  readonly stage: CloseWaveStage;
  readonly result: {
    readonly wave_id: string;
    readonly backup_path: string;
    // null sob backend sqlite (C7/dec-025 — sem hash derivado a manter).
    // Ver NOTA DE CORRECAO EMPIRICA #2 no cabecalho do arquivo.
    readonly state_sha256: string | null;
  } | null;
}

export interface CloseWaveDeps {
  readonly session: ResolvedSession;
  readonly env?: NodeJS.ProcessEnv;
  readonly ondasHelperPath?: string;
  readonly stateRwHelperPath?: string;
  readonly secretsFilterHelperPath?: string;
}

const WAVE_ID_SUFFIX_PATTERN = /^onda-([0-9]{3,})$/;

/**
 * Heuristica C2 [VERIFICADO: `_sr_backend`, _state-rw-db.sh:42]: "sqlite" se
 * `state.db` existe no state-dir, senao "json". Reimplementada aqui (nao ha
 * subcomando publico que exponha o backend) por ser uma checagem de
 * presenca de arquivo estavel e documentada, nao um comportamento inferido.
 */
function detectBackend(stateDir: string): "json" | "sqlite" {
  return existsSync(join(stateDir, "state.db")) ? "sqlite" : "json";
}

interface PreImageFile {
  readonly relPath: string;
  readonly tmpPath: string;
  readonly existed: boolean;
}

interface PreImage {
  readonly dir: string;
  readonly files: readonly PreImageFile[];
}

/** Copia os artefatos mutaveis do backend ativo para uma area temporaria. */
async function capturePreImage(
  stateDir: string,
  backend: "json" | "sqlite",
): Promise<PreImage> {
  const dir = await mkdtemp(join(tmpdir(), "cstk-close-wave-"));
  const names =
    backend === "sqlite"
      ? ["state.db", "state.db-wal", "state.db-shm"]
      : ["state.json", "state.json.sha256"];
  const files: PreImageFile[] = [];
  for (const name of names) {
    const src = join(stateDir, name);
    const tmpPath = join(dir, name);
    const existed = existsSync(src);
    if (existed) {
      await copyFile(src, tmpPath);
    }
    files.push({ relPath: name, tmpPath, existed });
  }
  return { dir, files };
}

/** Restaura os artefatos capturados (remove os que nao existiam antes). */
async function restorePreImage(
  stateDir: string,
  files: readonly PreImageFile[],
): Promise<void> {
  for (const file of files) {
    const dst = join(stateDir, file.relPath);
    if (file.existed) {
      await copyFile(file.tmpPath, dst);
    } else {
      await rm(dst, { force: true });
    }
  }
}

async function cleanupPreImage(dir: string): Promise<void> {
  await rm(dir, { recursive: true, force: true });
}

function helperErrorMessage(err: unknown): string {
  if (err instanceof HelperExecutionError) return err.diagnostic?.message ?? err.stderr;
  if (err instanceof Error) return err.message;
  return String(err);
}

/**
 * Handler da tool `close_wave`. Ver ORDEM e NOTAS DE CORRECAO no cabecalho
 * do arquivo.
 */
export async function handleCloseWave(
  input: CloseWaveInput,
  deps: CloseWaveDeps,
): Promise<CloseWaveResponse> {
  const { session, env = process.env } = deps;

  if (!matchesResolvedSession(session, input.session_id)) {
    return {
      outcome: "rejected",
      reason: formatToolError({
        code: "SESSION_MISMATCH",
        message: "session_id nao corresponde ao token de capacidade desta sessao",
      }),
      stage: "precondition",
      result: null,
    };
  }

  const scriptsDir = resolveScriptsDir(env);
  const ondasHelperPath = deps.ondasHelperPath ?? join(scriptsDir, "state-ondas.sh");
  const stateRwHelperPath = deps.stateRwHelperPath ?? join(scriptsDir, "state-rw.sh");
  const secretsFilterHelperPath =
    deps.secretsFilterHelperPath ?? join(scriptsDir, "secrets-filter.sh");

  // Precondicao NO_OPEN_WAVE + resolucao do wave_id corrente (necessario
  // para nomear o backup `wave-<NNN>.json`, mesmo padrao do Loop principal
  // do orquestrador — passo 8).
  let waveId: string;
  try {
    const { stdout: statusOut } = await runHelper(ondasHelperPath, [
      "wave-status",
      "--state-dir",
      session.stateDir,
    ]);
    if (statusOut.trim() !== "open") {
      return {
        outcome: "rejected",
        reason: formatToolError({
          code: "NO_OPEN_WAVE",
          message: "nenhuma onda em andamento (rode open_wave primeiro)",
        }),
        stage: "precondition",
        result: null,
      };
    }
    const { stdout: idOut } = await runHelper(ondasHelperPath, [
      "current-id",
      "--state-dir",
      session.stateDir,
    ]);
    waveId = idOut.trim();
  } catch (err) {
    return {
      outcome: "rejected",
      reason: sanitizeHelperReason(
        formatToolError({
          code: "HELPER_FAILED",
          message: `wave-status/current-id: ${helperErrorMessage(err)}`,
        }),
      ),
      stage: "delegation",
      result: null,
    };
  }

  // `.match()` em vez de `WAVE_ID_SUFFIX_PATTERN.exec()`: a assercao estatica
  // SEC-H1 (test/static-security.test.ts) proibe QUALQUER `exec(`/`execSync(`
  // em src/ (previne child_process.exec) e casa por `\b(exec|execSync)\s*\(`
  // -- que tambem pega `RegExp.prototype.exec()` como falso-positivo. `.match()`
  // e semanticamente equivalente aqui (grupo de captura unico) e nao aciona o
  // scanner.
  const suffixMatch = waveId.match(WAVE_ID_SUFFIX_PATTERN);
  if (!suffixMatch) {
    return {
      outcome: "rejected",
      reason: sanitizeHelperReason(
        formatToolError({
          code: "HELPER_FAILED",
          message: `wave_id '${waveId}' fora do padrao esperado (onda-NNN)`,
        }),
      ),
      stage: "delegation",
      result: null,
    };
  }
  // ex.: "013" -- zero-padded, usado no nome do arquivo de backup.
  const waveSuffix = suffixMatch[1] as string;
  // ex.: "13" -- inteiro sem padding, para --wave-number (mesma convencao
  // de `_so_cmd_start`: `_num` sem padding gera `_id` com printf '%03d').
  const waveNumber = String(Number.parseInt(waveSuffix, 10));

  const backend = detectBackend(session.stateDir);
  const preImage = await capturePreImage(session.stateDir, backend);

  const backupDir = join(session.stateDir, "backups");
  const backupPath = join(backupDir, `wave-${waveSuffix}.json`);

  /** Compensacao (research.md Decision 3, passo 5): restaura a pre-imagem e responde CLOSE_ROLLED_BACK. */
  async function rollback(code: McpToolErrorCode, message: string): Promise<CloseWaveResponse> {
    try {
      await restorePreImage(session.stateDir, preImage.files);
    } finally {
      await cleanupPreImage(preImage.dir);
    }
    return {
      outcome: "rejected",
      reason: sanitizeHelperReason(
        formatToolError({
          code: "CLOSE_ROLLED_BACK",
          message: `${code}: ${message} (pre-imagem restaurada, onda permanece aberta)`,
        }),
      ),
      stage: "delegation",
      result: null,
    };
  }

  // 2. Backup ESCRUBADO da onda: `state-rw.sh read` (backend-agnostico —
  // NOTA DE CORRECAO EMPIRICA #1) alimenta `secrets-filter.sh for-backup`
  // via stdin; o envelope resultante e gravado em disco pela propria tool.
  try {
    const { stdout: stateContent } = await runHelper(stateRwHelperPath, [
      "read",
      "--state-dir",
      session.stateDir,
    ]);
    const { stdout: envelope } = await runHelper(
      secretsFilterHelperPath,
      ["for-backup", "--wave-number", waveNumber],
      { stdin: stateContent },
    );
    await mkdir(backupDir, { recursive: true });
    await writeFile(backupPath, envelope, "utf8");
  } catch (err) {
    return rollback("HELPER_FAILED", `wave-backup: ${helperErrorMessage(err)}`);
  }

  // 3. Mutacao: state-ondas.sh end.
  const endArgs = [
    "end",
    "--state-dir",
    session.stateDir,
    "--motivo-termino",
    input.termination_reason,
  ];
  for (const stage of input.executed_stages ?? []) {
    endArgs.push("--add-etapa", stage);
  }
  if (input.next_scheduled_for) {
    endArgs.push("--proxima-agendada-para", input.next_scheduled_for);
  }
  if (input.next_instruction) {
    endArgs.push("--next-instruction", input.next_instruction);
  }
  if (input.advance) {
    endArgs.push("--advance");
    if (input.terminal_phase) {
      endArgs.push("--terminal-phase", input.terminal_phase);
    }
  }

  try {
    await runHelper(ondasHelperPath, endArgs);
  } catch (err) {
    const message = helperErrorMessage(err);
    // Classificacao defensiva (o inputSchema/zod ja bloqueia
    // INVALID_TERMINATION_REASON/INVALID_STAGE_TOKEN ANTES do handler —
    // mesmo padrao de defesa em profundidade de record_decision.ts).
    const code: McpToolErrorCode = message.includes("motivo invalido")
      ? "INVALID_TERMINATION_REASON"
      : message.includes("--add-etapa aceita token")
        ? "INVALID_STAGE_TOKEN"
        : message.includes("nao ha onda em andamento")
          ? "NO_OPEN_WAVE"
          : "HELPER_FAILED";
    return rollback(code, message);
  }

  // 4. Selo de integridade (redundante sob backend json — ver NOTA no
  // cabecalho; no-op documentado sob backend sqlite, C7/dec-025).
  let stateSha256: string | null = null;
  try {
    await runHelper(stateRwHelperPath, ["sha256-update", "--state-dir", session.stateDir]);
    if (backend === "json") {
      stateSha256 = (
        await readFile(join(session.stateDir, "state.json.sha256"), "utf8")
      ).trim();
    }
  } catch (err) {
    return rollback("HELPER_FAILED", `sha256-update: ${helperErrorMessage(err)}`);
  }

  await cleanupPreImage(preImage.dir);

  return {
    outcome: "accepted",
    reason: null,
    stage: null,
    result: { wave_id: waveId, backup_path: backupPath, state_sha256: stateSha256 },
  };
}
