#!/bin/sh
# test_init-guard.sh — cobre plugins/cstk/skills/cstk-init/scripts/init-guard.sh
# (feature cstk-init, tarefa 4.3).
#
# Ref: docs/specs/cstk-init/quickstart.md Scenarios 6 (passo 4), 7, 8 e 18;
#      docs/specs/cstk-init/contracts/cli-invocation.md §6; spec FR-010, FR-012, FR-019,
#      FR-027, FR-031, FR-032.
#
# Cobertura:
#   check: ALLOW na allowlist de 5 caminhos; DENY nas cinco razoes (outside-root,
#     symlink-escape, not-allowlisted, exists, unconfirmed); caminhos hostis (.. , absoluto,
#     newline, '-' inicial, barra dupla/final); op migrate; fail-closed (raiz inexistente,
#     op invalido)
#   scan: clean / secret-found (valor fora de stdout/stderr) / unavailable (scanner ausente,
#     scanner com exit 2, probe com scanner "sempre limpo"); --probe; arquivo inexistente
#   migrate: confirmado move (conteudo preservado); sem confirmacao, destino existente,
#     origem inexistente e symlink = DENY sem alterar o sistema de arquivos
#
# POSIX sh puro. Convencao de exit de scenario: 0 PASS, 1 FAIL, 2 ERROR.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

GUARD="$REPO_ROOT/plugins/cstk/skills/cstk-init/scripts/init-guard.sh"
CATALOG="$REPO_ROOT/plugins/cstk/skills"
TAB=$(printf '\t')
NL='
'

# _check <root> <path> <op> [--confirmed] — roda `check` e captura.
_check() {
  _r=$1; _p=$2; _o=$3; shift 3
  capture sh "$GUARD" check --root "$_r" --path "$_p" --op "$_o" "$@"
}

# _expect_deny <root> <path> <op> <reason> [--confirmed]
_expect_deny() {
  _r=$1; _p=$2; _o=$3; _why=$4; shift 4
  _check "$_r" "$_p" "$_o" "$@"
  [ "$_CAPTURED_EXIT" -eq 3 ] || { _fail "expect_deny" "exit $_CAPTURED_EXIT para $_p"; return 1; }
  assert_stdout_contains "DENY${TAB}$_p${TAB}$_why" || return 1
}

# _expect_allow <root> <path> <op> [--confirmed]
_expect_allow() {
  _r=$1; _p=$2; _o=$3; shift 3
  _check "$_r" "$_p" "$_o" "$@"
  [ "$_CAPTURED_EXIT" -eq 0 ] || { _fail "expect_allow" "exit $_CAPTURED_EXIT para $_p"; return 1; }
  assert_stdout_contains "ALLOW${TAB}$_p" || return 1
}

# _fake_catalog <dir> <exit-code> — catalogo com um secrets-filter.sh que sempre sai com o codigo.
_fake_catalog() {
  mkdir -p "$1/agente-00c-runtime/scripts"
  printf '#!/bin/sh\ncat >/dev/null\nexit %s\n' "$2" > "$1/agente-00c-runtime/scripts/secrets-filter.sh"
}

# ---- uso e fail-closed ----

scenario_usage_errors_exit_2() {
  mktemp_test || return 2
  assert_exit 2 sh "$GUARD" || return 1
  assert_exit 2 sh "$GUARD" bogus || return 1
  assert_exit 2 sh "$GUARD" check --root "$TMPDIR_TEST" || return 1
  assert_exit 2 sh "$GUARD" check --root "$TMPDIR_TEST" --path docs/briefing.md || return 1
  assert_exit 2 sh "$GUARD" check --root "$TMPDIR_TEST" --path docs/briefing.md --op delete || return 1
  assert_exit 2 sh "$GUARD" check --root "$TMPDIR_TEST" --path docs/briefing.md --op create --bogus || return 1
  assert_exit 2 sh "$GUARD" scan || return 1
}

