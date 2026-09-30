#!/bin/sh
# test_orchestrator-refs.sh — testes de orchestrator-refs.sh (path e list)
#
# Ref: docs/specs/orchestrator-slim/contracts/orchestrator-refs-cli.md
#      docs/specs/orchestrator-slim/spec.md FR-008, FR-009, FR-010
#      docs/specs/orchestrator-slim/quickstart.md Cenario 4
#
# Cobre: fase inexistente (exit 1, stdout vazio), phase/orchestrator invalidos
# (exit 2, inclusive `../`), symlink para fora (exit 1), resolucao a partir de
# copia do skill dir (ancora irma vence variavel de ambiente), copia `cp -R`
# sob HOME temporario, `list` ordenado/filtrado, e o vinculo FR-009 (todo
# marcador ORCH-REF dos prompts-base resolve no subtree do repositorio).

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

RUNTIME_SRC="$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime"
REFS_SCRIPT="$RUNTIME_SRC/scripts/orchestrator-refs.sh"

# _mk_runtime <dest>: skill dir minimo (scripts/ + helper de raiz), referencias vazias.
_mk_runtime() {
  mkdir -p "$1/scripts" "$1/references/orchestrators/root" "$1/references/orchestrators/feature"
  cp "$RUNTIME_SRC/scripts/orchestrator-refs.sh" "$RUNTIME_SRC/scripts/_resolve-root.sh" "$1/scripts/"
}

# _run <script> <args...>: executa isolando o ambiente de resolucao.
_run() {
  _run_script="$1"; shift
  env -u CLAUDE_PLUGIN_ROOT sh "$_run_script" "$@"
}

# ==== Uso incorreto (exit 2) ====

scenario_sem_subcomando_exit_2() {
  assert_exit 2 sh "$REFS_SCRIPT" || return 1
}

scenario_subcomando_desconhecido_exit_2() {
  assert_exit 2 sh "$REFS_SCRIPT" frobnicate || return 1
}

scenario_path_sem_flags_exit_2() {
  assert_exit 2 sh "$REFS_SCRIPT" path || return 1
  assert_exit 2 sh "$REFS_SCRIPT" path --orchestrator root || return 1
  assert_exit 2 sh "$REFS_SCRIPT" path --phase clarify || return 1
}

scenario_orchestrator_fora_do_enum_exit_2() {
  assert_exit 2 sh "$REFS_SCRIPT" path --orchestrator agente --phase clarify || return 1
  assert_exit 2 sh "$REFS_SCRIPT" list --orchestrator agente || return 1
}

scenario_phase_com_traversal_ou_caractere_invalido_exit_2() {
  for _p in '../x' '..' 'a/b' 'a.b' 'a b' 'Clarify' '' '-x/../y'; do
    assert_exit 2 sh "$REFS_SCRIPT" path --orchestrator root --phase "$_p" || return 1
    [ -z "$_CAPTURED_STDOUT" ] || { _fail "stdout deveria ser vazio" "phase='$_p'"; return 1; }
  done
}

# ==== Fase inexistente / confinamento (exit 1) ====

scenario_fase_inexistente_exit_1_stdout_vazio() {
  mktemp_test || return 2
  _mk_runtime "$TMPDIR_TEST/rt"
  assert_exit 1 _run "$TMPDIR_TEST/rt/scripts/orchestrator-refs.sh" path --orchestrator root --phase nao-existe || return 1
  [ -z "$_CAPTURED_STDOUT" ] || { _fail "stdout deveria ser vazio" "$_CAPTURED_STDOUT"; return 1; }
}

scenario_symlink_para_fora_exit_1() {
  mktemp_test || return 2
  _mk_runtime "$TMPDIR_TEST/rt"
  printf 'conteudo de fora\n' > "$TMPDIR_TEST/fora.md"
  ln -s "$TMPDIR_TEST/fora.md" "$TMPDIR_TEST/rt/references/orchestrators/root/clarify.md"
  assert_exit 1 _run "$TMPDIR_TEST/rt/scripts/orchestrator-refs.sh" path --orchestrator root --phase clarify || return 1
  [ -z "$_CAPTURED_STDOUT" ] || { _fail "stdout deveria ser vazio" "$_CAPTURED_STDOUT"; return 1; }
}

