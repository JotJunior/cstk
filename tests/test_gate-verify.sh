#!/bin/sh
# test_gate-verify.sh — cobre
# plugins/cstk/skills/agente-00c-runtime/scripts/gate-verify.sh (issue #242).
#
# Cobertura:
#   set-command: grava .gate_command; recusa vazio, multi-linha, >1000 bytes
#                e comando barrado pelo bash-guard (exit 2, state intacto)
#   get-command: vazio quando nao declarado
#   run: nao-declarado (degrada, exit 0, registra), pass (exit 0), fail
#        (exit 3, exit code + linha de sumario REAIS), roda na raiz do
#        projeto-alvo, sem onda aberta (exit 1), sumario passa pelo scrub
#   check: not-declared (exit 0 + aviso), missing (exit 3), fail (exit 3),
#          pass (exit 0), escopo por onda (run de onda anterior nao vale)
#   backend SQLite: set/run/check com paridade

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

_SCRIPTS="$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts"
SCRIPT="$_SCRIPTS/gate-verify.sh"
RW="$_SCRIPTS/state-rw.sh"
SO="$_SCRIPTS/state-ondas.sh"
SCHEMA_SCRIPT="$_SCRIPTS/state-db-schema.sh"

if ! command -v jq >/dev/null 2>&1; then
  printf '# test_gate-verify.sh: jq ausente — pulando suite\n'
  exit 0
fi

# _gv_fixture NAME -> state JSON com projeto-alvo real + onda aberta.
# Define _sd e _proj.
_gv_fixture() {
  _proj="$TMPDIR_TEST/$1-proj"
  _sd="$TMPDIR_TEST/$1-state"
  mkdir -p "$_proj"
  capture "$RW" init --state-dir "$_sd" \
    --execucao-id "exec-gate-test" --projeto-alvo-path "$_proj" --descricao "POC gate verify"
  [ "$_CAPTURED_EXIT" = 0 ] || { _error "fixture init" "$_CAPTURED_STDERR"; return 2; }
  capture "$SO" start --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _error "fixture start" "$_CAPTURED_STDERR"; return 2; }
}

# ==== set-command / get-command ====

scenario_set_command_grava_e_get_le() {
  _gv_fixture setget || return 2
  capture "$SCRIPT" get-command --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] && [ -z "$_CAPTURED_STDOUT" ] || { _fail "get sem comando" "exit=$_CAPTURED_EXIT out='$_CAPTURED_STDOUT'"; return 1; }
  capture "$SCRIPT" set-command --state-dir "$_sd" --command 'make check && echo "ok"'
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "set-command" "$_CAPTURED_STDERR"; return 1; }
  capture "$SCRIPT" get-command --state-dir "$_sd"
  [ "$_CAPTURED_STDOUT" = 'make check && echo "ok"' ] || { _fail "roundtrip" "'$_CAPTURED_STDOUT'"; return 1; }
}

scenario_set_command_recusa_invalidos_sem_write() {
  _gv_fixture setbad || return 2
  _long=$(awk 'BEGIN { for (i = 0; i < 1001; i++) printf "x" }')
  for _c in "" "   " "$(printf 'make test\nrm -rf /tmp/x')" "$_long" "git push origin main" "sudo make test"; do
    capture "$SCRIPT" set-command --state-dir "$_sd" --command "$_c"
    [ "$_CAPTURED_EXIT" = 2 ] || { _fail "comando invalido aceito" "exit=$_CAPTURED_EXIT cmd='$_c'"; return 1; }
  done
  capture "$SCRIPT" get-command --state-dir "$_sd"
  [ -z "$_CAPTURED_STDOUT" ] || { _fail "state alterado por set invalido" "'$_CAPTURED_STDOUT'"; return 1; }
}

scenario_state_ausente_exit1() {
  mkdir -p "$TMPDIR_TEST/vazio"
  capture "$SCRIPT" check --state-dir "$TMPDIR_TEST/vazio"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "state ausente" "exit=$_CAPTURED_EXIT"; return 1; }
}

