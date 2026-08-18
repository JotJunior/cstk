#!/bin/sh
# test_command-spawn-parallel-launch.sh — smoke textual sobre a oferta de
# leva paralela pos-roadmap embutida em plugins/cstk/commands/agente-00c.md
# §6.ter e plugins/cstk/commands/agente-00c-resume.md §9.ter (FASE 2 task
# 2.8/2.9 da feature roadmap-parallel-launch).
#
# Feature: roadmap-parallel-launch
# Ref: docs/specs/roadmap-parallel-launch/tasks.md FASE 2 tasks 2.8/2.9
#      docs/specs/roadmap-parallel-launch/spec.md FR-002/FR-003/FR-004/
#      FR-006/FR-011/FR-012/FR-014/FR-018, SC-001
#      docs/specs/roadmap-parallel-launch/contracts/parallel-launch.md §3/§8.bis
#
# Natureza: assert TEXTUAL nos .md (nao ha helper novo, EXCETO o parser de
# notificacao de FASE 3 — cobertura funcional dedicada em
# tests/test_parallel-notification-parse.sh). Precedente:
# tests/test_command-spawn-roadmap-mode.sh (mesmo padrao de grep estatico).
#
# Confinamento de escopo (FR-012, inegociavel): a DECISAO de quais features
# rodar e o LANCAMENTO efetivo (calculo de fronteira, `parallel-launch.sh
# emit`, pergunta de teto/selecao) sao EXCLUSIVOS da sessao coordenadora
# (agente-00c.md/agente-00c-resume.md) — nunca vazam para feature-00c.md/
# feature-00c-resume.md. A partir da FASE 3 (task 3.1), feature-00c.md/
# feature-00c-resume.md LEGITIMAMENTE ganham prosa de NOTIFICACAO (lado
# emissor, best-effort, contract §6) — isso nao viola FR-012 porque a
# sessao-filha so informa o desfecho, nunca decide/lanca nada. O confinamento
# testado abaixo, portanto, e sobre os marcadores de DECISAO/LANCAMENTO
# (`roadmap-frontier.sh`, `parallel-launch.sh emit`), nao sobre a existencia
# de qualquer mencao a leva paralela.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

CMD_INIT_AGENTE="$REPO_ROOT/plugins/cstk/commands/agente-00c.md"
CMD_RESUME_AGENTE="$REPO_ROOT/plugins/cstk/commands/agente-00c-resume.md"
CMD_INIT_FEAT="$REPO_ROOT/plugins/cstk/commands/feature-00c.md"
CMD_RESUME_FEAT="$REPO_ROOT/plugins/cstk/commands/feature-00c-resume.md"

# ==== Gatilho: presente nos 2 commands de nivel projeto (2.8.1) ====

scenario_gatilho_presente_em_agente00c() {
  [ -f "$CMD_INIT_AGENTE" ] || { _error "arquivo ausente" "$CMD_INIT_AGENTE"; return 2; }
  assert_exit 0 grep -Fq '### 6.ter Oferta de leva paralela pos-roadmap' "$CMD_INIT_AGENTE" || return 1
}

scenario_gatilho_condicionado_a_concluido_roadmap() {
  assert_exit 0 grep -Fq '_term_reason" = "concluido_roadmap"' "$CMD_INIT_AGENTE" || return 1
}

scenario_gatilho_presente_no_resume() {
  [ -f "$CMD_RESUME_AGENTE" ] || { _error "arquivo ausente" "$CMD_RESUME_AGENTE"; return 2; }
  assert_exit 0 grep -Fq '### 9.ter Oferta de leva paralela pos-roadmap' "$CMD_RESUME_AGENTE" || return 1
}

scenario_resume_referencia_fluxo_completo_sem_duplicar() {
  # 9.ter aponta para 6.ter em vez de duplicar o fluxo inteiro (DRY, mesmo
  # padrao ja usado por 9.bis -> 6.bis).
  assert_exit 0 grep -Fq 'agente-00c.md` §6.ter' "$CMD_RESUME_AGENTE" || return 1
}

scenario_ordem_9quater_nunca_reordenada() {
  # INV-1 do contrato: a sequencia MUST de 9.quater e citada como
  # inalterada, nunca reordenada por esta prosa. Texto-fonte quebra em 2
  # linhas ("...§9.quater\n— NUNCA reordenada..."); junta a janela antes
  # de casar (mesma tecnica de test_command-spawn-roadmap-mode.sh).
  assert_exit 0 sh -c "grep -A1 -F '9.quater' '$CMD_INIT_AGENTE' | tr '\\n' ' ' | grep -Eiq 'NUNCA.*(reordenada|alterada)'" || return 1
}

