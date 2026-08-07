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
# por padrao do state-rw.sh init) em DIR. HOME isolado em $TMPDIR_TEST/home
# (nunca o HOME real do operador): `state-rw.sh init` decide o backend
# (json|sqlite) lendo $HOME/.claude/cstk/config (state-backend.sh) — sem
# isolar, a suite herdaria silenciosamente o backend global da maquina do
# desenvolvedor (sqlite, se `cstk state enable-sqlite` ja tiver rodado ali),
# quebrando a hermeticidade do teste (CLAUDE.md "Fonte de verdade" +
# padrao ja praticado por test_mcp-docker.sh::_run_mcp_docker_fn).
_init_active_exec() {
  capture env HOME="$TMPDIR_TEST/home" "$STATE_RW" init --state-dir "$1" \
    --execucao-id "exec-mcp-test" --projeto-alvo-path "/tmp/p" --descricao "POC mcp status"
}

# _init_active_exec_at PROJECT_PATH STATE_DIR -> mesma coisa, mas com
# target_project_path REAL (necessario para start: o enforcement-log.jsonl
# e criado de fato sob <PROJECT_PATH>/.claude/).
_init_active_exec_at() {
  capture env HOME="$TMPDIR_TEST/home" "$STATE_RW" init --state-dir "$2" \
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

# _path_without_docker -> imprime uma copia do PATH corrente em que cada
# diretorio que contem um `docker` executavel e SUBSTITUIDO por um espelho
# (symlinks a todo o conteudo EXCETO `docker`). A versao anterior REMOVIA o
# diretorio inteiro — no CI Ubuntu docker mora em /usr/bin, e remover o dir
# arrancava junto sed/jq/awk do SUT: os cenarios "docker ausente" passavam
# local (macOS, docker em dir dedicado) e quebravam no CI com outra falha
# que nao docker-absent (variante nova da armadilha CLAUDE.md "PATH-stub
# nao esconde binario de /usr/bin", caso real: release v6.1.0 run
# 30751019774). O espelho preserva todos os utilitarios e faz
# `command -v docker` falhar de verdade em qualquer host.
_path_without_docker() {
  _pwd_out=""
  _pwd_mirrors="$TMPDIR_TEST/path-no-docker"
  _pwd_n=0
  _pwd_ifs_save=$IFS
  IFS=:
  for _pwd_dir in $PATH; do
    IFS=$_pwd_ifs_save
    [ -n "$_pwd_dir" ] || continue
    if [ -x "$_pwd_dir/docker" ]; then
      _pwd_n=$((_pwd_n + 1))
      _pwd_m="$_pwd_mirrors/$_pwd_n"
      if [ ! -d "$_pwd_m" ]; then
        mkdir -p "$_pwd_m"
        for _pwd_f in "$_pwd_dir"/*; do
          [ -e "$_pwd_f" ] || continue
          _pwd_b=${_pwd_f##*/}
          [ "$_pwd_b" = "docker" ] && continue
          ln -s "$_pwd_f" "$_pwd_m/$_pwd_b" 2>/dev/null || :
        done
      fi
      _pwd_dir="$_pwd_m"
    fi
    if [ -z "$_pwd_out" ]; then
      _pwd_out="$_pwd_dir"
    else
      _pwd_out="$_pwd_out:$_pwd_dir"
    fi
    IFS=:
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

scenario_status_live_deteccao_mid_onda_uma_unica_sonda_sem_retry() {
  # task 5.5, CHK071: gatilho de deteccao de queda MID-ONDA (apos a 1a tool
  # ja ter sido chamada) reusa `status --live` -- contracts/mcp-session-
  # lifecycle.md §Deteccao de queda mid-onda define ZERO retries da MESMA
  # chamada + UMA confirmacao via status --live. Esta assercao prova, no
  # nivel do stub `docker`, que a confirmacao e de fato uma UNICA sonda
  # (nenhum loop de retry escondido em _mcp_docker_healthcheck/status --live).
  _sd="$TMPDIR_TEST/sd-live-mid-onda"
  _write_descriptor "$_sd" "tok-live-mid-onda" "docker" ""
  _make_bin_dir
  _stub_docker "$_STUB_BIN"
  mkdir -p "$TMPDIR_TEST/docker-stub"
  : >"$TMPDIR_TEST/docker-stub/exec-fails"
  capture _cstk_mcp status --state-dir "$_sd" --live
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "live mid-onda exit" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "status=unavailable" || return 1
  assert_stdout_contains "reason=health-timeout" || return 1
  _exec_calls=$(grep -c '^exec ' "$TMPDIR_TEST/docker-calls.log" 2>/dev/null || echo 0)
  [ "$_exec_calls" = "1" ] || { _fail "gc mid-onda deveria fazer exatamente 1 sonda (0 retries), fez" "$_exec_calls"; return 1; }
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
  # Reason DISTINTO de image-build-failed (fix pos-6.2.1): fonte do servidor
  # nao instalada => server-source-missing (aponta `cstk update`), nunca o
  # reason de build que mascarava o gap de distribuicao.
  assert_stdout_contains "reason=server-source-missing" || return 1
  assert_stderr_contains "cstk update" || return 1
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

# ---------- gc (task 5.4, CHK064: deteccao/limpeza de container orfao) ----------

# _stub_docker_gc BIN_DIR — stub `docker` cobrindo info/ps/rm, suficiente
# para exercitar `cstk mcp gc`. Marcador $TMPDIR_TEST/docker-stub/ps-output
# (TSV name<TAB>state_dir, uma linha por container) e escrito PELO PROPRIO
# scenario ANTES de invocar `gc` — mesmo padrao de test_mcp-docker.sh
# scenario_list_managed_com_containers. rm-fails-for/rm-nothing-for listam
# (uma por linha) nomes de container para os quais `docker rm -f` deve
# falhar (permissao) ou reportar "No such container" (idempotente).
_stub_docker_gc() {
  _sdg_bin="$1"
  cat >"$_sdg_bin/docker" <<'STUB'
#!/bin/sh
_stub_dir="$TMPDIR_TEST/docker-stub"
mkdir -p "$_stub_dir"
printf '%s\n' "$*" >>"$TMPDIR_TEST/docker-calls.log"

case "$1" in
  info)
    [ -f "$_stub_dir/daemon-down" ] && exit 1
    exit 0
    ;;
  ps)
    [ -f "$_stub_dir/ps-output" ] && cat "$_stub_dir/ps-output"
    exit 0
    ;;
  rm)
    _target="$3"
    if [ -f "$_stub_dir/rm-fails-for" ] && grep -qx "$_target" "$_stub_dir/rm-fails-for" 2>/dev/null; then
      printf 'Error: permission denied while trying to connect to the Docker daemon socket\n' >&2
      exit 1
    fi
    if [ -f "$_stub_dir/rm-nothing-for" ] && grep -qx "$_target" "$_stub_dir/rm-nothing-for" 2>/dev/null; then
      printf 'Error: No such container: %s\n' "$_target" >&2
      exit 1
    fi
    exit 0
    ;;
  *)
    printf 'stub-docker-gc: subcomando inesperado: %s\n' "$*" >&2
    exit 1
    ;;
