#!/bin/sh
# test_command-spawn-delivery-tier.sh — smoke textual sobre o prompt de
# finalidade (tier de entrega) embutido em plugins/cstk/commands/agente-00c.md
# + leitura sem re-prompt em plugins/cstk/commands/agente-00c-resume.md
# (FASE 4 task 4.3 da feature delivery-tier, extensao aditiva a familia
# test_command-spawn-*.sh — precedente test_command-spawn-roadmap-mode.sh).
#
# Feature: delivery-tier
# Ref: docs/specs/delivery-tier/tasks.md FASE 4 task 4.3
#      docs/specs/delivery-tier/plan.md Fase C item 10
#      docs/specs/delivery-tier/contracts/cli-delivery-tier.md
#      docs/specs/delivery-tier/spec.md FR-001/FR-002/FR-003
#
# Natureza: assert TEXTUAL nos .md (nao ha helper novo aqui — a
# "implementacao" e o bloco de prompt embutido no command + a leitura
# documentada no resume). dec-011: restrito ao /agente-00c; /feature-00c e
# o orquestrador de feature NAO devem ganhar nenhuma referencia ao tier.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

CMD_INIT_AGENTE="$REPO_ROOT/plugins/cstk/commands/agente-00c.md"
CMD_RESUME_AGENTE="$REPO_ROOT/plugins/cstk/commands/agente-00c-resume.md"

# ==== Prompt de finalidade presente, com as 4 opcoes e default cloud-public (FR-001) ====

scenario_prompt_finalidade_presente() {
  [ -f "$CMD_INIT_AGENTE" ] || { _error "arquivo ausente" "$CMD_INIT_AGENTE"; return 2; }
  assert_exit 0 grep -Eq 'Selecione \[1-4, Enter = 4\]:' "$CMD_INIT_AGENTE" || return 1
}

scenario_quatro_opcoes_presentes() {
  capture sh -c "grep -Eq '1\\) Uso local' '$CMD_INIT_AGENTE' \
    && grep -Eq '2\\) Rede interna compartilhada' '$CMD_INIT_AGENTE' \
    && grep -Eq '3\\) Nuvem de uso interno' '$CMD_INIT_AGENTE' \
    && grep -Eq '4\\) Nuvem de uso publico' '$CMD_INIT_AGENTE'"
  assert_exit 0 sh -c "grep -Eq '1\\) Uso local' '$CMD_INIT_AGENTE' \
    && grep -Eq '2\\) Rede interna compartilhada' '$CMD_INIT_AGENTE' \
    && grep -Eq '3\\) Nuvem de uso interno' '$CMD_INIT_AGENTE' \
    && grep -Eq '4\\) Nuvem de uso publico' '$CMD_INIT_AGENTE'" || return 1
}

scenario_mapeamento_tokens_enum() {
  capture sh -c "grep -Eq '\`1\` .* \`local\`' '$CMD_INIT_AGENTE' \
    && grep -Eq '\`4\` .* \`cloud-public\`' '$CMD_INIT_AGENTE'"
  assert_exit 0 sh -c "grep -Eq '\`1\` .* \`local\`' '$CMD_INIT_AGENTE' \
    && grep -Eq '\`4\` .* \`cloud-public\`' '$CMD_INIT_AGENTE'" || return 1
}

scenario_default_cloud_public_documentado() {
  assert_exit 0 grep -Eq '_tier="cloud-public"' "$CMD_INIT_AGENTE" || return 1
}

scenario_nao_interativo_cai_no_default() {
  # FR-003: nenhuma execucao pode travar esperando resposta.
  assert_exit 0 grep -Eiq 'execucao.*nao-interativa.*_tier="cloud-public"|nao-interativa.*cai no default|Default e caso de erro' "$CMD_INIT_AGENTE" || return 1
}

# ==== Flag repassada ao init do state.json, comportamento atual intacto ====

scenario_flag_passada_ao_state_rw_init() {
  assert_exit 0 grep -Eq -- '--delivery-tier "\$_tier"' "$CMD_INIT_AGENTE" || return 1
}

scenario_default_documentado_como_comportamento_atual_intacto() {
  assert_exit 0 grep -Eq -- '--delivery-tier "\$_tier".*comportamento atual intacto' "$CMD_INIT_AGENTE" || return 1
}

# ==== Resume nao re-promptа (paridade com atomic-commit/roadmap-mode) ====

scenario_resume_nao_reprompta_documentado() {
  [ -f "$CMD_RESUME_AGENTE" ] || { _error "arquivo ausente" "$CMD_RESUME_AGENTE"; return 2; }
  assert_exit 0 grep -Eiq 'NAO apresenta a pergunta de finalidade' "$CMD_RESUME_AGENTE" || return 1
}

scenario_resume_le_exclusivamente_via_helper_get() {
  # INV-5: leitura exclusiva via delivery-tier.sh get, nunca campo cru.
  assert_exit 0 grep -Eq -- 'delivery-tier\.sh get --state-dir' "$CMD_RESUME_AGENTE" || return 1
}

scenario_resume_proibe_leitura_crua_do_campo() {
  assert_exit 0 grep -Eq -- "nunca leitura crua de .state-rw\.sh get --field '\.delivery_tier'" "$CMD_RESUME_AGENTE" || return 1
}

scenario_resume_documenta_inv4_operador() {
  # INV-4: set e sempre acao do operador, nunca iniciativa do orquestrador.
  assert_exit 0 grep -Eiq 'por iniciativa do proprio orquestrador' "$CMD_RESUME_AGENTE" || return 1
}

scenario_resume_documenta_allow_downgrade() {
  assert_exit 0 grep -Eq -- '--allow-downgrade' "$CMD_RESUME_AGENTE" || return 1
}

scenario_resume_documenta_decisao_obrigatoria_pos_set() {
  assert_exit 0 grep -Eiq 'state-decisions\.sh register.*MUST ser chamado' "$CMD_RESUME_AGENTE" || return 1
}

# ==== Confinamento de escopo (dec-011): restrito ao /agente-00c ====

scenario_ausente_em_feature_00c_commands() {
  for f in "$REPO_ROOT"/plugins/cstk/commands/feature-00c*.md; do
    [ -f "$f" ] || continue
    assert_exit 1 grep -Eiq 'delivery_tier|delivery-tier' "$f" || return 1
  done
}

scenario_ausente_em_feature_orchestrator_agent() {
  f="$REPO_ROOT/plugins/cstk/agents/agente-00c-feature-orchestrator.md"
  [ -f "$f" ] || { _error "arquivo ausente" "$f"; return 2; }
  assert_exit 1 grep -Eiq 'delivery_tier|delivery-tier' "$f" || return 1
}

run_all_scenarios "$0"
