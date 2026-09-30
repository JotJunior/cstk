#!/bin/sh
# test_locate-feature.sh — cobre
# plugins/cstk/skills/reconcile-docs/scripts/locate-feature.sh.
#
# Ref: docs/specs/code-reconciliation/contracts/cli-invocation.md §2
#      docs/specs/code-reconciliation/quickstart.md Scenarios 3, 4, 5

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"
. "$TESTS_ROOT/lib/harness.sh"
. "$TESTS_ROOT/lib/reconcile-fixture.sh"

SCRIPT="$REPO_ROOT/plugins/cstk/skills/reconcile-docs/scripts/locate-feature.sh"
TAB=$(printf '\t')

_lf_setup() {
  _LF_DIR=$(rd_make_fixture nogit) || return 2
  trap 'rm -rf "$_LF_DIR"; _cleanup_tmpdir' EXIT INT TERM
}

_lf_run() { capture sh "$SCRIPT" --root "$_LF_DIR" "$@"; }

_lf_exit() {
  [ "$_CAPTURED_EXIT" = "$1" ] || { _fail "exit" "esperado $1, obtido $_CAPTURED_EXIT"; return 1; }
}

scenario_ativa_por_nome() {
  _lf_setup || return 2
  _lf_run --name epsilon
  _lf_exit 0 || return 1
  [ "$_CAPTURED_STDOUT" = "active${TAB}epsilon${TAB}docs/specs/epsilon" ] || { _fail "stdout" "saida inesperada"; return 1; }
}

scenario_arquivada_por_nome_sem_data() {
  _lf_setup || return 2
  _lf_run --name beta
  _lf_exit 0 || return 1
  [ "$_CAPTURED_STDOUT" = "archived${TAB}beta${TAB}docs/specs/_archived/2026-01-15-beta" ] || { _fail "stdout" "saida inesperada"; return 1; }
}

scenario_arquivada_por_nome_com_data() {
  _lf_setup || return 2
  _lf_run --name 2026-01-15-beta
  _lf_exit 0 || return 1
  assert_stdout_contains "archived${TAB}beta${TAB}docs/specs/_archived/2026-01-15-beta" || return 1
}

scenario_arquivada_legada_sem_prefixo() {
  _lf_setup || return 2
  _lf_run --name gamma
  _lf_exit 0 || return 1
  [ "$_CAPTURED_STDOUT" = "archived${TAB}gamma${TAB}docs/specs/_archived/gamma" ] || { _fail "stdout" "saida inesperada"; return 1; }
}

scenario_inexistente_com_candidatos() {
  _lf_setup || return 2
  _lf_run --name alph
  _lf_exit 3 || return 1
  assert_stdout_contains "candidate${TAB}alpha${TAB}docs/specs/alpha" || return 1
}

scenario_inexistente_sem_candidatos() {
  _lf_setup || return 2
  _lf_run --name zzz
  _lf_exit 3 || return 1
  [ -z "$_CAPTURED_STDOUT" ] || { _fail "stdout" "esperado vazio"; return 1; }
}

scenario_ambigua_entre_arquivadas() {
  _lf_setup || return 2
  _lf_run --name delta
  _lf_exit 4 || return 1
  assert_stdout_contains "candidate${TAB}delta${TAB}docs/specs/_archived/2026-01-01-delta" || return 1
  assert_stdout_contains "candidate${TAB}delta${TAB}docs/specs/_archived/2026-02-01-delta" || return 1
}

scenario_homonima_ativa_e_arquivada() {
  _lf_setup || return 2
  _lf_run --name alpha
  _lf_exit 0 || return 1
  assert_stdout_contains "active${TAB}alpha${TAB}docs/specs/alpha" || return 1
  assert_stdout_contains "archived-shadowed${TAB}alpha${TAB}docs/specs/_archived/2025-12-01-alpha" || return 1
}

scenario_all_lista_ativas_depois_arquivadas() {
  _lf_setup || return 2
  _lf_run --all
  _lf_exit 0 || return 1
  _n=$(printf '%s\n' "$_CAPTURED_STDOUT" | wc -l | tr -d ' ')
  [ "$_n" = 7 ] || { _fail "linhas" "esperado 7 linhas, obtido $_n"; return 1; }
  _first=$(printf '%s\n' "$_CAPTURED_STDOUT" | sed -n 1p | cut -f1)
  _last=$(printf '%s\n' "$_CAPTURED_STDOUT" | sed -n '$p' | cut -f1)
  [ "$_first" = active ] && [ "$_last" = archived ] || { _fail "ordem" "ativas primeiro, arquivadas depois"; return 1; }
  assert_stdout_contains "archived-shadowed${TAB}alpha${TAB}docs/specs/_archived/2025-12-01-alpha" || return 1
  assert_stdout_not_contains "current" || return 1
}

scenario_nunca_lista_current_nem_archived_como_feature() {
  _lf_setup || return 2
  _lf_run --all
  case "$_CAPTURED_STDOUT" in
    *"${TAB}current${TAB}"* | *"${TAB}_archived${TAB}"*) _fail "stdout" "current/_archived listados"; return 1 ;;
  esac
  _lf_run --name current
  _lf_exit 3 || return 1
  [ -z "$_CAPTURED_STDOUT" ] || { _fail "stdout" "current nao deve casar"; return 1; }
}

scenario_nome_invalido_exit_2() {
  _lf_setup || return 2
  for _bad in '..' '../x' 'a/b' 'a b' 'A' 'a;b' '$x' '-x' ''; do
    _lf_run --name "$_bad"
    _lf_exit 2 || { printf '  nome: %s\n' "$_bad"; return 1; }
  done
}

scenario_docs_specs_ausente_exit_1() {
  _lf_setup || return 2
  rm -rf "$_LF_DIR/docs/specs"
  _lf_run --all
  _lf_exit 1 || return 1
  assert_stderr_contains "docs/specs/ ausente" || return 1
}

scenario_uso_incorreto_exit_2() {
  _lf_setup || return 2
  _lf_run
  _lf_exit 2 || return 1
  _lf_run --all --name alpha
  _lf_exit 2 || return 1
  capture sh "$SCRIPT" --name alpha
  _lf_exit 2 || return 1
}

scenario_all_em_projeto_sem_features() {
  _lf_setup || return 2
  rm -rf "$_LF_DIR/docs/specs"; mkdir -p "$_LF_DIR/docs/specs"
  _lf_run --all
  _lf_exit 0 || return 1
  [ -z "$_CAPTURED_STDOUT" ] || { _fail "stdout" "esperado vazio"; return 1; }
}

scenario_sem_bashismos() {
  if command -v checkbashisms >/dev/null 2>&1; then
    capture checkbashisms "$SCRIPT"
    _lf_exit 0 || return 1
  fi
  capture sh -n "$SCRIPT"
  _lf_exit 0 || return 1
  if command -v dash >/dev/null 2>&1; then
    capture dash -n "$SCRIPT"
    _lf_exit 0 || return 1
  fi
}

run_all_scenarios
