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

scenario_init_semeia_gitignore_no_state_dir() {
  # Estado e runtime/transacional: o state-dir nasce com .gitignore "*" para
  # nunca ser versionavel (repo trackeando state.json foi o gatilho do bug
  # .claude/.claude corrigido em v5.11.1).
  _sd="$TMPDIR_TEST/state"
  _init_default "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "init" "$_CAPTURED_STDERR"; return 1; }
  [ -f "$_sd/.gitignore" ] || { _fail ".gitignore ausente" "state-dir deveria nascer com .gitignore"; return 1; }
  _gi=$(cat "$_sd/.gitignore")
  [ "$_gi" = "*" ] || { _fail ".gitignore conteudo" "esperado '*', obtido '$_gi'"; return 1; }
  return 0
}

scenario_init_preserva_gitignore_customizado() {
  # Idempotencia: .gitignore pre-existente do operador NUNCA e sobrescrito.
  _sd="$TMPDIR_TEST/state"
  mkdir -p "$_sd"
  printf 'state-history/\n' > "$_sd/.gitignore"
  _init_default "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "init" "$_CAPTURED_STDERR"; return 1; }
  _gi=$(cat "$_sd/.gitignore")
  [ "$_gi" = "state-history/" ] || { _fail ".gitignore sobrescrito" "esperado 'state-history/', obtido '$_gi'"; return 1; }
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
  # Mensagem legada permanece byte-a-byte identica (SC-006, openspec-hygiene).
  assert_stderr_contains "stdin nao e JSON valido" || return 1
  # Envelope diagnostico aditivo (openspec-hygiene FR-012/FR-015).
  assert_stderr_contains "DIAG|error|state-invalid-json|" || return 1
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
  # Mensagem legada permanece byte-a-byte identica (SC-006, openspec-hygiene).
  assert_stderr_contains "hash divergente" || return 1
  # Envelope diagnostico aditivo (openspec-hygiene FR-012/FR-015).
  assert_stderr_contains "DIAG|error|hash-mismatch|" || return 1
}

# ==== get: state.json ausente -> mensagem legada + DIAG|state-not-found
# (openspec-hygiene FR-012/FR-015, escopo-piloto) ====

scenario_get_state_ausente_emite_diag() {
  _sd="$TMPDIR_TEST/state-inexistente"
  capture "$SCRIPT" get --state-dir "$_sd" --field '.current_stage'
  if [ "$_CAPTURED_EXIT" = 0 ]; then
    _fail "get state ausente exit" "esperado != 0, obtido 0"
    return 1
  fi
  assert_stderr_contains "get: state.json ausente" || return 1
  assert_stderr_contains "DIAG|error|state-not-found|" || return 1
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

# ===== recall-worktree-identity: --canonical-project / --session-name =====

# Cenario 1: init com ambas as flags grava os campos no JSON (US3 AC1)
scenario_init_canonical_project_e_session_name() {
  _sd="$TMPDIR_TEST/wt-both"
  capture "$SCRIPT" init --state-dir "$_sd" \
    --execucao-id "exec-wt-001" \
    --projeto-alvo-path "/tmp/cstk" \
    --descricao "worktree test" \
    --canonical-project "cstk" \
    --session-name "minha-feature"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "init exit" "esperado 0, obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"; return 1; }
  capture "$SCRIPT" get --state-dir "$_sd" --field '.execution.canonical_project'
  assert_stdout_contains "cstk" || return 1
  capture "$SCRIPT" get --state-dir "$_sd" --field '.execution.session_name'
  assert_stdout_contains "minha-feature" || return 1
}

# Cenario 2: init sem as flags NAO inclui as chaves no JSON (US3 AC2/AC3, FR-010)
scenario_init_sem_flags_worktree_ausencia_de_chaves() {
  _sd="$TMPDIR_TEST/wt-none"
  capture "$SCRIPT" init --state-dir "$_sd" \
    --execucao-id "exec-wt-002" \
    --projeto-alvo-path "/tmp/cstk" \
    --descricao "projeto normal"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "init exit" "esperado 0, obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"; return 1; }
  # Chaves canonical_project e session_name devem estar AUSENTES (nao null, ausentes)
  capture "$SCRIPT" get --state-dir "$_sd" --field '.execution | has("canonical_project")'
  assert_stdout_contains "false" || return 1
  capture "$SCRIPT" get --state-dir "$_sd" --field '.execution | has("session_name")'
  assert_stdout_contains "false" || return 1
}

# Cenario 3: --session-name sem --canonical-project => exit 2 (erro de uso)
scenario_init_session_sem_canonical_falha() {
  _sd="$TMPDIR_TEST/wt-err"
  capture "$SCRIPT" init --state-dir "$_sd" \
    --execucao-id "exec-wt-003" \
    --projeto-alvo-path "/tmp/cstk" \
    --descricao "session orphan" \
    --session-name "orphan-session"
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit esperado 2" "obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "canonical-project" || return 1
}

# Cenario 4: feature mode com canonical flags (regressao — flags valem nos dois modos)
scenario_init_feature_mode_com_canonical_flags() {
  _sd="$TMPDIR_TEST/wt-feat"
  capture "$SCRIPT" init --state-dir "$_sd" \
    --short-name "wt-feat" \
    --projeto-alvo-path "/tmp/cstk" \
    --descricao "feature em worktree" \
    --briefing-path "docs/briefing.md" --briefing-sha256 "abc123" \
    --constitution-path "docs/constitution.md" --constitution-sha256 "def456" \
    --constitution-version "1.0.0" \
    --canonical-project "cstk" \
    --session-name "wt-feat"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "init feature exit" "esperado 0, obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"; return 1; }
  capture "$SCRIPT" get --state-dir "$_sd" --field '.execution.canonical_project'
  assert_stdout_contains "cstk" || return 1
  capture "$SCRIPT" get --state-dir "$_sd" --field '.execution.session_name'
  assert_stdout_contains "wt-feat" || return 1
  # current_stage deve ser specify (feature mode intacto)
  capture "$SCRIPT" get --state-dir "$_sd" --field '.current_stage'
  assert_stdout_contains "specify" || return 1
}

