#!/bin/sh
# test_scan-project-docs.sh — cobre
# plugins/cstk/skills/presentation/scripts/scan-project-docs.sh.
#
# Ref: docs/specs/presentation/quickstart.md cenarios 1-4
#      docs/specs/presentation/data-model.md §Inventario

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"
. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/plugins/cstk/skills/presentation/scripts/scan-project-docs.sh"

# _sp_run DIR ARGS... -> roda o script com DIR como diretorio de trabalho.
_sp_run() {
  _dir=$1
  shift
  capture sh -c 'cd "$1" && shift && exec sh "$@"' _ "$_dir" "$SCRIPT" "$@"
}

# _sp_field KEY FIELD_N -> campo N (1-based) do registro spec de chave KEY.
_sp_field() {
  printf '%s\n' "$_CAPTURED_STDOUT" | awk -F '\t' -v k="$1" -v n="$2" '$1 == "spec" && $2 == k { print $n }'
}

_sp_expect() {
  _got=$(_sp_field "$1" "$2")
  [ "$_got" = "$3" ] || { _fail "field" "spec $1 campo $2: esperado '$3', obtido '$_got'"; return 1; }
}

scenario_inventory_registros_basicos() {
  fixture presentation || return 2
  _sp_run "$TMPDIR_TEST" inventory --docs docs
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "# cstk-presentation-inventory v1" || return 1
  assert_stdout_match '^project	Atlas$' || return 1
  assert_stdout_match '^briefing	docs/briefing.md	[0-9]+	Atlas$' || return 1
  assert_stdout_match '^constitution	docs/constitution.md	[0-9]+	1\.1\.0$' || return 1
  assert_stdout_match '^principle	2	II	yes	Dados Verdadeiros$' || return 1
  assert_stdout_match '^principle	1	I	no	Simplicidade Primeiro$' || return 1
  assert_stdout_match '^totals	4	1	2	1	5	7	5	3$' || return 1
}

scenario_inventory_campos_da_spec_arquivada() {
  fixture presentation || return 2
  _sp_run "$TMPDIR_TEST" inventory --docs docs
  _k=_archived/2026-01-10-login
  _sp_expect "$_k" 3 archived || return 1
  _sp_expect "$_k" 4 2026-01-10 || return 1
  _sp_expect "$_k" 5 implemented || return 1
  _sp_expect "$_k" 6 spec,plan,research,tasks,checklists,converge-report || return 1
  _sp_expect "$_k" 7 1 || return 1
  _sp_expect "$_k" 8 3 || return 1
  _sp_expect "$_k" 9 3 || return 1
  _sp_expect "$_k" 10 3 || return 1
  _sp_expect "$_k" 11 clean || return 1
  _sp_expect "$_k" 14 "Login por link magico" || return 1
}

scenario_inventory_spec_ativa_parcial_em_andamento() {
  fixture presentation || return 2
  _sp_run "$TMPDIR_TEST" inventory --docs docs
  _sp_expect checkout-flow 3 active || return 1
  _sp_expect checkout-flow 5 in-progress || return 1
  _sp_expect checkout-flow 9 2 || return 1
  _sp_expect checkout-flow 10 4 || return 1
  _sp_expect checkout-flow 11 - || return 1
}

scenario_inventory_arquivada_sem_tasks_nao_e_implementada() {
  fixture presentation || return 2
  _sp_run "$TMPDIR_TEST" inventory --docs docs
  _sp_expect _archived/origins 5 archived || return 1
  _sp_expect _archived/origins 9 - || return 1
  _sp_expect _archived/origins 10 - || return 1
}

scenario_inventory_spec_viva() {
  fixture presentation || return 2
  _sp_run "$TMPDIR_TEST" inventory --docs docs
  _sp_expect current/login 3 living || return 1
  _sp_expect current/login 5 living || return 1
  _sp_expect current/login 13 docs/specs/current/login.md || return 1
  _sp_expect current/login 14 login || return 1
}

scenario_inventory_ordem_narrativa() {
  fixture presentation || return 2
  _sp_run "$TMPDIR_TEST" inventory --docs docs
  _order=$(printf '%s\n' "$_CAPTURED_STDOUT" | awk -F '\t' '$1 == "spec" { printf "%s ", $2 }')
  [ "$_order" = "_archived/origins _archived/2026-01-10-login checkout-flow current/login " ] \
    || { _fail "order" "ordem inesperada: $_order"; return 1; }
}

