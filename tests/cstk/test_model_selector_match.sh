#!/bin/sh
# test_model_selector_match.sh
#
# Cobre subtarefas 2.3.1 a 2.3.4 da feature `model-selector` (FASE 2,
# task 2.3). Valida o estagio "match contra catalogo" + regra de
# conservadorismo FR-005 em scripts/classify.sh.
#
# Contratos testados:
#   2.3.1  parsing awk streaming de references/sinais.md extrai 15
#          (termo, faixa, peso) ignorando header + separator.
#   2.3.2  match exato `grep -Fxq` (rejeita substring e prefix).
#   2.3.3  contadores por faixa acumulam pesos (rasa, media, profunda).
#   2.3.4  regra FR-005: faixa MAIS PROFUNDA com pelo menos 1 match vence
#          (empate ou nao, profunda > media > rasa).
#
# Convencao de scenarios: nome do scenario carrega a sub-id (ex:
# scenario_2_3_4_*). Output intermediario do classify.sh nesta task
# expoe linha `rasa=N media=N profunda=N faixa=X` — assercoes
# inspecionam essa linha de smoke. Output markdown final entra em 2.5.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

CLASSIFY="$REPO_ROOT/plugins/cstk/skills/model-selector/scripts/classify.sh"
export CLASSIFY

# Helper: extrai a linha "rasa=N media=N profunda=N faixa=X" do stdout
# do classify.sh para input dado. Imprime a linha (ou string vazia).
_get_signals_line() {
  _input="$1"
  sh "$CLASSIFY" "$_input" 2>/dev/null | grep -E '^rasa=' | head -n 1
}

# ----------------------------------------------------------------------
# 2.3.1 + 2.3.2: rasa pura — verbos rasos batem
# ----------------------------------------------------------------------
scenario_2_3_1_rasa_pura_match_exato() {
  # "rode liste grep e formate" -> tokens (rode, liste, grep, e, formate)
  # apos sanitizacao. 4 deles batem em rasa (rode, liste, grep, formate).
  # "e" nao bate (nao esta no catalogo).
  _line=$(_get_signals_line "rode liste grep e formate")
  if [ -z "$_line" ]; then
    _fail "scenario_2_3_1" "linha de sinais ausente em stdout"
    return 1
  fi
  # rasa=4 esperado (peso uniforme 1, 4 matches), media=0, profunda=0,
  # faixa=rasa.
  case "$_line" in
    *"rasa=4"*"media=0"*"profunda=0"*"faixa=rasa"*) return 0 ;;
  esac
  _fail "scenario_2_3_1" "esperado rasa=4 media=0 profunda=0 faixa=rasa, obtido: $_line"
  return 1
}

# ----------------------------------------------------------------------
# 2.3.3: media pura
# ----------------------------------------------------------------------
scenario_2_3_2_media_pura() {
  # "explique e documente o codigo" -> tokens com 2 media (explique,
  # documente). Token "o", "e", "codigo" nao batem.
  _line=$(_get_signals_line "explique e documente o codigo")
  case "$_line" in
    *"rasa=0"*"media=2"*"profunda=0"*"faixa=media"*) return 0 ;;
  esac
  _fail "scenario_2_3_2" "esperado faixa=media, obtido: $_line"
  return 1
}

# ----------------------------------------------------------------------
# 2.3.3: profunda pura
# ----------------------------------------------------------------------
scenario_2_3_3_profunda_pura() {
  # "refatore e arquitete a solucao" -> tokens com 2 profunda (refatore,
  # arquitete). Token "e", "a", "solucao" nao batem.
  _line=$(_get_signals_line "refatore e arquitete a solucao")
  case "$_line" in
    *"rasa=0"*"media=0"*"profunda=2"*"faixa=profunda"*) return 0 ;;
  esac
  _fail "scenario_2_3_3" "esperado faixa=profunda, obtido: $_line"
  return 1
}

# ----------------------------------------------------------------------
# 2.3.4: empate rasa=media -> vence MEDIA (FR-005, mais profunda das
# nao-zero)
# ----------------------------------------------------------------------
scenario_2_3_4_empate_rasa_media_vence_media() {
  # 2 rasos (rode, liste) + 2 medios (explique, documente) + tokens
  # filler -> empate rasa=2 media=2 profunda=0.
  _line=$(_get_signals_line "rode liste explique documente o texto")
  case "$_line" in
    *"rasa=2"*"media=2"*"profunda=0"*"faixa=media"*) return 0 ;;
  esac
  _fail "scenario_2_3_4_empate_rm" "esperado faixa=media (FR-005), obtido: $_line"
  return 1
}

# ----------------------------------------------------------------------
# 2.3.4: empate media=profunda -> vence PROFUNDA (FR-005)
# ----------------------------------------------------------------------
scenario_2_3_4_empate_media_profunda_vence_profunda() {
  # 2 medios (explique, documente) + 2 profundos (projete, refatore) +
  # filler -> empate media=2 profunda=2.
  _line=$(_get_signals_line "explique documente projete refatore o sistema")
  case "$_line" in
    *"rasa=0"*"media=2"*"profunda=2"*"faixa=profunda"*) return 0 ;;
  esac
  _fail "scenario_2_3_4_empate_mp" "esperado faixa=profunda (FR-005), obtido: $_line"
  return 1
}

