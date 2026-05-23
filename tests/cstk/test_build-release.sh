#!/bin/sh
# test_build-release.sh — cobre scripts/build-release.sh (FASE 9.1).
#
# Cenarios chave:
#   - Determinismo: rodar 2x consecutivamente produz tarballs com SHA-256 identico
#   - Estrutura: tarball contem cli/cstk, cli/lib/*.sh, catalog/{VERSION,
#     profiles.txt,skills,language}, CHANGELOG.md
#   - Checksum file e gerado com sha256sum/shasum format
#   - profiles.txt parseavel pela lib (resolve_profile sdd retorna 12 skills)
#   - Layout consumivel por bootstrap/self-update (cli/cstk + cli/lib/ em paths
#     que find ... -path '*/cli/cstk' encontra)
#   - Errors de uso: sem version exit 2, version invalida exit 2

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

BUILD_SCRIPT="$REPO_ROOT/scripts/build-release.sh"

_sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

# ==== Determinismo (subtarefa 9.1.6) ====

scenario_build_release_e_deterministico() {
  _o1="$TMPDIR_TEST/run1"
  _o2="$TMPDIR_TEST/run2"
  mkdir -p "$_o1" "$_o2"

  capture sh "$BUILD_SCRIPT" v0.0.0-det --out "$_o1"
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "1st run" "exit=$_CAPTURED_EXIT stderr=$_CAPTURED_STDERR"
    return 1
  fi
  capture sh "$BUILD_SCRIPT" v0.0.0-det --out "$_o2"
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "2nd run" "exit=$_CAPTURED_EXIT stderr=$_CAPTURED_STDERR"
    return 1
  fi

  _h1=$(_sha256_of "$_o1/cstk-0.0.0-det.tar.gz")
  _h2=$(_sha256_of "$_o2/cstk-0.0.0-det.tar.gz")
  if [ "$_h1" != "$_h2" ]; then
    _fail "determinismo SHA-256" "h1=$_h1 h2=$_h2"
    return 1
  fi

  # Bonus: bytes identicos via diff.
  if ! diff -q "$_o1/cstk-0.0.0-det.tar.gz" "$_o2/cstk-0.0.0-det.tar.gz" >/dev/null; then
    _fail "determinismo bytes" "diff -q reportou diferenca apesar de hash igual"
    return 1
  fi
}

# ==== Estrutura do tarball ====

scenario_build_release_estrutura_layout() {
  _o="$TMPDIR_TEST/out"
  mkdir -p "$_o"
  capture sh "$BUILD_SCRIPT" 0.1.0 --out "$_o"
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "build" "$_CAPTURED_STDERR"
    return 1
  fi

  _tar="$_o/cstk-0.1.0.tar.gz"
  [ -f "$_tar" ] || { _fail "tarball ausente" ""; return 1; }

  _list=$(tar -tzf "$_tar")
  for _expected in \
    'cstk-0.1.0/cli/cstk' \
    'cstk-0.1.0/cli/lib/install.sh' \
    'cstk-0.1.0/cli/lib/self-update.sh' \
    'cstk-0.1.0/cli/lib/ui.sh' \
    'cstk-0.1.0/catalog/VERSION' \
    'cstk-0.1.0/catalog/profiles.txt' \
    'cstk-0.1.0/CHANGELOG.md'
  do
    if ! printf '%s\n' "$_list" | grep -qx -- "$_expected"; then
      _fail "entry ausente" "$_expected"
      return 1
    fi
  done

  # catalog/skills/ deve conter pelo menos uma SKILL.md
  if ! printf '%s\n' "$_list" | grep -q '^cstk-0\.1\.0/catalog/skills/[^/]*/SKILL\.md$'; then
    _fail "catalog/skills sem SKILL.md" ""
    return 1
  fi

  # catalog/language/{go,dotnet}/skills/ devem existir como subdirs
  if ! printf '%s\n' "$_list" | grep -q '^cstk-0\.1\.0/catalog/language/go/skills/'; then
    _fail "language/go/skills ausente" ""
    return 1
  fi
  if ! printf '%s\n' "$_list" | grep -q '^cstk-0\.1\.0/catalog/language/dotnet/skills/'; then
    _fail "language/dotnet/skills ausente" ""
    return 1
  fi
}

