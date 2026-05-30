#!/bin/sh
# test_state-validate.sh — cobre global/skills/agente-00c-runtime/scripts/state-validate.sh.
#
# Cada cenario monta um state.json sintetico via jq e roda o validador.
# Estado valido = exit 0; cada tipo de violacao = exit 1 com mensagem
# especifica em stderr.
#
# Schema EN (schema-en-migration): _make_valid_state usa `state-rw init`, que
# grava chaves EN no disco. _patch_state aplica jq cru (sem canonicalizer), logo
# os patches miram chaves EN. Os cenarios *_pt_fallback_* montam um state 100%
# pt-BR (via jq cru, sem passar por state-rw) e provam que o validador ainda le
# via fallback (.en // .pt) — regressao de back-compat.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/state-validate.sh"
RW="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/state-rw.sh"

if ! command -v jq >/dev/null 2>&1; then
  printf '# test_state-validate.sh: jq ausente — pulando suite\n'
  exit 0
fi

# ==== helpers ====

# _make_valid_state DIR -> cria state.json valido em DIR via state-rw init
_make_valid_state() {
  capture "$RW" init --state-dir "$1" \
    --execucao-id "exec-test-001" \
    --projeto-alvo-path "/tmp/poc-test" \
    --descricao "POC de teste (>=10 chars)"
}

# _patch_state DIR JQ-EXPR -> aplica patch via jq + grava (sem validacao do RW)
_patch_state() {
  _ps_dir=$1
  _ps_expr=$2
  _ps_file="$_ps_dir/state.json"
  _ps_tmp=$(mktemp)
  jq "$_ps_expr" "$_ps_file" > "$_ps_tmp"
  mv "$_ps_tmp" "$_ps_file"
}

# ==== Scenarios ====

scenario_estado_valido_exit_zero() {
  _sd="$TMPDIR_TEST/state"
  _make_valid_state "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "init" "$_CAPTURED_STDERR"; return 1; }
  capture "$SCRIPT" --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "validate exit" "esperado 0, obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"
    return 1
  fi
}

scenario_state_ausente_exit_um() {
  _sd="$TMPDIR_TEST/empty"
  mkdir -p "$_sd"
  capture "$SCRIPT" --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "validate sem state.json" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "state.json nao existe" || return 1
}

scenario_json_invalido_exit_um() {
  _sd="$TMPDIR_TEST/state"
  mkdir -p "$_sd"
  printf 'not-json\n' > "$_sd/state.json"
  capture "$SCRIPT" --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "validate json invalido" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "nao e JSON parseavel" || return 1
}

scenario_schema_version_desconhecido_falha() {
  _sd="$TMPDIR_TEST/state"
  _make_valid_state "$_sd"
  _patch_state "$_sd" '.schema_version = "9.9.9"'
  capture "$SCRIPT" --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "schema_version desconhecido" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "schema_version desconhecido" || return 1
}

scenario_profundidade_acima_de_3_falha() {
  _sd="$TMPDIR_TEST/state"
  _make_valid_state "$_sd"
  _patch_state "$_sd" '.budgets.current_subagent_depth = 4'
  capture "$SCRIPT" --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "profundidade > 3" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "FR-013" || return 1
  assert_stderr_contains "max 3 niveis" || return 1
}

scenario_ciclos_acima_de_5_falha() {
  _sd="$TMPDIR_TEST/state"
  _make_valid_state "$_sd"
  _patch_state "$_sd" '.budgets.cycles_consumed_current_stage = 6'
  capture "$SCRIPT" --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "ciclos > 5" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "FR-014.a" || return 1
}

scenario_retros_acima_de_2_falha() {
  _sd="$TMPDIR_TEST/state"
  _make_valid_state "$_sd"
  _patch_state "$_sd" '.budgets.retro_executions_consumed = 3'
  capture "$SCRIPT" --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "retros > 2" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "FR-006" || return 1
}

scenario_status_terminal_sem_finished_at_falha() {
  _sd="$TMPDIR_TEST/state"
  _make_valid_state "$_sd"
  _patch_state "$_sd" '.execution.status = "abortada"'
  capture "$SCRIPT" --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "abortada sem finished_at" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "terminal" || return 1
  assert_stderr_contains "finished_at e null" || return 1
}

