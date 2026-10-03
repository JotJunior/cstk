#!/bin/sh
. "$(dirname -- "$0")/lib/fixture.sh"
scenario_project_starts_before_governance_but_requires_three_optins() { t_select project || return; rm "$T_PROJECT/docs/briefing.md" "$T_PROJECT/docs/constitution.md"; t_bootstrap || return; t_bad open_wave || return; [ "$(cj_length "$CX_CONTEXT" /stages)" = 11 ]; }
scenario_full_project_json_pipeline() { t_ready project json bare || return; t_pipeline || return; [ "$(cj_length "$(t_state)" /waves)" = 11 ]; }
scenario_full_project_sqlite_pipeline() { t_ready project sqlite bare || return; t_pipeline || return; [ "$(cj_length "$(t_state)" /waves)" = 11 ]; }
scenario_roadmap_runs_three_canonical_phases() { t_ready project json bare true || return; t_good context || return; [ "$(cj_length "$CX_CONTEXT" /stages)" = 3 ] || return 1; t_pipeline; }
scenario_existing_constitution_requires_real_operator_block() { t_ready project || return; t_field .current_stage '"constitution"' || return; t_bad open_wave || return; [ "$(cj_length "$(t_state)" /human_blocks)" = 1 ] && [ ! -d "$CX_STATE/.lock" ]; }
run_all_scenarios