esac
STUB
  chmod +x "$_sdg_bin/docker"
}

# _gc_ps_line NAME STATE_DIR -> escreve uma linha TSV em docker-stub/ps-output
_gc_ps_line() {
  mkdir -p "$TMPDIR_TEST/docker-stub"
  printf '%s\t%s\n' "$1" "$2" >>"$TMPDIR_TEST/docker-stub/ps-output"
}

# _mark_terminal STATE_DIR STATUS -> promove execution.status para um valor
# terminal (concluida|abortada) na fixture ja inicializada por
# _init_active_exec[_at]. finished_at e escrito ANTES de status (sob
# backend sqlite, um CHECK constraint exige status terminal <=> finished_at
# NAO-NULO; escrever status sozinho primeiro violaria o constraint).
_mark_terminal() {
  capture env HOME="$TMPDIR_TEST/home" "$STATE_RW" set --state-dir "$1" \
    --field '.execution.finished_at' --value '"2026-08-01T00:00:00Z"'
  capture env HOME="$TMPDIR_TEST/home" "$STATE_RW" set --state-dir "$1" \
    --field '.execution.status' --value "\"$2\""
}

scenario_gc_docker_ausente_summary_indisponivel_exit_0() {
  _MCP_INNER_PATH=$(_path_without_docker)
  capture _cstk_mcp gc
  unset _MCP_INNER_PATH
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "gc docker ausente exit" "esperado 0, obtido $_CAPTURED_EXIT ($_CAPTURED_STDERR)"; return 1; }
  assert_stdout_contains "summary=docker-indisponivel" || return 1
}

