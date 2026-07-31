#!/bin/sh
# test__state-db.sh — cobre global/skills/agente-00c-runtime/scripts/_state-db.sh
# (helpers sourceaveis compartilhados do backend SQLite do state.db).
#
# Ref: docs/specs/state-db-foundation/tasks.md FASE 3, task 3.1
#      docs/specs/state-db-foundation/contracts/primitives.md §C5 C6 C8 C9

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

STATE_DB_LIB="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/_state-db.sh"
SCHEMA_SCRIPT="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/state-db-schema.sh"

if ! command -v sqlite3 >/dev/null 2>&1; then
  printf '# test__state-db.sh: sqlite3 ausente — pulando suite\n'
  exit 0
fi

# shellcheck source=../global/skills/agente-00c-runtime/scripts/_state-db.sh
. "$STATE_DB_LIB"

scenario_sql_escape_duplica_aspa_simples() {
  _out=$(sql_escape "it's a test")
  [ "$_out" = "it''s a test" ] || { _fail "sql_escape" "esperado \"it''s a test\", obtido \"$_out\""; return 1; }
}

scenario_sql_escape_payload_hostil_preservado_como_texto() {
  _out=$(sql_escape "'; DROP TABLE decision; --")
  [ "$_out" = "''; DROP TABLE decision; --" ] || { _fail "sql_escape hostil" "obtido \"$_out\""; return 1; }
}

scenario_strip_nul_remove_bytes_nul() {
  _out=$(printf 'wid\000get' | strip_nul)
  [ "$_out" = "widget" ] || { _fail "strip_nul" "esperado 'widget', obtido '$_out'"; return 1; }
}

# Paridade: sql_escape/strip_nul desta copia produzem EXATAMENTE a mesma
# saida que a copia REAL em cli/lib/recall.sh (sourced isolada em subshell,
# via mesmo mecanismo que tests/cstk/test_recall.sh usa), para o mesmo
# conjunto de payloads (incluindo o payload hostil de C8). Garante que as
# duas copias documentadas no cabecalho de _state-db.sh nunca divirjam
# silenciosamente em algoritmo.
scenario_paridade_com_cli_lib_recall_sql_escape() {
  _cstk_lib="$REPO_ROOT/cli/lib"
  [ -f "$_cstk_lib/recall.sh" ] || { _fail "paridade" "cli/lib/recall.sh nao encontrado"; return 1; }
  for _payload in "it's a test" "'; DROP TABLE decision; --" "sem aspas" "'''"; do
    _ours=$(sql_escape "$_payload")
    _theirs=$(CSTK_LIB="$_cstk_lib" sh -c '
      . "$CSTK_LIB/common.sh" 2>/dev/null
      . "$CSTK_LIB/recall.sh" 2>/dev/null
      sql_escape "$1"
    ' _ "$_payload")
    [ "$_ours" = "$_theirs" ] || { _fail "paridade sql_escape" "payload='$_payload' ours='$_ours' theirs='$_theirs'"; return 1; }
  done
}

scenario_paridade_com_cli_lib_recall_strip_nul() {
  _cstk_lib="$REPO_ROOT/cli/lib"
  [ -f "$_cstk_lib/recall.sh" ] || { _fail "paridade" "cli/lib/recall.sh nao encontrado"; return 1; }
  _ours=$(printf 'wid\000get' | strip_nul)
  _theirs=$(printf 'wid\000get' | CSTK_LIB="$_cstk_lib" sh -c '
    . "$CSTK_LIB/common.sh" 2>/dev/null
    . "$CSTK_LIB/recall.sh" 2>/dev/null
    strip_nul
  ')
  [ "$_ours" = "$_theirs" ] || { _fail "paridade strip_nul" "ours='$_ours' theirs='$_theirs'"; return 1; }
}

scenario_state_db_pragmas_default_5000() {
  _out=$(_state_db_pragmas)
  case "$_out" in
    *"PRAGMA foreign_keys=ON;"*"PRAGMA busy_timeout=5000;"*) : ;;
    *) _fail "pragmas default" "obtido: $_out"; return 1 ;;
  esac
}

scenario_state_db_pragmas_ms_customizado() {
  _out=$(_state_db_pragmas 9000)
  case "$_out" in
    *"PRAGMA busy_timeout=9000;"*) : ;;
    *) _fail "pragmas custom" "obtido: $_out"; return 1 ;;
  esac
}

