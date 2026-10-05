#!/bin/sh
# Globals below are consumed by sourced entrypoints.
# shellcheck disable=SC2034
set -eu
_hc_root=$(CDPATH='' cd -P -- "$(dirname -- "$0")" && pwd -P)
while [ "$_hc_root" != / ] && [ ! -f "$_hc_root/cli/lib/codex-json.sh" ]; do _hc_root=$(dirname -- "$_hc_root"); done
[ -f "$_hc_root/cli/lib/codex-json.sh" ] || exit 1
. "$_hc_root/cli/lib/codex-json.sh"
. "$_hc_root/cli/lib/codex-common.sh"
CX_SOURCE=$_hc_root
CX_ENTRY_DIR=$CX_SOURCE/skills/feature-00c/scripts
[ -d "$CX_ENTRY_DIR" ] || CX_ENTRY_DIR=$CX_SOURCE/adapters/codex/skills/feature-00c/scripts
. "$CX_ENTRY_DIR/_tools.sh"
CX_TOOLS=$(cat "$CX_ENTRY_DIR/tools.json")
CX_HOOK_INPUT=$(cat)
cx_hook_deny() { printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' "$(cj_quote "$1")"; }
cx_hook_scope() {
  [ "$(cj_type "$CX_HOOK_INPUT")" = object ] && [ "$(cj_type "$CX_HOOK_INPUT" /cwd)" = string ] || return 2
  CX_HOOK_PROJECT=$(cx_path "$(cj_get "$CX_HOOK_INPUT" /cwd)") || return 2
  [ -d "$CX_HOOK_PROJECT" ] || return 2
  CX_HOOK_STATE=$(cx_binding "$CX_HOOK_PROJECT") || return $?
}
