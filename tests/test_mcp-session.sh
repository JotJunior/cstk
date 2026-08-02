#!/bin/sh
# test_mcp-session.sh — cobre global/skills/agente-00c-runtime/scripts/mcp-session.sh.
#
# Ref: docs/specs/state-mcp-server/tasks.md FASE 1 task 1.3.4
#      docs/specs/state-mcp-server/contracts/mcp-session-lifecycle.md
#        §Resolucao da execucao ativa (SEC-H3)

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/mcp-session.sh"

if ! command -v jq >/dev/null 2>&1; then
  printf '# test_mcp-session.sh: jq ausente — pulando suite\n'
  exit 0
fi

# _write_descriptor PATH SESSION_ID EXEC_KIND SHORT_NAME STATE_DIR MODE STOPPED_AT
_write_descriptor() {
  _p=$1; _sid=$2; _kind=$3; _short=$4; _sdir=$5; _mode=$6; _stopped=$7
  mkdir -p "$(dirname "$_p")"
  if [ -n "$_stopped" ]; then
    jq -n --arg sid "$_sid" --arg kind "$_kind" --arg short "$_short" \
      --arg sdir "$_sdir" --arg mode "$_mode" --arg stopped "$_stopped" \
      '{session_id:$sid, execution_kind:$kind, short_name:$short,
        state_dir:$sdir, target_project_path:"/tmp/proj",
        container_name:"cstk-mcp-state-x", mode:$mode,
        started_at:"2026-08-01T00:00:00Z", stopped_at:$stopped}' > "$_p"
  else
    jq -n --arg sid "$_sid" --arg kind "$_kind" --arg short "$_short" \
      --arg sdir "$_sdir" --arg mode "$_mode" \
      '{session_id:$sid, execution_kind:$kind, short_name:$short,
        state_dir:$sdir, target_project_path:"/tmp/proj",
        container_name:"cstk-mcp-state-x", mode:$mode,
        started_at:"2026-08-01T00:00:00Z", stopped_at:null}' > "$_p"
  fi
  chmod 600 "$_p"
}

scenario_token_valido_resolve_agente00c() {
  _proj="$TMPDIR_TEST/proj1"
  _sd="$_proj/.claude/agente-00c-state"
  mkdir -p "$_sd"
  _write_descriptor "$_sd/mcp-server.json" "tok-abc123" "agente-00c" "" "$_sd" "docker" ""

  capture "$SCRIPT" resolve --project-path "$_proj" --token "tok-abc123"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "token valido exit" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "state_dir=$_sd" || return 1
  assert_stdout_contains "execution_kind=agente-00c" || return 1
  assert_stdout_contains "mode=docker" || return 1
}

scenario_token_valido_resolve_feature00c() {
  _proj="$TMPDIR_TEST/proj2"
  _sd="$_proj/.claude/feature-00c-state/minha-feature"
  mkdir -p "$_sd"
  _write_descriptor "$_sd/mcp-server.json" "tok-feat-1" "feature-00c" "minha-feature" "$_sd" "docker" ""

  capture "$SCRIPT" resolve --project-path "$_proj" --token "tok-feat-1"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "token feature valido exit" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "state_dir=$_sd" || return 1
  assert_stdout_contains "short_name=minha-feature" || return 1
}