# ==== Cenarios: --atomic-commit flag (feature atomic-commit-pr) ====

# Cenario: init --atomic-commit true persiste atomic_commit_enabled=true
scenario_init_atomic_commit_true() {
  _sd="$TMPDIR_TEST/atomic-true"
  capture "$SCRIPT" init --state-dir "$_sd" \
    --projeto-alvo-path "/tmp/cstk" \
    --descricao "test atomic true" \
    --execucao-id "exec-atomic-true-001" \
    --atomic-commit true
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit esperado 0" "obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"; return 1; }
  capture "$SCRIPT" get --state-dir "$_sd" --field '.atomic_commit_enabled'
  [ "$_CAPTURED_STDOUT" = "true" ] || { _fail "atomic_commit_enabled esperado true" "obtido $_CAPTURED_STDOUT"; return 1; }
}

# Cenario: init --atomic-commit false persiste atomic_commit_enabled=false
scenario_init_atomic_commit_false() {
  _sd="$TMPDIR_TEST/atomic-false"
  capture "$SCRIPT" init --state-dir "$_sd" \
    --projeto-alvo-path "/tmp/cstk" \
    --descricao "test atomic false" \
    --execucao-id "exec-atomic-false-001" \
    --atomic-commit false
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit esperado 0" "obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"; return 1; }
  capture "$SCRIPT" get --state-dir "$_sd" --field '.atomic_commit_enabled'
  [ "$_CAPTURED_STDOUT" = "false" ] || { _fail "atomic_commit_enabled esperado false" "obtido $_CAPTURED_STDOUT"; return 1; }
}

# Cenario: init sem --atomic-commit => atomic_commit_enabled=false (default seguro)
scenario_init_atomic_commit_default_false() {
  _sd="$TMPDIR_TEST/atomic-default"
  capture "$SCRIPT" init --state-dir "$_sd" \
    --projeto-alvo-path "/tmp/cstk" \
    --descricao "test atomic default" \
    --execucao-id "exec-atomic-default-001"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit esperado 0" "obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"; return 1; }
  capture "$SCRIPT" get --state-dir "$_sd" --field '.atomic_commit_enabled'
  [ "$_CAPTURED_STDOUT" = "false" ] || { _fail "atomic_commit_enabled esperado false (default)" "obtido $_CAPTURED_STDOUT"; return 1; }
}

# Cenario: init --atomic-commit valor invalido => exit 2
scenario_init_atomic_commit_invalid_value() {
  _sd="$TMPDIR_TEST/atomic-invalid"
  capture "$SCRIPT" init --state-dir "$_sd" \
    --projeto-alvo-path "/tmp/cstk" \
    --descricao "test atomic invalid" \
    --execucao-id "exec-atomic-invalid-001" \
    --atomic-commit yes
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit esperado 2 para valor invalido" "obtido $_CAPTURED_EXIT"; return 1; }
}

# Cenario: retro-compat — state legado sem atomic_commit_enabled lido como false
scenario_init_atomic_commit_retro_compat() {
  _sd="$TMPDIR_TEST/atomic-retro"
  # Criar state sem o campo
  capture "$SCRIPT" init --state-dir "$_sd" \
    --projeto-alvo-path "/tmp/cstk" \
    --descricao "test retro" \
    --execucao-id "exec-retro-001"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "init exit esperado 0" "obtido $_CAPTURED_EXIT"; return 1; }
  # Remover campo via jq (simula state legado)
  _sf="$_sd/state.json"
  _tmp=$(mktemp)
  jq 'del(.atomic_commit_enabled)' "$_sf" > "$_tmp" && mv "$_tmp" "$_sf"
  # Campo ausente deve retornar null/vazio (nao erro)
  capture "$SCRIPT" get --state-dir "$_sd" --field '.atomic_commit_enabled // false'
  [ "$_CAPTURED_STDOUT" = "false" ] || { _fail "legado sem campo: esperado false via jq fallback" "obtido $_CAPTURED_STDOUT"; return 1; }
}

# ==== Backend dual SQLite (feature state-db-foundation, FASE 3 task 3.2) ====
#
# Ref: docs/specs/state-db-foundation/contracts/primitives.md §C1 (paridade)
#      §C2 (selecao de backend) §C7 (sha256-* sob SQLite)
#
# NOTA (feature state-backend-config, FASE 5): `init` agora PODE criar
# state.db diretamente quando a config global declara `state_backend=sqlite`
# com dependencia adequada (ver scenarios `scenario_init_sqlite_*` mais
# abaixo) — mas o cenario historico permanece valido para o caso "projeto ja
# migrado / state.db pre-existente de outra origem" (guarda de recusa
# preservada independente da config, FR-006): os cenarios abaixo simulam
# esse estado aplicando o DDL diretamente via state-db-schema.sh (task
# 2.1.8) e semeando a linha de execution minima via sqlite3, o mesmo padrao
# usado por tests/test_state-db-schema.sh.

SCHEMA_SCRIPT="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/state-db-schema.sh"

if ! command -v sqlite3 >/dev/null 2>&1; then
  printf '# test_state-rw.sh: sqlite3 ausente — pulando cenarios de backend SQLite\n'
else

# _seed_sqlite_backend DIR [SHORT_NAME] -> cria state.db com uma execution
# minima (id=exec-1), pronta para read/get/set/write/sha256-*.
_seed_sqlite_backend() {
  _ssb_dir=$1
  _ssb_short=${2:-}
  mkdir -p "$_ssb_dir"
  "$SCHEMA_SCRIPT" create --db "$_ssb_dir/state.db" >/dev/null 2>&1 \
    || { _fail "seed: schema create falhou" ""; return 1; }
  _ssb_short_sql="NULL"
  [ -n "$_ssb_short" ] && _ssb_short_sql="'$_ssb_short'"
  sqlite3 "$_ssb_dir/state.db" "
    PRAGMA foreign_keys=ON;
    INSERT INTO execution (id,schema_version,short_name,target_project_path,target_project_description,status,started_at,current_stage,next_instruction,external_urls_whitelist,circular_movement_history,initial_key_aspects,atomic_commit_enabled)
    VALUES ('exec-1','1.0.0',$_ssb_short_sql,'/tmp/proj','desc de teste com detalhe','em_andamento','2026-07-30T00:00:00Z','specify','faca algo',' []','[]','[]',0);
  " || { _fail "seed: insert execution falhou" ""; return 1; }
}