scenario_uso_incorreto_exit2() {
  capture "$SCRIPT"
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "sem subcomando" "exit=$_CAPTURED_EXIT"; return 1; }
  capture "$SCRIPT" foo
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "subcomando desconhecido" "exit=$_CAPTURED_EXIT"; return 1; }
  capture "$SCRIPT" run --bogus x
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "flag desconhecida" "exit=$_CAPTURED_EXIT"; return 1; }
}

# ==== run ====

scenario_run_sem_comando_degrada_e_registra() {
  _gv_fixture nocmd || return 2
  capture "$SCRIPT" run --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "run nao-declarado deveria ser exit 0" "exit=$_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "gate=not-declared" || return 1
  assert_stderr_contains "gate=nao-declarado" || return 1
  grep -q "^onda-001	.*	not-declared	" "$_sd/gate-verify.tsv" \
    || { _fail "sidecar sem registro not-declared" "$(cat "$_sd/gate-verify.tsv" 2>/dev/null)"; return 1; }
}

scenario_run_pass_registra_exit_e_sumario() {
  _gv_fixture pass || return 2
  capture "$SCRIPT" set-command --state-dir "$_sd" --command 'echo "ok pkg 0.1s"; echo; echo "PASS 12 tests"'
  capture "$SCRIPT" run --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "run pass" "exit=$_CAPTURED_EXIT $_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "gate=pass exit=0 wave=onda-001" || return 1
  assert_stdout_contains "summary=PASS 12 tests" || return 1
  [ -f "$_sd/gate-verify/onda-001.log" ] || { _fail "log da onda ausente" ""; return 1; }
}

scenario_run_fail_exit3_com_exit_code_real() {
  _gv_fixture fail || return 2
  capture "$SCRIPT" set-command --state-dir "$_sd" --command 'echo "17 failed, 40 passed"; exit 7'
  capture "$SCRIPT" run --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 3 ] || { _fail "run fail deveria ser exit 3" "exit=$_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "gate=fail exit=7 wave=onda-001" || return 1
  assert_stdout_contains "summary=17 failed, 40 passed" || return 1
}

scenario_run_executa_na_raiz_do_projeto_alvo() {
  _gv_fixture cwd || return 2
  : > "$_proj/marker-gate"
  capture "$SCRIPT" set-command --state-dir "$_sd" --command 'test -f marker-gate'
  capture "$SCRIPT" run --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "deveria rodar na raiz do projeto-alvo" "exit=$_CAPTURED_EXIT $_CAPTURED_STDOUT"; return 1; }
}

scenario_run_sem_onda_aberta_exit1() {
  _gv_fixture closed || return 2
  capture "$SO" end --state-dir "$_sd" --motivo-termino bloqueio_humano
  capture "$SCRIPT" run --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "sem onda aberta" "exit=$_CAPTURED_EXIT"; return 1; }
}

scenario_run_sumario_passa_pelo_scrub() {
  _gv_fixture scrub || return 2
  capture "$SCRIPT" set-command --state-dir "$_sd" --command 'echo "token=ghp_abcdefghijklmnopqrstuvwxyz0123456789"; exit 1'
  capture "$SCRIPT" run --state-dir "$_sd"
  assert_stdout_not_contains "ghp_abcdefghijklmnopqrstuvwxyz0123456789" || return 1
  if grep -q "ghp_abcdefghijklmnopqrstuvwxyz0123456789" "$_sd/gate-verify.tsv"; then
    _fail "segredo vazou no sidecar" ""; return 1
  fi
}

scenario_run_rechecha_guard_mesmo_com_state_editado() {
  # O comando pode ter sido editado no state depois do set-command: `run`
  # re-checa o bash-guard antes de executar (roda fora do hook PreToolUse).
  _gv_fixture tamper || return 2
  capture "$RW" set --state-dir "$_sd" --field '.gate_command' --value '"git push origin main"'
  capture "$SCRIPT" run --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 3 ] || { _fail "comando barrado deveria ser exit 3" "exit=$_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "gate=blocked" || return 1
}

# ==== check ====

scenario_check_nao_declarado_exit0_com_aviso() {
  _gv_fixture chknd || return 2
  capture "$SCRIPT" check --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "check nao-declarado" "exit=$_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "gate=not-declared" || return 1
  assert_stderr_contains "gate=nao-declarado" || return 1
}

