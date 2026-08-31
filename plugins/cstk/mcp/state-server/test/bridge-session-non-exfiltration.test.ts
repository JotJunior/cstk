// test/bridge-session-non-exfiltration.test.ts — task 5.1.4 (Cenario 13 do
// quickstart, docs/specs/human-bridge/quickstart.md; FR-002/comentario de
// topo de routes/bridge.ts: "roteamento por session_id ... honrado ANTES
// desta camada, no servidor MCP — este arquivo nunca ve session_id").
//
// Confirma, com testes automatizados (nao so leitura manual de codigo):
//   (a) o payload HTTP de CRIACAO (`toCreateInterventionBody`/
//       `CreateInterventionRequest`) NUNCA carrega o token de capacidade —
//       nem como campo dedicado, nem embutido em outro campo;
//   (b) o objeto passado a `client.createIntervention()` dentro de
//       `handleAskOperator` tambem nunca carrega o token, mesmo quando o
//       `ResolvedSession.token` e distintivo o bastante para aparecer via
//       `JSON.stringify` se algum dia vazasse por engano;
//   (c) a entrada persistida em `.operator_answers[]` (que ALCANCA
//       `state.json`/`state.db` e, dali, `cstk recall --ingest` /
//       relatorios) tambem nunca carrega o token;
//   (d) os schemas HTTP compartilhados (`@cstk-panel/shared-types`,
//       `schemas/entities.ts`) e as rotas do painel (`routes/bridge.ts`)
//       nunca declaram um campo `sessionId`/`session_id` para a Ponte —
//       varredura estatica do CODIGO-FONTE (nao apenas do runtime).
//
// Fora de escopo (achado relacionado, PRE-EXISTENTE, nao introduzido por
// esta feature): `enforcement-log.jsonl` grava `session_id` em texto claro
// para toda tool que audita via `appendAuditRecord`/`appendOptinDecisionRecord`
// (padrao ja aceito desde `collect_optins.ts`, dec-053/CHK057) — `
// appendAskOperatorRecord` (audit/log.ts) replica o MESMO padrao para
// `ask_operator`. Esse arquivo vive em `<projeto-alvo>/.claude/` (SEMPRE
// gitignored — confirmado `.gitignore:3` `/.claude`) e nunca alcanca
// commit/report/spec; nao e "exfiltracao" no sentido deste cenario
// (fronteira HTTP + artefatos versionados), mas fica documentado aqui para
// nao ser reintroduzido como confusao de escopo.

import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import {
  createBridgeClient,
  type CreateInterventionRequest,
  type BridgeClient,
} from "../src/bridge/client.js";
import {
  handleAskOperator,
  askOperatorInputSchema,
} from "../src/tools/ask_operator.js";
import type { ResolvedSession } from "../src/session/resolve.js";

const HERE = dirname(fileURLToPath(import.meta.url));
// dist/test -> dist -> state-server -> mcp -> <repo root>
const REPO_ROOT = join(HERE, "..", "..", "..", "..", "..", "..");

const SESSION_TOKEN = "SECRET-CAPABILITY-TOKEN-nao-deveria-vazar-9f3a2c1d";
const FAKE_SESSION: ResolvedSession = {
  token: SESSION_TOKEN,
  stateDir: "/data/state",
  executionKind: "feature-00c",
  shortName: "human-bridge",
  targetProjectPath: "/work/cstk",
  mode: "direct",
  container: "-",
};

function fakeClientCapturingCreate(
  capturedReqs: CreateInterventionRequest[],
): BridgeClient {
  return {
    generateLocalQuestionId: () => "local-q-fake",
    createIntervention: async (req) => {
      capturedReqs.push(req);
      return { kind: "created", questionId: "q-real-1", expiresAt: "2026-08-29T19:00:00Z" };
    },
    pollIntervention: async () => ({
      kind: "answered",
      appliedValue: "sim",
      untrustedText: null,
    }),
  };
}

