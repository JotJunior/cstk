#!/bin/sh
# test_otel-usage.sh — cobre
# global/skills/agente-00c-runtime/scripts/otel-usage.sh
#
# Invariantes sob teste:
#   INV-1: PRIVACIDADE — nenhum label de PII (user_email, user_id,
#          user_account_*, organization_id) alcanca o snapshot em disco.
#   INV-2: o label `type` e extraido ANCORADO. Sem ancoragem, `type="`
#          casa antes com `terminal_type="ghostty"` (substring) e o
#          breakdown por tipo vira o nome do terminal — bug observado em
#          dados reais antes do fix.
#   INV-3: metrica AUSENTE e `null`, nunca zero fabricado (Principio VI).
#          Vale para snapshot faltando, endpoint fora do ar e session_id
#          divergente entre os dois snapshots.
#   INV-4: degradacao best-effort — endpoint indisponivel sai 0 e nao
#          derruba a onda.
#   INV-5: `available` exige as metricas que o script consome
#          (cost/token), nao um `claude_code_` qualquer — no cold start o
#          exporter ja responde com session_count e o snapshot sairia sem
#          session_id, descartando a onda inteira.
#
# As fixtures reproduzem o formato REAL do exporter Prometheus do Claude
# Code 2.1.220 (ordem dos labels inclusive — `terminal_type` antes de
# `type` e o que dispara INV-2). Os valores de identidade sao anonimizados
# de proposito: fixture de teste nao carrega PII de ninguem.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"
. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/otel-usage.sh"

if ! command -v jq >/dev/null 2>&1; then
  printf '# test_otel-usage.sh: jq ausente — pulando suite\n'
  exit 0
fi
if ! command -v curl >/dev/null 2>&1; then
  printf '# test_otel-usage.sh: curl ausente — pulando suite\n'
  exit 0
fi

# _labels SESSION QSOURCE MODEL [EXTRA] -> bloco de labels na ORDEM REAL do
# exporter. `terminal_type` vem antes de `type` de proposito (INV-2).
_labels() {
  printf 'user_id="anon-hash",session_id="%s",organization_id="anon-org",' "$1"
  printf 'user_email="anon@example.invalid",user_account_uuid="anon-uuid",'
  printf 'user_account_id="anon-acct",terminal_type="ghostty",'
  printf 'model="%s",query_source="%s"%s' "$3" "$2" "${4:-}"
  printf ',otel_scope_name="com.anthropic.claude_code",otel_scope_version="2.1.220"'
}

# _fixture FILE SESSION COST_MAIN COST_SUB IN_MAIN OUT_MAIN
_fixture() {
  _fx=$1; _sid=$2; _cm=$3; _cs=$4; _im=$5; _om=$6
  {
    printf 'claude_code_cost_usage_total{%s} %s\n'  "$(_labels "$_sid" main     "claude-opus-5[1m]")" "$_cm"
    printf 'claude_code_cost_usage_total{%s} %s\n'  "$(_labels "$_sid" subagent "claude-opus-5[1m]")" "$_cs"
    printf 'claude_code_token_usage_total{%s} %s\n' "$(_labels "$_sid" main "claude-opus-5[1m]" ',type="input"')"  "$_im"
    printf 'claude_code_token_usage_total{%s} %s\n' "$(_labels "$_sid" main "claude-opus-5[1m]" ',type="output"')" "$_om"
  } > "$_fx"
}

_snap() {
  # $1=state-dir $2=phase $3=fixture-file
  capture sh "$SCRIPT" snapshot --state-dir "$1" --phase "$2" --endpoint "file://$3"
}

# ==== INV-2: ancoragem do label `type` ====

scenario_type_nao_colide_com_terminal_type() {
  _sd="$TMPDIR_TEST/anchor"; mkdir -p "$_sd"
  _fx="$TMPDIR_TEST/anchor.txt"
  _fixture "$_fx" "sess-1" 1.0 0.5 100 20
  _snap "$_sd" end "$_fx"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "snapshot exit" "$_CAPTURED_EXIT / $_CAPTURED_STDERR"; return 1; }
  grep -q "	input	100$" "$_sd/otel-end.tsv" \
    || { _fail "type=input" "esperado linha com type input; obtido: $(cat "$_sd/otel-end.tsv")"; return 1; }
  grep -q "	output	20$" "$_sd/otel-end.tsv" \
    || { _fail "type=output" "esperado linha com type output"; return 1; }
  # O valor do terminal JAMAIS pode aparecer como tipo de token.
  grep -q "ghostty" "$_sd/otel-end.tsv" \
    && { _fail "colisao terminal_type" "'ghostty' vazou para o campo type"; return 1; }
  return 0
}

