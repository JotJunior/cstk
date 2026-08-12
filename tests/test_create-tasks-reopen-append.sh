#!/bin/sh
# test_create-tasks-reopen-append.sh — guarda ESTRUTURAL (INTERNO) sobre
# plugins/cstk/skills/create-tasks/SKILL.md §Deteccao de reabertura.
#
# Contexto (feature-reopen FASE 6.2): create-tasks ganhou uma secao gated
# por `.previous_round` (contexto de reabertura via `/feature-00c
# --reopen`) que, quando o `tasks.md`-alvo ja existe, apenda uma fase nova
# ao final em vez de regenerar o backlog do zero — mesmo padrao ja
# praticado pela skill `converge` (research.md Decision 11, FR-015).
#
# `create-tasks/SKILL.md` e prosa consumida por um agente LLM — este teste
# e um guard de PRESENCA/AUSENCIA de texto (regressao estrutural), nao um
# teste comportamental. Cobre tambem, via tests/test_next-task-id.sh, o
# unico pedaco executavel novo desta FASE (`next-task-id.sh --phase`).

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

SKILL_MD="$REPO_ROOT/plugins/cstk/skills/create-tasks/SKILL.md"

# ==== 6.2-a: arquivo existe ====

scenario_skill_md_existe() {
  [ -f "$SKILL_MD" ] || { printf 'SKILL.md nao encontrado: %s\n' "$SKILL_MD" >&2; return 1; }
  return 0
}

# ==== 6.2-b: nao-regressao — deteccao de origem original intacta ====

scenario_deteccao_origem_original_intacta() {
  grep -qF '### Deteccao de Origem (Spec vs Standalone)' "$SKILL_MD" || return 1
  grep -qF '**Se chamado de forma isolada** (sem spec associada):' "$SKILL_MD" || return 1
  return 0
}

# ==== 6.2-c: gated — deteccao de .previous_round + tasks.md existente ====

scenario_deteccao_reabertura_presente() {
  grep -qF '### Deteccao de reabertura' "$SKILL_MD" || return 1
  grep -qF "'.previous_round'" "$SKILL_MD" || return 1
  grep -qF 'ja existe' "$SKILL_MD" || return 1
  return 0
}

# ==== 6.2-d: 6.2.1 — nunca regenerar / preservar marcacoes [x] ====

scenario_nunca_regenerar_preserva_x() {
  grep -qF 'NUNCA regenerar' "$SKILL_MD" || return 1
  grep -qF 'marcacao `[x]` ja' "$SKILL_MD" || return 1
  return 0
}

# ==== 6.2-e: 6.2.2 — fase apendada via next-task-id.sh --phase, precedente converge ====

scenario_fase_apendada_via_next_task_id() {
  grep -qF 'next-task-id.sh \' "$SKILL_MD" || return 1
  grep -qF -- '--phase' "$SKILL_MD" || return 1
  grep -qF 'skill `converge`' "$SKILL_MD" || return 1
  return 0
}

# ==== 6.2-f: 6.2.3 — idempotencia (grep FR-NNN ja referenciado) ====

scenario_idempotencia_referenciada() {
  grep -qF 'Idempotencia (6.2.3)' "$SKILL_MD" || return 1
  return 0
}

# ==== 6.2-g: ordem estrutural — reabertura entre Deteccao de Origem e gaps do checklist ====

scenario_ordem_estrutural() {
  _LN_ORIGEM=$(grep -n '^### Deteccao de Origem' "$SKILL_MD" | head -n1 | cut -d: -f1)
  _LN_REOPEN=$(grep -n '^### Deteccao de reabertura' "$SKILL_MD" | head -n1 | cut -d: -f1)
  _LN_GAPS=$(grep -n '^### Consumir gaps abertos' "$SKILL_MD" | head -n1 | cut -d: -f1)
  [ -n "$_LN_ORIGEM" ] && [ -n "$_LN_REOPEN" ] && [ -n "$_LN_GAPS" ] || return 1
  [ "$_LN_ORIGEM" -lt "$_LN_REOPEN" ] || return 1
  [ "$_LN_REOPEN" -lt "$_LN_GAPS" ] || return 1
  return 0
}

run_all_scenarios
