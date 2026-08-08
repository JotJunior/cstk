#!/bin/sh
# test__state-rw-db.sh — cobre plugins/cstk/skills/agente-00c-runtime/scripts/_state-rw-db.sh
# (implementacao do backend SQLite de state-rw.sh — feature state-db-foundation,
# FASE 3 task 3.2).
#
# Ref: docs/specs/state-db-foundation/tasks.md FASE 3, task 3.2
#      docs/specs/state-db-foundation/contracts/primitives.md §C1 C2 C7
#
# Cobertura desta unit suite: helpers de baixo nivel (_sr_sql_quote,
# _sr_sql_literal, _sr_backend, _sr_db_file, _sr_exec_col_lookup). O
# comportamento observavel via CLI (read/get/set/write/sha256-*) e coberto
# em tests/test_state-rw.sh, que e o oraculo de paridade C1 (mesma superficie
# para os dois backends).

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

if ! command -v sqlite3 >/dev/null 2>&1; then
  printf '# test__state-rw-db.sh: sqlite3 ausente — pulando suite\n'
  exit 0
fi
if ! command -v jq >/dev/null 2>&1; then
  printf '# test__state-rw-db.sh: jq ausente — pulando suite\n'
  exit 0
fi

_R="$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts"
# shellcheck source=../plugins/cstk/skills/agente-00c-runtime/scripts/_diag.sh
. "$_R/_diag.sh"
# shellcheck source=../plugins/cstk/skills/agente-00c-runtime/scripts/_state-db.sh
. "$_R/_state-db.sh"
# shellcheck source=../plugins/cstk/skills/agente-00c-runtime/scripts/_state-rw-db.sh
. "$_R/_state-rw-db.sh"

# _sr_die/_SR_NAME: normalmente definidos por state-rw.sh antes de sourcear
# este lib. Fornecemos equivalentes minimos para exercitar as funcoes isoladas.
_SR_NAME="state-rw"
_sr_die() {
  printf '%s: %s\n' "$_SR_NAME" "$1" >&2
  exit "${2:-1}"
}

# ==== _sr_backend / _sr_db_file ====

scenario_backend_json_quando_sem_state_db() {
  _sd="$TMPDIR_TEST/proj"
  mkdir -p "$_sd"
  _out=$(_sr_backend "$_sd")
  [ "$_out" = "json" ] || { _fail "_sr_backend" "esperado 'json', obtido '$_out'"; return 1; }
}

scenario_backend_sqlite_quando_state_db_existe() {
  _sd="$TMPDIR_TEST/proj"
  mkdir -p "$_sd"
  : > "$_sd/state.db"
  _out=$(_sr_backend "$_sd")
  [ "$_out" = "sqlite" ] || { _fail "_sr_backend" "esperado 'sqlite', obtido '$_out'"; return 1; }
}

# ==== _sr_sql_quote (C8: paridade com sql_escape/strip_nul) ====

scenario_sql_quote_escapa_aspa_simples() {
  _out=$(_sr_sql_quote "it's a test")
  [ "$_out" = "'it''s a test'" ] || { _fail "_sr_sql_quote" "obtido '$_out'"; return 1; }
}

scenario_sql_quote_payload_hostil_preservado_literal() {
  _out=$(_sr_sql_quote "'; DROP TABLE decision; --")
  [ "$_out" = "'''; DROP TABLE decision; --'" ] || { _fail "_sr_sql_quote hostil" "obtido '$_out'"; return 1; }
}

# ==== _sr_sql_literal ====

scenario_sql_literal_str_null_vira_sql_null() {
  _out=$(_sr_sql_literal str 'null')
  [ "$_out" = "NULL" ] || { _fail "sql_literal str null" "obtido '$_out'"; return 1; }
}

scenario_sql_literal_str_string_e_escapada() {
  _out=$(_sr_sql_literal str '"o apostrofo dele'"'"'s"')
  [ "$_out" = "'o apostrofo dele''s'" ] || { _fail "sql_literal str" "obtido '$_out'"; return 1; }
}

scenario_sql_literal_int_number_passa_direto() {
  _out=$(_sr_sql_literal int '42')
  [ "$_out" = "42" ] || { _fail "sql_literal int" "obtido '$_out'"; return 1; }
}

scenario_sql_literal_int_rejeita_nao_numero() {
  _out=$(_sr_sql_literal int '"abc"' 2>/dev/null)
  _rc=$?
  [ "$_rc" != 0 ] || { _fail "sql_literal int nao-numero" "esperado exit != 0"; return 1; }
}

scenario_sql_literal_bool_true_vira_1() {
  _out=$(_sr_sql_literal bool 'true')
  [ "$_out" = "1" ] || { _fail "sql_literal bool true" "obtido '$_out'"; return 1; }
}

scenario_sql_literal_bool_false_vira_0() {
  _out=$(_sr_sql_literal bool 'false')
  [ "$_out" = "0" ] || { _fail "sql_literal bool false" "obtido '$_out'"; return 1; }
}

scenario_sql_literal_json_array_e_quotado_compacto() {
  _out=$(_sr_sql_literal json '["a", "b"]')
  [ "$_out" = "'[\"a\",\"b\"]'" ] || { _fail "sql_literal json" "obtido '$_out'"; return 1; }
}

scenario_sql_literal_json_null_vira_sql_null() {
  _out=$(_sr_sql_literal json 'null')
  [ "$_out" = "NULL" ] || { _fail "sql_literal json null" "obtido '$_out'"; return 1; }
}

# ==== _sr_exec_col_lookup ====

scenario_exec_col_lookup_mapeia_top_level_conhecido() {
  _sr_exec_col_lookup "current_stage"
  [ "$_sr_lu_col" = "current_stage" ] || { _fail "lookup current_stage" "col='$_sr_lu_col'"; return 1; }
  [ "$_sr_lu_type" = "str" ] || { _fail "lookup current_stage type" "type='$_sr_lu_type'"; return 1; }
}

scenario_exec_col_lookup_mapeia_prefixo_execution() {
  _sr_exec_col_lookup "execution.status"
  [ "$_sr_lu_col" = "status" ] || { _fail "lookup execution.status" "col='$_sr_lu_col'"; return 1; }
}

scenario_exec_col_lookup_mapeia_budgets_com_nome_diferente() {
  # budgets.current_subagent_depth -> coluna subagent_depth (nomes NAO coincidem)
  _sr_exec_col_lookup "budgets.current_subagent_depth"
  [ "$_sr_lu_col" = "subagent_depth" ] || { _fail "lookup budgets" "col='$_sr_lu_col'"; return 1; }
}

scenario_exec_col_lookup_desconhecido_fica_vazio() {
  _sr_exec_col_lookup "next_retrospective_milestone"
  [ -z "$_sr_lu_col" ] || { _fail "lookup desconhecido" "esperado vazio, obtido '$_sr_lu_col'"; return 1; }
}

scenario_exec_col_lookup_id_e_imutavel() {
  _out=$(_sr_exec_col_lookup "id" 2>&1)
  _rc=$?
  [ "$_rc" != 0 ] || { _fail "lookup id imutavel" "esperado exit != 0"; return 1; }
  case "$_out" in
    *imutavel*) : ;;
    *) _fail "lookup id imutavel msg" "obtido: $_out"; return 1 ;;
  esac
}

run_all_scenarios