scenario_status_em_andamento_com_finished_at_falha() {
  _sd="$TMPDIR_TEST/state"
  _make_valid_state "$_sd"
  _patch_state "$_sd" '.execution.finished_at = "2026-05-05T15:00:00Z"'
  capture "$SCRIPT" --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "em_andamento com finished_at" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "finished_at preenchido" || return 1
}

scenario_decisao_sem_5_campos_falha_com_id() {
  _sd="$TMPDIR_TEST/state"
  _make_valid_state "$_sd"
  # Adiciona decisao com campo "rationale" vazio (viola Principio I). Chaves EN.
  _patch_state "$_sd" '
    .decisions = [{
      "id": "dec-001",
      "wave_id": "onda-001",
      "timestamp": "2026-05-05T14:30:00Z",
      "stage": "briefing",
      "agent": "orquestrador-00c",
      "context": "contexto valido com mais de 20 chars",
      "options_considered": ["A","B"],
      "choice": "A",
      "rationale": ""
    }]
  '
  capture "$SCRIPT" --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "decisao incompleta" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "Decisao dec-001 viola Principio I" || return 1
}

scenario_bloqueio_referencia_decisao_inexistente_falha() {
  _sd="$TMPDIR_TEST/state"
  _make_valid_state "$_sd"
  _patch_state "$_sd" '
    .human_blocks = [{
      "id": "block-001",
      "decision_id": "dec-fantasma",
      "question": "x",
      "context_for_answer": "y",
      "status": "aguardando",
      "triggered_at": "2026-05-05T14:31:00Z"
    }]
  '
  capture "$SCRIPT" --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "bloqueio orfao" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "BloqueioHumano block-001 referencia decision_id inexistente" || return 1
}

scenario_whitelist_com_string_vazia_falha() {
  _sd="$TMPDIR_TEST/state"
  _make_valid_state "$_sd"
  _patch_state "$_sd" '.external_urls_whitelist = ["https://valido.example/**", ""]'
  capture "$SCRIPT" --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "whitelist vazia" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "external_urls_whitelist contem entrada" || return 1
}

scenario_campo_obrigatorio_ausente_falha() {
  _sd="$TMPDIR_TEST/state"
  _make_valid_state "$_sd"
  _patch_state "$_sd" 'del(.next_instruction)'
  capture "$SCRIPT" --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "campo ausente" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "next_instruction" || return 1
}

# ==== Cenarios para FR-CACHE-017 ====
#
# Schema EN (schema-en-migration §3.9d): o payload de cache canonico usa chaves
# EN (summary/summary_chars/strategy/generated_at/generated_in_wave); os patches
# miram a folha EN e os asserts batem a mensagem EN. O par coordenado e
# state-cache.sh (writer). O VALOR de strategy (resumo) NAO muda (follow-up B).
# Os cenarios *_pt_fallback_* abaixo provam que o reader ainda valida cache
# 100% pt-BR via fallback (.en // .pt).

# _cache_valid_payload imprime um cache valido (chaves EN) em stdout (JSON object)
_cache_valid_payload() {
  cat <<'EOF'
{
  "source_path": "/tmp/briefing.md",
  "source_sha256": "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789",
  "source_chars": 5000,
  "summary": "## H2\nlinha\n",
  "summary_chars": 18,
  "strategy": "resumo",
  "generated_at": "2026-05-21T01:00:00Z",
  "generated_in_wave": 1
}
EOF
}

# _cache_valid_payload_pt imprime um cache valido com chaves pt-BR (folhas
# legadas §3.9d). Usado para provar o fallback do reader.
_cache_valid_payload_pt() {
  cat <<'EOF'
{
  "source_path": "/tmp/briefing.md",
  "source_sha256": "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789",
  "source_chars": 5000,
  "resumo": "## H2\nlinha\n",
  "resumo_chars": 18,
  "estrategia": "resumo",
  "gerado_em": "2026-05-21T01:00:00Z",
  "gerado_na_onda": 1
}
EOF
}

