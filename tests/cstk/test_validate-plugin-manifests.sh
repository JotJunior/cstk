#!/bin/sh
# test_validate-plugin-manifests.sh — cobre scripts/validate-plugin-manifests.sh
# (claude-plugin-packaging, FASE 5.1.3/5.1.4).
#
# Invariantes cobertos: MP-1 (JSON parseavel), MP-2 (exatamente 2 entradas),
# MP-3 (source resolve para diretorio), MP-4 (source contem plugin.json),
# MP-5 (lockstep de versao: pulado sem --version, aviso sem --strict, erro
# com --strict), MP-6 (nomes unicos). Cada cenario monta um fixture-repo
# sintetico em $TMPDIR_TEST (isolado, nunca toca o repo real).

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/scripts/validate-plugin-manifests.sh"

# _make_valid_repo DIR VERSION1 VERSION2 -> monta um fixture-repo valido
# com 2 plugins (cstk, cstk-language-go), cada um com plugin.json na
# versao informada.
_make_valid_repo() {
  _mvr_dir=$1
  _mvr_v1=$2
  _mvr_v2=$3
  mkdir -p "$_mvr_dir/.claude-plugin" \
           "$_mvr_dir/plugins/cstk/.claude-plugin" \
           "$_mvr_dir/plugins/cstk-language-go/.claude-plugin"
  cat > "$_mvr_dir/.claude-plugin/marketplace.json" <<EOF
{
  "name": "cstk",
  "owner": { "name": "JotJunior" },
  "description": "fixture",
  "plugins": [
    { "name": "cstk", "description": "fixture", "source": "./plugins/cstk", "version": "$_mvr_v1", "category": "development" },
    { "name": "cstk-language-go", "description": "fixture", "source": "./plugins/cstk-language-go", "version": "$_mvr_v2", "category": "development" }
  ]
}
EOF
  printf '{"name":"cstk","description":"fixture","version":"%s","author":{"name":"JotJunior"}}\n' "$_mvr_v1" \
    > "$_mvr_dir/plugins/cstk/.claude-plugin/plugin.json"
  printf '{"name":"cstk-language-go","description":"fixture","version":"%s","author":{"name":"JotJunior"}}\n' "$_mvr_v2" \
    > "$_mvr_dir/plugins/cstk-language-go/.claude-plugin/plugin.json"
}

# ==== MP-1..MP-4/MP-6: fixture valido, sem --version (so avisos) ====

scenario_fixture_valido_sem_version_ok_com_avisos() {
  mktemp_test
  _make_valid_repo "$TMPDIR_TEST/repo" "1.0.0" "1.0.0"

  capture sh "$SCRIPT" --repo-root "$TMPDIR_TEST/repo"
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "exit_0_sem_version" "esperado exit 0 (so avisos MP-5), obteve $_CAPTURED_EXIT"
    return 1
  fi
  case "$_CAPTURED_STDERR" in
    *"MP-5"*"pulado"*) : ;;
    *) _fail "aviso_mp5_pulado" "esperava aviso MP-5 'pulado' em stderr, obteve: $_CAPTURED_STDERR"; return 1 ;;
  esac
}

# ==== MP-2: numero errado de entradas ====

scenario_mp2_numero_errado_de_entradas() {
  mktemp_test
  _make_valid_repo "$TMPDIR_TEST/repo" "1.0.0" "1.0.0"
  # Remove a 2a entrada via edicao direta (jq nao e dependencia garantida
  # no teste; reescreve o JSON a mao).
  cat > "$TMPDIR_TEST/repo/.claude-plugin/marketplace.json" <<'EOF'
{
  "name": "cstk",
  "owner": { "name": "JotJunior" },
  "description": "fixture",
  "plugins": [
    { "name": "cstk", "description": "fixture", "source": "./plugins/cstk", "version": "1.0.0", "category": "development" }
  ]
}
EOF

  capture sh "$SCRIPT" --repo-root "$TMPDIR_TEST/repo"
  if [ "$_CAPTURED_EXIT" = 0 ]; then
    _fail "exit_nao_zero" "esperado exit != 0 (MP-2 violado), obteve 0"
    return 1
  fi
  case "$_CAPTURED_STDERR" in
    *"MP-2"*) : ;;
    *) _fail "mensagem_mp2" "esperava MP-2 em stderr, obteve: $_CAPTURED_STDERR"; return 1 ;;
  esac
}

# ==== MP-3: source aponta para diretorio inexistente ====

scenario_mp3_source_inexistente() {
  mktemp_test
  _make_valid_repo "$TMPDIR_TEST/repo" "1.0.0" "1.0.0"
  rm -rf "$TMPDIR_TEST/repo/plugins/cstk-language-go"

  capture sh "$SCRIPT" --repo-root "$TMPDIR_TEST/repo"
  if [ "$_CAPTURED_EXIT" = 0 ]; then
    _fail "exit_nao_zero" "esperado exit != 0 (MP-3 violado), obteve 0"
    return 1
  fi
  case "$_CAPTURED_STDERR" in
    *"MP-3"*) : ;;
    *) _fail "mensagem_mp3" "esperava MP-3 em stderr, obteve: $_CAPTURED_STDERR"; return 1 ;;
  esac
}

# ==== MP-4: source existe mas sem .claude-plugin/plugin.json ====

