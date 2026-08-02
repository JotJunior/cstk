#!/bin/sh
# test_mcp.sh — cobre cli/lib/mcp.sh (subcomando `cstk mcp`).
#
# Ref: docs/specs/state-mcp-server/contracts/mcp-session-lifecycle.md
#        §CLI: `cstk mcp` / §`cstk mcp status` / §`cstk mcp start`/`stop`
#      docs/specs/state-mcp-server/tasks.md FASE 1 task 1.4.3, FASE 5
#        task 5.3.4
#
# ESCOPO: `status` (FASE 1, sem Docker) + `start`/`stop` (FASE 5 task 5.3,
# mock de `docker` — mesma filosofia de test_mcp-docker.sh: um stub
# completo substitui o daemon real, FAST e HERMETICO). Cobre os 3 estados
# de status (active/stopped/unavailable) via --state-dir e via
# --project-path (que reusa a precedencia de deteccao do hook
# PreToolUse, read-only).

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

# _cstk_mcp ARGS... -> roda `cstk mcp ARGS` com o layout de repo. PATH
# interno controlado via $_MCP_INNER_PATH (default: PATH corrente) — usa
# `env` explicito (nunca prefixo de atribuicao direto na chamada de
# `capture`) porque `capture` (harness.sh) precisa de `mktemp` no PATH
# NORMAL para o proprio mecanismo de captura funcionar; so o subprocesso
# `sh "$CSTK_BIN"` deve rodar com PATH restrito.
_cstk_mcp() {
  env CSTK_LIB="$CSTK_LIB_DIR" PATH="${_MCP_INNER_PATH:-$PATH}" \
    sh "$CSTK_BIN" mcp "$@"
}

# _init_active_exec DIR -> inicializa uma execucao 00c (status em_andamento
# por padrao do state-rw.sh init) em DIR.
_init_active_exec() {
  capture "$STATE_RW" init --state-dir "$1" \
    --execucao-id "exec-mcp-test" --projeto-alvo-path "/tmp/p" --descricao "POC mcp status"
}

# _init_active_exec_at PROJECT_PATH STATE_DIR -> mesma coisa, mas com
# target_project_path REAL (necessario para start: o enforcement-log.jsonl
# e criado de fato sob <PROJECT_PATH>/.claude/).
_init_active_exec_at() {
  capture "$STATE_RW" init --state-dir "$2" \
    --execucao-id "exec-mcp-start-test" --projeto-alvo-path "$1" --descricao "POC mcp start/stop"
}

# ---------- fixtures para start/stop (docker mockado) ----------

# _isolated_sh_dir: dir com APENAS um symlink para o `sh` real, para um
# PATH interno minimo sem arrastar o docker de verdade do host (mesmo
# padrao de tests/cstk/test_mcp-docker.sh / test_serve-docker.sh). So
# serve para testar FUNCOES ISOLADAS (sourced diretamente) — nao o binario
# `cstk` inteiro, que precisa de mais utilitarios (sed etc.) no PATH.
_isolated_sh_dir() {
  _ish_dir="$TMPDIR_TEST/shbin"
  if [ ! -e "$_ish_dir/sh" ]; then
    mkdir -p "$_ish_dir"
    _ish_sh=$(command -v sh)
    ln -sf "$_ish_sh" "$_ish_dir/sh"
  fi
  printf '%s' "$_ish_dir"
}

# _path_without_docker -> imprime uma copia do PATH corrente removendo
# APENAS o(s) diretorio(s) que de fato contem um binario `docker`
# executavel — nunca um PATH hardcoded/minimo (CLAUDE.md "PATH-stub nao
# esconde binario de /usr/bin": um PATH artificial pode nao refletir onde
# o SUT (aqui, o proprio binario `cstk`, que precisa de sed/jq/etc.)
# realmente busca seus utilitarios; passa local e quebra no CI). Deriva
# dinamicamente de $PATH — funciona independente de onde o `docker` do
# host esteja instalado.
_path_without_docker() {
  _pwd_out=""
  _pwd_ifs_save=$IFS
  IFS=:
  for _pwd_dir in $PATH; do
    IFS=$_pwd_ifs_save
    [ -n "$_pwd_dir" ] || continue
    [ -x "$_pwd_dir/docker" ] && continue
    if [ -z "$_pwd_out" ]; then
      _pwd_out="$_pwd_dir"
    else
      _pwd_out="$_pwd_out:$_pwd_dir"
    fi
  done
  IFS=$_pwd_ifs_save
  printf '%s' "$_pwd_out"
}

