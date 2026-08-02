#!/bin/sh
# test_mcp-docker.sh — cobre cli/lib/mcp-docker.sh (uso de Docker confinado
# do servidor MCP de estado).
#
# Ref: docs/specs/state-mcp-server/contracts/mcp-session-lifecycle.md
#        §Contrato do container / §Montagens (SEC-H2)
#      docs/specs/state-mcp-server/plan.md §Seguranca (SEC-H2, SEC-M4)
#      docs/specs/state-mcp-server/tasks.md FASE 5 task 5.2.5
#
# Mesma filosofia de tests/cstk/test_serve-docker.sh: um stub `docker`
# completo (info/build/rm/run/stop, logando cada invocacao) substitui o
# daemon real — FAST e HERMETICO, nunca rede ou runtime de container de
# verdade. As assercoes estaticas exigidas por 5.2.3 (nenhuma linha
# `docker run` monta `.claude` como diretorio, `$HOME`, `/`, ou
# `docker.sock`) sao verificadas sobre o LOG de invocacao real do stub —
# nao apenas grep no texto-fonte — porque a montagem e composta em
# runtime a partir de parametros.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

CSTK_LIB="$REPO_ROOT/cli/lib"
export CSTK_LIB

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# _run_mcp_docker_fn FUNC [ARGS...] — roda FUNC (definida em
# mcp-docker.sh) num subshell isolado, capturando stdout/stderr/exit.
# Mesmo padrao de test_serve-docker.sh::_run_serve_docker_fn. PATH
# interno controlado via _MD_INNER_PATH (default: PATH do harness).
_run_mcp_docker_fn() {
  capture env CSTK_LIB="$CSTK_LIB" HOME="$TMPDIR_TEST" \
    PATH="${_MD_INNER_PATH:-$PATH}" \
    sh -c '. "$CSTK_LIB/mcp-docker.sh" && "$@"' mcp_docker_test "$@"
}

# _isolated_sh_dir: identico a tests/cstk/test_serve-docker.sh (duplicado
# por design -- cada test_*.sh e autocontido). Dir com APENAS um symlink
# para o `sh` real, para compor um PATH interno minimo sem arrastar
# /usr/local/bin (onde `docker` de fato mora neste host — CLAUDE.md
# "PATH-stub nao esconde binario de /usr/bin" vale identicamente para
# /usr/local/bin/docker).
_isolated_sh_dir() {
  _ish_dir="$TMPDIR_TEST/shbin"
  if [ ! -e "$_ish_dir/sh" ]; then
    mkdir -p "$_ish_dir"
    _ish_sh=$(command -v sh)
    ln -sf "$_ish_sh" "$_ish_dir/sh"
  fi
  printf '%s' "$_ish_dir"
}

# _make_bin_dir — cria dir de stubs e o prepende ao PATH.
_make_bin_dir() {
  _STUB_BIN="$TMPDIR_TEST/stubs"
  mkdir -p "$_STUB_BIN"
  PATH="$_STUB_BIN:$PATH"
  export PATH
}

# _docker_calls_log — imprime o conteudo do log de invocacoes do stub.
_docker_calls_log() {
  cat "$TMPDIR_TEST/docker-calls.log" 2>/dev/null
}

# _docker_run_line — imprime a (unica) linha `run ...` logada pelo stub.
_docker_run_line() {
  grep '^run ' "$TMPDIR_TEST/docker-calls.log" 2>/dev/null
}

