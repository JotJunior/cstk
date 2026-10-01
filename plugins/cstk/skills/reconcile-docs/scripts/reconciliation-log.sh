#!/bin/sh
# reconciliation-log.sh — anexa uma entrada datada ao registro append-only
# `reconciliation.md` de uma feature, para a skill `reconcile-docs`.
#
# Ref: docs/specs/code-reconciliation/contracts/cli-invocation.md §6
#      research Decision 8; FR-018, FR-012
#
# Uso:
#   reconciliation-log.sh append --feature-dir <dir> --date <YYYY-MM-DD> \
#       --summary-file <file> [--root <dir>]
#
# Cria <feature-dir>/reconciliation.md com cabecalho se ausente e ANEXA
# `## <date>` + conteudo do --summary-file. Nunca edita entradas existentes.
# A raiz do projeto e derivada do feature-dir (.../docs/specs/[_archived/]<x>)
# quando --root nao e informado. Antes de escrever, o destino DEVE passar em
# `doc-guard.sh check` (fail-closed: qualquer exit != 0 do guarda, inclusive
# guarda ausente, nega a escrita).
#
# Exit: 0 entrada anexada | 1 destino negado pelo guarda (nada escrito)
#       2 uso incorreto / entrada invalida | 3 --summary-file vazio (nada escrito —
#       execucao sem alteracao nao grava: FR-012/SC-003)
# POSIX sh, sem jq, sem git.

set -eu

_RL_NAME="reconciliation-log"
_RL_DIR=$(cd "$(dirname "$0")" && pwd)

_rl_usage() {
  cat <<'USAGE' >&2
Uso: reconciliation-log.sh append --feature-dir <dir> --date <YYYY-MM-DD> --summary-file <file> [--root <dir>]
USAGE
}

[ $# -ge 1 ] || { _rl_usage; exit 2; }
[ "$1" = append ] || { _rl_usage; exit 2; }
shift

_RL_FDIR=""; _RL_DATE=""; _RL_SUM=""; _RL_ROOT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --feature-dir) [ $# -ge 2 ] || { _rl_usage; exit 2; }; _RL_FDIR=$2; shift 2 ;;
    --date) [ $# -ge 2 ] || { _rl_usage; exit 2; }; _RL_DATE=$2; shift 2 ;;
    --summary-file) [ $# -ge 2 ] || { _rl_usage; exit 2; }; _RL_SUM=$2; shift 2 ;;
    --root) [ $# -ge 2 ] || { _rl_usage; exit 2; }; _RL_ROOT=$2; shift 2 ;;
    *) _rl_usage; exit 2 ;;
  esac
done
[ -n "$_RL_FDIR" ] && [ -n "$_RL_DATE" ] && [ -n "$_RL_SUM" ] || { _rl_usage; exit 2; }

printf '%s\n' "$_RL_DATE" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' \
  || { printf '%s: --date invalida (esperado YYYY-MM-DD)\n' "$_RL_NAME" >&2; exit 2; }
[ -f "$_RL_SUM" ] || { printf '%s: --summary-file inexistente: %s\n' "$_RL_NAME" "$_RL_SUM" >&2; exit 2; }
[ -d "$_RL_FDIR" ] || { printf '%s: feature-dir inexistente: %s\n' "$_RL_NAME" "$_RL_FDIR" >&2; exit 1; }

_RL_FREAL=$(cd "$_RL_FDIR" && pwd -P)
if [ -z "$_RL_ROOT" ]; then
  case "$_RL_FREAL" in
    */docs/specs/_archived/*) _RL_ROOT=${_RL_FREAL%/docs/specs/_archived/*} ;;
    */docs/specs/*) _RL_ROOT=${_RL_FREAL%/docs/specs/*} ;;
    *) printf '%s: feature-dir fora de docs/specs/: %s\n' "$_RL_NAME" "$_RL_FDIR" >&2; exit 1 ;;
  esac
fi

_RL_TARGET="$_RL_FREAL/reconciliation.md"

# Guarda fail-closed: qualquer saida != 0 (ou guarda ausente) nega a escrita.
if [ ! -f "$_RL_DIR/doc-guard.sh" ] \
  || ! sh "$_RL_DIR/doc-guard.sh" check --root "$_RL_ROOT" --feature-dir "$_RL_FREAL" "$_RL_TARGET"; then
  printf '%s: escrita negada pelo doc-guard: %s\n' "$_RL_NAME" "$_RL_TARGET" >&2
  exit 1
fi

# Resumo vazio (ou so espacos): nada e escrito.
if ! grep -q '[^[:space:]]' "$_RL_SUM"; then
  printf '%s: --summary-file vazio; nada gravado\n' "$_RL_NAME" >&2
  exit 3
fi

if [ ! -e "$_RL_TARGET" ]; then
  {
    printf '# Reconciliation log\n\n'
    printf 'Registro append-only das reconciliacoes desta feature (skill `reconcile-docs`).\n'
    printf 'Nao edite entradas existentes; cada execucao com alteracao anexa uma nova entrada.\n\n'
  } > "$_RL_TARGET"
elif [ -s "$_RL_TARGET" ] && [ "$(tail -c 1 "$_RL_TARGET" | wc -c | tr -d ' ')" = 1 ] \
  && [ -n "$(tail -c 1 "$_RL_TARGET" | tr -d '\n')" ]; then
  printf '\n' >> "$_RL_TARGET"     # garante fronteira de linha antes de anexar
fi

{
  printf '## %s\n\n' "$_RL_DATE"
  cat "$_RL_SUM"
  printf '\n'
} >> "$_RL_TARGET"

printf 'APPENDED\t%s\n' "$_RL_TARGET"
exit 0
