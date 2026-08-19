#!/bin/sh
# state-db-schema.sh — criacao idempotente do state.db (task 2.1.8).
#
# Ref: docs/specs/state-db-foundation/data-model.md (9 entidades)
#      plugins/cstk/skills/agente-00c-runtime/references/state-db-schema.sql (DDL)
#      docs/constitution.md — Mandatory dependency carve-out: transactional
#      state layer (amendment 1.3.0), condicao (b) fail-fast diagnostico.
#
# Subcomandos:
#   state-db-schema.sh create --db PATH
#       — Aplica o DDL de references/state-db-schema.sql ao banco em PATH
#         (cria o arquivo se nao existir). Idempotente: toda CREATE do DDL
#         usa IF NOT EXISTS; reexecutar sobre um banco ja criado e no-op.
#       — Aplica `PRAGMA journal_mode=WAL` uma unica vez apos a criacao
#         (dec-014 — WAL como mecanismo primario de concorrencia).
#       — `chmod 600` no banco e nos sidecars -wal/-shm apos a escrita
#         (C9, finding S3, paridade com otel-usage.sh:262).
#
#   state-db-schema.sh ensure --db PATH
#       — Migracao aditiva idempotente (feature structural-decision-human-gate,
#         research.md Decision 3): garante que `decision` tenha as colunas
#         `decision_class`/`structural_axis`/`human_consent_block_id` e que
#         `human_block` tenha `subject_key`, adicionando via `ALTER TABLE
#         ADD COLUMN` SOMENTE a coluna de fato ausente (INV-E1). Puramente
#         aditivo: nunca DROP, nunca recriacao de tabela, nunca reescrita de
#         linha existente (INV-E2). Fail-hard: sqlite3 ausente, banco
#         ilegivel ou ALTER TABLE falho => exit 1, sem degradar para
#         best-effort (INV-E3 — fonte de verdade transacional). Chamado
#         apenas em caminhos de escrita (_sd_db_register, state-rw.sh init,
#         state-db-migrate.sh) — NUNCA no caminho de leitura.
#
# Exit codes:
#   0 sucesso
#   1 erro generico (sqlite3 ausente, escrita/DDL falhou)
#   2 uso incorreto
#
# POSIX sh. Dependencia obrigatoria de sqlite3 nesta camada — coberta pelo
# carve-out do amendment 1.3.0 (fail-fast abaixo satisfaz a condicao (b)).

set -eu

_SDS_NAME="state-db-schema"
_SDS_SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd -P)
_SDS_SCHEMA_SQL="$_SDS_SELF_DIR/../references/state-db-schema.sql"

# shellcheck source=./_state-db.sh
. "$_SDS_SELF_DIR/_state-db.sh"

_sds_die_usage() {
  printf '%s: %s\n' "$_SDS_NAME" "$1" >&2
  exit 2
}

_sds_die() {
  printf '%s: %s\n' "$_SDS_NAME" "$1" >&2
  exit "${2:-1}"
}

_sds_require_sqlite3() {
  command -v sqlite3 >/dev/null 2>&1 \
    || _sds_die "sqlite3 nao encontrado no PATH (brew install sqlite | apt install sqlite3) — dependencia obrigatoria da camada de estado transacional, ver docs/constitution.md amendment 1.3.0" 1
}

_sds_cmd_create() {
  _sds_db=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --db) _sds_db=$2; shift 2 ;;
      *) _sds_die_usage "create: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sds_db" ] || _sds_die_usage "create: --db obrigatorio"
  [ -f "$_SDS_SCHEMA_SQL" ] || _sds_die "create: DDL nao encontrado em $_SDS_SCHEMA_SQL" 1

  _sds_require_sqlite3

  _sds_dbdir=$(dirname -- "$_sds_db")
  [ -d "$_sds_dbdir" ] || _sds_die "create: diretorio do banco nao existe: $_sds_dbdir" 1

  sqlite3 "$_sds_db" < "$_SDS_SCHEMA_SQL" \
    || _sds_die "create: falha ao aplicar DDL em $_sds_db" 1

  # WAL: idempotente por natureza (PRAGMA journal_mode e persistido no
  # arquivo; reaplicar sobre um banco ja WAL e no-op silencioso do proprio
  # SQLite). Executado apos o DDL para nao interferir na criacao inicial.
  sqlite3 "$_sds_db" 'PRAGMA journal_mode=WAL;' >/dev/null \
    || _sds_die "create: falha ao aplicar PRAGMA journal_mode=WAL em $_sds_db" 1

  _state_db_secure_perms "$_sds_db"

  printf '%s: create: schema aplicado em %s\n' "$_SDS_NAME" "$_sds_db"
}

