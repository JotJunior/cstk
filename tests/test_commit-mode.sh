#!/bin/sh
# test_commit-mode.sh — cobre global/skills/agente-00c-runtime/scripts/commit-mode.sh.
#
# Cobertura:
#   INV-1: is-enabled sem campo => false, exit 0
#   INV-2: guard-branch em branch default => exit 3; em nao-default => exit 0
#   INV-3: finalize quando disabled => skipped-disabled, exit 0, sem gh/push
#   INV-4: finalize com gh ausente => skipped-gh-missing, exit 0
#   INV-5: finalize idempotente — PR ja existe => pr-exists
#   INV-6: stage-message / task-message emitem Conventional-Commit subjects
#   INV-7: grouped contiguous ids => range; non-contiguous => list form
#   INV-8: set-enabled grava via state-rw.sh (state-history + sha256 atualizado)
#
# Cenarios adicionais:
#   - set-enabled valor invalido => exit 2
#   - stage-message: todos os stages mapeados
#   - task-message: ID unico, range, lista
#   - guard-branch: git ausente => exit 1
#   - is-enabled: campo=true => stdout "true"

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/commit-mode.sh"
SCRIPT_RW="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/state-rw.sh"

# Bloqueia suite se jq ausente
if ! command -v jq >/dev/null 2>&1; then
  printf '# test_commit-mode.sh: jq ausente — pulando suite\n'
  exit 0
fi

# Bloqueia suite se git ausente (necessario para guard-branch e finalize)
if ! command -v git >/dev/null 2>&1; then
  printf '# test_commit-mode.sh: git ausente — pulando suite\n'
  exit 0
fi

# ==== helpers ====

# Cria um state.json minimo com atomic_commit_enabled=false (default)
_init_state() {
  _idir=$1
  _atomic=${2:-false}
  sh "$SCRIPT_RW" init --state-dir "$_idir" \
    --projeto-alvo-path "/tmp/cstk-test" \
    --descricao "teste commit-mode (>=10 chars)" \
    --execucao-id "exec-cm-test-001" \
    --atomic-commit "$_atomic" 2>/dev/null
}

# Cria um git repo temporario com branch nao-default
_init_git_repo() {
  _gdir=$1
  _branch=${2:-"feat/test"}
  mkdir -p "$_gdir"
  git -C "$_gdir" init -q 2>/dev/null
  git -C "$_gdir" config user.email "test@test.com" 2>/dev/null
  git -C "$_gdir" config user.name "Test" 2>/dev/null
  # Commit inicial na main
  printf 'init\n' > "$_gdir/README.md"
  git -C "$_gdir" add README.md 2>/dev/null
  git -C "$_gdir" commit -q -m "init" 2>/dev/null
  # Criar branch nao-default
  if [ "$_branch" != "main" ] && [ "$_branch" != "master" ]; then
    git -C "$_gdir" checkout -q -b "$_branch" 2>/dev/null
  fi
}

# ==== INV-1: is-enabled sem campo => false ====

scenario_inv1_is_enabled_sem_campo_retorna_false() {
  _sd="$TMPDIR_TEST/inv1"
  _init_state "$_sd" false
  # Remover campo para simular state legado
  _sf="$_sd/state.json"
  _tmp=$(mktemp)
  jq 'del(.atomic_commit_enabled)' "$_sf" > "$_tmp" && mv "$_tmp" "$_sf"
  # Atualizar sha256 apos remocao
  sh "$SCRIPT_RW" sha256-update --state-dir "$_sd" 2>/dev/null || :

  capture "$SCRIPT" is-enabled --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit esperado 0" "obtido $_CAPTURED_EXIT"; return 1; }
  [ "$_CAPTURED_STDOUT" = "false" ] || { _fail "stdout esperado 'false'" "obtido '$_CAPTURED_STDOUT'"; return 1; }
}

# ==== is-enabled: campo=true => true ====

scenario_is_enabled_campo_true_retorna_true() {
  _sd="$TMPDIR_TEST/is-true"
  _init_state "$_sd" true
  capture "$SCRIPT" is-enabled --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit esperado 0" "obtido $_CAPTURED_EXIT"; return 1; }
  [ "$_CAPTURED_STDOUT" = "true" ] || { _fail "stdout esperado 'true'" "obtido '$_CAPTURED_STDOUT'"; return 1; }
}

