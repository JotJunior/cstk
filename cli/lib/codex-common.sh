#!/bin/sh
# Shared POSIX boundary helpers; state operations remain in the canonical runtime.
# Globals below are consumed by sourced entrypoints.
# shellcheck disable=SC2034
set -eu

cx_fail() { CX_ERROR=$1; printf 'cstk codex: %s\n' "$1" >&2; return "${2:-1}"; }
cx_now() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }
cx_text_length() {
  _ctl_text=$(printf '%s\n' "$1" | awk '{s=s $0 "\n"} END {sub(/^[ \t\r\n]+/,"",s);sub(/[ \t\r\n]+$/,"",s);printf "%s",s}') || return
  cj_length "$(cj_quote "$_ctl_text")"
}
cx_timeout() {
  _ct_seconds=$1; shift
  "$@" < /dev/null & _ct_pid=$!
  (sleep "$_ct_seconds"; kill -TERM "$_ct_pid" 2>/dev/null || :) & _ct_watch=$!
  _ct_rc=0; wait "$_ct_pid" || _ct_rc=$?
  kill "$_ct_watch" 2>/dev/null || :; wait "$_ct_watch" 2>/dev/null || :
  return "$_ct_rc"
}
cx_quote_shell() { printf "'"; printf '%s' "$1" | sed "s/'/'\\\\''/g"; printf "'"; }
cx_discover() {
  _cd_root=$(CDPATH='' cd -P -- "$(dirname -- "$1")" && pwd -P) || return 1
  while [ "$_cd_root" != / ]; do
    if [ -f "$_cd_root/plugins/cstk/skills/agente-00c-runtime/scripts/pipeline.sh" ] && [ -f "$_cd_root/cli/VERSION" ]; then
      printf '%s\n' "$_cd_root"; return 0
    fi
    _cd_root=$(dirname -- "$_cd_root")
  done
  cx_fail 'cannot locate bundled CSTK runtime'
}
# Resolve directories physically; reject file symlinks and control bytes.
# Missing components are normalized lexically after the last existing parent.
cx_path() (
  _cp_raw=$1
  case "$_cp_raw" in /*) ;; *) _cp_raw=$(pwd -P)/$_cp_raw ;; esac
  case "$_cp_raw" in *"
"*|*"$(printf '\t')"*) cx_fail 'control bytes in path'; exit 1 ;; esac
  _cp_tail=${_cp_raw#/}; _cp_base=/
  while [ -n "$_cp_tail" ]; do
    case "$_cp_tail" in */*) _cp_part=${_cp_tail%%/*}; _cp_tail=${_cp_tail#*/} ;; *) _cp_part=$_cp_tail; _cp_tail= ;; esac
    case "$_cp_part" in ''|.) continue ;; ..) _cp_base=$(dirname -- "$_cp_base"); continue ;; esac
    _cp_next=${_cp_base%/}/$_cp_part
    if [ -d "$_cp_next" ]; then _cp_base=$(CDPATH='' cd -P -- "$_cp_next" && pwd -P) || exit 1
    elif [ -L "$_cp_next" ]; then cx_fail 'file symlink is not an authorized path'; exit 1
    else _cp_base=$_cp_next
    fi
  done
  printf '%s\n' "$_cp_base"
)
cx_within() { case "$2" in "$1"|"${1%/}/"*) return 0 ;; *) return 1 ;; esac; }
cx_sha() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum -- "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 -- "$1" | awk '{print $1}'
  else cx_fail 'SHA-256 utility unavailable'
  fi
}
cx_read() { [ ! -L "$1" ] && [ -f "$1" ] || { cx_fail 'missing or symlinked JSON file'; return 1; }; cj_value "$(cat -- "$1")"; }
cx_atomic() (
  [ ! -L "$1" ] || { cx_fail 'refusing symlinked destination'; exit 1; }
  _ca_tmp=$(mktemp "$(dirname -- "$1")/.cstk-json.XXXXXX") || exit 1
  trap 'rm -f -- "$_ca_tmp"' 0
  cj_value "$2" > "$_ca_tmp" || exit 1
  mv -- "$_ca_tmp" "$1"
)
cx_default() { cj_get "$1" "$2" 2>/dev/null || printf '%s' "$3"; }
cx_json_default() { cj_value "$1" "$2" 2>/dev/null || printf '%s' "$3"; }
cx_true() { [ "$1" = true ]; }
# Positive known PID only. Unknown liveness is never treated as death.
cx_dead() {
  case "$1" in ''|*[!0-9]*|0) return 1 ;; esac
  kill -0 "$1" 2>/dev/null && return 1
  _cd_pids=$(ps -e -o pid= 2>/dev/null) || return 1
  printf '%s\n' "$_cd_pids" | awk -v pid="$1" '$1==pid {found=1} END {exit found?1:0}'
}
# Binding is a project-wide owned wave, never an alphabetical execution search.
cx_binding() {
  _cb_project=$1
  _cb_dir=$_cb_project/.claude/.cstk-codex-wave-lock
  [ ! -L "$_cb_project/.claude" ] && [ ! -L "$_cb_dir" ] || return 2
  [ -d "$_cb_dir" ] || return 1
  _cb_doc=$(cx_read "$_cb_dir/owner.json") || return 2
  _cb_pid=$(cj_get "$_cb_doc" /pid) || return 2
  _cb_state=$(cj_get "$_cb_doc" /state_dir) || return 2
  _cb_wave=$(cj_get "$_cb_doc" /wave_id) || return 2
  case "$_cb_wave" in onda-[0-9]*) ;; *) return 2 ;; esac
  [ "$(cj_get "$_cb_doc" /project)" = "$_cb_project" ] || return 2
  case "$_cb_pid" in ''|*[!0-9]*|0) return 2 ;; esac
  kill -0 "$_cb_pid" 2>/dev/null || return 2
  cx_within "$_cb_project/.claude" "$_cb_state" || return 2
  [ "$(cx_path "$_cb_state")" = "$_cb_state" ] || return 2
  [ ! -L "$_cb_state" ] && [ ! -L "$_cb_state/.lock" ] && [ ! -L "$_cb_state/.lock/owner" ] || return 2
  _cb_recorded=$(sed -n 's/^pid=\([0-9][0-9]*\)$/\1/p' "$_cb_state/.lock/owner") || return 2
  [ "$_cb_recorded" = "$_cb_pid" ] || return 2
  printf '%s\n' "$_cb_state"
}
