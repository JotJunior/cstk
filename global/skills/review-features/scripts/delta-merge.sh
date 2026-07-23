#!/bin/sh
# delta-merge.sh — aplica atomicamente a secao "## Delta Requirements" de um
# spec.md ao corpus (docs/specs/current/<slug>.md), por capability.
#
# Ref: docs/specs/living-specs/spec.md FR-002..FR-008
#      docs/specs/living-specs/contracts/delta-merge-cli.md
#      docs/specs/living-specs/contracts/corpus-format.md
#
# Uso:
#   delta-merge.sh SPEC_MD --feature NAME [--corpus-dir DIR] \
#     [--date YYYY-MM-DD] [--dry-run]
#
# Saida (stdout):
#   FINDING|<severity>|<code>|<mensagem>
#   RESULT|<spec>|delta=<applied|skip|blocked>|added=<N>|modified=<N>|removed=<N>|renamed=<N>
#
# Exit: 0 aplicado (ou dry-run valido, ou skip); 1 bloqueado (corpus intacto);
#       2 uso incorreto / SPEC_MD inexistente.
#
# POSIX sh puro (`set -eu`), zero jq (Constitution II). REUSA o parser da
# secao delta e o scanner estrutural do corpus de delta-gate.sh via source
# same-dir (contracts/delta-merge-cli.md §Comportamento item 1 — "mesma
# gramatica do contrato delta-section-format"; nao duplica a gramatica).

set -eu

_DM_SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
_DM_NAME="delta-merge"

# shellcheck source=./_diag.sh
. "$_DM_SCRIPT_DIR/_diag.sh"

# Reusa delta-gate.sh apenas como biblioteca de funcoes (parser + scanner +
# validacao referencial + resolucao de corpus-dir + slug). _DG_SOURCED=1
# pula a secao "main" de delta-gate.sh (sem parse de argv, sem exit).
_DG_SOURCED=1
# shellcheck source=./delta-gate.sh
. "$_DM_SCRIPT_DIR/delta-gate.sh"

_dm_usage() {
  cat <<'USAGE' >&2
Uso: delta-merge.sh SPEC_MD --feature NAME [--corpus-dir DIR] \
       [--date YYYY-MM-DD] [--dry-run]

Aplica a secao "## Delta Requirements" de SPEC_MD ao corpus
(docs/specs/current/<slug>.md), por capability, de forma atomica
(mktemp + mv, so apos validacao TOTAL de todas as capabilities).

  --feature NAME      short-name gravado como proveniencia (obrigatorio)
  --corpus-dir DIR    mesma resolucao de delta-gate.sh
  --date YYYY-MM-DD   data de proveniencia (default: data corrente UTC)
  --dry-run           valida e reporta o que SERIA aplicado; zero escrita

Saida: FINDING|<severity>|<code>|<mensagem> + RESULT final.
Exit: 0 aplicado/skip/dry-run valido; 1 bloqueado; 2 uso incorreto.
USAGE
}