# ==== Checksum file ====

scenario_build_release_gera_sha256() {
  _o="$TMPDIR_TEST/out"
  mkdir -p "$_o"
  capture sh "$BUILD_SCRIPT" v0.2.0 --out "$_o"
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "build" "$_CAPTURED_STDERR"
    return 1
  fi
  _sha="$_o/cstk-0.2.0.tar.gz.sha256"
  [ -f "$_sha" ] || { _fail "sha256 file ausente" ""; return 1; }
  # Formato: "<hash> <space>(?)<filename>"
  _content=$(cat "$_sha")
  case "$_content" in
    *cstk-0.2.0.tar.gz*) ;;
    *) _fail "sha256 conteudo" "$_content"; return 1 ;;
  esac
  # Hash deve bater com o tarball
  _expected=$(_sha256_of "$_o/cstk-0.2.0.tar.gz")
  _actual=$(awk '{print $1}' "$_sha")
  if [ "$_expected" != "$_actual" ]; then
    _fail "sha256 mismatch" "expected=$_expected actual=$_actual"
    return 1
  fi
}

# ==== profiles.txt parseavel + sdd resolve corretamente ====

scenario_build_release_profiles_parseavel() {
  _o="$TMPDIR_TEST/out"
  mkdir -p "$_o"
  capture sh "$BUILD_SCRIPT" 0.3.0 --out "$_o"
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "build" "$_CAPTURED_STDERR"
    return 1
  fi
  # Extrai profiles.txt e roda resolve_profile
  _profiles="$TMPDIR_TEST/profiles.txt"
  tar -xzf "$_o/cstk-0.3.0.tar.gz" -O cstk-0.3.0/catalog/profiles.txt > "$_profiles"

  capture env CSTK_LIB="$REPO_ROOT/cli/lib" sh -c '
    . "$CSTK_LIB/profiles.sh"
    resolve_profile "'"$_profiles"'" sdd
  '
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "resolve sdd" "$_CAPTURED_STDERR"
    return 1
  fi
  # SDD profile tem 12 skills (10 da pipeline + agente-00c-runtime infra
  # do /agente-00c + model-selector, per scripts/profiles.txt.in).
  # model-selector entrou no profile em 7eecdb7 (corrige conformidade); este
  # count foi atualizado de 11 -> 12 junto.
  _count=$(printf '%s\n' "$_CAPTURED_STDOUT" | awk 'NF>0' | wc -l | awk '{print $1}')
  if [ "$_count" != 12 ]; then
    _fail "sdd count" "esperado 12, obtido $_count: $_CAPTURED_STDOUT"
    return 1
  fi
  # Regressao: agente-00c-runtime DEVE estar em sdd (causa principal do
  # bug "runtime nao instalada com cstk install default").
  if ! printf '%s\n' "$_CAPTURED_STDOUT" | grep -qx "agente-00c-runtime"; then
    _fail "sdd sem agente-00c-runtime" "$_CAPTURED_STDOUT"
    return 1
  fi
  # Regressao: model-selector DEVE estar em sdd (conformidade, 7eecdb7).
  if ! printf '%s\n' "$_CAPTURED_STDOUT" | grep -qx "model-selector"; then
    _fail "sdd sem model-selector" "$_CAPTURED_STDOUT"
    return 1
  fi

  # language-go nao deve ser vazio
  capture env CSTK_LIB="$REPO_ROOT/cli/lib" sh -c '
    . "$CSTK_LIB/profiles.sh"
    resolve_profile "'"$_profiles"'" language-go
  '
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "resolve language-go" "$_CAPTURED_STDERR"
    return 1
  fi
  if [ -z "$_CAPTURED_STDOUT" ]; then
    _fail "language-go vazio" ""
    return 1
  fi
}

# ==== Layout consumivel por bootstrap (cli/cstk + cli/lib/) ====

