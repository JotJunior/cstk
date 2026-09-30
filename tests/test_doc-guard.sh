#!/bin/sh
# test_doc-guard.sh — cobre
# plugins/cstk/skills/reconcile-docs/scripts/doc-guard.sh (guarda fail-closed).
#
# Ref: docs/specs/code-reconciliation/quickstart.md Scenario 8
#      docs/specs/code-reconciliation/contracts/cli-invocation.md §4

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"
. "$TESTS_ROOT/lib/harness.sh"
. "$TESTS_ROOT/lib/reconcile-fixture.sh"

SCRIPT="$REPO_ROOT/plugins/cstk/skills/reconcile-docs/scripts/doc-guard.sh"
FEAT=docs/specs/alpha

_dg_setup() {
  _DG_DIR=$(rd_make_fixture nogit) || return 2
  trap 'rm -rf "$_DG_DIR"; _cleanup_tmpdir' EXIT INT TERM
}

# _dg_check FEATURE_DIR PATH
_dg_check() { capture sh "$SCRIPT" check --root "$_DG_DIR" --feature-dir "$1" "$2"; }

_dg_expect() { # exit reason
  [ "$_CAPTURED_EXIT" = "$1" ] || { _fail "exit" "esperado $1, obtido $_CAPTURED_EXIT"; return 1; }
  [ -z "${2:-}" ] || assert_stderr_contains "$2"
}

scenario_corpus_canonico_negado() {
  _dg_setup || return 2
  _dg_check "$FEAT" docs/specs/current/x.md
  _dg_expect 1 living-corpus || return 1
}

scenario_tasks_md_nao_esta_na_allowlist() {
  _dg_setup || return 2
  _dg_check "$FEAT" "$FEAT/tasks.md"
  _dg_expect 1 not-in-allowlist || return 1
}

scenario_research_md_nao_esta_na_allowlist() {
  _dg_setup || return 2
  _dg_check "$FEAT" "$FEAT/research.md"
  _dg_expect 1 not-in-allowlist || return 1
}

scenario_checklists_fora_da_allowlist() {
  _dg_setup || return 2
  mkdir -p "$_DG_DIR/$FEAT/checklists"; : > "$_DG_DIR/$FEAT/checklists/requirements.md"
  _dg_check "$FEAT" "$FEAT/checklists/requirements.md"
  _dg_expect 1 not-in-allowlist || return 1
}

scenario_codigo_fora_da_feature_negado() {
  _dg_setup || return 2
  _dg_check "$FEAT" cli/lib/foo.sh
  _dg_expect 1 outside-feature || return 1
}

scenario_traversal_negado() {
  _dg_setup || return 2
  _dg_check "$FEAT" "$FEAT/../../../cli/lib/foo.sh"
  _dg_expect 1 outside-feature || return 1
}

scenario_simlink_negado_independente_do_alvo() {
  _dg_setup || return 2
  rm -f "$_DG_DIR/$FEAT/plan.md"
  ln -s ../../../cli/lib/foo.sh "$_DG_DIR/$FEAT/plan.md"
  _dg_check "$FEAT" "$FEAT/plan.md"
  _dg_expect 1 symlink-escape || return 1
  # simlink apontando para outro documento permitido da feature tambem e negado
  rm -f "$_DG_DIR/$FEAT/plan.md"
  ln -s spec.md "$_DG_DIR/$FEAT/plan.md"
  _dg_check "$FEAT" "$FEAT/plan.md"
  _dg_expect 1 symlink-escape || return 1
}

scenario_diretorio_pai_simlink_para_fora_negado() {
  _dg_setup || return 2
  rm -rf "$_DG_DIR/$FEAT/contracts"
  ln -s ../../../cli/lib "$_DG_DIR/$FEAT/contracts"
  _dg_check "$FEAT" "$FEAT/contracts/foo.md"
  _dg_expect 1 outside-feature || return 1
}

scenario_documentos_da_allowlist_permitidos() {
  _dg_setup || return 2
  for _f in spec.md plan.md data-model.md quickstart.md reconciliation.md contracts/api.md; do
    _dg_check "$FEAT" "$FEAT/$_f"
    _dg_expect 0 || { printf '  doc: %s\n' "$_f"; return 1; }
  done
}