# _dm_render_capability CAP CORPUS_DIR ENTRIES_FILE FEATURE DATE
# Le o arquivo de corpus existente (se houver) + as entradas ENTRY desta
# capability, e imprime em stdout o CONTEUDO RENDERIZADO completo do novo
# arquivo, mais uma linha final "%%COUNTS%%|<added>|<modified>|<removed>|<renamed>".
# Read-only sobre o corpus (nunca escreve — quem grava e o caller, via mktemp+mv).
_dm_render_capability() {
  _dmr_cap="$1"
  _dmr_corpus_file="$2/$1.md"
  _dmr_entries="$3"
  _dmr_feature="$4"
  _dmr_date="$5"
  _dmr_existing="/dev/null"
  [ -f "$_dmr_corpus_file" ] && _dmr_existing="$_dmr_corpus_file"

  awk -v capslug="$_dmr_cap" -v feature="$_dmr_feature" -v date="$_dmr_date" -v entriesfile="$_dmr_entries" '
    BEGIN { FS = "\t"; section = ""; cur_id = ""; body_acc = ""; pass1_open = 1 }
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    function flush_body() {
      if (cur_id != "" && section == "req") req_body[cur_id] = trim(body_acc)
      if (cur_id != "" && section == "removed") rem_body[cur_id] = trim(body_acc)
      cur_id = ""; body_acc = ""
    }
    # ---- Passe 1: le o corpus EXISTENTE (arquivo 1). Distincao por
    # FILENAME (NAO por FNR==NR — esse idioma falha quando o arquivo 1 e
    # vazio/inexistente (/dev/null), pois NR nao avanca e a 1a linha do
    # arquivo 2 tambem casaria FNR==NR). `pass1_open` fecha explicitamente
    # o passe 1 (flush do ultimo corpo acumulado) na PRIMEIRA linha do
    # passe 2 — sem isso, o `flush_body()` do END reflete estado STALE de
    # cur_id/body_acc do passe 1 e sobrescreve um MODIFIED aplicado no
    # passe 2 (bug real encontrado via teste manual: FR-001 modificado
    # perdia o novo texto, retendo o corpo original do corpus). ----
    FILENAME != entriesfile {
      if ($0 ~ /^## Requirements[ \t]*$/) { flush_body(); section = "req"; next }
      if ($0 ~ /^## Removed Requirements[ \t]*$/) { flush_body(); section = "removed"; next }
      if ($0 ~ /^## Renamed Identifiers[ \t]*$/) { flush_body(); section = "renamed"; next }
      if ($0 ~ /^## /) { flush_body(); section = ""; next }
      if ($0 ~ /^# Capability:/) { next }
      if (section == "req" && $0 ~ /^### FR-[0-9]+[ \t]*$/) {
        flush_body()
        cur_id = $0; sub(/^### /, "", cur_id); sub(/[ \t]+$/, "", cur_id)
        req_active[cur_id] = 1
        next
      }
      if (section == "removed" && $0 ~ /^### FR-[0-9]+ \[REMOVED\][ \t]*$/) {
        flush_body()
        cur_id = $0; sub(/^### /, "", cur_id); sub(/ \[REMOVED\].*/, "", cur_id)
        rem_set[cur_id] = 1
        next
      }
      if ((section == "req" || section == "removed") && $0 ~ /^\*Introduzida por: .*\([^)]*\)\*[ \t]*$/) {
        line = $0
        sub(/^\*Introduzida por: /, "", line); sub(/\*[ \t]*$/, "", line)
        match(line, /\(([^)]*)\)$/)
        dt = substr(line, RSTART + 1, RLENGTH - 2)
        feat = trim(substr(line, 1, RSTART - 1))
        if (section == "req") { req_intro_feat[cur_id] = feat; req_intro_date[cur_id] = dt }
        else { rem_intro_feat[cur_id] = feat; rem_intro_date[cur_id] = dt }
        next
      }
      if (section == "req" && $0 ~ /^\*Ultima modificacao: .*\([^)]*\)\*[ \t]*$/) {
        line = $0
        sub(/^\*Ultima modificacao: /, "", line); sub(/\*[ \t]*$/, "", line)
        match(line, /\(([^)]*)\)$/)
        dt = substr(line, RSTART + 1, RLENGTH - 2)
        feat = trim(substr(line, 1, RSTART - 1))
        req_mod_feat[cur_id] = feat; req_mod_date[cur_id] = dt
        next
      }
      if (section == "removed" && index($0, "*Removida por: ") == 1) {
        line = $0
        sub(/^\*Removida por: /, "", line)
        star = index(line, "*")
        meta = substr(line, 1, star - 1)
        rest = substr(line, star + 1)
        sub(/^[ \t]*—[ \t]*/, "", rest)
        match(meta, /\(([^)]*)\)$/)
        dt = substr(meta, RSTART + 1, RLENGTH - 2)
        feat = trim(substr(meta, 1, RSTART - 1))
        rem_removed_feat[cur_id] = feat; rem_removed_date[cur_id] = dt; rem_removed_motivo[cur_id] = trim(rest)
        next
      }
      if (section == "renamed" && $0 ~ /^\|/) {
        if ($0 ~ /^\|[ \t]*-+/) next
        if ($0 ~ /Antigo/ && $0 ~ /Novo/) next
        m = split($0, cols, "|")
        old = trim(cols[2]); new = trim(cols[3]); rfeat = trim(cols[4]); rdate = trim(cols[5])
        if (old != "") {
          ren_count++
          ren_old[ren_count] = old; ren_new[ren_count] = new
          ren_feat[ren_count] = rfeat; ren_date[ren_count] = rdate
        }
        next
      }
      if ((section == "req" || section == "removed") && cur_id != "" && $0 !~ /^\*/ && $0 !~ /^### / && $0 !~ /^[ \t]*$/) {
        body_acc = body_acc " " $0
        next
      }
      next
    }
    # ---- Passe 2: aplica as entradas ENTRY do delta (arquivo 2) ----
    FILENAME == entriesfile {
      if (pass1_open) { flush_body(); pass1_open = 0 }
      if ($1 != "ENTRY") next
      etype = $3; eid = $4; eid2 = $5; etext = $6
      if (etype == "ADDED") {
        req_active[eid] = 1
        req_body[eid] = etext
        req_intro_feat[eid] = feature; req_intro_date[eid] = date
        added_count++
      } else if (etype == "MODIFIED") {
        req_body[eid] = etext
        req_mod_feat[eid] = feature; req_mod_date[eid] = date
        modified_count++
      } else if (etype == "REMOVED") {
        rem_set[eid] = 1
        rem_body[eid] = req_body[eid]
        rem_intro_feat[eid] = req_intro_feat[eid]; rem_intro_date[eid] = req_intro_date[eid]
        rem_removed_feat[eid] = feature; rem_removed_date[eid] = date; rem_removed_motivo[eid] = etext
        delete req_active[eid]
        removed_count++
      } else if (etype == "RENAMED") {
        old = eid; new = eid2
        req_active[new] = 1
        req_body[new] = req_body[old]
        req_intro_feat[new] = req_intro_feat[old]; req_intro_date[new] = req_intro_date[old]
        if (old in req_mod_feat) { req_mod_feat[new] = req_mod_feat[old]; req_mod_date[new] = req_mod_date[old] }
        delete req_active[old]
        ren_count++
        ren_old[ren_count] = old; ren_new[ren_count] = new
        ren_feat[ren_count] = feature; ren_date[ren_count] = date
        renamed_count++
      }
      next
    }
    function numid(id,   n) { n = id; sub(/^FR-/, "", n); return n + 0 }
    function sort_ids(arr, n,    i, j, tmp) {
      for (i = 1; i <= n; i++)
        for (j = i + 1; j <= n; j++)
          if (numid(arr[i]) > numid(arr[j])) { tmp = arr[i]; arr[i] = arr[j]; arr[j] = tmp }
    }
    END {
      if (pass1_open) flush_body()
      print "# Capability: " capslug
      print ""
      print "> Comportamento ATUAL do sistema para esta capability. Gerado/atualizado"
      print "> exclusivamente por delta-merge.sh na acao de archive — nao editar a mao."
      print ""
      print "## Requirements"
      print ""
      nreq = 0
      for (id in req_active) { nreq++; reqids[nreq] = id }
      sort_ids(reqids, nreq)
      for (i = 1; i <= nreq; i++) {
        id = reqids[i]
        print "### " id
        print ""
        print req_body[id]
        print ""
        print "*Introduzida por: " req_intro_feat[id] " (" req_intro_date[id] ")*"
        if (id in req_mod_feat) {
          print "*Ultima modificacao: " req_mod_feat[id] " (" req_mod_date[id] ")*"
        }
        print ""
      }
      nrem = 0
      for (id in rem_set) { nrem++; remids[nrem] = id }
      if (nrem > 0) {
        sort_ids(remids, nrem)
        print "## Removed Requirements"
        print ""
        for (i = 1; i <= nrem; i++) {
          id = remids[i]
          print "### " id " [REMOVED]"
          print ""
          print rem_body[id]
          print ""
          print "*Introduzida por: " rem_intro_feat[id] " (" rem_intro_date[id] ")*"
          print "*Removida por: " rem_removed_feat[id] " (" rem_removed_date[id] ")* — " rem_removed_motivo[id]
          print ""
        }
      }
      if (ren_count > 0) {
        print "## Renamed Identifiers"
        print ""
        print "| Antigo | Novo | Feature | Data |"
        print "|--------|------|---------|------|"
        for (i = 1; i <= ren_count; i++) {
          print "| " ren_old[i] " | " ren_new[i] " | " ren_feat[i] " | " ren_date[i] " |"
        }
        print ""
      }
      printf "%%%%COUNTS%%%%|%d|%d|%d|%d\n", added_count, modified_count, removed_count, renamed_count
    }
  ' "$_dmr_existing" "$_dmr_entries"
}

# ------------------------------- main -------------------------------

SPEC_MD=""
FEATURE=""
CORPUS_DIR=""
DATE=""
DRY_RUN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --feature)
      [ $# -ge 2 ] || { _dm_usage; exit 2; }
      FEATURE=$2; shift 2 ;;
    --feature=*)
      FEATURE=${1#--feature=}; shift ;;
    --corpus-dir)
      [ $# -ge 2 ] || { _dm_usage; exit 2; }
      CORPUS_DIR=$2; shift 2 ;;
    --corpus-dir=*)
      CORPUS_DIR=${1#--corpus-dir=}; shift ;;
    --date)
      [ $# -ge 2 ] || { _dm_usage; exit 2; }
      DATE=$2; shift 2 ;;
    --date=*)
      DATE=${1#--date=}; shift ;;
    --dry-run)
      DRY_RUN=1; shift ;;
    -h|--help)
      _dm_usage; exit 2 ;;
    --*)
      printf '%s: opcao desconhecida: %s\n' "$_DM_NAME" "$1" >&2
      diag_emit error unknown-option "opcao desconhecida: $1" "consulte delta-merge.sh --help" || :
      _dm_usage; exit 2 ;;
    *)
      if [ -z "$SPEC_MD" ]; then
        SPEC_MD=$1; shift
      else
        printf '%s: argumento extra: %s\n' "$_DM_NAME" "$1" >&2
        diag_emit error extra-argument "argumento extra: $1" "delta-merge.sh aceita apenas SPEC_MD + flags" || :
        _dm_usage; exit 2
      fi ;;
  esac