# _make_bin_dir — cria dir de stubs e o prepende ao PATH (mutante global
# de PATH; escopo confinado ao subshell do scenario, como o resto do
# harness ja pratica).
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

# _stub_docker BIN_DIR — stub `docker` cobrindo info/build/rm/run/stop/
# exec, subset suficiente para exercitar `cstk mcp start`/`stop`. Marcadores
# em $TMPDIR_TEST/docker-stub/ (escrever ANTES de chamar a funcao sob
# teste): daemon-down, build-fails, run-fails, exec-fails.
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
    printf 'Error: No such container\n' >&2
    exit 1
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
  exec)
    if [ -f "$_stub_dir/exec-fails" ]; then
      printf 'healthcheck: falhou: stub-docker exec simulado falhou\n' >&2
      exit 1
    fi
    printf 'healthcheck: ok\n'
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

# _fake_context DIR -> escreve um package.json minimo em DIR (contexto de
# build sintetico — o stub `docker build` nunca le o conteudo de verdade).
_fake_context() {
  mkdir -p "$1"
  printf '{"name":"cstk-mcp-state-fixture","version":"9.9.9"}\n' >"$1/package.json"
}

# _setup_start_fixture -> prepara projeto+state-dir reais e exporta
# _SF_PROJECT / _SF_STATE_DIR / _SF_CONTEXT (via CSTK_MCP_CONTEXT_DIR).
_setup_start_fixture() {
  _SF_PROJECT="$TMPDIR_TEST/proj"
  _SF_STATE_DIR="$_SF_PROJECT/.claude/feature-00c-state/demo"
  _SF_CONTEXT="$TMPDIR_TEST/context"
  mkdir -p "$_SF_STATE_DIR"
  _fake_context "$_SF_CONTEXT"
  CSTK_MCP_CONTEXT_DIR="$_SF_CONTEXT"
  export CSTK_MCP_CONTEXT_DIR
  _init_active_exec_at "$_SF_PROJECT" "$_SF_STATE_DIR"
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

# ---------- status --live (task 5.3.3, FR-010: reverifica saude sem reiniciar) ----------

scenario_status_live_mode_docker_saudavel_permanece_active() {
  _sd="$TMPDIR_TEST/sd-live-ok"
  _write_descriptor "$_sd" "tok-live-ok" "docker" ""
  _make_bin_dir
  _stub_docker "$_STUB_BIN"
  capture _cstk_mcp status --state-dir "$_sd" --live
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "live saudavel exit" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "status=active" || return 1
  # a sonda de verdade (docker exec) MUST ter sido chamada.
  _log=$(_docker_calls_log)
  case "$_log" in
    *"exec "*) : ;;
    *) _fail "docker exec (live healthcheck) nao chamado" "$_log"; return 1 ;;
  esac
}

scenario_status_live_mode_docker_morto_reporta_unavailable_sem_reiniciar() {
  _sd="$TMPDIR_TEST/sd-live-dead"
  _write_descriptor "$_sd" "tok-live-dead" "docker" ""
  _make_bin_dir
  _stub_docker "$_STUB_BIN"
  mkdir -p "$TMPDIR_TEST/docker-stub"
  : >"$TMPDIR_TEST/docker-stub/exec-fails"
  capture _cstk_mcp status --state-dir "$_sd" --live
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "live morto exit" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "status=unavailable" || return 1
  assert_stdout_contains "reason=health-timeout" || return 1
  # NUNCA reinicia (FR-010: "reverifica saude SEM reiniciar") — nenhuma
  # invocacao de `docker run` deve ter ocorrido.
  _log=$(_docker_calls_log)
  case "$_log" in
    *"run "*) _fail "docker run nao deveria ter sido chamado (--live nunca reinicia)" "$_log"; return 1 ;;
    *) : ;;
  esac
  # o descritor em disco permanece INTOCADO (ainda mode=docker,
  # stopped_at=null) — --live e observacional, nao muda estado persistido.
  _mode_disco=$(jq -r '.mode' "$_sd/mcp-server.json")
  [ "$_mode_disco" = "docker" ] || { _fail "descritor mutado por --live" "$_mode_disco"; return 1; }
}

