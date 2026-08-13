#!/bin/sh
# test_commit-mode.sh — cobre plugins/cstk/skills/agente-00c-runtime/scripts/commit-mode.sh.
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
#   - snapshot: baseline ordenado; uso incorreto => exit 2
#   - stage-derived (living-specs FASE 5, FR-014..FR-017): regressao do
#     incidente .pptx — scope-dir exclui alheio, task-baseline inclui
#     arquivo novo, baseline ausente => untracked fora (fail-closed),
#     allowlist vazia => exit 3, paths com espaco/unicode, rename,
#     roundtrip real via 'git show --name-only'
#   - is-enabled: campo=true => stdout "true"

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts/commit-mode.sh"
SCRIPT_RW="$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts/state-rw.sh"

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
  # Branch determinista, independente do default do `git init` (que varia:
  # macOS default "main", Linux/CI default "master"). Renomeia o branch
  # inicial para o nome pedido em vez de assumir o default do ambiente.
  if [ "$_branch" = "main" ] || [ "$_branch" = "master" ]; then
    git -C "$_gdir" branch -m "$_branch" 2>/dev/null || :
  else
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

# ==== Regressao de campo: falha de `cstk session pr` NAO pode abortar ====
# O contrato documentado e "finalize e sempre exit 0 + push_pr_result
# sempre gravado". Como o script roda sob `set -eu`, um `eval "cstk session
# pr ..."` cru numa linha propria abortava a funcao INTEIRA quando o comando
# falhava — observado em campo: exit 9 com .push_pr_result null, sem passar
# por nenhum _cm_record_result.

scenario_finalize_cstk_session_pr_falha_mantem_exit0() {
  _gdir="$TMPDIR_TEST/repo-cstkfail"
  _sd="$TMPDIR_TEST/fin-cstkfail"
  _init_state "$_sd" true
  _init_git_repo "$_gdir" "feat/cstk-fail"

  # Branch default local + origin/HEAD, para o finalize passar do passo 3
  # (senao para em skipped-no-commits e nunca chega no passo 6).
  git -C "$_gdir" branch main 2>/dev/null || :
  git -C "$_gdir" update-ref refs/remotes/origin/main "$(git -C "$_gdir" rev-parse main)" 2>/dev/null || :
  git -C "$_gdir" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main 2>/dev/null || :

  printf 'change\n' >> "$_gdir/README.md"
  git -C "$_gdir" add README.md 2>/dev/null
  git -C "$_gdir" commit -q -m "feat: change" 2>/dev/null

  # Shims: gh autenticado mas sem PR; cstk que falha com exit 9.
  _stub="$TMPDIR_TEST/stub-cstkfail"
  mkdir -p "$_stub"
  cat > "$_stub/gh" <<'GHEOF'
#!/bin/sh
case "$1" in
  auth) exit 0 ;;
  *)    exit 1 ;;
esac
GHEOF
  cat > "$_stub/cstk" <<'CSTKEOF'
#!/bin/sh
exit 9
CSTKEOF
  chmod +x "$_stub/gh" "$_stub/cstk"

  _orig_path="$PATH"
  PATH="$_stub:$_orig_path"
  export PATH

  capture "$SCRIPT" finalize --state-dir "$_sd" --projeto-alvo-path "$_gdir" \
    --session "minha-sessao"
  _fin_exit=$_CAPTURED_EXIT
  _fin_out=$_CAPTURED_STDOUT
  _fin_err=$_CAPTURED_STDERR

  PATH="$_orig_path"
  export PATH

  [ "$_fin_exit" = 0 ] \
    || { _fail "exit esperado 0 mesmo com cstk falhando" "obtido $_fin_exit (regressao: set -eu abortando no eval)"; return 1; }
  printf '%s' "$_fin_err" | grep -q 'cstk session pr falhou (exit 9)' \
    || { _fail "esperado diagnostico da falha do cstk" "stderr: $_fin_err"; return 1; }
  # push_pr_result SEMPRE gravado — a garantia que o bug quebrava.
  printf '%s' "$_fin_out" | grep -q '"status":"' \
    || { _fail "push_pr_result deveria ter sido emitido" "stdout: $_fin_out"; return 1; }
  _persisted=$(jq -r '.push_pr_result.status // "null"' "$_sd/state.json" 2>/dev/null) || _persisted="null"
  [ "$_persisted" != "null" ] \
    || { _fail "push_pr_result nao persistido no state.json" "obtido null"; return 1; }
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

# INV-7 (regressao de campo): transicao de fase NAO e continuidade.
# "1.1,2.1,2.2,2.3" com 1.2/1.3 deliberadamente puladas/bloqueadas nesta
# onda emitia "feat: tasks 1.1-2.3" — mensagem que implica FALSAMENTE que
# 1.2/1.3 foram concluidas. Esperado agora: "feat: tasks 1.1, 2.1-2.3".
scenario_inv7_task_message_transicao_de_fase_nao_vira_range() {
  capture "$SCRIPT" task-message --feature "test-feat" --task-ids "1.1,2.1,2.2,2.3" --brief "fase 2"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit esperado 0" "obtido $_CAPTURED_EXIT"; return 1; }
  case "$_CAPTURED_STDOUT" in
    *"1.1-2.3"*)
      _fail "range cross-fase implica tasks puladas como concluidas" "obtido '$_CAPTURED_STDOUT'"
      return 1
      ;;
  esac
  printf '%s' "$_CAPTURED_STDOUT" | grep -qF 'feat: tasks 1.1, 2.1-2.3 fase 2' \
    || { _fail "esperado 'feat: tasks 1.1, 2.1-2.3 fase 2'" "obtido '$_CAPTURED_STDOUT'"; return 1; }
}

# INV-7: runs contiguos DENTRO da mesma fase seguem comprimindo.
scenario_inv7_task_message_runs_multiplos_por_fase() {
  capture "$SCRIPT" task-message --feature "f" --task-ids "1.1,1.2,1.4,1.5,1.6"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit esperado 0" "obtido $_CAPTURED_EXIT"; return 1; }
  printf '%s' "$_CAPTURED_STDOUT" | grep -qF 'feat: tasks 1.1-1.2, 1.4-1.6' \
    || { _fail "esperado 'feat: tasks 1.1-1.2, 1.4-1.6'" "obtido '$_CAPTURED_STDOUT'"; return 1; }
}

