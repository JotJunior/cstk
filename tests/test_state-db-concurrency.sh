#!/bin/sh
# test_state-db-concurrency.sh — testes de atomicidade e concorrencia do
# backend SQLite do state.db (feature state-db-foundation, FASE 3 task 3.7,
# SC-002, US1 AS-3).
#
# Ref: docs/specs/state-db-foundation/tasks.md FASE 3, task 3.7
#      docs/specs/state-db-foundation/spec.md SC-002
#      docs/specs/state-db-foundation/contracts/primitives.md §C4 (atomicidade
#      transacional), §C6 (concorrencia via WAL + retry/backoff)
#
# Nao mapeia 1:1 para um unico script — exercita a COMPOSICAO de varios
# scripts (state-decisions.sh, bloqueios.sh, state-ondas.sh) sobre o mesmo
# state.db para validar garantias transversais do backend SQLite:
#   3.7.1 duas mutacoes concorrentes DISTINTAS (tabelas diferentes) nao
#         perdem nenhuma atualizacao (0% de taxa de perda).
#   3.7.2 interrupcao simulada (kill -9 no meio de uma transacao aberta) nao
#         deixa o state.db com escrita parcial — PRAGMA integrity_check
#         continua 'ok' e a linha nao-commitada nao aparece (rollback
#         automatico do SQLite via WAL).
#   3.7.3 leitura concorrente durante escrita em andamento nao bloqueia e
#         nao ve dado nao-commitado (isolamento por snapshot, WAL).
# Registrado em run.sh::_is_internal_test (nao mapeia 1:1 para um script).

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

if ! command -v sqlite3 >/dev/null 2>&1; then
  printf '# test_state-db-concurrency.sh: sqlite3 ausente — pulando suite\n'
  exit 0
fi
if ! command -v jq >/dev/null 2>&1; then
  printf '# test_state-db-concurrency.sh: jq ausente — pulando suite\n'
  exit 0
fi

_R="$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts"
DEC="$_R/state-decisions.sh"
BLQ="$_R/bloqueios.sh"
ONDAS="$_R/state-ondas.sh"
SCHEMA_SCRIPT="$_R/state-db-schema.sh"

# shellcheck source=../plugins/cstk/skills/agente-00c-runtime/scripts/_state-db.sh
. "$_R/_state-db.sh"

# _seed_sqlite_backend DIR -> cria state.db com uma execution minima
# (id=exec-1), pronta para start/register/end.
_seed_sqlite_backend() {
  _ssb_dir=$1
  mkdir -p "$_ssb_dir"
  "$SCHEMA_SCRIPT" create --db "$_ssb_dir/state.db" >/dev/null 2>&1 \
    || { _fail "seed: schema create falhou" ""; return 1; }
  sqlite3 "$_ssb_dir/state.db" "
    PRAGMA foreign_keys=ON;
    INSERT INTO execution (id,schema_version,target_project_path,target_project_description,status,started_at,current_stage,next_instruction,external_urls_whitelist,circular_movement_history,initial_key_aspects,atomic_commit_enabled)
    VALUES ('exec-1','1.0.0','/tmp/p','desc de teste com detalhe','em_andamento','2026-07-30T00:00:00Z','execute-task','faca algo','[]','[]','[]',0);
  " || { _fail "seed: insert execution falhou" ""; return 1; }
}

