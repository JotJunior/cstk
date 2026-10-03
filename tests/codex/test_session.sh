#!/bin/sh
. "$(dirname -- "$0")/lib/fixture.sh"
scenario_bootstrap_resume_identity_and_release() { t_select || return; t_bootstrap || return; t_good status || return; t_expect /execution_provenance/runtime codex && [ ! -d "$CX_STATE/.lock" ]; }
scenario_existing_execution_is_never_overwritten() { t_select || return; t_bootstrap || return; _ss_before=$(t_state); t_bad bootstrap '{"description":"Another requested feature description","canonical_project":"canonical-project"}' || return; cj_equal "$_ss_before" "$(t_state)"; }
scenario_governance_changes_block_resume_without_mutation() { t_ready || return; _ss_before=$(t_state); printf 'drift\n' >> "$T_PROJECT/docs/constitution.md"; t_bad resume || return; cj_equal "$_ss_before" "$(t_state)"; }
scenario_foreign_lock_is_preserved() { t_ready || return; mkdir "$CX_STATE/.lock"; printf 'pid=%s\n' "$$" > "$CX_STATE/.lock/owner"; t_bad status || return; [ -f "$CX_STATE/.lock/owner" ]; }
scenario_control_symlinks_fail_closed() { t_ready || return; mv "$CX_STATE/state.json" "$TMPDIR_TEST/saved.json"; ln -s "$TMPDIR_TEST/saved.json" "$CX_STATE/state.json"; t_bad status || return; [ -L "$CX_STATE/state.json" ]; }
scenario_state_parent_escape_is_rejected() { t_select || return; mkdir -p "$T_PROJECT/.claude" "$TMPDIR_TEST/outside"; ln -s "$TMPDIR_TEST/outside" "$T_PROJECT/.claude/feature-00c-state"; t_bad bootstrap '{"description":"Create feature with escaped state parent","canonical_project":"canonical-project"}' || return; [ -z "$(ls -A "$TMPDIR_TEST/outside")" ]; }
scenario_sqlite_provenance_projection() { t_ready feature sqlite || return; [ -f "$CX_STATE/state.db" ] || return 1; t_good status || return; t_expect /execution_provenance/runtime codex; }
scenario_open_wave_refuses_session_resume() { t_ready || return; t_good open_wave || return; t_bad resume || return; [ -n "$CX_WAVE" ]; }
scenario_observed_model_is_recorded_only_when_provided() { t_select || return; t_good bootstrap '{"description":"Create observed model local feature","canonical_project":"canonical-project","model":"observed-host-model"}' || return; t_expect /execution_provenance/model observed-host-model; }
scenario_changed_lock_owner_cannot_be_mutated_or_released() {
  t_ready || return; t_good open_wave || return
  _ss_before=$(t_state)
  printf 'pid=99999999\n' > "$CX_STATE/.lock/owner"
  t_bad decision '{"context":"Actual context for audited execution decision.","options":["local"],"choice":"local","rationale":"Actual inspected source supports this operational choice."}' || return
  cj_equal "$_ss_before" "$(t_state)" && [ -f "$CX_STATE/.lock/owner" ]
}
run_all_scenarios
