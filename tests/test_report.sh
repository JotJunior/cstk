#!/bin/sh
# test_report.sh — cobre global/skills/agente-00c-runtime/scripts/report.sh.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"
. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/report.sh"
RW="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/state-rw.sh"
ON="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/state-ondas.sh"
DEC="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/state-decisions.sh"

if ! command -v jq >/dev/null 2>&1; then
  printf '# test_report.sh: jq ausente — pulando\n'
  exit 0
fi

_init() {
  capture "$RW" init --state-dir "$1" --execucao-id "exec-rep" \
    --projeto-alvo-path "/tmp/p" --descricao "POC report tests"
}

_run_wave_with_decision() {
  capture "$ON" start --state-dir "$1"
  capture "$DEC" register --state-dir "$1" \
    --agente "${2:-orquestrador-00c}" --etapa "briefing" \
    --contexto "Decisao de teste para popular relatorio de cenario" \
    --opcoes '["A","B"]' --escolha "A" \
    --justificativa "Justificativa de tamanho ok aqui sim para teste"
  capture "$ON" end --state-dir "$1" --motivo-termino etapa_concluida_avancando
}

scenario_generate_inclui_6_secoes() {
  _sd="$TMPDIR_TEST/state"
  _init "$_sd"
  _run_wave_with_decision "$_sd"
  capture "$SCRIPT" generate --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "generate" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "## 1. Resumo Executivo" || return 1
  assert_stdout_contains "## 2. Linha do Tempo" || return 1
  assert_stdout_contains "## 3. Decisoes" || return 1
  assert_stdout_contains "## 4. Bloqueios Humanos" || return 1
  assert_stdout_contains "## 5. Sugestoes para Skills Globais" || return 1
  assert_stdout_contains "## 6. Licoes Aprendidas" || return 1
  assert_stdout_contains "Apendice A" || return 1
}

scenario_generate_renderiza_decisao() {
  _sd="$TMPDIR_TEST/state"
  _init "$_sd"
  _run_wave_with_decision "$_sd"
  capture "$SCRIPT" generate --state-dir "$_sd"
  assert_stdout_contains "dec-001" || return 1
  assert_stdout_contains "**Contexto**" || return 1
  assert_stdout_contains "**Escolha**: A" || return 1
}

scenario_generate_paragrafo_resumo_inserido() {
  _sd="$TMPDIR_TEST/state"
  _init "$_sd"
  _run_wave_with_decision "$_sd"
  capture "$SCRIPT" generate --state-dir "$_sd" \
    --paragrafo-resumo "Sumario customizado da execucao com 1 onda."
  assert_stdout_contains "Sumario customizado da execucao com 1 onda" || return 1
}

scenario_generate_licoes_so_em_final() {
  _sd="$TMPDIR_TEST/state"
  _init "$_sd"
  _run_wave_with_decision "$_sd"
  # Sem --final: placeholder
  capture "$SCRIPT" generate --state-dir "$_sd"
  assert_stdout_contains "Sera preenchido no relatorio final" || return 1
  # Com --final + texto
  capture "$SCRIPT" generate --state-dir "$_sd" --final \
    --licoes-aprendidas "Aprendi muito nessa execucao."
  assert_stdout_contains "Aprendi muito nessa execucao" || return 1
}

scenario_generate_sem_ondas_lista_vazia_explicita() {
  _sd="$TMPDIR_TEST/state"
  _init "$_sd"
  capture "$SCRIPT" generate --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "generate" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "nenhuma onda completa ainda" || return 1
}

scenario_generate_sem_decisoes_explicito() {
  _sd="$TMPDIR_TEST/state"
  _init "$_sd"
  capture "$SCRIPT" generate --state-dir "$_sd"
  assert_stdout_contains "Nenhuma decisao registrada" || return 1
}

scenario_generate_sem_bloqueios_explicito() {
  _sd="$TMPDIR_TEST/state"
  _init "$_sd"
  capture "$SCRIPT" generate --state-dir "$_sd"
  assert_stdout_contains "Nenhum bloqueio humano nesta execucao" || return 1
}

scenario_generate_sem_sugestoes_explicito() {
  _sd="$TMPDIR_TEST/state"
  _init "$_sd"
  capture "$SCRIPT" generate --state-dir "$_sd"
  assert_stdout_contains "Nenhuma sugestao para skills globais nesta execucao" || return 1
}

scenario_validate_completo_exit_0() {
  _sd="$TMPDIR_TEST/state"
  _init "$_sd"
  _run_wave_with_decision "$_sd"
  _rf="$TMPDIR_TEST/report.md"
  capture "$SCRIPT" generate --state-dir "$_sd"
  printf '%s\n' "$_CAPTURED_STDOUT" > "$_rf"
  capture "$SCRIPT" validate --report-file "$_rf"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "validate completo" "$_CAPTURED_STDERR"; return 1; }
}

scenario_validate_incompleto_exit_1() {
  _rf="$TMPDIR_TEST/incomplete.md"
  printf '# Header only\n\n## 1. Resumo Executivo\n\nstub\n' > "$_rf"
  capture "$SCRIPT" validate --report-file "$_rf"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "validate incompleto" "esperado 1"
    return 1
  fi
  assert_stderr_contains "secoes faltando" || return 1
}

