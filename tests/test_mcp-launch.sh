#!/bin/sh
# test_mcp-launch.sh — cobre plugins/cstk/skills/agente-00c-runtime/scripts/mcp-launch.sh.
#
# Ref: docs/specs/mcp-direct-transport/contracts/server-session-resolution.md
#        §4 (Launcher) — L-1..L-7
#      docs/specs/mcp-direct-transport/quickstart.md Cenarios 1, 9, 10
#      docs/specs/mcp-direct-transport/tasks.md FASE 5 task 5.1.4
#
# REESCRITA COMPLETA (mcp-direct-transport FASE 5, cutover): a suite
# anterior cobria o comportamento PRE-cutover (stub idle sem token,
# `exec docker attach`). Esse comportamento foi REMOVIDO do script — o
# launcher agora faz `exec node <entrypoint>` direto, sem exigir token
# algum (L-1), sem motor de containers em nenhum ponto (L-2). ESCOPO
# desta suite: preflight de Node (L-6), build lazy (L-4), degradacao
# graciosa para idle quando o processo node real nao pode subir (L-5),
# e a garantia central de `exec` sem fork (L-7, FR-012) — validada
# empiricamente comparando o PID do processo `node` real com o PID do
# processo que rodou o launcher.
#
# Filosofia hermetica: `node` e substituido por um STUB no PATH que loga
# a invocacao/env e sai imediatamente — nunca sobe o servidor MCP de
# verdade aqui (evitaria bloquear a suite lendo stdio). Mesmo espirito
# de tests/test_mcp-build-lazy.sh (stub de `npm`) e do antigo stub de
# `docker` desta mesma suite.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts/mcp-launch.sh"

if ! command -v jq >/dev/null 2>&1; then
  printf '# test_mcp-launch.sh: jq ausente — pulando suite\n'
  exit 0
fi

# _make_state_server_dir DIR -> cria o esqueleto minimo de
# ~/.claude/mcp/state-server (package.json presente).
_make_state_server_dir() {
  _mssd_dir="$1"
  mkdir -p "$_mssd_dir"
  printf '{"name":"@cstk/state-mcp-server","version":"0.0.0"}\n' > "$_mssd_dir/package.json"
}

# _make_state_server_dir_with_dist DIR -> idem + dist/src/index.js ja
# presente (fast path idempotente do mcp-build-lazy.sh: nem npm ci, nem
# npm run build sao invocados).
_make_state_server_dir_with_dist() {
  _mssdwd_dir="$1"
  _make_state_server_dir "$_mssdwd_dir"
  mkdir -p "$_mssdwd_dir/dist/src"
  printf 'module.exports = {};\n' > "$_mssdwd_dir/dist/src/index.js"
}

# _stub_node BIN_DIR [MAJOR] -> stub `node` que responde `-v` com o major
# informado (default 24, sempre >= _ML_MIN_NODE_MAJOR) e, para qualquer
# outra invocacao, loga argv + as env vars relevantes num arquivo e sai 0
# imediatamente (nunca le stdin — evita bloquear a suite).
_stub_node() {
  _sn_bin="$1"
  _sn_major="${2:-24}"
  cat > "$_sn_bin/node" <<STUB
#!/bin/sh
if [ "\$1" = "-v" ]; then
  echo "v${_sn_major}.0.0"
  exit 0
fi
{
  printf 'argv=%s\n' "\$*"
  printf 'CSTK_MCP_PROJECT_PATH=%s\n' "\${CSTK_MCP_PROJECT_PATH:-}"
  printf 'CSTK_MCP_SCRIPTS_DIR=%s\n' "\${CSTK_MCP_SCRIPTS_DIR:-}"
  printf 'pid=%s\n' "\$\$"
} >> "\$TMPDIR_TEST/node-calls.log"
exit 0
STUB
  chmod +x "$_sn_bin/node"
}

_node_calls() {
  cat "$TMPDIR_TEST/node-calls.log" 2>/dev/null
}

# _run_launch STATE_SERVER_DIR PROJECT_PATH [NODE_MAJOR] -> roda
# mcp-launch.sh com PATH restrito (stub node prepended) e captura
# exit/stdout/stderr via harness.sh. Sem stdin (</dev/null): o stub
# nunca le, entao nao ha risco de bloqueio; os cenarios de idle
# consomem stdin proprio quando precisam do handshake.
_run_launch() {
  _rl_ssd="$1"
  _rl_proj="$2"
  _rl_major="${3:-24}"
  _rl_bin="$TMPDIR_TEST/stubs"
  mkdir -p "$_rl_bin"
  _stub_node "$_rl_bin" "$_rl_major"
  capture env PATH="$_rl_bin:$PATH" CSTK_MCP_STATE_SERVER_DIR="$_rl_ssd" \
    CSTK_MCP_PROJECT_PATH="$_rl_proj" "$SCRIPT" < /dev/null
}