# INV-7: IDs nao-numericos nunca entram em aritmetica (o script roda sob
# `set -eu`; um $(( )) sobre nao-numero abortaria tudo).
scenario_inv7_task_message_ids_nao_numericos_nao_abortam() {
  capture "$SCRIPT" task-message --feature "f" --task-ids "A.1,A.2"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit esperado 0" "obtido $_CAPTURED_EXIT stderr='$_CAPTURED_STDERR'"; return 1; }
  printf '%s' "$_CAPTURED_STDOUT" | grep -qF 'feat: tasks A.1, A.2' \
    || { _fail "esperado lista literal" "obtido '$_CAPTURED_STDOUT'"; return 1; }
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

# ==== FR-015(b): per-stage commit — exatamente 1 commit por stage no git log ====
# Simula o hook de commit atomico por etapa: verifica que stage-message gera mensagem
# diferente por stage e que commits seriam distintos.
scenario_fr015b_per_stage_commit_msg_distinct() {
  _msgs=""
  for _st in specify plan clarify checklist create-tasks; do
    capture "$SCRIPT" stage-message --feature "my-feat" --stage "$_st"
    [ "$_CAPTURED_EXIT" = 0 ] || { _fail "stage-message exit para $_st" "obtido $_CAPTURED_EXIT"; return 1; }
    _msg="$_CAPTURED_STDOUT"
    # Verificar formato Conventional Commit (docs(<scope>): ...)
    printf '%s' "$_msg" | grep -qE '^docs\([a-z-]+\): ' \
      || { _fail "mensagem nao e Conventional Commit para $_st" "obtido '$_msg'"; return 1; }
    # Acumular e verificar ausencia de duplicata
    if printf '%s' "$_msgs" | grep -qF "$_msg"; then
      _fail "mensagem duplicada para stage $_st" "msg='$_msg' ja vista"; return 1
    fi
    _msgs=$(printf '%s\n%s' "$_msgs" "$_msg")
  done
}

# FR-015(b): stage-message + commit real no git repo (verifica 1 commit no log)
scenario_fr015b_stage_commit_no_git_log() {
  _gdir="$TMPDIR_TEST/repo-stage-commit"
  _sd="$TMPDIR_TEST/sc-stage"
  _init_state "$_sd" true
  _init_git_repo "$_gdir" "feat/stage-commit"

  # Simular arquivo de artefato gerado pela etapa
  printf 'spec content\n' > "$_gdir/spec.md"
  git -C "$_gdir" add spec.md 2>/dev/null

  # Obter mensagem para etapa specify
  capture "$SCRIPT" stage-message --feature "test-feat" --stage "specify"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "stage-message exit" "obtido $_CAPTURED_EXIT"; return 1; }
  _msg="$_CAPTURED_STDOUT"

  # Commit direto (simula o hook do orquestrador)
  git -C "$_gdir" commit -q -m "$_msg" 2>/dev/null
  _commit_count=$(git -C "$_gdir" log --oneline 2>/dev/null | wc -l | tr -d ' ')
  # 2 commits: o init + o de specify
  [ "$_commit_count" -ge 2 ] || { _fail "esperado >= 2 commits (init+specify)" "obtido $_commit_count"; return 1; }
  # Verificar que a mensagem do ultimo commit segue Conventional Commits
  _last_msg=$(git -C "$_gdir" log --oneline -1 2>/dev/null | sed 's/^[a-f0-9]* //')
  printf '%s' "$_last_msg" | grep -qE '^docs\([a-z-]+\): ' \
    || { _fail "ultimo commit nao e Conventional Commit" "obtido '$_last_msg'"; return 1; }
}

# ==== FR-015(c): branch-default guard impede push em 100% dos casos ====
# Verifica que guard-branch em branch default retorna exit 3 em varios cenarios

scenario_fr015c_guard_branch_default_main() {
  _gdir="$TMPDIR_TEST/repo-guard-main"
  _sd="$TMPDIR_TEST/guard-main"
  _init_state "$_sd" true
  _init_git_repo "$_gdir" "main"
  git -C "$_gdir" checkout -q main 2>/dev/null || :

  capture "$SCRIPT" guard-branch --state-dir "$_sd" --projeto-alvo-path "$_gdir"
  [ "$_CAPTURED_EXIT" = 3 ] || { _fail "main: exit esperado 3" "obtido $_CAPTURED_EXIT"; return 1; }
}

scenario_fr015c_guard_branch_default_master() {
  _gdir="$TMPDIR_TEST/repo-guard-master"
  _sd="$TMPDIR_TEST/guard-master"
  _init_state "$_sd" true

  # Repo na branch "master" SEM remote. guard-branch sem origin/HEAD trata
  # tanto "main" quanto "master" como default => bloqueado exit 3. Cobre o
  # ambiente CI/Linux onde `git init` default e "master".
  _init_git_repo "$_gdir" "master"
  git -C "$_gdir" checkout -q master 2>/dev/null || :

  capture "$SCRIPT" guard-branch --state-dir "$_sd" --projeto-alvo-path "$_gdir"
  [ "$_CAPTURED_EXIT" = 3 ] || { _fail "master sem remote: exit esperado 3" "obtido $_CAPTURED_EXIT"; return 1; }
}

scenario_fr015c_guard_branch_nao_default_nao_bloqueia() {
  _gdir="$TMPDIR_TEST/repo-guard-feat"
  _sd="$TMPDIR_TEST/guard-feat2"
  _init_state "$_sd" true
  _init_git_repo "$_gdir" "feat/safe-branch"

  capture "$SCRIPT" guard-branch --state-dir "$_sd" --projeto-alvo-path "$_gdir"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "feat/: exit esperado 0" "obtido $_CAPTURED_EXIT"; return 1; }
}

# ==== ensure-branch (atomic-commit-ensure-branch FR-001..FR-003) ====
# Garante HEAD fora da default ANTES da execucao comecar; invocado pelos
# commands pai no opt-in/resume. NAO substitui guard-branch.

scenario_ensure_branch_cria_branch_quando_default() {
  _gdir="$TMPDIR_TEST/repo-eb-create"
  _init_git_repo "$_gdir" "main"
  capture "$SCRIPT" ensure-branch --projeto-alvo-path "$_gdir" --short-name minha-feat
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit esperado 0" "obtido $_CAPTURED_EXIT: $_CAPTURED_STDERR"; return 1; }
  [ "$_CAPTURED_STDOUT" = "created feature/minha-feat" ] \
    || { _fail "stdout esperado 'created feature/minha-feat'" "obtido '$_CAPTURED_STDOUT'"; return 1; }
  _cur=$(git -C "$_gdir" rev-parse --abbrev-ref HEAD 2>/dev/null)
  [ "$_cur" = "feature/minha-feat" ] || { _fail "HEAD esperado feature/minha-feat" "obtido '$_cur'"; return 1; }
}

scenario_ensure_branch_master_sem_remote_tambem_cria() {
  # Sem remote, "master" tambem conta como default (paridade com o
  # guard-branch no ambiente CI/Linux onde `git init` default e master).
  _gdir="$TMPDIR_TEST/repo-eb-master"
  _init_git_repo "$_gdir" "master"
  git -C "$_gdir" checkout -q master 2>/dev/null || :
  capture "$SCRIPT" ensure-branch --projeto-alvo-path "$_gdir" --short-name minha-feat
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit esperado 0" "obtido $_CAPTURED_EXIT"; return 1; }
  [ "$_CAPTURED_STDOUT" = "created feature/minha-feat" ] \
    || { _fail "stdout esperado 'created feature/minha-feat'" "obtido '$_CAPTURED_STDOUT'"; return 1; }
}

scenario_ensure_branch_noop_fora_da_default() {
  _gdir="$TMPDIR_TEST/repo-eb-noop"
  _init_git_repo "$_gdir" "feat/ja-isolada"
  capture "$SCRIPT" ensure-branch --projeto-alvo-path "$_gdir" --short-name minha-feat
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit esperado 0" "obtido $_CAPTURED_EXIT"; return 1; }
  [ "$_CAPTURED_STDOUT" = "noop feat/ja-isolada" ] \
    || { _fail "stdout esperado 'noop feat/ja-isolada'" "obtido '$_CAPTURED_STDOUT'"; return 1; }
  _cur=$(git -C "$_gdir" rev-parse --abbrev-ref HEAD 2>/dev/null)
  [ "$_cur" = "feat/ja-isolada" ] || { _fail "HEAD nao deveria mudar" "obtido '$_cur'"; return 1; }
}

scenario_ensure_branch_troca_para_branch_existente() {
  # Resume/reopen com a branch da feature ja criada: troca em vez de criar.
  _gdir="$TMPDIR_TEST/repo-eb-switch"
  _init_git_repo "$_gdir" "main"
  git -C "$_gdir" branch feature/minha-feat 2>/dev/null
  capture "$SCRIPT" ensure-branch --projeto-alvo-path "$_gdir" --short-name minha-feat
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit esperado 0" "obtido $_CAPTURED_EXIT"; return 1; }
  [ "$_CAPTURED_STDOUT" = "switched feature/minha-feat" ] \
    || { _fail "stdout esperado 'switched feature/minha-feat'" "obtido '$_CAPTURED_STDOUT'"; return 1; }
}