scenario_check_declarado_sem_run_missing_exit3() {
  _gv_fixture chkmiss || return 2
  capture "$SCRIPT" set-command --state-dir "$_sd" --command 'true'
  capture "$SCRIPT" check --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 3 ] || { _fail "check missing" "exit=$_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "gate=missing wave=onda-001" || return 1
}

scenario_check_reflete_ultimo_run_da_onda() {
  _gv_fixture chklast || return 2
  capture "$SCRIPT" set-command --state-dir "$_sd" --command 'exit 1'
  capture "$SCRIPT" run --state-dir "$_sd"
  capture "$SCRIPT" check --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 3 ] || { _fail "check apos fail" "exit=$_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "gate=fail exit=1" || return 1
  capture "$SCRIPT" set-command --state-dir "$_sd" --command 'true'
  capture "$SCRIPT" run --state-dir "$_sd"
  capture "$SCRIPT" check --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "check apos pass" "exit=$_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "gate=pass" || return 1
}

scenario_check_run_de_onda_anterior_nao_vale() {
  _gv_fixture chkwave || return 2
  capture "$SCRIPT" set-command --state-dir "$_sd" --command 'true'
  capture "$SCRIPT" run --state-dir "$_sd"
  capture "$SO" end --state-dir "$_sd" --motivo-termino threshold_proxy_atingido
  capture "$SO" start --state-dir "$_sd"
  capture "$SCRIPT" check --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 3 ] || { _fail "run da onda-001 nao deveria valer na onda-002" "exit=$_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "gate=missing wave=onda-002" || return 1
}

scenario_check_run_antes_de_declarar_nao_vale() {
  _gv_fixture chkorder || return 2
  capture "$SCRIPT" run --state-dir "$_sd"   # not-declared
  capture "$SCRIPT" set-command --state-dir "$_sd" --command 'true'
  capture "$SCRIPT" check --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 3 ] || { _fail "run sem comando nao prova o comando novo" "exit=$_CAPTURED_EXIT"; return 1; }
}

# ==== backend SQLite ====

if ! command -v sqlite3 >/dev/null 2>&1; then
  printf '# test_gate-verify.sh: sqlite3 ausente — pulando cenarios SQLite\n'
else

_gv_seed_sqlite() {
  _proj="$TMPDIR_TEST/$1-proj"
  _sd="$TMPDIR_TEST/$1-state"
  mkdir -p "$_proj" "$_sd"
  "$SCHEMA_SCRIPT" create --db "$_sd/state.db" >/dev/null 2>&1 \
    || { _error "seed: schema create falhou" ""; return 2; }
  sqlite3 "$_sd/state.db" "
    PRAGMA foreign_keys=ON;
    INSERT INTO execution (id,schema_version,target_project_path,target_project_description,status,started_at,current_stage,next_instruction,external_urls_whitelist,circular_movement_history,initial_key_aspects,atomic_commit_enabled)
    VALUES ('exec-1','1.0.0','$_proj','desc de teste com detalhe','em_andamento','2026-07-30T00:00:00Z','execute-task','faca algo','[]','[]','[]',0);
  " || { _error "seed: insert falhou" ""; return 2; }
  capture "$SO" start --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _error "seed: start" "$_CAPTURED_STDERR"; return 2; }
}

scenario_sqlite_set_run_check_paridade() {
  _gv_seed_sqlite sq || return 2
  capture "$SCRIPT" check --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "sqlite check nao-declarado" "exit=$_CAPTURED_EXIT"; return 1; }
  capture "$SCRIPT" set-command --state-dir "$_sd" --command 'echo "3 failed"; exit 1'
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "sqlite set-command" "$_CAPTURED_STDERR"; return 1; }
  capture "$SCRIPT" check --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 3 ] || { _fail "sqlite missing" "exit=$_CAPTURED_EXIT"; return 1; }
  capture "$SCRIPT" run --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 3 ] || { _fail "sqlite run fail" "exit=$_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "summary=3 failed" || return 1
  capture "$SCRIPT" set-command --state-dir "$_sd" --command 'true'
  capture "$SCRIPT" run --state-dir "$_sd"
  capture "$SCRIPT" check --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "sqlite pass" "exit=$_CAPTURED_EXIT"; return 1; }
}

fi # sqlite3 disponivel

run_all_scenarios
