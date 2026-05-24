#!/bin/sh
# test_run-modes.sh — cobre os modos/flags do proprio runner tests/run.sh:
# --fast, --slow, --stats (e o mutex --fast+--slow). Teste INTERNO: exercita o
# runner, nao um script sob a convencao 1:1 — registrado em
# run.sh::_is_internal_test (ramo test_smoke/test_harness/test_run-modes).
#
# Estrategia: invoca o run.sh real com cada flag e assere sobre stdout/stderr/
# exit. Usa apenas modos que NAO executam a suite (--list/--stats/--help/mutex),
# logo este teste e rapido (nada de rodar os ~1100 scenarios).
#
# Ancoras estaveis usadas:
#   test_smoke.sh — sempre presente e sempre RAPIDO (nunca na allowlist slow)
#   test_recall.sh — sempre presente e na allowlist slow (~82s medido)

# Sem 'set -eu' — convencao dos test files (ver test_smoke.sh).

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
. "$TESTS_ROOT/lib/harness.sh"
RUN_SH="$TESTS_ROOT/run.sh"

# _refute_stdout SUBSTRING — falha se a captura previa CONTEM substring.
# Complemento de assert_stdout_contains (o harness so tem o lado positivo).
_refute_stdout() {
  case "${_CAPTURED_STDOUT:-}" in
    *"$1"*)
      _fail "refute_stdout" "stdout contem (e nao deveria): $1"
      return "$_STATUS_FAIL"
      ;;
  esac
  return "$_STATUS_PASS"
}

scenario_fast_excludes_slow_keeps_fast() {
  # --fast --list: inclui o teste rapido (test_smoke), exclui o lento (recall).
  assert_exit 0 sh "$RUN_SH" --fast --list || return 1
  assert_stdout_contains "test_smoke.sh ::" || return 1
  _refute_stdout "test_recall.sh" || return 1
}

scenario_slow_keeps_slow_excludes_fast() {
  # --slow --list: inclui o lento (recall), exclui o rapido (test_smoke).
  assert_exit 0 sh "$RUN_SH" --slow --list || return 1
  assert_stdout_contains "test_recall.sh ::" || return 1
  _refute_stdout "test_smoke.sh" || return 1
}

scenario_fast_slow_mutually_exclusive() {
  # --fast + --slow juntos -> exit 2 com mensagem em stderr.
  assert_exit 2 sh "$RUN_SH" --fast --slow || return 1
  assert_stderr_contains "mutuamente exclusivos" || return 1
}

scenario_stats_outputs_count_and_total() {
  # --stats <pattern> -> linha 'N  arquivo' + linha TOTAL.
  assert_exit 0 sh "$RUN_SH" --stats recall || return 1
  assert_stdout_match '[0-9]+  test_recall.sh' || return 1
  assert_stdout_contains "TOTAL:" || return 1
}

scenario_stats_respects_speed_filter() {
  # --stats --slow conta so os lentos; nao deve listar o test_smoke (rapido).
  assert_exit 0 sh "$RUN_SH" --stats --slow || return 1
  assert_stdout_contains "test_recall.sh" || return 1
  _refute_stdout "test_smoke.sh" || return 1
}

scenario_stats_no_match_exit_2() {
  # PATTERN sem match -> exit 2 (consistente com --list).
  assert_exit 2 sh "$RUN_SH" --stats zzz-nao-existe-xyz || return 1
}

scenario_help_mentions_new_flags() {
  # --help documenta as 3 flags novas.
  assert_exit 0 sh "$RUN_SH" --help || return 1
  assert_stdout_contains "--fast" || return 1
  assert_stdout_contains "--slow" || return 1
  assert_stdout_contains "--stats" || return 1
}

run_all_scenarios