scenario_build_release_layout_para_bootstrap() {
  # Bootstrap usa: find $extracted -type f -path '*/cli/cstk'
  # Tem que retornar exatamente uma entry. Self-update tambem usa esse path.
  _o="$TMPDIR_TEST/out"
  _x="$TMPDIR_TEST/extracted"
  mkdir -p "$_o" "$_x"
  capture sh "$BUILD_SCRIPT" v0.4.0 --out "$_o"
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "build" "$_CAPTURED_STDERR"
    return 1
  fi
  tar -xzf "$_o/cstk-0.4.0.tar.gz" -C "$_x"

  _hits=$(find "$_x" -type f -path '*/cli/cstk' | wc -l | awk '{print $1}')
  if [ "$_hits" != 1 ]; then
    _fail "find cli/cstk" "esperado 1 hit, obtido $_hits"
    return 1
  fi
  _hits=$(find "$_x" -type d -path '*/cli/lib' | wc -l | awk '{print $1}')
  if [ "$_hits" != 1 ]; then
    _fail "find cli/lib" "esperado 1 hit, obtido $_hits"
    return 1
  fi
}

# ==== catalog/VERSION contem a versao bare ====

scenario_build_release_version_bare() {
  _o="$TMPDIR_TEST/out"
  mkdir -p "$_o"
  capture sh "$BUILD_SCRIPT" v1.2.3 --out "$_o"
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "build" "$_CAPTURED_STDERR"
    return 1
  fi
  _v=$(tar -xzf "$_o/cstk-1.2.3.tar.gz" -O cstk-1.2.3/catalog/VERSION | tr -d '[:space:]')
  if [ "$_v" != "1.2.3" ]; then
    _fail "VERSION conteudo" "esperado '1.2.3', obtido '$_v'"
    return 1
  fi
}

# ==== Erros de uso ====

scenario_build_release_sem_version_exit_2() {
  capture sh "$BUILD_SCRIPT"
  if [ "$_CAPTURED_EXIT" != 2 ]; then
    _fail "sem version" "esperado 2, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "Uso:" || return 1
}

scenario_build_release_version_invalida_exit_2() {
  capture sh "$BUILD_SCRIPT" 'inv@lid$'
  if [ "$_CAPTURED_EXIT" != 2 ]; then
    _fail "version invalida" "esperado 2, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "VERSION invalida" || return 1
}

scenario_build_release_flag_desconhecida_exit_2() {
  capture sh "$BUILD_SCRIPT" --frobnicate v0.1.0
  if [ "$_CAPTURED_EXIT" != 2 ]; then
    _fail "flag invalida" "esperado 2, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "flag desconhecida" || return 1
}

# ==== Sanidade: artefatos macOS sao filtrados ====

scenario_build_release_filtra_ds_store() {
  # Cria .DS_Store em uma skill source (tempdir override de REPO_ROOT)
  _fake_repo="$TMPDIR_TEST/fake-repo"
  mkdir -p "$_fake_repo/cli/lib" \
           "$_fake_repo/global/skills/foo" \
           "$_fake_repo/language-related/go/skills/bar"
  cp "$REPO_ROOT/cli/cstk" "$_fake_repo/cli/cstk"
  cp "$REPO_ROOT/cli/lib/"*.sh "$_fake_repo/cli/lib/"
  printf '# foo\n' > "$_fake_repo/global/skills/foo/SKILL.md"
  printf '# bar\n' > "$_fake_repo/language-related/go/skills/bar/SKILL.md"
  printf 'fake DS_Store\n' > "$_fake_repo/global/skills/foo/.DS_Store"
  printf 'fake AppleDouble\n' > "$_fake_repo/global/skills/foo/._SKILL.md"

  _o="$TMPDIR_TEST/out"
  mkdir -p "$_o"
  capture env REPO_ROOT="$_fake_repo" sh "$BUILD_SCRIPT" v0.5.0 --out "$_o"
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "build" "$_CAPTURED_STDERR"
    return 1
  fi
  _list=$(tar -tzf "$_o/cstk-0.5.0.tar.gz")
  if printf '%s\n' "$_list" | grep -qE '\.DS_Store|/\._'; then
    _fail "macOS artifacts vazaram" "$(printf '%s\n' "$_list" | grep -E '\.DS_Store|/\._' | head -3)"
    return 1
  fi
}

run_all_scenarios
