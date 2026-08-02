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
# Falha de resolucao (token ausente/invalido/colisao, ou sessao sem
# container docker ativo) => exit != 0 SEM tentar `docker attach` — o
# harness reporta a tool como indisponivel para ESTA sessao, mas isso
# nunca bloqueia a execucao: o command pai ja decidiu ANTES do spawn (via
# `cstk mcp status`) se usa o caminho MCP ou o caminho Bash de sempre
# (FR-007/FR-012) — este script nunca e o unico guardiao dessa decisao.
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
#   0  nunca observado em uso normal (docker attach so retorna quando a
#      sessao MCP encerra do lado do container — o proprio exit code do
#      attach e propagado via exec)
#   1  erro de resolucao (mcp-session.sh ausente, docker ausente)
#   3  SESSION_MISMATCH (propagado de mcp-session.sh resolve) ou sessao
#      resolvida sem container docker ativo (mode != docker)

set -eu

_ML_NAME="mcp-launch"

_ml_die() {
  printf '%s: %s\n' "$_ML_NAME" "$1" >&2
  exit "${2:-1}"
}

# Diretorio deste proprio script — mcp-session.sh vive ao lado dele tanto
# no catalogo instalado (~/.claude/skills/agente-00c-runtime/scripts/)
# quanto no layout de repo/dev (global/skills/agente-00c-runtime/scripts/).
_ml_script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd -P) \
  || _ml_die "nao consegui resolver o proprio diretorio"

_ml_session_sh="$_ml_script_dir/mcp-session.sh"
[ -f "$_ml_session_sh" ] || _ml_die "mcp-session.sh nao encontrado em $_ml_script_dir"
[ -x "$_ml_session_sh" ] || _ml_die "mcp-session.sh sem permissao de execucao em $_ml_script_dir"

command -v docker >/dev/null 2>&1 || _ml_die "docker nao encontrado no PATH"

# Project-path: o harness invoca com CWD = raiz do projeto-alvo (onde
# vive o .mcp.json que referencia este script — doc oficial do .mcp.json,
# nao [VERIFICADO] neste repo). Override via CSTK_MCP_PROJECT_PATH para
# testes/dev, onde o CWD do processo pode nao ser o projeto-alvo.
_ml_project_path="${CSTK_MCP_PROJECT_PATH:-$(pwd)}"

if _ml_resolved=$("$_ml_session_sh" resolve --project-path "$_ml_project_path" 2>&1); then
  _ml_rc=0
else
  _ml_rc=$?
fi

if [ "$_ml_rc" -ne 0 ]; then
  printf '%s: resolve falhou (exit %s): %s\n' "$_ML_NAME" "$_ml_rc" "$_ml_resolved" >&2
  exit "$_ml_rc"
fi

_ml_container=$(printf '%s\n' "$_ml_resolved" | sed -n 's/^container=//p')
_ml_mode=$(printf '%s\n' "$_ml_resolved" | sed -n 's/^mode=//p')

if [ "$_ml_mode" != "docker" ] || [ -z "$_ml_container" ] || [ "$_ml_container" = "-" ]; then
  _ml_die "sessao resolvida sem container docker ativo (mode=${_ml_mode:-'-'} container=${_ml_container:-'-'}) — nada para conectar" 3
fi

# exec: substitui este processo — o stdio do harness passa a ser o stdio
# do container (mantido aberto desde `docker run -d -i` em
# _mcp_docker_run). NUNCA um subshell/pipe intermediario: qualquer
# camada extra quebraria o handshake stdio do MCP.
exec docker attach "$_ml_container"
