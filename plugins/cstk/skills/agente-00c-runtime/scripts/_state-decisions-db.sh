#!/bin/sh
# _state-decisions-db.sh — implementacao do backend SQLite para
# state-decisions.sh (feature state-db-foundation, FASE 3 task 3.4).
#
# Ref: docs/specs/state-db-foundation/tasks.md FASE 3, task 3.4
#      docs/specs/state-db-foundation/contracts/primitives.md §C1 C2 C4 C5 C6 C8
#      docs/specs/state-db-foundation/data-model.md §Entity Decisao
#      (wave_id: NULL representa "init" — nao ha wave ainda)
#
# NAO e executavel diretamente. Sourced por state-decisions.sh, que ja fez
# `. _state-db.sh` e `. _state-rw-db.sh` antes — depende de sql_escape/
# strip_nul/_state_db_*/_sr_db_file/_sr_backend/_sr_exec_id/_sr_sql_quote
# (reuso dos primitivos ja testados das tasks 3.1/3.2, nao reimplementacao —
# mesmo racional de C8 documentado em _state-db.sh).
#
# Funcoes expostas (todas exigem STATE_DIR ja resolvido para backend sqlite
# pelo caller via _sr_backend, e state.db existente):
#   _sd_db_register DIR AGENT STAGE CTX OPTS_JSON CHOICE RATIONALE \
#                    SCORE EVIDENCE REFS_JSON ORIG_ARTIFACT
#                                              -> INSERT do dec-NNN novo numa
#                                                 unica transacao (C4), com o
#                                                 numero calculado por
#                                                 subquery DENTRO do proprio
#                                                 INSERT (nunca por leitura
#                                                 separada antes do BEGIN
#                                                 IMMEDIATE — e exatamente
#                                                 essa leitura separada que
#                                                 colidiria sob concorrencia,
#                                                 task 3.4.3). Imprime
#                                                 "dec-NNN" em stdout
#                                                 (paridade C1).
#   _sd_db_count DIR [AGENT]                  -> imprime o total (inteiro)
#   _sd_db_next_id DIR                        -> imprime o proximo "dec-NNN"
#                                                 SEM registrar (leitura pura)
#   _sd_db_list DIR [AGENT] [STAGE]           -> TSV id/wave_id/agent/stage/
#                                                 choice (paridade com o
#                                                 formato do path JSON;
#                                                 wave_id NULL -> "init" na
#                                                 saida, mesma convencao do
#                                                 documento JSON)
#
# GAP CONHECIDO E DOCUMENTADO (mesmo espirito da nota de _state-rw-db.sh):
# o export completo (`state-rw.sh read`, FASE 3.2) reconstroi
# `.decisions[].wave_id` a partir da coluna SQL crua — quando NULL (nenhuma
# onda existia no momento do register), o export emite JSON `null`, nao a
# string literal "init" que o path JSON grava. Aqui em `list` a saida
# textual É normalizada para "init" (parity de leitura pontual); a
# normalizacao equivalente no export completo fica fora do escopo desta task
# (pertence a FASE 3.2, ja implementada e testada) — registrado como nota
# para eventual sugestao futura, nao um bug silencioso: nenhum dado se
# perde, o campo apenas aparece como null em vez de "init" nesse caminho
# especifico.

# _sd_db_next_num_expr EXEC_ID_SQL_QUOTED -> imprime a subquery escalar que
# calcula o proximo numero sequencial de dec-NNN para a execution dada.
# Mesma logica do lado JSON (_sd_next_dec_id): extrai os 3 digitos apos o
# prefixo "dec-" (posicao 5 em diante, 1-indexed), converte para inteiro,
# soma 1 sobre o maximo (0 se nao houver nenhuma decisao ainda).
_sd_db_next_num_expr() {
  printf '(SELECT coalesce(max(cast(substr(id,5) as integer)),0)+1 FROM decision WHERE execution_id=%s)' "$1"
}

