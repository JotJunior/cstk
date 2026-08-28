#!/bin/sh
# test_validate-panel-workspace-lockstep.sh — cobre
# scripts/validate-panel-workspace-lockstep.sh (panel-monorepo, FASE 5.1-5.3,
# FR-015/FR-016).
#
# Invariantes cobertos: WL-1 (arquivos existem), WL-2 (JSON parseavel),
# WL-3 (lockstep entre os 4 package.json), WL-4 (lockstep do
# package-lock.json), WL-5 (lockstep com --version: pulado sem --version,
# aviso sem --strict, erro com --strict). Cada cenario monta um
# fixture-repo sintetico em $TMPDIR_TEST (isolado, nunca toca o repo real).

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/scripts/validate-panel-workspace-lockstep.sh"

# _make_valid_panel DIR VERSION -> monta um fixture-repo valido com os 4
# package.json (raiz + 3 workspaces) e package-lock.json (lockfileVersion 3)
# todos na mesma VERSION.
_make_valid_panel() {
  _mvp_dir=$1
  _mvp_v=$2
  mkdir -p "$_mvp_dir/panel/apps/server" \
           "$_mvp_dir/panel/apps/web" \
           "$_mvp_dir/panel/packages/shared-types"

  printf '{"name":"cstk-panel","version":"%s"}\n' "$_mvp_v" \
    > "$_mvp_dir/panel/package.json"
  printf '{"name":"@cstk-panel/server","version":"%s"}\n' "$_mvp_v" \
    > "$_mvp_dir/panel/apps/server/package.json"
  printf '{"name":"@cstk-panel/web","version":"%s"}\n' "$_mvp_v" \
    > "$_mvp_dir/panel/apps/web/package.json"
  printf '{"name":"@cstk-panel/shared-types","version":"%s"}\n' "$_mvp_v" \
    > "$_mvp_dir/panel/packages/shared-types/package.json"

  cat > "$_mvp_dir/panel/package-lock.json" <<EOF
{
  "name": "cstk-panel",
  "version": "$_mvp_v",
  "lockfileVersion": 3,
  "requires": true,
  "packages": {
    "": { "name": "cstk-panel", "version": "$_mvp_v" },
    "apps/server": { "name": "@cstk-panel/server", "version": "$_mvp_v" },
    "apps/web": { "name": "@cstk-panel/web", "version": "$_mvp_v" },
    "packages/shared-types": { "name": "@cstk-panel/shared-types", "version": "$_mvp_v" }
  }
}
EOF
}

# ==== WL-1..WL-4: fixture valido, sem --version (so aviso WL-5) ====

scenario_fixture_valido_sem_version_ok_com_avisos() {
  mktemp_test
  _make_valid_panel "$TMPDIR_TEST" "1.0.0"

  capture sh "$SCRIPT" --repo-root "$TMPDIR_TEST"
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "exit_0_sem_version" "esperado exit 0 (so aviso WL-5), obteve $_CAPTURED_EXIT stderr=$_CAPTURED_STDERR"
    return 1
  fi
  case "$_CAPTURED_STDERR" in
    *"WL-5"*"pulado"*) : ;;
    *) _fail "aviso_wl5_pulado" "esperava aviso WL-5 'pulado' em stderr, obteve: $_CAPTURED_STDERR"; return 1 ;;
  esac
}

# ==== WL-1: package.json de um workspace ausente ====

scenario_wl1_arquivo_ausente() {
  mktemp_test
  _make_valid_panel "$TMPDIR_TEST" "1.0.0"
  rm -f "$TMPDIR_TEST/panel/apps/web/package.json"

  capture sh "$SCRIPT" --repo-root "$TMPDIR_TEST"
  if [ "$_CAPTURED_EXIT" = 0 ]; then
    _fail "exit_nao_zero" "esperado exit != 0 (WL-1 violado), obteve 0"
    return 1
  fi
  case "$_CAPTURED_STDERR" in
    *"WL-1"*) : ;;
    *) _fail "mensagem_wl1" "esperava WL-1 em stderr, obteve: $_CAPTURED_STDERR"; return 1 ;;
  esac
}

# ==== WL-2: JSON malformado ====

scenario_wl2_json_malformado() {
  mktemp_test
  _make_valid_panel "$TMPDIR_TEST" "1.0.0"
  printf '{ nao e json' > "$TMPDIR_TEST/panel/package.json"

  capture sh "$SCRIPT" --repo-root "$TMPDIR_TEST"
  if [ "$_CAPTURED_EXIT" = 0 ]; then
    _fail "exit_nao_zero" "esperado exit != 0 (WL-2 violado), obteve 0"
    return 1
  fi
  case "$_CAPTURED_STDERR" in
    *"WL-2"*) : ;;
    *) _fail "mensagem_wl2" "esperava WL-2 em stderr, obteve: $_CAPTURED_STDERR"; return 1 ;;
  esac
}

# ==== WL-3: apps/web diverge dos demais package.json ====

