#!/bin/sh
# state-db-schema.sh — criacao idempotente do state.db (task 2.1.8).
#
# Ref: docs/specs/state-db-foundation/data-model.md (9 entidades)
#      global/skills/agente-00c-runtime/references/state-db-schema.sql (DDL)
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

_sds_main() {
  [ "$#" -ge 1 ] || _sds_die_usage "subcomando obrigatorio (create)"
  _sds_sub=$1; shift
  case "$_sds_sub" in
    create) _sds_cmd_create "$@" ;;
    *) _sds_die_usage "subcomando desconhecido: $_sds_sub" ;;
  esac
}

_sds_main "$@"
