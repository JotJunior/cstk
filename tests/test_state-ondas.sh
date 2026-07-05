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
  capture "$RW" get --state-dir "$_sd" --field '.budgets.tool_calls_current_wave'
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
  capture "$RW" get --state-dir "$_sd" --field '.waves[-1].termination_reason'
  assert_stdout_contains "bloqueio_humano" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.waves[-1].tool_calls'
  assert_stdout_contains "2" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.accumulated_metrics.waves_total'
  assert_stdout_contains "1" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.accumulated_metrics.tool_calls_total'
  assert_stdout_contains "2" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.waves[-1].executed_stages'
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
  capture "$RW" get --state-dir "$_sd" --field '.waves[-1].next_wave_scheduled_for'
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
  capture "$RW" get --state-dir "$_sd" --field '.waves[-1].skills_invoked[0].skill'
  assert_stdout_contains "briefing" || return 1
}

scenario_record_skill_idempotente_mesma_skill_e_decisao() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" record-skill --state-dir "$_sd" --skill constitution --decisao-id dec-004
  capture "$SCRIPT" record-skill --state-dir "$_sd" --skill constitution --decisao-id dec-004
  assert_stdout_contains "1" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.waves[-1].skills_invoked | length'
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
  capture "$RW" get --state-dir "$_sd" --field '.waves[-1].skills_invoked[0].decision_id'
  assert_stdout_contains "null" || return 1
}

# ==== record-skill --kind (higiene da metrica de skills, revisao 5.15.0) ====

scenario_record_skill_kind_default_e_skill() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" record-skill --state-dir "$_sd" --skill specify --decisao-id dec-001
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "$_CAPTURED_STDERR"; return 1; }
  capture "$RW" get --state-dir "$_sd" --field '.waves[-1].skills_invoked[0].kind'
  assert_stdout_contains "skill" || return 1
}

scenario_record_skill_kind_gate_gravado() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" record-skill --state-dir "$_sd" \
    --skill validate-tasks-template --decisao-id dec-002 --kind gate
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "$_CAPTURED_STDERR"; return 1; }
  capture "$RW" get --state-dir "$_sd" --field '.waves[-1].skills_invoked[0].kind'
  assert_stdout_contains "gate" || return 1
}

scenario_record_skill_kind_invalido_usage() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" record-skill --state-dir "$_sd" --skill x --kind tool
  if [ "$_CAPTURED_EXIT" != 2 ]; then
    _fail "kind invalido exit" "esperado 2, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "kind" || return 1
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
  capture "$RW" get --state-dir "$_sd" --field '.waves[-1].skills_invoked'
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "[]" || return 1
}

# ==== record-task (.tasks[] auditavel — rede contra perda de tasks) ====
scenario_record_task_append_basico() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" record-task --state-dir "$_sd" --task-id 1.1 \
    --titulo "Setup" --outcome pass --testes-rodados 3 --testes-passados 3 \
    --lint-ok true --arquivos '["a.go"]' --origem execute-task
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "record-task" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "1" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.tasks[0].task_id'
  assert_stdout_contains "1.1" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.tasks[0].wave_id'
  assert_stdout_contains "onda-001" || return 1
}

scenario_record_task_nao_exige_onda() {
  # .tasks[] e top-level; record-task funciona sem onda em andamento
  # (diferente de record-skill). Garante back-fill em review-task.
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" record-task --state-dir "$_sd" --task-id 9.9 --outcome pass
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "record-task sem onda" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "1" || return 1
}

scenario_record_task_upsert_idempotente() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" record-task --state-dir "$_sd" --task-id 1.1 --titulo "v1" --outcome pass
  capture "$SCRIPT" record-task --state-dir "$_sd" --task-id 1.1 --titulo "v2" --outcome fail
  assert_stdout_contains "1" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.tasks | length'
  assert_stdout_contains "1" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.tasks[0].title'
  assert_stdout_contains "v2" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.tasks[0].outcome'
  assert_stdout_contains "fail" || return 1
}

scenario_record_task_if_absent_nao_clobbera() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" record-task --state-dir "$_sd" --task-id 1.1 --titulo "real" --outcome pass --origem execute-task
  capture "$SCRIPT" record-task --state-dir "$_sd" --task-id 1.1 --titulo "derivada" --outcome pass --origem reconcile --if-absent
  assert_stdout_contains "1" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.tasks[0].title'
  assert_stdout_contains "real" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.tasks[0].source'
  assert_stdout_contains "execute-task" || return 1
}