# _stub_docker BIN_DIR
# Stub `docker` cobrindo info/build/rm/run/stop. Loga CADA invocacao
# (argv completo, uma linha) em $TMPDIR_TEST/docker-calls.log.
#
# Marcadores em $TMPDIR_TEST/docker-stub/ (escrever ANTES de chamar a
# funcao sob teste):
#   docker-stub/daemon-down    presente => `docker info` falha
#   docker-stub/build-fails    presente => `docker build` falha
#   docker-stub/rm-fails       presente => `docker rm -f` falha (permissao
#                               negada, NUNCA "no such container")
#   docker-stub/rm-nothing     presente => `docker rm -f` reporta "No such
#                               container" (idempotente, nada a remover)
#   docker-stub/run-fails      presente => `docker run` falha
_stub_docker() {
  _sdck_bin="$1"
  cat >"$_sdck_bin/docker" <<'STUB'
#!/bin/sh
_stub_dir="$TMPDIR_TEST/docker-stub"
mkdir -p "$_stub_dir"
printf '%s\n' "$*" >>"$TMPDIR_TEST/docker-calls.log"

case "$1" in
  info)
    [ -f "$_stub_dir/daemon-down" ] && exit 1
    exit 0
    ;;
  build)
    if [ -f "$_stub_dir/build-fails" ]; then
      printf 'stub-docker: build simulado falhou\n' >&2
      exit 1
    fi
    exit 0
    ;;
  rm)
    if [ -f "$_stub_dir/rm-fails" ]; then
      printf 'Error: permission denied while trying to connect to the Docker daemon socket\n' >&2
      exit 1
    fi
    if [ -f "$_stub_dir/rm-nothing" ]; then
      printf 'Error: No such container: %s\n' "$3" >&2
      exit 1
    fi
    exit 0
    ;;
  run)
    if [ -f "$_stub_dir/run-fails" ]; then
      printf 'docker: Error response from daemon: stub run simulado falhou\n' >&2
      exit 1
    fi
    printf 'fakecontainerid0123456789abcdef\n'
    exit 0
    ;;
  stop)
    exit 0
    ;;
  *)
    printf 'stub-docker: subcomando inesperado: %s\n' "$*" >&2
    exit 1
    ;;
esac
STUB
  chmod +x "$_sdck_bin/docker"
}

# _setup_run_fixture -> prepara state-dir/scripts-dir/enforcement-log
# realistas (enforcement-log SOB .claude/, como na execucao real). Exporta
# _RF_STATE_DIR / _RF_SCRIPTS_DIR / _RF_LOG_PATH / _RF_PROJECT_PATH.
_setup_run_fixture() {
  _RF_STATE_DIR="$TMPDIR_TEST/exec/.claude/feature-00c-state/demo"
  _RF_SCRIPTS_DIR="$TMPDIR_TEST/catalog/skills/agente-00c-runtime/scripts"
  _RF_LOG_PATH="$TMPDIR_TEST/exec/.claude/enforcement-log.jsonl"
  _RF_PROJECT_PATH="$TMPDIR_TEST/exec"
  mkdir -p "$_RF_STATE_DIR" "$_RF_SCRIPTS_DIR"
}

# ---------------------------------------------------------------------------
# _mcp_docker_preflight
# ---------------------------------------------------------------------------

scenario_preflight_docker_ausente() {
  _MD_INNER_PATH=$(_isolated_sh_dir)
  _run_mcp_docker_fn _mcp_docker_preflight
  unset _MD_INNER_PATH
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "preflight_absent_exit" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "docker nao encontrado no PATH" || return 1
}

scenario_preflight_daemon_inacessivel() {
  _make_bin_dir
  _stub_docker "$_STUB_BIN"
  mkdir -p "$TMPDIR_TEST/docker-stub"
  : >"$TMPDIR_TEST/docker-stub/daemon-down"
  _run_mcp_docker_fn _mcp_docker_preflight
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "preflight_daemon_exit" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "daemon nao esta acessivel" || return 1
}

scenario_preflight_ok() {
  _make_bin_dir
  _stub_docker "$_STUB_BIN"
  _run_mcp_docker_fn _mcp_docker_preflight
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "preflight_ok_exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
}

# ---------------------------------------------------------------------------
# nomenclatura (image/container)
# ---------------------------------------------------------------------------

