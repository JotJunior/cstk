#!/bin/sh
# test_report.sh — cobre plugins/cstk/skills/agente-00c-runtime/scripts/report.sh.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"
. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts/report.sh"
RW="$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts/state-rw.sh"
ON="$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts/state-ondas.sh"
DEC="$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts/state-decisions.sh"
BL="$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts/bloqueios.sh"

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

# Regressao: feature-00c-clarify-answerer grava `references` como array de
# OBJETOS estruturados (ex.: {"fonte":"spec_corrente","fr":"FR-007"}), nao
# array de strings. A secao 3 usava `join(", ")` direto, que so aceita
# strings — falhava com "jq: error ... string ("") and object (...) cannot
# be added" (descoberto em execucao real, onda-012 de skill-converge).
scenario_generate_referencias_objeto_estruturado_nao_quebra() {
  _sd="$TMPDIR_TEST/state"
  _init "$_sd"
  capture "$ON" start --state-dir "$_sd"
  capture "$DEC" register --state-dir "$_sd" \
    --agente "feature-00c-clarify-answerer" --etapa "clarify" \
    --contexto "Decisao com referencias estruturadas (fonte+fr)" \
    --opcoes '["A","B"]' --escolha "A" \
    --justificativa "Justificativa de tamanho ok aqui sim para teste" \
    --referencias '[{"fonte":"spec_corrente","fr":"FR-007"},{"fonte":"constitution","principio":"VI","version":"1.2.0"}]'
  capture "$ON" end --state-dir "$_sd" --motivo-termino etapa_concluida_avancando
  capture "$SCRIPT" generate --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "generate com referencias objeto" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "fonte=spec_corrente fr=FR-007" || return 1
  assert_stdout_contains "fonte=constitution principio=VI version=1.2.0" || return 1
}

# Regressao issue #115: o protocolo clarify-asker/answerer registra
# BloqueioHumano com opcoes ESTRUTURADAS [{rotulo,descricao}] — a secao 4
# assumia array de strings (`map("- " + .)`) e o emit inteiro morria com
# exit 5 ("string and object cannot be added"), zerando o relatorio
# terminal da onda. Os dois formatos sao validos (bloqueios.sh so exige
# array) e devem renderizar.
scenario_generate_opcoes_recomendadas_objeto_nao_quebra() {
  _sd="$TMPDIR_TEST/state"
  _init "$_sd"
  capture "$ON" start --state-dir "$_sd"
  capture "$DEC" register --state-dir "$_sd" \
    --agente "feature-00c-clarify-asker" --etapa "clarify" \
    --contexto "Pergunta Q1 com opcoes estruturadas do protocolo clarify" \
    --opcoes '["A","B"]' --escolha "A" \
    --justificativa "Justificativa de tamanho ok aqui sim para teste"
  capture "$BL" register --state-dir "$_sd" --decisao-id dec-001 \
    --pergunta "Qual conjunto de campos da secao 5 persistir?" \
    --contexto-para-resposta "Contexto para o operador decidir" \
    --opcoes-recomendadas '[{"rotulo":"A","descricao":"Somente nome e papel","default_sugerido":true},{"rotulo":"B","descricao":"Todos os campos"}]'
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "bloqueios register (objeto)" "$_CAPTURED_STDERR"; return 1; }
  capture "$BL" register --state-dir "$_sd" --decisao-id dec-001 \
    --pergunta "Segunda pergunta com opcoes em formato string?" \
    --contexto-para-resposta "Contexto para o operador decidir" \
    --opcoes-recomendadas '["op-string-1","op-string-2"]'
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "bloqueios register (string)" "$_CAPTURED_STDERR"; return 1; }
  capture "$ON" end --state-dir "$_sd" --motivo-termino bloqueio_humano
  capture "$SCRIPT" generate --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "generate com opcoes objeto (issue #115)" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "- (A) Somente nome e papel" || return 1
  assert_stdout_contains "- (B) Todos os campos" || return 1
  assert_stdout_contains "- op-string-1" || return 1
  assert_stdout_contains "- op-string-2" || return 1
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

scenario_generate_tier_linha_default_cloud_public() {
  # FR-008/FR-010 (delivery-tier): init sem --delivery-tier ⇒ estado
  # legado/default; generate() e usado exclusivamente por
  # agente-00c-orchestrator.md, tier sempre aplicavel.
  _sd="$TMPDIR_TEST/state"
  _init "$_sd"
  _run_wave_with_decision "$_sd"
  capture "$SCRIPT" generate --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "generate" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "| Tier de entrega | cloud-public |" || return 1
}

