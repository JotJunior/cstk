#!/bin/sh
# test_state.sh — cobre cli/lib/state.sh (subcomando `cstk state`).
#
# Ref: docs/specs/state-db-foundation/tasks.md FASE 6, task 6.1.2
#      docs/specs/state-db-foundation/contracts/migration.md §Nomeacao
#
# ESCOPO: esta lib e uma SUPERFICIE DE DELEGACAO. O comportamento da migracao
# em si (M1..M6) e coberto por tests/test_state-db-migrate.sh; aqui cobrimos o
# contrato da fronteira: resolucao do script delegado, repasse VERBATIM de
# flags e exit codes, e o tratamento de uso incorreto.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

CSTK_BIN="$REPO_ROOT/cli/cstk"
CSTK_LIB_DIR="$REPO_ROOT/cli/lib"
STATE_RW="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/state-rw.sh"

# _cstk_state ARGS... -> roda `cstk state ARGS` com o layout de repo.
_cstk_state() {
  CSTK_LIB="$CSTK_LIB_DIR" sh "$CSTK_BIN" state "$@"
}

scenario_state_sem_subcomando_mostra_uso() {
  capture _cstk_state
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "uso deveria sair 0" "exit=$_CAPTURED_EXIT"; return 1; }
  case "$_CAPTURED_STDOUT" in
    *migrate*) : ;;
    *) _fail "uso nao documenta migrate" "$_CAPTURED_STDOUT"; return 1 ;;
  esac
}

scenario_state_help_documenta_exit_codes() {
  capture _cstk_state --help
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "--help deveria sair 0" "exit=$_CAPTURED_EXIT"; return 1; }
  case "$_CAPTURED_STDOUT" in
    *"recusado por pre-condicao"*) : ;;
    *) _fail "help nao documenta o exit 3 (recusa)" "$_CAPTURED_STDOUT"; return 1 ;;
  esac
}

scenario_state_subcomando_desconhecido_exit_2() {
  capture _cstk_state naoexiste
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "subcomando invalido deveria ser exit 2" "exit=$_CAPTURED_EXIT"; return 1; }
}

# Repasse VERBATIM do exit 2 (uso incorreto) vindo do script delegado.
scenario_state_migrate_sem_state_dir_repassa_exit_2() {
  capture _cstk_state migrate
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "--state-dir ausente deveria repassar exit 2" "exit=$_CAPTURED_EXIT"; return 1; }
}

# Repasse VERBATIM do exit 3 (RECUSA por pre-condicao M1) — a distincao entre
# "recusado" e "falhou" e o ponto do contrato de exit codes desta lib.
scenario_state_migrate_recusa_repassa_exit_3() {
  if ! command -v jq >/dev/null 2>&1 || ! command -v sqlite3 >/dev/null 2>&1; then
    return 0
  fi
  _sd="$TMPDIR_TEST/sem-state-json"
  mkdir -p "$_sd"
  capture _cstk_state migrate --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 3 ] || { _fail "recusa deveria repassar exit 3" "exit=$_CAPTURED_EXIT stderr=$_CAPTURED_STDERR"; return 1; }
}

