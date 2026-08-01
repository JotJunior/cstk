#!/bin/sh
# test_mcp.sh — cobre cli/lib/mcp.sh (subcomando `cstk mcp`).
#
# Ref: docs/specs/state-mcp-server/contracts/mcp-session-lifecycle.md
#        §CLI: `cstk mcp` / §`cstk mcp status`
#      docs/specs/state-mcp-server/tasks.md FASE 1 task 1.4.3
#
# ESCOPO: fundacao FASE 1 — apenas `status`, sem Docker. Cobre os 3 estados
# (active/stopped/unavailable) via --state-dir e via --project-path (que
# reusa a precedencia de deteccao do hook PreToolUse, read-only).

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

CSTK_BIN="$REPO_ROOT/cli/cstk"
CSTK_LIB_DIR="$REPO_ROOT/cli/lib"
STATE_RW="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/state-rw.sh"

if ! command -v jq >/dev/null 2>&1; then
  printf '# test_mcp.sh: jq ausente — pulando suite\n'
  exit 0
fi

# _cstk_mcp ARGS... -> roda `cstk mcp ARGS` com o layout de repo.
_cstk_mcp() {
  CSTK_LIB="$CSTK_LIB_DIR" sh "$CSTK_BIN" mcp "$@"
}

# _init_active_exec DIR -> inicializa uma execucao 00c (status em_andamento
# por padrao do state-rw.sh init) em DIR.
_init_active_exec() {
  capture "$STATE_RW" init --state-dir "$1" \
    --execucao-id "exec-mcp-test" --projeto-alvo-path "/tmp/p" --descricao "POC mcp status"
}

# _write_descriptor STATE_DIR SESSION_ID MODE STOPPED_AT
_write_descriptor() {
  _wd_dir=$1; _wd_sid=$2; _wd_mode=$3; _wd_stopped=$4
  mkdir -p "$_wd_dir"
  if [ -n "$_wd_stopped" ]; then
    jq -n --arg sid "$_wd_sid" --arg mode "$_wd_mode" --arg stopped "$_wd_stopped" \
      '{session_id:$sid, execution_kind:"agente-00c", short_name:null,
        state_dir:"-", target_project_path:"/tmp/p",
        container_name:"cstk-mcp-state-x", mode:$mode,
        started_at:"2026-08-01T00:00:00Z", stopped_at:$stopped}' \
      > "$_wd_dir/mcp-server.json"
  else
    jq -n --arg sid "$_wd_sid" --arg mode "$_wd_mode" \
      '{session_id:$sid, execution_kind:"agente-00c", short_name:null,
        state_dir:"-", target_project_path:"/tmp/p",
        container_name:"cstk-mcp-state-x", mode:$mode,
        started_at:"2026-08-01T00:00:00Z", stopped_at:null}' \
      > "$_wd_dir/mcp-server.json"
  fi
}

# ---------- status via --state-dir ----------

scenario_status_state_dir_sem_descritor_unavailable() {
  _sd="$TMPDIR_TEST/sd1"
  mkdir -p "$_sd"
  capture _cstk_mcp status --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "unavailable exit" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "status=unavailable" || return 1
  assert_stdout_contains "reason=no-active-execution" || return 1
  assert_stdout_contains "session_id=-" || return 1
}

scenario_status_state_dir_descritor_ativo() {
  _sd="$TMPDIR_TEST/sd2"
  _write_descriptor "$_sd" "tok-active-1" "docker" ""
  capture _cstk_mcp status --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "active exit" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "status=active" || return 1
  assert_stdout_contains "session_id=tok-active-1" || return 1
  assert_stdout_contains "mode=docker" || return 1
  assert_stdout_contains "container=cstk-mcp-state-x" || return 1
}

scenario_status_state_dir_descritor_parado() {
  _sd="$TMPDIR_TEST/sd3"
  _write_descriptor "$_sd" "tok-stopped-1" "bash-fallback" "2026-08-01T02:00:00Z"
  capture _cstk_mcp status --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "stopped exit" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "status=stopped" || return 1
  assert_stdout_contains "session_id=tok-stopped-1" || return 1
}

scenario_status_state_dir_inexistente_exit_1() {
  capture _cstk_mcp status --state-dir "$TMPDIR_TEST/nao-existe"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "state-dir inexistente exit" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
}

# ---------- status via --project-path (precedencia) ----------