scenario_diretorio_de_orquestrador_symlink_para_fora_exit_1() {
  mktemp_test || return 2
  _mk_runtime "$TMPDIR_TEST/rt"
  mkdir -p "$TMPDIR_TEST/outside"
  printf 'x\n' > "$TMPDIR_TEST/outside/clarify.md"
  rm -rf "$TMPDIR_TEST/rt/references/orchestrators/root"
  ln -s "$TMPDIR_TEST/outside" "$TMPDIR_TEST/rt/references/orchestrators/root"
  assert_exit 1 _run "$TMPDIR_TEST/rt/scripts/orchestrator-refs.sh" path --orchestrator root --phase clarify || return 1
  [ -z "$_CAPTURED_STDOUT" ] || { _fail "stdout deveria ser vazio" "$_CAPTURED_STDOUT"; return 1; }
}

# ==== Resolucao (exit 0) ====

scenario_resolve_a_partir_de_copia_do_skill_dir() {
  mktemp_test || return 2
  _mk_runtime "$TMPDIR_TEST/rt"
  printf 'ref\n' > "$TMPDIR_TEST/rt/references/orchestrators/feature/clarify.md"
  assert_exit 0 _run "$TMPDIR_TEST/rt/scripts/orchestrator-refs.sh" path --orchestrator feature --phase clarify || return 1
  _real=$(cd "$TMPDIR_TEST/rt" && pwd)
  [ "$_CAPTURED_STDOUT" = "$_real/references/orchestrators/feature/clarify.md" ] \
    || { _fail "path resolvido" "esperado $_real/references/orchestrators/feature/clarify.md, obtido $_CAPTURED_STDOUT"; return 1; }
}

