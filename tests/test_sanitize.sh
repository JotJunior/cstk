#!/bin/sh
# test_sanitize.sh — cobre plugins/cstk/skills/agente-00c-runtime/scripts/sanitize.sh.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"
. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts/sanitize.sh"

scenario_limit_length_curto_passa_intacto() {
  capture sh -c "printf '%s' 'short text' | '$SCRIPT' limit-length --max 500"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" ""; return 1; }
  assert_stdout_contains "short text" || return 1
  case "$_CAPTURED_STDOUT" in
    *...*) _fail "marcador adicionado quando nao deveria" ""; return 1 ;;
  esac
}

scenario_limit_length_truncado_adiciona_reticencias() {
  capture sh -c "yes a | tr -d '\n' | head -c 600 | '$SCRIPT' limit-length --max 500"
  case "$_CAPTURED_STDOUT" in
    *...) ;;
    *) _fail "sem reticencias" ""; return 1 ;;
  esac
}

scenario_check_length_dentro_passa() {
  capture sh -c "printf '%s' 'ok' | '$SCRIPT' check-length --max 500"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "check" "$_CAPTURED_EXIT"; return 1; }
}

scenario_check_length_excede_falha() {
  capture sh -c "yes a | tr -d '\n' | head -c 600 | '$SCRIPT' check-length --max 500"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "check excede" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "excede" || return 1
}

scenario_escape_commit_msg_remove_newline() {
  capture sh -c "printf 'line1\nline2' | '$SCRIPT' escape-commit-msg"
  case "$_CAPTURED_STDOUT" in
    *line1*line2*) ;;
    *) _fail "perdeu conteudo" "$_CAPTURED_STDOUT"; return 1 ;;
  esac
  case "$_CAPTURED_STDOUT" in
    *$'\n'*) _fail "newline persistiu" ""; return 1 ;;
  esac
}

scenario_escape_commit_msg_remove_dollar_e_backtick() {
  capture sh -c "printf '%s' 'msg with \$x and \`evil\` and \"quote\"' | '$SCRIPT' escape-commit-msg"
  case "$_CAPTURED_STDOUT" in
    *'$'*) _fail "dollar persistiu" ""; return 1 ;;
    *'`'*) _fail "backtick persistiu" ""; return 1 ;;
    *'"'*) _fail "quote persistiu" ""; return 1 ;;
  esac
}

scenario_escape_issue_body_remove_subshell_e_backticks() {
  capture sh -c "printf '%s' 'paragraph with \$(rm -rf) and \`whoami\` calls' | '$SCRIPT' escape-issue-body"
  case "$_CAPTURED_STDOUT" in
    *'$('*) _fail "subshell persistiu" ""; return 1 ;;
    *'`'*) _fail "backtick persistiu" ""; return 1 ;;
  esac
  assert_stdout_contains "paragraph with" || return 1
}

scenario_escape_issue_body_preserva_newlines() {
  capture sh -c "printf 'line1\nline2' | '$SCRIPT' escape-issue-body"
  # Verifica que tem newline na saida
  _nl=$(printf '%s' "$_CAPTURED_STDOUT" | wc -l | tr -d ' ')
  if [ "$_nl" -lt 1 ]; then
    _fail "newlines perdidas" "$_CAPTURED_STDOUT"
    return 1
  fi
}

scenario_escape_path_remove_traversal() {
  capture sh -c "printf '%s' 'foo/../etc/passwd' | '$SCRIPT' escape-path"
  case "$_CAPTURED_STDOUT" in
    *../*) _fail "traversal persistiu" ""; return 1 ;;
    */etc/passwd) _fail "path traversal escape ineficaz" ""; return 1 ;;
  esac
  case "$_CAPTURED_STDOUT" in
    */*) _fail "slash persistiu" ""; return 1 ;;
  esac
}

scenario_escape_path_substitui_chars_unsafe() {
  capture sh -c "printf '%s' 'Bot Slack! Special#chars' | '$SCRIPT' escape-path"
  # Chars unsafe -> _
  case "$_CAPTURED_STDOUT" in
    *' '*) _fail "espaco persistiu" ""; return 1 ;;
    *'!'*) _fail "exclamacao persistiu" ""; return 1 ;;
    *'#'*) _fail "hash persistiu" ""; return 1 ;;
  esac
}

run_all_scenarios
