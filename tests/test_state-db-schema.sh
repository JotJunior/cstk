#!/bin/sh
# test_state-db-schema.sh — cobre global/skills/agente-00c-runtime/scripts/state-db-schema.sh
# e o DDL em global/skills/agente-00c-runtime/references/state-db-schema.sql.
#
# Ref: docs/specs/state-db-foundation/data-model.md (contrato das constraints)
#      docs/specs/state-db-foundation/tasks.md FASE 2 (2.1 DDL, 2.2 invariantes)

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/state-db-schema.sh"

if ! command -v sqlite3 >/dev/null 2>&1; then
  printf '# test_state-db-schema.sh: sqlite3 ausente — pulando suite\n'
  exit 0
fi

_seed_execution() {
  # $1 = db path, $2 = execution id (default exec-1)
  _se_db="$1"
  _se_id="${2:-exec-1}"
  sqlite3 "$_se_db" "INSERT INTO execution
    (id,schema_version,target_project_path,target_project_description,status,started_at,current_stage,next_instruction)
    VALUES ('$_se_id','1.0.0','/tmp/p','desc','em_andamento','2026-07-30T00:00:00Z','specify','x');"
}

scenario_create_gera_banco_com_9_tabelas() {
  _db="$TMPDIR_TEST/state.db"
  capture "$SCRIPT" create --db "$_db"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "create" "$_CAPTURED_STDERR"; return 1; }
  [ -f "$_db" ] || { _fail "create" "banco nao criado em $_db"; return 1; }
  _n=$(sqlite3 "$_db" "SELECT count(*) FROM sqlite_master WHERE type='table';")
  [ "$_n" = 9 ] || { _fail "tabelas" "esperado 9, obtido $_n"; return 1; }
}

scenario_create_e_idempotente() {
  _db="$TMPDIR_TEST/state.db"
  capture "$SCRIPT" create --db "$_db"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "create1" "$_CAPTURED_STDERR"; return 1; }
  capture "$SCRIPT" create --db "$_db"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "create2 (reexecucao)" "$_CAPTURED_STDERR"; return 1; }
}

scenario_create_aplica_wal() {
  _db="$TMPDIR_TEST/state.db"
  capture "$SCRIPT" create --db "$_db"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "create" "$_CAPTURED_STDERR"; return 1; }
  _mode=$(sqlite3 "$_db" "PRAGMA journal_mode;")
  [ "$_mode" = "wal" ] || { _fail "journal_mode" "esperado wal, obtido $_mode"; return 1; }
}

scenario_create_chmod_600() {
  _db="$TMPDIR_TEST/state.db"
  capture "$SCRIPT" create --db "$_db"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "create" "$_CAPTURED_STDERR"; return 1; }
  _perm=$(perl -e 'printf "%03o", (stat($ARGV[0]))[2] & 07777' "$_db" 2>/dev/null) \
    || _perm=$(stat -c '%a' "$_db" 2>/dev/null) \
    || _perm=$(stat -f '%Lp' "$_db" 2>/dev/null)
  [ "$_perm" = "600" ] || { _fail "chmod" "esperado 600, obtido $_perm"; return 1; }
}

scenario_wave_ux_wave_single_open_bloqueia_segunda_onda_aberta() {
  _db="$TMPDIR_TEST/state.db"
  "$SCRIPT" create --db "$_db" >/dev/null
  _seed_execution "$_db"
  sqlite3 "$_db" "INSERT INTO wave (id,execution_id,seq,started_at) VALUES ('onda-001','exec-1',1,'2026-07-30T00:00:00Z');"
  capture sqlite3 "$_db" "INSERT INTO wave (id,execution_id,seq,started_at) VALUES ('onda-002','exec-1',2,'2026-07-30T00:01:00Z');"
  [ "$_CAPTURED_EXIT" != 0 ] || { _fail "ux_wave_single_open" "segunda onda aberta deveria falhar"; return 1; }
}

