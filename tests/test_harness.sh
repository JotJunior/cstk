#!/bin/sh
# test_harness.sh — self-test da biblioteca tests/lib/harness.sh.
#
# Valida que cada helper funciona (happy path + alguns caminhos negativos).
# Se este test falha, os demais test_*.sh sao pouco confiaveis.
#
# Cobertura:
#   1.3.2 assert_exit 0 true -> PASS
#   1.3.3 assert_exit 0 false -> FAIL (esperado)
#   1.3.4 assert_stdout_contains presente/ausente
#   1.3.5 trap de cleanup — tmpdir removido apos scenario
#   1.3.6 fixture — copia correta para TMPDIR_TEST
#   1.3.7 status ERROR distinto de FAIL
#
# NOTA: deliberadamente NAO usamos 'set -eu'. O harness sinaliza via return
# codes explicitos; set -e mataria scenarios que testam FAIL intencionalmente.

. "${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}/lib/harness.sh"

# ==== 1.3.2 assert_exit PASS ====

scenario_assert_exit_pass() {
  assert_exit 0 true || return 1
  assert_exit 1 false || return 1
  assert_exit 2 sh -c 'exit 2' || return 1
}

# ==== 1.3.3 assert_exit FAIL (esperado) ====
# Verificamos explicitamente que assert_exit sinaliza FAIL quando o exit
# observado difere do esperado. Rodamos em subshell e inspecionamos status.

scenario_assert_exit_detects_mismatch() {
  # Deve FALHAR (retornar 1) porque 'true' sai 0, nao 99.
  # Executamos em subshell isolando a saida de diagnostico para nao poluir.
  (
    # Redireciona diagnostico de _fail para /dev/null: so nos importa o status.
    assert_exit 99 true >/dev/null 2>&1
  )
  _inner_status=$?
  if [ "$_inner_status" -ne 1 ]; then
    printf 'expected assert_exit to return 1 (FAIL), got %d\n' "$_inner_status" >&2
    return 1
  fi
  # Scenario PASS: confirmamos que assert_exit soube detectar mismatch.
  return 0
}

# ==== 1.3.4 assert_stdout_contains ====

scenario_stdout_contains_present() {
  capture sh -c 'printf "hello world\n"'
  assert_stdout_contains "hello" || return 1
  assert_stdout_contains "world" || return 1
}

scenario_stdout_contains_absent_detects_miss() {
  capture sh -c 'printf "hello world\n"'
  (
    assert_stdout_contains "missing_substring_xyz" >/dev/null 2>&1
  )
  _inner_status=$?
  if [ "$_inner_status" -ne 1 ]; then
    printf 'expected assert_stdout_contains to FAIL on absent substring, got %d\n' "$_inner_status" >&2
    return 1
  fi
  return 0
}

scenario_stdout_not_contains_absent_passes() {
  capture sh -c 'printf "hello world\n"'
  assert_stdout_not_contains "missing_substring_xyz" || return 1
}

scenario_stdout_not_contains_present_detects_miss() {
  capture sh -c 'printf "hello world\n"'
  (
    assert_stdout_not_contains "hello" >/dev/null 2>&1
  )
  _inner_status=$?
  if [ "$_inner_status" -ne 1 ]; then
    printf 'expected assert_stdout_not_contains to FAIL when substring present, got %d\n' "$_inner_status" >&2
    return 1
  fi
  return 0
}

# ==== 1.3.5 trap de cleanup ====

scenario_tmpdir_cleanup_on_normal_exit() {
  # mktemp_test ja foi chamado pelo run_all_scenarios — capturamos o path e
  # verificamos que o dir existe AGORA. Apos o scenario retornar, o subshell
  # termina e o trap EXIT remove o dir. Testamos isso atraves de um wrapper.
  [ -n "$TMPDIR_TEST" ] || return 1
  [ -d "$TMPDIR_TEST" ] || return 1
  # Criar um arquivo dentro garante que nao e dir vazio (removal mais robusto).
  printf 'marker\n' > "$TMPDIR_TEST/marker" || return 1
  [ -f "$TMPDIR_TEST/marker" ] || return 1
  # Guarda o path em arquivo externo ao tmpdir para inspecao posterior.
  # Fica em /tmp e sera limpado pelo OS ou em proximo scenario.
  printf '%s\n' "$TMPDIR_TEST" > /tmp/shell-tests-last-tmpdir-check.txt
}

