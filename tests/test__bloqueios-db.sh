#!/bin/sh
# test__bloqueios-db.sh — cobre
# global/skills/agente-00c-runtime/scripts/_bloqueios-db.sh
# (implementacao do backend SQLite de bloqueios.sh — feature
# state-db-foundation, FASE 3 task 3.5).
#
# Ref: docs/specs/state-db-foundation/tasks.md FASE 3, task 3.5
#      docs/specs/state-db-foundation/contracts/primitives.md §C1 C2 C3 C4 C6 C8
#
# Cobertura desta unit suite: helpers de baixo nivel
# (_bl_db_next_block_num_expr, _bl_db_exec_capture). O comportamento
# observavel via CLI (register/respond/list/count/next-id/get, incluindo o
# teste de concorrencia e o de FK) e coberto em tests/test_bloqueios.sh, que
# e o oraculo de paridade C1 (mesma superficie para os dois backends).

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

if ! command -v sqlite3 >/dev/null 2>&1; then
  printf '# test__bloqueios-db.sh: sqlite3 ausente — pulando suite\n'
  exit 0
fi
if ! command -v jq >/dev/null 2>&1; then
  printf '# test__bloqueios-db.sh: jq ausente — pulando suite\n'
  exit 0
fi

_R="$REPO_ROOT/global/skills/agente-00c-runtime/scripts"
# shellcheck source=../global/skills/agente-00c-runtime/scripts/_state-db.sh
. "$_R/_state-db.sh"
# shellcheck source=../global/skills/agente-00c-runtime/scripts/_state-rw-db.sh
. "$_R/_state-rw-db.sh"
# shellcheck source=../global/skills/agente-00c-runtime/scripts/_bloqueios-db.sh
. "$_R/_bloqueios-db.sh"

SCHEMA_SCRIPT="$_R/state-db-schema.sh"

# _sr_die/_bl_die: normalmente definidos por bloqueios.sh antes de sourcear
# estas libs. Fornecemos equivalentes minimos para exercitar as funcoes
# isoladas, sem depender do CLI completo.
_bl_die() { printf 'bloqueios: %s\n' "$1" >&2; exit "${2:-1}"; }
_sr_die() { _bl_die "$1" "${2:-1}"; }
_bl_iso_now() { date -u +%FT%TZ; }

# _seed_db PATH -> cria state.db minimo com execution id=exec-1 e decision
# id=dec-001.
_seed_db() {
  _sdb_db="$1"
  "$SCHEMA_SCRIPT" create --db "$_sdb_db" >/dev/null 2>&1 \
    || { _fail "seed: schema create falhou" ""; return 1; }
  sqlite3 "$_sdb_db" "
    PRAGMA foreign_keys=ON;
    INSERT INTO execution (id,schema_version,target_project_path,target_project_description,status,started_at,current_stage,next_instruction,external_urls_whitelist,circular_movement_history,initial_key_aspects,atomic_commit_enabled)
    VALUES ('exec-1','1.0.0','/tmp/p','desc de teste com detalhe','em_andamento','2026-07-30T00:00:00Z','execute-task','faca algo','[]','[]','[]',0);
    INSERT INTO decision (id,execution_id,timestamp,agent,stage,context,options_considered,choice,rationale)
    VALUES ('dec-001','exec-1','2026-07-30T00:00:00Z','x','clarify','contexto de teste com detalhe suficiente','[\"a\"]','a','justificativa de teste com detalhe suficiente');
  " || { _fail "seed: insert execution/decision falhou" ""; return 1; }
}

# ==== _bl_db_next_block_num_expr ====

scenario_next_block_num_expr_vazio_retorna_1() {
  _db="$TMPDIR_TEST/next-block-vazio.db"
  _seed_db "$_db" || return 1
  _expr=$(_bl_db_next_block_num_expr "'exec-1'")
  _out=$(_state_db_exec "$_db" "SELECT $_expr;")
  [ "$_out" = "1" ] || { _fail "next_block_num_expr vazio" "obtido '$_out'"; return 1; }
}

scenario_next_block_num_expr_apos_insert_retorna_2() {
  _db="$TMPDIR_TEST/next-block-apos.db"
  _seed_db "$_db" || return 1
  sqlite3 "$_db" "
    INSERT INTO human_block (id,execution_id,decision_id,question,context_for_answer,status,triggered_at)
    VALUES ('block-001','exec-1','dec-001','pergunta de teste com 20+ chars aqui','ctx','aguardando','2026-07-30T00:00:00Z');
  "
  _expr=$(_bl_db_next_block_num_expr "'exec-1'")
  _out=$(_state_db_exec "$_db" "SELECT $_expr;")
  [ "$_out" = "2" ] || { _fail "next_block_num_expr apos insert" "obtido '$_out'"; return 1; }
}

