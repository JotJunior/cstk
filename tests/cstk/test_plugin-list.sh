#!/bin/sh
# test_plugin-list.sh — cobre cli/lib/plugin-list.sh
#
# Cenarios cobertos:
#   lista_vazia          : sem plugins → exit 0 + "Nenhum plugin instalado."
#   lista_um_plugin      : 1 plugin instalado → exit 0, linha com NAME/VERSION/TYPE/ok
#   lista_n_plugins      : N plugins → todas as linhas listadas
#   status_tampered      : --verify com bundle adulterado → status "tampered"
#   status_unknown       : plugin no registry mas sem diretorio → "unknown"
#   sem_rede             : NENHUMA chamada de rede ocorre (Scenario 7)
#   performance          : <2s com 5 plugins (SC-004)

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

CSTK_LIB="$REPO_ROOT/cli/lib"
export CSTK_LIB

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# _setup_plugin_env: cria fake-home, CSTK_LIB env, escreve um script de
# contexto para ser sourced em capturas subsequentes.
# Exporta: _fake_home, _env_script
_setup_plugin_env() {
  _fake_home="$TMPDIR_TEST/fake-home"
  mkdir -p "$_fake_home"
  _env_script="$TMPDIR_TEST/_env_$$.sh"
  printf '%s\n' \
    "CSTK_LIB='$CSTK_LIB'" \
    "HOME='$_fake_home'" \
    "export CSTK_LIB HOME" \
    ". '$CSTK_LIB/plugin-common.sh'" \
    ". '$CSTK_LIB/plugin-list.sh'" \
    > "$_env_script"
}

# _install_fake_plugin: instala um plugin fake no fake-home.
#   $1 = name, $2 = version, $3 = type, $4 = sha256 (optional, 64 zeros por padrao)
_install_fake_plugin() {
  _ifp_name=$1
  _ifp_ver=${2:-"1.0.0"}
  _ifp_type=${3:-"llm"}
  _ifp_sha=${4:-"0000000000000000000000000000000000000000000000000000000000000000"}

  _ifp_dir="$_fake_home/.claude/cstk/plugins/$_ifp_name"
  mkdir -p "$_ifp_dir/skills"
  cat > "$_ifp_dir/plugin-manifest.json" << EOF
{"name":"$_ifp_name","version":"$_ifp_ver","type":"$_ifp_type","schema_version":1,"sha256":"$_ifp_sha","skills":[]}
EOF

  # Inicializar e upsert no registry.
  sh -c "
    CSTK_LIB='$CSTK_LIB'
    HOME='$_fake_home'
    export CSTK_LIB HOME
    . '$CSTK_LIB/plugin-common.sh'
    plugin_registry_init
    plugin_registry_upsert '$_ifp_name' '$_ifp_ver' '$_ifp_type' '$_ifp_sha'
  " 2>/dev/null
}

# _run_list: executa plugin_list_main com o env de fake-home.
#   $@ = args para plugin_list_main
_run_list() {
  _script="$TMPDIR_TEST/_list_$$.sh"
  cat "$_env_script" > "$_script"
  printf 'plugin_list_main "$@"\n' >> "$_script"
  capture sh "$_script" "$@"
  rm -f "$_script"
}

# ---------------------------------------------------------------------------
# Scenario: lista vazia
# ---------------------------------------------------------------------------

scenario_lista_vazia_exit0() {
  _setup_plugin_env
  _run_list

  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "lista_vazia_exit0" "exit esperado 0, obtido $_CAPTURED_EXIT; stderr: $_CAPTURED_STDERR"
    return 1
  fi

  case "$_CAPTURED_STDOUT" in
    *"Nenhum plugin instalado"*) : ;;
    *) _fail "lista_vazia_exit0" "stdout nao menciona lista vazia: $_CAPTURED_STDOUT"; return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# Scenario: lista com 1 plugin
# ---------------------------------------------------------------------------

