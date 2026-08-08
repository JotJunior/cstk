#!/bin/sh
# test_orchestrator-turn-completion.sh — smoke textual sobre os 2
# orquestradores (agente-00c-orchestrator, agente-00c-feature-orchestrator):
# trava de regressao do "Contrato de conclusao de turno" que previne o bug
# do orquestrador parar cedo apos uma Skill retornar (abandonando o fim de
# onda + ingestao + Schedule intent).
#
# Contexto: incidente microsoft-tools (2026-05-26) — o orquestrador gerou a
# spec via Skill(specify) e retornou SEM fechar a onda / emitir Schedule
# intent. O contrato reframa o retorno da Skill como o MEIO da onda e ancora
# o fim de turno na linha `Schedule intent:`.
#
# Natureza: assert TEXTUAL no .md (contrato comportamental embutido no
# prompt). NAO mapeia 1:1 a um unico .sh — registrado como interno em
# tests/run.sh::_is_internal_test (orphan-check), existence-guarded. Se a
# fonte do contrato sumir do prompt, o bug volta silenciosamente — por isso
# a presenca e travada aqui.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

ORCH_AGENTE="$REPO_ROOT/plugins/cstk/agents/agente-00c-orchestrator.md"
ORCH_FEAT="$REPO_ROOT/plugins/cstk/agents/agente-00c-feature-orchestrator.md"

# ==== Contrato presente nos dois orquestradores ====

scenario_agente_tem_contrato_conclusao() {
  [ -f "$ORCH_AGENTE" ] || { _error "arquivo ausente" "$ORCH_AGENTE"; return 2; }
  assert_exit 0 grep -Eq 'Contrato de conclusao de turno' "$ORCH_AGENTE" || return 1
}

scenario_feat_tem_contrato_conclusao() {
  [ -f "$ORCH_FEAT" ] || { _error "arquivo ausente" "$ORCH_FEAT"; return 2; }
  assert_exit 0 grep -Eq 'Contrato de conclusao de turno' "$ORCH_FEAT" || return 1
}

# ==== Reframing-chave: o retorno da Skill e o MEIO da onda ====

scenario_agente_skill_e_meio_da_onda() {
  assert_exit 0 grep -Eq 'MEIO da onda' "$ORCH_AGENTE" || return 1
}

scenario_feat_skill_e_meio_da_onda() {
  assert_exit 0 grep -Eq 'MEIO da onda' "$ORCH_FEAT" || return 1
}

# ==== Auto-checagem ancorada no token de saida (Schedule intent) ====

scenario_agente_tem_autochecagem() {
  assert_exit 0 grep -Eiq 'Auto-checagem' "$ORCH_AGENTE" || return 1
}

scenario_feat_tem_autochecagem() {
  assert_exit 0 grep -Eiq 'Auto-checagem' "$ORCH_FEAT" || return 1
}

# ==== Anotacao inline no passo 5 (ponto de gatilho) reforça o contrato ====

scenario_passo5_reforca_nos_dois() {
  # O passo onde a Skill e invocada deve lembrar que o retorno NAO encerra
  # a onda — reforco adjacente ao gatilho, nao so na secao distante.
  assert_exit 0 grep -Eiq 'NAO encerr|NAO encerra a onda' "$ORCH_AGENTE" || return 1
  assert_exit 0 grep -Eiq 'NAO encerr|NAO encerra a onda' "$ORCH_FEAT" || return 1
}

run_all_scenarios "$0"
