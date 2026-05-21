#!/bin/sh
# test_model_selector_score.sh
#
# Cobre subtarefas 2.4.1 a 2.4.5 da feature `model-selector` (FASE 2,
# task 2.4). Valida a logica de score 0..2, assercao defensiva de teto,
# justificativa textual, mapa faixa->modelo e mapa de fallback em
# scripts/classify.sh.
#
# Contratos testados:
#   2.4.1  score = 0 (zero sinais), 1 (um sinal), 2 (>=2 sinais)
#   2.4.2  TETO absoluto: input com >>2 sinais profundos -> ainda score=2
#          + assercao defensiva (script nunca emite score fora de [0..2])
#   2.4.3  justificativa contem cada termo detectado e sua faixa
#   2.4.4  mapa faixa -> modelo: rasa->haiku, media->sonnet, profunda->opus,
#          indeterminado->manter-atual
#   2.4.5  fallback: haiku->sonnet, sonnet->haiku, opus->sonnet,
#          manter-atual->none
#
# As asserts grepam linhas estaveis no stdout do classify.sh:
#   `score=N modelo=X alternativa=Y` (linha unica, no bloco "Sinais detectados").
# Output markdown final (4 secoes) entra em 2.5; testes aqui validam
# semantica, nao layout final.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

CLASSIFY="$REPO_ROOT/global/skills/model-selector/scripts/classify.sh"
export CLASSIFY

# Helper: extrai a linha "score=N modelo=X alternativa=Y" do stdout do
# classify.sh. Imprime a linha completa (ou string vazia).
_get_score_line() {
  _input="$1"
  sh "$CLASSIFY" "$_input" 2>/dev/null | grep -E '^score=' | head -n 1
}

# Helper: extrai a justificativa (linha apos "## Justificativa", pulando
# linha em branco). Em sh puro, e mais simples capturar todo o stdout e
# inspecionar via case.
_get_justificativa_block() {
  _input="$1"
  sh "$CLASSIFY" "$_input" 2>/dev/null \
    | awk '/^## Justificativa/{flag=1; next} /^## /{flag=0} flag && NF'
}

# ----------------------------------------------------------------------
# 2.4.1: 0 sinais (input com tokens validos mas nenhum match) -> score=0
# Tambem cobre 2.4.4: indeterminado -> manter-atual
# Tambem cobre 2.4.5: manter-atual -> none
# ----------------------------------------------------------------------
scenario_2_4_1_zero_sinais_score_zero() {
  # 4 tokens validos, nenhum no catalogo (>=3 evita fail-safe).
  _line=$(_get_score_line "tokens completamente randomicos nada catalogo")
  case "$_line" in
    "score=0 modelo=manter-atual alternativa=none"*) return 0 ;;
  esac
  _fail "scenario_2_4_1_zero" "esperado 'score=0 modelo=manter-atual alternativa=none', obtido: $_line"
  return 1
}

# ----------------------------------------------------------------------
# 2.4.1: 1 sinal -> score=1
# Tambem cobre 2.4.4: rasa -> haiku e 2.4.5: haiku -> sonnet
# ----------------------------------------------------------------------
scenario_2_4_1_um_sinal_rasa_score_um() {
  # "rode" e sinal rasa; tokens filler nao batem.
  _line=$(_get_score_line "rode os tokens filler aleatorios")
  case "$_line" in
    "score=1 modelo=haiku alternativa=sonnet"*) return 0 ;;
  esac
  _fail "scenario_2_4_1_um_rasa" "esperado 'score=1 modelo=haiku alternativa=sonnet', obtido: $_line"
  return 1
}

