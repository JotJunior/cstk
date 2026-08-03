#!/bin/sh
# retro.sh — limite de retro-execucoes (FR-006).
#
# Ref: docs/specs/agente-00c/spec.md FR-006
#      docs/specs/agente-00c/constitution.md §IV (Autonomia Limitada)
#      docs/specs/agente-00c/tasks.md FASE 5.6
#
# Semantica:
#   - Toda vez que o orquestrador volta para a etapa anterior (retro), ele
#     consome 1 unidade do orcamento `budgets.retro_executions_consumed`.
#   - Limite default: 2 retros por feature.
#   - 3a tentativa = bloqueio humano (delegado ao orquestrador via
#     `bloqueios.sh register`).
#
# Subcomandos:
#   retro.sh check --state-dir DIR
#       — Exit 0 se pode consumir mais 1 retro (consumed < max).
#       — Exit 3 se ja no limite (consumed == max).
#   retro.sh consume --state-dir DIR
#       — Incrementa budgets.retro_executions_consumed.
#       — Exit 3 SEM modificar estado se incremento excederia max.
#       — Stdout: novo valor consumido.
#   retro.sh count --state-dir DIR
#       — Imprime "consumed/max".
#   retro.sh reset --state-dir DIR
#       — Zera o contador (orquestrador chama ao avancar para nova feature
#         OU explicitamente quando o operador desbloqueia retro adicional).
#
# Exit codes:
#   0 sucesso (ou retro disponivel)
#   1 erro generico
#   2 uso incorreto
#   3 limite de retro atingido
#
# POSIX sh + jq.

set -eu

_RT_NAME="retro"

_rt_die_usage() { printf '%s: %s\n' "$_RT_NAME" "$1" >&2; exit 2; }
_rt_die()       { printf '%s: %s\n' "$_RT_NAME" "$1" >&2; exit "${2:-1}"; }

_rt_require_jq() {
  command -v jq >/dev/null 2>&1 \
    || _rt_die "jq nao encontrado no PATH" 1
}

# Leitura de estado via interface canonica (state-db-runtime-parity FR-001):
# materializa documento legivel por jq nos DOIS backends (json/sqlite).
# Mutacoes (consume/reset) roteiam por `state-rw.sh set` sobre
# `.budgets.retro_executions_consumed` (coluna int em execution — research
# Decision 6, classe read-write). O guard pre-write do consume ("exit 3 SEM
# modificar estado") ja casa com o CHECK do schema SQLite
# (retro_executions_consumed <= max_retro_executions_per_feature).
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/_state-read.sh"
trap state_read_cleanup EXIT INT TERM

# _rt_set_consumed STATE_DIR N — grava .budgets.retro_executions_consumed
# nos dois backends via state-rw.sh set (falha propaga via set -e — FR-012).
_rt_set_consumed() {
  "$(_state_read_rw_bin)" set --state-dir "$1" \
    --field '.budgets.retro_executions_consumed' --value "$2"
}

_rt_get_state() {
  _sf=$(state_read_materialize "$1")
  [ -f "$_sf" ] || _rt_die "state.json ausente em $1" 1
  # Readers (schema-en-migration): chaves EN com fallback pt-BR (.en // .pt).
  # Fallback no container (budgets // orcamentos) E na folha para ler states
  # legados (back-compat). Ver migration-map.md §3.1, §3.7.
  _RT_CONSUMED=$(jq -r '
    ((.budgets // .orcamentos) // {})
    | .retro_executions_consumed // .retro_execucoes_consumidas // 0
  ' "$_sf")
  _RT_MAX=$(jq -r '
    ((.budgets // .orcamentos) // {})
    | .max_retro_executions_per_feature // .retro_execucoes_max_por_feature // 2
  ' "$_sf")
}

_rt_cmd_check() {
  _sd=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir) _sd=$2; shift 2 ;;
      *) _rt_die_usage "check: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sd" ] || _rt_die_usage "check: --state-dir obrigatorio"
  _rt_require_jq
  _rt_get_state "$_sd"
  if [ "$_RT_CONSUMED" -ge "$_RT_MAX" ]; then
    printf '%s: limite atingido (consumed=%s, max=%s)\n' \
      "$_RT_NAME" "$_RT_CONSUMED" "$_RT_MAX" >&2
    exit 3
  fi
  exit 0
}

_rt_cmd_consume() {
  _sd=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir) _sd=$2; shift 2 ;;
      *) _rt_die_usage "consume: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sd" ] || _rt_die_usage "consume: --state-dir obrigatorio"
  _rt_require_jq
  _rt_get_state "$_sd"
  _new=$((_RT_CONSUMED + 1))
  if [ "$_new" -gt "$_RT_MAX" ]; then
    printf '%s: consume negado — incremento %s -> %s excederia max %s\n' \
      "$_RT_NAME" "$_RT_CONSUMED" "$_new" "$_RT_MAX" >&2
    exit 3
  fi

  # Writer (schema-en-migration): chave EN via state-rw.sh set (canonicaliza
  # o doc no backend json; UPDATE de coluna no sqlite).
  _rt_set_consumed "$_sd" "$_new"
  printf '%s\n' "$_new"
}

_rt_cmd_count() {
  _sd=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir) _sd=$2; shift 2 ;;
      *) _rt_die_usage "count: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sd" ] || _rt_die_usage "count: --state-dir obrigatorio"
  _rt_require_jq
  _rt_get_state "$_sd"
  printf '%s/%s\n' "$_RT_CONSUMED" "$_RT_MAX"
}

_rt_cmd_reset() {
  _sd=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir) _sd=$2; shift 2 ;;
      *) _rt_die_usage "reset: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sd" ] || _rt_die_usage "reset: --state-dir obrigatorio"
  _rt_require_jq
  _sf=$(state_read_materialize "$_sd")
  [ -f "$_sf" ] || _rt_die "reset: state.json ausente" 1
  # Writer (schema-en-migration): chave EN via state-rw.sh set.
  _rt_set_consumed "$_sd" 0
}

# ---------- Dispatch ----------

if [ "$#" -lt 1 ]; then
  cat >&2 <<'HELP'
retro.sh — limite de retro-execucoes (FR-006).

USO:
  retro.sh check   --state-dir DIR
  retro.sh consume --state-dir DIR
  retro.sh count   --state-dir DIR
  retro.sh reset   --state-dir DIR

Limite default: 2 retros por feature. 3a tentativa = exit 3.
HELP
  exit 2
fi

_RT_SUBCMD=$1
shift

case "$_RT_SUBCMD" in
  check)           _rt_cmd_check "$@" ;;
  consume)         _rt_cmd_consume "$@" ;;
  count)           _rt_cmd_count "$@" ;;
  reset)           _rt_cmd_reset "$@" ;;
  -h|--help|help)  exit 0 ;;
  *) _rt_die_usage "subcomando desconhecido: $_RT_SUBCMD" ;;
esac
