#!/bin/sh
# test_bootstrap.sh — cobre cli/install.sh (one-liner bootstrap).
#
# Cobre Scenario 1 (parte inicial — instalacao do binario), checksum mismatch,
# tarball malformado (sem cli/), CSTK_RELEASE_URL como override de fixture
# offline, deteccao de PATH, idempotencia (re-run substitui binario).

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

BOOTSTRAP="$REPO_ROOT/cli/install.sh"

# _make_bootstrap_fixture: monta release mock contendo cli/cstk + cli/lib/.
# Copia da arvore real do repo (e o cenario realista — o tarball que o
# release pipeline da FASE 9 vai gerar contem exatamente isso).
_make_bootstrap_fixture() {
  _mbf_dir=$1
  _mbf_tag=${2:-v0.1.0-test}
  _mbf_root="$_mbf_dir/cstk-$_mbf_tag"
  mkdir -p "$_mbf_root/cli/lib"
  cp -- "$REPO_ROOT/cli/cstk" "$_mbf_root/cli/cstk" || return 1
  cp -- "$REPO_ROOT/cli/lib/"*.sh "$_mbf_root/cli/lib/" || return 1
  printf '%s\n' "$_mbf_tag" > "$_mbf_root/VERSION"
  (cd "$_mbf_dir" && tar -czf "cstk-$_mbf_tag.tar.gz" "cstk-$_mbf_tag") || return 1
  if command -v sha256sum >/dev/null 2>&1; then
    (cd "$_mbf_dir" && sha256sum "cstk-$_mbf_tag.tar.gz" > "cstk-$_mbf_tag.tar.gz.sha256") || return 1
  else
    (cd "$_mbf_dir" && shasum -a 256 "cstk-$_mbf_tag.tar.gz" > "cstk-$_mbf_tag.tar.gz.sha256") || return 1
  fi
  return 0
}

_run_bootstrap() {
  _rb_home=$1; shift
  _rb_url=$1; shift
  capture env \
    HOME="$_rb_home" \
    INSTALL_BIN="$_rb_home/.local/bin" \
    INSTALL_LIB="$_rb_home/.local/share/cstk" \
    CSTK_RELEASE_URL="$_rb_url" \
    PATH="$PATH" \
    sh "$BOOTSTRAP"
}

# ==== Happy path: instalacao limpa ====

scenario_bootstrap_fresh_install() {
  _h="$TMPDIR_TEST/home"
  _r="$TMPDIR_TEST/release"
  _make_bootstrap_fixture "$_r" v0.1.0-test \
    || { _error "fixture" "tarball build falhou"; return 2; }

  _url="file://$_r/cstk-v0.1.0-test.tar.gz"
  _run_bootstrap "$_h" "$_url"

  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "bootstrap exit" "esperado 0, obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"
    return 1
  fi
  [ -x "$_h/.local/bin/cstk" ] || { _fail "binario ausente" ""; return 1; }
  [ -d "$_h/.local/share/cstk/lib" ] || { _fail "lib dir ausente" ""; return 1; }
  [ -f "$_h/.local/share/cstk/lib/manifest.sh" ] || { _fail "lib/manifest.sh ausente" ""; return 1; }
  [ -f "$_h/.local/share/cstk/VERSION" ] || { _fail "VERSION ausente" ""; return 1; }
  _v=$(cat "$_h/.local/share/cstk/VERSION")
  if [ "$_v" != "v0.1.0-test" ]; then
    _fail "VERSION conteudo" "esperado v0.1.0-test, obtido '$_v'"
    return 1
  fi
}

# ==== Binario instalado realmente roda ====

scenario_bootstrap_binario_executavel() {
  _h="$TMPDIR_TEST/home"
  _r="$TMPDIR_TEST/release"
  _make_bootstrap_fixture "$_r" v0.2.0-test \
    || { _error "fixture" ""; return 2; }
  _run_bootstrap "$_h" "file://$_r/cstk-v0.2.0-test.tar.gz"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "bootstrap setup" "$_CAPTURED_STDERR"; return 1; }

  capture "$_h/.local/bin/cstk" --version
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "cstk --version exit" "$_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"
    return 1
  fi
  assert_stdout_contains "v0.2.0-test" || return 1
}