# ==== FR-012: oferta e exclusiva do command pai ====

scenario_fr012_exclusividade_command_pai_documentada() {
  assert_exit 0 grep -Fq 'FR-012 — inegociavel' "$CMD_INIT_AGENTE" || return 1
}

# ==== Pergunta de teto default 2 (2.8.2, SC-001) ====

scenario_pergunta_teto_default_2() {
  assert_exit 0 grep -Fq 'Quantas features rodar simultaneamente nesta leva? [2]' "$CMD_INIT_AGENTE" || return 1
}

scenario_teto_default_documentado_fr003() {
  assert_exit 0 grep -Eq 'default \*\*2\*\* \(FR-003' "$CMD_INIT_AGENTE" || return 1
}

# ==== Fluxo de selecao quando candidatas excedem o teto (2.8.3, FR-004) ====

scenario_fluxo_selecao_excede_teto() {
  assert_exit 0 grep -Fq 'Selecao quando candidatas excedem o teto' "$CMD_INIT_AGENTE" || return 1
}

scenario_selecao_cita_fr004() {
  capture sh -c "grep -A2 -F 'Selecao quando candidatas excedem o teto' '$CMD_INIT_AGENTE' | tr '\\n' ' ' | grep -Eq 'FR-004'"
  assert_exit 0 sh -c "grep -A2 -F 'Selecao quando candidatas excedem o teto' '$CMD_INIT_AGENTE' | tr '\\n' ' ' | grep -Eq 'FR-004'" || return 1
}

# ==== Recusa preserva fluxo atual (2.8.4, FR-002) ====

scenario_recusa_preserva_fluxo_manual() {
  assert_exit 0 grep -Eq 'comportamento manual atual intacto \(FR-002\)' "$CMD_INIT_AGENTE" || return 1
}

scenario_nao_interativo_default_seguro_nao_lancar() {
  assert_exit 0 grep -Fq 'cai em "nao lancar" sem bloquear' "$CMD_INIT_AGENTE" || return 1
}

# ==== Declaracao explicita de nao-sandbox (2.8.5, FR-018/CHK103) ====

scenario_declaracao_nao_sandbox_presente() {
  assert_exit 0 grep -Fq 'isto nao e um sandbox' "$CMD_INIT_AGENTE" || return 1
}

scenario_declaracao_blast_radius_presente() {
  assert_exit 0 grep -Fiq 'limite de BLAST RADIUS' "$CMD_INIT_AGENTE" || return 1
}

scenario_declaracao_na_mesma_interacao_da_oferta() {
  # FR-018/CHK103 exige que a declaracao ocorra NA MESMA interacao da
  # pergunta de lancamento — checa que "Lancar leva paralela?" e a
  # declaracao de blast radius estao no MESMO bloco de prompt (janela de
  # 20 linhas, mesma tecnica de test_command-spawn-roadmap-mode.sh).
  capture sh -c "grep -A20 -F 'Lancar leva paralela agora?' '$CMD_INIT_AGENTE' | tr '\\n' ' ' | grep -Eq 'BLAST RADIUS'"
  assert_exit 0 sh -c "grep -A20 -F 'Lancar leva paralela agora?' '$CMD_INIT_AGENTE' | tr '\\n' ' ' | grep -Eq 'BLAST RADIUS'" || return 1
}

# ==== Aviso de sobreposicao de artefatos (FASE 5, FR-014, contract §6) ====

scenario_aviso_sobreposicao_repassado_ao_operador() {
  assert_exit 0 grep -Fq '### Avisos' "$CMD_INIT_AGENTE" || return 1
  assert_exit 0 grep -Fq 'REPASSE-A ao operador' "$CMD_INIT_AGENTE" || return 1
}

scenario_aviso_sobreposicao_nunca_bloqueia_documentado() {
  # AC3 da US4: presente ou nao, o aviso jamais bloqueia a pergunta do
  # passo 4 (janela de 15 linhas apos o marcador do passo 3, mesma tecnica
  # de scenario_declaracao_na_mesma_interacao_da_oferta acima).
  capture sh -c "grep -A15 -F '3. **Avisos de sobreposicao' '$CMD_INIT_AGENTE' | tr '\\n' ' ' | grep -Eiq 'NUNCA bloqueia'"
  assert_exit 0 sh -c "grep -A15 -F '3. **Avisos de sobreposicao' '$CMD_INIT_AGENTE' | tr '\\n' ' ' | grep -Eiq 'NUNCA bloqueia'" || return 1
}