scenario_cache_valido_passa() {
  _sd="$TMPDIR_TEST/state"
  _make_valid_state "$_sd"
  _payload=$(_cache_valid_payload)
  _patch_state "$_sd" ".briefing_cache = $_payload"
  capture "$SCRIPT" --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "cache valido" "esperado 0, obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"
    return 1
  fi
}

scenario_cache_sha256_invalido_falha() {
  _sd="$TMPDIR_TEST/state"
  _make_valid_state "$_sd"
  _payload=$(_cache_valid_payload)
  _patch_state "$_sd" ".briefing_cache = $_payload | .briefing_cache.source_sha256 = \"abc\""
  capture "$SCRIPT" --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "sha256 invalido" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "source_sha256" || return 1
}

scenario_cache_strategy_invalida_falha() {
  _sd="$TMPDIR_TEST/state"
  _make_valid_state "$_sd"
  _payload=$(_cache_valid_payload)
  _patch_state "$_sd" ".briefing_cache = $_payload | .briefing_cache.strategy = \"foo\""
  capture "$SCRIPT" --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "strategy invalida" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "strategy invalido" || return 1
}

scenario_cache_summary_maior_que_source_falha() {
  _sd="$TMPDIR_TEST/state"
  _make_valid_state "$_sd"
  _payload=$(_cache_valid_payload)
  _patch_state "$_sd" ".briefing_cache = $_payload | .briefing_cache.summary_chars = 99999"
  capture "$SCRIPT" --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "summary > source" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "summary_chars" || return 1
}

scenario_cache_generated_at_invalido_falha() {
  _sd="$TMPDIR_TEST/state"
  _make_valid_state "$_sd"
  _payload=$(_cache_valid_payload)
  _patch_state "$_sd" ".briefing_cache = $_payload | .briefing_cache.generated_at = \"ontem\""
  capture "$SCRIPT" --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "generated_at invalido" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "generated_at" || return 1
}

scenario_cache_generated_in_wave_zero_falha() {
  _sd="$TMPDIR_TEST/state"
  _make_valid_state "$_sd"
  _payload=$(_cache_valid_payload)
  _patch_state "$_sd" ".briefing_cache = $_payload | .briefing_cache.generated_in_wave = 0"
  capture "$SCRIPT" --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "generated_in_wave=0" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "generated_in_wave" || return 1
}

scenario_cache_ausente_eh_valido() {
  # state.json sem campos de cache (caso legado) deve passar
  _sd="$TMPDIR_TEST/state"
  _make_valid_state "$_sd"
  capture "$SCRIPT" --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "cache ausente deve passar (campos opcionais)" "esperado 0, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_constitution_cache_validado_independente() {
  _sd="$TMPDIR_TEST/state"
  _make_valid_state "$_sd"
  _payload=$(_cache_valid_payload)
  _patch_state "$_sd" ".constitution_cache = $_payload | .constitution_cache.strategy = \"bar\""
  capture "$SCRIPT" --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "constitution_cache invalido" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "constitution_cache.strategy" || return 1
}

# --- Back-compat das folhas de cache pt-BR (§3.9d) via fallback ---

scenario_cache_pt_fallback_valido_passa() {
  # Cache 100% pt-BR (resumo_chars/estrategia/gerado_em/gerado_na_onda) deve
  # validar via fallback (.en // .pt) do reader. Regressao de back-compat.
  _sd="$TMPDIR_TEST/state"
  _make_valid_state "$_sd"
  _payload=$(_cache_valid_payload_pt)
  _patch_state "$_sd" ".briefing_cache = $_payload"
  capture "$SCRIPT" --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "cache pt-BR valido via fallback" "esperado 0, obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"
    return 1
  fi
}

scenario_cache_pt_fallback_violacao_pega() {
  # Mesmo lendo a folha pt-BR (gerado_na_onda) via fallback, a invariante deve
  # ser pega (fallback NAO e pass-through silencioso). Mensagem ja e EN.
  _sd="$TMPDIR_TEST/state"
  _make_valid_state "$_sd"
  _payload=$(_cache_valid_payload_pt)
  _patch_state "$_sd" ".briefing_cache = $_payload | .briefing_cache.gerado_na_onda = 0"
  capture "$SCRIPT" --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "cache pt-BR violacao via fallback" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "generated_in_wave" || return 1
}

