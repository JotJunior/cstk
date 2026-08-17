// test/exec.test.ts — cobertura de runtime/exec.ts, foco no mascaramento de
// valores sensiveis (dec-087, achado do command pai na validacao e2e real
// de mcp-direct-transport FASE 6).
//
// Achado: `runHelper` compunha `HelperExecutionError.message` com
// `args.join(" ")` (linha inteira do argv, incluindo `--token <valor>`) MAIS
// `error.message` bruto do Node — que o proprio `execFile` reconstroi
// internamente como "Command failed: <file> <args...>" — vazando o token DUAS
// vezes no mesmo erro sempre que o helper falha com um token real (invalido
// ou de execucao terminal). O `execFile` com array de argv (SEC-H1) continua
// correto — o vazamento era so na RENDERIZACAO da mensagem de erro.
//
// Fixtures POSIX reais em test/fixtures/ (execFile de verdade, sem mocks
// JS) — mesma filosofia de test/audit-log.test.ts e test/resolve.test.ts.

import { test } from "node:test";
import assert from "node:assert/strict";
import { join } from "node:path";
import { runHelper, HelperExecutionError } from "../src/runtime/exec.js";
import {
  resolveActiveSession,
  SessionMismatchError,
} from "../src/session/resolve.js";

const FIXTURES_DIR = join(process.cwd(), "test", "fixtures");
const FAILING_HELPER = join(FIXTURES_DIR, "fake-mcp-session-mismatch.sh");

const SENSITIVE_TOKEN = "super-secret-capability-token-4f8c9a2e";

test("runHelper: falha com --token no argv NUNCA ecoa o valor real na mensagem de erro", async () => {
  await assert.rejects(
    () =>
      runHelper(FAILING_HELPER, [
        "resolve",
        "--project-path",
        "/work",
        "--token",
        SENSITIVE_TOKEN,
      ]),
    (err: unknown) => {
      assert.ok(err instanceof HelperExecutionError);
      // O token NUNCA aparece em texto plano na mensagem — nem via
      // args.join(" ") reconstruido por nos, nem via error.message que o
      // Node monta internamente (execFile reconstroi "Command failed: <cmd>
      // <args>" incluindo o argv inteiro — a mesma fronteira precisa ser
      // saneada nos dois lugares).
      assert.doesNotMatch(err.message, new RegExp(SENSITIVE_TOKEN));
      // O mascaramento MUST deixar rastro auditavel (nao apagar em silencio).
      assert.match(err.message, /\*\*\*REDACTED\*\*\*/);
      // stderr bruto do helper continua intacto (SEC-M1 e responsabilidade
      // do CHAMADOR aplicar scrub — nao mudou; o achado era so na message).
      assert.match(err.stderr, /SESSION_MISMATCH/);
      return true;
    },
  );
});

test("runHelper: mascaramento e seletivo — flags nao-sensiveis permanecem legiveis no erro", async () => {
  await assert.rejects(
    () =>
      runHelper(FAILING_HELPER, [
        "resolve",
        "--project-path",
        "/work/meu-projeto-nao-secreto",
        "--token",
        SENSITIVE_TOKEN,
      ]),
    (err: unknown) => {
      assert.ok(err instanceof HelperExecutionError);
      // Prova de que a redacao e por FLAG reconhecida, nao um blackout geral
      // da mensagem inteira — um valor nao-sensivel continua visivel para
      // diagnostico.
      assert.match(err.message, /\/work\/meu-projeto-nao-secreto/);
      assert.doesNotMatch(err.message, new RegExp(SENSITIVE_TOKEN));
      return true;
    },
  );
});

test("runHelper: sem flag sensivel no argv, mensagem de erro inalterada (sem regressao)", async () => {
  await assert.rejects(
    () => runHelper(FAILING_HELPER, ["resolve", "--project-path", "/work"]),
    (err: unknown) => {
      assert.ok(err instanceof HelperExecutionError);
      assert.match(err.message, new RegExp(FAILING_HELPER.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));
      assert.match(err.message, /--project-path \/work/);
      assert.doesNotMatch(err.message, /REDACTED/);
      return true;
    },
  );
});

test("resolveActiveSession: SESSION_MISMATCH com token real invalido nao vaza o token na mensagem propagada (integracao, dec-087)", async () => {
  await assert.rejects(
    () =>
      resolveActiveSession({
        projectPath: "/work",
        token: SENSITIVE_TOKEN,
        helperPath: FAILING_HELPER,
      }),
    (err: unknown) => {
      assert.ok(err instanceof SessionMismatchError);
      // resolveActiveSession encadeia `cause.message` (o HelperExecutionError
      // vindo de runHelper) na propria mensagem — se runHelper vazasse, este
      // seria o ponto de saida real ate o transcript/log do orquestrador.
      assert.doesNotMatch(err.message, new RegExp(SENSITIVE_TOKEN));
      return true;
    },
  );
});
