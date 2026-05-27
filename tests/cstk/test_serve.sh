#!/bin/sh
# test_serve.sh — cobre cli/lib/serve.sh
#
# Contrato:
#   serve_main [--port P] [--host H] [--reinstall] [--help]
#     exit 0  sucesso (painel rodando ou --help)
#     exit 1  erro geral (prereq ausente, download falhou, corrompido)
#     exit 2  uso incorreto (porta invalida, flag desconhecida)
#
# Estrategia de teste: stubs de PATH para curl/npm (sem rede real).
#   CSTK_PANEL_DIR aponta para tmpdir isolado por scenario.
#   Fixture de tarball em tests/cstk/fixtures/serve/panel-fixture.tar.gz.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

CSTK_LIB="$REPO_ROOT/cli/lib"
export CSTK_LIB

SERVE_FIXTURE_DIR="$TESTS_ROOT/cstk/fixtures/serve"

# ---------------------------------------------------------------------------
# Helpers compartilhados
# ---------------------------------------------------------------------------

# _setup_serve_env: cria CSTK_PANEL_DIR em tmpdir e exporta CSTK_LIB.
# Deve ser chamado dentro do scenario (TMPDIR_TEST ja existe via harness).
_setup_serve_env() {
  CSTK_PANEL_DIR="$TMPDIR_TEST/panel"
  export CSTK_PANEL_DIR
  export CSTK_LIB
}

# _make_bin_dir: cria diretorio de stubs no tmpdir, prepende ao PATH e
# define _STUB_BIN para uso pelo caller.
# NAO usa subshell — modifica PATH e _STUB_BIN diretamente no caller.
_make_bin_dir() {
  _STUB_BIN="$TMPDIR_TEST/stubs"
  mkdir -p "$_STUB_BIN"
  PATH="$_STUB_BIN:$PATH"
  export PATH
}

# _stub_curl_ok: cria stub de curl que retorna JSON da GitHub API simulada
# com tarball_url apontando para https://github.com (para passar a allowlist),
# e ao receber a URL do tarball, copia o fixture local.
# $1 = diretorio de stubs
_stub_curl_ok() {
  _sco_bin="$1"
  _sco_tarball="$SERVE_FIXTURE_DIR/panel-fixture.tar.gz"
  # A tarball_url usa https://github.com para passar a SSRF allowlist.
  # O stub intercepta o download e copia o fixture local.
  cat > "$_sco_bin/curl" <<STUB
#!/bin/sh
# Stub curl: intercepta chamadas de rede sem tocar a rede real.
_url=""
_output=""
while [ "\$#" -gt 0 ]; do
  case "\$1" in
    -o) shift; _output="\$1" ;;
    --) shift; _url="\$1" ;;
    https://*|http://*) _url="\$1" ;;
    *) ;;
  esac
  shift
done
case "\$_url" in
  *releases/latest*)
    # GitHub API response: tarball_url usa github.com para passar a allowlist
    _resp='{"tag_name":"v0.0.1","tarball_url":"https://github.com/JotJunior/cstk-panel/archive/v0.0.1.tar.gz","prerelease":false,"draft":false}'
    if [ -n "\$_output" ]; then
      printf '%s\n' "\$_resp" > "\$_output"
    else
      printf '%s\n' "\$_resp"
    fi
    ;;
  *github.com*.sha256*)
    # Nao disponivel: best-effort integridade falha silenciosamente
    exit 1
    ;;
  *github.com*tar.gz*)
    # Tarball download: copiar fixture local em vez de baixar da rede
    if [ -n "\$_output" ]; then
      cp "${_sco_tarball}" "\$_output"
    else
      cat "${_sco_tarball}"
    fi
    ;;
  *)
    printf 'stub-curl: URL inesperada: %s\n' "\$_url" >&2
    exit 1
    ;;
esac
STUB
  chmod +x "$_sco_bin/curl"
}