scenario_status_sem_live_nao_chama_docker() {
  _sd="$TMPDIR_TEST/sd-no-live"
  _write_descriptor "$_sd" "tok-no-live" "docker" ""
  # PATH sem docker: sem --live, status nunca deve tentar invocar docker.
  _MCP_INNER_PATH=$(_path_without_docker)
  capture _cstk_mcp status --state-dir "$_sd"
  unset _MCP_INNER_PATH
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "status sem live exit" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "status=active" || return 1
}

scenario_status_live_mode_bash_fallback_nao_chama_docker() {
  _sd="$TMPDIR_TEST/sd-live-fallback"
  _write_descriptor "$_sd" "tok-live-fb" "bash-fallback" ""
  # mode=bash-fallback: --live nao deve tentar docker exec (nao ha
  # container). PATH sem docker prova que nada foi invocado.
  _MCP_INNER_PATH=$(_path_without_docker)
  capture _cstk_mcp status --state-dir "$_sd" --live
  unset _MCP_INNER_PATH
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "live bash-fallback exit" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "status=active" || return 1
  assert_stdout_contains "mode=bash-fallback" || return 1
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

# ---------- start/stop: uso incorreto (sem Docker necessario) ----------

scenario_start_sem_flags_exit_2() {
  capture _cstk_mcp start
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "start sem flags exit" "esperado 2, obtido $_CAPTURED_EXIT"; return 1; }
}

scenario_start_flag_desconhecida_exit_2() {
  capture _cstk_mcp start --bogus x
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "start flag desconhecida exit" "esperado 2, obtido $_CAPTURED_EXIT"; return 1; }
}

scenario_start_state_dir_inexistente_exit_1() {
  capture _cstk_mcp start --state-dir "$TMPDIR_TEST/nao-existe"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "start state-dir inexistente exit" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
}

scenario_stop_sem_flags_exit_2() {
  capture _cstk_mcp stop
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "stop sem flags exit" "esperado 2, obtido $_CAPTURED_EXIT"; return 1; }
}

scenario_stop_state_dir_inexistente_exit_1() {
  capture _cstk_mcp stop --state-dir "$TMPDIR_TEST/nao-existe"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "stop state-dir inexistente exit" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
}

# ---------- start: caminho bash-fallback (FR-007, nunca aborta) ----------

scenario_start_docker_ausente_bash_fallback_exit_3() {
  _setup_start_fixture
  _MCP_INNER_PATH=$(_path_without_docker)
  capture _cstk_mcp start --state-dir "$_SF_STATE_DIR"
  unset _MCP_INNER_PATH
  [ "$_CAPTURED_EXIT" = 3 ] || { _fail "start docker ausente exit" "esperado 3, obtido $_CAPTURED_EXIT ($_CAPTURED_STDERR)"; return 1; }
  assert_stdout_contains "status=unavailable" || return 1
  assert_stdout_contains "reason=docker-absent" || return 1
  assert_stdout_contains "mode=bash-fallback" || return 1
  _mode=$(jq -r '.mode' "$_SF_STATE_DIR/mcp-server.json")
  [ "$_mode" = "bash-fallback" ] || { _fail "descritor mode" "esperado bash-fallback, obtido $_mode"; return 1; }
  _reason=$(jq -r '.unavailable_reason' "$_SF_STATE_DIR/mcp-server.json")
  [ "$_reason" = "docker-absent" ] || { _fail "descritor unavailable_reason" "esperado docker-absent, obtido $_reason"; return 1; }
}

