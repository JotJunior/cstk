#!/bin/sh
# test_state-rw.sh — cobre global/skills/agente-00c-runtime/scripts/state-rw.sh.
#
# Cobertura:
#   - init cria state.json + sha256 + state-history/
#   - init falha se state.json ja existe
#   - read imprime conteudo
#   - get extrai campo via jq
#   - set atualiza campo + faz backup automatico
#   - write valida JSON em stdin antes de gravar
#   - sha256-update + sha256-verify (FR-029)
#   - path-check: dir existe / cria com --create / aponta para arquivo / perm denied
#   - jq ausente => exit 1 com mensagem clara

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/state-rw.sh"

# Bloqueia toda a suite se jq ausente — esses testes pre-supoem ambiente
# de desenvolvimento com jq (mesmo carve-out que cli/lib/hooks.sh).
if ! command -v jq >/dev/null 2>&1; then
  printf '# test_state-rw.sh: jq ausente — pulando suite (instale: brew install jq)\n'
  exit 0
fi

# ==== helpers ====

_init_default() {
  _id_dir=$1
  capture "$SCRIPT" init --state-dir "$_id_dir" \
    --execucao-id "exec-test-001" \
    --projeto-alvo-path "/tmp/poc-test" \
    --descricao "POC de teste (>=10 chars)"
}

# ==== Scenarios ====

scenario_init_cria_estrutura_base() {
  _sd="$TMPDIR_TEST/state"
  _init_default "$_sd"
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "init exit" "esperado 0, obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"
    return 1
  fi
  [ -f "$_sd/state.json" ]         || { _fail "state.json ausente" ""; return 1; }
  [ -f "$_sd/state.json.sha256" ]  || { _fail "sha256 ausente" ""; return 1; }
  [ -d "$_sd/state-history" ]      || { _fail "state-history/ ausente" ""; return 1; }
  # JSON valido
  jq -e . "$_sd/state.json" >/dev/null \
    || { _fail "state.json nao-json" ""; return 1; }
  return 0
}

scenario_init_recusa_se_state_existe() {
  _sd="$TMPDIR_TEST/state"
  _init_default "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "primeira init" "$_CAPTURED_STDERR"; return 1; }
  _init_default "$_sd"
  if [ "$_CAPTURED_EXIT" = 0 ]; then
    _fail "segunda init exit" "esperado != 0 (state.json ja existe), obtido 0"
    return 1
  fi
  assert_stderr_contains "state.json ja existe" || return 1
}

scenario_get_extrai_campo() {
  _sd="$TMPDIR_TEST/state"
  _init_default "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "init" "$_CAPTURED_STDERR"; return 1; }
  capture "$SCRIPT" get --state-dir "$_sd" --field '.execution.status'
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "get exit" "$_CAPTURED_EXIT"
    return 1
  fi
  assert_stdout_contains "em_andamento" || return 1
}

scenario_set_atualiza_campo_e_faz_backup() {
  _sd="$TMPDIR_TEST/state"
  _init_default "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "init" "$_CAPTURED_STDERR"; return 1; }
  # Antes do set: state-history vazio
  _hist_count=$(find "$_sd/state-history" -name '*.json' | wc -l | tr -d ' ')
  [ "$_hist_count" = 0 ] || { _fail "history nao vazio" "antes do set"; return 1; }
  capture "$SCRIPT" set --state-dir "$_sd" --field '.current_stage' --value '"specify"'
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "set exit" "$_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"
    return 1
  fi
  # Apos set: 1 backup
  _hist_count=$(find "$_sd/state-history" -name '*.json' | wc -l | tr -d ' ')
  [ "$_hist_count" = 1 ] || { _fail "backup nao criado" "esperado 1, obtido $_hist_count"; return 1; }
  # Campo atualizado
  capture "$SCRIPT" get --state-dir "$_sd" --field '.current_stage'
  assert_stdout_contains "specify" || return 1
}