scenario_sqlite_init_recusa_se_state_db_existe() {
  _sd="$TMPDIR_TEST/migrated"
  _seed_sqlite_backend "$_sd" || return 1
  capture "$SCRIPT" init --state-dir "$_sd" --execucao-id "exec-x" \
    --projeto-alvo-path "/tmp/foo" --descricao "descricao valida >=10"
  [ "$_CAPTURED_EXIT" != 0 ] || { _fail "init sob state.db existente" "esperado exit != 0, obtido 0"; return 1; }
  case "$_CAPTURED_STDERR" in
    *state.db*) : ;;
    *) _fail "init recusa msg" "esperava mencionar state.db, obtido: $_CAPTURED_STDERR"; return 1 ;;
  esac
}

scenario_sqlite_read_reconstroi_documento_valido_por_state_validate() {
  _sd="$TMPDIR_TEST/migrated"
  _seed_sqlite_backend "$_sd" "my-feat" || return 1
  capture "$SCRIPT" read --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "read exit" "$_CAPTURED_STDERR"; return 1; }
  printf '%s' "$_CAPTURED_STDOUT" | jq -e . >/dev/null \
    || { _fail "read produz JSON invalido" "$_CAPTURED_STDOUT"; return 1; }
  _validate_dir="$TMPDIR_TEST/validate-export"
  mkdir -p "$_validate_dir"
  printf '%s' "$_CAPTURED_STDOUT" > "$_validate_dir/state.json"
  capture sh "$REPO_ROOT/global/skills/agente-00c-runtime/scripts/state-validate.sh" --state-dir "$_validate_dir"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "export nao passa em state-validate.sh (E1)" "$_CAPTURED_STDERR"; return 1; }
}

scenario_sqlite_read_e2_e3_ids_e_skills_invoked_aninhado() {
  # E2 (fidelidade de nomes/IDs) + E3 (aninhamento skills_invoked, ausente-vs-null)
  _sd="$TMPDIR_TEST/migrated"
  _seed_sqlite_backend "$_sd" || return 1
  sqlite3 "$_sd/state.db" "
    INSERT INTO wave (id,execution_id,seq,started_at) VALUES ('onda-001','exec-1',1,'2026-07-30T00:00:00Z');
    INSERT INTO decision (id,execution_id,wave_id,timestamp,agent,stage,context,options_considered,choice,rationale,justification_score)
      VALUES ('dec-001','exec-1','onda-001','2026-07-30T00:01:00Z','tester','specify','contexto de teste com pelo menos vinte caracteres','[\"a\",\"b\"]','a','justificativa de teste com pelo menos vinte caracteres',2);
    INSERT INTO human_block (id,execution_id,decision_id,question,context_for_answer,status,triggered_at)
      VALUES ('block-001','exec-1','dec-001','pergunta de teste com pelo menos vinte caracteres','contexto para resposta','aguardando','2026-07-30T00:02:00Z');
    INSERT INTO skill_invocation (wave_id,skill,timestamp,decision_id,kind)
      VALUES ('onda-001','specify','2026-07-30T00:01:30Z','dec-001','skill');
  " || { _fail "seed decision/human_block/skill_invocation falhou" ""; return 1; }

  capture "$SCRIPT" read --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "read exit" "$_CAPTURED_STDERR"; return 1; }
  _doc="$_CAPTURED_STDOUT"

  # IDs preservados literalmente (formato dec-NNN, block-NNN, onda-NNN)
  [ "$(printf '%s' "$_doc" | jq -r '.waves[0].id')" = "onda-001" ] \
    || { _fail "waves[0].id" "$(printf '%s' "$_doc" | jq -r '.waves[0].id')"; return 1; }
  [ "$(printf '%s' "$_doc" | jq -r '.decisions[0].id')" = "dec-001" ] \
    || { _fail "decisions[0].id" "$(printf '%s' "$_doc" | jq -r '.decisions[0].id')"; return 1; }
  [ "$(printf '%s' "$_doc" | jq -r '.human_blocks[0].id')" = "block-001" ] \
    || { _fail "human_blocks[0].id" "$(printf '%s' "$_doc" | jq -r '.human_blocks[0].id')"; return 1; }

  # Nome de campo justification_score (nao "score")
  [ "$(printf '%s' "$_doc" | jq -r '.decisions[0].justification_score')" = "2" ] \
    || { _fail "decisions[0].justification_score" "$(printf '%s' "$_doc" | jq -r '.decisions[0].justification_score')"; return 1; }

  # skills_invoked aninhado em waves[N], nao tabela solta no topo
  [ "$(printf '%s' "$_doc" | jq -r '.waves[0].skills_invoked[0].skill')" = "specify" ] \
    || { _fail "waves[0].skills_invoked[0].skill" "$(printf '%s' "$_doc" | jq -r '.waves[0].skills_invoked[0].skill')"; return 1; }
  [ "$(printf '%s' "$_doc" | jq -r '.waves[0].skills_invoked[0].decision_id')" = "dec-001" ] \
    || { _fail "waves[0].skills_invoked[0].decision_id" ""; return 1; }
  [ "$(printf '%s' "$_doc" | jq 'has("skills_invoked")')" = "false" ] \
    || { _fail "skills_invoked nao deveria existir no topo do documento" ""; return 1; }

  # Ausente-vs-null: canonical_project/session_name nao setados ficam AUSENTES
  [ "$(printf '%s' "$_doc" | jq -r '.execution | has("canonical_project")')" = "false" ] \
    || { _fail "execution deveria omitir canonical_project quando nao setado" ""; return 1; }
  [ "$(printf '%s' "$_doc" | jq -r '.execution | has("session_name")')" = "false" ] \
    || { _fail "execution deveria omitir session_name quando nao setado" ""; return 1; }
}

