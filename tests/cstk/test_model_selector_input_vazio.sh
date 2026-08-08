#!/bin/sh
# test_model_selector_input_vazio.sh
#
# Cobre subtarefa 2.6.5 da feature `model-selector` (Ref: Decision 7 do
# research.md, CHK019, FR-006). Valida o caminho FAIL-SAFE quando o
# input tem <3 tokens validos apos sanitizacao: o classificador NUNCA
# emite sugestao concreta — sempre `manter-atual` com score=0 e
# alternativa=none.
#
# Por que invariante:
#   Decision 7 (research.md) crava: sem >=3 tokens validos, o catalogo
#   de 15 sinais nao tem como ter cobertura estatistica suficiente
#   para diferenciar faixa. Output deterministico de fail-safe evita
#   sugestao falsa-positiva em prompts curtos ou ruido.
#
# Casos cobertos:
#   - input completamente vazio       -> exit !=0 + mensagem em stderr
#   - input so com 1 token            -> manter-atual / score=0
#   - input so com 2 tokens           -> manter-atual / score=0
#   - input so com whitespace         -> trata como vazio
#   - input com 3+ tokens mas zero match -> manter-atual / score=0
#     (este eh "indeterminado", nao "fail-safe", mas o output e
#     equivalente: manter-atual com alternativa=none)
#
# Distincao importante (cravada na justificativa do classify.sh):
#   - fail-safe   : "<3 = limite minimo"
#   - indeterminado: "nenhum sinal do catalogo detectado nos N tokens"

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

CLASSIFY="$REPO_ROOT/plugins/cstk/skills/model-selector/scripts/classify.sh"
export CLASSIFY

_modelo_sugerido() {
  sh "$CLASSIFY" "$1" 2>/dev/null \
    | awk '/^## Modelo Sugerido/{flag=1; next} /^## /{flag=0} flag && NF {print; exit}'
}

_score_line() {
  sh "$CLASSIFY" "$1" 2>/dev/null | grep -E '^score=' | head -n 1
}

_get_justificativa() {
  sh "$CLASSIFY" "$1" 2>/dev/null \
    | awk '/^## Justificativa/{flag=1; next} /^## /{flag=0} flag && NF'
}

# ----------------------------------------------------------------------
# 2.6.5.a: input completamente vazio -> erro em stderr, NAO emite bloco
# markdown. O classify.sh aborta cedo com mensagem de uso.
# ----------------------------------------------------------------------
scenario_2_6_5_input_vazio_string_aborta() {
  capture sh "$CLASSIFY" "" || true
  if [ "$_CAPTURED_EXIT" -eq 0 ]; then
    _fail "input_vazio_exit_zero" "esperado exit !=0 para input vazio, obtido: $_CAPTURED_EXIT"
    return 1
  fi
  case "$_CAPTURED_STDERR" in
    *"input vazio"*) return 0 ;;
  esac
  _fail "input_vazio_stderr" "esperado 'input vazio' em stderr, obtido: $_CAPTURED_STDERR"
  return 1
}

# ----------------------------------------------------------------------
# 2.6.5.b: 1 token apenas -> fail-safe: manter-atual, score=0,
# alternativa=none
# ----------------------------------------------------------------------
scenario_2_6_5_um_token_failsafe_manter_atual() {
  _mod=$(_modelo_sugerido "oi")
  if [ "$_mod" != "manter-atual" ]; then
    _fail "1t_modelo" "esperado 'manter-atual', obtido: '$_mod'"
    return 1
  fi
  _line=$(_score_line "oi")
  case "$_line" in
    "score=0 modelo=manter-atual alternativa=none"*) return 0 ;;
  esac
  _fail "1t_score_line" "esperado 'score=0 modelo=manter-atual alternativa=none', obtido: '$_line'"
  return 1
}

# ----------------------------------------------------------------------
# 2.6.5.c: 2 tokens -> ainda fail-safe (<3 = limite minimo)
# ----------------------------------------------------------------------
scenario_2_6_5_dois_tokens_failsafe_manter_atual() {
  _mod=$(_modelo_sugerido "oi mundo")
  if [ "$_mod" != "manter-atual" ]; then
    _fail "2t_modelo" "esperado 'manter-atual' (<3 limite), obtido: '$_mod'"
    return 1
  fi
  _line=$(_score_line "oi mundo")
  case "$_line" in
    "score=0 modelo=manter-atual alternativa=none"*) return 0 ;;
  esac
  _fail "2t_score_line" "esperado fail-safe, obtido: '$_line'"
  return 1
}