scenario_validate_arquivo_inexistente_falha() {
  capture "$SCRIPT" validate --report-file "$TMPDIR_TEST/nope.md"
  if [ "$_CAPTURED_EXIT" = 0 ]; then
    _fail "arquivo inexistente" "esperado != 0"
    return 1
  fi
}

# schema-en-migration: prova que o reader-fallback (.en // .pt) ainda
# renderiza um state.json LEGADO escrito 100% com chaves pt-BR (back-compat).
# As fixtures EN sao cobertas pelos cenarios acima (state-ondas/state-decisions
# ja escrevem EN). Aqui montamos um state pt-BR cru a mao.
scenario_generate_legado_pt_br_via_fallback() {
  _sd="$TMPDIR_TEST/legacy"
  mkdir -p "$_sd"
  cat > "$_sd/state.json" <<'JSON'
{
  "schema_version": 6,
  "execucao": {
    "id": "exec-legado-pt",
    "projeto_alvo_path": "/tmp/legado",
    "projeto_alvo_descricao": "Execucao legada pt-BR",
    "stack_sugerida": "Go + Postgres",
    "status": "concluida",
    "motivo_termino": "pipeline_completa",
    "iniciada_em": "2025-01-01T00:00:00Z",
    "terminada_em": "2025-01-02T00:00:00Z"
  },
  "metricas_acumuladas": {
    "ondas_total": 1,
    "tool_calls_total": 7,
    "decisoes_total": 1,
    "bloqueios_humanos_total": 1,
    "sugestoes_skills_globais_total": 1,
    "issues_toolkit_abertas": 0,
    "profundidade_max_atingida": 1
  },
  "ondas": [
    {
      "id": "onda-001",
      "inicio": "2025-01-01T00:00:00Z",
      "fim": "2025-01-01T01:00:00Z",
      "etapas_executadas": ["briefing"],
      "tool_calls": 7,
      "wallclock_seconds": 3600,
      "motivo_termino": "etapa_concluida_avancando"
    }
  ],
  "decisoes": [
    {
      "id": "dec-001",
      "onda_id": "onda-001",
      "timestamp": "2025-01-01T00:30:00Z",
      "etapa": "briefing",
      "agente": "orquestrador-00c",
      "contexto": "Contexto legado em portugues para a decisao",
      "opcoes_consideradas": ["X", "Y"],
      "escolha": "X",
      "justificativa": "Justificativa legada em portugues aqui",
      "score_justificativa": 3,
      "referencias": ["docs/spec.md"],
      "artefato_originador": "spec.md"
    }
  ],
  "bloqueios_humanos": [
    {
      "id": "blk-001",
      "status": "respondido",
      "disparado_em": "2025-01-01T00:10:00Z",
      "pergunta": "Pergunta legada em portugues?",
      "contexto_para_resposta": "Contexto pt para a resposta",
      "opcoes_recomendadas": ["op1"],
      "resposta_humana": "Resposta humana legada",
      "respondido_em": "2025-01-01T00:20:00Z"
    }
  ],
  "sugestoes": [
    {
      "id": "sug-001",
      "skill_afetada": "briefing",
      "severidade": "impeditiva",
      "diagnostico": "Diagnostico legado em portugues",
      "proposta": "Proposta legada em portugues",
      "issue_aberta": "https://example/issues/1"
    }
  ]
}
JSON
  capture "$SCRIPT" generate --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "generate legado pt" "$_CAPTURED_STDERR"; return 1; }
  # Cabecalho + secao 1 (execucao.*)
  assert_stdout_contains "exec-legado-pt" || return 1
  assert_stdout_contains "/tmp/legado" || return 1
  assert_stdout_contains "Go + Postgres" || return 1
  assert_stdout_contains "pipeline_completa" || return 1
  # Secao 2 (ondas[].*)
  assert_stdout_contains "onda-001" || return 1
  assert_stdout_contains "etapa_concluida_avancando" || return 1
  # Secao 3 (decisoes[].*)
  assert_stdout_contains "Contexto legado em portugues para a decisao" || return 1
  assert_stdout_contains "**Escolha**: X" || return 1
  assert_stdout_contains "Justificativa legada em portugues aqui" || return 1
  assert_stdout_contains "spec.md" || return 1
  # Secao 4 (bloqueios_humanos[].*)
  assert_stdout_contains "Pergunta legada em portugues?" || return 1
  assert_stdout_contains "Resposta humana legada" || return 1
  # Secao 5 (sugestoes[].*)
  assert_stdout_contains "Diagnostico legado em portugues" || return 1
  assert_stdout_contains "Proposta legada em portugues" || return 1
}

# ---------- emit (FR-018): resolve caminho por flavor + secrets-filter interno ----------