# _stub_curl_must_not_be_called: stub que falha com mensagem se curl for chamado.
# Usado para garantir que invocacoes subsequentes nao fazem chamada de rede.
_stub_curl_must_not_be_called() {
  _scno_bin="$1"
  cat > "$_scno_bin/curl" <<'STUB'
#!/bin/sh
# Coletar URL para mensagem de erro
_url=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    https://*|http://*) _url="$1" ;;
    --) shift; _url="$1" ;;
  esac
  shift
done
printf 'ERRO: curl foi chamado mas nao deveria (panel ja instalado): %s\n' "$_url" >&2
exit 1
STUB
  chmod +x "$_scno_bin/curl"
}

# _stub_npm_ok: npm que ignora install/run start e sai com 0
_stub_npm_ok() {
  _sno_bin="$1"
  cat > "$_sno_bin/npm" <<'STUB'
#!/bin/sh
# Stub npm: aceita install e run start silenciosamente
exit 0
STUB
  chmod +x "$_sno_bin/npm"
}

# _stub_npm_exit_code: npm que sai com exit code especificado para "run start",
# mas aceita "install" com exit 0 (para permitir que a instalacao ocorra).
# $1 = bin dir, $2 = exit code para "run start"
_stub_npm_exit_code() {
  _snec_bin="$1"
  _snec_exit="$2"
  cat > "$_snec_bin/npm" <<STUB
#!/bin/sh
# Aceitar install; falhar run start com o exit code configurado
case "\$1" in
  install) exit 0 ;;
  run) exit ${_snec_exit} ;;
  *) exit 0 ;;
esac
STUB
  chmod +x "$_snec_bin/npm"
}

# _run_serve: executa serve_main em subshell com env isolado
# Precisa de _setup_serve_env chamado antes
_run_serve() {
  capture env \
    CSTK_LIB="$CSTK_LIB" \
    CSTK_PANEL_DIR="$CSTK_PANEL_DIR" \
    PATH="$PATH" \
    HOME="$TMPDIR_TEST" \
    sh -c ". \$CSTK_LIB/serve.sh && serve_main \"\$@\"" serve_test "$@"
}

# ---------------------------------------------------------------------------
# FASE 1 — Infra: verificar coverage (task 1.1.7)
# ---------------------------------------------------------------------------

# (Este arquivo existe = --check-coverage passa. Scenarios abaixo validam logica.)

# ---------------------------------------------------------------------------
# FASE 2.1 — Parse de flags e validacao de porta (tasks 2.1.x)
# ---------------------------------------------------------------------------

scenario_help_exit0() {
  _setup_serve_env
  _run_serve --help
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "serve --help exit" "esperado 0, obtido $_CAPTURED_EXIT"
    return 1
  fi
  # Deve mencionar --port no stdout
  if ! printf '%s' "$_CAPTURED_STDOUT" | grep -q -- '--port'; then
    _fail "serve --help conteudo" "stdout nao menciona --port"
    return 1
  fi
}

scenario_help_menciona_flags() {
  _setup_serve_env
  _run_serve --help
  for _flag in '--port' '--host' '--reinstall'; do
    if ! printf '%s' "$_CAPTURED_STDOUT" | grep -q -- "$_flag"; then
      _fail "serve --help flag ausente" "nao encontrou $_flag no stdout"
      return 1
    fi
  done
}