scenario_ensure_branch_idempotente() {
  # SC-002: duas invocacoes seguidas => mesmo estado final, exit 0.
  _gdir="$TMPDIR_TEST/repo-eb-idem"
  _init_git_repo "$_gdir" "main"
  capture "$SCRIPT" ensure-branch --projeto-alvo-path "$_gdir" --short-name minha-feat
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "primeira invocacao" "$_CAPTURED_STDERR"; return 1; }
  capture "$SCRIPT" ensure-branch --projeto-alvo-path "$_gdir" --short-name minha-feat
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "segunda invocacao" "$_CAPTURED_STDERR"; return 1; }
  [ "$_CAPTURED_STDOUT" = "noop feature/minha-feat" ] \
    || { _fail "stdout esperado 'noop feature/minha-feat'" "obtido '$_CAPTURED_STDOUT'"; return 1; }
}

scenario_ensure_branch_prefix_custom() {
  # /agente-00c usa --prefix agente-00c/ (FR-004 do spec).
  _gdir="$TMPDIR_TEST/repo-eb-prefix"
  _init_git_repo "$_gdir" "main"
  capture "$SCRIPT" ensure-branch --projeto-alvo-path "$_gdir" \
    --short-name meu-projeto --prefix agente-00c/
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit esperado 0" "obtido $_CAPTURED_EXIT"; return 1; }
  [ "$_CAPTURED_STDOUT" = "created agente-00c/meu-projeto" ] \
    || { _fail "stdout esperado 'created agente-00c/meu-projeto'" "obtido '$_CAPTURED_STDOUT'"; return 1; }
}

scenario_ensure_branch_short_name_invalido_exit2() {
  # FR-003: token fail-closed ANTES de qualquer invocacao git.
  _gdir="$TMPDIR_TEST/repo-eb-token"
  mkdir -p "$_gdir"
  capture "$SCRIPT" ensure-branch --projeto-alvo-path "$_gdir" --short-name "com espaco"
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit esperado 2" "obtido $_CAPTURED_EXIT"; return 1; }
}

scenario_ensure_branch_prefix_sem_barra_exit2() {
  _gdir="$TMPDIR_TEST/repo-eb-prefix-bad"
  mkdir -p "$_gdir"
  capture "$SCRIPT" ensure-branch --projeto-alvo-path "$_gdir" \
    --short-name ok --prefix sem-barra
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit esperado 2" "obtido $_CAPTURED_EXIT"; return 1; }
}

scenario_ensure_branch_nao_repo_exit1() {
  # FR-002: fail-loud quando PATH nao e repositorio git.
  _gdir="$TMPDIR_TEST/eb-nao-repo"
  mkdir -p "$_gdir"
  capture "$SCRIPT" ensure-branch --projeto-alvo-path "$_gdir" --short-name minha-feat
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "exit esperado 1" "obtido $_CAPTURED_EXIT"; return 1; }
}

# ==== probe-pending-work (feature reopen-flow: contracts/pending-work-probe.md, dec-038) ====
#
# T-50: branch nao mesclada reporta pendencia citando o comando
# T-51: gh ausente/nao autenticado/falho => nunca infere merged/pr_state negativo
# T-52: branch com nome iniciado por '-' nao e consumida como flag
# T-53: sonda nunca bloqueia — exit permanece 0 com pendencia detectada

# Repo com branch default "main" (sem remote — cai no fallback main/master de
# guard-branch/finalize, task 4.1.2) e uma branch de feature com um commit
# extra nao mesclado de volta em "main".
_init_git_repo_probe() {
  _gdir=$1
  _feat=${2:-"feat/probe-x"}
  mkdir -p "$_gdir"
  git -C "$_gdir" init -q 2>/dev/null
  git -C "$_gdir" config user.email "test@test.com" 2>/dev/null
  git -C "$_gdir" config user.name "Test" 2>/dev/null
  printf 'init\n' > "$_gdir/README.md"
  git -C "$_gdir" add README.md 2>/dev/null
  git -C "$_gdir" commit -q -m "init" 2>/dev/null
  git -C "$_gdir" branch -m main 2>/dev/null || :
  git -C "$_gdir" checkout -q -b "$_feat" 2>/dev/null
  printf 'change\n' >> "$_gdir/README.md"
  git -C "$_gdir" add README.md 2>/dev/null
  git -C "$_gdir" commit -q -m "feat: change" 2>/dev/null
}

# ---- T-50: branch nao mesclada ⇒ merged=no citando o comando em source ----

scenario_t50_probe_branch_nao_mesclada_reporta_pendencia() {
  _gdir="$TMPDIR_TEST/repo-probe-t50"
  _sd="$TMPDIR_TEST/probe-t50"
  _init_git_repo_probe "$_gdir" "feat/probe-t50"

  # Mascara gh do PATH: isola a assercao git-side (merged), sem gh interferir.
  _orig_path="$PATH"
  _stub_dir="$TMPDIR_TEST/stub-t50-nogh"
  mkdir -p "$_stub_dir"
  PATH="$_stub_dir:/usr/bin:/bin"
  export PATH

  capture "$SCRIPT" probe-pending-work --state-dir "$_sd" --projeto-alvo-path "$_gdir" -- feat/probe-t50

  PATH="$_orig_path"
  export PATH

  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit esperado 0" "obtido $_CAPTURED_EXIT"; return 1; }
  IFS='|' read -r _tag _branch _dflt _merged _prst _prurl _src _pstat <<EOF
$_CAPTURED_STDOUT
EOF
  [ "$_tag" = "PROBE" ] || { _fail "envelope esperado PROBE" "obtido '$_tag'"; return 1; }
  [ "$_branch" = "feat/probe-t50" ] || { _fail "branch incorreto" "obtido '$_branch'"; return 1; }
  [ "$_dflt" = "main" ] || { _fail "default_branch esperado main" "obtido '$_dflt'"; return 1; }
  [ "$_merged" = "no" ] || { _fail "merged esperado 'no'" "obtido '$_merged'"; return 1; }
  case "$_src" in
    *'git merge-base --is-ancestor'*) : ;;
    *) _fail "source deveria citar 'git merge-base --is-ancestor'" "obtido '$_src'"; return 1 ;;
  esac
}

# ---- T-51: gh ausente/nao autenticado/falho apos auth ⇒ nunca infere negativo ----

# ===== issue #98: fallback apos pipe nunca disparava =====

# `var=$(cmd | sed ...) || var=FALLBACK` NUNCA cai no fallback: o exit status
# de um pipe e o do ULTIMO comando, e o sed sai 0 mesmo com entrada vazia.
# Em commit-mode.sh isso deixava `_default` VAZIO quando o repo nao tem
# origin/HEAD; o `git rev-list "..branch" --count` seguinte degenerava para 0
# e o finalize concluia "sem commits novos", pulando push+PR EM SILENCIO.
# Guard estatico: o idioma nao pode reaparecer em lugar nenhum do script.
scenario_issue98_idioma_de_fallback_apos_pipe_ausente() {
  [ -f "$SCRIPT" ] || { _error "script ausente" "$SCRIPT"; return 2; }
  if grep -nE "\| *sed [^)]*\) *\|\| *_[a-z_]+=" "$SCRIPT" >/dev/null 2>&1; then
    _fail "idioma de fallback-apos-pipe reapareceu (issue #98)" \
      "$(grep -nE "\| *sed [^)]*\) *\|\| *_[a-z_]+=" "$SCRIPT" | head -3)"
    return 1
  fi
  return 0
}

# A captura em duas etapas (exit status do symbolic-ref testavel) tem de
# estar presente — nao basta o idioma ruim ter sumido.
scenario_issue98_captura_em_duas_etapas_presente() {
  [ -f "$SCRIPT" ] || { _error "script ausente" "$SCRIPT"; return 2; }
  assert_exit 0 grep -Fq 'symbolic-ref refs/remotes/origin/HEAD 2>/dev/null) || _sr=""' "$SCRIPT" || return 1
  assert_exit 0 grep -Fq '[ -n "$_default" ] || _default="main"' "$SCRIPT" || return 1
}

