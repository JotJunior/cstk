#!/bin/sh
# delta-gate.sh — gate deterministico, READ-ONLY: valida a secao
# `## Delta Requirements` de um spec.md contra a gramatica do contrato
# delta-section-format.md e, quando a capability referenciada ja existe no
# corpus (docs/specs/current/<slug>.md), contra a estrutura e o estado
# referencial do contrato corpus-format.md.
#
# Ref: docs/specs/living-specs/spec.md FR-010..FR-013
#      docs/specs/living-specs/contracts/delta-gate-cli.md
#      docs/specs/living-specs/contracts/delta-section-format.md
#      docs/specs/living-specs/contracts/corpus-format.md
#
# Uso:
#   delta-gate.sh SPEC_MD [--corpus-dir DIR]
#
# Saida (stdout):
#   FINDING|<severity>|<code>|<mensagem>
#   RESULT|<spec>|delta=<present|skip|missing>|errors=<N>|warnings=<M>
#
# Exit: 0 archive liberado (delta valida ou skip valido; so warnings/infos);
#       1 archive bloqueado (>=1 FINDING error);
#       2 uso incorreto / SPEC_MD inexistente / corpus-dir irresoluvel.
#
# POSIX sh puro (`set -eu`), zero jq (Constitution II). Este arquivo tambem
# e SOURCEABLE por delta-merge.sh (mesmo diretorio) para reusar o parser da
# secao delta e o scanner estrutural do corpus SEM duplicar a gramatica
# (contracts/delta-merge-cli.md §Comportamento item 1, research.md Decision
# 7 do mesmo padrao de vendoring same-dir). O caller que so quer as
# funcoes deve exportar `_DG_SOURCED=1` ANTES de `. delta-gate.sh` — nesse
# modo a secao "main" abaixo e pulada (nenhum parse de argv, nenhum exit).

set -eu

_DG_SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
_DG_SOURCED="${_DG_SOURCED:-0}"
_DG_NAME="delta-gate"

# shellcheck source=./_diag.sh
. "$_DG_SCRIPT_DIR/_diag.sh"

_dg_usage() {
  cat <<'USAGE' >&2
Uso: delta-gate.sh SPEC_MD [--corpus-dir DIR]

Valida a secao "## Delta Requirements" de SPEC_MD (gramatica de
delta-section-format.md) e, para capabilities ja existentes no corpus,
a estrutura + estado referencial de corpus-format.md. Read-only.

  --corpus-dir DIR   raiz do corpus (default: resolvida subindo de SPEC_MD
                      pela convencao docs/specs/<feature>/spec.md ate
                      docs/specs/current/; sem convencao e sem flag => exit 2)

Saida: linhas FINDING|<severity>|<code>|<mensagem> + RESULT final.
Exit: 0 liberado; 1 bloqueado (>=1 erro); 2 uso incorreto.
USAGE
}

# --- funcoes compartilhadas (tambem usadas por delta-merge.sh via source) ---

# _dg_slug_valid SLUG — exit 0 valido, 1 invalido. Padrao [a-z0-9][a-z0-9-]*
_dg_slug_valid() {
  _dgv_s="$1"
  [ -n "$_dgv_s" ] || return 1
  case "$_dgv_s" in
    [a-z0-9]*) ;;
    *) return 1 ;;
  esac
  case "$_dgv_s" in
    *[!a-z0-9-]*) return 1 ;;
  esac
  return 0
}

# _dg_in_list NEEDLE HAYSTACK(space-separated) — exit 0 se presente.
_dg_in_list() {
  case " $2 " in
    *" $1 "*) return 0 ;;
    *) return 1 ;;
  esac
}

