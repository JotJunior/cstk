#!/bin/sh
# test__hash.sh — cobre _hash.sh (wrapper sha256 cross-platform).
# Ref: spec FR-CACHE-016A, tasks T1.7.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

HASH_LIB="$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts/_hash.sh"

# Sourcear o helper (nao eh executavel)
# shellcheck disable=SC1090
. "$HASH_LIB"

scenario_sha256_file_arquivo_existente() {
  _f="$TMPDIR_TEST/x.txt"
  printf 'hello world\n' >"$_f"
  _h=$(_hash_sha256_file "$_f")
  _expected="a948904f2f0f479b8f8197694b30184b0d2ed1c1cd2a1ec0fb85d299a192a447"
  if [ "$_h" != "$_expected" ]; then
    _fail "hash inesperado: $_h (esperado $_expected)"
    return 1
  fi
}

scenario_sha256_file_path_vazio_exit_1() {
  _hash_sha256_file "" 2>/dev/null
  _rc=$?
  if [ "$_rc" != "1" ]; then
    _fail "exit esperado 1, got $_rc"
    return 1
  fi
}

scenario_sha256_file_path_inexistente_exit_1() {
  _hash_sha256_file "/tmp/no-such-file-$$" 2>/dev/null
  _rc=$?
  if [ "$_rc" != "1" ]; then
    _fail "exit esperado 1, got $_rc"
    return 1
  fi
}

scenario_sha256_stdin_funciona() {
  _h=$(printf 'hello world\n' | _hash_sha256_stdin)
  _expected="a948904f2f0f479b8f8197694b30184b0d2ed1c1cd2a1ec0fb85d299a192a447"
  if [ "$_h" != "$_expected" ]; then
    _fail "hash inesperado: $_h (esperado $_expected)"
    return 1
  fi
}

scenario_sha256_file_64_hex_chars() {
  _f="$TMPDIR_TEST/y.txt"
  printf 'qualquer conteudo\n' >"$_f"
  _h=$(_hash_sha256_file "$_f")
  _len=${#_h}
  if [ "$_len" != "64" ]; then
    _fail "esperado 64 chars hex, got $_len ($_h)"
    return 1
  fi
  # Validar hex
  case "$_h" in
    *[!0-9a-f]*)
      _fail "hash contem caracter nao-hex: $_h"
      return 1
      ;;
  esac
}

scenario_sha256_file_deterministico() {
  _f="$TMPDIR_TEST/z.txt"
  printf 'deterministico\n' >"$_f"
  _h1=$(_hash_sha256_file "$_f")
  _h2=$(_hash_sha256_file "$_f")
  if [ "$_h1" != "$_h2" ]; then
    _fail "hashes diferentes para mesma entrada: $_h1 vs $_h2"
    return 1
  fi
}

# ==== Issue #157: sha256 em Windows/Git-Bash (MINGW*/MSYS*/CYGWIN*) ====
#
# Antes do fix, `uname -s` = MINGW64_NT-* caia no ramo `*)` e devolvia exit 2
# ("SO nao suportado"), mesmo com sha256sum presente e funcional — o que
# inviabilizava TODO write de state no Windows.
#
# Os scenarios abaixo shadowam `uname` via PATH stub (o SUT invoca `uname`
# sem qualificar path, entao o stub vence). PATH original preservado a
# direita para que sha256sum/shasum/awk continuem resolvendo.

# _hash_stub_uname VALOR -> cria stub de `uname -s` em $TMPDIR_TEST/bin e
# exporta PATH com ele na frente. Escopo: subshell do scenario corrente.
_hash_stub_uname() {
  mkdir -p "$TMPDIR_TEST/bin" || return 1
  cat >"$TMPDIR_TEST/bin/uname" <<EOF
#!/bin/sh
if [ "\$1" = "-s" ]; then
  printf '%s\\n' '$1'
  exit 0
fi
exec /usr/bin/uname "\$@"
EOF
  chmod +x "$TMPDIR_TEST/bin/uname" || return 1
  PATH="$TMPDIR_TEST/bin:$PATH"
  export PATH
}

scenario_sha256_file_mingw_suportado() {
  _hash_stub_uname "MINGW64_NT-10.0-26200" || return 2
  _f="$TMPDIR_TEST/w.txt"
  printf 'hello world\n' >"$_f"
  _h=$(_hash_sha256_file "$_f")
  _rc=$?
  _expected="a948904f2f0f479b8f8197694b30184b0d2ed1c1cd2a1ec0fb85d299a192a447"
  if [ "$_rc" != "0" ]; then
    _fail "exit esperado 0 sob MINGW64, got $_rc"
    return 1
  fi
  if [ "$_h" != "$_expected" ]; then
    _fail "hash inesperado sob MINGW64: $_h (esperado $_expected)"
    return 1
  fi
}

scenario_sha256_stdin_mingw_suportado() {
  _hash_stub_uname "MINGW64_NT-10.0-26200" || return 2
  _h=$(printf 'hello world\n' | _hash_sha256_stdin)
  _expected="a948904f2f0f479b8f8197694b30184b0d2ed1c1cd2a1ec0fb85d299a192a447"
  if [ "$_h" != "$_expected" ]; then
    _fail "hash inesperado sob MINGW64 (stdin): $_h (esperado $_expected)"
    return 1
  fi
}

scenario_sha256_stdin_msys_suportado() {
  _hash_stub_uname "MSYS_NT-10.0-26200" || return 2
  _h=$(printf 'hello world\n' | _hash_sha256_stdin)
  _expected="a948904f2f0f479b8f8197694b30184b0d2ed1c1cd2a1ec0fb85d299a192a447"
  if [ "$_h" != "$_expected" ]; then
    _fail "hash inesperado sob MSYS: $_h (esperado $_expected)"
    return 1
  fi
}

scenario_sha256_stdin_cygwin_suportado() {
  _hash_stub_uname "CYGWIN_NT-10.0" || return 2
  _h=$(printf 'hello world\n' | _hash_sha256_stdin)
  _expected="a948904f2f0f479b8f8197694b30184b0d2ed1c1cd2a1ec0fb85d299a192a447"
  if [ "$_h" != "$_expected" ]; then
    _fail "hash inesperado sob CYGWIN: $_h (esperado $_expected)"
    return 1
  fi
}

# Contrato negativo: o fail-closed do ramo `*)` NAO foi afrouxado — um SO
# genuinamente desconhecido continua exit 2, sem degradar mudo.
scenario_sha256_stdin_so_desconhecido_exit_2() {
  _hash_stub_uname "Plan9" || return 2
  printf 'x\n' | _hash_sha256_stdin >/dev/null 2>&1
  _rc=$?
  if [ "$_rc" != "2" ]; then
    _fail "exit esperado 2 em SO desconhecido, got $_rc"
    return 1
  fi
}

run_all_scenarios