scenario_status_project_path_sem_execucao_ativa_unavailable() {
  _proj="$TMPDIR_TEST/proj-none"
  mkdir -p "$_proj/.claude"
  capture _cstk_mcp status --project-path "$_proj"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "project-path sem exec exit" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "status=unavailable" || return 1
  assert_stdout_contains "reason=no-active-execution" || return 1
}

scenario_status_project_path_agente00c_ativo_sem_descritor() {
  _proj="$TMPDIR_TEST/proj-agente"
  _sd="$_proj/.claude/agente-00c-state"
  mkdir -p "$_sd"
  _init_active_exec "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "init agente-00c" "$_CAPTURED_STDERR"; return 1; }

  capture _cstk_mcp status --project-path "$_proj"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "project-path agente exit" "$_CAPTURED_STDERR"; return 1; }
  # execucao ativa detectada mas sem servidor MCP iniciado ainda => unavailable
  assert_stdout_contains "status=unavailable" || return 1
  assert_stdout_contains "reason=no-active-execution" || return 1
}

scenario_status_project_path_agente00c_ativo_com_descritor() {
  _proj="$TMPDIR_TEST/proj-agente-desc"
  _sd="$_proj/.claude/agente-00c-state"
  mkdir -p "$_sd"
  _init_active_exec "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "init agente-00c" "$_CAPTURED_STDERR"; return 1; }
  _write_descriptor "$_sd" "tok-agente-1" "docker" ""

  capture _cstk_mcp status --project-path "$_proj"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "project-path agente+desc exit" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "status=active" || return 1
  assert_stdout_contains "session_id=tok-agente-1" || return 1
}

# agente-00c vence sobre feature-00c mesmo com ambos ativos.
scenario_status_project_path_precedencia_agente_vence() {
  _proj="$TMPDIR_TEST/proj-prec-a"
  _sd_a="$_proj/.claude/agente-00c-state"
  _sd_f="$_proj/.claude/feature-00c-state/zzz-feature"
  mkdir -p "$_sd_a" "$_sd_f"
  _init_active_exec "$_sd_a"
  _init_active_exec "$_sd_f"
  _write_descriptor "$_sd_a" "tok-A" "docker" ""
  _write_descriptor "$_sd_f" "tok-F" "docker" ""

  capture _cstk_mcp status --project-path "$_proj"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "precedencia agente exit" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "session_id=tok-A" || return 1
  assert_stdout_not_contains "session_id=tok-F" || return 1
}

# Entre feature-00c concorrentes, menor short-name lexicografico vence.
scenario_status_project_path_precedencia_menor_short_name() {
  _proj="$TMPDIR_TEST/proj-prec-f"
  _sd_b="$_proj/.claude/feature-00c-state/bbb-feature"
  _sd_a="$_proj/.claude/feature-00c-state/aaa-feature"
  mkdir -p "$_sd_b" "$_sd_a"
  _init_active_exec "$_sd_b"
  _init_active_exec "$_sd_a"
  _write_descriptor "$_sd_b" "tok-B" "docker" ""
  _write_descriptor "$_sd_a" "tok-AAA" "docker" ""

  capture _cstk_mcp status --project-path "$_proj"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "precedencia menor short-name exit" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "session_id=tok-AAA" || return 1
  assert_stdout_not_contains "session_id=tok-B" || return 1
}

scenario_status_project_path_inexistente_exit_1() {
  capture _cstk_mcp status --project-path "$TMPDIR_TEST/nao-existe"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "project-path inexistente exit" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
}

scenario_status_sem_flags_exit_2() {
  capture _cstk_mcp status
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "sem flags exit" "esperado 2, obtido $_CAPTURED_EXIT"; return 1; }
}

# ---------- uso geral do subcomando ----------

scenario_mcp_sem_subcomando_mostra_uso() {
  capture _cstk_mcp
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "uso deveria sair 0" "exit=$_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "status" || return 1
}

scenario_mcp_subcomando_desconhecido_exit_2() {
  capture _cstk_mcp naoexiste
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "subcomando invalido deveria ser exit 2" "exit=$_CAPTURED_EXIT"; return 1; }
}

scenario_cstk_help_mcp() {
  capture env CSTK_LIB="$CSTK_LIB_DIR" sh "$CSTK_BIN" help mcp
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "help mcp exit" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "mcp-session-lifecycle" || return 1
}

run_all_scenarios
