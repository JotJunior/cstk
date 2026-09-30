#!/bin/sh
# test_markers.sh — cobre
# plugins/cstk/skills/reconcile-docs/scripts/markers.sh.
#
# Ref: docs/specs/code-reconciliation/contracts/markers.md
#      docs/specs/code-reconciliation/contracts/cli-invocation.md §5

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"
. "$TESTS_ROOT/lib/harness.sh"
. "$TESTS_ROOT/lib/reconcile-fixture.sh"

SCRIPT="$REPO_ROOT/plugins/cstk/skills/reconcile-docs/scripts/markers.sh"
TAB=$(printf '\t')

_mk_setup() {
  _MK_DIR=$(rd_make_fixture nogit) || return 2
  trap 'rm -rf "$_MK_DIR"; _cleanup_tmpdir' EXIT INT TERM
  cat > "$_MK_DIR/good.md" <<'DOC'
- **FR-004**: MUST `--foo`. [reconciled:removed 2026-10-02 evidence=absent:cli/lib/legacy.sh]
- **FR-006**: SHOULD algo. [reconciled:updated 2026-10-02 evidence=cli/lib/run.sh:3]
| FR-019 | novo comportamento | [reconciled:added 2026-10-02 evidence=cli/lib/config.sh:2] |
- Texto sem marcador.
DOC
}

_mk() { capture sh "$SCRIPT" "$@"; }
_mk_exit() { [ "$_CAPTURED_EXIT" = "$1" ] || { _fail "exit" "esperado $1, obtido $_CAPTURED_EXIT"; return 1; }; }

_mk_bad() { # linha mal formada -> lint exit 1 com a linha em stdout
  printf '%s\n' "$1" > "$_MK_DIR/bad.md"
  _mk lint "$_MK_DIR/bad.md"
  _mk_exit 1 || { printf '  linha: %s\n' "$1"; return 1; }
  assert_stdout_contains "1${TAB}" || return 1
}

scenario_lint_marcadores_validos_exit_0() {
  _mk_setup || return 2
  _mk lint "$_MK_DIR/good.md"
  _mk_exit 0 || return 1
  [ -z "$_CAPTURED_STDOUT" ] || { _fail "stdout" "esperado vazio"; return 1; }
}

scenario_lint_arquivo_sem_marcador_exit_0() {
  _mk_setup || return 2
  _mk lint "$_MK_DIR/docs/specs/alpha/spec.md"
  _mk_exit 0 || return 1
}

scenario_lint_kind_desconhecido() {
  _mk_setup || return 2
  _mk_bad '- x [reconciled:bogus 2026-10-02 evidence=a/b.sh:1]'
}

scenario_lint_evidencia_vazia() {
  _mk_setup || return 2
  _mk_bad '- x [reconciled:updated 2026-10-02 evidence=]'
}

scenario_lint_data_malformada() {
  _mk_setup || return 2
  _mk_bad '- x [reconciled:updated 2026-1-02 evidence=a/b.sh:1]' || return 1
  _mk_bad '- x [reconciled:updated 2026-13-02 evidence=a/b.sh:1]' || return 1
}

scenario_lint_sem_fechamento() {
  _mk_setup || return 2
  _mk_bad '- x [reconciled:updated 2026-10-02 evidence=a/b.sh:1'
}

scenario_lint_evidencia_com_espaco() {
  _mk_setup || return 2
  _mk_bad '- x [reconciled:updated 2026-10-02 evidence=a b.sh:1]'
}

scenario_lint_lista_a_linha_mal_formada() {
  _mk_setup || return 2
  printf '%s\n%s\n' '- ok [reconciled:added 2026-10-02 evidence=a/b.sh:1]' '- ruim [reconciled:nope 2026-10-02 evidence=a:1]' > "$_MK_DIR/two.md"
  _mk lint "$_MK_DIR/two.md"
  _mk_exit 1 || return 1
  assert_stdout_contains "2${TAB}- ruim" || return 1
  assert_stdout_not_contains "- ok" || return 1
}