// ---------------------------------------------------------------------------
// (a) toCreateInterventionBody() / bridge-client.ts — payload HTTP real
// ---------------------------------------------------------------------------
test("5.1.4(a) payload HTTP de criacao nunca carrega o token — chaves EXATAS, sem sessionId/session_id/token", async () => {
  let capturedBody: unknown = null;
  const fetchImpl = (async (_url: string | URL, init?: RequestInit) => {
    capturedBody = JSON.parse(String(init?.body));
    return new Response(
      JSON.stringify({
        data: { questionId: "q-1", expiresAt: "2026-08-29T19:00:00Z", state: "open" },
        meta: { degraded: false, reason: null },
      }),
      { status: 201, headers: { "Content-Type": "application/json" } },
    );
  }) as typeof fetch;

  const client = createBridgeClient("http://127.0.0.1:1", { fetchImpl });
  const req: CreateInterventionRequest = {
    projectPath: "/abs/path/do/projeto",
    project: "cstk",
    shortName: "human-bridge",
    executionKind: "feature-00c",
    kind: "choice",
    question: "prosseguir?",
    options: ["sim", "nao"],
    defaultValue: "nao",
    timeoutMs: 240000,
  };
  await client.createIntervention(req);

  assert.ok(capturedBody && typeof capturedBody === "object");
  const keys = Object.keys(capturedBody as Record<string, unknown>).sort();
  assert.deepEqual(keys, [
    "defaultValue",
    "executionKind",
    "kind",
    "options",
    "project",
    "projectPath",
    "question",
    "shortName",
    "timeoutMs",
  ]);
  const serialized = JSON.stringify(capturedBody);
  assert.doesNotMatch(serialized, /session[_-]?id/i);
  assert.doesNotMatch(serialized, /\btoken\b/i);
});

// ---------------------------------------------------------------------------
// (b) handleAskOperator -> client.createIntervention() — objeto de dominio
// ---------------------------------------------------------------------------
test("5.1.4(b) handleAskOperator nunca repassa session.token para createIntervention()", async () => {
  const captured: CreateInterventionRequest[] = [];
  const input = askOperatorInputSchema.parse({
    session_id: SESSION_TOKEN,
    question: "prosseguir com o deploy?",
    kind: "choice",
    options: ["sim", "nao"],
    default_value: "nao",
  });

  const noopHelperPath = join(REPO_ROOT, "plugins", "cstk", "mcp", "state-server", "test", "fixtures",
    "fake-ask-operator-state-rw-captures-set.sh");
  const result = await handleAskOperator(input, {
    session: FAKE_SESSION,
    bridgeClient: fakeClientCapturingCreate(captured),
    stateRwHelperPath: noopHelperPath, // persistOperatorAnswer nao e o foco deste teste (ver 5.1.4c)
  });

  assert.equal(result.outcome, "accepted");
  assert.equal(captured.length, 1);
  const req = captured[0] as CreateInterventionRequest;
  const serialized = JSON.stringify(req);
  assert.ok(
    !serialized.includes(SESSION_TOKEN),
    `o objeto passado a createIntervention() contem o token literal: ${serialized}`,
  );
  const keys = Object.keys(req).sort();
  assert.deepEqual(keys, [
    "defaultValue",
    "executionKind",
    "kind",
    "options",
    "project",
    "projectPath",
    "question",
    "shortName",
    "timeoutMs",
  ]);
});

// ---------------------------------------------------------------------------
// (c) .operator_answers[] — entrada persistida via state-rw.sh (fixture
// captura o --value real enviado ao helper)
// ---------------------------------------------------------------------------
test("5.1.4(c) entrada persistida em .operator_answers[] nunca carrega session.token", async () => {
  const { mkdtemp, readFile, rm } = await import("node:fs/promises");
  const { tmpdir } = await import("node:os");
  const dir = await mkdtemp(join(tmpdir(), "hb-nonexfil-"));
  const setValueFile = join(dir, "captured-set-values.txt");
  const fixture = join(REPO_ROOT, "plugins", "cstk", "mcp", "state-server", "test", "fixtures",
    "fake-ask-operator-state-rw-captures-set.sh");
  const original = process.env.FAKE_SET_VALUE_FILE;
  process.env.FAKE_SET_VALUE_FILE = setValueFile;
  try {
    const input = askOperatorInputSchema.parse({
      session_id: SESSION_TOKEN,
      question: "prosseguir?",
      kind: "confirm",
      default_value: "nao",
    });
    const result = await handleAskOperator(input, {
      session: FAKE_SESSION,
      bridgeClient: fakeClientCapturingCreate([]),
      stateRwHelperPath: fixture,
    });
    assert.equal(result.outcome, "accepted");

    const captured = await readFile(setValueFile, "utf8");
    assert.ok(captured.trim().length > 0, "nenhum --value capturado pela fixture");
    assert.ok(
      !captured.includes(SESSION_TOKEN),
      `.operator_answers[] persistido contem o token literal: ${captured}`,
    );
    const parsed = JSON.parse(captured.trim().split("\n").pop() as string) as unknown[];
    const entry = parsed[0] as Record<string, unknown>;
    const keys = Object.keys(entry).sort();
    assert.deepEqual(keys, [
      "applied_value",
      "channel",
      "effective_timeout_ms",
      "outcome",
      "question_id",
      "reason",
      "recorded_at",
      "untrusted_text",
    ]);
  } finally {
    if (original === undefined) delete process.env.FAKE_SET_VALUE_FILE;
    else process.env.FAKE_SET_VALUE_FILE = original;
    await rm(dir, { recursive: true, force: true });
  }
});