# ============================================================
# 3.7.1 — mutacoes concorrentes DISTINTAS (tabelas diferentes)
# ============================================================
#
# Dispara N `state-decisions.sh register` (tabela decision) em paralelo com
# UMA chamada `state-ondas.sh end` (tabela wave) fechando a onda aberta.
# Sao mutacoes sobre TABELAS diferentes mas sobre o MESMO arquivo state.db
# — exercita o retry/backoff sob lock (C6) de _state_db_exec_with_retry /
# _sd_db_exec_capture sem depender de ordem de chegada. Invariante validada:
# nenhum register perde a escrita (todos os N ids aparecem, sem duplicata,
# sem erro) E o fechamento da onda tambem e aplicado — nenhuma das duas
# mutacoes "desaparece" por causa da outra.
scenario_mutacoes_concorrentes_decisao_e_fechamento_onda_sem_perda() {
  _sd="$TMPDIR_TEST/concorrencia-mista"
  _seed_sqlite_backend "$_sd" || return 1
  capture "$ONDAS" start --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "seed: start onda" "$_CAPTURED_STDERR"; return 1; }

  _n=8
  _i=1
  while [ "$_i" -le "$_n" ]; do
    ( "$DEC" register --state-dir "$_sd" \
        --agente "worker-$_i" --etapa "specify" \
        --contexto "contexto concorrente numero $_i com 20+ chars" \
        --opcoes '["a","b"]' --escolha "a" \
        --justificativa "justificativa concorrente numero $_i com 20+chars" \
        > "$TMPDIR_TEST/dec-out-$_i.txt" \
        2> "$TMPDIR_TEST/dec-err-$_i.txt" ) &
    _i=$((_i + 1))
  done
  ( "$ONDAS" end --state-dir "$_sd" --motivo-termino etapa_concluida_avancando \
      > "$TMPDIR_TEST/end-out.txt" 2> "$TMPDIR_TEST/end-err.txt" ; \
    echo "$?" > "$TMPDIR_TEST/end-exit.txt" ) &
  wait

  # Nenhum worker de decisao emitiu stderr (nenhuma falha nao-lock, nenhum
  # esgotamento de retry).
  _i=1
  while [ "$_i" -le "$_n" ]; do
    if [ -s "$TMPDIR_TEST/dec-err-$_i.txt" ]; then
      _fail "worker decisao $_i emitiu stderr" "$(cat "$TMPDIR_TEST/dec-err-$_i.txt")"
      return 1
    fi
    _i=$((_i + 1))
  done
  # state-ondas.sh end loga uma linha de CONFIRMACAO de sucesso em stderr
  # (_so_log "end: onda finalizada ..."), nao um erro — a assercao valida e
  # o exit code, nao a ausencia de stderr.
  _end_exit=$(cat "$TMPDIR_TEST/end-exit.txt" 2>/dev/null)
  [ "$_end_exit" = "0" ] || { _fail "end onda falhou" "exit=$_end_exit; $(cat "$TMPDIR_TEST/end-err.txt")"; return 1; }

  # As N decisoes existem, todas com id unico (0% de perda).
  _unique=$(cat "$TMPDIR_TEST"/dec-out-*.txt | sort -u | wc -l | tr -d ' ')
  [ "$_unique" = "$_n" ] || { _fail "ids de decisao unicos" "esperado $_n, obtido $_unique"; return 1; }
  capture "$DEC" count --state-dir "$_sd"
  assert_stdout_contains "$_n" || return 1

  # A onda tambem foi fechada — a outra mutacao nao "desapareceu".
  capture "$ONDAS" wave-status --state-dir "$_sd"
  assert_stdout_contains "closed" || return 1
}

# ============================================================
# 3.7.2 — interrupcao simulada (kill -9 no meio de uma transacao)
# ============================================================
#
# Abre uma transacao BEGIN IMMEDIATE + INSERT via uma sessao sqlite3
# alimentada por FIFO (controle preciso de timing), NUNCA emite COMMIT, e
# mata o processo sqlite3 com SIGKILL enquanto a transacao segue aberta.
# Verifica: (a) PRAGMA integrity_check continua 'ok' (sem corrupcao do
# arquivo); (b) a linha da transacao interrompida NAO aparece (rollback
# automatico via WAL — SQLite so aplica frames com marcador de commit
# valido); (c) o banco segue utilizavel por escritores subsequentes (o lock
# do processo morto foi liberado pelo kernel, nao ficou preso).
scenario_kill9_meio_transacao_nao_deixa_escrita_parcial() {
  if ! command -v mkfifo >/dev/null 2>&1; then
    printf '# scenario_kill9_meio_transacao_nao_deixa_escrita_parcial: mkfifo ausente — pulando\n'
    return 0
  fi
  _sd="$TMPDIR_TEST/kill9"
  _seed_sqlite_backend "$_sd" || return 1
  _db="$_sd/state.db"
  _fifo="$TMPDIR_TEST/kill9.fifo"
  mkfifo "$_fifo" || { _fail "kill9: mkfifo falhou" ""; return 1; }

  # Sessao sqlite3 alimentada pela FIFO, em background.
  sqlite3 "$_db" < "$_fifo" >"$TMPDIR_TEST/kill9-sqlite-out.txt" 2>&1 &
  _sqlite_pid=$!

  # Abre o fd 9 para escrita na FIFO (bloqueia ate o leitor conectar).
  exec 9>"$_fifo"
  printf 'PRAGMA busy_timeout=5000;\n' >&9
  printf 'BEGIN IMMEDIATE;\n' >&9
  printf "INSERT INTO decision (id,execution_id,timestamp,agent,stage,context,options_considered,choice,rationale) VALUES ('dec-kill9','exec-1','2026-07-30T00:00:00Z','x','clarify','contexto de teste com detalhe suficiente','[\"a\"]','a','justificativa de teste com detalhe suficiente');\n" >&9
  # Da tempo do sqlite3 processar BEGIN+INSERT antes de matar o processo —
  # a transacao fica aberta (sem COMMIT), segurando o RESERVED lock.
  sleep 0.5

  kill -9 "$_sqlite_pid" 2>/dev/null
  exec 9>&-
  wait "$_sqlite_pid" 2>/dev/null

  # (a) integridade do arquivo preservada.
  _integrity=$(_state_db_exec "$_db" "PRAGMA integrity_check;" 2>&1)
  [ "$_integrity" = "ok" ] || { _fail "kill9 integrity_check" "obtido '$_integrity'"; return 1; }

  # (b) rollback automatico — a linha nao-commitada nao existe.
  _cnt=$(_state_db_exec "$_db" "SELECT count(*) FROM decision WHERE id='dec-kill9';" 2>&1)
  [ "$_cnt" = "0" ] || { _fail "kill9 rollback" "esperado 0 linhas, obtido $_cnt"; return 1; }

  # (c) banco segue utilizavel — um register normal subsequente funciona
  # (lock do processo morto foi liberado, sem deadlock/esgotamento de retry).
  capture "$DEC" register --state-dir "$_sd" \
    --agente "pos-kill9" --etapa "specify" \
    --contexto "contexto pos kill9 com 20+ chars de sobra" \
    --opcoes '["a","b"]' --escolha "a" \
    --justificativa "justificativa pos kill9 com 20+ chars de sobra"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "kill9 pos-recuperacao register" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "dec-001" || return 1
}