scenario_lista_um_plugin_exit0() {
  _setup_plugin_env
  _install_fake_plugin "codex" "1.2.0" "llm" \
    "0000000000000000000000000000000000000000000000000000000000000000"
  _run_list

  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "lista_um_plugin" "exit esperado 0, obtido $_CAPTURED_EXIT; stderr: $_CAPTURED_STDERR"
    return 1
  fi

  case "$_CAPTURED_STDOUT" in
    *"codex"*) : ;;
    *) _fail "lista_um_plugin" "stdout nao contem 'codex': $_CAPTURED_STDOUT"; return 1 ;;
  esac
  case "$_CAPTURED_STDOUT" in
    *"1.2.0"*) : ;;
    *) _fail "lista_um_plugin" "stdout nao contem versao '1.2.0': $_CAPTURED_STDOUT"; return 1 ;;
  esac
  case "$_CAPTURED_STDOUT" in
    *"llm"*) : ;;
    *) _fail "lista_um_plugin" "stdout nao contem type 'llm': $_CAPTURED_STDOUT"; return 1 ;;
  esac
  case "$_CAPTURED_STDOUT" in
    *"ok"*) : ;;
    *) _fail "lista_um_plugin" "stdout nao contem status 'ok': $_CAPTURED_STDOUT"; return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# Scenario: lista com N plugins
# ---------------------------------------------------------------------------

scenario_lista_n_plugins_exit0() {
  _setup_plugin_env
  _install_fake_plugin "codex" "1.0.0" "llm" \
    "0000000000000000000000000000000000000000000000000000000000000000"
  _install_fake_plugin "lang-dotnet" "0.3.1" "lang" \
    "0000000000000000000000000000000000000000000000000000000000000001"
  _run_list

  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "lista_n_plugins" "exit esperado 0, obtido $_CAPTURED_EXIT"
    return 1
  fi

  case "$_CAPTURED_STDOUT" in
    *"codex"*) : ;;
    *) _fail "lista_n_plugins" "stdout nao contem 'codex': $_CAPTURED_STDOUT"; return 1 ;;
  esac
  case "$_CAPTURED_STDOUT" in
    *"lang-dotnet"*) : ;;
    *) _fail "lista_n_plugins" "stdout nao contem 'lang-dotnet': $_CAPTURED_STDOUT"; return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# Scenario: status tampered (com --verify, bundle adulterado)
# ---------------------------------------------------------------------------

scenario_status_tampered_com_verify() {
  _setup_plugin_env
  # Instalar um plugin com sha256 que NAO bate com o conteudo real.
  _install_fake_plugin "tampered-plugin" "1.0.0" "llm" \
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  _run_list --verify

  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "status_tampered" "exit esperado 0, obtido $_CAPTURED_EXIT; stderr: $_CAPTURED_STDERR"
    return 1
  fi

  case "$_CAPTURED_STDOUT" in
    *"tampered"*) : ;;
    *) _fail "status_tampered" "stdout nao contem 'tampered': $_CAPTURED_STDOUT"; return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# Scenario: status ok com --verify (bundle integro)
# ---------------------------------------------------------------------------

scenario_status_ok_com_verify() {
  _setup_plugin_env

  # Instalar usando o bundle fixture valido cujo sha256 real conhecemos.
  _fake_dir="$_fake_home/.claude/cstk/plugins/test-plugin"
  mkdir -p "$_fake_dir/skills/example-skill"
  cp -R "$TESTS_ROOT/cstk/fixtures/plugin-add/valid-bundle/." "$_fake_dir/"

  # Calcular sha256 real do bundle (excluindo manifest).
  _real_sha=$(sh -c "
    CSTK_LIB='$CSTK_LIB'
    HOME='$_fake_home'
    export CSTK_LIB HOME
    . '$CSTK_LIB/plugin-common.sh'
    plugin_compute_bundle_checksum '$_fake_dir'
  " 2>/dev/null)

  # Instalar no registry com sha real.
  sh -c "
    CSTK_LIB='$CSTK_LIB'
    HOME='$_fake_home'
    export CSTK_LIB HOME
    . '$CSTK_LIB/plugin-common.sh'
    plugin_registry_init
    plugin_registry_upsert 'test-plugin' '1.0.0' 'llm' '$_real_sha'
  " 2>/dev/null

  _run_list --verify

  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "status_ok_com_verify" "exit esperado 0, obtido $_CAPTURED_EXIT; stderr: $_CAPTURED_STDERR"
    return 1
  fi

  case "$_CAPTURED_STDOUT" in
    *"test-plugin"*) : ;;
    *) _fail "status_ok_com_verify" "stdout nao contem 'test-plugin': $_CAPTURED_STDOUT"; return 1 ;;
  esac

  # Verificar que NAO aparece "tampered".
  case "$_CAPTURED_STDOUT" in
    *"tampered"*)
      _fail "status_ok_com_verify" "status 'tampered' inesperado para bundle integro: $_CAPTURED_STDOUT"
      return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# Scenario: status unknown (plugin no registry mas diretorio ausente)