scenario_sqlite_read_e4_accumulated_metrics_agregado() {
  # E4: accumulated_metrics MUST ser agregacao das tabelas no momento do
  # export, nao um contador materializado.
  _sd="$TMPDIR_TEST/migrated"
  _seed_sqlite_backend "$_sd" || return 1
  sqlite3 "$_sd/state.db" "
    INSERT INTO wave (id,execution_id,seq,started_at,finished_at,tool_calls,wallclock_seconds,termination_reason)
      VALUES ('onda-001','exec-1',1,'2026-07-30T00:00:00Z','2026-07-30T00:05:00Z',10,300,'etapa_concluida_avancando');
    INSERT INTO wave (id,execution_id,seq,started_at,finished_at,tool_calls,wallclock_seconds,termination_reason)
      VALUES ('onda-002','exec-1',2,'2026-07-30T00:05:00Z','2026-07-30T00:09:00Z',5,240,'etapa_concluida_avancando');
    INSERT INTO decision (id,execution_id,wave_id,timestamp,agent,stage,context,options_considered,choice,rationale,justification_score)
      VALUES ('dec-001','exec-1','onda-001','2026-07-30T00:01:00Z','tester','specify','contexto de teste com pelo menos vinte caracteres','[\"a\",\"b\"]','a','justificativa de teste com pelo menos vinte caracteres',2);
    INSERT INTO decision (id,execution_id,wave_id,timestamp,agent,stage,context,options_considered,choice,rationale,justification_score)
      VALUES ('dec-002','exec-1','onda-002','2026-07-30T00:06:00Z','tester','plan','contexto de teste com pelo menos vinte caracteres','[\"a\",\"b\"]','a','justificativa de teste com pelo menos vinte caracteres',2);
    INSERT INTO human_block (id,execution_id,decision_id,question,context_for_answer,status,triggered_at)
      VALUES ('block-001','exec-1','dec-001','pergunta de teste com pelo menos vinte caracteres','contexto para resposta','aguardando','2026-07-30T00:02:00Z');
  " || { _fail "seed multi-onda falhou" ""; return 1; }

  capture "$SCRIPT" read --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "read exit" "$_CAPTURED_STDERR"; return 1; }
  _doc="$_CAPTURED_STDOUT"

  [ "$(printf '%s' "$_doc" | jq -r '.accumulated_metrics.waves_total')" = "2" ] \
    || { _fail "waves_total" "$(printf '%s' "$_doc" | jq -r '.accumulated_metrics.waves_total')"; return 1; }
  [ "$(printf '%s' "$_doc" | jq -r '.accumulated_metrics.tool_calls_total')" = "15" ] \
    || { _fail "tool_calls_total" "$(printf '%s' "$_doc" | jq -r '.accumulated_metrics.tool_calls_total')"; return 1; }
  [ "$(printf '%s' "$_doc" | jq -r '.accumulated_metrics.wallclock_total_seconds')" = "540" ] \
    || { _fail "wallclock_total_seconds" "$(printf '%s' "$_doc" | jq -r '.accumulated_metrics.wallclock_total_seconds')"; return 1; }
  [ "$(printf '%s' "$_doc" | jq -r '.accumulated_metrics.decisions_total')" = "2" ] \
    || { _fail "decisions_total" "$(printf '%s' "$_doc" | jq -r '.accumulated_metrics.decisions_total')"; return 1; }
  [ "$(printf '%s' "$_doc" | jq -r '.accumulated_metrics.human_blocks_total')" = "1" ] \
    || { _fail "human_blocks_total" "$(printf '%s' "$_doc" | jq -r '.accumulated_metrics.human_blocks_total')"; return 1; }
}

scenario_sqlite_get_extrai_campo() {
  _sd="$TMPDIR_TEST/migrated"
  _seed_sqlite_backend "$_sd" || return 1
  capture "$SCRIPT" get --state-dir "$_sd" --field '.current_stage'
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "get exit" "$_CAPTURED_STDERR"; return 1; }
  [ "$_CAPTURED_STDOUT" = "specify" ] || { _fail "get .current_stage" "obtido '$_CAPTURED_STDOUT'"; return 1; }
}

scenario_sqlite_set_top_level_scalar_conhecido() {
  _sd="$TMPDIR_TEST/migrated"
  _seed_sqlite_backend "$_sd" || return 1
  capture "$SCRIPT" set --state-dir "$_sd" --field '.current_stage' --value '"plan"'
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "set exit" "$_CAPTURED_STDERR"; return 1; }
  capture "$SCRIPT" get --state-dir "$_sd" --field '.current_stage'
  [ "$_CAPTURED_STDOUT" = "plan" ] || { _fail "set nao persistiu" "obtido '$_CAPTURED_STDOUT'"; return 1; }
}

scenario_sqlite_set_campo_novo_cai_em_extra_fields() {
  # Fidelidade de round-trip (C1) para campos de topo ainda nao modelados
  # como coluna dedicada (gap documentado entre export.md e data-model.md).
  _sd="$TMPDIR_TEST/migrated"
  _seed_sqlite_backend "$_sd" || return 1
  capture "$SCRIPT" set --state-dir "$_sd" --field '.next_retrospective_milestone' --value '25'
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "set extra_fields exit" "$_CAPTURED_STDERR"; return 1; }
  capture "$SCRIPT" get --state-dir "$_sd" --field '.next_retrospective_milestone'
  [ "$_CAPTURED_STDOUT" = "25" ] || { _fail "extra_fields nao persistiu" "obtido '$_CAPTURED_STDOUT'"; return 1; }
}

scenario_sqlite_set_campo_aninhado_nao_modelado_falha_alto() {
  # Anti-silent-data-loss: path aninhado sob um campo NAO modelado nao tem
  # fallback seguro (mesclaria dentro de extra_fields.execution e seria
  # sombreado pela reconstrucao real na leitura) — deve falhar alto, nunca
  # silenciosamente perder o dado.
  _sd="$TMPDIR_TEST/migrated"
  _seed_sqlite_backend "$_sd" || return 1
  capture "$SCRIPT" set --state-dir "$_sd" --field '.execution.algum_campo_novo' --value '1'
  [ "$_CAPTURED_EXIT" != 0 ] || { _fail "set aninhado nao modelado deveria falhar" "obtido exit 0"; return 1; }
}

