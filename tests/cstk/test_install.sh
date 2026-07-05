#!/bin/sh
# test_install.sh — cobre cli/lib/install.sh
#
# Cobre Scenario 1 (fresh install global), preservacao third-party (FR-007),
# dry-run vs real (SC-006/FR-012), cherry-pick + profile union, idempotencia
# (re-install vira "updated"), --interactive nao-implementado retorna 2,
# --from invalido aborta sem escrita, scope=project sem indicadores aborta.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

CSTK_LIB="$REPO_ROOT/cli/lib"
export CSTK_LIB

# _make_fixture_release: monta um "release" mock no path passado, contendo
# tarball + .sha256 com 3 skills (foo, bar, baz) e profile sdd:foo,bar.
_make_fixture_release() {
  _mfr_dir=$1
  _mfr_root="$_mfr_dir/cstk-test-v0.1.0"
  mkdir -p "$_mfr_root/catalog/skills/foo" \
           "$_mfr_root/catalog/skills/bar" \
           "$_mfr_root/catalog/skills/baz"
  printf '0.1.0-test\n' > "$_mfr_root/catalog/VERSION"
  {
    printf '# fixture profiles\n'
    printf 'sdd:foo\n'
    printf 'sdd:bar\n'
  } > "$_mfr_root/catalog/profiles.txt"
  printf '# foo skill\n' > "$_mfr_root/catalog/skills/foo/SKILL.md"
  printf '# bar skill\n' > "$_mfr_root/catalog/skills/bar/SKILL.md"
  printf '# baz skill\n' > "$_mfr_root/catalog/skills/baz/SKILL.md"
  (cd "$_mfr_dir" && tar -czf cstk-test-v0.1.0.tar.gz cstk-test-v0.1.0) || return 1
  if command -v sha256sum >/dev/null 2>&1; then
    (cd "$_mfr_dir" && sha256sum cstk-test-v0.1.0.tar.gz > cstk-test-v0.1.0.tar.gz.sha256) || return 1
  else
    (cd "$_mfr_dir" && shasum -a 256 cstk-test-v0.1.0.tar.gz > cstk-test-v0.1.0.tar.gz.sha256) || return 1
  fi
  return 0
}

# _run_install: executa install_main em subshell isolado com HOME apontando
# para tmpdir, evitando vazar para ~/.claude real do usuario.
_run_install() {
  _ri_home=$1; shift
  mkdir -p "$_ri_home"
  # Argumentos extras viram args do install_main; isolados via "$@".
  capture env HOME="$_ri_home" CSTK_LIB="$CSTK_LIB" sh -c '
    . "$CSTK_LIB/install.sh"
    install_main "$@"
  ' install_test "$@"
}

# ==== Scenario 1: Fresh install em escopo global (happy path P1) ====

scenario_install_fresh_global_default_profile() {
  _h="$TMPDIR_TEST/home"
  _r="$TMPDIR_TEST/release"
  _make_fixture_release "$_r" || { _error "fixture" "tarball build falhou"; return 2; }
  _url="file://$_r/cstk-test-v0.1.0.tar.gz"
  _run_install "$_h" --from "$_url"
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "fresh install exit" "esperado 0, obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"
    return 1
  fi
  [ -f "$_h/.claude/skills/foo/SKILL.md" ] || { _fail "foo nao instalada" ""; return 1; }
  [ -f "$_h/.claude/skills/bar/SKILL.md" ] || { _fail "bar nao instalada" ""; return 1; }
  # baz NAO esta no profile sdd, nao deve estar instalada
  [ -e "$_h/.claude/skills/baz" ] && { _fail "baz instalada por engano" ""; return 1; }
  # Manifest existe e tem 2 entries
  _mf="$_h/.claude/skills/.cstk-manifest"
  [ -f "$_mf" ] || { _fail "manifest ausente" ""; return 1; }
  grep -q '^foo	0.1.0-test	' "$_mf" || { _fail "manifest sem foo" ""; return 1; }
  grep -q '^bar	0.1.0-test	' "$_mf" || { _fail "manifest sem bar" ""; return 1; }
  assert_stderr_contains "installed: 2" || return 1
  assert_stderr_contains "scope: global" || return 1
  return 0
}

