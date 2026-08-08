#!/bin/sh
# test_orchestrator-spawn-model-apply.sh — smoke textual sobre os 2
# orquestradores (agente-00c-orchestrator, agente-00c-feature-orchestrator)
# que APLICAM o modelo no spawn de clarify (FASE 5 da feature
# model-routing-por-onda, US2).
#
# Feature: model-routing-por-onda
# Ref: docs/specs/model-routing-por-onda/tasks.md FASE 5 (5.1.1, 5.1.2,
#        5.1.3, 5.2.1, 5.2.2)
#      docs/specs/model-routing-por-onda/contracts/wave-select.md
#        §"Integração: sequência pré-spawn de clarify (orquestradores)"
#
# Natureza: assert TEXTUAL no .md (a "implementacao" e a instrucao de
# spawn embutida no passo 8 da §5.e.bis / secao model-routing dos dois
# orquestradores). NAO mapeia 1:1 a um unico .sh, portanto e registrado
# como interno em tests/run.sh::_is_internal_test (orphan-check).
#
# Cobertura:
#   5.1.1/5.1.2 (FR-003): o passo 8 instrui aplicar `model=$MODEL_APLICAR`
#     condicional a escolha ∈ {haiku,sonnet,opus} E score >= 2 (nao-fallback).
#   5.1.3 (FR-003/FR-006): fallback/manter-atual/score<2 -> OMITIR o param
#     model (herda o frontmatter do agent file).
#   5.2.1/5.2.2 (FR-004): caminho degradado (mediacao inline) NAO aplica
#     override e NAO gera Decisao de model-routing orfa (Invariante I1).
#   POSIX-puro: snippet embutido sem `case` dentro de `$( )` (dec-003).

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

ORCH_AGENTE="$REPO_ROOT/plugins/cstk/agents/agente-00c-orchestrator.md"
ORCH_FEAT="$REPO_ROOT/plugins/cstk/agents/agente-00c-feature-orchestrator.md"

# ==== 5.1.1/5.1.2 / FR-003: passo 8 aplica model=$MODEL_APLICAR ====

scenario_orch_agente_aplica_model_no_spawn() {
  [ -f "$ORCH_AGENTE" ] || { _error "arquivo ausente" "$ORCH_AGENTE"; return 2; }
  # Deve instruir o spawn da tool Agent com model=$MODEL_APLICAR.
  assert_exit 0 grep -Eq 'model[:=] ?\$MODEL_APLICAR|model=\$MODEL_APLICAR' "$ORCH_AGENTE" || return 1
}

scenario_orch_feat_aplica_model_no_spawn() {
  [ -f "$ORCH_FEAT" ] || { _error "arquivo ausente" "$ORCH_FEAT"; return 2; }
  assert_exit 0 grep -Eq 'model[:=] ?\$MODEL_APLICAR|model=\$MODEL_APLICAR' "$ORCH_FEAT" || return 1
}

# ==== 5.1.1/5.1.2 / FR-003: condicional a score>=2 e escolha acionavel ====

scenario_orch_agente_condicional_score_e_escolha() {
  # O bloco deve testar score >= 2 e a escolha ∈ {haiku,sonnet,opus}.
  assert_exit 0 grep -Eq 'SCORE_DEC.*-ge 2|-ge 2.*SCORE_DEC' "$ORCH_AGENTE" || return 1
  assert_exit 0 grep -Eq 'ESCOLHA_DEC.*=.*"haiku"' "$ORCH_AGENTE" || return 1
}

scenario_orch_feat_condicional_score_e_escolha() {
  assert_exit 0 grep -Eq 'SCORE_DEC.*-ge 2|-ge 2.*SCORE_DEC' "$ORCH_FEAT" || return 1
  assert_exit 0 grep -Eq 'ESCOLHA_DEC.*=.*"haiku"' "$ORCH_FEAT" || return 1
}

# ==== 5.1.3 / FR-006: fallback/manter-atual -> OMITIR param model ====

