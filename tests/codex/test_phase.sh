#!/bin/sh
. "$(dirname -- "$0")/lib/fixture.sh"
scenario_phase_resolves_shared_reference_read_only() { t_ready || return; _ph_before=$(t_state); assert_exit 0 sh "$T_SCRIPTS/phase.sh" --project "$T_PROJECT" --short-name test-feature || return; assert_stdout_contains 'specify/SKILL.md' || return; cj_equal "$_ph_before" "$(t_state)"; }
run_all_scenarios
