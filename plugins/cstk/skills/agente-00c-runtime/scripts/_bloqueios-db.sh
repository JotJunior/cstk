#!/bin/sh
# _bloqueios-db.sh — implementacao do backend SQLite para bloqueios.sh
# (feature state-db-foundation, FASE 3 task 3.5).
#
# Ref: docs/specs/state-db-foundation/tasks.md FASE 3, task 3.5
#      docs/specs/state-db-foundation/contracts/primitives.md §C1 C2 C3 C4 C5 C6 C8
#      docs/specs/state-db-foundation/data-model.md §Entity BloqueioHumano (human_block)
#
# NAO e executavel diretamente. Sourced por bloqueios.sh, que ja fez
# `. _state-db.sh` e `. _state-rw-db.sh` antes — depende de sql_escape/
# strip_nul/_state_db_*/_sr_db_file/_sr_backend/_sr_exec_id/_sr_sql_quote
# (reuso dos primitivos ja testados das tasks 3.1/3.2, mesmo racional de C8
# documentado em _state-db.sh e replicado em _state-decisions-db.sh).
#
# Funcoes expostas (todas exigem STATE_DIR ja resolvido para backend sqlite
# pelo caller via _sr_backend, e state.db existente):
#   _bl_db_register DIR DEC_ID PERGUNTA CONTEXTO OPCOES_JSON SUBJECT_KEY
#                                              -> C4: grava o bloqueio E muda
#                                                 .execution.status para
#                                                 "aguardando_humano" na
#                                                 MESMA transacao BEGIN
#                                                 IMMEDIATE ... COMMIT. O
#                                                 numero sequencial de
#                                                 block-NNN e calculado por
#                                                 subquery DENTRO do proprio
#                                                 INSERT (mesmo padrao de
#                                                 _sd_db_register/dec-NNN —
#                                                 nunca por leitura separada
#                                                 antes do BEGIN IMMEDIATE).
#                                                 C3: decisao_id inexistente
#                                                 dispara a FK real
#                                                 (human_block.decision_id
#                                                 REFERENCES decision(id)) —
#                                                 o INSERT falha, a transacao
#                                                 inteira reverte (nenhuma
#                                                 mudanca de status), e o
#                                                 erro e mapeado para a mesma
#                                                 mensagem/exit 1 do path
#                                                 JSON. Imprime "block-NNN"
#                                                 em stdout (paridade C1).
#   _bl_db_respond DIR BLOCK_ID RESPOSTA      -> C4: UPDATE do human_block
#                                                 (status/human_answer/
#                                                 answered_at) e, se nao
#                                                 restar nenhum bloqueio
#                                                 aguardando, UPDATE de
#                                                 execution.status para
#                                                 "em_andamento" — mesma
#                                                 transacao.
#   _bl_db_list DIR [STATUS] [SUBJECT_KEY]    -> TSV id/decision_id/status/
#                                                 triggered_at/question
#                                                 (paridade com o formato do
#                                                 path JSON); SUBJECT_KEY
#                                                 filtra por igualdade exata
#                                                 quando nao-vazio
#   _bl_db_count DIR [PENDING]                -> imprime o total (inteiro);
#                                                 PENDING="1" filtra
#                                                 status='aguardando'
#   _bl_db_next_id DIR                        -> imprime o proximo
#                                                 "block-NNN" SEM registrar
#                                                 (leitura pura)
#   _bl_db_get DIR BLOCK_ID                   -> imprime o JSON do bloqueio
#                                                 (mesmos campos/ordem do
#                                                 path JSON)

# _bl_db_next_block_num_expr EXEC_ID_SQL_QUOTED -> imprime a subquery escalar
# que calcula o proximo numero sequencial de block-NNN para a execution
# dada. Mesma logica de _sd_db_next_num_expr (state-decisions), adaptada ao
# prefixo "block-" (6 chars, substr a partir da posicao 7, 1-indexed).
_bl_db_next_block_num_expr() {
  printf '(SELECT coalesce(max(cast(substr(id,7) as integer)),0)+1 FROM human_block WHERE execution_id=%s)' "$1"
}

