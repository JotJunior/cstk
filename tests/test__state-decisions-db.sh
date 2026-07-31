#!/bin/sh
# test__state-decisions-db.sh — cobre
# global/skills/agente-00c-runtime/scripts/_state-decisions-db.sh
# (implementacao do backend SQLite de state-decisions.sh — feature
# state-db-foundation, FASE 3 task 3.4).
#
# Ref: docs/specs/state-db-foundation/tasks.md FASE 3, task 3.4
#      docs/specs/state-db-foundation/contracts/primitives.md §C1 C2 C4 C6 C8
#
# Cobertura desta unit suite: helpers de baixo nivel (_sd_db_next_num_expr,
# _sd_db_exec_capture, _sd_db_current_wave_id). O comportamento observavel
# via CLI (register/count/next-id/list, incluindo o teste de concorrencia
# 3.4.3) e coberto em tests/test_state-decisions.sh, que e o oraculo de
# paridade C1 (mesma superficie para os dois backends).

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

if ! command -v sqlite3 >/dev/null 2>&1; then
  printf '# test__state-decisions-db.sh: sqlite3 ausente — pulando suite\n'
  exit 0
fi
if ! command -v jq >/dev/null 2>&1; then
  printf '# test__state-decisions-db.sh: jq ausente — pulando suite\n'
  exit 0
fi

_R="$REPO_ROOT/global/skills/agente-00c-runtime/scripts"
# shellcheck source=../global/skills/agente-00c-runtime/scripts/_state-db.sh
. "$_R/_state-db.sh"
# shellcheck source=../global/skills/agente-00c-runtime/scripts/_state-rw-db.sh
. "$_R/_state-rw-db.sh"
# shellcheck source=../global/skills/agente-00c-runtime/scripts/_state-decisions-db.sh
. "$_R/_state-decisions-db.sh"

SCHEMA_SCRIPT="$_R/state-db-schema.sh"

# _sr_die/_sd_die: normalmente definidos por state-decisions.sh antes de
# sourcear estas libs. Fornecemos equivalentes minimos para exercitar as
# funcoes isoladas, sem depender do CLI completo.
_sd_die() { printf 'state-decisions: %s\n' "$1" >&2; exit "${2:-1}"; }
_sr_die() { _sd_die "$1" "${2:-1}"; }
_sd_iso_now() { date -u +%FT%TZ; }

# _seed_db PATH -> cria state.db minimo com execution id=exec-1.
_seed_db() {
  _sdb_db="$1"
  "$SCHEMA_SCRIPT" create --db "$_sdb_db" >/dev/null 2>&1 \
    || { _fail "seed: schema create falhou" ""; return 1; }
  sqlite3 "$_sdb_db" "
    PRAGMA foreign_keys=ON;
    INSERT INTO execution (id,schema_version,target_project_path,target_project_description,status,started_at,current_stage,next_instruction,external_urls_whitelist,circular_movement_history,initial_key_aspects,atomic_commit_enabled)
    VALUES ('exec-1','1.0.0','/tmp/p','desc de teste com detalhe','em_andamento','2026-07-30T00:00:00Z','execute-task','faca algo','[]','[]','[]',0);
  " || { _fail "seed: insert execution falhou" ""; return 1; }
}

# ==== _sd_db_next_num_expr ====

scenario_next_num_expr_vazio_retorna_1() {
  _db="$TMPDIR_TEST/next-num-vazio.db"
  _seed_db "$_db" || return 1
  _expr=$(_sd_db_next_num_expr "'exec-1'")
  _out=$(_state_db_exec "$_db" "SELECT $_expr;")
  [ "$_out" = "1" ] || { _fail "next_num_expr vazio" "obtido '$_out'"; return 1; }
}

scenario_next_num_expr_apos_insert_retorna_2() {
  _db="$TMPDIR_TEST/next-num-apos.db"
  _seed_db "$_db" || return 1
  sqlite3 "$_db" "
    INSERT INTO decision (id,execution_id,timestamp,agent,stage,context,options_considered,choice,rationale)
    VALUES ('dec-001','exec-1','2026-07-30T00:00:00Z','x','specify','contexto de teste com detalhe suficiente','[\"a\"]','a','justificativa de teste com detalhe suficiente');
  "
  _expr=$(_sd_db_next_num_expr "'exec-1'")
  _out=$(_state_db_exec "$_db" "SELECT $_expr;")
  [ "$_out" = "2" ] || { _fail "next_num_expr apos insert" "obtido '$_out'"; return 1; }
}

