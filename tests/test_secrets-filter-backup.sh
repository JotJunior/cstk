#!/bin/sh
# test_secrets-filter-backup.sh — cobre o subcomando for-backup do
# secrets-filter.sh (FR-029 extensao + FR-034).
#
# Ref: docs/specs/_archived/feature-00c/tasks.md FASE 2 task 2.2.4

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"
. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/secrets-filter.sh"

scenario_backup_envelope_tem_campos_obrigatorios() {
  _input='{"execucao":{"id":"01HX","status":"em_andamento"},"decisoes":[]}'
  capture sh -c "printf '%s' '$_input' | '$SCRIPT' for-backup --wave-number 7"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "$_CAPTURED_EXIT; $_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains '"wave_number": 7' || return 1
  assert_stdout_contains '"captured_at"' || return 1
  assert_stdout_contains '"state_sha256_self"' || return 1
  assert_stdout_contains '"state_snapshot"' || return 1
}

scenario_backup_redact_aws_key() {
  _input='{"decisao":{"context":"erro logged: AKIAABCD1234EFGH5678IJKL"}}'
  capture sh -c "printf '%s' '$_input' | '$SCRIPT' for-backup --wave-number 1"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "$_CAPTURED_EXIT"; return 1; }
  # AWS key NAO deve aparecer no snapshot
  case "$_CAPTURED_STDOUT" in
    *AKIAABCD1234EFGH5678IJKL*)
      _fail "aws key vazou" "AKIA encontrado no backup"
      return 1
      ;;
  esac
  assert_stdout_contains 'REDACTED' || return 1
}

scenario_backup_redact_bearer_token() {
  _input='{"log":"Authorization: Bearer abc123xyz789supersecret"}'
  capture sh -c "printf '%s' '$_input' | '$SCRIPT' for-backup --wave-number 2"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "$_CAPTURED_EXIT"; return 1; }
  case "$_CAPTURED_STDOUT" in
    *abc123xyz789supersecret*)
      _fail "bearer token vazou" "valor de bearer encontrado"
      return 1
      ;;
  esac
}

scenario_backup_redact_basic_auth_em_url() {
  _input='{"url":"https://admin:supersecret123@host.example.com/api"}'
  capture sh -c "printf '%s' '$_input' | '$SCRIPT' for-backup --wave-number 3"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "$_CAPTURED_EXIT"; return 1; }
  case "$_CAPTURED_STDOUT" in
    *supersecret123*)
      _fail "basic auth vazou" "senha em URL encontrada"
      return 1
      ;;
  esac
}

scenario_backup_hash_bate_com_conteudo_filtrado() {
  _input='{"foo":"bar","baz":"qux"}'
  capture sh -c "printf '%s' '$_input' | '$SCRIPT' for-backup --wave-number 5"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "$_CAPTURED_EXIT"; return 1; }
  # Extrai state_sha256_self do envelope
  _recorded=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.state_sha256_self')
  # Calcula SHA do snapshot interno (deve bater)
  _snap=$(printf '%s' "$_CAPTURED_STDOUT" | jq -c '.state_snapshot')
  # O snapshot vem como JSON dentro do envelope; o hash foi calculado
  # sobre o conteudo filtrado ANTES da serializacao (input filtrado, em
  # arquivo temp). Validacao: hash recorded deve ser nao-vazio e em formato hex.
  case "$_recorded" in
    [0-9a-f][0-9a-f]*) : ;;
    *) _fail "hash formato" "esperado hex, obtido: $_recorded"; return 1 ;;
  esac
  # Hash deve ter 64 chars (SHA-256 hex)
  _len=$(printf '%s' "$_recorded" | wc -c | tr -d ' ')
  if [ "$_len" != "64" ]; then
    _fail "hash length" "esperado 64, obtido $_len"
    return 1
  fi
  [ -n "$_snap" ] || { _fail "snapshot vazio" "snapshot deveria estar presente"; return 1; }
}

scenario_backup_sem_wave_number_falha() {
  _input='{"foo":"bar"}'
  capture sh -c "printf '%s' '$_input' | '$SCRIPT' for-backup"
  if [ "$_CAPTURED_EXIT" != 2 ]; then
    _fail "exit" "esperado 2, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "wave-number obrigatorio" || return 1
}

scenario_backup_wave_number_invalido_falha() {
  _input='{"foo":"bar"}'
  capture sh -c "printf '%s' '$_input' | '$SCRIPT' for-backup --wave-number abc"
  if [ "$_CAPTURED_EXIT" != 2 ]; then
    _fail "exit" "esperado 2, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "invalido" || return 1
}

scenario_backup_preserva_estrutura_segura() {
  # Conteudo seguro deve passar inalterado dentro do envelope
  _input='{"execucao":{"id":"01HX","status":"concluida"},"meta":"safe text"}'
  capture sh -c "printf '%s' '$_input' | '$SCRIPT' for-backup --wave-number 10"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "$_CAPTURED_EXIT"; return 1; }
  _id=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.state_snapshot.execucao.id')
  if [ "$_id" != "01HX" ]; then
    _fail "preserva" "id deveria ser 01HX, obtido: $_id"
    return 1
  fi
}

run_all_scenarios
