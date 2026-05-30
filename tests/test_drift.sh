#!/bin/sh
# test_drift.sh — cobre global/skills/agente-00c-runtime/scripts/drift.sh.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"
. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/drift.sh"
RW="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/state-rw.sh"
ON="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/state-ondas.sh"
DEC="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/state-decisions.sh"

if ! command -v jq >/dev/null 2>&1; then
  printf '# test_drift.sh: jq ausente — pulando\n'
  exit 0
fi

_init() {
  capture "$RW" init --state-dir "$1" --execucao-id "x" \
    --projeto-alvo-path "/tmp/p" --descricao "POC drift tests"
}

# Cria 1 onda completa com 1 decisao tendo o contexto especificado
_run_wave() {
  capture "$ON" start --state-dir "$1"
  capture "$DEC" register --state-dir "$1" \
    --agente "x" --etapa "specify" \
    --contexto "$2" --opcoes '["A"]' --escolha "A" \
    --justificativa "justificativa de tamanho ok aqui sim"
  capture "$ON" end --state-dir "$1" --motivo-termino etapa_concluida_avancando
}

# ===== init =====

scenario_init_grava_aspectos() {
  _sd="$TMPDIR_TEST/state"
  _init "$_sd"
  capture "$SCRIPT" init --state-dir "$_sd" --aspectos '["slack","bot","threads"]'
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "init" "$_CAPTURED_STDERR"; return 1; }
  capture "$SCRIPT" aspectos --state-dir "$_sd"
  assert_stdout_contains "slack" || return 1
  assert_stdout_contains "bot" || return 1
  assert_stdout_contains "threads" || return 1
}

scenario_init_array_pequeno_falha() {
  _sd="$TMPDIR_TEST/state"
  _init "$_sd"
  capture "$SCRIPT" init --state-dir "$_sd" --aspectos '["a","b"]'
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "init <3 aspectos" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_init_array_grande_falha() {
  _sd="$TMPDIR_TEST/state"
  _init "$_sd"
  capture "$SCRIPT" init --state-dir "$_sd" \
    --aspectos '["a","b","c","d","e","f","g","h"]'
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "init >7 aspectos" "esperado 1"
    return 1
  fi
}

scenario_init_duplicado_falha_congelado() {
  _sd="$TMPDIR_TEST/state"
  _init "$_sd"
  capture "$SCRIPT" init --state-dir "$_sd" --aspectos '["a","b","c"]'
  capture "$SCRIPT" init --state-dir "$_sd" --aspectos '["x","y","z"]'
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "init duplicado" "esperado 1"
    return 1
  fi
  assert_stderr_contains "ja foi gravado" || return 1
}

scenario_init_force_sobrescreve() {
  _sd="$TMPDIR_TEST/state"
  _init "$_sd"
  capture "$SCRIPT" init --state-dir "$_sd" --aspectos '["a","b","c"]'
  capture "$SCRIPT" init --state-dir "$_sd" --aspectos '["x","y","z"]' --force
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "force" "$_CAPTURED_STDERR"; return 1; }
  capture "$SCRIPT" aspectos --state-dir "$_sd"
  assert_stdout_contains "x" || return 1
  case "$_CAPTURED_STDOUT" in
    *abc*) _fail "force nao limpou antigos" ""; return 1 ;;
  esac
}

scenario_init_com_3_camadas() {
  _sd="$TMPDIR_TEST/state"
  _init "$_sd"
  capture "$SCRIPT" init --state-dir "$_sd" \
    --aspectos '["produto-a","produto-b","produto-c"]' \
    --tecnicos '["auth","sessao","db"]' \
    --operacionais '["runbook","ci-cd"]'
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "init 3 camadas" "$_CAPTURED_STDERR"; return 1; }
  capture "$SCRIPT" aspectos --state-dir "$_sd" --camada tecnicos
  assert_stdout_contains "auth" || return 1
  assert_stdout_contains "sessao" || return 1
  capture "$SCRIPT" aspectos --state-dir "$_sd" --camada operacionais
  assert_stdout_contains "runbook" || return 1
  capture "$SCRIPT" aspectos --state-dir "$_sd" --camada all
  assert_stdout_contains "produto-a" || return 1
  assert_stdout_contains "auth" || return 1
  assert_stdout_contains "runbook" || return 1
}