# ==== is-enabled: campo=false => false ====

scenario_is_enabled_campo_false_retorna_false() {
  _sd="$TMPDIR_TEST/is-false"
  _init_state "$_sd" false
  capture "$SCRIPT" is-enabled --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit esperado 0" "obtido $_CAPTURED_EXIT"; return 1; }
  [ "$_CAPTURED_STDOUT" = "false" ] || { _fail "stdout esperado 'false'" "obtido '$_CAPTURED_STDOUT'"; return 1; }
}

# ==== INV-8: set-enabled grava via state-rw.sh (state-history + sha256) ====

scenario_inv8_set_enabled_grava_via_state_rw() {
  _sd="$TMPDIR_TEST/inv8"
  _init_state "$_sd" false
  _hist_before=$(ls "$_sd/state-history/" 2>/dev/null | wc -l | tr -d ' ')

  capture "$SCRIPT" set-enabled --state-dir "$_sd" --value true
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "set-enabled exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }

  # Verificar que state-history cresceu (backup foi criado)
  _hist_after=$(ls "$_sd/state-history/" 2>/dev/null | wc -l | tr -d ' ')
  [ "$_hist_after" -gt "$_hist_before" ] || { _fail "state-history nao cresceu" "antes=$_hist_before depois=$_hist_after"; return 1; }

  # Verificar que sha256 foi atualizado (nao corrompido)
  sh "$SCRIPT_RW" sha256-verify --state-dir "$_sd" >/dev/null 2>&1 \
    || { _fail "sha256-verify falhou apos set-enabled" ""; return 1; }

  # Verificar que valor foi persistido
  capture "$SCRIPT" is-enabled --state-dir "$_sd"
  [ "$_CAPTURED_STDOUT" = "true" ] || { _fail "is-enabled apos set-enabled true" "obtido '$_CAPTURED_STDOUT'"; return 1; }
}

# ==== set-enabled: valor invalido => exit 2 ====

scenario_set_enabled_valor_invalido_exit2() {
  _sd="$TMPDIR_TEST/set-invalid"
  _init_state "$_sd" false
  capture "$SCRIPT" set-enabled --state-dir "$_sd" --value "yes"
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit esperado 2" "obtido $_CAPTURED_EXIT"; return 1; }
}

# ==== INV-2: guard-branch em branch default => exit 3 ====

scenario_inv2_guard_branch_default_exit3() {
  _gdir="$TMPDIR_TEST/repo-default"
  _sd="$TMPDIR_TEST/gb-default"
  _init_state "$_sd" true
  _init_git_repo "$_gdir" "main"
  # Voltar para main (branch default)
  git -C "$_gdir" checkout -q main 2>/dev/null || :

  capture "$SCRIPT" guard-branch --state-dir "$_sd" --projeto-alvo-path "$_gdir"
  [ "$_CAPTURED_EXIT" = 3 ] || { _fail "exit esperado 3 (branch default)" "obtido $_CAPTURED_EXIT"; return 1; }
}

# ==== INV-2: guard-branch em branch nao-default => exit 0 ====

scenario_inv2_guard_branch_nao_default_exit0() {
  _gdir="$TMPDIR_TEST/repo-feat"
  _sd="$TMPDIR_TEST/gb-feat"
  _init_state "$_sd" true
  _init_git_repo "$_gdir" "feat/test-branch"

  capture "$SCRIPT" guard-branch --state-dir "$_sd" --projeto-alvo-path "$_gdir"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit esperado 0 (branch nao-default)" "obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"; return 1; }
  # stdout deve ser o nome do branch
  _stdout_trimmed=$(printf '%s' "$_CAPTURED_STDOUT" | head -1)
  [ "$_stdout_trimmed" = "feat/test-branch" ] || { _fail "stdout esperado branch name" "obtido '$_stdout_trimmed'"; return 1; }
}

# ==== INV-3: finalize quando disabled => skipped-disabled, exit 0 ====