# ----------------------------------------------------------------------
# 2.4.1: >=2 sinais consistentes -> score=2
# Tambem cobre 2.4.4: media -> sonnet e 2.4.5: sonnet -> haiku
# ----------------------------------------------------------------------
scenario_2_4_1_dois_sinais_media_score_dois() {
  # "explique" + "documente" sao 2 sinais media puros.
  _line=$(_get_score_line "explique e documente o codigo")
  case "$_line" in
    "score=2 modelo=sonnet alternativa=haiku"*) return 0 ;;
  esac
  _fail "scenario_2_4_1_dois_media" "esperado 'score=2 modelo=sonnet alternativa=haiku', obtido: $_line"
  return 1
}

# ----------------------------------------------------------------------
# 2.4.4 + 2.4.5: faixa profunda -> opus -> fallback sonnet
# ----------------------------------------------------------------------
scenario_2_4_4_profunda_opus_fallback_sonnet() {
  # 2 sinais profundos puros.
  _line=$(_get_score_line "refatore e arquitete a solucao")
  case "$_line" in
    "score=2 modelo=opus alternativa=sonnet"*) return 0 ;;
  esac
  _fail "scenario_2_4_4_opus" "esperado 'score=2 modelo=opus alternativa=sonnet', obtido: $_line"
  return 1
}

# ----------------------------------------------------------------------
# 2.4.2: TETO 2 — input com MUITOS sinais profundos ainda da score=2
# (nunca 3, 4, 5...).
# ----------------------------------------------------------------------
scenario_2_4_2_teto_dois_absoluto() {
  # Todos os 5 sinais profundos do catalogo + 5 rasas + 5 medias.
  # 15 matches no total. Score DEVE ser 2 (nao 15, nao 3).
  _input="projete refatore arquitete debate escolha explique documente resuma traduza compare rode liste conte grep formate"
  _line=$(_get_score_line "$_input")
  case "$_line" in
    "score=2 "*)
      # Tambem deve ser opus (faixa mais profunda vence)
      case "$_line" in
        *"modelo=opus alternativa=sonnet"*) return 0 ;;
      esac
      _fail "scenario_2_4_2_teto_modelo" "score=2 OK mas modelo errado: $_line"
      return 1
      ;;
  esac
  _fail "scenario_2_4_2_teto" "esperado 'score=2 ...', obtido: $_line"
  return 1
}

# ----------------------------------------------------------------------
# 2.4.2: assercao defensiva — varrer TODOS os scenarios anteriores e
# qualquer combinacao razoavel, garantir que NUNCA aparece score=3+
# nem score=-1 no stdout. Esta e a guarda contra regressao.
# ----------------------------------------------------------------------
scenario_2_4_2_assercao_defensiva_score_jamais_fora_de_faixa() {
  # Bateria de inputs cobrindo casos extremos.
  set -- \
    "rode" \
    "rode liste conte" \
    "tokens aleatorios sem match" \
    "projete refatore arquitete debate escolha" \
    "rode explique projete o texto" \
    "explique documente projete refatore arquitete" \
    "rode liste explique documente projete refatore arquitete debate escolha conte"
  for _in in "$@"; do
    _line=$(sh "$CLASSIFY" "$_in" 2>/dev/null | grep -E '^score=' | head -n 1)
    case "$_line" in
      "score=0 "*|"score=1 "*|"score=2 "*) ;;
      *)
        _fail "scenario_2_4_2_defensive" "input='$_in' produziu linha fora da faixa: $_line"
        return 1
        ;;
    esac
  done
  return 0
}

# ----------------------------------------------------------------------
# 2.4.3: justificativa cita CADA sinal detectado pelo nome
# ----------------------------------------------------------------------
scenario_2_4_3_justificativa_lista_sinais() {
  # 2 sinais rasos + 2 medios -> empate, vence media (FR-005).
  # Justificativa deve mencionar todos os 4 termos.
  _just=$(_get_justificativa_block "rode liste explique documente o texto")
  if [ -z "$_just" ]; then
    _fail "scenario_2_4_3" "justificativa vazia"
    return 1
  fi
  _missing=""
  for _termo in rode liste explique documente; do
    case "$_just" in
      *"$_termo"*) ;;
      *) _missing="$_missing $_termo" ;;
    esac
  done
  if [ -n "$_missing" ]; then
    _fail "scenario_2_4_3_termos" "termos ausentes da justificativa:$_missing — texto: $_just"
    return 1
  fi
  # Tambem deve citar a regra FR-005 ou a palavra "vence"/"mais profunda".
  case "$_just" in
    *"FR-005"*|*"mais profunda"*) return 0 ;;
  esac
  _fail "scenario_2_4_3_regra" "justificativa nao cita FR-005 nem 'mais profunda': $_just"
  return 1
}