scenario_write_recusa_json_invalido() {
  _sd="$TMPDIR_TEST/state"
  _init_default "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "init" "$_CAPTURED_STDERR"; return 1; }
  # Tenta gravar payload nao-JSON
  capture sh -c "printf '%s' 'not-valid-json' | '$SCRIPT' write --state-dir '$_sd'"
  if [ "$_CAPTURED_EXIT" = 0 ]; then
    _fail "write json invalido exit" "esperado != 0, obtido 0"
    return 1
  fi
  assert_stderr_contains "stdin nao e JSON valido" || return 1
}

scenario_sha256_verify_detecta_corrupcao() {
  _sd="$TMPDIR_TEST/state"
  _init_default "$_sd"
  capture "$SCRIPT" sha256-verify --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "sha256-verify estado limpo" "esperado 0, obtido $_CAPTURED_EXIT"
    return 1
  fi
  # Corrompe state.json sem regerar sha256
  echo "tampered" >> "$_sd/state.json"
  capture "$SCRIPT" sha256-verify --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "sha256-verify estado corrompido" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "hash divergente" || return 1
}

scenario_path_check_dir_existente_passa() {
  _pap="$TMPDIR_TEST/proj"
  mkdir -p "$_pap"
  capture "$SCRIPT" path-check --projeto-alvo-path "$_pap"
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "path-check existente" "$_CAPTURED_EXIT; $_CAPTURED_STDERR"
    return 1
  fi
}

scenario_path_check_dir_inexistente_sem_create_falha() {
  _pap="$TMPDIR_TEST/nope"
  capture "$SCRIPT" path-check --projeto-alvo-path "$_pap"
  if [ "$_CAPTURED_EXIT" = 0 ]; then
    _fail "path-check inexistente sem --create" "esperado != 0, obtido 0"
    return 1
  fi
  assert_stderr_contains "diretorio nao existe" || return 1
  [ -d "$_pap" ] && { _fail "criou sem --create" ""; return 1; }
  return 0
}

scenario_path_check_dir_inexistente_com_create_funciona() {
  _pap="$TMPDIR_TEST/created"
  capture "$SCRIPT" path-check --projeto-alvo-path "$_pap" --create
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "path-check --create" "$_CAPTURED_STDERR"
    return 1
  fi
  [ -d "$_pap" ] || { _fail "dir nao criado" ""; return 1; }
}

scenario_path_check_arquivo_falha() {
  _f="$TMPDIR_TEST/file.txt"
  : > "$_f"
  capture "$SCRIPT" path-check --projeto-alvo-path "$_f"
  if [ "$_CAPTURED_EXIT" = 0 ]; then
    _fail "path-check arquivo" "esperado != 0, obtido 0"
    return 1
  fi
  assert_stderr_contains "arquivo, nao diretorio" || return 1
}

scenario_path_check_perm_negada() {
  # Cria dir read-only e verifica que touch-probe detecta
  _pap="$TMPDIR_TEST/readonly"
  mkdir -p "$_pap"
  chmod 555 "$_pap"
  capture "$SCRIPT" path-check --projeto-alvo-path "$_pap"
  _exit=$_CAPTURED_EXIT
  chmod 755 "$_pap"  # restaura para cleanup
  if [ "$_exit" = 0 ]; then
    _fail "path-check read-only" "esperado != 0, obtido 0"
    return 1
  fi
  assert_stderr_contains "permissao de escrita negada" || return 1
}

