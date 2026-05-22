#!/bin/sh
# test_model_selector_faixa_profunda.sh
#
# Cobre subtarefa 2.6.3 da feature `model-selector` (Ref: SC-001, SC-006,
# CHK069, FR-003, FR-004). Valida que inputs com >=2 verbos da faixa
# PROFUNDA do catalogo MVP produzem `## Modelo Sugerido: opus` com
# score <=2.
#
# Catalogo profunda MVP (sinais.md):
#   projete, refatore, arquitete, debate, escolha
#
# SC-006 reforco: verbos de design (refatore, projete, arquitete,
# escolha) DEVEM elevar a sugestao para `opus`, NUNCA `haiku`. Aqui
# cravamos o caminho positivo (verbos de design -> opus). O caminho
# negativo (design + ruido nao deve cair para haiku) e coberto em
# 2.6.6 (falsos positivos).
#
# Contrato verificado:
#   - `## Modelo Sugerido` -> exatamente `opus`
#   - linha grep-able `modelo=opus alternativa=sonnet`
#   - `score=N` com N <= 2 (CHK069 / dec-006)
#   - faixa vencedora = `profunda`

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

CLASSIFY="$REPO_ROOT/global/skills/model-selector/scripts/classify.sh"
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
# 2.6.3.a: 2 verbos profundos -> opus, score=2 (SC-006)
# ----------------------------------------------------------------------
scenario_2_6_3_dois_verbos_profundos_opus() {
  _input="refatore e arquitete o modulo"
  _mod=$(_modelo_sugerido "$_input")
  if [ "$_mod" != "opus" ]; then
    _fail "modelo_sugerido_2v" "esperado 'opus', obtido: '$_mod' (input='$_input')"
    return 1
  fi
  _line=$(_score_line "$_input")
  case "$_line" in
    "score=2 modelo=opus alternativa=sonnet"*) return 0 ;;
  esac
  _fail "score_line_2v" "esperado 'score=2 modelo=opus alternativa=sonnet', obtido: '$_line'"
  return 1
}

# ----------------------------------------------------------------------
# 2.6.3.b: 3 verbos profundos -> opus, score=2 (TETO firme)
# ----------------------------------------------------------------------
scenario_2_6_3_tres_verbos_profundos_score_teto() {
  _input="projete refatore arquitete a solucao"
  _mod=$(_modelo_sugerido "$_input")
  if [ "$_mod" != "opus" ]; then
    _fail "modelo_sugerido_3v" "esperado 'opus', obtido: '$_mod'"
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
# 2.6.3.c: TODOS os 5 verbos profundos -> opus, faixa=profunda
# ----------------------------------------------------------------------
scenario_2_6_3_cinco_verbos_profundos_faixa_profunda_vence() {
  _input="projete refatore arquitete debate escolha a abordagem"
  _mod=$(_modelo_sugerido "$_input")
  if [ "$_mod" != "opus" ]; then
    _fail "modelo_sugerido_5v" "esperado 'opus', obtido: '$_mod'"
    return 1
  fi
  _faixa=$(sh "$CLASSIFY" "$_input" 2>/dev/null \
    | grep -E '^rasa=[0-9]+ media=[0-9]+ profunda=[0-9]+ faixa=' \
    | head -n 1)
  case "$_faixa" in
    *"faixa=profunda"*) ;;
    *)
      _fail "faixa_vencedora_5v" "esperado 'faixa=profunda', linha: '$_faixa'"
      return 1
      ;;
  esac
  _line=$(_score_line "$_input")
  case "$_line" in
    "score=2 modelo=opus alternativa=sonnet"*) return 0 ;;
  esac
  _fail "score_line_5v" "esperado 'score=2 modelo=opus alternativa=sonnet', obtido: '$_line'"
  return 1
}

# ----------------------------------------------------------------------
# 2.6.3.d: SC-006 — cada verbo de design isolado (com filler para
# fugir do fail-safe <3 tokens), score=1, modelo=opus. NUNCA haiku.
# ----------------------------------------------------------------------
scenario_2_6_3_sc006_design_isolado_eleva_para_opus() {
  set -- \
    "refatore o modulo agora" \
    "projete a interface publica" \
    "arquitete o pipeline novo" \
    "debate as alternativas hoje" \
    "escolha entre as opcoes apresentadas"
  for _in in "$@"; do
    _mod=$(_modelo_sugerido "$_in")
    if [ "$_mod" = "haiku" ]; then
      _fail "sc006_design_para_haiku" "input='$_in' produziu HAIKU (violacao SC-006)"
      return 1
    fi
    if [ "$_mod" != "opus" ]; then
      _fail "sc006_design_nao_opus" "input='$_in' esperado 'opus', obtido: '$_mod'"
      return 1
    fi
  done
  return 0
}

# ----------------------------------------------------------------------
# 2.6.3.e: CHK069 — bateria de inputs profundos, score sempre <=2
# ----------------------------------------------------------------------
scenario_2_6_3_assercao_score_teto_dois_em_inputs_profundos() {
  set -- \
    "refatore agora ja" \
    "refatore e arquitete" \
    "projete refatore arquitete" \
    "projete refatore arquitete debate" \
    "projete refatore arquitete debate escolha"
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
# 2.6.3.f: bloco markdown completo + Alternativa=sonnet
# ----------------------------------------------------------------------
scenario_2_6_3_output_markdown_alternativa_sonnet() {
  _out=$(sh "$CLASSIFY" "projete refatore arquitete" 2>/dev/null)
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
  if [ "$_alt" != "sonnet" ]; then
    _fail "alternativa_inesperada" "esperado 'sonnet', obtido: '$_alt'"
    return 1
  fi
}

run_all_scenarios