scenario_caminho_absoluto_permitido() {
  _dg_setup || return 2
  _abs=$(cd "$_DG_DIR" && pwd -P)
  _dg_check "$FEAT" "$_abs/$FEAT/spec.md"
  _dg_expect 0 || return 1
}

scenario_contracts_so_um_nivel() {
  _dg_setup || return 2
  mkdir -p "$_DG_DIR/$FEAT/contracts/sub"
  _dg_check "$FEAT" "$FEAT/contracts/sub/x.md"
  _dg_expect 1 || return 1
  _dg_check "$FEAT" "$FEAT/contracts/api.txt"
  _dg_expect 1 not-in-allowlist || return 1
}

scenario_feature_arquivada_permitida() {
  _dg_setup || return 2
  _dg_check docs/specs/_archived/gamma docs/specs/_archived/gamma/spec.md
  _dg_expect 0 || return 1
  _dg_check docs/specs/_archived/2026-01-15-beta docs/specs/_archived/2026-01-15-beta/spec.md
  _dg_expect 0 || return 1
}

scenario_feature_dir_sob_current_sempre_exit_1() {
  _dg_setup || return 2
  _dg_check docs/specs/current docs/specs/current/alpha.md
  _dg_expect 1 living-corpus || return 1
  _dg_check docs/specs/current docs/specs/alpha/spec.md
  _dg_expect 1 living-corpus || return 1
  mkdir -p "$_DG_DIR/docs/specs/current/sub"
  _dg_check docs/specs/current/sub docs/specs/current/sub/spec.md
  _dg_expect 1 living-corpus || return 1
}

scenario_feature_dir_invalido_negado() {
  _dg_setup || return 2
  _dg_check docs/specs docs/specs/spec.md
  _dg_expect 1 outside-feature || return 1
  _dg_check docs/specs/_archived docs/specs/_archived/spec.md
  _dg_expect 1 outside-feature || return 1
  _dg_check cli/lib cli/lib/foo.sh
  _dg_expect 1 outside-feature || return 1
  _dg_check docs/specs/inexistente docs/specs/inexistente/spec.md
  _dg_expect 1 outside-feature || return 1
}

scenario_argumentos_ausentes_exit_2() {
  _dg_setup || return 2
  capture sh "$SCRIPT"
  _dg_expect 2 || return 1
  capture sh "$SCRIPT" check --root "$_DG_DIR"
  _dg_expect 2 || return 1
  capture sh "$SCRIPT" check --root "$_DG_DIR" --feature-dir "$FEAT"
  _dg_expect 2 || return 1
  capture sh "$SCRIPT" check --feature-dir "$FEAT" "$FEAT/spec.md"
  _dg_expect 2 || return 1
  capture sh "$SCRIPT" nope --root "$_DG_DIR" --feature-dir "$FEAT" "$FEAT/spec.md"
  _dg_expect 2 || return 1
}

scenario_fail_closed_raiz_inexistente() {
  _dg_setup || return 2
  capture sh "$SCRIPT" check --root "$_DG_DIR/nao-existe" --feature-dir "$FEAT" "$FEAT/spec.md"
  [ "$_CAPTURED_EXIT" != 0 ] || { _fail "fail-closed" "raiz inexistente nao pode dar exit 0"; return 1; }
}

scenario_fail_closed_diretorio_pai_inexistente() {
  _dg_setup || return 2
  _dg_check "$FEAT" "$FEAT/contracts/novo/api.md"
  [ "$_CAPTURED_EXIT" != 0 ] || { _fail "fail-closed" "pai inexistente nao pode dar exit 0"; return 1; }
}

scenario_nao_escreve_nada() {
  _dg_setup || return 2
  _before=$(cd "$_DG_DIR" && find . -type f | LC_ALL=C sort | cksum)
  _dg_check "$FEAT" "$FEAT/reconciliation.md"
  _after=$(cd "$_DG_DIR" && find . -type f | LC_ALL=C sort | cksum)
  [ "$_before" = "$_after" ] || { _fail "side-effect" "check nao pode criar arquivos"; return 1; }
}

run_all_scenarios