scenario_generate_tier_linha_valor_explicito() {
  _sd="$TMPDIR_TEST/state"
  capture "$RW" init --state-dir "$_sd" --execucao-id "exec-rep-tier" \
    --projeto-alvo-path "/tmp/p" --descricao "POC report tier tests" \
    --delivery-tier local
  _run_wave_with_decision "$_sd"
  capture "$SCRIPT" generate --state-dir "$_sd"
  assert_stdout_contains "| Tier de entrega | local |" || return 1
}

scenario_emit_agente00c_inclui_tier() {
  # dec-011: tier restrito ao flavor agente-00c.
  _sd="$TMPDIR_TEST/proj/.claude/agente-00c-state"
  mkdir -p "$_sd"
  capture "$RW" init --state-dir "$_sd" --execucao-id "exec-rep-tier2" \
    --projeto-alvo-path "/tmp/p" --descricao "POC report tier emit" \
    --delivery-tier cloud-internal
  _run_wave_with_decision "$_sd"
  capture "$SCRIPT" emit --flavor agente-00c --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "emit agente tier" "$_CAPTURED_STDERR"; return 1; }
  capture cat "$TMPDIR_TEST/proj/.claude/agente-00c-report.md"
  assert_stdout_contains "| Tier de entrega | cloud-internal |" || return 1
}

scenario_emit_feature00c_omite_tier() {
  # dec-011: /feature-00c nao pergunta nem le o tier — a linha inteira
  # e omitida (nunca mostra um valor fabricado/fallback fora de escopo).
  _sd="$TMPDIR_TEST/state"
  _init "$_sd"
  _run_wave_with_decision "$_sd"
  capture "$SCRIPT" emit --flavor feature-00c --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "emit feature tier" "$_CAPTURED_STDERR"; return 1; }
  capture cat "$_sd/feature-00c-report.md"
  assert_stdout_not_contains "Tier de entrega" || return 1
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
  # _state-read.sh e dependencia obrigatoria (sourced sibling, FASE 2 lote
  # 2.6) — o cenario testa a ausencia do secrets-filter, nao do helper.
  cp "$(dirname "$SCRIPT")/_state-read.sh" "$_iso/_state-read.sh"
  _sd="$TMPDIR_TEST/state"
  _init "$_sd"
  _run_wave_with_decision "$_sd"
  _out="$_sd/feature-00c-report.md"
  capture "$_iso/report.sh" emit --flavor feature-00c --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" != 0 ] || { _fail "emit safety" "deveria abortar sem secrets-filter"; return 1; }
  [ -f "$_out" ] && { _fail "emit safety" "gravou relatorio nao-filtrado"; return 1; }
  assert_stderr_contains "secrets-filter" || return 1
}

# ---------- Secoes 1/2 estendidas com consumo de subagente (FASE 4.2 de
# wave-token-metrics, contracts/wave-usage-report.md §6) ----------

scenario_generate_secao1_spawns_tokens_quando_coletado() {
  _sd="$TMPDIR_TEST/state"
  _init "$_sd"
  _run_wave_with_decision "$_sd"
  # injeta agent_usage na onda-001 (equivalente ao que state-ondas.sh end
  # gravaria a partir do sidecar do hook posttooluse-agent-usage.sh)
  capture jq '.waves[0].agent_usage = {"spawns_total":3,"spawns_with_usage":2,"spawns_unavailable":1,"total_tokens":254000,"input_tokens":4,"output_tokens":1975,"cache_read_input_tokens":250900,"cache_creation_input_tokens":1049,"tool_use_count":72,"duration_ms":923000}' "$_sd/state.json"
  printf '%s' "$_CAPTURED_STDOUT" > "$_sd/state.json.tmp" && mv "$_sd/state.json.tmp" "$_sd/state.json"
  capture "$SCRIPT" generate --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "generate" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "| Spawns de subagente | 3 (2 com uso; 1 indisponiveis) |" || return 1
  assert_stdout_contains "| Tokens totais (observados) | 254.0k |" || return 1
  assert_stdout_contains "| Cobertura da metrica | 66.6% |" || return 1
  # secao 2: colunas novas + linha da onda-001 com dado real
  assert_stdout_contains "| Onda | Inicio | Fim | Etapas | Tool calls | Wallclock | Spawns | Tokens | Termino |" || return 1
  assert_stdout_contains "| onda-001 |" || return 1
  case "$_CAPTURED_STDOUT" in
    *"3 (2 c/uso) | 254.0k"*) : ;;
    *) _fail "generate secao2" "linha da onda sem spawns/tokens esperados"; return 1 ;;
  esac
}

