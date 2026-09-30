#!/bin/sh
# test_extract-anchors.sh — cobre
# plugins/cstk/skills/reconcile-docs/scripts/extract-anchors.sh.
#
# Ref: docs/specs/code-reconciliation/contracts/cli-invocation.md §3
#      docs/specs/code-reconciliation/data-model.md §Anchor

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"
. "$TESTS_ROOT/lib/harness.sh"
. "$TESTS_ROOT/lib/reconcile-fixture.sh"

SCRIPT="$REPO_ROOT/plugins/cstk/skills/reconcile-docs/scripts/extract-anchors.sh"
TAB=$(printf '\t')

_ea_setup() {
  _EA_DIR=$(rd_make_fixture nogit) || return 2
  trap 'rm -rf "$_EA_DIR"; _cleanup_tmpdir' EXIT INT TERM
}

_ea_run() { capture sh "$SCRIPT" --root "$_EA_DIR" --feature-dir "$1"; }

_ea_exit() { [ "$_CAPTURED_EXIT" = "$1" ] || { _fail "exit" "esperado $1, obtido $_CAPTURED_EXIT"; return 1; }; }

scenario_ancora_absent_do_arquivo_removido() {
  _ea_setup || return 2
  _ea_run docs/specs/alpha
  _ea_exit 0 || return 1
  assert_stdout_contains "path${TAB}cli/lib/legacy.sh${TAB}spec.md:8${TAB}absent" || return 1
}

scenario_ancora_present_de_arquivo_existente() {
  _ea_setup || return 2
  _ea_run docs/specs/alpha
  assert_stdout_contains "path${TAB}cli/lib/run.sh${TAB}spec.md:9${TAB}present" || return 1
  assert_stdout_contains "path${TAB}cli/lib/config.sh${TAB}spec.md:7${TAB}present" || return 1
}

scenario_flags_comandos_e_req_ids() {
  _ea_setup || return 2
  _ea_run docs/specs/alpha
  assert_stdout_contains "flag${TAB}--limit${TAB}spec.md:7${TAB}n/a" || return 1
  assert_stdout_contains "command${TAB}sh${TAB}quickstart.md:3${TAB}n/a" || return 1
  assert_stdout_contains "req-id${TAB}FR-001${TAB}plan.md:4${TAB}n/a" || return 1
  assert_stdout_contains "req-id${TAB}FR-003${TAB}plan.md:4${TAB}n/a" || return 1
}

scenario_presence_so_para_path() {
  _ea_setup || return 2
  _ea_run docs/specs/alpha
  printf '%s\n' "$_CAPTURED_STDOUT" | awk -F "$TAB" '$1 != "path" && $4 != "n/a" { bad = 1 } END { exit bad }' \
    || { _fail "presence" "kind != path com presence != n/a"; return 1; }
}

scenario_documentos_fora_da_allowlist_ignorados() {
  _ea_setup || return 2
  printf 'Cita `cli/lib/so-no-research.sh` e `cli/lib/so-em-tasks.sh`.\n' >> "$_EA_DIR/docs/specs/alpha/research.md"
  printf 'Cita `cli/lib/so-em-tasks.sh`.\n' >> "$_EA_DIR/docs/specs/alpha/tasks.md"
  _ea_run docs/specs/alpha
  assert_stdout_not_contains "so-no-research" || return 1
  assert_stdout_not_contains "so-em-tasks" || return 1
  assert_stdout_not_contains "research.md:" || return 1
}

scenario_ignora_cercas_de_codigo() {
  _ea_setup || return 2
  _ea_run docs/specs/alpha
  assert_stdout_not_contains "ignorado.sh" || return 1
  assert_stdout_not_contains "dentro-de-cerca" || return 1
}

scenario_contracts_incluidos() {
  _ea_setup || return 2
  _ea_run docs/specs/alpha
  assert_stdout_contains "flag${TAB}--limit${TAB}contracts/api.md:3${TAB}n/a" || return 1
}