# _make_shim_path_no_gh: PATH completo (symlinks) COM git mas SEM gh.
# Armadilha conhecida do repositorio (memoria de projeto
# feedback_test_path_stub_cannot_hide_usrbin.md) — PATH deve conter TODOS os
# binarios via symlink, exceto o suprimido, nunca um PATH minimo/stub.
# Historico: `PATH="$stub:/usr/bin:/bin"` NAO esconde o gh no CI Ubuntu (o gh
# mora em /usr/bin), so na maquina local (gh em /opt/homebrew/bin) — passava
# local e queimou a 1a tag v7.3.0 no gate de release.
# Espelha tests/test_posttooluse-tool-call-tick.sh::_make_shim_path_no_sqlite.
_make_shim_path_no_gh() {
  _shim="$TMPDIR_TEST/shimbin-no-gh"
  mkdir -p "$_shim"
  for _cmd in sh git jq mktemp awk sed grep find head printf cp mv rm mkdir \
              chmod ls dirname basename tr cut wc env command sort \
              uniq date cat; do
    _src=$(command -v "$_cmd" 2>/dev/null) || continue
    [ -n "$_src" ] || continue
    ln -sf "$_src" "$_shim/$_cmd" 2>/dev/null || :
  done
  printf '%s' "$_shim"
}

scenario_t51a_probe_gh_ausente_nunca_infere_negativo() {
  _gdir="$TMPDIR_TEST/repo-probe-t51a"
  _sd="$TMPDIR_TEST/probe-t51a"
  _init_git_repo_probe "$_gdir" "feat/probe-t51a"

  _orig_path="$PATH"
  PATH="$(_make_shim_path_no_gh)"
  export PATH

  # Auto-verificacao do sandbox: se o gh continuar visivel, o cenario nao esta
  # testando o que promete. Falha explicita em vez de falso-positivo silencioso.
  if command -v gh >/dev/null 2>&1; then
    PATH="$_orig_path"; export PATH
    _fail "sandbox de PATH nao suprimiu o gh" "command -v gh ainda resolve sob o shim"
    return 1
  fi

  capture "$SCRIPT" probe-pending-work --state-dir "$_sd" --projeto-alvo-path "$_gdir" -- feat/probe-t51a

  PATH="$_orig_path"
  export PATH

  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit esperado 0 (gh ausente nao rebaixa)" "obtido $_CAPTURED_EXIT"; return 1; }
  IFS='|' read -r _tag _branch _dflt _merged _prst _prurl _src _pstat <<EOF
$_CAPTURED_STDOUT
EOF
  [ "$_pstat" = "skipped-gh-missing" ] || { _fail "probe_status esperado skipped-gh-missing" "obtido '$_pstat'"; return 1; }
  [ "$_prst" = "unknown" ] || { _fail "pr_state deve ser unknown, nunca closed/merged" "obtido '$_prst'"; return 1; }
  [ "$_prurl" = "-" ] || { _fail "pr_url deve ser '-' (null)" "obtido '$_prurl'"; return 1; }
}

scenario_t51b_probe_gh_nao_autenticado_nunca_infere_negativo() {
  _gdir="$TMPDIR_TEST/repo-probe-t51b"
  _sd="$TMPDIR_TEST/probe-t51b"
  _init_git_repo_probe "$_gdir" "feat/probe-t51b"

  _stub="$TMPDIR_TEST/stub-t51b-unauth"
  mkdir -p "$_stub"
  cat > "$_stub/gh" <<'GHEOF'
#!/bin/sh
case "$1" in
  auth) exit 1 ;;
  *)    exit 1 ;;
esac
GHEOF
  chmod +x "$_stub/gh"

  _orig_path="$PATH"
  PATH="$_stub:/usr/bin:/bin"
  export PATH

  capture "$SCRIPT" probe-pending-work --state-dir "$_sd" --projeto-alvo-path "$_gdir" -- feat/probe-t51b

  PATH="$_orig_path"
  export PATH

  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit esperado 0 (gh unauth nao rebaixa)" "obtido $_CAPTURED_EXIT"; return 1; }
  IFS='|' read -r _tag _branch _dflt _merged _prst _prurl _src _pstat <<EOF
$_CAPTURED_STDOUT
EOF
  [ "$_pstat" = "skipped-gh-unauth" ] || { _fail "probe_status esperado skipped-gh-unauth" "obtido '$_pstat'"; return 1; }
  [ "$_prst" = "unknown" ] || { _fail "pr_state deve ser unknown, nunca closed/merged" "obtido '$_prst'"; return 1; }
}

# Ponto central de dec-038: gh PRESENTE e AUTENTICADO, mas `gh pr view` falha
# de fato (rede/timeout/rate-limit) — nao apenas ausencia do binario. Deve
# manter pr_state=unknown/pr_url=null. E a regressao literal que o anti-padrao
# de finalize (commit-mode.sh:726/:771, `cmd 2>/dev/null || var=""`) cometia:
# tratar saida vazia como resposta negativa.

scenario_t51c_probe_gh_pr_view_falha_apos_auth_nunca_infere_negativo() {
  _gdir="$TMPDIR_TEST/repo-probe-t51c"
  _sd="$TMPDIR_TEST/probe-t51c"
  _init_git_repo_probe "$_gdir" "feat/probe-t51c"

  _stub="$TMPDIR_TEST/stub-t51c-prfail"
  mkdir -p "$_stub"
  cat > "$_stub/gh" <<'GHEOF'
#!/bin/sh
case "$1" in
  auth) exit 0 ;;
  pr)   exit 1 ;;
  *)    exit 1 ;;
esac
GHEOF
  chmod +x "$_stub/gh"

  _orig_path="$PATH"
  PATH="$_stub:/usr/bin:/bin"
  export PATH

  capture "$SCRIPT" probe-pending-work --state-dir "$_sd" --projeto-alvo-path "$_gdir" -- feat/probe-t51c

  PATH="$_orig_path"
  export PATH

  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit esperado 0" "obtido $_CAPTURED_EXIT"; return 1; }
  IFS='|' read -r _tag _branch _dflt _merged _prst _prurl _src _pstat <<EOF
$_CAPTURED_STDOUT
EOF
  # merged (dado primario git-side) permanece corretamente determinado —
  # a falha do gh NAO deve contaminar o campo git-side.
  [ "$_merged" = "no" ] || { _fail "merged deveria permanecer 'no' (git-side, nao afetado por gh)" "obtido '$_merged'"; return 1; }
  [ "$_prst" = "unknown" ] || { _fail "pr_state deve ser unknown — NUNCA closed/merged de saida vazia" "obtido '$_prst'"; return 1; }
  [ "$_prurl" = "-" ] || { _fail "pr_url deve ser '-' (null), nunca inferido" "obtido '$_prurl'"; return 1; }
}

# ---- T-52: branch com nome iniciado por '-' nao e consumida como flag ----

scenario_t52_probe_branch_com_dash_nao_e_consumida_como_flag() {
  _gdir="$TMPDIR_TEST/repo-probe-t52"
  _sd="$TMPDIR_TEST/probe-t52"
  _init_git_repo_probe "$_gdir" "feat/probe-t52-base"

  # `git branch --force` seria interpretado como flag pelo proprio git; a
  # unica forma portavel de criar essa ref e via update-ref direto.
  _sha=$(git -C "$_gdir" rev-parse feat/probe-t52-base)
  git -C "$_gdir" update-ref refs/heads/--force "$_sha" 2>/dev/null

  _orig_path="$PATH"
  _stub_dir="$TMPDIR_TEST/stub-t52-nogh"
  mkdir -p "$_stub_dir"
  PATH="$_stub_dir:/usr/bin:/bin"
  export PATH

  capture "$SCRIPT" probe-pending-work --state-dir "$_sd" --projeto-alvo-path "$_gdir" -- --force

  PATH="$_orig_path"
  export PATH

  # Se '--force' tivesse sido consumido como flag, o resultado seria exit 2
  # ("flag desconhecida"), nao o fluxo normal da sonda.
  [ "$_CAPTURED_EXIT" != 2 ] \
    || { _fail "branch '--force' foi consumida como flag (deveria exigir '--')" "stderr: $_CAPTURED_STDERR"; return 1; }
  printf '%s' "$_CAPTURED_STDOUT" | grep -q '^PROBE|--force|' \
    || { _fail "branch no envelope deveria ser '--force'" "stdout: $_CAPTURED_STDOUT"; return 1; }
}