scenario_state_db_exec_aplica_foreign_keys_on() {
  _db="$TMPDIR_TEST/state.db"
  "$SCHEMA_SCRIPT" create --db "$_db" >/dev/null
  # FK ON: inserir human_block com decision_id inexistente MUST falhar.
  capture _state_db_exec "$_db" "INSERT INTO execution (id,schema_version,target_project_path,target_project_description,status,started_at,current_stage,next_instruction) VALUES ('exec-1','1.0.0','/tmp/p','desc','em_andamento','2026-07-30T00:00:00Z','specify','x');"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "seed execution" "$_CAPTURED_STDERR"; return 1; }
  capture _state_db_exec "$_db" "INSERT INTO human_block (id,execution_id,decision_id,question,context_for_answer,status,triggered_at) VALUES ('block-001','exec-1','dec-999','pergunta com pelo menos 20 chars','contexto','aguardando','2026-07-30T00:00:00Z');"
  [ "$_CAPTURED_EXIT" != 0 ] || { _fail "fk enforcement" "deveria falhar por FOREIGN KEY (foreign_keys=ON)"; return 1; }
}

scenario_state_db_exec_persiste_payload_hostil_literal_e_tabela_sobrevive() {
  # Task 3.1.5: payload hostil + apostrofo simples persistido literalmente,
  # tabela decision continua existindo. Equivalente ao gate de integridade
  # deste FASE (state-validate.sh so existe para o backend JSON ate a FASE 5
  # de export existir) e via PRAGMA integrity_check, ja documentado como o
  # substituto sob backend SQLite (contracts/primitives.md §C7).
  _db="$TMPDIR_TEST/state.db"
  "$SCHEMA_SCRIPT" create --db "$_db" >/dev/null
  _state_db_exec "$_db" "INSERT INTO execution (id,schema_version,target_project_path,target_project_description,status,started_at,current_stage,next_instruction) VALUES ('exec-1','1.0.0','/tmp/p','desc','em_andamento','2026-07-30T00:00:00Z','specify','x');" >/dev/null

  _hostile="contexto com apostrofo $(sql_escape "'") e fragmento; DROP TABLE decision; -- e mais texto"
  _sql="INSERT INTO decision (id,execution_id,timestamp,agent,stage,context,options_considered,choice,rationale) VALUES ('dec-001','exec-1','2026-07-30T00:00:00Z','agente','etapa','$_hostile','[\"a\"]','a','justificativa valida com >= 20 chars');"
  capture _state_db_exec "$_db" "$_sql"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "insert hostil" "$_CAPTURED_STDERR"; return 1; }

  _n=$(sqlite3 "$_db" "SELECT count(*) FROM decision;")
  [ "$_n" = 1 ] || { _fail "decision sobreviveu" "esperado 1, obtido $_n"; return 1; }
  _tables=$(sqlite3 "$_db" "SELECT count(*) FROM sqlite_master WHERE type='table';")
  [ "$_tables" = 9 ] || { _fail "tabelas apos payload" "esperado 9, obtido $_tables"; return 1; }
  _stored=$(sqlite3 "$_db" "SELECT context FROM decision WHERE id='dec-001';")
  case "$_stored" in
    *"DROP TABLE decision"*) : ;;
    *) _fail "conteudo literal" "payload nao persistido literalmente: $_stored"; return 1 ;;
  esac
  _integrity=$(sqlite3 "$_db" "PRAGMA integrity_check;")
  [ "$_integrity" = "ok" ] || { _fail "integrity_check" "esperado ok, obtido $_integrity"; return 1; }
}

scenario_state_db_exec_with_retry_sucesso_sem_lock() {
  _db="$TMPDIR_TEST/state.db"
  "$SCHEMA_SCRIPT" create --db "$_db" >/dev/null
  capture _state_db_exec_with_retry "$_db" "INSERT INTO execution (id,schema_version,target_project_path,target_project_description,status,started_at,current_stage,next_instruction) VALUES ('exec-1','1.0.0','/tmp/p','desc','em_andamento','2026-07-30T00:00:00Z','specify','x');"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "retry sem lock" "$_CAPTURED_STDERR"; return 1; }
}