# ==== Re-run substitui (idempotente como upgrade) ====

scenario_bootstrap_re_run_atualiza() {
  _h="$TMPDIR_TEST/home"
  _r="$TMPDIR_TEST/release"
  _make_bootstrap_fixture "$_r" v0.1.0-test || { _error "fixture v1" ""; return 2; }
  _run_bootstrap "$_h" "file://$_r/cstk-v0.1.0-test.tar.gz"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "primeira bootstrap" ""; return 1; }
  _v1=$(cat "$_h/.local/share/cstk/VERSION")
  [ "$_v1" = "v0.1.0-test" ] || { _fail "v1 setup" "$_v1"; return 1; }

  # Segunda release com tag diferente
  _r2="$TMPDIR_TEST/release2"
  _make_bootstrap_fixture "$_r2" v0.5.0-test || { _error "fixture v2" ""; return 2; }
  _run_bootstrap "$_h" "file://$_r2/cstk-v0.5.0-test.tar.gz"
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "re-run exit" "$_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"
    return 1
  fi
  _v2=$(cat "$_h/.local/share/cstk/VERSION")
  if [ "$_v2" != "v0.5.0-test" ]; then
    _fail "VERSION nao foi atualizada" "obtido '$_v2'"
    return 1
  fi
}

# ==== Checksum mismatch (FR-010a): zero writes ====

scenario_bootstrap_checksum_mismatch_aborta() {
  _h="$TMPDIR_TEST/home"
  _r="$TMPDIR_TEST/release"
  _make_bootstrap_fixture "$_r" v0.1.0-test || { _error "fixture" ""; return 2; }
  # Corrompe o sha256 file
  printf 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef  cstk-v0.1.0-test.tar.gz\n' \
    > "$_r/cstk-v0.1.0-test.tar.gz.sha256"

  _run_bootstrap "$_h" "file://$_r/cstk-v0.1.0-test.tar.gz"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "checksum mismatch exit" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "MISMATCH" || return 1
  # Nada criado em $_h
  [ -d "$_h/.local" ] && { _fail "checksum mismatch criou $_h/.local" ""; return 1; }
  return 0
}

# ==== Tarball sem cli/ aborta ====

scenario_bootstrap_tarball_sem_cli_aborta() {
  _h="$TMPDIR_TEST/home"
  _r="$TMPDIR_TEST/release"
  _bad_root="$_r/bogus-v0.1.0"
  mkdir -p "$_bad_root/random/dir"
  printf 'no cstk here\n' > "$_bad_root/random/file.txt"
  (cd "$_r" && tar -czf cstk-v0.1.0-test.tar.gz bogus-v0.1.0)
  if command -v sha256sum >/dev/null 2>&1; then
    (cd "$_r" && sha256sum cstk-v0.1.0-test.tar.gz > cstk-v0.1.0-test.tar.gz.sha256)
  else
    (cd "$_r" && shasum -a 256 cstk-v0.1.0-test.tar.gz > cstk-v0.1.0-test.tar.gz.sha256)
  fi

  _run_bootstrap "$_h" "file://$_r/cstk-v0.1.0-test.tar.gz"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "tarball ruim exit" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "tarball nao contem cli/cstk" || return 1
}

# ==== PATH check: avisa quando INSTALL_BIN nao esta no PATH ====

scenario_bootstrap_path_nao_setado_avisa() {
  _h="$TMPDIR_TEST/home"
  _r="$TMPDIR_TEST/release"
  _make_bootstrap_fixture "$_r" v0.1.0-test || { _error "fixture" ""; return 2; }
  # PATH explicitamente sem $_h/.local/bin
  capture env -i \
    HOME="$_h" \
    INSTALL_BIN="$_h/.local/bin" \
    INSTALL_LIB="$_h/.local/share/cstk" \
    CSTK_RELEASE_URL="file://$_r/cstk-v0.1.0-test.tar.gz" \
    PATH="/usr/bin:/bin" \
    sh "$BOOTSTRAP"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "bootstrap exit" "$_CAPTURED_STDERR"; return 1; }
  assert_stderr_contains "NAO esta no PATH" || return 1
  assert_stderr_contains "export PATH" || return 1
}

