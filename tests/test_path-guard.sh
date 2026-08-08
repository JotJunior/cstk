#!/bin/sh
# test_path-guard.sh — cobre plugins/cstk/skills/agente-00c-runtime/scripts/path-guard.sh.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"
. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts/path-guard.sh"

scenario_validate_target_dir_normal_passa() {
  _p="$TMPDIR_TEST/proj"
  mkdir -p "$_p"
  capture "$SCRIPT" validate-target --projeto-alvo-path "$_p"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "$_CAPTURED_EXIT; $_CAPTURED_STDERR"; return 1; }
}

scenario_validate_target_etc_falha() {
  capture "$SCRIPT" validate-target --projeto-alvo-path "/etc"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "exit /etc" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "FR-024" || return 1
  assert_stderr_contains "zona proibida" || return 1
}

scenario_validate_target_home_ssh_falha() {
  capture env HOME="$TMPDIR_TEST/fakehome" "$SCRIPT" validate-target \
    --projeto-alvo-path "$TMPDIR_TEST/fakehome/.ssh"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "exit ~/.ssh" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_validate_target_home_claude_falha() {
  capture env HOME="$TMPDIR_TEST/fakehome" "$SCRIPT" validate-target \
    --projeto-alvo-path "$TMPDIR_TEST/fakehome/.claude/skills"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "exit ~/.claude" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_validate_target_symlink_para_zona_proibida_falha() {
  # Cria symlink que aponta para zona proibida — defesa T2
  _fakehome="$TMPDIR_TEST/fakehome"
  mkdir -p "$_fakehome/.ssh"
  _sneaky="$TMPDIR_TEST/sneaky"
  ln -s "$_fakehome/.ssh" "$_sneaky"
  capture env HOME="$_fakehome" "$SCRIPT" validate-target \
    --projeto-alvo-path "$_sneaky"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "symlink adversarial" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "zona proibida" || return 1
}

scenario_check_write_inside_passa() {
  _b="$TMPDIR_TEST/proj"
  mkdir -p "$_b"
  capture "$SCRIPT" check-write --projeto-alvo-path "$_b" --target "$_b/file.txt"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "inside" "$_CAPTURED_EXIT; $_CAPTURED_STDERR"; return 1; }
}

scenario_check_write_outside_etc_falha() {
  _b="$TMPDIR_TEST/proj"
  mkdir -p "$_b"
  capture "$SCRIPT" check-write --projeto-alvo-path "$_b" --target "/etc/passwd"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "outside /etc" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "FR-017" || return 1
}

scenario_check_write_outside_via_symlink_no_target_falha() {
  _b="$TMPDIR_TEST/proj"
  mkdir -p "$_b"
  _victim="$TMPDIR_TEST/victim/secrets"
  mkdir -p "$_victim"
  # Cria symlink dentro do projeto que aponta para fora
  ln -s "$_victim" "$_b/escape"
  capture "$SCRIPT" check-write --projeto-alvo-path "$_b" --target "$_b/escape/leak.txt"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "symlink no target" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_resolve_imprime_path_absoluto() {
  _p="$TMPDIR_TEST/proj"
  mkdir -p "$_p"
  capture "$SCRIPT" resolve "$_p"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "$_CAPTURED_EXIT"; return 1; }
  # Output deve comecar com /
  case "$_CAPTURED_STDOUT" in
    /*) ;;
    *) _fail "resolve" "esperado path absoluto, obtido: $_CAPTURED_STDOUT"; return 1 ;;
  esac
}

run_all_scenarios
