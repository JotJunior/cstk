#!/bin/sh
# Metrics are best-effort. Never attribute a Codex call to a Claude/other feature.
set -eu
. "$(dirname -- "$0")/_common.sh"
if ! cx_hook_scope; then exit 0; fi
[ -n "$(cx_default "$CX_HOOK_INPUT" /tool_name '')" ] || exit 0
[ ! -L "$CX_HOOK_STATE/tool-call-ticks.log" ] || exit 0
printf '%s\n' "$(cx_now)" >> "$CX_HOOK_STATE/tool-call-ticks.log" 2>/dev/null || :