scenario_image_name() {
  _run_mcp_docker_fn _mcp_docker_image_name
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "image_name_exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "cstk-mcp-state" || return 1
}

scenario_image_tag() {
  _run_mcp_docker_fn _mcp_docker_image_tag "0.3.0"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "image_tag_exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "cstk-mcp-state:0.3.0" || return 1
}

scenario_container_name() {
  _run_mcp_docker_fn _mcp_docker_container_name "abc123"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "container_name_exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "cstk-mcp-state-abc123" || return 1
}

# ---------------------------------------------------------------------------
# _mcp_docker_write_dockerfile
# ---------------------------------------------------------------------------

scenario_write_dockerfile_conteudo() {
  _out="$TMPDIR_TEST/Dockerfile"
  _run_mcp_docker_fn _mcp_docker_write_dockerfile "$_out"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "write_dockerfile_exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  [ -f "$_out" ] || { _fail "write_dockerfile_file" "Dockerfile nao foi escrito"; return 1; }
  grep -q "FROM node:22-alpine@sha256:" "$_out" || { _fail "write_dockerfile_base" "base pinada por digest ausente"; return 1; }
  grep -q "npm ci --ignore-scripts" "$_out" || { _fail "write_dockerfile_npmci" "npm ci --ignore-scripts ausente"; return 1; }
  grep -q 'ENTRYPOINT \["node", "dist/src/index.js"\]' "$_out" || { _fail "write_dockerfile_entrypoint" "entrypoint stdio ausente"; return 1; }
  grep -q "apk add --no-cache jq" "$_out" || { _fail "write_dockerfile_jq" "instalacao de jq ausente"; return 1; }
  if grep -qE '^RUN npm install\b' "$_out"; then
    _fail "write_dockerfile_no_install" "Dockerfile nao deve conter npm install"
    return 1
  fi
  if grep -qi 'EXPOSE' "$_out"; then
    _fail "write_dockerfile_no_expose" "Dockerfile nao deve expor porta (stdio)"
    return 1
  fi
  if grep -qi 'docker push\|--network host\|--privileged' "$_out"; then
    _fail "write_dockerfile_no_push_priv" "Dockerfile nao deve conter push/--network host/--privileged"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# _mcp_docker_build_image
# ---------------------------------------------------------------------------

scenario_build_image_sem_package_json() {
  mkdir -p "$TMPDIR_TEST/ctx-empty"
  _run_mcp_docker_fn _mcp_docker_build_image "$TMPDIR_TEST/ctx-empty" "cstk-mcp-state:test"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "build_no_pkg_exit" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "package.json" || return 1
}

scenario_build_image_happy_path() {
  _make_bin_dir
  _stub_docker "$_STUB_BIN"
  mkdir -p "$TMPDIR_TEST/ctx-ok"
  : >"$TMPDIR_TEST/ctx-ok/package.json"
  _run_mcp_docker_fn _mcp_docker_build_image "$TMPDIR_TEST/ctx-ok" "cstk-mcp-state:test"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "build_happy_exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  case "$(_docker_calls_log)" in
    *"-t cstk-mcp-state:test"*) : ;;
    *) _fail "build_happy_tag" "docker build nao recebeu -t cstk-mcp-state:test"; return 1 ;;
  esac
}

scenario_build_image_docker_build_falha() {
  _make_bin_dir
  _stub_docker "$_STUB_BIN"
  mkdir -p "$TMPDIR_TEST/docker-stub"
  : >"$TMPDIR_TEST/docker-stub/build-fails"
  mkdir -p "$TMPDIR_TEST/ctx-ok2"
  : >"$TMPDIR_TEST/ctx-ok2/package.json"
  _run_mcp_docker_fn _mcp_docker_build_image "$TMPDIR_TEST/ctx-ok2" "cstk-mcp-state:test"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "build_fails_exit" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "docker build falhou" || return 1
}

# ---------------------------------------------------------------------------
# _mcp_docker_reconcile_container
# ---------------------------------------------------------------------------

