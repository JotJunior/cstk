#!/bin/sh
# test_metrics.sh — cobre plugins/cstk/skills/review-task/scripts/metrics.sh.
# Inclui regressao explicita do bug historico (grep -c sem matches).
#
# NOTA: deliberadamente NAO usamos 'set -eu' — o harness sinaliza falha via
# return codes. Scenarios usam '|| return 1' apos cada assert.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/plugins/cstk/skills/review-task/scripts/metrics.sh"

# ==== 3.1.1 tasks.md vazio ====

scenario_tasks_md_vazio() {
  fixture "tasks-md" || return 2
  assert_exit 0 sh "$SCRIPT" "$TMPDIR_TEST/empty.md" || return 1
  assert_stdout_contains "Nenhuma subtarefa" || return 1
}

# ==== 3.1.2 apenas pendentes (reproduz bug historico) ====

scenario_apenas_pendentes() {
  fixture "tasks-md" || return 2
  assert_exit 0 sh "$SCRIPT" "$TMPDIR_TEST/only-pending.md" || return 1
  assert_stdout_contains '"pct_done":0' || return 1
  assert_stdout_contains '"pending":5' || return 1
  assert_stdout_contains '"done":0' || return 1
}

# ==== 3.1.3 apenas concluidas ====

scenario_apenas_concluidas() {
  fixture "tasks-md" || return 2
  assert_exit 0 sh "$SCRIPT" "$TMPDIR_TEST/only-done.md" || return 1
  assert_stdout_contains '"pct_done":100' || return 1
  assert_stdout_contains '"done":5' || return 1
  assert_stdout_contains '"pending":0' || return 1
}

# ==== 3.1.4 mixed — contagens exatas ====

scenario_mixed() {
  fixture "tasks-md" || return 2
  assert_exit 0 sh "$SCRIPT" "$TMPDIR_TEST/mixed.md" || return 1
  # Proporcoes conhecidas do fixture: 4P/3D/2I/1B, 10 total, 30% done.
  assert_stdout_contains '"pending":4' || return 1
  assert_stdout_contains '"done":3' || return 1
  assert_stdout_contains '"in_progress":2' || return 1
  assert_stdout_contains '"blocked":1' || return 1
  assert_stdout_contains '"subtasks":10' || return 1
  assert_stdout_contains '"pct_done":30' || return 1
  # Estrutura: 2 fases, 3 tarefas, 1 critico, 1 alto, 1 medio.
  assert_stdout_contains '"phases":2' || return 1
  assert_stdout_contains '"tasks":3' || return 1
  assert_stdout_contains '"critical":1' || return 1
}

# ==== 3.1.5 JSON output valido (presenca de todos os campos) ====

scenario_json_output_valido() {
  fixture "tasks-md" || return 2
  capture sh "$SCRIPT" "$TMPDIR_TEST/with-phases-tasks.md" || return 2
  if [ "$_CAPTURED_EXIT" -ne 0 ]; then
    _fail "scenario_json" "exit nao-zero: $_CAPTURED_EXIT"
    return 1
  fi
  # Extrai a linha JSON (comeca com '{')
  _json=$(printf '%s\n' "$_CAPTURED_STDOUT" | grep -E '^\{')
  if [ -z "$_json" ]; then
    _fail "scenario_json" "linha JSON ausente no stdout"
    return 1
  fi
  # Valida presenca de todos os campos documentados (pareamento de chaves).
  for _field in file phases tasks subtasks done in_progress pending blocked pct_done critical high medium; do
    case "$_json" in
      *"\"$_field\":"*) ;;
      *) _fail "scenario_json" "campo '$_field' ausente no JSON"; return 1 ;;
    esac
  done
}

# ==== 3.1.6 arquivo inexistente ====

scenario_arquivo_inexistente() {
  assert_exit 1 sh "$SCRIPT" "/caminho/que-nao/existe.md" || return 1
  assert_stderr_contains "nao encontrado" || return 1
}

# ==== 3.1.7 sem argumento ====

scenario_sem_argumento() {
  assert_exit 2 sh "$SCRIPT" || return 1
  assert_stderr_contains "Uso:" || return 1
}

# ==== 3.1.8 regressao dedicada — zero "syntax error" em stderr ====
#
# Este scenario existe especificamente para detectar o retorno do bug
# historico. Se o padrao antigo `|| printf '0'` voltar ao metrics.sh, o
# stderr conteria "syntax error in expression" em qualquer fixture sem
# matches de algum tipo de checkbox. Testamos tres fixtures criticos:
# empty (zero de tudo), only-pending (zero [x], [~], [!]), only-done
# (zero [ ], [~], [!]).

scenario_regressao_bug_grep_c_sem_matches() {
  fixture "tasks-md" || return 2

  for _fx in empty.md only-pending.md only-done.md; do
    capture sh "$SCRIPT" "$TMPDIR_TEST/$_fx" || return 2
    case "$_CAPTURED_STDERR" in
      *"syntax error"*)
        _fail "scenario_regressao" "stderr do fixture '$_fx' contem 'syntax error' — bug grep -c voltou"
        return 1
        ;;
      *"unbound variable"*)
        _fail "scenario_regressao" "stderr do fixture '$_fx' contem 'unbound variable' — regressao de set -eu"
        return 1
        ;;
    esac
  done
}

run_all_scenarios
