#!/bin/sh
# test_command-spawn-model-routing.sh — smoke textual sobre os 4 commands
# de spawn/resume que integram model-routing por onda (FASE 3 da feature
# model-routing-por-onda).
#
# Feature: model-routing-por-onda
# Ref: docs/specs/model-routing-por-onda/tasks.md FASE 3 (3.1.4, 3.2.2)
#      docs/specs/model-routing-por-onda/contracts/wave-select.md
#        §"Integração: commands de spawn (agente-00c, feature-00c) e resume"
#
# Natureza: assert TEXTUAL no .md (nao ha helper novo nesta fase — a
# "implementacao" e a instrucao de spawn embutida nos commands). Cobre as
# 4 fontes em plugins/cstk/commands/. NAO mapeia 1:1 a um unico .sh, portanto e
# registrado como interno em tests/run.sh::_is_internal_test (orphan-check).
#
# Cobertura (FR-002, FR-006, FR-009 / quickstart C8):
#   Para cada um dos 4 commands (agente-00c, feature-00c, *-resume):
#     - instrui `model-routing.sh wave-select --state-dir` ANTES do spawn
#     - instrui omitir o param `model` quando MODEL = manter-atual (FR-006/C8)
#     - instrui aplicar `model=<MODEL>` quando MODEL ∈ {haiku,sonnet,opus}
#     - menciona bidirecionalidade FR-009
#   Resumes preservam a guarda TOCTOU (nao removem lock/sha-verify).
#   POSIX-puro: snippet embutido sem `case` dentro de `$( )` (dec-003).

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

CMD_INIT_AGENTE="$REPO_ROOT/plugins/cstk/commands/agente-00c.md"
CMD_INIT_FEAT="$REPO_ROOT/plugins/cstk/commands/feature-00c.md"
CMD_RES_AGENTE="$REPO_ROOT/plugins/cstk/commands/agente-00c-resume.md"
CMD_RES_FEAT="$REPO_ROOT/plugins/cstk/commands/feature-00c-resume.md"

# _grep_file FILE PATTERN -> captura grep -E (exit 0 se casa). Helper
# textual reutilizado pelos scenarios (capture + assert_exit 0).
_grep_file() {
  capture grep -Eq "$2" "$1"
}

# ==== 3.1.4 / FR-002: wave-select instruido em CADA command ====

scenario_init_agente_instrui_wave_select() {
  [ -f "$CMD_INIT_AGENTE" ] || { _error "arquivo ausente" "$CMD_INIT_AGENTE"; return 2; }
  _grep_file "$CMD_INIT_AGENTE" 'model-routing\.sh wave-select --state-dir'
  assert_exit 0 grep -Eq 'model-routing\.sh wave-select --state-dir' "$CMD_INIT_AGENTE" || return 1
}

scenario_init_feat_instrui_wave_select() {
  [ -f "$CMD_INIT_FEAT" ] || { _error "arquivo ausente" "$CMD_INIT_FEAT"; return 2; }
  assert_exit 0 grep -Eq 'model-routing\.sh wave-select --state-dir' "$CMD_INIT_FEAT" || return 1
}

scenario_resume_agente_instrui_wave_select() {
  [ -f "$CMD_RES_AGENTE" ] || { _error "arquivo ausente" "$CMD_RES_AGENTE"; return 2; }
  assert_exit 0 grep -Eq 'model-routing\.sh wave-select --state-dir' "$CMD_RES_AGENTE" || return 1
}

scenario_resume_feat_instrui_wave_select() {
  [ -f "$CMD_RES_FEAT" ] || { _error "arquivo ausente" "$CMD_RES_FEAT"; return 2; }
  assert_exit 0 grep -Eq 'model-routing\.sh wave-select --state-dir' "$CMD_RES_FEAT" || return 1
}

# ==== 3.2.2 / FR-006 / quickstart C8: manter-atual -> omitir param model ====

scenario_init_agente_manter_atual_omite_model() {
  # Deve instruir explicitamente: MODEL = manter-atual -> spawnar SEM o param model.
  assert_exit 0 grep -Eq 'manter-atual.*[Ss][Ee][Mm] o param .?model' "$CMD_INIT_AGENTE" || return 1
}

scenario_init_feat_manter_atual_omite_model() {
  assert_exit 0 grep -Eq 'manter-atual.*[Ss][Ee][Mm] o param .?model' "$CMD_INIT_FEAT" || return 1
}

