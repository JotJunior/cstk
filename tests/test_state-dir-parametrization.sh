#!/bin/sh
# test_state-dir-parametrization.sh — cobre o helper _state-dir.sh do
# runtime, validando os tres modos: (a) --state-dir explicito,
# (b) env var AGENTE_00C_STATE_DIR, (c) sem ambos = erro.
#
# Ref: docs/specs/_archived/feature-00c/spec.md FR-008, FR-011
#      docs/specs/_archived/feature-00c/research.md Decision 1
#      docs/specs/_archived/feature-00c/tasks.md FASE 1 task 1.3.4

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"
. "$TESTS_ROOT/lib/harness.sh"

HELPER="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/_state-dir.sh"

# Wrapper que source-a o helper e invoca _sd_resolve com o arg fornecido.
_run_resolve() {
  _arg="${1:-}"
  # shellcheck disable=SC1090
  ( . "$HELPER" && _sd_resolve "$_arg" )
}

# Wrapper que source-a o helper e invoca _sd_flavor_to_report_name.
_run_flavor_report() {
  _f="${1:-}"
  ( . "$HELPER" && _sd_flavor_to_report_name "$_f" )
}

# Wrapper que source-a o helper e invoca _sd_flavor_to_suggestions_name.
_run_flavor_suggestions() {
  _f="${1:-}"
  ( . "$HELPER" && _sd_flavor_to_suggestions_name "$_f" )
}

scenario_explicit_arg_tem_precedencia() {
  _expected="/some/path/agente-00c-state"
  capture sh -c ". '$HELPER' && _sd_resolve '$_expected'"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "$_CAPTURED_EXIT"; return 1; }
  if [ "$_CAPTURED_STDOUT" != "$_expected" ]; then
    _fail "stdout" "esperado $_expected, obtido $_CAPTURED_STDOUT"
    return 1
  fi
}

scenario_env_var_usada_quando_arg_vazio() {
  _expected="/tmp/feature-00c-state/user-auth"
  capture env AGENTE_00C_STATE_DIR="$_expected" sh -c \
    ". '$HELPER' && _sd_resolve ''"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "$_CAPTURED_EXIT"; return 1; }
  if [ "$_CAPTURED_STDOUT" != "$_expected" ]; then
    _fail "stdout" "esperado $_expected, obtido $_CAPTURED_STDOUT"
    return 1
  fi
}

scenario_arg_explicito_vence_env_var() {
  _arg="/explicit/state"
  _env="/env/state"
  capture env AGENTE_00C_STATE_DIR="$_env" sh -c \
    ". '$HELPER' && _sd_resolve '$_arg'"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "$_CAPTURED_EXIT"; return 1; }
  if [ "$_CAPTURED_STDOUT" != "$_arg" ]; then
    _fail "precedencia" "esperado $_arg, obtido $_CAPTURED_STDOUT"
    return 1
  fi
}

scenario_sem_arg_sem_env_falha() {
  capture env -u AGENTE_00C_STATE_DIR sh -c \
    ". '$HELPER' && _sd_resolve ''"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "exit" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "--state-dir nao fornecido" || return 1
}

scenario_require_dir_existente_passa() {
  _d="$TMPDIR_TEST/some-state"
  mkdir -p "$_d"
  capture sh -c ". '$HELPER' && _sd_require_dir '$_d'"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "$_CAPTURED_EXIT"; return 1; }
}

scenario_require_dir_inexistente_falha() {
  capture sh -c ". '$HELPER' && _sd_require_dir '/nao/existe'"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "exit" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "nao existe ou nao e diretorio" || return 1
}

scenario_flavor_agente00c_render_report() {
  capture sh -c ". '$HELPER' && _sd_flavor_to_report_name 'agente-00c'"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "$_CAPTURED_EXIT"; return 1; }
  if [ "$_CAPTURED_STDOUT" != "agente-00c-report.md" ]; then
    _fail "stdout" "esperado agente-00c-report.md, obtido $_CAPTURED_STDOUT"
    return 1
  fi
}

scenario_flavor_feature00c_render_report() {
  capture sh -c ". '$HELPER' && _sd_flavor_to_report_name 'feature-00c'"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "$_CAPTURED_EXIT"; return 1; }
  if [ "$_CAPTURED_STDOUT" != "feature-00c-report.md" ]; then
    _fail "stdout" "esperado feature-00c-report.md, obtido $_CAPTURED_STDOUT"
    return 1
  fi
}

scenario_flavor_default_e_agente00c() {
  # Sem arg, default deve ser agente-00c (backward-compat).
  capture sh -c ". '$HELPER' && _sd_flavor_to_report_name ''"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "$_CAPTURED_EXIT"; return 1; }
  if [ "$_CAPTURED_STDOUT" != "agente-00c-report.md" ]; then
    _fail "default" "esperado agente-00c-report.md (default), obtido $_CAPTURED_STDOUT"
    return 1
  fi
}

scenario_flavor_invalido_falha() {
  capture sh -c ". '$HELPER' && _sd_flavor_to_report_name 'desconhecido'"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "exit" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "flavor desconhecido" || return 1
}

scenario_flavor_suggestions_feature00c() {
  capture sh -c ". '$HELPER' && _sd_flavor_to_suggestions_name 'feature-00c'"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "$_CAPTURED_EXIT"; return 1; }
  if [ "$_CAPTURED_STDOUT" != "feature-00c-suggestions.md" ]; then
    _fail "stdout" "esperado feature-00c-suggestions.md, obtido $_CAPTURED_STDOUT"
    return 1
  fi
}

# Smoke test: garantir que helpers existentes (state-rw, etc) continuam
# funcionando exatamente como antes — backward-compat.
scenario_backcompat_state_rw_aceita_state_dir_arg() {
  _d="$TMPDIR_TEST/proj/.claude/agente-00c-state"
  mkdir -p "$_d"
  # state-rw.sh existe e aceita --state-dir como antes (sem nada mudou
  # nesse script). Smoke: invocar com path inexistente deve dar erro
  # claro, nao silencioso.
  capture "$REPO_ROOT/global/skills/agente-00c-runtime/scripts/state-rw.sh" \
    read --state-dir "/path/que/nao/existe"
  if [ "$_CAPTURED_EXIT" = 0 ]; then
    _fail "backcompat" "state-rw deveria falhar com path inexistente"
    return 1
  fi
}

run_all_scenarios