scenario_gc_daemon_down_summary_indisponivel_exit_0() {
  _make_bin_dir
  _stub_docker_gc "$_STUB_BIN"
  mkdir -p "$TMPDIR_TEST/docker-stub"
  : >"$TMPDIR_TEST/docker-stub/daemon-down"
  capture _cstk_mcp gc
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "gc daemon down exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "summary=docker-indisponivel" || return 1
}

scenario_gc_nenhum_container_gerenciado_summary_zero() {
  _make_bin_dir
  _stub_docker_gc "$_STUB_BIN"
  capture _cstk_mcp gc
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "gc vazio exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "summary=ok examined:0 removed:0 kept:0 skipped:0" || return 1
}

scenario_gc_sem_label_e_skipped_e_preservado() {
  _make_bin_dir
  _stub_docker_gc "$_STUB_BIN"
  _gc_ps_line "cstk-mcp-state-legacy" "-"
  capture _cstk_mcp gc
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "gc sem-label exit" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "action=skipped name=cstk-mcp-state-legacy reason=sem-label" || return 1
  assert_stdout_contains "skipped:1" || return 1
  case "$(_docker_calls_log)" in
    *"rm -f cstk-mcp-state-legacy"*) _fail "gc sem-label removeu" "$(_docker_calls_log)"; return 1 ;;
  esac
}

scenario_gc_state_dir_ausente_e_removido() {
  _make_bin_dir
  _stub_docker_gc "$_STUB_BIN"
  _gc_sd="$TMPDIR_TEST/nao-existe-mais/.claude/feature-00c-state/x"
  _gc_ps_line "cstk-mcp-state-gone" "$_gc_sd"
  capture _cstk_mcp gc
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "gc state-dir-ausente exit" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "action=removed name=cstk-mcp-state-gone reason=state-dir-ausente" || return 1
  assert_stdout_contains "removed:1" || return 1
  case "$(_docker_calls_log)" in
    *"rm -f cstk-mcp-state-gone"*) : ;;
    *) _fail "gc state-dir-ausente nao chamou docker rm" "$(_docker_calls_log)"; return 1 ;;
  esac
}

scenario_gc_execucao_terminal_concluida_e_removido() {
  _make_bin_dir
  _stub_docker_gc "$_STUB_BIN"
  _gc_sd="$TMPDIR_TEST/proj-term/.claude/feature-00c-state/x"
  mkdir -p "$_gc_sd"
  _init_active_exec "$_gc_sd"
  _mark_terminal "$_gc_sd" "concluida"
  _gc_ps_line "cstk-mcp-state-done" "$_gc_sd"
  capture _cstk_mcp gc
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "gc terminal exit" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "action=removed name=cstk-mcp-state-done reason=terminal:concluida" || return 1
  case "$(_docker_calls_log)" in
    *"rm -f cstk-mcp-state-done"*) : ;;
    *) _fail "gc terminal nao chamou docker rm" "$(_docker_calls_log)"; return 1 ;;
  esac
}

scenario_gc_execucao_terminal_abortada_e_removido() {
  _make_bin_dir
  _stub_docker_gc "$_STUB_BIN"
  _gc_sd="$TMPDIR_TEST/proj-abort/.claude/feature-00c-state/x"
  mkdir -p "$_gc_sd"
  _init_active_exec "$_gc_sd"
  _mark_terminal "$_gc_sd" "abortada"
  _gc_ps_line "cstk-mcp-state-aborted" "$_gc_sd"
  capture _cstk_mcp gc
  assert_stdout_contains "action=removed name=cstk-mcp-state-aborted reason=terminal:abortada" || return 1
}