scenario_generate_distingue_zero_spawns_de_nao_coletado() {
  # SC-004/FR-009 (Principio VI): "0 spawns" (dado real observado) e
  # "metrica nao coletada" (hook nunca provisionado/nenhum spawn tentado)
  # sao estados DIFERENTES e nao podem ser confundidos.
  #
  # Aqui simulamos o segundo caso: wave-usage-report.sh roda com sucesso,
  # mas nenhuma onda tem agent_usage != null (metric_collected=false) ->
  # secao 1 MUST dizer "nao coletado", NUNCA fabricar "0".
  _sd="$TMPDIR_TEST/state"
  _init "$_sd"
  _run_wave_with_decision "$_sd"
  capture "$SCRIPT" generate --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "generate" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "| Spawns de subagente | nao coletado nesta execucao |" || return 1
  assert_stdout_contains "| Tokens totais (observados) | nao coletado nesta execucao |" || return 1
  assert_stdout_contains "| Cobertura da metrica | nao coletado nesta execucao |" || return 1
  # secao 2: onda sem agent_usage -> "indisponivel", nunca "0"
  assert_stdout_contains "indisponivel | indisponivel | etapa_concluida_avancando |" || return 1
}

scenario_generate_wave_usage_report_ausente_degrada_graciosamente() {
  # Defesa em profundidade: se wave-usage-report.sh nao esta ao lado de
  # report.sh (skill parcialmente instalada), generate NUNCA aborta —
  # degrada para "nao coletado nesta execucao" (nunca 0 fabricado).
  _iso="$TMPDIR_TEST/iso-wu"
  mkdir -p "$_iso"
  cp "$SCRIPT" "$_iso/report.sh"
  # _state-read.sh e dependencia obrigatoria (sourced sibling, FASE 2 lote
  # 2.6) — o cenario testa a ausencia do wave-usage-report, nao do helper.
  cp "$(dirname "$SCRIPT")/_state-read.sh" "$_iso/_state-read.sh"
  _sd="$TMPDIR_TEST/state"
  _init "$_sd"
  _run_wave_with_decision "$_sd"
  capture "$_iso/report.sh" generate --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "generate sem wave-usage-report" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "| Spawns de subagente | nao coletado nesta execucao |" || return 1
  assert_stdout_contains "## 2. Linha do Tempo" || return 1
}

scenario_stack_final_condicional_ao_status() {
  # Regressao: 'Stack final' nao pode afirmar 'abortada' numa execucao
  # concluida sem suggested_stack (caso feature-00c, herda stack do projeto).
  _sd="$TMPDIR_TEST/state"
  _init "$_sd"
  _run_wave_with_decision "$_sd"
  capture "$RW" set --state-dir "$_sd" --field '.execution.status' --value '"concluida"'
  capture "$SCRIPT" generate --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "generate" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_not_contains "abortada antes de definir" || return 1
  assert_stdout_contains "herdada do projeto" || return 1
}

# ==== backend sqlite (fix pos-6.2.1): report NAO pode mascarar falha ====
# Bug de campo (meta-gob-ms, abort de document-templates): com state.db o
# emit reclamava "state.json ausente" e NENHUM relatorio era gerado.

scenario_generate_backend_sqlite_produz_relatorio() {
  command -v sqlite3 >/dev/null 2>&1 || { printf '# skip: sqlite3 indisponivel\n'; return 0; }
  _h="$TMPDIR_TEST/home-rpsq"
  mkdir -p "$_h/.claude/cstk"
  printf 'state_backend=sqlite\n' > "$_h/.claude/cstk/config"
  _sd="$TMPDIR_TEST/rpsq-state"
  env HOME="$_h" sh "$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts/state-rw.sh" init \
    --state-dir "$_sd" --execucao-id "exec-rpsq-1" --projeto-alvo-path "/tmp/rpsq" \
    --descricao "descricao de teste com tamanho suficiente para validacao" >/dev/null 2>&1 \
    || { _error "fixture" "init sqlite falhou"; return 2; }
  [ -f "$_sd/state.db" ] || { _error "fixture" "state.db nao criado"; return 2; }
  [ ! -f "$_sd/state.json" ] || { _error "fixture" "state.json presente — cenario invalido"; return 2; }

  capture env HOME="$_h" "$SCRIPT" generate --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "generate sqlite exit" "esperado 0, obtido $_CAPTURED_EXIT: $_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "Relatorio do Agente-00C" || return 1
  assert_stdout_contains "exec-rpsq-1" || return 1
}