scenario_start_daemon_down_bash_fallback_exit_3() {
  _setup_start_fixture
  _make_bin_dir
  _stub_docker "$_STUB_BIN"
  mkdir -p "$TMPDIR_TEST/docker-stub"
  : >"$TMPDIR_TEST/docker-stub/daemon-down"
  capture _cstk_mcp start --state-dir "$_SF_STATE_DIR"
  [ "$_CAPTURED_EXIT" = 3 ] || { _fail "start daemon down exit" "esperado 3, obtido $_CAPTURED_EXIT ($_CAPTURED_STDERR)"; return 1; }
  assert_stdout_contains "reason=daemon-unreachable" || return 1
}

scenario_start_build_falha_bash_fallback_exit_3() {
  _setup_start_fixture
  _make_bin_dir
  _stub_docker "$_STUB_BIN"
  mkdir -p "$TMPDIR_TEST/docker-stub"
  : >"$TMPDIR_TEST/docker-stub/build-fails"
  capture _cstk_mcp start --state-dir "$_SF_STATE_DIR"
  [ "$_CAPTURED_EXIT" = 3 ] || { _fail "start build falha exit" "esperado 3, obtido $_CAPTURED_EXIT ($_CAPTURED_STDERR)"; return 1; }
  assert_stdout_contains "reason=image-build-failed" || return 1
}

scenario_start_run_falha_bash_fallback_exit_3() {
  _setup_start_fixture
  _make_bin_dir
  _stub_docker "$_STUB_BIN"
  mkdir -p "$TMPDIR_TEST/docker-stub"
  : >"$TMPDIR_TEST/docker-stub/run-fails"
  capture _cstk_mcp start --state-dir "$_SF_STATE_DIR"
  [ "$_CAPTURED_EXIT" = 3 ] || { _fail "start run falha exit" "esperado 3, obtido $_CAPTURED_EXIT ($_CAPTURED_STDERR)"; return 1; }
  assert_stdout_contains "reason=container-start-failed" || return 1
}

scenario_start_healthcheck_falha_bash_fallback_para_container() {
  _setup_start_fixture
  _make_bin_dir
  _stub_docker "$_STUB_BIN"
  mkdir -p "$TMPDIR_TEST/docker-stub"
  : >"$TMPDIR_TEST/docker-stub/exec-fails"
  capture _cstk_mcp start --state-dir "$_SF_STATE_DIR"
  [ "$_CAPTURED_EXIT" = 3 ] || { _fail "start healthcheck falha exit" "esperado 3, obtido $_CAPTURED_EXIT ($_CAPTURED_STDERR)"; return 1; }
  assert_stdout_contains "reason=health-timeout" || return 1
  # health check falho DEVE derrubar o container recem-subido (evita
  # orfao saudavel-de-mentirinha) — confirma que `docker stop` foi chamado.
  _log=$(_docker_calls_log)
  case "$_log" in
    *"stop "*) : ;;
    *) _fail "docker stop nao chamado apos healthcheck falho" "$_log"; return 1 ;;
  esac
}

scenario_start_contexto_ausente_bash_fallback_exit_3() {
  _SF_PROJECT="$TMPDIR_TEST/proj2"
  _SF_STATE_DIR="$_SF_PROJECT/.claude/feature-00c-state/demo2"
  mkdir -p "$_SF_STATE_DIR"
  _init_active_exec_at "$_SF_PROJECT" "$_SF_STATE_DIR"
  _make_bin_dir
  _stub_docker "$_STUB_BIN"
  # CSTK_MCP_CONTEXT_DIR aponta para path SEM package.json — forca a
  # resolucao a nao cair no fallback real do repo (relativo a CSTK_LIB),
  # que existiria de verdade nesta arvore de dev.
  CSTK_MCP_CONTEXT_DIR="$TMPDIR_TEST/nao-existe-context"
  export CSTK_MCP_CONTEXT_DIR
  CSTK_LIB="$TMPDIR_TEST/lib-sem-contexto"
  mkdir -p "$CSTK_LIB"
  cp "$CSTK_LIB_DIR"/mcp.sh "$CSTK_LIB_DIR"/mcp-docker.sh "$CSTK_LIB_DIR"/common.sh "$CSTK_LIB" 2>/dev/null
  export CSTK_LIB
  capture sh "$CSTK_BIN" mcp start --state-dir "$_SF_STATE_DIR"
  unset CSTK_LIB
  [ "$_CAPTURED_EXIT" = 3 ] || { _fail "start contexto ausente exit" "esperado 3, obtido $_CAPTURED_EXIT ($_CAPTURED_STDERR)"; return 1; }
  assert_stdout_contains "reason=image-build-failed" || return 1
}