scenario_emit_feature00c_grava_arquivo_filtrado() {
  _sd="$TMPDIR_TEST/state"
  _init "$_sd"
  _run_wave_with_decision "$_sd"
  capture "$SCRIPT" emit --flavor feature-00c --short-name demo --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "emit" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "feature-00c-report.md" || return 1   # imprime o caminho gravado
  _out="$_sd/feature-00c-report.md"
  [ -f "$_out" ] || { _fail "emit" "arquivo nao gravado: $_out"; return 1; }
  capture cat "$_out"
  assert_stdout_contains "## 1. Resumo Executivo" || return 1
  assert_stdout_contains "## 5. Sugestoes para Skills Globais" || return 1
  assert_stdout_contains "## 6. Licoes Aprendidas" || return 1
  assert_stdout_contains "Apendice A" || return 1
}

scenario_emit_agente00c_resolve_caminho_pai() {
  # flavor agente-00c grava em <state-dir>/../agente-00c-report.md
  _sd="$TMPDIR_TEST/proj/.claude/agente-00c-state"
  mkdir -p "$_sd"
  _init "$_sd"
  _run_wave_with_decision "$_sd"
  capture "$SCRIPT" emit --flavor agente-00c --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "emit agente" "$_CAPTURED_STDERR"; return 1; }
  [ -f "$TMPDIR_TEST/proj/.claude/agente-00c-report.md" ] \
    || { _fail "emit agente" "relatorio nao gravado no diretorio pai"; return 1; }
}

scenario_emit_exige_flavor() {
  _sd="$TMPDIR_TEST/state"; _init "$_sd"
  assert_exit 2 "$SCRIPT" emit --state-dir "$_sd" || return 1
}

scenario_emit_exige_state_dir() {
  assert_exit 2 "$SCRIPT" emit --flavor feature-00c || return 1
}

scenario_emit_flavor_invalido_rejeitado() {
  _sd="$TMPDIR_TEST/state"; _init "$_sd"
  assert_exit 2 "$SCRIPT" emit --flavor xpto --state-dir "$_sd" || return 1
}

scenario_emit_parcial_sem_licoes_final_com() {
  _sd="$TMPDIR_TEST/state"
  _init "$_sd"
  _run_wave_with_decision "$_sd"
  _out="$_sd/feature-00c-report.md"
  capture "$SCRIPT" emit --flavor feature-00c --state-dir "$_sd" --final \
    --licoes-aprendidas "LICAO_EMIT_FINAL_XYZ"
  capture cat "$_out"
  assert_stdout_contains "LICAO_EMIT_FINAL_XYZ" || return 1
  # parcial (default): NAO repete a licao
  capture "$SCRIPT" emit --flavor feature-00c --state-dir "$_sd"
  capture cat "$_out"
  case "$_CAPTURED_STDOUT" in
    *LICAO_EMIT_FINAL_XYZ*) _fail "emit parcial" "licao apareceu em relatorio parcial"; return 1 ;;
  esac
}

scenario_emit_aplica_secrets_filter_sempre() {
  _sd="$TMPDIR_TEST/state"
  capture "$RW" init --state-dir "$_sd" --execucao-id "exec-emit-sec" \
    --projeto-alvo-path "/tmp/p" --descricao "emit secret scrub"
  capture "$ON" start --state-dir "$_sd"
  capture "$DEC" register --state-dir "$_sd" --agente "orquestrador-00c" --etapa "briefing" \
    --contexto "valor sensivel gho_aB3xK9mZ1qP7rT2vW5yU8nL4jH6dF0sC embutido no contexto da decisao" \
    --opcoes '["A","B"]' --escolha "A" \
    --justificativa "justificativa longa o suficiente para passar o gate de score"
  capture "$ON" end --state-dir "$_sd" --motivo-termino etapa_concluida_avancando
  printf 'CRED=gho_aB3xK9mZ1qP7rT2vW5yU8nL4jH6dF0sC\n' > "$TMPDIR_TEST/.env"
  capture "$SCRIPT" emit --flavor feature-00c --state-dir "$_sd" --env-file "$TMPDIR_TEST/.env"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "emit secret" "$_CAPTURED_STDERR"; return 1; }
  capture cat "$_sd/feature-00c-report.md"
  case "$_CAPTURED_STDOUT" in
    *gho_aB3xK9mZ1qP7rT2vW5yU8nL4jH6dF0sC*) _fail "emit secret" "secret vazou no relatorio gravado"; return 1 ;;
  esac
}

scenario_emit_aborta_sem_secrets_filter() {
  # report.sh e self-contained: isolando-o num dir SEM secrets-filter.sh ao lado,
  # emit deve ABORTAR (nunca gravar relatorio nao-filtrado — vazamento persistente).
  _iso="$TMPDIR_TEST/iso"
  mkdir -p "$_iso"
  cp "$SCRIPT" "$_iso/report.sh"
  _sd="$TMPDIR_TEST/state"
  _init "$_sd"
  _run_wave_with_decision "$_sd"
  _out="$_sd/feature-00c-report.md"
  capture "$_iso/report.sh" emit --flavor feature-00c --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" != 0 ] || { _fail "emit safety" "deveria abortar sem secrets-filter"; return 1; }
  [ -f "$_out" ] && { _fail "emit safety" "gravou relatorio nao-filtrado"; return 1; }
  assert_stderr_contains "secrets-filter" || return 1
}

run_all_scenarios