# ==== INV-1: privacidade ====

scenario_pii_nunca_alcanca_o_snapshot() {
  _sd="$TMPDIR_TEST/pii"; mkdir -p "$_sd"
  _fx="$TMPDIR_TEST/pii.txt"
  _fixture "$_fx" "sess-pii" 1.0 0.5 100 20
  _snap "$_sd" end "$_fx"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "snapshot exit" "$_CAPTURED_EXIT"; return 1; }
  for _lbl in user_id user_email user_account_uuid user_account_id organization_id anon@example.invalid anon-hash anon-org; do
    grep -q "$_lbl" "$_sd/otel-end.tsv" \
      && { _fail "PII" "'$_lbl' vazou para o snapshot"; return 1; }
  done
  return 0
}

# ==== delta: aritmetica ====

scenario_delta_subtrai_contadores_cumulativos() {
  _sd="$TMPDIR_TEST/delta"; mkdir -p "$_sd"
  _fs="$TMPDIR_TEST/d-start.txt"; _fe="$TMPDIR_TEST/d-end.txt"
  _fixture "$_fs" "sess-d" 1.0 0.5 100 20
  _fixture "$_fe" "sess-d" 3.0 2.0 400 60
  _snap "$_sd" start "$_fs"
  _snap "$_sd" end   "$_fe"
  capture sh "$SCRIPT" delta --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "delta exit" "$_CAPTURED_EXIT / $_CAPTURED_STDERR"; return 1; }
  _main=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.by_source.main.cost_usd')
  _sub=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.by_source.subagent.cost_usd')
  _in=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.by_source.main.input')
  [ "$_main" = "2" ] || { _fail "delta main cost" "esperado 2 (3.0-1.0), obtido $_main"; return 1; }
  [ "$_sub" = "1.5" ] || { _fail "delta subagent cost" "esperado 1.5 (2.0-0.5), obtido $_sub"; return 1; }
  [ "$_in" = "300" ] || { _fail "delta main input" "esperado 300 (400-100), obtido $_in"; return 1; }
  return 0
}

# Subagente e o recorte que motivou a feature — precisa vir separado.
scenario_delta_separa_subagente_de_main() {
  _sd="$TMPDIR_TEST/split"; mkdir -p "$_sd"
  _fs="$TMPDIR_TEST/s-start.txt"; _fe="$TMPDIR_TEST/s-end.txt"
  _fixture "$_fs" "sess-s" 0 0 0 0
  _fixture "$_fe" "sess-s" 1.0 9.0 10 5
  _snap "$_sd" start "$_fs"
  _snap "$_sd" end   "$_fe"
  capture sh "$SCRIPT" delta --state-dir "$_sd"
  _keys=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.by_source | keys | join(",")')
  case "$_keys" in
    *subagent*) : ;;
    *) _fail "by_source" "esperado recorte subagent; obtido '$_keys'"; return 1 ;;
  esac
  _sub=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.by_source.subagent.cost_usd')
  [ "$_sub" = "9" ] || { _fail "subagent cost" "esperado 9, obtido $_sub"; return 1; }
  return 0
}

# Contador reiniciado nao pode virar delta negativo.
scenario_delta_negativo_e_clampado() {
  _sd="$TMPDIR_TEST/neg"; mkdir -p "$_sd"
  _fs="$TMPDIR_TEST/n-start.txt"; _fe="$TMPDIR_TEST/n-end.txt"
  _fixture "$_fs" "sess-n" 5.0 5.0 500 50
  _fixture "$_fe" "sess-n" 1.0 1.0 100 10
  _snap "$_sd" start "$_fs"
  _snap "$_sd" end   "$_fe"
  capture sh "$SCRIPT" delta --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "delta exit" "$_CAPTURED_EXIT"; return 1; }
  # Todos os deltas <= 0 sao descartados => nada sobra => null.
  [ "$(printf '%s' "$_CAPTURED_STDOUT" | tr -d '[:space:]')" = "null" ] \
    || { _fail "clamp" "esperado null (nenhum delta positivo), obtido '$_CAPTURED_STDOUT'"; return 1; }
  return 0
}

# ==== INV-3: ausente e null, nunca zero ====