# ---- T-53: sonda nunca bloqueia — exit permanece 0 com pendencia detectada ----

scenario_t53_probe_nunca_bloqueia_com_pendencia_detectada() {
  _gdir="$TMPDIR_TEST/repo-probe-t53"
  _sd="$TMPDIR_TEST/probe-t53"
  _init_git_repo_probe "$_gdir" "feat/probe-t53"

  _orig_path="$PATH"
  _stub_dir="$TMPDIR_TEST/stub-t53-nogh"
  mkdir -p "$_stub_dir"
  PATH="$_stub_dir:/usr/bin:/bin"
  export PATH

  capture "$SCRIPT" probe-pending-work --state-dir "$_sd" --projeto-alvo-path "$_gdir" -- feat/probe-t53

  PATH="$_orig_path"
  export PATH

  # Pendencia REAL detectada (merged=no) — mas a sonda e so-informativa
  # (FR-021): exit permanece 0, nunca um codigo que sinalize bloqueio.
  [ "$_CAPTURED_EXIT" = 0 ] \
    || { _fail "sonda nao deve bloquear mesmo com pendencia detectada" "exit obtido $_CAPTURED_EXIT"; return 1; }
  printf '%s' "$_CAPTURED_STDOUT" | grep -q '|no|' \
    || { _fail "esperava pendencia (merged=no) detectada" "stdout: $_CAPTURED_STDOUT"; return 1; }
}

# ---- uso incorreto: '--' ausente / BRANCH vazio ⇒ exit 2 ----

scenario_probe_sem_separador_exit2() {
  capture "$SCRIPT" probe-pending-work --state-dir "$TMPDIR_TEST/x" --projeto-alvo-path "$TMPDIR_TEST/y" feat/sem-separador
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit esperado 2 (sem '--')" "obtido $_CAPTURED_EXIT"; return 1; }
}

scenario_probe_branch_vazia_apos_separador_exit2() {
  capture "$SCRIPT" probe-pending-work --state-dir "$TMPDIR_TEST/x" --projeto-alvo-path "$TMPDIR_TEST/y" --
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit esperado 2 (BRANCH vazio)" "obtido $_CAPTURED_EXIT"; return 1; }
}

# ---- git ausente no PATH ⇒ skipped-no-git, exit 3 ----

scenario_probe_git_ausente_skipped_no_git_exit3() {
  # NAO reusar o padrao "PATH=$stub:/usr/bin:/bin" aqui: git mora em
  # /usr/bin neste ambiente (e em muitos Ubuntu via usrmerge), entao
  # prefixar um stub-dir vazio nao o esconde (feedback_test_path_stub_
  # cannot_hide_usrbin). Em vez de mutar o PATH do processo de teste (o
  # que quebraria o proprio mktemp usado por `capture`), isola o PATH so
  # do processo filho (o SUT) via `env PATH=... "$SCRIPT" ...` — o
  # harness continua enxergando o PATH ambiente intacto.
  _stub_dir="$TMPDIR_TEST/stub-probe-nogit"
  mkdir -p "$_stub_dir"

  capture env PATH="$_stub_dir" "$SCRIPT" probe-pending-work \
    --state-dir "$TMPDIR_TEST/x" --projeto-alvo-path "$TMPDIR_TEST/y" -- feat/sem-git

  [ "$_CAPTURED_EXIT" = 3 ] || { _fail "exit esperado 3 (git ausente)" "obtido $_CAPTURED_EXIT"; return 1; }
  printf '%s' "$_CAPTURED_STDOUT" | grep -q 'skipped-no-git$' \
    || { _fail "probe_status esperado skipped-no-git" "stdout: $_CAPTURED_STDOUT"; return 1; }
}

# ---- branch inexistente ⇒ skipped-no-git, exit 3 ----

scenario_probe_branch_inexistente_skipped_no_git_exit3() {
  _gdir="$TMPDIR_TEST/repo-probe-nobranch"
  _sd="$TMPDIR_TEST/probe-nobranch"
  _init_git_repo_probe "$_gdir" "feat/probe-existe"

  capture "$SCRIPT" probe-pending-work --state-dir "$_sd" --projeto-alvo-path "$_gdir" -- feat/nao-existe

  [ "$_CAPTURED_EXIT" = 3 ] || { _fail "exit esperado 3 (branch inexistente)" "obtido $_CAPTURED_EXIT"; return 1; }
  printf '%s' "$_CAPTURED_STDOUT" | grep -q 'skipped-no-git$' \
    || { _fail "probe_status esperado skipped-no-git" "stdout: $_CAPTURED_STDOUT"; return 1; }
}

# ---- branch mesclada ⇒ merged=yes ----

scenario_probe_branch_mesclada_merged_yes() {
  _gdir="$TMPDIR_TEST/repo-probe-merged"
  _sd="$TMPDIR_TEST/probe-merged"
  _init_git_repo_probe "$_gdir" "feat/probe-merged"
  git -C "$_gdir" checkout -q main 2>/dev/null
  git -C "$_gdir" merge -q feat/probe-merged --no-edit 2>/dev/null

  _orig_path="$PATH"
  _stub_dir="$TMPDIR_TEST/stub-merged-nogh"
  mkdir -p "$_stub_dir"
  PATH="$_stub_dir:/usr/bin:/bin"
  export PATH

  capture "$SCRIPT" probe-pending-work --state-dir "$_sd" --projeto-alvo-path "$_gdir" -- feat/probe-merged

  PATH="$_orig_path"
  export PATH

  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit esperado 0" "obtido $_CAPTURED_EXIT"; return 1; }
  printf '%s' "$_CAPTURED_STDOUT" | grep -q '|yes|' \
    || { _fail "merged esperado 'yes'" "stdout: $_CAPTURED_STDOUT"; return 1; }
}

# ---- gh presente + autenticado + PR OPEN ⇒ checked, pr_state=open ----

scenario_probe_gh_pr_open_checked() {
  _gdir="$TMPDIR_TEST/repo-probe-propen"
  _sd="$TMPDIR_TEST/probe-propen"
  _init_git_repo_probe "$_gdir" "feat/probe-propen"

  _stub="$TMPDIR_TEST/stub-probe-propen"
  mkdir -p "$_stub"
  cat > "$_stub/gh" <<'GHEOF'
#!/bin/sh
case "$1" in
  auth) exit 0 ;;
  pr)   printf '{"url":"https://example.test/pr/42","state":"OPEN"}\n'; exit 0 ;;
  *)    exit 1 ;;
esac
GHEOF
  chmod +x "$_stub/gh"

  _orig_path="$PATH"
  PATH="$_stub:/usr/bin:/bin"
  export PATH

  capture "$SCRIPT" probe-pending-work --state-dir "$_sd" --projeto-alvo-path "$_gdir" -- feat/probe-propen

  PATH="$_orig_path"
  export PATH

  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit esperado 0" "obtido $_CAPTURED_EXIT"; return 1; }
  IFS='|' read -r _tag _branch _dflt _merged _prst _prurl _src _pstat <<EOF
$_CAPTURED_STDOUT
EOF
  [ "$_pstat" = "checked" ] || { _fail "probe_status esperado checked" "obtido '$_pstat'"; return 1; }
  [ "$_prst" = "open" ] || { _fail "pr_state esperado open" "obtido '$_prst'"; return 1; }
  [ "$_prurl" = "https://example.test/pr/42" ] || { _fail "pr_url incorreto" "obtido '$_prurl'"; return 1; }
}

