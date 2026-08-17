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
CT_DELIVERY_TIER="$REPO_ROOT/docs/specs/delivery-tier/contracts/cli-delivery-tier.md"

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
  # INV-4: o path de `set` manual via resume segue sendo acao do
  # operador, nunca iniciativa do orquestrador (narrower, ainda valido
  # apos a emenda dec-048/dec-053 — essa janela nao mudou).
  assert_exit 0 grep -Eiq 'por iniciativa do proprio orquestrador' "$CMD_RESUME_AGENTE" || return 1
}

scenario_inv4_distingue_escolha_de_disparo_mediado() {
  # Emenda dec-048/dec-053 (feature mcp-elicitation-optins FASE 8, regra 1
  # do INV-4): o contrato precisa distinguir escolha/set direto (proibido)
  # de disparo de coleta mediada pelo operador via collect_optins
  # (permitido) — em vez de proibir todo e qualquer envolvimento do
  # orquestrador com o tier.
  [ -f "$CT_DELIVERY_TIER" ] || { _error "arquivo ausente" "$CT_DELIVERY_TIER"; return 2; }
  assert_exit 0 sh -c "grep -Eiq 'nunca escolhe.*o valor do tier' '$CT_DELIVERY_TIER' \
    && grep -Eiq 'set direto' '$CT_DELIVERY_TIER' \
    && grep -Eiq 'coleta mediada' '$CT_DELIVERY_TIER' \
    && grep -Eq 'collect_optins' '$CT_DELIVERY_TIER'" || return 1
}

scenario_inv4_set_direto_sem_consentimento_continua_detectado() {
  # Regra 3 emendada: consentimento estruturado (.optin_responses[] com
  # channel=structured/outcome=accepted) passa a ser reconhecido, mas um
  # set SEM nenhuma das duas evidencias (nem Decisao do resume, nem
  # consentimento estruturado) — inclusive um set direto por iniciativa
  # propria do orquestrador — MUST continuar sendo detectado e reportado
  # como delivery-tier-unattended-change severidade critical. A emenda
  # nao pode afrouxar o controle de deteccao do finding F5.
  [ -f "$CT_DELIVERY_TIER" ] || { _error "arquivo ausente" "$CT_DELIVERY_TIER"; return 2; }
  assert_exit 0 sh -c "grep -Fq 'channel: \"structured\"' '$CT_DELIVERY_TIER' \
    && grep -Fq 'outcome: \"accepted\"' '$CT_DELIVERY_TIER' \
    && grep -Eiq 'NENHUMA das duas evidencias' '$CT_DELIVERY_TIER' \
    && grep -Eiq 'continua sendo detectada' '$CT_DELIVERY_TIER'" || return 1
}

scenario_resume_documenta_allow_downgrade() {
  assert_exit 0 grep -Eq -- '--allow-downgrade' "$CMD_RESUME_AGENTE" || return 1
}

scenario_resume_documenta_decisao_obrigatoria_pos_set() {
  assert_exit 0 grep -Eiq 'state-decisions\.sh register.*MUST ser chamado' "$CMD_RESUME_AGENTE" || return 1
}

# ==== Nao-interativo NAO infere o tier de fonte nenhuma (FR-003 literal) ====
#
# Achado do spike headless de 2026-08-15 (quickstart Cenario 17): um agente
# rodando `claude -p` leu o briefing ratificado, registrou Decisao citando as
# secoes e gravou `local` em vez do default contratual `cloud-public`. O texto
# do command precisa RECUSAR esse raciocinio explicitamente, senao ele se
# repete — a clausula "default e caso de erro" sozinha nao bastou.

scenario_nao_interativo_proibe_inferir_tier() {
  assert_exit 0 grep -Eiq 'NAO infira o tier do briefing' "$CMD_INIT_AGENTE" || return 1
}

scenario_nao_interativo_recusa_briefing_inequivoco() {
  # A proibicao precisa cobrir o caso "fonte citavel e inequivoca" — que foi
  # exatamente a justificativa usada pelo agente no spike.
  # NB: padrao de UMA linha — o texto do command quebra a frase entre
  # "por mais" e "inequivoca", e grep nao cruza linhas.
  assert_exit 0 grep -Eiq 'inequivoca e citavel que pareca' "$CMD_INIT_AGENTE" || return 1
}

scenario_nao_interativo_explica_por_que_nao_viola_principio_vi() {
  # Sem esta racionalizacao explicita, o agente resolve o conflito
  # aparente com o Principio VI a favor da inferencia.
  assert_exit 0 grep -Eiq 'NAO viola o Principio VI' "$CMD_INIT_AGENTE" || return 1
}

scenario_nao_interativo_cita_vetor_asi01() {
  assert_exit 0 grep -Eiq 'injecao indireta.*ASI01|ASI01.*INV-4|INV-4 fecha' "$CMD_INIT_AGENTE" || return 1
}

scenario_nao_interativo_aponta_caminho_legitimo_para_tier_menor() {
  # Rebaixar continua possivel — via operador, com Decisao rastreavel.
  assert_exit 0 grep -Eq 'delivery-tier\.sh set' "$CMD_INIT_AGENTE" || return 1
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
