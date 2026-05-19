#!/bin/sh
# test_state-ondas.sh — cobre global/skills/agente-00c-runtime/scripts/state-ondas.sh.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/state-ondas.sh"
RW="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/state-rw.sh"

if ! command -v jq >/dev/null 2>&1; then
  printf '# test_state-ondas.sh: jq ausente — pulando suite\n'
  exit 0
fi

_init_state() {
  capture "$RW" init --state-dir "$1" \
    --execucao-id "exec-onda-test" --projeto-alvo-path "/tmp/p" --descricao "POC ondas"
}

scenario_start_cria_onda_001() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" start --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "start" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "onda-001" || return 1
  capture "$SCRIPT" current-id --state-dir "$_sd"
  assert_stdout_contains "onda-001" || return 1
}

scenario_start_sequencial_gera_onda_002() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" end --state-dir "$_sd" --motivo-termino etapa_concluida_avancando
  capture "$SCRIPT" start --state-dir "$_sd"
  assert_stdout_contains "onda-002" || return 1
}

scenario_tool_call_tick_incrementa() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" tool-call-tick --state-dir "$_sd"
  assert_stdout_contains "1" || return 1
  capture "$SCRIPT" tool-call-tick --state-dir "$_sd"
  assert_stdout_contains "2" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.orcamentos.tool_calls_onda_corrente'
  assert_stdout_contains "2" || return 1
}

scenario_end_atualiza_onda_e_acumulados() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" tool-call-tick --state-dir "$_sd"
  capture "$SCRIPT" tool-call-tick --state-dir "$_sd"
  capture "$SCRIPT" end --state-dir "$_sd" --motivo-termino bloqueio_humano \
    --add-etapa briefing
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "end" "$_CAPTURED_STDERR"; return 1; }
  capture "$RW" get --state-dir "$_sd" --field '.ondas[-1].motivo_termino'
  assert_stdout_contains "bloqueio_humano" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.ondas[-1].tool_calls'
  assert_stdout_contains "2" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.metricas_acumuladas.ondas_total'
  assert_stdout_contains "1" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.metricas_acumuladas.tool_calls_total'
  assert_stdout_contains "2" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.ondas[-1].etapas_executadas'
  assert_stdout_contains "briefing" || return 1
}

scenario_end_motivo_invalido_falha() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" end --state-dir "$_sd" --motivo-termino motivo_invalido
  if [ "$_CAPTURED_EXIT" != 2 ]; then
    _fail "motivo invalido" "esperado 2, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_end_sem_onda_em_andamento_falha() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" end --state-dir "$_sd" --motivo-termino etapa_concluida_avancando
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "end sem onda" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_proxima_agendada_para_persiste() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" end --state-dir "$_sd" --motivo-termino etapa_concluida_avancando \
    --proxima-agendada-para "2026-05-05T15:30:00Z"
  capture "$RW" get --state-dir "$_sd" --field '.ondas[-1].proxima_onda_agendada_para'
  assert_stdout_contains "2026-05-05T15:30:00Z" || return 1
}

scenario_current_id_retorna_init_sem_onda() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" current-id --state-dir "$_sd"
  assert_stdout_contains "init" || return 1
}

scenario_git_commit_cria_commit() {
  _sd="$TMPDIR_TEST/state"
  _pap="$TMPDIR_TEST/proj"
  _init_state "$_sd"
  mkdir -p "$_pap"
  ( cd "$_pap" && git init -q -b main \
    && git config user.email t@t \
    && git config user.name t \
    && touch hello.txt )
  capture "$SCRIPT" git-commit --state-dir "$_sd" --projeto-alvo-path "$_pap" \
    --motivo "test commit FASE 3"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "commit" "$_CAPTURED_STDERR"; return 1; }
  _msg=$(git -C "$_pap" log -1 --pretty=%s)
  case "$_msg" in
    *"chore(agente-00c):"*"test commit FASE 3"*) ;;
    *) _fail "commit msg" "esperado contem 'chore(agente-00c)' e motivo; obtido: $_msg"; return 1 ;;
  esac
}

scenario_git_commit_idempotente_sem_changes() {
  _sd="$TMPDIR_TEST/state"
  _pap="$TMPDIR_TEST/proj"
  _init_state "$_sd"
  mkdir -p "$_pap"
  ( cd "$_pap" && git init -q -b main \
    && git config user.email t@t && git config user.name t \
    && touch x && git add . && git commit -q -m initial )
  capture "$SCRIPT" git-commit --state-dir "$_sd" --projeto-alvo-path "$_pap" \
    --motivo "noop"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "no-op exit" "$_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "nada para commitar" || return 1
}

scenario_git_commit_sem_repo_falha() {
  _sd="$TMPDIR_TEST/state"
  _pap="$TMPDIR_TEST/notrepo"
  _init_state "$_sd"
  mkdir -p "$_pap"
  capture "$SCRIPT" git-commit --state-dir "$_sd" --projeto-alvo-path "$_pap" \
    --motivo "x"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "sem repo" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "nao e repositorio git" || return 1
}

# ==== record-skill (defesa contra dec-014 da exec rolledback) ====
scenario_record_skill_append_basico() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" record-skill --state-dir "$_sd" --skill briefing --decisao-id dec-001
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "$_CAPTURED_EXIT; $_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "1" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.ondas[-1].skills_invoked[0].skill'
  assert_stdout_contains "briefing" || return 1
}

scenario_record_skill_idempotente_mesma_skill_e_decisao() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" record-skill --state-dir "$_sd" --skill constitution --decisao-id dec-004
  capture "$SCRIPT" record-skill --state-dir "$_sd" --skill constitution --decisao-id dec-004
  assert_stdout_contains "1" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.ondas[-1].skills_invoked | length'
  assert_stdout_contains "1" || return 1
}

scenario_record_skill_multiplas_skills_acumulam() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" record-skill --state-dir "$_sd" --skill briefing --decisao-id dec-001
  capture "$SCRIPT" record-skill --state-dir "$_sd" --skill constitution --decisao-id dec-004
  capture "$SCRIPT" record-skill --state-dir "$_sd" --skill create-tasks --decisao-id dec-014
  assert_stdout_contains "3" || return 1
}

scenario_record_skill_sem_decisao_id_funciona() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" record-skill --state-dir "$_sd" --skill briefing
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "1" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.ondas[-1].skills_invoked[0].decisao_id'
  assert_stdout_contains "null" || return 1
}

scenario_record_skill_sem_onda_falha() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  # Nao chamar start
  capture "$SCRIPT" record-skill --state-dir "$_sd" --skill briefing
  if [ "$_CAPTURED_EXIT" = 0 ]; then
    _fail "exit" "esperado != 0, obtido 0"
    return 1
  fi
  assert_stderr_contains "nenhuma onda em andamento" || return 1
}

scenario_record_skill_obriga_flags() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" start --state-dir "$_sd"
  # Sem --skill
  capture "$SCRIPT" record-skill --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" = 0 ]; then
    _fail "exit" "esperado != 0 sem --skill"
    return 1
  fi
  assert_stderr_contains "skill obrigatorio" || return 1
}

scenario_start_inclui_skills_invoked_vazio() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$RW" get --state-dir "$_sd" --field '.ondas[-1].skills_invoked'
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "[]" || return 1
}

run_all_scenarios
