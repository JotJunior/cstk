#!/bin/sh
# test_mcp-launch.sh — cobre plugins/cstk/skills/agente-00c-runtime/scripts/mcp-launch.sh.
#
# Ref: docs/specs/state-mcp-server/contracts/mcp-session-lifecycle.md
#        §CLI: `cstk mcp` / §`cstk mcp install` / §Resolucao da execucao
#        ativa (SEC-H3)
#      docs/specs/state-mcp-server/tasks.md FASE 6 task 6.1.3
#
# ESCOPO: entrypoint stdio do .mcp.json. Nao ha Docker real aqui — um
# stub `docker` no PATH prova que o script chega (ou nao) ate o
# `exec docker attach`, mesma filosofia hermetica de test_mcp-docker.sh/
# test_mcp.sh (stub completo substitui o daemon real).

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts/mcp-launch.sh"

if ! command -v jq >/dev/null 2>&1; then
  printf '# test_mcp-launch.sh: jq ausente — pulando suite\n'
  exit 0
fi

# _write_descriptor STATE_DIR SESSION_ID CONTAINER MODE -> grava
# mcp-server.json minimo (mesma forma dos demais testes de mcp-session).
#
# Grava tambem um `state.json` IRMAO com `.execution.status: em_andamento`
# (dec-060/dec-061, mcp-direct-transport FASE 8): `mcp-session.sh` agora
# consulta o status REAL da execucao (nao so o proxy `.stopped_at` do
# proprio descritor) — sem esse arquivo, `state-rw.sh get` falha e o
# fail-closed recusaria toda chamada, mesmo com `stopped_at: null`.
_write_descriptor() {
  _wd_dir=$1; _wd_sid=$2; _wd_container=$3; _wd_mode=$4
  mkdir -p "$_wd_dir"
  jq -n --arg sid "$_wd_sid" --arg container "$_wd_container" --arg mode "$_wd_mode" \
    '{session_id:$sid, execution_kind:"agente-00c", short_name:null,
      state_dir:"-", target_project_path:"/tmp/p",
      container_name:$container, mode:$mode,
      started_at:"2026-08-01T00:00:00Z", stopped_at:null}' \
    > "$_wd_dir/mcp-server.json"
  jq -n '{execution:{status:"em_andamento"}}' > "$_wd_dir/state.json"
}

# _stub_docker BIN_DIR -> stub minimo que so loga a invocacao (o
# scenario de sucesso so precisa provar QUE `attach <container>` foi
# chamado, nao simular o handshake MCP real).
_stub_docker() {
  _sd_bin="$1"
  cat >"$_sd_bin/docker" <<'STUB'
#!/bin/sh
printf 'docker %s\n' "$*" >>"$TMPDIR_TEST/docker-launch-calls.log"
exit 0
STUB
  chmod +x "$_sd_bin/docker"
}

_docker_launch_calls() {
  cat "$TMPDIR_TEST/docker-launch-calls.log" 2>/dev/null
}

# _run_launch PROJECT_PATH [TOKEN] -> roda mcp-launch.sh com PATH restrito
# (stub docker prepended) e captura exit/stdout/stderr via harness.sh.
_run_launch() {
  _rl_project=$1
  _rl_token=${2:-}
  _rl_bin="$TMPDIR_TEST/stubs"
  mkdir -p "$_rl_bin"
  _stub_docker "$_rl_bin"
  if [ -n "$_rl_token" ]; then
    capture env PATH="$_rl_bin:$PATH" CSTK_MCP_PROJECT_PATH="$_rl_project" \
      MCP_SESSION_TOKEN="$_rl_token" "$SCRIPT"
  else
    capture env PATH="$_rl_bin:$PATH" CSTK_MCP_PROJECT_PATH="$_rl_project" "$SCRIPT"
  fi
}

# Fix "-32000 no boot": sem token (boot normal do harness, nenhuma
# execucao 00c ativa) o launcher NAO pode morrer — serve o stub MCP idle
# e encerra 0 no EOF do stdin.
scenario_sem_token_serve_idle_exit_0() {
  _proj="$TMPDIR_TEST/proj1"
  mkdir -p "$_proj"
  _run_launch "$_proj"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "sem token exit" "esperado 0 (idle), obtido $_CAPTURED_EXIT: $_CAPTURED_STDERR"; return 1; }
  assert_stderr_contains "modo IDLE" || return 1
  case "$(_docker_launch_calls)" in
    *attach*) _fail "docker attach nao deveria ter sido chamado" "$(_docker_launch_calls)"; return 1 ;;
  esac
}

