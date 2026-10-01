#!/bin/sh
# test_reconciliation-log.sh — cobre
# plugins/cstk/skills/reconcile-docs/scripts/reconciliation-log.sh.
#
# Ref: docs/specs/code-reconciliation/contracts/cli-invocation.md §6; FR-018

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"
. "$TESTS_ROOT/lib/harness.sh"
. "$TESTS_ROOT/lib/reconcile-fixture.sh"

SCRIPT="$REPO_ROOT/plugins/cstk/skills/reconcile-docs/scripts/reconciliation-log.sh"

_rl_setup() {
  _RL_D=$(rd_make_fixture nogit) || return 2
  trap 'rm -rf "$_RL_D"; _cleanup_tmpdir' EXIT INT TERM
  _RL_F="$_RL_D/docs/specs/alpha"
  _RL_LOG="$_RL_F/reconciliation.md"
  printf 'Alteracoes: 1 updated, 1 removed\nDocumentos: spec.md\n' > "$_RL_D/sum.txt"
}

_rl() { capture sh "$SCRIPT" append --feature-dir "$_RL_F" --date "$1" --summary-file "${2:-$_RL_D/sum.txt}"; }
_rl_exit() { [ "$_CAPTURED_EXIT" = "$1" ] || { _fail "exit" "esperado $1, obtido $_CAPTURED_EXIT"; return 1; }; }

scenario_cria_com_cabecalho_e_primeira_entrada() {
  _rl_setup || return 2
  [ ! -e "$_RL_LOG" ] || return 2
  _rl 2026-10-02
  _rl_exit 0 || return 1
  head -n 1 "$_RL_LOG" | grep -q '^# Reconciliation log' || { _fail "cabecalho" "cabecalho ausente"; return 1; }
  grep -q '^## 2026-10-02$' "$_RL_LOG" || { _fail "entrada" "entrada ausente"; return 1; }
  grep -q 'Alteracoes: 1 updated' "$_RL_LOG" || { _fail "conteudo" "resumo ausente"; return 1; }
}

scenario_append_nao_edita_entradas_existentes() {
  _rl_setup || return 2
  _rl 2026-10-02; _rl_exit 0 || return 1
  _size1=$(wc -c < "$_RL_LOG" | tr -d ' ')
  cp "$_RL_LOG" "$_RL_D/before.md"
  printf 'Segunda entrada\n' > "$_RL_D/sum2.txt"
  _rl 2026-10-05 "$_RL_D/sum2.txt"; _rl_exit 0 || return 1
  # o conteudo anterior permanece byte a byte como prefixo
  _prefix=$(head -c "$_size1" "$_RL_LOG" | cksum)
  _orig=$(cksum < "$_RL_D/before.md")
  [ "$_prefix" = "$_orig" ] || { _fail "append-only" "entradas existentes foram alteradas"; return 1; }
  grep -q '^## 2026-10-05$' "$_RL_LOG" || { _fail "entrada" "nova entrada ausente"; return 1; }
  _n=$(grep -c '^## ' "$_RL_LOG")
  [ "$_n" = 2 ] || { _fail "entradas" "esperado 2 entradas, obtido $_n"; return 1; }
}

scenario_resumo_vazio_exit_3_sem_escrever() {
  _rl_setup || return 2
  : > "$_RL_D/empty.txt"
  _rl 2026-10-02 "$_RL_D/empty.txt"
  _rl_exit 3 || return 1
  [ ! -e "$_RL_LOG" ] || { _fail "escrita" "reconciliation.md nao deveria existir"; return 1; }
  printf '  \n\n' > "$_RL_D/blank.txt"
  _rl 2026-10-02 "$_RL_D/blank.txt"
  _rl_exit 3 || return 1
  [ ! -e "$_RL_LOG" ] || { _fail "escrita" "so espacos tambem nao grava"; return 1; }
}

