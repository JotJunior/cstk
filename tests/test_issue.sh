#!/bin/sh
# test_issue.sh — cobre global/skills/agente-00c-runtime/scripts/issue.sh.
#
# Testes apenas locais (dry-run) — NAO chama gh real para nao gerar issues
# de teste em produçao. check-duplicate exige rede + auth, portanto e
# deixado para validacao end-to-end.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"
. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/issue.sh"
RW="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/state-rw.sh"
DEC="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/state-decisions.sh"
SG="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/suggestions.sh"

if ! command -v jq >/dev/null 2>&1; then
  printf '# test_issue.sh: jq ausente — pulando\n'
  exit 0
fi

_setup() {
  capture "$RW" init --state-dir "$1" --execucao-id "exec-issue-test" \
    --projeto-alvo-path "/tmp/p" --descricao "POC issue tests"
  [ "$_CAPTURED_EXIT" = 0 ] || return 1
  capture "$DEC" register --state-dir "$1" \
    --agente "orquestrador-00c" --etapa "clarify" \
    --contexto "Tentou avancar pipeline com perguntas contraditorias" \
    --opcoes '["A","B"]' --escolha "A" \
    --justificativa "Justificativa de tamanho ok aqui sim para teste"
  capture "$SG" register --state-dir "$1" --suggestions-file "$2" \
    --skill "clarify" --severidade "impeditiva" \
    --diagnostico "Skill clarify gerou opcoes contraditorias entre perguntas Q3 e Q5 para o mesmo escopo" \
    --proposta "Adicionar etapa de cross-check entre perguntas geradas pela skill"
}

scenario_hash_deterministico() {
  capture "$SCRIPT" hash --diagnostico "test diagnostico"
  _h1=$_CAPTURED_STDOUT
  capture "$SCRIPT" hash --diagnostico "test diagnostico"
  _h2=$_CAPTURED_STDOUT
  if [ "$_h1" != "$_h2" ]; then
    _fail "hash determinismo" "$_h1 != $_h2"
    return 1
  fi
  # 8 chars hex
  case "$_h1" in
    [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) ;;
    *) _fail "hash format" "esperado 8 hex chars, obtido: $_h1"; return 1 ;;
  esac
}

scenario_hash_normaliza_whitespace_e_case() {
  capture "$SCRIPT" hash --diagnostico "Test Diagnostico"
  _h1=$_CAPTURED_STDOUT
  capture "$SCRIPT" hash --diagnostico "  test  diagnostico  "
  _h2=$_CAPTURED_STDOUT
  if [ "$_h1" != "$_h2" ]; then
    _fail "normalizacao" "$_h1 != $_h2 (devia ser igual apos lowercase + collapse ws)"
    return 1
  fi
}

scenario_dry_run_imprime_template_completo() {
  _sd="$TMPDIR_TEST/state"; _md="$TMPDIR_TEST/sug.md"
  _setup "$_sd" "$_md" || { _error "fixture" ""; return 2; }
  capture "$SCRIPT" create --state-dir "$_sd" --suggestion-id "sug-001" \
    --skill "clarify" \
    --diagnostico "Skill clarify gerou opcoes contraditorias entre perguntas Q3 e Q5 para o mesmo escopo de armazenamento" \
    --proposta "Adicionar etapa de cross-check entre perguntas" \
    --por-que-impeditivo "Pipeline ja consumiu 1 retro — terceira tentativa violaria limite" \
    --reproducao "Onda 2 disparou bug" \
    --dry-run
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "dry-run exit" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "DRY-RUN" || return 1
  assert_stdout_contains "Title: [agente-00C] Bug em clarify" || return 1
  assert_stdout_contains "Repo: JotJunior/cstk" || return 1
  assert_stdout_contains "Labels: agente-00c,bug,skill-global" || return 1
  assert_stdout_contains "## Skill afetada" || return 1
  assert_stdout_contains "## Diagnostico" || return 1
  assert_stdout_contains "## Reproducao" || return 1
  assert_stdout_contains "## Por que e impeditivo" || return 1
  assert_stdout_contains "## Proposta de correcao" || return 1
  assert_stdout_contains "## Anexos" || return 1
}

scenario_dry_run_inclui_hash_no_titulo() {
  _sd="$TMPDIR_TEST/state"; _md="$TMPDIR_TEST/sug.md"
  _setup "$_sd" "$_md" || { _error "fixture" ""; return 2; }
  capture "$SCRIPT" create --state-dir "$_sd" --suggestion-id "sug-001" \
    --skill "clarify" \
    --diagnostico "Skill clarify gerou opcoes contraditorias entre perguntas Q3 e Q5 para o mesmo escopo de armazenamento" \
    --proposta "fix proposta detalhada" \
    --dry-run
  # Hash deve aparecer entre parenteses no titulo
  case "$_CAPTURED_STDOUT" in
    *"Title: [agente-00C] Bug em clarify ("*")"*) ;;
    *) _fail "hash no titulo" "esperado padrao 'Bug em SKILL (HASH):'"; return 1 ;;
  esac
}

