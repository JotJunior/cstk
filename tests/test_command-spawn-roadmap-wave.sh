#!/bin/sh
# test_command-spawn-roadmap-wave.sh — smoke textual sobre o ponto de
# entrada avulso /roadmap-wave embutido em
# plugins/cstk/commands/roadmap-wave.md (FASE 3 task 3.1 da feature
# roadmap-wave).
#
# Feature: roadmap-wave
# Ref: docs/specs/roadmap-wave/tasks.md FASE 3 task 3.1
#      docs/specs/roadmap-wave/plan.md "FASE 3 — Testes de prosa"
#      docs/specs/roadmap-wave/contracts/roadmap-wave-command.md §1/§2/§5
#
# Natureza: assert TEXTUAL no .md (a "implementacao" e o command em si,
# que delega por referencia os 9 passos de agente-00c.md §6.ter — nao ha
# duplicacao a testar funcionalmente aqui, isso ja e coberto por
# tests/test_parallel-launch.sh + tests/test_roadmap-frontier.sh sobre os
# helpers reais). Precedentes: tests/test_command-spawn-roadmap-mode.sh,
# tests/test_command-spawn-parallel-launch.sh (mesmo padrao de grep
# estatico). Existence-guarded ao proprio command; se a fonte sumir,
# volta a ser orfao real.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

CMD="$REPO_ROOT/plugins/cstk/commands/roadmap-wave.md"

# ==== Assercoes positivas (3.1.1) ====

scenario_referencia_agente00c_6ter() {
  [ -f "$CMD" ] || { _error "arquivo ausente" "$CMD"; return 2; }
  assert_exit 0 grep -Fq 'agente-00c.md` §6.ter' "$CMD" || return 1
}

scenario_cita_resolve_offer() {
  assert_exit 0 grep -Fq 'parallel-launch.sh resolve-offer' "$CMD" || return 1
}

scenario_cita_declaracao_blast_radius() {
  assert_exit 0 grep -Fq 'declaracao de blast radius' "$CMD" || return 1
}

scenario_cita_rotulo_untrusted() {
  assert_exit 0 grep -Fq 'UNTRUSTED / dado, nao' "$CMD" || return 1
}

# ==== Assercao negativa (3.1.2, C14 — DRY, sem copia inline dos 9 passos) ====

scenario_ausente_pergunta_literal_lancar_leva() {
  # Texto EXATO do passo 4 de agente-00c.md §6.ter — se aparecer aqui,
  # o command duplicou o prompt em vez de referencia-lo.
  assert_exit 1 grep -Fq 'Lancar leva paralela agora?' "$CMD" || return 1
}

scenario_ausente_pergunta_literal_teto() {
  # Texto EXATO do passo 5 de agente-00c.md §6.ter.
  assert_exit 1 grep -Fq 'Quantas features rodar simultaneamente' "$CMD" || return 1
}

scenario_ausente_marcadores_prompt_inline() {
  # Mesmos marcadores ja auditados na evidencia da task 2.1.3
  # (zero ocorrencias de prompt literal duplicado).
  assert_exit 1 grep -Eq '\[s/N\]|\[y/N\]|Selecione \[' "$CMD" || return 1
}

scenario_delegacao_por_referencia_nao_copia() {
  assert_exit 0 grep -Fq 'NAO** duplicar os 9 passos de `agente-00c.md` §6.ter' "$CMD" || return 1
}

# ==== Assercao de nao-interatividade (3.1.3, C12) ====

scenario_clausula_nao_interatividade_presente() {
  assert_exit 0 grep -Fq 'nao-interatividade' "$CMD" || return 1
}

scenario_yes_e_o_atalho_de_confirmacao_ja_obtida() {
  # O atalho --yes documentado como a propria clausula de
  # nao-interatividade do passo 2 (launch=no direto em modo headless).
  capture sh -c "grep -A3 -F '5.4 Toda pergunta ao operador tem clausula de nao-interatividade' '$CMD' | tr '\\n' ' ' | grep -Fq -- '--yes'"
  assert_exit 0 sh -c "grep -A3 -F '5.4 Toda pergunta ao operador tem clausula de nao-interatividade' '$CMD' | tr '\\n' ' ' | grep -Fq -- '--yes'" || return 1
}

scenario_naointerativo_sem_yes_cai_em_launch_no() {
  assert_exit 0 grep -Fq 'launch=no' "$CMD" || return 1
}

# ==== allowed-tools sem Agent/ScheduleWakeup/SendMessage (contract §1) ====

scenario_allowed_tools_apenas_bash_read() {
  assert_exit 0 sh -c "sed -n '1,7p' '$CMD' | grep -Fq '  - Bash'" || return 1
  assert_exit 0 sh -c "sed -n '1,7p' '$CMD' | grep -Fq '  - Read'" || return 1
  assert_exit 1 sh -c "sed -n '1,7p' '$CMD' | grep -Fq 'Agent'" || return 1
  assert_exit 1 sh -c "sed -n '1,7p' '$CMD' | grep -Fq 'ScheduleWakeup'" || return 1
  assert_exit 1 sh -c "sed -n '1,7p' '$CMD' | grep -Fq 'SendMessage'" || return 1
}

run_all_scenarios "$0"