# ---------- start: caminho feliz (mode=docker) ----------

scenario_start_happy_path_mode_docker() {
  _setup_start_fixture
  _make_bin_dir
  _stub_docker "$_STUB_BIN"
  capture _cstk_mcp start --state-dir "$_SF_STATE_DIR"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "start happy path exit" "esperado 0, obtido $_CAPTURED_EXIT ($_CAPTURED_STDERR)"; return 1; }
  assert_stdout_contains "status=active" || return 1
  assert_stdout_contains "mode=docker" || return 1

  [ -f "$_SF_STATE_DIR/mcp-server.json" ] || { _fail "descritor nao gravado" ""; return 1; }
  # GNU (-c) primeiro, fallback BSD (-f) — mesmo padrao de
  # tests/cstk/test_recall.sh::_perm_of.
  _perm=$(stat -c '%a' "$_SF_STATE_DIR/mcp-server.json" 2>/dev/null) \
    || _perm=$(stat -f '%Lp' "$_SF_STATE_DIR/mcp-server.json" 2>/dev/null)
  [ "$_perm" = "600" ] || { _fail "descritor sem chmod 600" "$_perm"; return 1; }

  _sid=$(jq -r '.session_id' "$_SF_STATE_DIR/mcp-server.json")
  # >= 128 bits = >= 32 hex chars; geramos 32 bytes (64 hex chars).
  _sid_len=$(printf '%s' "$_sid" | tr -d '\n' | wc -c | tr -d ' ')
  [ "$_sid_len" -ge 32 ] || { _fail "session_id curto demais" "len=$_sid_len"; return 1; }
  case "$_sid" in
    *[!0-9a-f]*) _fail "session_id nao e hex" "$_sid"; return 1 ;;
  esac

  _kind=$(jq -r '.execution_kind' "$_SF_STATE_DIR/mcp-server.json")
  [ "$_kind" = "feature-00c" ] || { _fail "execution_kind" "esperado feature-00c, obtido $_kind"; return 1; }
  _short=$(jq -r '.short_name' "$_SF_STATE_DIR/mcp-server.json")
  [ "$_short" = "demo" ] || { _fail "short_name" "esperado demo, obtido $_short"; return 1; }
  _mode=$(jq -r '.mode' "$_SF_STATE_DIR/mcp-server.json")
  [ "$_mode" = "docker" ] || { _fail "mode" "esperado docker, obtido $_mode"; return 1; }
  _container=$(jq -r '.container_name' "$_SF_STATE_DIR/mcp-server.json")
  case "$_container" in
    cstk-mcp-state-*) : ;;
    *) _fail "container_name inesperado" "$_container"; return 1 ;;
  esac
  _stopped=$(jq -r '.stopped_at' "$_SF_STATE_DIR/mcp-server.json")
  [ "$_stopped" = "null" ] || { _fail "stopped_at deveria ser null" "$_stopped"; return 1; }

  # healthcheck (docker exec) MUST ter sido chamado ANTES de reportar
  # sucesso (FR-011).
  _log=$(_docker_calls_log)
  case "$_log" in
    *"exec "*) : ;;
    *) _fail "docker exec (healthcheck) nao chamado" "$_log"; return 1 ;;
  esac
}

scenario_start_agente00c_execution_kind() {
  _SF_PROJECT="$TMPDIR_TEST/proj-a"
  _SF_STATE_DIR="$_SF_PROJECT/.claude/agente-00c-state"
  _SF_CONTEXT="$TMPDIR_TEST/context-a"
  mkdir -p "$_SF_STATE_DIR"
  _fake_context "$_SF_CONTEXT"
  CSTK_MCP_CONTEXT_DIR="$_SF_CONTEXT"
  export CSTK_MCP_CONTEXT_DIR
  _init_active_exec_at "$_SF_PROJECT" "$_SF_STATE_DIR"
  _make_bin_dir
  _stub_docker "$_STUB_BIN"
  capture _cstk_mcp start --state-dir "$_SF_STATE_DIR"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "start agente-00c exit" "esperado 0, obtido $_CAPTURED_EXIT ($_CAPTURED_STDERR)"; return 1; }
  _kind=$(jq -r '.execution_kind' "$_SF_STATE_DIR/mcp-server.json")
  [ "$_kind" = "agente-00c" ] || { _fail "execution_kind" "esperado agente-00c, obtido $_kind"; return 1; }
  _short=$(jq -r '.short_name' "$_SF_STATE_DIR/mcp-server.json")
  [ "$_short" = "null" ] || { _fail "short_name deveria ser null" "$_short"; return 1; }
}

