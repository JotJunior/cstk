// tools/record_task.ts — tool `record_task`: registra outcome de task,
// idempotente por `task_id` (FR-004).
//
// Delega para [VERIFICADO: global/skills/agente-00c-runtime/scripts/state-ondas.sh
// _so_cmd_record_task, linhas 973-1056]:
//   state-ondas.sh record-task --state-dir <SD> --task-id --outcome
//     [--titulo] [--wave-id] [--testes-rodados] [--testes-passados]
//     [--lint-ok] [--arquivos] [--origem] [--if-absent]
//
// Ref: docs/specs/state-mcp-server/contracts/mcp-tools.md §Tool: record_task
//
// NOTA DE CORRECAO EMPIRICA (Principio VI — nao inventar dados, mesmo
// padrao ja aplicado em tools/record_skill.ts):
//
// 1. [CORRIGIDO] `result.operation` ("inserted"|"updated") foi removido do
//    contrato [PROPOSTA]. Leitura do codigo-fonte real [VERIFICADO:
//    state-ondas.sh:1017-1056 e _state-ondas-db.sh:372-375] mostra que
//    AMBOS os backends imprimem em stdout a CONTAGEM total de
//    `.tasks`/`task_outcome` da execucao apos o upsert — nunca um par
//    {task_id, operation}. Nao ha como derivar "inserted" vs "updated" do
//    stdout sem uma leitura extra fragil (e, sob `--if-absent` com task ja
//    existente, o upsert nem executa — "updated" seria uma mentira). Este
//    arquivo reflete o comportamento verificado (`result.tasks_total_count`).
// 2. [CORRIGIDO] `NO_OPEN_WAVE` no contrato [PROPOSTA] descrevia uma
//    checagem que o helper NAO faz: `record-task` nunca verifica se a
//    ultima onda esta aberta ou fechada, so usa `.waves[-1].id` como
//    default best-effort [VERIFICADO: state-ondas.sh:1026-1029]. A tool
//    IMPOE essa pre-condicao explicitamente (mesmo padrao de
//    tools/open_wave.ts para `WAVE_ALREADY_OPEN`: tornar fisicamente
//    impossivel o que antes dependia do LLM lembrar a guarda).
// 3. Fecha o gap CHK016 (task 3.8.3): `WAVE_ID_NOT_FOUND` — quando
//    `wave_id` e informado explicitamente e nao corresponde a nenhuma onda
//    existente, a tool rejeita ANTES de delegar (o helper aceitaria
//    silenciosamente qualquer string).

import { join } from "node:path";
import { z } from "zod";
import {
  runHelper,
  resolveScriptsDir,
  HelperExecutionError,
} from "../runtime/exec.js";
import { sanitizeForLlmContext } from "../runtime/sanitize.js";
import {
  matchesResolvedSession,
  type ResolvedSession,
} from "../session/resolve.js";
import { IDENTIFIER_PATTERN, WAVE_ID_PATTERN, isSafeRelativePath } from "../runtime/identifiers.js";

const MAX_REASON_BYTES = 2048; // 2 KiB (SEC-M1)

function sanitizeHelperReason(stderr: string): string {
  return sanitizeForLlmContext(stderr, MAX_REASON_BYTES);
}

export const recordTaskInputShape = {
  session_id: z.string().min(1, "session_id obrigatorio"),
  task_id: z
    .string()
    .regex(IDENTIFIER_PATTERN, "task_id deve casar com ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$"),
  outcome: z.enum(["pass", "fail"]),
  title: z.string().nullable().optional(),
  wave_id: z
    .string()
    .regex(WAVE_ID_PATTERN, "wave_id deve casar com ^onda-[0-9]{3,}$")
    .nullable()
    .optional(),
  tests_run: z.number().int().min(0).nullable().optional(),
  tests_passed: z.number().int().min(0).nullable().optional(),
  lint_ok: z.boolean().nullable().optional(),
  touched_files: z.array(z.string()).nullable().optional(),
  source: z.string().nullable().optional(),
  if_absent: z.boolean().nullable().optional(),
} as const;

