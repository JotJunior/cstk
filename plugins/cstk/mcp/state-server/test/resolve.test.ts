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
//
// mcp-direct-transport FASE 6 (tasks 6.1.2 + 6.2.1): fecha 2 lacunas
// deixadas pelos testes acima (todos usam fixtures stub OU um unico
// token/execucao):
//   6.1.2 — o fluxo miss->hit de `resolveSessionForCall` nunca foi
//     exercitado ponta-a-ponta contra o mcp-session.sh REAL (so contra
//     fixtures fake-mcp-session-ok.sh); o teste 1.2.7 usa o helper real,
//     mas so testa revalidacao apos terminar, nao a transicao miss->hit.
//   6.2.1 — nenhum teste cobre DUAS execucoes ativas simultaneas
//     (cardinalidade 1 processo : N sessoes, FR-011): dois tokens
//     distintos, dois projetos tmpdir descartaveis (NUNCA a execucao real
//     desta feature — dec-075), compartilhando o MESMO SessionCache, para
//     provar ausencia de cross-talk na resolucao (o que os handlers de
//     tool usam para decidir QUAL state-dir mutar).

import { test } from "node:test";
import assert from "node:assert/strict";
import { join } from "node:path";
import { mkdir, mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import {
  resolveActiveSession,
  resolveSessionForCall,
  createSessionCache,
  matchesResolvedSession,
  SessionMismatchError,
} from "../src/session/resolve.js";

const FIXTURES_DIR = join(process.cwd(), "test", "fixtures");
// cwd = plugins/cstk/mcp/state-server -> "../.." JA e plugins/cstk
const REAL_MCP_SESSION_SH = join(
  process.cwd(),
  "..",
  "..",
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

// ---------------------------------------------------------------------------
// task 6.1.2 (FASE 6): resolucao por chamada, cache hit + miss, contra o
// mcp-session.sh REAL (nao um stub) — a mesma dupla hit/miss ja coberta
// acima (linha ~141) so exercita fixtures fake; aqui o tree-walk
// `--project-path` REAL sobre um layout de projeto de verdade
// (`.claude/agente-00c-state/mcp-server.json`) e o modo direto
// `--state-dir` REAL sao os dois lados da transicao.
// ---------------------------------------------------------------------------

/**
 * Monta um projeto tmpdir descartavel com o layout real de uma execucao
 * (agente-00c ou feature-00c) + descritor ATIVO + state.json irmao com
 * `.execution.status = em_andamento` (dec-060/061 — exigido pelo
 * mcp-session.sh REAL, nao so o proxy `stopped_at`).
 */
async function makeProjectWithExecution(
  kind: "agente-00c" | "feature-00c",
  sessionId: string,
  shortName = "outra-feature",
): Promise<{ projectPath: string; stateDir: string }> {
  const projectPath = await mkdtemp(join(tmpdir(), "cstk-mcp-multi-session-test-"));
  const stateDir =
    kind === "agente-00c"
      ? join(projectPath, ".claude", "agente-00c-state")
      : join(projectPath, ".claude", "feature-00c-state", shortName);
  await mkdir(stateDir, { recursive: true });
  await writeFile(
    join(stateDir, "mcp-server.json"),
    JSON.stringify({
      session_id: sessionId,
      state_dir: stateDir,
      execution_kind: kind,
      short_name: kind === "feature-00c" ? shortName : null,
      target_project_path: projectPath,
      mode: "direct",
      container_name: null,
      stopped_at: null,
    }),
    "utf8",
  );
  await writeActiveState(stateDir);
  return { projectPath, stateDir };
}

test("resolveSessionForCall (task 6.1.2, mcp-session.sh REAL): 1a chamada (miss) resolve via tree-walk --project-path real e POPULA o cache; 2a chamada com o MESMO token (hit) usa --state-dir direto, sem tree-walk", async () => {
  const token = "synthetic-token-real-miss-then-hit";
  const { projectPath, stateDir } = await makeProjectWithExecution("agente-00c", token);
  const cache = createSessionCache();

  assert.equal(cache.get(token), undefined);

  const first = await resolveSessionForCall(cache, {
    projectPath,
    token,
    helperPath: REAL_MCP_SESSION_SH,
  });
  assert.equal(first.stateDir, stateDir);
  assert.equal(first.executionKind, "agente-00c");
  assert.equal(cache.get(token), stateDir);

  // 2a chamada: passa um projectPath INEXISTENTE/errado deliberadamente —
  // se o hit reexecutasse o tree-walk em vez de usar o cache (--state-dir
  // direto), esta chamada falharia. Ela nao falha, provando o caminho A-5.
  const second = await resolveSessionForCall(cache, {
    projectPath: "/nao/existe/nao/deveria/ser/lido",
    token,
    helperPath: REAL_MCP_SESSION_SH,
  });
  assert.equal(second.stateDir, stateDir);
  assert.equal(second.executionKind, "agente-00c");
});

// ---------------------------------------------------------------------------
// task 6.2.1 (FASE 6, FR-011): duas execucoes ativas simultaneas
// (agente-00c + feature-00c) com tokens distintos, MESMO SessionCache
// compartilhado (1 processo : N sessoes) — nenhum cross-talk: apresentar o
// token de A jamais resolve o state-dir de B, nem vice-versa. E o exato
// mecanismo que os handlers de tool (record_decision, open_wave, ...)
// usam para decidir qual state-dir mutar — cobrir a resolucao cobre a
// garantia de isolamento de mutacao por construcao.
// ---------------------------------------------------------------------------

test("resolveSessionForCall (task 6.2.1, FR-011): duas execucoes ativas simultaneas com tokens distintos e cache compartilhado — nenhum cross-talk", async () => {
  const tokenA = "synthetic-token-multi-agente-A";
  const tokenB = "synthetic-token-multi-feature-B";
  const { projectPath: projA, stateDir: sdA } = await makeProjectWithExecution(
    "agente-00c",
    tokenA,
  );
  const { projectPath: projB, stateDir: sdB } = await makeProjectWithExecution(
    "feature-00c",
    tokenB,
    "mcp-direct-transport-fixture",
  );
  assert.notEqual(sdA, sdB);

  const cache = createSessionCache();

  // 1a chamada (miss) para A: tree-walk real sobre o projeto A, popula o
  // cache compartilhado.
  const sessionA1 = await resolveSessionForCall(cache, {
    projectPath: projA,
    token: tokenA,
    helperPath: REAL_MCP_SESSION_SH,
  });
  assert.equal(sessionA1.stateDir, sdA);
  assert.equal(cache.get(tokenA), sdA);

  // 1a chamada (miss) para B: projeto DIFERENTE, token DIFERENTE, mesmo
  // objeto de cache — simula o mesmo processo servidor atendendo as duas
  // execucoes.
  const sessionB1 = await resolveSessionForCall(cache, {
    projectPath: projB,
    token: tokenB,
    helperPath: REAL_MCP_SESSION_SH,
  });
  assert.equal(sessionB1.stateDir, sdB);
  assert.equal(cache.get(tokenB), sdB);

  // A entrada de A sobrevive intacta a insercao de B (sem colisao de
  // chave no Map).
  assert.equal(cache.get(tokenA), sdA);

  // 2a chamada (hit) para A e para B, em sequencia intercalada — cada uma
  // usa --state-dir direto com o proprio valor cacheado, isolada da
  // outra.
  const sessionA2 = await resolveSessionForCall(cache, {
    projectPath: "/nao/deveria/ser/usado",
    token: tokenA,
    helperPath: REAL_MCP_SESSION_SH,
  });
  const sessionB2 = await resolveSessionForCall(cache, {
    projectPath: "/nao/deveria/ser/usado",
    token: tokenB,
    helperPath: REAL_MCP_SESSION_SH,
  });

  assert.equal(sessionA2.stateDir, sdA);
  assert.equal(sessionB2.stateDir, sdB);
  assert.notEqual(sessionA2.stateDir, sessionB2.stateDir);

  // A garantia central de FR-011: apresentar o token de A NUNCA resolve o
  // state-dir de B, e vice-versa.
  assert.notEqual(sessionA2.stateDir, sdB);
  assert.notEqual(sessionB2.stateDir, sdA);
});