# ==== exit 7 contratual por estado ausente (state-db-runtime-parity FR-008) ====
# Contrato: contracts/runtime-interfaces.md §3 + cli-invocation.md do
# feature-00c ("falha na geracao do relatorio: exit 7 + estado preservado").
# state-dir sem state.json E sem state.db => exit 7 nos DOIS subcomandos,
# sob os DOIS backends configurados (a resolucao por presenca de state.db
# no dir garante o mesmo veredito independente da config global).

scenario_generate_estado_ausente_exit_7_backend_json() {
  _sd="$TMPDIR_TEST/ausente-gen-json"
  mkdir -p "$_sd"
  capture "$SCRIPT" generate --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 7 ] || { _fail "exit" "esperado 7, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "estado ausente" || return 1
}

scenario_emit_estado_ausente_exit_7_backend_json() {
  _sd="$TMPDIR_TEST/ausente-emit-json"
  mkdir -p "$_sd"
  capture "$SCRIPT" emit --flavor feature-00c --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 7 ] || { _fail "exit" "esperado 7, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "estado ausente" || return 1
}

scenario_generate_estado_ausente_exit_7_backend_sqlite_config() {
  _h="$TMPDIR_TEST/home-aus-sq"
  mkdir -p "$_h/.claude/cstk"
  printf 'state_backend=sqlite\n' > "$_h/.claude/cstk/config"
  _sd="$TMPDIR_TEST/ausente-gen-sq"
  mkdir -p "$_sd"
  capture env HOME="$_h" "$SCRIPT" generate --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 7 ] || { _fail "exit" "esperado 7, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "estado ausente" || return 1
}

scenario_emit_estado_ausente_exit_7_backend_sqlite_config() {
  _h="$TMPDIR_TEST/home-aus-sq2"
  mkdir -p "$_h/.claude/cstk"
  printf 'state_backend=sqlite\n' > "$_h/.claude/cstk/config"
  _sd="$TMPDIR_TEST/ausente-emit-sq"
  mkdir -p "$_sd"
  capture env HOME="$_h" "$SCRIPT" emit --flavor agente-00c --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 7 ] || { _fail "exit" "esperado 7, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "estado ausente" || return 1
}

scenario_generate_estado_ausente_preserva_state_dir() {
  # "estado preservado": a morte por exit 7 nao pode criar/remover nada
  # dentro do state-dir (anti-mirror FR-003 + contrato "estado preservado").
  _sd="$TMPDIR_TEST/ausente-preserva"
  mkdir -p "$_sd/backups"
  : > "$_sd/backups/wave-001.json"
  capture "$SCRIPT" generate --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 7 ] || { _fail "exit" "esperado 7, obtido $_CAPTURED_EXIT"; return 1; }
  [ -f "$_sd/backups/wave-001.json" ] || { _fail "preservacao" "conteudo previo do state-dir sumiu"; return 1; }
  _n=$(find "$_sd" -type f | wc -l | tr -d ' ')
  [ "$_n" = 1 ] || { _fail "anti-mirror" "arquivos inesperados criados no state-dir ($_n)"; return 1; }
}

scenario_usage_exit_2_preservado_pos_fr008() {
  # CHK010: exit 2 (uso) nao pode ter sido absorvido pelo 7
  capture "$SCRIPT" generate
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit" "esperado 2, obtido $_CAPTURED_EXIT"; return 1; }
  capture "$SCRIPT" emit --flavor feature-00c
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit" "esperado 2, obtido $_CAPTURED_EXIT"; return 1; }
}

# ==== Secao roadmap (opcional, task 5.4, FR-004 roadmap-mode) ====

