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
  capture "$RW" get --state-dir "$_sd" --field '.suggestions[0].issue_opened'
  assert_stdout_contains "issues/42" || return 1
  capture "$RW" get --state-dir "$_sd" --field '.accumulated_metrics.toolkit_issues_opened'
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

# --- Back-compat: fixture pt-BR legada lida via reader-fallback (.en // .pt) ---
# schema-en-migration §6: os readers (count/list/next-id/render-md) usam paths EN
# com fallback pt-BR. Prova que um state.json legado (escrito antes da migracao,
# com chaves .sugestoes/.ondas/.execucao/.skill_afetada/.severidade/.diagnostico
# /.proposta/.issue_aberta/.criada_em/.metricas_acumuladas) continua legivel sem
# migrate previo. O WRITER grava chaves EN sem fallback (confia em EN-on-disk;
# o command-pai roda `state-rw.sh migrate` antes dos direct-writers), logo estes
# cenarios provam so o lado READER sobre um doc pt-BR.
_write_legacy_ptbr_state() {
  # $1 = state-dir. Escreve um state.json minimo com chaves pt-BR legadas.
  mkdir -p "$1"
  cat > "$1/state.json" <<'PTBR'
{
  "schema_version": 1,
  "execucao": { "id": "exec-legacy" },
  "ondas": [{ "id": "onda-001" }],
  "sugestoes": [
    {
      "id": "sug-001",
      "skill_afetada": "clarify",
      "diagnostico": "Diagnostico legado pt-BR longo o suficiente para passar a validacao minima de chars",
      "severidade": "impeditiva",
      "proposta": "Proposta legada pre-migracao em chaves pt-BR",
      "referencias": ["docs/legado.md"],
      "issue_aberta": null,
      "criada_em": "2024-01-01T00:00:00Z"
    }
  ],
  "metricas_acumuladas": { "sugestoes_skills_globais_total": 1 }
}
PTBR
}

scenario_ptbr_legado_readers_via_fallback() {
  # count/list/next-id leem o doc pt-BR via fallback (.suggestions // .sugestoes),
  # (.severity // .severidade), (.affected_skill // .skill_afetada), etc.
  _sd="$TMPDIR_TEST/legacy"
  _write_legacy_ptbr_state "$_sd"

  capture "$SCRIPT" count --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "count pt-BR" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "1" || return 1

  # count filtrado por severidade le (.severity // .severidade).
  capture "$SCRIPT" count --state-dir "$_sd" --severidade impeditiva
  assert_stdout_contains "1" || return 1

  # next-id deriva de max(.sugestoes[].id) = sug-001 -> sug-002.
  capture "$SCRIPT" next-id --state-dir "$_sd"
  assert_stdout_contains "sug-002" || return 1

  # list emite skill/severidade/diagnostico legados via fallback.
  capture "$SCRIPT" list --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "list pt-BR" "$_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "sug-001	clarify	impeditiva" || return 1
}

scenario_ptbr_legado_render_md_via_fallback() {
  # render-md le .execucao.id, .sugestoes[] e todas as folhas via fallback,
  # produzindo o markdown a partir de um state legado puro pt-BR.
  _sd="$TMPDIR_TEST/legacy-md"
  _write_legacy_ptbr_state "$_sd"
  capture "$SCRIPT" render-md --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "render-md pt-BR" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "exec-legacy" || return 1
  assert_stdout_contains "sug-001" || return 1
  assert_stdout_contains "skill \`clarify\`" || return 1
  assert_stdout_contains "Proposta legada" || return 1
  assert_stdout_contains "docs/legado.md" || return 1
}

run_all_scenarios