scenario_sqlite_set_events_substitui_array_completo() {
  _sd="$TMPDIR_TEST/migrated"
  _seed_sqlite_backend "$_sd" || return 1
  capture "$SCRIPT" set --state-dir "$_sd" --field '.events' \
    --value '[{"event_type":"lock_contention","timestamp":"2026-07-30T00:00:00Z"},{"event_type":"schedule_wait","timestamp":"2026-07-30T00:01:00Z","description":"aguardando"}]'
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "set .events exit" "$_CAPTURED_STDERR"; return 1; }
  capture "$SCRIPT" get --state-dir "$_sd" --field '.events | length'
  [ "$_CAPTURED_STDOUT" = "2" ] || { _fail "events length" "obtido '$_CAPTURED_STDOUT'"; return 1; }
  capture "$SCRIPT" get --state-dir "$_sd" --field '.events[1].description'
  [ "$_CAPTURED_STDOUT" = "aguardando" ] || { _fail "events[1].description" "obtido '$_CAPTURED_STDOUT'"; return 1; }
  capture "$SCRIPT" get --state-dir "$_sd" --field '.events[0] | has("description")'
  [ "$_CAPTURED_STDOUT" = "false" ] || { _fail "events[0] nao deveria ter description (ausente, nao null)" "obtido '$_CAPTURED_STDOUT'"; return 1; }
}

scenario_sqlite_set_waves_field_conhecido_e_extra() {
  _sd="$TMPDIR_TEST/migrated"
  _seed_sqlite_backend "$_sd" || return 1
  sqlite3 "$_sd/state.db" "INSERT INTO wave (id,execution_id,seq,started_at) VALUES ('onda-001','exec-1',1,'2026-07-30T00:00:00Z');" \
    || { _fail "seed wave falhou" ""; return 1; }

  capture "$SCRIPT" set --state-dir "$_sd" --field '.waves[-1].next_wave_scheduled_for' --value '"2026-07-31T00:00:00Z"'
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "set waves[-1] coluna conhecida" "$_CAPTURED_STDERR"; return 1; }

  capture "$SCRIPT" set --state-dir "$_sd" --field '.waves[-1].touched_key_aspects' --value '["foo","bar"]'
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "set waves[-1] campo extra" "$_CAPTURED_STDERR"; return 1; }

  capture "$SCRIPT" get --state-dir "$_sd" --field '.waves[-1].next_wave_scheduled_for'
  [ "$_CAPTURED_STDOUT" = "2026-07-31T00:00:00Z" ] || { _fail "waves[-1].next_wave_scheduled_for" "obtido '$_CAPTURED_STDOUT'"; return 1; }
  capture "$SCRIPT" get --state-dir "$_sd" --field '.waves[-1].touched_key_aspects | join(",")'
  [ "$_CAPTURED_STDOUT" = "foo,bar" ] || { _fail "waves[-1].touched_key_aspects" "obtido '$_CAPTURED_STDOUT'"; return 1; }
}

scenario_sqlite_write_full_document_roundtrip() {
  _sd="$TMPDIR_TEST/migrated"
  _seed_sqlite_backend "$_sd" || return 1
  sqlite3 "$_sd/state.db" "INSERT INTO wave (id,execution_id,seq,started_at) VALUES ('onda-001','exec-1',1,'2026-07-30T00:00:00Z');" \
    || { _fail "seed wave falhou" ""; return 1; }

  _doc=$("$SCRIPT" read --state-dir "$_sd")
  _newdoc=$(printf '%s' "$_doc" | jq '
    .current_stage = "checklist"
    | .decisions += [{"id":"dec-001","wave_id":"onda-001","timestamp":"2026-07-30T00:02:00Z","agent":"tester","stage":"specify","context":"contexto de teste com pelo menos vinte caracteres","options_considered":["a","b"],"choice":"a","rationale":"justificativa de teste com pelo menos vinte caracteres","justification_score":2,"evidence":null,"references":null,"originating_artifact":null}]
    | .tasks += [{"task_id":"1.1","title":"t","wave_id":"onda-001","outcome":"pass","tests_run":1,"tests_passed":1,"lint_ok":true,"touched_files":["a.sh"],"recorded_at":"2026-07-30T00:04:00Z","source":"execute-task"}]
  ')
  # capture roda o comando do lado direito de um pipe DENTRO de um subshell
  # em sh/dash — as variaveis _CAPTURED_* setadas la nao propagam de volta.
  # Idioma correto (ja usado por scenario_write_recusa_json_invalido acima):
  # gravar o payload em arquivo e envolver TODO o pipeline num unico
  # `sh -c`, que passa a ser o comando capturado (nao o alvo de um pipe).
  _newdoc_file="$TMPDIR_TEST/newdoc.json"
  printf '%s' "$_newdoc" > "$_newdoc_file"
  capture sh -c "cat '$_newdoc_file' | '$SCRIPT' write --state-dir '$_sd'"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "write exit" "$_CAPTURED_STDERR"; return 1; }

  capture "$SCRIPT" get --state-dir "$_sd" --field '.current_stage'
  [ "$_CAPTURED_STDOUT" = "checklist" ] || { _fail "write nao persistiu current_stage" "obtido '$_CAPTURED_STDOUT'"; return 1; }
  capture "$SCRIPT" get --state-dir "$_sd" --field '.decisions | length'
  [ "$_CAPTURED_STDOUT" = "1" ] || { _fail "write nao persistiu decisions" "obtido '$_CAPTURED_STDOUT'"; return 1; }
  capture "$SCRIPT" get --state-dir "$_sd" --field '.tasks[0].outcome'
  [ "$_CAPTURED_STDOUT" = "pass" ] || { _fail "write nao persistiu tasks" "obtido '$_CAPTURED_STDOUT'"; return 1; }
}

