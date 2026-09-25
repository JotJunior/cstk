#!/bin/sh
# render-presentation.sh — transforma story.md + inventario em um index.html
# autocontido (CSS e JS inline, fontes do sistema, zero rede) seguindo o
# template fixo da skill `presentation`. Deterministico: mesmas entradas,
# saida identica byte a byte.
#
# Ref: docs/specs/presentation/contracts/slide-grammar.md (R-01..R-05)
#      docs/specs/presentation/contracts/cli-invocation.md
#      plugins/cstk/skills/presentation/references/slide-grammar.md
#
# Uso:
#   render-presentation.sh --story FILE --inventory FILE --out FILE [--templates DIR]
#
#   --templates DIR  default: <dir-do-script>/../templates (presentation.html,
#                    theme.css, deck.js)
#
# Nao valida semantica (papel de validate-presentation.sh). Todo texto da
# story e escapado antes da formatacao inline; nenhum HTML cru do redator
# chega ao deck.
#
# Saida: RENDERED|<out>|slides=N em stdout.
# Exit: 0 sucesso | 1 story sem frontmatter/slides | 2 uso incorreto.
#
# POSIX sh + awk, sem jq.

set -eu

_RP_NAME="render-presentation"

_rp_usage() {
  cat <<'USAGE' >&2
Uso: render-presentation.sh --story FILE --inventory FILE --out FILE [--templates DIR]

Renderiza story.md + inventario em um HTML unico e offline.
Exit: 0 sucesso; 1 story sem frontmatter/slides; 2 uso incorreto.
USAGE
}

_rp_die_usage() {
  printf '%s: %s\n' "$_RP_NAME" "$1" >&2
  _rp_usage
  exit 2
}

_RP_DIR=$(cd "$(dirname "$0")" && pwd)
STORY=""
INVENTORY=""
OUT=""
TEMPLATES="$_RP_DIR/../templates"
while [ $# -gt 0 ]; do
  case "$1" in
    --story) [ $# -ge 2 ] || _rp_die_usage "--story exige valor"; STORY=$2; shift 2 ;;
    --inventory) [ $# -ge 2 ] || _rp_die_usage "--inventory exige valor"; INVENTORY=$2; shift 2 ;;
    --out) [ $# -ge 2 ] || _rp_die_usage "--out exige valor"; OUT=$2; shift 2 ;;
    --templates) [ $# -ge 2 ] || _rp_die_usage "--templates exige valor"; TEMPLATES=$2; shift 2 ;;
    -h|--help) _rp_usage; exit 0 ;;
    *) _rp_die_usage "argumento desconhecido: $1" ;;
  esac
done
[ -n "$STORY" ] && [ -n "$INVENTORY" ] && [ -n "$OUT" ] \
  || _rp_die_usage "--story, --inventory e --out sao obrigatorios"
[ -f "$STORY" ] || _rp_die_usage "story inexistente: $STORY"
[ -f "$INVENTORY" ] || _rp_die_usage "inventario inexistente: $INVENTORY"
for _t in presentation.html theme.css deck.js; do
  [ -f "$TEMPLATES/$_t" ] || _rp_die_usage "template ausente: $TEMPLATES/$_t"
done
_outdir=$(dirname "$OUT")
[ -d "$_outdir" ] || _rp_die_usage "diretorio de saida inexistente: $_outdir"

_slides=$(mktemp "${TMPDIR:-/tmp}/render-presentation.XXXXXX")
_meta=$(mktemp "${TMPDIR:-/tmp}/render-presentation.XXXXXX")
_html=$(mktemp "$_outdir/.index.html.XXXXXX")
trap 'rm -f "$_slides" "$_meta" "$_html"' EXIT INT TERM