# ---------- stop ----------

scenario_stop_sem_descritor_idempotente_exit_0() {
  _sd="$TMPDIR_TEST/sd-stop-none"
  mkdir -p "$_sd"
  capture _cstk_mcp stop --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "stop sem descritor exit" "esperado 0, obtido $_CAPTURED_EXIT ($_CAPTURED_STDERR)"; return 1; }
}

scenario_stop_ja_parado_idempotente_nao_re_invoca_docker() {
  _sd="$TMPDIR_TEST/sd-stop-already"
  _write_descriptor "$_sd" "tok-x" "docker" "2026-08-01T03:00:00Z"
  _make_bin_dir
  _stub_docker "$_STUB_BIN"
  capture _cstk_mcp stop --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "stop ja parado exit" "esperado 0, obtido $_CAPTURED_EXIT ($_CAPTURED_STDERR)"; return 1; }
  # container ja estava parado — nenhuma invocacao NOVA de `docker stop`
  # deveria ter ocorrido (log inexistente ou vazio).
  _log=$(_docker_calls_log)
  case "$_log" in
    *"stop "*) _fail "docker stop nao deveria ter sido chamado (ja parado)" "$_log"; return 1 ;;
    *) : ;;
  esac
}

scenario_stop_ativo_mode_docker_chama_docker_stop_e_preenche_stopped_at() {
  _sd="$TMPDIR_TEST/sd-stop-active"
  _write_descriptor "$_sd" "tok-y" "docker" ""
  _make_bin_dir
  _stub_docker "$_STUB_BIN"
  capture _cstk_mcp stop --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "stop ativo exit" "esperado 0, obtido $_CAPTURED_EXIT ($_CAPTURED_STDERR)"; return 1; }
  _log=$(_docker_calls_log)
  case "$_log" in
    *"stop "*) : ;;
    *) _fail "docker stop nao chamado" "$_log"; return 1 ;;
  esac
  _stopped=$(jq -r '.stopped_at' "$_sd/mcp-server.json")
  [ "$_stopped" != "null" ] && [ -n "$_stopped" ] || { _fail "stopped_at nao preenchido" "$_stopped"; return 1; }
}

scenario_stop_ativo_mode_bash_fallback_nao_chama_docker() {
  _sd="$TMPDIR_TEST/sd-stop-fallback"
  _write_descriptor "$_sd" "tok-z" "bash-fallback" ""
  # Nao precisa restringir PATH: o codigo so invoca _mcp_docker_stop
  # quando mode="docker" — mode=bash-fallback ja garante, pelo proprio
  # fluxo, que `docker` nunca e chamado (o docker do host, se presente,
  # segue disponivel no PATH normal aqui — irrelevante para o teste).
  capture _cstk_mcp stop --state-dir "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "stop bash-fallback exit" "esperado 0, obtido $_CAPTURED_EXIT ($_CAPTURED_STDERR)"; return 1; }
  _stopped=$(jq -r '.stopped_at' "$_sd/mcp-server.json")
  [ "$_stopped" != "null" ] && [ -n "$_stopped" ] || { _fail "stopped_at nao preenchido (bash-fallback)" "$_stopped"; return 1; }
}

# ---------- uso geral do subcomando ----------

scenario_mcp_sem_subcomando_mostra_uso() {
  capture _cstk_mcp
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "uso deveria sair 0" "exit=$_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "status" || return 1
  assert_stdout_contains "start" || return 1
  assert_stdout_contains "stop" || return 1
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
