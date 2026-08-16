#!/bin/sh
# mcp-session.sh — resolucao da execucao ativa por TOKEN DE CAPACIDADE (SEC-H3).
#
# Ref: docs/specs/state-mcp-server/spec.md FR-016, FR-008
#      docs/specs/state-mcp-server/contracts/mcp-session-lifecycle.md
#        §Resolucao da execucao ativa (helper mcp-session.sh)
#      docs/specs/state-mcp-server/data-model.md
#        §Entity: Orchestrator Server Session
#      docs/specs/state-mcp-server/tasks.md FASE 1 task 1.3
#      docs/specs/mcp-direct-transport/spec.md FR-003 (fail-closed em
#        execucao terminal); tasks.md FASE 8 (dec-060/dec-061)
#
# Fail-closed por desenho (SEC-H3, finding HIGH do gate owasp-security,
# onda-003/block-001/dec-021, ratificado em dec-023/onda-004): o
# roteamento de MUTACAO nunca usa a precedencia do hook PreToolUse
# (agente-00c vence; entre feature-00c, menor short-name lexicografico —
# plugins/cstk/skills/agente-00c-runtime/hooks/pretooluse-bash-guard.sh). Essa
# regra so vale para uma guarda que BLOQUEIA; aqui o roteador MUTA, entao
# a autorizacao e por POSSE de um token de capacidade — o `session_id` do
# descritor `<state-dir>/mcp-server.json` (>= 128 bits CSPRNG, gravado por
# `cstk mcp start`) — nunca por heuristica de ambiente. Token
# ausente/desconhecido/de execucao ja terminal ⇒ SESSION_MISMATCH, sem
# fallback para "a execucao ativa mais provavel".
#
# "Execucao ja terminal" e aferido em DUAS camadas (dec-060/dec-061,
# `mcp-direct-transport` FASE 8): (1) o proxy `.stopped_at` do proprio
# descritor — barato, mas so reflete `cstk mcp stop`, chamado pelos
# commands pai em best-effort; se `stop` nunca rodar (aborto/crash/sessao
# interrompida), o proxy nunca acusa terminal; (2) o status REAL da
# execucao (`.execution.status` via `state-rw.sh get`, backend-agnostico)
# — `_ms_execution_active`. As duas camadas MUST concordar; qualquer uma
# recusando e suficiente para SESSION_MISMATCH.
#
# Subcomandos:
#   mcp-session.sh resolve --project-path PATH
#       [--token TOKEN | --token-file FILE]
#     Le o token nesta ordem de precedencia: --token, --token-file, env
#     MCP_SESSION_TOKEN (aceita token SINTETICO por qualquer uma das tres
#     fontes — viabiliza testes desta fase sem depender da coordenacao
#     cross-feature ainda pendente com os commands pai, task 1.2). Varre
#     os descritores `mcp-server.json` de TODAS as execucoes do
#     projeto-alvo (`.claude/agente-00c-state/` +
#     `.claude/feature-00c-state/*/`) e imprime os campos do UNICO
#     descritor cujo `session_id` bate exatamente e cujo `stopped_at`
#     ainda e nulo. Zero match, mais de um match (colisao) ou token vazio
#     => SESSION_MISMATCH (exit 3), nada em stdout.
#
#   mcp-session.sh resolve --state-dir DIR
#       [--token TOKEN | --token-file FILE]
#     Modo DIRETO (task 5.3, dec-081) — mutuamente exclusivo com
#     --project-path. Le e valida `DIR/mcp-server.json` sem nenhum
#     tree-walk. Existe porque, DENTRO do container do servidor MCP
#     (contracts/mcp-session-lifecycle.md §Montagens), apenas o
#     state-dir da propria execucao esta montado (`/data/state`, flat) —
#     o `CSTK_MCP_PROJECT_PATH` (path do HOST) nao existe como diretorio
#     no container, entao o modo `--project-path` (tree-walk a partir do
#     projeto-alvo) sempre falharia ali. O container e 1:1 com uma unica
#     execucao (data-model.md), entao nao ha ambiguidade/precedencia a
#     resolver — a MESMA regra de autorizacao por token de capacidade
#     (SEC-H3) se aplica identica: token vazio, divergente do
#     `session_id` do descritor, ou `stopped_at` preenchido =>
#     SESSION_MISMATCH (exit 3). Nenhum comportamento do modo
#     `--project-path` existente muda.
#
# Saida (stdout, uma chave por linha — mesmo estilo de `state-backend.sh
# resolve` / `cstk mcp status`):
#   state_dir=<path>
#   execution_kind=<agente-00c|feature-00c>
#   short_name=<name|->
#   target_project_path=<path>
#   mode=<docker|bash-fallback>
#   container=<name|->
#
# Exit codes:
#   0 sucesso (descritor unico resolvido)
#   1 erro generico (I/O, jq ausente)
#   2 uso incorreto
#   3 SESSION_MISMATCH (fail-closed — token invalido/ausente/terminal/colisao)
#
# POSIX sh + jq.