scenario_delta_sem_snapshot_start_e_null() {
  _sd="$TMPDIR_TEST/nostart"; mkdir -p "$_sd"
  _fe="$TMPDIR_TEST/ns-end.txt"
  _fixture "$_fe" "sess-x" 1.0 1.0 10 5
  _snap "$_sd" end "$_fe"
  capture sh "$SCRIPT" delta --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "$_CAPTURED_EXIT"; return 1; }
  [ "$(printf '%s' "$_CAPTURED_STDOUT" | tr -d '[:space:]')" = "null" ] \
    || { _fail "null" "sem start deve ser null, obtido '$_CAPTURED_STDOUT'"; return 1; }
  return 0
}

scenario_delta_session_divergente_e_null() {
  _sd="$TMPDIR_TEST/divsess"; mkdir -p "$_sd"
  _fs="$TMPDIR_TEST/v-start.txt"; _fe="$TMPDIR_TEST/v-end.txt"
  _fixture "$_fs" "sess-AAA" 1.0 1.0 10 5
  _fixture "$_fe" "sess-BBB" 9.0 9.0 90 50
  _snap "$_sd" start "$_fs"
  _snap "$_sd" end   "$_fe"
  capture sh "$SCRIPT" delta --state-dir "$_sd"
  [ "$(printf '%s' "$_CAPTURED_STDOUT" | tr -d '[:space:]')" = "null" ] \
    || { _fail "null" "session_id divergente deve dar null (processo trocou)"; return 1; }
  printf '%s' "$_CAPTURED_STDERR" | grep -q "session_id divergente" \
    || { _fail "stderr" "faltou aviso de session_id divergente"; return 1; }
  return 0
}

# ==== INV-4: degradacao best-effort ====

scenario_snapshot_endpoint_indisponivel_exit0() {
  _sd="$TMPDIR_TEST/down"; mkdir -p "$_sd"
  capture sh "$SCRIPT" snapshot --state-dir "$_sd" --phase start \
    --endpoint "file://$TMPDIR_TEST/nao-existe-mesmo.txt"
  [ "$_CAPTURED_EXIT" = 0 ] \
    || { _fail "exit" "endpoint fora do ar deve degradar com exit 0, obtido $_CAPTURED_EXIT"; return 1; }
  [ -f "$_sd/otel-start.tsv" ] \
    && { _fail "arquivo" "nao deve escrever snapshot sem dados"; return 1; }
  return 0
}

# ==== INV-5: available exige cost/token, nao qualquer claude_code_ ====

scenario_available_exige_metricas_consumidas() {
  # Cold start: o exporter ja responde com session_count mas ainda nao
  # emitiu cost/token. Aceitar isso produzia snapshot sem session_id.
  _fx="$TMPDIR_TEST/coldstart.txt"
  printf 'claude_code_session_count_total{session_id="s"} 1\n' > "$_fx"
  capture sh "$SCRIPT" available --endpoint "file://$_fx"
  [ "$_CAPTURED_EXIT" = 1 ] \
    || { _fail "cold start" "so session_count deve dar exit 1, obtido $_CAPTURED_EXIT"; return 1; }
  return 0
}

scenario_available_ok_com_metricas_reais() {
  _fx="$TMPDIR_TEST/warm.txt"
  _fixture "$_fx" "sess-w" 1.0 1.0 10 5
  capture sh "$SCRIPT" available --endpoint "file://$_fx"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  return 0
}

scenario_available_endpoint_morto_exit1() {
  capture sh "$SCRIPT" available --endpoint "file://$TMPDIR_TEST/vazio-inexistente.txt"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "exit" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
  return 0
}

# ==== uso incorreto ====

scenario_sem_subcomando_exit2() {
  assert_exit 2 sh "$SCRIPT" || return 1
  return 0
}

scenario_subcomando_desconhecido_exit2() {
  assert_exit 2 sh "$SCRIPT" nao-existe || return 1
  return 0
}

scenario_snapshot_phase_invalida_exit2() {
  _sd="$TMPDIR_TEST/badphase"; mkdir -p "$_sd"
  assert_exit 2 sh "$SCRIPT" snapshot --state-dir "$_sd" --phase meio || return 1
  return 0
}

scenario_snapshot_sem_state_dir_exit2() {
  assert_exit 2 sh "$SCRIPT" snapshot --phase start || return 1
  return 0
}

scenario_delta_sem_state_dir_exit2() {
  assert_exit 2 sh "$SCRIPT" delta || return 1
  return 0
}

scenario_flag_desconhecida_exit2() {
  _sd="$TMPDIR_TEST/badflag"; mkdir -p "$_sd"
  assert_exit 2 sh "$SCRIPT" snapshot --state-dir "$_sd" --phase start --nao-existe || return 1
  return 0
}

run_all_scenarios
exit $?
