#!/bin/sh
# test__spawn-tracker-db.sh — cobre
# plugins/cstk/skills/agente-00c-runtime/scripts/_spawn-tracker-db.sh
# (implementacao do backend SQLite de spawn-tracker.sh — feature
# state-db-foundation, FASE 3 task 3.6).
#
# Ref: docs/specs/state-db-foundation/tasks.md FASE 3, task 3.6
#      docs/specs/state-db-foundation/contracts/primitives.md §C1 C2 C3 C5 C6
#
# Cobertura desta unit suite: helpers de baixo nivel (_st_db_get_current,
# _st_db_get_max, _st_db_check, _st_db_enter, _st_db_leave, _st_db_current)
# isolados. O comportamento observavel via CLI (check/enter/leave/current,
# incluindo exit 3 no teto e paridade C1) e coberto em
# tests/test_spawn-tracker.sh, que e o oraculo de paridade para os dois
# backends.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

if ! command -v sqlite3 >/dev/null 2>&1; then
  printf '# test__spawn-tracker-db.sh: sqlite3 ausente — pulando suite\n'
  exit 0
fi
if ! command -v jq >/dev/null 2>&1; then
  printf '# test__spawn-tracker-db.sh: jq ausente — pulando suite\n'
  exit 0
fi

_R="$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts"
# shellcheck source=../plugins/cstk/skills/agente-00c-runtime/scripts/_state-db.sh
. "$_R/_state-db.sh"
# shellcheck source=../plugins/cstk/skills/agente-00c-runtime/scripts/_state-rw-db.sh
. "$_R/_state-rw-db.sh"
# shellcheck source=../plugins/cstk/skills/agente-00c-runtime/scripts/_spawn-tracker-db.sh
. "$_R/_spawn-tracker-db.sh"

SCHEMA_SCRIPT="$_R/state-db-schema.sh"

# _st_die/_sr_die: normalmente definidos por spawn-tracker.sh antes de
# sourcear estas libs. Fornecemos equivalentes minimos para exercitar as
# funcoes isoladas, sem depender do CLI completo.
_ST_NAME="spawn-tracker"
_st_die() { printf '%s: %s\n' "$_ST_NAME" "$1" >&2; exit "${2:-1}"; }
_sr_die() { _st_die "$1" "${2:-1}"; }

# _seed_db PATH [MAX_RECURSION] -> cria state.db minimo com execution
# id=exec-1, subagent_depth=1 (default do schema), max_recursion opcional
# (default do schema = 3).
_seed_db() {
  _sdb_db="$1"
  _sdb_max="${2:-}"
  "$SCHEMA_SCRIPT" create --db "$_sdb_db" >/dev/null 2>&1 \
    || { _fail "seed: schema create falhou" ""; return 1; }
  if [ -n "$_sdb_max" ]; then
    sqlite3 "$_sdb_db" "
      INSERT INTO execution (id,schema_version,target_project_path,target_project_description,status,started_at,current_stage,next_instruction,external_urls_whitelist,circular_movement_history,initial_key_aspects,atomic_commit_enabled,max_recursion)
      VALUES ('exec-1','1.0.0','/tmp/p','desc de teste com detalhe','em_andamento','2026-07-30T00:00:00Z','execute-task','faca algo','[]','[]','[]',0,$_sdb_max);
    " || { _fail "seed: insert execution falhou" ""; return 1; }
  else
    sqlite3 "$_sdb_db" "
      INSERT INTO execution (id,schema_version,target_project_path,target_project_description,status,started_at,current_stage,next_instruction,external_urls_whitelist,circular_movement_history,initial_key_aspects,atomic_commit_enabled)
      VALUES ('exec-1','1.0.0','/tmp/p','desc de teste com detalhe','em_andamento','2026-07-30T00:00:00Z','execute-task','faca algo','[]','[]','[]',0);
    " || { _fail "seed: insert execution falhou" ""; return 1; }
  fi
}

# ==== _st_db_get_current / _st_db_get_max ====

scenario_get_current_inicial_e_1() {
  _sd="$TMPDIR_TEST/get-current"
  mkdir -p "$_sd"
  _seed_db "$_sd/state.db" || return 1
  _out=$(_st_db_get_current "$_sd")
  [ "$_out" = "1" ] || { _fail "get_current inicial" "obtido '$_out'"; return 1; }
}

scenario_get_max_default_e_3() {
  _sd="$TMPDIR_TEST/get-max"
  mkdir -p "$_sd"
  _seed_db "$_sd/state.db" || return 1
  _out=$(_st_db_get_max "$_sd")
  [ "$_out" = "3" ] || { _fail "get_max default" "obtido '$_out'"; return 1; }
}