scenario_resumo_vazio_nao_altera_log_existente() {
  _rl_setup || return 2
  _rl 2026-10-02; _rl_exit 0 || return 1
  _b=$(cksum < "$_RL_LOG")
  : > "$_RL_D/empty.txt"
  _rl 2026-10-03 "$_RL_D/empty.txt"; _rl_exit 3 || return 1
  [ "$_b" = "$(cksum < "$_RL_LOG")" ] || { _fail "escrita" "log alterado com resumo vazio"; return 1; }
}

scenario_destino_negado_pelo_guarda_exit_1() {
  _rl_setup || return 2
  capture sh "$SCRIPT" append --feature-dir "$_RL_D/docs/specs/current" --date 2026-10-02 --summary-file "$_RL_D/sum.txt"
  _rl_exit 1 || return 1
  [ ! -e "$_RL_D/docs/specs/current/reconciliation.md" ] || { _fail "escrita" "escreveu em current/"; return 1; }
  # simlink no destino
  ln -s ../../../cli/lib/foo.sh "$_RL_LOG"
  _rl 2026-10-02; _rl_exit 1 || return 1
  assert_stderr_contains "symlink-escape" || return 1
  [ "$(cat "$_RL_D/cli/lib/foo.sh")" = "#!/bin/sh
# foo.sh — alvo de escrita proibida nos testes do doc-guard.
printf 'foo\\n'" ] || { _fail "escrita" "arquivo apontado pelo simlink foi alterado"; return 1; }
}

scenario_fail_closed_sem_doc_guard() {
  _rl_setup || return 2
  _copy="$_RL_D/scripts-copy"; mkdir -p "$_copy"
  cp "$SCRIPT" "$_copy/reconciliation-log.sh"
  capture sh "$_copy/reconciliation-log.sh" append --feature-dir "$_RL_F" --date 2026-10-02 --summary-file "$_RL_D/sum.txt"
  _rl_exit 1 || return 1
  [ ! -e "$_RL_LOG" ] || { _fail "fail-closed" "escreveu sem guarda"; return 1; }
}

scenario_feature_arquivada_permitida() {
  _rl_setup || return 2
  capture sh "$SCRIPT" append --feature-dir "$_RL_D/docs/specs/_archived/gamma" --date 2026-10-02 --summary-file "$_RL_D/sum.txt"
  _rl_exit 0 || return 1
  [ -f "$_RL_D/docs/specs/_archived/gamma/reconciliation.md" ] || { _fail "escrita" "log da arquivada ausente"; return 1; }
}

scenario_entradas_do_mesmo_dia_nao_colapsam() {
  _rl_setup || return 2
  _rl 2026-10-02; _rl 2026-10-02
  _n=$(grep -c '^## 2026-10-02$' "$_RL_LOG")
  [ "$_n" = 2 ] || { _fail "append" "esperado 2 entradas, obtido $_n"; return 1; }
}

scenario_data_invalida_e_uso_incorreto_exit_2() {
  _rl_setup || return 2
  _rl 2026-1-2; _rl_exit 2 || return 1
  _rl 'ontem'; _rl_exit 2 || return 1
  capture sh "$SCRIPT"; _rl_exit 2 || return 1
  capture sh "$SCRIPT" append --feature-dir "$_RL_F" --date 2026-10-02; _rl_exit 2 || return 1
  _rl 2026-10-02 "$_RL_D/nao-existe.txt"; _rl_exit 2 || return 1
  [ ! -e "$_RL_LOG" ] || { _fail "escrita" "nao deveria existir"; return 1; }
}

scenario_sem_bashismos() {
  capture sh -n "$SCRIPT"; _rl_exit 0 || return 1
  if command -v dash >/dev/null 2>&1; then capture dash -n "$SCRIPT"; _rl_exit 0 || return 1; fi
  if command -v checkbashisms >/dev/null 2>&1; then capture checkbashisms "$SCRIPT"; _rl_exit 0 || return 1; fi
}

run_all_scenarios
