#!/bin/sh
# test_model_selector_faixa_rasa.sh
#
# Cobre subtarefa 2.6.1 da feature `model-selector` (Ref: SC-001, CHK069,
# FR-003, FR-004). Valida que inputs com >=2 verbos da faixa RASA do
# catalogo MVP produzem `## Modelo Sugerido: haiku` com score <=2.
#
# Por que faixa-especifica:
#   SC-001 exige output deterministico por faixa. Este teste cobre a
#   faixa rasa de ponta a ponta — desde tokenizacao do input ate o
#   bloco markdown final — usando inputs sem ambiguidade (so verbos
#   rasos do catalogo MVP, sem misturar faixas).
#
# Catalogo rasa MVP (sinais.md):
#   rode, liste, conte, grep, formate
#
# Contrato verificado:
#   - `## Modelo Sugerido` aparece e o valor abaixo e exatamente `haiku`
#   - linha grep-able `modelo=haiku alternativa=sonnet`
#   - `score=N` com N <= 2 (cravado em CHK069 / dec-006: TETO absoluto)
#   - faixa vencedora = `rasa` quando inputs sao puros rasos
#
# Inputs cobrem variacoes:
#   - 2 verbos rasos puros
#   - 3 verbos rasos puros
#   - 5 verbos rasos puros (todos do catalogo) — exercita TETO 2

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

CLASSIFY="$REPO_ROOT/global/skills/model-selector/scripts/classify.sh"
export CLASSIFY

# Helper: roda classify.sh e retorna a linha grep-able `score=...`.
_score_line() {
  sh "$CLASSIFY" "$1" 2>/dev/null | grep -E '^score=' | head -n 1
}

# Helper: extrai o valor abaixo de `## Modelo Sugerido` (primeira linha
# nao-vazia apos o header). Output esperado: haiku|sonnet|opus|manter-atual.
_modelo_sugerido() {
  sh "$CLASSIFY" "$1" 2>/dev/null \
    | awk '/^## Modelo Sugerido/{flag=1; next} /^## /{flag=0} flag && NF {print; exit}'
}

# Helper: extrai o numero inteiro da secao `## Score` (primeira linha
# nao-vazia apos o header, antes da linha grep-able `rasa=`).
_score_int() {
  sh "$CLASSIFY" "$1" 2>/dev/null \
    | awk '/^## Score/{flag=1; next} /^## /{flag=0} flag && NF && !/^rasa=/ && !/^score=/ {print; exit}'
}

# ----------------------------------------------------------------------
# 2.6.1.a: 2 verbos rasos puros -> haiku, score=2
# ----------------------------------------------------------------------
scenario_2_6_1_dois_verbos_rasos_haiku() {
  _input="rode e liste os arquivos"
  _mod=$(_modelo_sugerido "$_input")
  if [ "$_mod" != "haiku" ]; then
    _fail "modelo_sugerido_2v" "esperado 'haiku', obtido: '$_mod' (input='$_input')"
    return 1
  fi
  _line=$(_score_line "$_input")
  case "$_line" in
    "score=2 modelo=haiku alternativa=sonnet"*) return 0 ;;
  esac
  _fail "score_line_2v" "esperado 'score=2 modelo=haiku alternativa=sonnet', obtido: '$_line'"
  return 1
}

# ----------------------------------------------------------------------
# 2.6.1.b: 3 verbos rasos puros -> haiku, score=2 (teto continua firme)
# ----------------------------------------------------------------------
scenario_2_6_1_tres_verbos_rasos_haiku_score_teto() {
  _input="rode liste conte os logs"
  _mod=$(_modelo_sugerido "$_input")
  if [ "$_mod" != "haiku" ]; then
    _fail "modelo_sugerido_3v" "esperado 'haiku', obtido: '$_mod'"
    return 1
  fi
  _int=$(_score_int "$_input")
  case "$_int" in
    0|1|2) ;;  # CHK069 / dec-006: TETO 2
    *)
      _fail "score_int_3v_fora_de_faixa" "esperado int em [0..2], obtido: '$_int'"
      return 1
      ;;
  esac
  # Especifico: 3+ matches => score=2 absoluto.
  if [ "$_int" != "2" ]; then
    _fail "score_int_3v_esperado_2" "esperado '2' com 3 sinais, obtido: '$_int'"
    return 1
  fi
}

# ----------------------------------------------------------------------
# 2.6.1.c: TODOS os 5 verbos rasos do catalogo -> haiku, score=2.
# Tambem garante que a faixa vencedora e `rasa` (cabecalho grep-able).
# ----------------------------------------------------------------------
scenario_2_6_1_cinco_verbos_rasos_faixa_rasa_vence() {
  _input="rode liste conte grep formate o arquivo"
  _mod=$(_modelo_sugerido "$_input")
  if [ "$_mod" != "haiku" ]; then
    _fail "modelo_sugerido_5v" "esperado 'haiku', obtido: '$_mod'"
    return 1
  fi
  _faixa=$(sh "$CLASSIFY" "$_input" 2>/dev/null \
    | grep -E '^rasa=[0-9]+ media=[0-9]+ profunda=[0-9]+ faixa=' \
    | head -n 1)
  case "$_faixa" in
    *"faixa=rasa"*) ;;
    *)
      _fail "faixa_vencedora_5v" "esperado 'faixa=rasa', linha: '$_faixa'"
      return 1
      ;;
  esac
  _line=$(_score_line "$_input")
  case "$_line" in
    "score=2 modelo=haiku alternativa=sonnet"*) return 0 ;;
  esac
  _fail "score_line_5v" "esperado 'score=2 modelo=haiku alternativa=sonnet', obtido: '$_line'"
  return 1
}

# ----------------------------------------------------------------------
# 2.6.1.d: assercao explicita CHK069 — varrer 5 inputs puros rasos
# e exigir score <=2 em TODOS (assercao defensiva por faixa).
# ----------------------------------------------------------------------
scenario_2_6_1_assercao_score_teto_dois_em_inputs_rasos() {
  set -- \
    "rode o comando" \
    "rode e liste" \
    "rode liste conte" \
    "rode liste conte grep" \
    "rode liste conte grep formate"
  for _in in "$@"; do
    _int=$(_score_int "$_in")
    case "$_int" in
      0|1|2) ;;
      *)
        _fail "score_int_fora_de_faixa" "input='$_in' produziu int='$_int' (esperado [0..2])"
        return 1
        ;;
    esac
  done
  return 0
}

# ----------------------------------------------------------------------
# 2.6.1.e: bloco markdown completo presente (4 secoes fixas)
# ----------------------------------------------------------------------
scenario_2_6_1_output_markdown_quatro_secoes() {
  _out=$(sh "$CLASSIFY" "rode liste conte" 2>/dev/null)
  for _sec in "## Modelo Sugerido" "## Score" "## Justificativa" "## Alternativa"; do
    case "$_out" in
      *"$_sec"*) ;;
      *)
        _fail "secao_ausente" "secao '$_sec' faltando no output"
        return 1
        ;;
    esac
  done
  # Alternativa esperada para haiku e sonnet (dec dec-008/2.4.5).
  _alt=$(printf '%s' "$_out" \
    | awk '/^## Alternativa/{flag=1; next} /^## /{flag=0} flag && NF {print; exit}')
  if [ "$_alt" != "sonnet" ]; then
    _fail "alternativa_inesperada" "esperado 'sonnet', obtido: '$_alt'"
    return 1
  fi
}

run_all_scenarios
