#!/bin/sh
# test_plugin-detect.sh — cobre cli/lib/plugin-detect.sh (feature
# claude-plugin-packaging, FASE 6, task 6.1.5).
#
# Contrato: docs/specs/claude-plugin-packaging/contracts/cli-plugin-awareness.md
#           §Helper compartilhado
#
# Cobre os 3 estados (instalado+habilitado, so instalado, ausente) x
# degradacao (JSON malformado, jq ausente).

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

CSTK_LIB="$REPO_ROOT/cli/lib"
export CSTK_LIB

_has_jq() {
  command -v jq >/dev/null 2>&1
}

# _make_shim_path: dir com symlinks para binarios POSIX essenciais EXCETO
# jq (mesma lista de tests/cstk/test_hooks.sh — manter em sync).
_make_shim_path() {
  _shim="$TMPDIR_TEST/shimbin"
  mkdir -p "$_shim"
  for _cmd in sh mktemp awk sed grep find head printf cp mv rm mkdir \
              chmod ls dirname basename tr cut wc env command sort \
              uniq date cat tar gzip gunzip xz bzip2 curl shasum sha256sum; do
    _src=$(command -v "$_cmd" 2>/dev/null) || continue
    [ -n "$_src" ] || continue
    ln -sf "$_src" "$_shim/$_cmd" 2>/dev/null || :
  done
  printf '%s' "$_shim"
}

# _make_home_installed_enabled: HOME sandbox com "cstk@cstk" instalado E
# habilitado, hooks.json presente no installPath.
_make_home_installed_enabled() {
  _h="$TMPDIR_TEST/home_ie"
  _ip="$_h/plugins/cache/cstk-marketplace/cstk/6.8.0"
  mkdir -p "$_h/.claude/plugins" "$_ip/hooks"
  cat > "$_h/.claude/plugins/installed_plugins.json" <<EOF
{
  "version": 2,
  "plugins": {
    "cstk@cstk": [
      {
        "scope": "user",
        "installPath": "$_ip",
        "version": "6.8.0",
        "installedAt": "2026-08-01T00:00:00.000Z",
        "lastUpdated": "2026-08-08T00:00:00.000Z"
      }
    ]
  }
}
EOF
  cat > "$_h/.claude/settings.json" <<'EOF'
{
  "enabledPlugins": {
    "cstk@cstk": true
  }
}
EOF
  printf '{"hooks":{}}\n' > "$_ip/hooks/hooks.json"
  printf '%s' "$_h"
}

# _make_home_installed_only: instalado, mas enabledPlugins == false.
_make_home_installed_only() {
  _h="$TMPDIR_TEST/home_io"
  _ip="$_h/plugins/cache/cstk-marketplace/cstk/6.8.0"
  mkdir -p "$_h/.claude/plugins" "$_ip"
  cat > "$_h/.claude/plugins/installed_plugins.json" <<EOF
{
  "version": 2,
  "plugins": {
    "cstk@cstk": [
      {
        "scope": "user",
        "installPath": "$_ip",
        "version": "6.8.0",
        "installedAt": "2026-08-01T00:00:00.000Z",
        "lastUpdated": "2026-08-01T00:00:00.000Z"
      }
    ]
  }
}
EOF
  cat > "$_h/.claude/settings.json" <<'EOF'
{
  "enabledPlugins": {
    "cstk@cstk": false
  }
}
EOF
  printf '%s' "$_h"
}

# _make_home_absent: nenhum registro nativo (nem diretorio .claude/plugins).
_make_home_absent() {
  _h="$TMPDIR_TEST/home_absent"
  mkdir -p "$_h/.claude"
  printf '%s' "$_h"
}

# ==== plugin_enabled ====

scenario_plugin_enabled_instalado_e_habilitado() {
  if ! _has_jq; then _error "no_jq" "jq indisponivel"; return 2; fi
  _h=$(_make_home_installed_enabled)
  capture env HOME="$_h" CSTK_LIB="$CSTK_LIB" sh -c \
    '. "$CSTK_LIB/plugin-detect.sh"; plugin_enabled cstk'
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"
    return 1
  fi
}