scenario_orch_agente_omite_model_em_fallback() {
  # Deve instruir explicitamente: senao (fallback/manter-atual/score<2)
  # -> spawnar SEM o param model.
  assert_exit 0 grep -Eiq '[Ss][Ee][Mm] o param .?model|OMITIR o param .?model|OMITIDO' "$ORCH_AGENTE" || return 1
}

scenario_orch_feat_omite_model_em_fallback() {
  assert_exit 0 grep -Eiq '[Ss][Ee][Mm] o param .?model|OMITIR o param .?model|OMITIDO' "$ORCH_FEAT" || return 1
}

# ==== Derivacao da Decisao (idempotent-safe): le DEC_ID, nao vars locais ====

scenario_orch_agente_deriva_da_decisao() {
  # Robustez ao caminho idempotente: deriva escolha/score do DEC_ID via
  # state-rw.sh get, nao das vars MODELO/SCORE locais (so existem no else).
  assert_exit 0 grep -Eq 'select\(\.id ==' "$ORCH_AGENTE" || return 1
  assert_exit 0 grep -Eq 'ESCOLHA_DEC=' "$ORCH_AGENTE" || return 1
  # NB: campo de score e justification_score no schema da Decisao.
  assert_exit 0 grep -Eq 'justification_score' "$ORCH_AGENTE" || return 1
}

scenario_orch_feat_deriva_da_decisao() {
  assert_exit 0 grep -Eq 'select\(\.id ==' "$ORCH_FEAT" || return 1
  assert_exit 0 grep -Eq 'ESCOLHA_DEC=' "$ORCH_FEAT" || return 1
  assert_exit 0 grep -Eq 'justification_score' "$ORCH_FEAT" || return 1
}

# ==== 5.2.1/5.2.2 / FR-004: degradacao inline NAO gera Decisao orfa ====

scenario_orch_agente_preserva_degradacao_inline() {
  # Deve haver nota explicita de preservacao FR-004 declarando que no
  # caminho degradado NENHUMA Decisao de model-routing orfa e gerada.
  assert_exit 0 grep -Eiq 'Preservacao FR-004|FR-004' "$ORCH_AGENTE" || return 1
  assert_exit 0 grep -Eiq 'orfa|órfã|orphan' "$ORCH_AGENTE" || return 1
}

scenario_orch_feat_preserva_degradacao_inline() {
  assert_exit 0 grep -Eiq 'Preservacao FR-004|FR-004' "$ORCH_FEAT" || return 1
  assert_exit 0 grep -Eiq 'orfa|órfã|orphan' "$ORCH_FEAT" || return 1
}

# ==== Invariante I1 preservada: 1 Decisao por spawn real ====

scenario_orch_agente_invariante_i1_mencionada() {
  # A aplicacao NAO cria nova Decisao — apenas le a ja registrada (I1).
  assert_exit 0 grep -Eiq 'Invariante I1|1-para-1|NAO cria nova Decisao|nao cria nova decisao' "$ORCH_AGENTE" || return 1
}

scenario_orch_feat_invariante_i1_mencionada() {
  assert_exit 0 grep -Eiq 'Invariante I1|1-para-1|NAO cria nova Decisao|nao cria nova decisao' "$ORCH_FEAT" || return 1
}

# ==== POSIX-puro: snippet embutido sem `case` dentro de $( ) (dec-003) ====

scenario_no_case_dentro_de_command_substitution() {
  # Espelha o assert da FASE 3: nenhuma linha pode combinar $( ... case.
  for _f in "$ORCH_AGENTE" "$ORCH_FEAT"; do
    if grep -nE '\$\([^)]*\bcase\b' "$_f" >/dev/null 2>&1; then
      _fail "no_case_em_subshell" "anti-padrao dec-003 (case dentro de \$()) em $_f"
      return 1
    fi
  done
  return 0
}

run_all_scenarios "$0"
