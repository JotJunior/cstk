#!/bin/sh
# test_converge-orchestrator-gate.sh — smoke textual sobre os 2 orquestradores
# (agente-00c-orchestrator, agente-00c-feature-orchestrator): trava de
# regressao da etapa `convergence` (feature skill-converge, FASE 4 —
# US5/FR-015/FR-019; reclassificada por `pipeline-converge`, FASE 6 —
# FR-001/FR-006).
#
# Contexto: `converge` fecha o loop de reconciliacao spec-vs-codigo na
# fronteira execute-task -> review-task. Desde `pipeline-converge` (FASE 6),
# NAO e mais descrita como um "gate incondicional" especial e paralelo ao
# Loop principal — e etapa REGULAR do pipeline (`_PL_STAGES_LIST`), com o
# MESMO nivel de rastreabilidade/auditoria das demais (FR-006), inserida por
# `pipeline.sh next-stage` entre `execute-task` e `review-task`. Nenhuma
# flag de skip existe para ela (FR-015 de `skill-converge`, redacao MUST
# literal — isso continua verdade), mas o fechamento da sua onda e
# CONDICIONAL ao veredito da skill (3 ramos: escalar-para-humano / volta a
# execute-task / avanca a review-task), nao um "gate paralelo bloqueante".
# A skill `converge` auto-registra seu proprio two-step (state-decisions.sh
# register + state-ondas.sh record-skill) quando detecta modo autonomo — o
# orquestrador NAO deve duplicar esse registro externamente (duplicaria
# Decisao para o mesmo evento).
#
# Natureza: assert TEXTUAL nos .md (contrato comportamental embutido no
# prompt), mesmo padrao de test_orchestrator-turn-completion.sh. NAO mapeia
# 1:1 a um unico .sh — registrado como interno em
# tests/run.sh::_is_internal_test (orphan-check), existence-guarded. Se a
# fonte da etapa sumir do prompt, a regressao (converge nunca invocada antes
# de review-task, ou Decisao duplicada) volta silenciosamente.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

ORCH_AGENTE="$REPO_ROOT/plugins/cstk/agents/agente-00c-orchestrator.md"
ORCH_FEAT="$REPO_ROOT/plugins/cstk/agents/agente-00c-feature-orchestrator.md"

# ==== Linha na tabela de Quality Gates complementares (4.1.1/4.2.1) ====

scenario_agente_tem_linha_tabela_convergence() {
  [ -f "$ORCH_AGENTE" ] || { _error "arquivo ausente" "$ORCH_AGENTE"; return 2; }
  assert_exit 0 grep -Eq '\| *convergence *\| *`converge`' "$ORCH_AGENTE" || return 1
}

scenario_feat_tem_linha_tabela_convergence() {
  [ -f "$ORCH_FEAT" ] || { _error "arquivo ausente" "$ORCH_FEAT"; return 2; }
  assert_exit 0 grep -Eq '\| *convergence *\| *`converge`' "$ORCH_FEAT" || return 1
}

# ==== Secao dedicada da etapa na fronteira execute-task -> review-task
#      (pipeline-converge FASE 6, tarefa 6.3.2 — regex ajustada a nova
#      prosa: nao mais "Gate incondicional", e sim "Etapa `converge`:
#      fechamento condicional de onda") ====

scenario_agente_tem_secao_etapa_converge_fechamento_condicional() {
  assert_exit 0 grep -Eq 'Etapa .convergence.? \(execute-task' "$ORCH_AGENTE" || return 1
}

scenario_feat_tem_secao_etapa_converge_fechamento_condicional() {
  assert_exit 0 grep -Eq 'Etapa .converge.: fechamento condicional de onda' "$ORCH_FEAT" || return 1
}

# Regressao: a antiga framing "Gate incondicional" (bloco especial, paralelo
# ao Loop principal) NAO deve reaparecer — FR-006 exige tratamento de etapa
# regular, nao caso especial fora da maquina de etapas.
scenario_agente_nao_reintroduz_framing_gate_incondicional() {
  assert_exit 1 grep -Eq 'Gate incondicional .converge' "$ORCH_AGENTE" || return 1
}

scenario_feat_nao_reintroduz_framing_gate_incondicional() {
  assert_exit 1 grep -Eq 'Gate incondicional .converge' "$ORCH_FEAT" || return 1
}

scenario_agente_fronteira_execute_task_review_task() {
  assert_exit 0 grep -Eq 'execute-task.{0,5}(->|→).{0,5}review-task' "$ORCH_AGENTE" || return 1
}

scenario_feat_fronteira_execute_task_review_task() {
  assert_exit 0 grep -Eq 'execute-task.{0,5}(->|→).{0,5}review-task' "$ORCH_FEAT" || return 1
}

# ==== FR-006 (pipeline-converge): etapa regular, mesmo nivel de auditoria ====

scenario_agente_cita_fr006_etapa_regular() {
  assert_exit 0 grep -Fq 'FR-006' "$ORCH_AGENTE" || return 1
  assert_exit 0 grep -Fq 'mesmo nivel de rastreabilidade' "$ORCH_AGENTE" || return 1
}

scenario_feat_cita_fr006_etapa_regular() {
  assert_exit 0 grep -Fq 'FR-006' "$ORCH_FEAT" || return 1
  assert_exit 0 grep -Fq 'nivel de rastreabilidade/auditoria' "$ORCH_FEAT" || return 1
}

# ==== FR-015 MUST literal, sem flag de opt-out (continua verdade — so a
#      framing "incondicional/diferente das demais" foi removida) ====

scenario_agente_fr015_must_literal() {
  assert_exit 0 grep -Fq 'FR-015, redacao MUST literal' "$ORCH_AGENTE" || return 1
}

scenario_feat_fr015_must_literal() {
  assert_exit 0 grep -Fq 'redacao MUST literal' "$ORCH_FEAT" || return 1
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
