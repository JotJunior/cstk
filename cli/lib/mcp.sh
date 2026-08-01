# mcp.sh — subcomando `cstk mcp` (feature state-mcp-server, FASE 1 fundacao).
#
# Ref: docs/specs/state-mcp-server/contracts/mcp-session-lifecycle.md
#        §CLI: `cstk mcp` / §`cstk mcp status`
#      docs/specs/state-mcp-server/data-model.md
#        §Entity: Orchestrator Server Session
#      docs/specs/state-mcp-server/tasks.md FASE 1 task 1.4
#
# FASE 1 fundacao: apenas `status`, sem exigir Docker rodando (F5 adiciona
# o container real via cli/lib/mcp-docker.sh + `install`/`start`/`stop`).
# `status` reporta o descritor `<state-dir>/mcp-server.json` quando existe;
# sem `--state-dir`, resolve a execucao ativa do projeto-alvo pela MESMA
# precedencia do hook PreToolUse (agente-00c vence; entre feature-00c,
# menor short-name lexicografico —
# global/skills/agente-00c-runtime/hooks/pretooluse-bash-guard.sh). Essa
# precedencia e leitura de CONVENIENCIA, read-only — nunca roteia mutacao
# (isso e por token de capacidade, ver
# global/skills/agente-00c-runtime/scripts/mcp-session.sh resolve; SEC-H3,
# contracts/mcp-session-lifecycle.md §SEC-H3).
#
# Subcomandos:
#   cstk mcp status [--state-dir DIR] [--project-path PATH]
#
# Saida (stdout, uma chave por linha — mesmo estilo de `state-backend.sh
# resolve`):
#   status=active|stopped|unavailable
#   reason=<motivo>            # presente quando != active
#   container=<nome>|-
#   session_id=<id>|-
#   mode=docker|bash-fallback|-
#
# Exit codes:
#   0 consulta bem-sucedida (inclusive status=unavailable — NAO e erro)
#   1 erro inesperado (path invalido)
#   2 uso incorreto
#
# POSIX sh puro. Sem bash-isms.

if [ -n "${_CSTK_MCP_LOADED:-}" ]; then
  return 0 2>/dev/null
fi
_CSTK_MCP_LOADED=1

if [ -n "${CSTK_LIB:-}" ] && [ -f "$CSTK_LIB/common.sh" ]; then
  # shellcheck source=./common.sh
  . "$CSTK_LIB/common.sh"
fi

# _mcp_runtime_script_path NAME -> imprime o path do script NAME do
# runtime agente-00c-runtime. Mesmo padrao de _state_migrate_script_path
# (cli/lib/state.sh): (1) PATH; (2) layout de repo relativo a CSTK_LIB
# (cli/lib -> ../../global/skills/agente-00c-runtime/scripts); (3) layout
# instalado em ~/.claude. Necessario porque testes/CI rodam o CLI da
# arvore do repo (CSTK_LIB=cli/lib), sem o runtime em ~/.claude.
_mcp_runtime_script_path() {
  _mrs_name=$1
  if command -v "$_mrs_name" >/dev/null 2>&1; then
    command -v "$_mrs_name"
    return 0
  fi
  if [ -n "${CSTK_LIB:-}" ]; then
    _mrs_repo="$CSTK_LIB/../../global/skills/agente-00c-runtime/scripts/$_mrs_name"
    if [ -f "$_mrs_repo" ]; then
      printf '%s\n' "$_mrs_repo"
      return 0
    fi
  fi
  _mrs_default="${HOME:-/tmp}/.claude/skills/agente-00c-runtime/scripts/$_mrs_name"
  if [ -f "$_mrs_default" ]; then
    printf '%s\n' "$_mrs_default"
    return 0
  fi
  return 1
}

_mcp_is_active_status() {
  case "$1" in
    em_andamento | aguardando_humano) return 0 ;;
    *) return 1 ;;
  esac
}