scenario_token_ausente_exit_3() {
  _proj="$TMPDIR_TEST/proj3"
  mkdir -p "$_proj/.claude"
  capture "$SCRIPT" resolve --project-path "$_proj"
  [ "$_CAPTURED_EXIT" = 3 ] || { _fail "token ausente exit" "esperado 3, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "SESSION_MISMATCH" || return 1
}

scenario_token_invalido_exit_3_sem_fallback() {
  _proj="$TMPDIR_TEST/proj4"
  _sd="$_proj/.claude/agente-00c-state"
  mkdir -p "$_sd"
  _write_descriptor "$_sd/mcp-server.json" "tok-real" "agente-00c" "" "$_sd" "docker" ""

  capture "$SCRIPT" resolve --project-path "$_proj" --token "tok-adivinhado"
  [ "$_CAPTURED_EXIT" = 3 ] || { _fail "token invalido exit" "esperado 3, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "SESSION_MISMATCH" || return 1
  assert_stdout_not_contains "state_dir=" || return 1
}

scenario_token_de_execucao_terminal_exit_3() {
  _proj="$TMPDIR_TEST/proj5"
  _sd="$_proj/.claude/agente-00c-state"
  mkdir -p "$_sd"
  _write_descriptor "$_sd/mcp-server.json" "tok-terminal" "agente-00c" "" "$_sd" "docker" "2026-08-01T01:00:00Z"

  capture "$SCRIPT" resolve --project-path "$_proj" --token "tok-terminal"
  [ "$_CAPTURED_EXIT" = 3 ] || { _fail "token terminal exit" "esperado 3, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "SESSION_MISMATCH" || return 1
}

# Dois state-dirs concorrentes: cada token so pode resolver o SEU proprio
# descritor — nunca vazar para o outro (SEC-H3, contract §Roteamento).
scenario_dois_state_dirs_concorrentes_sem_vazamento() {
  _proj="$TMPDIR_TEST/proj6"
  _sd_a="$_proj/.claude/agente-00c-state"
  _sd_b="$_proj/.claude/feature-00c-state/outra-feature"
  mkdir -p "$_sd_a" "$_sd_b"
  _write_descriptor "$_sd_a/mcp-server.json" "tok-A" "agente-00c" "" "$_sd_a" "docker" ""
  _write_descriptor "$_sd_b/mcp-server.json" "tok-B" "feature-00c" "outra-feature" "$_sd_b" "docker" ""

  capture "$SCRIPT" resolve --project-path "$_proj" --token "tok-A"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "tok-A exit" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "state_dir=$_sd_a" || return 1
  assert_stdout_not_contains "state_dir=$_sd_b" || return 1

  capture "$SCRIPT" resolve --project-path "$_proj" --token "tok-B"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "tok-B exit" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "state_dir=$_sd_b" || return 1
  assert_stdout_not_contains "state_dir=$_sd_a" || return 1
}

scenario_token_via_env_var() {
  _proj="$TMPDIR_TEST/proj7"
  _sd="$_proj/.claude/agente-00c-state"
  mkdir -p "$_sd"
  _write_descriptor "$_sd/mcp-server.json" "tok-env-1" "agente-00c" "" "$_sd" "bash-fallback" ""

  MCP_SESSION_TOKEN="tok-env-1" capture "$SCRIPT" resolve --project-path "$_proj"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "token via env exit" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "mode=bash-fallback" || return 1
}

scenario_token_via_arquivo() {
  _proj="$TMPDIR_TEST/proj8"
  _sd="$_proj/.claude/agente-00c-state"
  mkdir -p "$_sd"
  _write_descriptor "$_sd/mcp-server.json" "tok-file-1" "agente-00c" "" "$_sd" "docker" ""
  _tokfile="$TMPDIR_TEST/token.txt"
  printf 'tok-file-1\n' > "$_tokfile"

  capture "$SCRIPT" resolve --project-path "$_proj" --token-file "$_tokfile"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "token via arquivo exit" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "state_dir=$_sd" || return 1
}

scenario_project_path_ausente_exit_2() {
  capture "$SCRIPT" resolve --token "tok-x"
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "project-path ausente exit" "esperado 2, obtido $_CAPTURED_EXIT"; return 1; }
}

scenario_project_path_inexistente_exit_1() {
  capture "$SCRIPT" resolve --project-path "$TMPDIR_TEST/nao-existe" --token "tok-x"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "project-path inexistente exit" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
}

scenario_sem_subcomando_exit_2() {
  capture "$SCRIPT"
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "sem subcomando exit" "esperado 2, obtido $_CAPTURED_EXIT"; return 1; }
}

# ---------- modo direto --state-dir (dec-081, task 5.3) ----------

scenario_state_dir_direto_resolve_sem_tree_walk() {
  _sd="$TMPDIR_TEST/direct1/qualquer-nome"
  mkdir -p "$_sd"
  # Descritor grava .state_dir=/data/state (simula o valor REAL gravado por
  # cli/lib/mcp.sh — sempre o path ABSOLUTO DO HOST, nao "/data/state"; aqui
  # usamos "/data/state" so como um valor DIFERENTE do $_sd de resolucao,
  # para provar que o output reflete o --state-dir do CALLER, nao o campo
  # interno do JSON).
  _write_descriptor "$_sd/mcp-server.json" "tok-direct-1" "feature-00c" "state-mcp-server" "/data/state" "docker" ""

  capture "$SCRIPT" resolve --state-dir "$_sd" --token "tok-direct-1"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "state-dir direto exit" "$_CAPTURED_STDERR"; return 1; }
  # achado empirico (task 5.3, validacao com Docker real): o modo direto
  # DEVE ecoar o --state-dir usado para localizar o descritor (valido
  # DENTRO do container), nunca o campo .state_dir do proprio JSON (que e
  # sempre o path do HOST — inutilizavel de dentro do container).
  assert_stdout_contains "state_dir=$_sd" || return 1
  assert_stdout_not_contains "state_dir=/data/state" || return 1
  assert_stdout_contains "execution_kind=feature-00c" || return 1
}