# _bl_db_exec_capture DB SQL [BUSY_MS] -> mesmo backoff/retry sob lock (C6)
# de _sd_db_exec_capture (state-decisions), MAS com uma diferenca de
# invocacao deliberada: este helper e chamado DIRETAMENTE como comando
# simples — `if _bl_db_exec_capture DB SQL; then ...; fi` — NUNCA dentro de
# `$(...)`. Motivo: o caller (register/respond) precisa inspecionar o TEXTO
# do erro apos a falha para diferenciar FK (C3, mensagem amigavel dedicada)
# de qualquer outra causa; `$(...)` sempre forka uma subshell (POSIX), e
# qualquer atribuicao feita DENTRO dela — inclusive a uma variavel "global"
# como $_bl_db_last_err — e descartada quando a subshell termina e nunca
# chega ao shell chamador. Por isso o resultado e devolvido via duas
# globais (não pelo stdout de um `$(...)`): $_bl_db_last_out (sucesso) e
# $_bl_db_last_err (falha); o exit code sinaliza qual delas ler.
_bl_db_last_out=""
_bl_db_last_err=""
_bl_db_exec_capture() {
  _blc_db="$1"; _blc_sql="$2"; _blc_ms="${3:-5000}"
  _blc_try=1
  _bl_db_last_out=""
  _bl_db_last_err=""
  while [ "$_blc_try" -le 4 ]; do
    _blc_errfile=$(mktemp) || return 1
    # `if x=$(cmd); then ... else ...; fi`, NAO uma atribuicao nua seguida
    # de `rc=$?`: sob `set -e` (bloqueios.sh sempre roda com `set -eu`),
    # `x=$(cmd)` cujo `cmd` falha dispara saida imediata do shell inteiro —
    # a atribuicao nua nao esta numa lista if/while/&&/|| que a isente de
    # -e (POSIX 2.8.1). Mesmo bug corrigido em _sd_db_exec_capture
    # (_state-decisions-db.sh, task 3.4) — sem este guard, o retry/lock
    # (C6) e o mapeamento de erro FK (C3) abaixo nunca eram alcancados: o
    # processo morria silenciosamente na primeira falha nao-zero de
    # _state_db_exec.
    if _blc_out=$(_state_db_exec "$_blc_db" "$_blc_sql" "$_blc_ms" 2>"$_blc_errfile"); then
      _blc_rc=0
    else
      _blc_rc=$?
    fi
    _blc_err=$(cat -- "$_blc_errfile" 2>/dev/null)
    rm -f -- "$_blc_errfile"
    if [ "$_blc_rc" -eq 0 ]; then
      _bl_db_last_out="$_blc_out"
      return 0
    fi
    case "$_blc_err" in
      *"database is locked"*|*"database is busy"*|*"locking protocol"*)
        _state_db_backoff_sleep "$_blc_try"
        _blc_try=$((_blc_try + 1))
        ;;
      *)
        _bl_db_last_err="$_blc_err"
        return 1
        ;;
    esac
  done
  _bl_db_last_err="$_blc_err"
  return 1
}

# ---------- register ----------

_bl_db_register() {
  _bdr_sdir="$1"; _bdr_dec="$2"; _bdr_perg="$3"; _bdr_ctx="$4"; _bdr_opcoes="$5"
  _bdr_subj="${6:-}"

  _bdr_db=$(_sr_db_file "$_bdr_sdir")
  [ -f "$_bdr_db" ] || _bl_die "register: state.db ausente em $_bdr_sdir" 1

  # feature structural-decision-human-gate (task 2.4.3, INV-E3): garante a
  # coluna subject_key [NOVO] antes de qualquer INSERT — paridade com
  # _sd_db_register (state-decisions.sh, task 1.2.4).
  "$_BL_DIR/state-db-schema.sh" ensure --db "$_bdr_db" \
    || _bl_die "register: falha ao garantir schema aditivo (state-db-schema.sh ensure) em $_bdr_db" 1

  _bdr_exec_id=$(_sr_exec_id "$_bdr_db")
  [ -n "$_bdr_exec_id" ] || _bl_die "register: execution ausente em $_bdr_db" 1

  _bdr_now=$(_bl_iso_now)

  _bdr_opts_sql="NULL"
  if [ "$_bdr_opcoes" != "null" ]; then
    _bdr_opts_c=$(printf '%s' "$_bdr_opcoes" | jq -c '.' 2>/dev/null) || _bdr_opts_c="$_bdr_opcoes"
    _bdr_opts_sql=$(_sr_sql_quote "$_bdr_opts_c")
  fi

  _bdr_subj_sql="NULL"
  [ -n "$_bdr_subj" ] && _bdr_subj_sql=$(_sr_sql_quote "$_bdr_subj")

  _bdr_exec_id_sql=$(_sr_sql_quote "$_bdr_exec_id")
  _bdr_dec_sql=$(_sr_sql_quote "$_bdr_dec")
  _bdr_id_expr=$(_bl_db_next_block_num_expr "$_bdr_exec_id_sql")

  # C4: INSERT do human_block + UPDATE de execution.status, numa unica
  # transacao. O id novo e lido de volta via last_insert_rowid() ANTES do
  # COMMIT (isolado por conexao, nunca enxerga commit de outro escritor) —
  # mesmo padrao de _sd_db_register para evitar colisao sob concorrencia.
  _bdr_sql="BEGIN IMMEDIATE; INSERT INTO human_block (id,execution_id,decision_id,question,context_for_answer,recommended_options,status,human_answer,triggered_at,answered_at,subject_key) VALUES ('block-' || printf('%03d',$_bdr_id_expr),$_bdr_exec_id_sql,$_bdr_dec_sql,$(_sr_sql_quote "$_bdr_perg"),$(_sr_sql_quote "$_bdr_ctx"),$_bdr_opts_sql,'aguardando',NULL,$(_sr_sql_quote "$_bdr_now"),NULL,$_bdr_subj_sql); UPDATE execution SET status='aguardando_humano' WHERE id=$_bdr_exec_id_sql; SELECT id FROM human_block WHERE rowid=last_insert_rowid(); COMMIT;"

  # Chamada DIRETA (nunca dentro de $(...)) — ver nota de cabecalho de
  # _bl_db_exec_capture: e so assim que $_bl_db_last_err sobrevive a
  # chamada para o `case` abaixo poder diferenciar FK (C3) de erro generico.
  if _bl_db_exec_capture "$_bdr_db" "$_bdr_sql"; then
    _bdr_id="$_bl_db_last_out"
  else
    case "$_bl_db_last_err" in
      *"FOREIGN KEY constraint failed"*)
        _bl_die "register: decisao_id nao existe: $_bdr_dec (use state-decisions.sh register antes)" 1
        ;;
      *)
        [ -n "$_bl_db_last_err" ] && printf '%s\n' "$_bl_db_last_err" >&2
        _bl_die "register: INSERT falhou (backend sqlite) — ver stderr acima" 1
        ;;
    esac
  fi
  [ -n "$_bdr_id" ] || _bl_die "register: INSERT nao retornou id (backend sqlite)" 1
  printf '%s\n' "$_bdr_id"
}

