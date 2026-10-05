#!/bin/sh
# Read-only app-server probes; never grant trust or start a model turn.
# Globals below are consumed by sourced entrypoints.
# shellcheck disable=SC2034
set -eu
_cn_root=$(CDPATH='' cd -P -- "$(dirname -- "$0")" && pwd -P)
while [ "$_cn_root" != / ] && [ ! -f "$_cn_root/cli/lib/codex-json.sh" ]; do _cn_root=$(dirname -- "$_cn_root"); done
. "$_cn_root/cli/lib/codex-json.sh"
. "$_cn_root/cli/lib/codex-common.sh"
CN_PROJECT='' CN_HOME=${CODEX_HOME:-$HOME/.codex} CN_ID=0 CN_PID='' CN_WATCH='' CN_NOTIFICATIONS='[]'
while [ "$#" -gt 0 ]; do
  [ "$#" -ge 2 ] || exit 2
  case "$1" in --project) CN_PROJECT=$2 ;; --codex-home) CN_HOME=$2 ;; *) exit 2 ;; esac
  shift 2
done
[ -n "$CN_PROJECT" ] || { cx_fail "explicit project required"; exit 2; }
CN_PROJECT=$(cx_path "$CN_PROJECT"); CN_HOME=$(cx_path "$CN_HOME")
[ -d "$CN_PROJECT" ] && [ -d "$CN_HOME" ] || { cx_fail 'probe requires an existing project and isolated Codex home'; exit 1; }
CN_TEMP=$(mktemp -d); chmod 700 "$CN_TEMP"
cn_cleanup() {
  if [ -n "$CN_WATCH" ]; then kill "$CN_WATCH" 2>/dev/null || :; wait "$CN_WATCH" 2>/dev/null || :; fi
  if [ -n "$CN_PID" ]; then kill "$CN_PID" 2>/dev/null || :; wait "$CN_PID" 2>/dev/null || :; fi
  exec 3>&- 4>&-
  rm -r -- "$CN_TEMP"
}
trap 'cn_cleanup' 0
trap 'exit 130' INT TERM
mkfifo "$CN_TEMP/in" "$CN_TEMP/out"
# Open both ends before spawning: no FIFO-open deadlock and no non-POSIX read -t.
exec 3<> "$CN_TEMP/in"
(cd -- "$CN_PROJECT" && exec env CODEX_HOME="$CN_HOME" codex app-server --stdio < "$CN_TEMP/in" > "$CN_TEMP/out" 2> "$CN_TEMP/stderr") & CN_PID=$!
exec 4< "$CN_TEMP/out"
cn_send() { printf '%s\n' "$1" >&3; }
cn_request() {
  CN_ID=$((CN_ID+1))
  cn_send "$(printf '{"id":%s,"method":%s,"params":%s}' "$CN_ID" "$(cj_quote "$1")" "$2")"
  (sleep 30; printf 'cstk codex: native request timed out\n' >&2; kill -TERM "$$") & CN_WATCH=$!
  while IFS= read -r _nr_line <&4; do
    _nr_doc=$(cj_value "$_nr_line") || return
    if [ "$(cx_default "$_nr_doc" /id null)" = "$CN_ID" ]; then
      kill "$CN_WATCH" 2>/dev/null || :; wait "$CN_WATCH" 2>/dev/null || :; CN_WATCH=''
      if cj_type "$_nr_doc" /error >/dev/null 2>&1; then cx_fail "native request rejected: $(cj_value "$_nr_doc" /error)"; return 1; fi
      CN_RESULT=$(cj_value "$_nr_doc" /result); return
    fi
    if cj_type "$_nr_doc" /id >/dev/null 2>&1 && cj_type "$_nr_doc" /method >/dev/null 2>&1; then
      cn_send "$(printf '{"id":%s,"error":{"code":-32000,"message":"Read-only probe cannot grant approval"}}' "$(cj_value "$_nr_doc" /id)")"
    fi
    CN_NOTIFICATIONS=$(cj_append "$CN_NOTIFICATIONS" '' "$_nr_doc")
  done
  cx_fail "native app-server closed before responding: $(cat "$CN_TEMP/stderr")"
}
cn_request initialize '{"clientInfo":{"name":"cstk-native-probe","version":"0.6.0"},"capabilities":{"experimentalApi":true}}'
cn_send '{"method":"initialized","params":{}}'
