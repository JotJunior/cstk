#!/bin/sh
# requirement-coverage.sh — gate deterministico: cada Functional Requirement
# de um spec.md precisa de ao menos um cenario (Acceptance Scenario ou Edge
# Case) associado, por citacao literal do ID ou por correspondencia
# heuristica de termos-chave.
#
# Ref: docs/specs/openspec-hygiene/spec.md FR-001, FR-003, FR-004, FR-005
#      docs/specs/openspec-hygiene/contracts/requirement-coverage-cli.md
#
# Uso:
#   requirement-coverage.sh FILE [--min-match N]
#
#   FILE            path de um spec.md no formato do template feature-spec.md
#   --min-match N   minimo de termos-chave distintos do requisito que devem
#                   aparecer no corpus de cenarios para considera-lo coberto
#                   pela heuristica (default: 2; inteiro >= 1)
#
# Saida (stdout):
#   FINDING|error|fr-no-scenario|<ID> sem cenario associado — adicionar
#     Acceptance Scenario ou Edge Case cobrindo os termos centrais de <ID>
#   RESULT|<FILE>|requirements=<T>|covered=<C>|errors=<N>
#
# Exit: 0 zero gaps (inclui spec sem FRs); 1 >=1 requisito sem cenario;
#       2 uso incorreto / FILE inexistente / --min-match invalido.
#
# POSIX sh + awk. Zero dependencia de jq (mesmo padrao de
# validate-tasks-template.sh).

set -eu

_RC_NAME="requirement-coverage"

_rc_usage() {
  cat <<'USAGE' >&2
Uso: requirement-coverage.sh FILE [--min-match N]

Verifica se cada Functional Requirement de FILE (um spec.md) tem ao menos
um cenario associado (Acceptance Scenario ou Edge Case), por citacao
literal do ID ou por heuristica de termos-chave (--min-match, default 2).
Emite linhas FINDING|error|fr-no-scenario|... e um RESULT final.
Exit: 0 sem gaps; 1 com gaps; 2 uso/arquivo/--min-match invalido.
USAGE
}

FILE=""
MIN_MATCH=2

while [ $# -gt 0 ]; do
  case "$1" in
    --min-match)
      [ $# -ge 2 ] || { _rc_usage; exit 2; }
      MIN_MATCH=$2; shift 2 ;;
    --min-match=*)
      MIN_MATCH=${1#--min-match=}; shift ;;
    -h|--help)
      _rc_usage; exit 2 ;;
    --*)
      printf '%s: opcao desconhecida: %s\n' "$_RC_NAME" "$1" >&2
      _rc_usage; exit 2 ;;
    *)
      if [ -z "$FILE" ]; then
        FILE=$1; shift
      else
        printf '%s: argumento extra: %s\n' "$_RC_NAME" "$1" >&2
        _rc_usage; exit 2
      fi ;;
  esac
done

if [ -z "$FILE" ]; then
  _rc_usage; exit 2
fi
if [ ! -f "$FILE" ]; then
  printf '%s: arquivo nao encontrado: %s\n' "$_RC_NAME" "$FILE" >&2
  exit 2
fi
case "$MIN_MATCH" in
  ''|*[!0-9]*)
    printf '%s: --min-match deve ser inteiro >= 1 (recebido: %s)\n' "$_RC_NAME" "$MIN_MATCH" >&2
    exit 2 ;;
esac
if [ "$MIN_MATCH" -lt 1 ]; then
  printf '%s: --min-match deve ser inteiro >= 1 (recebido: %s)\n' "$_RC_NAME" "$MIN_MATCH" >&2
  exit 2
fi

awk -v min_match="$MIN_MATCH" -v filepath="$FILE" '
BEGIN {
  # Stoplist embutida (pt/en) — termos genericos que aparecem em quase todo
  # enunciado de requisito e nao carregam sinal discriminativo. Calibrada
  # empiricamente contra specs reais do repo (docs/specs/openspec-hygiene/
  # spec.md — 17 FRs).
  nstop = split("sistema system deve devem usuario usuarios campo campos " \
    "formato arquivo script feature quando apenas sempre todos toda todas " \
    "conforme antes durante sobre cada ainda nenhum nenhuma qualquer " \
    "existe existem existente existentes onde essa esse estes estas mesmo " \
    "mesma mesmos mesmas outro outra outros outras sendo pode podem tera " \
    "tem tinha vai vao sera serao para pelo pela pelos pelas como mais " \
    "menos entre desde apos depois disso disto aquele aquela aquilo " \
    "dentro fora forma formas modo modos sendo sido houve tera about " \
    "which their there where these those shall should would could", stop, " ")
  for (i = 1; i <= nstop; i++) stopset[stop[i]] = 1

  section = ""       # "fr" | "as" | "edge" | ""
  fr_count = 0
  corpus_raw = ""     # lowercase, pontuacao preservada (fast-path por ID)
}