# ---------- respond ----------

_bl_db_respond() {
  _bdrp_sdir="$1"; _bdrp_bid="$2"; _bdrp_resp="$3"

  _bdrp_db=$(_sr_db_file "$_bdrp_sdir")
  [ -f "$_bdrp_db" ] || _bl_die "respond: state.db ausente em $_bdrp_sdir" 1
  _bdrp_exec_id=$(_sr_exec_id "$_bdrp_db")
  [ -n "$_bdrp_exec_id" ] || _bl_die "respond: execution ausente em $_bdrp_db" 1
  _bdrp_exec_id_sql=$(_sr_sql_quote "$_bdrp_exec_id")

  _bdrp_status=$(_state_db_exec "$_bdrp_db" \
    "SELECT status FROM human_block WHERE id=$(_sr_sql_quote "$_bdrp_bid") AND execution_id=$_bdrp_exec_id_sql;")
  case "$_bdrp_status" in
    aguardando) ;;
    "")
      diag_emit error bloqueio-not-found "respond: bloqueio nao encontrado: $_bdrp_bid" \
        "confira o id com bloqueios.sh list --state-dir $_bdrp_sdir (block-id invalido ou ja respondido)" || :
      _bl_die "respond: bloqueio nao encontrado: $_bdrp_bid" 1
      ;;
    *) _bl_die "respond: bloqueio $_bdrp_bid nao esta em status aguardando (status=$_bdrp_status)" 1 ;;
  esac

  _bdrp_now=$(_bl_iso_now)

  # C4: fecha o bloqueio e, se nao restar nenhum outro aguardando, promove
  # execution.status de volta a "em_andamento" — numa unica transacao.
  _bdrp_sql="BEGIN IMMEDIATE; UPDATE human_block SET status='respondido', human_answer=$(_sr_sql_quote "$_bdrp_resp"), answered_at=$(_sr_sql_quote "$_bdrp_now") WHERE id=$(_sr_sql_quote "$_bdrp_bid") AND execution_id=$_bdrp_exec_id_sql; UPDATE execution SET status='em_andamento' WHERE id=$_bdrp_exec_id_sql AND NOT EXISTS (SELECT 1 FROM human_block WHERE execution_id=$_bdrp_exec_id_sql AND status='aguardando'); COMMIT;"

  if ! _bl_db_exec_capture "$_bdrp_db" "$_bdrp_sql"; then
    [ -n "$_bl_db_last_err" ] && printf '%s\n' "$_bl_db_last_err" >&2
    _bl_die "respond: UPDATE falhou (backend sqlite) — ver stderr acima" 1
  fi
}

# ---------- list ----------