scenario_round_trip_serializa_le_compara() {
  # Subtarefa 2.1.6
  _sd="$TMPDIR_TEST/state"
  _init_default "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "init" ""; return 1; }
  # Le, modifica via jq, escreve, le de novo, compara campo
  _content=$("$SCRIPT" read --state-dir "$_sd")
  # Escreve chave pt-BR de proposito: o write canonicaliza -> disco fica EN
  # (schema-en-migration). O get le via path EN.
  _new=$(printf '%s' "$_content" | jq '.etapa_corrente = "plan"')
  printf '%s' "$_new" | "$SCRIPT" write --state-dir "$_sd" 2>/dev/null
  capture "$SCRIPT" get --state-dir "$_sd" --field '.current_stage'
  assert_stdout_contains "plan" || return 1
  # prova convergencia: no disco e current_stage, nao etapa_corrente
  grep -q '"current_stage"' "$_sd/state.json" || { _fail "write nao canonicalizou" ""; return 1; }
  grep -q '"etapa_corrente"' "$_sd/state.json" && { _fail "chave pt-BR residual no disco" ""; return 1; }
  # state-history tem 1 backup do pre-write
  _hist_count=$(find "$_sd/state-history" -name '*.json' | wc -l | tr -d ' ')
  [ "$_hist_count" = 1 ] || { _fail "backup esperado" "obtido $_hist_count"; return 1; }
}

# ===== infer-aspectos (§2.3) =====

# Helper: cria projeto-alvo git repo com arquivos especificos commitados
# em 2 commits (HEAD~1 e HEAD), simulando uma onda.
_setup_pap_with_diff() {
  _pap=$1
  shift
  _files_baseline=$1
  shift
  _files_onda="$*"
  mkdir -p -- "$_pap"
  (
    cd "$_pap" || exit 1
    git init -q
    git config user.email "test@test.local"
    git config user.name "Test"
    # Baseline: arquivo inicial
    for _f in $_files_baseline; do
      mkdir -p -- "$(dirname -- "$_f")" 2>/dev/null || :
      printf 'base\n' > "$_f"
    done
    git add -A
    git commit -q -m "baseline"
    # Onda: arquivos modificados
    for _f in $_files_onda; do
      mkdir -p -- "$(dirname -- "$_f")" 2>/dev/null || :
      printf 'onda\n' > "$_f"
    done
    git add -A
    git commit -q -m "onda"
  )
}

scenario_infer_aspectos_diff_com_aspecto_iniciais() {
  _sd="$TMPDIR_TEST/state"
  _pap="$TMPDIR_TEST/pap"
  capture "$SCRIPT" init --state-dir "$_sd" \
    --execucao-id "exec-test" \
    --projeto-alvo-path "$_pap" \
    --descricao "POC com aspectos"
  # Grava aspectos manualmente
  capture "$SCRIPT" set --state-dir "$_sd" \
    --field '.initial_key_aspects' \
    --value '["slack","bot","threads"]'
  # Cria repo com arquivos relacionados
  _setup_pap_with_diff "$_pap" "README.md" "src/slack-handler.ts src/threads.ts"
  capture "$SCRIPT" infer-aspectos --state-dir "$_sd" --projeto-alvo-path "$_pap"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "infer" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "slack" || return 1
  assert_stdout_contains "threads" || return 1
}

scenario_infer_aspectos_diff_sem_aspecto_retorna_vazio() {
  _sd="$TMPDIR_TEST/state"
  _pap="$TMPDIR_TEST/pap"
  capture "$SCRIPT" init --state-dir "$_sd" \
    --execucao-id "exec-test" \
    --projeto-alvo-path "$_pap" \
    --descricao "POC com aspectos"
  capture "$SCRIPT" set --state-dir "$_sd" \
    --field '.initial_key_aspects' \
    --value '["slack","bot","threads"]'
  _setup_pap_with_diff "$_pap" "README.md" "src/logger.ts src/cache.ts"
  capture "$SCRIPT" infer-aspectos --state-dir "$_sd" --projeto-alvo-path "$_pap"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "infer vazio" "$_CAPTURED_STDERR"; return 1; }
  # JSON array vazio
  case "$_CAPTURED_STDOUT" in
    *'[]'*) ;;
    *) _fail "esperado [] vazio" "$_CAPTURED_STDOUT"; return 1 ;;
  esac
}