scenario_dry_run_aplica_secrets_filter() {
  _sd="$TMPDIR_TEST/state"; _md="$TMPDIR_TEST/sug.md"
  _env="$TMPDIR_TEST/.env"
  printf 'DB_PWD=mysupersecretpwd123\n' > "$_env"
  _setup "$_sd" "$_md" || { _error "fixture" ""; return 2; }
  capture "$SCRIPT" create --state-dir "$_sd" --suggestion-id "sug-001" \
    --skill "clarify" \
    --diagnostico "Skill clarify falhou — leak: api_key=abcdef1234567890123456789xyz aqui" \
    --proposta "fix com mysupersecretpwd123 vazando aqui" \
    --env-file "$_env" \
    --dry-run
  case "$_CAPTURED_STDOUT" in
    *abcdef1234567890123456789xyz*)
      _fail "token vazou" "secrets-filter nao aplicado"; return 1 ;;
    *mysupersecretpwd123*)
      _fail "env vazou" "env-file scrub nao aplicado"; return 1 ;;
  esac
  assert_stdout_contains "REDACTED" || return 1
}

scenario_create_sem_state_falha() {
  _sd="$TMPDIR_TEST/empty"
  mkdir -p "$_sd"
  capture "$SCRIPT" create --state-dir "$_sd" --suggestion-id "sug-001" \
    --skill "x" \
    --diagnostico "Diagnostico longo o suficiente para passar a validacao" \
    --proposta "fix" --dry-run
  if [ "$_CAPTURED_EXIT" = 0 ]; then
    _fail "sem state" "esperado != 0"
    return 1
  fi
}

# --- Back-compat: fixture pt-BR legada lida via reader-fallback (.en // .pt) ---
# schema-en-migration: _ish_get_state / _ish_build_body leem o state.json com
# paths EN + fallback pt-BR. Prova que um state.json legado (escrito antes da
# migracao, com chaves .execucao/.etapa_corrente/.ondas/.decisoes/.contexto)
# continua sendo lido sem migrate previo — os valores legados afloram no body
# do dry-run. (As fixtures default via state-rw.sh init ja produzem EN no disco,
# entao exercitam o lado EN do fallback.)
_write_legacy_ptbr_state() {
  # $1 = state-dir. Escreve um state.json minimo com chaves pt-BR legadas.
  mkdir -p "$1"
  cat > "$1/state.json" <<'PTBR'
{
  "schema_version": 1,
  "execucao": {
    "id": "exec-legado-ptbr",
    "projeto_alvo_path": "/tmp/legado",
    "projeto_alvo_descricao": "Projeto legado pt-BR back-compat"
  },
  "etapa_corrente": "clarify",
  "ondas": [{ "id": "onda-042" }],
  "decisoes": [
    {
      "id": "dec-001",
      "contexto": "Decisao legada que evidencia bug via fallback pt-BR"
    }
  ]
}
PTBR
}

scenario_ptbr_legado_reader_fallback() {
  # _ish_get_state le execucao.id / projeto_alvo_descricao / etapa_corrente /
  # ondas[-1].id via fallback; _ish_build_body le decisoes[].contexto via
  # fallback. Todos afloram no body do dry-run.
  _sd="$TMPDIR_TEST/legacy"
  _write_legacy_ptbr_state "$_sd"
  capture "$SCRIPT" create --state-dir "$_sd" --suggestion-id "sug-001" \
    --skill "clarify" \
    --diagnostico "Skill clarify falhou em estado legado pt-BR para validar fallback" \
    --proposta "fix proposta detalhada" \
    --dry-run
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "dry-run pt-BR" "$_CAPTURED_STDERR"; return 1; }
  # execucao.id (fallback) aparece no cabecalho do body
  assert_stdout_contains "exec-legado-ptbr" || return 1
  # projeto_alvo_descricao (fallback) aparece em Projeto-alvo
  assert_stdout_contains "Projeto legado pt-BR back-compat" || return 1
  # etapa_corrente (fallback) aparece em Etapa
  assert_stdout_contains "Etapa: \`clarify\`" || return 1
  # ondas[-1].id (fallback) aparece em Onda
  assert_stdout_contains "Onda: \`onda-042\`" || return 1
  # decisoes[].id + contexto (fallback) afloram nas decisoes relevantes
  assert_stdout_contains "Decisao \`dec-001\`" || return 1
  assert_stdout_contains "Decisao legada que evidencia bug via fallback pt-BR" || return 1
}

run_all_scenarios