# _sd_db_exec_capture DB SQL [BUSY_MS] -> como _state_db_exec_with_retry
# (mesmo backoff/retry sob lock, mesmo contrato de falha C6: lock
# persistente apos 4 tentativas MUST sair nao-zero), mas PRESERVA o stdout
# da tentativa vencedora.
#
# Por que nao reusar _state_db_exec_with_retry diretamente: aquela funcao
# descarta stdout por desenho (`2>&1 >/dev/null`) — nenhum caller de FASE
# 3.2/3.3 precisava do stdout da transacao (sempre fazem uma leitura
# SEPARADA depois do COMMIT para reportar). `register` nao pode seguir esse
# padrao: o id novo PRECISA ser lido de DENTRO da mesma transacao (via
# `last_insert_rowid()`, antes do COMMIT) para nao colidir sob concorrencia
# — uma leitura separada apos o COMMIT poderia enxergar o dec-NNN de OUTRO
# escritor que tenha comitado no meio (task 3.4.3). Duplicar o loop de
# retry aqui (em vez de generalizar o helper compartilhado) mantem
# _state-db.sh estavel para os callers ja testados de 3.1/3.2/3.3.
_sd_db_exec_capture() {
  _sdc_db="$1"; _sdc_sql="$2"; _sdc_ms="${3:-5000}"
  _sdc_try=1
  while [ "$_sdc_try" -le 4 ]; do
    _sdc_errfile=$(mktemp) || return 1
    # `if _sdc_out=$(...); then ... else ...; fi` (NAO uma atribuicao nua
    # seguida de `_sdc_rc=$?`): sob `set -e` (o caller sempre roda com
    # `set -eu`), uma atribuicao `x=$(cmd)` cujo `cmd` falha DISPARA saida
    # imediata do shell inteiro — a atribuicao nao esta numa lista
    # if/while/&&/|| que a isente de -e (POSIX 2.8.1). Bug latente achado
    # na task 3.5 (bloqueios.sh dual-backend), corrigido aqui por
    # compartilhar exatamente o mesmo padrao: o `case` de retry/lock (C6)
    # abaixo nunca era alcancado sob erro nao-lock nem sob lock persistente
    # — o processo morria silenciosamente na primeira falha de
    # `_state_db_exec`, pulando o backoff/retry inteiro.
    if _sdc_out=$(_state_db_exec "$_sdc_db" "$_sdc_sql" "$_sdc_ms" 2>"$_sdc_errfile"); then
      _sdc_rc=0
    else
      _sdc_rc=$?
    fi
    _sdc_err=$(cat -- "$_sdc_errfile" 2>/dev/null)
    rm -f -- "$_sdc_errfile"
    if [ "$_sdc_rc" -eq 0 ]; then
      printf '%s\n' "$_sdc_out"
      return 0
    fi
    case "$_sdc_err" in
      *"database is locked"*|*"database is busy"*|*"locking protocol"*)
        _state_db_backoff_sleep "$_sdc_try"
        _sdc_try=$((_sdc_try + 1))
        ;;
      *)
        [ -n "$_sdc_err" ] && printf '%s\n' "$_sdc_err" >&2
        return 1
        ;;
    esac
  done
  [ -n "${_sdc_err:-}" ] && printf '%s\n' "$_sdc_err" >&2
  return 1
}

# _sd_db_current_wave_id DB EXEC_ID -> id da ultima onda por seq (NAO
# necessariamente aberta), ou "" se nenhuma onda existe ainda. Paridade
# exata com _sd_current_onda_id do path JSON (.waves[-1].id), que tambem
# nao filtra por onda aberta/fechada — so pelo default "init" quando o
# array esta vazio.
_sd_db_current_wave_id() {
  _sdw_db="$1"; _sdw_exec_id="$2"
  _state_db_exec "$_sdw_db" \
    "SELECT id FROM wave WHERE execution_id=$(_sr_sql_quote "$_sdw_exec_id") ORDER BY seq DESC LIMIT 1;"
}

# ---------- register ----------

_sd_db_register() {
  _sdb_sdir="$1"; _sdb_agent="$2"; _sdb_stage="$3"; _sdb_ctx="$4"
  _sdb_opts="$5"; _sdb_choice="$6"; _sdb_rationale="$7"; _sdb_score="$8"
  _sdb_evi="$9"
  shift 9
  _sdb_refs="$1"; _sdb_orig="$2"

  _sdb_db=$(_sr_db_file "$_sdb_sdir")
  [ -f "$_sdb_db" ] || _sd_die "register: state.db ausente em $_sdb_sdir" 1
  _sdb_exec_id=$(_sr_exec_id "$_sdb_db")
  [ -n "$_sdb_exec_id" ] || _sd_die "register: execution ausente em $_sdb_db" 1

  _sdb_wid=$(_sd_db_current_wave_id "$_sdb_db" "$_sdb_exec_id")
  _sdb_wid_sql="NULL"
  [ -n "$_sdb_wid" ] && _sdb_wid_sql=$(_sr_sql_quote "$_sdb_wid")

  _sdb_now=$(_sd_iso_now)

  _sdb_score_sql="NULL"
  [ "$_sdb_score" != "null" ] && _sdb_score_sql="$_sdb_score"

  _sdb_evi_sql="NULL"
  [ -n "$_sdb_evi" ] && _sdb_evi_sql=$(_sr_sql_quote "$_sdb_evi")

  _sdb_orig_sql="NULL"
  [ -n "$_sdb_orig" ] && [ "$_sdb_orig" != "null" ] && _sdb_orig_sql=$(_sr_sql_quote "$_sdb_orig")

  # options_considered/references ja foram validados como JSON array pelo
  # caller (state-decisions.sh, antes do dispatch de backend) — compactamos
  # aqui so por higiene de armazenamento (paridade com _sr_db_upsert_decision,
  # que usa `jq -c` no mesmo par de campos).
  _sdb_opts_c=$(printf '%s' "$_sdb_opts" | jq -c '.' 2>/dev/null) || _sdb_opts_c="$_sdb_opts"
  _sdb_refs_c=$(printf '%s' "$_sdb_refs" | jq -c '.' 2>/dev/null) || _sdb_refs_c="$_sdb_refs"

  _sdb_exec_id_sql=$(_sr_sql_quote "$_sdb_exec_id")
  _sdb_id_expr=$(_sd_db_next_num_expr "$_sdb_exec_id_sql")

  # C4: id novo (via subquery), insercao e leitura do proprio id inserido
  # (last_insert_rowid(), isolado por conexao — nunca enxerga commit de
  # outro escritor) na MESMA transacao BEGIN IMMEDIATE ... COMMIT. Isso e o
  # que garante nao colidir sob concorrencia (task 3.4.3): um segundo
  # escritor so consegue seu proprio BEGIN IMMEDIATE apos o primeiro
  # COMMITar, e nesse momento seu MAX(...) ja enxerga a linha do primeiro.
  _sdb_sql="BEGIN IMMEDIATE; INSERT INTO decision (id,execution_id,wave_id,timestamp,agent,stage,context,options_considered,choice,rationale,justification_score,evidence,\"references\",originating_artifact) VALUES ('dec-' || printf('%03d',$_sdb_id_expr),$_sdb_exec_id_sql,$_sdb_wid_sql,$(_sr_sql_quote "$_sdb_now"),$(_sr_sql_quote "$_sdb_agent"),$(_sr_sql_quote "$_sdb_stage"),$(_sr_sql_quote "$_sdb_ctx"),$(_sr_sql_quote "$_sdb_opts_c"),$(_sr_sql_quote "$_sdb_choice"),$(_sr_sql_quote "$_sdb_rationale"),$_sdb_score_sql,$_sdb_evi_sql,$(_sr_sql_quote "$_sdb_refs_c"),$_sdb_orig_sql); SELECT id FROM decision WHERE rowid=last_insert_rowid(); COMMIT;"

  _sdb_id=$(_sd_db_exec_capture "$_sdb_db" "$_sdb_sql") \
    || _sd_die "register: INSERT falhou (backend sqlite) — ver stderr acima" 1
  [ -n "$_sdb_id" ] || _sd_die "register: INSERT nao retornou id (backend sqlite)" 1
  printf '%s\n' "$_sdb_id"
}

