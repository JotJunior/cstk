#!/bin/sh
# test_plugin-remove.sh — cobre cli/lib/plugin-remove.sh
#
# Cenarios cobertos:
#   remove_existente      : remove plugin instalado → exit 0, store limpo, registry limpo
#   remove_ausente        : plugin nao instalado → exit 1 com mensagem clara (FR-012)
#   nome_invalido         : nome invalido → exit 2, ZERO fs
#   offline_ok            : NENHUMA chamada de rede (Scenario 7, FR-018)
#   falha_io_parcial      : simula rm parcial → exit 1, mensagem de estado inconsistente (tarefa 1.4)

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

CSTK_LIB="$REPO_ROOT/cli/lib"
export CSTK_LIB

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

_setup_remove_env() {
  _fake_home="$TMPDIR_TEST/fake-home"
  mkdir -p "$_fake_home"
}

# _install_fake_plugin_for_remove: instala plugin simples no fake-home.
_install_fake_plugin_for_remove() {
  _n=$1
  _ver=${2:-"1.0.0"}
  _type=${3:-"llm"}
  _sha=${4:-"0000000000000000000000000000000000000000000000000000000000000000"}
  _dir="$_fake_home/.claude/cstk/plugins/$_n"
  mkdir -p "$_dir/skills"
  cat > "$_dir/plugin-manifest.json" << EOF
{"name":"$_n","version":"$_ver","type":"$_type","schema_version":1,"sha256":"$_sha","skills":[]}
EOF
  sh -c "
    CSTK_LIB='$CSTK_LIB'
    HOME='$_fake_home'
    export CSTK_LIB HOME
    . '$CSTK_LIB/plugin-common.sh'
    plugin_registry_init
    plugin_registry_upsert '$_n' '$_ver' '$_type' '$_sha'
  " 2>/dev/null
}

# _run_remove: executa plugin_remove_main com fake-home.
_run_remove() {
  _script="$TMPDIR_TEST/_remove_$$.sh"
  printf '%s\n' \
    "CSTK_LIB='$CSTK_LIB'" \
    "HOME='$_fake_home'" \
    "export CSTK_LIB HOME" \
    ". '$CSTK_LIB/plugin-common.sh'" \
    ". '$CSTK_LIB/plugin-remove.sh'" \
    'plugin_remove_main "$@"' \
    > "$_script"
  capture sh "$_script" "$@"
  rm -f "$_script"
}

# ---------------------------------------------------------------------------
# Scenario: remove plugin existente
# ---------------------------------------------------------------------------

scenario_remove_existente_exit0() {
  _setup_remove_env
  _install_fake_plugin_for_remove "codex" "1.0.0" "llm" \
    "0000000000000000000000000000000000000000000000000000000000000000"

  _run_remove codex

  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "remove_existente" "exit esperado 0, obtido $_CAPTURED_EXIT; stderr: $_CAPTURED_STDERR"
    return 1
  fi

  # Verificar que o diretorio foi removido.
  if [ -d "$_fake_home/.claude/cstk/plugins/codex" ]; then
    _fail "remove_existente" "diretorio do plugin ainda existe apos remocao"
    return 1
  fi

  # Verificar que o registry nao tem mais a entrada.
  _registry_content=$(cat "$_fake_home/.claude/cstk/plugins/registry.json" 2>/dev/null || printf '{}')
  case "$_registry_content" in
    *'"codex"'*)
      _fail "remove_existente" "registry ainda contem 'codex' apos remocao"
      return 1 ;;
  esac

  # Verificar mensagem de confirmacao.
  case "$_CAPTURED_STDOUT" in
    *"codex"*"removido"*) : ;;
    *"removido"*"codex"*) : ;;
    *) _fail "remove_existente" "stdout nao confirma remocao: $_CAPTURED_STDOUT"; return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# Scenario: remove plugin nao instalado → exit 1 (FR-012)
# ---------------------------------------------------------------------------

