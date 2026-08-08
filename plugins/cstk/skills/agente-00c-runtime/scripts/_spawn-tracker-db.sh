#!/bin/sh
# _spawn-tracker-db.sh — implementacao do backend SQLite para
# spawn-tracker.sh (feature state-db-foundation, FASE 3 task 3.6).
#
# Ref: docs/specs/state-db-foundation/tasks.md FASE 3, task 3.6
#      docs/specs/state-db-foundation/contracts/primitives.md §C1 C2 C3 C5 C6
#      docs/specs/state-db-foundation/data-model.md (execution.subagent_depth,
#      execution.max_recursion, CHECK 3 — teto de profundidade)
#
# NAO e executavel diretamente. Sourced por spawn-tracker.sh, que ja fez
# `. _state-db.sh` e `. _state-rw-db.sh` antes — depende de sql_escape/
# strip_nul/_state_db_*/_sr_db_file/_sr_backend/_sr_exec_id/_sr_sql_quote
# (reuso dos primitivos ja testados de state-rw.sh, mesmo racional de C8
# documentado em _state-db.sh e replicado em _bloqueios-db.sh/
# _state-decisions-db.sh).
#
# Escopo desta task (C1/C3): apenas a coluna execution.subagent_depth (teto
# execution.max_recursion, espelho de _ST_MAX=3). O campo
# accumulated_metrics.max_depth_reached/subagents_spawned permanece o
# placeholder ja documentado no cabecalho de _sr_db_read (task 3.2 —
# 'max_depth_reached' = subagent_depth corrente, 'subagents_spawned' = 0):
# gap conhecido entre export.md e data-model.md (schema fechado em 9
# entidades sem coluna dedicada para contador cumulativo de spawns), fora
# do escopo desta task — spawn-tracker.sh nao inventa uma coluna nova aqui.
#
# Funcoes expostas (todas exigem STATE_DIR ja resolvido para backend sqlite
# pelo caller via _sr_backend, e state.db existente):
#   _st_db_get_current STATE_DIR  -> imprime subagent_depth corrente (leitura pura)
#   _st_db_get_max STATE_DIR      -> imprime max_recursion (leitura pura)
#   _st_db_check STATE_DIR        -> exit 0 (pode spawnar +1) | exit 3 (teto,
#                                     paridade C1/C3 com spawn-tracker.sh check)
#   _st_db_enter STATE_DIR        -> valida ANTES de escrever (mesmo padrao do
#                                     path JSON — nunca depende do CHECK do
#                                     schema para reportar o teto); exit 3 SEM
#                                     gravar se excederia MAX; senao UPDATE
#                                     (via _state_db_exec_with_retry, C6) +
#                                     stdout com a nova profundidade
#   _st_db_leave STATE_DIR        -> idempotente em depth<=1 (nao grava,
#                                     stdout=depth atual); senao UPDATE +
#                                     stdout com a nova profundidade
#   _st_db_current STATE_DIR      -> imprime subagent_depth corrente

_st_db_get_current() {
  _stdbc_db=$(_sr_db_file "$1")
  _state_db_exec "$_stdbc_db" "SELECT subagent_depth FROM execution LIMIT 1;"
}

_st_db_get_max() {
  _stdbm_db=$(_sr_db_file "$1")
  _state_db_exec "$_stdbm_db" "SELECT max_recursion FROM execution LIMIT 1;"
}

_st_db_check() {
  _stdck_sdir="$1"
  _stdck_db=$(_sr_db_file "$_stdck_sdir")
  [ -f "$_stdck_db" ] || _st_die "check: state.db ausente em $_stdck_sdir" 1
  _stdck_curr=$(_st_db_get_current "$_stdck_sdir")
  _stdck_max=$(_st_db_get_max "$_stdck_sdir")
  [ -n "$_stdck_curr" ] || _st_die "check: execution ausente em $_stdck_db" 1
  _stdck_next=$((_stdck_curr + 1))
  if [ "$_stdck_next" -gt "$_stdck_max" ]; then
    printf '%s: profundidade no limite (corrente=%s, MAX=%s) — spawn negado\n' \
      "$_ST_NAME" "$_stdck_curr" "$_stdck_max" >&2
    exit 3
  fi
  exit 0
}

_st_db_enter() {
  _stden_sdir="$1"
  _stden_db=$(_sr_db_file "$_stden_sdir")
  [ -f "$_stden_db" ] || _st_die "enter: state.db ausente em $_stden_sdir" 1
  _stden_exec_id=$(_sr_exec_id "$_stden_db")
  [ -n "$_stden_exec_id" ] || _st_die "enter: execution ausente em $_stden_db" 1

  _stden_curr=$(_st_db_get_current "$_stden_sdir")
  _stden_max=$(_st_db_get_max "$_stden_sdir")
  _stden_next=$((_stden_curr + 1))
  # Validacao ANTES de qualquer escrita (mesmo padrao do path JSON) —
  # deliberadamente NAO delegado ao CHECK do schema: precisamos da mensagem
  # + exit 3 SEM depender do texto de erro do SQLite (paridade C1 exata com
  # spawn-tracker.sh check/enter hoje).
  if [ "$_stden_next" -gt "$_stden_max" ]; then
    printf '%s: enter negado — profundidade %s -> %s excederia MAX %s\n' \
      "$_ST_NAME" "$_stden_curr" "$_stden_next" "$_stden_max" >&2
    exit 3
  fi

  _stden_exec_id_sql=$(_sr_sql_quote "$_stden_exec_id")
  _stden_sql="UPDATE execution SET subagent_depth=$_stden_next WHERE id=$_stden_exec_id_sql;"
  _state_db_exec_with_retry "$_stden_db" "$_stden_sql" \
    || _st_die "enter: UPDATE falhou (backend sqlite) — ver stderr acima" 1

  printf '%s\n' "$_stden_next"
}

_st_db_leave() {
  _stdlv_sdir="$1"
  _stdlv_db=$(_sr_db_file "$_stdlv_sdir")
  [ -f "$_stdlv_db" ] || _st_die "leave: state.db ausente em $_stdlv_sdir" 1
  _stdlv_exec_id=$(_sr_exec_id "$_stdlv_db")
  [ -n "$_stdlv_exec_id" ] || _st_die "leave: execution ausente em $_stdlv_db" 1

  _stdlv_curr=$(_st_db_get_current "$_stdlv_sdir")
  if [ "$_stdlv_curr" -le 1 ]; then
    # Idempotente: orquestrador raiz tem profundidade 1; nao baixa abaixo.
    printf '%s\n' "$_stdlv_curr"
    return 0
  fi
  _stdlv_next=$((_stdlv_curr - 1))

  _stdlv_exec_id_sql=$(_sr_sql_quote "$_stdlv_exec_id")
  _stdlv_sql="UPDATE execution SET subagent_depth=$_stdlv_next WHERE id=$_stdlv_exec_id_sql;"
  _state_db_exec_with_retry "$_stdlv_db" "$_stdlv_sql" \
    || _st_die "leave: UPDATE falhou (backend sqlite) — ver stderr acima" 1

  printf '%s\n' "$_stdlv_next"
}

_st_db_current() {
  _stdcu_sdir="$1"
  _stdcu_db=$(_sr_db_file "$_stdcu_sdir")
  [ -f "$_stdcu_db" ] || _st_die "current: state.db ausente em $_stdcu_sdir" 1
  _st_db_get_current "$_stdcu_sdir"
}
