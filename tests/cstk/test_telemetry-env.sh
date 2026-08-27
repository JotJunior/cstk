#!/bin/sh
# test_telemetry-env.sh — cobre cli/lib/telemetry-env.sh (issue #168).
#
# Contrato:
#   telemetry_env_enabled   exit 0 = injetar; 1 = nao injetar
#   telemetry_env_free_port stdout porta livre; exit 1 se nao conseguiu
#   telemetry_exec_claude   exec do binario `claude` com as variaveis
#                           ligadas SO no ambiente daquele processo
#
# Estrategia: source direto da lib + stub de `claude` no PATH que imprime as
# variaveis recebidas. Sem rede, sem Claude Code real.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

CSTK_LIB="$REPO_ROOT/cli/lib"
export CSTK_LIB

LIB="$CSTK_LIB/telemetry-env.sh"

# _stub_claude_path -> diretorio com um `claude` falso que imprime, uma por
# linha, as 4 variaveis de telemetria + os argumentos recebidos.
_stub_claude_path() {
  _dir="$TMPDIR_TEST/stubbin"
  mkdir -p "$_dir"
  cat > "$_dir/claude" <<'STUB'
#!/bin/sh
printf 'ENABLE=%s\n' "${CLAUDE_CODE_ENABLE_TELEMETRY:-<unset>}"
printf 'EXPORTER=%s\n' "${OTEL_METRICS_EXPORTER:-<unset>}"
printf 'PORT=%s\n' "${OTEL_EXPORTER_PROMETHEUS_PORT:-<unset>}"
printf 'ENDPOINT=%s\n' "${CSTK_OTEL_ENDPOINT:-<unset>}"
printf 'ARGV=%s\n' "$*"
STUB
  chmod +x "$_dir/claude"
  printf '%s' "$_dir"
}

# ==== telemetry_env_enabled ====

scenario_enabled_por_default() {
  capture env -u CSTK_TELEMETRY_AUTO -u CSTK_OTEL_ENDPOINT -u CLAUDE_CODE_ENABLE_TELEMETRY \
    sh -c ". \"$LIB\" && telemetry_env_enabled"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "default deveria injetar" "exit=$_CAPTURED_EXIT"; return 1; }
}

scenario_kill_switch_desabilita() {
  for _v in 0 no off false; do
    capture env CSTK_TELEMETRY_AUTO="$_v" sh -c ". \"$LIB\" && telemetry_env_enabled"
    [ "$_CAPTURED_EXIT" = 1 ] || { _fail "CSTK_TELEMETRY_AUTO=$_v deveria desabilitar" "exit=$_CAPTURED_EXIT"; return 1; }
  done
}

scenario_endpoint_ja_definido_nao_e_tocado() {
  # Ja configurado (wrapper do rc, config do operador) -> nao mexe.
  capture env CSTK_OTEL_ENDPOINT="http://127.0.0.1:9999/metrics" \
    sh -c ". \"$LIB\" && telemetry_env_enabled"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "endpoint ja definido deveria inibir" "exit=$_CAPTURED_EXIT"; return 1; }
}

scenario_optout_explicito_de_telemetria_respeitado() {
  # CLAUDE_CODE_ENABLE_TELEMETRY definido com valor != 1 = opt-out explicito.
  capture env CLAUDE_CODE_ENABLE_TELEMETRY=0 \
    sh -c ". \"$LIB\" && telemetry_env_enabled"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "opt-out explicito nao respeitado" "exit=$_CAPTURED_EXIT"; return 1; }
}

scenario_enable_igual_1_nao_inibe() {
  # =1 sem endpoint: ainda falta o endpoint, entao segue injetando.
  capture env -u CSTK_OTEL_ENDPOINT CLAUDE_CODE_ENABLE_TELEMETRY=1 \
    sh -c ". \"$LIB\" && telemetry_env_enabled"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "=1 sem endpoint deveria injetar" "exit=$_CAPTURED_EXIT"; return 1; }
}

# ==== telemetry_env_free_port ====

scenario_free_port_retorna_inteiro() {
  command -v python3 >/dev/null 2>&1 || { _fail "pre-requisito ausente" "python3"; return 2; }
  capture sh -c ". \"$LIB\" && telemetry_env_free_port"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "free_port falhou" "$_CAPTURED_STDERR"; return 1; }
  case "$_CAPTURED_STDOUT" in
    ''|*[!0-9]*) _fail "porta nao numerica" "[$_CAPTURED_STDOUT]"; return 1 ;;
  esac
}

scenario_free_port_sem_python3_falha_mudo() {
  _shim="$TMPDIR_TEST/nopy"
  mkdir -p "$_shim"
  for _c in sh env printf; do
    _p=$(command -v "$_c" 2>/dev/null) || continue
    [ -e "$_shim/$_c" ] || ln -s "$_p" "$_shim/$_c" 2>/dev/null || :
  done
  capture env PATH="$_shim" sh -c ". \"$LIB\" && telemetry_env_free_port"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "sem python3 deveria sair 1" "exit=$_CAPTURED_EXIT"; return 1; }
  [ -z "$_CAPTURED_STDOUT" ] || { _fail "deveria ser mudo em stdout" "[$_CAPTURED_STDOUT]"; return 1; }
}

