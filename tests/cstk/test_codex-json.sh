#!/bin/sh
TESTS_ROOT=${TESTS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}
REPO_ROOT=${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}
. "$TESTS_ROOT/lib/harness.sh"
. "$REPO_ROOT/cli/lib/codex-json.sh"
set +eu
scenario_unicode_surrogates_escaping_and_roundtrip() { _j='{"a":["á",true,null,"\uD83D\uDE00"],"x.y":"line\nquote\"slash\\"}'; [ "$(cj_get "$_j" /a/0)" = á ] && [ "$(cj_get "$_j" /a/-1)" = 😀 ] && [ "$(cj_length '[]')" = 0 ] && [ "$(cj_length '"á😀"')" = 2 ] && cj_equal "$_j" "$(cj_value "$_j")"; }
scenario_mutations_handle_keys_and_arrays() { _j=$(cj_set '{}' /a/b '["x"]'); _j=$(cj_append "$_j" /a/b '"y"'); [ "$(cj_get "$_j" /a/b/1)" = y ] && cj_equal '{"a":1,"b":2}' '{"b":2,"a":1}' && cj_equal "$(cj_delete "$_j" /a)" '{}'; }
scenario_invalid_json_is_rejected() { for _j in '{"x":1,"x":2}' '"\uD800"' '"\u0000"' '01' 'true false' '[1,]' '"\q"' '{"a":}'; do capture cj_value "$_j"; [ "$_CAPTURED_EXIT" != 0 ] || { _fail parser "accepted $_j"; return 1; }; done; }
scenario_input_is_never_evaluated() { _j=$(cj_quote '$(touch /tmp/cstk-should-never-exist) `id`'); [ "$(cj_get "$_j")" = '$(touch /tmp/cstk-should-never-exist) `id`' ]; }
scenario_raw_invalid_utf8_is_rejected() { capture cj_quote "$(printf '\300\257')"; [ "$_CAPTURED_EXIT" != 0 ]; }
scenario_quote_preserves_trailing_newlines() { _j=$(cj_quote "line

"); [ "$_j" = '"line\n\n"' ]; }
run_all_scenarios