# Caminho feliz de ponta a ponta pela superficie do CLI (nao so pelo script).
scenario_state_migrate_caminho_feliz_pelo_cli() {
  if ! command -v jq >/dev/null 2>&1 || ! command -v sqlite3 >/dev/null 2>&1; then
    return 0
  fi
  _sd="$TMPDIR_TEST/ok"
  mkdir -p "$_sd"
  cat > "$_sd/state.json" <<'JSON'
{
  "schema_version": "1.0.0",
  "short_name": "cli-fixture",
  "execution": {
    "id": "exec-cli-001",
    "target_project_path": "/tmp/projeto",
    "target_project_description": "descricao de fixture com tamanho suficiente",
    "status": "concluida",
    "termination_reason": "concluido",
    "started_at": "2026-07-30T10:00:00Z",
    "finished_at": "2026-07-30T12:00:00Z"
  },
  "current_stage": "review-task",
  "next_instruction": "nada a fazer",
  "external_urls_whitelist": [],
  "circular_movement_history": [],
  "initial_key_aspects": ["cli", "state"],
  "accumulated_metrics": {
    "waves_total": 0,
    "tool_calls_total": 0,
    "wallclock_total_seconds": 0,
    "max_depth_reached": 1,
    "subagents_spawned": 0,
    "decisions_total": 0,
    "human_blocks_total": 0,
    "global_skill_suggestions_total": 0,
    "toolkit_issues_opened": 0
  },
  "budgets": {
    "max_recursion": 3,
    "current_subagent_depth": 1,
    "max_retro_executions_per_feature": 2,
    "retro_executions_consumed": 0,
    "max_cycles_per_stage": 5,
    "cycles_consumed_current_stage": 0,
    "tool_calls_threshold_wave": 80,
    "wallclock_threshold_seconds": 5400,
    "state_size_threshold_bytes": 1048576
  },
  "waves": [],
  "decisions": [],
  "human_blocks": [],
  "tasks": [],
  "events": []
}
JSON
  "$STATE_RW" sha256-update --state-dir "$_sd" >/dev/null 2>&1

  capture _cstk_state migrate --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "migracao pelo CLI" "exit=$_CAPTURED_EXIT stderr=$_CAPTURED_STDERR"; return 1; }
  [ -f "$_sd/state.db" ] || { _fail "state.db nao publicado pelo CLI" ""; return 1; }
  [ -f "$_sd/state.json" ] || { _fail "state.json apagado (M6)" ""; return 1; }
}

# A resolucao do script delegado NAO pode depender exclusivamente de
# ~/.claude (licao de campo de recall_secrets_filter_path): com HOME falso e
# CSTK_LIB apontando para a arvore do repo, a camada (2) deve resolver.
scenario_resolucao_do_script_independe_de_home_instalado() {
  _out=$(HOME="$TMPDIR_TEST/home-vazio" CSTK_LIB="$CSTK_LIB_DIR" sh -c '
    . "$CSTK_LIB/state.sh"
    _state_migrate_script_path
  ' 2>/dev/null) || { _fail "resolucao falhou com HOME vazio" ""; return 1; }
  [ -n "$_out" ] || { _fail "caminho vazio" ""; return 1; }
  [ -f "$_out" ] || { _fail "caminho resolvido nao existe" "$_out"; return 1; }
}

# `cstk state` esta registrado nas superficies de descoberta do CLI.
scenario_state_aparece_no_help_geral() {
  capture sh -c "CSTK_LIB='$CSTK_LIB_DIR' sh '$CSTK_BIN' --help"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "help geral" "$_CAPTURED_STDERR"; return 1; }
  case "$_CAPTURED_STDOUT" in
    *"  state "*) : ;;
    *) _fail "cstk --help nao lista o comando state" ""; return 1 ;;
  esac
}

scenario_help_topico_state_sai_zero() {
  capture sh -c "CSTK_LIB='$CSTK_LIB_DIR' sh '$CSTK_BIN' help state"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "cstk help state" "$_CAPTURED_STDERR"; return 1; }
}

# ---------------------------------------------------------------------------
# `cstk state enable-sqlite` (feature state-backend-config, FASE 4, task
# 4.2.3). ESCOPO: mesma disciplina de fronteira de `migrate` acima — o
# comportamento exaustivo (parsing/allowlist/escrita atomica/P8) de
# enable-sqlite ja e coberto por tests/test_state-backend.sh; aqui
# confirmamos que a delegacao via `cstk state` (cli/lib/state.sh ->
# cli/lib/config.sh -> state-backend.sh) repassa env/args/exit code
# corretamente ponta-a-ponta.
# ---------------------------------------------------------------------------

MIN_SQLITE_VER="3.45.1"