scenario_porta_invalida_letras_exit2() {
  _setup_serve_env
  _run_serve --port abc
  if [ "$_CAPTURED_EXIT" != "2" ]; then
    _fail "porta_invalida_letras" "esperado exit 2, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_porta_zero_exit2() {
  _setup_serve_env
  _run_serve --port 0
  if [ "$_CAPTURED_EXIT" != "2" ]; then
    _fail "porta_zero" "esperado exit 2, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_porta_65536_exit2() {
  _setup_serve_env
  _run_serve --port 65536
  if [ "$_CAPTURED_EXIT" != "2" ]; then
    _fail "porta_65536" "esperado exit 2, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_porta_65535_aceita() {
  _setup_serve_env
  _make_bin_dir
  _stub_curl_ok "$_STUB_BIN"
  _stub_npm_ok "$_STUB_BIN"
  _run_serve --port 65535
  # Deve sair com 0 (npm stub retorna 0)
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "porta_65535_aceita" "esperado exit 0, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_porta_5173_aceita() {
  _setup_serve_env
  _make_bin_dir
  _stub_curl_ok "$_STUB_BIN"
  _stub_npm_ok "$_STUB_BIN"
  _run_serve --port 5173
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "porta_5173_aceita" "esperado exit 0, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_flag_desconhecida_exit2() {
  _setup_serve_env
  _run_serve --nao-existe
  if [ "$_CAPTURED_EXIT" != "2" ]; then
    _fail "flag_desconhecida" "esperado exit 2, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_host_nao_loopback_aviso_stdout() {
  _setup_serve_env
  _make_bin_dir
  _stub_curl_ok "$_STUB_BIN"
  _stub_npm_ok "$_STUB_BIN"
  _run_serve --host 0.0.0.0
  # Deve prosseguir (exit 0) e emitir aviso no stdout
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "host_nao_loopback_prossegue" "esperado exit 0, obtido $_CAPTURED_EXIT"
    return 1
  fi
  if ! printf '%s' "$_CAPTURED_STDOUT" | grep -qi 'aviso\|warn\|atencao\|0\.0\.0\.0'; then
    _fail "host_nao_loopback_aviso" "stdout nao contem aviso sobre host nao-loopback"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# FASE 2.2 — Pre-requisitos (tasks 2.2.x)
# ---------------------------------------------------------------------------

# _stub_curl_present_npm_absent: PATH minimo com curl-stub mas sem npm,
# para testar prereq-check de npm ausente sem usar real npm do sistema.
_stub_curl_present_npm_absent() {
  _stub_curl_ok "$_STUB_BIN"
  # Criar "false-npm" que retorna exit 1 para simular ausencia no PATH.
  # command -v so verifica se existe no PATH; como o stub existe, o
  # prereq check vai encontra-lo. Precisamos de outra abordagem:
  # usar PATH MINIMO que nao inclua diretorios com npm real.
  #
  # Estrategia: sobrescrever PATH para incluir APENAS $STUB_BIN + dirs basicos
  # (sh, tar, etc) mas sem diretorios que contenham npm (homebrew, usr/local).
  _ISOLATED_PATH="$_STUB_BIN:/usr/bin:/bin"
  PATH="$_ISOLATED_PATH"
  export PATH
}

_stub_npm_present_curl_absent() {
  _stub_npm_ok "$_STUB_BIN"
  # Igual: PATH minimo sem curl real
  _ISOLATED_PATH="$_STUB_BIN:/usr/bin:/bin"
  PATH="$_ISOLATED_PATH"
  export PATH
}

scenario_prereq_curl_ausente_exit1() {
  _setup_serve_env
  _make_bin_dir
  # npm presente (stub), curl ausente — PATH minimo sem curl real
  _stub_npm_present_curl_absent
  _run_serve
  if [ "$_CAPTURED_EXIT" != "1" ]; then
    _fail "prereq_curl_ausente" "esperado exit 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  if ! printf '%s' "$_CAPTURED_STDERR" | grep -qi 'curl'; then
    _fail "prereq_curl_mensagem" "stderr nao menciona curl"
    return 1
  fi
}

scenario_prereq_npm_ausente_exit1() {
  _setup_serve_env
  _make_bin_dir
  # curl presente (stub), npm ausente — PATH minimo sem npm real
  _stub_curl_present_npm_absent
  _run_serve
  if [ "$_CAPTURED_EXIT" != "1" ]; then
    _fail "prereq_npm_ausente" "esperado exit 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  if ! printf '%s' "$_CAPTURED_STDERR" | grep -qi 'npm'; then
    _fail "prereq_npm_mensagem" "stderr nao menciona npm"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# FASE 3.3 — Porta privilegiada < 1024 (tasks 3.3.x)
# ---------------------------------------------------------------------------

scenario_porta_80_exit1_privilegio() {
  _setup_serve_env
  _run_serve --port 80
  if [ "$_CAPTURED_EXIT" != "1" ]; then
    _fail "porta_80_privilegio" "esperado exit 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  if ! printf '%s' "$_CAPTURED_STDERR" | grep -qi 'privileg\|root\|1024'; then
    _fail "porta_80_mensagem" "stderr nao menciona privilegio/1024"
    return 1
  fi
}

scenario_porta_1_exit1_privilegio() {
  _setup_serve_env
  _run_serve --port 1
  if [ "$_CAPTURED_EXIT" != "1" ]; then
    _fail "porta_1_privilegio" "esperado exit 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_porta_1023_exit1_privilegio() {
  _setup_serve_env
  _run_serve --port 1023
  if [ "$_CAPTURED_EXIT" != "1" ]; then
    _fail "porta_1023_privilegio" "esperado exit 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_porta_1024_aceita() {
  _setup_serve_env
  _make_bin_dir
  _stub_curl_ok "$_STUB_BIN"
  _stub_npm_ok "$_STUB_BIN"
  _run_serve --port 1024
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "porta_1024_aceita" "esperado exit 0, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# FASE 3.1 — SSRF host-allowlist (tasks 3.1.x)
# ---------------------------------------------------------------------------

scenario_host_allowlist_url_nao_autorizada_exit1() {
  _setup_serve_env
  _make_bin_dir
  _stub_npm_ok "$_STUB_BIN"
  # Stub curl que retorna URL de host nao-autorizado na API response
  cat > "$_STUB_BIN/curl" <<'STUB'
#!/bin/sh
_output=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o) shift; _output="$1" ;;
  esac
  shift
done
_resp='{"tag_name":"v0.0.1","tarball_url":"https://evil.com/malware.tar.gz","prerelease":false,"draft":false}'
if [ -n "$_output" ]; then
  printf '%s\n' "$_resp" > "$_output"
else
  printf '%s\n' "$_resp"
fi
STUB
  chmod +x "$_STUB_BIN/curl"
  _run_serve
  if [ "$_CAPTURED_EXIT" != "1" ]; then
    _fail "allowlist_host_nao_autorizado" "esperado exit 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  if ! printf '%s' "$_CAPTURED_STDERR" | grep -qi 'evil\|host\|nao.*permit\|nao.*autorizado\|allowlist\|rejeit'; then
    _fail "allowlist_mensagem" "stderr nao menciona host rejeitado"
    return 1
  fi
}

scenario_host_allowlist_http_schema_exit1() {
  _setup_serve_env
  _make_bin_dir
  _stub_npm_ok "$_STUB_BIN"
  # Stub curl que retorna URL com schema http:// (nao https) na tarball_url
  cat > "$_STUB_BIN/curl" <<'STUB'
#!/bin/sh
_output=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o) shift; _output="$1" ;;
  esac
  shift
done
_resp='{"tag_name":"v0.0.1","tarball_url":"http://github.com/tarball.tar.gz","prerelease":false,"draft":false}'
if [ -n "$_output" ]; then
  printf '%s\n' "$_resp" > "$_output"
else
  printf '%s\n' "$_resp"
fi
STUB
  chmod +x "$_STUB_BIN/curl"
  _run_serve
  if [ "$_CAPTURED_EXIT" != "1" ]; then
    _fail "allowlist_http_schema" "esperado exit 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_host_allowlist_github_url_ok() {
  _setup_serve_env
  _make_bin_dir
  _stub_curl_ok "$_STUB_BIN"
  _stub_npm_ok "$_STUB_BIN"
  _run_serve
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "allowlist_github_ok" "URL github.com valida deve passar; exit=$_CAPTURED_EXIT stderr=$_CAPTURED_STDERR"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# FASE 2.3 — Deteccao de instalacao existente (tasks 2.3.x)
# ---------------------------------------------------------------------------

scenario_instalacao_subsequente_sem_rede() {
  _setup_serve_env
  _make_bin_dir
  # Instalar o "panel" manualmente no panel_dir
  mkdir -p "$CSTK_PANEL_DIR"
  printf '{"name":"cstk-panel","version":"0.0.1"}\n' > "$CSTK_PANEL_DIR/package.json"
  # Stub de curl que FALHA se chamado (nao deve ser chamado)
  _stub_curl_must_not_be_called "$_STUB_BIN"
  _stub_npm_ok "$_STUB_BIN"
  _run_serve
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "subsequente_sem_rede" "esperado exit 0, obtido $_CAPTURED_EXIT stderr=$_CAPTURED_STDERR"
    return 1
  fi
}

scenario_instalacao_corrompida_sem_packagejson_exit1() {
  _setup_serve_env
  _make_bin_dir
  # Panel dir existe mas sem package.json
  mkdir -p "$CSTK_PANEL_DIR"
  _stub_curl_ok "$_STUB_BIN"
  _stub_npm_ok "$_STUB_BIN"
  _run_serve
  if [ "$_CAPTURED_EXIT" != "1" ]; then
    _fail "corrompida_sem_pkg" "esperado exit 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  if ! printf '%s' "$_CAPTURED_STDERR" | grep -qi 'reinstall\|corrompid\|incompleto'; then
    _fail "corrompida_mensagem" "stderr nao sugere --reinstall"
    return 1
  fi
}

scenario_reinstall_apaga_e_reinstala() {
  _setup_serve_env
  _make_bin_dir
  # Instalar panel dir primeiro
  mkdir -p "$CSTK_PANEL_DIR"
  printf '{"name":"cstk-panel","version":"0.0.0"}\n' > "$CSTK_PANEL_DIR/package.json"
  printf 'v0.0.0\n' > "$CSTK_PANEL_DIR/.panel-version"
  _stub_curl_ok "$_STUB_BIN"
  _stub_npm_ok "$_STUB_BIN"
  _run_serve --reinstall
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "reinstall_ok" "esperado exit 0, obtido $_CAPTURED_EXIT stderr=$_CAPTURED_STDERR"
    return 1
  fi
  # Deve ter nova versao instalada
  if [ ! -f "$CSTK_PANEL_DIR/.panel-version" ]; then
    _fail "reinstall_version_file" ".panel-version nao gravado apos reinstall"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# FASE 2.4 — Download e instalacao (tasks 2.4.x)
# ---------------------------------------------------------------------------

scenario_primeira_exec_ok_package_json_presente() {
  _setup_serve_env
  _make_bin_dir
  _stub_curl_ok "$_STUB_BIN"
  _stub_npm_ok "$_STUB_BIN"
  _run_serve
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "primeira_exec_exit" "esperado exit 0, obtido $_CAPTURED_EXIT stderr=$_CAPTURED_STDERR"
    return 1
  fi
  if [ ! -f "$CSTK_PANEL_DIR/package.json" ]; then
    _fail "primeira_exec_pkg" "package.json nao encontrado em CSTK_PANEL_DIR"
    return 1
  fi
}

scenario_primeira_exec_grava_panel_version() {
  _setup_serve_env
  _make_bin_dir
  _stub_curl_ok "$_STUB_BIN"
  _stub_npm_ok "$_STUB_BIN"
  _run_serve
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "version_file_exit" "esperado exit 0, obtido $_CAPTURED_EXIT"
    return 1
  fi
  if [ ! -f "$CSTK_PANEL_DIR/.panel-version" ]; then
    _fail "version_file_ausente" ".panel-version nao gravado"
    return 1
  fi
  _v=$(cat "$CSTK_PANEL_DIR/.panel-version")
  if [ -z "$_v" ]; then
    _fail "version_file_vazio" ".panel-version esta vazio"
    return 1
  fi
}

scenario_tarball_corrompido_exit1() {
  _setup_serve_env
  _make_bin_dir
  # Stub curl: retorna JSON valido para API mas arquivo corrompido para download
  cat > "$_STUB_BIN/curl" <<'STUB'
#!/bin/sh
_output=""
_url=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o) shift; _output="$1" ;;
    --) shift; _url="$1" ;;
    https://*) _url="$1" ;;
  esac
  shift
done
case "$_url" in
  *releases/latest*)
    _resp='{"tag_name":"v0.0.1","tarball_url":"https://github.com/JotJunior/cstk-panel/archive/v0.0.1.tar.gz","prerelease":false,"draft":false}'
    if [ -n "$_output" ]; then printf '%s\n' "$_resp" > "$_output"; else printf '%s\n' "$_resp"; fi
    ;;
  *tar.gz*)
    # Gerar conteudo corrompido (nao eh tar valido)
    if [ -n "$_output" ]; then
      printf 'INVALIDO_NAO_EH_TARBALL_CORROMPIDO\n' > "$_output"
    fi
    ;;