scenario_ancora_irma_vence_claude_plugin_root() {
  mktemp_test || return 2
  _mk_runtime "$TMPDIR_TEST/rt"
  printf 'sibling\n' > "$TMPDIR_TEST/rt/references/orchestrators/root/plan.md"
  _mk_runtime "$TMPDIR_TEST/plug/skills/agente-00c-runtime"
  printf 'plugin\n' > "$TMPDIR_TEST/plug/skills/agente-00c-runtime/references/orchestrators/root/plan.md"
  capture env CLAUDE_PLUGIN_ROOT="$TMPDIR_TEST/plug" sh "$TMPDIR_TEST/rt/scripts/orchestrator-refs.sh" path --orchestrator root --phase plan
  [ "$_CAPTURED_EXIT" -eq 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  _real=$(cd "$TMPDIR_TEST/rt" && pwd)
  [ "$_CAPTURED_STDOUT" = "$_real/references/orchestrators/root/plan.md" ] \
    || { _fail "ancora irma" "resolveu $_CAPTURED_STDOUT em vez do irmao"; return 1; }
}

scenario_copia_cp_r_em_home_temporario() {
  mktemp_test || return 2
  mkdir -p "$TMPDIR_TEST/home/.claude/skills"
  cp -R "$RUNTIME_SRC" "$TMPDIR_TEST/home/.claude/skills/agente-00c-runtime"
  mkdir -p "$TMPDIR_TEST/home/.claude/skills/agente-00c-runtime/references/orchestrators/root"
  printf 'ref\n' > "$TMPDIR_TEST/home/.claude/skills/agente-00c-runtime/references/orchestrators/root/specify.md"
  _copy="$TMPDIR_TEST/home/.claude/skills/agente-00c-runtime/scripts/orchestrator-refs.sh"
  capture env -u CLAUDE_PLUGIN_ROOT HOME="$TMPDIR_TEST/home" sh "$_copy" path --orchestrator root --phase specify
  [ "$_CAPTURED_EXIT" -eq 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  _real=$(cd "$TMPDIR_TEST/home/.claude/skills/agente-00c-runtime" && pwd)
  [ "$_CAPTURED_STDOUT" = "$_real/references/orchestrators/root/specify.md" ] \
    || { _fail "path na copia" "obtido $_CAPTURED_STDOUT"; return 1; }
  # error case (Cenario 4): apagar a referencia na copia => exit 1, stdout vazio
  rm -f "$TMPDIR_TEST/home/.claude/skills/agente-00c-runtime/references/orchestrators/root/specify.md"
  capture env -u CLAUDE_PLUGIN_ROOT HOME="$TMPDIR_TEST/home" sh "$_copy" path --orchestrator root --phase specify
  [ "$_CAPTURED_EXIT" -eq 1 ] || { _fail "exit apos remover" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
  [ -z "$_CAPTURED_STDOUT" ] || { _fail "stdout deveria ser vazio" "$_CAPTURED_STDOUT"; return 1; }
}

# ==== list ====

scenario_list_ordenado_e_filtrado() {
  mktemp_test || return 2
  _mk_runtime "$TMPDIR_TEST/rt"
  _r="$TMPDIR_TEST/rt/references/orchestrators"
  printf 'x\n' > "$_r/root/plan.md"
  printf 'x\n' > "$_r/root/clarify.md"
  printf 'x\n' > "$_r/feature/specify.md"
  printf 'x\n' > "$_r/root/README.txt"
  assert_exit 0 _run "$TMPDIR_TEST/rt/scripts/orchestrator-refs.sh" list || return 1
  _real=$(cd "$TMPDIR_TEST/rt" && pwd)
  _exp=$(printf 'feature\tspecify\t%s/references/orchestrators/feature/specify.md\nroot\tclarify\t%s/references/orchestrators/root/clarify.md\nroot\tplan\t%s/references/orchestrators/root/plan.md' "$_real" "$_real" "$_real")
  [ "$_CAPTURED_STDOUT" = "$_exp" ] || { _fail "list" "saida inesperada"; return 1; }
  assert_exit 0 _run "$TMPDIR_TEST/rt/scripts/orchestrator-refs.sh" list --orchestrator feature || return 1
  _exp_f=$(printf 'feature\tspecify\t%s/references/orchestrators/feature/specify.md' "$_real")
  [ "$_CAPTURED_STDOUT" = "$_exp_f" ] || { _fail "list --orchestrator feature" "saida inesperada"; return 1; }
}

scenario_list_vazio_e_valido_exit_0() {
  mktemp_test || return 2
  _mk_runtime "$TMPDIR_TEST/rt"
  assert_exit 0 _run "$TMPDIR_TEST/rt/scripts/orchestrator-refs.sh" list || return 1
  [ -z "$_CAPTURED_STDOUT" ] || { _fail "list vazio" "$_CAPTURED_STDOUT"; return 1; }
}

scenario_list_sem_diretorio_de_referencias_exit_0() {
  mktemp_test || return 2
  mkdir -p "$TMPDIR_TEST/rt/scripts"
  cp "$RUNTIME_SRC/scripts/orchestrator-refs.sh" "$RUNTIME_SRC/scripts/_resolve-root.sh" "$TMPDIR_TEST/rt/scripts/"
  assert_exit 0 _run "$TMPDIR_TEST/rt/scripts/orchestrator-refs.sh" list || return 1
  assert_exit 1 _run "$TMPDIR_TEST/rt/scripts/orchestrator-refs.sh" path --orchestrator root --phase clarify || return 1
}

scenario_list_ignora_symlinks() {
  mktemp_test || return 2
  _mk_runtime "$TMPDIR_TEST/rt"
  printf 'x\n' > "$TMPDIR_TEST/fora.md"
  ln -s "$TMPDIR_TEST/fora.md" "$TMPDIR_TEST/rt/references/orchestrators/root/clarify.md"
  assert_exit 0 _run "$TMPDIR_TEST/rt/scripts/orchestrator-refs.sh" list || return 1
  [ -z "$_CAPTURED_STDOUT" ] || { _fail "list deveria ignorar symlink" "$_CAPTURED_STDOUT"; return 1; }
}

# ==== FR-009: todo marcador ORCH-REF dos prompts-base resolve no subtree ====

scenario_todo_marcador_orch_ref_resolve_no_subtree() {
  _n=0
  for _f in "$REPO_ROOT/plugins/cstk/agents/agente-00c-orchestrator.md" \
            "$REPO_ROOT/plugins/cstk/agents/agente-00c-feature-orchestrator.md"; do
    [ -f "$_f" ] || { _error "arquivo ausente" "$_f"; return 2; }
    _markers=$(grep -oE '<!-- ORCH-REF: (root|feature)/[a-z0-9-]+ -->' "$_f" | sed -e 's/<!-- ORCH-REF: //' -e 's/ -->//' | sort -u)
    for _m in $_markers; do
      _o=${_m%%/*}
      _p=${_m#*/}
      assert_exit 0 _run "$REFS_SCRIPT" path --orchestrator "$_o" --phase "$_p" || return 1
      _n=$((_n + 1))
    done
  done
  return 0
}

run_all_scenarios "$@"
