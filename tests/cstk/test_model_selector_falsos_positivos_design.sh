#!/bin/sh
# test_model_selector_falsos_positivos_design.sh
#
# Cobre subtarefa 2.6.6 da feature `model-selector` (Ref: SC-006, CHK070).
# CHK070 (criterio cravado): nenhum verbo de design (`refatore`,
# `projete`, `arquitete`, `escolha`) pode produzir `haiku` — nem
# isolado, nem misturado com verbos rasos, nem em frases longas com
# tokens nao-catalogo.
#
# Por que esse criterio existe (SC-006):
#   "refatore tudo" e um pedido caro. Se o classificador rotular como
#   `haiku`, o operador trocaria para modelo barato e a refatoracao
#   sairia incompleta/insegura. A regra FR-005 (vence mais profunda)
#   foi desenhada exatamente para essa proteção — este teste e o
#   guarda regressional que o invariante nao se quebre.
#
# Estrategia de cobertura:
#   - loop interno sobre os 4 verbos de design (`refatore`, `projete`,
#     `arquitete`, `escolha`) — debate nao esta na lista de SC-006
#     literal mas TAMBEM e testado por ser sinal profundo
#   - para cada verbo:
#       a) verbo isolado + filler (>=3 tokens)         -> NAO haiku
#       b) verbo + 1 raso (1 profundo + 1 raso)        -> NAO haiku
#       c) verbo + multiplos rasos (1p + 5r)           -> NAO haiku
#       d) verbo + 1 medio                              -> NAO haiku
#       e) verbo + frase longa com tokens irrelevantes  -> NAO haiku

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

CLASSIFY="$REPO_ROOT/global/skills/model-selector/scripts/classify.sh"
export CLASSIFY

# Lista dos 4 verbos de design cravados em CHK070 / SC-006.
# (Mantemos como variavel para o loop e tambem para documentacao
# explicita do que e considerado "verbo de design" pelo MVP.)
_VERBOS_DESIGN="refatore projete arquitete escolha"

_modelo_sugerido() {
  sh "$CLASSIFY" "$1" 2>/dev/null \
    | awk '/^## Modelo Sugerido/{flag=1; next} /^## /{flag=0} flag && NF {print; exit}'
}

# Helper de assercao: dado input + label, falha se output for haiku.
# Retorna 0 (PASS implicito do scenario) ou 1 (FAIL).
_assert_nao_haiku() {
  _label="$1"
  _input="$2"
  _mod=$(_modelo_sugerido "$_input")
  if [ "$_mod" = "haiku" ]; then
    _fail "design_para_haiku [$_label]" "input='$_input' produziu HAIKU (violacao SC-006/CHK070)"
    return 1
  fi
  # Tambem rejeita manter-atual: verbo de design + >=3 tokens deve
  # gerar sugestao positiva (opus ou sonnet via FR-005, mas nao
  # manter-atual a menos que algum filler tenha invalidado os tokens
  # — improvavel com inputs deste teste).
  if [ "$_mod" = "manter-atual" ]; then
    _fail "design_para_manter_atual [$_label]" "input='$_input' produziu manter-atual (esperado opus/sonnet)"
    return 1
  fi
  return 0
}

# ----------------------------------------------------------------------
# 2.6.6.a: cada verbo de design ISOLADO (com filler para passar fail-safe)
# NUNCA produz haiku.
# ----------------------------------------------------------------------
scenario_2_6_6_design_isolado_nao_haiku() {
  for _verbo in $_VERBOS_DESIGN; do
    _input="$_verbo o codigo agora"
    _assert_nao_haiku "isolado:$_verbo" "$_input" || return 1
  done
  return 0
}

# ----------------------------------------------------------------------
# 2.6.6.b: verbo de design + 1 verbo RASO -> FR-005 vence profunda
# -> opus, NUNCA haiku.
# ----------------------------------------------------------------------
scenario_2_6_6_design_mais_raso_nao_haiku() {
  for _verbo in $_VERBOS_DESIGN; do
    _input="rode e $_verbo o modulo"
    _assert_nao_haiku "design_mais_raso:$_verbo" "$_input" || return 1
    # Reforco positivo: deve ser exatamente opus
    _mod=$(_modelo_sugerido "$_input")
    if [ "$_mod" != "opus" ]; then
      _fail "design_mais_raso_nao_opus:$_verbo" "esperado 'opus' (FR-005), obtido: '$_mod'"
      return 1
    fi
  done
  return 0
}

