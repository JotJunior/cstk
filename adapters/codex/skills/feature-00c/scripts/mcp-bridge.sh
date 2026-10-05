#!/bin/sh
# Persistent synchronous JSON-RPC MCP. EOF/signals close an owned wave.
# Globals below are consumed by sourced entrypoints.
# shellcheck disable=SC2034
set -eu
. "$(dirname -- "$0")/_entry.sh"
_mcp_initialized=false _mcp_ready=false
[ "$#" = 0 ] || { cx_fail 'bind through cstk_select_execution; no implicit project' 2; exit 2; }
while IFS= read -r _mcp_line || [ -n "$_mcp_line" ]; do
  _mcp_error='' _mcp_result='' _mcp_id=null
  if ! _mcp_request=$(cj_value "$_mcp_line" 2>/dev/null); then
    printf '{"jsonrpc":"2.0","id":null,"error":{"code":-32700,"message":"Parse error"}}\n'; continue
  fi
  if [ "$(cj_type "$_mcp_request")" != object ] || [ "$(cx_default "$_mcp_request" /jsonrpc '')" != 2.0 ]; then
    printf '{"jsonrpc":"2.0","id":null,"error":{"code":-32600,"message":"Invalid Request"}}\n'; continue
  fi
  _mcp_method=$(cx_default "$_mcp_request" /method '')
  if ! _mcp_id=$(cj_value "$_mcp_request" /id 2>/dev/null); then
    if [ "$_mcp_method" = notifications/initialized ] && [ "$_mcp_initialized" = true ]; then _mcp_ready=true; fi
    continue
  fi
  _mcp_params=$(cx_json_default "$_mcp_request" /params '{}')
  if [ "$(cj_type "$_mcp_params")" != object ]; then _mcp_error='{"code":-32602,"message":"Invalid params"}'
  else
    case "$_mcp_method" in
      initialize)
        _mcp_initialized=true
        _mcp_version=$(cx_default "$_mcp_params" /protocolVersion 2025-06-18)
        case "$_mcp_version" in 2024-11-05|2025-03-26|2025-06-18) ;; *) _mcp_version=2025-06-18 ;; esac
        _mcp_result=$(printf '{"protocolVersion":%s,"capabilities":{"tools":{}},"serverInfo":{"name":"cstk-supervised","version":"0.6.0"}}' "$(cj_quote "$_mcp_version")") ;;
      ping) _mcp_result='{}' ;;
      *)
        if [ "$_mcp_ready" != true ]; then _mcp_error='{"code":-32600,"message":"Initialization required"}'
        else
          case "$_mcp_method" in
            tools/list) _mcp_result=$(printf '{"tools":%s}' "$CX_TOOLS") ;;
            tools/call)
              _mcp_name=$(cx_default "$_mcp_params" /name '')
              CX_ARGS=$(cx_json_default "$_mcp_params" /arguments '{}')
              CX_ERROR=; _mcp_failed=false
              case "$_mcp_name" in cstk_*) if ! cx_action "${_mcp_name#cstk_}"; then _mcp_failed=true; fi ;; *) CX_ERROR='unknown tool'; _mcp_failed=true ;; esac
              if [ "$_mcp_failed" = true ]; then _mcp_result=$(printf '{"isError":true,"content":[{"type":"text","text":%s}]}' "$(cj_quote "${CX_ERROR:-operation failed}")")
              else _mcp_result=$(printf '{"content":[{"type":"text","text":%s}]}' "$(cj_quote "$CX_RESULT")")
              fi ;;
            *) _mcp_error='{"code":-32601,"message":"Method not found"}' ;;
          esac
        fi ;;
    esac
  fi
  if [ -n "$_mcp_error" ]; then printf '{"jsonrpc":"2.0","id":%s,"error":%s}\n' "$_mcp_id" "$_mcp_error"
  else printf '{"jsonrpc":"2.0","id":%s,"result":%s}\n' "$_mcp_id" "$_mcp_result"
  fi
done