scenario_resume_agente_manter_atual_omite_model() {
  assert_exit 0 grep -Eq 'manter-atual.*[Ss][Ee][Mm] o param .?model' "$CMD_RES_AGENTE" || return 1
}

scenario_resume_feat_manter_atual_omite_model() {
  assert_exit 0 grep -Eq 'manter-atual.*[Ss][Ee][Mm] o param .?model' "$CMD_RES_FEAT" || return 1
}

# ==== 3.1.1/3.1.2: aplicar model=<MODEL> quando != manter-atual ====

scenario_init_agente_aplica_model_param() {
  # Cada command deve instruir o spawn com model=<MODEL> no caso != manter-atual.
  assert_exit 0 grep -Eq 'model=<MODEL>|model: <MODEL>' "$CMD_INIT_AGENTE" || return 1
}

scenario_init_feat_aplica_model_param() {
  assert_exit 0 grep -Eq 'model=<MODEL>|model: <MODEL>' "$CMD_INIT_FEAT" || return 1
}

scenario_resume_agente_aplica_model_param() {
  assert_exit 0 grep -Eq 'model=<MODEL>|model: <MODEL>' "$CMD_RES_AGENTE" || return 1
}

scenario_resume_feat_aplica_model_param() {
  assert_exit 0 grep -Eq 'model=<MODEL>|model: <MODEL>' "$CMD_RES_FEAT" || return 1
}

# ==== 3.1.3 / FR-009: bidirecionalidade mencionada ====

scenario_init_agente_menciona_bidirecionalidade() {
  assert_exit 0 grep -Eiq 'bidirecionalidade|FR-009' "$CMD_INIT_AGENTE" || return 1
}

scenario_init_feat_menciona_bidirecionalidade() {
  assert_exit 0 grep -Eiq 'bidirecionalidade|FR-009' "$CMD_INIT_FEAT" || return 1
}

scenario_resume_agente_menciona_bidirecionalidade() {
  assert_exit 0 grep -Eiq 'bidirecionalidade|FR-009' "$CMD_RES_AGENTE" || return 1
}

scenario_resume_feat_menciona_bidirecionalidade() {
  assert_exit 0 grep -Eiq 'bidirecionalidade|FR-009' "$CMD_RES_FEAT" || return 1
}

# ==== Resumes: preservar guarda TOCTOU (nao remover lock/sha-verify) ====

scenario_resume_agente_preserva_sha_verify() {
  # A guarda de integridade (sha256-verify) DEVE continuar presente apos a
  # insercao do passo wave-select — o passo 3 do resume nao pode ter sumido.
  assert_exit 0 grep -Eiq 'sha256-verify|sha-verify|validacao de hash|validate.*hash' "$CMD_RES_AGENTE" || return 1
}

scenario_resume_feat_preserva_sha_verify() {
  assert_exit 0 grep -Eiq 'sha256-verify|sha-verify|validacao de hash|validate.*hash|hash' "$CMD_RES_FEAT" || return 1
}

scenario_resume_agente_preserva_lock() {
  assert_exit 0 grep -Eq 'state-lock\.sh' "$CMD_RES_AGENTE" || return 1
}

scenario_resume_feat_preserva_lock() {
  assert_exit 0 grep -Eq 'state-lock\.sh' "$CMD_RES_FEAT" || return 1
}

# ==== POSIX-puro: snippet embutido sem `case` dentro de $( ) (dec-003) ====

scenario_no_case_dentro_de_command_substitution() {
  # Heuristica conservadora: a string literal "$(" seguida (em qualquer
  # ponto antes do fechamento) de " case " indicaria o anti-padrao dec-003.
  # Como os snippets de spawn usam MODEL=$(model-routing.sh ...) numa unica
  # linha sem `case`, asseguramos que nenhuma linha combine $( ... case.
  for _f in "$CMD_INIT_AGENTE" "$CMD_INIT_FEAT" "$CMD_RES_AGENTE" "$CMD_RES_FEAT"; do
    if grep -nE '\$\([^)]*\bcase\b' "$_f" >/dev/null 2>&1; then
      _fail "no_case_em_subshell" "anti-padrao dec-003 (case dentro de \$()) em $_f"
      return 1
    fi
  done
  return 0
}

run_all_scenarios "$0"
