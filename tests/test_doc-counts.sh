#!/bin/sh
# test_doc-counts.sh — guarda numeros DERIVADOS do repositorio contra drift na
# documentacao de entrada (README.md). Anti-drift (backlog P0.3).
#
# Motivacao: o README ja declarou "20 skills" com 23 pastas reais. Este teste
# falha (FAIL) quando esse numero, ou a listagem de skills, diverge da realidade,
# fechando o loop de manutencao.
#
# Por que NAO guardamos a contagem de scenarios da suite (como o P0.3 sugeria):
#   1. O numero e nao-deterministico — alguns tests (ex: model_selector_corpus)
#      sao GERADOS sob demanda durante a execucao, entao `run.sh --list` retorna
#      contagens diferentes antes/depois de uma rodada completa.
#   2. A unica doc que cita esse numero (CLAUDE.md) e gitignored/per-usuario,
#      logo um guard nao valeria em CI.
#   Resultado: pinar esse numero geraria FAIL espurio. O CLAUDE.md o cita de
#   forma aproximada e aponta para `run.sh --list` como fonte exata.
#
# NAO mapeia 1:1 para um script — e um teste de INVARIANTE do repositorio.
# Registrado como interno em tests/run.sh::_is_internal_test (lado dos tests).
#
# POSIX sh puro. Sem set -eu (convencao do harness — ver tests/README.md).

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

README="$REPO_ROOT/README.md"
SKILLS_DIR="$REPO_ROOT/global/skills"

# _count_skills: numero de subdiretorios imediatos de global/skills/.
_count_skills() {
  find "$SKILLS_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' '
}

# O numero "<N> skills globais" no README bate com a contagem real de pastas.
# README e versionado -> esta guarda e ativa tambem em CI.
scenario_skills_count_matches_readme() {
  [ -f "$README" ] || { _error missing "README.md ausente"; return 2; }
  _real=$(_count_skills)
  _doc=$(grep -oE '[0-9]+ skills globais' "$README" | head -1 | grep -oE '^[0-9]+')
  if [ -z "$_doc" ]; then
    printf 'README.md nao declara "<N> skills globais"\n' >&2
    return 1
  fi
  if [ "$_doc" != "$_real" ]; then
    printf 'drift: README declara %s skills globais, repo tem %s\n' "$_doc" "$_real" >&2
    return 1
  fi
  return 0
}

# Toda pasta de skill aparece em algum lugar do README (sem skill ausente da doc
# de entrada — foi exatamente esse o gap com agente-00c-runtime/decision-tree/
# model-selector). Baixa rotatividade: so muda ao adicionar/remover skill.
scenario_all_skills_referenced_in_readme() {
  [ -f "$README" ] || { _error missing "README.md ausente"; return 2; }
  _missing=""
  for _dir in "$SKILLS_DIR"/*/; do
    [ -d "$_dir" ] || continue
    _name=$(basename "$_dir")
    grep -q "$_name" "$README" || _missing="$_missing $_name"
  done
  if [ -n "$_missing" ]; then
    printf 'skills nao referenciadas no README:%s\n' "$_missing" >&2
    return 1
  fi
  return 0
}

run_all_scenarios
