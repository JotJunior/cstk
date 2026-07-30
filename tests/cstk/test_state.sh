#!/bin/sh
# test_state.sh — cobre cli/lib/state.sh (subcomando `cstk state`).
#
# Ref: docs/specs/state-db-foundation/tasks.md FASE 6, task 6.1.2
#      docs/specs/state-db-foundation/contracts/migration.md §Nomeacao
#
# ESCOPO: esta lib e uma SUPERFICIE DE DELEGACAO. O comportamento da migracao
# em si (M1..M6) e coberto por tests/test_state-db-migrate.sh; aqui cobrimos o
# contrato da fronteira: resolucao do script delegado, repasse VERBATIM de
# flags e exit codes, e o tratamento de uso incorreto.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

CSTK_BIN="$REPO_ROOT/cli/cstk"
CSTK_LIB_DIR="$REPO_ROOT/cli/lib"
STATE_RW="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/state-rw.sh"

# _cstk_state ARGS... -> roda `cstk state ARGS` com o layout de repo.
_cstk_state() {
  CSTK_LIB="$CSTK_LIB_DIR" sh "$CSTK_BIN" state "$@"
}

scenario_state_sem_subcomando_mostra_uso() {
  capture _cstk_state
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "uso deveria sair 0" "exit=$_CAPTURED_EXIT"; return 1; }
  case "$_CAPTURED_STDOUT" in
    *migrate*) : ;;
    *) _fail "uso nao documenta migrate" "$_CAPTURED_STDOUT"; return 1 ;;
  esac
}

scenario_state_help_documenta_exit_codes() {
  capture _cstk_state --help
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "--help deveria sair 0" "exit=$_CAPTURED_EXIT"; return 1; }
  case "$_CAPTURED_STDOUT" in
    *"recusado por pre-condicao"*) : ;;
    *) _fail "help nao documenta o exit 3 (recusa)" "$_CAPTURED_STDOUT"; return 1 ;;
  esac
}

scenario_state_subcomando_desconhecido_exit_2() {
  capture _cstk_state naoexiste
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "subcomando invalido deveria ser exit 2" "exit=$_CAPTURED_EXIT"; return 1; }
}

# Repasse VERBATIM do exit 2 (uso incorreto) vindo do script delegado.
scenario_state_migrate_sem_state_dir_repassa_exit_2() {
  capture _cstk_state migrate
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "--state-dir ausente deveria repassar exit 2" "exit=$_CAPTURED_EXIT"; return 1; }
}

# Repasse VERBATIM do exit 3 (RECUSA por pre-condicao M1) — a distincao entre
# "recusado" e "falhou" e o ponto do contrato de exit codes desta lib.
scenario_state_migrate_recusa_repassa_exit_3() {
  if ! command -v jq >/dev/null 2>&1 || ! command -v sqlite3 >/dev/null 2>&1; then
    return 0
  fi
  _sd="$TMPDIR_TEST/sem-state-json"
  mkdir -p "$_sd"
  capture _cstk_state migrate --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 3 ] || { _fail "recusa deveria repassar exit 3" "exit=$_CAPTURED_EXIT stderr=$_CAPTURED_STDERR"; return 1; }
}

# Caminho feliz de ponta a ponta pela superficie do CLI (nao so pelo script).
scenario_state_migrate_caminho_feliz_pelo_cli() {
  if ! command -v jq >/dev/null 2>&1 || ! command -v sqlite3 >/dev/null 2>&1; then
    return 0
  fi
  _sd="$TMPDIR_TEST/ok"
  mkdir -p "$_sd"
  cat > "$_sd/state.json" <<'JSON'
{
  "schema_version": "1.0.0",
  "short_name": "cli-fixture",
  "execution": {
    "id": "exec-cli-001",
    "target_project_path": "/tmp/projeto",
    "target_project_description": "descricao de fixture com tamanho suficiente",
    "status": "concluida",
    "termination_reason": "concluido",
    "started_at": "2026-07-30T10:00:00Z",
    "finished_at": "2026-07-30T12:00:00Z"
  },
  "current_stage": "review-task",
  "next_instruction": "nada a fazer",
  "external_urls_whitelist": [],
  "circular_movement_history": [],
  "initial_key_aspects": ["cli", "state"],
  "accumulated_metrics": {
    "waves_total": 0,
    "tool_calls_total": 0,
    "wallclock_total_seconds": 0,
    "max_depth_reached": 1,
    "subagents_spawned": 0,
    "decisions_total": 0,
    "human_blocks_total": 0,
    "global_skill_suggestions_total": 0,
    "toolkit_issues_opened": 0
  },
  "budgets": {
    "max_recursion": 3,
    "current_subagent_depth": 1,
    "max_retro_executions_per_feature": 2,
    "retro_executions_consumed": 0,
    "max_cycles_per_stage": 5,
    "cycles_consumed_current_stage": 0,
    "tool_calls_threshold_wave": 80,
    "wallclock_threshold_seconds": 5400,
    "state_size_threshold_bytes": 1048576
  },
  "waves": [],
  "decisions": [],
  "human_blocks": [],
  "tasks": [],
  "events": []
}
JSON
  "$STATE_RW" sha256-update --state-dir "$_sd" >/dev/null 2>&1

  capture _cstk_state migrate --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "migracao pelo CLI" "exit=$_CAPTURED_EXIT stderr=$_CAPTURED_STDERR"; return 1; }
  [ -f "$_sd/state.db" ] || { _fail "state.db nao publicado pelo CLI" ""; return 1; }
  [ -f "$_sd/state.json" ] || { _fail "state.json apagado (M6)" ""; return 1; }
}

# A resolucao do script delegado NAO pode depender exclusivamente de
# ~/.claude (licao de campo de recall_secrets_filter_path): com HOME falso e
# CSTK_LIB apontando para a arvore do repo, a camada (2) deve resolver.
scenario_resolucao_do_script_independe_de_home_instalado() {
  _out=$(HOME="$TMPDIR_TEST/home-vazio" CSTK_LIB="$CSTK_LIB_DIR" sh -c '
    . "$CSTK_LIB/state.sh"
    _state_migrate_script_path
  ' 2>/dev/null) || { _fail "resolucao falhou com HOME vazio" ""; return 1; }
  [ -n "$_out" ] || { _fail "caminho vazio" ""; return 1; }
  [ -f "$_out" ] || { _fail "caminho resolvido nao existe" "$_out"; return 1; }
}

# `cstk state` esta registrado nas superficies de descoberta do CLI.
scenario_state_aparece_no_help_geral() {
  capture sh -c "CSTK_LIB='$CSTK_LIB_DIR' sh '$CSTK_BIN' --help"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "help geral" "$_CAPTURED_STDERR"; return 1; }
  case "$_CAPTURED_STDOUT" in
    *"  state "*) : ;;
    *) _fail "cstk --help nao lista o comando state" ""; return 1 ;;
  esac
}

scenario_help_topico_state_sai_zero() {
  capture sh -c "CSTK_LIB='$CSTK_LIB_DIR' sh '$CSTK_BIN' help state"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "cstk help state" "$_CAPTURED_STDERR"; return 1; }
}

run_all_scenarios