# ==== snapshot: grava baseline ordenado de untracked ====

scenario_snapshot_grava_baseline_untracked_ordenado() {
  _gdir="$TMPDIR_TEST/repo-snap"
  _sd="$TMPDIR_TEST/sd-snap"
  _init_git_repo "$_gdir" "feat/snap"
  printf 'b\n' > "$_gdir/beta.txt"
  printf 'a\n' > "$_gdir/alpha.txt"

  capture "$SCRIPT" snapshot --state-dir "$_sd" --projeto-alvo-path "$_gdir"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "snapshot exit" "obtido $_CAPTURED_EXIT"; return 1; }
  [ -f "$_sd/commit-baseline.txt" ] || { _fail "baseline nao gravado" "arquivo ausente"; return 1; }

  _expected="alpha.txt
beta.txt"
  _got=$(cat "$_sd/commit-baseline.txt")
  [ "$_got" = "$_expected" ] || { _fail "baseline ordenado" "esperado '$_expected' obtido '$_got'"; return 1; }
}

# ==== issue #49: collation estavel (LC_ALL=C) entre snapshot e stage-derived ====
# Incidente real: ~45 untracked PRE-EXISTENTES staged no wave-commit. Uma
# das causas: baseline ordenado sob collation de locale (en_US/pt_BR poem
# "a.txt" antes de "Z.txt") e `comm` comparando sob outra — linhas do
# baseline nao casam e o pre-existente "vaza" como novo. Com o fix, sort e
# comm rodam SEMPRE em LC_ALL=C nos dois subcomandos, independente do
# locale herdado da invocacao.

scenario_issue49_collation_c_entre_snapshot_e_stagederived() {
  _loc=$(locale -a 2>/dev/null | grep -i '^en_US\.utf-*8$' | head -1)
  [ -n "$_loc" ] || { printf '# skip: locale en_US.UTF-8 indisponivel\n'; return 0; }
  _gdir="$TMPDIR_TEST/repo-collation"
  _sd="$TMPDIR_TEST/sd-collation"
  _init_git_repo "$_gdir" "feat/collation"
  # Em C, "Z.txt" < "a.txt"; em en_US, "a.txt" < "Z.txt" — o par detecta
  # qualquer sort fora de LC_ALL=C.
  printf 'z\n' > "$_gdir/Z.txt"
  printf 'a\n' > "$_gdir/a.txt"

  # snapshot herda locale UTF-8 (sessao tipica do operador nao-C)
  capture env LC_ALL="$_loc" "$SCRIPT" snapshot --state-dir "$_sd" --projeto-alvo-path "$_gdir"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "snapshot exit" "obtido $_CAPTURED_EXIT"; return 1; }
  _expected="Z.txt
a.txt"
  _got=$(cat "$_sd/commit-baseline.txt")
  [ "$_got" = "$_expected" ] \
    || { _fail "baseline deve ser C-sorted mesmo sob $_loc" "obtido '$_got'"; return 1; }

  # stage-derived herda OUTRO locale (C): os pre-existentes continuam fora,
  # so a mudanca tracked entra.
  printf 'r2\n' >> "$_gdir/README.md"
  capture env LC_ALL=C "$SCRIPT" stage-derived --state-dir "$_sd" --projeto-alvo-path "$_gdir"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "stage-derived exit" "obtido $_CAPTURED_EXIT stderr='$_CAPTURED_STDERR'"; return 1; }
  _staged=$(git -C "$_gdir" diff --cached --name-only)
  case "$_staged" in
    *Z.txt*|*a.txt*) _fail "pre-existentes vazaram para o staging" "obtido: $_staged"; return 1 ;;
  esac
  case "$_staged" in
    *README.md*) : ;;
    *) _fail "README.md deveria estar staged" "obtido: $_staged"; return 1 ;;
  esac
}

# ==== snapshot: uso incorreto sem --state-dir/--projeto-alvo-path => exit 2 ====

scenario_snapshot_uso_incorreto_exit2() {
  capture "$SCRIPT" snapshot --state-dir "$TMPDIR_TEST/x"
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit esperado 2" "obtido $_CAPTURED_EXIT"; return 1; }
}

# ==== 5.3.1: commit de etapa (scope-dir) exclui alheio pre-existente ====

scenario_5_3_1_stagederived_scope_dir_exclui_alien() {
  _gdir="$TMPDIR_TEST/repo-etapa"
  _sd="$TMPDIR_TEST/sd-etapa"
  _init_git_repo "$_gdir" "feat/etapa"

  # Alheio untracked PRE-EXISTENTE (analogo ao incidente .pptx real).
  printf 'alien\n' > "$_gdir/alien.pptx"

  capture "$SCRIPT" snapshot --state-dir "$_sd" --projeto-alvo-path "$_gdir"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "snapshot exit" "obtido $_CAPTURED_EXIT"; return 1; }

  mkdir -p "$_gdir/docs/specs/feat-x"
  printf 's\n' > "$_gdir/docs/specs/feat-x/plan.md"

  capture "$SCRIPT" stage-derived --state-dir "$_sd" --projeto-alvo-path "$_gdir" \
    --scope-dir "docs/specs/feat-x"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "stage-derived exit" "obtido $_CAPTURED_EXIT stderr='$_CAPTURED_STDERR'"; return 1; }

  _staged=$(git -C "$_gdir" diff --cached --name-only)
  case "$_staged" in
    *alien.pptx*) _fail "alien.pptx nao deveria estar staged" "obtido: $_staged"; return 1 ;;
  esac
  case "$_staged" in
    *"docs/specs/feat-x/plan.md"*) : ;;
    *) _fail "plan.md deveria estar staged" "obtido: $_staged"; return 1 ;;
  esac

  _untracked=$(git -C "$_gdir" status --porcelain | grep '^??' || :)
  case "$_untracked" in
    *alien.pptx*) : ;;
    *) _fail "alien.pptx deveria permanecer untracked" "obtido: $_untracked"; return 1 ;;
  esac
}

# ==== Regressao de campo: --scope-dir ABSOLUTO sob o projeto-alvo ====
# Os prompts dos orquestradores passam <FD>, que resolve para path absoluto
# em varios pontos. Antes, o casamento por prefixo contra os paths de
# `git status --porcelain` (sempre relativos) nunca casava e o comando
# devolvia rc=3 "allowlist vazia" — diagnostico enganoso, havia arquivo
# staged-avel. Agora o absoluto e normalizado para relativo.

scenario_stagederived_scope_dir_absoluto_normaliza() {
  _gdir="$TMPDIR_TEST/repo-abs-scope"
  _sd="$TMPDIR_TEST/sd-abs-scope"
  _init_git_repo "$_gdir" "feat/abs-scope"

  printf 'alien\n' > "$_gdir/alien.pptx"
  capture "$SCRIPT" snapshot --state-dir "$_sd" --projeto-alvo-path "$_gdir"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "snapshot exit" "obtido $_CAPTURED_EXIT"; return 1; }

  mkdir -p "$_gdir/docs/specs/feat-abs"
  printf 's\n' > "$_gdir/docs/specs/feat-abs/spec.md"

  # --scope-dir ABSOLUTO (o modo de falha reportado)
  capture "$SCRIPT" stage-derived --state-dir "$_sd" --projeto-alvo-path "$_gdir" \
    --scope-dir "$_gdir/docs/specs/feat-abs"
  [ "$_CAPTURED_EXIT" = 0 ] \
    || { _fail "stage-derived com scope absoluto" "esperado exit 0, obtido $_CAPTURED_EXIT stderr='$_CAPTURED_STDERR'"; return 1; }

  _staged=$(git -C "$_gdir" diff --cached --name-only)
  case "$_staged" in
    *"docs/specs/feat-abs/spec.md"*) : ;;
    *) _fail "spec.md deveria estar staged" "obtido: $_staged"; return 1 ;;
  esac
  # Confinamento preservado: o alheio continua fora.
  case "$_staged" in
    *alien.pptx*) _fail "alien.pptx nao deveria estar staged" "obtido: $_staged"; return 1 ;;
  esac
}