# ---------- count ----------

_sd_db_count() {
  _sdc_sdir="$1"; _sdc_agent="$2"
  _sdc_db=$(_sr_db_file "$_sdc_sdir")
  [ -f "$_sdc_db" ] || _sd_die "count: state.db ausente em $_sdc_sdir" 1
  _sdc_exec_id=$(_sr_exec_id "$_sdc_db")
  [ -n "$_sdc_exec_id" ] || _sd_die "count: execution ausente em $_sdc_db" 1
  if [ -n "$_sdc_agent" ]; then
    _state_db_exec "$_sdc_db" \
      "SELECT count(*) FROM decision WHERE execution_id=$(_sr_sql_quote "$_sdc_exec_id") AND agent=$(_sr_sql_quote "$_sdc_agent");"
  else
    _state_db_exec "$_sdc_db" \
      "SELECT count(*) FROM decision WHERE execution_id=$(_sr_sql_quote "$_sdc_exec_id");"
  fi
}

# ---------- next-id ----------

_sd_db_next_id() {
  _sdn_sdir="$1"
  _sdn_db=$(_sr_db_file "$_sdn_sdir")
  [ -f "$_sdn_db" ] || _sd_die "next-id: state.db ausente em $_sdn_sdir" 1
  _sdn_exec_id=$(_sr_exec_id "$_sdn_db")
  [ -n "$_sdn_exec_id" ] || _sd_die "next-id: execution ausente em $_sdn_db" 1
  _sdn_expr=$(_sd_db_next_num_expr "$(_sr_sql_quote "$_sdn_exec_id")")
  _state_db_exec "$_sdn_db" "SELECT 'dec-' || printf('%03d',$_sdn_expr);"
}

# ---------- list ----------

_sd_db_list() {
  _sdl_sdir="$1"; _sdl_agent="$2"; _sdl_stage="$3"
  _sdl_db=$(_sr_db_file "$_sdl_sdir")
  [ -f "$_sdl_db" ] || _sd_die "list: state.db ausente em $_sdl_sdir" 1
  _sdl_exec_id=$(_sr_exec_id "$_sdl_db")
  [ -n "$_sdl_exec_id" ] || _sd_die "list: execution ausente em $_sdl_db" 1

  _sdl_where="execution_id=$(_sr_sql_quote "$_sdl_exec_id")"
  [ -n "$_sdl_agent" ] && _sdl_where="$_sdl_where AND agent=$(_sr_sql_quote "$_sdl_agent")"
  [ -n "$_sdl_stage" ] && _sdl_where="$_sdl_where AND stage=$(_sr_sql_quote "$_sdl_stage")"

  # wave_id NULL -> "init" na saida textual (mesma convencao de exibicao do
  # path JSON; ver nota de GAP CONHECIDO no cabecalho deste arquivo).
  _state_db_exec "$_sdl_db" \
    "SELECT id || char(9) || coalesce(wave_id,'init') || char(9) || agent || char(9) || stage || char(9) || choice FROM decision WHERE $_sdl_where ORDER BY rowid;"
}