# ==== Cenarios de back-compat: state 100% pt-BR via fallback (.en // .pt) ====
#
# Estes provam que o validador (READ-ONLY) ainda le states pt-BR vivos sem
# passar pelo canonicalizer de state-rw. Escrevem state.json com chaves pt-BR
# direto no disco (NAO usam _make_valid_state, que canonicaliza via state-rw).

# _write_pt_state DIR -> grava um state.json valido 100% pt-BR (schema legado).
_write_pt_state() {
  mkdir -p -- "$1"
  cat > "$1/state.json" <<'EOF'
{
  "schema_version": "1.0.0",
  "execucao": {
    "id": "exec-pt-001",
    "projeto_alvo_path": "/tmp/poc-pt",
    "projeto_alvo_descricao": "POC legado pt-BR (>=10 chars)",
    "status": "em_andamento",
    "iniciada_em": "2026-05-05T14:00:00Z",
    "terminada_em": null
  },
  "etapa_corrente": "briefing",
  "proxima_instrucao": "Iniciar etapa briefing.",
  "ondas": [],
  "decisoes": [],
  "bloqueios_humanos": [],
  "orcamentos": {
    "profundidade_corrente_subagentes": 1,
    "ciclos_consumidos_etapa_corrente": 0,
    "retro_execucoes_consumidas": 0
  },
  "whitelist_urls_externas": []
}
EOF
}

scenario_pt_fallback_estado_valido_passa() {
  # Um state 100% pt-BR (sem nenhuma chave EN) deve validar via fallback.
  _sd="$TMPDIR_TEST/state-pt"
  _write_pt_state "$_sd"
  capture "$SCRIPT" --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "state pt-BR valido via fallback" "esperado 0, obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"
    return 1
  fi
}

scenario_pt_fallback_invariante_numerica_pega() {
  # Invariante de orcamento deve ser pega mesmo lendo a chave pt-BR via fallback.
  _sd="$TMPDIR_TEST/state-pt"
  _write_pt_state "$_sd"
  _patch_state "$_sd" '.orcamentos.profundidade_corrente_subagentes = 4'
  capture "$SCRIPT" --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "pt-BR profundidade > 3 via fallback" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "FR-013" || return 1
}

scenario_pt_fallback_decisao_incompleta_pega() {
  # Decisao pt-BR sem os 5 campos deve ser pega via fallback nas folhas.
  _sd="$TMPDIR_TEST/state-pt"
  _write_pt_state "$_sd"
  _patch_state "$_sd" '
    .decisoes = [{
      "id": "dec-pt-001",
      "onda_id": "onda-001",
      "timestamp": "2026-05-05T14:30:00Z",
      "etapa": "briefing",
      "agente": "orquestrador-00c",
      "contexto": "contexto valido com mais de 20 chars",
      "opcoes_consideradas": ["A","B"],
      "escolha": "A",
      "justificativa": ""
    }]
  '
  capture "$SCRIPT" --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "pt-BR decisao incompleta via fallback" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "Decisao dec-pt-001 viola Principio I" || return 1
}

scenario_pt_fallback_bloqueio_orfao_pega() {
  # BloqueioHumano pt-BR apontando para decisao inexistente, via fallback.
  _sd="$TMPDIR_TEST/state-pt"
  _write_pt_state "$_sd"
  _patch_state "$_sd" '
    .bloqueios_humanos = [{
      "id": "block-pt-001",
      "decisao_id": "dec-fantasma",
      "pergunta": "x",
      "contexto_para_resposta": "y",
      "status": "aguardando",
      "disparado_em": "2026-05-05T14:31:00Z"
    }]
  '
  capture "$SCRIPT" --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "pt-BR bloqueio orfao via fallback" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "BloqueioHumano block-pt-001 referencia decision_id inexistente" || return 1
}

run_all_scenarios
