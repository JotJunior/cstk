#!/bin/sh
# test_self-update.sh — cobre cli/lib/self-update.sh (FASE 5).
#
# Cobre Scenario 6 (happy path), Scenario 7 (network/checksum drop),
# Scenario 7b (kill em 4 pontos criticos via CSTK_TEST_SU_ABORT_AT —
# valida estados observaveis FR-006), invariante FR-006a (manifest mtime
# preservado), --check, --dry-run, --scope rejeitado, --force+--keep n/a,
# recovery do estado transiente.
#
# Estrategia: cada cenario instala v1 via bootstrap (CSTK_RELEASE_URL),
# entao chama o BINARIO INSTALADO (com sed do CSTK_EMBEDDED_VERSION) com
# CSTK_RELEASE_URL apontando para v2. O cstk instalado usa o lib interno
# (que tambem foi copiado pelo bootstrap), entao o codigo testado e
# realmente o release-shape.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

CSTK_LIB="$REPO_ROOT/cli/lib"
export CSTK_LIB

# _make_release_pair: monta releases v1 e v2 no $TMPDIR_TEST/r-vN/.
# Tags fixas (v1.0 e v2.0) para todos os cenarios.
_make_release_pair() {
  for _tag in v1.0 v2.0; do
    _root="$TMPDIR_TEST/r-$_tag/cstk-$_tag"
    mkdir -p "$_root/cli/lib" || return 1
    cp -- "$REPO_ROOT/cli/cstk" "$_root/cli/cstk" || return 1
    cp -- "$REPO_ROOT/cli/lib/"*.sh "$_root/cli/lib/" || return 1
    (cd "$TMPDIR_TEST/r-$_tag" && tar -czf "cstk-$_tag.tar.gz" "cstk-$_tag") || return 1
    if command -v sha256sum >/dev/null 2>&1; then
      (cd "$TMPDIR_TEST/r-$_tag" && sha256sum "cstk-$_tag.tar.gz" > "cstk-$_tag.tar.gz.sha256") || return 1
    else
      (cd "$TMPDIR_TEST/r-$_tag" && shasum -a 256 "cstk-$_tag.tar.gz" > "cstk-$_tag.tar.gz.sha256") || return 1
    fi
  done
  return 0
}

_install_v1() {
  _h=$1
  _url="file://$TMPDIR_TEST/r-v1.0/cstk-v1.0.tar.gz"
  capture env HOME="$_h" \
    INSTALL_BIN="$_h/.local/bin" INSTALL_LIB="$_h/.local/share/cstk" \
    CSTK_RELEASE_URL="$_url" \
    sh "$REPO_ROOT/cli/install.sh"
  return $_CAPTURED_EXIT
}

# _run_su: invoca o binario INSTALADO com CSTK_RELEASE_URL apontando para vN.
_run_su() {
  _h=$1; _vtag=$2; shift 2
  _url="file://$TMPDIR_TEST/r-$_vtag/cstk-$_vtag.tar.gz"
  capture env HOME="$_h" \
    CSTK_BIN="$_h/.local/bin/cstk" \
    CSTK_LIB="$_h/.local/share/cstk/lib" \
    CSTK_RELEASE_URL="$_url" \
    PATH="$PATH" \
    "$_h/.local/bin/cstk" self-update "$@"
}

_run_su_with_abort() {
  _h=$1; _vtag=$2; _abort=$3; shift 3
  _url="file://$TMPDIR_TEST/r-$_vtag/cstk-$_vtag.tar.gz"
  capture env HOME="$_h" \
    CSTK_BIN="$_h/.local/bin/cstk" \
    CSTK_LIB="$_h/.local/share/cstk/lib" \
    CSTK_RELEASE_URL="$_url" \
    CSTK_TEST_SU_ABORT_AT="$_abort" \
    PATH="$PATH" \
    "$_h/.local/bin/cstk" self-update "$@"
}

_installed_version() {
  # Override CSTK_LIB para a instalacao isolada — o env do test file exporta
  # CSTK_LIB apontando pro repo, o que faz o cstk ler cli/VERSION em vez do
  # VERSION instalado em $_h/.local/share/cstk/lib/VERSION.
  CSTK_LIB="$1/.local/share/cstk/lib" \
    "$1/.local/bin/cstk" --version 2>/dev/null | awk '{print $2}'
}

