#!/bin/sh
# locate-feature.sh — localiza features (ativas e arquivadas) sob docs/specs/
# para a skill `reconcile-docs`.
#
# Ref: docs/specs/code-reconciliation/contracts/cli-invocation.md §2
#      research Decision 3; FR-002, FR-014, FR-015
#
# Uso:
#   locate-feature.sh --root <dir> --name <feature>
#   locate-feature.sh --root <dir> --all
#
# stdout TSV (sem cabecalho): <location>\t<name>\t<dir>
#   <location> = active | archived | archived-shadowed | candidate
#   <dir>      = caminho relativo a --root
#
# Exit: 0 sucesso | 1 erro (docs/specs/ ausente) | 2 uso incorreto
#       3 nenhum casamento exato (candidatos por substring, pode ser vazio)
#       4 mais de um casamento exato na mesma classe (candidatos)
#
# Nunca lista docs/specs/current/ nem docs/specs/_archived/ como feature.
# POSIX sh, sem jq, sem git.

set -eu

_LF_NAME="locate-feature"
TAB=$(printf '\t')
NL='
'
_LF_RE_DIR='^([0-9]{4}-[0-9]{2}-[0-9]{2}-)?[a-z0-9][a-z0-9-]*$'

_lf_err() { printf '%s: %s\n' "$_LF_NAME" "$*" >&2; }

_lf_usage() {
  cat <<'USAGE' >&2
Uso:
  locate-feature.sh --root <dir> --name <feature>
  locate-feature.sh --root <dir> --all
USAGE
}

# Remove o prefixo AAAA-MM-DD- (se houver).
_lf_strip() {
  printf '%s\n' "$1" | sed 's/^[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}-//'
}

# Nome valido (dir de feature ou --name): regex + sem quebra de linha.
_lf_valid() {
  case "$1" in
    '' | *"$NL"* | *"$TAB"*) return 1 ;;
  esac
  printf '%s\n' "$1" | grep -Eq "$_LF_RE_DIR"
}

# Lista as ativas: "<name>\t<reldir>" ordenado.
_lf_list_active() {
  for _d in "$_LF_SPECS"/*/; do
    [ -d "$_d" ] || continue
    _d=${_d%/}
    [ -L "$_d" ] && continue
    _b=${_d##*/}
    case "$_b" in current | _archived) continue ;; esac
    _lf_valid "$_b" || continue
    printf '%s\t%s\n' "$_b" "docs/specs/$_b"
  done | LC_ALL=C sort
}

# Lista as arquivadas: "<name>\t<reldir>" ordenado por dir (name sem prefixo).
_lf_list_archived() {
  [ -d "$_LF_SPECS/_archived" ] || return 0
  for _d in "$_LF_SPECS"/_archived/*/; do
    [ -d "$_d" ] || continue
    _d=${_d%/}
    [ -L "$_d" ] && continue
    _b=${_d##*/}
    _lf_valid "$_b" || continue
    printf '%s\t%s\n' "$(_lf_strip "$_b")" "docs/specs/_archived/$_b"
  done | LC_ALL=C sort -t "$TAB" -k2,2
}

_LF_ROOT=""
_LF_FEATURE=""
_LF_ALL=0
_LF_HAVE_NAME=0
while [ $# -gt 0 ]; do
  case "$1" in
    --root) [ $# -ge 2 ] || { _lf_usage; exit 2; }; _LF_ROOT=$2; shift 2 ;;
    --name) [ $# -ge 2 ] || { _lf_usage; exit 2; }; _LF_FEATURE=$2; _LF_HAVE_NAME=1; shift 2 ;;
    --all) _LF_ALL=1; shift ;;
    *) _lf_usage; exit 2 ;;
  esac
done

[ -n "$_LF_ROOT" ] || { _lf_usage; exit 2; }
if [ "$_LF_ALL" = 1 ] && [ "$_LF_HAVE_NAME" = 1 ]; then _lf_usage; exit 2; fi
if [ "$_LF_ALL" = 0 ] && [ "$_LF_HAVE_NAME" = 0 ]; then _lf_usage; exit 2; fi
if [ "$_LF_HAVE_NAME" = 1 ] && ! _lf_valid "$_LF_FEATURE"; then
  _lf_err "nome de feature invalido (esperado ^([0-9]{4}-[0-9]{2}-[0-9]{2}-)?[a-z0-9][a-z0-9-]*\$)"
  exit 2