scenario_state_db_exec_with_retry_erro_nao_lock_falha_imediato() {
  _db="$TMPDIR_TEST/state.db"
  "$SCHEMA_SCRIPT" create --db "$_db" >/dev/null
  # SQL invalido (erro de sintaxe, nao lock): deve falhar sem 4 retries
  # (validado indiretamente pelo exit != 0; o teste de timing fica no
  # cenario de lock persistente abaixo).
  capture _state_db_exec_with_retry "$_db" "INSERT INTO tabela_inexistente (x) VALUES (1);"
  [ "$_CAPTURED_EXIT" != 0 ] || { _fail "erro nao-lock" "deveria falhar (tabela inexistente)"; return 1; }
}

scenario_state_db_exec_with_retry_lock_persistente_sai_nao_zero() {
  # C6: lock persistente apos as 4 tentativas MUST sair nao-zero — nunca
  # degradar silenciosamente. Simula lock mantendo uma transacao BEGIN
  # EXCLUSIVE aberta num processo sqlite3 em background (alimentado por
  # FIFO, mantido aberto ate o teste terminar) durante a chamada sob teste.
  _db="$TMPDIR_TEST/state.db"
  "$SCHEMA_SCRIPT" create --db "$_db" >/dev/null

  _fifo="$TMPDIR_TEST/lockctl"
  mkfifo "$_fifo" 2>/dev/null || { _fail "lock persistente" "mkfifo indisponivel neste ambiente"; return 1; }
  ( sqlite3 "$_db" <"$_fifo" >/dev/null 2>&1 ) &
  _holder_pid=$!
  exec 9>"$_fifo"
  printf 'PRAGMA busy_timeout=0;\nBEGIN EXCLUSIVE;\nSELECT 1;\n' >&9
  # da tempo do BEGIN EXCLUSIVE assentar antes de disparar a chamada sob teste
  sleep 0.3

  _start=$(date +%s)
  capture _state_db_exec_with_retry "$_db" "INSERT INTO execution (id,schema_version,target_project_path,target_project_description,status,started_at,current_stage,next_instruction) VALUES ('exec-1','1.0.0','/tmp/p','desc','em_andamento','2026-07-30T00:00:00Z','specify','x');" 500
  _rc=$_CAPTURED_EXIT
  _elapsed=$(( $(date +%s) - _start ))

  printf 'COMMIT;\n' >&9
  exec 9>&-
  wait "$_holder_pid" 2>/dev/null

  [ "$_rc" != 0 ] || { _fail "lock persistente" "deveria sair nao-zero apos esgotar retries; saiu 0"; return 1; }
  # 4 tentativas com backoff ~1+2+3+4s (com busy_timeout curto) leva alguns
  # segundos; so garantimos que NAO retornou instantaneo (retry de fato rodou).
  [ "$_elapsed" -ge 1 ] || { _fail "lock persistente" "retornou rapido demais (${_elapsed}s) — retry pode nao ter rodado"; return 1; }
}

scenario_state_db_secure_perms_aplica_600_no_db_e_sidecars() {
  _db="$TMPDIR_TEST/perms.db"
  "$SCHEMA_SCRIPT" create --db "$_db" >/dev/null
  chmod 644 "$_db"
  [ -f "$_db-wal" ] && chmod 644 "$_db-wal" 2>/dev/null
  _state_db_secure_perms "$_db"
  _perm_db=$(stat -f '%Lp' "$_db" 2>/dev/null || stat -c '%a' "$_db" 2>/dev/null)
  [ "$_perm_db" = "600" ] || { _fail "chmod db" "esperado 600, obtido $_perm_db"; return 1; }
  if [ -f "$_db-wal" ]; then
    _perm_wal=$(stat -f '%Lp' "$_db-wal" 2>/dev/null || stat -c '%a' "$_db-wal" 2>/dev/null)
    [ "$_perm_wal" = "600" ] || { _fail "chmod wal" "esperado 600, obtido $_perm_wal"; return 1; }
  fi
}

scenario_state_db_secure_perms_sidecar_ausente_nao_falha() {
  _db="$TMPDIR_TEST/no-sidecars.db"
  : >"$_db"
  capture _state_db_secure_perms "$_db"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "sidecar ausente" "nao deveria falhar: $_CAPTURED_STDERR"; return 1; }
}

run_all_scenarios