scenario_next_block_num_expr_isola_por_execution_id() {
  # Outra execution com bloqueios nao deve influenciar o calculo desta.
  _db="$TMPDIR_TEST/next-block-isola.db"
  _seed_db "$_db" || return 1
  sqlite3 "$_db" "
    INSERT INTO execution (id,schema_version,target_project_path,target_project_description,status,started_at,current_stage,next_instruction,external_urls_whitelist,circular_movement_history,initial_key_aspects,atomic_commit_enabled)
    VALUES ('exec-2','1.0.0','/tmp/p2','desc de teste com detalhe','em_andamento','2026-07-30T00:00:00Z','execute-task','faca algo','[]','[]','[]',0);
    INSERT INTO decision (id,execution_id,timestamp,agent,stage,context,options_considered,choice,rationale)
    VALUES ('dec-100','exec-2','2026-07-30T00:00:00Z','x','clarify','contexto de teste com detalhe suficiente','[\"a\"]','a','justificativa de teste com detalhe suficiente');
    INSERT INTO human_block (id,execution_id,decision_id,question,context_for_answer,status,triggered_at)
    VALUES ('block-001','exec-2','dec-100','pergunta de teste com 20+ chars aqui','ctx','aguardando','2026-07-30T00:00:00Z');
  "
  _expr=$(_bl_db_next_block_num_expr "'exec-1'")
  _out=$(_state_db_exec "$_db" "SELECT $_expr;")
  [ "$_out" = "1" ] || { _fail "next_block_num_expr isola execution" "obtido '$_out'"; return 1; }
}

# ==== _bl_db_exec_capture ====
#
# Chamada DIRETA (nunca dentro de $(...)) — ver nota de cabecalho em
# _bloqueios-db.sh: $_bl_db_last_out/$_bl_db_last_err so sobrevivem se a
# funcao NAO roda numa subshell de command substitution.

scenario_exec_capture_sucesso_preserva_last_out() {
  _db="$TMPDIR_TEST/exec-capture-ok.db"
  _seed_db "$_db" || return 1
  if _bl_db_exec_capture "$_db" "SELECT 'ok-' || 42;"; then
    :
  else
    _fail "exec_capture sucesso" "deveria ter retornado 0"
    return 1
  fi
  [ "$_bl_db_last_out" = "ok-42" ] || { _fail "exec_capture last_out" "obtido '$_bl_db_last_out'"; return 1; }
}

scenario_exec_capture_erro_nao_lock_falha_imediato_e_seta_last_err() {
  _db="$TMPDIR_TEST/exec-capture-erro.db"
  _seed_db "$_db" || return 1
  if _bl_db_exec_capture "$_db" "INSERT INTO tabela_inexistente (x) VALUES (1);"; then
    _fail "exec_capture erro nao-lock" "deveria falhar"
    return 1
  fi
  case "$_bl_db_last_err" in
    *"no such table"*) ;;
    *) _fail "exec_capture last_err" "esperava 'no such table', obtido '$_bl_db_last_err'"; return 1 ;;
  esac
}

# Regressao do bug achado na task 3.5: uma falha de FOREIGN KEY precisa
# propagar ate $_bl_db_last_err mesmo com o caller rodando sob `set -eu`
# (bloqueios.sh sempre roda com essas flags) — sem o guard `if x=$(cmd);
# then...else...fi` dentro de _bl_db_exec_capture, o processo morreria na
# primeira falha de _state_db_exec sem alcancar o `case` de retry (C6).
scenario_exec_capture_fk_falha_seta_last_err_com_foreign_key() {
  _db="$TMPDIR_TEST/exec-capture-fk.db"
  _seed_db "$_db" || return 1
  _sql="BEGIN IMMEDIATE; INSERT INTO human_block (id,execution_id,decision_id,question,context_for_answer,status,triggered_at) VALUES ('block-001','exec-1','dec-fantasma','pergunta de teste com 20+ chars aqui','ctx','aguardando','2026-07-30T00:00:00Z'); COMMIT;"
  if _bl_db_exec_capture "$_db" "$_sql"; then
    _fail "exec_capture FK" "deveria falhar (decision_id inexistente)"
    return 1
  fi
  case "$_bl_db_last_err" in
    *"FOREIGN KEY constraint failed"*) ;;
    *) _fail "exec_capture FK last_err" "esperava FOREIGN KEY, obtido '$_bl_db_last_err'"; return 1 ;;
  esac
  # Transacao revertida — nenhuma linha persistida.
  _cnt=$(sqlite3 "$_db" "SELECT count(*) FROM human_block;")
  [ "$_cnt" = "0" ] || { _fail "exec_capture FK rollback" "esperado 0 linhas, obtido $_cnt"; return 1; }
}

scenario_exec_capture_transacao_com_select_antes_do_commit() {
  # Mesmo padrao usado por register: BEGIN IMMEDIATE + INSERT + SELECT do
  # proprio rowid + COMMIT, tudo numa unica invocacao — garante que
  # $_bl_db_last_out e o da linha recem-inserida por ESTA sessao.
  _db="$TMPDIR_TEST/exec-capture-tx.db"
  _seed_db "$_db" || return 1
  _sql="BEGIN IMMEDIATE; INSERT INTO human_block (id,execution_id,decision_id,question,context_for_answer,status,triggered_at) VALUES ('block-001','exec-1','dec-001','pergunta de teste com 20+ chars aqui','ctx','aguardando','2026-07-30T00:00:00Z'); SELECT id FROM human_block WHERE rowid=last_insert_rowid(); COMMIT;"
  if ! _bl_db_exec_capture "$_db" "$_sql"; then
    _fail "exec_capture tx select" "deveria ter sucedido: $_bl_db_last_err"
    return 1
  fi
  [ "$_bl_db_last_out" = "block-001" ] || { _fail "exec_capture tx select last_out" "obtido '$_bl_db_last_out'"; return 1; }
  _cnt=$(sqlite3 "$_db" "SELECT count(*) FROM human_block;")
  [ "$_cnt" = "1" ] || { _fail "exec_capture tx commitou" "obtido '$_cnt'"; return 1; }
}

run_all_scenarios