# ==== Scenario 1b: explicit profile + cherry-pick uniao ====

scenario_install_profile_e_cherrypick_union() {
  _h="$TMPDIR_TEST/home"
  _r="$TMPDIR_TEST/release"
  _make_fixture_release "$_r" || { _error "fixture" "tarball build falhou"; return 2; }
  _url="file://$_r/cstk-test-v0.1.0.tar.gz"
  # baz nao esta em sdd, mas vai como cherry-pick. Resultado: foo, bar, baz.
  _run_install "$_h" --from "$_url" --profile sdd baz
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "union exit" "$_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"
    return 1
  fi
  for _s in foo bar baz; do
    [ -f "$_h/.claude/skills/$_s/SKILL.md" ] || { _fail "skill $_s ausente" ""; return 1; }
  done
  assert_stderr_contains "installed: 3" || return 1
}

# ==== Preservacao de third-party (FR-007) ====

scenario_install_preserva_skill_terceira() {
  _h="$TMPDIR_TEST/home"
  _r="$TMPDIR_TEST/release"
  _make_fixture_release "$_r" || { _error "fixture" "tarball build falhou"; return 2; }
  # Pre-cria foo manualmente (sem manifest) — simulando skill de terceiro
  mkdir -p "$_h/.claude/skills/foo"
  printf 'CONTEUDO TERCEIRO\n' > "$_h/.claude/skills/foo/SKILL.md"
  _url="file://$_r/cstk-test-v0.1.0.tar.gz"
  _run_install "$_h" --from "$_url"
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "preserve exit" "$_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"
    return 1
  fi
  # foo intocada
  grep -q 'CONTEUDO TERCEIRO' "$_h/.claude/skills/foo/SKILL.md" \
    || { _fail "foo sobrescrita" "third-party perdida"; return 1; }
  # bar instalada normalmente
  [ -f "$_h/.claude/skills/bar/SKILL.md" ] || { _fail "bar nao instalada" ""; return 1; }
  # foo NAO entrou no manifest (continua sendo third-party)
  _mf="$_h/.claude/skills/.cstk-manifest"
  grep -q '^foo	' "$_mf" && { _fail "foo entrou no manifest" "preservada deveria ficar fora"; return 1; }
  grep -q '^bar	' "$_mf" || { _fail "bar nao entrou no manifest" ""; return 1; }
  assert_stderr_contains "preserved (third-party): 1" || return 1
  assert_stderr_contains "installed: 1" || return 1
}

# ==== Dry-run vs real (SC-006, FR-012) ====

scenario_install_dry_run_zero_writes() {
  _h="$TMPDIR_TEST/home-dry"
  _r="$TMPDIR_TEST/release"
  _make_fixture_release "$_r" || { _error "fixture" "tarball build falhou"; return 2; }
  _url="file://$_r/cstk-test-v0.1.0.tar.gz"
  _run_install "$_h" --from "$_url" --dry-run
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "dry-run exit" "$_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"
    return 1
  fi
  # Nada criado em $_h (nem o /.claude/skills/)
  if [ -d "$_h/.claude" ]; then
    _fail "dry-run criou diretorios" "$_h/.claude existe"
    return 1
  fi
  assert_stderr_contains "(dry-run)" || return 1
  assert_stderr_contains "installed: 2" || return 1
}

