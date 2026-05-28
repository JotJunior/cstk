#!/bin/sh
# test_whitelist-validate.sh — cobre global/skills/agente-00c-runtime/scripts/whitelist-validate.sh.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"
. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/whitelist-validate.sh"

_make_wl() {
  _f="$TMPDIR_TEST/wl"
  printf '%s\n' "$1" > "$_f"
  printf '%s\n' "$_f"
}

scenario_check_arquivo_inexistente_exit_2() {
  capture "$SCRIPT" check --whitelist-file "$TMPDIR_TEST/nope"
  if [ "$_CAPTURED_EXIT" != 2 ]; then
    _fail "arquivo inexistente" "esperado 2, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_check_so_validas_exit_0() {
  _wl=$(_make_wl 'https://api.github.com/repos/JotJunior/cstk/**
https://github.com/JotJunior/cstk
https://pkg.go.dev/**
https://*.npmjs.org/foo
http://localhost:8080/api/*')
  capture "$SCRIPT" check --whitelist-file "$_wl"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "validas exit" "$_CAPTURED_EXIT; $_CAPTURED_STDERR"; return 1; }
}

scenario_check_comentarios_e_vazias_ignoradas() {
  _wl=$(_make_wl '# comentario
https://github.com/foo/bar

# outro
https://api.example.com/path')
  capture "$SCRIPT" check --whitelist-file "$_wl"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "$_CAPTURED_STDERR"; return 1; }
}

scenario_rejeita_estrela_dupla_pura() {
  _wl=$(_make_wl '**')
  capture "$SCRIPT" check --whitelist-file "$_wl"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "** puro" "esperado 1"
    return 1
  fi
  assert_stderr_contains "puro" || return 1
}

scenario_rejeita_scheme_glob() {
  _wl=$(_make_wl '*://*')
  capture "$SCRIPT" check --whitelist-file "$_wl"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "*://*" "esperado 1"
    return 1
  fi
  assert_stderr_contains "scheme com glob" || return 1
}

scenario_rejeita_https_estrela() {
  _wl=$(_make_wl 'https://*')
  capture "$SCRIPT" check --whitelist-file "$_wl"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "https://*" "esperado 1"
    return 1
  fi
}

scenario_rejeita_sem_scheme() {
  _wl=$(_make_wl 'example.com/path')
  capture "$SCRIPT" check --whitelist-file "$_wl"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "sem scheme" "esperado 1"
    return 1
  fi
  assert_stderr_contains "scheme" || return 1
}

scenario_rejeita_host_vazio() {
  _wl=$(_make_wl 'https://')
  capture "$SCRIPT" check --whitelist-file "$_wl"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "host vazio" "esperado 1"
    return 1
  fi
}

scenario_rejeita_wildcard_no_meio_do_host() {
  _wl=$(_make_wl 'https://*foo.example.com/path')
  capture "$SCRIPT" check --whitelist-file "$_wl"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "*foo" "esperado 1"
    return 1
  fi
}

scenario_aceita_subdominio_wildcard_padrao() {
  _wl=$(_make_wl 'https://*.example.com/path')
  capture "$SCRIPT" check --whitelist-file "$_wl"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "*.example.com" "$_CAPTURED_STDERR"; return 1; }
}

scenario_list_imprime_nao_comentarios() {
  _wl=$(_make_wl '# comentario
https://github.com/foo/bar

# outro')
  capture "$SCRIPT" list --whitelist-file "$_wl"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" ""; return 1; }
  assert_stdout_contains "https://github.com/foo/bar" || return 1
  case "$_CAPTURED_STDOUT" in
    *comentario*) _fail "comentario vazou" ""; return 1 ;;
  esac
}

scenario_relatorio_indica_linha_e_motivo() {
  _wl=$(_make_wl '# header
https://github.com/foo
**
https://api.example.com/x')
  capture "$SCRIPT" check --whitelist-file "$_wl"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "exit" "esperado 1"
    return 1
  fi
  assert_stderr_contains "linha 3" || return 1
}

run_all_scenarios