scenario_wave_trg_wave_close_once_bloqueia_reabertura() {
  _db="$TMPDIR_TEST/state.db"
  "$SCRIPT" create --db "$_db" >/dev/null
  _seed_execution "$_db"
  sqlite3 "$_db" "INSERT INTO wave (id,execution_id,seq,started_at) VALUES ('onda-001','exec-1',1,'2026-07-30T00:00:00Z');"
  sqlite3 "$_db" "UPDATE wave SET termination_reason='concluido', finished_at='2026-07-30T00:05:00Z' WHERE id='onda-001';"
  capture sqlite3 "$_db" "UPDATE wave SET termination_reason='aborto', finished_at='2026-07-30T00:06:00Z' WHERE id='onda-001';"
  [ "$_CAPTURED_EXIT" != 0 ] || { _fail "trg_wave_close_once" "reabrir onda fechada deveria falhar"; return 1; }
  # apos fechar a primeira, uma segunda onda aberta e permitida
  capture sqlite3 "$_db" "INSERT INTO wave (id,execution_id,seq,started_at) VALUES ('onda-002','exec-1',2,'2026-07-30T00:07:00Z');"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "segunda onda pos-fechamento" "$_CAPTURED_STDERR"; return 1; }
}

scenario_decision_campo_obrigatorio_ausente_e_rejeitado() {
  _db="$TMPDIR_TEST/state.db"
  "$SCRIPT" create --db "$_db" >/dev/null
  _seed_execution "$_db"
  # context com menos de 20 chars
  capture sqlite3 "$_db" "INSERT INTO decision (id,execution_id,timestamp,agent,stage,context,options_considered,choice,rationale) VALUES ('dec-001','exec-1','2026-07-30T00:00:00Z','agente','etapa','curto','[\"a\"]','a','justificativa valida com >=20 chars');"
  [ "$_CAPTURED_EXIT" != 0 ] || { _fail "context curto" "deveria ser rejeitado pelo CHECK"; return 1; }
}

scenario_decision_score3_sem_evidencia_e_rejeitado() {
  _db="$TMPDIR_TEST/state.db"
  "$SCRIPT" create --db "$_db" >/dev/null
  _seed_execution "$_db"
  capture sqlite3 "$_db" "INSERT INTO decision (id,execution_id,timestamp,agent,stage,context,options_considered,choice,rationale,justification_score) VALUES ('dec-001','exec-1','2026-07-30T00:00:00Z','agente','etapa','contexto com pelo menos 20 chars','[\"a\",\"b\"]','a','justificativa com pelo menos 20 chars',3);"
  [ "$_CAPTURED_EXIT" != 0 ] || { _fail "score3 sem evidencia" "deveria ser rejeitado pelo CHECK"; return 1; }
  # com evidencia >= 20 chars, deve passar
  capture sqlite3 "$_db" "INSERT INTO decision (id,execution_id,timestamp,agent,stage,context,options_considered,choice,rationale,justification_score,evidence) VALUES ('dec-002','exec-1','2026-07-30T00:00:00Z','agente','etapa','contexto com pelo menos 20 chars','[\"a\",\"b\"]','a','justificativa com pelo menos 20 chars',3,'evidencia literal com >= 20 chars');"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "score3 com evidencia" "$_CAPTURED_STDERR"; return 1; }
}

scenario_decision_payload_hostil_persistido_literal() {
  _db="$TMPDIR_TEST/state.db"
  "$SCRIPT" create --db "$_db" >/dev/null
  _seed_execution "$_db"
  # apostrofo simples (escapado a SQL padrao, '' ) + fragmento de injecao
  # como TEXTO LITERAL dentro do valor — via script SQL aplicado com
  # `sqlite3 db < arquivo.sql`, mesmo caminho real de aplicacao do DDL.
  # Cobre a mesma garantia de C8 (contracts/primitives.md): dado hostil
  # nunca reinterpretado como SQL quando corretamente escapado.
  _sqlfile="$TMPDIR_TEST/payload.sql"
  cat > "$_sqlfile" <<'EOF'
INSERT INTO decision (id,execution_id,timestamp,agent,stage,context,options_considered,choice,rationale)
  VALUES ('dec-001','exec-1','2026-07-30T00:00:00Z','agente','etapa',
          'contexto com apostrofo '' e fragmento; DROP TABLE decision; -- e mais texto',
          '["a"]','a','justificativa valida com >= 20 chars');
EOF
  capture sqlite3 "$_db" ".read $_sqlfile"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "payload hostil" "$_CAPTURED_STDERR"; return 1; }
  _n=$(sqlite3 "$_db" "SELECT count(*) FROM decision;")
  [ "$_n" = 1 ] || { _fail "tabela decision sobreviveu" "esperado 1 linha, obtido $_n"; return 1; }
  _tables_still=$(sqlite3 "$_db" "SELECT count(*) FROM sqlite_master WHERE type='table';")
  [ "$_tables_still" = 9 ] || { _fail "tabelas apos payload" "esperado 9, obtido $_tables_still"; return 1; }
  _stored=$(sqlite3 "$_db" "SELECT context FROM decision WHERE id='dec-001';")
  case "$_stored" in
    *"DROP TABLE decision"*) : ;;
    *) _fail "conteudo literal" "payload nao persistido literalmente: $_stored"; return 1 ;;
  esac
}