done

if [ -z "$SPEC_MD" ]; then
  _dm_usage; exit 2
fi
if [ ! -f "$SPEC_MD" ]; then
  printf '%s: spec nao encontrado: %s\n' "$_DM_NAME" "$SPEC_MD" >&2
  diag_emit error spec-not-found "spec.md nao encontrado: $SPEC_MD" "verifique o path de SPEC_MD" || :
  exit 2
fi
if [ -z "$FEATURE" ]; then
  printf '%s: --feature e obrigatorio\n' "$_DM_NAME" >&2
  diag_emit error feature-missing "--feature NAME nao informado" "passe --feature <short-name> da feature que origina a mudanca" || :
  _dm_usage; exit 2
fi
if [ -z "$DATE" ]; then
  DATE=$(date -u +%Y-%m-%d)
fi

if [ -z "$CORPUS_DIR" ]; then
  if ! CORPUS_DIR=$(_dg_resolve_corpus_dir "$SPEC_MD"); then
    printf '%s: nao foi possivel resolver --corpus-dir (SPEC_MD fora da convencao docs/specs/<feature>/spec.md)\n' "$_DM_NAME" >&2
    diag_emit error corpus-dir-unresolvable "corpus-dir nao resolvido para $SPEC_MD" "passe --corpus-dir explicitamente" || :
    exit 2
  fi
