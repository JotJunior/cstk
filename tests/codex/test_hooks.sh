#!/bin/sh
. "$(dirname -- "$0")/lib/fixture.sh"
t_hook() {
  _th_payload=$(printf '{"cwd":%s,"tool_name":%s,"tool_input":%s}' "$(cj_quote "$T_PROJECT")" "$(cj_quote "$2")" "$3")
  printf '%s\n' "$_th_payload" | sh "$REPO_ROOT/adapters/codex/hooks/$1.sh"
}
scenario_inactive_project_and_claude_are_unaffected() { t_ready || return; capture t_hook pretooluse unknown '{}'; [ "$_CAPTURED_STDOUT" = '{}' ]; }
scenario_shared_bash_policy_and_patch_scope() { t_ready || return; t_good open_wave || return; capture t_hook pretooluse Bash '{"command":"git status"}'; assert_stdout_not_contains 'deny' || return; capture t_hook pretooluse Bash '{"command":"rm -rf /"}'; assert_stdout_contains 'deny' || return; capture t_hook pretooluse apply_patch '{"command":"*** Begin Patch\n*** Add File: ../escape\n+evil\n*** End Patch"}'; assert_stdout_contains 'deny'; }
scenario_patch_controls_and_unknown_wrappers_denied() { t_ready || return; t_good open_wave || return; capture t_hook pretooluse apply_patch '{"command":"*** Begin Patch\n*** Add File: .claude/control\n+evil\n*** End Patch"}'; assert_stdout_contains 'deny' || return; capture t_hook pretooluse exec_command '{"cmd":"git status"}'; assert_stdout_contains 'deny'; }
scenario_malformed_envelope_fails_closed() { t_select || return; capture sh -c 'printf "malformed\n" | sh "$1"' sh "$REPO_ROOT/adapters/codex/hooks/pretooluse.sh"; assert_stdout_contains 'deny'; }
scenario_mcp_schema_target_and_identity_are_checked() { t_ready || return; t_good open_wave || return; capture t_hook pretooluse mcp__cstk_pipeline__cstk_complete '{"evidence_paths":["docs/a.md"],"rationale":"Actual evidence checked before phase completion."}'; assert_stdout_not_contains 'deny' || return; capture t_hook pretooluse mcp__cstk_pipeline__cstk_unknown '{}'; assert_stdout_contains 'deny' || return; capture t_hook pretooluse mcp__cstk_pipeline__cstk_select_execution '{"project":"/tmp","short_name":"other","kind":"feature"}'; assert_stdout_contains 'deny'; }
scenario_ticks_target_owned_codex_with_alphabetical_claude_active() {
  t_ready || return
  T_CLAUDE=$T_PROJECT/.claude/feature-00c-state/a-claude
  sh "$T_RUNTIME/state-rw.sh" init --state-dir "$T_CLAUDE" --execucao-id a-claude --projeto-alvo-path "$T_PROJECT" --descricao 'Unrelated Claude execution' --runtime claude-code >/dev/null || return
  t_good open_wave || return
  t_hook posttooluse Bash '{"command":"git status"}' >/dev/null || return
  [ "$(wc -l < "$CX_STATE/tool-call-ticks.log" | tr -d ' ')" = 1 ] && [ ! -f "$T_CLAUDE/tool-call-ticks.log" ] || return 1
  # Default Claude discovery is preserved; explicit native override selects owner.
  capture env CSTK_CODEX_HOOK_STATE_DIR="$CX_STATE" sh -c '. "$1"; hook_active_exec "$2"' sh "$T_RUNTIME/_hook-active-exec.sh" "$T_PROJECT"
  assert_stdout_contains "$CX_STATE"
}
scenario_second_codex_wave_in_project_is_refused() {
  t_ready || return; t_good open_wave || return
  assert_exit 1 sh "$T_SCRIPTS/controller.sh" serve --project "$T_PROJECT" --short-name test-feature || return
  [ "$(cj_get "$(cx_read "$T_PROJECT/.claude/.cstk-codex-wave-lock/owner.json")" /pid)" = "$$" ]
}
scenario_foreign_or_dead_binding_never_receives_ticks() { t_ready || return; t_good open_wave || return; cx_atomic "$T_PROJECT/.claude/.cstk-codex-wave-lock/owner.json" "$(cj_set "$(cx_read "$T_PROJECT/.claude/.cstk-codex-wave-lock/owner.json")" /pid 99999999)"; t_hook posttooluse Bash '{}' >/dev/null; [ ! -f "$CX_STATE/tool-call-ticks.log" ]; }
run_all_scenarios