# Absoluto FORA do projeto-alvo: nao ha relativo equivalente. Mantem o
# comportamento anterior (nao casa => allowlist vazia => rc=3), mas agora
# com diagnostico explicito em vez de silencio.
scenario_stagederived_scope_dir_absoluto_fora_do_repo_diagnostica() {
  _gdir="$TMPDIR_TEST/repo-abs-fora"
  _sd="$TMPDIR_TEST/sd-abs-fora"
  _init_git_repo "$_gdir" "feat/abs-fora"

  capture "$SCRIPT" snapshot --state-dir "$_sd" --projeto-alvo-path "$_gdir"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "snapshot exit" "obtido $_CAPTURED_EXIT"; return 1; }

  mkdir -p "$_gdir/docs"
  printf 's\n' > "$_gdir/docs/spec.md"

  capture "$SCRIPT" stage-derived --state-dir "$_sd" --projeto-alvo-path "$_gdir" \
    --scope-dir "/caminho/totalmente/alheio"
  [ "$_CAPTURED_EXIT" = 3 ] \
    || { _fail "esperado rc=3 (allowlist vazia)" "obtido $_CAPTURED_EXIT"; return 1; }
  printf '%s' "$_CAPTURED_STDERR" | grep -q 'fora de --projeto-alvo-path' \
    || { _fail "faltou diagnostico de scope-dir fora do repo" "stderr='$_CAPTURED_STDERR'"; return 1; }
}

# ==== 5.3.2: commit de task (baseline + arquivo novo pos-snapshot) inclui o novo ====

scenario_5_3_2_stagederived_task_baseline_inclui_novo_arquivo() {
  _gdir="$TMPDIR_TEST/repo-task"
  _sd="$TMPDIR_TEST/sd-task"
  _init_git_repo "$_gdir" "feat/task"
  printf 'alien\n' > "$_gdir/alien.pptx"

  capture "$SCRIPT" snapshot --state-dir "$_sd" --projeto-alvo-path "$_gdir"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "snapshot exit" "obtido $_CAPTURED_EXIT"; return 1; }

  mkdir -p "$_gdir/cli"
  printf 'helper\n' > "$_gdir/cli/new-helper.sh"

  capture "$SCRIPT" stage-derived --state-dir "$_sd" --projeto-alvo-path "$_gdir"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "stage-derived exit" "obtido $_CAPTURED_EXIT"; return 1; }

  _staged=$(git -C "$_gdir" diff --cached --name-only)
  case "$_staged" in
    *"cli/new-helper.sh"*) : ;;
    *) _fail "new-helper.sh deveria estar staged" "obtido: $_staged"; return 1 ;;
  esac
  case "$_staged" in
    *alien.pptx*) _fail "alien.pptx nao deveria estar staged" "obtido: $_staged"; return 1 ;;
  esac
}

# ==== 5.3.3: baseline AUSENTE => untracked todos fora, fail-closed ====

scenario_5_3_3_stagederived_baseline_ausente_untracked_fora() {
  _gdir="$TMPDIR_TEST/repo-nobase"
  _sd="$TMPDIR_TEST/sd-nobase"
  _init_git_repo "$_gdir" "feat/nobase"
  mkdir -p "$_sd"

  printf 'novo\n' > "$_gdir/untracked-novo.txt"
  printf 'a\n' >> "$_gdir/README.md"

  capture "$SCRIPT" stage-derived --state-dir "$_sd" --projeto-alvo-path "$_gdir"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "stage-derived exit" "obtido $_CAPTURED_EXIT"; return 1; }

  case "$_CAPTURED_STDERR" in
    *baseline*) : ;;
    *) _fail "aviso de baseline ausente esperado em stderr" "obtido: $_CAPTURED_STDERR"; return 1 ;;
  esac

  _staged=$(git -C "$_gdir" diff --cached --name-only)
  case "$_staged" in
    *untracked-novo.txt*) _fail "untracked sem baseline nao deveria ser staged" "obtido: $_staged"; return 1 ;;
  esac
  case "$_staged" in
    *README.md*) : ;;
    *) _fail "README.md (tracked) deveria estar staged mesmo sem baseline" "obtido: $_staged"; return 1 ;;
  esac
}

# ==== 5.3.4: allowlist vazia (fixture limpa) => exit 3, nenhum commit ====

scenario_5_3_4_stagederived_allowlist_vazia_exit3() {
  _gdir="$TMPDIR_TEST/repo-clean"
  _sd="$TMPDIR_TEST/sd-clean"
  _init_git_repo "$_gdir" "feat/clean"

  capture "$SCRIPT" snapshot --state-dir "$_sd" --projeto-alvo-path "$_gdir"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "snapshot exit" "obtido $_CAPTURED_EXIT"; return 1; }

  capture "$SCRIPT" stage-derived --state-dir "$_sd" --projeto-alvo-path "$_gdir"
  [ "$_CAPTURED_EXIT" = 3 ] || { _fail "exit esperado 3" "obtido $_CAPTURED_EXIT"; return 1; }

  _cached=$(git -C "$_gdir" diff --cached --name-only)
  [ -z "$_cached" ] || { _fail "diff --cached deveria estar vazio" "obtido: $_cached"; return 1; }
}

# ==== 5.3.6: path com espaco e char nao-ASCII, tracked e untracked ====

scenario_5_3_6_stagederived_paths_espaco_unicode() {
  _gdir="$TMPDIR_TEST/repo-unicode"
  _sd="$TMPDIR_TEST/sd-unicode"
  mkdir -p "$_gdir"
  git -C "$_gdir" init -q
  git -C "$_gdir" config user.email "test@test.com"
  git -C "$_gdir" config user.name "Test"
  printf 'a\n' > "$_gdir/tracked file.txt"
  git -C "$_gdir" add -A 2>/dev/null
  git -C "$_gdir" commit -q -m init 2>/dev/null
  git -C "$_gdir" checkout -q -b "feat/unicode" 2>/dev/null

  capture "$SCRIPT" snapshot --state-dir "$_sd" --projeto-alvo-path "$_gdir"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "snapshot exit" "obtido $_CAPTURED_EXIT"; return 1; }

  printf 'b\n' >> "$_gdir/tracked file.txt"
  printf 'n\n' > "$_gdir/new \303\274nicode file.txt"

  capture "$SCRIPT" stage-derived --state-dir "$_sd" --projeto-alvo-path "$_gdir"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "stage-derived exit" "obtido $_CAPTURED_EXIT stderr='$_CAPTURED_STDERR'"; return 1; }

  _count=$(git -C "$_gdir" diff --cached --name-only | wc -l | tr -d ' ')
  [ "$_count" = 2 ] || { _fail "esperado 2 paths staged (tracked+unicode)" "obtido $_count: $(git -C "$_gdir" diff --cached --name-only)"; return 1; }
}

# ==== rename: path novo staged, path antigo descartado (formato -z) ====

scenario_stagederived_rename_stage_path_novo() {
  _gdir="$TMPDIR_TEST/repo-rename"
  _sd="$TMPDIR_TEST/sd-rename"
  _init_git_repo "$_gdir" "feat/rename"
  printf 'conteudo estavel o suficiente para o git detectar rename\n' > "$_gdir/oldname.txt"
  git -C "$_gdir" add -A 2>/dev/null
  git -C "$_gdir" commit -q -m "add oldname" 2>/dev/null

  capture "$SCRIPT" snapshot --state-dir "$_sd" --projeto-alvo-path "$_gdir"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "snapshot exit" "obtido $_CAPTURED_EXIT"; return 1; }

  git -C "$_gdir" mv oldname.txt newname.txt 2>/dev/null

  capture "$SCRIPT" stage-derived --state-dir "$_sd" --projeto-alvo-path "$_gdir"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "stage-derived exit" "obtido $_CAPTURED_EXIT"; return 1; }

  _staged=$(git -C "$_gdir" diff --cached --name-status)
  case "$_staged" in
    *newname.txt*) : ;;
    *) _fail "newname.txt deveria estar staged" "obtido: $_staged"; return 1 ;;
  esac
}