scenario_sqlite_sha256_verify_ok_via_integrity_check() {
  _sd="$TMPDIR_TEST/migrated"
  _seed_sqlite_backend "$_sd" || return 1
  capture "$SCRIPT" sha256-verify --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "sha256-verify ok" "$_CAPTURED_STDERR"; return 1; }
}

scenario_sqlite_sha256_verify_corrompido_falha() {
  _sd="$TMPDIR_TEST/migrated"
  _seed_sqlite_backend "$_sd" || return 1
  _sz=$(wc -c < "$_sd/state.db")
  _half=$((_sz / 2))
  dd if="$_sd/state.db" of="$_sd/state.db.trunc" bs=1 count="$_half" 2>/dev/null
  mv "$_sd/state.db.trunc" "$_sd/state.db"
  capture "$SCRIPT" sha256-verify --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" != 0 ] || { _fail "sha256-verify deveria falhar sob corrupcao" "obtido exit 0"; return 1; }
}

scenario_sqlite_sha256_update_e_noop_com_exit_0() {
  _sd="$TMPDIR_TEST/migrated"
  _seed_sqlite_backend "$_sd" || return 1
  capture "$SCRIPT" sha256-update --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "sha256-update sob sqlite deveria ser exit 0 (C7)" "$_CAPTURED_STDERR"; return 1; }
  [ ! -f "$_sd/state.json.sha256" ] || { _fail "sha256-update sob sqlite nao deveria criar state.json.sha256" ""; return 1; }
}

# Task 7.1.3 (contracts/primitives.md §C7, dec-025/D4-a FECHADA, block-002):
# edicao externa bem-formada (UPDATE direto via sqlite3, sem quebrar a
# estrutura do banco) NAO e detectada por PRAGMA integrity_check. Este e o
# comportamento ACEITO e DOCUMENTADO (nao um bug) — cenario 7.a do
# quickstart.md. O assert correto e "exit 0 mesmo apos edicao bem-formada",
# registrando o limite conhecido do mecanismo (modelo de ameaca: operador
# local confiavel).
scenario_sqlite_sha256_verify_edicao_bem_formada_nao_detectada() {
  _sd="$TMPDIR_TEST/migrated"
  _seed_sqlite_backend "$_sd" || return 1
  sqlite3 "$_sd/state.db" "
    INSERT INTO wave (id,execution_id,seq,started_at) VALUES ('onda-001','exec-1',1,'2026-07-30T00:00:00Z');
    INSERT INTO decision (id,execution_id,wave_id,timestamp,agent,stage,context,options_considered,choice,rationale,justification_score)
      VALUES ('dec-001','exec-1','onda-001','2026-07-30T00:01:00Z','tester','specify','contexto de teste com pelo menos vinte caracteres','[\"a\",\"b\"]','a','justificativa de teste com pelo menos vinte caracteres',2);
  " || { _fail "seed decision falhou" ""; return 1; }

  capture "$SCRIPT" sha256-verify --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "sha256-verify pre-edicao deveria ser exit 0" "$_CAPTURED_STDERR"; return 1; }

  sqlite3 "$_sd/state.db" "UPDATE decision SET choice='outra' WHERE id='dec-001';" \
    || { _fail "UPDATE bem-formado falhou" ""; return 1; }

  capture "$SCRIPT" sha256-verify --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] \
    || { _fail "regresso documentado (D4-a/dec-025): integrity_check deveria seguir exit 0 apos UPDATE bem-formado" "$_CAPTURED_STDERR"; return 1; }
}

# ---- Paridade C1 (task 3.2.4): mesma sequencia de operacoes, dois backends,
# mesmo stdout/exit code observavel nos pontos comparaveis ----
scenario_sqlite_paridade_get_set_com_backend_json() {
  # Backend JSON: init normal + set + get.
  _sd_json="$TMPDIR_TEST/parity-json"
  capture "$SCRIPT" init --state-dir "$_sd_json" --execucao-id "exec-parity" \
    --projeto-alvo-path "/tmp/proj" --descricao "descricao de paridade valida"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "paridade: init json" "$_CAPTURED_STDERR"; return 1; }
  capture "$SCRIPT" set --state-dir "$_sd_json" --field '.current_stage' --value '"plan"'
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "paridade: set json" "$_CAPTURED_STDERR"; return 1; }
  capture "$SCRIPT" get --state-dir "$_sd_json" --field '.current_stage'
  _json_out="$_CAPTURED_STDOUT"
  _json_rc="$_CAPTURED_EXIT"

  # Backend SQLite: schema + seed equivalente + mesmo set + get.
  _sd_db="$TMPDIR_TEST/parity-sqlite"
  _seed_sqlite_backend "$_sd_db" || return 1
  capture "$SCRIPT" set --state-dir "$_sd_db" --field '.current_stage' --value '"plan"'
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "paridade: set sqlite" "$_CAPTURED_STDERR"; return 1; }
  capture "$SCRIPT" get --state-dir "$_sd_db" --field '.current_stage'
  _db_out="$_CAPTURED_STDOUT"
  _db_rc="$_CAPTURED_EXIT"

  [ "$_json_rc" = "$_db_rc" ] || { _fail "paridade exit code" "json=$_json_rc sqlite=$_db_rc"; return 1; }
  [ "$_json_out" = "$_db_out" ] || { _fail "paridade stdout" "json='$_json_out' sqlite='$_db_out'"; return 1; }
}

scenario_sqlite_paridade_sha256_verify_exit_0_ok() {
  # sha256-verify: exit 0 em ambos os backends quando integro (C1/C7).
  _sd_json="$TMPDIR_TEST/parity-sha-json"
  capture "$SCRIPT" init --state-dir "$_sd_json" --execucao-id "exec-parity-sha" \
    --projeto-alvo-path "/tmp/proj" --descricao "descricao de paridade valida"
  capture "$SCRIPT" sha256-verify --state-dir "$_sd_json"
  _json_rc="$_CAPTURED_EXIT"

  _sd_db="$TMPDIR_TEST/parity-sha-sqlite"
  _seed_sqlite_backend "$_sd_db" || return 1
  capture "$SCRIPT" sha256-verify --state-dir "$_sd_db"
  _db_rc="$_CAPTURED_EXIT"

  [ "$_json_rc" = 0 ] || { _fail "paridade sha256-verify json exit" "obtido $_json_rc"; return 1; }
  [ "$_db_rc" = 0 ] || { _fail "paridade sha256-verify sqlite exit" "obtido $_db_rc"; return 1; }
}