# ----------------------------------------------------------------------
# 2.3.4: triplo empate (rasa=1, media=1, profunda=1) -> vence PROFUNDA
# (mais profunda das nao-zero)
# ----------------------------------------------------------------------
scenario_2_3_4_triplo_empate_vence_profunda() {
  # 1 sinal por faixa + filler.
  _line=$(_get_signals_line "rode explique projete o texto")
  case "$_line" in
    *"rasa=1"*"media=1"*"profunda=1"*"faixa=profunda"*) return 0 ;;
  esac
  _fail "scenario_2_3_4_triplo" "esperado faixa=profunda (FR-005), obtido: $_line"
  return 1
}

# ----------------------------------------------------------------------
# 2.3.2: verbo nao listado -> nao contribui para nenhum contador
# (tokens validos >=3, sem match nenhum -> faixa=indeterminado)
# ----------------------------------------------------------------------
scenario_2_3_2_verbo_nao_listado_ignorado() {
  # 4 tokens sanitizados, nenhum no catalogo -> rasa=0 media=0 profunda=0,
  # faixa=indeterminado.
  _line=$(_get_signals_line "tokens completamente randomicos nada catalogo")
  case "$_line" in
    *"rasa=0"*"media=0"*"profunda=0"*"faixa=indeterminado"*) return 0 ;;
  esac
  _fail "scenario_2_3_2_no_match" "esperado faixa=indeterminado, obtido: $_line"
  return 1
}

# ----------------------------------------------------------------------
# 2.3.2: match e EXATO (rejeita substring). Token "rod" NAO deve casar
# com termo "rode" do catalogo.
# ----------------------------------------------------------------------
scenario_2_3_2_match_rejeita_substring() {
  # "rod rod rod" -> 3 tokens "rod". Se substring match, casaria com
  # "rode" e produziria rasa=3. Com `grep -Fxq` (exact-line), NAO casa.
  _line=$(_get_signals_line "rod rod rod")
  case "$_line" in
    *"rasa=0"*"media=0"*"profunda=0"*"faixa=indeterminado"*) return 0 ;;
  esac
  _fail "scenario_2_3_2_substring" "substring matched indevidamente (esperado rasa=0): $_line"
  return 1
}

# ----------------------------------------------------------------------
# 2.3.3: deduplicacao — token repetido conta UMA vez
# ----------------------------------------------------------------------
scenario_2_3_3_token_repetido_conta_uma_vez() {
  # "rode rode rode foo" -> 4 tokens, mas "rode" dedup -> conta 1.
  # rasa=1, faixa=rasa.
  _line=$(_get_signals_line "rode rode rode foo")
  case "$_line" in
    *"rasa=1"*"media=0"*"profunda=0"*"faixa=rasa"*) return 0 ;;
  esac
  _fail "scenario_2_3_3_dedup" "esperado rasa=1 (dedup), obtido: $_line"
  return 1
}

# ----------------------------------------------------------------------
# 2.3.1: estresse de parsing — todos os sinais do catalogo reconhecidos
# como linhas validas. O catalogo foi expandido de 15 (MVP) para 45
# (15 por faixa) pela feature model-routing-por-onda (FR-018); este
# teste guarda contra regressao do formato do catalogo.
# ----------------------------------------------------------------------
scenario_2_3_1_parsing_catalogo_extrai_45_sinais() {
  # Esta nao usa o classify.sh diretamente, mas valida que o awk de
  # parsing (mesma logica) extrai 45 sinais.
  _count=$(awk -F'|' '
    /^\|---/ { next }
    /^\|/ {
      t = $2; f = $3
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", t)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", f)
      if (t == "termo" || t == "") next
      if (f != "rasa" && f != "media" && f != "profunda") next
      c++
    }
    END { print c+0 }
  ' "$REPO_ROOT/plugins/cstk/skills/model-selector/references/sinais.md")
  if [ "$_count" != "45" ]; then
    _fail "scenario_2_3_1_parsing" "esperado 45 sinais, parser extraiu: $_count"
    return 1
  fi
}

# ----------------------------------------------------------------------
# 2.3.1.b: distribuicao balanceada — 15 sinais por faixa apos a
# expansao FR-018. Guarda contra desbalanceamento acidental do catalogo.
# ----------------------------------------------------------------------
scenario_2_3_1_distribuicao_15_por_faixa() {
  _dist=$(awk -F'|' '
    /^\|---/ { next }
    /^\|/ {
      t = $2; f = $3
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", t)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", f)
      if (t == "termo" || t == "") next
      if (f != "rasa" && f != "media" && f != "profunda") next
      cnt[f]++
    }
    END { printf "%d|%d|%d", cnt["rasa"]+0, cnt["media"]+0, cnt["profunda"]+0 }
  ' "$REPO_ROOT/plugins/cstk/skills/model-selector/references/sinais.md")
  if [ "$_dist" != "15|15|15" ]; then
    _fail "scenario_2_3_1_dist" "esperado 15|15|15 (rasa|media|profunda), obtido: $_dist"
    return 1
  fi
}

run_all_scenarios