scenario_bootstrap_path_ja_setado_silencia_aviso() {
  _h="$TMPDIR_TEST/home"
  _r="$TMPDIR_TEST/release"
  _make_bootstrap_fixture "$_r" v0.1.0-test || { _error "fixture" ""; return 2; }
  capture env -i \
    HOME="$_h" \
    INSTALL_BIN="$_h/.local/bin" \
    INSTALL_LIB="$_h/.local/share/cstk" \
    CSTK_RELEASE_URL="file://$_r/cstk-v0.1.0-test.tar.gz" \
    PATH="$_h/.local/bin:/usr/bin:/bin" \
    sh "$BOOTSTRAP"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "bootstrap exit" "$_CAPTURED_STDERR"; return 1; }
  case "$_CAPTURED_STDERR" in
    *"NAO esta no PATH"*)
      _fail "aviso indevido" "PATH contem INSTALL_BIN mas warn apareceu"
      return 1
      ;;
  esac
  assert_stderr_contains "ja esta no PATH" || return 1
}

# ==== Tag inferida do filename do CSTK_RELEASE_URL ====

scenario_bootstrap_tag_inferida_do_url() {
  _h="$TMPDIR_TEST/home"
  _r="$TMPDIR_TEST/release"
  _make_bootstrap_fixture "$_r" v3.5.0 || { _error "fixture" ""; return 2; }
  _run_bootstrap "$_h" "file://$_r/cstk-v3.5.0.tar.gz"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "bootstrap exit" "$_CAPTURED_STDERR"; return 1; }
  _v=$(cat "$_h/.local/share/cstk/VERSION")
  if [ "$_v" != "v3.5.0" ]; then
    _fail "tag inferida errada" "esperado v3.5.0, VERSION='$_v'"
    return 1
  fi
}

# ==== Telemetria opt-in no install (feature install-telemetry-optin) ====

# Sem TTY e sem CSTK_INSTALL_TELEMETRY: fail-safe = nao escreve rc nenhum e
# aponta o caminho manual (cstk help telemetry).
scenario_bootstrap_telemetry_non_tty_skips() {
  _h="$TMPDIR_TEST/home-tel-nontty"
  _r="$TMPDIR_TEST/release-tel-nontty"
  _make_bootstrap_fixture "$_r" v0.1.0-test || { _error "fixture" "tarball build falhou"; return 2; }
  capture env HOME="$_h" INSTALL_BIN="$_h/.local/bin" INSTALL_LIB="$_h/.local/share/cstk" \
    CSTK_RELEASE_URL="file://$_r/cstk-v0.1.0-test.tar.gz" PATH="$PATH" SHELL=/bin/zsh \
    sh "$BOOTSTRAP"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  [ ! -f "$_h/.zshrc" ] || { _fail "rc" "sem opt-in nao pode escrever .zshrc"; return 1; }
  case "$_CAPTURED_STDERR" in
    *"cstk help telemetry"*) : ;;
    *) _fail "pointer" "stderr nao aponta cstk help telemetry: $_CAPTURED_STDERR"; return 1 ;;
  esac
}

# CSTK_INSTALL_TELEMETRY=yes + SHELL=zsh: snippet vai para ~/.zshrc entre
# marcadores; wrapper contem as 4 variaveis no prefixo do processo.
scenario_bootstrap_telemetry_yes_zsh_writes_zshrc() {
  _h="$TMPDIR_TEST/home-tel-zsh"
  _r="$TMPDIR_TEST/release-tel-zsh"
  _make_bootstrap_fixture "$_r" v0.1.0-test || { _error "fixture" "tarball build falhou"; return 2; }
  capture env HOME="$_h" INSTALL_BIN="$_h/.local/bin" INSTALL_LIB="$_h/.local/share/cstk" \
    CSTK_RELEASE_URL="file://$_r/cstk-v0.1.0-test.tar.gz" PATH="$PATH" SHELL=/bin/zsh \
    CSTK_INSTALL_TELEMETRY=yes sh "$BOOTSTRAP"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"; return 1; }
  grep -Fq '# >>> cstk telemetry >>>' "$_h/.zshrc" || { _fail "marker" "marcador begin ausente de .zshrc"; return 1; }
  grep -Fq '# <<< cstk telemetry <<<' "$_h/.zshrc" || { _fail "marker" "marcador end ausente"; return 1; }
  for _var in CLAUDE_CODE_ENABLE_TELEMETRY=1 OTEL_METRICS_EXPORTER=prometheus \
              OTEL_EXPORTER_PROMETHEUS_PORT CSTK_OTEL_ENDPOINT; do
    grep -Fq "$_var" "$_h/.zshrc" || { _fail "var" "wrapper sem $_var"; return 1; }
  done
}