# Task 4.1.1/4.2.2 (FASE 4): branch de selecao de backend explicito por C2 —
# "existe state.db => SQLite; um state.json coexistente e export/legado e
# NUNCA consultado como fonte". Prova positiva: com os dois arquivos
# presentes e VALORES DIVERGENTES, get/set devem refletir sempre o state.db,
# e set nao deve tocar o state.json coexistente.
scenario_c2_state_json_coexistente_ignorado_quando_state_db_presente() {
  _sd="$TMPDIR_TEST/c2-coexist"
  _seed_sqlite_backend "$_sd" || return 1  # current_stage='specify' no state.db

  # state.json divergente no MESMO diretorio (simula export/legado stale).
  mkdir -p "$_sd"
  printf '{"current_stage":"clarify"}\n' > "$_sd/state.json"

  capture "$SCRIPT" get --state-dir "$_sd" --field '.current_stage'
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "c2 get exit" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "specify" \
    || { _fail "c2: get deveria refletir state.db, nao o state.json coexistente" "obtido $_CAPTURED_STDOUT"; return 1; }

  capture "$SCRIPT" set --state-dir "$_sd" --field '.current_stage' --value '"plan"'
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "c2 set exit" "$_CAPTURED_STDERR"; return 1; }

  capture "$SCRIPT" get --state-dir "$_sd" --field '.current_stage'
  assert_stdout_contains "plan" \
    || { _fail "c2: set/get pos-mutacao deveria refletir state.db" "obtido $_CAPTURED_STDOUT"; return 1; }

  # o state.json coexistente permanece intocado (script nunca escreve nele
  # quando o backend e sqlite).
  _stale_now=$(cat "$_sd/state.json")
  [ "$_stale_now" = '{"current_stage":"clarify"}' ] \
    || { _fail "c2: state.json coexistente foi modificado" "obtido: $_stale_now"; return 1; }
}

# ==== FASE 5 (state-backend-config): init honra a configuracao global ====
# Ref: docs/specs/state-backend-config/tasks.md FASE 5 task 5.2
#      docs/specs/state-backend-config/quickstart.md Scenario 1, 7, 8a/8b

MIN_SQLITE_VER_FASE5="3.45.1"

# _sr_real_sqlite3_adequate: exit 0 se o sqlite3 REAL do ambiente atende o
# minimo exigido — necessario porque `init` sob config sqlite consulta
# `state-backend.sh resolve`, que so retorna effective_backend=sqlite se a
# dependencia REAL for adequada (nao basta sqlite3 estar no PATH).
_sr_real_sqlite3_adequate() {
  command -v sqlite3 >/dev/null 2>&1 || return 1
  _v=$(sqlite3 --version 2>/dev/null | cut -d' ' -f1) || return 1
  _va=$(printf '%s' "$_v" | cut -d'.' -f1); _vb=$(printf '%s' "$_v" | cut -d'.' -f2); _vc=$(printf '%s' "$_v" | cut -d'.' -f3)
  _ma=$(printf '%s' "$MIN_SQLITE_VER_FASE5" | cut -d'.' -f1); _mb=$(printf '%s' "$MIN_SQLITE_VER_FASE5" | cut -d'.' -f2); _mc=$(printf '%s' "$MIN_SQLITE_VER_FASE5" | cut -d'.' -f3)
  [ "${_va:-0}" -gt "${_ma:-0}" ] 2>/dev/null && return 0
  [ "${_va:-0}" -lt "${_ma:-0}" ] 2>/dev/null && return 1
  [ "${_vb:-0}" -gt "${_mb:-0}" ] 2>/dev/null && return 0
  [ "${_vb:-0}" -lt "${_mb:-0}" ] 2>/dev/null && return 1
  [ "${_vc:-0}" -ge "${_mc:-0}" ] 2>/dev/null
}

# 5.2.1 (Scenario 1, passos 5-6): config declara sqlite + dependencia
# adequada -> init cria state.db, NAO cria state.json.
scenario_init_sqlite_config_declarada_cria_state_db_nao_state_json() {
  _sr_real_sqlite3_adequate || { printf '# skip: sqlite3 real >= %s indisponivel\n' "$MIN_SQLITE_VER_FASE5"; return 0; }
  _home="$TMPDIR_TEST/home-fase5-sqlite"
  mkdir -p "$_home/.claude/cstk"
  printf 'state_backend=sqlite\n' > "$_home/.claude/cstk/config"
  _sd="$TMPDIR_TEST/fase5-sqlite"
  capture env HOME="$_home" "$SCRIPT" init --state-dir "$_sd" \
    --execucao-id "exec-fase5-1" --projeto-alvo-path "/tmp/p5" \
    --descricao "descricao de teste com tamanho suficiente para validacao"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "init sob config sqlite" "$_CAPTURED_STDERR"; return 1; }
  [ -f "$_sd/state.db" ] || { _fail "state.db nao foi criado" ""; return 1; }
  [ -f "$_sd/state.json" ] && { _fail "state.json NAO deveria ser criado sob backend sqlite" ""; return 1; }
  capture env HOME="$_home" "$SCRIPT" get --state-dir "$_sd" --field '.execution.status'
  assert_stdout_contains "em_andamento" || return 1
}