# ===== matcher bidirecional =====

scenario_matcher_text_contem_aspecto() {
  # aspecto curto, texto longo
  _sd="$TMPDIR_TEST/state"
  _init "$_sd"
  capture "$SCRIPT" init --state-dir "$_sd" --aspectos '["slack","bot","threads"]'
  _run_wave "$_sd" "Bot Slack para sumarizar threads de canal"
  capture "$SCRIPT" check --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "match" "$_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "0" || return 1
}

scenario_matcher_token_compartilhado_aspecto_longo() {
  # aspecto longo "integracao-bidirecional-mcp-jira", texto curto cita "mcp-jira"
  # — match via tokens compartilhados (sug-041)
  _sd="$TMPDIR_TEST/state"
  _init "$_sd"
  capture "$SCRIPT" init --state-dir "$_sd" \
    --aspectos '["integracao-bidirecional-mcp-jira","triagem","priorizacao"]'
  _run_wave "$_sd" "Decisao sobre webhook mcp-jira para sync"
  capture "$SCRIPT" check --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "token match aspecto longo" "$_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "0" || return 1
}

scenario_matcher_case_insensitive() {
  _sd="$TMPDIR_TEST/state"
  _init "$_sd"
  capture "$SCRIPT" init --state-dir "$_sd" --aspectos '["Slack","BOT","threads"]'
  _run_wave "$_sd" "BOT SLACK PARA THREADS"
  capture "$SCRIPT" check --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "case-insens" "$_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "0" || return 1
}

# ===== check semantica nova (janela movel) =====

scenario_check_sem_aspectos_disable() {
  _sd="$TMPDIR_TEST/state"
  _init "$_sd"
  capture "$SCRIPT" check --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "$_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "0" || return 1
  assert_stderr_contains "desabilitado" || return 1
}

scenario_check_drift_zero_quando_aspectos_tocados() {
  _sd="$TMPDIR_TEST/state"
  _init "$_sd"
  capture "$SCRIPT" init --state-dir "$_sd" --aspectos '["slack","bot","threads"]'
  _run_wave "$_sd" "Bot Slack para sumarizar threads"
  capture "$SCRIPT" check --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "drift c/ aspectos" "$_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "0" || return 1
}

scenario_check_4_drift_continuas_nao_dispara() {
  # Threshold default: warn>=5 untouched, abort>=8. 4 ondas drift => OK.
  _sd="$TMPDIR_TEST/state"
  _init "$_sd"
  capture "$SCRIPT" init --state-dir "$_sd" --aspectos '["slack","bot","threads"]'
  for _ in 1 2 3 4; do
    _run_wave "$_sd" "Decidir lib de logging para microservico"
  done
  capture "$SCRIPT" check --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "4 drift" "$_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "4" || return 1
  case "$_CAPTURED_STDERR" in
    *AVISO*) _fail "warn disparado prematuro" "$_CAPTURED_STDERR"; return 1 ;;
  esac
}

scenario_check_warn_em_5_untouched() {
  _sd="$TMPDIR_TEST/state"
  _init "$_sd"
  capture "$SCRIPT" init --state-dir "$_sd" --aspectos '["slack","bot","threads"]'
  for _ in 1 2 3 4 5; do
    _run_wave "$_sd" "Decidir lib de logging para microservico"
  done
  capture "$SCRIPT" check --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "warn deve exit 0" "$_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "5" || return 1
  assert_stderr_contains "AVISO" || return 1
}

scenario_check_abort_em_8_untouched() {
  _sd="$TMPDIR_TEST/state"
  _init "$_sd"
  capture "$SCRIPT" init --state-dir "$_sd" --aspectos '["slack","bot","threads"]'
  for _ in 1 2 3 4 5 6 7 8; do
    _run_wave "$_sd" "Decidir lib de logging para microservico"
  done
  capture "$SCRIPT" check --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 3 ]; then
    _fail "abort 8 untouched" "esperado 3, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "desvio_de_finalidade" || return 1
}

