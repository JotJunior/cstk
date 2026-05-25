#!/bin/sh
# test_skills-cache-protocol.sh — valida que SKILL.md de specify/clarify/plan/
# execute-task incluem o bloco "Leitura de artefatos foundational" sem
# quebrar estrutura existente (FR-CACHE-008, FR-CACHE-008A, SC-002).
#
# Como "diff=0 do output do LLM" eh nao-testavel em CI sem LLM call, este
# teste valida estrutural: YAML frontmatter parse OK, secoes pre-existentes
# preservadas, bloco novo inserido na posicao correta.
#
# Ref: docs/specs/_archived/agente-00c-artifact-cache/tasks.md T2.5

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

SKILLS_DIR="$REPO_ROOT/global/skills"

# Skills afetadas pelo protocolo de cache
_AFFECTED_SKILLS="specify clarify plan execute-task"

# Bloco signature: secao introduzida em T2.1-T2.4
_CACHE_BLOCK_HEADING="## Leitura de artefatos foundational (briefing + constitution)"

# Comando de fluxo (anchor pos-bloco) — varia por skill
_fluxo_anchor_for() {
  case "$1" in
    execute-task) printf '## FLUXO OBRIGATORIO DE EXECUCAO' ;;
    *)            printf '## FLUXO DE EXECUCAO' ;;
  esac
}

# Argumentos anchor (pre-bloco) — varia por skill
_args_anchor_for() {
  case "$1" in
    execute-task) printf '## Tarefa Solicitada' ;;
    *)            printf '## Argumentos' ;;
  esac
}

# Cenarios

_for_each_skill() {
  _fn=$1
  for _s in $_AFFECTED_SKILLS; do
    _skill_path="$SKILLS_DIR/$_s/SKILL.md"
    "$_fn" "$_s" "$_skill_path" || return 1
  done
}

_check_yaml_frontmatter() {
  _skill=$1
  _path=$2
  # Primeira linha deve ser ---
  _first=$(head -n1 "$_path")
  if [ "$_first" != "---" ]; then
    _fail "skill=$_skill: primeira linha nao eh '---' (got: '$_first')"
    return 1
  fi
  # Deve fechar com --- em alguma das primeiras 30 linhas
  _close_line=$(awk 'NR>1 && /^---$/ { print NR; exit }' "$_path")
  if [ -z "$_close_line" ]; then
    _fail "skill=$_skill: YAML frontmatter nao fechado (--- ausente nas primeiras 30 linhas)"
    return 1
  fi
  # name: field deve estar presente
  if ! head -n "$_close_line" "$_path" | grep -qE "^name:"; then
    _fail "skill=$_skill: campo 'name:' ausente do frontmatter"
    return 1
  fi
  return 0
}

_check_cache_block_present() {
  _skill=$1
  _path=$2
  if ! grep -qF "$_CACHE_BLOCK_HEADING" "$_path"; then
    _fail "skill=$_skill: bloco '$_CACHE_BLOCK_HEADING' nao encontrado"
    return 1
  fi
  return 0
}

_check_cache_block_before_fluxo() {
  _skill=$1
  _path=$2
  _fluxo=$(_fluxo_anchor_for "$_skill")
  _cache_line=$(grep -nF "$_CACHE_BLOCK_HEADING" "$_path" | head -n1 | cut -d: -f1)
  _fluxo_line=$(grep -nF "$_fluxo" "$_path" | head -n1 | cut -d: -f1)
  if [ -z "$_cache_line" ] || [ -z "$_fluxo_line" ]; then
    _fail "skill=$_skill: nao foi possivel localizar bloco cache (line=$_cache_line) ou fluxo (line=$_fluxo_line)"
    return 1
  fi
  if [ "$_cache_line" -ge "$_fluxo_line" ]; then
    _fail "skill=$_skill: cache block (linha $_cache_line) deve vir ANTES de fluxo (linha $_fluxo_line)"
    return 1
  fi
  return 0
}