scenario_record_task_multiplas_acumulam() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" record-task --state-dir "$_sd" --task-id 1.1 --outcome pass
  capture "$SCRIPT" record-task --state-dir "$_sd" --task-id 1.2 --outcome pass
  capture "$SCRIPT" record-task --state-dir "$_sd" --task-id 1.3 --outcome fail
  assert_stdout_contains "3" || return 1
}

scenario_record_task_valida_outcome() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  assert_exit 2 "$SCRIPT" record-task --state-dir "$_sd" --task-id 1.1 --outcome talvez || return 1
}

scenario_record_task_valida_testes_passados_le_rodados() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  assert_exit 2 "$SCRIPT" record-task --state-dir "$_sd" --task-id 1.1 --outcome pass \
    --testes-rodados 1 --testes-passados 5 || return 1
}

scenario_record_task_valida_arquivos_array() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  assert_exit 2 "$SCRIPT" record-task --state-dir "$_sd" --task-id 1.1 --outcome pass \
    --arquivos 'naoarray' || return 1
}

scenario_record_task_obriga_flags() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  assert_exit 2 "$SCRIPT" record-task --state-dir "$_sd" --outcome pass || return 1
  assert_exit 2 "$SCRIPT" record-task --state-dir "$_sd" --task-id 1.1 || return 1
}

# ==== reconcile-tasks (rede deterministica contra perda — fonte: tasks.md) ====
_write_tasks_md() {
  # backlog com mix de estados: 1.1 e 1.3 concluidas; 1.2 parcial; 2.1 bloqueada;
  # 2.1.1-bis (emergente) concluida.
  cat > "$1" <<'TASKS'
# Tarefas Projeto X

## FASE 1 - Fundacao

### 1.1 Setup do Projeto `[A]`

- [x] 1.1.1 Criar repo
- [x] 1.1.2 CI

### 1.2 Dominio `[C]`

- [x] 1.2.1 Entidades
- [ ] 1.2.2 Regras

### 1.3 Persistencia `[A]`

- [x] 1.3.1 Migrations
- [x] 1.3.2 Repo

## FASE 2 - Backend

### 2.1 Handlers `[A]`

- [!] 2.1.1 Bloqueada
- [x] 2.1.2 Outra

### 2.1.1-bis Hotfix emergente `[C]`

- [x] 2.1.1-bis.1 patch

## Resumo Quantitativo

| Fase | Tarefas |
|------|---------|
TASKS
}

scenario_reconcile_tasks_dry_run_lista_concluidas_ausentes() {
  _sd="$TMPDIR_TEST/state"
  _md="$TMPDIR_TEST/tasks.md"
  _init_state "$_sd"
  capture "$SCRIPT" start --state-dir "$_sd"
  _write_tasks_md "$_md"
  capture "$SCRIPT" reconcile-tasks --state-dir "$_sd" --tasks-md "$_md" --dry-run
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "reconcile dry-run" "$_CAPTURED_STDERR"; return 1; }
  # concluidas e ausentes: 1.1, 1.3, 2.1.1-bis
  assert_stdout_contains "1.1" || return 1
  assert_stdout_contains "1.3" || return 1
  assert_stdout_contains "2.1.1-bis" || return 1
}

scenario_reconcile_tasks_ignora_pendentes_e_bloqueadas() {
  _sd="$TMPDIR_TEST/state"
  _md="$TMPDIR_TEST/tasks.md"
  _init_state "$_sd"
  _write_tasks_md "$_md"
  capture "$SCRIPT" reconcile-tasks --state-dir "$_sd" --tasks-md "$_md"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "reconcile apply" "$_CAPTURED_STDERR"; return 1; }
  # 3 concluidas back-filled (1.1, 1.3, 2.1.1-bis). 1.2 (parcial) e 2.1 ([!]) fora.
  assert_stdout_contains "3" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.tasks | length'
  assert_stdout_contains "3" || return 1
  # equidade exata (NAO contains, que faz match de substring: "2.1.1-bis" ~ "2.1")
  capture "$RW" get --state-dir "$_sd" --field '[.tasks[].task_id] | any(. == "1.2")'
  assert_stdout_contains "false" || return 1
  capture "$RW" get --state-dir "$_sd" --field '[.tasks[].task_id] | any(. == "2.1")'
  assert_stdout_contains "false" || return 1
  # mas a emergente 2.1.1-bis (concluida) DEVE estar presente
  capture "$RW" get --state-dir "$_sd" --field '[.tasks[].task_id] | any(. == "2.1.1-bis")'
  assert_stdout_contains "true" || return 1
}