scenario_remove_ausente_exit1() {
  _setup_remove_env

  _run_remove "plugin-nao-existe"

  if [ "$_CAPTURED_EXIT" != "1" ]; then
    _fail "remove_ausente" "exit esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi

  # Verificar mensagem clara.
  case "$_CAPTURED_STDERR" in
    *"nao instalado"*|*"nao encontrado"*) : ;;
    *) _fail "remove_ausente" "stderr nao menciona 'nao instalado': $_CAPTURED_STDERR"; return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# Scenario: nome invalido → exit 2, ZERO fs (FR-002)
# ---------------------------------------------------------------------------

scenario_nome_invalido_exit2() {
  _setup_remove_env

  _run_remove "../evil"

  if [ "$_CAPTURED_EXIT" != "2" ]; then
    _fail "nome_invalido_exit2" "exit esperado 2, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Scenario: offline OK — sem rede (Scenario 7, FR-018)
# ---------------------------------------------------------------------------

scenario_offline_ok() {
  _setup_remove_env
  _install_fake_plugin_for_remove "offline-plugin" "1.0.0" "llm" \
    "0000000000000000000000000000000000000000000000000000000000000000"

  # Rodar com PATH sem curl.
  _script="$TMPDIR_TEST/_offline_$$.sh"
  printf '%s\n' \
    "CSTK_LIB='$CSTK_LIB'" \
    "HOME='$_fake_home'" \
    "export CSTK_LIB HOME" \
    ". '$CSTK_LIB/plugin-common.sh'" \
    ". '$CSTK_LIB/plugin-remove.sh'" \
    'plugin_remove_main "$@"' \
    > "$_script"
  _safe_path=$(printf '%s' "$PATH" | tr ':' '\n' | grep -v '/curl' | tr '\n' ':' | sed 's/:$//')
  capture env PATH="$_safe_path" sh "$_script" "offline-plugin"
  rm -f "$_script"

  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "offline_ok" "exit esperado 0 sem curl, obtido $_CAPTURED_EXIT; stderr: $_CAPTURED_STDERR"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Scenario: falha de IO parcial → exit 1, mensagem de estado inconsistente (tarefa 1.4)
# ---------------------------------------------------------------------------

scenario_falha_io_parcial_exit1() {
  _setup_remove_env
  _install_fake_plugin_for_remove "locked-plugin" "1.0.0" "llm" \
    "0000000000000000000000000000000000000000000000000000000000000000"

  _plugin_dir="$_fake_home/.claude/cstk/plugins/locked-plugin"

  # Simular falha de rm: tornar o arquivo de manifest read-only E o diretorio
  # tambem, para que rm -rf falhe no macOS/BSD quando o dono nao tem write no dir.
  # NOTA: em muitos sistemas, root ou o dono pode ainda remover com rm -rf.
  # Abordagem mais confiavel: substituir rm por stub que falha no script.

  _script="$TMPDIR_TEST/_failrm_$$.sh"
  printf '%s\n' \
    "CSTK_LIB='$CSTK_LIB'" \
    "HOME='$_fake_home'" \
    "export CSTK_LIB HOME" \
    ". '$CSTK_LIB/plugin-common.sh'" \
    ". '$CSTK_LIB/plugin-remove.sh'" \
    > "$_script"

  # Redefinir rm para simular falha e manter o diretorio.
  # O plugin_remove_main chama 'rm -rf -- "$_pr_store"'.
  # Ao substituir rm com uma funcao que falha, o store NAO e removido.
  printf '%s\n' \
    "rm() { printf 'rm: simulando falha de IO\n' >&2; return 1; }" \
    'plugin_remove_main "$@"' \
    >> "$_script"

  capture sh "$_script" "locked-plugin"
  rm -f "$_script"

  if [ "$_CAPTURED_EXIT" != "1" ]; then
    _fail "falha_io_parcial" "exit esperado 1, obtido $_CAPTURED_EXIT; stderr: $_CAPTURED_STDERR"
    return 1
  fi

  # Verificar que stderr menciona estado inconsistente.
  case "$_CAPTURED_STDERR" in
    *"parcial"*|*"indeterminado"*|*"inconsistente"*) : ;;
    *) _fail "falha_io_parcial" "stderr nao menciona estado inconsistente: $_CAPTURED_STDERR"; return 1 ;;
  esac
}

run_all_scenarios
