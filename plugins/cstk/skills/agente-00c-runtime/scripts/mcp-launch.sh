#!/bin/sh
# mcp-launch.sh — entrypoint stdio registrado em `.mcp.json` (`cstk mcp
# install`, cli/lib/mcp.sh::_mcp_cmd_install).
#
# Ref: docs/specs/state-mcp-server/contracts/mcp-session-lifecycle.md
#        §CLI: `cstk mcp` / §`cstk mcp install` / §Resolucao da execucao
#        ativa (helper mcp-session.sh) / §SEC-H3
#      docs/specs/mcp-direct-transport/contracts/server-session-resolution.md
#        §4 (Launcher) — L-1..L-7
#      docs/specs/mcp-direct-transport/tasks.md FASE 5 task 5.1
#
# CUTOVER (mcp-direct-transport, FASE 5): o servidor de verdade
# (mcp/state-server) DEIXOU de rodar dentro de um container Docker
# subido por `cstk mcp start` — desde a FASE 3, `start` so grava um
# descritor `mode=direct` (nenhum motor de containers envolvido). Este
# launcher agora faz `exec` DIRETO no processo `node` que roda
# `dist/src/index.js`, sem exigir token algum no boot (L-1, dec-010): o
# servidor registra as 7 tools incondicionalmente (FASE 1) e resolve a
# sessao de CADA chamada pelo `session_id` recebido como argumento da
# propria tool (nunca por env fixada no boot deste processo) — ver
# contracts/server-session-resolution.md §1-§2.
#
# Responsabilidade deste script, em ordem:
#   1. Resolver `~/.claude/mcp/state-server` (catalogo instalado — L-3,
#      override `CSTK_MCP_STATE_SERVER_DIR` so para testes/dev).
#   2. Preflight de Node (L-6, mesmo padrao de `cli/lib/serve.sh`
#      `_serve_node_preflight`): a arvore exige Node >= 22
#      ([REAL] `mcp/state-server/package.json` `engines.node`).
#   3. Build lazy do entrypoint via `mcp-build-lazy.sh ensure --dir`
#      (idempotente — no-op se `dist/src/index.js` ja existe).
#   4. `exec node <entrypoint>`, repassando `CSTK_MCP_PROJECT_PATH`
#      (tree-walk de cache-miss em CADA chamada, dentro do processo) e
#      `CSTK_MCP_SCRIPTS_DIR` (aponta para o proprio diretorio deste
#      script — onde vivem `state-rw.sh`/`state-ondas.sh`/etc.,
#      consumidos por `runtime/exec.ts`; o default `/opt/cstk/scripts`
#      so existia dentro do container removido).
#
# AUSENCIA GRACIOSA (modo IDLE — herdado do fix pos-v6.2.0, bug "-32000
# no boot"): a entrada do `.mcp.json` e estatica e o harness a conecta em
# TODO boot de sessao — inclusive (caso mais comum) sem nenhuma execucao
# 00c ativa. Isso continua valendo sob o cutover: SEM execucao ativa
# nao ha nada de especial a fazer — o processo `node` sobe do mesmo jeito
# e so rejeita (SESSION_MISMATCH) toda chamada de mutacao sem token
# valido, tool por tool (fail-closed preservado, so mudou de lugar —
# contracts/server-session-resolution.md §1.2 "Invariante de
# nao-regressao"). O modo IDLE (stub em sh+jq, ZERO tools) so entra em
# cena quando o processo `node` real NAO PODE subir (L-5): Node ausente/
# major incompativel, ou build lazy falhou (sem npm, sem rede, lockfile
# ausente, `npm ci`/`npm run build` com erro). Nesses casos, sair com
# exit != 0 faria o harness reportar "Failed to reconnect to cstk-state:
# -32000" em toda sessao normal — em vez disso, servimos o stub idle com
# motivo explicito em stderr; o `/mcp` mostra o servidor conectado, sem
# erro, e o command pai segue decidindo (via `cstk mcp status`) se a onda
# usa o caminho MCP ou o Bash.
#
# `exec node <entrypoint>` substitui o PROCESSO deste script (nao um
# subshell/fork em background) — o processo do servidor MORRE junto com
# a sessao do harness que o hospeda (L-7, FR-012). A SESSAO MCP
# (descritor `mcp-server.json` + token) e independente do PROCESSO e
# sobrevive normalmente a pausas entre ondas (quem grava/apaga o
# descritor e `cstk mcp start`/`stop`, nunca este launcher).
#
# POSIX sh puro. Deps: node (>=22), npm (so no caminho de build), o
# proprio mcp-build-lazy.sh (script irmao).
#
# Exit codes:
#   0  modo IDLE encerrado por EOF do harness (sessao fechou), ou node
#      encerrado normalmente (nao deveria acontecer via exec, mas o
#      codigo de saida do exec e propagado se acontecer)
#   1  falha de MECANISMO barulhenta (mcp-build-lazy.sh/jq ausentes no
#      idle, `node` desaparece do PATH entre o preflight e o exec)