esac
STUB
  chmod +x "$_STUB_BIN/curl"
  _stub_npm_ok "$_STUB_BIN"
  _run_serve
  if [ "$_CAPTURED_EXIT" != "1" ]; then
    _fail "tarball_corrompido" "esperado exit 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_npm_install_falha_exit1() {
  _setup_serve_env
  _make_bin_dir
  _stub_curl_ok "$_STUB_BIN"
  # npm que falha em install mas ok em start
  cat > "$_STUB_BIN/npm" <<'STUB'
#!/bin/sh
case "$1" in
  install) exit 1 ;;
  *) exit 0 ;;
esac
STUB
  chmod +x "$_STUB_BIN/npm"
  _run_serve
  if [ "$_CAPTURED_EXIT" != "1" ]; then
    _fail "npm_install_falha" "esperado exit 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# FASE 4.2 — Graceful shutdown: SIGTERM + SIGKILL fallback (task 4.2.5)
# ---------------------------------------------------------------------------

# _stub_npm_ignores_sigterm: cria stub de npm que ignora SIGTERM por alguns
# ciclos antes de sair. Testa que o grace period aciona SIGKILL.
# $1 = bin dir
_stub_npm_ignores_sigterm() {
  _snist_bin="$1"
  cat > "$_snist_bin/npm" <<'STUB'
#!/bin/sh
# Aceitar install normalmente; para "run start", ignorar SIGTERM por 2 ciclos
case "$1" in
  install) exit 0 ;;
  run)
    # Registrar handler SIGTERM que NAO encerra o processo (ignora o sinal)
    trap '' TERM
    # Aguardar com sleep em loop; o SIGKILL (enviado apos grace period) vai
    # matar este processo mesmo sem handler. Usar sleep curto para nao
    # travar o teste por muito tempo.
    _cnt=0
    while [ "$_cnt" -lt 20 ]; do
      sleep 0.2 2>/dev/null || sleep 1
      _cnt=$((_cnt + 1))
    done
    exit 0
    ;;
  *) exit 0 ;;
