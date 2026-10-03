#!/bin/sh
. "$(dirname -- "$0")/lib/fixture.sh"
scenario_first_wave_requires_actual_optin() { t_select || return; t_bootstrap || return; t_bad open_wave || return; [ ! -d "$CX_STATE/.lock" ] && [ ! -d "$T_PROJECT/.claude/.cstk-codex-wave-lock" ]; }
scenario_false_is_idempotent_and_cannot_be_replaced() { t_ready || return; _oi_before=$(t_state); t_good optin '{"value":false,"channel":"prose","response_source":"Actual operator fixture response"}' || return; cj_equal "$_oi_before" "$(t_state)" || return; t_bad optin '{"value":true,"channel":"prose","response_source":"Another operator fixture response"}'; }
scenario_short_source_and_wrong_field_are_refused() { t_select || return; t_bootstrap || return; t_bad optin '{"value":false,"channel":"prose","response_source":"guess"}' || return; t_bad optin '{"value":false,"field":"roadmap_mode","channel":"prose","response_source":"Actual operator fixture response"}'; }
scenario_unknown_schema_argument_is_refused() { t_select || return; t_bad bootstrap '{"description":"Create a local test feature","canonical_project":"canonical-project","shell":"touch /tmp/injection"}'; }
run_all_scenarios
