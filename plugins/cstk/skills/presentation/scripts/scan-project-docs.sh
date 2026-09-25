#!/bin/sh
# scan-project-docs.sh — inventario deterministico das docs SDD de um projeto
# (briefing, constitution, specs ativas/arquivadas/vivas) para a skill
# `presentation`. Os fatos da apresentacao saem daqui, nunca do redator
# (Constitution Principio VI).
#
# Ref: docs/specs/presentation/data-model.md §Inventario
#      docs/specs/presentation/contracts/cli-invocation.md
#
# Subcomandos:
#
#   scan-project-docs.sh inventory [--docs DIR]
#       Imprime o inventario TSV (um registro por linha, campos por TAB,
#       primeiro campo = tipo). Valor ausente = "-".
#
#   scan-project-docs.sh diff --old FILE --new FILE
#       Compara dois inventarios por digest e imprime
#       "estado<TAB>tipo<TAB>chave" (added|changed|removed|unchanged).
#
# POSIX sh + awk, sem jq. Read-only sobre DIR.
# Exit: 0 sucesso | 2 uso incorreto ou entrada inexistente.

set -eu

_SP_NAME="scan-project-docs"
TAB=$(printf '\t')

_sp_usage() {
  cat <<'USAGE' >&2
Uso:
  scan-project-docs.sh inventory [--docs DIR]
  scan-project-docs.sh diff --old FILE --new FILE

inventory  inventario TSV de briefing, constitution e specs (default DIR: docs)
diff       compara dois inventarios: added|changed|removed|unchanged por item
Exit: 0 sucesso; 2 uso incorreto ou entrada inexistente.
USAGE
}

_sp_die_usage() {
  printf '%s: %s\n' "$_SP_NAME" "$1" >&2
  _sp_usage
  exit 2
}

# _sp_clean -> stdin sem TAB/CR (campos TSV nunca carregam separador).
_sp_clean() {
  tr '\t\r' '  '
}

# _sp_title FILE PREFIX... -> primeiro heading "# " sem os prefixos dados.
_sp_title() {
  _f=$1
  shift
  _t=$(awk '/^# /{sub(/^# +/, ""); print; exit}' "$_f" | _sp_clean)
  for _p in "$@"; do
    case "$_t" in
      "$_p"*) _t=${_t#"$_p"} ;;
    esac
  done
  # remove espacos nas pontas
  printf '%s' "$_t" | sed 's/^ *//; s/ *$//'
}

_sp_digest_file() {
  cksum < "$1" | awk '{print $1}'
}

# _sp_digest_dir DIR -> cksum do conteudo concatenado, ordem LC_ALL=C.
_sp_digest_dir() {
  find "$1" -type f | LC_ALL=C sort | while IFS= read -r _df; do
    cat "$_df"
  done | cksum | awk '{print $1}'
}