scenario_plugin_enabled_so_instalado() {
  if ! _has_jq; then _error "no_jq" "jq indisponivel"; return 2; fi
  _h=$(_make_home_installed_only)
  capture env HOME="$_h" CSTK_LIB="$CSTK_LIB" sh -c \
    '. "$CSTK_LIB/plugin-detect.sh"; plugin_enabled cstk'
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "exit" "esperado 1, obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"
    return 1
  fi
}

scenario_plugin_enabled_ausente() {
  if ! _has_jq; then _error "no_jq" "jq indisponivel"; return 2; fi
  _h=$(_make_home_absent)
  capture env HOME="$_h" CSTK_LIB="$CSTK_LIB" sh -c \
    '. "$CSTK_LIB/plugin-detect.sh"; plugin_enabled cstk'
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "exit" "esperado 1, obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"
    return 1
  fi
}

scenario_plugin_enabled_prefixo_nao_confunde_nomes_parecidos() {
  # "cstk-language-go@cstk" NAO deve casar prefixo "cstk@" (achado de
  # design do contrato: "@" faz parte do prefixo casado).
  if ! _has_jq; then _error "no_jq" "jq indisponivel"; return 2; fi
  _h="$TMPDIR_TEST/home_prefix"
  mkdir -p "$_h/.claude/plugins"
  cat > "$_h/.claude/plugins/installed_plugins.json" <<'EOF'
{
  "version": 2,
  "plugins": {
    "cstk-language-go@cstk": [
      {"scope": "user", "installPath": "/tmp/x", "installedAt": "2026-08-01T00:00:00.000Z"}
    ]
  }
}
EOF
  cat > "$_h/.claude/settings.json" <<'EOF'
{"enabledPlugins": {"cstk-language-go@cstk": true}}
EOF
  capture env HOME="$_h" CSTK_LIB="$CSTK_LIB" sh -c \
    '. "$CSTK_LIB/plugin-detect.sh"; plugin_enabled cstk'
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "exit" "esperado 1, obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"
    return 1
  fi
}

scenario_plugin_enabled_json_malformado() {
  if ! _has_jq; then _error "no_jq" "jq indisponivel"; return 2; fi
  _h="$TMPDIR_TEST/home_bad_json"
  mkdir -p "$_h/.claude/plugins"
  printf '{' > "$_h/.claude/plugins/installed_plugins.json"
  capture env HOME="$_h" CSTK_LIB="$CSTK_LIB" sh -c \
    '. "$CSTK_LIB/plugin-detect.sh"; plugin_enabled cstk'
  if [ "$_CAPTURED_EXIT" != 2 ]; then
    _fail "exit" "esperado 2, obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"
    return 1
  fi
}

scenario_plugin_enabled_settings_json_malformado() {
  if ! _has_jq; then _error "no_jq" "jq indisponivel"; return 2; fi
  _h=$(_make_home_installed_only)
  printf '{' > "$_h/.claude/settings.json"
  capture env HOME="$_h" CSTK_LIB="$CSTK_LIB" sh -c \
    '. "$CSTK_LIB/plugin-detect.sh"; plugin_enabled cstk'
  if [ "$_CAPTURED_EXIT" != 2 ]; then
    _fail "exit" "esperado 2, obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"
    return 1
  fi
}

scenario_plugin_enabled_jq_ausente() {
  _path_clean=$(_make_shim_path)
  _h=$(_make_home_installed_enabled)
  capture env -i HOME="$_h" PATH="$_path_clean" CSTK_LIB="$CSTK_LIB" sh -c '
    . "$CSTK_LIB/plugin-detect.sh"
    plugin_enabled cstk
  '
  if [ "$_CAPTURED_EXIT" != 2 ]; then
    _fail "exit" "esperado 2, obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"
    return 1
  fi
}

scenario_plugin_enabled_argumento_ausente() {
  capture sh -c '. "$CSTK_LIB/plugin-detect.sh"; plugin_enabled' CSTK_LIB="$CSTK_LIB"
  if [ "$_CAPTURED_EXIT" != 2 ]; then
    _fail "exit" "esperado 2, obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"
    return 1
  fi
}

# ==== plugin_install_path ====