# ==== roundtrip real: git show --name-only HEAD confirma alheio ausente em TODOS os commits ====

scenario_5_3_5_roundtrip_git_show_alien_ausente() {
  _gdir="$TMPDIR_TEST/repo-roundtrip"
  _sd="$TMPDIR_TEST/sd-roundtrip"
  _init_git_repo "$_gdir" "feat/roundtrip"
  printf 'alien\n' > "$_gdir/alien.pptx"

  capture "$SCRIPT" snapshot --state-dir "$_sd" --projeto-alvo-path "$_gdir"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "snapshot exit" "obtido $_CAPTURED_EXIT"; return 1; }

  printf 'novo\n' > "$_gdir/legit.txt"
  capture "$SCRIPT" stage-derived --state-dir "$_sd" --projeto-alvo-path "$_gdir"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "stage-derived exit" "obtido $_CAPTURED_EXIT"; return 1; }

  git -C "$_gdir" commit -q -m "add legit.txt" 2>/dev/null

  _shown=$(git -C "$_gdir" show --name-only --format= HEAD)
  case "$_shown" in
    *alien.pptx*) _fail "alien.pptx nao deveria aparecer no commit real" "obtido: $_shown"; return 1 ;;
  esac
  case "$_shown" in
    *legit.txt*) : ;;
    *) _fail "legit.txt deveria estar no commit" "obtido: $_shown"; return 1 ;;
  esac
}

# ==== sug-008: PR OPEN pre-existente NAO dispensa o push ====
# Regressao de campo (state-mcp-server): finalize retornava pr-exists sem
# empurrar, deixando commits locais fora do PR aberto.

scenario_finalize_pr_aberto_ainda_empurra_push() {
  _gdir="$TMPDIR_TEST/repo-propen"
  _sd="$TMPDIR_TEST/fin-propen"
  _init_state "$_sd" true
  _init_git_repo "$_gdir" "feat/pr-open"

  git -C "$_gdir" branch main 2>/dev/null || :
  git -C "$_gdir" update-ref refs/remotes/origin/main "$(git -C "$_gdir" rev-parse main)" 2>/dev/null || :
  git -C "$_gdir" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main 2>/dev/null || :

  # Remote REAL (bare) para o push acontecer de verdade.
  _bare="$TMPDIR_TEST/origin-propen.git"
  git init -q --bare "$_bare" 2>/dev/null
  git -C "$_gdir" remote add origin "$_bare" 2>/dev/null

  printf 'change\n' >> "$_gdir/README.md"
  git -C "$_gdir" add README.md 2>/dev/null
  git -C "$_gdir" commit -q -m "feat: change" 2>/dev/null
  _head_sha=$(git -C "$_gdir" rev-parse HEAD)

  # gh stub: autenticado; pr view responde OPEN; pr create NUNCA deve rodar.
  _stub="$TMPDIR_TEST/stub-propen"
  mkdir -p "$_stub"
  cat > "$_stub/gh" <<GHEOF
#!/bin/sh
case "\$1 \$2" in
  "auth status") exit 0 ;;
  "pr view")     printf '{"url":"https://example.test/pr/1","state":"OPEN"}\n'; exit 0 ;;
  "pr create")   printf 'create-nao-deveria-rodar\n' >> "$_stub/pr-create-called"; exit 1 ;;
  *) exit 1 ;;
esac
GHEOF
  chmod +x "$_stub/gh"

  _orig_path="$PATH"
  PATH="$_stub:$_orig_path"
  export PATH

  capture "$SCRIPT" finalize --state-dir "$_sd" --projeto-alvo-path "$_gdir"
  _fin_exit=$_CAPTURED_EXIT
  _fin_out=$_CAPTURED_STDOUT

  PATH="$_orig_path"
  export PATH

  [ "$_fin_exit" = 0 ] || { _fail "exit esperado 0" "obtido $_fin_exit"; return 1; }
  printf '%s' "$_fin_out" | grep -q '"status":"pr-exists"' \
    || { _fail "status esperado pr-exists" "stdout: $_fin_out"; return 1; }
  # A prova do sug-008: o remoto bare TEM o commit local apos o finalize.
  _remote_sha=$(git -C "$_bare" rev-parse refs/heads/feat/pr-open 2>/dev/null) || _remote_sha=""
  [ "$_remote_sha" = "$_head_sha" ] \
    || { _fail "push nao aconteceu com PR OPEN (sug-008)" "remoto=$_remote_sha esperado=$_head_sha"; return 1; }
  [ ! -f "$_stub/pr-create-called" ] \
    || { _fail "pr create nao deveria rodar com PR pre-existente" "foi chamado"; return 1; }
}

# ==== sug-007: sem --title/--body, pr create usa --fill ====
# Regressao de campo: gh nao-interativo FALHA sem title/body — finalize
# empurrava a branch e nunca criava o PR.

scenario_finalize_sem_titulo_usa_fill() {
  _gdir="$TMPDIR_TEST/repo-fill"
  _sd="$TMPDIR_TEST/fin-fill"
  _init_state "$_sd" true
  _init_git_repo "$_gdir" "feat/fill"

  git -C "$_gdir" branch main 2>/dev/null || :
  git -C "$_gdir" update-ref refs/remotes/origin/main "$(git -C "$_gdir" rev-parse main)" 2>/dev/null || :
  git -C "$_gdir" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main 2>/dev/null || :

  _bare="$TMPDIR_TEST/origin-fill.git"
  git init -q --bare "$_bare" 2>/dev/null
  git -C "$_gdir" remote add origin "$_bare" 2>/dev/null

  printf 'change\n' >> "$_gdir/README.md"
  git -C "$_gdir" add README.md 2>/dev/null
  git -C "$_gdir" commit -q -m "feat: change" 2>/dev/null

  # gh stub: sem PR previo (view falha); pr create grava argv e responde URL.
  _stub="$TMPDIR_TEST/stub-fill"
  mkdir -p "$_stub"
  cat > "$_stub/gh" <<GHEOF
#!/bin/sh
case "\$1 \$2" in
  "auth status") exit 0 ;;
  "pr view")     exit 1 ;;
  "pr create")   printf '%s\n' "\$*" > "$_stub/pr-create-args"
                 printf 'https://example.test/pr/2\n'; exit 0 ;;
  *) exit 1 ;;
esac
GHEOF
  chmod +x "$_stub/gh"

  _orig_path="$PATH"
  PATH="$_stub:$_orig_path"
  export PATH

  capture "$SCRIPT" finalize --state-dir "$_sd" --projeto-alvo-path "$_gdir"
  _fin_exit=$_CAPTURED_EXIT
  _fin_out=$_CAPTURED_STDOUT

  PATH="$_orig_path"
  export PATH

  [ "$_fin_exit" = 0 ] || { _fail "exit esperado 0" "obtido $_fin_exit"; return 1; }
  [ -f "$_stub/pr-create-args" ] \
    || { _fail "gh pr create nao foi invocado (sug-007)" "stdout: $_fin_out"; return 1; }
  grep -q -- '--fill' "$_stub/pr-create-args" \
    || { _fail "esperado --fill nos args do pr create" "args: $(cat "$_stub/pr-create-args")"; return 1; }
  if grep -q -- '--title' "$_stub/pr-create-args"; then
    _fail "--title nao deveria aparecer sem input do operador" "args: $(cat "$_stub/pr-create-args")"; return 1
  fi
  printf '%s' "$_fin_out" | grep -q '"status":"pr-opened"' \
    || { _fail "status esperado pr-opened" "stdout: $_fin_out"; return 1; }
}

run_all_scenarios