_check_cache_block_after_argumentos() {
  _skill=$1
  _path=$2
  _args=$(_args_anchor_for "$_skill")
  _args_line=$(grep -nF "$_args" "$_path" | head -n1 | cut -d: -f1)
  _cache_line=$(grep -nF "$_CACHE_BLOCK_HEADING" "$_path" | head -n1 | cut -d: -f1)
  if [ -z "$_args_line" ] || [ -z "$_cache_line" ]; then
    _fail "skill=$_skill: ancoras nao localizadas (args=$_args_line, cache=$_cache_line)"
    return 1
  fi
  if [ "$_cache_line" -le "$_args_line" ]; then
    _fail "skill=$_skill: cache block (linha $_cache_line) deve vir DEPOIS de argumentos (linha $_args_line)"
    return 1
  fi
  return 0
}

_check_state_cache_ref_present() {
  _skill=$1
  _path=$2
  if ! grep -qF "state-cache.sh get-resumo" "$_path"; then
    _fail "skill=$_skill: referencia a 'state-cache.sh get-resumo' ausente do bloco"
    return 1
  fi
  if ! grep -qF "state-cache.sh metrics-bump" "$_path"; then
    _fail "skill=$_skill: referencia a 'state-cache.sh metrics-bump' ausente do bloco"
    return 1
  fi
  return 0
}

_check_fr_reference() {
  _skill=$1
  _path=$2
  # Bloco deve referenciar FR-CACHE-008 (ou FR-CACHE-014) para rastreabilidade
  if ! grep -qE "FR-CACHE-(008|014)" "$_path"; then
    _fail "skill=$_skill: bloco deve referenciar FR-CACHE-008 ou FR-CACHE-014"
    return 1
  fi
  return 0
}

_check_pre_existing_sections_present() {
  _skill=$1
  _path=$2
  # Cada skill tem seu set de secoes essenciais nao-relacionadas ao cache
  case "$_skill" in
    specify)
      for _expected in "## Pre-requisitos" "## Proximos passos" "## Argumentos" "## ETAPA 1: ANALISE" "## ETAPA 6: SALVAMENTO" "## Gotchas"; do
        grep -qF "$_expected" "$_path" || { _fail "skill=$_skill: secao pre-existente ausente: $_expected"; return 1; }
      done
      ;;
    clarify)
      for _expected in "## Pre-requisitos" "## Proximos passos" "## Argumentos" "## ETAPA 1: LOCALIZAR SPEC" "## ETAPA 6: REPORTAR" "## Gotchas"; do
        grep -qF "$_expected" "$_path" || { _fail "skill=$_skill: secao pre-existente ausente: $_expected"; return 1; }
      done
      ;;
    plan)
      for _expected in "## Pre-requisitos" "## Proximos passos" "## Argumentos" "## ETAPA 1: CONTEXTO" "## ETAPA 8: SALVAMENTO" "## Gotchas"; do
        grep -qF "$_expected" "$_path" || { _fail "skill=$_skill: secao pre-existente ausente: $_expected"; return 1; }
      done
      ;;
    execute-task)
      for _expected in "## Pre-requisitos" "## Proximos passos" "## Tarefa Solicitada" "## ETAPA 1: ANALISE" "## ETAPA 9: ATUALIZACAO" "## Gotchas"; do
        grep -qF "$_expected" "$_path" || { _fail "skill=$_skill: secao pre-existente ausente: $_expected"; return 1; }
      done
      ;;
  esac
  return 0
}

# Scenarios — um por skill x check (4 skills x 6 checks = 24, mas agrupados em 6 cenarios)

scenario_yaml_frontmatter_valido_em_4_skills() {
  _for_each_skill _check_yaml_frontmatter
}

scenario_bloco_cache_presente_em_4_skills() {
  _for_each_skill _check_cache_block_present
}

scenario_bloco_cache_antes_de_fluxo_em_4_skills() {
  _for_each_skill _check_cache_block_before_fluxo
}

scenario_bloco_cache_depois_de_argumentos_em_4_skills() {
  _for_each_skill _check_cache_block_after_argumentos
}

scenario_bloco_cache_referencia_primitiva_em_4_skills() {
  _for_each_skill _check_state_cache_ref_present
}

scenario_bloco_cache_tem_ref_fr_em_4_skills() {
  _for_each_skill _check_fr_reference
}

scenario_secoes_pre_existentes_preservadas_em_4_skills() {
  _for_each_skill _check_pre_existing_sections_present
}

run_all_scenarios