scenario_check_missing_root_is_fail_closed() {
  mktemp_test || return 2
  _check "$TMPDIR_TEST/inexistente" docs/briefing.md create
  [ "$_CAPTURED_EXIT" -eq 1 ] || { _fail "missing_root" "exit $_CAPTURED_EXIT"; return 1; }
  assert_stdout_not_contains "ALLOW" || return 1
}

# ---- check: ALLOW ----

scenario_check_allow_five_paths_on_create() {
  mktemp_test || return 2
  mkdir "$TMPDIR_TEST/p"
  for _p in docs/briefing.md docs/constitution.md docs/specs/minha-feature/spec.md \
    docs/specs/minha-feature/data-model.md docs/specs/minha-feature/checklists/security.md; do
    _expect_allow "$TMPDIR_TEST/p" "$_p" create || return 1
  done
}

scenario_check_amend_confirmed_allowed_unconfirmed_denied() {
  mktemp_test || return 2
  fixture cstk-init/conformant || return 2
  _expect_deny "$TMPDIR_TEST" docs/constitution.md amend unconfirmed || return 1
  _expect_allow "$TMPDIR_TEST" docs/constitution.md amend --confirmed || return 1
}

# ---- check: DENY (Scenario 7, cinco razoes) ----

scenario_check_deny_exists() {
  mktemp_test || return 2
  fixture cstk-init/conformant || return 2
  _expect_deny "$TMPDIR_TEST" docs/briefing.md create exists || return 1
  # --confirmed nao autoriza sobrescrever com create
  _expect_deny "$TMPDIR_TEST" docs/briefing.md create exists --confirmed || return 1
}

scenario_check_deny_not_allowlisted() {
  mktemp_test || return 2
  mkdir "$TMPDIR_TEST/p"
  for _p in src/index.js README.md docs/other.md docs/specs/x/tasks.md docs/specs/x/plan.md \
    docs/specs/current/spec.md docs/specs/_archived/spec.md docs/specs/Bad_Name/spec.md \
    docs/specs/-rf/spec.md docs/specs/x/checklists/a/b.md docs/specs/x/checklists/Sec.md \
    docs//briefing.md ./docs/briefing.md docs/./briefing.md docs/briefing.md/ -rf; do
    _expect_deny "$TMPDIR_TEST/p" "$_p" create not-allowlisted || return 1
  done
}

scenario_check_deny_outside_root() {
  mktemp_test || return 2
  mkdir "$TMPDIR_TEST/p"
  for _p in ../x.md /etc/passwd docs/../../x.md docs/specs/x/../../../y.md ..; do
    _expect_deny "$TMPDIR_TEST/p" "$_p" create outside-root || return 1
  done
}

scenario_check_deny_symlink_escape() {
  mktemp_test || return 2
  mkdir -p "$TMPDIR_TEST/p/docs" "$TMPDIR_TEST/fora/docs"
  # arquivo-alvo e symlink para fora
  : > "$TMPDIR_TEST/fora/alvo.md"
  ln -s "$TMPDIR_TEST/fora/alvo.md" "$TMPDIR_TEST/p/docs/briefing.md"
  _expect_deny "$TMPDIR_TEST/p" docs/briefing.md amend symlink-escape --confirmed || return 1
  # symlink interno tambem e negado (Write seguiria o link para fora da allowlist)
  ln -s ../README.md "$TMPDIR_TEST/p/docs/constitution.md"
  _expect_deny "$TMPDIR_TEST/p" docs/constitution.md amend symlink-escape --confirmed || return 1
  # diretorio intermediario e symlink para fora
  mkdir "$TMPDIR_TEST/q"
  ln -s "$TMPDIR_TEST/fora/docs" "$TMPDIR_TEST/q/docs"
  _expect_deny "$TMPDIR_TEST/q" docs/briefing.md create symlink-escape || return 1
  [ ! -e "$TMPDIR_TEST/fora/docs/briefing.md" ] || return 1
}

scenario_check_deny_unconfirmed_only_for_amend() {
  mktemp_test || return 2
  fixture cstk-init/conformant || return 2
  _expect_deny "$TMPDIR_TEST" docs/briefing.md amend unconfirmed || return 1
}

