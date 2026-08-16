// test/resolve.test.ts — cobertura de session/resolve.ts.
//
// Usa fixtures POSIX reais em test/fixtures/ (processos de verdade via
// execFile, nao mocks) para exercitar o caminho feliz e o fail-closed de
// SEC-H3. Assume cwd = raiz do pacote (comportamento padrao de `npm test`).
//
// mcp-direct-transport FASE 1 (task 1.2): cobre tambem a resolucao por
// chamada — `resolveSessionForCall` + `createSessionCache` — incluindo o
// teste central da FASE (task 1.2.7): hit de cache revalida INTEGRALMENTE
// contra o disco, nunca autoriza so pelo valor cacheado.

import { test } from "node:test";
import assert from "node:assert/strict";
import { join } from "node:path";
import { mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import {
  resolveActiveSession,
  resolveSessionForCall,
  createSessionCache,
  matchesResolvedSession,
  SessionMismatchError,
} from "../src/session/resolve.js";

const FIXTURES_DIR = join(process.cwd(), "test", "fixtures");
const REAL_MCP_SESSION_SH = join(
  process.cwd(),
  "..",
  "..",
  "plugins",
  "cstk",
  "skills",
  "agente-00c-runtime",
  "scripts",
  "mcp-session.sh",
);

test("resolveActiveSession: caminho feliz resolve os 6 campos do descritor", async () => {
  const session = await resolveActiveSession({
    projectPath: "/work",
    token: "synthetic-token-abc123",
    helperPath: join(FIXTURES_DIR, "fake-mcp-session-ok.sh"),
  });

  assert.equal(session.token, "synthetic-token-abc123");
  assert.equal(session.stateDir, "/data/state");
  assert.equal(session.executionKind, "feature-00c");
  assert.equal(session.shortName, "state-mcp-server");
  assert.equal(session.targetProjectPath, "/work");
  assert.equal(session.mode, "docker");
  assert.equal(session.container, "cstk-mcp-state-test");
});

test("resolveActiveSession: token ausente falha SEM invocar o helper (fail-closed)", async () => {
  await assert.rejects(
    () =>
      resolveActiveSession({
        projectPath: "/work",
        token: "",
        helperPath: join(FIXTURES_DIR, "fake-mcp-session-ok.sh"),
      }),
    SessionMismatchError,
  );
});

test("resolveActiveSession: projectPath ausente E stateDir ausente falha SEM invocar o helper (fail-closed)", async () => {
  await assert.rejects(
    () =>
      resolveActiveSession({
        projectPath: "",
        token: "synthetic-token-abc123",
        helperPath: join(FIXTURES_DIR, "fake-mcp-session-ok.sh"),
      }),
    SessionMismatchError,
  );
});

test("resolveActiveSession: SESSION_MISMATCH (exit 3) do helper vira SessionMismatchError, sem fallback", async () => {
  await assert.rejects(
    () =>
      resolveActiveSession({
        projectPath: "/work",
        token: "token-desconhecido",
        helperPath: join(FIXTURES_DIR, "fake-mcp-session-mismatch.sh"),
      }),
    SessionMismatchError,
  );
});

test("resolveActiveSession (mcp-direct-transport FASE 1): stateDir explicito -> usa modo direto --state-dir, nunca --project-path", async () => {
  const session = await resolveActiveSession({
    projectPath: "/host/path/nao/existe/no/container",
    token: "synthetic-token-abc123",
    helperPath: join(FIXTURES_DIR, "fake-mcp-session-ok-container-mode.sh"),
    stateDir: "/data/state",
  });

  assert.equal(session.stateDir, "/data/state");
  assert.equal(session.executionKind, "feature-00c");
});

test("resolveActiveSession: stateDir explicito dispensa projectPath (fail-closed do project-path nao se aplica no modo direto)", async () => {
  const session = await resolveActiveSession({
    projectPath: "",
    token: "synthetic-token-abc123",
    helperPath: join(FIXTURES_DIR, "fake-mcp-session-ok-container-mode.sh"),
    stateDir: "/data/state",
  });

  assert.equal(session.stateDir, "/data/state");
});

test("resolveActiveSession: sem stateDir, comportamento --project-path e IDENTICO ao anterior (zero regressao)", async () => {
  const session = await resolveActiveSession({
    projectPath: "/work",
    token: "synthetic-token-abc123",
    helperPath: join(FIXTURES_DIR, "fake-mcp-session-ok.sh"),
    env: {},
  });

  assert.equal(session.stateDir, "/data/state");
  assert.equal(session.targetProjectPath, "/work");
});

test("matchesResolvedSession: compara o session_id apresentado contra o token resolvido", async () => {
  const session = await resolveActiveSession({
    projectPath: "/work",
    token: "synthetic-token-abc123",
    helperPath: join(FIXTURES_DIR, "fake-mcp-session-ok.sh"),
  });

  assert.equal(matchesResolvedSession(session, "synthetic-token-abc123"), true);
  assert.equal(matchesResolvedSession(session, "outro-token"), false);
  assert.equal(matchesResolvedSession(session, ""), false);
});

// ---------------------------------------------------------------------------
// resolveSessionForCall + createSessionCache (task 1.2.1/1.2.2/1.2.5/1.2.6)
// ---------------------------------------------------------------------------

test("resolveSessionForCall (K-5, cache-miss): sem entrada no cache, resolve via tree-walk --project-path e POPULA o cache no sucesso", async () => {
  const cache = createSessionCache();
  assert.equal(cache.get("synthetic-token-abc123"), undefined);

  const session = await resolveSessionForCall(cache, {
    projectPath: "/work",
    token: "synthetic-token-abc123",
    helperPath: join(FIXTURES_DIR, "fake-mcp-session-ok.sh"),
  });

  assert.equal(session.stateDir, "/data/state");
  assert.equal(cache.get("synthetic-token-abc123"), "/data/state");
});

test("resolveSessionForCall (A-5, cache-hit): usa modo direto --state-dir com o valor cacheado, nunca --project-path de novo", async () => {
  const cache = createSessionCache();
  cache.set("synthetic-token-abc123", "/data/state");

  const session = await resolveSessionForCall(cache, {
    projectPath: "/host/path/nao/existe",
    token: "synthetic-token-abc123",
    helperPath: join(FIXTURES_DIR, "fake-mcp-session-ok-container-mode.sh"),
  });

  assert.equal(session.stateDir, "/data/state");
});

test("resolveSessionForCall (K-5): cache-miss cujo token nunca resolveu antes NAO falha so por ser miss — tenta o tree-walk normalmente", async () => {
  const cache = createSessionCache();
  const session = await resolveSessionForCall(cache, {
    projectPath: "/work",
    token: "token-nunca-visto",
    helperPath: join(FIXTURES_DIR, "fake-mcp-session-ok.sh"),
  });
  assert.equal(session.stateDir, "/data/state");
});

test("resolveSessionForCall: miss com SESSION_MISMATCH do helper rejeita e NAO popula o cache", async () => {
  const cache = createSessionCache();
  await assert.rejects(
    () =>
      resolveSessionForCall(cache, {
        projectPath: "/work",
        token: "token-desconhecido",
        helperPath: join(FIXTURES_DIR, "fake-mcp-session-mismatch.sh"),
      }),
    SessionMismatchError,
  );
  assert.equal(cache.get("token-desconhecido"), undefined);
});

// ---------------------------------------------------------------------------
// Revalidacao integral (task 1.2.7 — o teste central desta fase): usa o
// mcp-session.sh REAL (nao uma fixture stub) contra um descritor real em
// disco, para provar que um hit de cache NAO autoriza sozinho — a segunda
// chamada com o MESMO token, apos o descritor virar terminal em disco, e
// rejeitada (research Decision 2 / K-2).
// ---------------------------------------------------------------------------

// dec-060/dec-061 (mcp-direct-transport FASE 8): o mcp-session.sh REAL
// agora tambem consulta o status REAL da execucao (`.execution.status` via
// `state-rw.sh get`, backend-agnostico) alem do proxy `.stopped_at` do
// descritor — sem um `state.json` IRMAO com status ativo, toda chamada
// fail-closed recusaria (SESSION_MISMATCH), mesmo com `stopped_at: null`.
async function writeActiveState(dir: string, status = "em_andamento"): Promise<void> {
  await writeFile(
    join(dir, "state.json"),
    JSON.stringify({ execution: { status } }),
    "utf8",
  );
}

async function makeDescriptorDir(sessionId: string): Promise<string> {
  const dir = await mkdtemp(join(tmpdir(), "cstk-mcp-resolve-test-"));
  await writeFile(
    join(dir, "mcp-server.json"),
    JSON.stringify({
      session_id: sessionId,
      execution_kind: "feature-00c",
      short_name: "state-mcp-server",
      target_project_path: "/work",
      mode: "direct",
      container_name: null,
      stopped_at: null,
    }),
    "utf8",
  );
  await writeActiveState(dir);
  return dir;
}

test("resolveSessionForCall (task 1.2.7, K-2/A-5): hit de cache revalida INTEGRALMENTE — 2a chamada com o MESMO token e rejeitada apos stopped_at ser gravado em disco", async () => {
  const token = "synthetic-token-real-revalidation";
  const stateDir = await makeDescriptorDir(token);
  const cache = createSessionCache();

  // 1a chamada (miss): resolve via --state-dir explicito (equivalente ao
  // modo direto de um processo que ja conhece seu proprio state-dir — aqui
  // simulado passando `stateDir` diretamente, o caminho de hit da funcao
  // de mais alto nivel usada pelos handlers de tool).
  const first = await resolveActiveSession({
    projectPath: "",
    token,
    stateDir,
    helperPath: REAL_MCP_SESSION_SH,
  });
  assert.equal(first.stateDir, stateDir);
  cache.set(token, stateDir);

  // Confirma que o cache tem uma entrada (hit na proxima chamada).
  assert.equal(cache.get(token), stateDir);

  // Muta o descritor em disco: execucao virou terminal.
  await writeFile(
    join(stateDir, "mcp-server.json"),
    JSON.stringify({
      session_id: token,
      execution_kind: "feature-00c",
      short_name: "state-mcp-server",
      target_project_path: "/work",
      mode: "direct",
      container_name: null,
      stopped_at: "2026-08-16T00:00:00Z",
    }),
    "utf8",
  );

  // 2a chamada, MESMO token: se a revalidacao fosse so pelo cache (sem
  // reler o disco), isto passaria — o teste prova que NAO passa.
  await assert.rejects(
    () =>
      resolveSessionForCall(cache, {
        projectPath: "",
        token,
        helperPath: REAL_MCP_SESSION_SH,
      }),
    SessionMismatchError,
  );
});

test("resolveActiveSession (task 1.2.7, caminho feliz real): mcp-session.sh REAL resolve um descritor ativo (stopped_at null) em modo direto", async () => {
  const token = "synthetic-token-real-happy";
  const stateDir = await makeDescriptorDir(token);

  const session = await resolveActiveSession({
    projectPath: "",
    token,
    stateDir,
    helperPath: REAL_MCP_SESSION_SH,
  });

  assert.equal(session.stateDir, stateDir);
  assert.equal(session.token, token);
  assert.equal(session.executionKind, "feature-00c");
  assert.equal(session.mode, "direct");
});

// ---------------------------------------------------------------------------
// dec-060/dec-061 (mcp-direct-transport FASE 8): status REAL da execucao,
// nao so o proxy `.stopped_at` do descritor. Prova de ponta a ponta contra
// o mcp-session.sh REAL: o proxy do descritor sozinho NAO basta mais.
// ---------------------------------------------------------------------------

test("resolveActiveSession (dec-060): descritor com stopped_at=null MAS execution.status=concluida no state.json irmao -> SessionMismatchError (proxy divergente do status real)", async () => {
  const token = "synthetic-token-dec060-diverge";
  const stateDir = await makeDescriptorDir(token);
  // Sobrescreve o state.json ativo escrito por makeDescriptorDir: a
  // execucao terminou de verdade (ex.: `cstk mcp stop` nunca rodou), mas o
  // descritor continua com `stopped_at: null` (proxy desatualizado).
  await writeActiveState(stateDir, "concluida");

  await assert.rejects(
    () =>
      resolveActiveSession({
        projectPath: "",
        token,
        stateDir,
        helperPath: REAL_MCP_SESSION_SH,
      }),
    SessionMismatchError,
  );
});

test("resolveActiveSession (dec-060): sem state.json ao lado do descritor -> fail-closed (SessionMismatchError), nunca tratado como ativa", async () => {
  const token = "synthetic-token-dec060-nostate";
  const dir = await mkdtemp(join(tmpdir(), "cstk-mcp-resolve-test-"));
  await writeFile(
    join(dir, "mcp-server.json"),
    JSON.stringify({
      session_id: token,
      execution_kind: "feature-00c",
      short_name: "state-mcp-server",
      target_project_path: "/work",
      mode: "direct",
      container_name: null,
      stopped_at: null,
    }),
    "utf8",
  );
  // Deliberadamente SEM state.json — leitura de status falha.

  await assert.rejects(
    () =>
      resolveActiveSession({
        projectPath: "",
        token,
        stateDir: dir,
        helperPath: REAL_MCP_SESSION_SH,
      }),
    SessionMismatchError,
  );
});