scenario_infer_aspectos_considera_camada_tecnica() {
  _sd="$TMPDIR_TEST/state"
  _pap="$TMPDIR_TEST/pap"
  capture "$SCRIPT" init --state-dir "$_sd" \
    --execucao-id "exec-test" \
    --projeto-alvo-path "$_pap" \
    --descricao "POC com 3 camadas"
  capture "$SCRIPT" set --state-dir "$_sd" \
    --field '.initial_key_aspects' --value '["produto-a","produto-b","produto-c"]'
  capture "$SCRIPT" set --state-dir "$_sd" \
    --field '.technical_key_aspects' --value '["auth","sessao","db"]'
  _setup_pap_with_diff "$_pap" "README.md" "src/auth/middleware.ts src/sessao-store.ts"
  capture "$SCRIPT" infer-aspectos --state-dir "$_sd" --projeto-alvo-path "$_pap"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "camada tec" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "auth" || return 1
  assert_stdout_contains "sessao" || return 1
}

scenario_infer_aspectos_matcher_fuzzy_token() {
  # aspecto "integracao-bidirecional-mcp-jira" deve casar com path
  # que cite token "mcp-jira" ou "jira"
  _sd="$TMPDIR_TEST/state"
  _pap="$TMPDIR_TEST/pap"
  capture "$SCRIPT" init --state-dir "$_sd" \
    --execucao-id "exec-test" \
    --projeto-alvo-path "$_pap" \
    --descricao "POC fuzzy"
  capture "$SCRIPT" set --state-dir "$_sd" \
    --field '.initial_key_aspects' \
    --value '["integracao-bidirecional-mcp-jira","triagem","priorizacao"]'
  _setup_pap_with_diff "$_pap" "README.md" "src/jira-webhook.ts"
  capture "$SCRIPT" infer-aspectos --state-dir "$_sd" --projeto-alvo-path "$_pap"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "fuzzy" "$_CAPTURED_STDERR"; return 1; }
  # Deve identificar aspecto via token "jira" compartilhado
  assert_stdout_contains "integracao-bidirecional-mcp-jira" || return 1
}

scenario_infer_aspectos_resolve_pap_de_state_se_nao_passado() {
  _sd="$TMPDIR_TEST/state"
  _pap="$TMPDIR_TEST/pap"
  capture "$SCRIPT" init --state-dir "$_sd" \
    --execucao-id "exec-test" \
    --projeto-alvo-path "$_pap" \
    --descricao "POC pap auto"
  capture "$SCRIPT" set --state-dir "$_sd" \
    --field '.initial_key_aspects' --value '["slack","bot","threads"]'
  _setup_pap_with_diff "$_pap" "README.md" "src/slack-bot.ts"
  # Sem --projeto-alvo-path explicito; resolve via state
  capture "$SCRIPT" infer-aspectos --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "auto pap" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "slack" || return 1
}

scenario_infer_aspectos_state_ausente_falha() {
  _sd="$TMPDIR_TEST/empty"
  mkdir -p "$_sd"
  capture "$SCRIPT" infer-aspectos --state-dir "$_sd" --projeto-alvo-path "/tmp"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "state ausente" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

# ===== schema-en-migration: chaves EN, init feature-mode, migrate, canonicalize =====

scenario_init_projeto_emite_chaves_en() {
  _sd="$TMPDIR_TEST/state"
  _init_default "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "init" "$_CAPTURED_STDERR"; return 1; }
  capture "$SCRIPT" read --state-dir "$_sd"
  assert_stdout_contains '"execution"' || return 1
  assert_stdout_contains '"current_stage"' || return 1
  assert_stdout_contains '"budgets"' || return 1
  assert_stdout_contains '"accumulated_metrics"' || return 1
  capture "$SCRIPT" get --state-dir "$_sd" --field '.current_stage'
  assert_stdout_contains "briefing" || return 1
}

scenario_init_feature_mode() {
  _sd="$TMPDIR_TEST/feat"
  capture "$SCRIPT" init --state-dir "$_sd" --short-name "minha-feature" \
    --projeto-alvo-path "/tmp/p" --descricao "feature de teste" \
    --briefing-path "docs/briefing.md" --briefing-sha256 "abc123" \
    --constitution-path "docs/constitution.md" --constitution-sha256 "def456" \
    --constitution-version "1.2.0" --key-aspects '["asp-um","asp-dois"]'
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "init feature" "$_CAPTURED_STDERR"; return 1; }
  capture "$SCRIPT" get --state-dir "$_sd" --field '.short_name'
  assert_stdout_contains "minha-feature" || return 1
  capture "$SCRIPT" get --state-dir "$_sd" --field '.current_stage'
  assert_stdout_contains "specify" || return 1
  capture "$SCRIPT" get --state-dir "$_sd" --field '.prerequisites.constitution.version'
  assert_stdout_contains "1.2.0" || return 1
  # execucao-id auto-derivado feat-<short>-<ts> quando omitido
  capture "$SCRIPT" get --state-dir "$_sd" --field '.execution.id'
  assert_stdout_contains "feat-minha-feature-" || return 1
  capture "$SCRIPT" get --state-dir "$_sd" --field '.initial_key_aspects | join(",")'
  assert_stdout_contains "asp-um" || return 1
}