scenario_check_hostile_newline_path_keeps_tsv_integrity() {
  mktemp_test || return 2
  mkdir "$TMPDIR_TEST/p"
  _check "$TMPDIR_TEST/p" "docs/a${NL}b.md" create
  [ "$_CAPTURED_EXIT" -eq 3 ] || { _fail "newline" "exit $_CAPTURED_EXIT"; return 1; }
  _n=$(printf '%s\n' "$_CAPTURED_STDOUT" | wc -l | tr -d ' ')
  [ "$_n" -eq 1 ] || { _fail "newline" "stdout com $_n linhas"; return 1; }
  assert_stdout_contains "not-allowlisted" || return 1
}

scenario_check_path_is_never_executed() {
  mktemp_test || return 2
  mkdir "$TMPDIR_TEST/p"
  _expect_deny "$TMPDIR_TEST/p" 'docs/$(touch pwned).md' create not-allowlisted || return 1
  [ ! -e pwned ] && [ ! -e "$TMPDIR_TEST/p/pwned" ] || { _fail "exec" "comando executado"; return 1; }
}

# ---- check: op migrate ----

scenario_check_migrate_op() {
  mktemp_test || return 2
  fixture cstk-init/legacy || return 2
  _expect_deny "$TMPDIR_TEST" docs/01-briefing-discovery/briefing.md migrate unconfirmed || return 1
  _expect_allow "$TMPDIR_TEST" docs/01-briefing-discovery/briefing.md migrate --confirmed || return 1
  # so a origem fixa e aceita
  _expect_deny "$TMPDIR_TEST" docs/briefing.md migrate not-allowlisted --confirmed || return 1
  _expect_deny "$TMPDIR_TEST" docs/constitution.md migrate not-allowlisted --confirmed || return 1
}

# ---- scan ----

scenario_scan_clean_and_secret_found() {
  mktemp_test || return 2
  fixture cstk-init/secrets || return 2
  assert_exit 0 sh "$GUARD" scan --file "$TMPDIR_TEST/README.md" --catalog-root "$CATALOG" || return 1
  assert_stdout_contains "SCAN${TAB}clean" || return 1
  assert_exit 3 sh "$GUARD" scan --file "$TMPDIR_TEST/config/app.yml" --catalog-root "$CATALOG" || return 1
  assert_stdout_contains "SCAN${TAB}secret-found" || return 1
  assert_stdout_not_contains "FIXTURE_FAKE_KEY_" || return 1
  assert_stdout_not_contains "api_key" || return 1
  case "$_CAPTURED_STDERR" in
    *FIXTURE_FAKE_KEY_*|*api_key*) _fail "scan" "match vazou para stderr"; return 1 ;;
  esac
}

scenario_scan_default_catalog_root_resolves_sibling_skills() {
  mktemp_test || return 2
  printf 'texto limpo\n' > "$TMPDIR_TEST/doc.md"
  # sem --catalog-root: usa <skills>/ a partir do proprio script
  assert_exit 0 sh "$GUARD" scan --file "$TMPDIR_TEST/doc.md" || return 1
  assert_stdout_contains "SCAN${TAB}clean" || return 1
}

scenario_scan_probe_available_with_real_scanner() {
  mktemp_test || return 2
  assert_exit 0 sh "$GUARD" scan --probe --catalog-root "$CATALOG" || return 1
  assert_stdout_contains "SCAN${TAB}available" || return 1
}

scenario_scan_unavailable_when_scanner_missing_scenario18() {
  mktemp_test || return 2
  fixture cstk-init/secrets || return 2
  mkdir "$TMPDIR_TEST/catalogo-vazio"
  assert_exit 4 sh "$GUARD" scan --probe --catalog-root "$TMPDIR_TEST/catalogo-vazio" || return 1
  assert_stdout_contains "SCAN${TAB}unavailable" || return 1
  assert_exit 4 sh "$GUARD" scan --file "$TMPDIR_TEST/config/app.yml" --catalog-root "$TMPDIR_TEST/catalogo-vazio" || return 1
  assert_stdout_contains "SCAN${TAB}unavailable" || return 1
  assert_stdout_not_contains "FIXTURE_FAKE_KEY_" || return 1
  case "$_CAPTURED_STDERR" in
    *FIXTURE_FAKE_KEY_*) _fail "scan" "valor vazou para stderr"; return 1 ;;
  esac
}

