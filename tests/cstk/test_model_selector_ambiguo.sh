#!/bin/sh
# test_model_selector_ambiguo.sh
#
# Cobre subtarefa 2.6.4 da feature `model-selector` (Ref: FR-005, dec-004).
# Valida a regra CONSERVADORA aplicada quando o input contem sinais em
# faixas DIFERENTES: vence a faixa MAIS PROFUNDA presente, mesmo que
# tenha menos ocorrencias.
#
# FR-005 (literal):
#   Em empate ou conflito cross-faixa, vence a faixa mais profunda. Ordem
#   de profundidade: profunda > media > rasa. Justificativa cita
#   explicitamente a regra (texto "FR-005" ou "mais profunda").
#
# Casos cobertos:
#   - 1 raso + 1 medio                    -> sonnet (vence media)
#   - 1 raso + 1 profundo                 -> opus   (vence profunda)
#   - 1 medio + 1 profundo                -> opus   (vence profunda)
#   - 1 raso + 1 medio + 1 profundo       -> opus   (vence profunda, 3 nao-zero)
#   - 5 rasos + 1 medio                   -> sonnet (vence media, ate desbalanceado)
#   - 5 rasos + 1 profundo                -> opus   (vence profunda, dramatico)
#   - Justificativa cita FR-005 / "mais profunda"

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
# 2.6.4.a: raso + medio -> sonnet (vence media)
# ----------------------------------------------------------------------
scenario_2_6_4_raso_mais_medio_vence_media() {
  _input="rode e explique o trecho"
  _mod=$(_modelo_sugerido "$_input")
  if [ "$_mod" != "sonnet" ]; then
    _fail "raso_mais_medio" "esperado 'sonnet' (FR-005 vence media), obtido: '$_mod'"
    return 1
  fi
}

# ----------------------------------------------------------------------
# 2.6.4.b: raso + profundo -> opus (vence profunda)
# ----------------------------------------------------------------------
scenario_2_6_4_raso_mais_profundo_vence_profunda() {
  _input="rode e refatore o modulo"
  _mod=$(_modelo_sugerido "$_input")
  if [ "$_mod" != "opus" ]; then
    _fail "raso_mais_profundo" "esperado 'opus' (FR-005 vence profunda), obtido: '$_mod'"
    return 1
  fi
}

# ----------------------------------------------------------------------
# 2.6.4.c: medio + profundo -> opus (vence profunda)
# ----------------------------------------------------------------------
scenario_2_6_4_medio_mais_profundo_vence_profunda() {
  _input="explique e arquitete o sistema"
  _mod=$(_modelo_sugerido "$_input")
  if [ "$_mod" != "opus" ]; then
    _fail "medio_mais_profundo" "esperado 'opus', obtido: '$_mod'"
    return 1
  fi
}

# ----------------------------------------------------------------------
# 2.6.4.d: 3 faixas simultaneamente -> opus (vence a mais profunda)
# ----------------------------------------------------------------------
scenario_2_6_4_tres_faixas_simultaneas_vence_profunda() {
  _input="rode explique e refatore o modulo"
  _mod=$(_modelo_sugerido "$_input")
  if [ "$_mod" != "opus" ]; then
    _fail "tres_faixas" "esperado 'opus' com 3 faixas presentes, obtido: '$_mod'"
    return 1
  fi
  # Justificativa deve citar FR-005 ou "mais profunda".
  _just=$(_get_justificativa "$_input")
  case "$_just" in
    *"FR-005"*|*"mais profunda"*) ;;
    *)
      _fail "justificativa_sem_regra" "justificativa nao cita FR-005 nem 'mais profunda': $_just"
      return 1
      ;;
  esac
}

# ----------------------------------------------------------------------
# 2.6.4.e: 5 rasos + 1 medio -> sonnet (regra conservadora vence
# desbalanceamento de contagem)
# ----------------------------------------------------------------------
scenario_2_6_4_cinco_rasos_um_medio_vence_media() {
  _input="rode liste conte grep formate explique"
  _mod=$(_modelo_sugerido "$_input")
  if [ "$_mod" != "sonnet" ]; then
    _fail "5r_1m" "esperado 'sonnet' (FR-005 vence media), obtido: '$_mod'"
    return 1
  fi
  # Score sempre teto 2 (CHK069).
  _line=$(_score_line "$_input")
  case "$_line" in
    "score=2 "*) ;;
    *)
      _fail "5r_1m_score" "esperado 'score=2 ...', obtido: '$_line'"
      return 1
      ;;
  esac
}

# ----------------------------------------------------------------------
# 2.6.4.f: 5 rasos + 1 profundo -> opus (regra conservadora dramatica)
# ----------------------------------------------------------------------
scenario_2_6_4_cinco_rasos_um_profundo_vence_profunda() {
  _input="rode liste conte grep formate refatore"
  _mod=$(_modelo_sugerido "$_input")
  if [ "$_mod" != "opus" ]; then
    _fail "5r_1p" "esperado 'opus' (FR-005 vence profunda mesmo 5:1), obtido: '$_mod'"
    return 1
  fi
}

# ----------------------------------------------------------------------
# 2.6.4.g: justificativa em caso ambiguo cita CADA sinal e a regra
# ----------------------------------------------------------------------
scenario_2_6_4_justificativa_cita_sinais_e_regra() {
  _input="rode explique refatore"
  _just=$(_get_justificativa "$_input")
  for _termo in rode explique refatore; do
    case "$_just" in
      *"$_termo"*) ;;
      *)
        _fail "justificativa_termo_ausente" "termo '$_termo' ausente: $_just"
        return 1
        ;;
    esac
  done
  case "$_just" in
    *"FR-005"*|*"mais profunda"*) return 0 ;;
  esac
  _fail "justificativa_regra_ausente" "regra FR-005/mais profunda ausente: $_just"
  return 1
}

# ----------------------------------------------------------------------
# 2.6.4.h: tabela de casos compactos (cobertura grossa via loop)
# ----------------------------------------------------------------------
scenario_2_6_4_tabela_cross_faixa() {
  # Formato: "input|modelo_esperado"
  _cases='rode liste explique|sonnet
explique documente refatore|opus
rode conte arquitete projete|opus
explique compare resuma escolha|opus
liste conte formate traduza|sonnet'

  _OLD_IFS="$IFS"
  IFS='
'
  for _row in $_cases; do
    _input=$(printf '%s' "$_row" | awk -F'|' '{print $1}')
    _exp=$(printf '%s' "$_row" | awk -F'|' '{print $2}')
    _mod=$(_modelo_sugerido "$_input")
    if [ "$_mod" != "$_exp" ]; then
      IFS="$_OLD_IFS"
      _fail "tabela_cross_faixa" "input='$_input' esperado '$_exp', obtido: '$_mod'"
      return 1
    fi
  done
  IFS="$_OLD_IFS"
  return 0
}

run_all_scenarios