_write_roadmap_fixture() {
  # $1 = diretorio docs/ do projeto-alvo; $2 = numero de entradas (1 ou 2)
  mkdir -p "$1"
  if [ "$2" = 1 ]; then
    cat > "$1/roadmap.md" <<'EOF'
# Roadmap: projeto-teste

**Gerado por**: /agente-00c (modo roadmap)
**Atualizado em**: 2026-08-14

Contexto curto.

## Ordem sugerida

| # | Feature | Depende de | Descricao (resumo) |
|---|---------|------------|--------------------|
| 1 | `auth-basica` | - | Autenticacao de usuario |

## Features

### 1. auth-basica

- **short-name**: `auth-basica`
- **ordem**: 1
- **depende-de**: -

**Descricao**: Autenticacao de usuario via login/senha.

**Justificativa**: Pre-requisito para as demais features.
EOF
  else
    cat > "$1/roadmap.md" <<'EOF'
# Roadmap: projeto-teste

**Gerado por**: /agente-00c (modo roadmap)
**Atualizado em**: 2026-08-14

Contexto curto.

## Ordem sugerida

| # | Feature | Depende de | Descricao (resumo) |
|---|---------|------------|--------------------|
| 1 | `auth-basica` | - | Autenticacao de usuario |
| 2 | `perfil-usuario` | `auth-basica` | Edicao de perfil |

## Features

### 1. auth-basica

- **short-name**: `auth-basica`
- **ordem**: 1
- **depende-de**: -

**Descricao**: Autenticacao de usuario via login/senha.

**Justificativa**: Pre-requisito para as demais features.

### 2. perfil-usuario

- **short-name**: `perfil-usuario`
- **ordem**: 2
- **depende-de**: `auth-basica`

**Descricao**: Edicao de dados de perfil.

**Justificativa**: Segunda feature natural apos auth.
EOF
  fi
}

scenario_generate_sem_roadmap_mode_nao_emite_secao() {
  _sd="$TMPDIR_TEST/state-rm-off"
  _init "$_sd"
  _run_wave_with_decision "$_sd"
  capture "$SCRIPT" generate --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "generate" "$_CAPTURED_STDERR"; return 1; }
  if printf '%s' "$_CAPTURED_STDOUT" | grep -q '## Roadmap'; then
    _fail "secao roadmap NAO deveria aparecer com modo desabilitado" "" ; return 1
  fi
}

scenario_generate_roadmap_mode_sem_artefato_emite_placeholder() {
  _sd="$TMPDIR_TEST/state-rm-noartifact"
  _pap="$TMPDIR_TEST/proj-noartifact"
  mkdir -p "$_pap"
  capture "$RW" init --state-dir "$_sd" --execucao-id "exec-rm-1" \
    --projeto-alvo-path "$_pap" --descricao "POC roadmap sem artefato" \
    --roadmap-mode true
  _run_wave_with_decision "$_sd"
  capture "$SCRIPT" generate --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "generate" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "## Roadmap (modo roadmap" || return 1
  assert_stdout_contains "ainda nao foi escrito" || return 1
}

scenario_generate_roadmap_mode_com_artefato_emite_tabela_e_untrusted() {
  _sd="$TMPDIR_TEST/state-rm-2entries"
  _pap="$TMPDIR_TEST/proj-2entries"
  mkdir -p "$_pap/docs"
  _write_roadmap_fixture "$_pap/docs" 2
  capture "$RW" init --state-dir "$_sd" --execucao-id "exec-rm-2" \
    --projeto-alvo-path "$_pap" --descricao "POC roadmap com 2 entradas" \
    --roadmap-mode true
  _run_wave_with_decision "$_sd"
  capture "$SCRIPT" generate --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "generate" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "## Roadmap (modo roadmap" || return 1
  assert_stdout_contains "DADO produzido pelo" || return 1
  assert_stdout_contains "## Ordem sugerida" || return 1
  assert_stdout_contains "auth-basica" || return 1
  assert_stdout_contains "perfil-usuario" || return 1
  # 2 entradas -> NAO deve emitir a sugestao de entrada unica
  if printf '%s' "$_CAPTURED_STDOUT" | grep -q 'roadmap com uma unica entrada'; then
    _fail "sugestao de entrada unica NAO deveria aparecer com 2 entradas" ""; return 1
  fi
}

