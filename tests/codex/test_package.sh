#!/bin/sh
. "$(dirname -- "$0")/lib/fixture.sh"
scenario_self_contained_package_resolves_runtime_without_python() { t_select || return; assert_exit 0 sh "$REPO_ROOT/scripts/build-codex-plugin.sh" --out "$TMPDIR_TEST/package" || return; assert_exit 0 sh "$TMPDIR_TEST/package/skills/feature-00c/scripts/context.sh" --project "$T_PROJECT" --short-name test-feature || return; assert_stdout_contains "$TMPDIR_TEST/package/plugins/cstk"; }
scenario_output_inside_source_is_rejected_before_copy() { assert_exit 1 sh "$REPO_ROOT/scripts/build-codex-plugin.sh" --out "$REPO_ROOT/adapters/codex/rejected-output"; }
scenario_all_six_skills_have_gotchas_and_narrow_triggers() { for _pk_name in feature-00c feature-00c-resume feature-00c-abort agente-00c agente-00c-resume agente-00c-abort; do grep -F '## Gotchas' "$REPO_ROOT/adapters/codex/skills/$_pk_name/SKILL.md" >/dev/null || return 1; done; }
run_all_scenarios