# ----------------------------------------------------------------------
# 2.6.5.d: whitespace only -> trata como vazio (aborta)
# ----------------------------------------------------------------------
scenario_2_6_5_whitespace_apenas_trata_como_vazio() {
  capture sh "$CLASSIFY" "   " || true
  # Aceita 2 caminhos: aborta cedo (exit !=0) OU produz fail-safe
  # (manter-atual). Ambos sao seguros — o invariante e "nao sugerir
  # troca de modelo a partir de espacos em branco".
  if [ "$_CAPTURED_EXIT" -ne 0 ]; then
    return 0  # aborto cedo ok
  fi
  _mod=$(printf '%s' "$_CAPTURED_STDOUT" \
    | awk '/^## Modelo Sugerido/{flag=1; next} /^## /{flag=0} flag && NF {print; exit}')
  if [ "$_mod" = "manter-atual" ]; then
    return 0  # fail-safe ok
  fi
  _fail "whitespace_sugere_troca" "input whitespace produziu '$_mod' (esperado abort OU manter-atual)"
  return 1
}

# ----------------------------------------------------------------------
# 2.6.5.e: 3+ tokens validos SEM match no catalogo -> indeterminado
# -> manter-atual / score=0 / alternativa=none
# Distinto do fail-safe semanticamente, mesma saida operacional.
# ----------------------------------------------------------------------
scenario_2_6_5_tres_tokens_zero_match_indeterminado() {
  _input="alfa beta gama delta"
  _mod=$(_modelo_sugerido "$_input")
  if [ "$_mod" != "manter-atual" ]; then
    _fail "indet_modelo" "esperado 'manter-atual', obtido: '$_mod'"
    return 1
  fi
  _line=$(_score_line "$_input")
  case "$_line" in
    "score=0 modelo=manter-atual alternativa=none"*) ;;
    *)
      _fail "indet_score_line" "esperado 'score=0 manter-atual none', obtido: '$_line'"
      return 1
      ;;
  esac
  # Justificativa deve citar "nenhum sinal" (Decision 7 do research.md).
  _just=$(_get_justificativa "$_input")
  case "$_just" in
    *"nenhum sinal"*) return 0 ;;
  esac
  _fail "indet_justificativa" "justificativa nao cita 'nenhum sinal': $_just"
  return 1
}

# ----------------------------------------------------------------------
# 2.6.5.f: justificativa do fail-safe cita "<3" / "limite minimo"
# (Decision 7 do research.md)
# ----------------------------------------------------------------------
scenario_2_6_5_failsafe_justificativa_cita_limite() {
  _just=$(_get_justificativa "oi")
  case "$_just" in
    *"<3"*|*"limite minimo"*|*"3 tokens"*) return 0 ;;
  esac
  _fail "failsafe_justificativa" "justificativa nao cita limite minimo: $_just"
  return 1
}

# ----------------------------------------------------------------------
# 2.6.5.g: bloco markdown nas 4 secoes mesmo no fail-safe
# (operador precisa do output estruturado mesmo no caminho fail-safe)
# ----------------------------------------------------------------------
scenario_2_6_5_failsafe_emite_quatro_secoes_markdown() {
  _out=$(sh "$CLASSIFY" "oi" 2>/dev/null)
  for _sec in "## Modelo Sugerido" "## Score" "## Justificativa" "## Alternativa"; do
    case "$_out" in
      *"$_sec"*) ;;
      *)
        _fail "secao_ausente" "secao '$_sec' faltando no output fail-safe"
        return 1
        ;;
    esac
  done
  return 0
}

# ----------------------------------------------------------------------
# 2.6.5.h: CHK019 — varredura defensiva: qualquer input <3 tokens
# NUNCA pode sugerir haiku/sonnet/opus.
# ----------------------------------------------------------------------
scenario_2_6_5_chk019_failsafe_nunca_sugere_modelo_concreto() {
  set -- \
    "a" \
    "ab" \
    "rode" \
    "rode liste" \
    "refatore" \
    "projete arquitete"
  for _in in "$@"; do
    _mod=$(_modelo_sugerido "$_in")
    case "$_mod" in
      haiku|sonnet|opus)
        _fail "chk019_violado" "input='$_in' (<3 tokens) sugeriu '$_mod' (esperado manter-atual)"
        return 1
        ;;
      manter-atual) ;;
      *)
        _fail "chk019_modelo_invalido" "input='$_in' produziu modelo inesperado: '$_mod'"
        return 1
        ;;
    esac
  done
  return 0
}

run_all_scenarios
