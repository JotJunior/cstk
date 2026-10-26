#!/bin/sh
. "$(dirname -- "$0")/lib/fixture.sh"
t_start_child() {
  mkfifo "$TMPDIR_TEST/in" "$TMPDIR_TEST/out"
  exec 3<> "$TMPDIR_TEST/in"
  sh "$T_SCRIPTS/controller.sh" serve --project "$T_PROJECT" --short-name test-feature < "$TMPDIR_TEST/in" > "$TMPDIR_TEST/out" 2> "$TMPDIR_TEST/child-error" & T_CHILD=$!
  exec 4< "$TMPDIR_TEST/out"
  IFS= read -r _in_descriptor <&4 || { cat "$TMPDIR_TEST/child-error"; return 1; }
  [ "$(cj_get "$_in_descriptor" /controller_pid)" = "$T_CHILD" ]
}
t_pre_hook() { printf '{"cwd":%s,"tool_name":%s,"tool_input":%s}\n' "$(cj_quote "$T_PROJECT")" "$(cj_quote "$1")" "$2" | sh "$REPO_ROOT/adapters/codex/hooks/pretooluse.sh"; }
# Issue #224: a dead owner must not lock the recovery tools out of the hook.
scenario_sigkill_hook_keeps_recovery_tools_reachable() {
  t_ready || return; t_start_child || return
  kill -KILL "$T_CHILD"; wait "$T_CHILD" 2>/dev/null || :; exec 3>&- 4<&-
  _ir_pid=$(printf '{"abandoned_owner_pid":%s}' "$T_CHILD")
  capture t_pre_hook mcp__cstk_pipeline__cstk_recover "$_ir_pid"; assert_stdout_not_contains 'deny' || return
  capture t_pre_hook mcp__cstk_pipeline__cstk_abort "$_ir_pid"; assert_stdout_not_contains 'deny' || return
  capture t_pre_hook mcp__cstk_pipeline__cstk_status '{}'; assert_stdout_not_contains 'deny' || return
  capture t_pre_hook mcp__cstk_pipeline__cstk_select_execution "$(printf '{"project":%s,"short_name":"test-feature","kind":"feature"}' "$(cj_quote "$T_PROJECT")")"
  assert_stdout_not_contains 'deny' || return
  capture t_pre_hook mcp__cstk_pipeline__cstk_complete '{"evidence_paths":["docs/a.md"],"rationale":"Actual evidence checked before phase completion."}'
  assert_stdout_contains 'deny' || return
  capture t_pre_hook Bash '{"command":"git status"}'
  assert_stdout_contains 'deny' || return
  assert_stdout_contains "PID $T_CHILD is dead" || return
  assert_stdout_contains "recover --project" || return
  assert_stdout_contains "--abandoned-owner-pid $T_CHILD" || return
  t_good recover "$(printf '{"abandoned_owner_pid":%s}' "$T_CHILD")" || return
  capture t_pre_hook Bash '{"command":"git status"}'
  [ "$_CAPTURED_STDOUT" = '{}' ]
}
scenario_sigterm_closes_without_advance_and_releases_ownership() { t_ready || return; t_start_child || return; kill -TERM "$T_CHILD"; wait "$T_CHILD" 2>/dev/null || :; exec 3>&- 4<&-; t_expect /current_stage specify || return; [ ! -d "$CX_STATE/.lock" ] && [ ! -d "$T_PROJECT/.claude/.cstk-codex-wave-lock" ] && [ "$(cj_get "$(t_state)" /waves/-1/finished_at)" != null ]; }
scenario_sigkill_requires_matching_dead_pid_for_recovery() { t_ready || return; t_start_child || return; t_bad recover "$(printf '{"abandoned_owner_pid":%s}' "$T_CHILD")" || return; kill -KILL "$T_CHILD"; wait "$T_CHILD" 2>/dev/null || :; exec 3>&- 4<&-; t_bad recover || return; t_good recover "$(printf '{"abandoned_owner_pid":%s}' "$T_CHILD")" || return; t_good recover || return; [ ! -d "$CX_STATE/.lock" ] && [ ! -d "$T_PROJECT/.claude/.cstk-codex-wave-lock" ]; }
run_all_scenarios