scenario_reconcile_nada_remanescente() {
  _make_bin_dir
  _stub_docker "$_STUB_BIN"
  mkdir -p "$TMPDIR_TEST/docker-stub"
  : >"$TMPDIR_TEST/docker-stub/rm-nothing"
  _run_mcp_docker_fn _mcp_docker_reconcile_container "cstk-mcp-state-x"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "reconcile_nothing_exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
}

scenario_reconcile_container_removido() {
  _make_bin_dir
  _stub_docker "$_STUB_BIN"
  _run_mcp_docker_fn _mcp_docker_reconcile_container "cstk-mcp-state-x"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "reconcile_removed_exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
}

scenario_reconcile_falha_permissao() {
  _make_bin_dir
  _stub_docker "$_STUB_BIN"
  mkdir -p "$TMPDIR_TEST/docker-stub"
  : >"$TMPDIR_TEST/docker-stub/rm-fails"
  _run_mcp_docker_fn _mcp_docker_reconcile_container "cstk-mcp-state-x"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "reconcile_perm_exit" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "nao foi possivel reconciliar" || return 1
}

# ---------------------------------------------------------------------------
# _mcp_docker_ensure_enforcement_log_file
# ---------------------------------------------------------------------------

scenario_ensure_log_cria_arquivo() {
  _target="$TMPDIR_TEST/proj/.claude/enforcement-log.jsonl"
  _run_mcp_docker_fn _mcp_docker_ensure_enforcement_log_file "$_target"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "ensure_log_exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  [ -f "$_target" ] || { _fail "ensure_log_created" "arquivo nao foi criado"; return 1; }
}

scenario_ensure_log_idempotente_preserva_conteudo() {
  _target="$TMPDIR_TEST/proj2/.claude/enforcement-log.jsonl"
  mkdir -p "$(dirname "$_target")"
  printf 'existing-line\n' >"$_target"
  _run_mcp_docker_fn _mcp_docker_ensure_enforcement_log_file "$_target"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "ensure_log_idem_exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  grep -q "existing-line" "$_target" || { _fail "ensure_log_preserved" "conteudo existente foi truncado"; return 1; }
}

scenario_ensure_log_path_e_diretorio() {
  _target="$TMPDIR_TEST/proj3/.claude/enforcement-log.jsonl"
  mkdir -p "$_target"
  _run_mcp_docker_fn _mcp_docker_ensure_enforcement_log_file "$_target"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "ensure_log_dir_exit" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "SEC-H2" || return 1
}

# ---------------------------------------------------------------------------
# _mcp_docker_run — montagens + hardening (SEC-H2 estatico)
# ---------------------------------------------------------------------------

scenario_run_happy_path_invoca_docker_run() {
  _make_bin_dir
  _stub_docker "$_STUB_BIN"
  _setup_run_fixture
  _run_mcp_docker_fn _mcp_docker_run "cstk-mcp-state-demo" "cstk-mcp-state:test" \
    "$_RF_STATE_DIR" "$_RF_SCRIPTS_DIR" "$_RF_LOG_PATH" "$_RF_PROJECT_PATH" "tok3n"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "run_happy_exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  [ -n "$(_docker_run_line)" ] || { _fail "run_logged" "docker run nao foi invocado"; return 1; }
}