fi

ERRORS=0
PARSE_OUT=$(mktemp)
trap 'rm -f "$PARSE_OUT"' EXIT
_dg_parse_spec "$SPEC_MD" > "$PARSE_OUT"

DELTA_STATUS=$(awk -F"$(printf '\t')" '$1=="__STATUS__"{print $2}' "$PARSE_OUT")

while IFS= read -r _dm_line; do
  case "$_dm_line" in
    FINDING\|error\|*)
      printf '%s\n' "$_dm_line"
      ERRORS=$((ERRORS + 1)) ;;
    FINDING\|*)
      printf '%s\n' "$_dm_line" ;;
  esac
done < "$PARSE_OUT"

if [ "$DELTA_STATUS" = "skip" ] && [ "$ERRORS" -eq 0 ]; then
  printf 'RESULT|%s|delta=skip|added=0|modified=0|removed=0|renamed=0\n' "$SPEC_MD"
  exit 0
fi

if [ "$ERRORS" -gt 0 ]; then
  printf 'RESULT|%s|delta=blocked|added=0|modified=0|removed=0|renamed=0\n' "$SPEC_MD"
  exit 1
fi

# Validacao referencial + estrutural por capability (mesma logica do gate —
# defesa em profundidade, invariante 2-ter do contrato: NUNCA confia que
# delta-gate.sh rodou antes).
CAPS=$(awk -F"$(printf '\t')" '$1=="ENTRY"{print $2}' "$PARSE_OUT" | sort -u)
for _cap in $CAPS; do
  _dg_process_capability "$_cap" "$CORPUS_DIR" "$PARSE_OUT"
