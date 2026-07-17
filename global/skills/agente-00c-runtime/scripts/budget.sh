#!/bin/sh
# budget.sh — proxies de orcamento de sessao (FR-009).
#
# Ref: docs/specs/agente-00c/spec.md FR-009
#      docs/specs/agente-00c/research.md Decision 2
#      docs/specs/agente-00c/tasks.md FASE 5.1
#
# Os proxies cobrem 3 dimensoes (chaves EN do schema; fallback pt-BR no read):
#   1. tool_calls_current_wave >= tool_calls_threshold_wave (default 80)
#      (valor corrente = campo do state + linhas do sidecar
#      <state-dir>/tool-call-ticks.log appendado pelo hook PostToolUse
#      posttooluse-tool-call-tick.sh — mesma agregacao do state-ondas.sh end)
#   2. wallclock (now - current_wave_start) >= wallclock_threshold_seconds (5400 = 90min)
#   3. file size de state.json >= state_size_threshold_bytes (1MB)
#
# Sem signal nativo de tokens consumidos no Claude Code (Decision 2);
# por isso usa proxies indiretos.
#
# Subcomandos:
#   budget.sh check --state-dir DIR
#       — Avalia os 3 proxies. Se NENHUM disparou, exit 0.
#       — Se algum disparou, exit 1 + linha em stdout: TIPO\tCURRENT\tTHRESHOLD
#         TIPO = tool_calls | wallclock | state_size
#       — Atalho de aborto graceful para o orquestrador.
#   budget.sh status --state-dir DIR
#       — Imprime os 3 valores correntes vs thresholds (TSV) sem fazer veredito.
#         Util para logging/diagnostico.
#
# Exit codes:
#   0 dentro dos limites
#   1 algum threshold disparou (orquestrador deve fechar onda)
#   2 uso incorreto
#
# POSIX sh + jq + date + stat (BSD/GNU detection).

set -eu

_BD_NAME="budget"

_bd_die_usage() { printf '%s: %s\n' "$_BD_NAME" "$1" >&2; exit 2; }
_bd_die()       { printf '%s: %s\n' "$_BD_NAME" "$1" >&2; exit "${2:-1}"; }

_bd_require_jq() {
  command -v jq >/dev/null 2>&1 \
    || _bd_die "jq nao encontrado no PATH (brew install jq | apt install jq)" 1
}

_bd_state_file() { printf '%s/state.json\n' "$1"; }

# _bd_file_size FILE -> tamanho em bytes (portavel BSD/GNU)
_bd_file_size() {
  if stat -f '%z' -- "$1" >/dev/null 2>&1; then
    stat -f '%z' -- "$1"
  elif stat -c '%s' -- "$1" >/dev/null 2>&1; then
    stat -c '%s' -- "$1"
  else
    # Fallback POSIX: wc -c (incl newline final, pode ser off-by-1; aceitavel
    # para threshold de 1MB).
    wc -c < "$1" | tr -d ' '
  fi
}

# _bd_iso_to_epoch ISO_TS -> epoch seconds (BSD/GNU); falha = 0
_bd_iso_to_epoch() {
  if _e=$(date -u -d "$1" +%s 2>/dev/null); then
    printf '%s\n' "$_e"
    return 0
  fi
  if _e=$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$1" +%s 2>/dev/null); then
    printf '%s\n' "$_e"
    return 0
  fi
  printf '0\n'
  return 1
}

_bd_now_epoch() { date -u +%s; }

