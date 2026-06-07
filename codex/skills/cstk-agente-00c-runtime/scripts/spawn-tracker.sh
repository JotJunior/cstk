#!/bin/sh
# spawn-tracker.sh — tracking de profundidade de subagentes (FR-013).
#
# Ref: docs/specs/agente-00c/spec.md FR-013
#      docs/specs/agente-00c/research.md Decision 7
#      docs/specs/agente-00c/tasks.md FASE 3.3
#
# Defesa em profundidade contra recursividade descontrolada:
#   1. (este script) Validacao runtime de profundidade <= 3 ANTES de spawn.
#   2. (definicao do agente bisneto) Tool Agent NAO declarada — impossibilita
#      o 3o nivel de spawnar um 4o.
#
# Subcomandos:
#   spawn-tracker.sh check --state-dir DIR
#       — Exit 0 se current_subagent_depth < 3 (pode spawnar +1).
#       — Exit 3 se >= 3 (limite atingido). NAO modifica estado.
#
#   spawn-tracker.sh enter --state-dir DIR
#       — Valida (current+1 <= 3); se OK incrementa current_subagent_depth,
#         atualiza max_depth_reached e subagents_spawned.
#       — Falha = exit 3 SEM modificar estado.
#
#   spawn-tracker.sh leave --state-dir DIR
#       — Decrementa current_subagent_depth (min 1, igual ao
#         orquestrador raiz). Idempotente (decremento abaixo de 1 = no-op).
#
#   spawn-tracker.sh current --state-dir DIR
#       — Imprime current_subagent_depth em stdout.
#
# Exit codes:
#   0 sucesso (ou profundidade ok p/ spawn)
#   1 erro generico
#   2 uso incorreto
#   3 limite de profundidade atingido (MAX 3)
#
# POSIX sh + jq.

set -eu

_ST_NAME="spawn-tracker"
_ST_MAX=3   # FR-013: max 3 niveis (filho, neto, bisneto)

_st_die_usage() {
  printf '%s: %s\n' "$_ST_NAME" "$1" >&2
  exit 2
}

_st_die() {
  printf '%s: %s\n' "$_ST_NAME" "$1" >&2
  exit "${2:-1}"
}

_st_require_jq() {
  command -v jq >/dev/null 2>&1 \
    || _st_die "jq nao encontrado no PATH (brew install jq | apt install jq)" 1
}

_st_state_file() { printf '%s/state.json\n' "$1"; }

_st_atomic_write() {
  _dst=$1
  _src=$2
  _tmp=$(mktemp -- "${_dst}.XXXXXX") || _st_die "mktemp falhou" 1
  cp -- "$_src" "$_tmp" || { rm -f -- "$_tmp"; _st_die "I/O cp" 1; }
  mv -f -- "$_tmp" "$_dst" || { rm -f -- "$_tmp"; _st_die "mv" 1; }
}

_st_update_sha() {
  _sf=$(_st_state_file "$1")
  _shf="$1/state.json.sha256"
  if command -v sha256sum >/dev/null 2>&1; then
    _h=$(sha256sum -- "$_sf" | awk '{print $1}')
  else
    _h=$(shasum -a 256 -- "$_sf" | awk '{print $1}')
  fi
  printf '%s\n' "$_h" > "$_shf"
}