scenario_aviso_sobreposicao_indicio_nunca_afirmacao() {
  # Principio VI: heuristica textual nao comprova sobreposicao — nunca
  # reescrever como conflito confirmado.
  capture sh -c "grep -A15 -F '3. **Avisos de sobreposicao' '$CMD_INIT_AGENTE' | tr '\\n' ' ' | grep -Eiq 'indicio'"
  assert_exit 0 sh -c "grep -A15 -F '3. **Avisos de sobreposicao' '$CMD_INIT_AGENTE' | tr '\\n' ' ' | grep -Eiq 'indicio'" || return 1
  assert_exit 0 grep -Fq 'NUNCA resuma/reescreva/reforce o aviso como se fosse um conflito' "$CMD_INIT_AGENTE" || return 1
}

scenario_aviso_sobreposicao_placeholder_no_prompt_template() {
  # o placeholder da secao "### Avisos" MUST aparecer no template do
  # prompt entre a tabela de fronteira e a pergunta de lancamento.
  assert_exit 0 sh -c "grep -A10 -F 'Fronteira elegivel do roadmap:' '$CMD_INIT_AGENTE' | tr '\\n' ' ' | grep -Eq 'secao \"### Avisos\"'" || return 1
  assert_exit 0 sh -c "grep -A10 -F 'Fronteira elegivel do roadmap:' '$CMD_INIT_AGENTE' | tr '\\n' ' ' | grep -Eq 'Lancar leva paralela agora'" || return 1
}

scenario_aviso_sobreposicao_heuristica_pendente_removida() {
  # FASE 5 concluida: o marcador antigo de "heuristica pendente" nao pode
  # mais aparecer nem em agente-00c.md nem em agente-00c-resume.md.
  case "$(grep -F 'heuristica pendente' "$CMD_INIT_AGENTE" 2>/dev/null)" in
    "") : ;;
    *) _fail "marcador de pendencia obsoleto ainda presente" "$CMD_INIT_AGENTE"; return 1 ;;
  esac
  case "$(grep -F 'no-op ate a FASE 5' "$CMD_RESUME_AGENTE" 2>/dev/null)" in
    "") : ;;
    *) _fail "marcador de pendencia obsoleto ainda presente" "$CMD_RESUME_AGENTE"; return 1 ;;
  esac
}

# ==== Uso REAL dos helpers (nenhuma flag inventada — Principio VI) ====

scenario_invoca_roadmap_frontier_com_flag_real() {
  assert_exit 0 grep -Fq 'roadmap-frontier.sh \' "$CMD_INIT_AGENTE" || return 1
}

scenario_invoca_exclude_active_from_repo() {
  assert_exit 0 grep -Fq -- '--exclude-active-from-repo <PAP>' "$CMD_INIT_AGENTE" || return 1
}

scenario_invoca_parallel_launch_emit() {
  assert_exit 0 grep -Fq 'parallel-launch.sh emit \' "$CMD_INIT_AGENTE" || return 1
}

scenario_emit_nunca_executa_documentado() {
  assert_exit 0 grep -Fiq 'nunca executa' "$CMD_INIT_AGENTE" || return 1
}

scenario_degradacao_sem_tmux_documentada() {
  # FR-007/SC-003: forma degradada exata do contrato §4.2.
  assert_exit 0 grep -Fq 'cd <WORKTREE> && claude --name ... "/feature-00c' "$CMD_INIT_AGENTE" || return 1
}

# ==== Guarda anti-duplicidade / TOCTOU (FR-011) ====

scenario_guarda_toctou_documentada() {
  assert_exit 0 grep -Fq 'TOCTOU, FR-011' "$CMD_INIT_AGENTE" || return 1
}

scenario_outcomes_blocked_reportados() {
  assert_exit 0 grep -Fq 'blocked-duplicate' "$CMD_INIT_AGENTE" || return 1
}

# ==== Confinamento de escopo (FR-012): decisao/lancamento nao vaza para feature-00c ====