scenario_lint_ignora_cercas_e_crases() {
  _mk_setup || return 2
  cat > "$_MK_DIR/doc.md" <<'DOC'
Sintaxe: `[reconciled:<kind> <date> evidence=<ref>]` e exemplo:

```
[reconciled:xxx]
```
DOC
  _mk lint "$_MK_DIR/doc.md"
  _mk_exit 0 || return 1
}

scenario_list_tsv() {
  _mk_setup || return 2
  _mk list "$_MK_DIR/good.md"
  _mk_exit 0 || return 1
  assert_stdout_contains "1${TAB}removed${TAB}2026-10-02${TAB}absent:cli/lib/legacy.sh" || return 1
  assert_stdout_contains "2${TAB}updated${TAB}2026-10-02${TAB}cli/lib/run.sh:3" || return 1
  assert_stdout_contains "3${TAB}added${TAB}2026-10-02${TAB}cli/lib/config.sh:2" || return 1
}

scenario_list_sem_marcadores_vazio() {
  _mk_setup || return 2
  _mk list "$_MK_DIR/docs/specs/alpha/spec.md"
  _mk_exit 0 || return 1
  [ -z "$_CAPTURED_STDOUT" ] || { _fail "stdout" "esperado vazio"; return 1; }
}

scenario_next_fr_maior_mais_um() {
  _mk_setup || return 2
  _mk next-fr "$_MK_DIR/docs/specs/alpha/spec.md"
  _mk_exit 0 || return 1
  [ "$_CAPTURED_STDOUT" = "FR-005" ] || { _fail "next-fr" "esperado FR-005"; return 1; }
}

scenario_next_fr_sem_fr_retorna_fr_001() {
  _mk_setup || return 2
  printf 'sem requisitos\n' > "$_MK_DIR/none.md"
  _mk next-fr "$_MK_DIR/none.md"
  _mk_exit 0 || return 1
  [ "$_CAPTURED_STDOUT" = "FR-001" ] || { _fail "next-fr" "esperado FR-001"; return 1; }
}

scenario_next_fr_tres_digitos_e_maior_nao_sequencial() {
  _mk_setup || return 2
  printf -- '- **FR-002**: a\n- **FR-018**: b\n- **FR-009**: c\n' > "$_MK_DIR/n.md"
  _mk next-fr "$_MK_DIR/n.md"
  [ "$_CAPTURED_STDOUT" = "FR-019" ] || { _fail "next-fr" "esperado FR-019"; return 1; }
}

scenario_verify_positivo() {
  _mk_setup || return 2
  _mk verify --root "$_MK_DIR" "$_MK_DIR/good.md"
  _mk_exit 0 || return 1
}

scenario_verify_missing_file() {
  _mk_setup || return 2
  printf '%s\n' '- x [reconciled:updated 2026-10-02 evidence=cli/lib/nao-existe.sh:1]' > "$_MK_DIR/v.md"
  _mk verify --root "$_MK_DIR" "$_MK_DIR/v.md"
  _mk_exit 1 || return 1
  assert_stdout_contains "1${TAB}cli/lib/nao-existe.sh:1${TAB}missing-file" || return 1
}

scenario_verify_line_out_of_range() {
  _mk_setup || return 2
  printf '%s\n' '- x [reconciled:updated 2026-10-02 evidence=cli/lib/config.sh:999]' \
                '- y [reconciled:updated 2026-10-02 evidence=cli/lib/config.sh:0]' > "$_MK_DIR/v.md"
  _mk verify --root "$_MK_DIR" "$_MK_DIR/v.md"
  _mk_exit 1 || return 1
  assert_stdout_contains "1${TAB}cli/lib/config.sh:999${TAB}line-out-of-range" || return 1
  assert_stdout_contains "2${TAB}cli/lib/config.sh:0${TAB}line-out-of-range" || return 1
}

scenario_verify_not_absent() {
  _mk_setup || return 2
  printf '%s\n' '- x [reconciled:removed 2026-10-02 evidence=absent:cli/lib/run.sh]' > "$_MK_DIR/v.md"
  _mk verify --root "$_MK_DIR" "$_MK_DIR/v.md"
  _mk_exit 1 || return 1
  assert_stdout_contains "1${TAB}absent:cli/lib/run.sh${TAB}not-absent" || return 1
}