scenario_dedupe_preserva_ordem() {
  _ea_setup || return 2
  printf -- '- `cli/lib/x.sh` e `cli/lib/x.sh` e `cli/lib/y.sh`\n' >> "$_EA_DIR/docs/specs/alpha/spec.md"
  _ea_run docs/specs/alpha
  _n=$(printf '%s\n' "$_CAPTURED_STDOUT" | grep -c "cli/lib/x.sh${TAB}spec.md:11")
  [ "$_n" = 1 ] || { _fail "dedupe" "esperado 1 ocorrencia, obtido $_n"; return 1; }
  _x=$(printf '%s\n' "$_CAPTURED_STDOUT" | grep -n "cli/lib/x.sh" | cut -d: -f1)
  _y=$(printf '%s\n' "$_CAPTURED_STDOUT" | grep -n "cli/lib/y.sh" | cut -d: -f1)
  [ "$_x" -lt "$_y" ] || { _fail "ordem" "x deveria vir antes de y"; return 1; }
}

scenario_feature_so_com_plan() {
  _ea_setup || return 2
  _ea_run docs/specs/epsilon
  _ea_exit 0 || return 1
  assert_stdout_contains "path${TAB}cli/lib/run.sh${TAB}plan.md:3${TAB}present" || return 1
}

scenario_feature_sem_documentos_exit_0_vazio() {
  _ea_setup || return 2
  mkdir -p "$_EA_DIR/docs/specs/vazia"
  _ea_run docs/specs/vazia
  _ea_exit 0 || return 1
  [ -z "$_CAPTURED_STDOUT" ] || { _fail "stdout" "esperado vazio"; return 1; }
}

scenario_feature_dir_inexistente_exit_1() {
  _ea_setup || return 2
  _ea_run docs/specs/nao-existe
  _ea_exit 1 || return 1
}

scenario_uso_incorreto_exit_2() {
  _ea_setup || return 2
  capture sh "$SCRIPT"
  _ea_exit 2 || return 1
  capture sh "$SCRIPT" --root "$_EA_DIR"
  _ea_exit 2 || return 1
  capture sh "$SCRIPT" --feature-dir docs/specs/alpha
  _ea_exit 2 || return 1
}

scenario_nao_escreve_nada() {
  _ea_setup || return 2
  _b=$(cd "$_EA_DIR" && find . -type f | LC_ALL=C sort | cksum)
  _ea_run docs/specs/alpha
  _a=$(cd "$_EA_DIR" && find . -type f | LC_ALL=C sort | cksum)
  [ "$_a" = "$_b" ] || { _fail "side-effect" "script criou arquivos"; return 1; }
}

# 3.1.5 — desempenho sobre ESTE repositorio (ativas + arquivadas). O relatorio
# de teste registra o total (linha de comentario) e falha se qualquer feature
# passar de 2 s (limite do plan §Performance Goals).
scenario_desempenho_menor_que_2s_por_feature_no_repositorio() {
  _specs="$REPO_ROOT/docs/specs"
  [ -d "$_specs" ] || return 0
  _t0=$(date +%s); _n=0
  for _d in "$_specs"/*/ "$_specs"/_archived/*/; do
    [ -d "$_d" ] || continue
    _d=${_d%/}
    case "${_d##*/}" in current | _archived) continue ;; esac
    _s=$(date +%s)
    capture sh "$SCRIPT" --root "$REPO_ROOT" --feature-dir "$_d"
    _e=$(date +%s)
    [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "falhou em $_d"; return 1; }
    [ $((_e - _s)) -lt 2 ] || { _fail "tempo" "$_d levou $((_e - _s))s (>= 2s)"; return 1; }
    _n=$((_n + 1))
  done
  printf '# extract-anchors: %s features do repositorio em %ss (limite 2s por feature)\n' "$_n" "$(( $(date +%s) - _t0 ))"
}

scenario_sem_bashismos() {
  capture sh -n "$SCRIPT"
  _ea_exit 0 || return 1
  if command -v dash >/dev/null 2>&1; then capture dash -n "$SCRIPT"; _ea_exit 0 || return 1; fi
  if command -v checkbashisms >/dev/null 2>&1; then capture checkbashisms "$SCRIPT"; _ea_exit 0 || return 1; fi
}

run_all_scenarios