scenario_init_feature_mode_exige_prereqs() {
  _sd="$TMPDIR_TEST/feat2"
  capture "$SCRIPT" init --state-dir "$_sd" --short-name "x" \
    --projeto-alvo-path "/tmp/p" --descricao "sem prereqs"
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "feature sem prereq" "esperado 2, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "briefing" || return 1
}

scenario_migrate_ptbr_para_en_idempotente() {
  _sd="$TMPDIR_TEST/legacy"
  mkdir -p "$_sd/state-history"
  cat > "$_sd/state.json" <<'JSON'
{ "schema_version":"1.0.0", "execucao":{"id":"x","status":"em_andamento","motivo_termino":null},
  "etapa_corrente":"plan", "ondas":[{"id":"onda-002","inicio":"t"}], "decisoes":[],
  "orcamentos":{"tool_calls_onda_corrente":3} }
JSON
  capture "$SCRIPT" migrate --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "migrate" "$_CAPTURED_STDERR"; return 1; }
  grep -q '"current_stage"' "$_sd/state.json" || { _fail "migrate nao gerou EN" ""; return 1; }
  grep -q '"etapa_corrente"' "$_sd/state.json" && { _fail "pt-BR residual pos-migrate" ""; return 1; }
  _hist=$(find "$_sd/state-history" -name '*.json' | wc -l | tr -d ' ')
  [ "$_hist" = 1 ] || { _fail "backup pt-BR nao preservado" "esperado 1, obtido $_hist"; return 1; }
  # 2o migrate = no-op idempotente (sem novo backup)
  capture "$SCRIPT" migrate --state-dir "$_sd"
  _hist2=$(find "$_sd/state-history" -name '*.json' | wc -l | tr -d ' ')
  [ "$_hist2" = 1 ] || { _fail "migrate nao-idempotente" "obtido $_hist2 backups"; return 1; }
}

scenario_get_legacy_ptbr_via_canonicalize() {
  _sd="$TMPDIR_TEST/legacy2"
  mkdir -p "$_sd/state-history"
  cat > "$_sd/state.json" <<'JSON'
{ "schema_version":"1.0.0", "execucao":{"id":"old","status":"em_andamento"},
  "etapa_corrente":"clarify", "ondas":[{"id":"onda-001","inicio":"t"}], "decisoes":[] }
JSON
  # path EN sobre arquivo pt-BR legado (canonicalize-on-read)
  capture "$SCRIPT" get --state-dir "$_sd" --field '.current_stage'
  assert_stdout_contains "clarify" || return 1
  capture "$SCRIPT" get --state-dir "$_sd" --field '.waves[0].id'
  assert_stdout_contains "onda-001" || return 1
  capture "$SCRIPT" get --state-dir "$_sd" --field '.execution.status'
  assert_stdout_contains "em_andamento" || return 1
}

run_all_scenarios