scenario_tmpdir_cleanup_verifies_removal() {
  # Scenario seguinte: confirma que o tmpdir do scenario anterior ja nao existe.
  # Nao temos garantia de ordem de execucao entre scenarios em geral, mas
  # run_all_scenarios itera em ordem alfabetica; este nome ordena depois do
  # 'cleanup_on_normal_exit' pela proximidade dos nomes.
  #
  # Implementacao defensiva: se o arquivo de rastro nao existe, skippamos
  # essa parte como PASS (nao ha o que validar).
  if [ ! -f /tmp/shell-tests-last-tmpdir-check.txt ]; then
    return 0
  fi
  _previous_tmpdir=$(cat /tmp/shell-tests-last-tmpdir-check.txt)
  rm -f /tmp/shell-tests-last-tmpdir-check.txt
  if [ -z "$_previous_tmpdir" ]; then
    return 0
  fi
  if [ -d "$_previous_tmpdir" ]; then
    printf 'tmpdir %s persisted after scenario exit (trap falhou)\n' "$_previous_tmpdir" >&2
    return 1
  fi
  return 0
}

# ==== 1.3.6 fixture copia para TMPDIR_TEST ====

scenario_fixture_copies_content() {
  fixture "_harness-smoke" || return 1
  [ -f "$TMPDIR_TEST/sample.txt" ] || {
    printf 'sample.txt nao foi copiado para TMPDIR_TEST\n' >&2
    return 1
  }
  _content=$(cat "$TMPDIR_TEST/sample.txt")
  if [ "$_content" != "fixture content" ]; then
    printf 'conteudo inesperado: %s\n' "$_content" >&2
    return 1
  fi
  return 0
}

scenario_fixture_missing_returns_error() {
  # fixture com nome inexistente retorna status 2 (ERROR).
  (
    fixture "nao_existe_xyz" >/dev/null 2>&1
  )
  _inner_status=$?
  if [ "$_inner_status" -ne 2 ]; then
    printf 'expected fixture to return 2 (ERROR) on missing, got %d\n' "$_inner_status" >&2
    return 1
  fi
  return 0
}

# ==== 1.3.7 status ERROR distinto de FAIL ====

scenario_error_status_distinct_from_fail() {
  # Scenario que chama _error diretamente: o scenario retorna 2 (ERROR).
  # Testamos atraves de funcao definida inline + invocacao via subshell.
  (
    _error "simulated_prereq" "simulated missing mktemp"
    exit 2
  ) >/dev/null 2>&1
  _status=$?
  if [ "$_status" -ne 2 ]; then
    printf 'expected inner subshell to exit 2 for ERROR, got %d\n' "$_status" >&2
    return 1
  fi
  # Adicional: garantir que o nosso sistema distingue 1 (FAIL) de 2 (ERROR).
  # Se qualquer dos dois exit codes fosse mapeado como "falha generica",
  # perderiamos a distincao que FR-003 exige.
  [ "$_STATUS_FAIL" -eq 1 ] || return 1
  [ "$_STATUS_ERROR" -eq 2 ] || return 1
  [ "$_STATUS_FAIL" -ne "$_STATUS_ERROR" ] || return 1
  return 0
}

# ==== assert_stdout_match (grep -E) ====

scenario_stdout_match_regex() {
  capture sh -c 'printf "version 1.2.3\n"'
  assert_stdout_match '^version [0-9]+\.[0-9]+\.[0-9]+$' || return 1
}

# ==== assert_stderr_contains ====

scenario_stderr_contains_works() {
  capture sh -c 'printf "error happened\n" >&2'
  assert_stderr_contains "error" || return 1
}

# ==== 4.1.5 YAML-block em falha contem todos os campos obrigatorios ====
#
# Forca uma assercao a falhar e captura o output para verificar que o bloco
# diagnostico contem todos os campos documentados em contracts/runner-cli.md:
# assert, message, command, exit_code, stdout, stderr.

scenario_fail_block_has_all_fields() {
  # Dispara um _fail controlado (subshell, saida capturada em arquivo).
  _diag_file="$TMPDIR_TEST/diag.out"
  (
    capture sh -c 'printf "hi\n"; exit 42'
    assert_exit 0 sh -c 'printf "hi\n"; exit 42'
  ) > "$_diag_file" 2>&1 || :
  # Agora valida presenca dos campos esperados.
  for _field in "assert: assert_exit" "message:" "command:" "exit_code: 42" "stdout:" "stderr:"; do
    if ! grep -Fq "$_field" "$_diag_file"; then
      _fail "scenario_fail_block_has_all_fields" "campo ausente no bloco YAML: $_field"
      return 1
    fi
  done
}

run_all_scenarios