// ---------------------------------------------------------------------------
// (d) varredura ESTATICA do codigo-fonte — nenhum schema/rota da Ponte
// declara um campo sessionId/session_id no payload HTTP.
// ---------------------------------------------------------------------------
test("5.1.4(d) varredura estatica: routes/bridge.ts e o schema compartilhado nunca declaram sessionId/session_id", () => {
  const bridgeRoutesPath = join(
    REPO_ROOT, "panel", "apps", "server", "src", "routes", "bridge.ts",
  );
  const sharedSchemasPath = join(
    REPO_ROOT, "panel", "packages", "shared-types", "src", "schemas", "entities.ts",
  );
  const clientPath = join(REPO_ROOT, "plugins", "cstk", "mcp", "state-server", "src", "bridge", "client.ts");
  const askOperatorPath = join(REPO_ROOT, "plugins", "cstk", "mcp", "state-server", "src", "tools", "ask_operator.ts");

  const bridgeRoutesSrc = readFileSync(bridgeRoutesPath, "utf8");
  const clientSrc = readFileSync(clientPath, "utf8");
  const askOperatorSrc = readFileSync(askOperatorPath, "utf8");
  const sharedSchemasSrc = readFileSync(sharedSchemasPath, "utf8");

  // routes/bridge.ts: o UNICO lugar onde "session_id" pode aparecer e no
  // COMENTARIO que documenta a invariante ("este arquivo nunca ve
  // session_id") — nunca como identificador de campo/z.object() key.
  assert.doesNotMatch(bridgeRoutesSrc, /['"]session_?[Ii]d['"]\s*:/);

  // client.ts: nenhuma referencia a `sessionId` como CHAVE de payload HTTP.
  assert.doesNotMatch(clientSrc, /\bsessionId\s*[:,)]/);

  // ask_operator.ts: o bloco de argumentos passado a createIntervention()
  // legitimamente referencia `session.targetProjectPath`/`session.shortName`/
  // `session.executionKind` (dados PUBLICOS, nao o segredo) — a checagem
  // especifica e que `session.token` (o SEGREDO) nunca aparece DENTRO desse
  // bloco especifico (extraido de forma nao-gulosa ate o primeiro `})`).
  const createCallMatch = askOperatorSrc.match(/createIntervention\(\{[\s\S]*?\}\)/);
  assert.ok(createCallMatch, "chamada a createIntervention({...}) nao encontrada em ask_operator.ts");
  assert.doesNotMatch(createCallMatch[0], /session\s*\.\s*token/);
  assert.doesNotMatch(createCallMatch[0], /\bsessionId\b/);

  // Schema compartilhado: a secao "Intervention*" (feature human-bridge) nao
  // declara sessionId/session_id em NENHUM lugar (delimitado pelo marcador
  // de secao do proprio arquivo, para nao acusar campos de OUTRAS features,
  // ex.: sessions-api, que legitimamente tem `sessionId: z.string()`).
  const marker = "Intervention* schemas (feature human-bridge";
  const idx = sharedSchemasSrc.indexOf(marker);
  assert.ok(idx >= 0, "marcador de secao Intervention* nao encontrado em schemas/entities.ts");
  const interventionSection = sharedSchemasSrc.slice(idx, idx + 4000);
  assert.doesNotMatch(interventionSection, /session[_-]?[Ii]d/);
});
