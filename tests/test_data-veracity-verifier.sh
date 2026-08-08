#!/bin/sh
# test_data-veracity-verifier.sh — smoke textual: trava de regressao do contrato
# do subagente READ-ONLY `data-veracity-verifier` (Principio VI — Veracidade de
# Dados / Zero Fabricacao).
#
# Contexto: um agente autonomo inventou dados (nomes de propriedades, valores
# financeiros, status) que nao existiam na API que deveria ter consultado. O
# verificador e o "double check" do anti-fabricacao: audita um artefato e
# classifica cada dado factual concreto como SOURCED/PROPOSAL/UNSOURCED contra
# fontes permitidas, recomendando proceed|human_block. Ele NAO corrige — so
# reporta (read-only). Se o contrato sumir do prompt, a defesa some silenciosamente.
#
# Natureza: assert TEXTUAL no .md do agente + na fiacao dos 2 orquestradores que
# o invocam. NAO mapeia 1:1 a um .sh — interno em tests/run.sh::_is_internal_test
# (orphan-check), existence-guarded.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

AGENT="$REPO_ROOT/plugins/cstk/agents/data-veracity-verifier.md"
ORCH_AGENTE="$REPO_ROOT/plugins/cstk/agents/agente-00c-orchestrator.md"
ORCH_FEAT="$REPO_ROOT/plugins/cstk/agents/agente-00c-feature-orchestrator.md"

# ==== Existencia + identidade ====

scenario_agent_existe() {
  [ -f "$AGENT" ] || { _error "agente ausente" "$AGENT"; return 2; }
}

scenario_frontmatter_name() {
  assert_exit 0 grep -Eq '^name: data-veracity-verifier$' "$AGENT" || return 1
}

# ==== Read-only: NAO pode portar Write/Edit/Bash no campo tools ====
# A garantia central: o verificador relata, nunca conserta. Se Write/Edit
# vazarem para o tools, ele deixa de ser auditor e vira mais um gerador
# que pode fabricar. Bash tambem fica fora: quebra o read-only por vias
# indiretas (sed -i, tee, redirecionamento).
# NOTA: agents usam o campo `tools:` (CSV) — `allowed-tools:` e o campo de
# SKILL.md/commands e era IGNORADO pelo harness em agents (restricao inerte
# ate a revisao 5.15.0).

scenario_readonly_sem_write_edit() {
  _tools=$(awk -F': *' '/^tools:/{print $2; exit}' "$AGENT")
  if [ -z "$_tools" ]; then
    _fail "agent sem campo tools: no frontmatter (restricao read-only ausente)" ""
    return 1
  fi
  if printf '%s\n' "$_tools" | grep -Eq '(^|[^a-zA-Z])(Write|Edit|Bash)([^a-zA-Z]|$)'; then
    _fail "tools contem Write/Edit/Bash (verificador deve ser read-only)" "$_tools"
    return 1
  fi
  # Campo legado nao pode reaparecer (seria ignorado pelo harness e
  # daria falsa sensacao de restricao).
  if grep -q '^allowed-tools:' "$AGENT"; then
    _fail "agent ainda declara allowed-tools: (campo ignorado em agents)" ""
    return 1
  fi
}

# ==== As 3 classes de dado factual nomeadas ====

scenario_classes_de_dado() {
  assert_exit 0 grep -Eiq 'request/response|assinaturas' "$AGENT" || return 1
  assert_exit 0 grep -Eiq 'endpoint|querystring' "$AGENT" || return 1
  assert_exit 0 grep -Eiq 'financeiros|status de registro|valores concretos' "$AGENT" || return 1
}

# ==== Classificacao + default ceticista ====

scenario_classificacao_e_default() {
  assert_exit 0 grep -Fq 'SOURCED' "$AGENT" || return 1
  assert_exit 0 grep -Fq 'UNSOURCED' "$AGENT" || return 1
  assert_exit 0 grep -Fq 'PROPOSAL' "$AGENT" || return 1
  # default ceticista: na duvida = UNSOURCED
  assert_exit 0 grep -Eiq 'duvida.*UNSOURCED|default ceticista' "$AGENT" || return 1
}

# ==== Veredito + acao recomendada (human_block em UNSOURCED) ====

scenario_veredito_human_block() {
  assert_exit 0 grep -Fq 'has_unsourced' "$AGENT" || return 1
  assert_exit 0 grep -Fq 'human_block' "$AGENT" || return 1
}

# ==== Auto-aterramento (verificador nao confabula a propria fonte) ====

scenario_auto_aterramento() {
  assert_exit 0 grep -Eiq 'substring LITERAL' "$AGENT" || return 1
}

# ==== Fiacao: os 2 orquestradores invocam o verificador pelo nome ====

scenario_orquestradores_referenciam_verificador() {
  assert_exit 0 grep -Fq 'data-veracity-verifier' "$ORCH_AGENTE" || return 1
  assert_exit 0 grep -Fq 'data-veracity-verifier' "$ORCH_FEAT" || return 1
}

run_all_scenarios "$0"