scenario_reconcile_tasks_extrai_titulo_sem_criticidade() {
  _sd="$TMPDIR_TEST/state"
  _md="$TMPDIR_TEST/tasks.md"
  _init_state "$_sd"
  _write_tasks_md "$_md"
  capture "$SCRIPT" reconcile-tasks --state-dir "$_sd" --tasks-md "$_md"
  capture "$RW" get --state-dir "$_sd" --field '.tasks[] | select(.task_id=="1.1") | .title'
  assert_stdout_contains "Setup do Projeto" || return 1
  # nao deve carregar a tag de criticidade [A]
  if printf '%s' "$_CAPTURED_STDOUT" | grep -q '\['; then
    _fail "titulo" "titulo carregou tag de criticidade: $_CAPTURED_STDOUT"; return 1
  fi
}

scenario_reconcile_tasks_nao_clobbera_entrada_real() {
  _sd="$TMPDIR_TEST/state"
  _md="$TMPDIR_TEST/tasks.md"
  _init_state "$_sd"
  capture "$SCRIPT" start --state-dir "$_sd"
  # entrada real previa para 1.1 (execute-task)
  capture "$SCRIPT" record-task --state-dir "$_sd" --task-id 1.1 --titulo "REAL" \
    --outcome pass --origem execute-task
  _write_tasks_md "$_md"
  capture "$SCRIPT" reconcile-tasks --state-dir "$_sd" --tasks-md "$_md"
  # so 1.3 e 2.1.1-bis sao novas (1.1 ja existe)
  assert_stdout_contains "2" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.tasks[] | select(.task_id=="1.1") | .title'
  assert_stdout_contains "REAL" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.tasks[] | select(.task_id=="1.1") | .source'
  assert_stdout_contains "execute-task" || return 1
}

scenario_reconcile_tasks_idempotente() {
  _sd="$TMPDIR_TEST/state"
  _md="$TMPDIR_TEST/tasks.md"
  _init_state "$_sd"
  _write_tasks_md "$_md"
  capture "$SCRIPT" reconcile-tasks --state-dir "$_sd" --tasks-md "$_md"
  assert_stdout_contains "3" || return 1
  capture "$SCRIPT" reconcile-tasks --state-dir "$_sd" --tasks-md "$_md"
  assert_stdout_contains "0" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.tasks | length'
  assert_stdout_contains "3" || return 1
}

scenario_reconcile_tasks_md_ausente_falha() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  assert_exit 1 "$SCRIPT" reconcile-tasks --state-dir "$_sd" \
    --tasks-md "$TMPDIR_TEST/nao-existe.md" || return 1
}

scenario_reconcile_tasks_obriga_flags() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  assert_exit 2 "$SCRIPT" reconcile-tasks --state-dir "$_sd" || return 1
}

# ---- cura de titulos vazios (onda execute-task longa gravada em lote) ----
scenario_reconcile_tasks_cura_titulo_vazio() {
  _sd="$TMPDIR_TEST/state"
  _md="$TMPDIR_TEST/tasks.md"
  _init_state "$_sd"
  capture "$SCRIPT" start --state-dir "$_sd"
  # entrada real previa SEM --titulo (title="") com tests 39/39 — replica o
  # sintoma do lote de onda-009.
  capture "$SCRIPT" record-task --state-dir "$_sd" --task-id 1.1 \
    --outcome pass --testes-rodados 39 --testes-passados 39 --origem execute-task
  _write_tasks_md "$_md"
  capture "$SCRIPT" reconcile-tasks --state-dir "$_sd" --tasks-md "$_md"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "reconcile cura" "$_CAPTURED_STDERR"; return 1; }
  # titulo curado a partir do heading em tasks.md
  capture "$RW" get --state-dir "$_sd" --field '.tasks[] | select(.task_id=="1.1") | .title'
  assert_stdout_contains "Setup do Projeto" || return 1
  # NAO carrega a tag de criticidade
  if printf '%s' "$_CAPTURED_STDOUT" | grep -q '\['; then
    _fail "cura titulo" "titulo curado carregou tag: $_CAPTURED_STDOUT"; return 1
  fi
  # tests_run/passed PRESERVADOS (39/39) — cura nunca fabrica/zera contagem
  capture "$RW" get --state-dir "$_sd" --field '.tasks[] | select(.task_id=="1.1") | .tests_run'
  assert_stdout_contains "39" || return 1
}

