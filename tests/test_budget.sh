#!/bin/sh
# test_budget.sh — cobre global/skills/agente-00c-runtime/scripts/budget.sh.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"
. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/budget.sh"
RW="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/state-rw.sh"
ON="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/state-ondas.sh"

if ! command -v jq >/dev/null 2>&1; then
  printf '# test_budget.sh: jq ausente — pulando\n'
  exit 0
fi

_init_with_onda() {
  capture "$RW" init --state-dir "$1" --execucao-id "x" \
    --projeto-alvo-path "/tmp/p" --descricao "POC budget tests"
  capture "$ON" start --state-dir "$1"
}

scenario_status_imprime_3_linhas_tsv() {
  _sd="$TMPDIR_TEST/state"
  _init_with_onda "$_sd"
  capture "$SCRIPT" status --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "status" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "tool_calls	0	80" || return 1
  assert_stdout_contains "wallclock	" || return 1
  assert_stdout_contains "state_size	" || return 1
}

scenario_check_inicial_passa() {
  _sd="$TMPDIR_TEST/state"
  _init_with_onda "$_sd"
  capture "$SCRIPT" check --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "check inicial" "$_CAPTURED_STDERR"; return 1; }
}

scenario_tool_calls_threshold_dispara_exit_1() {
  _sd="$TMPDIR_TEST/state"
  _init_with_onda "$_sd"
  # Writer via state-rw set: campo EN (schema-en-migration). O set canonicaliza
  # o doc p/ EN antes de aplicar, entao o reader le pelo path EN primario.
  capture "$RW" set --state-dir "$_sd" \
    --field '.budgets.tool_calls_current_wave' --value '85'
  capture "$SCRIPT" check --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "tool_calls trigger" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stdout_contains "tool_calls	85	80" || return 1
}

scenario_state_size_threshold_dispara_exit_1() {
  _sd="$TMPDIR_TEST/state"
  _init_with_onda "$_sd"
  # Reduz threshold p/ valor menor que estado atual (campo EN — schema-en-migration)
  capture "$RW" set --state-dir "$_sd" \
    --field '.budgets.state_size_threshold_bytes' --value '100'
  capture "$SCRIPT" check --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "state_size trigger" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stdout_contains "state_size	" || return 1
}

scenario_wallclock_threshold_dispara_exit_1() {
  _sd="$TMPDIR_TEST/state"
  _init_with_onda "$_sd"
  # Reduz threshold p/ 0 -> qualquer wallclock dispara (campo EN — schema-en-migration)
  capture "$RW" set --state-dir "$_sd" \
    --field '.budgets.wallclock_threshold_seconds' --value '0'
  capture "$SCRIPT" check --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "wallclock trigger" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stdout_contains "wallclock	" || return 1
}

scenario_check_state_ausente_falha() {
  _sd="$TMPDIR_TEST/empty"
  mkdir -p "$_sd"
  capture "$SCRIPT" check --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "state ausente" "esperado 1"
    return 1
  fi
}

# Back-compat (schema-en-migration idiom §6): state pt-BR puro (chaves legadas
# .orcamentos.*) DEVE continuar sendo lido via fallback (.en // .pt). Fixture
# montada na mao para nao depender da migracao de state-rw/state-ondas; prova
# que o reader EN-com-fallback do budget.sh ainda dispara sobre dados pt-BR.
scenario_check_fallback_state_pt_br_legado() {
  _sd="$TMPDIR_TEST/legacy"
  mkdir -p "$_sd"
  cat > "$_sd/state.json" <<'JSON'
{
  "schema_version": 6,
  "orcamentos": {
    "tool_calls_onda_corrente": 90,
    "tool_calls_threshold_onda": 80,
    "wallclock_threshold_segundos": 5400,
    "estado_size_threshold_bytes": 1048576,
    "inicio_onda_corrente": null
  }
}
JSON
  capture "$SCRIPT" check --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "fallback pt-BR check" "esperado 1 (90>=80 via .orcamentos), obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stdout_contains "tool_calls	90	80" || return 1
}

# Companheiro do anterior: status sobre o MESMO state pt-BR puro deve imprimir
# os valores lidos via fallback (tool_calls=90, threshold=80) sem veredito.
scenario_status_fallback_state_pt_br_legado() {
  _sd="$TMPDIR_TEST/legacy"
  mkdir -p "$_sd"
  cat > "$_sd/state.json" <<'JSON'
{
  "schema_version": 6,
  "orcamentos": {
    "tool_calls_onda_corrente": 90,
    "tool_calls_threshold_onda": 80,
    "wallclock_threshold_segundos": 5400,
    "estado_size_threshold_bytes": 1048576,
    "inicio_onda_corrente": null
  }
}
JSON
  capture "$SCRIPT" status --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "status fallback pt-BR" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "tool_calls	90	80" || return 1
  assert_stdout_contains "wallclock	0	5400" || return 1
}

run_all_scenarios