# ==== telemetry_exec_claude ====

scenario_exec_liga_as_quatro_variaveis() {
  # O caso central da issue #168: `exec claude` cru nao alcanca a funcao
  # `claude()` do rc, entao a sessao subia sem NENHUMA variavel.
  command -v python3 >/dev/null 2>&1 || { _fail "pre-requisito ausente" "python3"; return 2; }
  _stub=$(_stub_claude_path)
  capture env -u CSTK_OTEL_ENDPOINT -u CLAUDE_CODE_ENABLE_TELEMETRY PATH="$_stub:$PATH" \
    sh -c ". \"$LIB\" && telemetry_exec_claude"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exec falhou" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "ENABLE=1" || return 1
  assert_stdout_contains "EXPORTER=prometheus" || return 1
  assert_stdout_match "PORT=[0-9]+" || return 1
  assert_stdout_match "ENDPOINT=http://127\.0\.0\.1:[0-9]+/metrics" || return 1
}

scenario_exec_porta_e_endpoint_sao_coerentes() {
  command -v python3 >/dev/null 2>&1 || { _fail "pre-requisito ausente" "python3"; return 2; }
  _stub=$(_stub_claude_path)
  capture env -u CSTK_OTEL_ENDPOINT -u CLAUDE_CODE_ENABLE_TELEMETRY PATH="$_stub:$PATH" \
    sh -c ". \"$LIB\" && telemetry_exec_claude"
  _porta=$(printf '%s\n' "$_CAPTURED_STDOUT" | sed -n 's/^PORT=//p')
  _end=$(printf '%s\n' "$_CAPTURED_STDOUT" | sed -n 's/^ENDPOINT=//p')
  [ "$_end" = "http://127.0.0.1:${_porta}/metrics" ] || {
    _fail "endpoint nao casa com a porta" "porta=$_porta endpoint=$_end"; return 1; }
}

scenario_exec_repassa_argumentos_intactos() {
  # `cstk 00c` passa a slash command inteira como argv[1] — nao pode ser
  # quebrada em palavras pela injecao.
  _stub=$(_stub_claude_path)
  capture env PATH="$_stub:$PATH" \
    sh -c ". \"$LIB\" && telemetry_exec_claude \"/agente-00c 'desc com espaco' --projeto-alvo-path '/tmp/p'\""
  assert_stdout_contains "ARGV=/agente-00c 'desc com espaco' --projeto-alvo-path '/tmp/p'" || return 1
}

scenario_exec_kill_switch_nao_injeta_nada() {
  _stub=$(_stub_claude_path)
  capture env -u CSTK_OTEL_ENDPOINT -u CLAUDE_CODE_ENABLE_TELEMETRY CSTK_TELEMETRY_AUTO=0 PATH="$_stub:$PATH" \
    sh -c ". \"$LIB\" && telemetry_exec_claude"
  assert_stdout_contains "ENABLE=<unset>" || return 1
  assert_stdout_contains "ENDPOINT=<unset>" || return 1
}

scenario_exec_preserva_endpoint_preexistente() {
  _stub=$(_stub_claude_path)
  capture env PATH="$_stub:$PATH" CSTK_OTEL_ENDPOINT="http://127.0.0.1:9999/metrics" \
    sh -c ". \"$LIB\" && telemetry_exec_claude"
  assert_stdout_contains "ENDPOINT=http://127.0.0.1:9999/metrics" || return 1
}

scenario_exec_sem_python3_cai_na_porta_default_e_avisa() {
  # Processo UNICO: cair na 9464 (default do exporter) mantem o custo por
  # onda medindo — ao contrario da leva paralela, onde N filhas na mesma
  # porta fixa seria pior que nada. Precisa avisar que o endpoint faltou.
  _stub=$(_stub_claude_path)
  _shim="$TMPDIR_TEST/nopy2"
  mkdir -p "$_shim"
  for _c in sh env printf chmod ln mkdir cat rm; do
    _p=$(command -v "$_c" 2>/dev/null) || continue
    [ -e "$_shim/$_c" ] || ln -s "$_p" "$_shim/$_c" 2>/dev/null || :
  done
  ln -s "$_stub/claude" "$_shim/claude" 2>/dev/null || :
  capture env -u CSTK_OTEL_ENDPOINT -u CLAUDE_CODE_ENABLE_TELEMETRY PATH="$_shim" \
    sh -c ". \"$LIB\" && telemetry_exec_claude"
  assert_stdout_contains "ENABLE=1" || return 1
  assert_stdout_contains "EXPORTER=prometheus" || return 1
  assert_stdout_contains "ENDPOINT=<unset>" || return 1
  assert_stderr_contains "cstk help telemetry" || return 1
}

run_all_scenarios