# _mcp_detect_active_dir PROJECT_PATH -> imprime o state-dir da execucao
# ativa (precedencia agente-00c > menor short-name feature-00c) em stdout;
# stdout vazio se nenhuma execucao ativa. Read-only. Reusa a MESMA regra
# de precedencia de hooks/pretooluse-bash-guard.sh sem reimportar codigo
# (duplicacao textual e o padrao ja praticado pelos 3 consumidores
# existentes da regra: pretooluse-bash-guard.sh,
# posttooluse-agent-usage.sh, posttooluse-tool-call-tick.sh — nenhum dos
# tres a fatorou num helper compartilhado).
_mcp_detect_active_dir() {
  _mda_proj=$1
  _mda_rw=$(_mcp_runtime_script_path state-rw.sh) || return 0

  _mda_agente="$_mda_proj/.claude/agente-00c-state"
  if [ -f "$_mda_agente/state.json" ] || [ -f "$_mda_agente/state.db" ]; then
    _mda_status=$("$_mda_rw" get --state-dir "$_mda_agente" --field '.execution.status' 2>/dev/null) || _mda_status=""
    if _mcp_is_active_status "$_mda_status"; then
      printf '%s' "$_mda_agente"
      return 0
    fi
  fi

  _mda_feat_root="$_mda_proj/.claude/feature-00c-state"
  if [ -d "$_mda_feat_root" ]; then
    _mda_shorts=""
    for _mda_d in "$_mda_feat_root"/*/; do
      [ -d "$_mda_d" ] || continue
      { [ -f "${_mda_d}state.json" ] || [ -f "${_mda_d}state.db" ]; } || continue
      _mda_status=$("$_mda_rw" get --state-dir "${_mda_d%/}" --field '.execution.status' 2>/dev/null) || continue
      _mcp_is_active_status "$_mda_status" || continue
      _mda_shorts="${_mda_shorts}$(basename "$_mda_d")
"
    done
    if [ -n "$_mda_shorts" ]; then
      # Ordem lexicografica byte-wise (C locale), deterministica —
      # mesma disciplina de pretooluse-bash-guard.sh (CHK007).
      _mda_first=$(printf '%s' "$_mda_shorts" | LC_ALL=C sort | sed -n '1p')
      printf '%s' "$_mda_feat_root/$_mda_first"
      return 0
    fi
  fi

  return 0
}

# _mcp_print_unavailable REASON -> emite o bloco de 5 linhas com
# status=unavailable. Sempre exit 0 (contrato de nao-falha: unavailable
# nao e erro).
_mcp_print_unavailable() {
  printf 'status=unavailable\n'
  printf 'reason=%s\n' "$1"
  printf 'container=-\n'
  printf 'session_id=-\n'
  printf 'mode=-\n'
}

# _mcp_print_status_from_descriptor STATE_DIR -> le
# <STATE_DIR>/mcp-server.json (se existir) e emite o bloco de 5 linhas.
_mcp_print_status_from_descriptor() {
  _desc="$1/mcp-server.json"
  if [ ! -f "$_desc" ]; then
    _mcp_print_unavailable "no-active-execution"
    return 0
  fi
  if ! command -v jq >/dev/null 2>&1; then
    _mcp_print_unavailable "jq-ausente"
    return 0
  fi
  _stopped=$(jq -r '.stopped_at // ""' "$_desc" 2>/dev/null) || _stopped=""
  _container=$(jq -r '.container_name // "-"' "$_desc" 2>/dev/null) || _container="-"
  _sid=$(jq -r '.session_id // "-"' "$_desc" 2>/dev/null) || _sid="-"
  _mode=$(jq -r '.mode // "-"' "$_desc" 2>/dev/null) || _mode="-"
  if [ -n "$_stopped" ]; then
    printf 'status=stopped\n'
    printf 'reason=stopped\n'
  else
    printf 'status=active\n'
    printf 'reason=-\n'
  fi
  printf 'container=%s\n' "$_container"
  printf 'session_id=%s\n' "$_sid"
  printf 'mode=%s\n' "$_mode"
}

_mcp_cmd_status() {
  _mcp_state_dir=""
  _mcp_project_path=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir) _mcp_state_dir=$2; shift 2 ;;
      --project-path) _mcp_project_path=$2; shift 2 ;;
      *)
        printf 'cstk mcp status: flag desconhecida: %s\n' "$1" >&2
        return 2
        ;;
    esac
  done

  if [ -n "$_mcp_state_dir" ]; then
    if [ ! -d "$_mcp_state_dir" ]; then
      printf 'cstk mcp status: --state-dir nao existe: %s\n' "$_mcp_state_dir" >&2
      return 1
    fi
    _mcp_print_status_from_descriptor "$_mcp_state_dir"
    return 0
  fi

  if [ -n "$_mcp_project_path" ]; then
    if [ ! -d "$_mcp_project_path" ]; then
      printf 'cstk mcp status: --project-path nao existe: %s\n' "$_mcp_project_path" >&2
      return 1
    fi
    _mcp_dir=$(_mcp_detect_active_dir "$_mcp_project_path")
    if [ -z "$_mcp_dir" ]; then
      _mcp_print_unavailable "no-active-execution"
      return 0
    fi
    _mcp_print_status_from_descriptor "$_mcp_dir"
    return 0
  fi

  printf 'cstk mcp status: forneca --state-dir DIR ou --project-path PATH\n' >&2
  return 2
}

_mcp_usage() {
  cat <<'HELP'
cstk mcp — operacoes sobre o servidor MCP de estado das execucoes 00c

USO:
  cstk mcp status [--state-dir DIR] [--project-path PATH]
      Reporta status=active|stopped|unavailable sem inspecionar Docker
      diretamente (fundacao FASE 1; F5 adiciona start/stop com container
      real). Sem --state-dir, resolve a execucao ativa do projeto-alvo
      pela mesma precedencia do hook PreToolUse (consulta de
      conveniencia, read-only — nunca usada para roteamento de mutacao).

EXIT CODES:
  0 consulta bem-sucedida (inclusive status=unavailable)
  1 erro inesperado
  2 uso incorreto
HELP
}

mcp_main() {
  _mcp_sub="${1:-}"
  [ "$#" -ge 1 ] && shift || :

  case "$_mcp_sub" in
    ''|-h|--help|help)
      _mcp_usage
      return 0
      ;;
    status)
      _mcp_cmd_status "$@"
      return $?
      ;;
    *)
      printf 'cstk mcp: subcomando desconhecido: %s\n' "$_mcp_sub" >&2
      printf 'Subcomandos validos: status\n' >&2
      return 2
      ;;
  esac
}
