#!/bin/sh
# test_digest-facets.sh — cobre
# plugins/cstk/skills/apply-insights/scripts/digest-facets.sh
#
# Agregador dos facets do /insights nativo -> digest markdown data-driven.
# Cobre: agregacao basica, ranking de friccao (sort desc), cap --top da cauda
# longa, amostras de friction_detail, degradacao graciosa (dir ausente/vazio,
# jq ausente) e validacao de argumentos.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"
. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/plugins/cstk/skills/apply-insights/scripts/digest-facets.sh"

_need_jq() { command -v jq >/dev/null 2>&1 || return 1; return 0; }

# _write_facets DIR -> 3 facets com contagens conhecidas:
#   goal_categories: bug_fix=2, feature_implementation=1
#   friction_counts: buggy_code=3, wrong_approach=2  (ranking deterministico)
#   outcome: fully_achieved/mostly_achieved/not_achieved = 1 cada
_write_facets() {
  _wf="$1"
  mkdir -p "$_wf"
  cat > "$_wf/f1.json" <<'JSON'
{ "underlying_goal": "g1", "goal_categories": {"bug_fix": 1}, "outcome": "fully_achieved",
  "friction_counts": {"buggy_code": 1}, "friction_detail": "DETALHE-BUGGY-UM",
  "claude_helpfulness": "very_helpful", "session_type": "single_task",
  "user_satisfaction_counts": {"likely_satisfied": 1}, "session_id": "f1" }
JSON
  cat > "$_wf/f2.json" <<'JSON'
{ "underlying_goal": "g2", "goal_categories": {"feature_implementation": 1}, "outcome": "mostly_achieved",
  "friction_counts": {"buggy_code": 1, "wrong_approach": 1}, "friction_detail": "DETALHE-APPROACH-DOIS",
  "claude_helpfulness": "very_helpful", "session_type": "single_task",
  "user_satisfaction_counts": {"likely_satisfied": 1}, "session_id": "f2" }
JSON
  cat > "$_wf/f3.json" <<'JSON'
{ "underlying_goal": "g3", "goal_categories": {"bug_fix": 1}, "outcome": "not_achieved",
  "friction_counts": {"buggy_code": 1, "wrong_approach": 1}, "friction_detail": "DETALHE-APPROACH-TRES",
  "claude_helpfulness": "unhelpful", "session_type": "single_task",
  "user_satisfaction_counts": {"dissatisfied": 1}, "session_id": "f3" }
JSON
}

# Agregacao basica: header, contagem de sessoes, somas por categoria/friccao.
scenario_agregacao_basica() {
  _need_jq || return 0
  _write_facets "$TMPDIR_TEST/facets"
  assert_exit 0 "$SCRIPT" --facets-dir "$TMPDIR_TEST/facets" || return 1
  capture "$SCRIPT" --facets-dir "$TMPDIR_TEST/facets"
  assert_stdout_contains "3 sessoes analisadas" || return 1
  assert_stdout_contains "Usage Facets Digest" || return 1
  assert_stdout_contains "buggy_code: 3" || return 1
  assert_stdout_contains "wrong_approach: 2" || return 1
  assert_stdout_contains "bug_fix: 2" || return 1
  assert_stdout_contains "feature_implementation: 1" || return 1
}

# Ranking: friccao mais frequente (buggy_code) aparece como 1a linha da secao.
scenario_friction_ranking_desc() {
  _need_jq || return 0
  _write_facets "$TMPDIR_TEST/facets"
  capture "$SCRIPT" --facets-dir "$TMPDIR_TEST/facets"
  _first=$(printf '%s\n' "$_CAPTURED_STDOUT" | grep -A1 'Padroes de friccao' | tail -1)
  [ "$_first" = "- buggy_code: 3" ] || { _fail "ranking friccao" "1a linha esperada '- buggy_code: 3', obtido '$_first'"; return 1; }
}

# Outcomes e satisfacao (mapsum) corretos.
scenario_outcomes_e_satisfacao() {
  _need_jq || return 0
  _write_facets "$TMPDIR_TEST/facets"
  capture "$SCRIPT" --facets-dir "$TMPDIR_TEST/facets"
  assert_stdout_contains "fully_achieved: 1" || return 1
  assert_stdout_contains "not_achieved: 1" || return 1
  assert_stdout_contains "likely_satisfied: 2" || return 1
}