scenario_reconcile_tasks_cura_titulo_nivel_checkbox() {
  # onda execute-task longa grava no nivel do CHECKBOX (N.M.K), nao do heading;
  # o titulo deve ser curado a partir do texto do checkbox em tasks.md.
  _sd="$TMPDIR_TEST/state"
  _md="$TMPDIR_TEST/tasks.md"
  _init_state "$_sd"
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" record-task --state-dir "$_sd" --task-id 1.1.1 \
    --outcome pass --testes-rodados 39 --testes-passados 39 --origem execute-task
  _write_tasks_md "$_md"
  capture "$SCRIPT" reconcile-tasks --state-dir "$_sd" --tasks-md "$_md"
  capture "$RW" get --state-dir "$_sd" --field '.tasks[] | select(.task_id=="1.1.1") | .title'
  assert_stdout_contains "Criar repo" || return 1
}

scenario_reconcile_tasks_cura_nao_clobbera_titulo_existente() {
  _sd="$TMPDIR_TEST/state"
  _md="$TMPDIR_TEST/tasks.md"
  _init_state "$_sd"
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" record-task --state-dir "$_sd" --task-id 1.1 --titulo "REAL" \
    --outcome pass --origem execute-task
  _write_tasks_md "$_md"
  capture "$SCRIPT" reconcile-tasks --state-dir "$_sd" --tasks-md "$_md"
  capture "$RW" get --state-dir "$_sd" --field '.tasks[] | select(.task_id=="1.1") | .title'
  assert_stdout_contains "REAL" || return 1
}

scenario_reconcile_tasks_dry_run_nao_cura() {
  _sd="$TMPDIR_TEST/state"
  _md="$TMPDIR_TEST/tasks.md"
  _init_state "$_sd"
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" record-task --state-dir "$_sd" --task-id 1.1 \
    --outcome pass --origem execute-task
  _write_tasks_md "$_md"
  capture "$SCRIPT" reconcile-tasks --state-dir "$_sd" --tasks-md "$_md" --dry-run
  # dry-run nao escreve: title de 1.1 permanece vazio
  capture "$RW" get --state-dir "$_sd" --field '.tasks[] | select(.task_id=="1.1") | .title'
  if [ -n "$_CAPTURED_STDOUT" ] && [ "$_CAPTURED_STDOUT" != "" ]; then
    _fail "dry-run cura" "dry-run alterou o titulo: [$_CAPTURED_STDOUT]"; return 1
  fi
}

# ==== back-compat pt-BR (schema-en-migration §6: readers leem state legado) ====
# Os writers do state-ondas assumem EN-on-disk (garantido pelo migrate
# defensivo do command-pai), igual ao exemplar drift.sh mark-touched. O que
# DEVE continuar funcionando em state legado/misto sao os READERS, via fallback
# (.en // .pt). Estes cenarios montam state.json com chaves pt-BR direto no
# disco (SEM passar por state-rw.sh init, que ja produz EN) e provam que os
# readers ainda leem os valores pt.

# state legado puro pt-BR com 1 onda + orcamentos pt (sem nenhuma chave EN).
_write_legacy_ptbr_state() {
  jq -n '{
    schema_version: 6,
    ondas: [
      { id: "onda-007", inicio: "2026-05-01T10:00:00Z", fim: null,
        etapas_executadas: ["briefing"], tool_calls: 0, wallclock_seconds: 0,
        motivo_termino: null, proxima_onda_agendada_para: null,
        skills_invoked: [] }
    ],
    orcamentos: { tool_calls_onda_corrente: 4, inicio_onda_corrente: "2026-05-01T10:00:00Z" },
    metricas_acumuladas: { ondas_total: 6, tool_calls_total: 50 }
  }' > "$1/state.json"
}

scenario_ptbr_legacy_current_id_le_via_fallback() {
  # current-id le .ondas[-1].id de um state pt-BR puro.
  _sd="$TMPDIR_TEST/state"
  mkdir -p "$_sd"
  _write_legacy_ptbr_state "$_sd"
  capture "$SCRIPT" current-id --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "ptbr current-id" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "onda-007" || return 1
}

