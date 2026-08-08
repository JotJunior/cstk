#!/bin/sh
# test_cstk-main.sh — cobre cli/cstk (dispatch, --version, --help).
#
# Contrato (FASE 1.1 do backlog cstk-cli):
#   cstk --version         → imprime "cstk <ver>"; exit 0
#   cstk --help            → imprime USO/COMANDOS; exit 0
#   cstk help              → idem --help
#   cstk help install      → aponta para documentacao do subcomando; exit 0
#   cstk help UNKNOWN      → erro claro; exit 2
#   cstk                   → imprime USO; exit 0 (sem args = help)
#   cstk unknown-command   → erro + lista comandos; exit 2
#   cstk --unknown-flag    → erro de flag; exit 2
#   cstk install           → nao implementado (FASE 3); exit 1
#
# Obs: este test NAO e descoberto por tests/run.sh ate FASE 9.3.1 (que
# estende o --check-coverage para varrer cli/lib/ e tests/cstk/).
# Enquanto isso: rodar direto com `sh tests/cstk/test_cstk-main.sh`.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

CSTK="$REPO_ROOT/cli/cstk"

# ==== 1.1.6.a --version imprime a versao do arquivo VERSION ====

scenario_version_imprime() {
  capture sh "$CSTK" --version || return 1
  assert_exit 0 sh "$CSTK" --version || return 1
  assert_stdout_contains "cstk" || return 1
  # Dev mode: VERSION contem "0.0.0-dev"; release: tag SemVer (ex: 3.2.0)
  assert_stdout_match "^cstk [0-9A-Za-z.-]+$" || return 1
}

scenario_version_flag_curta() {
  # -V e alias de --version
  assert_exit 0 sh "$CSTK" -V || return 1
}

scenario_version_subcomando() {
  # `cstk version` tambem funciona como atalho
  assert_exit 0 sh "$CSTK" version || return 1
}

# ==== 1.1.6.b --help imprime USO + comandos ====

scenario_help_flag() {
  assert_exit 0 sh "$CSTK" --help || return 1
  assert_stdout_contains "USO:" || return 1
  assert_stdout_contains "install" || return 1
  assert_stdout_contains "self-update" || return 1
  assert_stdout_contains "doctor" || return 1
}

scenario_help_flag_curta() {
  assert_exit 0 sh "$CSTK" -h || return 1
  assert_stdout_contains "USO:" || return 1
}

scenario_help_subcomando() {
  assert_exit 0 sh "$CSTK" help || return 1
  assert_stdout_contains "USO:" || return 1
}

scenario_sem_args_imprime_help() {
  # cstk sem nenhum arg e equivalente a cstk --help
  assert_exit 0 sh "$CSTK" || return 1
  assert_stdout_contains "USO:" || return 1
}

# ==== 1.1.6.c help <comando-valido> aponta para documentacao ====

scenario_help_install() {
  assert_exit 0 sh "$CSTK" help install || return 1
  assert_stdout_contains "install" || return 1
  assert_stdout_contains "contracts/cli-commands.md" || return 1
}

scenario_help_self_update() {
  assert_exit 0 sh "$CSTK" help self-update || return 1
  assert_stdout_contains "self-update" || return 1
}

# ==== 1.1.6.d help <desconhecido> erro + exit 2 ====

scenario_help_desconhecido() {
  capture sh "$CSTK" help foobar
  if [ "$_CAPTURED_EXIT" != "2" ]; then
    _fail "scenario_help_desconhecido" \
      "exit esperado 2, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "comando desconhecido" || return 1
}

# ==== 1.1.6.e comando desconhecido → exit 2 ====

scenario_comando_desconhecido() {
  capture sh "$CSTK" foo-bar
  if [ "$_CAPTURED_EXIT" != "2" ]; then
    _fail "scenario_comando_desconhecido" \
      "exit esperado 2, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "comando desconhecido" || return 1
  assert_stderr_contains "install" || return 1
}

scenario_flag_desconhecida() {
  capture sh "$CSTK" --random-flag
  if [ "$_CAPTURED_EXIT" != "2" ]; then
    _fail "scenario_flag_desconhecida" \
      "exit esperado 2, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "flag desconhecida" || return 1
}

# ==== 1.1.6.f comando valido mas lib ausente → exit 1 (scaffold-stage) ====
#
# Removido apos FASE 6: todos os comandos roteados (install/update/self-update/
# list/doctor) tem suas libs em cli/lib/. O caminho "lib ausente" ainda e
# coberto por scenario_cstk_lib_override abaixo (override de CSTK_LIB para
# fakelib vazio). Re-adicionar aqui se um novo comando for registrado no
# dispatcher antes da lib correspondente.

