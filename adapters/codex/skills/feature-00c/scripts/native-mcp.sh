#!/bin/sh
set -eu
. "$(dirname -- "$0")/_native.sh"
cn_request thread/start "$(printf '{"cwd":%s,"ephemeral":true,"sandbox":"workspace-write","approvalPolicy":"on-request"}' "$(cj_quote "$CN_PROJECT")")"
_cn_thread=$(cj_value "$CN_RESULT" /thread/id)
cn_request mcpServerStatus/list "$(printf '{"threadId":%s}' "$_cn_thread")"
_cn_inventory=$CN_RESULT; _cn_connected=false; _cn_list=$(cj_each "$CN_RESULT" /data)
while IFS= read -r _cn_server; do
  [ -n "$_cn_server" ] || continue
  if [ "$(cx_default "$_cn_server" /name '')" = cstk_pipeline ] && [ "$(cx_default "$_cn_server" /runtimeStatus '')" = connected ] && [ "$(cx_default "$_cn_server" /pluginId '')" = cstk-codex-pilot@cstk-codex-pilot-local ]; then _cn_connected=true; fi
done <<EOF
$_cn_list
EOF
printf '{"project":%s,"inventory":%s,"native_mcp_connected":%s,"notifications":%s,"model_turn_executed":false,"autonomous_ready":false}\n' "$(cj_quote "$CN_PROJECT")" "$_cn_inventory" "$_cn_connected" "$CN_NOTIFICATIONS"
[ "$_cn_connected" = true ]
