#!/bin/sh
. "$(dirname -- "$0")/lib/fixture.sh"
native_fixture() {
  t_select || return
  mkdir -p "$TMPDIR_TEST/bin" "$TMPDIR_TEST/codex-home/cstk"
  export CSTK_TEST_ROOT="$REPO_ROOT"
  cat > "$TMPDIR_TEST/bin/codex" <<'EOF'
#!/bin/sh
set -eu
. "$CSTK_TEST_ROOT/cli/lib/codex-json.sh"
while IFS= read -r doc; do
  method=$(cj_get "$doc" /method 2>/dev/null || printf '')
  id=$(cj_get "$doc" /id 2>/dev/null || printf null)
  case "$method" in
    initialize) result='{}' ;;
    initialized) continue ;;
    thread/start) result='{"thread":{"id":"ephemeral-probe"}}' ;;
    mcpServerStatus/list) result='{"data":[{"name":"cstk_pipeline","runtimeStatus":"connected","pluginId":"cstk-codex-pilot@cstk-codex-pilot-local","tools":{}}]}' ;;
    hooks/list) result='{"data":[{"hooks":[{"pluginId":"cstk-codex-pilot@cstk-codex-pilot-local","eventName":"preToolUse","trustStatus":"untrusted","enabled":true},{"pluginId":"cstk-codex-pilot@cstk-codex-pilot-local","eventName":"postToolUse","trustStatus":"untrusted","enabled":true}],"errors":[],"warnings":[]}]}' ;;
    *) exit 2 ;;
  esac
  printf '{"id":%s,"result":%s}\n' "$id" "$result"
done
EOF
  chmod +x "$TMPDIR_TEST/bin/codex"; PATH=$TMPDIR_TEST/bin:$PATH; export PATH
}
scenario_native_protocol_fixture_never_runs_model_or_grants_trust() { native_fixture || return; assert_exit 0 sh "$T_SCRIPTS/native-mcp.sh" --project "$T_PROJECT" --codex-home "$TMPDIR_TEST/codex-home" || return; assert_stdout_contains '"model_turn_executed":false' || return; assert_exit 0 sh "$T_SCRIPTS/native-status.sh" --project "$T_PROJECT" --codex-home "$TMPDIR_TEST/codex-home" || return; assert_stdout_contains '"native_hooks_loaded":true' || return; assert_stdout_contains '"native_hooks_trusted":false'; }
scenario_optional_installed_native_mcp_connection() { if [ -z "${CSTK_NATIVE_TEST_HOME:-}" ]; then printf '# SKIP: isolated native installation not configured\n'; return 0; fi; t_select || return; assert_exit 0 sh "$T_SCRIPTS/native-mcp.sh" --project "$T_PROJECT" --codex-home "$CSTK_NATIVE_TEST_HOME"; }
run_all_scenarios
