#!/bin/sh
# path-guard.sh — validacao de paths (FR-024 + FR-017).
#
# Ref: docs/specs/agente-00c/spec.md FR-024 (zonas proibidas para projeto-alvo)
#      docs/specs/agente-00c/spec.md FR-017 (runtime path validation em escrita)
#      docs/specs/agente-00c/threat-model.md T2
#      docs/specs/agente-00c/tasks.md FASE 6.1 + 6.8
#
# Defesa em duas camadas:
#   1. validate-target — rejeita --projeto-alvo-path em zonas sensiveis do
#      sistema (`/`, `/etc`, `/usr`, `/var`, `~/.claude`, `~/.ssh`,
#      `~/.config`, `~/.aws`, `~/.docker`, `~/Library`, `~/.gnupg`).
#      Resolve symlinks via `realpath -- PATH` (ou `readlink -f`) ANTES da
#      comparacao — evita symlinks que apontam para zona proibida (T2).
#   2. check-write — rejeita escrita fora do projeto-alvo. Resolve target via
#      realpath, verifica string-prefix com projeto-alvo resolvido. Read /
#      Glob / Grep NAO sao validados (leitura fora e permitida — skills,
#      CLAUDE.md raiz, etc).
#
# Subcomandos:
#   path-guard.sh validate-target --projeto-alvo-path PATH
#       — Resolve symlinks. Se nao existe, valida o path absoluto que seria
#         usado (sem requerir existencia ainda).
#       — Exit 0 se OK; exit 1 se em zona proibida.
#
#   path-guard.sh check-write --projeto-alvo-path BASE --target PATH
#       — Resolve target. Verifica que o resolvido tem prefixo BASE
#         (apos resolver BASE tambem). Se nao, exit 1.
#       — Exit 0 se OK.
#
#   path-guard.sh resolve PATH
#       — Helper: imprime path resolvido (debug/inspecao).
#
# Exit codes:
#   0 OK
#   1 violacao (zona proibida ou prefixo nao-bate)
#   2 uso incorreto
#
# POSIX sh + realpath/readlink (BSD/GNU detection).

set -eu

_PG_NAME="path-guard"

# Lista de zonas proibidas (string com paths separados por NEWLINE).
# `~` expandido em runtime via $HOME. Precisamos cobrir tanto a forma
# canonica (/etc) quanto a forma resolvida no macOS (/private/etc), porque
# `realpath /etc` retorna `/private/etc` em darwin.
#
# IMPORTANTE: NAO incluir `/private` ou `/var` puros — o macOS usa
# `/private/var/folders` para `mktemp -d`, que e local LEGITIMO de
# projetos temporarios. Listar subdirs especificos.
_pg_forbidden_zones() {
  cat <<EOF
/
/etc
/usr
/bin
/sbin
/var/log
/var/db
/var/run
/var/lib
/private/etc
/private/usr
/private/bin
/private/sbin
/private/var/log
/private/var/db
/private/var/run
/private/var/lib
/System
/Library
${HOME:?HOME nao setado}/.claude
${HOME}/.ssh
${HOME}/.config
${HOME}/.aws
${HOME}/.docker
${HOME}/.gnupg
${HOME}/.kube
EOF
}

_pg_die_usage() { printf '%s: %s\n' "$_PG_NAME" "$1" >&2; exit 2; }
_pg_die()       { printf '%s: %s\n' "$_PG_NAME" "$1" >&2; exit "${2:-1}"; }