scenario_inventory_briefing_legado() {
  fixture presentation || return 2
  mkdir -p "$TMPDIR_TEST/docs/01-briefing-discovery"
  mv "$TMPDIR_TEST/docs/briefing.md" "$TMPDIR_TEST/docs/01-briefing-discovery/briefing.md"
  _sp_run "$TMPDIR_TEST" inventory --docs docs
  assert_stdout_match '^briefing	docs/01-briefing-discovery/briefing.md	' || return 1
}

scenario_inventory_sem_briefing_constitution_e_specs() {
  mkdir -p "$TMPDIR_TEST/proj/docs"
  _sp_run "$TMPDIR_TEST/proj" inventory
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stdout_match '^project	proj$' || return 1
  assert_stdout_not_contains "briefing	" || return 1
  assert_stdout_not_contains "constitution	" || return 1
  assert_stdout_match '^totals	0	0	0	0	0	0	0	0$' || return 1
}

scenario_inventory_formatos_alternativos_de_clarify() {
  fixture presentation || return 2
  mkdir -p "$TMPDIR_TEST/docs/specs/alt"
  cat > "$TMPDIR_TEST/docs/specs/alt/spec.md" <<'SPEC'
# Feature Specification: Alternativa

## Clarifications

### CQ1 — Primeira pergunta
Resposta.

### CQ2 — Segunda pergunta
Resposta.

- **Q3 — Terceira pergunta?**

## Requirements

- Q: fora da secao nao conta
SPEC
  _sp_run "$TMPDIR_TEST" inventory --docs docs
  _sp_expect alt 7 1 || return 1
  _sp_expect alt 8 3 || return 1
}

scenario_inventory_deterministico() {
  fixture presentation || return 2
  _sp_run "$TMPDIR_TEST" inventory --docs docs
  _a=$_CAPTURED_STDOUT
  _sp_run "$TMPDIR_TEST" inventory --docs docs
  [ "$_a" = "$_CAPTURED_STDOUT" ] || { _fail "determinism" "duas execucoes divergiram"; return 1; }
}

scenario_inventory_docs_inexistente_exit2() {
  _sp_run "$TMPDIR_TEST" inventory --docs nao-existe
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit" "esperado 2, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "inexistente" || return 1
}

scenario_diff_added_changed_removed_unchanged() {
  fixture presentation || return 2
  _sp_run "$TMPDIR_TEST" inventory --docs docs
  printf '%s\n' "$_CAPTURED_STDOUT" > "$TMPDIR_TEST/old.tsv"
  mkdir -p "$TMPDIR_TEST/docs/specs/search"
  printf '# Feature Specification: Busca\n' > "$TMPDIR_TEST/docs/specs/search/spec.md"
  printf -- '- [x] 1.1.5 Extra\n' >> "$TMPDIR_TEST/docs/specs/checkout-flow/tasks.md"
  rm -rf "$TMPDIR_TEST/docs/specs/_archived/origins"
  _sp_run "$TMPDIR_TEST" inventory --docs docs
  printf '%s\n' "$_CAPTURED_STDOUT" > "$TMPDIR_TEST/new.tsv"
  _sp_run "$TMPDIR_TEST" diff --old old.tsv --new new.tsv
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stdout_match '^added	spec	search$' || return 1
  assert_stdout_match '^changed	spec	checkout-flow$' || return 1
  assert_stdout_match '^removed	spec	_archived/origins$' || return 1
  assert_stdout_match '^unchanged	spec	_archived/2026-01-10-login$' || return 1
  assert_stdout_match '^unchanged	briefing	briefing$' || return 1
  assert_stdout_match '^unchanged	constitution	constitution$' || return 1
}

scenario_diff_arquivo_inexistente_exit2() {
  : > "$TMPDIR_TEST/a.tsv"
  _sp_run "$TMPDIR_TEST" diff --old a.tsv --new b.tsv
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit" "esperado 2, obtido $_CAPTURED_EXIT"; return 1; }
}

scenario_sem_subcomando_exit2() {
  assert_exit 2 sh "$SCRIPT" || return 1
  assert_stderr_contains "Uso:" || return 1
}

scenario_subcomando_desconhecido_exit2() {
  assert_exit 2 sh "$SCRIPT" bogus || return 1
}

run_all_scenarios
