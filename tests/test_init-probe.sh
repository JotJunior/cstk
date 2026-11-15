#!/bin/sh
# test_init-probe.sh — cobre plugins/cstk/skills/cstk-init/scripts/init-probe.sh
# (feature cstk-init, tarefa 4.1).
#
# Ref: docs/specs/cstk-init/quickstart.md Scenarios 3, 4 e 15;
#      docs/specs/cstk-init/contracts/cli-invocation.md §2.
#
# Cobertura:
#   Uso: sem args / subcomando desconhecido / sem --root / flag desconhecida -> exit 2
#   preflight: raiz inexistente, nao-diretorio, somente-leitura, ok; VCS none / git-clean /
#     git-dirty; ausencia de git (seam INIT_PROBE_GIT_BIN) -> VCS none; raiz com espaco e
#     com '-' inicial (caminho tratado como dado)
#   artifacts: briefing absent/legacy/both/canonical; constitution com versao do rodape;
#     specs ativas (sem _archived/ e current/); raiz inexistente -> exit 1; constitution
#     symlink nao e lida
#   version: plugin-json, manifest, unknown; exit 0 em todos
#
# POSIX sh puro. Convencao de exit de scenario: 0 PASS, 1 FAIL, 2 ERROR.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

PROBE="$REPO_ROOT/plugins/cstk/skills/cstk-init/scripts/init-probe.sh"
TAB=$(printf '\t')

_git_ok() { command -v git >/dev/null 2>&1; }

# _git_init <dir> — repositorio com um commit (arquivo rastreado), sem depender de config global.
_git_init() {
  (
    cd "$1" || exit 1
    git init -q . || exit 1
    printf 'x\n' > tracked.txt
    git add tracked.txt || exit 1
    git -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false \
      commit -q -m init || exit 1
  )
}

# ---- uso ----

scenario_usage_errors_exit_2() {
  mktemp_test || return 2
  assert_exit 2 sh "$PROBE" || return 1
  assert_exit 2 sh "$PROBE" bogus || return 1
  assert_exit 2 sh "$PROBE" preflight || return 1
  assert_exit 2 sh "$PROBE" artifacts || return 1
  assert_exit 2 sh "$PROBE" version || return 1
  assert_exit 2 sh "$PROBE" preflight --root || return 1
  assert_exit 2 sh "$PROBE" preflight --root "$TMPDIR_TEST" --bogus || return 1
  return 0
}

# ---- preflight (Scenario 3) ----

scenario_preflight_missing_root_denied() {
  mktemp_test || return 2
  assert_exit 3 sh "$PROBE" preflight --root "$TMPDIR_TEST/inexistente" || return 1
  assert_stdout_contains "WRITE${TAB}denied-missing" || return 1
}

scenario_preflight_not_a_directory_denied() {
  mktemp_test || return 2
  : > "$TMPDIR_TEST/arquivo"
  assert_exit 3 sh "$PROBE" preflight --root "$TMPDIR_TEST/arquivo" || return 1
  assert_stdout_contains "WRITE${TAB}denied-not-dir" || return 1
}

scenario_preflight_readonly_denied() {
  mktemp_test || return 2
  mkdir "$TMPDIR_TEST/ro"
  chmod 555 "$TMPDIR_TEST/ro"
  if [ -w "$TMPDIR_TEST/ro" ]; then
    # executando como root: chmod nao nega escrita; cenario nao aplicavel
    chmod 755 "$TMPDIR_TEST/ro"
    return 0
  fi
  assert_exit 3 sh "$PROBE" preflight --root "$TMPDIR_TEST/ro"
  _rc=$?
  chmod 755 "$TMPDIR_TEST/ro"
  [ "$_rc" -eq 0 ] || return 1
  assert_stdout_contains "WRITE${TAB}denied-readonly" || return 1
}