scenario_ptbr_legacy_tool_call_tick_le_e_converge() {
  # tool-call-tick le o contador pt (.orcamentos.tool_calls_onda_corrente=4),
  # incrementa para 5 e ESCREVE em chave EN (.budgets.tool_calls_current_wave).
  _sd="$TMPDIR_TEST/state"
  mkdir -p "$_sd"
  _write_legacy_ptbr_state "$_sd"
  capture "$SCRIPT" tool-call-tick --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "ptbr tick" "$_CAPTURED_STDERR"; return 1; }
  # leu 4 (pt) -> 5
  assert_stdout_contains "5" || return 1
  # convergencia EN-on-disk: o writer grava a chave EN
  capture "$RW" get --state-dir "$_sd" --field '.budgets.tool_calls_current_wave'
  assert_stdout_contains "5" || return 1
}

scenario_ptbr_legacy_start_next_num_le_via_fallback() {
  # start deriva o proximo numero de onda lendo .ondas (pt, max=onda-007 => 008)
  # e grava a nova onda em chave EN (.waves).
  _sd="$TMPDIR_TEST/state"
  mkdir -p "$_sd"
  _write_legacy_ptbr_state "$_sd"
  capture "$SCRIPT" start --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "ptbr start" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "onda-008" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.waves[-1].id'
  assert_stdout_contains "onda-008" || return 1
}

scenario_ptbr_legacy_end_le_tool_calls_via_fallback() {
  # end consolida tool_calls da onda lendo o contador pt
  # (.orcamentos.tool_calls_onda_corrente). Onda em EN (.waves) ja existe — o
  # cenario que o migrate defensivo produz: container EN + orcamentos legado pt.
  _sd="$TMPDIR_TEST/state"
  mkdir -p "$_sd"
  jq -n '{
    schema_version: 6,
    waves: [
      { id: "onda-003", started_at: "2026-05-01T10:00:00Z", finished_at: null,
        executed_stages: [], tool_calls: 0, wallclock_seconds: 0,
        termination_reason: null, next_wave_scheduled_for: null, skills_invoked: [] }
    ],
    orcamentos: { tool_calls_onda_corrente: 9, inicio_onda_corrente: "2026-05-01T10:00:00Z" }
  }' > "$_sd/state.json"
  capture "$SCRIPT" end --state-dir "$_sd" --motivo-termino concluido
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "ptbr end" "$_CAPTURED_STDERR"; return 1; }
  # leu 9 do contador pt e gravou em waves[-1].tool_calls (chave EN)
  capture "$RW" get --state-dir "$_sd" --field '.waves[-1].tool_calls'
  assert_stdout_contains "9" || return 1
}

scenario_ptbr_legacy_record_skill_idempotencia_le_decisao_id() {
  # A idempotencia do record-skill compara decisao_id da entrada existente.
  # Entrada legada usa a chave pt `decisao_id`; o reader le via fallback
  # (.decision_id // .decisao_id), entao re-registrar a mesma skill+decisao
  # NAO duplica.
  _sd="$TMPDIR_TEST/state"
  mkdir -p "$_sd"
  jq -n '{
    schema_version: 6,
    waves: [
      { id: "onda-001", started_at: "2026-05-01T10:00:00Z", finished_at: null,
        executed_stages: [], tool_calls: 0, wallclock_seconds: 0,
        termination_reason: null, next_wave_scheduled_for: null,
        skills_invoked: [ { skill: "briefing", timestamp: "t", decisao_id: "dec-001" } ] }
    ]
  }' > "$_sd/state.json"
  capture "$SCRIPT" record-skill --state-dir "$_sd" --skill briefing --decisao-id dec-001
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "ptbr record-skill" "$_CAPTURED_STDERR"; return 1; }
  # idempotente: continua 1 (a entrada pt foi reconhecida via fallback)
  assert_stdout_contains "1" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.waves[-1].skills_invoked | length'
  assert_stdout_contains "1" || return 1
}

# ---------------------------------------------------------------------------
# wave-status + reconcile-wave (rede de seguranca anti "onda nao fechada")
# ---------------------------------------------------------------------------

scenario_wave_status_none_quando_sem_onda() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" wave-status --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "wave-status" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "none" || return 1
}

scenario_wave_status_open_apos_start() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" wave-status --state-dir "$_sd"
  assert_stdout_contains "open" || return 1
}

scenario_wave_status_closed_apos_end() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" end --state-dir "$_sd" --motivo-termino etapa_concluida_avancando
  capture "$SCRIPT" wave-status --state-dir "$_sd"
  assert_stdout_contains "closed" || return 1
}

scenario_reconcile_wave_noop_quando_fechada() {
  # Onda ja fechada -> NO-OP (exit 0, stdout "noop (closed)"). E a guarda que
  # torna seguro o pai chamar reconcile-wave a CADA onda.
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" end --state-dir "$_sd" --motivo-termino etapa_concluida_avancando
  capture "$SCRIPT" reconcile-wave --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "reconcile noop" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "noop" || return 1
}

