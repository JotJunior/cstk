#!/bin/sh
# extract-anchors.sh — extrai as ANCORAS (tokens entre crases) dos documentos de
# uma feature para a skill `reconcile-docs`: caminhos, flags, comandos e ids de
# requisito que a documentacao cita e que o LLM confronta com o codigo.
#
# Ref: docs/specs/code-reconciliation/contracts/cli-invocation.md §3
#      docs/specs/code-reconciliation/data-model.md §Anchor; research Decision 7;
#      FR-004
#
# Uso:
#   extract-anchors.sh --root <dir> --feature-dir <dir>
#
# stdout TSV (sem cabecalho): <kind>\t<token>\t<doc>:<line>\t<presence>
#   kind     = path | flag | command | req-id
#   doc      = documento relativo a --feature-dir (linha 1-based)
#   presence = present | absent | n/a   (so `path` recebe present/absent)
#
# Regras de `path`/presence (relativo a --root):
#   - token com `/`: present se existe em <root>/<token> (ou em <feature-dir>/<token>),
#     senao absent;
#   - nome de arquivo sem `/` (ex.: spec.md): present se existe na raiz ou no
#     feature-dir; senao n/a (nao ha como resolver sem varrer o repositorio);
#   - token com `..` no caminho: n/a.
# Varre so os documentos da allowlist presentes: spec.md, plan.md, data-model.md,
# quickstart.md e contracts/*.md (nunca research.md, checklists/, tasks.md).
# Ignora linhas dentro de cercas de codigo (```). Dedupe por (kind, token,
# doc:line) preservando a ordem.
#
# Exit: 0 (0+ linhas) | 1 feature-dir inexistente OU documento da allowlist presente
#       mas ilegivel (fail-closed: nunca omite ancoras em silencio; diagnostico em
#       stderr) | 2 uso incorreto
# POSIX sh + awk (sem intervalos de regex — compativel com mawk/BWK/gawk), sem jq, sem git.

set -eu

_EA_NAME="extract-anchors"
TAB=$(printf '\t')

_ea_usage() {
  printf 'Uso: extract-anchors.sh --root <dir> --feature-dir <dir>\n' >&2
}

_EA_ROOT=""
_EA_FDIR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root) [ $# -ge 2 ] || { _ea_usage; exit 2; }; _EA_ROOT=$2; shift 2 ;;
    --feature-dir) [ $# -ge 2 ] || { _ea_usage; exit 2; }; _EA_FDIR=$2; shift 2 ;;
    *) _ea_usage; exit 2 ;;
  esac
done
[ -n "$_EA_ROOT" ] && [ -n "$_EA_FDIR" ] || { _ea_usage; exit 2; }