scenario_mp4_plugin_json_ausente() {
  mktemp_test
  _make_valid_repo "$TMPDIR_TEST/repo" "1.0.0" "1.0.0"
  rm -f "$TMPDIR_TEST/repo/plugins/cstk/.claude-plugin/plugin.json"

  capture sh "$SCRIPT" --repo-root "$TMPDIR_TEST/repo"
  if [ "$_CAPTURED_EXIT" = 0 ]; then
    _fail "exit_nao_zero" "esperado exit != 0 (MP-4 violado), obteve 0"
    return 1
  fi
  case "$_CAPTURED_STDERR" in
    *"MP-4"*) : ;;
    *) _fail "mensagem_mp4" "esperava MP-4 em stderr, obteve: $_CAPTURED_STDERR"; return 1 ;;
  esac
}

# ==== MP-6: nomes duplicados ====

scenario_mp6_nomes_duplicados() {
  mktemp_test
  _make_valid_repo "$TMPDIR_TEST/repo" "1.0.0" "1.0.0"
  cat > "$TMPDIR_TEST/repo/.claude-plugin/marketplace.json" <<'EOF'
{
  "name": "cstk",
  "owner": { "name": "JotJunior" },
  "description": "fixture",
  "plugins": [
    { "name": "cstk", "description": "fixture", "source": "./plugins/cstk", "version": "1.0.0", "category": "development" },
    { "name": "cstk", "description": "fixture-dup", "source": "./plugins/cstk-language-go", "version": "1.0.0", "category": "development" }
  ]
}
EOF

  capture sh "$SCRIPT" --repo-root "$TMPDIR_TEST/repo"
  if [ "$_CAPTURED_EXIT" = 0 ]; then
    _fail "exit_nao_zero" "esperado exit != 0 (MP-6 violado), obteve 0"
    return 1
  fi
  case "$_CAPTURED_STDERR" in
    *"MP-6"*) : ;;
    *) _fail "mensagem_mp6" "esperava MP-6 em stderr, obteve: $_CAPTURED_STDERR"; return 1 ;;
  esac
}

# ==== MP-1: JSON malformado ====

scenario_mp1_json_malformado() {
  mktemp_test
  _make_valid_repo "$TMPDIR_TEST/repo" "1.0.0" "1.0.0"
  printf '{ nao e json' > "$TMPDIR_TEST/repo/.claude-plugin/marketplace.json"

  capture sh "$SCRIPT" --repo-root "$TMPDIR_TEST/repo"
  if [ "$_CAPTURED_EXIT" = 0 ]; then
    _fail "exit_nao_zero" "esperado exit != 0 (MP-1 violado), obteve 0"
    return 1
  fi
  case "$_CAPTURED_STDERR" in
    *"MP-1"*) : ;;
    *) _fail "mensagem_mp1" "esperava MP-1 em stderr, obteve: $_CAPTURED_STDERR"; return 1 ;;
  esac
}

# ==== MP-5: match exato com --version --strict -> exit 0 sem avisos ====

scenario_mp5_match_exato_strict_ok() {
  mktemp_test
  _make_valid_repo "$TMPDIR_TEST/repo" "2.3.4" "2.3.4"

  capture sh "$SCRIPT" --repo-root "$TMPDIR_TEST/repo" --version 2.3.4 --strict
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "exit_0" "esperado exit 0 (versao bate), obteve $_CAPTURED_EXIT stderr=$_CAPTURED_STDERR"
    return 1
  fi
}

# ==== MP-5: mismatch sem --strict -> aviso, exit 0 ====

scenario_mp5_mismatch_sem_strict_apenas_aviso() {
  mktemp_test
  _make_valid_repo "$TMPDIR_TEST/repo" "1.0.0" "1.0.0"

  capture sh "$SCRIPT" --repo-root "$TMPDIR_TEST/repo" --version 9.9.9
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "exit_0_apesar_de_mismatch" "sem --strict, mismatch MP-5 deve ser aviso (exit 0), obteve $_CAPTURED_EXIT"
    return 1
  fi
  case "$_CAPTURED_STDERR" in
    *"WARN"*"MP-5"*) : ;;
    *) _fail "aviso_mp5" "esperava aviso MP-5 em stderr, obteve: $_CAPTURED_STDERR"; return 1 ;;
  esac
}

# ==== MP-5: mismatch com --strict -> erro, exit != 0 ====

scenario_mp5_mismatch_com_strict_e_erro() {
  mktemp_test
  _make_valid_repo "$TMPDIR_TEST/repo" "1.0.0" "1.0.0"

  capture sh "$SCRIPT" --repo-root "$TMPDIR_TEST/repo" --version 9.9.9 --strict
  if [ "$_CAPTURED_EXIT" = 0 ]; then
    _fail "exit_nao_zero" "esperado exit != 0 (MP-5 + --strict), obteve 0"
    return 1
  fi
  case "$_CAPTURED_STDERR" in
    *"ERROR"*"MP-5"*) : ;;
    *) _fail "erro_mp5" "esperava ERROR MP-5 em stderr, obteve: $_CAPTURED_STDERR"; return 1 ;;
  esac
}

# ==== Uso invalido: marketplace.json ausente ====

scenario_marketplace_ausente() {
  mktemp_test
  mkdir -p "$TMPDIR_TEST/repo"

  capture sh "$SCRIPT" --repo-root "$TMPDIR_TEST/repo"
  if [ "$_CAPTURED_EXIT" = 0 ]; then
    _fail "exit_nao_zero" "esperado exit != 0 (marketplace.json ausente), obteve 0"
    return 1
  fi
}

# ==== Uso invalido: argumento desconhecido -> exit 2 ====

scenario_argumento_desconhecido_exit_2() {
  mktemp_test
  capture sh "$SCRIPT" --nao-existe
  if [ "$_CAPTURED_EXIT" != 2 ]; then
    _fail "exit_2" "esperado exit 2 (uso invalido), obteve $_CAPTURED_EXIT"
    return 1
  fi
}

run_all_scenarios
