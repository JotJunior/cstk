#!/bin/sh
. "$(dirname -- "$0")/lib/fixture.sh"
scenario_read_only_canonical_feature_context() {
  t_select || return
  [ "$(cj_length "$CX_CONTEXT" /stages)" = 8 ] && [ "$(cj_get "$CX_CONTEXT" /prerequisites_ready)" = true ] && [ ! -f "$CX_STATE/state.json" ] && [ ! -f "$CX_STATE/state.db" ]
}
scenario_unknown_model_and_database_are_explicit() { t_select || return; [ "$(cj_get "$CX_CONTEXT" /model)" = null ] && [ "$(cj_get "$CX_CONTEXT" /knowledge_db)" = "$CSTK_KNOWLEDGE_DB" ]; }
scenario_legacy_briefing_and_missing_governance() {
  t_select || return; mkdir -p "$T_PROJECT/docs/01-briefing-discovery"; mv "$T_PROJECT/docs/briefing.md" "$T_PROJECT/docs/01-briefing-discovery/briefing.md"
  t_good context || return; [ "$(cj_get "$CX_RESULT" /prerequisites_ready)" = true ] || return 1
  rm "$T_PROJECT/docs/constitution.md"; t_good context || return; [ "$(cj_get "$CX_RESULT" /prerequisites_ready)" = false ]
}
scenario_invalid_name_target_and_database_refused() {
  t_select || return
  t_bad select_execution '{"short_name":"../escape","kind":"feature"}' || return
  t_bad select_execution '{"short_name":"other","kind":"invalid"}' || return
  t_bad select_execution "$(printf '{"project":%s,"short_name":"other","kind":"feature"}' "$(cj_quote "$TMPDIR_TEST")")"
}
scenario_builtin_context_cli_exit_and_source_anchor() {
  t_select || return
  assert_exit 0 sh "$T_SCRIPTS/context.sh" --project "$T_PROJECT" --short-name test-feature || return
  assert_stdout_contains '"source_root"' || return
  assert_exit 2 sh "$T_SCRIPTS/context.sh" --project "$T_PROJECT" --short-name test-feature --source-root /untrusted
}
scenario_missing_transactional_dependency_blocks_context_read_only() {
  t_select || return; mkdir "$TMPDIR_TEST/bin"
  for _cx_cmd in awk basename cat chmod date dirname find git grep head mkdir mktemp ps rm sed sh shasum sha256sum sort tail tr uname wc cp mv cut; do
    _cx_path=$(command -v "$_cx_cmd") || continue
    ln -s "$_cx_path" "$TMPDIR_TEST/bin/$_cx_cmd"
  done
  assert_exit 1 env PATH="$TMPDIR_TEST/bin" sh "$T_SCRIPTS/context.sh" --project "$T_PROJECT" --short-name test-feature || return
  assert_stdout_contains '"missing_prerequisites":["state_runtime"]' || return
  [ ! -f "$CX_STATE/state.json" ]
}
run_all_scenarios
