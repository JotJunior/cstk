#!/bin/sh
# mcp-launch.sh — entrypoint stdio registrado em `.mcp.json` (`cstk mcp
# install`, cli/lib/mcp.sh::_mcp_cmd_install).
#
# Ref: docs/specs/state-mcp-server/contracts/mcp-session-lifecycle.md
#        §CLI: `cstk mcp` / §`cstk mcp install` / §Resolucao da execucao
#        ativa (helper mcp-session.sh) / §SEC-H3
#      docs/specs/state-mcp-server/tasks.md FASE 6 task 6.1.2
#
# PAPEL: o harness (Claude Code) invoca este script como o `command` do
# `.mcp.json` para abrir o transporte stdio da tool MCP `cstk-state`. O
# servidor de verdade (mcp/state-server) ja esta rodando DENTRO de um
# container Docker dedicado, subido DETACHED (`docker run -d -i`, stdin
# mantido aberto) por `cstk mcp start` (cli/lib/mcp-docker.sh::
# _mcp_docker_run) — este script so PRECISA descobrir QUAL container
# pertence a execucao corrente e entregar o stdio do harness a ele.
#
# Roteamento por CAPACIDADE (SEC-H3), nao por precedencia: reusa
# `mcp-session.sh resolve --project-path` (mesmo script, mesmo protocolo
# de token ja usado por `cstk mcp status`). O token vem de
# MCP_SESSION_TOKEN (env) — dec-043: a geracao/injecao REAL do token
# pelos commands pai (/agente-00c, /feature-00c) fica FORA do escopo
# desta feature; ate essa coordenacao cross-feature concluir, um token
# SINTETICO exportado na mesma env cobre o roteamento (mesmo mecanismo
# ja usado pelos testes de mcp-session.sh/task 1.3).
#
# AUSENCIA GRACIOSA (modo IDLE — fix pos-v6.2.0, bug "-32000 no boot"):
# a entrada do `.mcp.json` e estatica e o harness a conecta em TODO boot
# de sessao — inclusive (caso mais comum) sem nenhuma execucao 00c ativa.
# Sair com exit != 0 aqui fazia o harness reportar "Failed to reconnect
# to cstk-state: -32000" em toda sessao normal. Em vez disso:
#   - SEM token de sessao (MCP_SESSION_TOKEN vazio — boot normal), ou
#     sessao resolvida SEM container docker (mode=bash-fallback/stopped):
#     servir um stub MCP IDLE em sh+jq — responde initialize/tools/list
#     (ZERO tools)/ping e nada mais. Zero tools => zero mutacao possivel
#     (SEC-H3 intacto); o /mcp mostra o servidor conectado, sem erro.
#   - Token FORNECIDO e divergente => exit 3 barulhento (violacao de
#     capacidade, nunca e caso benigno).
#   - Falha de MECANISMO (mcp-session.sh/jq ausentes) => exit 1 barulhento.
# O command pai segue decidindo ANTES do spawn (via `cstk mcp status`) se
# a onda usa o caminho MCP ou o Bash (FR-007/FR-012) — este script nunca
# e o unico guardiao dessa decisao. Para anexar ao container depois de
# `cstk mcp start`, reconecte o MCP (/mcp) ou abra sessao nova.
#
# `exec docker attach <container>` substitui o PROCESSO deste script
# (nao um subshell) — o stdio do harness passa a falar DIRETAMENTE com o
# PID1 do container, sem camada intermediaria. Nenhuma outra invocacao de
# `docker` acontece aqui (attach e read-only quanto ao ciclo de vida do
# container; start/stop/gc continuam confinados a cli/lib/mcp-docker.sh
# — Constitution carve-out condicao b, dec-074, um arquivo por par
# dependencia-feature via cli/lib/mcp.sh + mcp-docker.sh).
#
# POSIX sh puro. Deps: docker (subcomando `attach`), o proprio
# mcp-session.sh (jq, indiretamente).
#
# Exit codes:
#   0  modo IDLE encerrado por EOF do harness (sessao fechou), ou attach
#      encerrado normalmente
#   1  falha de MECANISMO (mcp-session.sh ausente, jq ausente no idle,
#      docker ausente quando a sessao exige attach)
#   3  SESSION_MISMATCH com token FORNECIDO (violacao de capacidade —
#      nunca degrada para idle)

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
  printf '%s: %s — servindo em modo IDLE (0 tools). Apos iniciar uma execucao 00c com Docker (`cstk mcp start` via command pai), reconecte o MCP (/mcp) para anexar ao container.\n' \
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
            '{jsonrpc:"2.0", id:.id, error:{code:-32601, message:"cstk-state em modo idle: nenhuma execucao 00c ativa"}}'
        fi
        ;;
    esac
  done
  exit 0
}

