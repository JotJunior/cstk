#!/bin/sh
# test_command-wakeup-schedule.sh — smoke textual sobre os 4 commands pai
# (agente-00c, agente-00c-resume, feature-00c, feature-00c-resume) que
# gravam o horario agendado da proxima onda e diagnosticam wakeup perdido.
#
# Issue #248: desde o Claude Code 2.1.329 o agendamento vive na sessao que o
# criou (sessao nova nao o re-executa; `claude --resume` sim). O command pai
# — unico que conhece o delaySeconds aplicado — grava
# .waves[-1].next_wave_scheduled_for via `state-ondas.sh record-schedule`, e
# os resumes rodam `state-ondas.sh wakeup-check` (read-only) antes de
# retomar.
#
# Natureza: assert TEXTUAL nos .md (a integracao e a instrucao embutida no
# command, consumida por um agente LLM). Os subcomandos em si sao cobertos
# por tests/test_state-ondas.sh. Registrado como interno em
# tests/run.sh::_is_internal_test (orphan-check).
#
# Cobertura:
#   - record-schedule aparece nos 4 commands, DEPOIS de uma chamada real
#     `ScheduleWakeup(` e sempre best-effort (`|| :`)
#   - wakeup-check aparece nos 2 resumes, best-effort, ANTES do spawn do
#     orquestrador
#   - os 4 commands orientam `claude --resume` ao operador

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

CMD_INIT_FEAT="$REPO_ROOT/plugins/cstk/commands/feature-00c.md"
CMD_RES_FEAT="$REPO_ROOT/plugins/cstk/commands/feature-00c-resume.md"
CMD_INIT_AGENTE="$REPO_ROOT/plugins/cstk/commands/agente-00c.md"
CMD_RES_AGENTE="$REPO_ROOT/plugins/cstk/commands/agente-00c-resume.md"

_line_of() {
  grep -nE "$2" "$1" 2>/dev/null | head -n1 | cut -d: -f1
}

# _assert_record_after_schedule FILE -> record-schedule presente, best-effort
# e depois da primeira chamada real ScheduleWakeup( (ou da linha da tabela
# `Invocar ScheduleWakeup(`).
_assert_record_after_schedule() {
  _f="$1"
  [ -f "$_f" ] || { _error "arquivo ausente" "$_f"; return 2; }
  _ln_sched=$(_line_of "$_f" 'ScheduleWakeup\(')
  _ln_rec=$(_line_of "$_f" 'state-ondas\.sh record-schedule')
  [ -n "$_ln_sched" ] || { _fail "schedule-ausente" "ScheduleWakeup( nao encontrado em $_f"; return 1; }
  [ -n "$_ln_rec" ] || { _fail "record-schedule-ausente" "record-schedule nao encontrado em $_f"; return 1; }
  [ "$_ln_rec" -gt "$_ln_sched" ] \
    || { _fail "ordem" "record-schedule (L$_ln_rec) antes de ScheduleWakeup( (L$_ln_sched) em $_f"; return 1; }
  grep -Eq 'state-ondas\.sh record-schedule .*--delay-seconds <N> \|\| :' "$_f" \
    || { _fail "best-effort" "record-schedule sem '--delay-seconds <N> || :' em $_f"; return 1; }
}

# _assert_wakeup_check_before_spawn FILE -> wakeup-check presente,
# best-effort, antes da primeira mencao a spawn do orquestrador.
_assert_wakeup_check_before_spawn() {
  _f="$1"
  [ -f "$_f" ] || { _error "arquivo ausente" "$_f"; return 2; }
  _ln_wk=$(_line_of "$_f" 'WK_OUT=\$\(state-ondas\.sh wakeup-check')
  _ln_spawn=$(_line_of "$_f" 'reconcile-wave')
  [ -n "$_ln_wk" ] || { _fail "wakeup-check-ausente" "wakeup-check nao encontrado em $_f"; return 1; }
  [ -n "$_ln_spawn" ] || { _fail "ancora-ausente" "reconcile-wave nao encontrado em $_f"; return 1; }
  [ "$_ln_wk" -lt "$_ln_spawn" ] \
    || { _fail "ordem" "wakeup-check (L$_ln_wk) depois de reconcile-wave (L$_ln_spawn) em $_f"; return 1; }
  grep -Eq 'WK_OUT=\$\(state-ondas\.sh wakeup-check .*\|\| WK_OUT=""' "$_f" \
    || { _fail "best-effort" "wakeup-check sem fallback '|| WK_OUT=\"\"' em $_f"; return 1; }
}

scenario_init_agente_grava_horario() { _assert_record_after_schedule "$CMD_INIT_AGENTE"; }
scenario_resume_agente_grava_horario() { _assert_record_after_schedule "$CMD_RES_AGENTE"; }
scenario_init_feat_grava_horario() { _assert_record_after_schedule "$CMD_INIT_FEAT"; }
scenario_resume_feat_grava_horario() { _assert_record_after_schedule "$CMD_RES_FEAT"; }

scenario_resume_agente_diagnostica_wakeup() { _assert_wakeup_check_before_spawn "$CMD_RES_AGENTE"; }
scenario_resume_feat_diagnostica_wakeup() { _assert_wakeup_check_before_spawn "$CMD_RES_FEAT"; }

scenario_quatro_commands_orientam_claude_resume() {
  for _f in "$CMD_INIT_AGENTE" "$CMD_RES_AGENTE" "$CMD_INIT_FEAT" "$CMD_RES_FEAT"; do
    grep -q 'claude --resume' "$_f" \
      || { _fail "orientacao-ausente" "'claude --resume' nao citado em $_f"; return 1; }
  done
}

run_all_scenarios "$0"
