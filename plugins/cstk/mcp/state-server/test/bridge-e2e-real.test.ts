// test/bridge-e2e-real.test.ts — task 5.1.1 (Cenario 1, OBRIGATORIO do
// quickstart, docs/specs/human-bridge/quickstart.md).
//
// Fecha a lacuna explicitamente declarada em
// `docs/specs/human-bridge/contracts/mcp-tool-ask-operator.md` §10:
// "Long-poll ponta-a-ponta contra o painel: NAO exercitado" — ate esta
// tarefa, TODOS os testes de `ask_operator`/`bridge-client` usam
// `bridgeClient`/`fetchImpl` FAKES (ver `test/ask_operator.test.ts`,
// `test/bridge-client.test.ts`) e uma fixture POSIX no lugar do
// `state-rw.sh` REAL (`test/fixtures/fake-ask-operator-state-rw-captures-set.sh`).
// Nenhum teste ate aqui sobe o servidor Fastify REAL do painel nem escreve
// de fato num `bridge.db` sqlite.
//
// Este teste sobe:
//   1. o servidor REAL do painel (`panel/apps/server/dist/index.js`, o MESMO
//      modulo que producao roda) como um PROCESSO SEPARADO, escutando numa
//      porta livre real, com `bridge.db` sqlite real num arquivo tmp isolado;
//   2. `handleAskOperator` (mesma funcao usada pela tool MCP `ask_operator`
//      em producao) SEM `bridgeClient` mockado — usa `createBridgeClient`
//      real, HTTP real via `fetch`, contra o servidor do passo 1;
//   3. o `state-rw.sh` REAL instalado (`~/.claude/skills/agente-00c-runtime/
//      scripts/state-rw.sh`) para inicializar um state-dir real e depois
//      ler `.operator_answers[]` de volta.
//
// "Responder via painel real" e simulado pela MESMA chamada HTTP que a UI
// do painel faz (`POST /api/v1/bridge/interventions/:id/answer`,
// `apps/web/src/lib/hooks-bridge.ts`) — nao ha automacao de browser aqui
// (fora do orcamento desta tarefa), mas o contrato HTTP exercitado e
// identico ao que a UI usa, contra o MESMO `routes/bridge.ts` real.
//
// Se este teste passar, o achado do contrato §10 muda de `[PROPOSTA]` para
// `[MEDIDO]` — a atualizacao do contrato deve citar a evidencia literal da
// execucao deste arquivo (ver Decisao registrada na onda que fechou 5.1.1).

import { test } from "node:test";
import assert from "node:assert/strict";
import { spawn, execFile as execFileCb } from "node:child_process";
import { promisify } from "node:util";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { createServer } from "node:net";
import {
  handleAskOperator,
  askOperatorInputSchema,
} from "../src/tools/ask_operator.js";
import type { ResolvedSession } from "../src/session/resolve.js";

const execFile = promisify(execFileCb);

// dist/test/bridge-e2e-real.test.js -> dist -> state-server -> mcp -> <repo root>
const HERE = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = join(HERE, "..", "..", "..", "..");
const PANEL_SERVER_DIR = join(REPO_ROOT, "panel", "apps", "server");
const RUNTIME_SCRIPTS_DIR = join(
  process.env["HOME"] ?? "",
  ".claude",
  "skills",
  "agente-00c-runtime",
  "scripts",
);
const STATE_RW = join(RUNTIME_SCRIPTS_DIR, "state-rw.sh");

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/** Porta livre real via bind efemero (porta 0) — evita colisao entre execucoes. */
async function findFreePort(): Promise<number> {
  return await new Promise((resolve, reject) => {
    const srv = createServer();
    srv.on("error", reject);
    srv.listen(0, "127.0.0.1", () => {
      const addr = srv.address();
      if (addr && typeof addr === "object") {
        const port = addr.port;
        srv.close(() => resolve(port));
      } else {
        srv.close(() => reject(new Error("nao foi possivel obter porta livre")));
      }
    });
  });
}

async function waitForHealth(baseUrl: string, timeoutMs: number): Promise<void> {
  const deadline = Date.now() + timeoutMs;
  let lastErr: unknown = null;
  while (Date.now() < deadline) {
    try {
      const res = await fetch(`${baseUrl}/api/v1/health`);
      if (res.status === 200) return;
    } catch (err) {
      lastErr = err;
    }
    await sleep(150);
  }
  throw new Error(`servidor real do painel nao respondeu /health a tempo: ${String(lastErr)}`);
}

interface QueueIntervention {
  readonly questionId: string;
  readonly question: string;
}
interface QueueEnvelope {
  readonly data: { readonly interventions: readonly QueueIntervention[] } | null;
}

