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

# ==== Backend SQLite (feature state-db-foundation, FASE 3 task 3.6) ====
#
# Ref: docs/specs/state-db-foundation/contracts/primitives.md
#      §C1 (paridade) §C2 (selecao de backend) §C3 (exit 3 no teto) §C6
#
# Mesmo padrao de tests/test_bloqueios.sh (task 3.5): aplica o DDL via
# state-db-schema.sh e semeia uma execution minima via sqlite3 diretamente
# (init nunca cria state.db — isso e a migracao, FASE 6, ainda nao
# implementada).

if ! command -v sqlite3 >/dev/null 2>&1; then
  printf '# test_spawn-tracker.sh: sqlite3 ausente — pulando cenarios de backend SQLite\n'
else

SCHEMA_SCRIPT="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/state-db-schema.sh"

# _seed_sqlite_backend DIR [MAX_RECURSION] -> cria state.db com execution
# minima (id=exec-1, subagent_depth=1 default do schema).
_seed_sqlite_backend() {
  _ssb_dir=$1
  _ssb_max="${2:-}"
  mkdir -p "$_ssb_dir"
  "$SCHEMA_SCRIPT" create --db "$_ssb_dir/state.db" >/dev/null 2>&1 \
    || { _fail "seed: schema create falhou" ""; return 1; }
  if [ -n "$_ssb_max" ]; then
    sqlite3 "$_ssb_dir/state.db" "
      INSERT INTO execution (id,schema_version,target_project_path,target_project_description,status,started_at,current_stage,next_instruction,external_urls_whitelist,circular_movement_history,initial_key_aspects,atomic_commit_enabled,max_recursion)
      VALUES ('exec-1','1.0.0','/tmp/p','desc de teste com detalhe','em_andamento','2026-07-30T00:00:00Z','execute-task','faca algo','[]','[]','[]',0,$_ssb_max);
    " || { _fail "seed: insert execution falhou" ""; return 1; }
  else
    sqlite3 "$_ssb_dir/state.db" "
      INSERT INTO execution (id,schema_version,target_project_path,target_project_description,status,started_at,current_stage,next_instruction,external_urls_whitelist,circular_movement_history,initial_key_aspects,atomic_commit_enabled)
      VALUES ('exec-1','1.0.0','/tmp/p','desc de teste com detalhe','em_andamento','2026-07-30T00:00:00Z','execute-task','faca algo','[]','[]','[]',0);
    " || { _fail "seed: insert execution falhou" ""; return 1; }
  fi
}

scenario_sqlite_inicial_profundidade_1() {
  _sd="$TMPDIR_TEST/sqlite-inicial"
  _seed_sqlite_backend "$_sd" || return 1
  capture "$SCRIPT" current --state-dir "$_sd"
  assert_stdout_contains "1" || return 1
}

scenario_sqlite_check_inicial_passa() {
  _sd="$TMPDIR_TEST/sqlite-check-ok"
  _seed_sqlite_backend "$_sd" || return 1
  capture "$SCRIPT" check --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "sqlite check inicial" "$_CAPTURED_EXIT"; return 1; }
}

scenario_sqlite_enter_incrementa_e_persiste() {
  _sd="$TMPDIR_TEST/sqlite-enter"
  _seed_sqlite_backend "$_sd" || return 1
  capture "$SCRIPT" enter --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "sqlite enter" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "2" || return 1
  capture "$SCRIPT" current --state-dir "$_sd"
  assert_stdout_contains "2" || return 1
}

# enter/check sobre o teto: paridade C1/C3 — mesma mensagem/exit 3 do path
# JSON (contracts/primitives.md linha "enter acima do teto | CHECK
# subagent_depth | 3 (paridade com hoje)").
scenario_sqlite_enter_excedendo_max_exit_3_sem_modificar_estado() {
  _sd="$TMPDIR_TEST/sqlite-enter-teto"
  _seed_sqlite_backend "$_sd" || return 1
  capture "$SCRIPT" enter --state-dir "$_sd"  # 1->2
  capture "$SCRIPT" enter --state-dir "$_sd"  # 2->3
  _before=$(sqlite3 "$_sd/state.db" "SELECT subagent_depth FROM execution;")
  capture "$SCRIPT" enter --state-dir "$_sd"  # 3->4 negado
  if [ "$_CAPTURED_EXIT" != 3 ]; then
    _fail "sqlite enter ilegal exit" "esperado 3, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "MAX 3" || return 1
  _after=$(sqlite3 "$_sd/state.db" "SELECT subagent_depth FROM execution;")
  if [ "$_before" != "$_after" ]; then
    _fail "sqlite enter negado MUTOU estado" "before=$_before after=$_after"
    return 1
  fi
}