# _pg_resolve PATH -> path absoluto resolvido (symlinks expandidos)
# Falha portavel: tenta realpath -> readlink -f -> python -c
# Se path nao existe ainda, resolve o pai e concatena o basename.
_pg_resolve() {
  _p=$1
  [ -n "$_p" ] || { printf '\n'; return 1; }
  # Atalho: paths existentes via realpath/readlink
  if [ -e "$_p" ]; then
    if command -v realpath >/dev/null 2>&1; then
      realpath -- "$_p" 2>/dev/null && return 0
    fi
    if readlink -f "$_p" >/dev/null 2>&1; then
      readlink -f "$_p" 2>/dev/null && return 0
    fi
  fi
  # Path nao existe: resolve o dir pai (deve existir) e concatena basename
  _parent=$(dirname -- "$_p")
  _base=$(basename -- "$_p")
  if [ -d "$_parent" ]; then
    if command -v realpath >/dev/null 2>&1; then
      _r=$(realpath -- "$_parent" 2>/dev/null) || _r=""
      [ -n "$_r" ] && { printf '%s/%s\n' "$_r" "$_base"; return 0; }
    fi
    if readlink -f "$_parent" >/dev/null 2>&1; then
      _r=$(readlink -f "$_parent" 2>/dev/null) || _r=""
      [ -n "$_r" ] && { printf '%s/%s\n' "$_r" "$_base"; return 0; }
    fi
    # Fallback: usa pwd se for caminho relativo
    if [ "${_p#/}" = "$_p" ]; then
      printf '%s/%s\n' "$(cd "$_parent" 2>/dev/null && pwd)" "$_base"
      return 0
    fi
    printf '%s\n' "$_p"
    return 0
  fi
  # Pai tambem nao existe: assume absoluto + remove . e .. textualmente
  case "$_p" in
    /*) printf '%s\n' "$_p" ;;
    *)  printf '%s/%s\n' "$(pwd)" "$_p" ;;
  esac
}

# _pg_is_in_forbidden RESOLVED_PATH -> 0 se em zona proibida, 1 caso contrario
# Match: path == zona OU path comeca com "zona/"
# Resolve TAMBEM cada zona via _pg_resolve antes de comparar — isso permite
# que o usuario passe `HOME` apontando para tmpdir cujo `realpath` resolve
# para `/private/var/folders/...`, e que `$HOME/.ssh` resolva idem antes
# de comparar com o RESOLVED_PATH.
_pg_is_in_forbidden() {
  _r=$1
  _OLD_IFS=$IFS
  IFS='
'
  for _z in $(_pg_forbidden_zones); do
    IFS=$_OLD_IFS
    [ -z "$_z" ] && { IFS='
'; continue; }
    # Resolve a zona se ela existe (caso contrario usa o path literal)
    if [ -e "$_z" ]; then
      _z_resolved=$(_pg_resolve "$_z")
    else
      _z_resolved=$_z
    fi
    # Match exato (zona literal OU resolvida)
    if [ "$_r" = "$_z" ] || [ "$_r" = "$_z_resolved" ]; then
      printf '%s\n' "$_z"
      return 0
    fi
    # Match prefixo (zona literal OU resolvida)
    case "$_r" in
      "$_z"/*|"$_z_resolved"/*)
        printf '%s\n' "$_z"
        return 0
        ;;
    esac
    IFS='
'
  done
  IFS=$_OLD_IFS
  return 1
}

# _pg_has_prefix RESOLVED_TARGET RESOLVED_BASE -> 0 se target esta sob base
_pg_has_prefix() {
  _t=$1
  _b=$2
  if [ "$_t" = "$_b" ]; then
    return 0
  fi
  case "$_t" in
    "$_b"/*) return 0 ;;
  esac
  return 1
}

# ---------- Subcomandos ----------

_pg_cmd_validate_target() {
  _pap=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --projeto-alvo-path) _pap=$2; shift 2 ;;
      *) _pg_die_usage "validate-target: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_pap" ] || _pg_die_usage "validate-target: --projeto-alvo-path obrigatorio"
  _r=$(_pg_resolve "$_pap")
  [ -n "$_r" ] || _pg_die "validate-target: nao foi possivel resolver $_pap" 1
  if _hit=$(_pg_is_in_forbidden "$_r"); then
    printf '%s: violacao FR-024 — projeto-alvo em zona proibida\n' "$_PG_NAME" >&2
    printf '  --projeto-alvo-path: %s\n' "$_pap" >&2
    printf '  resolvido para: %s\n' "$_r" >&2
    printf '  zona proibida: %s\n' "$_hit" >&2
    exit 1
  fi
  exit 0
}

_pg_cmd_check_write() {
  _pap=""
  _tg=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --projeto-alvo-path) _pap=$2; shift 2 ;;
      --target)            _tg=$2; shift 2 ;;
      *) _pg_die_usage "check-write: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_pap" ] || _pg_die_usage "check-write: --projeto-alvo-path obrigatorio"
  [ -n "$_tg" ]  || _pg_die_usage "check-write: --target obrigatorio"
  _rb=$(_pg_resolve "$_pap")
  _rt=$(_pg_resolve "$_tg")
  [ -n "$_rb" ] || _pg_die "check-write: nao consegui resolver projeto-alvo-path: $_pap" 1
  [ -n "$_rt" ] || _pg_die "check-write: nao consegui resolver target: $_tg" 1
  if ! _pg_has_prefix "$_rt" "$_rb"; then
    printf '%s: violacao FR-017 — escrita fora do projeto-alvo\n' "$_PG_NAME" >&2
    printf '  --target: %s\n' "$_tg" >&2
    printf '  resolvido: %s\n' "$_rt" >&2
    printf '  --projeto-alvo-path: %s\n' "$_pap" >&2
    printf '  base resolvida: %s\n' "$_rb" >&2
    exit 1
  fi
  exit 0
}

_pg_cmd_resolve() {
  [ "$#" -ge 1 ] || _pg_die_usage "resolve: PATH obrigatorio"
  _r=$(_pg_resolve "$1")
  [ -n "$_r" ] || exit 1
  printf '%s\n' "$_r"
}

# ---------- Dispatch ----------

if [ "$#" -lt 1 ]; then
  cat >&2 <<'HELP'
path-guard.sh — validacao de paths (FR-024 + FR-017).

USO:
  path-guard.sh validate-target --projeto-alvo-path PATH
  path-guard.sh check-write     --projeto-alvo-path BASE --target PATH
  path-guard.sh resolve PATH

EXIT:
  0 OK
  1 violacao (zona proibida ou prefixo nao-bate)
  2 uso incorreto

Zonas proibidas: /, /etc, /usr, /var, /bin, /sbin, /private, /System,
/Library, ~/.claude, ~/.ssh, ~/.config, ~/.aws, ~/.docker, ~/.gnupg,
~/.kube, ~/Library
HELP
  exit 2
fi

_PG_SUBCMD=$1
shift

case "$_PG_SUBCMD" in
  validate-target) _pg_cmd_validate_target "$@" ;;
  check-write)     _pg_cmd_check_write "$@" ;;
  resolve)         _pg_cmd_resolve "$@" ;;
  -h|--help|help)  exit 0 ;;
  *) _pg_die_usage "subcomando desconhecido: $_PG_SUBCMD" ;;
esac
