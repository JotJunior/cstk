#!/bin/sh
# test_model_selector_corpus.sh
#
# Cobre a subtarefa 4.2 da feature `model-routing-por-onda` (FASE 4):
# corpus rotulado + metrica SC-008 sobre o classificador EXPANDIDO
# (catalogo de 45 sinais, 15 por faixa — FR-018).
#
# Contratos testados (SC-008, quickstart C10):
#   - taxa de `indeterminado` <= 25% sobre o corpus de referencia
#   - discriminacao rasa-vs-profunda: NENHUM caso rotulado `rasa` e
#     classificado `profunda` e vice-versa (o erro mais grave — troca
#     barato<->caro na direcao errada)
#   - sanity: corpus existe, e legivel, e tem entradas das 3 faixas
#
# Cobertura (orphan-check): este teste exercita
# plugins/cstk/skills/model-selector/scripts/classify.sh — ja isento via o
# ramo `test_model_selector_*.sh` de _is_internal_test em tests/run.sh
# (existence-guarded ao classify.sh). Nenhum script novo introduzido.
#
# Conformidade: POSIX puro (#!/bin/sh), sem rede, sem jq.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

CLASSIFY="$REPO_ROOT/plugins/cstk/skills/model-selector/scripts/classify.sh"
CORPUS="$TESTS_ROOT/fixtures/model-selector-corpus/corpus.tsv"
export CLASSIFY CORPUS

# Separador TAB literal para o `read` (POSIX: $(printf '\t')).
_TAB=$(printf '\t')

# Classifica uma descricao e imprime a faixa vencedora (rasa|media|
# profunda|indeterminado) extraida da linha `rasa=... faixa=X`.
_faixa_de() {
  sh "$CLASSIFY" "$1" 2>/dev/null \
    | grep -E '^rasa=' \
    | head -n 1 \
    | sed -E 's/.*faixa=([a-z]+).*/\1/'
}

# Emite apenas as linhas de DADOS do corpus (descarta comentarios `#` e
# linhas em branco) — evita `case` dentro de command-substitution
# (gotcha dec-003) ao pre-filtrar com grep antes do `while read`.
_corpus_data_lines() {
  grep -v '^#' "$CORPUS" | grep -v '^[[:space:]]*$'
}

# ----------------------------------------------------------------------
# Sanity: corpus existe, legivel, tem as 3 faixas representadas.
# ----------------------------------------------------------------------
scenario_corpus_existe_e_balanceado() {
  if [ ! -r "$CORPUS" ]; then
    _fail "scenario_corpus_existe" "corpus nao encontrado/ilegivel: $CORPUS"
    return 1
  fi
  _dist=$(grep -v '^#' "$CORPUS" \
    | grep -v '^[[:space:]]*$' \
    | awk -F"$_TAB" '{c[$1]++} END {printf "%d|%d|%d", c["rasa"]+0, c["media"]+0, c["profunda"]+0}')
  case "$_dist" in
    0\|*|*\|0\|*|*\|0) _fail "scenario_corpus_balanceado" "alguma faixa sem entradas: $_dist"; return 1 ;;
  esac
  return 0
}

# ----------------------------------------------------------------------
# SC-008 (a): taxa de `indeterminado` <= 25% sobre o corpus.
# ----------------------------------------------------------------------
scenario_sc008_taxa_indeterminado_max_25() {
  _total=0
  _indet=0
  # `while read` em subshell perderia os contadores; usamos arquivo temp
  # so como fonte. Acumulacao no shell corrente via here-string seria
  # bash-ism — preferimos pipe para `awk` final POSIX.
  _line_results=$(
    _corpus_data_lines | while IFS="$_TAB" read -r _expected _desc; do
      [ -z "$_desc" ] && continue
      _f=$(_faixa_de "$_desc")
      printf '%s\n' "$_f"
    done
  )
  _total=$(printf '%s\n' "$_line_results" | grep -c .)
  _indet=$(printf '%s\n' "$_line_results" | grep -c '^indeterminado$' || true)
  if [ "$_total" -le 0 ]; then
    _fail "scenario_sc008_taxa" "corpus sem linhas de dados"
    return 1
  fi
  # Comparacao inteira: indet*100 <= 25*total  <=>  indet/total <= 0.25
  if [ "$((_indet * 100))" -gt "$((_total * 25))" ]; then
    _fail "scenario_sc008_taxa" \
      "taxa indeterminado $_indet/$_total > 25% (SC-008 viola)"
    return 1
  fi
  return 0
}

# ----------------------------------------------------------------------
# SC-008 (b): discriminacao rasa-vs-profunda — NENHUM cruzamento.
# rasa rotulado classificado profunda (ou vice-versa) e o erro mais
# grave: trocaria modelo barato<->caro na direcao oposta. Tolerancia 0.
# ----------------------------------------------------------------------
scenario_sc008_discrimina_rasa_vs_profunda() {
  _cross=$(
    _corpus_data_lines | while IFS="$_TAB" read -r _expected _desc; do
      [ -z "$_desc" ] && continue
      _f=$(_faixa_de "$_desc")
      if { [ "$_expected" = "rasa" ] && [ "$_f" = "profunda" ]; } \
         || { [ "$_expected" = "profunda" ] && [ "$_f" = "rasa" ]; }; then
        printf 'CROSS expected=%s got=%s :: %s\n' "$_expected" "$_f" "$_desc"
      fi
    done
  )
  if [ -n "$_cross" ]; then
    _fail "scenario_sc008_discrimina" \
      "cruzamento rasa<->profunda detectado: $_cross"
    return 1
  fi
  return 0
}

# ----------------------------------------------------------------------
# Acerto de faixa exata: guarda de qualidade adicional (nao-SC-008
# estrito, mas detecta regressao grosseira). Exige >=70% de faixa exata
# — margem larga abaixo do observado (100%) para tolerar evolucao do
# corpus sem virar teste fragil.
# ----------------------------------------------------------------------
scenario_acerto_faixa_exata_min_70() {
  _results=$(
    _corpus_data_lines | while IFS="$_TAB" read -r _expected _desc; do
      [ -z "$_desc" ] && continue
      _f=$(_faixa_de "$_desc")
      if [ "$_f" = "$_expected" ]; then printf 'HIT\n'; else printf 'MISS\n'; fi
    done
  )
  _total=$(printf '%s\n' "$_results" | grep -c .)
  _hit=$(printf '%s\n' "$_results" | grep -c '^HIT$' || true)
  if [ "$_total" -le 0 ]; then
    _fail "scenario_acerto_faixa" "corpus sem linhas de dados"
    return 1
  fi
  if [ "$((_hit * 100))" -lt "$((_total * 70))" ]; then
    _fail "scenario_acerto_faixa" \
      "acerto de faixa $_hit/$_total < 70% (regressao do catalogo?)"
    return 1
  fi
  return 0
}

run_all_scenarios