scenario_sqlite_check_no_limite_exit_3() {
  _sd="$TMPDIR_TEST/sqlite-check-limite"
  _seed_sqlite_backend "$_sd" || return 1
  capture "$SCRIPT" enter --state-dir "$_sd"
  capture "$SCRIPT" enter --state-dir "$_sd"
  capture "$SCRIPT" check --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 3 ]; then
    _fail "sqlite check no limite" "esperado 3, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_sqlite_leave_decrementa() {
  _sd="$TMPDIR_TEST/sqlite-leave"
  _seed_sqlite_backend "$_sd" || return 1
  capture "$SCRIPT" enter --state-dir "$_sd"
  capture "$SCRIPT" leave --state-dir "$_sd"
  assert_stdout_contains "1" || return 1
}

scenario_sqlite_leave_idempotente_no_minimo() {
  _sd="$TMPDIR_TEST/sqlite-leave-idempotente"
  _seed_sqlite_backend "$_sd" || return 1
  capture "$SCRIPT" leave --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "sqlite leave inicial" "$_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "1" || return 1
  capture "$SCRIPT" current --state-dir "$_sd"
  assert_stdout_contains "1" || return 1
}

# Teto customizado (max_recursion != 3) — prova que o teto e lido da coluna
# execution.max_recursion, nao de uma constante hardcoded no path sqlite.
scenario_sqlite_teto_customizado_respeitado() {
  _sd="$TMPDIR_TEST/sqlite-teto-custom"
  _seed_sqlite_backend "$_sd" 1 || return 1  # max_recursion=1
  capture "$SCRIPT" check --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 3 ]; then
    _fail "sqlite teto customizado" "esperado 3 (max=1, current=1), obtido $_CAPTURED_EXIT"
    return 1
  fi
}

# Paridade cross-backend (C1): mesmos inputs, mesmo stdout/exit code para
# check/enter/leave/current nos dois backends.
scenario_sqlite_paridade_enter_leave_json() {
  _sd_json="$TMPDIR_TEST/paridade-spawn-json"
  _init_state "$_sd_json"
  capture "$SCRIPT" enter --state-dir "$_sd_json"
  _json_enter_out="$_CAPTURED_STDOUT"
  _json_enter_exit="$_CAPTURED_EXIT"
  capture "$SCRIPT" leave --state-dir "$_sd_json"
  _json_leave_out="$_CAPTURED_STDOUT"

  _sd_sqlite="$TMPDIR_TEST/paridade-spawn-sqlite"
  _seed_sqlite_backend "$_sd_sqlite" || return 1
  capture "$SCRIPT" enter --state-dir "$_sd_sqlite"
  _sqlite_enter_out="$_CAPTURED_STDOUT"
  _sqlite_enter_exit="$_CAPTURED_EXIT"
  capture "$SCRIPT" leave --state-dir "$_sd_sqlite"
  _sqlite_leave_out="$_CAPTURED_STDOUT"

  [ "$_json_enter_out" = "$_sqlite_enter_out" ] \
    || { _fail "paridade enter stdout" "json='$_json_enter_out' sqlite='$_sqlite_enter_out'"; return 1; }
  [ "$_json_enter_exit" = "$_sqlite_enter_exit" ] \
    || { _fail "paridade enter exit" "json=$_json_enter_exit sqlite=$_sqlite_enter_exit"; return 1; }
  [ "$_json_leave_out" = "$_sqlite_leave_out" ] \
    || { _fail "paridade leave stdout" "json='$_json_leave_out' sqlite='$_sqlite_leave_out'"; return 1; }
}

# Task 4.1.1/4.2.2 (FASE 4): branch de selecao de backend explicito por C2 —
# um state.json coexistente e export/legado, NUNCA consultado como fonte.
# Prova positiva: subagent_depth=2 no state.db (1 enter), state.json
# divergente com depth=99 — current deve refletir sempre o state.db (2).
scenario_c2_state_json_coexistente_ignorado_quando_state_db_presente() {
  _sd="$TMPDIR_TEST/c2-coexist-spawn"
  _seed_sqlite_backend "$_sd" || return 1
  capture "$SCRIPT" enter --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "c2: enter sqlite" "$_CAPTURED_STDERR"; return 1; }

  # state.json divergente no MESMO diretorio.
  printf '{"execution":{"subagent_depth":99}}\n' > "$_sd/state.json"

  capture "$SCRIPT" current --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "c2 current exit" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "2" \
    || { _fail "c2: current deveria refletir state.db (2), nao o state.json coexistente (99)" "obtido $_CAPTURED_STDOUT"; return 1; }
  case "$_CAPTURED_STDOUT" in
    99*) _fail "c2: current leu o state.json coexistente" "obtido $_CAPTURED_STDOUT"; return 1 ;;
  esac

  # state.json coexistente permanece intocado.
  _stale_now=$(cat "$_sd/state.json")
  [ "$_stale_now" = '{"execution":{"subagent_depth":99}}' ] \
    || { _fail "c2: state.json coexistente foi modificado" "obtido: $_stale_now"; return 1; }
}

fi  # command -v sqlite3

run_all_scenarios
