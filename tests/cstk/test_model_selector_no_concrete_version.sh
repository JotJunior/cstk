#!/bin/sh
# test_model_selector_no_concrete_version.sh
#
# Cobre subtarefa 2.5.3 da feature `model-selector` (CHK044, FR-002a,
# dec-005). Garante que a skill NUNCA emite strings versionadas
# concretas tipo `claude-haiku-4-5`, `claude-opus-4-7`, `claude-sonnet-4-6`
# — apenas rotulos abstratos `haiku|sonnet|opus|manter-atual`.
#
# Por que isso e invariante (dec-005, FR-002a):
#   Modelos da Anthropic deprecam em ciclos de 6-18 meses. Uma skill
#   que codifica "claude-haiku-4-5" no output ou na documentacao vira
#   obsoleta no instante em que a familia avanca para 4-6/4-7. Rotulo
#   abstrato (`haiku`) e estavel — o orquestrador mapeia para a versao
#   corrente lendo `~/.claude/config` ou similar.
#
# Cobertura:
#   1. grep recursivo em SKILL.md + scripts/ + references/ procura
#      padrao `claude-[a-z]+-[0-9]` — esperado ZERO hits.
#   2. invoca classify.sh em ~5 inputs cobrindo cada faixa + edge cases;
#      output stdout NUNCA pode conter o padrao versionado.
#
# Contrato de regex: `claude-[a-z]+-[0-9]`
#   - Casa `claude-haiku-4`, `claude-opus-4-7`, `claude-sonnet-4-6`, etc.
#   - NAO casa o nome aspect-keyword `claude-code` (sem digito).
#   - NAO casa palavra solta `claude` (sem hifen+familia+digito).

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

SKILL_DIR="$REPO_ROOT/plugins/cstk/skills/model-selector"
CLASSIFY="$SKILL_DIR/scripts/classify.sh"
export SKILL_DIR CLASSIFY

# Padrao versionado proibido (alinhado com tasks.md 2.5.3).
VERSION_REGEX='claude-[a-z]+-[0-9]'

scenario_2_5_3_skill_md_sem_versao_concreta() {
  if [ ! -f "$SKILL_DIR/SKILL.md" ]; then
    _error "skill_md_ausente" "esperado $SKILL_DIR/SKILL.md"
    return 2
  fi
  _hits=$(grep -E "$VERSION_REGEX" "$SKILL_DIR/SKILL.md" || true)
  if [ -n "$_hits" ]; then
    _fail "SKILL.md cita versao concreta" "padrao=$VERSION_REGEX; matches=$_hits"
    return 1
  fi
}

scenario_2_5_3_scripts_sem_versao_concreta() {
  if [ ! -d "$SKILL_DIR/scripts" ]; then
    _error "scripts_ausentes" "esperado $SKILL_DIR/scripts/"
    return 2
  fi
  # grep -r em todo o subdir scripts/ — qualquer hit reprova.
  _hits=$(grep -rE "$VERSION_REGEX" "$SKILL_DIR/scripts" 2>/dev/null || true)
  if [ -n "$_hits" ]; then
    _fail "scripts/ citam versao concreta" "padrao=$VERSION_REGEX; matches=$_hits"
    return 1
  fi
}

scenario_2_5_3_references_sem_versao_concreta() {
  if [ ! -d "$SKILL_DIR/references" ]; then
    _error "references_ausentes" "esperado $SKILL_DIR/references/"
    return 2
  fi
  _hits=$(grep -rE "$VERSION_REGEX" "$SKILL_DIR/references" 2>/dev/null || true)
  if [ -n "$_hits" ]; then
    _fail "references/ citam versao concreta" "padrao=$VERSION_REGEX; matches=$_hits"
    return 1
  fi
}

# Helper interno: roda classify.sh com input dado e reprova se output
# tiver match para o regex versionado. Mantem cobertura nas 5 faixas.
_assert_output_sem_versao() {
  _label="$1"
  _input="$2"
  _out=$(sh "$CLASSIFY" "$_input" 2>/dev/null) || true
  _hits=$(printf '%s' "$_out" | grep -E "$VERSION_REGEX" || true)
  if [ -n "$_hits" ]; then
    _fail "output cita versao concreta [$_label]" "input=$_input; matches=$_hits"
    return 1
  fi
}

scenario_2_5_3_output_rasa_sem_versao() {
  # Faixa rasa: tokens "rode", "grep" estao no catalogo MVP.
  _assert_output_sem_versao "rasa" "rode o grep no arquivo de log" || return 1
}

scenario_2_5_3_output_media_sem_versao() {
  # Faixa media: tokens "implemente", "feature", "endpoint" tipicamente
  # listados no catalogo MVP.
  _assert_output_sem_versao "media" "implemente a feature do endpoint de login" || return 1
}

scenario_2_5_3_output_profunda_sem_versao() {
  # Faixa profunda: tokens "arquitete", "projete", "refatore" — verbos
  # de design tipicamente listados como profunda.
  _assert_output_sem_versao "profunda" "arquitete um sistema de cache distribuido com consistencia" || return 1
}

scenario_2_5_3_output_indeterminado_sem_versao() {
  # Input com 3+ tokens nao listados no catalogo -> faixa indeterminada
  # -> manter-atual. Rotulo abstrato no output, sem versao.
  _assert_output_sem_versao "indeterminado" "alfa beta gama delta epsilon" || return 1
}

scenario_2_5_3_output_edge_failsafe_sem_versao() {
  # Edge: fail-safe (<3 tokens). Output tem caminho de codigo distinto;
  # checamos que tambem nao vaza versao concreta.
  _assert_output_sem_versao "edge_failsafe" "rode" || return 1
}

run_all_scenarios
