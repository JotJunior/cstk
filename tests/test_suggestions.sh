#!/bin/sh
# test_suggestions.sh — cobre global/skills/agente-00c-runtime/scripts/suggestions.sh.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"
. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/suggestions.sh"
RW="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/state-rw.sh"

if ! command -v jq >/dev/null 2>&1; then
  printf '# test_suggestions.sh: jq ausente — pulando\n'
  exit 0
fi

_init() {
  capture "$RW" init --state-dir "$1" --execucao-id "exec-sug" \
    --projeto-alvo-path "/tmp/p" --descricao "POC suggestions tests"
}

_register_default() {
  capture "$SCRIPT" register --state-dir "$1" --suggestions-file "$2" \
    --skill "${3:-clarify}" --severidade "${4:-aviso}" \
    --diagnostico "Skill X gerou comportamento inesperado em uma situacao plausivel para reproducao" \
    --proposta "Ajustar template/skill para cobrir o caso especifico"
}

scenario_register_basico_gera_sug_001() {
  _sd="$TMPDIR_TEST/state"; _md="$TMPDIR_TEST/sug.md"
  _init "$_sd"
  _register_default "$_sd" "$_md"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "register" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "sug-001" || return 1
  [ -f "$_md" ] || { _fail "md nao gerada" ""; return 1; }
}

scenario_register_sequencial_gera_sug_002() {
  _sd="$TMPDIR_TEST/state"; _md="$TMPDIR_TEST/sug.md"
  _init "$_sd"
  _register_default "$_sd" "$_md"
  _register_default "$_sd" "$_md"
  capture "$SCRIPT" next-id --state-dir "$_sd"
  assert_stdout_contains "sug-003" || return 1
}

scenario_diagnostico_curto_falha() {
  _sd="$TMPDIR_TEST/state"; _md="$TMPDIR_TEST/sug.md"
  _init "$_sd"
  capture "$SCRIPT" register --state-dir "$_sd" --suggestions-file "$_md" \
    --skill "clarify" --severidade "aviso" \
    --diagnostico "muito curto" --proposta "fix"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "diag curto" "esperado 1"
    return 1
  fi
  assert_stderr_contains "< 50 chars" || return 1
}

scenario_severidade_invalida_falha() {
  _sd="$TMPDIR_TEST/state"; _md="$TMPDIR_TEST/sug.md"
  _init "$_sd"
  capture "$SCRIPT" register --state-dir "$_sd" --suggestions-file "$_md" \
    --skill "clarify" --severidade "critica" \
    --diagnostico "Diagnostico longo o suficiente para passar a validacao de tamanho minimo" \
    --proposta "fix"
  if [ "$_CAPTURED_EXIT" != 2 ]; then
    _fail "severidade invalida" "esperado 2"
    return 1
  fi
}

scenario_count_filtra_por_severidade() {
  _sd="$TMPDIR_TEST/state"; _md="$TMPDIR_TEST/sug.md"
  _init "$_sd"
  _register_default "$_sd" "$_md" clarify aviso
  _register_default "$_sd" "$_md" plan impeditiva
  _register_default "$_sd" "$_md" specify informativa
  capture "$SCRIPT" count --state-dir "$_sd"
  assert_stdout_contains "3" || return 1
  capture "$SCRIPT" count --state-dir "$_sd" --severidade impeditiva
  assert_stdout_contains "1" || return 1
  capture "$SCRIPT" count --state-dir "$_sd" --severidade aviso
  assert_stdout_contains "1" || return 1
}

scenario_list_filtra_e_imprime_tsv() {
  _sd="$TMPDIR_TEST/state"; _md="$TMPDIR_TEST/sug.md"
  _init "$_sd"
  _register_default "$_sd" "$_md" clarify aviso
  _register_default "$_sd" "$_md" plan impeditiva
  capture "$SCRIPT" list --state-dir "$_sd" --severidade impeditiva
  assert_stdout_contains "sug-002	plan	impeditiva" || return 1
  case "$_CAPTURED_STDOUT" in
    *clarify*) _fail "filtro nao excluiu clarify" ""; return 1 ;;
  esac
}

scenario_mark_issue_atualiza_url_e_metric() {
  _sd="$TMPDIR_TEST/state"; _md="$TMPDIR_TEST/sug.md"
  _init "$_sd"
  _register_default "$_sd" "$_md" clarify impeditiva
  capture "$SCRIPT" mark-issue --state-dir "$_sd" --suggestions-file "$_md" \
    --suggestion-id "sug-001" \
    --issue "https://github.com/JotJunior/cstk/issues/42"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "mark-issue" "$_CAPTURED_STDERR"; return 1; }
  capture "$RW" get --state-dir "$_sd" --field '.sugestoes[0].issue_aberta'
  assert_stdout_contains "issues/42" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.metricas_acumuladas.issues_toolkit_abertas'
  assert_stdout_contains "1" || return 1
  # MD foi regenerada com a issue
  grep -q "issues/42" "$_md" || { _fail "md nao regenerada" ""; return 1; }
}

scenario_mark_issue_inexistente_falha() {
  _sd="$TMPDIR_TEST/state"; _md="$TMPDIR_TEST/sug.md"
  _init "$_sd"
  capture "$SCRIPT" mark-issue --state-dir "$_sd" --suggestions-file "$_md" \
    --suggestion-id "sug-999" --issue "https://x"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "sug fantasma" "esperado 1"
    return 1
  fi
}

scenario_render_md_lista_sugestoes() {
  _sd="$TMPDIR_TEST/state"; _md="$TMPDIR_TEST/sug.md"
  _init "$_sd"
  _register_default "$_sd" "$_md" clarify aviso
  capture "$SCRIPT" render-md --state-dir "$_sd"
  assert_stdout_contains "# Sugestoes do Agente-00C" || return 1
  assert_stdout_contains "sug-001" || return 1
  assert_stdout_contains "skill \`clarify\`" || return 1
  assert_stdout_contains "severidade: aviso" || return 1
}

scenario_render_md_sem_sugestoes() {
  _sd="$TMPDIR_TEST/state"
  _init "$_sd"
  capture "$SCRIPT" render-md --state-dir "$_sd"
  assert_stdout_contains "Nenhuma sugestao" || return 1
}

run_all_scenarios