_bl_db_list() {
  _bdl_sdir="$1"; _bdl_status="$2"; _bdl_subj="${3:-}"
  _bdl_db=$(_sr_db_file "$_bdl_sdir")
  [ -f "$_bdl_db" ] || _bl_die "list: state.db ausente em $_bdl_sdir" 1
  _bdl_exec_id=$(_sr_exec_id "$_bdl_db")
  [ -n "$_bdl_exec_id" ] || _bl_die "list: execution ausente em $_bdl_db" 1

  _bdl_where="execution_id=$(_sr_sql_quote "$_bdl_exec_id")"
  [ -n "$_bdl_status" ] && _bdl_where="$_bdl_where AND status=$(_sr_sql_quote "$_bdl_status")"

  # feature structural-decision-human-gate (task 2.4.3): filtro por
  # subject_key SEM invocar `ensure` no caminho de leitura (INV-E3 — mesmo
  # racional de _sr_db_read/task 2.3.1). Banco pre-feature (coluna ausente)
  # nao pode ter nenhum bloqueio com subject_key setado — equivalente a
  # "nenhuma linha casa", resolvido com uma condicao sempre-falsa em vez de
  # referenciar a coluna (que faria o SELECT falhar com "no such column").
  if [ -n "$_bdl_subj" ]; then
    _bdl_has_col=$(_state_db_exec "$_bdl_db" \
      "SELECT count(*) FROM pragma_table_info('human_block') WHERE name='subject_key';")
    if [ "$_bdl_has_col" = "1" ]; then
      _bdl_where="$_bdl_where AND subject_key=$(_sr_sql_quote "$_bdl_subj")"
    else
      _bdl_where="$_bdl_where AND 1=0"
    fi
  fi

  _state_db_exec "$_bdl_db" \
    "SELECT id || char(9) || decision_id || char(9) || status || char(9) || triggered_at || char(9) || question FROM human_block WHERE $_bdl_where ORDER BY rowid;"
}

# ---------- count ----------

_bl_db_count() {
  _bdc_sdir="$1"; _bdc_pending="$2"
  _bdc_db=$(_sr_db_file "$_bdc_sdir")
  [ -f "$_bdc_db" ] || _bl_die "count: state.db ausente em $_bdc_sdir" 1
  _bdc_exec_id=$(_sr_exec_id "$_bdc_db")
  [ -n "$_bdc_exec_id" ] || _bl_die "count: execution ausente em $_bdc_db" 1
  if [ "$_bdc_pending" = "1" ]; then
    _state_db_exec "$_bdc_db" \
      "SELECT count(*) FROM human_block WHERE execution_id=$(_sr_sql_quote "$_bdc_exec_id") AND status='aguardando';"
  else
    _state_db_exec "$_bdc_db" \
      "SELECT count(*) FROM human_block WHERE execution_id=$(_sr_sql_quote "$_bdc_exec_id");"
  fi
}

# ---------- next-id ----------

_bl_db_next_id() {
  _bdn_sdir="$1"
  _bdn_db=$(_sr_db_file "$_bdn_sdir")
  [ -f "$_bdn_db" ] || _bl_die "next-id: state.db ausente em $_bdn_sdir" 1
  _bdn_exec_id=$(_sr_exec_id "$_bdn_db")
  [ -n "$_bdn_exec_id" ] || _bl_die "next-id: execution ausente em $_bdn_db" 1
  _bdn_expr=$(_bl_db_next_block_num_expr "$(_sr_sql_quote "$_bdn_exec_id")")
  _state_db_exec "$_bdn_db" "SELECT 'block-' || printf('%03d',$_bdn_expr);"
}

# ---------- get ----------

_bl_db_get() {
  _bdg_sdir="$1"; _bdg_bid="$2"
  _bdg_db=$(_sr_db_file "$_bdg_sdir")
  [ -f "$_bdg_db" ] || _bl_die "get: state.db ausente em $_bdg_sdir" 1
  _bdg_exec_id=$(_sr_exec_id "$_bdg_db")
  [ -n "$_bdg_exec_id" ] || _bl_die "get: execution ausente em $_bdg_db" 1

  _bdg_out=$(_state_db_exec "$_bdg_db" "SELECT json_object('id',id,'decision_id',decision_id,'question',question,'context_for_answer',context_for_answer,'recommended_options',json(coalesce(recommended_options,'null')),'status',status,'human_answer',human_answer,'triggered_at',triggered_at,'answered_at',answered_at) FROM human_block WHERE id=$(_sr_sql_quote "$_bdg_bid") AND execution_id=$(_sr_sql_quote "$_bdg_exec_id");")
  [ -n "$_bdg_out" ] || _bl_die "get: bloqueio nao encontrado: $_bdg_bid" 1
  printf '%s\n' "$_bdg_out"
}
