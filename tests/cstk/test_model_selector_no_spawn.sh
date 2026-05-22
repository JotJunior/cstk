#!/bin/sh
# test_model_selector_no_spawn.sh
#
# Cobre subtarefas 5.2.1 e 5.2.2 da feature `model-selector` (FR-013e,
# CHK054, Edge Case "loop"). Garante:
#
#  (1) scripts/ da skill NAO contem nenhuma referencia textual a
#      mecanismos de spawn de subagente — tokens `Task`, `Agent`,
#      `claude-code`, `subagent` em codigo executavel devem ser zero.
#  (2) SKILL.md cita LITERALMENTE no Gotcha (e) que a skill "nao
#      spawna subagente" — invariante documental (FR-013e).
#
# Por que isso e invariante (FR-013e + Edge Case "loop"):
#   Uma skill que invoca subagente pode entrar em loop infinito:
#   orquestrador chama model-selector -> model-selector spawna outra
#   skill -> outra skill chama model-selector -> ... A skill foi
#   desenhada deliberadamente stateless e sem spawn para que o limite
#   de profundidade (3 niveis maximos no toolkit) seja respeitado
#   mesmo em invocacoes auto-encadeadas. O `allowed-tools` em SKILL.md
#   exclui `Task` e `Agent` — este teste valida que o codigo do scripts/
#   nao tenta contornar (ex: via Bash construindo string com `Task(...)`).
#
# Mecanismo:
#   grep estatico sobre `scripts/` filtrando comentarios shell que
#   iniciam com `#`. Padrao: `Task\|Agent\|claude-code\|subagent`.
#
# Falsos positivos esperados (e como evitar):
#   - Token "Task" em ingles aparece em comentarios e em docs como
#     palavra normal. Por isso o teste filtra comentarios shell. Se
#     algum identificador do codigo (variavel, funcao) usar o nome
#     "Task" como parte de algo nao relacionado a spawn, o filtro de
#     comentarios nao alcanca — vai ser preciso renomear. Aceitamos
#     o tradeoff: codigo POSIX da skill nao tem motivo para nomear
#     variaveis assim.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

SKILL_DIR="$REPO_ROOT/global/skills/model-selector"
SCRIPTS_DIR="$SKILL_DIR/scripts"
SKILL_MD="$SKILL_DIR/SKILL.md"
export SKILL_DIR SCRIPTS_DIR SKILL_MD

SPAWN_PATTERN='Task\|Agent\|claude-code\|subagent'

scenario_5_2_1_scripts_sem_token_de_spawn() {
  if [ ! -d "$SCRIPTS_DIR" ]; then
    _error "scripts_ausentes" "esperado $SCRIPTS_DIR"
    return 2
  fi
  # grep -rn + filtro de comentarios shell. Conservador: descarta
  # apenas linhas que iniciam com `#` apos whitespace.
  _hits=$(grep -rn "$SPAWN_PATTERN" "$SCRIPTS_DIR" 2>/dev/null \
            | grep -v '^[^:]*:[[:space:]]*[0-9][0-9]*:[[:space:]]*#' \
            || true)
  if [ -n "$_hits" ]; then
    _fail "token_de_spawn_em_scripts" \
      "padrao=$SPAWN_PATTERN; matches=$_hits"
    return 1
  fi
}

scenario_5_2_2_skill_md_cita_gotcha_sem_spawn() {
  if [ ! -f "$SKILL_MD" ]; then
    _error "skill_md_ausente" "esperado $SKILL_MD"
    return 2
  fi
  # Frase canonica do Gotcha (e). Tolerancia case-insensitive minima
  # via grep -F (literal exato — match deve preservar mensagem).
  if ! grep -F 'nao spawna subagente' "$SKILL_MD" >/dev/null 2>&1; then
    _fail "gotcha_sem_spawn_ausente" \
      "SKILL.md deve citar literalmente 'nao spawna subagente' (Gotcha (e), FR-013e)"
    return 1
  fi
}

run_all_scenarios