scenario_preflight_ok_reports_abs_root() {
  mktemp_test || return 2
  mkdir "$TMPDIR_TEST/proj"
  assert_exit 0 sh "$PROBE" preflight --root "$TMPDIR_TEST/proj" || return 1
  assert_stdout_contains "WRITE${TAB}ok" || return 1
  assert_stdout_match "^ROOT${TAB}/.*/proj\$" || return 1
}

scenario_preflight_vcs_none_when_git_missing() {
  mktemp_test || return 2
  mkdir "$TMPDIR_TEST/proj"
  # seam: binario de git inexistente -> fallback VCS none (mesmo em repositorio)
  assert_exit 0 env INIT_PROBE_GIT_BIN="git-inexistente-cstk-init" sh "$PROBE" preflight --root "$TMPDIR_TEST/proj" || return 1
  assert_stdout_contains "VCS${TAB}none" || return 1
  if _git_ok; then
    _git_init "$TMPDIR_TEST/proj" || return 2
    printf 'sujo\n' > "$TMPDIR_TEST/proj/novo.txt"
    assert_exit 0 env INIT_PROBE_GIT_BIN="git-inexistente-cstk-init" sh "$PROBE" preflight --root "$TMPDIR_TEST/proj" || return 1
    assert_stdout_contains "VCS${TAB}none" || return 1
  fi
  return 0
}

scenario_preflight_vcs_clean_and_dirty() {
  mktemp_test || return 2
  _git_ok || return 0
  mkdir "$TMPDIR_TEST/proj"
  _git_init "$TMPDIR_TEST/proj" || return 2
  assert_exit 0 sh "$PROBE" preflight --root "$TMPDIR_TEST/proj" || return 1
  assert_stdout_contains "VCS${TAB}git-clean" || return 1
  printf 'y\n' > "$TMPDIR_TEST/proj/tracked.txt"
  assert_exit 0 sh "$PROBE" preflight --root "$TMPDIR_TEST/proj" || return 1
  assert_stdout_contains "VCS${TAB}git-dirty" || return 1
}

scenario_preflight_env_git_dir_does_not_redirect() {
  mktemp_test || return 2
  _git_ok || return 0
  mkdir "$TMPDIR_TEST/proj" "$TMPDIR_TEST/other"
  _git_init "$TMPDIR_TEST/other" || return 2
  printf 'sujo\n' > "$TMPDIR_TEST/other/novo.txt"
  # GIT_DIR apontando para outro repositorio sujo nao pode vazar para a sondagem de proj
  assert_exit 0 env GIT_DIR="$TMPDIR_TEST/other/.git" sh "$PROBE" preflight --root "$TMPDIR_TEST/proj" || return 1
  assert_stdout_not_contains "git-dirty" || return 1
}

