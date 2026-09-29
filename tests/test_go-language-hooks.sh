#!/bin/sh
# test_go-language-hooks.sh — cobre os hooks do perfil Go
# (plugins/cstk-language-go/hooks/*.sh) + o snippet classico
# language-related/go/settings.json.
#
# Regressao coberta: os hooks liam $CLAUDE_TOOL_INPUT (env var inexistente no
# harness) e o snippet registrava eventos PreToolCall/PostToolCall (nomes que
# nao existem) — os gates de Pre/PostToolUse nunca disparavam. O contrato real
# do harness: JSON no stdin com .tool_input; exit 2 bloqueia (PreToolUse) ou
# devolve stderr ao Claude (PostToolUse).

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"
. "$TESTS_ROOT/lib/harness.sh"

HOOKS_DIR="$REPO_ROOT/plugins/cstk-language-go/hooks"
SETTINGS="$REPO_ROOT/language-related/go/settings.json"

# _run_hook SCRIPT JSON -> invoca o hook com JSON via stdin; popula _CAPTURED_*.
_run_hook() {
  capture sh -c 'printf "%s" "$1" | "$2"' _ "$2" "$HOOKS_DIR/$1"
}

_require_jq_bash() {
  command -v jq >/dev/null 2>&1 && command -v bash >/dev/null 2>&1 && return 0
  _error "no_jq_bash" "jq ou bash indisponivel neste ambiente de teste"
  return 1
}

scenario_settings_usa_eventos_reais_do_harness() {
  _require_jq_bash || return 2
  jq -e '.hooks | has("PreToolUse") and has("PostToolUse") and has("Stop")' "$SETTINGS" >/dev/null \
    || { _fail "eventos" "esperado PreToolUse/PostToolUse/Stop em $SETTINGS"; return 1; }
  if grep -q 'PreToolCall\|PostToolCall' "$SETTINGS"; then
    _fail "eventos legados" "PreToolCall/PostToolCall nao existem no harness"; return 1
  fi
}

scenario_hooks_nao_dependem_de_env_var_inexistente() {
  if grep -l 'CLAUDE_TOOL_INPUT' "$HOOKS_DIR"/*.sh >/dev/null 2>&1; then
    _fail "env var" "hooks ainda leem CLAUDE_TOOL_INPUT: $(grep -l 'CLAUDE_TOOL_INPUT' "$HOOKS_DIR"/*.sh)"; return 1
  fi
}

scenario_route_order_bloqueia_rota_estatica_apos_parametrizada() {
  _require_jq_bash || return 2
  _json='{"hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"file_path":"/x/user_handler.go","content":"router.Get(\"/:id\", h.Get)\nrouter.Get(\"/export\", h.Export)\n"}}'
  _run_hook check-route-order.sh "$_json"
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit" "esperado 2, obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"; return 1; }
  assert_stderr_contains "Fiber trie conflict" || return 1
}

scenario_route_order_passa_com_ordem_correta() {
  _require_jq_bash || return 2
  _json='{"hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"file_path":"/x/user_handler.go","content":"router.Get(\"/export\", h.Export)\nrouter.Get(\"/:id\", h.Get)\n"}}'
  _run_hook check-route-order.sh "$_json"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"; return 1; }
}

scenario_route_order_ignora_arquivo_nao_handler() {
  _require_jq_bash || return 2
  _json='{"tool_name":"Write","tool_input":{"file_path":"/x/service.go","content":"router.Get(\"/:id\", h.Get)\nrouter.Get(\"/export\", h.Export)\n"}}'
  _run_hook check-route-order.sh "$_json"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"; return 1; }
}

scenario_schema_prefix_avisa_sem_bloquear() {
  _require_jq_bash || return 2
  _json='{"tool_name":"Edit","tool_input":{"file_path":"/x/repository/member.go","new_string":"q := `SELECT id FROM members WHERE id = $1`"}}'
  _run_hook check-schema-prefix.sh "$_json"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"; return 1; }
  assert_stderr_contains "schema prefix" || return 1
}

scenario_build_gate_devolve_falha_ao_claude() {
  _require_jq_bash || return 2
  mkdir -p "$TMPDIR_TEST/proj/services/svc-a" "$TMPDIR_TEST/bin"
  : > "$TMPDIR_TEST/proj/services/svc-a/go.mod"
  printf '#!/bin/sh\necho "main.go:1: syntax error" >&2\nexit 1\n' > "$TMPDIR_TEST/bin/go"
  chmod +x "$TMPDIR_TEST/bin/go"
  _json='{"hook_event_name":"PostToolUse","tool_name":"Edit","tool_input":{"file_path":"'"$TMPDIR_TEST"'/proj/services/svc-a/main.go"}}'
  capture env PATH="$TMPDIR_TEST/bin:$PATH" CLAUDE_PROJECT_DIR="$TMPDIR_TEST/proj" \
    sh -c 'printf "%s" "$1" | "$2"' _ "$_json" "$HOOKS_DIR/go-build-gate.sh"
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit" "esperado 2, obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"; return 1; }
  assert_stderr_contains "BUILD FAILED in services/svc-a" || return 1
}

scenario_build_gate_ignora_arquivo_nao_go() {
  _require_jq_bash || return 2
  mkdir -p "$TMPDIR_TEST/proj"
  _json='{"tool_name":"Write","tool_input":{"file_path":"'"$TMPDIR_TEST"'/proj/README.md"}}'
  capture env CLAUDE_PROJECT_DIR="$TMPDIR_TEST/proj" \
    sh -c 'printf "%s" "$1" | "$2"' _ "$_json" "$HOOKS_DIR/go-build-gate.sh"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"; return 1; }
}

run_all_scenarios
exit $?
