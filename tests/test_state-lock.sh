#!/bin/sh
# test_state-lock.sh — cobre global/skills/agente-00c-runtime/scripts/state-lock.sh.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/state-lock.sh"
RW="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/state-rw.sh"

if ! command -v jq >/dev/null 2>&1; then
  printf '# test_state-lock.sh: jq ausente — pulando suite\n'
  exit 0
fi

scenario_acquire_release_basico() {
  _sd="$TMPDIR_TEST/state"
  capture "$SCRIPT" acquire --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "acquire" "$_CAPTURED_EXIT; $_CAPTURED_STDERR"
    return 1
  fi
  [ -d "$_sd/.lock" ] || { _fail ".lock dir ausente apos acquire" ""; return 1; }
  capture "$SCRIPT" release --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "release" "$_CAPTURED_EXIT"
    return 1
  fi
  [ -d "$_sd/.lock" ] && { _fail ".lock dir presente apos release" ""; return 1; }
  return 0
}

scenario_acquire_semeia_gitignore_no_state_dir() {
  # acquire roda ANTES do state-rw init no fluxo do command pai e pode criar
  # o state-dir: deve semear .gitignore "*" desde o primeiro toque (paridade
  # com _sr_ensure_state_dir). Lock release (rmdir .lock) segue intacto.
  _sd="$TMPDIR_TEST/state-gi"
  capture "$SCRIPT" acquire --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "acquire" "$_CAPTURED_STDERR"; return 1; }
  [ -f "$_sd/.gitignore" ] || { _fail ".gitignore ausente" "acquire criou state-dir sem .gitignore"; return 1; }
  _gi=$(cat "$_sd/.gitignore")
  [ "$_gi" = "*" ] || { _fail ".gitignore conteudo" "esperado '*', obtido '$_gi'"; return 1; }
  capture "$SCRIPT" release --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "release" "$_CAPTURED_EXIT"; return 1; }
  return 0
}

scenario_acquire_duplicado_exit_3() {
  _sd="$TMPDIR_TEST/state"
  capture "$SCRIPT" acquire --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "acquire 1" ""; return 1; }
  capture "$SCRIPT" acquire --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 3 ]; then
    _fail "acquire duplicado exit" "esperado 3, obtido $_CAPTURED_EXIT"
    return 1
  fi
  # Mensagem legada permanece byte-a-byte identica (SC-006, openspec-hygiene).
  assert_stderr_contains "lock ja detido" || return 1
  # Envelope diagnostico aditivo (openspec-hygiene FR-012/FR-015).
  assert_stderr_contains "DIAG|error|lock-contention|" || return 1
}

scenario_release_idempotente() {
  _sd="$TMPDIR_TEST/state"
  mkdir -p "$_sd"
  capture "$SCRIPT" release --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "release sem lock" "esperado 0 (idempotente), obtido $_CAPTURED_EXIT"
    return 1
  fi
  capture "$SCRIPT" release --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "release 2" ""; return 1; }
}

scenario_check_livre_exit_0() {
  _sd="$TMPDIR_TEST/state"
  mkdir -p "$_sd"
  capture "$SCRIPT" check --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "check livre" "$_CAPTURED_EXIT"; return 1; }
}

scenario_check_detido_exit_3() {
  _sd="$TMPDIR_TEST/state"
  capture "$SCRIPT" acquire --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "acquire" ""; return 1; }
  capture "$SCRIPT" check --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 3 ]; then
    _fail "check detido" "esperado 3, obtido $_CAPTURED_EXIT"
    return 1
  fi
  # Mensagem legada permanece byte-a-byte identica (SC-006, openspec-hygiene).
  assert_stderr_contains "lock detido" || return 1
  # Envelope diagnostico aditivo (openspec-hygiene FR-012/FR-015).
  assert_stderr_contains "DIAG|error|lock-contention|" || return 1
}

scenario_locks_independentes_por_state_dir() {
  # Permite invocacoes simultaneas em projetos distintos (2.5.3)
  _sd1="$TMPDIR_TEST/state1"
  _sd2="$TMPDIR_TEST/state2"
  capture "$SCRIPT" acquire --state-dir "$_sd1"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "acquire 1" ""; return 1; }
  capture "$SCRIPT" acquire --state-dir "$_sd2"
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "acquire em outro state-dir" "esperado 0 (independente), obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_check_execution_busy_state_ausente_passa() {
  _sd="$TMPDIR_TEST/state"
  mkdir -p "$_sd"
  capture "$SCRIPT" check-execution-busy --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "busy sem state" "esperado 0, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_check_execution_busy_em_andamento_exit_3() {
  _sd="$TMPDIR_TEST/state"
  capture "$RW" init --state-dir "$_sd" --execucao-id "exec-1" \
    --projeto-alvo-path "/tmp/p" --descricao "POC teste"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "init" "$_CAPTURED_STDERR"; return 1; }
  capture "$SCRIPT" check-execution-busy --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 3 ]; then
    _fail "busy em_andamento" "esperado 3, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "/agente-00c-resume" || return 1
  assert_stderr_contains "/agente-00c-abort" || return 1
}

