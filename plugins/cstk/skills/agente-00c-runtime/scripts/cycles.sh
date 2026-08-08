#!/bin/sh
# cycles.sh — limite de ciclos por etapa (FR-014.a — loop em etapa).
#
# Ref: docs/specs/agente-00c/spec.md FR-014.a
#      docs/specs/agente-00c/tasks.md FASE 5.2
#
# Modelo: a cada nova iteracao na MESMA etapa o orquestrador chama
# `cycles.sh tick`. Quando a etapa muda, o contador reseta. Se houver
# "progresso mensuravel" (4 indicadores em FR-014), o tick e chamado com
# `--progress-made` e o contador e zerado. Sem progresso por mais de
# `max_cycles_per_stage` (default 5) ticks consecutivos = aborto
# `loop_em_etapa`.
#
# "Progresso mensuravel" (FR-014, decisao do orquestrador):
#   - novo artefato em docs/specs/<feature>/
#   - mudanca em artefato existente
#   - nova decisao com agente != "orquestrador-00c"
#   - mudanca de exit code de teste/lint
#
# Subcomandos:
#   cycles.sh tick --state-dir DIR [--progress-made]
#       — incrementa .budgets.cycles_consumed_current_stage.
#       — Se --progress-made: zera o contador (progresso = sem loop).
#       — Stdout: novo valor do contador.
#       — Exit 3 se contador resultante > max (orquestrador deve abortar).
#       — IMPORTANTE: orquestrador deve chamar `reset` ao avancar para
#         nova etapa (separadamente). Esta primitiva nao infere mudanca
#         de etapa — opera sobre contador unico.
#
#   cycles.sh check --state-dir DIR
#       — Exit 3 se cycles_consumed_current_stage > max_cycles_per_stage.
#       — Exit 0 caso contrario.
#
#   cycles.sh count --state-dir DIR
#       — Imprime contador corrente.
#
#   cycles.sh reset --state-dir DIR
#       — Zera o contador (orquestrador chama ao avancar para nova etapa).
#
# Exit codes:
#   0 sucesso
#   1 erro generico
#   2 uso incorreto
#   3 limite atingido (loop_em_etapa)
#
# POSIX sh + jq.

set -eu

_CY_NAME="cycles"

# Leitura de estado via interface canonica (state-db-runtime-parity FR-001):
# materializa documento legivel por jq nos DOIS backends (json/sqlite).
# Mutacoes (tick/reset) roteiam por `state-rw.sh set` (research Decision 6,
# classe read-write) — o set cuida de atomic write + sha (json) ou UPDATE
# na coluna cycles_consumed_current_stage (sqlite).
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/_state-read.sh"
trap state_read_cleanup EXIT INT TERM

_cy_die_usage() { printf '%s: %s\n' "$_CY_NAME" "$1" >&2; exit 2; }
_cy_die()       { printf '%s: %s\n' "$_CY_NAME" "$1" >&2; exit "${2:-1}"; }

_cy_require_jq() {
  command -v jq >/dev/null 2>&1 \
    || _cy_die "jq nao encontrado no PATH" 1
}

# _cy_set_counter STATE_DIR N — grava .budgets.cycles_consumed_current_stage
# nos dois backends via state-rw.sh set (falha propaga via set -e — FR-012).
_cy_set_counter() {
  "$(_state_read_rw_bin)" set --state-dir "$1" \
    --field '.budgets.cycles_consumed_current_stage' --value "$2"
}