# ---------- L-2: nenhuma invocacao de docker no caminho novo (5.1.2) ----------

scenario_launcher_nunca_invoca_docker() {
  case "$(grep -Ec 'docker (attach|run|ps|inspect)|command -v docker' "$SCRIPT" 2>/dev/null)" in
    0) : ;;
    *) _fail "sem-docker" "mcp-launch.sh nao deve invocar docker em ponto algum (L-2)"; return 1 ;;
  esac
}

# ---------- L-3/L-5: state-server nao instalado -> idle, nunca falha ----------

scenario_state_server_ausente_serve_idle_exit_0() {
  _proj="$TMPDIR_TEST/proj1"
  mkdir -p "$_proj"
  _run_launch "$TMPDIR_TEST/nao-existe-xyz" "$_proj"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "state-server ausente exit" "esperado 0 (idle), obtido $_CAPTURED_EXIT: $_CAPTURED_STDERR"; return 1; }
  assert_stderr_contains "nao instalado" || return 1
  assert_stderr_contains "modo IDLE" || return 1
  [ -z "$(_node_calls)" ] || { _fail "node nao deveria ter sido invocado" "$(_node_calls)"; return 1; }
}

scenario_state_server_sem_package_json_serve_idle_exit_0() {
  _proj="$TMPDIR_TEST/proj1b"
  mkdir -p "$_proj"
  _ssd="$TMPDIR_TEST/ssd-sem-pkg"
  mkdir -p "$_ssd"
  _run_launch "$_ssd" "$_proj"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "sem package.json exit" "esperado 0 (idle), obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "nao instalado" || return 1
}

# ---------- L-6: preflight de Node ----------

scenario_node_ausente_no_path_serve_idle_exit_0() {
  _proj="$TMPDIR_TEST/proj2"
  mkdir -p "$_proj"
  _ssd="$TMPDIR_TEST/ssd-ok"
  _make_state_server_dir_with_dist "$_ssd"
  _bare_bin="$TMPDIR_TEST/bare-bin"
  mkdir -p "$_bare_bin"
  for _u in sh cd pwd dirname jq printf cat; do
    _p=$(command -v "$_u" 2>/dev/null) || continue
    ln -sf "$_p" "$_bare_bin/$_u" 2>/dev/null || :
  done
  capture env PATH="$_bare_bin" CSTK_MCP_STATE_SERVER_DIR="$_ssd" \
    CSTK_MCP_PROJECT_PATH="$_proj" "$SCRIPT" < /dev/null
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "node ausente exit" "esperado 0 (idle), obtido $_CAPTURED_EXIT: $_CAPTURED_STDERR"; return 1; }
  assert_stderr_contains "node nao encontrado" || return 1
  assert_stderr_contains "modo IDLE" || return 1
}

scenario_node_major_insuficiente_serve_idle_exit_0() {
  _proj="$TMPDIR_TEST/proj3"
  mkdir -p "$_proj"
  _ssd="$TMPDIR_TEST/ssd-ok2"
  _make_state_server_dir_with_dist "$_ssd"
  _run_launch "$_ssd" "$_proj" 18
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "node major insuficiente exit" "esperado 0 (idle), obtido $_CAPTURED_EXIT: $_CAPTURED_STDERR"; return 1; }
  assert_stderr_contains "Node 18 detectado" || return 1
  assert_stderr_contains "modo IDLE" || return 1
  case "$(_node_calls)" in
    *pid=*) _fail "node nao deveria ter sido exec'ado (major insuficiente)" "$(_node_calls)"; return 1 ;;
  esac
}

# ---------- L-4/L-5: build lazy ----------