function ltrim_rtrim(s) {
  sub(/^[ \t]+/, "", s)
  sub(/[ \t]+$/, "", s)
  return s
}

# --- deteccao de secoes ---
/^### Functional Requirements[ \t]*$/ { section = "fr"; next }
/^\*\*Acceptance Scenarios\*\*:/      { section = "as"; next }
/^### Edge Cases[ \t]*$/              { section = "edge"; next }

# Heading de nivel <=3 (#, ##, ###) fecha fr/edge/as — mesmo nivel ou mais
# raso que os headings de secao reconhecidos acima. Headings mais profundos
# (####+, usados para subagrupar FRs dentro de "### Functional Requirements",
# ex.: enforced-guards/spec.md) NAO fecham a secao — apenas sao ignorados
# como conteudo (nao viram continuacao de FR/corpus).
/^#{1,3}[ \t]/ {
  if (section == "fr" || section == "edge" || section == "as") section = ""
  next
}
/^#{4,6}[ \t]/ {
  next
}
/^---[ \t]*$/ {
  if (section == "as") section = ""
  next
}

{
  if (section == "fr") {
    if (match($0, /^- \*\*FR-[0-9]+\*\*:/)) {
      fr_count++
      idpart = $0
      sub(/^- \*\*/, "", idpart)
      sub(/\*\*:.*$/, "", idpart)
      fr_id[fr_count] = idpart
      rest = $0
      sub(/^- \*\*FR-[0-9]+\*\*:[ \t]*/, "", rest)
      fr_text[fr_count] = rest
    } else if (fr_count > 0 && $0 !~ /^[ \t]*$/) {
      fr_text[fr_count] = fr_text[fr_count] " " ltrim_rtrim($0)
    }
  } else if (section == "as" || section == "edge") {
    corpus_raw = corpus_raw " " $0
  }
}

END {
  corpus_lower = tolower(corpus_raw)

  # corpus_norm: lowercase + pontuacao removida (para tokenizacao), com
  # espacos de padding para permitir match de palavra inteira via index().
  corpus_norm = corpus_lower
  gsub(/[^a-z0-9]+/, " ", corpus_norm)
  corpus_norm = " " corpus_norm " "

  total_req = fr_count
  covered_count = 0
  errors = 0

  for (k = 1; k <= fr_count; k++) {
    id = fr_id[k]
    id_lower = tolower(id)
    covered = 0

    # Fast-path: corpus cita o ID literal (ex.: "FR-003").
    if (index(corpus_lower, id_lower) > 0) covered = 1

    if (!covered) {
      # Heuristica: tokeniza enunciado, filtra termos >=5 chars, remove
      # stoplist, deduplica.
      text_norm = tolower(fr_text[k])
      gsub(/[^a-z0-9]+/, " ", text_norm)
      n_tok = split(text_norm, toks, " ")
      delete seen
      n_distinct = 0
      for (t = 1; t <= n_tok; t++) {
        w = toks[t]
        if (length(w) >= 5 && !(w in stopset) && !(w in seen)) {
          seen[w] = 1
          n_distinct++
        }
      }

      required = min_match
      if (n_distinct < required) required = n_distinct
      if (required < 1) required = 1

      matched = 0
      if (n_distinct > 0) {
        for (w in seen) {
          if (index(corpus_norm, " " w " ") > 0) matched++
        }
      }
      if (n_distinct > 0 && matched >= required) covered = 1
    }

    if (covered) {
      covered_count++
    } else {
      errors++
      printf "FINDING|error|fr-no-scenario|%s sem cenario associado \xe2\x80\x94 adicionar Acceptance Scenario ou Edge Case cobrindo os termos centrais de %s\n", id, id
    }
  }

  printf "RESULT|%s|requirements=%d|covered=%d|errors=%d\n", filepath, total_req, covered_count, errors

  exit (errors > 0) ? 1 : 0
}
' "$FILE"