scenario_generate_roadmap_mode_entrada_unica_sugere_pipeline_completa() {
  _sd="$TMPDIR_TEST/state-rm-1entry"
  _pap="$TMPDIR_TEST/proj-1entry"
  mkdir -p "$_pap/docs"
  _write_roadmap_fixture "$_pap/docs" 1
  capture "$RW" init --state-dir "$_sd" --execucao-id "exec-rm-3" \
    --projeto-alvo-path "$_pap" --descricao "POC roadmap com 1 entrada" \
    --roadmap-mode true
  _run_wave_with_decision "$_sd"
  capture "$SCRIPT" generate --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "generate" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "roadmap com uma unica entrada" || return 1
  assert_stdout_contains "pipeline completa" || return 1
}

scenario_validate_ignora_secao_roadmap_extra() {
  # A secao roadmap e OPCIONAL (nao uma das 6 fixas) — validate() so
  # checa presenca das 6 obrigatorias, nao rejeita secoes extras.
  _sd="$TMPDIR_TEST/state-rm-validate"
  _pap="$TMPDIR_TEST/proj-validate"
  mkdir -p "$_pap/docs"
  _write_roadmap_fixture "$_pap/docs" 2
  capture "$RW" init --state-dir "$_sd" --execucao-id "exec-rm-4" \
    --projeto-alvo-path "$_pap" --descricao "POC roadmap validate" \
    --roadmap-mode true
  _run_wave_with_decision "$_sd"
  capture "$SCRIPT" generate --state-dir "$_sd"
  _rf="$TMPDIR_TEST/relatorio-rm.md"
  printf '%s' "$_CAPTURED_STDOUT" > "$_rf"
  capture "$SCRIPT" validate --report-file "$_rf"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "validate deveria passar com secao extra" "$_CAPTURED_STDERR"; return 1; }
}

scenario_generate_roadmap_mode_deriva_entradas_obsoletas() {
  _sd="$TMPDIR_TEST/state-rm-obsolete"
  _pap="$TMPDIR_TEST/proj-obsolete"
  mkdir -p "$_pap/docs"
  cat > "$_pap/docs/roadmap.md" <<'EOF'
# Roadmap: projeto-teste

**Gerado por**: /agente-00c (modo roadmap)
**Atualizado em**: 2026-08-14

Contexto curto.

## Ordem sugerida

| # | Feature | Depende de | Descricao (resumo) |
|---|---------|------------|--------------------|
| 1 | `auth-basica` | - | Autenticacao de usuario |
| 2 | `legado-x` | - | Feature descontinuada |

## Features

### 1. auth-basica

- **short-name**: `auth-basica`
- **ordem**: 1
- **depende-de**: -

**Descricao**: Autenticacao de usuario via login/senha.

**Justificativa**: Pre-requisito para as demais features.

### 2. legado-x

- **short-name**: `legado-x`
- **ordem**: 2
- **depende-de**: -
- **marcada-obsoleta**: substituida por auth-basica

**Descricao**: Feature descontinuada.

**Justificativa**: Nao se aplica mais.
EOF
  capture "$RW" init --state-dir "$_sd" --execucao-id "exec-rm-5" \
    --projeto-alvo-path "$_pap" --descricao "POC roadmap obsoleta" \
    --roadmap-mode true
  _run_wave_with_decision "$_sd"
  capture "$SCRIPT" generate --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "generate" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "### Entradas marcadas obsoletas" || return 1
  assert_stdout_contains "legado-x" || return 1
  assert_stdout_contains "substituida por auth-basica" || return 1
}