# _sds_exec_capture_retry DB SQL [BUSY_MS] -> stdout da tentativa vencedora.
# `ensure` roda no caminho de escrita CONCORRENTE (_sd_db_register e chamado
# por N workers em paralelo — task 1.2.4), diferente de `create` (chamado
# uma unica vez antes de qualquer escritor existir). Sem busy_timeout/retry
# aqui, o PRAGMA table_info() de um worker podia colidir com o ALTER TABLE
# exclusivo de outro e falhar com "database is locked" — achado empirico
# rodando tests/test_state-decisions.sh::scenario_sqlite_register_concorrente_sem_colisao
# apos wire-up desta feature. Mesmo padrao de retry/backoff de
# _state_db_exec_with_retry (C6), mas preservando stdout (paridade com
# _sd_db_exec_capture em _state-decisions-db.sh) — precisamos do resultado
# do SELECT, nao so do exit code.
_sds_exec_capture_retry() {
  _sec2_db="$1"; _sec2_sql="$2"; _sec2_ms="${3:-5000}"
  _sec2_try=1
  while [ "$_sec2_try" -le 4 ]; do
    _sec2_errfile=$(mktemp) || return 1
    if _sec2_out=$(_state_db_exec "$_sec2_db" "$_sec2_sql" "$_sec2_ms" 2>"$_sec2_errfile"); then
      _sec2_rc=0
    else
      _sec2_rc=$?
    fi
    _sec2_err=$(cat -- "$_sec2_errfile" 2>/dev/null)
    rm -f -- "$_sec2_errfile"
    if [ "$_sec2_rc" -eq 0 ]; then
      printf '%s\n' "$_sec2_out"
      return 0
    fi
    case "$_sec2_err" in
      *"database is locked"*|*"database is busy"*|*"locking protocol"*)
        _state_db_backoff_sleep "$_sec2_try"
        _sec2_try=$((_sec2_try + 1))
        ;;
      *"duplicate column name"*)
        # Corrida entre dois `ensure` concorrentes: outro worker ja
        # adicionou a mesma coluna entre o nosso table_info e este ALTER.
        # Resultado final e identico (INV-E1 idempotente) -> sucesso.
        return 0
        ;;
      *)
        [ -n "$_sec2_err" ] && printf '%s\n' "$_sec2_err" >&2
        return 1
        ;;
    esac
  done
  [ -n "${_sec2_err:-}" ] && printf '%s\n' "$_sec2_err" >&2
  return 1
}

# _sds_ensure_column DB TABLE COLUMN TYPE
# Adiciona COLUMN a TABLE somente se ausente (INV-E1). TABLE/COLUMN/TYPE sao
# SEMPRE literais fixos passados pelo proprio script (nunca input externo) —
# a interpolacao abaixo nao e superficie de injecao.
_sds_ensure_column() {
  _sec_db="$1" _sec_table="$2" _sec_col="$3" _sec_type="$4"
  _sec_exists=$(_sds_exec_capture_retry "$_sec_db" \
    "SELECT count(*) FROM pragma_table_info('$_sec_table') WHERE name='$_sec_col';") \
    || _sds_die "ensure: falha ao consultar table_info($_sec_table) em $_sec_db" 1
  [ "$_sec_exists" = "0" ] || return 0
  _sds_exec_capture_retry "$_sec_db" \
    "ALTER TABLE $_sec_table ADD COLUMN $_sec_col $_sec_type;" >/dev/null \
    || _sds_die "ensure: falha ao adicionar coluna $_sec_col em $_sec_table ($_sec_db)" 1
}

_sds_cmd_ensure() {
  _sds_db=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --db) _sds_db=$2; shift 2 ;;
      *) _sds_die_usage "ensure: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sds_db" ] || _sds_die_usage "ensure: --db obrigatorio"
  [ -f "$_sds_db" ] || _sds_die "ensure: banco nao encontrado em $_sds_db" 1

  _sds_require_sqlite3

  _sds_ensure_column "$_sds_db" decision decision_class TEXT
  _sds_ensure_column "$_sds_db" decision structural_axis TEXT
  _sds_ensure_column "$_sds_db" decision human_consent_block_id TEXT
  _sds_ensure_column "$_sds_db" human_block subject_key TEXT
}

_sds_main() {
  [ "$#" -ge 1 ] || _sds_die_usage "subcomando obrigatorio (create|ensure)"
  _sds_sub=$1; shift
  case "$_sds_sub" in
    create) _sds_cmd_create "$@" ;;
    ensure) _sds_cmd_ensure "$@" ;;
    *) _sds_die_usage "subcomando desconhecido: $_sds_sub" ;;
  esac
}

_sds_main "$@"