scenario_run_flags_basicas() {
  _make_bin_dir
  _stub_docker "$_STUB_BIN"
  _setup_run_fixture
  _run_mcp_docker_fn _mcp_docker_run "cstk-mcp-state-demo" "cstk-mcp-state:test" \
    "$_RF_STATE_DIR" "$_RF_SCRIPTS_DIR" "$_RF_LOG_PATH" "$_RF_PROJECT_PATH" "tok3n"
  _line=$(_docker_run_line)
  case "$_line" in
    *' -d '*) : ;;
    *) _fail "run_dashd" "faltou -d: $_line"; return 1 ;;
  esac
  case "$_line" in
    *' -i '*) : ;;
    *) _fail "run_dashi" "faltou -i: $_line"; return 1 ;;
  esac
  case "$_line" in
    *'--init'*) : ;;
    *) _fail "run_init" "faltou --init: $_line"; return 1 ;;
  esac
  case "$_line" in
    *'--rm'*) : ;;
    *) _fail "run_rm" "faltou --rm: $_line"; return 1 ;;
  esac
  case "$_line" in
    *'--name cstk-mcp-state-demo'*) : ;;
    *) _fail "run_name" "faltou --name: $_line"; return 1 ;;
  esac
  case "$_line" in
    *'cstk.managed=mcp-state'*) : ;;
    *) _fail "run_label" "faltou label: $_line"; return 1 ;;
  esac
}

scenario_run_hardening() {
  _make_bin_dir
  _stub_docker "$_STUB_BIN"
  _setup_run_fixture
  _run_mcp_docker_fn _mcp_docker_run "cstk-mcp-state-demo" "cstk-mcp-state:test" \
    "$_RF_STATE_DIR" "$_RF_SCRIPTS_DIR" "$_RF_LOG_PATH" "$_RF_PROJECT_PATH" "tok3n"
  _line=$(_docker_run_line)
  case "$_line" in
    *'--cap-drop ALL'*) : ;;
    *) _fail "run_capdrop" "faltou --cap-drop ALL: $_line"; return 1 ;;
  esac
  case "$_line" in
    *'--security-opt no-new-privileges'*) : ;;
    *) _fail "run_nnp" "faltou --security-opt no-new-privileges: $_line"; return 1 ;;
  esac
  case "$_line" in
    *'--read-only'*) : ;;
    *) _fail "run_readonly" "faltou --read-only: $_line"; return 1 ;;
  esac
  case "$_line" in
    *'--tmpfs /tmp:rw,noexec,nosuid'*) : ;;
    *) _fail "run_tmpfs" "faltou --tmpfs /tmp: $_line"; return 1 ;;
  esac
}

scenario_run_montagens_contratadas() {
  _make_bin_dir
  _stub_docker "$_STUB_BIN"
  _setup_run_fixture
  _run_mcp_docker_fn _mcp_docker_run "cstk-mcp-state-demo" "cstk-mcp-state:test" \
    "$_RF_STATE_DIR" "$_RF_SCRIPTS_DIR" "$_RF_LOG_PATH" "$_RF_PROJECT_PATH" "tok3n"
  _line=$(_docker_run_line)
  case "$_line" in
    *"${_RF_STATE_DIR}:/data/state"*) : ;;
    *) _fail "run_mount_state" "state-dir nao montado em /data/state: $_line"; return 1 ;;
  esac
  case "$_line" in
    *"${_RF_SCRIPTS_DIR}:/opt/cstk/scripts:ro"*) : ;;
    *) _fail "run_mount_scripts" "scripts-dir nao montado ro em /opt/cstk/scripts: $_line"; return 1 ;;
  esac
  case "$_line" in
    *"${_RF_LOG_PATH}:/data/enforcement-log.jsonl"*) : ;;
    *) _fail "run_mount_log" "enforcement-log nao montado em /data/enforcement-log.jsonl: $_line"; return 1 ;;
  esac
}

