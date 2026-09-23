#!/bin/sh
# test_command-wave-summary.sh — smoke textual sobre os 4 commands pai
# (feature-00c, feature-00c-resume, agente-00c, agente-00c-resume) que
# integram o resumo deterministico de fechamento de onda (wave-summary.sh).
#
# Feature: wave-close-summary
# Ref: docs/specs/wave-close-summary/tasks.md FASE 6 (6.5)
#      docs/specs/wave-close-summary/contracts/wave-summary-cli.md
#        §"Uso pelo command pai (padrao unico, os 4 commands)"
#      docs/specs/wave-close-summary/research.md Decision 6
#
# Natureza: assert TEXTUAL nos .md (a "integracao" e a instrucao embutida
# no proprio command, consumida por um agente LLM — nao ha script novo
# associado a esta FASE). NAO mapeia 1:1 a um unico .sh, portanto e
# registrado como interno em tests/run.sh::_is_internal_test (orphan-check)
# — mesmo padrao de test_command-spawn-model-routing.sh.
#
# Cobertura (tasks.md 6.5.1-6.5.3):
#   - wave-summary.sh emit aparece DEPOIS de reconcile-wave e ANTES de
#     ScheduleWakeup na ordem do texto (ordem por numero de linha)
#   - fallback "Resumo da onda indisponivel" presente nos 4 arquivos
#   - nenhuma das 4 secoes condiciona ScheduleWakeup/liberacao de lock/
#     ingestao ao exit do helper (grep negativo por
#     `wave-summary.sh emit && ...` seguido de ScheduleWakeup/state-lock/
#     recall --ingest na MESMA linha)

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

CMD_INIT_FEAT="$REPO_ROOT/plugins/cstk/commands/feature-00c.md"
CMD_RES_FEAT="$REPO_ROOT/plugins/cstk/commands/feature-00c-resume.md"
CMD_INIT_AGENTE="$REPO_ROOT/plugins/cstk/commands/agente-00c.md"
CMD_RES_AGENTE="$REPO_ROOT/plugins/cstk/commands/agente-00c-resume.md"

# _line_of FILE PATTERN -> imprime numero da PRIMEIRA linha que casa
# PATTERN (ERE) em FILE, vazio se nao casar.
_line_of() {
  grep -nE "$2" "$1" 2>/dev/null | head -n1 | cut -d: -f1
}

# _assert_order FILE -> reconcile-wave < wave-summary.sh emit <
# ScheduleWakeup, todas presentes.
_assert_order() {
  _f="$1"
  [ -f "$_f" ] || { _error "arquivo ausente" "$_f"; return 2; }

  _ln_reconcile=$(_line_of "$_f" 'reconcile-wave')
  _ln_wavesum=$(_line_of "$_f" 'wave-summary\.sh emit')
  # Usa a chamada REAL (ScheduleWakeup( ...) e nao a mera mencao em
  # allowed-tools do frontmatter (linha ~9-10 de todos os 4 arquivos, que
  # precede reconcile-wave e invalidaria a checagem de ordem).
  _ln_schedule=$(_line_of "$_f" 'ScheduleWakeup\(')

  if [ -z "$_ln_reconcile" ]; then
    _fail "reconcile-wave-ausente" "reconcile-wave nao encontrado em $_f"
    return 1
  fi
  if [ -z "$_ln_wavesum" ]; then
    _fail "wave-summary-ausente" "wave-summary.sh emit nao encontrado em $_f"
    return 1
  fi
  if [ -z "$_ln_schedule" ]; then
    _fail "schedulewakeup-ausente" "ScheduleWakeup nao encontrado em $_f"
    return 1
  fi

  if [ "$_ln_reconcile" -ge "$_ln_wavesum" ]; then
    _fail "ordem-invalida" "wave-summary.sh emit (linha $_ln_wavesum) nao esta APOS reconcile-wave (linha $_ln_reconcile) em $_f"
    return 1
  fi
  if [ "$_ln_wavesum" -ge "$_ln_schedule" ]; then
    _fail "ordem-invalida" "wave-summary.sh emit (linha $_ln_wavesum) nao esta ANTES de ScheduleWakeup (linha $_ln_schedule) em $_f"
    return 1
  fi
  return 0
}

# ==== 6.5.1: ordem reconcile-wave -> wave-summary.sh emit -> ScheduleWakeup ====

scenario_init_feat_ordem_wave_summary() {
  _assert_order "$CMD_INIT_FEAT" || return 1
}

scenario_resume_feat_ordem_wave_summary() {
  _assert_order "$CMD_RES_FEAT" || return 1
}

