#!/bin/sh
# test_converge-orchestrator-gate.sh — smoke textual sobre os 2 orquestradores
# (agente-00c-orchestrator, agente-00c-feature-orchestrator): trava de
# regressao do gate incondicional `convergence` (feature skill-converge,
# FASE 4 — US5/FR-015/FR-019).
#
# Contexto: o gate `convergence` fecha o loop de reconciliacao spec-vs-codigo
# na fronteira execute-task -> review-task, incondicional (sem flag de
# opt-out, ao contrario dos demais quality gates de "Quality Gates
# complementares"). A skill `converge` auto-registra seu proprio two-step
# (state-decisions.sh register + state-ondas.sh record-skill) quando detecta
# modo autonomo — o orquestrador NAO deve duplicar esse registro
# externamente (duplicaria Decisao para o mesmo evento).
#
# Natureza: assert TEXTUAL nos .md (contrato comportamental embutido no
# prompt), mesmo padrao de test_orchestrator-turn-completion.sh. NAO mapeia
# 1:1 a um unico .sh — registrado como interno em
# tests/run.sh::_is_internal_test (orphan-check), existence-guarded. Se a
# fonte do gate sumir do prompt, a regressao (converge nunca invocada antes
# de review-task, ou Decisao duplicada) volta silenciosamente.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

ORCH_AGENTE="$REPO_ROOT/global/agents/agente-00c-orchestrator.md"
ORCH_FEAT="$REPO_ROOT/global/agents/agente-00c-feature-orchestrator.md"

# ==== Linha na tabela de Quality Gates complementares (4.1.1/4.2.1) ====

scenario_agente_tem_linha_tabela_convergence() {
  [ -f "$ORCH_AGENTE" ] || { _error "arquivo ausente" "$ORCH_AGENTE"; return 2; }
  assert_exit 0 grep -Eq '\| *convergence *\| *`converge`' "$ORCH_AGENTE" || return 1
}

scenario_feat_tem_linha_tabela_convergence() {
  [ -f "$ORCH_FEAT" ] || { _error "arquivo ausente" "$ORCH_FEAT"; return 2; }
  assert_exit 0 grep -Eq '\| *convergence *\| *`converge`' "$ORCH_FEAT" || return 1
}

# ==== Secao dedicada do gate na fronteira execute-task -> review-task (4.1.2/4.2.2) ====

scenario_agente_tem_secao_gate_incondicional() {
  assert_exit 0 grep -Eq 'Gate incondicional .converge' "$ORCH_AGENTE" || return 1
}

scenario_feat_tem_secao_gate_incondicional() {
  assert_exit 0 grep -Eq 'Gate incondicional .converge' "$ORCH_FEAT" || return 1
}

scenario_agente_fronteira_execute_task_review_task() {
  assert_exit 0 grep -Eq 'execute-task.{0,5}(->|→).{0,5}review-task' "$ORCH_AGENTE" || return 1
}

scenario_feat_fronteira_execute_task_review_task() {
  assert_exit 0 grep -Eq 'execute-task.{0,5}(->|→).{0,5}review-task' "$ORCH_FEAT" || return 1
}

# ==== Incondicional: FR-015 MUST literal, sem flag de opt-out ====

scenario_agente_incondicional_fr015() {
  assert_exit 0 grep -Fq 'FR-015, redacao MUST literal' "$ORCH_AGENTE" || return 1
}

scenario_feat_incondicional_fr015() {
  assert_exit 0 grep -Fq 'FR-015, redacao MUST literal' "$ORCH_FEAT" || return 1
}

# ==== Anti-duplicacao: skill auto-registra, orquestrador NAO duplica (4.1.3/4.2.3) ====

scenario_agente_nao_duplica_registro() {
  assert_exit 0 grep -Fq 'ETAPA 8' "$ORCH_AGENTE" || return 1
  assert_exit 0 grep -Fq 'duplicada' "$ORCH_AGENTE" || return 1
}

scenario_feat_nao_duplica_registro() {
  assert_exit 0 grep -Fq 'ETAPA 8' "$ORCH_FEAT" || return 1
  assert_exit 0 grep -Fq 'duplicada' "$ORCH_FEAT" || return 1
}

# ==== Enum de 2 valores (divergencia intencional, CHK025/tarefa 1.5) ====

scenario_agente_enum_escalar_para_humano() {
  assert_exit 0 grep -Fq 'escalar-para-humano' "$ORCH_AGENTE" || return 1
}

scenario_feat_enum_escalar_para_humano() {
  assert_exit 0 grep -Fq 'escalar-para-humano' "$ORCH_FEAT" || return 1
}

run_all_scenarios "$0"