test(
  "5.1.1 [E2E REAL OBRIGATORIO] ask_operator roundtrip contra servidor+banco de fato rodando",
  async () => {
    const workDir = await mkdtemp(join(tmpdir(), "human-bridge-e2e-"));
    const bridgeDbPath = join(workDir, "bridge.db");
    // Isolamento deliberado: NUNCA o knowledge.db real do operador (5.1.2
    // trata disso como invariante propria; aqui so evita side-effect).
    const knowledgeDbPath = join(workDir, "knowledge-inexistente.db");
    const sessionsRoot = join(workDir, "sessions-vazio");
    const stateDir = join(workDir, "state-dir");
    const port = await findFreePort();
    const baseUrl = `http://127.0.0.1:${port}`;

    await execFile(STATE_RW, [
      "init",
      "--state-dir",
      stateDir,
      "--execucao-id",
      "human-bridge-e2e-test",
      "--projeto-alvo-path",
      workDir,
      "--descricao",
      "teste E2E real do ask_operator (task 5.1.1)",
    ]);

    const child = spawn(process.execPath, ["dist/index.js"], {
      cwd: PANEL_SERVER_DIR,
      env: {
        ...process.env,
        PORT: String(port),
        HOST: "127.0.0.1",
        CSTK_BRIDGE_DB: bridgeDbPath,
        CSTK_KNOWLEDGE_DB: knowledgeDbPath,
        CSTK_SESSIONS_ROOT: sessionsRoot,
        LOG_LEVEL: "error",
      },
      stdio: ["ignore", "pipe", "pipe"],
    });
    const stderrChunks: Buffer[] = [];
    child.stderr.on("data", (d: Buffer) => stderrChunks.push(d));

    let resultPromise: ReturnType<typeof handleAskOperator> | null = null;
    try {
      await waitForHealth(baseUrl, 15000);

      const session: ResolvedSession = {
        token: "e2e-real-token",
        stateDir,
        executionKind: "feature-00c",
        shortName: "human-bridge",
        targetProjectPath: workDir,
        mode: "direct",
        container: "-",
      };

      const input = askOperatorInputSchema.parse({
        session_id: "e2e-real-token",
        question: "prosseguir com o roundtrip real (5.1.1)?",
        kind: "choice",
        options: ["sim", "nao"],
        default_value: "nao",
      });

      // clientTimeoutMs=120000 -> effectiveTimeoutMs default = 120000-60000
      // = 60000ms = ASK_MIN_TIMEOUT_MS exato (piso legal, R-CLOCK-4/R-CLOCK-7)
      // — o teto so importa no caminho de FALHA; o caminho feliz resolve em
      // menos de 1s (pollIntervalMs=100).
      resultPromise = handleAskOperator(input, {
        session,
        env: { ...process.env, CSTK_MCP_SCRIPTS_DIR: RUNTIME_SCRIPTS_DIR },
        panelUrl: baseUrl,
        clientTimeoutMs: 120000,
        pollIntervalMs: 100,
      });

      // "Responder via painel real": mesma chamada HTTP que a UI do painel
      // faz (contrato §7) contra o MESMO servidor/rota real — sem bridgeClient
      // mockado, sem fetch injetado.
      let questionId: string | null = null;
      const queueDeadline = Date.now() + 10000;
      while (Date.now() < queueDeadline && !questionId) {
        const res = await fetch(`${baseUrl}/api/v1/bridge/interventions?state=open`);
        const body = (await res.json()) as QueueEnvelope;
        const found = body.data?.interventions.find((i) => i.question === input.question);
        if (found) {
          questionId = found.questionId;
        } else {
          await sleep(100);
        }
      }
      assert.ok(questionId, "intervencao nao apareceu na fila real do painel a tempo");

      const answerRes = await fetch(
        `${baseUrl}/api/v1/bridge/interventions/${questionId}/answer`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ resolution: "answered", value: "sim" }),
        },
      );
      assert.equal(answerRes.status, 200, "POST /answer real deveria responder 200");

      const result = await resultPromise;

      // A fronteira que o contrato §10 declarava nunca exercitada: a tool
      // retorna `answered` com o valor de fato aplicado pelo painel real.
      assert.equal(result.outcome, "accepted");
      assert.equal(result.result?.outcome, "answered");
      assert.equal(result.result?.applied_value, "sim");
      assert.equal(result.result?.question_id, questionId);

      // `.operator_answers[]` gravado corretamente via state-rw.sh REAL.
      const { stdout } = await execFile(STATE_RW, [
        "get",
        "--state-dir",
        stateDir,
        "--field",
        ".operator_answers",
      ]);
      const answers = JSON.parse(stdout) as {
        question_id: string;
        outcome: string;
        applied_value: string;
      }[];
      const persisted = answers.find((a) => a.question_id === questionId);
      assert.ok(
        persisted,
        `.operator_answers[] nao contem question_id=${String(questionId)}: ${stdout}`,
      );
      assert.equal(persisted?.outcome, "answered");
      assert.equal(persisted?.applied_value, "sim");
    } finally {
      // Garantir que a promise (se em voo) assente ANTES do processo do
      // teste seguir — evita timer pendente do polling interno mantendo o
      // event loop vivo apos uma falha de asserction no meio do fluxo.
      if (resultPromise) {
        await resultPromise.catch(() => undefined);
      }
      child.kill("SIGTERM");
      await new Promise<void>((resolve) => {
        const to = setTimeout(resolve, 3000);
        child.once("exit", () => {
          clearTimeout(to);
          resolve();
        });
      });
      await rm(workDir, { recursive: true, force: true });
    }
  },
);
