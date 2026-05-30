#!/bin/sh
# test_retro.sh — cobre global/skills/agente-00c-runtime/scripts/retro.sh.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"
. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/retro.sh"
RW="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/state-rw.sh"

if ! command -v jq >/dev/null 2>&1; then
  printf '# test_retro.sh: jq ausente — pulando\n'
  exit 0
fi

_init() {
  capture "$RW" init --state-dir "$1" --execucao-id "x" \
    --projeto-alvo-path "/tmp/p" --descricao "POC retro tests"
}

# _read_consumed STATE_DIR — le o contador via path EN + fallback pt-BR.
# (state-rw.sh init ja emite EN; o fallback cobre states legados pt-BR.)
_read_consumed() {
  jq -r '
    ((.budgets // .orcamentos) // {})
    | .retro_executions_consumed // .retro_execucoes_consumidas // 0
  ' "$1/state.json"
}

# _seed_pt_state STATE_DIR — cria um state.json legado em chaves pt-BR
# (.orcamentos.retro_execucoes_*) sem passar pelo state-rw.sh init (que ja
# converge para EN). Prova o reader-fallback (.en // .pt) de back-compat.
_seed_pt_state() {
  mkdir -p "$1"
  cat > "$1/state.json" <<'PTSTATE'
{
  "schema_version": 1,
  "orcamentos": {
    "retro_execucoes_max_por_feature": 2,
    "retro_execucoes_consumidas": 0
  }
}
PTSTATE
}

scenario_count_inicial_0_2() {
  _sd="$TMPDIR_TEST/state"
  _init "$_sd"
  capture "$SCRIPT" count --state-dir "$_sd"
  assert_stdout_contains "0/2" || return 1
}

scenario_check_inicial_passa() {
  _sd="$TMPDIR_TEST/state"
  _init "$_sd"
  capture "$SCRIPT" check --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "check 0/2" "$_CAPTURED_EXIT"; return 1; }
}

scenario_consume_incrementa() {
  _sd="$TMPDIR_TEST/state"
  _init "$_sd"
  capture "$SCRIPT" consume --state-dir "$_sd"
  assert_stdout_contains "1" || return 1
  capture "$SCRIPT" consume --state-dir "$_sd"
  assert_stdout_contains "2" || return 1
  capture "$SCRIPT" count --state-dir "$_sd"
  assert_stdout_contains "2/2" || return 1
}

scenario_check_no_limite_exit_3() {
  _sd="$TMPDIR_TEST/state"
  _init "$_sd"
  capture "$SCRIPT" consume --state-dir "$_sd"
  capture "$SCRIPT" consume --state-dir "$_sd"
  capture "$SCRIPT" check --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 3 ]; then
    _fail "check 2/2" "esperado 3, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_consume_terceira_vez_exit_3_sem_modificar() {
  _sd="$TMPDIR_TEST/state"
  _init "$_sd"
  capture "$SCRIPT" consume --state-dir "$_sd"
  capture "$SCRIPT" consume --state-dir "$_sd"
  _before=$(_read_consumed "$_sd")
  capture "$SCRIPT" consume --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 3 ]; then
    _fail "consume 3rd" "esperado 3, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "consume negado" || return 1
  _after=$(_read_consumed "$_sd")
  if [ "$_before" != "$_after" ]; then
    _fail "consume negado MUTOU estado" "before=$_before after=$_after"
    return 1
  fi
}

scenario_reset_zera() {
  _sd="$TMPDIR_TEST/state"
  _init "$_sd"
  capture "$SCRIPT" consume --state-dir "$_sd"
  capture "$SCRIPT" consume --state-dir "$_sd"
  capture "$SCRIPT" reset --state-dir "$_sd"
  capture "$SCRIPT" count --state-dir "$_sd"
  assert_stdout_contains "0/2" || return 1
}

scenario_state_ausente_falha() {
  _sd="$TMPDIR_TEST/empty"
  mkdir -p "$_sd"
  capture "$SCRIPT" check --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "state ausente" "esperado 1"
    return 1
  fi
}

# ---- back-compat: reader-fallback sobre state legado pt-BR (.orcamentos) ----
# (schema-en-migration §6: >=1 fixture pt-BR provando que o reader EN+fallback
#  ainda le states gravados com chaves pt-BR antigas.)

scenario_pt_state_count_le_via_fallback() {
  _sd="$TMPDIR_TEST/pt"
  _seed_pt_state "$_sd"
  capture "$SCRIPT" count --state-dir "$_sd"
  assert_stdout_contains "0/2" || return 1
}

scenario_pt_state_check_le_via_fallback() {
  _sd="$TMPDIR_TEST/pt"
  _seed_pt_state "$_sd"
  capture "$SCRIPT" check --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "check pt 0/2" "$_CAPTURED_EXIT"; return 1; }
}

scenario_pt_state_consume_converge_para_en() {
  # 1o consume sobre state pt-BR legado: reader le consumed=0 via fallback
  # (.orcamentos); writer grava na chave EN (.budgets.retro_executions_consumed).
  # Prova convergencia EN-on-disk + que o reader EN ja enxerga o novo valor.
  _sd="$TMPDIR_TEST/pt"
  _seed_pt_state "$_sd"
  capture "$SCRIPT" consume --state-dir "$_sd"
  assert_stdout_contains "1" || return 1
  _v=$(jq -r '.budgets.retro_executions_consumed' "$_sd/state.json")
  [ "$_v" = 1 ] || { _fail "writer EN" "esperado .budgets.retro_executions_consumed=1, obtido $_v"; return 1; }
  capture "$SCRIPT" count --state-dir "$_sd"
  assert_stdout_contains "1/2" || return 1
}

run_all_scenarios