scenario_init_agente_ordem_wave_summary() {
  _assert_order "$CMD_INIT_AGENTE" || return 1
}

scenario_resume_agente_ordem_wave_summary() {
  _assert_order "$CMD_RES_AGENTE" || return 1
}

# ==== 6.5.2: fallback "Resumo da onda indisponivel" presente ====

scenario_init_feat_fallback_presente() {
  assert_exit 0 grep -qF 'Resumo da onda indisponivel' "$CMD_INIT_FEAT" || return 1
}

scenario_resume_feat_fallback_presente() {
  assert_exit 0 grep -qF 'Resumo da onda indisponivel' "$CMD_RES_FEAT" || return 1
}

scenario_init_agente_fallback_presente() {
  assert_exit 0 grep -qF 'Resumo da onda indisponivel' "$CMD_INIT_AGENTE" || return 1
}

scenario_resume_agente_fallback_presente() {
  assert_exit 0 grep -qF 'Resumo da onda indisponivel' "$CMD_RES_AGENTE" || return 1
}

# ==== 6.5.2 (complemento): $WS_OUT referenciado como incluido na mensagem final ====

scenario_init_feat_ws_out_referenciado() {
  assert_exit 0 grep -qF 'WS_OUT' "$CMD_INIT_FEAT" || return 1
}

scenario_resume_feat_ws_out_referenciado() {
  assert_exit 0 grep -qF 'WS_OUT' "$CMD_RES_FEAT" || return 1
}

scenario_init_agente_ws_out_referenciado() {
  assert_exit 0 grep -qF 'WS_OUT' "$CMD_INIT_AGENTE" || return 1
}

scenario_resume_agente_ws_out_referenciado() {
  assert_exit 0 grep -qF 'WS_OUT' "$CMD_RES_AGENTE" || return 1
}

# ==== 6.5.3: nenhuma secao condiciona ScheduleWakeup/lock/ingestao ao exit
# do helper (grep negativo por `wave-summary.sh emit && ...` seguido de
# ScheduleWakeup/state-lock/recall --ingest na MESMA linha) ====

_assert_no_conditioning() {
  _f="$1"
  if grep -nE 'wave-summary\.sh emit.*&&.*(ScheduleWakeup|state-lock\.sh|recall --ingest)' "$_f" >/dev/null 2>&1; then
    _fail "condicionamento-indevido" "wave-summary.sh emit condiciona ScheduleWakeup/lock/ingestao em $_f"
    return 1
  fi
  return 0
}

scenario_init_feat_sem_condicionamento() {
  [ -f "$CMD_INIT_FEAT" ] || { _error "arquivo ausente" "$CMD_INIT_FEAT"; return 2; }
  _assert_no_conditioning "$CMD_INIT_FEAT" || return 1
}

scenario_resume_feat_sem_condicionamento() {
  [ -f "$CMD_RES_FEAT" ] || { _error "arquivo ausente" "$CMD_RES_FEAT"; return 2; }
  _assert_no_conditioning "$CMD_RES_FEAT" || return 1
}

scenario_init_agente_sem_condicionamento() {
  [ -f "$CMD_INIT_AGENTE" ] || { _error "arquivo ausente" "$CMD_INIT_AGENTE"; return 2; }
  _assert_no_conditioning "$CMD_INIT_AGENTE" || return 1
}

scenario_resume_agente_sem_condicionamento() {
  [ -f "$CMD_RES_AGENTE" ] || { _error "arquivo ausente" "$CMD_RES_AGENTE"; return 2; }
  _assert_no_conditioning "$CMD_RES_AGENTE" || return 1
}

# ==== nunca set -e sobre a chamada — o padrao usa `||` de fallback, nunca
# a chamada crua sem fallback (WS_OUT=$(...) || WS_OUT="...") ====

scenario_init_feat_usa_fallback_or() {
  assert_exit 0 grep -Eq 'WS_OUT=\$\(wave-summary\.sh emit' "$CMD_INIT_FEAT" || return 1
}

scenario_resume_feat_usa_fallback_or() {
  assert_exit 0 grep -Eq 'WS_OUT=\$\(wave-summary\.sh emit' "$CMD_RES_FEAT" || return 1
}

scenario_init_agente_usa_fallback_or() {
  assert_exit 0 grep -Eq 'WS_OUT=\$\(wave-summary\.sh emit' "$CMD_INIT_AGENTE" || return 1
}

scenario_resume_agente_usa_fallback_or() {
  assert_exit 0 grep -Eq 'WS_OUT=\$\(wave-summary\.sh emit' "$CMD_RES_AGENTE" || return 1
}

run_all_scenarios "$0"