scenario_plugin_install_path_encontrado() {
  if ! _has_jq; then _error "no_jq" "jq indisponivel"; return 2; fi
  _h=$(_make_home_installed_enabled)
  capture env HOME="$_h" CSTK_LIB="$CSTK_LIB" sh -c \
    '. "$CSTK_LIB/plugin-detect.sh"; plugin_install_path cstk'
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"
    return 1
  fi
  case "$_CAPTURED_STDOUT" in
    *"/plugins/cache/cstk-marketplace/cstk/6.8.0"*) ;;
    *) _fail "install_path stdout" "esperava installPath, obtido: $_CAPTURED_STDOUT"; return 1 ;;
  esac
}

scenario_plugin_install_path_nao_encontrado() {
  if ! _has_jq; then _error "no_jq" "jq indisponivel"; return 2; fi
  _h=$(_make_home_absent)
  capture env HOME="$_h" CSTK_LIB="$CSTK_LIB" sh -c \
    '. "$CSTK_LIB/plugin-detect.sh"; plugin_install_path cstk'
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "exit" "esperado 1, obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"
    return 1
  fi
}

scenario_plugin_install_path_jq_ausente() {
  _path_clean=$(_make_shim_path)
  _h=$(_make_home_installed_enabled)
  capture env -i HOME="$_h" PATH="$_path_clean" CSTK_LIB="$CSTK_LIB" sh -c '
    . "$CSTK_LIB/plugin-detect.sh"
    plugin_install_path cstk
  '
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "exit" "esperado 1, obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"
    return 1
  fi
}

scenario_plugin_install_path_multiplos_escolhe_mais_recente() {
  if ! _has_jq; then _error "no_jq" "jq indisponivel"; return 2; fi
  _h="$TMPDIR_TEST/home_multi"
  mkdir -p "$_h/.claude/plugins"
  cat > "$_h/.claude/plugins/installed_plugins.json" <<'EOF'
{
  "version": 2,
  "plugins": {
    "cstk@cstk": [
      {"scope": "user", "installPath": "/old/path", "installedAt": "2026-01-01T00:00:00.000Z", "lastUpdated": "2026-01-01T00:00:00.000Z"},
      {"scope": "user", "installPath": "/new/path", "installedAt": "2026-08-01T00:00:00.000Z", "lastUpdated": "2026-08-08T00:00:00.000Z"}
    ]
  }
}
EOF
  capture env HOME="$_h" CSTK_LIB="$CSTK_LIB" sh -c \
    '. "$CSTK_LIB/plugin-detect.sh"; plugin_install_path cstk'
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"
    return 1
  fi
  case "$_CAPTURED_STDOUT" in
    *"/new/path"*) ;;
    *) _fail "install_path multi" "esperava /new/path (mais recente), obtido: $_CAPTURED_STDOUT"; return 1 ;;
  esac
}

# ==== plugin_hooks_present ====

scenario_plugin_hooks_present_existe() {
  if ! _has_jq; then _error "no_jq" "jq indisponivel"; return 2; fi
  _h=$(_make_home_installed_enabled)
  capture env HOME="$_h" CSTK_LIB="$CSTK_LIB" sh -c \
    '. "$CSTK_LIB/plugin-detect.sh"; plugin_hooks_present cstk'
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"
    return 1
  fi
}

scenario_plugin_hooks_present_ausente() {
  if ! _has_jq; then _error "no_jq" "jq indisponivel"; return 2; fi
  _h=$(_make_home_installed_only)
  capture env HOME="$_h" CSTK_LIB="$CSTK_LIB" sh -c \
    '. "$CSTK_LIB/plugin-detect.sh"; plugin_hooks_present cstk'
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "exit" "esperado 1, obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"
    return 1
  fi
}

scenario_plugin_hooks_present_plugin_nao_instalado() {
  if ! _has_jq; then _error "no_jq" "jq indisponivel"; return 2; fi
  _h=$(_make_home_absent)
  capture env HOME="$_h" CSTK_LIB="$CSTK_LIB" sh -c \
    '. "$CSTK_LIB/plugin-detect.sh"; plugin_hooks_present cstk'
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "exit" "esperado 1, obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"
    return 1
  fi
}

run_all_scenarios