_mtime() {
  # Linux/GNU stat (-c %Y) PRIMEIRO. Em macOS/BSD, -c falha com nao-zero
  # e cai no fallback BSD (-f %m). Ordem inversa quebra no Linux: stat -f %m
  # exit 0 mas imprime info do filesystem (Block size, Inodes, etc.) em vez
  # de mtime do arquivo, mascarando o fallback correto.
  if stat -c %Y -- "$1" 2>/dev/null; then return 0; fi
  stat -f %m -- "$1" 2>/dev/null
}

# ==== Scenario 6: Happy path v1 → v2 ====

scenario_self_update_happy_path() {
  _h="$TMPDIR_TEST/h"
  _make_release_pair || { _error "fixture" ""; return 2; }
  _install_v1 "$_h" || { _fail "install v1" ""; return 1; }
  [ "$(_installed_version "$_h")" = "v1.0" ] || { _fail "v1 setup" ""; return 1; }

  _run_su "$_h" v2.0
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "self-update exit" "$_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"
    return 1
  fi
  if [ "$(_installed_version "$_h")" != "v2.0" ]; then
    _fail "post-update version" "ainda na v1"
    return 1
  fi
  # bin's CSTK_EMBEDDED_VERSION foi sed'do para v2.0
  grep -q '^CSTK_EMBEDDED_VERSION="v2.0"$' "$_h/.local/bin/cstk" \
    || { _fail "bin embedded nao foi sed" ""; return 1; }
  # lib's VERSION = v2.0
  [ "$(cat "$_h/.local/share/cstk/lib/VERSION")" = "v2.0" ] \
    || { _fail "lib VERSION nao atualizada" ""; return 1; }
}

# ==== --check ====

scenario_self_update_check_no_update() {
  _h="$TMPDIR_TEST/h"
  _make_release_pair || { _error "fixture" ""; return 2; }
  _install_v1 "$_h" || { _fail "install" ""; return 1; }
  _run_su "$_h" v1.0 --check
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "--check exit (no update)" "esperado 0, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stdout_contains "latest:v1.0 current:v1.0" || return 1
}

scenario_self_update_check_update_available() {
  _h="$TMPDIR_TEST/h"
  _make_release_pair || { _error "fixture" ""; return 2; }
  _install_v1 "$_h" || { _fail "install" ""; return 1; }
  _run_su "$_h" v2.0 --check
  if [ "$_CAPTURED_EXIT" != 10 ]; then
    _fail "--check exit (update avail)" "esperado 10, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stdout_contains "latest:v2.0 current:v1.0" || return 1
}

# ==== --scope rejeitado ====

scenario_self_update_scope_rejected() {
  _h="$TMPDIR_TEST/h"
  _make_release_pair || { _error "fixture" ""; return 2; }
  _install_v1 "$_h" || { _fail "install" ""; return 1; }
  _run_su "$_h" v2.0 --scope global
  # parse_args retorna 1 internamente; update_main mapeia para exit 2 (USAGE)
  if [ "$_CAPTURED_EXIT" != 2 ]; then
    _fail "--scope rejeitado exit" "esperado 2 (USAGE), obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "scope" || return 1
}

# ==== http:// texto plano rejeitado (revisao 5.15.0) ====
# MITM pode trocar tarball E .sha256 juntos; checksum de mesma origem nao
# protege origem adulterada. So https:// e file:// passam.

scenario_self_update_from_http_plano_aborta() {
  _h="$TMPDIR_TEST/h-http"
  _make_release_pair || { _error "fixture" ""; return 2; }
  _install_v1 "$_h" || { _fail "install" ""; return 1; }
  capture env HOME="$_h" \
    CSTK_BIN="$_h/.local/bin/cstk" \
    CSTK_LIB="$_h/.local/share/cstk/lib" \
    PATH="$PATH" \
    "$_h/.local/bin/cstk" self-update --from "http://example.com/cstk-9.9.9.tar.gz"
  if [ "$_CAPTURED_EXIT" = 0 ]; then
    _fail "http --from exit" "esperado nao-zero, obtido 0"
    return 1
  fi
  assert_stderr_contains "http:// rejeitado" || return 1
}

# ==== Lock detido => exit 3 ====