scenario_preflight_path_with_space_and_leading_dash() {
  mktemp_test || return 2
  mkdir "$TMPDIR_TEST/dir com espaco" "$TMPDIR_TEST/-lead"
  assert_exit 0 sh "$PROBE" preflight --root "$TMPDIR_TEST/dir com espaco" || return 1
  assert_stdout_contains "WRITE${TAB}ok" || return 1
  _old=$(pwd)
  cd "$TMPDIR_TEST" || return 2
  capture sh "$PROBE" preflight --root "-lead"
  cd "$_old" || return 2
  [ "$_CAPTURED_EXIT" -eq 0 ] || { _fail "leading_dash" "exit $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "WRITE${TAB}ok" || return 1
}

# ---- artifacts (Scenario 4) ----

scenario_artifacts_bare() {
  mktemp_test || return 2
  fixture cstk-init/bare || return 2
  assert_exit 0 sh "$PROBE" artifacts --root "$TMPDIR_TEST" || return 1
  assert_stdout_contains "briefing${TAB}absent${TAB}-${TAB}-" || return 1
  assert_stdout_contains "constitution${TAB}absent${TAB}-${TAB}-" || return 1
  assert_stdout_not_contains "spec${TAB}" || return 1
}

scenario_artifacts_legacy() {
  mktemp_test || return 2
  fixture cstk-init/legacy || return 2
  assert_exit 0 sh "$PROBE" artifacts --root "$TMPDIR_TEST" || return 1
  assert_stdout_contains "briefing${TAB}legacy${TAB}docs/01-briefing-discovery/briefing.md${TAB}-" || return 1
  assert_stdout_contains "constitution${TAB}present${TAB}docs/constitution.md${TAB}" || return 1
}

scenario_artifacts_both() {
  mktemp_test || return 2
  fixture cstk-init/both-briefings || return 2
  assert_exit 0 sh "$PROBE" artifacts --root "$TMPDIR_TEST" || return 1
  assert_stdout_contains "briefing${TAB}both${TAB}docs/briefing.md,docs/01-briefing-discovery/briefing.md${TAB}-" || return 1
}

scenario_artifacts_conformant_reads_footer_version() {
  mktemp_test || return 2
  fixture cstk-init/conformant || return 2
  assert_exit 0 sh "$PROBE" artifacts --root "$TMPDIR_TEST" || return 1
  assert_stdout_contains "briefing${TAB}canonical${TAB}docs/briefing.md${TAB}-" || return 1
  assert_stdout_contains "constitution${TAB}present${TAB}docs/constitution.md${TAB}1.0.0" || return 1
}

scenario_artifacts_specs_exclude_archived_and_current() {
  mktemp_test || return 2
  mkdir -p "$TMPDIR_TEST/docs/specs/alpha" "$TMPDIR_TEST/docs/specs/beta" \
    "$TMPDIR_TEST/docs/specs/_archived/old" "$TMPDIR_TEST/docs/specs/current" \
    "$TMPDIR_TEST/docs/specs/sem-spec"
  : > "$TMPDIR_TEST/docs/specs/alpha/spec.md"
  : > "$TMPDIR_TEST/docs/specs/beta/spec.md"
  : > "$TMPDIR_TEST/docs/specs/_archived/old/spec.md"
  : > "$TMPDIR_TEST/docs/specs/_archived/spec.md"
  : > "$TMPDIR_TEST/docs/specs/current/spec.md"
  assert_exit 0 sh "$PROBE" artifacts --root "$TMPDIR_TEST" || return 1
  assert_stdout_contains "spec${TAB}present${TAB}docs/specs/alpha/spec.md${TAB}alpha" || return 1
  assert_stdout_contains "spec${TAB}present${TAB}docs/specs/beta/spec.md${TAB}beta" || return 1
  assert_stdout_not_contains "_archived" || return 1
  assert_stdout_not_contains "current" || return 1
  assert_stdout_not_contains "sem-spec" || return 1
}

scenario_artifacts_missing_root_exit_1() {
  mktemp_test || return 2
  assert_exit 1 sh "$PROBE" artifacts --root "$TMPDIR_TEST/inexistente" || return 1
}

scenario_artifacts_constitution_symlink_not_read() {
  mktemp_test || return 2
  mkdir -p "$TMPDIR_TEST/proj/docs" "$TMPDIR_TEST/fora"
  printf '**Version**: 9.9.9 | **Ratified**: x\n' > "$TMPDIR_TEST/fora/c.md"
  ln -s "$TMPDIR_TEST/fora/c.md" "$TMPDIR_TEST/proj/docs/constitution.md"
  assert_exit 0 sh "$PROBE" artifacts --root "$TMPDIR_TEST/proj" || return 1
  assert_stdout_contains "constitution${TAB}present${TAB}docs/constitution.md${TAB}-" || return 1
  assert_stdout_not_contains "9.9.9" || return 1
}

# ---- version (Scenario 15) ----

scenario_version_plugin_json() {
  mktemp_test || return 2
  mkdir -p "$TMPDIR_TEST/plug/skills/cstk-init" "$TMPDIR_TEST/plug/.claude-plugin"
  cat > "$TMPDIR_TEST/plug/.claude-plugin/plugin.json" <<'EOF'
{
  "name": "cstk",
  "version": "1.2.3",
  "author": {"name": "t"}
}
EOF
  assert_exit 0 sh "$PROBE" version --skill-dir "$TMPDIR_TEST/plug/skills/cstk-init" || return 1
  assert_stdout_contains "CSTK_VERSION${TAB}1.2.3${TAB}plugin-json" || return 1
}

scenario_version_manifest() {
  mktemp_test || return 2
  mkdir -p "$TMPDIR_TEST/cat/skills/cstk-init"
  {
    printf '# cstk manifest v1\n'
    printf '# schema: <skill-name>\\t<toolkit-version>\\t<source-sha256>\\t<installed-at-iso>\n'
    printf 'briefing\t0.0.1\tabc\t2026-01-01T00:00:00Z\n'
    printf 'cstk-init\t4.5.6\tdef\t2026-01-01T00:00:00Z\n'
  } > "$TMPDIR_TEST/cat/skills/.cstk-manifest"
  assert_exit 0 sh "$PROBE" version --skill-dir "$TMPDIR_TEST/cat/skills/cstk-init/" || return 1
  assert_stdout_contains "CSTK_VERSION${TAB}4.5.6${TAB}manifest" || return 1
}

scenario_version_unknown() {
  mktemp_test || return 2
  mkdir -p "$TMPDIR_TEST/nada/skills/cstk-init"
  assert_exit 0 sh "$PROBE" version --skill-dir "$TMPDIR_TEST/nada/skills/cstk-init" || return 1
  assert_stdout_contains "CSTK_VERSION${TAB}unknown${TAB}unknown" || return 1
  # skill-dir inexistente tambem e `unknown` com exit 0
  assert_exit 0 sh "$PROBE" version --skill-dir "$TMPDIR_TEST/nao/existe" || return 1
  assert_stdout_contains "CSTK_VERSION${TAB}unknown${TAB}unknown" || return 1
}

scenario_version_rejects_hostile_value() {
  mktemp_test || return 2
  mkdir -p "$TMPDIR_TEST/p/skills/cstk-init" "$TMPDIR_TEST/p/.claude-plugin"
  printf '{ "version": "1.0; rm -rf /" }\n' > "$TMPDIR_TEST/p/.claude-plugin/plugin.json"
  assert_exit 0 sh "$PROBE" version --skill-dir "$TMPDIR_TEST/p/skills/cstk-init" || return 1
  assert_stdout_contains "CSTK_VERSION${TAB}unknown${TAB}unknown" || return 1
}

# ---- hardening 7.4 (owasp-security pos-implementacao) ----

scenario_artifacts_do_not_read_through_escaping_symlink() {
  mktemp_test || return 2
  mkdir -p "$TMPDIR_TEST/out" "$TMPDIR_TEST/p"
  printf '**Version**: FIXTURE_FAKE_VERSION_LEAK\n' > "$TMPDIR_TEST/out/constitution.md"
  ln -s "$TMPDIR_TEST/out" "$TMPDIR_TEST/p/docs" || return 2
  capture sh "$PROBE" artifacts --root "$TMPDIR_TEST/p"
  [ "$_CAPTURED_EXIT" -eq 0 ] || { _fail "escape" "exit $_CAPTURED_EXIT"; return 1; }
  assert_stdout_not_contains "FIXTURE_FAKE_VERSION_LEAK" || return 1
  assert_stdout_contains "constitution${TAB}absent" || return 1
}

scenario_artifacts_follow_internal_symlink() {
  mktemp_test || return 2
  mkdir -p "$TMPDIR_TEST/p/documentation"
  printf '**Version**: 1.2.3\n' > "$TMPDIR_TEST/p/documentation/constitution.md"
  ln -s documentation "$TMPDIR_TEST/p/docs" || return 2
  capture sh "$PROBE" artifacts --root "$TMPDIR_TEST/p"
  [ "$_CAPTURED_EXIT" -eq 0 ] || { _fail "internal" "exit $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "constitution${TAB}present" || return 1
}

run_all_scenarios