# ==== _st_db_check ====

scenario_check_abaixo_do_teto_exit_0() {
  _sd="$TMPDIR_TEST/check-ok"
  mkdir -p "$_sd"
  _seed_db "$_sd/state.db" || return 1
  ( _st_db_check "$_sd" )
  [ "$?" = 0 ] || { _fail "check abaixo do teto" "esperado exit 0"; return 1; }
}

scenario_check_no_teto_exit_3() {
  _sd="$TMPDIR_TEST/check-teto"
  mkdir -p "$_sd"
  _seed_db "$_sd/state.db" 1 || return 1  # max_recursion=1, current=1 -> next=2 > 1
  ( _st_db_check "$_sd" ) 2>"$TMPDIR_TEST/check-teto-err.txt"
  _rc=$?
  [ "$_rc" = 3 ] || { _fail "check no teto" "esperado exit 3, obtido $_rc"; return 1; }
  grep -q "profundidade no limite" "$TMPDIR_TEST/check-teto-err.txt" \
    || { _fail "check no teto mensagem" "$(cat "$TMPDIR_TEST/check-teto-err.txt")"; return 1; }
}

# ==== _st_db_enter ====

scenario_enter_incrementa_e_persiste() {
  _sd="$TMPDIR_TEST/enter-ok"
  mkdir -p "$_sd"
  _seed_db "$_sd/state.db" || return 1
  _out=$(_st_db_enter "$_sd")
  [ "$_out" = "2" ] || { _fail "enter incrementa" "obtido '$_out'"; return 1; }
  _persisted=$(sqlite3 "$_sd/state.db" "SELECT subagent_depth FROM execution;")
  [ "$_persisted" = "2" ] || { _fail "enter persistido" "obtido '$_persisted'"; return 1; }
}

scenario_enter_acima_do_teto_exit_3_sem_gravar() {
  _sd="$TMPDIR_TEST/enter-teto"
  mkdir -p "$_sd"
  _seed_db "$_sd/state.db" 1 || return 1  # max_recursion=1
  _before=$(sqlite3 "$_sd/state.db" "SELECT subagent_depth FROM execution;")
  ( _st_db_enter "$_sd" ) 2>"$TMPDIR_TEST/enter-teto-err.txt"
  _rc=$?
  [ "$_rc" = 3 ] || { _fail "enter acima do teto exit" "esperado 3, obtido $_rc"; return 1; }
  grep -q "excederia MAX" "$TMPDIR_TEST/enter-teto-err.txt" \
    || { _fail "enter acima do teto mensagem" "$(cat "$TMPDIR_TEST/enter-teto-err.txt")"; return 1; }
  _after=$(sqlite3 "$_sd/state.db" "SELECT subagent_depth FROM execution;")
  [ "$_before" = "$_after" ] || { _fail "enter negado MUTOU estado" "before=$_before after=$_after"; return 1; }
}

# ==== _st_db_leave ====

scenario_leave_decrementa() {
  _sd="$TMPDIR_TEST/leave-ok"
  mkdir -p "$_sd"
  _seed_db "$_sd/state.db" || return 1
  _st_db_enter "$_sd" >/dev/null
  _out=$(_st_db_leave "$_sd")
  [ "$_out" = "1" ] || { _fail "leave decrementa" "obtido '$_out'"; return 1; }
}

scenario_leave_idempotente_no_minimo() {
  _sd="$TMPDIR_TEST/leave-idempotente"
  mkdir -p "$_sd"
  _seed_db "$_sd/state.db" || return 1
  _out=$(_st_db_leave "$_sd")
  [ "$_out" = "1" ] || { _fail "leave idempotente" "obtido '$_out'"; return 1; }
  _persisted=$(sqlite3 "$_sd/state.db" "SELECT subagent_depth FROM execution;")
  [ "$_persisted" = "1" ] || { _fail "leave idempotente persistido" "obtido '$_persisted'"; return 1; }
}

# ==== _st_db_current ====

scenario_current_reflete_estado_apos_enter_e_leave() {
  _sd="$TMPDIR_TEST/current-fluxo"
  mkdir -p "$_sd"
  _seed_db "$_sd/state.db" || return 1
  _st_db_enter "$_sd" >/dev/null
  _st_db_enter "$_sd" >/dev/null
  _out=$(_st_db_current "$_sd")
  [ "$_out" = "3" ] || { _fail "current apos 2x enter" "obtido '$_out'"; return 1; }
  _st_db_leave "$_sd" >/dev/null
  _out=$(_st_db_current "$_sd")
  [ "$_out" = "2" ] || { _fail "current apos leave" "obtido '$_out'"; return 1; }
}

run_all_scenarios