scenario_gc_execucao_ativa_e_preservado_nunca_remove() {
  _make_bin_dir
  _stub_docker_gc "$_STUB_BIN"
  _gc_sd="$TMPDIR_TEST/proj-ativo/.claude/feature-00c-state/x"
  mkdir -p "$_gc_sd"
  _init_active_exec "$_gc_sd"
  _gc_ps_line "cstk-mcp-state-live" "$_gc_sd"
  capture _cstk_mcp gc
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "gc ativo exit" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "action=kept name=cstk-mcp-state-live reason=ativo:em_andamento" || return 1
  case "$(_docker_calls_log)" in
    *"rm -f cstk-mcp-state-live"*) _fail "gc ativo removeu execucao viva" "$(_docker_calls_log)"; return 1 ;;
  esac
}

scenario_gc_state_dir_existe_sem_estado_e_removido() {
  _make_bin_dir
  _stub_docker_gc "$_STUB_BIN"
  _gc_sd="$TMPDIR_TEST/proj-vazio/.claude/feature-00c-state/x"
  mkdir -p "$_gc_sd"
  _gc_ps_line "cstk-mcp-state-empty" "$_gc_sd"
  capture _cstk_mcp gc
  assert_stdout_contains "action=removed name=cstk-mcp-state-empty reason=state-dir-sem-estado" || return 1
}

scenario_gc_dry_run_reporta_sem_remover() {
  _make_bin_dir
  _stub_docker_gc "$_STUB_BIN"
  _gc_sd="$TMPDIR_TEST/proj-dry/.claude/feature-00c-state/x"
  mkdir -p "$_gc_sd"
  _init_active_exec "$_gc_sd"
  _mark_terminal "$_gc_sd" "concluida"
  _gc_ps_line "cstk-mcp-state-dryrun" "$_gc_sd"
  capture _cstk_mcp gc --dry-run
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "gc dry-run exit" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "action=would-remove name=cstk-mcp-state-dryrun reason=terminal:concluida" || return 1
  case "$(_docker_calls_log)" in
    *"rm -f cstk-mcp-state-dryrun"*) _fail "gc --dry-run chamou docker rm" "$(_docker_calls_log)"; return 1 ;;
  esac
}

scenario_gc_remocao_falha_reporta_remove_failed() {
  _make_bin_dir
  _stub_docker_gc "$_STUB_BIN"
  _gc_sd="$TMPDIR_TEST/proj-rmfail/.claude/feature-00c-state/x"
  mkdir -p "$_gc_sd"
  _init_active_exec "$_gc_sd"
  _mark_terminal "$_gc_sd" "concluida"
  _gc_ps_line "cstk-mcp-state-rmfail" "$_gc_sd"
  printf 'cstk-mcp-state-rmfail\n' >"$TMPDIR_TEST/docker-stub/rm-fails-for"
  capture _cstk_mcp gc
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "gc rm-fails exit" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "action=remove-failed name=cstk-mcp-state-rmfail" || return 1
  assert_stdout_contains "removed:0" || return 1
}

scenario_gc_remocao_ja_removido_idempotente() {
  _make_bin_dir
  _stub_docker_gc "$_STUB_BIN"
  _gc_sd="$TMPDIR_TEST/proj-rmnothing/.claude/feature-00c-state/x"
  mkdir -p "$_gc_sd"
  _init_active_exec "$_gc_sd"
  _mark_terminal "$_gc_sd" "concluida"
  _gc_ps_line "cstk-mcp-state-already-gone" "$_gc_sd"
  printf 'cstk-mcp-state-already-gone\n' >"$TMPDIR_TEST/docker-stub/rm-nothing-for"
  capture _cstk_mcp gc
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "gc rm-nothing exit" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "action=removed name=cstk-mcp-state-already-gone" || return 1
}

scenario_gc_multiplos_containers_summary_agrega() {
  _make_bin_dir
  _stub_docker_gc "$_STUB_BIN"
  _gc_sd_term="$TMPDIR_TEST/proj-multi-term/.claude/feature-00c-state/x"
  _gc_sd_ativo="$TMPDIR_TEST/proj-multi-ativo/.claude/feature-00c-state/x"
  mkdir -p "$_gc_sd_term" "$_gc_sd_ativo"
  _init_active_exec "$_gc_sd_term"
  _mark_terminal "$_gc_sd_term" "concluida"
  _init_active_exec "$_gc_sd_ativo"
  _gc_ps_line "cstk-mcp-state-t" "$_gc_sd_term"
  _gc_ps_line "cstk-mcp-state-a" "$_gc_sd_ativo"
  _gc_ps_line "cstk-mcp-state-nolabel" "-"
  capture _cstk_mcp gc
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "gc multi exit" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "summary=ok examined:3 removed:1 kept:1 skipped:1" || return 1
}