# _bd_collect STATE_DIR
# Sets globals: _bd_tc, _bd_tc_max, _bd_wc, _bd_wc_max, _bd_sz, _bd_sz_max
_bd_collect() {
  _sf=$(_bd_state_file "$1")
  [ -f "$_sf" ] || _bd_die "state.json ausente em $1" 1
  _bd_require_jq
  # Readers diretos sobre o arquivo (schema-en-migration): path EN + fallback
  # (.en // .pt) para back-compat com states pt-BR vivos e com direct-writers
  # ainda nao migrados (ex: state-ondas.sh grava .orcamentos.inicio_onda_corrente).
  _bd_tc_field=$(jq -r '(.budgets.tool_calls_current_wave // .orcamentos.tool_calls_onda_corrente) // 0' "$_sf")
  # Sidecar do hook PostToolUse (ticks automaticos); ausente/ilegivel = 0.
  _bd_tc_side=0
  _bd_ticks="$1/tool-call-ticks.log"
  if [ -f "$_bd_ticks" ]; then
    _bd_tc_side=$(wc -l < "$_bd_ticks" 2>/dev/null | tr -d '[:space:]') || _bd_tc_side=0
    case "$_bd_tc_side" in '' | *[!0-9]*) _bd_tc_side=0 ;; esac
  fi
  _bd_tc=$((_bd_tc_field + _bd_tc_side))
  _bd_tc_max=$(jq -r '(.budgets.tool_calls_threshold_wave // .orcamentos.tool_calls_threshold_onda) // 80' "$_sf")
  _bd_wc_max=$(jq -r '(.budgets.wallclock_threshold_seconds // .orcamentos.wallclock_threshold_segundos) // 5400' "$_sf")
  _bd_sz_max=$(jq -r '(.budgets.state_size_threshold_bytes // .orcamentos.estado_size_threshold_bytes) // 1048576' "$_sf")
  _bd_inicio=$(jq -r '(.budgets.current_wave_start // .orcamentos.inicio_onda_corrente) // ""' "$_sf")
  if [ -n "$_bd_inicio" ]; then
    _bd_inicio_e=$(_bd_iso_to_epoch "$_bd_inicio") || _bd_inicio_e=0
    if [ "$_bd_inicio_e" -gt 0 ]; then
      _bd_wc=$(( $(_bd_now_epoch) - _bd_inicio_e ))
    else
      _bd_wc=0
    fi
  else
    _bd_wc=0
  fi
  _bd_sz=$(_bd_file_size "$_sf")
}

_bd_cmd_check() {
  _sd=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir) _sd=$2; shift 2 ;;
      *) _bd_die_usage "check: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sd" ] || _bd_die_usage "check: --state-dir obrigatorio"
  _bd_collect "$_sd"

  _triggered=0
  if [ "$_bd_tc" -ge "$_bd_tc_max" ]; then
    printf 'tool_calls\t%s\t%s\n' "$_bd_tc" "$_bd_tc_max"
    _triggered=1
  fi
  if [ "$_bd_wc" -ge "$_bd_wc_max" ]; then
    printf 'wallclock\t%s\t%s\n' "$_bd_wc" "$_bd_wc_max"
    _triggered=1
  fi
  if [ "$_bd_sz" -ge "$_bd_sz_max" ]; then
    printf 'state_size\t%s\t%s\n' "$_bd_sz" "$_bd_sz_max"
    _triggered=1
  fi
  if [ "$_triggered" = 0 ]; then
    return 0
  fi
  exit 1
}

_bd_cmd_status() {
  _sd=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir) _sd=$2; shift 2 ;;
      *) _bd_die_usage "status: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sd" ] || _bd_die_usage "status: --state-dir obrigatorio"
  _bd_collect "$_sd"
  printf 'tool_calls\t%s\t%s\n' "$_bd_tc" "$_bd_tc_max"
  printf 'wallclock\t%s\t%s\n'  "$_bd_wc" "$_bd_wc_max"
  printf 'state_size\t%s\t%s\n' "$_bd_sz" "$_bd_sz_max"
}

# ---------- Dispatch ----------

if [ "$#" -lt 1 ]; then
  cat >&2 <<'HELP'
budget.sh — proxies de orcamento de sessao (FR-009).

USO:
  budget.sh check  --state-dir DIR
  budget.sh status --state-dir DIR

EXIT (check):
  0 dentro dos limites
  1 algum threshold disparou (TIPO\tCURRENT\tTHRESHOLD em stdout)
  2 uso incorreto

Saida (status): tabela TSV com tool_calls, wallclock, state_size.
HELP
  exit 2
fi

_BD_SUBCMD=$1
shift

case "$_BD_SUBCMD" in
  check)           _bd_cmd_check "$@" ;;
  status)          _bd_cmd_status "$@" ;;
  -h|--help|help)  exit 0 ;;
  *) _bd_die_usage "subcomando desconhecido: $_BD_SUBCMD" ;;
esac