done

if [ "$ERRORS" -gt 0 ]; then
  printf 'RESULT|%s|delta=blocked|added=0|modified=0|removed=0|renamed=0\n' "$SPEC_MD"
  exit 1
fi

if [ -z "$CAPS" ]; then
  printf 'RESULT|%s|delta=applied|added=0|modified=0|removed=0|renamed=0\n' "$SPEC_MD"
  exit 0
fi

TAB="$(printf '\t')"
TOTAL_ADDED=0
TOTAL_MODIFIED=0
TOTAL_REMOVED=0
TOTAL_RENAMED=0

# Fase 1: renderiza TODAS as capabilities para arquivos temporarios ANTES de
# qualquer mv (atomicidade multi-capability — invariante 3.7.6).
_pending_list=""
for _cap in $CAPS; do
  _entries=$(mktemp)
  awk -F"$TAB" -v c="$_cap" '$1=="ENTRY" && $2==c {print}' "$PARSE_OUT" > "$_entries"
  _rendered=$(mktemp)
  _dm_render_capability "$_cap" "$CORPUS_DIR" "$_entries" "$FEATURE" "$DATE" > "$_rendered"
  rm -f "$_entries"

  _counts=$(grep '^%%COUNTS%%' "$_rendered")
  _added=$(printf '%s' "$_counts" | cut -d'|' -f2)
  _modified=$(printf '%s' "$_counts" | cut -d'|' -f3)
  _removed=$(printf '%s' "$_counts" | cut -d'|' -f4)
  _renamed=$(printf '%s' "$_counts" | cut -d'|' -f5)
  TOTAL_ADDED=$((TOTAL_ADDED + _added))
  TOTAL_MODIFIED=$((TOTAL_MODIFIED + _modified))
  TOTAL_REMOVED=$((TOTAL_REMOVED + _removed))
  TOTAL_RENAMED=$((TOTAL_RENAMED + _renamed))

  _final=$(mktemp)
  grep -v '^%%COUNTS%%' "$_rendered" > "$_final"
  rm -f "$_rendered"

  _pending_list="$_pending_list $_cap:$_final"
done

if [ "$DRY_RUN" = "1" ]; then
  for _pair in $_pending_list; do
    _f=${_pair#*:}
    rm -f "$_f"
  done
  printf 'RESULT|%s|delta=applied|added=%d|modified=%d|removed=%d|renamed=%d\n' \
    "$SPEC_MD" "$TOTAL_ADDED" "$TOTAL_MODIFIED" "$TOTAL_REMOVED" "$TOTAL_RENAMED"
  exit 0
fi

mkdir -p "$CORPUS_DIR"
for _pair in $_pending_list; do
  _cap=${_pair%%:*}
  _f=${_pair#*:}
  mv "$_f" "$CORPUS_DIR/$_cap.md"
done

printf 'RESULT|%s|delta=applied|added=%d|modified=%d|removed=%d|renamed=%d\n' \
  "$SPEC_MD" "$TOTAL_ADDED" "$TOTAL_MODIFIED" "$TOTAL_REMOVED" "$TOTAL_RENAMED"
exit 0