scenario_install_dry_run_e_real_concordam() {
  # SC-006: dry-run reporta o mesmo plano que execucao real.
  _h_dry="$TMPDIR_TEST/home-dry"
  _h_real="$TMPDIR_TEST/home-real"
  _r="$TMPDIR_TEST/release"
  _make_fixture_release "$_r" || { _error "fixture" "tarball build falhou"; return 2; }
  _url="file://$_r/cstk-test-v0.1.0.tar.gz"

  _run_install "$_h_dry" --from "$_url" --dry-run
  _dry_summary=$(printf '%s\n' "$_CAPTURED_STDERR" | grep -E '^  (installed|updated|preserved|missing|scope|toolkit)' || :)
  _dry_exit=$_CAPTURED_EXIT

  _run_install "$_h_real" --from "$_url"
  _real_summary=$(printf '%s\n' "$_CAPTURED_STDERR" | grep -E '^  (installed|updated|preserved|missing|scope|toolkit)' || :)
  _real_exit=$_CAPTURED_EXIT

  if [ "$_dry_exit" != "$_real_exit" ]; then
    _fail "dry vs real exit" "dry=$_dry_exit real=$_real_exit"
    return 1
  fi
  if [ "$_dry_summary" != "$_real_summary" ]; then
    _fail "dry vs real summary divergem (SC-006)" "dry=<$_dry_summary> real=<$_real_summary>"
    return 1
  fi
}

# ==== Re-install vira update (FASE 4 fara o full edit-detection) ====

scenario_install_reinstall_e_update() {
  _h="$TMPDIR_TEST/home"
  _r="$TMPDIR_TEST/release"
  _make_fixture_release "$_r" || { _error "fixture" "tarball build falhou"; return 2; }
  _url="file://$_r/cstk-test-v0.1.0.tar.gz"
  # Primeira: install fresh
  _run_install "$_h" --from "$_url"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "primeira install" "$_CAPTURED_STDERR"; return 1; }
  # Segunda: ja existem em disco + manifest -> conta como update
  _run_install "$_h" --from "$_url"
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "re-install exit" "$_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"
    return 1
  fi
  assert_stderr_contains "installed: 0" || return 1
  assert_stderr_contains "updated: 2" || return 1
}

# ==== Help, flags invalidas, --interactive (placeholder FASE 8) ====

scenario_install_help_exit_zero() {
  _run_install "$TMPDIR_TEST/h" --help
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "help exit" "$_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "cstk install" || return 1
  # Profiles disponiveis devem aparecer no help (discoverability).
  assert_stderr_contains "PROFILES DISPONIVEIS" || return 1
  assert_stderr_contains "sdd" || return 1
  assert_stderr_contains "complementary" || return 1
  assert_stderr_contains "all" || return 1
}

scenario_install_interactive_sem_tty_aborta() {
  # FASE 8: --interactive exige TTY. Sem TTY (test pipe), exit 2 com msg clara.
  _run_install "$TMPDIR_TEST/h" --interactive
  if [ "$_CAPTURED_EXIT" != 2 ]; then
    _fail "interactive sem TTY exit" "esperado 2, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "requires a TTY" || return 1
}

scenario_install_flag_desconhecida() {
  _run_install "$TMPDIR_TEST/h" --frobnicate
  if [ "$_CAPTURED_EXIT" != 2 ]; then
    _fail "flag invalida exit" "esperado 2, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "flag desconhecida" || return 1
}

scenario_install_sem_from_e_sem_env_consulta_api() {
  # Sem --from + sem $CSTK_RELEASE_URL = consulta API GitHub. Para nao
  # depender de rede em testes, apontamos CSTK_REPO para um repo
  # invalido (404 garantido) — install deve falhar com msg de "falha ao
  # consultar". Garante que CSTK_RELEASE_URL nao vaza do ambiente.
  capture env -i HOME="$TMPDIR_TEST/h" CSTK_LIB="$CSTK_LIB" PATH="$PATH" \
    CSTK_REPO="invalid-owner-cstk-test/nonexistent-repo" sh -c '
    . "$CSTK_LIB/install.sh"
    install_main
  '
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "API fail exit" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "falha ao consultar" || return 1
}