scenario_build_lazy_sem_lockfile_serve_idle_exit_0() {
  _proj="$TMPDIR_TEST/proj4"
  mkdir -p "$_proj"
  _ssd="$TMPDIR_TEST/ssd-sem-lock"
  _make_state_server_dir "$_ssd"
  # sem dist/, sem package-lock.json -> mcp-build-lazy.sh MUST falhar
  # (CHK015, fail-closed) -> launcher degrada para idle, nunca propaga erro.
  _run_launch "$_ssd" "$_proj"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "build lazy sem lockfile exit" "esperado 0 (idle), obtido $_CAPTURED_EXIT: $_CAPTURED_STDERR"; return 1; }
  assert_stderr_contains "build lazy do servidor MCP falhou" || return 1
  assert_stderr_contains "modo IDLE" || return 1
}

# ---------- L-1/L-4: dist ja presente (fast path) -> exec node real ----------

scenario_dist_existente_exec_node_com_entrypoint_correto() {
  _proj="$TMPDIR_TEST/proj5"
  mkdir -p "$_proj"
  _ssd="$TMPDIR_TEST/ssd-dist-pronto"
  _make_state_server_dir_with_dist "$_ssd"
  _run_launch "$_ssd" "$_proj"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exec node exit" "esperado 0, obtido $_CAPTURED_EXIT: $_CAPTURED_STDERR"; return 1; }
  case "$(_node_calls)" in
    *"argv=$_ssd/dist/src/index.js"*) : ;;
    *) _fail "node deveria ter sido exec'ado com o entrypoint" "$(_node_calls)"; return 1 ;;
  esac
  case "$_CAPTURED_STDERR" in
    *"modo IDLE"*) _fail "nao deveria degradar para idle (dist ja pronto)" "$_CAPTURED_STDERR"; return 1 ;;
  esac
}

scenario_env_repassado_ao_processo_node() {
  _proj="$TMPDIR_TEST/proj6/nested"
  mkdir -p "$_proj"
  _ssd="$TMPDIR_TEST/ssd-env"
  _make_state_server_dir_with_dist "$_ssd"
  _run_launch "$_ssd" "$_proj"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "env repassado exit" "esperado 0, obtido $_CAPTURED_EXIT: $_CAPTURED_STDERR"; return 1; }
  case "$(_node_calls)" in
    *"CSTK_MCP_PROJECT_PATH=$_proj"*) : ;;
    *) _fail "CSTK_MCP_PROJECT_PATH nao repassado corretamente" "$(_node_calls)"; return 1 ;;
  esac
  _script_dir="$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts"
  case "$(_node_calls)" in
    *"CSTK_MCP_SCRIPTS_DIR=$_script_dir"*) : ;;
    *) _fail "CSTK_MCP_SCRIPTS_DIR deveria apontar para o dir do proprio launcher" "$(_node_calls)"; return 1 ;;
  esac
}

# ---------- L-7/FR-012: exec sem fork — mesmo PID, morre com a sessao ----------
# Cenario 10 do quickstart (equivalente automatizado): se o launcher fizesse
# fork em vez de exec, o PID do processo `node` seria FILHO do PID que rodou
# o launcher (dois PIDs distintos, um orfao possivel se o pai morresse
# sozinho). `exec` substitui a imagem do processo: o PID que roda `node`
# deve ser LITERALMENTE o mesmo PID que rodou o script (FR-012 comprovado
# sem precisar matar sessao real do harness).
scenario_exec_sem_fork_mesmo_pid_do_launcher() {
  _proj="$TMPDIR_TEST/proj7"
  mkdir -p "$_proj"
  _ssd="$TMPDIR_TEST/ssd-pid"
  _make_state_server_dir_with_dist "$_ssd"
  _bin="$TMPDIR_TEST/stubs-pid"
  mkdir -p "$_bin"
  _stub_node "$_bin" 24
  env PATH="$_bin:$PATH" CSTK_MCP_STATE_SERVER_DIR="$_ssd" \
    CSTK_MCP_PROJECT_PATH="$_proj" "$SCRIPT" < /dev/null > /dev/null 2>"$TMPDIR_TEST/stderr-pid.log" &
  _launcher_pid=$!
  wait "$_launcher_pid" 2>/dev/null
  _node_pid=$(sed -n 's/^pid=//p' "$TMPDIR_TEST/node-calls.log" 2>/dev/null | tail -1)
  [ -n "$_node_pid" ] || { _fail "node nao rodou" "$(cat "$TMPDIR_TEST/stderr-pid.log" 2>/dev/null)"; return 1; }
  [ "$_node_pid" = "$_launcher_pid" ] || { _fail "exec-mesmo-pid" "esperado node PID == launcher PID ($_launcher_pid), obtido $_node_pid — indica fork em vez de exec (viola L-7/FR-012)"; return 1; }
}

run_all_scenarios