# 5.2.2 (Scenario 7, passos 4-5): config ausente OU invalida (lixo
# nao-interpretavel) -> init cria state.json normalmente, sem falhar.
scenario_init_config_ausente_ou_invalida_cria_state_json_sem_falhar() {
  _home_ausente="$TMPDIR_TEST/home-fase5-ausente"
  mkdir -p "$_home_ausente"
  _sd_a="$TMPDIR_TEST/fase5-config-ausente"
  capture env HOME="$_home_ausente" "$SCRIPT" init --state-dir "$_sd_a" \
    --execucao-id "exec-fase5-2a" --projeto-alvo-path "/tmp/p5a" \
    --descricao "descricao de teste com tamanho suficiente para validacao"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "init sem config" "$_CAPTURED_STDERR"; return 1; }
  [ -f "$_sd_a/state.json" ] || { _fail "state.json nao foi criado (config ausente)" ""; return 1; }
  [ -f "$_sd_a/state.db" ] && { _fail "state.db nao deveria existir (config ausente)" ""; return 1; }

  _home_lixo="$TMPDIR_TEST/home-fase5-lixo"
  mkdir -p "$_home_lixo/.claude/cstk"
  printf 'isto nao e key=value valido\n' > "$_home_lixo/.claude/cstk/config"
  _sd_b="$TMPDIR_TEST/fase5-config-invalida"
  capture env HOME="$_home_lixo" "$SCRIPT" init --state-dir "$_sd_b" \
    --execucao-id "exec-fase5-2b" --projeto-alvo-path "/tmp/p5b" \
    --descricao "descricao de teste com tamanho suficiente para validacao"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "init com config invalida" "$_CAPTURED_STDERR"; return 1; }
  [ -f "$_sd_b/state.json" ] || { _fail "state.json nao foi criado (config invalida)" ""; return 1; }
  # ANTI-PADRAO evitado: um `[ ... ] && { ... }` como ULTIMA instrucao da
  # funcao faria o exit code do proprio teste (1, quando a condicao e falsa
  # — o caso PASSANDO aqui) virar o retorno da funcao inteira, marcando um
  # scenario correto como FAIL. `return 0` explicito fecha o caminho feliz.
  if [ -f "$_sd_b/state.db" ]; then
    _fail "state.db nao deveria existir (config invalida)" ""
    return 1
  fi
  return 0
}

# 5.2.3 (Scenario 8a/8b, FR-006): projeto com state.json OU state.db
# pre-existente -> guardas de recusa preservadas independentemente da
# config global (config global NUNCA dispara/forca migracao).
scenario_init_guardas_preservadas_independente_da_config_global() {
  # 8a: state.json ja existente + config global declara sqlite -> recusa.
  _sd_json="$TMPDIR_TEST/fase5-guarda-json"
  capture env HOME="$TMPDIR_TEST/home-vazio-guarda" "$SCRIPT" init --state-dir "$_sd_json" \
    --execucao-id "exec-fase5-3a" --projeto-alvo-path "/tmp/p5c" \
    --descricao "descricao de teste com tamanho suficiente para validacao"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "fixture: init inicial (sem config)" "$_CAPTURED_STDERR"; return 1; }
  [ -f "$_sd_json/state.json" ] || { _fail "fixture: state.json deveria existir" ""; return 1; }

  _home_sqlite="$TMPDIR_TEST/home-fase5-guardas-sqlite"
  mkdir -p "$_home_sqlite/.claude/cstk"
  printf 'state_backend=sqlite\n' > "$_home_sqlite/.claude/cstk/config"
  capture env HOME="$_home_sqlite" "$SCRIPT" init --state-dir "$_sd_json" \
    --execucao-id "exec-fase5-3a-retry" --projeto-alvo-path "/tmp/p5c" \
    --descricao "descricao de teste com tamanho suficiente para validacao"
  [ "$_CAPTURED_EXIT" != 0 ] || { _fail "8a: init com state.json ja existente + config sqlite deveria recusar" "exit=0"; return 1; }
  assert_stderr_contains "state.json ja existe" || return 1

  # 8b: state.db ja existente (projeto migrado) + config global declara
  # json -> recusa (guarda independe da config).
  _home_json="$TMPDIR_TEST/home-fase5-guardas-json"
  mkdir -p "$_home_json/.claude/cstk"
  printf 'state_backend=json\n' > "$_home_json/.claude/cstk/config"
  _sd_db="$TMPDIR_TEST/fase5-guarda-db"
  _seed_sqlite_backend "$_sd_db" || return 1
  capture env HOME="$_home_json" "$SCRIPT" init --state-dir "$_sd_db" \
    --execucao-id "exec-fase5-3b" --projeto-alvo-path "/tmp/p5d" \
    --descricao "descricao de teste com tamanho suficiente para validacao"
  [ "$_CAPTURED_EXIT" != 0 ] || { _fail "8b: init com state.db ja existente + config json deveria recusar" "exit=0"; return 1; }
  assert_stderr_contains "state.db ja existe" || return 1
}

fi # sqlite3 disponivel

# ==== set aceita literais JSON falsy (state-db-runtime-parity 2.4.3) ====
# Regressao: a validacao de --value usava `jq -e`, que retorna exit 1 para
# output falsy (null/false) — valores JSON VALIDOS e legitimos (ex.:
# `.briefing_cache = null` do state-cache.sh invalidate). Sem -e, parse
# invalido segue detectado (jq exit 2).
scenario_set_aceita_null_e_false_como_valor() {
  _sd="$TMPDIR_TEST/state-falsy"
  _init_default "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "init" "$_CAPTURED_STDERR"; return 1; }
  capture "$SCRIPT" set --state-dir "$_sd" --field '.briefing_cache' --value 'null'
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "set null" "exit $_CAPTURED_EXIT: $_CAPTURED_STDERR"; return 1; }
  capture "$SCRIPT" set --state-dir "$_sd" --field '.atomic_commit_enabled' --value 'false'
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "set false" "exit $_CAPTURED_EXIT: $_CAPTURED_STDERR"; return 1; }
  _v=$(jq -r '.atomic_commit_enabled' "$_sd/state.json")
  [ "$_v" = "false" ] || { _fail "false persistido" "obtido $_v"; return 1; }
  # Parse invalido continua recusado
  capture "$SCRIPT" set --state-dir "$_sd" --field '.current_stage' --value 'nao-e-json'
  [ "$_CAPTURED_EXIT" != 0 ] || { _fail "set invalido" "aceitou valor nao-JSON"; return 1; }
}

run_all_scenarios
