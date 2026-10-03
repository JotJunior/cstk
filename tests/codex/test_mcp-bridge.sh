#!/bin/sh
. "$(dirname -- "$0")/lib/fixture.sh"
scenario_protocol_negotiation_errors_and_inventory() {
  t_select || return
  cat > "$TMPDIR_TEST/requests" <<'EOF'
invalid
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05"}}
{"jsonrpc":"2.0","method":"notifications/initialized"}
{"jsonrpc":"2.0","id":2,"method":"tools/list"}
{"jsonrpc":"2.0","id":3,"method":"unknown"}
{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"cstk_bootstrap","arguments":{}}}
EOF
  sh "$T_SCRIPTS/mcp-bridge.sh" < "$TMPDIR_TEST/requests" > "$TMPDIR_TEST/replies" || return
  _mb_list=$(sed -n '3p' "$TMPDIR_TEST/replies")
  [ "$(cj_length "$_mb_list" /result/tools)" = 15 ] && [ "$(cj_get "$(sed -n '1p' "$TMPDIR_TEST/replies")" /error/code)" = -32700 ] && [ "$(cj_get "$(sed -n '4p' "$TMPDIR_TEST/replies")" /error/code)" = -32601 ]
}
scenario_owned_wave_spans_mcp_calls_and_eof_closes_without_advance() {
  t_ready || return
  cat > "$TMPDIR_TEST/requests" <<EOF
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26"}}
{"jsonrpc":"2.0","method":"notifications/initialized"}
{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"cstk_select_execution","arguments":{"project":$(cj_quote "$T_PROJECT"),"short_name":"test-feature","kind":"feature"}}}
{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"cstk_open_wave","arguments":{}}}
{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"cstk_context","arguments":{}}}
{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"cstk_select_execution","arguments":{"short_name":"other","kind":"feature"}}}
EOF
  sh "$T_SCRIPTS/mcp-bridge.sh" < "$TMPDIR_TEST/requests" > "$TMPDIR_TEST/replies" || return
  [ "$(cx_default "$(sed -n '3p' "$TMPDIR_TEST/replies")" /result/isError false)" = false ] || { cat "$TMPDIR_TEST/replies"; return 1; }
  [ "$(cj_get "$(sed -n '5p' "$TMPDIR_TEST/replies")" /result/isError)" = true ] || return 1
  t_expect /current_stage specify && [ ! -d "$CX_STATE/.lock" ] && [ "$(cj_get "$(t_state)" /waves/-1/finished_at)" != null ]
}
run_all_scenarios
