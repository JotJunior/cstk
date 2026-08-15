#!/bin/sh
# roadmap-mode.sh — helper POSIX para o modo opt-in roadmap-mode.
#
# Feature: roadmap-mode
# Ref:     docs/specs/roadmap-mode/contracts/cli-roadmap-mode.md §2
#          docs/specs/roadmap-mode/plan.md Fase A passo 2
#
# Espelha commit-mode.sh is-enabled/set-enabled (mesmo contrato de
# exit-0-sempre em is-enabled, mesma leitura defensiva via state-rw.sh get).
#
# Subcomandos:
#   is-enabled  --state-dir DIR
#               stdout: "true" ou "false", exit 0 SEMPRE (campo
#               ausente/estado ilegivel/valor nao-booleano => "false").
#   set-enabled --state-dir DIR --value <true|false>
#               Grava .roadmap_mode_enabled. O flag e WRITE-ONCE (MUST):
#               recusa (exit 2, sem escrever) quando ja existe onda com
#               etapa executada posterior a `constitution` (specify,
#               clarify, plan, ... ja rodaram) — ligar o modo no meio de
#               uma execucao truncaria a pipeline restante e a execucao
#               se autodeclararia concluida cedo demais. Trocar de modo
#               apos iniciada a execucao e decisao do operador via
#               abort + reabertura, nao mutacao em voo.
#
# Exit codes (set-enabled):
#   0  gravado
#   1  falha de escrita no estado / state-rw.sh ausente
#   2  uso incorreto (valor fora de true|false) OU trava write-once
#      (onda ja passou de constitution)
#
# POSIX sh puro. Depende de state-rw.sh (mesmo diretorio) + jq (via
# state-rw.sh).

set -eu

_RM_NAME="roadmap-mode"

# ---------- helpers de log ----------

_rm_selfdir() { cd -- "$(dirname -- "$0")" && pwd; }
_rm_log_sourced=0
if _rm_sd=$(_rm_selfdir 2>/dev/null) && [ -f "$_rm_sd/_log.sh" ]; then
  # shellcheck disable=SC1090
  . "$_rm_sd/_log.sh" && _rm_log_sourced=1
fi

_rm_err() {
  if [ "$_rm_log_sourced" = 1 ]; then
    log_err "$_RM_NAME: $*"
  else
    printf '%s: %s\n' "$_RM_NAME" "$*" >&2
  fi
}

_rm_die() {
  _rm_err "$1"
  exit "${2:-1}"
}

_rm_die_usage() {
  _rm_err "$1"
  exit 2
}

# Localiza state-rw.sh no mesmo diretorio que este script.
_rm_rw() {
  _rm_d=$(_rm_selfdir 2>/dev/null) || _rm_die "nao foi possivel resolver selfdir" 1
  printf '%s/state-rw.sh' "$_rm_d"
}

# ---------- subcomando: is-enabled ----------
_rm_cmd_is_enabled() {
  _sdir=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir) _sdir=$2; shift 2 ;;
      *) _rm_die_usage "is-enabled: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sdir" ] || _rm_die_usage "is-enabled: --state-dir obrigatorio"

  _rw=$(_rm_rw)
  if [ ! -f "$_rw" ]; then
    printf 'false\n'
    return 0
  fi

  # Defensivo (contrato exit-0-sempre): estado ausente/ilegivel/campo
  # ausente/valor nao-booleano => "false". Nunca propaga erro do state-rw.
  _val=$(sh "$_rw" get --state-dir "$_sdir" \
    --field '.roadmap_mode_enabled // false' 2>/dev/null) || _val="false"

  case "$_val" in
    true)  printf 'true\n'  ;;
    *)     printf 'false\n' ;;  # inclui "false" e qualquer valor defensivo
  esac
  return 0
}

# ---------- subcomando: set-enabled ----------
#
# Trava write-once: recusa mudar o modo quando ja existe onda que
# executou etapa posterior a `constitution` (specify/clarify/plan/...).
# Consulta `.waves[].executed_stages` (uniao) via state-rw.sh get — mesmo
# caminho de leitura usado pelo resto do runtime, funciona identico sob
# os dois backends (JSON/SQLite) porque `state-rw.sh get` reconstroi o
# documento completo em ambos.
_rm_write_once_blocked() {
  _wob_sdir="$1"
  _wob_rw=$(_rm_rw)
  _wob_stages=$(sh "$_wob_rw" get --state-dir "$_wob_sdir" \
    --field '[(.waves // [])[].executed_stages[]?] | unique' 2>/dev/null) || _wob_stages="[]"
  _wob_blocked=$(printf '%s' "$_wob_stages" | jq -r \
    '(map(select(. != "briefing" and . != "constitution")) | length) > 0' 2>/dev/null) \
    || _wob_blocked="false"
  [ "$_wob_blocked" = "true" ]
}

_rm_cmd_set_enabled() {
  _sdir=""
  _value=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir) _sdir=$2;  shift 2 ;;
      --value)     _value=$2; shift 2 ;;
      *) _rm_die_usage "set-enabled: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sdir" ]  || _rm_die_usage "set-enabled: --state-dir obrigatorio"
  [ -n "$_value" ] || _rm_die_usage "set-enabled: --value obrigatorio"

  case "$_value" in
    true|false) ;;
    *) _rm_die_usage "set-enabled: --value aceita apenas 'true' ou 'false'" ;;
  esac

  _rw=$(_rm_rw)
  [ -f "$_rw" ] || _rm_die "state-rw.sh nao encontrado: $_rw" 1
  command -v jq >/dev/null 2>&1 || _rm_die "jq nao encontrado no PATH" 1

  if _rm_write_once_blocked "$_sdir"; then
    _rm_die "set-enabled: modo roadmap e write-once — ja existe onda com etapa executada posterior a 'constitution'. Trocar de modo requer abortar e reabrir a execucao, nao mutacao em voo." 2
  fi

  sh "$_rw" set --state-dir "$_sdir" \
    --field '.roadmap_mode_enabled' \
    --value "$_value" || _rm_die "set-enabled: falha ao gravar state" 1

  return 0
}

# ---------- dispatch ----------

[ "$#" -gt 0 ] || _rm_die_usage "subcomando obrigatorio: is-enabled|set-enabled"

_RM_CMD=$1
shift

case "$_RM_CMD" in
  is-enabled)  _rm_cmd_is_enabled  "$@" ;;
  set-enabled) _rm_cmd_set_enabled "$@" ;;
  -h|--help|help)
    printf 'roadmap-mode.sh is-enabled --state-dir DIR\nroadmap-mode.sh set-enabled --state-dir DIR --value <true|false>\n'
    exit 0
    ;;
  *)
    _rm_die_usage "subcomando desconhecido: $_RM_CMD (validos: is-enabled|set-enabled)"
    ;;
esac