scenario_self_update_lock_held() {
  _h="$TMPDIR_TEST/h"
  _make_release_pair || { _error "fixture" ""; return 2; }
  _install_v1 "$_h" || { _fail "install" ""; return 1; }
  mkdir -p "$_h/.local/share/cstk/.self-update.lock"
  _run_su "$_h" v2.0
  if [ "$_CAPTURED_EXIT" != 3 ]; then
    _fail "lock conflito exit" "esperado 3, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

# ==== FR-010a: checksum mismatch nao escreve nada ====

scenario_self_update_checksum_mismatch_zero_writes() {
  _h="$TMPDIR_TEST/h"
  _make_release_pair || { _error "fixture" ""; return 2; }
  _install_v1 "$_h" || { _fail "install" ""; return 1; }
  printf 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef  cstk-v2.0.tar.gz\n' \
    > "$TMPDIR_TEST/r-v2.0/cstk-v2.0.tar.gz.sha256"

  _bin_before=$(_mtime "$_h/.local/bin/cstk")
  _lib_before=$(_mtime "$_h/.local/share/cstk/lib/VERSION")
  sleep 1.1

  _run_su "$_h" v2.0
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "mismatch exit" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "MISMATCH" || return 1
  # bin e lib intocados
  _bin_after=$(_mtime "$_h/.local/bin/cstk")
  _lib_after=$(_mtime "$_h/.local/share/cstk/lib/VERSION")
  if [ "$_bin_before" != "$_bin_after" ]; then
    _fail "bin mtime mudou em mismatch" "$_bin_before -> $_bin_after"
    return 1
  fi
  if [ "$_lib_before" != "$_lib_after" ]; then
    _fail "lib VERSION mtime mudou em mismatch" "$_lib_before -> $_lib_after"
    return 1
  fi
}

# ==== FR-006a: NAO toca manifest de skills ====

scenario_self_update_nao_toca_manifest() {
  _h="$TMPDIR_TEST/h"
  _make_release_pair || { _error "fixture" ""; return 2; }
  _install_v1 "$_h" || { _fail "install" ""; return 1; }
  # Cria um manifest "fake" com mtime conhecido
  mkdir -p "$_h/.claude/skills"
  printf '# cstk manifest v1\n# schema: x\nfoo\tv1\tabc\t2026-01-01T00:00:00Z\n' \
    > "$_h/.claude/skills/.cstk-manifest"
  _mfst_before=$(_mtime "$_h/.claude/skills/.cstk-manifest")
  _mfst_sha_before=$(shasum -a 256 "$_h/.claude/skills/.cstk-manifest" 2>/dev/null \
    || sha256sum "$_h/.claude/skills/.cstk-manifest")
  sleep 1.1

  _run_su "$_h" v2.0
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "self-update exit" "$_CAPTURED_STDERR"; return 1; }

  _mfst_after=$(_mtime "$_h/.claude/skills/.cstk-manifest")
  _mfst_sha_after=$(shasum -a 256 "$_h/.claude/skills/.cstk-manifest" 2>/dev/null \
    || sha256sum "$_h/.claude/skills/.cstk-manifest")
  if [ "$_mfst_before" != "$_mfst_after" ]; then
    _fail "manifest mtime mudou (FR-006a)" "$_mfst_before -> $_mfst_after"
    return 1
  fi
  if [ "$_mfst_sha_before" != "$_mfst_sha_after" ]; then
    _fail "manifest hash mudou (FR-006a)" "$_mfst_sha_before -> $_mfst_sha_after"
    return 1
  fi
}

# ==== FR-006: atomicidade — kill em 4 pontos criticos ====

scenario_self_update_kill_after_download() {
  _h="$TMPDIR_TEST/h"
  _make_release_pair || { _error "fixture" ""; return 2; }
  _install_v1 "$_h" || { _fail "install" ""; return 1; }
  _run_su_with_abort "$_h" v2.0 after-download
  if [ "$_CAPTURED_EXIT" != 99 ]; then
    _fail "abort exit" "esperado 99, obtido $_CAPTURED_EXIT"
    return 1
  fi
  # Estado: 100% antiga (nada renomeado)
  if [ "$(_installed_version "$_h")" != "v1.0" ]; then
    _fail "estado pos-abort" "deveria estar 100% antiga"
    return 1
  fi
  grep -q '^CSTK_EMBEDDED_VERSION="v1.0"$' "$_h/.local/bin/cstk" \
    || { _fail "bin embedded mudou" ""; return 1; }
}