# CSTK_INSTALL_TELEMETRY=yes + SHELL=bash: rc alvo e ~/.bashrc (o host pode
# ser bash — deteccao por $SHELL, nao hardcoded zshrc).
scenario_bootstrap_telemetry_yes_bash_writes_bashrc() {
  _h="$TMPDIR_TEST/home-tel-bash"
  _r="$TMPDIR_TEST/release-tel-bash"
  _make_bootstrap_fixture "$_r" v0.1.0-test || { _error "fixture" "tarball build falhou"; return 2; }
  capture env HOME="$_h" INSTALL_BIN="$_h/.local/bin" INSTALL_LIB="$_h/.local/share/cstk" \
    CSTK_RELEASE_URL="file://$_r/cstk-v0.1.0-test.tar.gz" PATH="$PATH" SHELL=/bin/bash \
    CSTK_INSTALL_TELEMETRY=yes sh "$BOOTSTRAP"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  grep -Fq '# >>> cstk telemetry >>>' "$_h/.bashrc" || { _fail "rc" "snippet nao foi para .bashrc com SHELL=bash"; return 1; }
  [ ! -f "$_h/.zshrc" ] || { _fail "rc" "com SHELL=bash nao pode tocar .zshrc"; return 1; }
}

# Re-run com marcador ja presente: idempotente (1 unico bloco).
scenario_bootstrap_telemetry_idempotent_rerun() {
  _h="$TMPDIR_TEST/home-tel-idem"
  _r="$TMPDIR_TEST/release-tel-idem"
  _make_bootstrap_fixture "$_r" v0.1.0-test || { _error "fixture" "tarball build falhou"; return 2; }
  for _i in 1 2; do
    capture env HOME="$_h" INSTALL_BIN="$_h/.local/bin" INSTALL_LIB="$_h/.local/share/cstk" \
      CSTK_RELEASE_URL="file://$_r/cstk-v0.1.0-test.tar.gz" PATH="$PATH" SHELL=/bin/zsh \
      CSTK_INSTALL_TELEMETRY=yes sh "$BOOTSTRAP"
    [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "run $_i esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  done
  _n=$(grep -Fc '# >>> cstk telemetry >>>' "$_h/.zshrc")
  [ "$_n" = 1 ] || { _fail "idem" "esperado 1 bloco apos re-run, obtido $_n"; return 1; }
}

# rc ja tem claude() proprio (sem marcadores): NUNCA sobrescrever — avisa e
# aponta o caminho manual.
scenario_bootstrap_telemetry_existing_claude_fn_preserved() {
  _h="$TMPDIR_TEST/home-tel-existing"
  _r="$TMPDIR_TEST/release-tel-existing"
  _make_bootstrap_fixture "$_r" v0.1.0-test || { _error "fixture" "tarball build falhou"; return 2; }
  mkdir -p "$_h"
  printf 'claude() {\n  command claude --meu-wrapper "$@"\n}\n' > "$_h/.zshrc"
  _before=$(cat "$_h/.zshrc")
  capture env HOME="$_h" INSTALL_BIN="$_h/.local/bin" INSTALL_LIB="$_h/.local/share/cstk" \
    CSTK_RELEASE_URL="file://$_r/cstk-v0.1.0-test.tar.gz" PATH="$PATH" SHELL=/bin/zsh \
    CSTK_INSTALL_TELEMETRY=yes sh "$BOOTSTRAP"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  [ "$(cat "$_h/.zshrc")" = "$_before" ] || { _fail "preserve" "claude() pre-existente foi alterado"; return 1; }
  case "$_CAPTURED_STDERR" in
    *"cstk help telemetry"*) : ;;
    *) _fail "pointer" "sem instrucao manual no aviso: $_CAPTURED_STDERR"; return 1 ;;
  esac
}

run_all_scenarios
