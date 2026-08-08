#!/bin/sh
# test_aggregate.sh — cobre plugins/cstk/skills/review-features/scripts/aggregate.sh.
#
# Cria fixtures inline em $TMPDIR_TEST (em vez de fixtures/<dir>) porque cada
# scenario precisa de uma estrutura de subdirs dinamica com mtimes especificos.
#
# Convencao: usar 'return 1' apos cada assert (sem set -eu — harness sinaliza
# falha via exit code).

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/plugins/cstk/skills/review-features/scripts/aggregate.sh"

# ==== helpers locais ====

# _make_feature DIR NAME SPEC_FIRST_LINE TASKS_CONTENT [MTIME]
# Cria docs/specs/NAME/{spec.md,tasks.md} dentro de DIR, opcionalmente com
# mtime ajustado via touch -t (formato YYYYMMDDhhmm).
_make_feature() {
  _root="$1"; _fname="$2"; _spec_line="$3"; _tasks="$4"; _mtime="${5:-}"
  mkdir -p "$_root/$_fname" || return 2
  if [ -n "$_spec_line" ]; then
    printf '# %s\n\n%s\n' "$_fname" "$_spec_line" > "$_root/$_fname/spec.md"
  fi
  printf '%s\n' "$_tasks" > "$_root/$_fname/tasks.md"
  if [ -n "$_mtime" ]; then
    touch -t "$_mtime" "$_root/$_fname/tasks.md" || return 2
  fi
}

# ==== scenarios ====

scenario_diretorio_inexistente() {
  assert_exit 1 sh "$SCRIPT" "/caminho/que-nao/existe" || return 1
  assert_stderr_contains "nao encontrado" || return 1
}

scenario_diretorio_vazio() {
  mkdir -p "$TMPDIR_TEST/empty-root" || return 2
  assert_exit 0 sh "$SCRIPT" "$TMPDIR_TEST/empty-root" || return 1
  assert_stdout_contains "Nenhum subdiretorio" || return 1
}

scenario_subdir_sem_tasks_md_e_ignorado() {
  mkdir -p "$TMPDIR_TEST/no-tasks/feat-x" || return 2
  capture sh "$SCRIPT" "$TMPDIR_TEST/no-tasks" || return 2
  if [ "$_CAPTURED_EXIT" -ne 0 ]; then
    _fail "scenario_no_tasks" "exit nao-zero: $_CAPTURED_EXIT"
    return 1
  fi
  # Subdir existe mas nao tem tasks.md → nao aparece no relatorio.
  case "$_CAPTURED_STDOUT" in
    *"feat-x"*)
      _fail "scenario_no_tasks" "feat-x sem tasks.md aparece no relatorio"
      return 1
      ;;
  esac
}

scenario_arquivar_quando_100_pct() {
  _make_feature "$TMPDIR_TEST/r1" "done-feat" "Feature pronta." "\
### 1.1 Tudo \`[A]\`
- [x] 1.1.1 a
- [x] 1.1.2 b
" || return 2
  capture sh "$SCRIPT" --json "$TMPDIR_TEST/r1" || return 2
  assert_stdout_contains '"name":"done-feat"' || return 1
  assert_stdout_contains '"pct_done":100' || return 1
  assert_stdout_contains '"suggestion":"ARQUIVAR"' || return 1
}

scenario_priorizar_quando_critico_pendente_e_lt_50() {
  _make_feature "$TMPDIR_TEST/r2" "crit-feat" "Tem critico." "\
### 1.1 Critico \`[C]\`
- [x] 1.1.1 a
- [ ] 1.1.2 b
- [ ] 1.1.3 c
" || return 2
  capture sh "$SCRIPT" --json "$TMPDIR_TEST/r2" || return 2
  assert_stdout_contains '"criticality":"C"' || return 1
  assert_stdout_contains '"pct_done":33' || return 1
  assert_stdout_contains '"suggestion":"PRIORIZAR"' || return 1
}

scenario_continuar_quando_progresso_saudavel() {
  _make_feature "$TMPDIR_TEST/r3" "ok-feat" "Em ritmo." "\
### 1.1 Coisa \`[A]\`
- [x] 1.1.1 a
- [x] 1.1.2 b
- [x] 1.1.3 c
- [ ] 1.1.4 d
" || return 2
  capture sh "$SCRIPT" --json "$TMPDIR_TEST/r3" || return 2
  assert_stdout_contains '"pct_done":75' || return 1
  assert_stdout_contains '"suggestion":"CONTINUAR"' || return 1
}

scenario_abandonar_quando_zero_pct_e_mtime_antigo() {
  # Mtime fixado em 2020-01-01 → mais de 90 dias atras (em qualquer momento atual).
  _make_feature "$TMPDIR_TEST/r4" "stale-feat" "" "\
### 1.1 Algo \`[M]\`
- [ ] 1.1.1 nada feito
- [ ] 1.1.2 nem isso
" "202001010000" || return 2
  capture sh "$SCRIPT" --json "$TMPDIR_TEST/r4" || return 2
  assert_stdout_contains '"pct_done":0' || return 1
  assert_stdout_contains '"suggestion":"ABANDONAR"' || return 1
}

scenario_indefinido_quando_tasks_md_vazio() {
  mkdir -p "$TMPDIR_TEST/r5/empty-feat" || return 2
  : > "$TMPDIR_TEST/r5/empty-feat/tasks.md"
  capture sh "$SCRIPT" --json "$TMPDIR_TEST/r5" || return 2
  assert_stdout_contains '"name":"empty-feat"' || return 1
  assert_stdout_contains '"total":0' || return 1
  assert_stdout_contains '"suggestion":"INDEFINIDO"' || return 1
}