scenario_check_backbone_intercalado_nao_aborta() {
  # 5 drift waves intercaladas com 3 product waves NUNCA disparam abort
  # (sao 5/8 untouched, abaixo do abort threshold de 8).
  # Cenario classico FASE 4.x backbone tecnico mais features.
  # Contextos >=20 chars (validacao Principio I).
  _sd="$TMPDIR_TEST/state"
  _init "$_sd"
  capture "$SCRIPT" init --state-dir "$_sd" --aspectos '["slack","bot","threads"]'
  _run_wave "$_sd" "Bot Slack inicial setup ok"
  _run_wave "$_sd" "Decidir lib de logging para api"
  _run_wave "$_sd" "Decidir db backend storage"
  _run_wave "$_sd" "Threads handler implementation"
  _run_wave "$_sd" "Decidir cache layer Redis"
  _run_wave "$_sd" "Decidir auth middleware JWT"
  _run_wave "$_sd" "Decidir config layer setup"
  _run_wave "$_sd" "Slack webhook setup pipeline"
  capture "$SCRIPT" check --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "backbone misto" "$_CAPTURED_EXIT/$_CAPTURED_STDERR"; return 1; }
}

scenario_check_janela_movel_descarta_ondas_antigas() {
  # Janela default = 12. Se temos 15 ondas, e as ultimas 12 sao todas
  # tocadas, untouched=0 mesmo que ondas 1-3 sejam drift.
  _sd="$TMPDIR_TEST/state"
  _init "$_sd"
  capture "$SCRIPT" init --state-dir "$_sd" --aspectos '["slack","bot","threads"]'
  for _ in 1 2 3; do
    _run_wave "$_sd" "Decidir lib de logging — sem aspecto"
  done
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
    _run_wave "$_sd" "Slack bot threads handler iteracao"
  done
  capture "$SCRIPT" check --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "janela movel" "$_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "0" || return 1
}

scenario_check_considera_camada_tecnica() {
  # Onda com decisao sobre "auth" (camada tecnica) conta como tocada.
  _sd="$TMPDIR_TEST/state"
  _init "$_sd"
  capture "$SCRIPT" init --state-dir "$_sd" \
    --aspectos '["produto-a","produto-b","produto-c"]' \
    --tecnicos '["auth","sessao","db"]'
  _run_wave "$_sd" "Implementar middleware de auth com JWT"
  capture "$SCRIPT" check --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "camada tec" "$_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "0" || return 1
}

# ===== mark-touched =====

scenario_mark_touched_registra_aspecto_na_onda() {
  _sd="$TMPDIR_TEST/state"
  _init "$_sd"
  capture "$SCRIPT" init --state-dir "$_sd" --aspectos '["slack","bot","threads"]'
  capture "$ON" start --state-dir "$_sd"
  capture "$SCRIPT" mark-touched --state-dir "$_sd" --aspecto "slack"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "mark-touched" "$_CAPTURED_STDERR"; return 1; }
  # get canonicaliza disco->EN, entao o path e EN (schema-en-migration)
  capture "$RW" get --state-dir "$_sd" --field '.waves[-1].touched_key_aspects'
  assert_stdout_contains "slack" || return 1
}

scenario_mark_touched_evita_falso_positivo() {
  # Mesmo cenario que dispara warn (5 drift), mas marcamos 1 onda como
  # tocada — passa a 4 untouched, abaixo de warn.
  _sd="$TMPDIR_TEST/state"
  _init "$_sd"
  capture "$SCRIPT" init --state-dir "$_sd" --aspectos '["slack","bot","threads"]'
  for _ in 1 2 3 4; do
    _run_wave "$_sd" "Decidir lib de logging"
  done
  capture "$ON" start --state-dir "$_sd"
  capture "$SCRIPT" mark-touched --state-dir "$_sd" --aspecto "slack"
  capture "$DEC" register --state-dir "$_sd" \
    --agente "x" --etapa "specify" \
    --contexto "Refactor de logger — nao toca aspecto via texto" \
    --opcoes '["A"]' --escolha "A" \
    --justificativa "justificativa de tamanho ok aqui sim"
  capture "$ON" end --state-dir "$_sd" --motivo-termino etapa_concluida_avancando
  capture "$SCRIPT" check --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "post-mark" "$_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "4" || return 1
  case "$_CAPTURED_STDERR" in
    *AVISO*) _fail "mark-touched nao limpou warn" ""; return 1 ;;
  esac
}