set -eu

_MS_NAME="mcp-session"

_ms_die_usage() {
  printf '%s: %s\n' "$_MS_NAME" "$1" >&2
  exit 2
}

_ms_die() {
  printf '%s: %s\n' "$_MS_NAME" "$1" >&2
  exit "${2:-1}"
}

_ms_mismatch() {
  printf '%s: resolve: SESSION_MISMATCH (%s)\n' "$_MS_NAME" "$1" >&2
  exit 3
}

_ms_require_jq() {
  command -v jq >/dev/null 2>&1 \
    || _ms_die "jq nao encontrado no PATH (brew install jq | apt install jq)" 1
}

# _ms_resolve_token EXPLICIT TOKENFILE -> imprime o token em stdout (string
# vazia se nenhuma fonte forneceu um); a validacao de "vazio" e feita pelo
# caller (resolve). Ordem: --token > --token-file > env MCP_SESSION_TOKEN.
_ms_resolve_token() {
  _explicit=$1
  _file=$2
  if [ -n "$_explicit" ]; then
    printf '%s' "$_explicit"
    return 0
  fi
  if [ -n "$_file" ]; then
    [ -f "$_file" ] || _ms_die "resolve: --token-file nao encontrado: $_file" 1
    _t=$(head -n 1 -- "$_file" 2>/dev/null) || _t=""
    printf '%s' "$_t"
    return 0
  fi
  if [ -n "${MCP_SESSION_TOKEN:-}" ]; then
    printf '%s' "$MCP_SESSION_TOKEN"
    return 0
  fi
  printf '%s' ""
}

# Diretorio do proprio script — resolve o script irmao state-rw.sh (mesmo
# padrao de state-ondas.sh::_so_self_dir / model-routing.sh).
_ms_self_dir() {
  CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd -P
}

# _ms_execution_active EXEC_DIR -> exit 0 SOMENTE se o status REAL da
# execucao (`.execution.status`, lido via `state-rw.sh get` — backend-
# agnostico, funciona sob state.json OU state.db, nunca le state.json
# direto) esta em {em_andamento, aguardando_humano}. Exit 1 em QUALQUER
# outro caso: status terminal (concluida/abortada), status vazio/
# desconhecido, ou falha de leitura (self-dir irresolvivel, state-rw.sh
# ausente, state ausente/corrompido, jq/sqlite3 indisponivel).
#
# Fail-closed por desenho (mesmo principio de SEC-H3 no cabecalho deste
# arquivo): uma leitura que FALHA nunca e tratada como "execucao ativa" —
# equivale a dizer "nao consigo provar que esta ativa, logo recuso".
#
# Origem (dec-060/dec-061, feature `mcp-direct-transport` FASE 8):
# `_ms_check_descriptor` so conferia `.stopped_at` do PROPRIO descritor
# (proxy). Quem grava `stopped_at` e `cstk mcp stop`, chamado pelos
# commands pai em best-effort (`|| :`) e somente quando o status ja e
# concluida/abortada — se `stop` nao rodar (aborto, crash, sessao
# interrompida, ou falha engolida pelo `|| :`), a execucao termina e o
# token de capacidade permanecia valido indefinidamente (SESSION_MISMATCH
# nunca disparava, violando FR-003 "pertenca a uma execucao em status
# terminal"). Esta funcao consulta a fonte de verdade REAL alem do proxy.
_ms_execution_active() {
  _mea_dir=$1
  _mea_selfdir=$(_ms_self_dir) || return 1
  _mea_rw="$_mea_selfdir/state-rw.sh"
  [ -f "$_mea_rw" ] || return 1
  _mea_status=$(sh "$_mea_rw" get --state-dir "$_mea_dir" --field '.execution.status' 2>/dev/null) || return 1
  case "$_mea_status" in
    em_andamento | aguardando_humano) return 0 ;;
    *) return 1 ;;
  esac
}

