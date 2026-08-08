#!/bin/sh
# test_model_selector_faixa_media.sh
#
# Cobre subtarefa 2.6.2 da feature `model-selector` (Ref: SC-001, CHK069,
# FR-003, FR-004). Valida que inputs com >=2 verbos da faixa MEDIA do
# catalogo MVP produzem `## Modelo Sugerido: sonnet` com score <=2.
#
# Catalogo media MVP (sinais.md):
#   explique, documente, resuma, traduza, compare
#
# Contrato verificado:
#   - `## Modelo Sugerido` -> exatamente `sonnet`
#   - linha grep-able `modelo=sonnet alternativa=haiku`
#   - `score=N` com N <= 2 (CHK069 / dec-006)
#   - faixa vencedora = `media` quando inputs sao puros medios

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

CLASSIFY="$REPO_ROOT/plugins/cstk/skills/model-selector/scripts/classify.sh"
export CLASSIFY

_score_line() {
  sh "$CLASSIFY" "$1" 2>/dev/null | grep -E '^score=' | head -n 1
}

_modelo_sugerido() {
  sh "$CLASSIFY" "$1" 2>/dev/null \
    | awk '/^## Modelo Sugerido/{flag=1; next} /^## /{flag=0} flag && NF {print; exit}'
}

_score_int() {
  sh "$CLASSIFY" "$1" 2>/dev/null \
    | awk '/^## Score/{flag=1; next} /^## /{flag=0} flag && NF && !/^rasa=/ && !/^score=/ {print; exit}'
}

# ----------------------------------------------------------------------
# 2.6.2.a: 2 verbos medios puros -> sonnet, score=2
# ----------------------------------------------------------------------
scenario_2_6_2_dois_verbos_medios_sonnet() {
  _input="explique e documente a funcao"
  _mod=$(_modelo_sugerido "$_input")
  if [ "$_mod" != "sonnet" ]; then
    _fail "modelo_sugerido_2v" "esperado 'sonnet', obtido: '$_mod'"
    return 1
  fi
  _line=$(_score_line "$_input")
  case "$_line" in
    "score=2 modelo=sonnet alternativa=haiku"*) return 0 ;;
  esac
  _fail "score_line_2v" "esperado 'score=2 modelo=sonnet alternativa=haiku', obtido: '$_line'"
  return 1
}

# ----------------------------------------------------------------------
# 2.6.2.b: 3 verbos medios -> sonnet, score=2 (teto firme)
# ----------------------------------------------------------------------
scenario_2_6_2_tres_verbos_medios_score_teto() {
  _input="explique documente resuma esse trecho"
  _mod=$(_modelo_sugerido "$_input")
  if [ "$_mod" != "sonnet" ]; then
    _fail "modelo_sugerido_3v" "esperado 'sonnet', obtido: '$_mod'"
    return 1
  fi
  _int=$(_score_int "$_input")
  case "$_int" in
    0|1|2) ;;
    *)
      _fail "score_int_fora_de_faixa" "esperado [0..2], obtido: '$_int'"
      return 1
      ;;
  esac
  if [ "$_int" != "2" ]; then
    _fail "score_int_esperado_2" "esperado '2' com 3 sinais, obtido: '$_int'"
    return 1
  fi
}

# ----------------------------------------------------------------------
# 2.6.2.c: TODOS os 5 verbos medios -> sonnet, faixa=media
# ----------------------------------------------------------------------
scenario_2_6_2_cinco_verbos_medios_faixa_media_vence() {
  _input="explique documente resuma traduza compare o codigo"
  _mod=$(_modelo_sugerido "$_input")
  if [ "$_mod" != "sonnet" ]; then
    _fail "modelo_sugerido_5v" "esperado 'sonnet', obtido: '$_mod'"
    return 1
  fi
  _faixa=$(sh "$CLASSIFY" "$_input" 2>/dev/null \
    | grep -E '^rasa=[0-9]+ media=[0-9]+ profunda=[0-9]+ faixa=' \
    | head -n 1)
  case "$_faixa" in
    *"faixa=media"*) ;;
    *)
      _fail "faixa_vencedora_5v" "esperado 'faixa=media', linha: '$_faixa'"
      return 1
      ;;
  esac
  _line=$(_score_line "$_input")
  case "$_line" in
    "score=2 modelo=sonnet alternativa=haiku"*) return 0 ;;
  esac
  _fail "score_line_5v" "esperado 'score=2 modelo=sonnet alternativa=haiku', obtido: '$_line'"
  return 1
}

# ----------------------------------------------------------------------
# 2.6.2.d: assercao CHK069 em bateria de inputs medios
# ----------------------------------------------------------------------
scenario_2_6_2_assercao_score_teto_dois_em_inputs_medios() {
  set -- \
    "explique a logica" \
    "explique e documente" \
    "explique documente resuma" \
    "explique documente resuma traduza" \
    "explique documente resuma traduza compare"
  for _in in "$@"; do
    _int=$(_score_int "$_in")
    case "$_int" in
      0|1|2) ;;
      *)
        _fail "score_int_fora_de_faixa" "input='$_in' produziu int='$_int'"
        return 1
        ;;
    esac
  done
  return 0
}

# ----------------------------------------------------------------------
# 2.6.2.e: bloco markdown completo + Alternativa=haiku
# ----------------------------------------------------------------------
scenario_2_6_2_output_markdown_alternativa_haiku() {
  _out=$(sh "$CLASSIFY" "explique documente resuma" 2>/dev/null)
  for _sec in "## Modelo Sugerido" "## Score" "## Justificativa" "## Alternativa"; do
    case "$_out" in
      *"$_sec"*) ;;
      *)
        _fail "secao_ausente" "secao '$_sec' faltando"
        return 1
        ;;
    esac
  done
  _alt=$(printf '%s' "$_out" \
    | awk '/^## Alternativa/{flag=1; next} /^## /{flag=0} flag && NF {print; exit}')
  if [ "$_alt" != "haiku" ]; then
    _fail "alternativa_inesperada" "esperado 'haiku', obtido: '$_alt'"
    return 1
  fi
}

run_all_scenarios