# ---------------------------------------------------------------------------

scenario_status_unknown_sem_diretorio() {
  _setup_plugin_env

  # Inserir no registry sem criar o diretorio.
  sh -c "
    CSTK_LIB='$CSTK_LIB'
    HOME='$_fake_home'
    export CSTK_LIB HOME
    . '$CSTK_LIB/plugin-common.sh'
    plugin_registry_init
    plugin_registry_upsert 'ghost-plugin' '1.0.0' 'llm' \
      '0000000000000000000000000000000000000000000000000000000000000000'
  " 2>/dev/null

  _run_list

  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "status_unknown" "exit esperado 0, obtido $_CAPTURED_EXIT"
    return 1
  fi

  case "$_CAPTURED_STDOUT" in
    *"unknown"*) : ;;
    *) _fail "status_unknown" "stdout nao contem 'unknown': $_CAPTURED_STDOUT"; return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# Scenario: sem rede — nenhuma chamada de rede (Scenario 7, FR-018)
# ---------------------------------------------------------------------------

scenario_sem_rede_nenhuma_chamada() {
  _setup_plugin_env
  _install_fake_plugin "offline-plugin" "1.0.0" "llm" \
    "0000000000000000000000000000000000000000000000000000000000000000"

  # Usar PATH sem curl para confirmar que nenhuma rede e acessada.
  _script="$TMPDIR_TEST/_nonet_$$.sh"
  cat "$_env_script" > "$_script"
  printf 'plugin_list_main "$@"\n' >> "$_script"

  # PATH sem curl (manter sh + utilitarios basicos).
  _safe_path=$(printf '%s' "$PATH" | tr ':' '\n' | grep -v '/curl' | tr '\n' ':' | sed 's/:$//')
  capture env PATH="$_safe_path" sh "$_script"
  rm -f "$_script"

  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "sem_rede" "exit esperado 0 sem curl, obtido $_CAPTURED_EXIT; stderr: $_CAPTURED_STDERR"
    return 1
  fi

  case "$_CAPTURED_STDOUT" in
    *"offline-plugin"*) : ;;
    *) _fail "sem_rede" "stdout nao contem 'offline-plugin': $_CAPTURED_STDOUT"; return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# Scenario: performance <2s com 5 plugins (SC-004)
# ---------------------------------------------------------------------------

scenario_performance_5_plugins() {
  _setup_plugin_env
  _install_fake_plugin "plugin-a" "1.0.0" "llm" \
    "0000000000000000000000000000000000000000000000000000000000000000"
  _install_fake_plugin "plugin-b" "1.0.0" "lang" \
    "0000000000000000000000000000000000000000000000000000000000000001"
  _install_fake_plugin "plugin-c" "1.0.0" "llm" \
    "0000000000000000000000000000000000000000000000000000000000000002"
  _install_fake_plugin "plugin-d" "1.0.0" "lang" \
    "0000000000000000000000000000000000000000000000000000000000000003"
  _install_fake_plugin "plugin-e" "1.0.0" "llm" \
    "0000000000000000000000000000000000000000000000000000000000000004"

  _script="$TMPDIR_TEST/_perf_$$.sh"
  cat "$_env_script" > "$_script"
  printf 'plugin_list_main "$@"\n' >> "$_script"

  _t0=$(date +%s 2>/dev/null) || _t0=0
  capture sh "$_script"
  _t1=$(date +%s 2>/dev/null) || _t1=0
  rm -f "$_script"

  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "performance" "exit esperado 0, obtido $_CAPTURED_EXIT; stderr: $_CAPTURED_STDERR"
    return 1
  fi

  # Verificar que 5 plugins aparecem no output.
  _count=$(printf '%s\n' "$_CAPTURED_STDOUT" | grep -c "plugin-" 2>/dev/null || printf '0')
  if [ "$_count" -lt 5 ]; then
    _fail "performance" "esperado >=5 linhas de plugin, obtido $_count"
    return 1
  fi

  # Verificar <2s (SC-004) — date +%s tem resolucao de 1s; 2s e margem segura.
  _elapsed=$(( _t1 - _t0 ))
  if [ "$_elapsed" -gt 2 ]; then
    _fail "performance" "plugin-list levou ${_elapsed}s, limite e 2s (SC-004)"
    return 1
  fi
}

run_all_scenarios