# ----------------------------------------------------------------------
# 2.4.3: justificativa em input sem sinais cita "nenhum sinal"
# ----------------------------------------------------------------------
scenario_2_4_3_justificativa_zero_sinais() {
  _just=$(_get_justificativa_block "tokens completamente randomicos nada catalogo")
  case "$_just" in
    *"nenhum sinal"*) return 0 ;;
  esac
  _fail "scenario_2_4_3_zero_just" "justificativa nao cita 'nenhum sinal': $_just"
  return 1
}

# ----------------------------------------------------------------------
# 2.4.4: indeterminado -> manter-atual (input sem matches, tokens >=3)
# Ja coberto em scenario_2_4_1_zero_sinais_score_zero — assertiva
# explicita para o mapa.
# ----------------------------------------------------------------------
scenario_2_4_4_indeterminado_manter_atual() {
  _line=$(_get_score_line "tokens aleatorios sem catalogo total")
  case "$_line" in
    *"modelo=manter-atual"*) return 0 ;;
  esac
  _fail "scenario_2_4_4_indet" "esperado modelo=manter-atual para indeterminado, obtido: $_line"
  return 1
}

# ----------------------------------------------------------------------
# 2.4.5: manter-atual -> alternativa=none (fail-safe path)
# ----------------------------------------------------------------------
scenario_2_4_5_manter_atual_fallback_none_failsafe() {
  # Input <3 tokens -> fail-safe -> manter-atual / none.
  _line=$(sh "$CLASSIFY" "oi" 2>/dev/null | grep -E '^score=' | head -n 1)
  case "$_line" in
    "score=0 modelo=manter-atual alternativa=none"*) return 0 ;;
  esac
  _fail "scenario_2_4_5_failsafe" "esperado fail-safe -> score=0 manter-atual none, obtido: $_line"
  return 1
}

# ----------------------------------------------------------------------
# 2.4.4 + 2.4.5: cobertura completa do mapa via tabela explicita.
# Loop interno valida todos os 4 mapeamentos faixa->modelo->fallback.
# ----------------------------------------------------------------------
scenario_2_4_completa_tabela_mapa() {
  # Formato: "input|modelo_esperado|alternativa_esperada"
  _cases='rode liste conte|haiku|sonnet
explique documente resuma|sonnet|haiku
projete refatore arquitete|opus|sonnet
tokens aleatorios completamente|manter-atual|none'

  _OLD_IFS="$IFS"
  IFS='
'
  for _row in $_cases; do
    _input=$(printf '%s' "$_row" | awk -F'|' '{print $1}')
    _exp_mod=$(printf '%s' "$_row" | awk -F'|' '{print $2}')
    _exp_alt=$(printf '%s' "$_row" | awk -F'|' '{print $3}')
    _line=$(sh "$CLASSIFY" "$_input" 2>/dev/null | grep -E '^score=' | head -n 1)
    case "$_line" in
      *"modelo=$_exp_mod alternativa=$_exp_alt"*) ;;
      *)
        IFS="$_OLD_IFS"
        _fail "scenario_2_4_tabela" "input='$_input' esperado modelo=$_exp_mod alt=$_exp_alt; obtido: $_line"
        return 1
        ;;
    esac
  done
  IFS="$_OLD_IFS"
  return 0
}

run_all_scenarios