scenario_reconcile_wave_noop_quando_sem_onda() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" reconcile-wave --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "reconcile noop none" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "noop (none)" || return 1
}

scenario_reconcile_wave_fecha_e_avanca_ponteiro() {
  # Onda aberta na fase specify -> fecha (etapa_concluida_avancando) e avanca
  # current_stage para clarify. E a recuperacao deterministica do bug
  # "orquestrador parou cedo sem fechar a onda".
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$RW" set --state-dir "$_sd" --field '.current_stage' --value '"specify"'
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" reconcile-wave --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "reconcile open" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "reconciled" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.current_stage'
  assert_stdout_contains "clarify" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.waves[-1].termination_reason'
  assert_stdout_contains "etapa_concluida_avancando" || return 1
  # skill da fase registrada (audit)
  capture "$RW" get --state-dir "$_sd" --field '.waves[-1].skills_invoked | length'
  assert_stdout_contains "1" || return 1
}

scenario_reconcile_wave_idempotente_nao_double_conta() {
  # Re-chamada apos reconciliar NAO incrementa accumulated_metrics.waves_total
  # nem re-avanca o ponteiro (guarda de idempotencia). Protege contra o pai
  # chamar reconcile-wave em onda que o orquestrador JA fechou corretamente.
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$RW" set --state-dir "$_sd" --field '.current_stage' --value '"specify"'
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" reconcile-wave --state-dir "$_sd"
  capture "$RW" get --state-dir "$_sd" --field '.accumulated_metrics.waves_total'
  assert_stdout_contains "1" || return 1
  # segunda chamada: noop
  capture "$SCRIPT" reconcile-wave --state-dir "$_sd"
  assert_stdout_contains "noop" || return 1
  # waves_total continua 1 (sem double-count)
  capture "$RW" get --state-dir "$_sd" --field '.accumulated_metrics.waves_total'
  assert_stdout_contains "1" || return 1
  # current_stage continua clarify (sem over-advance)
  capture "$RW" get --state-dir "$_sd" --field '.current_stage'
  assert_stdout_contains "clarify" || return 1
}

scenario_reconcile_wave_terminal_promove_status_feature00c() {
  # feature-00c: review-task e terminal. --terminal-phase review-task evita
  # que pipeline.sh avance erroneamente para review-features. Deve promover
  # .execution.status para concluida.
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$RW" set --state-dir "$_sd" --field '.current_stage' --value '"review-task"'
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" reconcile-wave --state-dir "$_sd" --terminal-phase review-task
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "reconcile terminal" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "terminal" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.execution.status'
  assert_stdout_contains "concluida" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.execution.termination_reason'
  assert_stdout_contains "concluido" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.waves[-1].termination_reason'
  assert_stdout_contains "concluido" || return 1
}

scenario_reconcile_wave_sha256_consistente() {
  # Apos reconciliar, o sha256 do state.json deve bater (state-rw.sh set
  # recomputa). Senao o resume seguinte falha o gate de integridade.
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$RW" set --state-dir "$_sd" --field '.current_stage' --value '"plan"'
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" reconcile-wave --state-dir "$_sd"
  assert_exit 0 "$RW" sha256-verify --state-dir "$_sd" || return 1
}

scenario_reconcile_wave_dry_run_nao_escreve() {
  # --dry-run descreve a acao sem fechar a onda nem mexer no ponteiro.
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$RW" set --state-dir "$_sd" --field '.current_stage' --value '"specify"'
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" reconcile-wave --state-dir "$_sd" --dry-run
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "dry-run" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "would reconcile" || return 1
  # onda continua aberta
  capture "$SCRIPT" wave-status --state-dir "$_sd"
  assert_stdout_contains "open" || return 1
  # ponteiro intacto
  capture "$RW" get --state-dir "$_sd" --field '.current_stage'
  assert_stdout_contains "specify" || return 1
}

scenario_reconcile_wave_phase_override() {
  # --phase fixa a fase explicitamente (pai pode pinar), ignorando current_stage.
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$RW" set --state-dir "$_sd" --field '.current_stage' --value '"specify"'
  capture "$SCRIPT" start --state-dir "$_sd"
  capture "$SCRIPT" reconcile-wave --state-dir "$_sd" --phase plan
  assert_stdout_contains "next=checklist" || return 1
}

run_all_scenarios
