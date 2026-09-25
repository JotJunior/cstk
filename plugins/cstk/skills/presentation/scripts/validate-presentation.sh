#!/bin/sh
# validate-presentation.sh — valida um story.md da skill `presentation`
# contra a gramatica fechada e contra o inventario deterministico, antes do
# render. Garante cobertura 1:1 das specs, fontes citadas e metricas so por
# chave do inventario (Constitution Principio VI).
#
# Ref: docs/specs/presentation/contracts/slide-grammar.md (G-01..G-10)
#      plugins/cstk/skills/presentation/references/slide-grammar.md
#
# Uso:
#   validate-presentation.sh --story FILE --inventory FILE [--root DIR]
#
#   --root DIR   base para resolver os caminhos de @source (default: .)
#
# Saida: violacoes em stderr ("FILE:LINHA: mensagem"); ultima linha em
# stdout: RESULT|slides=N|specs=C/T|errors=E
# Exit: 0 sem violacao | 1 com violacao | 2 uso incorreto.
#
# POSIX sh + awk, sem jq. Read-only.

set -eu

_VP_NAME="validate-presentation"

_vp_usage() {
  cat <<'USAGE' >&2
Uso: validate-presentation.sh --story FILE --inventory FILE [--root DIR]

Valida story.md (gramatica, cobertura das specs, @source, @metric,
placeholders) contra o inventario de scan-project-docs.sh.
Exit: 0 valido; 1 violacoes (stderr, FILE:LINHA: mensagem); 2 uso.
USAGE
}

_vp_die_usage() {
  printf '%s: %s\n' "$_VP_NAME" "$1" >&2
  _vp_usage
  exit 2
}

STORY=""
INVENTORY=""
ROOT="."
while [ $# -gt 0 ]; do
  case "$1" in
    --story) [ $# -ge 2 ] || _vp_die_usage "--story exige valor"; STORY=$2; shift 2 ;;
    --inventory) [ $# -ge 2 ] || _vp_die_usage "--inventory exige valor"; INVENTORY=$2; shift 2 ;;
    --root) [ $# -ge 2 ] || _vp_die_usage "--root exige valor"; ROOT=$2; shift 2 ;;
    -h|--help) _vp_usage; exit 0 ;;
    *) _vp_die_usage "argumento desconhecido: $1" ;;
  esac
done
[ -n "$STORY" ] && [ -n "$INVENTORY" ] || _vp_die_usage "--story e --inventory sao obrigatorios"
[ -f "$STORY" ] || _vp_die_usage "story inexistente: $STORY"
[ -f "$INVENTORY" ] || _vp_die_usage "inventario inexistente: $INVENTORY"
[ -d "$ROOT" ] || _vp_die_usage "root inexistente: $ROOT"

_tmp=$(mktemp "${TMPDIR:-/tmp}/validate-presentation.XXXXXX")
trap 'rm -f "$_tmp"' EXIT INT TERM