# Diretorio deste proprio script — mcp-session.sh vive ao lado dele tanto
# no catalogo instalado (~/.claude/skills/agente-00c-runtime/scripts/)
# quanto no layout de repo/dev (global/skills/agente-00c-runtime/scripts/).
_ml_script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd -P) \
  || _ml_die "nao consegui resolver o proprio diretorio"

_ml_session_sh="$_ml_script_dir/mcp-session.sh"
[ -f "$_ml_session_sh" ] || _ml_die "mcp-session.sh nao encontrado em $_ml_script_dir"
[ -x "$_ml_session_sh" ] || _ml_die "mcp-session.sh sem permissao de execucao em $_ml_script_dir"

# Project-path: o harness invoca com CWD = raiz do projeto-alvo (onde
# vive o .mcp.json que referencia este script — doc oficial do .mcp.json,
# nao [VERIFICADO] neste repo). Override via CSTK_MCP_PROJECT_PATH para
# testes/dev, onde o CWD do processo pode nao ser o projeto-alvo.
_ml_project_path="${CSTK_MCP_PROJECT_PATH:-$(pwd)}"

# Sem token de sessao = boot normal do harness fora de execucao 00c — o
# caso mais comum. Nao ha o que rotear (mutacao exige token, SEC-H3):
# modo idle, nunca erro.
if [ -z "${MCP_SESSION_TOKEN:-}" ]; then
  _ml_idle_serve "nenhuma execucao 00c ativa nesta sessao (sem token)"
fi

if _ml_resolved=$("$_ml_session_sh" resolve --project-path "$_ml_project_path" 2>&1); then
  _ml_rc=0
else
  _ml_rc=$?
fi

if [ "$_ml_rc" -ne 0 ]; then
  # Token FORNECIDO e resolucao falhou: capacidade divergente/colisao —
  # NUNCA degrada para idle (SEC-H3), falha barulhenta como antes.
  printf '%s: resolve falhou (exit %s): %s\n' "$_ML_NAME" "$_ml_rc" "$_ml_resolved" >&2
  exit "$_ml_rc"
fi

_ml_container=$(printf '%s\n' "$_ml_resolved" | sed -n 's/^container=//p')
_ml_mode=$(printf '%s\n' "$_ml_resolved" | sed -n 's/^mode=//p')

if [ "$_ml_mode" != "docker" ] || [ -z "$_ml_container" ] || [ "$_ml_container" = "-" ]; then
  # Execucao ativa mas sem container (bash-fallback/stopped): benigno —
  # a onda roda pelo caminho Bash; o MCP fica conectado em idle.
  _ml_idle_serve "execucao resolvida sem container docker (mode=${_ml_mode:-'-'})"
fi

command -v docker >/dev/null 2>&1 || _ml_die "docker nao encontrado no PATH (sessao exige attach)"

# exec: substitui este processo — o stdio do harness passa a ser o stdio
# do container (mantido aberto desde `docker run -d -i` em
# _mcp_docker_run). NUNCA um subshell/pipe intermediario: qualquer
# camada extra quebraria o handshake stdio do MCP.
exec docker attach "$_ml_container"