scenario_wl3_apps_web_diverge() {
  mktemp_test
  _make_valid_panel "$TMPDIR_TEST" "1.0.0"
  printf '{"name":"@cstk-panel/web","version":"1.0.1"}\n' \
    > "$TMPDIR_TEST/panel/apps/web/package.json"

  capture sh "$SCRIPT" --repo-root "$TMPDIR_TEST"
  if [ "$_CAPTURED_EXIT" = 0 ]; then
    _fail "exit_nao_zero" "esperado exit != 0 (WL-3 violado), obteve 0"
    return 1
  fi
  case "$_CAPTURED_STDERR" in
    *"WL-3"*"apps/web"*) : ;;
    *) _fail "mensagem_wl3" "esperava WL-3 apps/web em stderr, obteve: $_CAPTURED_STDERR"; return 1 ;;
  esac
}

# ==== WL-4: package-lock.json diverge (workspace apps/server) ====

scenario_wl4_lockfile_diverge() {
  mktemp_test
  _make_valid_panel "$TMPDIR_TEST" "1.0.0"
  cat > "$TMPDIR_TEST/panel/package-lock.json" <<'EOF'
{
  "name": "cstk-panel",
  "version": "1.0.0",
  "lockfileVersion": 3,
  "requires": true,
  "packages": {
    "": { "name": "cstk-panel", "version": "1.0.0" },
    "apps/server": { "name": "@cstk-panel/server", "version": "0.9.9" },
    "apps/web": { "name": "@cstk-panel/web", "version": "1.0.0" },
    "packages/shared-types": { "name": "@cstk-panel/shared-types", "version": "1.0.0" }
  }
}
EOF

  capture sh "$SCRIPT" --repo-root "$TMPDIR_TEST"
  if [ "$_CAPTURED_EXIT" = 0 ]; then
    _fail "exit_nao_zero" "esperado exit != 0 (WL-4 violado), obteve 0"
    return 1
  fi
  case "$_CAPTURED_STDERR" in
    *"WL-4"*"apps/server"*) : ;;
    *) _fail "mensagem_wl4" "esperava WL-4 apps/server em stderr, obteve: $_CAPTURED_STDERR"; return 1 ;;
  esac
}

# ==== WL-5: match exato com --version --strict -> exit 0 sem erro ====

scenario_wl5_match_exato_strict_ok() {
  mktemp_test
  _make_valid_panel "$TMPDIR_TEST" "2.3.4"

  capture sh "$SCRIPT" --repo-root "$TMPDIR_TEST" --version 2.3.4 --strict
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "exit_0" "esperado exit 0 (versao bate), obteve $_CAPTURED_EXIT stderr=$_CAPTURED_STDERR"
    return 1
  fi
}

# ==== WL-5: mismatch sem --strict -> aviso, exit 0 ====

scenario_wl5_mismatch_sem_strict_apenas_aviso() {
  mktemp_test
  _make_valid_panel "$TMPDIR_TEST" "1.0.0"

  capture sh "$SCRIPT" --repo-root "$TMPDIR_TEST" --version 9.9.9
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "exit_0_apesar_de_mismatch" "sem --strict, mismatch WL-5 deve ser aviso (exit 0), obteve $_CAPTURED_EXIT"
    return 1
  fi
  case "$_CAPTURED_STDERR" in
    *"WARN"*"WL-5"*) : ;;
    *) _fail "aviso_wl5" "esperava aviso WL-5 em stderr, obteve: $_CAPTURED_STDERR"; return 1 ;;
  esac
}

# ==== WL-5: mismatch com --strict -> erro, exit != 0 ====

scenario_wl5_mismatch_com_strict_e_erro() {
  mktemp_test
  _make_valid_panel "$TMPDIR_TEST" "1.0.0"

  capture sh "$SCRIPT" --repo-root "$TMPDIR_TEST" --version 9.9.9 --strict
  if [ "$_CAPTURED_EXIT" = 0 ]; then
    _fail "exit_nao_zero" "esperado exit != 0 (WL-5 + --strict), obteve 0"
    return 1
  fi
  case "$_CAPTURED_STDERR" in
    *"ERROR"*"WL-5"*) : ;;
    *) _fail "erro_wl5" "esperava ERROR WL-5 em stderr, obteve: $_CAPTURED_STDERR"; return 1 ;;
  esac
}

# ==== Uso invalido: panel dir ausente ====

scenario_panel_dir_ausente() {
  mktemp_test

  capture sh "$SCRIPT" --repo-root "$TMPDIR_TEST"
  if [ "$_CAPTURED_EXIT" = 0 ]; then
    _fail "exit_nao_zero" "esperado exit != 0 (panel dir ausente), obteve 0"
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

# ==== Sonda contra o repo real: o proprio repo deve estar em lockstep ====

scenario_repo_real_em_lockstep() {
  capture sh "$SCRIPT" --repo-root "$REPO_ROOT"
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "repo_real_lockstep" "repo real deveria estar em lockstep (WL-1..WL-4), obteve exit $_CAPTURED_EXIT stderr=$_CAPTURED_STDERR"
    return 1
  fi
}

run_all_scenarios