# _dg_resolve_corpus_dir SPEC_MD -> stdout: path do corpus-dir; exit 1 se
# SPEC_MD nao segue a convencao docs/specs/<feature>/spec.md.
_dg_resolve_corpus_dir() {
  _dgr_spec="$1"
  case "$_dgr_spec" in
    */docs/specs/*/spec.md|docs/specs/*/spec.md)
      _dgr_base=${_dgr_spec%/*/spec.md}
      printf '%s/current\n' "$_dgr_base"
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# _dg_parse_spec SPEC_MD -> stdout: linhas FINDING|..., ENTRY|... (TSV,
# separador TAB), SKIP_OK|... (TSV) e uma linha final "__STATUS__\t<v>"
# com v in {missing,skip,present}. Emite o FINDING capability-slug-invalid
# como a PRIMEIRA checagem sobre cada "### Capability:" lida, ANTES de
# qualquer composicao de path com o slug (invariante 4 do contrato
# delta-gate-cli.md / tarefa 3.4.1) — nenhum path e composto aqui.
_dg_parse_spec() {
  awk '
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    function esc(s) { gsub(/\t/, " ", s); return s }
    function slug_ok(s) { return (s ~ /^[a-z0-9][a-z0-9-]*$/) }
    function flush_entry() {
      if (entry_type != "") {
        printf "ENTRY\t%s\t%s\t%s\t%s\t%s\n", cap_slug, entry_type, entry_id, entry_id2, esc(trim(entry_text))
      }
      entry_type = ""; entry_id = ""; entry_id2 = ""; entry_text = ""
    }
    BEGIN {
      in_section = 0; in_capability = 0; cap_valid = 1; cap_slug = ""
      group = ""; has_heading = 0; has_capability_block = 0
      skip_seen = 0; skip_valid = 0; skip_just = ""; skip_auth = ""; skip_date = ""
    }
    /^## Delta Requirements[ \t]*$/ {
      flush_entry()
      in_section = 1; has_heading = 1
      in_capability = 0; cap_slug = ""; group = ""
      next
    }
    /^#[ \t]/ || /^##[ \t]/ {
      if (in_section) {
        flush_entry()
        in_section = 0; in_capability = 0; cap_slug = ""; group = ""
      }
      next
    }
    !in_section { next }
    /^\*\*Skip\*\*:/ {
      flush_entry()
      skip_seen = 1
      rest = $0
      sub(/^\*\*Skip\*\*:[ \t]*/, "", rest)
      em = index(rest, "—")
      if (em == 0) {
        skip_valid = 0
      } else {
        just = trim(substr(rest, 1, em - 1))
        tail = trim(substr(rest, em + 3))
        lastcomma = 0
        for (p = length(tail); p >= 1; p--) {
          if (substr(tail, p, 1) == ",") { lastcomma = p; break }
        }
        if (lastcomma == 0) {
          skip_valid = 0
        } else {
          auth = trim(substr(tail, 1, lastcomma - 1))
          dt = trim(substr(tail, lastcomma + 1))
          if (just == "" || auth == "" || dt == "") {
            skip_valid = 0
          } else {
            skip_valid = 1; skip_just = just; skip_auth = auth; skip_date = dt
          }
        }
      }
      next
    }
    /^### Capability:[ \t]/ {
      flush_entry()
      has_capability_block = 1
      in_capability = 1; group = ""
      raw = $0
      sub(/^### Capability:[ \t]*/, "", raw)
      slug = trim(raw)
      cap_slug = slug
      if (!slug_ok(slug)) {
        printf "FINDING|error|capability-slug-invalid|slug \"%s\" fora do padrao [a-z0-9][a-z0-9-]* — capability ignorada\n", esc(slug)
        cap_valid = 0
      } else {
        cap_valid = 1
      }
      next
    }
    /^#### ADDED[ \t]*$/    { flush_entry(); group = "ADDED"; next }
    /^#### MODIFIED[ \t]*$/ { flush_entry(); group = "MODIFIED"; next }
    /^#### REMOVED[ \t]*$/  { flush_entry(); group = "REMOVED"; next }
    /^#### RENAMED[ \t]*$/  { flush_entry(); group = "RENAMED"; next }
    /^[ \t]*$/ { next }
    {
      if (!in_capability) {
        printf "FINDING|error|entry-malformed|linha inesperada fora de bloco Capability: %s\n", esc($0)
        next
      }
      if (!cap_valid) { next }
      if (group == "RENAMED") {
        if ($0 ~ /^- \*\*FR-[0-9]+ -> FR-[0-9]+\*\*[ \t]*$/) {
          flush_entry()
          line = $0
          sub(/^- \*\*/, "", line); sub(/\*\*[ \t]*$/, "", line)
          split(line, parts, " -> ")
          entry_type = "RENAMED"; entry_id = parts[1]; entry_id2 = parts[2]; entry_text = ""
          next
        } else if ($0 ~ /^  +[^ \t]/ && entry_type != "") {
          entry_text = entry_text " " trim($0)
          next
        } else {
          printf "FINDING|error|entry-malformed|entrada RENAMED invalida em %s: %s\n", cap_slug, esc($0)
          next
        }
      } else if (group == "ADDED" || group == "MODIFIED" || group == "REMOVED") {
        if ($0 ~ /^- \*\*FR-[0-9]+\*\*:/) {
          flush_entry()
          line = $0
          idpart = line
          sub(/^- \*\*/, "", idpart); sub(/\*\*:.*$/, "", idpart)
          txt = line
          sub(/^- \*\*FR-[0-9]+\*\*:[ \t]*/, "", txt)
          entry_type = group; entry_id = idpart; entry_id2 = ""; entry_text = txt
          next
        } else if ($0 ~ /^  +[^ \t]/ && entry_type != "") {
          entry_text = entry_text " " trim($0)
          next
        } else {
          printf "FINDING|error|entry-malformed|entrada invalida em #### %s de %s: %s\n", group, cap_slug, esc($0)
          next
        }
      } else {
        printf "FINDING|error|entry-malformed|linha fora de grupo #### em %s: %s\n", cap_slug, esc($0)
        next
      }
    }
    END {
      flush_entry()
      if (!has_heading) {
        printf "FINDING|error|delta-missing|secao \"## Delta Requirements\" ausente e sem marcador Skip\n"
        print "__STATUS__\tmissing"
      } else if (!skip_seen && !has_capability_block) {
        printf "FINDING|error|delta-empty|secao presente sem blocos Capability nem Skip\n"
        print "__STATUS__\tpresent"
      } else if (skip_seen && has_capability_block) {
        printf "FINDING|error|skip-with-delta|marcador Skip e blocos Capability presentes simultaneamente (mutuamente exclusivos)\n"
        print "__STATUS__\tpresent"
      } else if (skip_seen && !has_capability_block) {
        if (skip_valid) {
          printf "SKIP_OK\t%s\t%s\t%s\n", esc(skip_just), esc(skip_auth), esc(skip_date)
          print "__STATUS__\tskip"
        } else {
          printf "FINDING|error|skip-invalid|marcador Skip sem justificativa, autor ou data validos\n"
          print "__STATUS__\tpresent"
        }
      } else {
        print "__STATUS__\tpresent"
      }
    }
  ' "$1"
}