scenario_check_execution_busy_terminal_passa() {
  _sd="$TMPDIR_TEST/state"
  capture "$RW" init --state-dir "$_sd" --execucao-id "exec-1" \
    --projeto-alvo-path "/tmp/p" --descricao "POC teste"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "init" ""; return 1; }
  # Marca como concluida + terminada_em
  capture "$RW" set --state-dir "$_sd" --field '.execucao.status' --value '"concluida"'
  capture "$RW" set --state-dir "$_sd" --field '.execucao.terminada_em' --value '"2026-05-05T15:00:00Z"'
  capture "$SCRIPT" check-execution-busy --state-dir "$_sd"
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "busy terminal" "esperado 0, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_check_execution_busy_json_caminho_inalterado() {
  # 2.5.3 (FR-004): sob backend JSON o comportamento e identico ao legado —
  # exit 3 e mensagem apontando o proprio state.json (nunca tmp materializado).
  _sd="$TMPDIR_TEST/state-json-path"
  capture "$RW" init --state-dir "$_sd" --execucao-id "exec-1" \
    --projeto-alvo-path "/tmp/p" --descricao "POC teste"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "init" "$_CAPTURED_STDERR"; return 1; }
  [ -f "$_sd/state.json" ] || { _fail "fixture json" "harness deveria ter backend json (HOME sandbox)"; return 1; }
  capture "$SCRIPT" check-execution-busy --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 3 ] || { _fail "busy json" "esperado 3, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "$_sd/state.json" || return 1
}

# --- Cenarios sqlite (state-db-runtime-parity FASE 2 lote 2.5) ------------
# Fixture: init sob config global state_backend=sqlite em HOME proprio
# (padrao test_retro.sh). Requer sqlite3 >= piso do state-db-foundation.

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
    --execucao-id "x-sqlite" --projeto-alvo-path "/tmp/p" \
    --descricao "POC lock sqlite" >/dev/null 2>&1 || return 1
  [ -f "$1/state.db" ] || return 1
}

scenario_sqlite_busy_em_andamento_exit_3() {
  # FR-010: sob state.db com execucao ativa, busy NAO pode degradar para
  # exit 0 (comportamento pre-porte). Mensagem aponta o state.db real.
  _sqlite3_adequate || { printf "# skip: sqlite3 indisponivel\n"; return 0; }
  _sd="$TMPDIR_TEST/state-sqlite"
  _init_sqlite "$_sd" || { _fail "fixture sqlite" "init nao gerou state.db"; return 1; }
  capture "$SCRIPT" check-execution-busy --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 3 ] || { _fail "busy sqlite em_andamento" "esperado 3, obtido $_CAPTURED_EXIT: $_CAPTURED_STDERR"; return 1; }
  assert_stderr_contains "/agente-00c-resume" || return 1
  assert_stderr_contains "$_sd/state.db" || return 1
}

scenario_sqlite_busy_terminal_passa() {
  _sqlite3_adequate || { printf "# skip: sqlite3 indisponivel\n"; return 0; }
  _sd="$TMPDIR_TEST/state-sqlite-term"
  _init_sqlite "$_sd" || { _fail "fixture sqlite" "init nao gerou state.db"; return 1; }
  # Status terminal direto no schema (CHECK exige finished_at junto — o set
  # multi-campo atomico e escopo da FASE 3; fixture manipula via sqlite3,
  # padrao test_state-db-schema.sh).
  capture sqlite3 "$_sd/state.db" \
    "UPDATE execution SET status='concluida', finished_at='2026-08-03T00:00:00Z';"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "fixture UPDATE" "$_CAPTURED_STDERR"; return 1; }
  capture "$SCRIPT" check-execution-busy --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "busy sqlite terminal" "esperado 0, obtido $_CAPTURED_EXIT: $_CAPTURED_STDERR"; return 1; }
}

scenario_sqlite_busy_anti_mirror_state_dir_intacto() {
  # FR-003: a materializacao NUNCA cria arquivo dentro do state-dir (nem
  # state.json espelho, nem tmp).
  _sqlite3_adequate || { printf "# skip: sqlite3 indisponivel\n"; return 0; }
  _sd="$TMPDIR_TEST/state-sqlite-mirror"
  _init_sqlite "$_sd" || { _fail "fixture sqlite" "init nao gerou state.db"; return 1; }
  _antes=$(ls -a "$_sd" | sort)
  capture "$SCRIPT" check-execution-busy --state-dir "$_sd"
  _depois=$(ls -a "$_sd" | sort)
  [ "$_antes" = "$_depois" ] || { _fail "anti-mirror" "conteudo do state-dir mudou: antes[$_antes] depois[$_depois]"; return 1; }
  [ ! -f "$_sd/state.json" ] || { _fail "anti-mirror" "state.json espelho criado no state-dir"; return 1; }
}

scenario_help_exit_zero() {
  capture "$SCRIPT" --help
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "help exit" "$_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "state-lock.sh" || return 1
}

scenario_subcomando_invalido_exit_2() {
  capture "$SCRIPT" frobnicate --state-dir "$TMPDIR_TEST/x"
  if [ "$_CAPTURED_EXIT" != 2 ]; then
    _fail "subcmd invalido" "esperado 2, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

run_all_scenarios