scenario_self_update_kill_after_stage() {
  _h="$TMPDIR_TEST/h"
  _make_release_pair || { _error "fixture" ""; return 2; }
  _install_v1 "$_h" || { _fail "install" ""; return 1; }
  _run_su_with_abort "$_h" v2.0 after-stage
  if [ "$_CAPTURED_EXIT" != 99 ]; then
    _fail "abort exit" "$_CAPTURED_EXIT"
    return 1
  fi
  # Estado: 100% antiga; .new files podem estar presentes mas nao renomeados
  [ "$(_installed_version "$_h")" = "v1.0" ] || { _fail "estado" "deveria 100% antiga"; return 1; }
  # Os arquivos .new podem ter sido criados (esperado)
  if [ ! -d "$_h/.local/share/cstk/lib.new" ]; then
    _fail "stage" "lib.new ausente apos abort em after-stage"
    return 1
  fi
  if [ ! -f "$_h/.local/bin/cstk.new" ]; then
    _fail "stage" "cstk.new ausente apos abort em after-stage"
    return 1
  fi
}

scenario_self_update_kill_between_lib_bin_recovery() {
  _h="$TMPDIR_TEST/h"
  _make_release_pair || { _error "fixture" ""; return 2; }
  _install_v1 "$_h" || { _fail "install" ""; return 1; }
  _run_su_with_abort "$_h" v2.0 between-lib-bin
  if [ "$_CAPTURED_EXIT" != 99 ]; then
    _fail "abort exit" "$_CAPTURED_EXIT"
    return 1
  fi
  # Estado transiente: lib swapped (v2), bin nao (v1)
  [ "$(cat "$_h/.local/share/cstk/lib/VERSION")" = "v2.0" ] \
    || { _fail "lib nao foi swapped" ""; return 1; }
  grep -q '^CSTK_EMBEDDED_VERSION="v1.0"$' "$_h/.local/bin/cstk" \
    || { _fail "bin foi swapped por engano" ""; return 1; }

  # Comando NAO-self-update deve ser bloqueado pelo boot-check (FR-006c)
  capture env HOME="$_h" CSTK_BIN="$_h/.local/bin/cstk" \
    CSTK_LIB="$_h/.local/share/cstk/lib" \
    "$_h/.local/bin/cstk" install --from foo
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "boot-check nao acionou em install" "exit $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "bin/lib version mismatch" || return 1
  assert_stderr_contains "self-update parece estar em progresso" || return 1

  # Recovery: re-rodar self-update completa o swap
  _run_su "$_h" v2.0
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "recovery exit" "$_CAPTURED_EXIT; $_CAPTURED_STDERR"
    return 1
  fi
  if [ "$(_installed_version "$_h")" != "v2.0" ]; then
    _fail "recovery version" "ainda nao na v2"
    return 1
  fi
  grep -q '^CSTK_EMBEDDED_VERSION="v2.0"$' "$_h/.local/bin/cstk" \
    || { _fail "bin embedded nao recovered" ""; return 1; }
}

scenario_self_update_kill_after_bin_match_state() {
  _h="$TMPDIR_TEST/h"
  _make_release_pair || { _error "fixture" ""; return 2; }
  _install_v1 "$_h" || { _fail "install" ""; return 1; }
  _run_su_with_abort "$_h" v2.0 after-bin
  if [ "$_CAPTURED_EXIT" != 99 ]; then
    _fail "abort exit" "$_CAPTURED_EXIT"
    return 1
  fi
  # Estado: 100% nova (commit point ja passou)
  [ "$(_installed_version "$_h")" = "v2.0" ] \
    || { _fail "post-commit version" "deveria ser v2"; return 1; }
  grep -q '^CSTK_EMBEDDED_VERSION="v2.0"$' "$_h/.local/bin/cstk" \
    || { _fail "bin embedded nao swapped" ""; return 1; }
}

# ==== --dry-run nao escreve ====