# ============================================================
# 3.7.3 — leitura concorrente durante escrita em andamento (WAL, C6)
# ============================================================
#
# Mesma tecnica de FIFO: abre uma transacao de escrita (BEGIN IMMEDIATE +
# INSERT) e a deixa ABERTA (sem COMMIT nem ROLLBACK) enquanto uma leitura
# concorrente roda numa conexao SEPARADA. Sob WAL (dec-014), o leitor MUST
# (a) nao bloquear (retornar rapido, sem esperar o busy_timeout de 5s) e
# (b) ver o snapshot ANTERIOR a escrita nao-commitada (isolamento). Depois
# do COMMIT, uma nova leitura MUST refletir o dado novo.
scenario_leitura_concorrente_durante_escrita_sem_bloqueio() {
  if ! command -v mkfifo >/dev/null 2>&1; then
    printf '# scenario_leitura_concorrente_durante_escrita_sem_bloqueio: mkfifo ausente — pulando\n'
    return 0
  fi
  _sd="$TMPDIR_TEST/leitura-concorrente"
  _seed_sqlite_backend "$_sd" || return 1
  _db="$_sd/state.db"
  _fifo="$TMPDIR_TEST/leitura.fifo"
  mkfifo "$_fifo" || { _fail "leitura: mkfifo falhou" ""; return 1; }

  sqlite3 "$_db" < "$_fifo" >"$TMPDIR_TEST/leitura-sqlite-out.txt" 2>&1 &
  _sqlite_pid=$!

  exec 9>"$_fifo"
  printf 'PRAGMA busy_timeout=5000;\n' >&9
  printf 'BEGIN IMMEDIATE;\n' >&9
  printf "INSERT INTO decision (id,execution_id,timestamp,agent,stage,context,options_considered,choice,rationale) VALUES ('dec-leitura','exec-1','2026-07-30T00:00:00Z','x','clarify','contexto de teste com detalhe suficiente','[\"a\"]','a','justificativa de teste com detalhe suficiente');\n" >&9
  sleep 0.3

  # Leitura concorrente NAO deve bloquear — mede elapsed via epoch (evita
  # dependencia de `timeout`, GNU-only, per CLAUDE.md portabilidade).
  _t0=$(date +%s)
  capture "$DEC" count --state-dir "$_sd"
  _t1=$(date +%s)
  _elapsed=$((_t1 - _t0))

  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "leitura concorrente exit" "$_CAPTURED_STDERR"; return 1; }
  if [ "$_elapsed" -gt 2 ]; then
    _fail "leitura concorrente bloqueou" "elapsed=${_elapsed}s (esperado <2s sob WAL)"
    # Nao retorna ainda — segue limpando a transacao pendurada abaixo.
  fi
  # (b) snapshot anterior: a insercao ainda nao-commitada nao e vista.
  assert_stdout_contains "0" || { kill -9 "$_sqlite_pid" 2>/dev/null; exec 9>&-; return 1; }

  # Fecha a transacao normalmente desta vez (COMMIT) para validar o pos-write.
  printf 'COMMIT;\n' >&9
  sleep 0.2
  exec 9>&-
  wait "$_sqlite_pid" 2>/dev/null

  capture "$DEC" count --state-dir "$_sd"
  assert_stdout_contains "1" || return 1
}

run_all_scenarios