scenario_install_from_nao_url_aborta() {
  _run_install "$TMPDIR_TEST/h" --from v0.1.0
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "tag --from exit" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "precisa ser URL" || return 1
}

# http:// texto plano e rejeitado (revisao 5.15.0): MITM pode trocar
# tarball E .sha256 juntos — o checksum de mesma origem nao protege.
scenario_install_from_http_plano_aborta() {
  _run_install "$TMPDIR_TEST/h-http" --from "http://example.com/cstk-0.1.0.tar.gz"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "http --from exit" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "http:// rejeitado" || return 1
  # Zero escrita: home de destino nao pode ter sido criada/populada
  if [ -d "$TMPDIR_TEST/h-http/.claude/skills" ]; then
    _fail "http --from escreveu" "diretorio de skills criado apesar do abort"
    return 1
  fi
}

# ==== Escopo project ====

scenario_install_project_sem_indicadores_aborta() {
  _r="$TMPDIR_TEST/release"
  _make_fixture_release "$_r" || { _error "fixture" "tarball build falhou"; return 2; }
  # CWD limpo, sem .git, package.json etc.
  _cwd="$TMPDIR_TEST/clean-cwd"
  mkdir -p "$_cwd"
  capture env HOME="$TMPDIR_TEST/h" CSTK_LIB="$CSTK_LIB" sh -c "
    cd '$_cwd'
    . '$CSTK_LIB/install.sh'
    install_main --scope project --from 'file://$_r/cstk-test-v0.1.0.tar.gz'
  "
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "project sem indicador exit" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "nao parece ser um projeto" || return 1
  # Nada foi criado
  [ -d "$_cwd/.claude" ] && { _fail "criou .claude por engano" ""; return 1; }
  return 0
}

scenario_install_project_com_indicador_funciona() {
  _r="$TMPDIR_TEST/release"
  _make_fixture_release "$_r" || { _error "fixture" "tarball build falhou"; return 2; }
  _cwd="$TMPDIR_TEST/proj"
  mkdir -p "$_cwd"
  : > "$_cwd/package.json"  # marca como projeto
  capture env HOME="$TMPDIR_TEST/h" CSTK_LIB="$CSTK_LIB" sh -c "
    cd '$_cwd'
    . '$CSTK_LIB/install.sh'
    install_main --scope project --from 'file://$_r/cstk-test-v0.1.0.tar.gz'
  "
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "project install exit" "$_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"
    return 1
  fi
  [ -f "$_cwd/.claude/skills/foo/SKILL.md" ] || { _fail "foo no project" ""; return 1; }
  [ -f "$_cwd/.claude/skills/.cstk-manifest" ] || { _fail "manifest no project" ""; return 1; }
  assert_stderr_contains "scope: project" || return 1
}

# ==== Lock conflito ====

scenario_install_lock_detido_exit_3() {
  _h="$TMPDIR_TEST/home"
  _r="$TMPDIR_TEST/release"
  _make_fixture_release "$_r" || { _error "fixture" "tarball build falhou"; return 2; }
  # Pre-cria o lock
  mkdir -p "$_h/.claude/skills/.cstk.lock"
  _run_install "$_h" --from "file://$_r/cstk-test-v0.1.0.tar.gz"
  if [ "$_CAPTURED_EXIT" != 3 ]; then
    _fail "lock conflito exit" "esperado 3, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "lock ja detido" || return 1
}

# ==== Checksum mismatch nao escreve nada (FR-010a) ====

scenario_install_checksum_mismatch_zero_writes() {
  _h="$TMPDIR_TEST/home"
  _r="$TMPDIR_TEST/release"
  _make_fixture_release "$_r" || { _error "fixture" "tarball build falhou"; return 2; }
  # Corrompe o sha256 file
  printf 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef  cstk-test-v0.1.0.tar.gz\n' \
    > "$_r/cstk-test-v0.1.0.tar.gz.sha256"
  _run_install "$_h" --from "file://$_r/cstk-test-v0.1.0.tar.gz"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "checksum mismatch exit" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "MISMATCH" || return 1
  # Nada criado em $_h
  [ -d "$_h/.claude" ] && { _fail "checksum mismatch criou diretorios" ""; return 1; }
  return 0
}

