#!/bin/sh
# test_next-task-id.sh — cobre plugins/cstk/skills/create-tasks/scripts/next-task-id.sh.
#
# Contrato:
#   next-task-id.sh PREFIX FILE
#     PREFIX=<fase>         -> proxima tarefa (ex: 1.3)
#     PREFIX=<fase>.<tarefa> -> proxima subtarefa (ex: 1.2.4)
#     Prefix inexistente    -> {prefix}.1
#   Exit: 0 sucesso; 1 arquivo inexistente; 2 uso incorreto.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/plugins/cstk/skills/create-tasks/scripts/next-task-id.sh"

# ==== 3.2.1 proxima tarefa em fase existente ====

scenario_proxima_tarefa_em_fase_existente() {
  fixture "tasks-md" || return 2
  # mixed.md tem fase 1 com tarefas 1.1, 1.2 -> proxima = 1.3
  assert_exit 0 sh "$SCRIPT" "1" "$TMPDIR_TEST/mixed.md" || return 1
  assert_stdout_contains "1.3" || return 1
  # Fase 2 tem so 2.1 -> proxima = 2.2
  assert_exit 0 sh "$SCRIPT" "2" "$TMPDIR_TEST/mixed.md" || return 1
  assert_stdout_contains "2.2" || return 1
}

# ==== 3.2.2 proxima subtarefa ====

scenario_proxima_subtarefa() {
  fixture "tasks-md" || return 2
  # mixed.md tarefa 1.1 tem subtarefas 1.1.1 a 1.1.4 -> proxima = 1.1.5
  assert_exit 0 sh "$SCRIPT" "1.1" "$TMPDIR_TEST/mixed.md" || return 1
  assert_stdout_contains "1.1.5" || return 1
}

# ==== 3.2.3 prefix inexistente ====

scenario_prefix_inexistente() {
  fixture "tasks-md" || return 2
  # Fase 9 nao existe -> deve retornar 9.1
  assert_exit 0 sh "$SCRIPT" "9" "$TMPDIR_TEST/mixed.md" || return 1
  assert_stdout_contains "9.1" || return 1
  # Tambem: prefix 1.99 nao existe -> 1.99.1
  assert_exit 0 sh "$SCRIPT" "1.99" "$TMPDIR_TEST/mixed.md" || return 1
  assert_stdout_contains "1.99.1" || return 1
}

# ==== 3.2.4 sem argumentos ====

scenario_sem_argumentos() {
  assert_exit 2 sh "$SCRIPT" || return 1
  assert_stderr_contains "Uso:" || return 1
}

# ==== 3.2.5 arquivo inexistente ====

scenario_arquivo_inexistente() {
  assert_exit 1 sh "$SCRIPT" "1" "/caminho/inexistente.md" || return 1
  assert_stderr_contains "nao encontrado" || return 1
}

run_all_scenarios