# _sp_spec_dir KEY STATUS DATE DIR -> linha "sortkey<TAB>spec<TAB>..." em stdout
_sp_spec_dir() {
  _key=$1 _status=$2 _date=$3 _dir=${4%/}
  _arts=""
  for _a in spec plan research data-model quickstart tasks; do
    [ -f "$_dir/$_a.md" ] && _arts="$_arts,$_a"
  done
  for _a in checklists contracts; do
    [ -d "$_dir/$_a" ] && _arts="$_arts,$_a"
  done
  [ -f "$_dir/converge-report.md" ] && _arts="$_arts,converge-report"
  _arts=${_arts#,}
  [ -n "$_arts" ] || _arts="-"

  # Clarify: sessoes = headings "### Session"; perguntas = itens de pergunta
  # dentro da secao "## Clarifications" nos formatos usados pelo pipeline
  # ("- Q:", "- **Q1", "### CQ1"). Secao com perguntas mas sem heading de
  # sessao conta como 1 sessao.
  _sessions=0
  _questions=0
  if [ -f "$_dir/spec.md" ]; then
    _cq=$(awk '
      /^### Session/ { s++ }
      /^## / { inclar = ($0 ~ /^## Clarifications/) ; next }
      inclar && (/^- Q:/ || /^- \*\*Q[0-9]/ || /^### CQ[0-9]/) { q++ }
      END { if (s == 0 && q > 0) s = 1; printf "%d %d\n", s, q }' "$_dir/spec.md")
    _sessions=${_cq% *}
    _questions=${_cq#* }
  fi

  if [ -f "$_dir/tasks.md" ]; then
    _tc=$(awk '
      /^[[:space:]]*- \[[ xX~!]\] / { t++ }
      /^[[:space:]]*- \[[xX]\] /    { d++ }
      END { printf "%d %d\n", d, t }' "$_dir/tasks.md")
    _done=${_tc% *}
    _total=${_tc#* }
  else
    _done="-"
    _total="-"
  fi

  _conv="-"
  if [ -f "$_dir/converge-report.md" ]; then
    _c=$(sed -n 's/.*converge-status: outcome=\([a-z-]*\).*/\1/p' "$_dir/converge-report.md" | tail -n 1)
    [ -n "$_c" ] && _conv=$_c
  fi

  if [ "$_total" != "-" ] && [ "$_total" -gt 0 ]; then
    if [ "$_done" -eq "$_total" ]; then _stage=implemented; else _stage=in-progress; fi
  elif [ "$_status" = archived ]; then
    _stage=archived
  else
    _stage=specified
  fi

  _title=""
  [ -f "$_dir/spec.md" ] && _title=$(_sp_title "$_dir/spec.md" "Feature Specification:" "Feature Spec:")
  [ -n "$_title" ] || _title=$(basename "$_dir")

  _digest=$(_sp_digest_dir "$_dir")
  _path="$_dir"
  [ -f "$_dir/spec.md" ] && _path="$_dir/spec.md"

  _sort=$_date
  [ "$_sort" != "-" ] || _sort="0000-00-00"
  case "$_status" in
    archived) _grp=1 ;;
    active) _grp=2 ;;
    *) _grp=3 ;;
  esac

  printf '%s %s %s\tspec\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$_grp" "$_sort" "$_key" \
    "$_key" "$_status" "$_date" "$_stage" "$_arts" "$_sessions" "$_questions" \
    "$_done" "$_total" "$_conv" "$_digest" "$_path" "$_title"
}

_sp_inventory() {
  DOCS=docs
  while [ $# -gt 0 ]; do
    case "$1" in
      --docs) [ $# -ge 2 ] || _sp_die_usage "--docs exige valor"; DOCS=$2; shift 2 ;;
      --docs=*) DOCS=${1#--docs=}; shift ;;
      -h|--help) _sp_usage; exit 0 ;;
      *) _sp_die_usage "argumento desconhecido: $1" ;;
    esac
  done
  DOCS=${DOCS%/}
  [ -d "$DOCS" ] || _sp_die_usage "diretorio de docs inexistente: $DOCS"

  printf '# cstk-presentation-inventory v1\n'

  # --- project + briefing ---
  _briefing=""
  for _b in "$DOCS/briefing.md" "$DOCS/01-briefing-discovery/briefing.md"; do
    if [ -f "$_b" ]; then _briefing=$_b; break; fi
  done
  _project=""
  _btitle=""
  if [ -n "$_briefing" ]; then
    _btitle=$(_sp_title "$_briefing" "Project Briefing:" "Briefing:")
    _project=$_btitle
  fi
  if [ -z "$_project" ]; then
    _project=$(basename "$(cd "$DOCS/.." && pwd)")
  fi
  printf 'project\t%s\n' "$_project"
  if [ -n "$_briefing" ]; then
    [ -n "$_btitle" ] || _btitle="-"
    printf 'briefing\t%s\t%s\t%s\n' "$_briefing" "$(_sp_digest_file "$_briefing")" "$_btitle"
  fi

  # --- constitution + principles ---
  _nprinc=0
  _const="$DOCS/constitution.md"
  if [ -f "$_const" ]; then
    _ver=$(sed -n 's/.*\*\*Vers[a-z]*\*\*:[[:space:]]*\([0-9][0-9.]*\).*/\1/p' "$_const" | head -n 1)
    [ -n "$_ver" ] || _ver="-"
    printf 'constitution\t%s\t%s\t%s\n' "$_const" "$(_sp_digest_file "$_const")" "$_ver"
    awk '
      /^### [IVXLC]+\. / {
        line = $0
        sub(/^### /, "", line)
        numeral = line
        sub(/\..*$/, "", numeral)
        title = line
        sub(/^[IVXLC]+\.[ ]*/, "", title)
        nn = "no"
        up = toupper(title)
        if (index(up, "NON-NEGOTIABLE") > 0 || index(up, "INEGOCIAVEL") > 0) {
          nn = "yes"
          sub(/[ ]*\((NON-NEGOTIABLE|INEGOCIAVEL|non-negotiable|inegociavel)\)[ ]*$/, "", title)
        }
        gsub(/\t/, " ", title)
        n++
        printf "principle\t%d\t%s\t%s\t%s\n", n, numeral, nn, title
      }' "$_const"
    _nprinc=$(grep -c '^### [IVXLC][IVXLC]*\. ' "$_const" 2>/dev/null || true)
  fi

  # --- specs ---
  _tmp=$(mktemp "${TMPDIR:-/tmp}/scan-project-docs.XXXXXX")
  trap 'rm -f "$_tmp"' EXIT INT TERM
  _specs="$DOCS/specs"
  if [ -d "$_specs" ]; then
    for _d in "$_specs"/*/; do
      [ -d "$_d" ] || continue
      _n=$(basename "$_d")
      case "$_n" in _archived|current) continue ;; esac
      _sp_spec_dir "$_n" active - "$_d" >> "$_tmp"
    done
    if [ -d "$_specs/_archived" ]; then
      for _d in "$_specs"/_archived/*/; do
        [ -d "$_d" ] || continue
        _n=$(basename "$_d")
        _date="-"
        case "$_n" in
          [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-*) _date=$(printf '%s' "$_n" | cut -c1-10) ;;
        esac
        _sp_spec_dir "_archived/$_n" archived "$_date" "$_d" >> "$_tmp"
      done
    fi
    if [ -d "$_specs/current" ]; then
      for _f in "$_specs"/current/*.md; do
        [ -f "$_f" ] || continue
        _n=$(basename "$_f" .md)
        _t=$(_sp_title "$_f" "Capability:")
        [ -n "$_t" ] || _t=$_n
        printf '3 0000-00-00 current/%s\tspec\tcurrent/%s\tliving\t-\tliving\t-\t-\t-\t-\t-\t-\t%s\t%s\t%s\n' \
          "$_n" "$_n" "$(_sp_digest_file "$_f")" "$_f" "$_t" >> "$_tmp"
      done
    fi
  fi
  LC_ALL=C sort -t "$TAB" -k1,1 "$_tmp" | cut -f2-

  # --- totals ---
  LC_ALL=C sort -t "$TAB" -k1,1 "$_tmp" | cut -f2- | awk -F '\t' -v np="${_nprinc:-0}" '
    $1 == "spec" {
      n++
      if ($3 == "active") a++
      else if ($3 == "archived") r++
      else if ($3 == "living") l++
      if ($9 != "-") { d += $9; t += $10 }
      if ($8 != "-") q += $8
    }
    END { printf "totals\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\n", n, a, r, l, d, t, q, np }'
}

_sp_diff() {
  OLD=""
  NEW=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --old) [ $# -ge 2 ] || _sp_die_usage "--old exige valor"; OLD=$2; shift 2 ;;
      --new) [ $# -ge 2 ] || _sp_die_usage "--new exige valor"; NEW=$2; shift 2 ;;
      -h|--help) _sp_usage; exit 0 ;;
      *) _sp_die_usage "argumento desconhecido: $1" ;;
    esac
  done
  [ -n "$OLD" ] && [ -n "$NEW" ] || _sp_die_usage "diff exige --old e --new"
  [ -f "$OLD" ] || _sp_die_usage "arquivo inexistente: $OLD"
  [ -f "$NEW" ] || _sp_die_usage "arquivo inexistente: $NEW"

  awk -F '\t' '
    function item(   k) {
      if ($1 == "briefing")     { key = "briefing\tbriefing"; dg = $3; return 1 }
      if ($1 == "constitution") { key = "constitution\tconstitution"; dg = $3; return 1 }
      if ($1 == "spec")         { key = "spec\t" $2; dg = $12; return 1 }
      return 0
    }
    FNR == NR { if (item()) old[key] = dg; next }
    {
      if (!item()) next
      seen[key] = 1
      if (!(key in old)) print "added\t" key
      else if (old[key] != dg) print "changed\t" key
      else print "unchanged\t" key
    }
    END { for (k in old) if (!(k in seen)) print "removed\t" k }
  ' "$OLD" "$NEW" | LC_ALL=C sort -t "$TAB" -k2,2 -k3,3
}

[ $# -ge 1 ] || { _sp_usage; exit 2; }
_cmd=$1
shift
case "$_cmd" in
  inventory) _sp_inventory "$@" ;;
  diff) _sp_diff "$@" ;;
  -h|--help) _sp_usage; exit 0 ;;
  *) _sp_die_usage "subcomando desconhecido: $_cmd" ;;
esac
