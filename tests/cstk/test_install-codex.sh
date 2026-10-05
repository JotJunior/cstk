#!/bin/sh
TESTS_ROOT=${TESTS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}
REPO_ROOT=${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}
. "$TESTS_ROOT/lib/harness.sh"
. "$REPO_ROOT/cli/lib/codex-json.sh"
set +eu
ic_fixture() {
  HOME=$TMPDIR_TEST/home CODEX_HOME=$TMPDIR_TEST/home/.codex CSTK_TEST_ROOT=$REPO_ROOT
  export HOME CODEX_HOME CSTK_TEST_ROOT
  mkdir -p "$CODEX_HOME" "$TMPDIR_TEST/bin"
  cp "$TESTS_ROOT/codex/lib/fake-codex.sh" "$TMPDIR_TEST/bin/codex"; chmod +x "$TMPDIR_TEST/bin/codex"
  printf '#!/bin/sh\nexit 99\n' > "$TMPDIR_TEST/bin/python3"; chmod +x "$TMPDIR_TEST/bin/python3"
  PATH=$TMPDIR_TEST/bin:$PATH; export PATH
  unset CSTK_RELEASE_URL CSTK_KNOWLEDGE_DB
}
ic_install() { sh "$REPO_ROOT/cli/cstk" install --cli=codex "$@"; }
scenario_dry_run_and_invalid_selectors_do_not_mutate() { ic_fixture; assert_exit 0 ic_install --dry-run || return; [ ! -d "$CODEX_HOME/cstk" ] && [ ! -d "$HOME/.claude" ] || return 1; assert_exit 2 ic_install --scope=project; }
scenario_native_install_reinstall_preserve_configuration_hooks_database() {
  ic_fixture
  printf 'model = "existing-model"\n[plugins."other@team"]\nenabled = true\n' > "$CODEX_HOME/config.toml"
  printf '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"user-custom-handler","timeout":10}]}]}}\n' > "$CODEX_HOME/hooks.json"
  printf 'Existing database bytes\n' > "$TMPDIR_TEST/shared.db"
  assert_exit 0 ic_install --knowledge-db "$TMPDIR_TEST/shared.db" || return
  assert_exit 0 ic_install --knowledge-db "$TMPDIR_TEST/shared.db" || return
  _ic_doc=$(cat "$CODEX_HOME/hooks.json")
  [ "$(cj_length "$_ic_doc" /hooks/PreToolUse)" = 2 ] && [ "$(cj_length "$_ic_doc" /hooks/PostToolUse)" = 1 ] && [ "$(cat "$TMPDIR_TEST/shared.db")" = 'Existing database bytes' ] || return 1
  grep -F 'model = "existing-model"' "$CODEX_HOME/config.toml" >/dev/null && [ ! -d "$CODEX_HOME/cstk/.install-lock" ]
}
scenario_cache_edits_are_preserved_and_refused() { ic_fixture; assert_exit 0 ic_install || return; _ic_receipt=$(cat "$CODEX_HOME/cstk/install.json"); _ic_cache=$(cj_get "$_ic_receipt" /cache_path); printf 'Operator edited skill\n' > "$_ic_cache/skills/feature-00c/SKILL.md"; assert_exit 4 ic_install || return; [ "$(cat "$_ic_cache/skills/feature-00c/SKILL.md")" = 'Operator edited skill' ]; }
scenario_hook_edits_are_preserved_and_refused() { ic_fixture; assert_exit 0 ic_install || return; _ic_doc=$(cj_set "$(cat "$CODEX_HOME/hooks.json")" /hooks/PreToolUse/0/hooks/0/timeout 99); printf '%s\n' "$_ic_doc" > "$CODEX_HOME/hooks.json"; assert_exit 4 ic_install || return; cj_equal "$_ic_doc" "$(cat "$CODEX_HOME/hooks.json")"; }
scenario_lock_and_invalid_hooks_refuse_native_mutations() { ic_fixture; mkdir -p "$CODEX_HOME/cstk/.install-lock"; assert_exit 3 ic_install || return; rmdir "$CODEX_HOME/cstk/.install-lock"; printf '{"hooks":{"PreToolUse":{}}}' > "$CODEX_HOME/hooks.json"; assert_exit 4 ic_install || return; [ ! -f "$CODEX_HOME/config.toml" ]; }
scenario_verified_release_installs_without_python() { ic_fixture; assert_exit 0 sh "$REPO_ROOT/scripts/build-release.sh" 0.0.0-codex-test --out "$TMPDIR_TEST/release" || return; assert_exit 0 ic_install --from "file://$TMPDIR_TEST/release/cstk-0.0.0-codex-test.tar.gz" || return; _ic_cache=$(cj_get "$(cat "$CODEX_HOME/cstk/install.json")" /cache_path); [ -f "$_ic_cache/cli/lib/install-codex.sh" ] && [ -f "$_ic_cache/skills/agente-00c-abort/SKILL.md" ] && [ ! -d "$HOME/.claude/skills" ]; }
run_all_scenarios
