#!/bin/sh
# test_spawn-tracker.sh — cobre global/skills/agente-00c-runtime/scripts/spawn-tracker.sh.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/spawn-tracker.sh"
RW="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/state-rw.sh"

if ! command -v jq >/dev/null 2>&1; then
  printf '# test_spawn-tracker.sh: jq ausente — pulando suite\n'
  exit 0
fi

_init_state() {
  capture "$RW" init --state-dir "$1" \
    --execucao-id "exec-spawn-test" --projeto-alvo-path "/tmp/p" --descricao "POC spawn"
}

scenario_inicial_profundidade_1() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" current --state-dir "$_sd"
  assert_stdout_contains "1" || return 1
}

scenario_check_inicial_passa() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" check --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "check inicial" "$_CAPTURED_EXIT"; return 1; }
}

scenario_enter_incrementa_e_persiste() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" enter --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "enter" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "2" || return 1
  capture "$SCRIPT" current --state-dir "$_sd"
  assert_stdout_contains "2" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.accumulated_metrics.subagents_spawned'
  assert_stdout_contains "1" || return 1
}

scenario_enter_max_atingida_atualizada() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" enter --state-dir "$_sd"
  capture "$SCRIPT" enter --state-dir "$_sd"
  capture "$RW" get --state-dir "$_sd" --field '.accumulated_metrics.max_depth_reached'
  assert_stdout_contains "3" || return 1
}

scenario_enter_excedendo_max_exit_3_sem_modificar_estado() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" enter --state-dir "$_sd"  # 1->2
  capture "$SCRIPT" enter --state-dir "$_sd"  # 2->3
  # Snapshot do estado antes do enter ilegal (state-rw.sh init emite EN)
  _before=$(jq -c '.budgets.current_subagent_depth' "$_sd/state.json")
  capture "$SCRIPT" enter --state-dir "$_sd"  # 3->4 negado
  if [ "$_CAPTURED_EXIT" != 3 ]; then
    _fail "enter ilegal exit" "esperado 3, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "MAX 3" || return 1
  _after=$(jq -c '.budgets.current_subagent_depth' "$_sd/state.json")
  if [ "$_before" != "$_after" ]; then
    _fail "enter negado MUTOU estado" "before=$_before after=$_after"
    return 1
  fi
}

scenario_check_no_limite_exit_3() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" enter --state-dir "$_sd"
  capture "$SCRIPT" enter --state-dir "$_sd"
  capture "$SCRIPT" check --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 3 ]; then
    _fail "check no limite" "esperado 3, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_leave_decrementa() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" enter --state-dir "$_sd"
  capture "$SCRIPT" leave --state-dir "$_sd"
  assert_stdout_contains "1" || return 1
}

scenario_leave_idempotente_no_minimo() {
  _sd="$TMPDIR_TEST/state"
  _init_state "$_sd"
  capture "$SCRIPT" leave --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "leave inicial" "$_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "1" || return 1
  capture "$SCRIPT" current --state-dir "$_sd"
  assert_stdout_contains "1" || return 1
}

scenario_state_ausente_falha() {
  _sd="$TMPDIR_TEST/empty"
  mkdir -p "$_sd"
  capture "$SCRIPT" check --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "state ausente" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

# Escreve um state.json pt-BR LEGADO direto no disco (sem passar por
# state-rw.sh, que canonicalizaria para EN). Prova que os readers do
# spawn-tracker leem schema pt-BR via fallback (.en // .pt) — regressao
# de back-compat (schema-en-migration, idiom §6).
_write_legacy_pt_state() {
  mkdir -p "$1"
  cat > "$1/state.json" <<'JSON'
{
  "schema_version": 1,
  "ondas": [{ "id": "onda-001" }],
  "orcamentos": { "profundidade_corrente_subagentes": 1 },
  "metricas_acumuladas": { "profundidade_max_atingida": 1, "subagentes_spawned": 0 }
}
JSON
}

scenario_reader_fallback_le_state_pt_legado() {
  _sd="$TMPDIR_TEST/state-pt"
  _write_legacy_pt_state "$_sd"

  # current LE .orcamentos.profundidade_corrente_subagentes via fallback
  capture "$SCRIPT" current --state-dir "$_sd"
  assert_stdout_contains "1" || return 1

  # check usa o mesmo reader (profundidade 1 -> pode spawnar)
  capture "$SCRIPT" check --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "check pt-legado" "$_CAPTURED_EXIT"; return 1; }

  # enter: reader (fallback) + backup (_st_backup_current le .ondas[-1].id
  # via fallback) + writer (converge para EN no disco).
  capture "$SCRIPT" enter --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "enter pt-legado" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "2" || return 1

  # Pos-write o estado converge para chaves EN (writer sem fallback).
  _depth=$(jq -r '.budgets.current_subagent_depth' "$_sd/state.json")
  [ "$_depth" = 2 ] || { _fail "converge EN depth" "esperado 2, obtido $_depth"; return 1; }
  _spawned=$(jq -r '.accumulated_metrics.subagents_spawned' "$_sd/state.json")
  [ "$_spawned" = 1 ] || { _fail "converge EN spawned" "esperado 1, obtido $_spawned"; return 1; }
}

run_all_scenarios
