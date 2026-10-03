#!/bin/sh
TESTS_ROOT=${TESTS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}
REPO_ROOT=${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}
. "$TESTS_ROOT/lib/harness.sh"
. "$REPO_ROOT/cli/lib/codex-json.sh"
. "$REPO_ROOT/cli/lib/codex-common.sh"
set +eu
scenario_path_normalization_and_shell_quote() { mkdir "$TMPDIR_TEST/a"; [ "$(cx_path "$TMPDIR_TEST/a/../a/new")" = "$(cd "$TMPDIR_TEST/a" && pwd -P)/new" ] || return 1; _q=$(cx_quote_shell "space and ' quote"); [ "$(sh -c "printf '%s' $_q")" = "space and ' quote" ]; }
scenario_symlink_file_refused_and_atomic_write_preserves_it() { printf data > "$TMPDIR_TEST/original"; ln -s "$TMPDIR_TEST/original" "$TMPDIR_TEST/link"; capture cx_path "$TMPDIR_TEST/link"; [ "$_CAPTURED_EXIT" != 0 ] || return 1; capture cx_atomic "$TMPDIR_TEST/link" '{}'; [ "$_CAPTURED_EXIT" != 0 ] && [ "$(cat "$TMPDIR_TEST/original")" = data ]; }
scenario_timeout_and_live_owner_are_conservative() { capture cx_timeout 1 sleep 5; [ "$_CAPTURED_EXIT" != 0 ] || return 1; capture cx_dead "$$"; [ "$_CAPTURED_EXIT" != 0 ]; }
run_all_scenarios