# _dg_corpus_scan CORPUS_FILE -> stdout: MALFORMED|<motivo> (0+, corte de
# processamento posterior pelo caller), ACTIVE|<id>, REMOVED|<id>,
# RENAMED_OLD|<id>, RENAMED_NEW|<id>. Read-only.
_dg_corpus_scan() {
  awk '
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    BEGIN { section = ""; seen_h1 = 0 }
    /^# Capability:[ \t]/ { seen_h1++; next }
    /^## Requirements[ \t]*$/ { section = "req"; next }
    /^## Removed Requirements[ \t]*$/ { section = "removed"; next }
    /^## Renamed Identifiers[ \t]*$/ { section = "renamed"; next }
    /^## / { section = ""; next }
    # Duplicidade: 3 sets independentes (active/removed/old-aposentado).
    # O id "Novo" de um rename COINCIDE por design com o heading ativo
    # corrente (e a mesma entidade, so o nome mudou) — NAO entra na
    # checagem de duplicidade estrutural (so no cross-check referencial
    # de _dg_process_capability, que e semantica distinta: "id ja usado").
    /^### / {
      if (section == "req") {
        if ($0 ~ /^### FR-[0-9]+[ \t]*$/) {
          id = $0; sub(/^### /, "", id); sub(/[ \t]+$/, "", id)
          if (id in active_set) printf "MALFORMED\tid duplicado: %s\n", id
          if (id in removed_set) printf "MALFORMED\tid ativo e removido simultaneamente: %s\n", id
          active_set[id] = 1
          printf "ACTIVE\t%s\n", id
        } else {
          printf "MALFORMED\theading em Requirements mal-formado: %s\n", $0
        }
      } else if (section == "removed") {
        if ($0 ~ /^### FR-[0-9]+ \[REMOVED\][ \t]*$/) {
          id = $0; sub(/^### /, "", id); sub(/ \[REMOVED\].*/, "", id)
          if (id in removed_set) printf "MALFORMED\tid duplicado: %s\n", id
          if (id in active_set) printf "MALFORMED\tid ativo e removido simultaneamente: %s\n", id
          removed_set[id] = 1
          printf "REMOVED\t%s\n", id
        } else {
          printf "MALFORMED\theading em Removed Requirements mal-formado: %s\n", $0
        }
      } else {
        printf "MALFORMED\theading ### fora de secao reconhecida: %s\n", $0
      }
      next
    }
    section == "renamed" && /^\|/ {
      if ($0 ~ /^\|[ \t]*-+/) next
      if ($0 ~ /Antigo/ && $0 ~ /Novo/) next
      n = split($0, cols, "|")
      old = trim(cols[2]); new = trim(cols[3])
      if (old != "") {
        if (old in old_set) printf "MALFORMED\tid aposentado duplicado (renamed old): %s\n", old
        if (old in active_set) printf "MALFORMED\tid aposentado ainda ativo: %s\n", old
        old_set[old] = 1
        printf "RENAMED_OLD\t%s\n", old
      }
      if (new != "") {
        if (new in new_set) printf "MALFORMED\tid renamed-target duplicado (renamed new): %s\n", new
        new_set[new] = 1
        printf "RENAMED_NEW\t%s\n", new
      }
      next
    }
    END {
      if (seen_h1 == 0) printf "MALFORMED\theading \"# Capability:\" ausente\n"
    }
  ' "$1"
}

# _dg_process_capability CAP CORPUS_DIR PARSE_OUT_FILE — le/emite FINDINGs
# via stdout e MUTA a variavel de escopo do caller ERRORS (o caller DEVE
# invocar esta funcao fora de subshell/pipe: `_dg_process_capability ...`
# direto, nunca `... | _dg_process_capability`). Ordem CHK034: structural
# ANTES de referencial (invariante 6 do contrato delta-gate-cli.md).
_dg_process_capability() {
  _dgp_cap="$1"
  _dgp_corpus_dir="$2"
  _dgp_parse_out="$3"
  _dgp_corpus_file="$_dgp_corpus_dir/$_dgp_cap.md"
  _dgp_tab="$(printf '\t')"
  _dgp_entries=$(mktemp)
  awk -F"$_dgp_tab" -v c="$_dgp_cap" '$1=="ENTRY" && $2==c {print}' "$_dgp_parse_out" > "$_dgp_entries"

  if [ ! -f "$_dgp_corpus_file" ]; then
    _dgp_only_added=1
    _dgp_seen=""
    while IFS="$_dgp_tab" read -r _tag _c _type _id _id2 _text; do
      [ "$_tag" = "ENTRY" ] || continue
      if [ "$_type" != "ADDED" ]; then
        _dgp_only_added=0
        printf 'FINDING|error|ref-not-found|%s: %s referencia %s inexistente (corpus/capability ainda nao existe)\n' "$_dgp_cap" "$_type" "$_id"
        ERRORS=$((ERRORS + 1))
      else
        if _dg_in_list "$_id" "$_dgp_seen"; then
          printf 'FINDING|error|added-collision|%s: ADDED %s duplicado na mesma capability\n' "$_dgp_cap" "$_id"
          ERRORS=$((ERRORS + 1))
        else
          _dgp_seen="$_dgp_seen $_id"
        fi
      fi
    done < "$_dgp_entries"
    if [ "$_dgp_only_added" = "1" ] && [ -s "$_dgp_entries" ]; then
      printf 'FINDING|info|corpus-missing|%s: corpus/capability ainda nao existe (sera criado pelo merge)\n' "$_dgp_cap"
    fi
  else
    _dgp_scan=$(mktemp)
    _dg_corpus_scan "$_dgp_corpus_file" > "$_dgp_scan"
    if awk -F"$_dgp_tab" '$1=="MALFORMED"{f=1} END{exit !f}' "$_dgp_scan"; then
      _dgp_reason=$(awk -F"$_dgp_tab" '$1=="MALFORMED"{print $2; exit}' "$_dgp_scan")
      printf 'FINDING|error|corpus-malformed|%s: %s\n' "$_dgp_cap" "$_dgp_reason"
      ERRORS=$((ERRORS + 1))
      rm -f "$_dgp_scan" "$_dgp_entries"
      return 0
    fi
    _dgp_active=$(awk -F"$_dgp_tab" '$1=="ACTIVE"{print $2}' "$_dgp_scan" | tr '\n' ' ')
    _dgp_removed=$(awk -F"$_dgp_tab" '$1=="REMOVED"{print $2}' "$_dgp_scan" | tr '\n' ' ')
    _dgp_rold=$(awk -F"$_dgp_tab" '$1=="RENAMED_OLD"{print $2}' "$_dgp_scan" | tr '\n' ' ')
    _dgp_rnew=$(awk -F"$_dgp_tab" '$1=="RENAMED_NEW"{print $2}' "$_dgp_scan" | tr '\n' ' ')
    _dgp_all="$_dgp_active $_dgp_removed $_dgp_rold $_dgp_rnew"
    _dgp_session=""
    while IFS="$_dgp_tab" read -r _tag _c _type _id _id2 _text; do
      [ "$_tag" = "ENTRY" ] || continue
      case "$_type" in
        ADDED)
          if _dg_in_list "$_id" "$_dgp_all $_dgp_session"; then
            printf 'FINDING|error|added-collision|%s: ADDED %s ja existe no corpus (ativo, removido ou renomeado)\n' "$_dgp_cap" "$_id"
            ERRORS=$((ERRORS + 1))
          else
            _dgp_session="$_dgp_session $_id"
          fi
          ;;
        MODIFIED)
          if ! _dg_in_list "$_id" "$_dgp_active"; then
            printf 'FINDING|error|ref-not-found|%s: MODIFIED referencia %s inexistente ou inativo\n' "$_dgp_cap" "$_id"
            ERRORS=$((ERRORS + 1))
          fi
          ;;
        REMOVED)
          if ! _dg_in_list "$_id" "$_dgp_active"; then
            printf 'FINDING|error|ref-not-found|%s: REMOVED referencia %s inexistente ou inativo\n' "$_dgp_cap" "$_id"
            ERRORS=$((ERRORS + 1))
          fi
          ;;
        RENAMED)
          if ! _dg_in_list "$_id" "$_dgp_active"; then
            printf 'FINDING|error|ref-not-found|%s: RENAMED referencia %s inexistente ou inativo\n' "$_dgp_cap" "$_id"
            ERRORS=$((ERRORS + 1))
          fi
          if _dg_in_list "$_id2" "$_dgp_all $_dgp_session"; then
            printf 'FINDING|error|renamed-target-exists|%s: RENAMED alvo %s ja existe no corpus\n' "$_dgp_cap" "$_id2"
            ERRORS=$((ERRORS + 1))
          else
            _dgp_session="$_dgp_session $_id2"
          fi
          ;;
      esac
    done < "$_dgp_entries"
    rm -f "$_dgp_scan"
  fi
  rm -f "$_dgp_entries"
}