scenario_human_block_fk_decisao_inexistente_e_rejeitado_com_fk_on() {
  _db="$TMPDIR_TEST/state.db"
  "$SCRIPT" create --db "$_db" >/dev/null
  _seed_execution "$_db"
  capture sqlite3 "$_db" "PRAGMA foreign_keys=ON; INSERT INTO human_block (id,execution_id,decision_id,question,context_for_answer,status,triggered_at) VALUES ('block-001','exec-1','dec-999','pergunta com pelo menos 20 chars','contexto','aguardando','2026-07-30T00:00:00Z');"
  [ "$_CAPTURED_EXIT" != 0 ] || { _fail "fk decisao inexistente" "deveria ser rejeitado pela FOREIGN KEY"; return 1; }
}

scenario_execution_subagent_depth_acima_do_teto_e_rejeitado() {
  # Paridade com spawn-tracker.sh `enter` (exit 3 no teto _ST_MAX=3):
  # sob o backend SQLite, tentar gravar profundidade acima de
  # max_recursion falha na propria camada de banco (CHECK), nao apenas no
  # script chamador.
  _db="$TMPDIR_TEST/state.db"
  "$SCRIPT" create --db "$_db" >/dev/null
  _seed_execution "$_db"
  # max_recursion default = 3 (DEFAULT do schema); depth=3 e valido (== teto).
  capture sqlite3 "$_db" "UPDATE execution SET subagent_depth=3 WHERE id='exec-1';"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "depth=3 (== teto)" "$_CAPTURED_STDERR"; return 1; }
  # depth=4 (> teto de 3) deve ser rejeitado pelo CHECK.
  capture sqlite3 "$_db" "UPDATE execution SET subagent_depth=4 WHERE id='exec-1';"
  [ "$_CAPTURED_EXIT" != 0 ] || { _fail "depth=4 (> teto)" "deveria ser rejeitado pelo CHECK (subagent_depth <= max_recursion)"; return 1; }
}

scenario_task_outcome_pk_composta_upsert_idempotente() {
  _db="$TMPDIR_TEST/state.db"
  "$SCRIPT" create --db "$_db" >/dev/null
  _seed_execution "$_db"
  sqlite3 "$_db" "INSERT INTO wave (id,execution_id,seq,started_at) VALUES ('onda-001','exec-1',1,'2026-07-30T00:00:00Z');"
  sqlite3 "$_db" "INSERT INTO task_outcome (execution_id,task_id,title,wave_id,outcome,tests_run,tests_passed,touched_files,recorded_at) VALUES ('exec-1','1.1','t','onda-001','pass',0,0,'[]','2026-07-30T00:00:00Z');"
  capture sqlite3 "$_db" "INSERT INTO task_outcome (execution_id,task_id,title,wave_id,outcome,tests_run,tests_passed,touched_files,recorded_at) VALUES ('exec-1','1.1','t','onda-001','fail',0,0,'[]','2026-07-30T00:01:00Z');"
  [ "$_CAPTURED_EXIT" != 0 ] || { _fail "pk composta" "segunda linha com mesma (execution_id, task_id) deveria colidir na PK"; return 1; }
}

run_all_scenarios
