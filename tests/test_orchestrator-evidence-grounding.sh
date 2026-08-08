#!/bin/sh
# test_orchestrator-evidence-grounding.sh — smoke textual: trava de regressao da
# regra "aterramento de evidencia em escalada de SEGURANCA" (anti-confabulacao)
# nos 2 orquestradores + nos 2 comandos de resume (PAI).
#
# Contexto (incidente security-hardening-owasp, 2026-05-30): um resume (PAI)
# CONFABULOU uma string de prompt-injection num output SSH LIMPO (etcd healthy,
# 17 servicos up), registrou Decisao score-3 com `--evidencia` FABRICADA e
# escalou ao operador (dec-122, depois retratada). A trava de score-3 exige que
# `--evidencia` EXISTA — nao que seja REAL. A regra fecha o furo: evidencia de
# ameaca tem que ser substring LITERAL de um tool result observado; senao,
# `--score 0 --escolha ameaca-nao-verificada` (pause), nunca escalar ameaca
# fabricada. Move o flagra do momento-da-acao para o momento-do-registro.
#
# Natureza: assert TEXTUAL no .md/.command (contrato comportamental no prompt).
# NAO mapeia 1:1 a um .sh — interno em tests/run.sh::_is_internal_test
# (orphan-check), existence-guarded. Se a regra sumir do prompt, o bug volta
# silenciosamente — por isso a presenca e travada aqui.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

ORCH_AGENTE="$REPO_ROOT/plugins/cstk/agents/agente-00c-orchestrator.md"
ORCH_FEAT="$REPO_ROOT/plugins/cstk/agents/agente-00c-feature-orchestrator.md"
RES_AGENTE="$REPO_ROOT/plugins/cstk/commands/agente-00c-resume.md"
RES_FEAT="$REPO_ROOT/plugins/cstk/commands/feature-00c-resume.md"

# Token-ancora ASCII da regra: a escolha score-0 que substitui a escalada.
_assert_grounding_token() {
  [ -f "$1" ] || { _error "arquivo ausente" "$1"; return 2; }
  assert_exit 0 grep -Fq 'ameaca-nao-verificada' "$1" || return 1
}

# ==== Remedio (token score-0) presente nos 4 prompts ====

scenario_orquestrador_agente_tem_aterramento()  { _assert_grounding_token "$ORCH_AGENTE"; }
scenario_orquestrador_feature_tem_aterramento() { _assert_grounding_token "$ORCH_FEAT"; }
scenario_resume_agente_tem_aterramento()         { _assert_grounding_token "$RES_AGENTE"; }
scenario_resume_feature_tem_aterramento()        { _assert_grounding_token "$RES_FEAT"; }

# ==== Natureza do furo nomeada nos 2 orquestradores (evidencia literal/fabricada) ====

scenario_orquestradores_exigem_evidencia_literal() {
  assert_exit 0 grep -Eiq 'substring LITERAL' "$ORCH_AGENTE" || return 1
  assert_exit 0 grep -Eiq 'substring LITERAL' "$ORCH_FEAT" || return 1
  assert_exit 0 grep -Eiq 'confabul|fabricad' "$ORCH_AGENTE" || return 1
  assert_exit 0 grep -Eiq 'confabul|fabricad' "$ORCH_FEAT" || return 1
}

run_all_scenarios "$0"
