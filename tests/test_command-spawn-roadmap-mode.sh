#!/bin/sh
# test_command-spawn-roadmap-mode.sh — smoke textual sobre o prompt opt-in
# do modo roadmap embutido em plugins/cstk/commands/agente-00c.md (FASE 6
# task 6.2.2 da feature roadmap-mode, extensao aditiva ao prose-lint da
# familia test_command-spawn-*.sh).
#
# Feature: roadmap-mode
# Ref: docs/specs/roadmap-mode/tasks.md FASE 6 task 6.2.2
#      docs/specs/roadmap-mode/plan.md Fase D passo 12
#      docs/specs/roadmap-mode/contracts/cli-roadmap-mode.md
#
# Natureza: assert TEXTUAL no .md (nao ha helper novo — a "implementacao"
# e o bloco de prompt embutido no command). Cobre APENAS
# plugins/cstk/commands/agente-00c.md: o modo roadmap e um conceito de
# NIVEL DE PROJETO (briefing -> constitution -> roadmap), nao existe em
# feature-00c.md nem nos *-resume.md (resumes leem .roadmap_mode_enabled
# do state.json sem reprompt — nao ha prosa dedicada la). Existence-guarded
# ao command portador do prompt; se a fonte sumir, volta a ser orfao real.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

CMD_INIT_AGENTE="$REPO_ROOT/plugins/cstk/commands/agente-00c.md"
CMD_INIT_FEAT="$REPO_ROOT/plugins/cstk/commands/feature-00c.md"

# ==== Prompt opt-in presente e com default seguro (FR-001) ====

scenario_prompt_opt_in_presente() {
  [ -f "$CMD_INIT_AGENTE" ] || { _error "arquivo ausente" "$CMD_INIT_AGENTE"; return 2; }
  assert_exit 0 grep -Eq 'Habilitar o modo roadmap\? \[s/N\]' "$CMD_INIT_AGENTE" || return 1
}

scenario_afirmativas_setam_roadmap_true() {
  assert_exit 0 grep -Eq '_roadmap=true' "$CMD_INIT_AGENTE" || return 1
}

scenario_default_seguro_roadmap_false() {
  # Texto-fonte quebra em 2 linhas ("(default\n  seguro..."); junta a
  # janela de 2 linhas antes de casar (grep multi-linha nao e portavel).
  capture sh -c "grep -A1 -F '_roadmap=false' '$CMD_INIT_AGENTE' | tr '\\n' ' ' | grep -Eq 'default[[:space:]]+seguro'"
  assert_exit 0 sh -c "grep -A1 -F '_roadmap=false' '$CMD_INIT_AGENTE' | tr '\\n' ' ' | grep -Eq 'default[[:space:]]+seguro'" || return 1
}

scenario_nao_interativo_cai_no_default() {
  # FR-001: nenhuma execucao pode travar esperando resposta.
  assert_exit 0 grep -Eiq 'Nao-interativo.*cai no default' "$CMD_INIT_AGENTE" || return 1
}

# ==== Resume nao re-promptа (paridade com atomic-commit) ====

scenario_resume_nao_reprompta_documentado() {
  assert_exit 0 grep -Eq '\.roadmap_mode_enabled.*state\.json.*sem interacao' "$CMD_INIT_AGENTE" || return 1
}

# ==== Flag repassada ao init do state.json, comportamento atual intacto ====

scenario_flag_passada_ao_state_rw_init() {
  assert_exit 0 grep -Eq -- '--roadmap-mode "\$_roadmap"' "$CMD_INIT_AGENTE" || return 1
}

scenario_false_documentado_como_comportamento_atual_intacto() {
  assert_exit 0 grep -Eq -- '--roadmap-mode "\$_roadmap".*comportamento atual intacto' "$CMD_INIT_AGENTE" || return 1
}

# ==== Confinamento de escopo: roadmap e conceito de projeto, nao de feature ====

scenario_ausente_em_feature_00c() {
  # roadmap-mode nao existe no escopo feature-00c (pipeline
  # specify->clarify->plan->...); confirma que a prosa nao vazou.
  [ -f "$CMD_INIT_FEAT" ] || { _error "arquivo ausente" "$CMD_INIT_FEAT"; return 2; }
  assert_exit 1 grep -Eiq 'modo roadmap' "$CMD_INIT_FEAT" || return 1
}

run_all_scenarios "$0"