# Handshake do stub idle: initialize ecoa o protocolVersion do cliente,
# tools/list responde lista VAZIA (zero mutacao possivel — SEC-H3),
# metodo desconhecido com id recebe -32601.
scenario_idle_handshake_initialize_e_tools_vazio() {
  _proj="$TMPDIR_TEST/proj1b"
  mkdir -p "$_proj"
  _hs_in="$TMPDIR_TEST/idle-handshake-in"
  printf '%s\n%s\n%s\n%s\n' \
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}' \
    '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
    '{"jsonrpc":"2.0","id":3,"method":"prompts/list"}' > "$_hs_in"
  capture sh -c 'env CSTK_MCP_PROJECT_PATH="$1" "$2" < "$3"' _ "$_proj" "$SCRIPT" "$_hs_in"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "idle handshake exit" "esperado 0, obtido $_CAPTURED_EXIT: $_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains '"protocolVersion":"2025-06-18"' || return 1
  assert_stdout_contains '"tools":[]' || return 1
  assert_stdout_contains '"code":-32601' || return 1
  # Notificacao nao gera resposta: nenhuma linha com id nulo/ausente.
  case "$_CAPTURED_STDOUT" in
    *'"id":null'*) _fail "notificacao nao deveria receber resposta" "$_CAPTURED_STDOUT"; return 1 ;;
  esac
}

scenario_token_desconhecido_exit_3_sem_chamar_docker() {
  _proj="$TMPDIR_TEST/proj2"
  _sd="$_proj/.claude/agente-00c-state"
  _write_descriptor "$_sd" "tok-real" "cstk-mcp-state-x" "docker"
  _run_launch "$_proj" "tok-errado"
  [ "$_CAPTURED_EXIT" = 3 ] || { _fail "token errado exit" "esperado 3, obtido $_CAPTURED_EXIT"; return 1; }
  case "$(_docker_launch_calls)" in
    *attach*) _fail "docker attach nao deveria ter sido chamado" "$(_docker_launch_calls)"; return 1 ;;
  esac
}

# Execucao ativa mas SEM container (bash-fallback): benigno — a onda roda
# pelo caminho Bash e o launcher serve idle em vez de morrer.
scenario_sessao_bash_fallback_serve_idle_exit_0() {
  _proj="$TMPDIR_TEST/proj3"
  _sd="$_proj/.claude/agente-00c-state"
  _write_descriptor "$_sd" "tok-bf" "-" "bash-fallback"
  _run_launch "$_proj" "tok-bf"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "bash-fallback exit" "esperado 0 (idle), obtido $_CAPTURED_EXIT: $_CAPTURED_STDERR"; return 1; }
  assert_stderr_contains "mode=bash-fallback" || return 1
  assert_stderr_contains "modo IDLE" || return 1
  case "$(_docker_launch_calls)" in
    *attach*) _fail "docker attach nao deveria ter sido chamado (mode=bash-fallback)" "$(_docker_launch_calls)"; return 1 ;;
  esac
}

scenario_sessao_docker_ativa_faz_exec_docker_attach() {
  _proj="$TMPDIR_TEST/proj4"
  _sd="$_proj/.claude/agente-00c-state"
  _write_descriptor "$_sd" "tok-ok" "cstk-mcp-state-ok" "docker"
  _run_launch "$_proj" "tok-ok"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "docker ativo exit" "esperado 0, obtido $_CAPTURED_EXIT: $_CAPTURED_STDERR"; return 1; }
  case "$(_docker_launch_calls)" in
    *"attach cstk-mcp-state-ok"*) : ;;
    *) _fail "docker attach cstk-mcp-state-ok esperado" "$(_docker_launch_calls)"; return 1 ;;
  esac
}

scenario_docker_ausente_no_path_exit_1() {
  _proj="$TMPDIR_TEST/proj5"
  _sd="$_proj/.claude/agente-00c-state"
  _write_descriptor "$_sd" "tok-nodock" "cstk-mcp-state-y" "docker"
  # PATH restrito a um dir sem docker nem stub — so os utilitarios minimos
  # que o proprio harness/script precisam (sh via caminho absoluto do
  # SCRIPT nao passa por PATH, mas comandos internos como jq/cd/pwd sim).
  _bare_bin="$TMPDIR_TEST/bare-bin"
  mkdir -p "$_bare_bin"
  for _u in sh cd pwd dirname sed jq printf cat; do
    _p=$(command -v "$_u" 2>/dev/null) || continue
    ln -sf "$_p" "$_bare_bin/$_u" 2>/dev/null || :
  done
  capture env PATH="$_bare_bin" CSTK_MCP_PROJECT_PATH="$_proj" MCP_SESSION_TOKEN="tok-nodock" "$SCRIPT"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "docker ausente exit" "esperado 1, obtido $_CAPTURED_EXIT: $_CAPTURED_STDERR"; return 1; }
  assert_stderr_contains "docker nao encontrado" || return 1
}

run_all_scenarios
