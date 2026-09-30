#!/bin/sh
# markers.sh — valida, lista e confere os MARCADORES inline de reconciliacao e
# calcula o proximo FR-NNN, para a skill `reconcile-docs`.
#
# Ref: docs/specs/code-reconciliation/contracts/markers.md
#      docs/specs/code-reconciliation/contracts/cli-invocation.md §5; FR-009, FR-012
#
# Sintaxe do marcador (contracts/markers.md §1):
#   [reconciled:<kind> <date> evidence=<ref>]
#   kind = removed|updated|added ; date = YYYY-MM-DD ;
#   ref  = <path>:<line> | absent:<path>
#
# Uso:
#   markers.sh lint <file>                 exit 0 ok | 1 marcador mal formado
#                                          (stdout: <line>\t<texto>)
#   markers.sh list <file>                 TSV <line>\t<kind>\t<date>\t<ref>
#   markers.sh next-fr <spec.md>           imprime FR-NNN seguinte (FR-001 se nenhum)
#   markers.sh verify --root <dir> <file>  exit 0 se toda evidencia confere;
#                                          1 lista <line>\t<ref>\t<motivo>
#       motivos: missing-file | line-out-of-range | not-absent
#
# Marcadores dentro de cercas de codigo (```) ou de crases inline sao ignorados
# (documentacao da propria sintaxe, ex.: contracts/markers.md). Somente leitura:
# nenhum subcomando escreve arquivos (idempotencia — contracts/markers.md §4).
#
# Exit: 0 ok | 1 falha de validacao | 2 uso incorreto ou arquivo inexistente
# POSIX sh + awk (sem intervalos de regex), sem jq, sem git.

set -eu

_MK_NAME="markers"
TAB=$(printf '\t')

_mk_usage() {
  cat <<'USAGE' >&2
Uso:
  markers.sh lint <file>
  markers.sh list <file>
  markers.sh next-fr <spec.md>
  markers.sh verify --root <dir> <file>
USAGE
}

# Emite registros do arquivo: "L<TAB>linha<TAB>kind<TAB>date<TAB>ref" (bem
# formados) e "B<TAB>linha<TAB>texto" (linhas com marcador mal formado).
_mk_scan() {
  awk '
    BEGIN {
      RE = "\\[reconciled:(removed|updated|added) [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] evidence=(absent:)?[^] :]+(:[0-9]+)?\\]"
    }
    /^[ \t]*```/ { fence = !fence; next }
    fence { next }
    {
      orig = $0
      s = $0
      gsub(/`[^`]*`/, "", s)
      total = 0; t = s
      while ((p = index(t, "[reconciled:")) > 0) { total++; t = substr(t, p + 12) }
      if (total == 0) next
      good = 0; bad = 0; rest = s
      while (match(rest, RE)) {
        m = substr(rest, RSTART + 12, RLENGTH - 13)   # kind date evidence=ref
        rest = substr(rest, RSTART + RLENGTH)
        n = split(m, f, " ")
        kind = f[1]; date = f[2]; ref = substr(f[3], 10)
        mo = substr(date, 6, 2) + 0; dy = substr(date, 9, 2) + 0
        if (mo < 1 || mo > 12 || dy < 1 || dy > 31) { bad++; continue }
        good++
        print "L\t" NR "\t" kind "\t" date "\t" ref
      }
      if (bad > 0 || total > good + bad) {
        sub(/^[ \t]+/, "", orig)
        print "B\t" NR "\t" orig
      }
    }
  ' "$1"
}

_mk_need_file() {
  [ -f "$1" ] || { printf '%s: arquivo inexistente: %s\n' "$_MK_NAME" "$1" >&2; exit 2; }
}

[ $# -ge 1 ] || { _mk_usage; exit 2; }
_MK_CMD=$1
shift

case "$_MK_CMD" in
  lint)
    [ $# -eq 1 ] || { _mk_usage; exit 2; }
    _mk_need_file "$1"
    _MK_BAD=$(_mk_scan "$1" | awk -F "$TAB" '$1 == "B" { print $2 "\t" $3 }')
    if [ -n "$_MK_BAD" ]; then
      printf '%s\n' "$_MK_BAD"
      exit 1
    fi
    exit 0
    ;;
  list)
    [ $# -eq 1 ] || { _mk_usage; exit 2; }
    _mk_need_file "$1"
    _mk_scan "$1" | awk -F "$TAB" '$1 == "L" { print $2 "\t" $3 "\t" $4 "\t" $5 }'
    exit 0
    ;;
  next-fr)
    [ $# -eq 1 ] || { _mk_usage; exit 2; }
    _mk_need_file "$1"
    awk '
      {
        s = $0
        while (match(s, /FR-[0-9][0-9]*/)) {
          v = substr(s, RSTART + 3, RLENGTH - 3) + 0
          if (v > max) max = v
          s = substr(s, RSTART + RLENGTH)
        }
      }
      END { printf "FR-%03d\n", max + 1 }
    ' "$1"
    exit 0
    ;;
  verify)
    _MK_ROOT=""; _MK_FILE=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --root) [ $# -ge 2 ] || { _mk_usage; exit 2; }; _MK_ROOT=$2; shift 2 ;;
        -*) _mk_usage; exit 2 ;;
        *) [ -z "$_MK_FILE" ] || { _mk_usage; exit 2; }; _MK_FILE=$1; shift ;;
      esac
    done
    [ -n "$_MK_ROOT" ] && [ -n "$_MK_FILE" ] || { _mk_usage; exit 2; }
    _mk_need_file "$_MK_FILE"
    [ -d "$_MK_ROOT" ] || { printf '%s: raiz inexistente: %s\n' "$_MK_NAME" "$_MK_ROOT" >&2; exit 2; }
    _MK_FAIL=0
    _MK_LIST=$(_mk_scan "$_MK_FILE" | awk -F "$TAB" '$1 == "L" { print $2 "\t" $5 }')
    if [ -n "$_MK_LIST" ]; then
      while IFS="$TAB" read -r _ln _ref; do
        _why=""
        case "$_ref" in
          absent:*)
            _p=${_ref#absent:}
            case "$_p" in
              /* | ../* | */../* | ..) _why=not-absent ;;
              *) if [ -e "$_MK_ROOT/$_p" ] || [ -L "$_MK_ROOT/$_p" ]; then _why=not-absent; fi ;;
            esac ;;
          *)
            _p=$_ref; _l=""
            case "$_ref" in
              *:[0-9]*) _p=${_ref%:*}; _l=${_ref##*:} ;;
            esac
            case "$_p" in
              /* | ../* | */../* | ..) _why=missing-file ;;
              *)
                if [ ! -f "$_MK_ROOT/$_p" ]; then
                  _why=missing-file
                elif [ -n "$_l" ]; then
                  _tot=$(awk 'END { print NR }' "$_MK_ROOT/$_p")
                  if [ "$_l" -lt 1 ] || [ "$_l" -gt "$_tot" ]; then _why=line-out-of-range; fi
                fi ;;
            esac ;;
        esac
        if [ -n "$_why" ]; then
          printf '%s\t%s\t%s\n' "$_ln" "$_ref" "$_why"
          _MK_FAIL=1
        fi
      done <<EOF2
$_MK_LIST
EOF2
    fi
    [ "$_MK_FAIL" = 0 ] || exit 1
    exit 0
    ;;
  *) _mk_usage; exit 2 ;;
esac