# ==== issue #141: Decisao com opcoes estruturadas {rotulo, descricao} ====
# O clarify autonomo emite opcoes_recomendadas como objetos e a prosa do
# orquestrador as passa verbatim em --opcoes; `join` sobre objeto quebrava o
# generate inteiro (exit 5, .md truncado sem secoes 4/5/6, validate exit 1).
scenario_issue141_generate_com_opcoes_objeto_rende_6_secoes() {
  _sd="$TMPDIR_TEST/state-141"
  _init "$_sd"
  capture "$ON" start --state-dir "$_sd"
  capture "$DEC" register --state-dir "$_sd" \
    --agente "clarify-answerer" --etapa "clarify" \
    --contexto "Pergunta de clarify com opcoes estruturadas do asker" \
    --opcoes '[{"rotulo":"A","descricao":"Comando slash no canal","default_sugerido":true},{"rotulo":"B","descricao":"Mention na thread"},"C-string-solta"]' \
    --escolha "A" \
    --justificativa "Justificativa de tamanho ok aqui sim para teste" --score 2
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "register com opcoes-objeto deveria passar" "$_CAPTURED_STDERR"; return 1; }
  capture "$ON" end --state-dir "$_sd" --motivo-termino etapa_concluida_avancando

  capture "$SCRIPT" generate --state-dir "$_sd" --paragrafo-resumo "x"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "generate exit" "esperado 0, obtido $_CAPTURED_EXIT; $_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "**Opcoes consideradas**: (A) Comando slash no canal / (B) Mention na thread / C-string-solta" || return 1
  for _h in "## 4. Bloqueios Humanos" "## 5. Sugestoes para Skills Globais" "## 6. Licoes Aprendidas"; do
    assert_stdout_contains "$_h" || return 1
  done
  # validate sobre o artefato gravado tambem passa.
  _out="$TMPDIR_TEST/out-141.md"
  printf '%s\n' "$_CAPTURED_STDOUT" > "$_out"
  capture "$SCRIPT" validate --report-file "$_out"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "validate" "esperado 0, obtido $_CAPTURED_EXIT; $_CAPTURED_STDERR"; return 1; }
}

# O emit propaga falha do render (nao e pipe): contrato que a prosa do
# orquestrador passa a usar em vez de `generate | scrub > arquivo`.
scenario_issue141_emit_agente_00c_grava_relatorio_completo() {
  _sd="$TMPDIR_TEST/pap-141/.claude/agente-00c-state"
  mkdir -p "$_sd"
  _init "$_sd"
  capture "$ON" start --state-dir "$_sd"
  capture "$DEC" register --state-dir "$_sd" \
    --agente "clarify-answerer" --etapa "clarify" \
    --contexto "Pergunta de clarify com opcoes estruturadas do asker" \
    --opcoes '[{"rotulo":"A","descricao":"opcao A"}]' --escolha "A" \
    --justificativa "Justificativa de tamanho ok aqui sim para teste" --score 2
  capture "$ON" end --state-dir "$_sd" --motivo-termino etapa_concluida_avancando
  capture "$SCRIPT" emit --flavor agente-00c --state-dir "$_sd" --paragrafo-resumo "x"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "emit exit" "esperado 0, obtido $_CAPTURED_EXIT; $_CAPTURED_STDERR"; return 1; }
  [ -f "$TMPDIR_TEST/pap-141/.claude/agente-00c-report.md" ] || { _fail "relatorio nao gravado em <SD>/../agente-00c-report.md" ""; return 1; }
  capture "$SCRIPT" validate --report-file "$TMPDIR_TEST/pap-141/.claude/agente-00c-report.md"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "validate" "$_CAPTURED_STDERR"; return 1; }
}

# ==== issue #144: Decisao invalidada via mark-invalid aparece como INVALIDADA ====
scenario_issue144_generate_marca_decisao_invalidada() {
  _sd="$TMPDIR_TEST/state-144"
  _init "$_sd"
  _run_wave_with_decision "$_sd"
  capture "$DEC" mark-invalid --state-dir "$_sd" --decisao-id dec-001 \
    --motivo "decisao registrada com a escolha errada por engano"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "mark-invalid" "$_CAPTURED_STDERR"; return 1; }
  capture "$SCRIPT" generate --state-dir "$_sd" --paragrafo-resumo "x"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "generate" "$_CAPTURED_STDERR"; return 1; }
  printf '%s\n' "$_CAPTURED_STDOUT" | grep -q '^#### dec-001 — .* — \*\*INVALIDADA por dec-002\*\*$' \
    || { _fail "heading da original" "$(printf '%s\n' "$_CAPTURED_STDOUT" | grep '^#### dec-001')"; return 1; }
  assert_stdout_contains "> **INVALIDADA** por dec-002" || return 1
  assert_stdout_contains "motivo: decisao registrada com a escolha errada por engano" || return 1
  # A invalidacao em si e uma Decisao normal (nao marcada como invalidada).
  printf '%s\n' "$_CAPTURED_STDOUT" | grep -q '^#### dec-002 — .*INVALIDADA' \
    && { _fail "dec-002 nao deveria aparecer como invalidada" ""; return 1; }
  assert_stdout_contains "**Escolha**: invalidar-dec-001" || return 1
  # Relatorio segue completo.
  assert_stdout_contains "## 6. Licoes Aprendidas" || return 1
}

run_all_scenarios