set -eu

_ML_NAME="mcp-launch"

_ml_die() {
  printf '%s: %s\n' "$_ML_NAME" "$1" >&2
  exit "${2:-1}"
}

# Stub MCP idle: JSON-RPC newline-delimited (framing VERIFICADO em
# @modelcontextprotocol/sdk dist/esm/shared/stdio.js — serialize =
# JSON.stringify(msg) + '\n'). Responde o minimo do protocolo com ZERO
# tools; tudo que tem id e nao e reconhecido recebe -32601. EOF => exit 0.
_ml_idle_serve() {
  printf '%s: %s — servindo em modo IDLE (0 tools). Corrija a causa acima e reconecte o MCP (/mcp) para tentar de novo.\n' \
    "$_ML_NAME" "$1" >&2
  command -v jq >/dev/null 2>&1 || _ml_die "jq necessario para o modo idle"
  while IFS= read -r _ml_line; do
    [ -n "$_ml_line" ] || continue
    _ml_method=$(printf '%s' "$_ml_line" | jq -r '.method // ""' 2>/dev/null) || continue
    case "$_ml_method" in
      initialize)
        printf '%s' "$_ml_line" | jq -c \
          '{jsonrpc:"2.0", id:.id, result:{protocolVersion:(.params.protocolVersion // "2024-11-05"), capabilities:{tools:{}}, serverInfo:{name:"cstk-state-idle", version:"idle"}}}'
        ;;
      tools/list)
        printf '%s' "$_ml_line" | jq -c '{jsonrpc:"2.0", id:.id, result:{tools:[]}}'
        ;;
      ping)
        printf '%s' "$_ml_line" | jq -c '{jsonrpc:"2.0", id:.id, result:{}}'
        ;;
      notifications/*)
        : # notificacoes nao recebem resposta
        ;;
      *)
        if printf '%s' "$_ml_line" | jq -e 'has("id")' >/dev/null 2>&1; then
          printf '%s' "$_ml_line" | jq -c \
            '{jsonrpc:"2.0", id:.id, error:{code:-32601, message:"cstk-state em modo idle: servidor real indisponivel nesta sessao"}}'
        fi
        ;;
    esac
  done
  exit 0
}

# Diretorio deste proprio script — mcp-build-lazy.sh vive ao lado dele
# tanto no catalogo instalado (~/.claude/skills/agente-00c-runtime/scripts/)
# quanto no layout de repo/dev (plugins/cstk/skills/agente-00c-runtime/scripts/).
# Este e TAMBEM o dir passado como CSTK_MCP_SCRIPTS_DIR (as state-*.sh
# scripts que runtime/exec.ts invoca vivem aqui, nao no entrypoint do
# servidor).
_ml_script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd -P) \
  || _ml_die "nao consegui resolver o proprio diretorio"

# Project-path: o harness invoca com CWD = raiz do projeto-alvo (onde
# vive o .mcp.json que referencia este script — doc oficial do .mcp.json,
# nao [VERIFICADO] neste repo). Override via CSTK_MCP_PROJECT_PATH para
# testes/dev, onde o CWD do processo pode nao ser o projeto-alvo. Sempre
# repassado ao servidor real — usado no tree-walk de cache-miss de CADA
# chamada (contracts/server-session-resolution.md §3), nao so no boot.
_ml_project_path="${CSTK_MCP_PROJECT_PATH:-$(pwd)}"

# Diretorio-fonte do servidor MCP: path fixo no catalogo instalado
# (L-3; [REAL] cli/lib/install.sh::_install_apply_mcp_server escreve em
# ~/.claude/mcp/state-server). Override so para testes/dev (fixture sem
# depender de HOME real nem de instalacao de verdade).
_ml_state_server_dir="${CSTK_MCP_STATE_SERVER_DIR:-${HOME:-}/.claude/mcp/state-server}"

if [ ! -d "$_ml_state_server_dir" ] || [ ! -f "$_ml_state_server_dir/package.json" ]; then
  _ml_idle_serve "mcp/state-server nao instalado em $_ml_state_server_dir (rode: cstk install)"
fi

# Preflight de Node (L-6, mesmo padrao de cli/lib/serve.sh
# _serve_node_major/_serve_node_preflight): a arvore exige Node >= 22
# ([REAL] mcp/state-server/package.json engines.node ">=22"). Sem upper
# bound (nao ha dependencia nativa compilada tipo better-sqlite3 aqui —
# so @modelcontextprotocol/sdk + zod, JS puro, ver mcp-build-lazy.sh
# auditoria de supply chain).
_ML_MIN_NODE_MAJOR=22

_ml_node_major() {
  command -v node >/dev/null 2>&1 || return 1
  _mnm_v=$(node -v 2>/dev/null | head -1 | tr -d ' \r\n')
  case "$_mnm_v" in
    v[0-9]*) ;;
    *) return 1 ;;
  esac
  _mnm_major="${_mnm_v#v}"
  _mnm_major="${_mnm_major%%.*}"
  case "$_mnm_major" in
    ''|*[!0-9]*) return 1 ;;
  esac
  printf '%s\n' "$_mnm_major"
}

if ! _ml_major=$(_ml_node_major); then
  _ml_idle_serve "node nao encontrado no PATH (servidor MCP requer Node >= $_ML_MIN_NODE_MAJOR)"
fi
if [ "$_ml_major" -lt "$_ML_MIN_NODE_MAJOR" ]; then
  _ml_idle_serve "Node $_ml_major detectado; servidor MCP requer Node >= $_ML_MIN_NODE_MAJOR"
fi

# Build lazy (L-4): idempotente — no-op imediato se dist/src/index.js ja
# existe. stdout limpo = path do entrypoint (contrato de
# mcp-build-lazy.sh); qualquer diagnostico de erro vai para o stderr
# HERDADO deste processo (nao capturado aqui), visivel a quem observa a
# sessao do harness.
_ml_build_lazy_sh="$_ml_script_dir/mcp-build-lazy.sh"
if [ ! -x "$_ml_build_lazy_sh" ]; then
  _ml_idle_serve "mcp-build-lazy.sh nao encontrado/sem permissao de execucao em $_ml_script_dir"
fi

if _ml_entrypoint=$("$_ml_build_lazy_sh" ensure --dir "$_ml_state_server_dir"); then
  _ml_build_rc=0
else
  _ml_build_rc=$?
fi

if [ "$_ml_build_rc" -ne 0 ] || [ -z "$_ml_entrypoint" ] || [ ! -f "$_ml_entrypoint" ]; then
  _ml_idle_serve "build lazy do servidor MCP falhou (exit ${_ml_build_rc}) — ver mensagem acima em stderr"
fi

# exec: substitui este processo pelo processo node real — o stdio do
# harness passa a falar DIRETAMENTE com o servidor MCP (L-7, FR-012:
# nenhum outro processo intermediario sobrevive; o servidor morre junto
# com a sessao do harness). CSTK_MCP_PROJECT_PATH e CSTK_MCP_SCRIPTS_DIR
# sao exportados para o processo filho; qualquer MCP_MAX_TOOL_CALLS ja
# presente no ambiente e herdado sem alteracao.
export CSTK_MCP_PROJECT_PATH="$_ml_project_path"
export CSTK_MCP_SCRIPTS_DIR="$_ml_script_dir"

exec node "$_ml_entrypoint"