# _es_real_sqlite3_adequate: exit 0 se o sqlite3 REAL do ambiente for
# suficiente para o happy-path/idempotencia (que dependem de dependencia
# adequada de verdade, nao de stub).
_es_real_sqlite3_adequate() {
  command -v sqlite3 >/dev/null 2>&1 || return 1
  _v=$(sqlite3 --version 2>/dev/null | cut -d' ' -f1) || return 1
  _va=$(printf '%s' "$_v" | cut -d'.' -f1); _vb=$(printf '%s' "$_v" | cut -d'.' -f2); _vc=$(printf '%s' "$_v" | cut -d'.' -f3)
  _ma=$(printf '%s' "$MIN_SQLITE_VER" | cut -d'.' -f1); _mb=$(printf '%s' "$MIN_SQLITE_VER" | cut -d'.' -f2); _mc=$(printf '%s' "$MIN_SQLITE_VER" | cut -d'.' -f3)
  [ "${_va:-0}" -gt "${_ma:-0}" ] 2>/dev/null && return 0
  [ "${_va:-0}" -lt "${_ma:-0}" ] 2>/dev/null && return 1
  [ "${_vb:-0}" -gt "${_mb:-0}" ] 2>/dev/null && return 0
  [ "${_vb:-0}" -lt "${_mb:-0}" ] 2>/dev/null && return 1
  [ "${_vc:-0}" -ge "${_mc:-0}" ] 2>/dev/null
}

# _es_isolated_bin_dir: PATH isolado (symlinks explicitos, sem sqlite3) —
# mesmo GOTCHA/tecnica de _sb_isolated_bin_dir em test_state-backend.sh: um
# PATH="stub:$PATH" nao esconde um sqlite3 ja presente adiante no PATH.
# Lista de comandos MAIOR que a de test_state-backend.sh porque aqui
# atravessamos o binario `cstk` inteiro (dispatch usa sed/tr/grep/dirname),
# nao so state-backend.sh.
_es_isolated_bin_dir() {
  _eibd="$TMPDIR_TEST/no-sqlite3-bin"
  if [ ! -d "$_eibd" ]; then
    mkdir -p "$_eibd"
    for _eicmd in cut mktemp mv chmod mkdir rm dirname basename cat sh \
                  sed tr grep awk head; do
      _eicmd_path=$(command -v "$_eicmd" 2>/dev/null) || continue
      ln -sf "$_eicmd_path" "$_eibd/$_eicmd"
    done
  fi
  printf '%s' "$_eibd"
}

scenario_enable_sqlite_help_lista_subcomando() {
  capture _cstk_state --help
  case "$_CAPTURED_STDOUT" in
    *enable-sqlite*) : ;;
    *) _fail "--help nao documenta enable-sqlite" "$_CAPTURED_STDOUT"; return 1 ;;
  esac
}

# Recusa por sqlite3 ausente — repasse verbatim do exit de pre-condicao
# (state-backend.sh usa exit 3; a fronteira nao pode normalizar para outro
# valor) e da config byte-a-byte intocada.
scenario_enable_sqlite_recusa_sqlite3_ausente_repassa_pela_cli() {
  _home="$TMPDIR_TEST/home"
  mkdir -p "$_home"
  _isolated=$(_es_isolated_bin_dir)
  capture env HOME="$_home" PATH="$_isolated" CSTK_LIB="$CSTK_LIB_DIR" \
    sh "$CSTK_BIN" state enable-sqlite
  [ "$_CAPTURED_EXIT" = 3 ] || { _fail "recusa por ausencia deveria repassar exit 3" "exit=$_CAPTURED_EXIT stderr=$_CAPTURED_STDERR"; return 1; }
  assert_stderr_contains "sqlite3" || return 1
  [ -e "$_home/.claude/cstk/config" ] && { _fail "config" "nao deveria ter sido criada"; return 1; }
  return 0
}