// EXPORTADO (nao apenas a `shape`) pelo MESMO motivo de record_decision.ts:
// `registerTool` aceita `AnySchema` completo em `inputSchema`, e e isso que
// permite o `.superRefine()` (TESTS_PASSED_EXCEEDS_RUN, touched_files
// inseguro) rodar DENTRO da validacao do SDK, antes do handler.
export const recordTaskInputSchema = z
  .object(recordTaskInputShape)
  .superRefine((val, ctx) => {
    const testsRun = val.tests_run ?? 0;
    const testsPassed = val.tests_passed ?? 0;
    // TESTS_PASSED_EXCEEDS_RUN [VERIFICADO: state-ondas.sh:1009].
    if (testsPassed > testsRun) {
      ctx.addIssue({
        code: "custom",
        path: ["tests_passed"],
        message: `TESTS_PASSED_EXCEEDS_RUN: tests_passed (${testsPassed}) > tests_run (${testsRun})`,
      });
    }
    if (val.touched_files) {
      for (const [idx, file] of val.touched_files.entries()) {
        if (!isSafeRelativePath(file)) {
          ctx.addIssue({
            code: "custom",
            path: ["touched_files", idx],
            message: `touched_files[${idx}] deve ser path relativo (sem absoluto, '..' ou NUL): '${file}'`,
          });
        }
      }
    }
  });

export type RecordTaskInput = z.infer<typeof recordTaskInputSchema>;

export type RecordTaskOutcome = "accepted" | "rejected";
export type RecordTaskStage = "precondition" | "delegation" | null;

export interface RecordTaskResponse {
  readonly outcome: RecordTaskOutcome;
  readonly reason: string | null;
  readonly stage: RecordTaskStage;
  readonly result: {
    readonly task_id: string;
    readonly tasks_total_count: number;
  } | null;
}

export interface RecordTaskDeps {
  readonly session: ResolvedSession;
  readonly env?: NodeJS.ProcessEnv;
  /** Override do path de `state-ondas.sh`. */
  readonly helperPath?: string;
  /** Override do path de `state-rw.sh` (usado nas pre-condicoes de leitura). */
  readonly stateRwHelperPath?: string;
}

async function readWaveIds(
  stateRwHelperPath: string,
  stateDir: string,
): Promise<readonly string[]> {
  const { stdout } = await runHelper(stateRwHelperPath, [
    "get",
    "--state-dir",
    stateDir,
    "--field",
    "(.waves // []) | map(.id)",
  ]);
  const parsed: unknown = JSON.parse(stdout);
  if (!Array.isArray(parsed)) return [];
  return parsed.filter((v): v is string => typeof v === "string");
}

/**
 * Handler da tool `record_task`. Pre-condicoes IMPOSTAS PELA TOOL (o
 * helper `record-task` nao as verifica — ver NOTA DE CORRECAO EMPIRICA no
 * cabecalho do arquivo):
 *   1. NO_OPEN_WAVE — exige `wave-status == open` (Edge Case "fora de
 *      ordem", mesma semantica de `record_skill`/`open_wave`).
 *   2. WAVE_ID_NOT_FOUND — quando `wave_id` e explicito, exige que exista
 *      em `.waves[].id` (fecha CHK016).
 */