scenario_scan_scanner_failure_is_unavailable() {
  mktemp_test || return 2
  printf 'texto\n' > "$TMPDIR_TEST/doc.md"
  _fake_catalog "$TMPDIR_TEST/cat2" 2
  assert_exit 4 sh "$GUARD" scan --file "$TMPDIR_TEST/doc.md" --catalog-root "$TMPDIR_TEST/cat2" || return 1
  assert_stdout_contains "SCAN${TAB}unavailable" || return 1
  assert_exit 4 sh "$GUARD" scan --probe --catalog-root "$TMPDIR_TEST/cat2" || return 1
}

scenario_scan_probe_rejects_always_clean_scanner() {
  mktemp_test || return 2
  _fake_catalog "$TMPDIR_TEST/cat0" 0
  assert_exit 4 sh "$GUARD" scan --probe --catalog-root "$TMPDIR_TEST/cat0" || return 1
  assert_stdout_contains "SCAN${TAB}unavailable" || return 1
}

scenario_scan_missing_file_exit_1() {
  mktemp_test || return 2
  assert_exit 1 sh "$GUARD" scan --file "$TMPDIR_TEST/inexistente.md" --catalog-root "$CATALOG" || return 1
  assert_stdout_not_contains "clean" || return 1
}

# ---- migrate ----

scenario_migrate_confirmed_moves_and_preserves_content() {
  mktemp_test || return 2
  fixture cstk-init/legacy || return 2
  cp "$TMPDIR_TEST/docs/01-briefing-discovery/briefing.md" "$TMPDIR_TEST/orig.copy"
  assert_exit 0 sh "$GUARD" migrate --root "$TMPDIR_TEST" --confirmed || return 1
  assert_stdout_contains "MIGRATED${TAB}docs/01-briefing-discovery/briefing.md${TAB}docs/briefing.md" || return 1
  [ -f "$TMPDIR_TEST/docs/briefing.md" ] || { _fail "migrate" "destino ausente"; return 1; }
  [ ! -e "$TMPDIR_TEST/docs/01-briefing-discovery/briefing.md" ] || { _fail "migrate" "origem permaneceu"; return 1; }
  cmp -s "$TMPDIR_TEST/orig.copy" "$TMPDIR_TEST/docs/briefing.md" || { _fail "migrate" "conteudo alterado"; return 1; }
  # a constitution e o resto do projeto permanecem
  [ -f "$TMPDIR_TEST/docs/constitution.md" ] || { _fail "migrate" "constitution removida"; return 1; }
}

scenario_migrate_without_confirmation_moves_nothing() {
  mktemp_test || return 2
  fixture cstk-init/legacy || return 2
  assert_exit 3 sh "$GUARD" migrate --root "$TMPDIR_TEST" || return 1
  assert_stdout_contains "DENY${TAB}docs/01-briefing-discovery/briefing.md${TAB}unconfirmed" || return 1
  [ -f "$TMPDIR_TEST/docs/01-briefing-discovery/briefing.md" ] || { _fail "migrate" "origem sumiu"; return 1; }
  [ ! -e "$TMPDIR_TEST/docs/briefing.md" ] || { _fail "migrate" "destino criado"; return 1; }
}

scenario_migrate_denied_when_destination_exists() {
  mktemp_test || return 2
  fixture cstk-init/both-briefings || return 2
  cp "$TMPDIR_TEST/docs/briefing.md" "$TMPDIR_TEST/dst.copy"
  assert_exit 3 sh "$GUARD" migrate --root "$TMPDIR_TEST" --confirmed || return 1
  assert_stdout_contains "${TAB}exists" || return 1
  [ -f "$TMPDIR_TEST/docs/01-briefing-discovery/briefing.md" ] || { _fail "migrate" "origem sumiu"; return 1; }
  cmp -s "$TMPDIR_TEST/dst.copy" "$TMPDIR_TEST/docs/briefing.md" || { _fail "migrate" "destino sobrescrito"; return 1; }
}