# Recusa por versao abaixo do minimo — stub controlado (nao depende do
# ambiente); confirma que a mensagem cita minima e detectada, verbatim.
scenario_enable_sqlite_recusa_versao_baixa_repassa_pela_cli() {
  _home="$TMPDIR_TEST/home"
  mkdir -p "$_home"
  _stub="$TMPDIR_TEST/stub-low"
  mkdir -p "$_stub"
  cat > "$_stub/sqlite3" <<'EOF'
#!/bin/sh
printf '3.40.0 2024-01-01 00:00:00 deadbeef\n'
EOF
  chmod +x "$_stub/sqlite3"
  capture env HOME="$_home" PATH="$_stub:$PATH" CSTK_LIB="$CSTK_LIB_DIR" \
    sh "$CSTK_BIN" state enable-sqlite
  [ "$_CAPTURED_EXIT" = 3 ] || { _fail "recusa por versao baixa deveria repassar exit 3" "exit=$_CAPTURED_EXIT stderr=$_CAPTURED_STDERR"; return 1; }
  assert_stderr_contains "3.45.1" || return 1
  assert_stderr_contains "3.40.0" || return 1
  [ -e "$_home/.claude/cstk/config" ] && { _fail "config" "nao deveria ter sido criada"; return 1; }
  return 0
}

# Recusa por runtime do catalogo instalado incapaz (P8) — pelo CLI, com
# CSTK_LIB apontando para o repo real (capaz) e HOME fixture com catalogo
# instalado incapaz; catalogo instalado MUST prevalecer.
scenario_enable_sqlite_recusa_runtime_incapaz_repassa_pela_cli() {
  _es_real_sqlite3_adequate || { printf '# skip: sqlite3 real >= %s indisponivel\n' "$MIN_SQLITE_VER"; return 0; }
  _home="$TMPDIR_TEST/home"
  mkdir -p "$_home/.claude/skills/agente-00c-runtime/scripts"
  cat > "$_home/.claude/skills/agente-00c-runtime/scripts/state-backend.sh" <<'EOF'
#!/bin/sh
printf 'subcomando desconhecido\n' >&2
exit 2
EOF
  chmod +x "$_home/.claude/skills/agente-00c-runtime/scripts/state-backend.sh"
  capture env HOME="$_home" CSTK_LIB="$CSTK_LIB_DIR" sh "$CSTK_BIN" state enable-sqlite
  [ "$_CAPTURED_EXIT" = 3 ] || { _fail "runtime incapaz deveria repassar exit 3" "exit=$_CAPTURED_EXIT stderr=$_CAPTURED_STDERR"; return 1; }
  assert_stderr_contains "capability verificado via catalogo-instalado" || return 1
  assert_stderr_contains "cstk update" || return 1
  [ -e "$_home/.claude/cstk/config" ] && { _fail "config" "nao deveria ter sido criada"; return 1; }
  return 0
}

# Caminho feliz + idempotencia ponta-a-ponta pela superficie do CLI.
scenario_enable_sqlite_sucesso_e_idempotencia_pela_cli() {
  _es_real_sqlite3_adequate || { printf '# skip: sqlite3 real >= %s indisponivel\n' "$MIN_SQLITE_VER"; return 0; }
  _home="$TMPDIR_TEST/home"
  mkdir -p "$_home"
  capture env HOME="$_home" CSTK_LIB="$CSTK_LIB_DIR" sh "$CSTK_BIN" state enable-sqlite
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "1a ativacao pelo CLI" "exit=$_CAPTURED_EXIT stderr=$_CAPTURED_STDERR"; return 1; }
  [ -f "$_home/.claude/cstk/config" ] || { _fail "config" "nao foi criada"; return 1; }
  grep -q '^state_backend=sqlite$' "$_home/.claude/cstk/config" \
    || { _fail "config" "esperado state_backend=sqlite, obtido: $(cat "$_home/.claude/cstk/config")"; return 1; }

  capture env HOME="$_home" CSTK_LIB="$CSTK_LIB_DIR" sh "$CSTK_BIN" state enable-sqlite
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "2a ativacao (idempotente) pelo CLI" "exit=$_CAPTURED_EXIT stderr=$_CAPTURED_STDERR"; return 1; }
  _n=$(grep -c '^state_backend=' "$_home/.claude/cstk/config")
  [ "$_n" = 1 ] || { _fail "idempotencia" "esperado 1 linha state_backend=, obtido $_n"; return 1; }
}

run_all_scenarios