fi

[ -d "$_LF_ROOT" ] || { _lf_err "raiz inexistente: $_LF_ROOT"; exit 1; }
_LF_SPECS="$_LF_ROOT/docs/specs"
[ -d "$_LF_SPECS" ] || { _lf_err "docs/specs/ ausente em $_LF_ROOT"; exit 1; }

_LF_ACTIVE=$(_lf_list_active)
_LF_ARCH=$(_lf_list_archived)

# --- modo --all -------------------------------------------------------------
if [ "$_LF_ALL" = 1 ]; then
  if [ -n "$_LF_ACTIVE" ]; then
    printf '%s\n' "$_LF_ACTIVE" | while IFS="$TAB" read -r _n _p; do
      printf 'active\t%s\t%s\n' "$_n" "$_p"
    done
  fi
  if [ -n "$_LF_ARCH" ]; then
    printf '%s\n' "$_LF_ARCH" | while IFS="$TAB" read -r _n _p; do
      _loc=archived
      if [ -n "$_LF_ACTIVE" ] && printf '%s\n' "$_LF_ACTIVE" | cut -f1 | grep -Fxq -- "$_n"; then
        _loc=archived-shadowed
      fi
      printf '%s\t%s\t%s\n' "$_loc" "$_n" "$_p"
    done
  fi
  exit 0
fi

# --- modo --name ------------------------------------------------------------
# Casamento exato: ativa por nome; arquivada por nome sem prefixo OU por dir.
_LF_M_ACTIVE=""
if [ -n "$_LF_ACTIVE" ]; then
  _LF_M_ACTIVE=$(printf '%s\n' "$_LF_ACTIVE" | awk -F "$TAB" -v n="$_LF_FEATURE" '$1 == n')
fi
_LF_M_ARCH=""
if [ -n "$_LF_ARCH" ]; then
  _LF_M_ARCH=$(printf '%s\n' "$_LF_ARCH" | awk -F "$TAB" -v n="$_LF_FEATURE" '{ b=$2; sub(/.*\//, "", b); if ($1 == n || b == n) print }')
fi

if [ -n "$_LF_M_ACTIVE" ]; then
  printf '%s\n' "$_LF_M_ACTIVE" | while IFS="$TAB" read -r _n _p; do
    printf 'active\t%s\t%s\n' "$_n" "$_p"
  done
  if [ -n "$_LF_M_ARCH" ]; then
    printf '%s\n' "$_LF_M_ARCH" | while IFS="$TAB" read -r _n _p; do
      printf 'archived-shadowed\t%s\t%s\n' "$_n" "$_p"
    done
  fi
  _cnt=$(printf '%s\n' "$_LF_M_ACTIVE" | wc -l | tr -d ' ')
  [ "$_cnt" -gt 1 ] && exit 4
  exit 0
fi

if [ -n "$_LF_M_ARCH" ]; then
  _cnt=$(printf '%s\n' "$_LF_M_ARCH" | wc -l | tr -d ' ')
  if [ "$_cnt" -eq 1 ]; then
    printf '%s\n' "$_LF_M_ARCH" | while IFS="$TAB" read -r _n _p; do
      printf 'archived\t%s\t%s\n' "$_n" "$_p"
    done
    exit 0
  fi
  printf '%s\n' "$_LF_M_ARCH" | while IFS="$TAB" read -r _n _p; do
    printf 'candidate\t%s\t%s\n' "$_n" "$_p"
  done
  exit 4
fi

# Sem casamento exato: candidatos por substring (nome ou basename do dir).
{
  [ -n "$_LF_ACTIVE" ] && printf '%s\n' "$_LF_ACTIVE"
  [ -n "$_LF_ARCH" ] && printf '%s\n' "$_LF_ARCH"
  :
} | awk -F "$TAB" -v n="$_LF_FEATURE" '{ b=$2; sub(/.*\//, "", b); if (index($1, n) > 0 || index(b, n) > 0) print }' \
  | LC_ALL=C sort -u | while IFS="$TAB" read -r _n _p; do
    [ -n "$_n" ] && printf 'candidate\t%s\t%s\n' "$_n" "$_p"
  done
exit 3