scenario_self_update_dry_run() {
  _h="$TMPDIR_TEST/h"
  _make_release_pair || { _error "fixture" ""; return 2; }
  _install_v1 "$_h" || { _fail "install" ""; return 1; }
  _bin_before=$(_mtime "$_h/.local/bin/cstk")
  sleep 1.1
  _run_su "$_h" v2.0 --dry-run
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "dry-run exit" "$_CAPTURED_STDERR"; return 1; }
  assert_stderr_contains "[dry-run]" || return 1
  if [ "$_bin_before" != "$(_mtime "$_h/.local/bin/cstk")" ]; then
    _fail "dry-run alterou bin" ""
    return 1
  fi
  [ "$(_installed_version "$_h")" = "v1.0" ] \
    || { _fail "dry-run mudou versao" ""; return 1; }
}

# ==== Help ====

scenario_self_update_help() {
  _h="$TMPDIR_TEST/h"
  _make_release_pair || { _error "fixture" ""; return 2; }
  _install_v1 "$_h" || { _fail "install" ""; return 1; }
  _run_su "$_h" v2.0 --help
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "help exit" "$_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "self-update" || return 1
}

# ==== US3: allowlist de hosts confiaveis (enforced-guards FASE 4) ====
# Ref: spec.md FR-012/FR-013/FR-014; contracts/trusted-hosts.md;
#      quickstart.md Scenarios 8/9/10.

# Scenario 8: host https valido mas fora da allowlist -> rejeitado ANTES de
# qualquer download (mesmo padrao de scenario_self_update_from_http_plano_aborta).
scenario_self_update_host_nao_confiavel_rejeitado() {
  _h="$TMPDIR_TEST/h-evil"
  _make_release_pair || { _error "fixture" ""; return 2; }
  _install_v1 "$_h" || { _fail "install" ""; return 1; }
  capture env HOME="$_h" \
    CSTK_BIN="$_h/.local/bin/cstk" \
    CSTK_LIB="$_h/.local/share/cstk/lib" \
    PATH="$PATH" \
    "$_h/.local/bin/cstk" self-update --from "https://evil.example.com/cstk-9.9.9.tar.gz"
  if [ "$_CAPTURED_EXIT" = 0 ]; then
    _fail "host nao confiavel exit" "esperado nao-zero, obtido 0"
    return 1
  fi
  assert_stderr_contains "evil.example.com" || return 1
}

# Scenario 9: host confiavel (github.com real) continua funcionando sem
# passo manual novo. Testado direto sobre _su_resolve_urls (funcao pura,
# sem I/O de rede) para nao depender de acesso real a internet no harness —
# o download em si ja e coberto pelos scenarios file:// existentes (happy
# path v1->v2); o que esta feature MUDA e exclusivamente a checagem de host
# dentro de _su_resolve_urls.
scenario_self_update_host_confiavel_github_resolve_urls_ok() {
  capture sh -c '. "$CSTK_LIB/self-update.sh"
    _su_from="https://github.com/JotJunior/cstk/releases/download/v1.0.0/cstk-1.0.0.tar.gz"
    _su_resolve_urls
    _rc=$?
    printf "tarball_url=%s\n" "$_su_tarball_url"
    printf "sha256_url=%s\n" "$_su_sha256_url"
    exit "$_rc"'
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "host confiavel resolve_urls exit" "esperado 0, obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"
    return 1
  fi
  case "$_CAPTURED_STDOUT" in
    *'tarball_url=https://github.com/JotJunior/cstk/releases/download/v1.0.0/cstk-1.0.0.tar.gz'*) ;;
    *) _fail "host confiavel tarball_url" "stdout inesperado: $_CAPTURED_STDOUT"; return 1 ;;
  esac
}

# Scenario 10 (regressao FR-014): file:// segue isento de allowlist de host.
# Traco explicito alem da cobertura incidental ja fornecida pelo resto da
# suite (happy path e baseado em file:// via _install_v1/_run_su).
scenario_self_update_host_file_scheme_regressao() {
  _h="$TMPDIR_TEST/h-file10"
  _make_release_pair || { _error "fixture" ""; return 2; }
  _install_v1 "$_h" || { _fail "install" ""; return 1; }
  _run_su "$_h" v2.0
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "file scheme regressao exit" "esperado 0, obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"
    return 1
  fi
  [ "$(_installed_version "$_h")" = "v2.0" ] || { _fail "file scheme regressao versao" ""; return 1; }
}

run_all_scenarios
