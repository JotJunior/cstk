// healthcheck.ts — sonda de saude do servidor MCP de estado (task 5.3.2,
// dec-081 do orquestrador da onda 16, contracts/mcp-session-lifecycle.md
// §Health check).
//
// DESENHO (evidencia real, ver dec-081/onda 16): a alternativa mais obvia
// -- fazer `docker attach` no processo PID1 do container (o servidor JA em
// producao, servindo stdio real) e injetar `initialize` + `tools/call` por
// ali -- foi DESCARTADA. `docker attach` sem TTY conecta o pipe do host
// DIRETAMENTE ao stdin do container: fechar esse pipe ao fim da sonda (como
// qualquer processo shell de vida curta faz) propaga EOF ao stdin do
// servidor, e `StdioServerTransport` trata EOF como desconexao do cliente
// -- encerrando o processo que deveria continuar vivo para o resto da
// execucao (FR-010). Nenhuma sonda de saude pode correr o risco de matar o
// que esta sondando.
//
// Em vez disso, este script SOBE UMA INSTANCIA EFEMERA DO PROPRIO SERVIDOR
// como processo filho (mesma imagem, MESMO env herdado do `docker exec` que
// invoca este arquivo -- inclusive MCP_SESSION_TOKEN/CSTK_MCP_PROJECT_PATH/
// CSTK_MCP_STATE_DIR ja setados pelo `docker run` original), conecta um
// CLIENTE MCP real via stdio a essa instancia efemera, faz o handshake
// `initialize` (a conexao do SDK client->server ja o realiza internamente)
// e chama a tool read-only `get_status` (zero mutacao — dec-064). O
// processo PID1 do container (o servidor real, em producao) nunca e tocado
// -- zero risco de fechar o stdio errado.
//
// O que esta sonda VALIDA de fato: a imagem sobe, a sessao resolve
// corretamente dado o MESMO env do container (fail-closed identico ao
// bootstrap real — se o env estiver errado, o bootstrap real tambem
// falharia), as 7 tools registram, e uma chamada de tool completa um
// round-trip JSON-RPC de ponta a ponta. Nao prova que o processo PID1
// especifico ainda esta vivo (isso e responsabilidade de `docker inspect`/
// `docker exec` em si -- se o container morreu, o `docker exec` que invoca
// este script ja falha antes de chegar aqui).
//
// Invocacao: `docker exec <container> node dist/src/healthcheck.js`
// (cli/lib/mcp-docker.sh::_mcp_docker_healthcheck aplica o timeout externo
// via watcher POSIX -- este arquivo tambem impoe um teto interno como
// segunda linha de defesa contra o SDK nunca resolver a Promise).
//
// stdout: `healthcheck: ok` em sucesso. stderr: diagnostico em falha.
// Exit 0 = saudavel; exit 1 = falha (env, spawn, handshake ou tool
// rejeitada); exit 124 = teto interno estourado (convencao GNU timeout,
// mesma reaproveitada por model-routing.sh::_mr_invoke_skill).

import { fileURLToPath, pathToFileURL } from "node:url";
import { dirname, join } from "node:path";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

/** Teto interno (2a linha de defesa; a 1a e o timeout externo do caller). */
const INTERNAL_TIMEOUT_MS = 8_000;

function withTimeout<T>(promise: Promise<T>, ms: number, label: string): Promise<T> {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      reject(new Error(`healthcheck: timeout interno (${ms}ms) em: ${label}`));
    }, ms);
    promise.then(
      (value) => {
        clearTimeout(timer);
        resolve(value);
      },
      (err) => {
        clearTimeout(timer);
        reject(err instanceof Error ? err : new Error(String(err)));
      },
    );
  });
}

export async function runHealthcheck(env: NodeJS.ProcessEnv = process.env): Promise<void> {
  const token = env.MCP_SESSION_TOKEN ?? "";
  if (!token) {
    throw new Error("healthcheck: MCP_SESSION_TOKEN ausente no ambiente do exec");
  }

  // dist/src/healthcheck.js -> dist/src/index.js (mesmo diretorio de build,
  // sempre presente no MESMO container/imagem que gerou este arquivo).
  const serverEntrypoint = join(__dirname, "index.js");

  const transport = new StdioClientTransport({
    command: process.execPath,
    args: [serverEntrypoint],
    env: env as Record<string, string>,
    stderr: "pipe",
  });

  const client = new Client({ name: "cstk-mcp-healthcheck", version: "0.0.0" }, { capabilities: {} });

  try {
    await withTimeout(client.connect(transport), INTERNAL_TIMEOUT_MS, "initialize handshake");

    const result = await withTimeout(
      client.callTool({ name: "get_status", arguments: { session_id: token } }),
      INTERNAL_TIMEOUT_MS,
      "tools/call get_status",
    );

    if (result.isError) {
      throw new Error(
        `healthcheck: get_status rejeitou: ${JSON.stringify(result.content ?? result)}`,
      );
    }
  } finally {
    // Encerra o CHILD efemero (nunca o PID1 do container — este script
    // spawnou seu proprio subprocesso via StdioClientTransport, isolado).
    await client.close().catch(() => undefined);
  }
}

const isMainModule =
  process.argv[1] !== undefined && import.meta.url === pathToFileURL(process.argv[1]).href;
if (isMainModule) {
  runHealthcheck()
    .then(() => {
      process.stdout.write("healthcheck: ok\n");
      process.exitCode = 0;
    })
    .catch((err) => {
      process.stderr.write(
        `healthcheck: falhou: ${err instanceof Error ? (err.stack ?? err.message) : String(err)}\n`,
      );
      process.exitCode = 1;
    });
}