export async function handleRecordTask(
  input: RecordTaskInput,
  deps: RecordTaskDeps,
): Promise<RecordTaskResponse> {
  const { session, env = process.env } = deps;

  if (!matchesResolvedSession(session, input.session_id)) {
    return {
      outcome: "rejected",
      reason: "SESSION_MISMATCH: session_id nao corresponde ao token de capacidade desta sessao",
      stage: "precondition",
      result: null,
    };
  }

  const scriptsDir = resolveScriptsDir(env);
  const helperPath = deps.helperPath ?? join(scriptsDir, "state-ondas.sh");
  const stateRwHelperPath = deps.stateRwHelperPath ?? join(scriptsDir, "state-rw.sh");

  try {
    const { stdout: statusOut } = await runHelper(helperPath, [
      "wave-status",
      "--state-dir",
      session.stateDir,
    ]);
    if (statusOut.trim() !== "open") {
      return {
        outcome: "rejected",
        reason: "NO_OPEN_WAVE: nenhuma onda em andamento (rode open_wave primeiro)",
        stage: "precondition",
        result: null,
      };
    }
  } catch (err) {
    const message =
      err instanceof HelperExecutionError
        ? (err.diagnostic?.message ?? err.stderr)
        : err instanceof Error
          ? err.message
          : String(err);
    return {
      outcome: "rejected",
      reason: sanitizeHelperReason(`HELPER_FAILED: wave-status: ${message}`),
      stage: "delegation",
      result: null,
    };
  }

  if (input.wave_id) {
    try {
      const waveIds = await readWaveIds(stateRwHelperPath, session.stateDir);
      if (!waveIds.includes(input.wave_id)) {
        return {
          outcome: "rejected",
          reason: `WAVE_ID_NOT_FOUND: wave_id '${input.wave_id}' nao corresponde a nenhuma onda existente`,
          stage: "precondition",
          result: null,
        };
      }
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      return {
        outcome: "rejected",
        reason: sanitizeHelperReason(`HELPER_FAILED: leitura de .waves: ${message}`),
        stage: "delegation",
        result: null,
      };
    }
  }

  const args = [
    "record-task",
    "--state-dir",
    session.stateDir,
    "--task-id",
    input.task_id,
    "--outcome",
    input.outcome,
  ];
  if (input.title) {
    args.push("--titulo", input.title);
  }
  if (input.wave_id) {
    args.push("--wave-id", input.wave_id);
  }
  if (input.tests_run !== undefined && input.tests_run !== null) {
    args.push("--testes-rodados", String(input.tests_run));
  }
  if (input.tests_passed !== undefined && input.tests_passed !== null) {
    args.push("--testes-passados", String(input.tests_passed));
  }
  if (input.lint_ok !== undefined && input.lint_ok !== null) {
    args.push("--lint-ok", input.lint_ok ? "true" : "false");
  }
  args.push("--arquivos", JSON.stringify(input.touched_files ?? []));
  if (input.source) {
    args.push("--origem", input.source);
  }
  if (input.if_absent) {
    args.push("--if-absent");
  }

  try {
    const { stdout } = await runHelper(helperPath, args);
    const count = Number.parseInt(stdout.trim(), 10);
    if (!Number.isFinite(count) || Number.isNaN(count)) {
      return {
        outcome: "rejected",
        reason: sanitizeHelperReason(
          `HELPER_FAILED: saida inesperada de state-ondas.sh record-task: '${stdout.trim()}'`,
        ),
        stage: "delegation",
        result: null,
      };
    }
    return {
      outcome: "accepted",
      reason: null,
      stage: null,
      result: { task_id: input.task_id, tasks_total_count: count },
    };
  } catch (err) {
    if (err instanceof HelperExecutionError) {
      const message = err.diagnostic?.message ?? err.stderr;
      const code = message.includes("--testes-passados")
        ? "TESTS_PASSED_EXCEEDS_RUN"
        : "HELPER_FAILED";
      return {
        outcome: "rejected",
        reason: sanitizeHelperReason(`${code}: ${message}`),
        stage: "delegation",
        result: null,
      };
    }
    return {
      outcome: "rejected",
      reason: sanitizeHelperReason(
        `HELPER_FAILED: ${err instanceof Error ? err.message : String(err)}`,
      ),
      stage: "delegation",
      result: null,
    };
  }
}
