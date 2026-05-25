#!/bin/sh
# test_runtime-log-redaction.sh — cobre _log.sh (FR-036).
#
# Ref: docs/specs/_archived/feature-00c/tasks.md FASE 2 task 2.3.4
#      docs/specs/_archived/feature-00c/spec.md FR-036

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"
. "$TESTS_ROOT/lib/harness.sh"

SCRIPTS_DIR="$REPO_ROOT/global/skills/agente-00c-runtime/scripts"
HELPER="$SCRIPTS_DIR/_log.sh"
export AGENTE_00C_RUNTIME_SCRIPTS_DIR="$SCRIPTS_DIR"

scenario_log_err_redact_aws_key() {
  capture sh -c ". '$HELPER' && log_err 'erro: token AKIAABCD1234EFGH5678IJKL falhou'"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "$_CAPTURED_EXIT"; return 1; }
  # stderr deve conter REDACTED, NAO o AWS key
  case "$_CAPTURED_STDERR" in
    *AKIAABCD1234EFGH5678IJKL*)
      _fail "aws key vazou em stderr" "AKIA encontrado: $_CAPTURED_STDERR"
      return 1
      ;;
  esac
  assert_stderr_contains "REDACTED" || return 1
}

scenario_log_err_redact_bearer_em_stderr() {
  capture sh -c ". '$HELPER' && log_err 'falha: Bearer secret_token_xyz_123'"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "$_CAPTURED_EXIT"; return 1; }
  case "$_CAPTURED_STDERR" in
    *secret_token_xyz_123*)
      _fail "bearer vazou em stderr" "valor bearer encontrado"
      return 1
      ;;
  esac
}

scenario_log_out_redact_para_stdout() {
  capture sh -c ". '$HELPER' && log_out 'estado: token=secretsuperlong20charsplus_real'"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "$_CAPTURED_EXIT"; return 1; }
  # stdout deve conter REDACTED
  assert_stdout_contains "REDACTED" || return 1
  case "$_CAPTURED_STDOUT" in
    *secretsuperlong20charsplus_real*)
      _fail "secret vazou em stdout" "padrao token=... mantido"
      return 1
      ;;
  esac
}

scenario_log_err_texto_seguro_passa() {
  capture sh -c ". '$HELPER' && log_err 'mensagem normal sem secrets'"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "$_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "mensagem normal sem secrets" || return 1
}

scenario_log_out_texto_seguro_passa() {
  capture sh -c ". '$HELPER' && log_out 'output normal'"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "$_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "output normal" || return 1
}

scenario_log_err_fallback_quando_filter_ausente() {
  # Criar um helper "fake" em um dir temp onde secrets-filter.sh nao existe
  _fake_dir="$TMPDIR_TEST/fake-scripts"
  mkdir -p "$_fake_dir"
  cp "$HELPER" "$_fake_dir/_log.sh"
  # NOTA: secrets-filter.sh propositalmente AUSENTE
  # Apontar env var para o dir fake (sem filter) para testar fallback
  capture env AGENTE_00C_RUNTIME_SCRIPTS_DIR="$_fake_dir" \
    sh -c ". '$_fake_dir/_log.sh' && log_err 'mensagem fallback'"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "$_CAPTURED_EXIT"; return 1; }
  # Sem filter, fallback emite com prefixo [NO-FILTER]
  assert_stderr_contains "NO-FILTER" || return 1
  assert_stderr_contains "mensagem fallback" || return 1
}

run_all_scenarios
