#!/bin/sh
# test_model_selector_skill_lines.sh
#
# Cobre subtarefas 1.2.4 e 1.2.5 da feature `model-selector` (FR-014,
# CHK028, CHK029, CHK030, CHK031, SC-004).
#
# Contrato testado em global/skills/model-selector/SKILL.md:
#   1. Progressive disclosure: `wc -l SKILL.md` < 200 (limite operacional
#      199, conforme tasks.md §1.2.4). Threshold de falha: >=200.
#   2. Frontmatter contem description com trigger + anti-trigger via
#      regex `Use quando.*NAO use` (CHK029, CHK030).
#   3. Frontmatter declara `allowed-tools` sem `Task` ou `Agent`
#      (FR-013e — skill nao spawna subagente, CHK031).
#   4. Frontmatter contem campos obrigatorios do toolkit: `description`
#      e `allowed-tools` (CHK031).

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

SKILL_MD="$REPO_ROOT/global/skills/model-selector/SKILL.md"
export SKILL_MD

scenario_skill_md_existe() {
  if [ ! -f "$SKILL_MD" ]; then
    _fail "SKILL.md ausente" "esperado $SKILL_MD"
    return 1
  fi
}

scenario_skill_md_menor_que_200_linhas() {
  # SC-004: progressive disclosure. wc -l literal, qualquer linha conta
  # (frontmatter, branco, code fences). Limite operacional = 199.
  _lines=$(wc -l <"$SKILL_MD" | tr -d ' ')
  if [ "$_lines" -ge 200 ]; then
    _fail "SKILL.md >= 200 linhas" "wc -l = $_lines (limite operacional = 199)"
    return 1
  fi
}

# Extrai bloco frontmatter (entre as duas primeiras linhas '---').
_extract_frontmatter() {
  awk '
    BEGIN { in_fm = 0; count = 0 }
    /^---[[:space:]]*$/ {
      count++
      if (count == 1) { in_fm = 1; next }
      if (count == 2) { in_fm = 0; exit }
    }
    in_fm { print }
  ' "$SKILL_MD"
}

scenario_frontmatter_description_trigger_e_antitrigger() {
  # CHK029, CHK030: description precisa de 1+ trigger E 1+ anti-trigger.
  # O INVARIANTE e a presenca das duas clausulas, nao a frase literal:
  # aceita a forma original ("Use quando ... NAO use") e a convencao
  # enxuta do catalogo pos-5.15.0 ("Use ANTES ... Skip:") — o trim de
  # boot-tax da description manteve trigger+anti-trigger.
  # DOTALL via tr para colapsar newlines.
  _fm=$(_extract_frontmatter)
  if [ -z "$_fm" ]; then
    _fail "frontmatter vazio" "esperado bloco YAML entre '---' no topo"
    return 1
  fi
  # Colapsa newlines para 1 linha e aplica regex.
  _flat=$(printf '%s' "$_fm" | tr '\n' ' ')
  if ! printf '%s' "$_flat" | grep -Eq 'Use (quando|ANTES)'; then
    _fail "frontmatter sem clausula de trigger" \
      "regex 'Use (quando|ANTES)' nao casou no frontmatter"
    return 1
  fi
  if ! printf '%s' "$_flat" | grep -Eq '(NAO use|Skip:)'; then
    _fail "frontmatter sem clausula de anti-trigger" \
      "regex '(NAO use|Skip:)' nao casou no frontmatter"
    return 1
  fi
}

scenario_frontmatter_tem_description_obrigatorio() {
  # CHK031: campo `description` obrigatorio.
  _fm=$(_extract_frontmatter)
  if ! printf '%s\n' "$_fm" | grep -Eq '^description:'; then
    _fail "campo description ausente" "frontmatter deve declarar 'description:'"
    return 1
  fi
}

scenario_frontmatter_tem_allowed_tools_obrigatorio() {
  # CHK031: campo `allowed-tools` obrigatorio.
  _fm=$(_extract_frontmatter)
  if ! printf '%s\n' "$_fm" | grep -Eq '^allowed-tools:'; then
    _fail "campo allowed-tools ausente" "frontmatter deve declarar 'allowed-tools:'"
    return 1
  fi
}

scenario_allowed_tools_sem_task_nem_agent() {
  # FR-013e + CHK031: allowed-tools NAO pode listar `Task` ou `Agent`
  # (skill nao spawna subagente). Procura no bloco que comeca com
  # `allowed-tools:` ate a proxima chave (linha sem indentacao) ou
  # fim do frontmatter.
  _fm=$(_extract_frontmatter)
  _tools=$(printf '%s\n' "$_fm" | awk '
    /^allowed-tools:/ { in_block = 1; next }
    in_block && /^[^[:space:]-]/ { in_block = 0 }
    in_block { print }
  ')
  if [ -z "$_tools" ]; then
    _fail "bloco allowed-tools vazio" \
      "esperado lista de tools sob 'allowed-tools:'"
    return 1
  fi
  # Match exato de item de lista YAML `- Task` ou `- Agent` (com
  # possivel whitespace ao redor).
  if printf '%s\n' "$_tools" | grep -Eq '^[[:space:]]*-[[:space:]]+(Task|Agent)[[:space:]]*$'; then
    _bad=$(printf '%s\n' "$_tools" | grep -E '^[[:space:]]*-[[:space:]]+(Task|Agent)[[:space:]]*$')
    _fail "allowed-tools contem Task/Agent" \
      "FR-013e proibe tool de spawn de subagente; achei: $_bad"
    return 1
  fi
}

run_all_scenarios