# ---------------------------------------------------------------------------
# Passo 1: story + inventario -> <section>s (em $_slides) + metadados (em $_meta)
# ---------------------------------------------------------------------------
awk -F '\t' -v META="$_meta" '
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
function esc(s) {
  gsub(/&/, "\\&amp;", s); gsub(/</, "\\&lt;", s); gsub(/>/, "\\&gt;", s); gsub(/"/, "\\&quot;", s)
  return s
}
function pairs(s, mk, tag,   out, p, q, rest, L) {
  L = length(mk); out = ""
  while ((p = index(s, mk)) > 0) {
    rest = substr(s, p + L); q = index(rest, mk)
    if (q <= 1) break
    out = out substr(s, 1, p - 1) "<" tag ">" substr(rest, 1, q - 1) "</" tag ">"
    s = substr(rest, q + L)
  }
  return out s
}
function emph(s) { return pairs(pairs(s, "**", "strong"), "*", "em") }
function inline(s,   out, p, q, rest) {
  s = esc(s); out = ""
  while ((p = index(s, "`")) > 0) {
    rest = substr(s, p + 1); q = index(rest, "`")
    if (q == 0) break
    out = out emph(substr(s, 1, p - 1)) "<code>" substr(rest, 1, q - 1) "</code>"
    s = substr(rest, q + 1)
  }
  return out emph(s)
}
function plain(s) { gsub(/[`*]/, "", s); return esc(s) }
function L(k) { return (lang == "en") ? EN[k] : PT[k] }
function na() { return "<span class=\"na\">" L("na") "</span>" }
function val(v) { return (v == "" || v == "-") ? na() : esc(v) }
function stage_label(s) { return (("stage_" s) in PT) ? L("stage_" s) : esc(s) }
function status_label(s) { return (("status_" s) in PT) ? L("status_" s) : esc(s) }
function conv_label(s) { return (("conv_" s) in PT) ? L("conv_" s) : val(s) }
function count_list(s,   n, a) { if (s == "-" || s == "") return "-"; return split(s, a, ",") "" }
function ratio(d, t) { return (d == "-" || t == "-" || d == "" || t == "") ? na() : esc(d) "<span class=\"metric__of\">/" esc(t) "</span>" }
function metric(key, k) {
  if (stype == "spec" && k != "" && (k in S_status)) {
    if (key == "tasks") return ratio(S_done[k], S_total[k])
    if (key == "tasks-done") return val(S_done[k])
    if (key == "tasks-total") return val(S_total[k])
    if (key == "clarify-sessions") return val(S_cs[k])
    if (key == "clarify-questions") return val(S_cq[k])
    if (key == "artifacts") return val(count_list(S_arts[k]))
    if (key == "converge") return conv_label(S_conv[k])
    if (key == "date") return val(S_date[k])
    if (key == "stage") return stage_label(S_stage[k])
    if (key == "status") return status_label(S_status[k])
    return na()
  }
  if (key == "specs") return val(T[1])
  if (key == "specs-active") return val(T[2])
  if (key == "specs-archived") return val(T[3])
  if (key == "specs-living") return val(T[4])
  if (key == "tasks") return ratio(T[5], T[6])
  if (key == "tasks-done") return val(T[5])
  if (key == "tasks-total") return val(T[6])
  if (key == "clarify-questions") return val(T[7])
  if (key == "principles") return val(T[8])
  if (key == "constitution-version") return val(const_version)
  return na()
}

# ---- blocos de texto dentro do slide corrente ----
function target_add(h) {
  if (ncards > 0) card_body[ncards] = card_body[ncards] h
  else lead = lead h
}
function flush_par() {
  if (par != "") { target_add("<p>" inline(par) "</p>\n"); par = "" }
}
function flush_list() {
  if (inlist) { target_add("</ul>\n"); inlist = 0 }
}
function flush_quote() {
  if (quote != "") {
    if (stype == "cover" && ncards == 0) tagline = tagline "<blockquote class=\"tagline\"><p>" inline(quote) "</p></blockquote>\n"
    else target_add("<blockquote class=\"pull\"><p>" inline(quote) "</p></blockquote>\n")
    quote = ""
  }
}
function flush_all() { flush_par(); flush_list(); flush_quote() }

function start_slide(hdr,   body, n, parts, i) {
  body = hdr
  sub(/^<!-- slide:[ ]*/, "", body); sub(/[ ]*-->[ ]*$/, "", body)
  n = split(body, parts, " ")
  stype = parts[1]; skey = ""
  for (i = 2; i <= n; i++) if (parts[i] ~ /^key=/) skey = substr(parts[i], 5)
  nslide++
  h1 = ""; h1plain_cur = ""; h2 = ""; h2plain = ""; sub2 = ""; lead = ""; tagline = ""; ncards = 0
  metrics = ""; nmetrics = 0; sources = ""; special = ""
  par = ""; inlist = 0; quote = ""; in_slide = 1
  delete card_title; delete card_body; delete card_strong
}

function eyebrow() {
  if (stype == "cover") return esc(project)
  if (stype == "manifesto") return L("manifesto")
  if (stype == "briefing") return L("briefing")
  if (stype == "constitution") return L("constitution") ((const_version != "" && const_version != "-") ? " &middot; <span class=\"nocase\">v" esc(const_version) "</span>" : "")
  if (stype == "chapter") return L("chapter") " " sprintf("%02d", nchapter)
  if (stype == "spec") {
    if (!(skey in S_status)) return esc(skey)
    return ((chapter_title != "") ? chapter_title : status_label(S_status[skey])) ((S_date[skey] != "-") ? " &middot; " esc(S_date[skey]) : "")
  }
  return L(stype)
}

function timeline_html(   i, k, out, cur, grp, open) {
  out = "<ol class=\"timeline\">\n"; cur = ""; open = 0
  for (i = 1; i <= nspec; i++) {
    k = S_order[i]
    if (S_status[k] == "living") continue
    if (S_status[k] == "archived") grp = (S_date[k] == "-") ? L("origins") : esc(S_date[k])
    else grp = L("inprogress")
    if (grp != cur) {
      if (open) out = out "</ul></li>\n"
      out = out "<li class=\"timeline__group\"><span class=\"timeline__date\">" grp "</span><ul class=\"timeline__specs\">"
      cur = grp; open = 1
    }
    out = out "<li class=\"stage-" esc(S_stage[k]) "\">" esc(S_title[k]) "</li>"
  }
  if (open) out = out "</ul></li>\n"
  return out "</ol>\n"
}

function sources_html(   i, k, out) {
  out = "<div class=\"source-index\">\n"
  if (briefing_path != "" || const_path != "") {
    out = out "<section><h3>" L("foundation") "</h3><ul>"
    if (briefing_path != "") out = out "<li><code>" esc(briefing_path) "</code><span>" L("briefing") "</span></li>"
    if (const_path != "") out = out "<li><code>" esc(const_path) "</code><span>" L("constitution") "</span></li>"
    out = out "</ul></section>\n"
  }
  if (nspec > 0) {
    out = out "<section><h3>" L("specs") "</h3><ul>"
    for (i = 1; i <= nspec; i++) {
      k = S_order[i]
      out = out "<li><code>" esc(S_path[k]) "</code><span>" esc(S_title[k]) "</span></li>"
    }
    out = out "</ul></section>\n"
  }
  return out "</div>\n"
}

function end_slide(   i, cls, attrs, title, out, stage, body_cls) {
  if (!in_slide) return
  flush_all()
  if (stype == "chapter") { nchapter++; chapter_title = h2plain }
  title = (h1plain_cur != "") ? h1plain_cur : h2plain
  cls = "slide slide--" esc(stype)
  attrs = ""
  if (stype == "spec" && (skey in S_status)) {
    stage = S_stage[skey]
    cls = cls " stage-" esc(stage)
    attrs = " data-key=\"" esc(skey) "\" data-stage=\"" esc(stage) "\""
  }
  out = "<section class=\"" cls "\" id=\"slide-" nslide "\" data-index=\"" nslide "\" data-type=\"" esc(stype) "\" data-title=\"" title "\"" attrs ">\n"
  out = out "<div class=\"slide__frame\">\n"
  if (stype == "chapter") out = out "<span class=\"chapter__numeral\" aria-hidden=\"true\">" sprintf("%02d", nchapter) "</span>\n"
  out = out "<header class=\"slide__header\">\n<p class=\"eyebrow\">" eyebrow() "</p>\n"
  if (stype == "spec" && (skey in S_status)) out = out "<span class=\"badge badge--" esc(stage) "\">" stage_label(stage) "</span>\n"
  if (h1 != "") out = out "<h1 class=\"slide__title slide__title--hero\">" h1 "</h1>\n"
  if (h2 != "") {
    if (stype == "cover") out = out "<p class=\"slide__subtitle\">" h2 "</p>\n"
    else out = out "<h2 class=\"slide__title\">" h2 "</h2>\n"
  }
  out = out "</header>\n"
  body_cls = "slide__body"
  out = out "<div class=\"" body_cls "\">\n"
  if (lead != "") out = out "<div class=\"lead\">\n" lead "</div>\n"
  if (tagline != "") out = out tagline
  if (ncards > 0) {
    out = out "<div class=\"cards cards--" ncards "\">\n"
    for (i = 1; i <= ncards; i++) {
      out = out "<article class=\"card" (card_strong[i] ? " card--strong" : "") "\">\n"
      if (stype == "spec") out = out "<span class=\"card__index\">" sprintf("%02d", i) "</span>\n"
      if (card_strong[i]) out = out "<span class=\"card__flag\">" L("nonneg") "</span>\n"
      out = out "<h3 class=\"card__title\">" card_title[i] "</h3>\n"
      out = out "<div class=\"card__body\">\n" card_body[i] "</div>\n</article>\n"
    }
    out = out "</div>\n"
  }
  if (special != "") out = out special
  if (metrics != "") out = out "<div class=\"metrics metrics--" nmetrics "\">\n" metrics "</div>\n"
  out = out "</div>\n"
  if (sources != "") out = out "<footer class=\"slide__footer\"><span class=\"slide__footer-label\">" L("source") "</span>" sources "</footer>\n"
  out = out "</div>\n</section>\n"
  printf "%s", out
  in_slide = 0
}

BEGIN {
  PT["na"] = "n&atilde;o registrado";       EN["na"] = "not recorded"
  PT["manifesto"] = "Manifesto";            EN["manifesto"] = "Manifesto"
  PT["briefing"] = "Briefing";              EN["briefing"] = "Briefing"
  PT["constitution"] = "Constitui&ccedil;&atilde;o"; EN["constitution"] = "Constitution"
  PT["chapter"] = "Cap&iacute;tulo";        EN["chapter"] = "Chapter"
  PT["timeline"] = "Linha do tempo";        EN["timeline"] = "Timeline"
  PT["numbers"] = "Em n&uacute;meros";      EN["numbers"] = "By the numbers"
  PT["closing"] = "Horizonte";              EN["closing"] = "Horizon"
  PT["sources"] = "Fontes";                 EN["sources"] = "Sources"
  PT["source"] = "Fonte";                   EN["source"] = "Source"
  PT["foundation"] = "Funda&ccedil;&atilde;o"; EN["foundation"] = "Foundation"
  PT["specs"] = "Specs";                    EN["specs"] = "Specs"
  PT["origins"] = "Origens";                EN["origins"] = "Origins"
  PT["inprogress"] = "Em andamento";        EN["inprogress"] = "In progress"
  PT["nonneg"] = "Inegoci&aacute;vel";      EN["nonneg"] = "Non-negotiable"
  PT["stage_implemented"] = "Implementada"; EN["stage_implemented"] = "Implemented"
  PT["stage_in-progress"] = "Em andamento"; EN["stage_in-progress"] = "In progress"
  PT["stage_specified"] = "Especificada";   EN["stage_specified"] = "Specified"
  PT["stage_archived"] = "Arquivada";       EN["stage_archived"] = "Archived"
  PT["stage_living"] = "Spec viva";         EN["stage_living"] = "Living spec"
  PT["status_active"] = "Ativa";            EN["status_active"] = "Active"
  PT["status_archived"] = "Arquivada";      EN["status_archived"] = "Archived"
  PT["status_living"] = "Spec viva";        EN["status_living"] = "Living spec"
  PT["conv_clean"] = "convergida";          EN["conv_clean"] = "converged"
  PT["conv_actionable"] = "com pend&ecirc;ncias"; EN["conv_actionable"] = "actionable"
  PT["conv_risk-accepted"] = "risco aceito"; EN["conv_risk-accepted"] = "risk accepted"
}

# ---- inventario ----
FNR == NR {
  if ($1 == "project") project = $2
  else if ($1 == "briefing") briefing_path = $2
  else if ($1 == "constitution") { const_path = $2; const_version = $4 }
  else if ($1 == "totals") { for (i = 2; i <= 9; i++) T[i - 1] = $i }
  else if ($1 == "spec") {
    k = $2; nspec++; S_order[nspec] = k
    S_status[k] = $3; S_date[k] = $4; S_stage[k] = $5; S_arts[k] = $6
    S_cs[k] = $7; S_cq[k] = $8; S_done[k] = $9; S_total[k] = $10
    S_conv[k] = $11; S_path[k] = $13; S_title[k] = $14
  }
  next
}

# ---- story: frontmatter ----
FNR == 1 && $0 == "---" { fm = 1; next }
fm == 1 {
  if ($0 == "---") { fm = 2; lang = (front["lang"] == "en") ? "en" : "pt-BR"; if (front["project"] != "") project = front["project"]; next }
  p = index($0, ":")
  if (p > 0) front[trim(substr($0, 1, p - 1))] = trim(substr($0, p + 1))
  next
}

/^<!-- slide:/ { end_slide(); start_slide($0); next }
!in_slide { next }
/^[ \t]*<!--.*-->[ \t]*$/ { next }

{
  line = $0
  sub(/[ \t]+$/, "", line)
}
line == "" { flush_all(); next }
/^# / {
  flush_all(); t = substr(line, 3); h1 = inline(t); h1plain_cur = plain(t); next
}
/^## / {
  flush_all(); t = substr(line, 4); h2 = inline(t); h2plain = plain(t); next
}
/^### / {
  flush_all(); t = substr(line, 5)
  ncards++; card_title[ncards] = inline(t); card_body[ncards] = ""
  u = toupper(t)
  card_strong[ncards] = (stype == "constitution" && (index(u, "NON-NEGOTIABLE") > 0 || index(u, "INEGOCI") > 0)) ? 1 : 0
  if (card_strong[ncards]) {
    sub(/[ ]*[(][^)]*([Nn][Oo][Nn]-[Nn][Ee][Gg][Oo][Tt][Ii][Aa][Bb][Ll][Ee]|[Ii][Nn][Ee][Gg][Oo][Cc][Ii])[^)]*[)]/, "", t)
    card_title[ncards] = inline(t)
  }
  next
}
/^- / {
  flush_par(); flush_quote()
  if (!inlist) { target_add("<ul>\n"); inlist = 1 }
  target_add("<li>" inline(substr(line, 3)) "</li>\n")
  next
}
/^> ?/ {
  flush_par(); flush_list()
  t = line; sub(/^> ?/, "", t)
  quote = (quote == "") ? t : quote " " t
  next
}
/^@metric[ \t]/ {
  flush_all()
  t = substr(line, 8); p = index(t, "|")
  lbl = trim(substr(t, 1, p - 1)); key = trim(substr(t, p + 1))
  v = metric(key, skey)
  nmetrics++
  metrics = metrics "<div class=\"metric\"><span class=\"metric__value\">" v "</span><span class=\"metric__label\">" inline(lbl) "</span></div>\n"
  next
}
/^@source[ \t]/ {
  flush_all()
  t = trim(substr(line, 8))
  sources = sources "<code>" esc(t) "</code>"
  next
}
/^@timeline[ \t]*$/ { flush_all(); special = special timeline_html(); next }
/^@sources[ \t]*$/ { flush_all(); special = special sources_html(); next }
{
  flush_list(); flush_quote()
  par = (par == "") ? line : par " " line
}
END {
  end_slide()
  lang_out = (lang == "") ? "pt-BR" : lang
  printf "fm\t%d\n", fm > META
  printf "slides\t%d\n", nslide > META
  printf "lang\t%s\n", lang_out > META
  printf "title\t%s\n", esc(front["title"]) > META
  printf "subtitle\t%s\n", esc(front["subtitle"]) > META
  printf "project\t%s\n", esc(project) > META
  printf "generated\t%s\n", esc(front["generated"]) > META
}
' "$INVENTORY" "$STORY" > "$_slides"

_meta_get() {
  awk -F '\t' -v k="$1" '$1 == k { print $2; exit }' "$_meta"
}

if [ "$(_meta_get fm)" != "2" ]; then
  printf '%s: story sem frontmatter valido: %s\n' "$_RP_NAME" "$STORY" >&2
  exit 1
fi
_nslides=$(_meta_get slides)
if [ "${_nslides:-0}" -eq 0 ]; then
  printf '%s: story sem slides: %s\n' "$_RP_NAME" "$STORY" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Passo 2: costura template + CSS + JS + slides em um unico arquivo
# ---------------------------------------------------------------------------
awk -v CSS="$TEMPLATES/theme.css" -v JS="$TEMPLATES/deck.js" -v SLIDES="$_slides" -v META="$_meta" '
function cat_file(f,   l) { while ((getline l < f) > 0) print l; close(f) }
function repl(s, from, to,   out, p) {
  out = ""
  while ((p = index(s, from)) > 0) { out = out substr(s, 1, p - 1) to; s = substr(s, p + length(from)) }
  return out s
}
BEGIN {
  FS = "\t"
  while ((getline l < META) > 0) { split(l, kv, "\t"); M[kv[1]] = kv[2] }
  close(META)
  pt = (M["lang"] != "en")
  U["{{UI_SLIDES}}"]   = pt ? "Slides" : "Slides"
  U["{{UI_REPORT}}"]   = pt ? "Relat&oacute;rio" : "Report"
  U["{{UI_THEME}}"]    = pt ? "Tema" : "Theme"
  U["{{UI_PRINT}}"]    = pt ? "Imprimir" : "Print"
  U["{{UI_CONTENTS}}"] = pt ? "Sum&aacute;rio" : "Contents"
  U["{{UI_HELP}}"]     = pt ? "&larr; &rarr; navegar &middot; R relat&oacute;rio &middot; T tema &middot; F tela cheia &middot; P imprimir" : "&larr; &rarr; navigate &middot; R report &middot; T theme &middot; F fullscreen &middot; P print"
}
$0 == "{{CSS}}" { cat_file(CSS); next }
$0 == "{{JS}}" { cat_file(JS); next }
$0 == "{{SLIDES}}" { cat_file(SLIDES); next }
{
  s = $0
  s = repl(s, "{{TITLE}}", M["title"])
  s = repl(s, "{{SUBTITLE}}", M["subtitle"])
  s = repl(s, "{{PROJECT}}", M["project"])
  s = repl(s, "{{LANG}}", M["lang"])
  s = repl(s, "{{GENERATED}}", M["generated"])
  for (k in U) s = repl(s, k, U[k])
  print s
}
' "$TEMPLATES/presentation.html" > "$_html"

chmod 644 "$_html"
mv "$_html" "$OUT"
printf 'RENDERED|%s|slides=%s\n' "$OUT" "$_nslides"
