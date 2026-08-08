#!/bin/sh
# test_suggestions.sh — cobre plugins/cstk/skills/agente-00c-runtime/scripts/suggestions.sh.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"
. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts/suggestions.sh"
RW="$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts/state-rw.sh"

if ! command -v jq >/dev/null 2>&1; then
  printf '# test_suggestions.sh: jq ausente — pulando\n'
  exit 0
fi

_init() {
  # HOME sandbox SEM config global: forca backend JSON deterministico mesmo
  # em hosts com `state_backend=sqlite` em ~/.claude/cstk/config (padrao de
  # hermeticidade do test__state-read.sh; state-db-runtime-parity 2.4.2).
  _i_home="$TMPDIR_TEST/home-json"
  mkdir -p "$_i_home"
  capture env HOME="$_i_home" "$RW" init --state-dir "$1" --execucao-id "exec-sug" \
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

# ==== Backend SQLite (state-db-runtime-parity FASE 2.4 / FR-001 / SC-003) ====
# register/mark-issue roteiam por state-rw.sh set (.suggestions vive em
# extra_fields; contadores accumulated_metrics derivados no read — dec-052).

_sqlite3_adequate() {
  command -v sqlite3 >/dev/null 2>&1 || return 1
  _v=$(sqlite3 --version 2>/dev/null | cut -d' ' -f1) || return 1
  [ -n "$_v" ]
}

_init_sqlite() {
  _is_home="$TMPDIR_TEST/home-sqlite"
  mkdir -p "$_is_home/.claude/cstk"
  printf 'state_backend=sqlite\n' > "$_is_home/.claude/cstk/config"
  env HOME="$_is_home" "$RW" init --state-dir "$1" \
    --execucao-id "exec-sug-sqlite" --projeto-alvo-path "/tmp/p" \
    --descricao "POC suggestions sqlite" >/dev/null 2>&1 || return 1
  [ -f "$1/state.db" ] || return 1
}

scenario_sqlite_register_persiste_e_count_le() {
  _sqlite3_adequate || { printf "# skip: sqlite3 indisponivel\n"; return 0; }
  _sd="$TMPDIR_TEST/state-sqlite"; _md="$TMPDIR_TEST/sug-sqlite.md"
  _init_sqlite "$_sd" || { _fail "fixture sqlite" "init nao gerou state.db"; return 1; }
  _register_default "$_sd" "$_md"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "register sqlite" "exit $_CAPTURED_EXIT: $_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "sug-001" || return 1
  case "$_CAPTURED_STDERR" in
    *"state.json ausente"*) _fail "register sqlite" "degradou com 'state.json ausente'"; return 1 ;;
  esac
  [ -f "$_md" ] || { _fail "md sqlite" "suggestions.md nao gerada"; return 1; }
  _register_default "$_sd" "$_md" "plan" "informativa"
  assert_stdout_contains "sug-002" || return 1
  capture "$SCRIPT" count --state-dir "$_sd"
  assert_stdout_contains "2" || return 1
  capture "$SCRIPT" list --state-dir "$_sd" --severidade informativa
  assert_stdout_contains "sug-002" || return 1
}

scenario_sqlite_metric_derivada_no_read() {
  # Sob sqlite o contador global_skill_suggestions_total NAO e gravado pelo
  # register — e derivado no read a partir de .suggestions (dec-052).
  _sqlite3_adequate || { printf "# skip: sqlite3 indisponivel\n"; return 0; }
  _sd="$TMPDIR_TEST/state-sqlite"; _md="$TMPDIR_TEST/sug-sqlite.md"
  _init_sqlite "$_sd" || { _fail "fixture sqlite" "init nao gerou state.db"; return 1; }
  _register_default "$_sd" "$_md"
  _register_default "$_sd" "$_md"
  _total=$("$RW" read --state-dir "$_sd" \
    | jq -r '.accumulated_metrics.global_skill_suggestions_total')
  [ "$_total" = "2" ] || { _fail "metric derivada" "esperado 2, obtido $_total"; return 1; }
}

scenario_sqlite_mark_issue_e_toolkit_issues_derivado() {
  _sqlite3_adequate || { printf "# skip: sqlite3 indisponivel\n"; return 0; }
  _sd="$TMPDIR_TEST/state-sqlite"; _md="$TMPDIR_TEST/sug-sqlite.md"
  _init_sqlite "$_sd" || { _fail "fixture sqlite" "init nao gerou state.db"; return 1; }
  _register_default "$_sd" "$_md"
  capture "$SCRIPT" mark-issue --state-dir "$_sd" \
    --suggestion-id "sug-001" --issue "https://github.com/JotJunior/cstk/issues/999"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "mark-issue sqlite" "exit $_CAPTURED_EXIT: $_CAPTURED_STDERR"; return 1; }
  capture "$SCRIPT" list --state-dir "$_sd"
  assert_stdout_contains "issues/999" || return 1
  _ti=$("$RW" read --state-dir "$_sd" \
    | jq -r '.accumulated_metrics.toolkit_issues_opened')
  [ "$_ti" = "1" ] || { _fail "toolkit_issues derivado" "esperado 1, obtido $_ti"; return 1; }
}

scenario_sqlite_anti_mirror() {
  # FR-003: nenhuma operacao pode materializar state.json dentro do state-dir.
  _sqlite3_adequate || { printf "# skip: sqlite3 indisponivel\n"; return 0; }
  _sd="$TMPDIR_TEST/state-sqlite"; _md="$TMPDIR_TEST/sug-sqlite.md"
  _init_sqlite "$_sd" || { _fail "fixture sqlite" "init nao gerou state.db"; return 1; }
  _register_default "$_sd" "$_md"
  capture "$SCRIPT" next-id --state-dir "$_sd"
  assert_stdout_contains "sug-002" || return 1
  capture "$SCRIPT" render-md --state-dir "$_sd"
  assert_stdout_contains "sug-001" || return 1
  if [ -f "$_sd/state.json" ]; then
    _fail "anti-mirror" "suggestions criou state.json dentro do state-dir sqlite"
    return 1
  fi
}

run_all_scenarios