scenario_mark_touched_sem_onda_falha() {
  _sd="$TMPDIR_TEST/state"
  _init "$_sd"
  capture "$SCRIPT" init --state-dir "$_sd" --aspectos '["a","b","c"]'
  capture "$SCRIPT" mark-touched --state-dir "$_sd" --aspecto "a"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "sem onda" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "nenhuma onda" || return 1
}

# ===== debug =====

scenario_debug_lista_camadas_e_ondas() {
  _sd="$TMPDIR_TEST/state"
  _init "$_sd"
  capture "$SCRIPT" init --state-dir "$_sd" \
    --aspectos '["slack","bot","threads"]' \
    --tecnicos '["auth","db"]'
  _run_wave "$_sd" "Bot Slack para sumarizar threads"
  _run_wave "$_sd" "Decidir lib de logging para api"
  capture "$SCRIPT" debug --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "debug" "$_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "iniciais:" || return 1
  assert_stdout_contains "slack" || return 1
  assert_stdout_contains "tecnicos:" || return 1
  assert_stdout_contains "auth" || return 1
  assert_stdout_contains "TOUCHED" || return 1
  assert_stdout_contains "untouched" || return 1
}

# ===== extract (novo subcomando — schema-en-migration) =====

scenario_extract_keywords() {
  capture "$SCRIPT" extract --text "OAuth Redis cache" --max 4
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "extract" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "oauth" || return 1
  assert_stdout_contains "redis" || return 1
}

scenario_extract_respeita_max() {
  # --max limita o numero de keywords retornadas
  capture "$SCRIPT" extract --text "alfa beta gama delta epsilon zeta" --max 2
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "extract max" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "alfa" || return 1
  assert_stdout_contains "beta" || return 1
  case "$_CAPTURED_STDOUT" in *gama*) _fail "extract nao respeitou --max 2" ""; return 1 ;; esac
}

scenario_extract_so_stopwords_vazio() {
  capture "$SCRIPT" extract --text "de a o e que para com"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "extract vazio" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "[]" || return 1
}

scenario_extract_sem_text_falha() {
  capture "$SCRIPT" extract --max 5
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "extract sem --text" "esperado 2, obtido $_CAPTURED_EXIT"; return 1; }
}

# ===== key-aspects (rename EN) + alias 'aspectos' deprecado =====

scenario_key_aspects_subcomando_en() {
  _sd="$TMPDIR_TEST/state"
  _init "$_sd"
  capture "$SCRIPT" init --state-dir "$_sd" --aspectos '["slack","bot","threads"]'
  capture "$SCRIPT" key-aspects --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "key-aspects" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "slack" || return 1
}

scenario_aspectos_alias_deprecado_avisa() {
  _sd="$TMPDIR_TEST/state"
  _init "$_sd"
  capture "$SCRIPT" init --state-dir "$_sd" --aspectos '["slack","bot","threads"]'
  capture "$SCRIPT" aspectos --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "alias aspectos" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "slack" || return 1
  assert_stderr_contains "deprecado" || return 1
}

# ===== back-compat: drift le state.json pt-BR legado via fallback (idiom §6) =====

scenario_legacy_ptbr_state_via_fallback() {
  _sd="$TMPDIR_TEST/state"
  mkdir -p "$_sd/state-history"
  # state.json pt-BR legado (schema antigo), construido direto no disco
  cat > "$_sd/state.json" <<'JSON'
{ "schema_version":"1.0.0", "execucao":{"id":"x","status":"em_andamento"}, "etapa_corrente":"plan",
  "ondas":[{"id":"onda-001","inicio":"t"}],
  "decisoes":[{"id":"d1","onda_id":"onda-001","contexto":"trabalho em slack-bot agora","escolha":"usar slack","justificativa":"j"}],
  "aspectos_chave_iniciais":["slack-bot","cache-redis"] }
JSON
  # key-aspects le via (.initial_key_aspects // .aspectos_chave_iniciais)
  capture "$SCRIPT" key-aspects --state-dir "$_sd" --camada iniciais
  assert_stdout_contains "slack-bot" || return 1
  # check le .ondas/.decisoes/.contexto via fallback e detecta touched (exit 0)
  capture "$SCRIPT" check --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "check legacy ptbr" "$_CAPTURED_STDERR"; return 1; }
}

run_all_scenarios
