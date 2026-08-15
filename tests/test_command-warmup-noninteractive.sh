#!/bin/sh
# test_command-warmup-noninteractive.sh — smoke textual sobre a clausula de
# execucao NAO-INTERATIVA do warm-up de permissoes, embutida em
# plugins/cstk/commands/agente-00c.md e feature-00c.md.
#
# Ref: docs/specs/delivery-tier/quickstart.md Cenario 17
#
# Natureza: assert TEXTUAL nos .md (a "implementacao" e a prosa do command
# lida pelo LLM — nao ha helper .sh a exercitar), mesma familia de
# test_command-spawn-*.sh. Existence-guarded aos commands portadores.
#
# MOTIVO (achado empirico, spike headless 2026-08-15): rodando
# `claude -p '/agente-00c "..."'` num projeto sandbox, o command parava em
# `Continuar? [s/N]` do warm-up e encerrava com exit 0 SEM criar state-dir
# algum. Nenhuma execucao agendada/CI conseguia iniciar. O prompt de
# finalidade (delivery-tier) e o opt-in roadmap-mode ja tinham clausula de
# nao-interatividade; o warm-up, que vem ANTES dos dois, nao tinha — logo o
# caminho que essas clausulas protegiam era inalcancavel na pratica.
#
# Estes cenarios travam a clausula contra regressao nos DOIS commands: o
# gargalo so desaparece se ambos a tiverem (o /feature-00c reproduzia o
# mesmo aborto).

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

CMD_AGENTE="$REPO_ROOT/plugins/cstk/commands/agente-00c.md"
CMD_FEATURE="$REPO_ROOT/plugins/cstk/commands/feature-00c.md"

# ==== A clausula existe nos dois commands ====

scenario_agente_00c_tem_clausula_nao_interativa_no_warmup() {
  [ -f "$CMD_AGENTE" ] || { _error "arquivo ausente" "$CMD_AGENTE"; return 2; }
  assert_exit 0 grep -Eiq '\*\*Nao-interativo\*\*: PULE o warm-up' "$CMD_AGENTE" || return 1
}

scenario_feature_00c_tem_clausula_nao_interativa_no_warmup() {
  [ -f "$CMD_FEATURE" ] || { _error "arquivo ausente" "$CMD_FEATURE"; return 2; }
  assert_exit 0 grep -Eiq '\*\*Nao-interativo\*\*: PULE o warm-up' "$CMD_FEATURE" || return 1
}

# ==== Semantica: PULAR e prosseguir, nunca abortar nem aguardar ====

scenario_agente_00c_proibe_abortar_em_nao_interativo() {
  assert_exit 0 grep -Eiq 'nunca aborte, nunca fique aguardando' "$CMD_AGENTE" || return 1
}

scenario_feature_00c_proibe_abortar_em_nao_interativo() {
  assert_exit 0 grep -Eiq 'nunca aborte, nunca fique aguardando' "$CMD_FEATURE" || return 1
}

scenario_agente_00c_prossegue_para_o_passo_1() {
  assert_exit 0 grep -Eiq 'PULE o warm-up inteiro e prossiga para o passo 1' "$CMD_AGENTE" || return 1
}

scenario_feature_00c_prossegue_para_o_passo_1() {
  assert_exit 0 grep -Eiq 'PULE o warm-up inteiro e prossiga para o passo 1' "$CMD_FEATURE" || return 1
}

# ==== A decisao e auditavel (nao e skip silencioso) ====

scenario_agente_00c_registra_decisao_do_skip() {
  assert_exit 0 grep -Eq 'Warm-up de permissoes pulado: execucao' "$CMD_AGENTE" || return 1
}

scenario_feature_00c_registra_decisao_do_skip() {
  assert_exit 0 grep -Eq 'Warm-up de permissoes pulado: execucao' "$CMD_FEATURE" || return 1
}

# ==== Pular o warm-up NAO afrouxa guarda alguma ====
#
# O warm-up so enfileira prompts de permissao; as guardas enforced sao
# mecanismo separado (hook PreToolUse fail-closed). Sem esta ressalva
# escrita, "pular o warm-up" e facilmente lido como "rodar sem guardas".

scenario_agente_00c_ressalva_guardas_intactas() {
  assert_exit 0 grep -Eiq 'NAO afrouxa nenhuma guarda' "$CMD_AGENTE" || return 1
}

scenario_feature_00c_ressalva_guardas_intactas() {
  assert_exit 0 grep -Eiq 'NAO afrouxa nenhuma guarda' "$CMD_FEATURE" || return 1
}

scenario_agente_00c_cita_hook_fail_closed() {
  assert_exit 0 grep -Eiq 'PreToolUse.*fail-closed|fail-closed' "$CMD_AGENTE" || return 1
}

scenario_feature_00c_cita_hook_fail_closed() {
  assert_exit 0 grep -Eiq 'PreToolUse.*fail-closed|fail-closed' "$CMD_FEATURE" || return 1
}

# ==== O caminho interativo continua intacto ====
#
# A clausula e ADITIVA: com operador presente, o warm-up segue obrigatorio
# e a nao-confirmacao continua abortando.

scenario_agente_00c_preserva_aborto_interativo() {
  assert_exit 0 grep -Eq 'Se o operador NAO confirmar' "$CMD_AGENTE" || return 1
}

scenario_feature_00c_preserva_aborto_interativo() {
  assert_exit 0 grep -Eq 'Se o operador NAO confirmar' "$CMD_FEATURE" || return 1
}

scenario_agente_00c_preserva_pergunta_de_confirmacao() {
  assert_exit 0 grep -Eq 'Continuar\? \[s/N\]' "$CMD_AGENTE" || return 1
}

scenario_feature_00c_preserva_pergunta_de_confirmacao() {
  assert_exit 0 grep -Eq 'Continuar\? \[s/N\]' "$CMD_FEATURE" || return 1
}

run_all_scenarios "$0"