# ==== 1.1.6.g $CSTK_VERSION_FILE override funciona ====

scenario_version_file_override() {
  _alt=$(mktemp "$TMPDIR_TEST/version.XXXXXX") || {
    _error "scenario_version_file_override" "mktemp falhou"
    return 2
  }
  printf '9.9.9-test\n' > "$_alt"
  CSTK_VERSION_FILE="$_alt" capture sh "$CSTK" --version || return 1
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "scenario_version_file_override" \
      "exit esperado 0, obtido $_CAPTURED_EXIT"
    return 1
  fi
  echo "$_CAPTURED_STDOUT" | grep -q "cstk 9.9.9-test" || {
    _fail "scenario_version_file_override" \
      "stdout nao contem '9.9.9-test': $_CAPTURED_STDOUT"
    return 1
  }
}

# ==== 1.1.6.h $CSTK_LIB override troca localizacao da lib ====

scenario_cstk_lib_override() {
  # Quando CSTK_LIB aponta para tempdir vazio, invocar install ainda deve
  # dizer "nao implementado" (lib file ausente), exit 1 — nao crashar.
  mkdir "$TMPDIR_TEST/fakelib" || {
    _error "scenario_cstk_lib_override" "mkdir falhou"
    return 2
  }
  printf '1.2.3\n' > "$TMPDIR_TEST/VERSION"
  CSTK_LIB="$TMPDIR_TEST/fakelib" \
    capture sh "$CSTK" install
  if [ "$_CAPTURED_EXIT" != "1" ]; then
    _fail "scenario_cstk_lib_override" \
      "exit esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "nao implementado" || return 1
}

# ==== dispatch de `cstk hooks` (5.27.0) ====
#
# `hooks` segue a convencao generica do dispatch (cli/lib/<cmd>.sh definindo
# <cmd>_main), entao o que precisa de teste aqui e o WIRING: o comando existe,
# aparece no help e nao cai no ramo "comando desconhecido".

scenario_help_lista_hooks() {
  assert_exit 0 sh "$CSTK" --help || return 1
  assert_stdout_contains "hooks" || return 1
}

scenario_help_hooks_aponta_doc() {
  assert_exit 0 sh "$CSTK" help hooks || return 1
  assert_stdout_contains "hooks" || return 1
}

scenario_hooks_sem_subcomando_exit2() {
  # Chega em hooks_main (nao no ramo de comando desconhecido, que tambem e 2):
  # a mensagem de uso do proprio `cstk hooks` cita o subcomando install.
  assert_exit 2 sh "$CSTK" hooks || return 1
  assert_stderr_contains "install" || return 1
}

scenario_hooks_help_inline() {
  assert_exit 0 sh "$CSTK" hooks --help || return 1
  assert_stderr_contains "cstk hooks install" || return 1
}

# ==== cstk help telemetry (feature install-telemetry-optin) ====

scenario_help_telemetry_prints_snippet() {
  capture env CSTK_LIB="$CSTK_LIB" sh "$CSTK" help telemetry
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  for _tok in '# >>> cstk telemetry >>>' 'CLAUDE_CODE_ENABLE_TELEMETRY=1' \
              'OTEL_METRICS_EXPORTER=prometheus' 'CSTK_OTEL_ENDPOINT' 'command claude "$@"'; do
    case "$_CAPTURED_STDOUT" in
      *"$_tok"*) : ;;
      *) _fail "conteudo" "help telemetry sem '$_tok'"; return 1 ;;
    esac
  done
}

# Paridade: o snippet entre marcadores em cli/install.sh e cli/cstk MUST ser
# byte-identico — o help ensina exatamente o que o install escreveria.
scenario_help_telemetry_snippet_parity_with_install() {
  _a=$(awk '/^# >>> cstk telemetry >>>$/,/^# <<< cstk telemetry <<<$/' "$REPO_ROOT/cli/install.sh")
  _b=$(awk '/^# >>> cstk telemetry >>>$/,/^# <<< cstk telemetry <<<$/' "$REPO_ROOT/cli/cstk")
  [ -n "$_a" ] || { _fail "extract" "snippet ausente de cli/install.sh"; return 1; }
  [ "$_a" = "$_b" ] || { _fail "parity" "snippet de telemetria divergiu entre cli/install.sh e cli/cstk"; return 1; }
}

run_all_scenarios