# ------------------------------- main -------------------------------
# Pulado quando sourced por delta-merge.sh (_DG_SOURCED=1 setado ANTES do
# `.`). Nesse modo so as funcoes acima ficam disponiveis ao caller.
if [ "$_DG_SOURCED" != "1" ]; then

  SPEC_MD=""
  CORPUS_DIR=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --corpus-dir)
        [ $# -ge 2 ] || { _dg_usage; exit 2; }
        CORPUS_DIR=$2; shift 2 ;;
      --corpus-dir=*)
        CORPUS_DIR=${1#--corpus-dir=}; shift ;;
      -h|--help)
        _dg_usage; exit 2 ;;
      --*)
        printf '%s: opcao desconhecida: %s\n' "$_DG_NAME" "$1" >&2
        diag_emit error unknown-option "opcao desconhecida: $1" "consulte delta-gate.sh --help" || :
        _dg_usage; exit 2 ;;
      *)
        if [ -z "$SPEC_MD" ]; then
          SPEC_MD=$1; shift
        else
          printf '%s: argumento extra: %s\n' "$_DG_NAME" "$1" >&2
          diag_emit error extra-argument "argumento extra: $1" "delta-gate.sh aceita apenas SPEC_MD + --corpus-dir" || :
          _dg_usage; exit 2
        fi ;;
    esac
  done

  if [ -z "$SPEC_MD" ]; then
    _dg_usage; exit 2
  fi
  if [ ! -f "$SPEC_MD" ]; then
    printf '%s: spec nao encontrado: %s\n' "$_DG_NAME" "$SPEC_MD" >&2
    diag_emit error spec-not-found "spec.md nao encontrado: $SPEC_MD" "verifique o path de SPEC_MD" || :
    exit 2
  fi

  if [ -z "$CORPUS_DIR" ]; then
    if ! CORPUS_DIR=$(_dg_resolve_corpus_dir "$SPEC_MD"); then
      printf '%s: nao foi possivel resolver --corpus-dir (SPEC_MD fora da convencao docs/specs/<feature>/spec.md)\n' "$_DG_NAME" >&2
      diag_emit error corpus-dir-unresolvable "corpus-dir nao resolvido para $SPEC_MD" "passe --corpus-dir explicitamente" || :
      exit 2
    fi
  fi

  ERRORS=0
  WARNINGS=0
  PARSE_OUT=$(mktemp)
  trap 'rm -f "$PARSE_OUT"' EXIT
  _dg_parse_spec "$SPEC_MD" > "$PARSE_OUT"

  DELTA_STATUS=$(awk -F"$(printf '\t')" '$1=="__STATUS__"{print $2}' "$PARSE_OUT")

  while IFS= read -r _dg_line; do
    case "$_dg_line" in
      FINDING\|error\|*)
        printf '%s\n' "$_dg_line"
        ERRORS=$((ERRORS + 1)) ;;
      FINDING\|warning\|*)
        printf '%s\n' "$_dg_line"
        WARNINGS=$((WARNINGS + 1)) ;;
      FINDING\|*)
        printf '%s\n' "$_dg_line" ;;
    esac
  done < "$PARSE_OUT"

  CAPS=$(awk -F"$(printf '\t')" '$1=="ENTRY"{print $2}' "$PARSE_OUT" | sort -u)
  for _cap in $CAPS; do
    _dg_process_capability "$_cap" "$CORPUS_DIR" "$PARSE_OUT"
  done

  printf 'RESULT|%s|delta=%s|errors=%d|warnings=%d\n' "$SPEC_MD" "$DELTA_STATUS" "$ERRORS" "$WARNINGS"

  if [ "$ERRORS" -gt 0 ]; then
    exit 1
  fi
  exit 0
fi