_st_backup_current() {
  _sf=$(_st_state_file "$1")
  [ -f "$_sf" ] || return 0
  _hd="$1/state-history"
  mkdir -p -- "$_hd" 2>/dev/null || _st_die "mkdir state-history falhou" 1
  _curr=$(jq -r '
    ((.waves // .ondas) // []) as $w
    | if ($w | length) > 0 then ($w[-1].id // "init") else "init" end
  ' "$_sf" 2>/dev/null) || _curr="init"
  _ts=$(date -u +%Y%m%dT%H%M%SZ)
  _bk="$_hd/${_curr}-${_ts}.json"
  mv -- "$_sf" "$_bk" || _st_die "backup falhou" 1
}

_st_get_current() {
  _sf=$(_st_state_file "$1")
  jq -r '((.budgets.current_subagent_depth // .orcamentos.profundidade_corrente_subagentes)) // 1' "$_sf" 2>/dev/null
}

_st_cmd_check() {
  _sdir=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir) _sdir=$2; shift 2 ;;
      *) _st_die_usage "check: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sdir" ] || _st_die_usage "check: --state-dir obrigatorio"
  _st_require_jq
  _sf=$(_st_state_file "$_sdir")
  [ -f "$_sf" ] || _st_die "check: state.json ausente em $_sdir" 1
  _curr=$(_st_get_current "$_sdir")
  _next=$((_curr + 1))
  if [ "$_next" -gt "$_ST_MAX" ]; then
    printf '%s: profundidade no limite (corrente=%s, MAX=%s) — spawn negado\n' \
      "$_ST_NAME" "$_curr" "$_ST_MAX" >&2
    exit 3
  fi
  exit 0
}

_st_cmd_enter() {
  _sdir=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir) _sdir=$2; shift 2 ;;
      *) _st_die_usage "enter: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sdir" ] || _st_die_usage "enter: --state-dir obrigatorio"
  _st_require_jq
  _sf=$(_st_state_file "$_sdir")
  [ -f "$_sf" ] || _st_die "enter: state.json ausente em $_sdir" 1

  _curr=$(_st_get_current "$_sdir")
  _next=$((_curr + 1))
  # Validacao ANTES de qualquer escrita (FR-013, defesa em profundidade)
  if [ "$_next" -gt "$_ST_MAX" ]; then
    printf '%s: enter negado — profundidade %s -> %s excederia MAX %s\n' \
      "$_ST_NAME" "$_curr" "$_next" "$_ST_MAX" >&2
    exit 3
  fi

  # Aplicacao. Writer (schema-en-migration): chaves EN, sem fallback.
  # Confia em EN-on-disk (migrate defensivo do command-pai no inicio da onda).
  _new_state=$(mktemp) || _st_die "mktemp falhou" 1
  jq --argjson n "$_next" '
    .budgets.current_subagent_depth = $n
    | .accumulated_metrics.max_depth_reached =
        (if ($n > (.accumulated_metrics.max_depth_reached // 0))
         then $n else .accumulated_metrics.max_depth_reached end)
    | .accumulated_metrics.subagents_spawned =
        ((.accumulated_metrics.subagents_spawned // 0) + 1)
  ' "$_sf" > "$_new_state" || { rm -f -- "$_new_state"; _st_die "jq update falhou" 1; }

  _st_backup_current "$_sdir"
  _st_atomic_write "$_sf" "$_new_state"
  rm -f -- "$_new_state" 2>/dev/null || :
  _st_update_sha "$_sdir"
  printf '%s\n' "$_next"  # stdout: nova profundidade
}

_st_cmd_leave() {
  _sdir=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir) _sdir=$2; shift 2 ;;
      *) _st_die_usage "leave: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sdir" ] || _st_die_usage "leave: --state-dir obrigatorio"
  _st_require_jq
  _sf=$(_st_state_file "$_sdir")
  [ -f "$_sf" ] || _st_die "leave: state.json ausente em $_sdir" 1

  _curr=$(_st_get_current "$_sdir")
  if [ "$_curr" -le 1 ]; then
    # Idempotente: orquestrador raiz tem profundidade 1; nao baixa abaixo.
    printf '%s\n' "$_curr"
    exit 0
  fi
  _next=$((_curr - 1))

  # Writer (schema-en-migration): chave EN, sem fallback (EN-on-disk).
  _new_state=$(mktemp) || _st_die "mktemp falhou" 1
  jq --argjson n "$_next" '.budgets.current_subagent_depth = $n' \
    "$_sf" > "$_new_state" || { rm -f -- "$_new_state"; _st_die "jq update falhou" 1; }

  _st_backup_current "$_sdir"
  _st_atomic_write "$_sf" "$_new_state"
  rm -f -- "$_new_state" 2>/dev/null || :
  _st_update_sha "$_sdir"
  printf '%s\n' "$_next"
}

_st_cmd_current() {
  _sdir=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir) _sdir=$2; shift 2 ;;
      *) _st_die_usage "current: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sdir" ] || _st_die_usage "current: --state-dir obrigatorio"
  _st_require_jq
  _sf=$(_st_state_file "$_sdir")
  [ -f "$_sf" ] || _st_die "current: state.json ausente em $_sdir" 1
  _st_get_current "$_sdir"
}

# ---------- Dispatch ----------

if [ "$#" -lt 1 ]; then
  cat >&2 <<'HELP'
spawn-tracker.sh — tracker de profundidade de subagentes (FR-013).

USO:
  spawn-tracker.sh check  --state-dir DIR
  spawn-tracker.sh enter  --state-dir DIR
  spawn-tracker.sh leave  --state-dir DIR
  spawn-tracker.sh current --state-dir DIR

EXIT:
  0 sucesso
  1 erro generico
  2 uso incorreto
  3 limite atingido (MAX 3)
HELP
  exit 2
fi

_ST_SUBCMD=$1
shift

case "$_ST_SUBCMD" in
  check)           _st_cmd_check "$@" ;;
  enter)           _st_cmd_enter "$@" ;;
  leave)           _st_cmd_leave "$@" ;;
  current)         _st_cmd_current "$@" ;;
  -h|--help|help)  exit 0 ;;
  *) _st_die_usage "subcomando desconhecido: $_ST_SUBCMD" ;;
esac