# ----------------------------------------------------------------------
# 2.6.6.c: verbo de design + TODOS os 5 rasos -> dramatico desbalanco
# de contagem (5:1) ainda vence profunda. ZERO haiku.
# ----------------------------------------------------------------------
scenario_2_6_6_design_mais_cinco_rasos_nao_haiku() {
  for _verbo in $_VERBOS_DESIGN; do
    _input="rode liste conte grep formate $_verbo"
    _assert_nao_haiku "design_5rasos:$_verbo" "$_input" || return 1
    _mod=$(_modelo_sugerido "$_input")
    if [ "$_mod" != "opus" ]; then
      _fail "design_5rasos_nao_opus:$_verbo" "esperado 'opus' (FR-005 dramatico), obtido: '$_mod'"
      return 1
    fi
  done
  return 0
}

# ----------------------------------------------------------------------
# 2.6.6.d: verbo de design + 1 verbo MEDIO -> opus (profunda > media)
# ----------------------------------------------------------------------
scenario_2_6_6_design_mais_medio_nao_haiku() {
  for _verbo in $_VERBOS_DESIGN; do
    _input="explique e $_verbo a logica"
    _assert_nao_haiku "design_mais_medio:$_verbo" "$_input" || return 1
    _mod=$(_modelo_sugerido "$_input")
    if [ "$_mod" != "opus" ]; then
      _fail "design_mais_medio_nao_opus:$_verbo" "esperado 'opus', obtido: '$_mod'"
      return 1
    fi
  done
  return 0
}

# ----------------------------------------------------------------------
# 2.6.6.e: verbo de design embutido em frase longa com tokens
# nao-catalogo (ruido) -> sinal isolado ainda eleva para opus.
# Exercita robustez do match contra ruido lexical.
# ----------------------------------------------------------------------
scenario_2_6_6_design_em_frase_longa_nao_haiku() {
  for _verbo in $_VERBOS_DESIGN; do
    _input="por favor $_verbo todo este modulo seguindo as melhores praticas atuais"
    _assert_nao_haiku "design_frase_longa:$_verbo" "$_input" || return 1
  done
  return 0
}

# ----------------------------------------------------------------------
# 2.6.6.f: assercao agregada — varredura ampla com inputs construidos
# programaticamente a partir do cross-produto verbo x ruido. Falha
# ao primeiro hit de `haiku`.
#
# Esta e a barreira-mae do CHK070: 4 verbos x 6 padroes = 24 inputs.
# ----------------------------------------------------------------------
scenario_2_6_6_chk070_cross_produto_amplo() {
  _padroes="
{V} rapido o trecho
{V} este codigo logo
faca um {V} agora mesmo
preciso que voce {V} este modulo
gostaria de {V} o componente
quero {V} a abordagem atual
"
  _OLD_IFS="$IFS"
  for _verbo in $_VERBOS_DESIGN; do
    IFS='
'
    for _padrao in $_padroes; do
      [ -z "$_padrao" ] && continue
      _input=$(printf '%s' "$_padrao" | sed "s/{V}/$_verbo/g")
      IFS="$_OLD_IFS"
      _mod=$(_modelo_sugerido "$_input")
      if [ "$_mod" = "haiku" ]; then
        _fail "chk070_cross_produto" "input='$_input' produziu HAIKU"
        return 1
      fi
      IFS='
'
    done
  done
  IFS="$_OLD_IFS"
  return 0
}

# ----------------------------------------------------------------------
# 2.6.6.g: contraprova explicita — input PURO raso (sem verbo de
# design) DEVE produzir haiku. Este scenario garante que o teste nao
# esta apenas "nunca dizendo haiku" — ele confirma que haiku ainda eh
# alcancavel quando a entrada e legitimamente rasa.
# ----------------------------------------------------------------------
scenario_2_6_6_contraprova_input_puro_raso_produz_haiku() {
  _input="rode liste conte"
  _mod=$(_modelo_sugerido "$_input")
  if [ "$_mod" != "haiku" ]; then
    _fail "contraprova_falhou" "input puro raso esperado 'haiku', obtido: '$_mod' (sinal de bug no classificador)"
    return 1
  fi
}

run_all_scenarios