scenario_criticidade_pareada_com_pendencia_correta() {
  # Tarefa [C] toda concluida; tarefa [A] com pendentes → criticidade pendente = A.
  _make_feature "$TMPDIR_TEST/r6" "mixed-crit" "" "\
### 1.1 Critico ja feito \`[C]\`
- [x] 1.1.1 a
- [x] 1.1.2 b

### 1.2 Alto pendente \`[A]\`
- [x] 1.2.1 a
- [ ] 1.2.2 b
- [ ] 1.2.3 c
" || return 2
  capture sh "$SCRIPT" --json "$TMPDIR_TEST/r6" || return 2
  # Maior criticidade COM pendentes deve ser A, nao C (C ja esta todo concluido).
  assert_stdout_contains '"criticality":"A"' || return 1
}

scenario_markdown_output_tem_header_e_tabela() {
  _make_feature "$TMPDIR_TEST/r7" "md-feat" "Descricao." "\
### 1.1 Algo \`[A]\`
- [x] 1.1.1 a
- [ ] 1.1.2 b
" || return 2
  capture sh "$SCRIPT" "$TMPDIR_TEST/r7" || return 2
  assert_stdout_contains "## Relatorio Global de Features" || return 1
  assert_stdout_contains "| Feature | Descricao |" || return 1
  assert_stdout_contains "| md-feat |" || return 1
  assert_stdout_contains "Legenda de sugestoes" || return 1
}

scenario_json_only_omite_markdown() {
  _make_feature "$TMPDIR_TEST/r8" "json-feat" "Descricao." "\
### 1.1 Algo \`[A]\`
- [x] 1.1.1 a
" || return 2
  capture sh "$SCRIPT" --json "$TMPDIR_TEST/r8" || return 2
  if [ "$_CAPTURED_EXIT" -ne 0 ]; then
    _fail "scenario_json_only" "exit nao-zero: $_CAPTURED_EXIT"
    return 1
  fi
  # Deve ter JSON-line.
  assert_stdout_contains '"name":"json-feat"' || return 1
  # Nao deve ter o header markdown.
  case "$_CAPTURED_STDOUT" in
    *"## Relatorio"*|*"Legenda"*)
      _fail "scenario_json_only" "modo --json contem markdown indesejado"
      return 1
      ;;
  esac
}

scenario_help_imprime_uso() {
  assert_exit 0 sh "$SCRIPT" --help || return 1
  assert_stdout_contains "Uso:" || return 1
  assert_stdout_contains "DIRETORIO" || return 1
}

scenario_opcao_invalida_falha() {
  assert_exit 2 sh "$SCRIPT" --opcao-que-nao-existe || return 1
  assert_stderr_contains "opcao desconhecida" || return 1
}

scenario_dois_diretorios_falha() {
  assert_exit 2 sh "$SCRIPT" "/tmp/a" "/tmp/b" || return 1
  assert_stderr_contains "apenas um diretorio" || return 1
}

scenario_descricao_pipe_e_escapado_em_md() {
  _make_feature "$TMPDIR_TEST/r9" "pipe-feat" "Tem | pipe na descricao." "\
### 1.1 Algo \`[A]\`
- [ ] 1.1.1 a
" || return 2
  capture sh "$SCRIPT" "$TMPDIR_TEST/r9" || return 2
  # Coluna de descricao deve substituir | por / para nao quebrar tabela.
  case "$_CAPTURED_STDOUT" in
    *"Tem / pipe na descricao"*) ;;
    *)
      _fail "scenario_pipe_escape" "descricao com '|' nao foi escapada"
      return 1
      ;;
  esac
}

scenario_multiplas_features_listadas_em_ordem_alfabetica() {
  _make_feature "$TMPDIR_TEST/r10" "zebra"  "" "### 1.1 X \`[M]\`
- [x] 1.1.1 a" || return 2
  _make_feature "$TMPDIR_TEST/r10" "alpha"  "" "### 1.1 X \`[M]\`
- [x] 1.1.1 a" || return 2
  _make_feature "$TMPDIR_TEST/r10" "middle" "" "### 1.1 X \`[M]\`
- [x] 1.1.1 a" || return 2
  capture sh "$SCRIPT" --json "$TMPDIR_TEST/r10" || return 2
  # Verifica ordem: alpha aparece antes de middle, middle antes de zebra.
  _stdout="$_CAPTURED_STDOUT"
  _pos_alpha=$(printf '%s\n' "$_stdout" | grep -n '"name":"alpha"' | head -1 | cut -d: -f1)
  _pos_middle=$(printf '%s\n' "$_stdout" | grep -n '"name":"middle"' | head -1 | cut -d: -f1)
  _pos_zebra=$(printf '%s\n' "$_stdout" | grep -n '"name":"zebra"' | head -1 | cut -d: -f1)
  if [ -z "$_pos_alpha" ] || [ -z "$_pos_middle" ] || [ -z "$_pos_zebra" ]; then
    _fail "scenario_ordering" "uma das features nao apareceu no output"
    return 1
  fi
  if [ "$_pos_alpha" -ge "$_pos_middle" ] || [ "$_pos_middle" -ge "$_pos_zebra" ]; then
    _fail "scenario_ordering" "ordem nao alfabetica: alpha=$_pos_alpha middle=$_pos_middle zebra=$_pos_zebra"
    return 1
  fi
}

run_all_scenarios