scenario_gc_flag_desconhecida_exit_2() {
  capture _cstk_mcp gc --bogus
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "gc flag desconhecida deveria ser exit 2" "exit=$_CAPTURED_EXIT"; return 1; }
}

scenario_mcp_sem_subcomando_mostra_gc_no_uso() {
  capture _cstk_mcp
  assert_stdout_contains "gc" || return 1
}

scenario_mcp_subcomando_desconhecido_lista_gc() {
  capture _cstk_mcp naoexiste
  assert_stderr_contains "status, start, stop, gc" || return 1
}

# ---------- install (FASE 6 task 6.1.4) ----------

scenario_install_dry_run_nao_escreve() {
  _ip="$TMPDIR_TEST/install-dry"
  mkdir -p "$_ip"
  capture _cstk_mcp install --project-path "$_ip" --dry-run
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "install dry-run exit" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "dry-run" || return 1
  if [ -f "$_ip/.mcp.json" ]; then
    _fail "install --dry-run nao deveria escrever .mcp.json" "arquivo existe"
    return 1
  fi
}

scenario_install_cria_mcp_json_com_cstk_state() {
  if ! command -v jq >/dev/null 2>&1; then
    return 0
  fi
  _ip="$TMPDIR_TEST/install-fresh"
  mkdir -p "$_ip"
  capture _cstk_mcp install --project-path "$_ip"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "install exit" "$_CAPTURED_STDERR"; return 1; }
  [ -f "$_ip/.mcp.json" ] || { _fail "install deveria criar .mcp.json" "ausente"; return 1; }
  _cmd=$(jq -r '.mcpServers["cstk-state"].command' "$_ip/.mcp.json")
  case "$_cmd" in
    */mcp-launch.sh) : ;;
    *) _fail "command deveria apontar para mcp-launch.sh" "$_cmd"; return 1 ;;
  esac
  _type=$(jq -r '.mcpServers["cstk-state"].type' "$_ip/.mcp.json")
  [ "$_type" = "stdio" ] || { _fail "type deveria ser stdio" "$_type"; return 1; }
}

scenario_install_idempotente_preserva_chaves_existentes() {
  if ! command -v jq >/dev/null 2>&1; then
    return 0
  fi
  _ip="$TMPDIR_TEST/install-idem"
  mkdir -p "$_ip"
  printf '{"mcpServers":{"outro-servidor":{"type":"stdio","command":"/bin/true","args":[]}}}\n' \
    >"$_ip/.mcp.json"
  capture _cstk_mcp install --project-path "$_ip"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "install idempotente exit 1a chamada" "$_CAPTURED_STDERR"; return 1; }
  capture _cstk_mcp install --project-path "$_ip"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "install idempotente exit 2a chamada" "$_CAPTURED_STDERR"; return 1; }
  # chave pre-existente de outro servidor MCP precisa sobreviver ao merge
  _outro=$(jq -r '.mcpServers["outro-servidor"].command' "$_ip/.mcp.json")
  [ "$_outro" = "/bin/true" ] || { _fail "merge nao deveria descartar outro-servidor" "$_outro"; return 1; }
  _cstk=$(jq -r '.mcpServers["cstk-state"].type' "$_ip/.mcp.json")
  [ "$_cstk" = "stdio" ] || { _fail "cstk-state deveria estar presente apos merge" "$_cstk"; return 1; }
}

scenario_install_recusa_home_exit_3() {
  capture _cstk_mcp install --project-path "$HOME"
  [ "$_CAPTURED_EXIT" = 3 ] || { _fail "install HOME exit" "esperado 3, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "HOME" || return 1
}

scenario_install_project_path_inexistente_exit_1() {
  capture _cstk_mcp install --project-path "$TMPDIR_TEST/nao-existe-install"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "install path inexistente exit" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
}

scenario_install_flag_desconhecida_exit_2() {
  capture _cstk_mcp install --bogus
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "install flag desconhecida exit" "esperado 2, obtido $_CAPTURED_EXIT"; return 1; }
}