scenario_next_num_expr_isola_por_execution_id() {
  # Outra execution com decisoes nao deve influenciar o calculo desta.
  _db="$TMPDIR_TEST/next-num-isola.db"
  _seed_db "$_db" || return 1
  sqlite3 "$_db" "
    INSERT INTO execution (id,schema_version,target_project_path,target_project_description,status,started_at,current_stage,next_instruction,external_urls_whitelist,circular_movement_history,initial_key_aspects,atomic_commit_enabled)
    VALUES ('exec-2','1.0.0','/tmp/p2','desc de teste com detalhe','em_andamento','2026-07-30T00:00:00Z','execute-task','faca algo','[]','[]','[]',0);
    INSERT INTO decision (id,execution_id,timestamp,agent,stage,context,options_considered,choice,rationale)
    VALUES ('dec-001','exec-2','2026-07-30T00:00:00Z','x','specify','contexto de teste com detalhe suficiente','[\"a\"]','a','justificativa de teste com detalhe suficiente');
  "
  _expr=$(_sd_db_next_num_expr "'exec-1'")
  _out=$(_state_db_exec "$_db" "SELECT $_expr;")
  [ "$_out" = "1" ] || { _fail "next_num_expr isola execution" "obtido '$_out'"; return 1; }
}

# ==== _sd_db_current_wave_id ====

scenario_current_wave_id_vazio_sem_ondas() {
  _db="$TMPDIR_TEST/wave-id-vazio.db"
  _seed_db "$_db" || return 1
  _out=$(_sd_db_current_wave_id "$_db" "exec-1")
  [ -z "$_out" ] || { _fail "current_wave_id vazio" "obtido '$_out'"; return 1; }
}

scenario_current_wave_id_pega_ultima_por_seq() {
  _db="$TMPDIR_TEST/wave-id-ultima.db"
  _seed_db "$_db" || return 1
  sqlite3 "$_db" "
    INSERT INTO wave (id,execution_id,seq,started_at,executed_stages)
    VALUES ('onda-001','exec-1',1,'2026-07-30T00:00:00Z','[]');
    INSERT INTO wave (id,execution_id,seq,started_at,finished_at,termination_reason,executed_stages)
    VALUES ('onda-002','exec-1',2,'2026-07-30T00:01:00Z','2026-07-30T00:02:00Z','etapa_concluida_avancando','[]');
  "
  _out=$(_sd_db_current_wave_id "$_db" "exec-1")
  # paridade com .waves[-1].id do path JSON: pega a ultima por seq, mesmo
  # ja fechada — nao filtra por onda aberta.
  [ "$_out" = "onda-002" ] || { _fail "current_wave_id ultima" "obtido '$_out'"; return 1; }
}

# ==== _sd_db_exec_capture ====

scenario_exec_capture_sucesso_preserva_stdout() {
  _db="$TMPDIR_TEST/exec-capture-ok.db"
  _seed_db "$_db" || return 1
  _out=$(_sd_db_exec_capture "$_db" "SELECT 'ok-' || 42;")
  [ "$_out" = "ok-42" ] || { _fail "exec_capture stdout" "obtido '$_out'"; return 1; }
}

scenario_exec_capture_erro_nao_lock_falha_imediato() {
  _db="$TMPDIR_TEST/exec-capture-erro.db"
  _seed_db "$_db" || return 1
  capture _sd_db_exec_capture "$_db" "INSERT INTO tabela_inexistente (x) VALUES (1);"
  [ "$_CAPTURED_EXIT" != 0 ] || { _fail "exec_capture erro nao-lock" "deveria falhar"; return 1; }
}

scenario_exec_capture_transacao_com_select_antes_do_commit() {
  # Mesmo padrao usado por register: BEGIN IMMEDIATE + INSERT + SELECT do
  # proprio rowid + COMMIT, tudo numa unica invocacao — garante que o
  # stdout devolvido e o da linha recem-inserida por ESTA sessao.
  _db="$TMPDIR_TEST/exec-capture-tx.db"
  _seed_db "$_db" || return 1
  _sql="BEGIN IMMEDIATE; INSERT INTO decision (id,execution_id,timestamp,agent,stage,context,options_considered,choice,rationale) VALUES ('dec-001','exec-1','2026-07-30T00:00:00Z','x','specify','contexto de teste com detalhe suficiente','[\"a\"]','a','justificativa de teste com detalhe suficiente'); SELECT id FROM decision WHERE rowid=last_insert_rowid(); COMMIT;"
  _out=$(_sd_db_exec_capture "$_db" "$_sql")
  [ "$_out" = "dec-001" ] || { _fail "exec_capture tx select" "obtido '$_out'"; return 1; }
  _cnt=$(sqlite3 "$_db" "SELECT count(*) FROM decision;")
  [ "$_cnt" = "1" ] || { _fail "exec_capture tx commitou" "obtido '$_cnt'"; return 1; }
}

run_all_scenarios