# 5.2.3 — assercao estatica obrigatoria: nenhuma linha `docker run` monta
# .claude como DIRETORIO, $HOME, /, ou docker.sock (SEC-H2). O fixture
# acima ja coloca o enforcement-log SOB .claude/ deliberadamente -- esta
# assercao confirma que apenas o ARQUIVO aparece na linha de mount, nunca
# o diretorio .claude sozinho, e que nenhuma porta/privilegio escala.
scenario_run_sec_h2_montagens_proibidas() {
  _make_bin_dir
  _stub_docker "$_STUB_BIN"
  _setup_run_fixture
  _run_mcp_docker_fn _mcp_docker_run "cstk-mcp-state-demo" "cstk-mcp-state:test" \
    "$_RF_STATE_DIR" "$_RF_SCRIPTS_DIR" "$_RF_LOG_PATH" "$_RF_PROJECT_PATH" "tok3n"
  _line=$(_docker_run_line)
  if printf '%s' "$_line" | grep -qE -- '-v [^ ]*/\.claude:[^/]'; then
    _fail "sec_h2_claude_dir" "montou .claude inteiro como diretorio: $_line"
    return 1
  fi
  if printf '%s' "$_line" | grep -qE -- '\$HOME'; then
    _fail "sec_h2_home" "referencia \$HOME literal na linha de run: $_line"
    return 1
  fi
  if printf '%s' "$_line" | grep -qE -- '-v /:'; then
    _fail "sec_h2_root" "montou / (raiz do host): $_line"
    return 1
  fi
  if printf '%s' "$_line" | grep -qi 'docker.sock'; then
    _fail "sec_h2_dockersock" "montou docker.sock: $_line"
    return 1
  fi
  if printf '%s' "$_line" | grep -qE -- '(^| )-p |--network host|--privileged'; then
    _fail "sec_h2_no_port_no_priv" "publicou porta ou escalou privilegio: $_line"
    return 1
  fi
}

scenario_run_enforcement_log_e_diretorio_nunca_chama_docker_run() {
  _make_bin_dir
  _stub_docker "$_STUB_BIN"
  _setup_run_fixture
  mkdir -p "$_RF_LOG_PATH"
  _run_mcp_docker_fn _mcp_docker_run "cstk-mcp-state-demo" "cstk-mcp-state:test" \
    "$_RF_STATE_DIR" "$_RF_SCRIPTS_DIR" "$_RF_LOG_PATH" "$_RF_PROJECT_PATH" "tok3n"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "run_logdir_exit" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
  [ -z "$(_docker_run_line)" ] || { _fail "run_never_called" "docker run foi invocado apesar do enforcement-log invalido"; return 1; }
}

scenario_run_docker_run_falha() {
  _make_bin_dir
  _stub_docker "$_STUB_BIN"
  mkdir -p "$TMPDIR_TEST/docker-stub"
  : >"$TMPDIR_TEST/docker-stub/run-fails"
  _setup_run_fixture
  _run_mcp_docker_fn _mcp_docker_run "cstk-mcp-state-demo" "cstk-mcp-state:test" \
    "$_RF_STATE_DIR" "$_RF_SCRIPTS_DIR" "$_RF_LOG_PATH" "$_RF_PROJECT_PATH" "tok3n"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "run_fails_exit" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "docker run falhou" || return 1
}

# ---------------------------------------------------------------------------
# _mcp_docker_stop
# ---------------------------------------------------------------------------

scenario_stop_invoca_docker_stop_grace() {
  _make_bin_dir
  _stub_docker "$_STUB_BIN"
  _run_mcp_docker_fn _mcp_docker_stop "cstk-mcp-state-demo"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "stop_exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  case "$(_docker_calls_log)" in
    *'stop -t 5 cstk-mcp-state-demo'*) : ;;
    *) _fail "stop_invocation" "docker stop -t 5 nao foi chamado corretamente"; return 1 ;;
  esac
}

scenario_stop_idempotente_container_inexistente() {
  _make_bin_dir
  mkdir -p "$_STUB_BIN"
  cat >"$_STUB_BIN/docker" <<'STUBFAIL'
#!/bin/sh
if [ "$1" = "stop" ]; then
  printf 'Error: No such container: %s\n' "$3" >&2
  exit 1
fi
exit 0
STUBFAIL
  chmod +x "$_STUB_BIN/docker"
  _run_mcp_docker_fn _mcp_docker_stop "cstk-mcp-state-inexistente"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "stop_idem_exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
}

run_all_scenarios