scenario_ausente_em_feature_00c() {
  # Marcador de INVOCACAO real (com continuacao de linha `\`), nao mencao
  # em prosa explicativa — feature-00c.md pode legitimamente CITAR
  # `parallel-launch.sh emit` (explicando por que --coordinator-name nunca
  # e injetado) sem jamais INVOCA-LO (FR-012).
  [ -f "$CMD_INIT_FEAT" ] || { _error "arquivo ausente" "$CMD_INIT_FEAT"; return 2; }
  assert_exit 1 grep -Fq 'roadmap-frontier.sh \' "$CMD_INIT_FEAT" || return 1
  assert_exit 1 grep -Fq 'parallel-launch.sh emit \' "$CMD_INIT_FEAT" || return 1
}

scenario_ausente_em_feature_00c_resume() {
  [ -f "$CMD_RESUME_FEAT" ] || { _error "arquivo ausente" "$CMD_RESUME_FEAT"; return 2; }
  assert_exit 1 grep -Fq 'roadmap-frontier.sh \' "$CMD_RESUME_FEAT" || return 1
  assert_exit 1 grep -Fq 'parallel-launch.sh emit \' "$CMD_RESUME_FEAT" || return 1
}

# ==== FASE 3 task 3.1 — notificacao terminal (lado EMISSOR, feature-00c) ====

scenario_31_notificacao_presente_em_feature00c() {
  assert_exit 0 grep -Fq '### 5.quater Notificacao de leva paralela a sessao coordenadora' "$CMD_INIT_FEAT" || return 1
}

scenario_31_notificacao_presente_em_feature00c_resume() {
  assert_exit 0 grep -Fq '### 4.quinquies Notificacao de leva paralela a sessao coordenadora' "$CMD_RESUME_FEAT" || return 1
}

scenario_31_tres_desfechos_sem_sinonimo() {
  # CHK012: os 3 desfechos reais, verbatim, sem traducao/sinonimo.
  assert_exit 0 sh -c "grep -A8 -F '### 5.quater' '$CMD_INIT_FEAT' | tr '\\n' ' ' | grep -Fq 'concluida\`, \`abortada\`, \`aguardando_humano\`'" || return 1
}

scenario_31_best_effort_fr015_documentado() {
  assert_exit 0 grep -Fq 'Best-effort (FR-015)' "$CMD_INIT_FEAT" || return 1
}

scenario_31_sendmessage_no_allowed_tools() {
  assert_exit 0 sh -c "sed -n '1,12p' '$CMD_INIT_FEAT' | grep -Fq 'SendMessage'" || return 1
  assert_exit 0 sh -c "sed -n '1,10p' '$CMD_RESUME_FEAT' | grep -Fq 'SendMessage'" || return 1
}

scenario_31_payload_exato_do_contrato() {
  assert_exit 0 grep -Fq '_notify_payload="[cstk-parallel] feature=$SHORT outcome=$_status_final repo=$_repo_name"' "$CMD_INIT_FEAT" || return 1
}

# ==== FASE 3 task 3.2/3.3 — recepcao fail-closed + recalculo (lado RECEPTOR, agente-00c) ====

scenario_32_receptor_invoca_parser_dedicado() {
  assert_exit 0 grep -Fq 'parallel-notification-parse.sh' "$CMD_INIT_AGENTE" || return 1
  assert_exit 0 grep -Fq 'parallel-notification-parse.sh' "$CMD_RESUME_AGENTE" || return 1
}

scenario_32_gatilho_opaco_documentado() {
  assert_exit 0 grep -Fq 'INV-8' "$CMD_INIT_AGENTE" || return 1
}

scenario_33_recalculo_incondicional_documentado() {
  assert_exit 0 grep -Fiq 'NUNCA confie no payload' "$CMD_INIT_AGENTE" || return 1
}

scenario_33_reusa_fluxo_de_6ter() {
  assert_exit 0 grep -Fq 'fluxo de oferta INTEIRO de 6.ter' "$CMD_INIT_AGENTE" || return 1
}

scenario_34_pior_caso_recalculo_redundante_documentado() {
  # CHK107/quickstart.md C7b: notificacao forjada => no maximo recalculo
  # redundante, nunca lancamento fora da fronteira.
  assert_exit 0 grep -Fq 'recalculo redundante, nunca um lancamento fora da fronteira' "$CMD_INIT_AGENTE" || return 1
}

run_all_scenarios "$0"