scenario_migrate_denied_when_source_missing() {
  mktemp_test || return 2
  fixture cstk-init/bare || return 2
  assert_exit 3 sh "$GUARD" migrate --root "$TMPDIR_TEST" --confirmed || return 1
  assert_stdout_contains "${TAB}not-allowlisted" || return 1
  [ ! -e "$TMPDIR_TEST/docs" ] || { _fail "migrate" "docs/ criado"; return 1; }
}

scenario_migrate_denied_on_symlink_and_never_touches_outside() {
  mktemp_test || return 2
  mkdir -p "$TMPDIR_TEST/p/docs" "$TMPDIR_TEST/fora/01-briefing-discovery"
  printf 'externo\n' > "$TMPDIR_TEST/fora/01-briefing-discovery/briefing.md"
  ln -s "$TMPDIR_TEST/fora/01-briefing-discovery" "$TMPDIR_TEST/p/docs/01-briefing-discovery"
  assert_exit 3 sh "$GUARD" migrate --root "$TMPDIR_TEST/p" --confirmed || return 1
  assert_stdout_contains "${TAB}symlink-escape" || return 1
  [ -f "$TMPDIR_TEST/fora/01-briefing-discovery/briefing.md" ] || { _fail "migrate" "arquivo externo movido"; return 1; }
  [ ! -e "$TMPDIR_TEST/p/docs/briefing.md" ] || { _fail "migrate" "destino criado"; return 1; }
}

scenario_migrate_missing_root_and_usage() {
  mktemp_test || return 2
  assert_exit 1 sh "$GUARD" migrate --root "$TMPDIR_TEST/inexistente" --confirmed || return 1
  assert_exit 2 sh "$GUARD" migrate --confirmed || return 1
}

# ---- assert estatico do SKILL.md (Scenario 7 passo 4, SC-010, FR-026) ----

scenario_skill_md_declares_procedural_guard_and_residual_risk() {
  _skill="$REPO_ROOT/plugins/cstk/skills/cstk-init/SKILL.md"
  [ -f "$_skill" ] || { _fail "skill" "SKILL.md ausente"; return 1; }
  # secao Gotchas presente
  grep -q '^## Gotchas' "$_skill" || { _fail "skill" "secao ## Gotchas ausente"; return 1; }
  # so o texto APOS o titulo Gotchas conta
  _g=$(sed -n '/^## Gotchas/,$p' "$_skill")
  for _needle in 'procedimental' 'risco residual' 'nenhuma ferramenta bloqueia' 'init-guard.sh check' \
                 '`PreToolUse` `Write|Edit`' 'feature futura'; do
    printf '%s\n' "$_g" | grep -qiF -- "$_needle" || { _fail "skill" "Gotchas sem: $_needle"; return 1; }
  done
}

# ---- Scenario 7 completo: as cinco razoes de DENY na mesma raiz ----

scenario_scenario7_five_deny_reasons_exit_3() {
  mktemp_test || return 2
  _r="$TMPDIR_TEST/p"
  mkdir -p "$_r/docs" "$TMPDIR_TEST/fora"
  printf 'x\n' > "$_r/docs/briefing.md"
  printf 'y\n' > "$TMPDIR_TEST/fora/alvo.md"
  ln -s "$TMPDIR_TEST/fora" "$_r/docs/specs-link"
  _expect_deny "$_r" docs/briefing.md create exists || return 1
  _expect_deny "$_r" ../fora.md create outside-root || return 1
  _expect_deny "$_r" docs/specs-link/alvo.md create symlink-escape || return 1
  _expect_deny "$_r" src/x.md create not-allowlisted || return 1
  _expect_deny "$_r" docs/constitution.md amend unconfirmed || return 1
}

run_all_scenarios