# _ms_check_descriptor DESCRIPTOR_PATH TOKEN -> exit 0 SE o descritor
# existe, `session_id` bate exatamente com TOKEN, `stopped_at` e nulo
# (proxy do descritor) E o status REAL da execucao (state-rw.sh get,
# dec-060/dec-061) esta em {em_andamento, aguardando_humano}; exit 1 caso
# contrario. Nunca imprime nada nem aborta o script — quem decide o
# resultado agregado e o caller.
_ms_check_descriptor() {
  _desc=$1
  _token=$2
  [ -f "$_desc" ] || return 1
  _sid=$(jq -r '.session_id // ""' "$_desc" 2>/dev/null) || return 1
  [ -n "$_sid" ] || return 1
  [ "$_sid" = "$_token" ] || return 1
  _stopped=$(jq -r '.stopped_at // ""' "$_desc" 2>/dev/null) || _stopped=""
  [ -z "$_stopped" ] || return 1   # execucao ja terminal por PROXY — fail-closed
  _ms_execution_active "$(dirname -- "$_desc")" || return 1   # status REAL — fail-closed
  return 0
}

# _ms_print_descriptor DESCRIPTOR_PATH [STATE_DIR_OVERRIDE]
#
# STATE_DIR_OVERRIDE (task 5.3, achado empirico com Docker real — validando
# `cstk mcp start`/health check ponta a ponta): quando fornecido, imprime
# esse valor em vez de `.state_dir` do proprio descritor. Existe porque o
# campo `.state_dir` do JSON e sempre o path ABSOLUTO DO HOST (gravado por
# `cli/lib/mcp.sh::_mcp_write_descriptor` — data-model.md "state_dir |
# path absoluto"). No modo DIRETO (`--state-dir`, dec-081), quem chama esta
# funcao esta DENTRO do container, onde o path do host nao existe no
# filesystem — so o mount `/data/state` (ou o que veio em
# CSTK_MCP_STATE_DIR) e valido ali. Sem este override, toda tool MCP que
# usa `session.stateDir` (mcp/state-server/src/session/resolve.ts) recebia
# o path do HOST e falhava (`state-ondas.sh wave-status: state.json
# ausente em <path-do-host>`, sonda: `docker logs` de um container real
# apos `cstk mcp start` bem-sucedido). No modo `--project-path`
# (tree-walk, quem chama roda no HOST), NENHUM override e passado — o
# `.state_dir` do proprio descritor (ja o path certo do host) permanece
# inalterado, zero regressao.
_ms_print_descriptor() {
  _desc=$1
  _sd_override=${2:-}
  jq -r --arg override "$_sd_override" '
    "state_dir=" + (if $override != "" then $override else (.state_dir // "-") end),
    "execution_kind=" + (.execution_kind // "-"),
    "short_name=" + (.short_name // "-"),
    "target_project_path=" + (.target_project_path // "-"),
    "mode=" + (.mode // "-"),
    "container=" + (.container_name // "-")
  ' "$_desc"
}

_ms_cmd_resolve() {
  _project_path=""
  _state_dir=""
  _token_explicit=""
  _token_file=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --project-path) _project_path=$2; shift 2 ;;
      --state-dir) _state_dir=$2; shift 2 ;;
      --token) _token_explicit=$2; shift 2 ;;
      --token-file) _token_file=$2; shift 2 ;;
      *) _ms_die_usage "resolve: flag desconhecida: $1" ;;
    esac
  done

  if [ -n "$_project_path" ] && [ -n "$_state_dir" ]; then
    _ms_die_usage "resolve: --project-path e --state-dir sao mutuamente exclusivos"
  fi
  if [ -z "$_project_path" ] && [ -z "$_state_dir" ]; then
    _ms_die_usage "resolve: forneca --project-path PATH ou --state-dir DIR"
  fi
  _ms_require_jq

  _token=$(_ms_resolve_token "$_token_explicit" "$_token_file")
  if [ -z "$_token" ]; then
    _ms_mismatch "nenhum token fornecido (--token | --token-file | MCP_SESSION_TOKEN)"
  fi

  # Modo direto (dec-081, task 5.3): usado DENTRO do container, onde so o
  # state-dir da propria execucao esta montado. Sem tree-walk, sem
  # ambiguidade — o container e 1:1 com uma execucao.
  if [ -n "$_state_dir" ]; then
    [ -d "$_state_dir" ] \
      || _ms_die "resolve: --state-dir nao existe ou nao e diretorio: $_state_dir" 1
    _direct_desc="$_state_dir/mcp-server.json"
    if ! _ms_check_descriptor "$_direct_desc" "$_token"; then
      _ms_mismatch "token desconhecido, invalido ou de execucao ja terminal (--state-dir)"
    fi
    _ms_print_descriptor "$_direct_desc" "$_state_dir"
    return 0
  fi

  [ -d "$_project_path" ] \
    || _ms_die "resolve: --project-path nao existe ou nao e diretorio: $_project_path" 1

  _match=""
  _match_count=0

  _agente_desc="$_project_path/.claude/agente-00c-state/mcp-server.json"
  if _ms_check_descriptor "$_agente_desc" "$_token"; then
    _match="$_agente_desc"
    _match_count=$((_match_count + 1))
  fi

  _feat_root="$_project_path/.claude/feature-00c-state"
  if [ -d "$_feat_root" ]; then
    for _d in "$_feat_root"/*/; do
      [ -d "$_d" ] || continue
      _fd="${_d}mcp-server.json"
      if _ms_check_descriptor "$_fd" "$_token"; then
        _match="$_fd"
        _match_count=$((_match_count + 1))
      fi
    done
  fi

  if [ "$_match_count" -eq 0 ]; then
    _ms_mismatch "token desconhecido, invalido ou de execucao ja terminal"
  fi
  if [ "$_match_count" -gt 1 ]; then
    _ms_mismatch "colisao de token entre multiplas execucoes — recusado, nunca roteia por precedencia"
  fi

  _ms_print_descriptor "$_match"
}

# ---------- Dispatch ----------

if [ "$#" -lt 1 ]; then
  cat >&2 <<'HELP'
mcp-session.sh — resolucao da execucao ativa por token de capacidade (SEC-H3).

USO:
  mcp-session.sh resolve --project-path PATH \
      [--token TOKEN | --token-file FILE]
  mcp-session.sh resolve --state-dir DIR \
      [--token TOKEN | --token-file FILE]

  --project-path e --state-dir sao mutuamente exclusivos. --state-dir e o
  modo direto usado DENTRO do container do servidor MCP (dec-081): sem
  tree-walk, valida so DIR/mcp-server.json.

  Token tambem pode vir de MCP_SESSION_TOKEN (env), com precedencia
  --token > --token-file > env.

EXIT:
  0 sucesso
  1 erro generico
  2 uso incorreto
  3 SESSION_MISMATCH (fail-closed — token invalido/ausente/terminal/colisao)
HELP
  exit 2
fi

_MS_SUBCMD=$1
shift

case "$_MS_SUBCMD" in
  resolve)         _ms_cmd_resolve "$@" ;;
  -h|--help|help)  exit 0 ;;
  *) _ms_die_usage "subcomando desconhecido: $_MS_SUBCMD" ;;
esac