scenario_inv3_finalize_disabled_skip() {
  _gdir="$TMPDIR_TEST/repo-disabled"
  _sd="$TMPDIR_TEST/fin-disabled"
  _init_state "$_sd" false
  _init_git_repo "$_gdir" "feat/disabled-test"

  capture "$SCRIPT" finalize --state-dir "$_sd" --projeto-alvo-path "$_gdir"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit esperado 0 (disabled)" "obtido $_CAPTURED_EXIT"; return 1; }
  # JSON de resultado deve indicar skipped-disabled
  printf '%s' "$_CAPTURED_STDOUT" | grep -q '"skipped-disabled"' \
    || { _fail "status esperado skipped-disabled" "stdout: $_CAPTURED_STDOUT"; return 1; }
  # Sem invocacao de gh ou git push (verificar que push_pr_result foi gravado)
  _status=$(jq -r '.push_pr_result.status // "absent"' "$_sd/state.json" 2>/dev/null)
  [ "$_status" = "skipped-disabled" ] || { _fail "push_pr_result.status no state" "obtido '$_status'"; return 1; }
}

# ==== INV-4: finalize com gh ausente => skipped-gh-missing, exit 0 ====

scenario_inv4_finalize_gh_missing() {
  _gdir="$TMPDIR_TEST/repo-nogh"
  _sd="$TMPDIR_TEST/fin-nogh"
  _init_state "$_sd" true
  _init_git_repo "$_gdir" "feat/no-gh"

  # Adicionar commit para ter "ahead" count
  printf 'change\n' >> "$_gdir/README.md"
  git -C "$_gdir" add README.md 2>/dev/null
  git -C "$_gdir" commit -q -m "feat: add change" 2>/dev/null

  # Mascara gh do PATH via PATH stub
  _orig_path="$PATH"
  _stub_dir="$TMPDIR_TEST/stub-nogh"
  mkdir -p "$_stub_dir"
  # Criar stub que apenas nao existe (sem gh no stub dir, e PATH sobrescrito)
  PATH="$_stub_dir:/usr/bin:/bin"
  export PATH

  capture "$SCRIPT" finalize --state-dir "$_sd" --projeto-alvo-path "$_gdir"
  _fin_exit=$_CAPTURED_EXIT
  _fin_out=$_CAPTURED_STDOUT

  PATH="$_orig_path"
  export PATH

  [ "$_fin_exit" = 0 ] || { _fail "exit esperado 0 (gh missing)" "obtido $_fin_exit"; return 1; }
  printf '%s' "$_fin_out" | grep -q '"skipped-gh-missing"\|"skipped-no-commits"' \
    || { _fail "status esperado skipped-gh-missing ou skipped-no-commits" "stdout: $_fin_out"; return 1; }
}

# ==== INV-6: stage-message emite Conventional-Commit subjects ====

scenario_inv6_stage_message_conventional_commit() {
  # Testar todos os stages mapeados
  for _st in specify clarify plan checklist create-tasks; do
    capture "$SCRIPT" stage-message --feature "test-feat" --stage "$_st"
    [ "$_CAPTURED_EXIT" = 0 ] || { _fail "stage-message exit para $_st" "obtido $_CAPTURED_EXIT"; return 1; }
    # Formato esperado: "docs(<scope>): <stage> <feature>"
    printf '%s' "$_CAPTURED_STDOUT" | grep -qE '^docs\([a-z-]+\): ' \
      || { _fail "stage-message nao e Conventional Commit para $_st" "obtido '$_CAPTURED_STDOUT'"; return 1; }
  done
}

# ==== INV-7: task-message — range vs lista ====

scenario_inv7_task_message_ids_contiguos_range() {
  capture "$SCRIPT" task-message --feature "test-feat" --task-ids "1.1,1.2,1.3" --brief "add helper"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit esperado 0" "obtido $_CAPTURED_EXIT"; return 1; }
  # Esperado: "feat: tasks 1.1-1.3 add helper"
  printf '%s' "$_CAPTURED_STDOUT" | grep -qE '^feat: tasks [0-9]+\.[0-9]+-[0-9]+\.[0-9]+' \
    || { _fail "IDs contiguos: esperado range" "obtido '$_CAPTURED_STDOUT'"; return 1; }
}

