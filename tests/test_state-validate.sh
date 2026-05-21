#!/bin/sh
# test_state-validate.sh — cobre global/skills/agente-00c-runtime/scripts/state-validate.sh.
#
# Cada cenario monta um state.json sintetico via jq e roda o validador.
# Estado valido = exit 0; cada tipo de violacao = exit 1 com mensagem
# especifica em stderr.

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
  _patch_state "$_sd" '.orcamentos.profundidade_corrente_subagentes = 4'
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
  _patch_state "$_sd" '.orcamentos.ciclos_consumidos_etapa_corrente = 6'
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
  _patch_state "$_sd" '.orcamentos.retro_execucoes_consumidas = 3'
  capture "$SCRIPT" --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "retros > 2" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "FR-006" || return 1
}

scenario_status_terminal_sem_terminada_em_falha() {
  _sd="$TMPDIR_TEST/state"
  _make_valid_state "$_sd"
  _patch_state "$_sd" '.execucao.status = "abortada"'
  capture "$SCRIPT" --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "abortada sem terminada_em" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "terminal" || return 1
  assert_stderr_contains "terminada_em e null" || return 1
}

scenario_status_em_andamento_com_terminada_em_falha() {
  _sd="$TMPDIR_TEST/state"
  _make_valid_state "$_sd"
  _patch_state "$_sd" '.execucao.terminada_em = "2026-05-05T15:00:00Z"'
  capture "$SCRIPT" --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "em_andamento com terminada_em" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "terminada_em preenchido" || return 1
}

scenario_decisao_sem_5_campos_falha_com_id() {
  _sd="$TMPDIR_TEST/state"
  _make_valid_state "$_sd"
  # Adiciona decisao com campo "justificativa" vazio (viola Principio I)
  _patch_state "$_sd" '
    .decisoes = [{
      "id": "dec-001",
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
    _fail "decisao incompleta" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "Decisao dec-001 viola Principio I" || return 1
}

scenario_bloqueio_referencia_decisao_inexistente_falha() {
  _sd="$TMPDIR_TEST/state"
  _make_valid_state "$_sd"
  _patch_state "$_sd" '
    .bloqueios_humanos = [{
      "id": "block-001",
      "decisao_id": "dec-fantasma",
      "pergunta": "x",
      "contexto_para_resposta": "y",
      "status": "aguardando",
      "disparado_em": "2026-05-05T14:31:00Z"
    }]
  '
  capture "$SCRIPT" --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "bloqueio orfao" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "BloqueioHumano block-001 referencia decisao_id inexistente" || return 1
}

scenario_whitelist_com_string_vazia_falha() {
  _sd="$TMPDIR_TEST/state"
  _make_valid_state "$_sd"
  _patch_state "$_sd" '.whitelist_urls_externas = ["https://valido.example/**", ""]'
  capture "$SCRIPT" --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "whitelist vazia" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "whitelist_urls_externas contem entrada" || return 1
}

scenario_campo_obrigatorio_ausente_falha() {
  _sd="$TMPDIR_TEST/state"
  _make_valid_state "$_sd"
  _patch_state "$_sd" 'del(.proxima_instrucao)'
  capture "$SCRIPT" --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "campo ausente" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "proxima_instrucao" || return 1
}

# ==== Cenarios para FR-CACHE-017 ====

# _cache_valid_payload imprime um cache valido em stdout (JSON object)
_cache_valid_payload() {
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

scenario_cache_estrategia_invalida_falha() {
  _sd="$TMPDIR_TEST/state"
  _make_valid_state "$_sd"
  _payload=$(_cache_valid_payload)
  _patch_state "$_sd" ".briefing_cache = $_payload | .briefing_cache.estrategia = \"foo\""
  capture "$SCRIPT" --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "estrategia invalida" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "estrategia invalido" || return 1
}

scenario_cache_resumo_maior_que_source_falha() {
  _sd="$TMPDIR_TEST/state"
  _make_valid_state "$_sd"
  _payload=$(_cache_valid_payload)
  _patch_state "$_sd" ".briefing_cache = $_payload | .briefing_cache.resumo_chars = 99999"
  capture "$SCRIPT" --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "resumo > source" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "resumo_chars" || return 1
}

scenario_cache_gerado_em_invalido_falha() {
  _sd="$TMPDIR_TEST/state"
  _make_valid_state "$_sd"
  _payload=$(_cache_valid_payload)
  _patch_state "$_sd" ".briefing_cache = $_payload | .briefing_cache.gerado_em = \"ontem\""
  capture "$SCRIPT" --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "gerado_em invalido" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "gerado_em" || return 1
}

scenario_cache_gerado_na_onda_zero_falha() {
  _sd="$TMPDIR_TEST/state"
  _make_valid_state "$_sd"
  _payload=$(_cache_valid_payload)
  _patch_state "$_sd" ".briefing_cache = $_payload | .briefing_cache.gerado_na_onda = 0"
  capture "$SCRIPT" --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "gerado_na_onda=0" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "gerado_na_onda" || return 1
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
  _patch_state "$_sd" ".constitution_cache = $_payload | .constitution_cache.estrategia = \"bar\""
  capture "$SCRIPT" --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "constitution_cache invalido" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "constitution_cache.estrategia" || return 1
}

run_all_scenarios