scenario_mcp_uso_lista_install() {
  capture _cstk_mcp
  assert_stdout_contains "install" || return 1
}

scenario_mcp_subcomando_desconhecido_lista_install() {
  capture _cstk_mcp naoexiste
  assert_stderr_contains "install" || return 1
}

# ---------- _mcp_registration_status (feature cstk-setup, FASE 2.3, FR-016) ----------
#
# Funcao interna (nao subcomando `cstk mcp`), consumida pelo wizard
# `cstk setup`. Testada sourcing cli/lib/mcp.sh diretamente e chamando a
# funcao — mesmo motivo de nao existir `cstk mcp registration-status`
# (contracts/cli-setup.md §4.1: "lib DONA da area", nao um comando novo).
#
# INVARIANTES:
#   SEC-05 (CHK012): candidato via PATH restrito ao sufixo
#     /skills/agente-00c-runtime/scripts/mcp-launch.sh E existente em disco.
#   SEC-06 (CHK013): stdout NUNCA vazio; sem atribuicao textual => divergent
#     (nunca "configured" por omissao).

# _registration_status PROJECT_PATH -> stdout de _mcp_registration_status,
# rodando com CSTK_LIB=repo (mesmo contexto de _cstk_mcp install) e PATH
# controlavel via $_MCP_INNER_PATH (default: PATH corrente).
_registration_status() {
  env CSTK_LIB="$CSTK_LIB_DIR" PATH="${_MCP_INNER_PATH:-$PATH}" \
    sh -c '. "$CSTK_LIB/mcp.sh"; _mcp_registration_status "$1"' _ "$1"
}

scenario_mcp_not_configured_arquivo_ausente() {
  _p="$TMPDIR_TEST/reg-ausente"
  mkdir -p "$_p"
  capture _registration_status "$_p"
  [ "$_CAPTURED_STDOUT" = "not-configured" ] \
    || { _fail "stdout" "esperado 'not-configured', obtido '$_CAPTURED_STDOUT'"; return 1; }
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  return 0
}

scenario_mcp_not_configured_sem_cstk_state() {
  _p="$TMPDIR_TEST/reg-outro-servidor"
  mkdir -p "$_p"
  printf '{"mcpServers":{"outro-servidor":{"type":"stdio","command":"/bin/true","args":[]}}}\n' \
    > "$_p/.mcp.json"
  capture _registration_status "$_p"
  [ "$_CAPTURED_STDOUT" = "not-configured" ] \
    || { _fail "stdout" "esperado 'not-configured', obtido '$_CAPTURED_STDOUT'"; return 1; }
  return 0
}

scenario_mcp_configured_apos_install_real() {
  _p="$TMPDIR_TEST/reg-configured"
  mkdir -p "$_p"
  capture _cstk_mcp install --project-path "$_p"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "install exit" "$_CAPTURED_STDERR"; return 1; }
  capture _registration_status "$_p"
  [ "$_CAPTURED_STDOUT" = "configured" ] \
    || { _fail "stdout" "esperado 'configured', obtido '$_CAPTURED_STDOUT'"; return 1; }
  return 0
}

scenario_mcp_divergent_foreign_script() {
  _p="$TMPDIR_TEST/reg-divergent"
  mkdir -p "$_p"
  printf '{\n  "mcpServers": {\n    "cstk-state": {\n      "type": "stdio",\n      "command": "/usr/local/bin/outro-launcher.sh",\n      "args": []\n    }\n  }\n}\n' \
    > "$_p/.mcp.json"
  capture _registration_status "$_p"
  [ "$_CAPTURED_STDOUT" = "divergent" ] \
    || { _fail "stdout" "esperado 'divergent', obtido '$_CAPTURED_STDOUT'"; return 1; }
  return 0
}