# ==== US3: allowlist de hosts confiaveis (enforced-guards FASE 4) ====
# Ref: spec.md FR-012/FR-013/FR-014; contracts/trusted-hosts.md;
#      quickstart.md Scenarios 8/9/10.

# Scenario 8: host https valido mas fora da allowlist -> rejeitado ANTES de
# qualquer download/transferencia (mesmo padrao de zero-writes ja usado por
# scenario_install_from_http_plano_aborta/scenario_install_checksum_mismatch_zero_writes).
scenario_install_host_nao_confiavel_zero_bytes() {
  _run_install "$TMPDIR_TEST/h-evil" --from "https://evil.example.com/cstk-9.9.9.tar.gz"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "host nao confiavel exit" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "evil.example.com" || return 1
  assert_stderr_contains "confiaveis" || return 1
  # Zero escrita: nem staging nem instalacao devem ter tocado o destino.
  if [ -d "$TMPDIR_TEST/h-evil/.claude/skills" ]; then
    _fail "host nao confiavel escreveu" "diretorio de skills criado apesar do abort"
    return 1
  fi
}

# Scenario 9: host confiavel (github.com real) continua funcionando sem
# passo manual novo. Testado direto sobre _install_resolve_urls (funcao
# pura, sem I/O de rede) para nao depender de acesso real a internet no
# harness de teste — o download em si ja e coberto pelas dezenas de
# scenarios file:// existentes; o que esta feature MUDA e exclusivamente a
# checagem de host dentro de _install_resolve_urls.
scenario_install_host_confiavel_github_resolve_urls_ok() {
  capture sh -c '. "$CSTK_LIB/install.sh"
    _install_from="https://github.com/JotJunior/cstk/releases/download/v1.0.0/cstk-1.0.0.tar.gz"
    _install_resolve_urls
    _rc=$?
    printf "tarball_url=%s\n" "$_install_tarball_url"
    printf "sha256_url=%s\n" "$_install_sha256_url"
    exit "$_rc"'
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "host confiavel resolve_urls exit" "esperado 0, obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"
    return 1
  fi
  case "$_CAPTURED_STDOUT" in
    *'tarball_url=https://github.com/JotJunior/cstk/releases/download/v1.0.0/cstk-1.0.0.tar.gz'*) ;;
    *) _fail "host confiavel tarball_url" "stdout inesperado: $_CAPTURED_STDOUT"; return 1 ;;
  esac
  case "$_CAPTURED_STDOUT" in
    *'sha256_url=https://github.com/JotJunior/cstk/releases/download/v1.0.0/cstk-1.0.0.tar.gz.sha256'*) ;;
    *) _fail "host confiavel sha256_url" "stdout inesperado: $_CAPTURED_STDOUT"; return 1 ;;
  esac
}

# Scenario 10 (regressao FR-014): file:// segue isento de allowlist de host
# — mesmo comportamento de sempre. Traco explicito alem da cobertura
# incidental ja fornecida por praticamente todo o resto da suite (que usa
# file:// para os fixtures).
scenario_install_host_file_scheme_regressao() {
  _h="$TMPDIR_TEST/home-file10"
  _r="$TMPDIR_TEST/release-file10"
  _make_fixture_release "$_r" || { _error "fixture" "tarball build falhou"; return 2; }
  _run_install "$_h" --from "file://$_r/cstk-test-v0.1.0.tar.gz"
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "file scheme regressao exit" "esperado 0, obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"
    return 1
  fi
  [ -f "$_h/.claude/skills/foo/SKILL.md" ] || { _fail "file scheme regressao instalacao" ""; return 1; }
}

run_all_scenarios