# Amostras de friction_detail aparecem sob o heading do tipo de friccao.
scenario_friction_detail_samples() {
  _need_jq || return 0
  _write_facets "$TMPDIR_TEST/facets"
  capture "$SCRIPT" --facets-dir "$TMPDIR_TEST/facets"
  assert_stdout_contains "### buggy_code (3)" || return 1
  assert_stdout_contains "DETALHE-BUGGY-UM" || return 1
}

# Cap --top corta a cauda longa e anota o restante.
scenario_top_cap_cauda_longa() {
  _need_jq || return 0
  _d="$TMPDIR_TEST/facets"
  mkdir -p "$_d"
  _i=1
  while [ "$_i" -le 5 ]; do
    cat > "$_d/g$_i.json" <<JSON
{ "goal_categories": {"cat_$_i": 1}, "outcome": "fully_achieved", "friction_counts": {}, "session_id": "g$_i" }
JSON
    _i=$((_i + 1))
  done
  capture "$SCRIPT" --facets-dir "$_d" --top 2
  assert_stdout_contains "(+3 mais de 5)" || return 1
}

# friction_counts vazio em todos -> secao "(nenhum)" e amostras "(sem detalhe...)".
scenario_sem_friccao() {
  _need_jq || return 0
  _d="$TMPDIR_TEST/facets"
  mkdir -p "$_d"
  cat > "$_d/x.json" <<'JSON'
{ "goal_categories": {"bug_fix": 1}, "outcome": "fully_achieved", "friction_counts": {}, "session_id": "x" }
JSON
  assert_exit 0 "$SCRIPT" --facets-dir "$_d" || return 1
  capture "$SCRIPT" --facets-dir "$_d"
  assert_stdout_contains "## Padroes de friccao" || return 1
  assert_stdout_contains "(nenhum)" || return 1
}

# Degradacao: diretorio inexistente -> exit 0, stdout vazio, aviso em stderr.
scenario_dir_inexistente() {
  _need_jq || return 0
  capture "$SCRIPT" --facets-dir "$TMPDIR_TEST/nao-existe-xyz"
  [ "$_CAPTURED_EXIT" = "0" ] || { _fail "dir inexistente exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  [ -z "$_CAPTURED_STDOUT" ] || { _fail "dir inexistente stdout" "esperado vazio, obtido: $_CAPTURED_STDOUT"; return 1; }
  assert_stderr_contains "ausente" || return 1
}

# Degradacao: diretorio sem *.json -> exit 0, stdout vazio.
scenario_dir_sem_json() {
  _need_jq || return 0
  mkdir -p "$TMPDIR_TEST/vazio"
  capture "$SCRIPT" --facets-dir "$TMPDIR_TEST/vazio"
  [ "$_CAPTURED_EXIT" = "0" ] || { _fail "dir vazio exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  [ -z "$_CAPTURED_STDOUT" ] || { _fail "dir vazio stdout" "esperado vazio"; return 1; }
  assert_stderr_contains "nenhum facet" || return 1
}

# Degradacao: jq ausente -> exit 0, stdout vazio, aviso "jq" em stderr.
# Simula via PATH com os utilitarios necessarios MENOS jq (idem test_recall).
scenario_sem_jq() {
  _bin="$TMPDIR_TEST/bin"
  mkdir -p "$_bin"
  for _t in find cat wc tr printf sh; do
    _p=$(command -v "$_t" 2>/dev/null) && ln -sf "$_p" "$_bin/$_t"
  done
  _write_facets "$TMPDIR_TEST/facets"
  capture sh -c 'PATH="'"$_bin"'"; export PATH; exec "'"$SCRIPT"'" --facets-dir "'"$TMPDIR_TEST"'/facets"'
  [ "$_CAPTURED_EXIT" = "0" ] || { _fail "sem-jq exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  [ -z "$_CAPTURED_STDOUT" ] || { _fail "sem-jq stdout" "esperado vazio"; return 1; }
  assert_stderr_contains "jq" || return 1
}

# Validacao de argumentos: exit 2.
scenario_samples_invalido() {
  assert_exit 2 "$SCRIPT" --samples abc || return 1
}
scenario_samples_zero_invalido() {
  assert_exit 2 "$SCRIPT" --samples 0 || return 1
}
scenario_top_invalido() {
  assert_exit 2 "$SCRIPT" --top 0 || return 1
}
scenario_arg_desconhecido() {
  assert_exit 2 "$SCRIPT" --bogus || return 1
}
scenario_help_exit0() {
  assert_exit 0 "$SCRIPT" --help || return 1
  capture "$SCRIPT" --help
  assert_stdout_contains "Uso:" || return 1
}

run_all_scenarios