[ -d "$_EA_ROOT" ] || { printf '%s: raiz inexistente: %s\n' "$_EA_NAME" "$_EA_ROOT" >&2; exit 1; }
case "$_EA_FDIR" in /*) : ;; *) _EA_FDIR="$_EA_ROOT/$_EA_FDIR" ;; esac
[ -d "$_EA_FDIR" ] || { printf '%s: feature-dir inexistente: %s\n' "$_EA_NAME" "$_EA_FDIR" >&2; exit 1; }

# Lista de documentos (ordem estavel): spec, plan, data-model, quickstart, contracts/*.md.
_EA_DOCS=""
for _d in spec.md plan.md data-model.md quickstart.md; do
  [ -f "$_EA_FDIR/$_d" ] && _EA_DOCS="$_EA_DOCS$_d
"
done
if [ -d "$_EA_FDIR/contracts" ]; then
  if [ ! -r "$_EA_FDIR/contracts" ] || [ ! -x "$_EA_FDIR/contracts" ]; then
    printf '%s: diretorio ilegivel: %s\n' "$_EA_NAME" "$_EA_FDIR/contracts" >&2
    exit 1
  fi
  _EA_C=$(cd "$_EA_FDIR/contracts" && for _f in *.md; do [ -f "$_f" ] && printf 'contracts/%s\n' "$_f"; done | LC_ALL=C sort) || _EA_C=""
  [ -n "$_EA_C" ] && _EA_DOCS="$_EA_DOCS$_EA_C
"
fi
[ -n "$_EA_DOCS" ] || exit 0

# Fail-closed (FR-004): documento presente mas ilegivel nao pode virar exit 0 com
# ancoras omitidas (o awk so reportaria "can't open file" num pipeline).
_EA_UNREADABLE=$(printf '%s' "$_EA_DOCS" | while IFS= read -r _doc; do
  [ -n "$_doc" ] || continue
  [ -r "$_EA_FDIR/$_doc" ] || printf '%s\n' "$_doc"
done)
if [ -n "$_EA_UNREADABLE" ]; then
  printf '%s\n' "$_EA_UNREADABLE" | while IFS= read -r _doc; do
    printf '%s: documento ilegivel: %s\n' "$_EA_NAME" "$_EA_FDIR/$_doc" >&2
  done
  exit 1
fi

# Fase 1 (awk): tokens candidatos "kind TAB token TAB doc:line".
printf '%s' "$_EA_DOCS" | while IFS= read -r _doc; do
  [ -n "$_doc" ] || continue
  awk -v doc="$_doc" '
    function clean(w) {
      sub(/^[\[(<"\047]+/, "", w)
      sub(/[\])>,.;:!?"\047]+$/, "", w)
      return w
    }
    function emit(kind, tok) {
      key = kind "\t" tok "\t" doc ":" NR
      if (!(key in seen)) { seen[key] = 1; print key }
    }
    /^[ \t]*```/ { fence = !fence; next }
    fence { next }
    {
      n = split($0, parts, "`")
      for (i = 2; i <= n; i += 2) {
        if (i == n) break                     # crase nao fechada
        span = parts[i]
        nw = split(span, words, /[ \t]+/)
        first_kind = ""
        has_flag_or_path = 0
        for (j = 1; j <= nw; j++) {
          w = clean(words[j])
          if (w == "") continue
          if (w ~ /:\/\// || w ~ /[*<>{}$|\\=~]/ && w !~ /^--?[A-Za-z][A-Za-z0-9_-]*=/) continue
          if (w ~ /^--?[A-Za-z][A-Za-z0-9_-]*(=.*)?$/) {
            t = w; sub(/=.*/, "", t)
            emit("flag", t); has_flag_or_path = 1
            continue
          }
          if (w ~ /^[A-Z][A-Z]+-[0-9][0-9]+$/) { emit("req-id", w); continue }
          if (w ~ /^\/[a-z][a-z0-9-]*$/) { emit("command", w); continue }
          t = w; sub(/:[0-9]+$/, "", t); sub(/^\.\//, "", t)
          if (t ~ /^\// || t ~ /^-/) continue
          if (t ~ /\// && t ~ /^[A-Za-z0-9._][A-Za-z0-9._\/-]*$/ && t !~ /\/\//) {
            emit("path", t); has_flag_or_path = 1; continue
          }
          if (t ~ /^[A-Za-z0-9_][A-Za-z0-9_-]*(\.[A-Za-z0-9_-]+)*\.[A-Za-z][A-Za-z0-9]+$/ && t !~ /^[0-9.]+$/) {
            emit("path", t); has_flag_or_path = 1; continue
          }
          if (j == 1 && w ~ /^[a-z][a-z0-9_-]*$/) first_kind = "command"
        }
        if (first_kind == "command" && nw > 1 && has_flag_or_path) {
          w = clean(words[1]); emit("command", w)
        }
      }
    }
  ' "$_EA_FDIR/$_doc"
done | while IFS="$TAB" read -r _kind _tok _src; do
  # Fase 2 (sh): presence so para `path`.
  _pres="n/a"
  if [ "$_kind" = path ]; then
    case "$_tok" in
      *..*) _pres="n/a" ;;
      */*)
        if [ -e "$_EA_ROOT/$_tok" ] || [ -e "$_EA_FDIR/$_tok" ]; then _pres=present; else _pres=absent; fi ;;
      *)
        if [ -e "$_EA_ROOT/$_tok" ] || [ -e "$_EA_FDIR/$_tok" ]; then _pres=present; else _pres="n/a"; fi ;;
    esac
  fi
  printf '%s\t%s\t%s\t%s\n' "$_kind" "$_tok" "$_src" "$_pres"
done
exit 0
