#!/bin/sh
# doc-guard.sh — guarda fail-closed de escrita da skill `reconcile-docs`.
# Decide se um destino pode ser escrito: so documentos da allowlist dentro do
# diretorio de UMA feature (ativa ou arquivada), nunca o corpus canonico
# docs/specs/current/.
#
# Ref: docs/specs/code-reconciliation/contracts/cli-invocation.md §4
#      research Decision 5; FR-006, FR-017, SC-001; checklists/security.md
#
# Uso:
#   doc-guard.sh check --root <dir> --feature-dir <dir> <path>
#
# Allowlist (relativa ao --feature-dir resolvido com pwd -P): spec.md, plan.md,
# data-model.md, quickstart.md, reconciliation.md e contracts/*.md (um nivel).
# Caminhos relativos sao resolvidos a partir de --root.
#
# Exit: 0 escrita permitida | 1 negada (motivo em stderr) | 2 uso incorreto
# Motivos: outside-feature | not-in-allowlist | living-corpus | symlink-escape
#
# FAIL-CLOSED: qualquer erro interno termina com exit != 0; o chamador MUST
# tratar qualquer exit != 0 (inclusive script ausente) como negacao.
# POSIX sh, sem jq, sem git.

set -eu

_DG_NAME="doc-guard"
_DG_OK=0
# Rede de seguranca: exit 0 so quando _DG_OK=1 (setado apenas no fim).
trap 'st=$?; if [ "$st" -eq 0 ] && [ "$_DG_OK" != 1 ]; then exit 1; fi' EXIT

_dg_usage() {
  printf 'Uso: doc-guard.sh check --root <dir> --feature-dir <dir> <path>\n' >&2
}

_dg_deny() {
  printf '%s: negado: %s (%s)\n' "$_DG_NAME" "$1" "${2:-}" >&2
  exit 1
}

# Resolve diretorio existente para caminho fisico (sem simlinks).
_dg_realdir() { (cd "$1" 2>/dev/null && pwd -P); }

[ $# -ge 1 ] || { _dg_usage; exit 2; }
_DG_CMD=$1
shift
[ "$_DG_CMD" = check ] || { _dg_usage; exit 2; }

_DG_ROOT=""
_DG_FDIR=""
_DG_TARGET=""
_DG_HAVE_TARGET=0
while [ $# -gt 0 ]; do
  case "$1" in
    --root) [ $# -ge 2 ] || { _dg_usage; exit 2; }; _DG_ROOT=$2; shift 2 ;;
    --feature-dir) [ $# -ge 2 ] || { _dg_usage; exit 2; }; _DG_FDIR=$2; shift 2 ;;
    --) shift ;;
    -*) _dg_usage; exit 2 ;;
    *)
      [ "$_DG_HAVE_TARGET" = 0 ] || { _dg_usage; exit 2; }
      _DG_TARGET=$1; _DG_HAVE_TARGET=1; shift ;;
  esac
done

[ -n "$_DG_ROOT" ] && [ -n "$_DG_FDIR" ] && [ "$_DG_HAVE_TARGET" = 1 ] && [ -n "$_DG_TARGET" ] \
  || { _dg_usage; exit 2; }

NL='
'
case "$_DG_TARGET$_DG_FDIR" in *"$NL"*) _dg_deny outside-feature "caminho com quebra de linha" ;; esac

_DG_ROOT_REAL=$(_dg_realdir "$_DG_ROOT") || _dg_deny outside-feature "raiz inacessivel"

# --feature-dir: relativo a --root quando nao absoluto.
case "$_DG_FDIR" in /*) _DG_FDIR_ABS=$_DG_FDIR ;; *) _DG_FDIR_ABS="$_DG_ROOT_REAL/$_DG_FDIR" ;; esac
_DG_FEAT=$(_dg_realdir "$_DG_FDIR_ABS") || _dg_deny outside-feature "feature-dir inexistente"

# Precisa estar sob a raiz: <root>/docs/specs/<seg> ou <root>/docs/specs/_archived/<seg>.
case "$_DG_FEAT" in
  "$_DG_ROOT_REAL"/docs/specs/*) _DG_FREL=${_DG_FEAT#"$_DG_ROOT_REAL"/docs/specs/} ;;
  *) _dg_deny outside-feature "feature-dir fora de docs/specs/" ;;
esac

_DG_LOWER=$(printf '%s' "$_DG_FREL" | LC_ALL=C tr 'A-Z' 'a-z')
case "$_DG_LOWER" in
  current | current/*) _dg_deny living-corpus "feature-dir sob docs/specs/current/" ;;
esac

case "$_DG_FREL" in
  _archived/*) _DG_SEG=${_DG_FREL#_archived/} ;;
  *) _DG_SEG=$_DG_FREL ;;
esac
# Exatamente um segmento, nome de feature valido (minusculo kebab, prefixo de data opcional).
case "$_DG_SEG" in */* | '') _dg_deny outside-feature "feature-dir nao e um diretorio de feature" ;; esac
printf '%s\n' "$_DG_SEG" | grep -Eq '^([0-9]{4}-[0-9]{2}-[0-9]{2}-)?[a-z0-9][a-z0-9-]*$' \
  || _dg_deny outside-feature "nome de feature invalido"

# Destino: relativo a --root quando nao absoluto.
case "$_DG_TARGET" in /*) _DG_T_ABS=$_DG_TARGET ;; *) _DG_T_ABS="$_DG_ROOT_REAL/$_DG_TARGET" ;; esac

# Simlink no proprio destino -> negado, independente do alvo.
if [ -L "$_DG_T_ABS" ]; then
  _dg_deny symlink-escape "$_DG_TARGET"
fi

_DG_T_PARENT=${_DG_T_ABS%/*}
_DG_T_BASE=${_DG_T_ABS##*/}
[ -n "$_DG_T_BASE" ] || _dg_deny not-in-allowlist "$_DG_TARGET"
_DG_T_PARENT_REAL=$(_dg_realdir "$_DG_T_PARENT") || _dg_deny outside-feature "diretorio pai inexistente: $_DG_TARGET"
_DG_T_REAL="$_DG_T_PARENT_REAL/$_DG_T_BASE"

# Corpus canonico por caminho (mesmo com feature-dir valido).
_DG_TLOWER=$(printf '%s' "$_DG_T_REAL" | LC_ALL=C tr 'A-Z' 'a-z')
case "$_DG_TLOWER" in
  "$(printf '%s' "$_DG_ROOT_REAL" | LC_ALL=C tr 'A-Z' 'a-z')"/docs/specs/current | "$(printf '%s' "$_DG_ROOT_REAL" | LC_ALL=C tr 'A-Z' 'a-z')"/docs/specs/current/*)
    _dg_deny living-corpus "$_DG_TARGET" ;;
esac

case "$_DG_T_REAL" in
  "$_DG_FEAT"/*) _DG_TREL=${_DG_T_REAL#"$_DG_FEAT"/} ;;
  *) _dg_deny outside-feature "$_DG_TARGET" ;;
esac

case "$_DG_TREL" in
  spec.md | plan.md | data-model.md | quickstart.md | reconciliation.md) : ;;
  contracts/*.md)
    _DG_CN=${_DG_TREL#contracts/}
    case "$_DG_CN" in
      */* | .md | .*) _dg_deny not-in-allowlist "$_DG_TARGET" ;;
    esac ;;
  *) _dg_deny not-in-allowlist "$_DG_TARGET" ;;
esac

_DG_OK=1
exit 0