scenario_state_dir_direto_token_invalido_exit_3() {
  _sd="$TMPDIR_TEST/direct2"
  mkdir -p "$_sd"
  _write_descriptor "$_sd/mcp-server.json" "tok-real-2" "agente-00c" "" "/data/state" "docker" ""

  capture "$SCRIPT" resolve --state-dir "$_sd" --token "tok-adivinhado"
  [ "$_CAPTURED_EXIT" = 3 ] || { _fail "state-dir token invalido exit" "esperado 3, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "SESSION_MISMATCH" || return 1
}

scenario_state_dir_direto_execucao_terminal_exit_3() {
  _sd="$TMPDIR_TEST/direct3"
  mkdir -p "$_sd"
  _write_descriptor "$_sd/mcp-server.json" "tok-term-2" "agente-00c" "" "/data/state" "docker" "2026-08-01T01:00:00Z"

  capture "$SCRIPT" resolve --state-dir "$_sd" --token "tok-term-2"
  [ "$_CAPTURED_EXIT" = 3 ] || { _fail "state-dir terminal exit" "esperado 3, obtido $_CAPTURED_EXIT"; return 1; }
}

scenario_state_dir_direto_sem_descritor_exit_3() {
  _sd="$TMPDIR_TEST/direct4"
  mkdir -p "$_sd"

  capture "$SCRIPT" resolve --state-dir "$_sd" --token "tok-qualquer"
  [ "$_CAPTURED_EXIT" = 3 ] || { _fail "state-dir sem descritor exit" "esperado 3, obtido $_CAPTURED_EXIT"; return 1; }
}

scenario_state_dir_inexistente_exit_1() {
  capture "$SCRIPT" resolve --state-dir "$TMPDIR_TEST/nao-existe-direct" --token "tok-x"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "state-dir inexistente exit" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
}

scenario_state_dir_e_project_path_juntos_exit_2() {
  _sd="$TMPDIR_TEST/direct5"
  mkdir -p "$_sd"
  capture "$SCRIPT" resolve --state-dir "$_sd" --project-path "$TMPDIR_TEST" --token "tok-x"
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "state-dir+project-path exit" "esperado 2, obtido $_CAPTURED_EXIT"; return 1; }
}

scenario_nenhum_locator_exit_2() {
  capture "$SCRIPT" resolve --token "tok-x"
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "nenhum locator exit" "esperado 2, obtido $_CAPTURED_EXIT"; return 1; }
}

run_all_scenarios