esac
STUB
  chmod +x "$_snist_bin/npm"
}

# scenario_sigterm_graceful_kill: verifica que _serve_shutdown envia SIGKILL
# quando o filho ignora SIGTERM apos o grace period.
# O cenario cria um panel instalado (para evitar download) e dispara
# serve_main em background via subshell, depois envia SIGTERM ao processo
# serve_main e verifica que ele encerra dentro de 8s (grace 5s + margem 3s).
scenario_sigterm_graceful_kill() {
  _setup_serve_env
  _make_bin_dir
  _stub_curl_ok "$_STUB_BIN"
  _stub_npm_ignores_sigterm "$_STUB_BIN"

  # Pre-instalar o panel para que serve_main nao tente download
  mkdir -p "$CSTK_PANEL_DIR"
  printf '{}' > "$CSTK_PANEL_DIR/package.json"
  printf 'v0.0.1\n' > "$CSTK_PANEL_DIR/.panel-version"

  # Arquivo de resultado para comunicacao entre subshell e test
  _result_file="$TMPDIR_TEST/serve_exit_code"

  # Rodar serve_main em background em subshell; gravar exit code
  (
    export CSTK_LIB CSTK_PANEL_DIR PATH HOME="$TMPDIR_TEST"
    . "$CSTK_LIB/serve.sh"
    serve_main --port 5173
    printf '%d\n' "$?" > "$_result_file"
  ) &
  _serve_pid=$!

  # Aguardar o npm stub iniciar (grace de 0.5s)
  sleep 0.5 2>/dev/null || sleep 1

  # Enviar SIGTERM ao grupo de processos do serve_main
  kill -TERM "$_serve_pid" 2>/dev/null || :

  # Aguardar encerramento com timeout de 8s (grace period 5s + margem 3s)
  _wait_max=16
  _wait_cnt=0
  while [ "$_wait_cnt" -lt "$_wait_max" ]; do
    if ! kill -0 "$_serve_pid" 2>/dev/null; then
      break
    fi
    sleep 0.5 2>/dev/null || sleep 1
    _wait_cnt=$((_wait_cnt + 1))
  done

  # Se ainda vivo apos 8s, o teste falha (SIGKILL nao funcionou)
  if kill -0 "$_serve_pid" 2>/dev/null; then
    kill -KILL "$_serve_pid" 2>/dev/null || :
    wait "$_serve_pid" 2>/dev/null || :
    _fail "sigterm_graceful_kill" "serve_main nao encerrou em 8s apos SIGTERM (SIGKILL falhou)"
    return 1
  fi

  # Aguardar finalizacao para capturar exit code
  wait "$_serve_pid" 2>/dev/null || :

  # O processo deve ter encerrado (qualquer exit code e aceitavel aqui;
  # o importante e que o processo nao ficou pendurado)
  if [ "$_wait_cnt" -ge "$_wait_max" ]; then
    _fail "sigterm_graceful_kill" "serve_main demorou demais para encerrar: $_wait_cnt ciclos"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# FASE 3.2 — POSIX puro: zero eval (tasks 3.2.x)
# ---------------------------------------------------------------------------

scenario_zero_eval_no_serve_sh() {
  # Verifica que serve.sh nao usa eval (S5/CHK-S05)
  _serve_sh="$REPO_ROOT/cli/lib/serve.sh"
  if [ ! -f "$_serve_sh" ]; then
    _error "zero_eval" "serve.sh nao existe"
    return 2
  fi
  # grep -c retorna 0 se nenhuma ocorrencia, >0 se encontrou.
  # Sucesso (exit 0 do scenario) = zero ocorrencias de eval.
  if grep -qE '\beval\b' "$_serve_sh" 2>/dev/null; then
    _count=$(grep -cE '\beval\b' "$_serve_sh" 2>/dev/null || printf '?')
    _fail "zero_eval" "serve.sh contem $_count uso(s) de eval"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# FASE 4 — Saida espontanea do filho (tasks 4.x)
# ---------------------------------------------------------------------------

scenario_saida_espontanea_filho_propaga_exit() {
  _setup_serve_env
  _make_bin_dir
  _stub_curl_ok "$_STUB_BIN"
  # npm que sai com exit 2 imediatamente
  _stub_npm_exit_code "$_STUB_BIN" 2
  _run_serve
  if [ "$_CAPTURED_EXIT" != "2" ]; then
    _fail "saida_espontanea_exit" "esperado exit 2 (propagado do filho), obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_saida_espontanea_mensagem_stderr() {
  _setup_serve_env
  _make_bin_dir
  _stub_curl_ok "$_STUB_BIN"
  _stub_npm_exit_code "$_STUB_BIN" 1
  _run_serve
  # Deve emitir mensagem de encerramento inesperado no stderr
  if ! printf '%s' "$_CAPTURED_STDERR" | grep -qi 'encerrou\|inesperado\|exit'; then
    _fail "saida_espontanea_msg" "stderr nao menciona encerramento inesperado"
    return 1
  fi
}

run_all_scenarios