# Cross-layer (quickstart Scenario 14b): .mcp.json com o "command" na forma
# HOME/catalogo instalado (candidato independente de CSTK_LIB), verificado
# num contexto com CSTK_LIB=repo — deve dar "configured", nunca "divergent"
# (evita falso-positivo entre camadas, contracts/cli-setup.md §4.1).
scenario_mcp_configured_cross_layer() {
  _p="$TMPDIR_TEST/reg-cross-layer"
  mkdir -p "$_p"
  _fake_home="$TMPDIR_TEST/reg-cross-layer-home"
  _catalog_launcher="$_fake_home/.claude/skills/agente-00c-runtime/scripts/mcp-launch.sh"
  mkdir -p "$(dirname "$_catalog_launcher")"
  printf '#!/bin/sh\nexit 0\n' > "$_catalog_launcher"
  chmod +x "$_catalog_launcher"
  printf '{\n  "mcpServers": {\n    "cstk-state": {\n      "type": "stdio",\n      "command": "%s",\n      "args": []\n    }\n  }\n}\n' \
    "$_catalog_launcher" > "$_p/.mcp.json"
  # Verifica com CSTK_LIB=repo (contexto DIFERENTE do HOME onde o
  # candidato "instalado" mora) + HOME apontando para o catalogo fake —
  # candidato 3 (home) e independente de CSTK_LIB, entao casa mesmo assim.
  capture env CSTK_LIB="$CSTK_LIB_DIR" HOME="$_fake_home" PATH="${_MCP_INNER_PATH:-$PATH}" \
    sh -c '. "$CSTK_LIB/mcp.sh"; _mcp_registration_status "$1"' _ "$_p"
  [ "$_CAPTURED_STDOUT" = "configured" ] \
    || { _fail "stdout" "esperado 'configured' (cross-layer), obtido '$_CAPTURED_STDOUT'"; return 1; }
  return 0
}

# SEC-06 (CHK013): cstk-state presente mas "command" nao atribuivel
# textualmente (bloco malformado, sem linha "command" apos "cstk-state")
# => "divergent", NUNCA stdout vazio, NUNCA "configured" por omissao.
scenario_mcp_registration_status_empty_stdout() {
  _p="$TMPDIR_TEST/reg-malformado"
  mkdir -p "$_p"
  printf '{\n  "mcpServers": {\n    "cstk-state": {\n      "type": "stdio"\n    }\n  }\n}\n' \
    > "$_p/.mcp.json"
  capture _registration_status "$_p"
  [ -n "$_CAPTURED_STDOUT" ] \
    || { _fail "stdout" "_mcp_registration_status NUNCA pode emitir stdout vazio (SEC-06)"; return 1; }
  [ "$_CAPTURED_STDOUT" = "divergent" ] \
    || { _fail "stdout" "esperado 'divergent' (nao-atribuivel), obtido '$_CAPTURED_STDOUT'"; return 1; }
  return 0
}

# SEC-05 (CHK012): candidato via PATH homonimo FORA do sufixo esperado
# NAO pode contar como legitimo, mesmo apontando para um arquivo real.
scenario_mcp_path_candidate_fora_do_sufixo_nao_conta() {
  _p="$TMPDIR_TEST/reg-path-homonimo"
  mkdir -p "$_p"
  _fake_bin="$TMPDIR_TEST/reg-path-homonimo-bin"
  mkdir -p "$_fake_bin"
  printf '#!/bin/sh\nexit 0\n' > "$_fake_bin/mcp-launch.sh"
  chmod +x "$_fake_bin/mcp-launch.sh"
  printf '{\n  "mcpServers": {\n    "cstk-state": {\n      "type": "stdio",\n      "command": "%s",\n      "args": []\n    }\n  }\n}\n' \
    "$_fake_bin/mcp-launch.sh" > "$_p/.mcp.json"
  # Homonimo na FRENTE do PATH real (command -v acha ele primeiro); o
  # sufixo de path esperado nao bate, entao SEC-05 deve rejeita-lo mesmo
  # apontando para um arquivo que de fato existe em disco.
  capture env CSTK_LIB="$CSTK_LIB_DIR" HOME="$TMPDIR_TEST/reg-path-homonimo-home" \
    PATH="$_fake_bin:$PATH" \
    sh -c '. "$CSTK_LIB/mcp.sh"; _mcp_registration_status "$1"' _ "$_p"
  [ "$_CAPTURED_STDOUT" = "divergent" ] \
    || { _fail "stdout" "candidato PATH fora do sufixo nao pode contar (SEC-05), obtido '$_CAPTURED_STDOUT'"; return 1; }
  return 0
}

run_all_scenarios