# Registros emitidos pelo awk (TAB-separados):
#   ERR<TAB>linha<TAB>mensagem
#   SRC<TAB>linha<TAB>caminho
#   SUM<TAB>slides<TAB>cobertas<TAB>total
awk -F '\t' '
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
function err(ln, msg) { printf "ERR\t%d\t%s\n", ln, msg }
function close_slide(   k) {
  if (stype == "") return
  if (stype == "spec") {
    if (h3 != 4) err(sline, "spec " skey ": esperado 4 secoes ###, obtido " h3)
  }
  if ((stype == "spec" || stype == "briefing" || stype == "constitution") && nsrc == 0)
    err(sline, "slide " stype " sem @source")
}
BEGIN {
  split("cover manifesto briefing constitution chapter spec timeline numbers closing sources", t, " ")
  for (i in t) types[t[i]] = 1
  split("tasks tasks-done tasks-total clarify-sessions clarify-questions artifacts converge date stage status", t, " ")
  for (i in t) mspec[t[i]] = 1
  split("specs specs-active specs-archived specs-living tasks tasks-done tasks-total clarify-questions principles constitution-version", t, " ")
  for (i in t) mglobal[t[i]] = 1
}
# ---- inventario ----
FNR == NR {
  if ($1 == "spec") { inv[$2] = 1; ninv++ }
  else if ($1 == "briefing") has_briefing = 1
  else if ($1 == "constitution") has_const = 1
  next
}
# ---- story ----
FNR == 1 {
  if ($0 != "---") { err(1, "frontmatter: arquivo deve comecar com ---"); fm = 2 }
  else { fm = 1; next }
}
fm == 1 {
  if ($0 == "---") { fm = 2; next }
  p = index($0, ":")
  if (p > 0) front[trim(substr($0, 1, p - 1))] = trim(substr($0, p + 1))
  next
}
{
  line = $0
  # placeholders (G-10)
  if (index(line, "{{") > 0) err(FNR, "placeholder: {{")
  if (line ~ /(^|[^A-Za-z])TODO([^A-Za-z]|$)/) err(FNR, "placeholder: TODO")
  if (line ~ /(^|[^A-Za-z])TBD([^A-Za-z]|$)/) err(FNR, "placeholder: TBD")
  if (index(line, "[PREENCHER") > 0) err(FNR, "placeholder: [PREENCHER")
  if (index(line, "NEEDS CLARIFICATION") > 0) err(FNR, "placeholder: NEEDS CLARIFICATION")
  if (index(tolower(line), "lorem ipsum") > 0) err(FNR, "placeholder: lorem ipsum")
}
/^<!-- slide:/ {
  close_slide()
  body = line
  sub(/^<!-- slide:[ ]*/, "", body)
  sub(/[ ]*-->[ ]*$/, "", body)
  n = split(body, parts, " ")
  stype = parts[1]; skey = ""; h3 = 0; nsrc = 0; sline = FNR
  for (i = 2; i <= n; i++) {
    if (parts[i] ~ /^key=/) skey = substr(parts[i], 5)
    else if (parts[i] != "") err(FNR, "atributo desconhecido: " parts[i])
  }
  nslides++
  order[nslides] = stype
  oline[nslides] = FNR
  if (!(stype in types)) { err(FNR, "tipo de slide desconhecido: " stype) }
  count[stype]++
  if (stype == "spec") {
    if (skey == "") err(FNR, "slide spec sem key=")
    else if (!(skey in inv)) err(FNR, "key desconhecida: " skey)
    else if (skey in covered) err(FNR, "key duplicada: " skey)
    else covered[skey] = FNR
  } else if (skey != "") {
    err(FNR, "key= so e permitido em slide spec")
  }
  next
}
/^[ \t]*<!--.*-->[ \t]*$/ { next }
{
  if (nslides == 0) {
    if (trim(line) != "") err(FNR, "conteudo fora de slide")
    next
  }
}
/^### / { h3++ }
/^@/ {
  d = line
  sub(/^@/, "", d)
  name = d
  sub(/[ \t].*$/, "", name)
  arg = trim(substr(d, length(name) + 1))
  if (name == "metric") {
    p = index(arg, "|")
    if (p == 0) { err(FNR, "@metric sem separador |") ; next }
    key = trim(substr(arg, p + 1))
    label = trim(substr(arg, 1, p - 1))
    if (label == "") err(FNR, "@metric sem rotulo")
    if (stype == "spec") { if (!(key in mspec)) err(FNR, "@metric chave invalida: " key) }
    else if (!(key in mglobal)) err(FNR, "@metric chave invalida: " key)
  } else if (name == "source") {
    if (arg == "") err(FNR, "@source sem caminho")
    else { nsrc++; printf "SRC\t%d\t%s\n", FNR, arg }
  } else if (name == "timeline" || name == "sources") {
    # sem argumento
  } else {
    err(FNR, "diretiva desconhecida: @" name)
  }
}
END {
  close_slide()
  if (fm != 2) err(1, "frontmatter: sem fechamento ---")
  if (!("title" in front) || front["title"] == "") err(1, "frontmatter: title obrigatorio")
  if (!("lang" in front)) err(1, "frontmatter: lang obrigatorio")
  else if (front["lang"] != "pt-BR" && front["lang"] != "en") err(1, "frontmatter: lang deve ser pt-BR ou en")
  if (nslides == 0) err(1, "nenhum slide")
  else {
    if (count["cover"] != 1) err(1, "cover deve aparecer exatamente uma vez (obtido " count["cover"] + 0 ")")
    else if (order[1] != "cover") err(oline[1], "cover deve ser o primeiro slide")
    if (count["sources"] != 1) err(1, "sources deve aparecer exatamente uma vez (obtido " count["sources"] + 0 ")")
    else if (order[nslides] != "sources") err(oline[nslides], "sources deve ser o ultimo slide")
    if (count["closing"] < 1) err(1, "falta slide closing")
    if (has_briefing && count["briefing"] < 1) err(1, "falta slide briefing (inventario tem briefing)")
    if (has_const && count["constitution"] < 1) err(1, "falta slide constitution (inventario tem constitution)")
  }
  nc = 0
  for (k in inv) {
    if (k in covered) nc++
    else missing[k] = 1
  }
  for (k in missing) err(1, "spec sem slide: " k)
  printf "SUM\t%d\t%d\t%d\n", nslides, nc, ninv
}
' "$INVENTORY" "$STORY" > "$_tmp"

_errors=0
_sum=""
while IFS="	" read -r _kind _a _b _c; do
  case "$_kind" in
    ERR)
      printf '%s:%s: %s\n' "$STORY" "$_a" "$_b" >&2
      _errors=$((_errors + 1))
      ;;
    SRC)
      if [ ! -e "$ROOT/$_b" ]; then
        printf '%s:%s: @source inexistente: %s\n' "$STORY" "$_a" "$_b" >&2
        _errors=$((_errors + 1))
      fi
      ;;
    SUM)
      _sum="slides=$_a|specs=$_b/$_c"
      ;;
  esac
done < "$_tmp"

printf 'RESULT|%s|errors=%d\n' "$_sum" "$_errors"
[ "$_errors" -eq 0 ] || exit 1
exit 0