_cy_cmd_tick() {
  _sd=""
  _prog=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir)     _sd=$2; shift 2 ;;
      --progress-made) _prog=1; shift ;;
      *) _cy_die_usage "tick: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sd" ] || _cy_die_usage "tick: --state-dir obrigatorio"
  _cy_require_jq
  # Falha de materializacao sob sqlite (sqlite3 ausente, state.db corrompido)
  # propaga exit+stderr do state-rw.sh read via set -e (FR-012).
  _sf=$(state_read_materialize "$_sd")
  [ -f "$_sf" ] || _cy_die "tick: state.json ausente em $_sd" 1

  _curr_count=$(jq -r '((.budgets.cycles_consumed_current_stage // .orcamentos.ciclos_consumidos_etapa_corrente) // 0)' "$_sf")
  _max=$(jq -r '((.budgets.max_cycles_per_stage // .orcamentos.ciclos_max_por_etapa) // 5)' "$_sf")

  if [ "$_prog" = 1 ]; then
    _new=0
  else
    _new=$((_curr_count + 1))
  fi

  if [ "$_new" -gt "$_max" ]; then
    # Estouro NAO e persistido: o schema SQLite tem CHECK
    # (cycles_consumed_current_stage <= max_cycles_per_stage) que rejeita o
    # valor com "estado intacto" (contrato runtime-interfaces §1); paridade
    # exige o mesmo modelo no backend JSON. O veredito de aborto e o exit 3
    # — ticks subsequentes re-disparam ate o orquestrador abortar.
    printf '%s\n' "$_new"
    printf '%s: loop_em_etapa — %s ciclos consecutivos sem progresso (max %s)\n' \
      "$_CY_NAME" "$_new" "$_max" >&2
    exit 3
  fi

  _cy_set_counter "$_sd" "$_new"
  printf '%s\n' "$_new"
}

_cy_cmd_check() {
  _sd=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir) _sd=$2; shift 2 ;;
      *) _cy_die_usage "check: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sd" ] || _cy_die_usage "check: --state-dir obrigatorio"
  _cy_require_jq
  _sf=$(state_read_materialize "$_sd")
  [ -f "$_sf" ] || _cy_die "check: state.json ausente" 1
  _curr=$(jq -r '((.budgets.cycles_consumed_current_stage // .orcamentos.ciclos_consumidos_etapa_corrente) // 0)' "$_sf")
  _max=$(jq -r '((.budgets.max_cycles_per_stage // .orcamentos.ciclos_max_por_etapa) // 5)' "$_sf")
  if [ "$_curr" -gt "$_max" ]; then
    printf '%s: loop_em_etapa (%s > %s)\n' "$_CY_NAME" "$_curr" "$_max" >&2
    exit 3
  fi
  exit 0
}

_cy_cmd_count() {
  _sd=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir) _sd=$2; shift 2 ;;
      *) _cy_die_usage "count: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sd" ] || _cy_die_usage "count: --state-dir obrigatorio"
  _cy_require_jq
  _sf=$(state_read_materialize "$_sd")
  [ -f "$_sf" ] || _cy_die "count: state.json ausente" 1
  jq -r '((.budgets.cycles_consumed_current_stage // .orcamentos.ciclos_consumidos_etapa_corrente) // 0)' "$_sf"
}

_cy_cmd_reset() {
  _sd=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir) _sd=$2; shift 2 ;;
      *) _cy_die_usage "reset: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sd" ] || _cy_die_usage "reset: --state-dir obrigatorio"
  _cy_require_jq
  _sf=$(state_read_materialize "$_sd")
  [ -f "$_sf" ] || _cy_die "reset: state.json ausente" 1
  _cy_set_counter "$_sd" 0
}

# ---------- Dispatch ----------

if [ "$#" -lt 1 ]; then
  cat >&2 <<'HELP'
cycles.sh — limite de ciclos por etapa (FR-014.a).

USO:
  cycles.sh tick  --state-dir DIR [--progress-made]
  cycles.sh check --state-dir DIR
  cycles.sh count --state-dir DIR
  cycles.sh reset --state-dir DIR

NOTA: chame `reset` ao avancar para nova etapa. `tick` opera sobre
contador unico — nao infere mudanca de etapa.

EXIT:
  0 sucesso
  1 erro generico
  2 uso incorreto
  3 loop_em_etapa (orquestrador deve abortar)
HELP
  exit 2
fi

_CY_SUBCMD=$1
shift

case "$_CY_SUBCMD" in
  tick)            _cy_cmd_tick "$@" ;;
  check)           _cy_cmd_check "$@" ;;
  count)           _cy_cmd_count "$@" ;;
  reset)           _cy_cmd_reset "$@" ;;
  -h|--help|help)  exit 0 ;;
  *) _cy_die_usage "subcomando desconhecido: $_CY_SUBCMD" ;;
esac