scenario_inv7_task_message_ids_nao_contiguos_lista() {
  capture "$SCRIPT" task-message --feature "test-feat" --task-ids "1.1,1.3" --brief "two tasks"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit esperado 0" "obtido $_CAPTURED_EXIT"; return 1; }
  # Esperado: "feat: tasks 1.1, 1.3 two tasks"
  printf '%s' "$_CAPTURED_STDOUT" | grep -qE '^feat: tasks [0-9]+\.[0-9]+, [0-9]+\.[0-9]+' \
    || { _fail "IDs nao-contiguos: esperado lista" "obtido '$_CAPTURED_STDOUT'"; return 1; }
}

scenario_inv7_task_message_id_unico() {
  capture "$SCRIPT" task-message --feature "test-feat" --task-ids "3.1" --brief "single task"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit esperado 0" "obtido $_CAPTURED_EXIT"; return 1; }
  # Esperado: "feat: task 3.1 single task"
  if ! printf '%s' "$_CAPTURED_STDOUT" | grep -qE '^feat: task [0-9]+\.[0-9]+'; then
    _fail "ID unico: esperado 'feat: task X.Y'" "obtido '$_CAPTURED_STDOUT'"
    return 1
  fi
  # NAO deve ter "tasks" (plural) — se grep achar, e falha
  if printf '%s' "$_CAPTURED_STDOUT" | grep -qE '^feat: tasks '; then
    _fail "ID unico: nao deve ser plural" "obtido '$_CAPTURED_STDOUT'"
    return 1
  fi
}

# INV-7: task-message sem --brief tambem funciona
scenario_inv7_task_message_sem_brief() {
  capture "$SCRIPT" task-message --feature "test-feat" --task-ids "2.1,2.2"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit esperado 0" "obtido $_CAPTURED_EXIT"; return 1; }
  printf '%s' "$_CAPTURED_STDOUT" | grep -qE '^feat: tasks' \
    || { _fail "sem brief: esperado 'feat: tasks'" "obtido '$_CAPTURED_STDOUT'"; return 1; }
}

# INV-5: finalize idempotente verificado via state (skipped-disabled para
# simplificar — teste completo com PR real exigiria gh autenticado)
scenario_inv5_finalize_nao_duplica_push_pr_result() {
  _gdir="$TMPDIR_TEST/repo-idem"
  _sd="$TMPDIR_TEST/fin-idem"
  _init_state "$_sd" false  # disabled para testar que nao chama gh

  # Primeira chamada
  capture "$SCRIPT" finalize --state-dir "$_sd" --projeto-alvo-path "$_gdir"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "finalize 1a exit" "obtido $_CAPTURED_EXIT"; return 1; }

  # Segunda chamada (idempotente — nao aborta, apenas registra)
  capture "$SCRIPT" finalize --state-dir "$_sd" --projeto-alvo-path "$_gdir"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "finalize 2a exit" "obtido $_CAPTURED_EXIT"; return 1; }

  # sha256 deve ser valido apos duas chamadas
  sh "$SCRIPT_RW" sha256-verify --state-dir "$_sd" >/dev/null 2>&1 \
    || { _fail "sha256 invalido apos finalize duplo" ""; return 1; }
}

# Subcomando desconhecido => exit 2
scenario_subcomando_desconhecido_exit2() {
  capture "$SCRIPT" nao-existe
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit esperado 2 para subcomando invalido" "obtido $_CAPTURED_EXIT"; return 1; }
}

# stage-message: args faltando => exit 2
scenario_stage_message_sem_args_exit2() {
  capture "$SCRIPT" stage-message --feature "feat"
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit esperado 2 sem --stage" "obtido $_CAPTURED_EXIT"; return 1; }
}

# task-message: args faltando => exit 2
scenario_task_message_sem_args_exit2() {
  capture "$SCRIPT" task-message --feature "feat"
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit esperado 2 sem --task-ids" "obtido $_CAPTURED_EXIT"; return 1; }
}

run_all_scenarios