scenario_verify_ultima_linha_valida_e_absent_valido() {
  _mk_setup || return 2
  _n=$(awk 'END { print NR }' "$_MK_DIR/cli/lib/config.sh")
  printf '%s\n' "- x [reconciled:updated 2026-10-02 evidence=cli/lib/config.sh:$_n]" > "$_MK_DIR/v.md"
  _mk verify --root "$_MK_DIR" "$_MK_DIR/v.md"
  _mk_exit 0 || return 1
}

scenario_verify_caminho_fora_da_raiz_nao_confere() {
  _mk_setup || return 2
  printf '%s\n' '- x [reconciled:updated 2026-10-02 evidence=../../etc/hosts:1]' > "$_MK_DIR/v.md"
  _mk verify --root "$_MK_DIR" "$_MK_DIR/v.md"
  _mk_exit 1 || return 1
  assert_stdout_contains "missing-file" || return 1
}

# 3.2.6 — idempotencia: reexecutar lint/list nao muda data, linha nem arquivo.
scenario_idempotencia_lint_e_list_nao_alteram_o_arquivo() {
  _mk_setup || return 2
  _b=$(cksum < "$_MK_DIR/good.md")
  _mk list "$_MK_DIR/good.md"; _l1=$_CAPTURED_STDOUT
  _mk lint "$_MK_DIR/good.md"; _mk_exit 0 || return 1
  _mk verify --root "$_MK_DIR" "$_MK_DIR/good.md"; _mk_exit 0 || return 1
  _mk list "$_MK_DIR/good.md"; _l2=$_CAPTURED_STDOUT
  _a=$(cksum < "$_MK_DIR/good.md")
  [ "$_b" = "$_a" ] || { _fail "idempotencia" "arquivo foi alterado"; return 1; }
  [ "$_l1" = "$_l2" ] || { _fail "idempotencia" "list mudou entre execucoes"; return 1; }
}

scenario_uso_incorreto_e_arquivo_inexistente_exit_2() {
  _mk_setup || return 2
  _mk; _mk_exit 2 || return 1
  _mk lint; _mk_exit 2 || return 1
  _mk nope x; _mk_exit 2 || return 1
  _mk lint "$_MK_DIR/nao-existe.md"; _mk_exit 2 || return 1
  _mk verify "$_MK_DIR/good.md"; _mk_exit 2 || return 1
  _mk next-fr "$_MK_DIR/nao-existe.md"; _mk_exit 2 || return 1
}

# 8.2 — arquivo presente mas ilegivel: fail-closed em TODOS os subcomandos
# (exit != 0 + diagnostico em stderr), nunca exit 0 (write-policy §2.3).
scenario_arquivo_ilegivel_falha_fechado() {
  _mk_setup || return 2
  printf '%s\n' '- x [reconciled:updated 2026-10-02 evidence=nao/existe.sh:9] [reconciled:oops' > "$_MK_DIR/unread.md"
  chmod 000 "$_MK_DIR/unread.md"
  if [ -r "$_MK_DIR/unread.md" ]; then
    chmod 644 "$_MK_DIR/unread.md"
    return 0 # executando como root: chmod 000 nao torna o arquivo ilegivel
  fi
  for _c in "lint" "list" "next-fr" "verify --root $_MK_DIR"; do
    # shellcheck disable=SC2086
    _mk $_c "$_MK_DIR/unread.md"
    if [ "$_CAPTURED_EXIT" = 0 ]; then
      chmod 644 "$_MK_DIR/unread.md"; _fail "exit" "$_c com arquivo ilegivel terminou com exit 0"; return 1
    fi
    assert_stderr_contains "ilegivel" || { chmod 644 "$_MK_DIR/unread.md"; return 1; }
  done
  chmod 644 "$_MK_DIR/unread.md"
}

scenario_sem_bashismos() {
  capture sh -n "$SCRIPT"
  _mk_exit 0 || return 1
  if command -v dash >/dev/null 2>&1; then capture dash -n "$SCRIPT"; _mk_exit 0 || return 1; fi
  if command -v checkbashisms >/dev/null 2>&1; then capture checkbashisms "$SCRIPT"; _mk_exit 0 || return 1; fi
}

run_all_scenarios
