#!/bin/sh
# test_serve-docker.sh — cobre cli/lib/serve-docker.sh (modo `cstk serve --docker`)
#
# Ref: docs/specs/panel-docker/tasks.md FASE 1 (1.1.4, 1.2.7, 1.3.5) + FASE 2
# (2.2-2.8 -- orquestracao completa de _serve_docker_main)
#
# FASE 1 (scaffold + geradores -- _serve_docker_write_dockerfile/
# _serve_docker_write_entrypoint/_serve_docker_image_tag/
# _serve_docker_build_image + confinamento de `docker` num unico arquivo,
# task 1.1.3): sourcing direto do lib, sem stub de rede (nenhuma funcao
# daquela FASE faz I/O), assercoes de CONTEUDO sobre os arquivos gerados
# (Dockerfile/entrypoint) em tmpdir isolado por scenario.
#
# FASE 2 (esta extensao -- 2.2 pre-flight, 2.3 reuso de instalacao
# verificada, 2.4 build/rebuild condicional, 2.5 `docker run` completo,
# 2.6 reconciliacao, 2.7 encerramento gracioso, 2.8 mensagens acionaveis):
# _serve_docker_main agora orquestra de verdade e depende de funcoes
# definidas em serve.sh (_serve_download_verify_extract/_serve_latest_tag/
# _serve_check_host_allowlist/_serve_write_integrity_log -- mesmo
# mecanismo de download/integridade do modo nativo, FR-007), entao os
# scenarios que exercitam _serve_docker_main sourceiam AMBOS os arquivos
# (_run_serve_docker_main, abaixo) -- mesma composicao que o dispatch real
# de serve_main faz. Continua tudo FAST e HERMETICO: um stub `docker`
# completo (subcomandos info/image/build/rmi/rm/run/wait/stop, logando
# cada invocacao) substitui o daemon real -- mesma filosofia de stub de
# tests/cstk/test_serve.sh (curl/npm), nunca rede ou runtime de container
# real. A validacao EMPIRICA com `docker build`/`docker run` reais
# (tasks 1.2.7/1.3.5) foi feita manualmente na wave da FASE 1 (ver Decisao
# registrada pelo orquestrador) -- este arquivo cobre a LOGICA de CLI
# (argv composto, branches de erro, precedencia de flags), nao builds
# reais (backlog task 4.1.1 planeja exatamente essa filosofia de stub).
#
# Scenarios de COMPOSICAO da flag --docker com o parser de serve_main
# (2.1 -- ex.: ausencia de --docker nunca toca `docker`, nem exige npm
# quando presente) vivem em tests/cstk/test_serve.sh (aquele arquivo ja
# cobre o parser/dispatch de serve.sh); este arquivo foca no que
# _serve_docker_main faz uma vez despachado.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

CSTK_LIB="$REPO_ROOT/cli/lib"
export CSTK_LIB

# ---------------------------------------------------------------------------
# Helpers compartilhados
# ---------------------------------------------------------------------------

# _run_serve_docker_fn FUNC [ARGS...]
# Roda FUNC (definida em serve-docker.sh) num subshell isolado (sh -c),
# capturando stdout/stderr/exit -- mesmo padrao de test_serve.sh::_run_serve,
# adaptado para chamar uma funcao interna especifica em vez de serve_main.
_run_serve_docker_fn() {
  capture env CSTK_LIB="$CSTK_LIB" HOME="$TMPDIR_TEST" \
    sh -c '. "$CSTK_LIB/serve-docker.sh" && "$@"' serve_docker_test "$@"
}

# _assert_captured_exit EXPECTED
# Compara $_CAPTURED_EXIT (de uma captura ja feita, ex. via
# _run_serve_docker_fn/capture) com EXPECTED. Diferente de assert_exit
# (harness.sh), que RE-EXECUTA um comando novo para capturar -- aqui so
# inspecionamos o estado JA capturado por uma chamada anterior. Mesmo
# padrao inline usado por tests/cstk/test_serve.sh::scenario_* (via
# `[ "$_CAPTURED_EXIT" != "N" ]`), extraido em helper para reduzir
# repeticao nos ~18 scenarios abaixo que reusam _run_serve_docker_fn.
_assert_captured_exit() {
  _ace_expected="$1"
  if [ "${_CAPTURED_EXIT:-}" != "$_ace_expected" ]; then
    _fail "assert_captured_exit" "esperado exit=$_ace_expected, obtido exit=${_CAPTURED_EXIT:-?}"
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Helpers FASE 2 — orquestracao completa de _serve_docker_main
# ---------------------------------------------------------------------------

SERVE_FIXTURE_DIR="$TESTS_ROOT/cstk/fixtures/serve"

# _make_bin_dir -- identico a test_serve.sh::_make_bin_dir (duplicado, ver
# nota acima): cria dir de stubs, prepende ao PATH do PROPRIO processo de
# teste (herdado por _run_serve_docker_main quando _SDM_INNER_PATH nao
# esta setada -- suficiente para a maioria dos scenarios, que so precisam
# que os stubs sejam encontrados ANTES de qualquer binario real).
_make_bin_dir() {
  _STUB_BIN="$TMPDIR_TEST/stubs"
  mkdir -p "$_STUB_BIN"
  PATH="$_STUB_BIN:$PATH"
  export PATH
}

# _isolated_sh_dir: identico a tests/cstk/test_serve.sh::_isolated_sh_dir
# (duplicado aqui por design -- cada arquivo test_*.sh e autocontido,
# so compartilha harness.sh). Dir com APENAS um symlink para o `sh` real,
# para compor um PATH interno minimo sem arrastar /usr/local/bin (onde
# `docker` de fato mora neste host -- CLAUDE.md "PATH-stub nao esconde
# binario de /usr/bin" vale identicamente para /usr/local/bin/docker).
_isolated_sh_dir() {
  _ish_dir="$TMPDIR_TEST/shbin"
  if [ ! -e "$_ish_dir/sh" ]; then
    mkdir -p "$_ish_dir"
    _ish_sh=$(command -v sh)
    ln -sf "$_ish_sh" "$_ish_dir/sh"
  fi
  printf '%s' "$_ish_dir"
}

# _serve_fixture_sha256 FILE -- identico a test_serve.sh (duplicado, ver
# nota acima). sha256 REAL do fixture, nunca hardcoded (Constitution VI).
_serve_fixture_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

# _stub_curl_ok BIN_DIR -- identico a test_serve.sh::_stub_curl_ok
# (duplicado, ver nota acima): caminho FELIZ, .sha256 confere (outcome
# verified). Usado pelos scenarios 2.3/2.4 que precisam completar o fetch
# para chegar em build/run.
_stub_curl_ok() {
  _sco_bin="$1"
  _sco_tarball="$SERVE_FIXTURE_DIR/panel-fixture.tar.gz"
  _sco_sha256=$(_serve_fixture_sha256 "$_sco_tarball")
  cat > "$_sco_bin/curl" <<STUB
#!/bin/sh
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
    _resp='{"tag_name":"v0.0.1","tarball_url":"https://github.com/JotJunior/cstk-panel/archive/v0.0.1.tar.gz","prerelease":false,"draft":false}'
    if [ -n "\$_output" ]; then printf '%s\n' "\$_resp" > "\$_output"; else printf '%s\n' "\$_resp"; fi
    ;;
  *github.com*.sha256*)
    if [ -n "\$_output" ]; then printf '%s  archive.tar.gz\n' "${_sco_sha256}" > "\$_output"; else printf '%s  archive.tar.gz\n' "${_sco_sha256}"; fi
    ;;
  *github.com*tar.gz*)
    if [ -n "\$_output" ]; then cp "${_sco_tarball}" "\$_output"; else cat "${_sco_tarball}"; fi
    ;;
  *)
    printf 'stub-curl: URL inesperada: %s\n' "\$_url" >&2
    exit 1
    ;;
esac
STUB
  chmod +x "$_sco_bin/curl"
}

# _stub_curl_no_sha256 BIN_DIR -- identico a test_serve.sh (duplicado):
# asset .sha256 indisponivel -> outcome unverifiable-blocked (default) ou
# unverifiable-bypassed (--allow-unverified). Usado pelo scenario 2.3.4
# de paridade de integridade no caminho --docker.
_stub_curl_no_sha256() {
  _scns_bin="$1"
  _scns_tarball="$SERVE_FIXTURE_DIR/panel-fixture.tar.gz"
  cat > "$_scns_bin/curl" <<STUB
#!/bin/sh
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
    _resp='{"tag_name":"v0.0.1","tarball_url":"https://github.com/JotJunior/cstk-panel/archive/v0.0.1.tar.gz","prerelease":false,"draft":false}'
    if [ -n "\$_output" ]; then printf '%s\n' "\$_resp" > "\$_output"; else printf '%s\n' "\$_resp"; fi
    ;;
  *github.com*.sha256*)
    exit 1
    ;;
  *github.com*tar.gz*)
    if [ -n "\$_output" ]; then cp "${_scns_tarball}" "\$_output"; else cat "${_scns_tarball}"; fi
    ;;
  *)
    printf 'stub-curl: URL inesperada: %s\n' "\$_url" >&2
    exit 1
    ;;
esac
STUB
  chmod +x "$_scns_bin/curl"
}

# _stub_docker BIN_DIR
# Cria um stub `docker` completo (subcomandos info/image inspect/build/
# rmi/rm/run/wait/stop) usado por TODOS os scenarios de orquestracao de
# _serve_docker_main. Loga CADA invocacao (argv completo, uma linha por
# chamada) em $TMPDIR_TEST/docker-calls.log -- e a partir desse log que os
# scenarios abaixo asserem o `docker run` exato (nome/label/porta/mount/
# hardening) e o `docker stop -t <grace>` do encerramento gracioso.
#
# Comportamento controlavel via arquivos-marcador em
# $TMPDIR_TEST/docker-stub/ (o scenario escreve ANTES de chamar
# _run_serve_docker_main -- mesmo espirito dos toggles _stub_npm_exit_code/
# _stub_curl_* de test_serve.sh, adaptado para uma orquestracao
# multi-chamada em vez de um unico comando):
#   docker-stub/daemon-down          presente => `docker info` falha
#   docker-stub/build-fails          presente => `docker build` falha
#   docker-stub/rm-fails             presente => `docker rm -f` falha
#                                     (permissao negada, NUNCA "no such
#                                     container" -- CHK003 caso irreconciliavel)
#   docker-stub/run-port-conflict    presente => `docker run` falha com
#                                     mensagem de porta ja em uso
#   docker-stub/run-fails            presente => `docker run` falha
#                                     generico (sem ser conflito de porta)
#   docker-stub/container-exit       conteudo = exit code que `docker
#                                     wait` deve reportar (default "0")
#   docker-stub/images/<tag-saneada> presenca simula imagem JA construida
#                                     (docker image inspect sucede) --
#                                     usar _mark_image_built para criar
#   docker-stub/container-running    presenca simula container remanescente
#                                     em execucao (docker rm -f "remove"
#                                     algo; ausencia simula "No such
#                                     container", idempotente) -- tambem
#                                     criado pelo proprio stub quando `run`
#                                     sucede (para o scenario de shutdown
#                                     detectar que o container "subiu")
#   docker-stub/container-long-running presenca faz `docker wait` BLOQUEAR
#                                     (poll) ate container-stopped aparecer
#                                     -- por padrao `wait` retorna IMEDIATO
#                                     (rapido para os demais scenarios).
#                                     Usar SOMENTE no teste de encerramento
#                                     gracioso (2.7).
_stub_docker() {
  _sdck_bin="$1"
  cat > "$_sdck_bin/docker" <<'STUB'
#!/bin/sh
_stub_dir="$TMPDIR_TEST/docker-stub"
mkdir -p "$_stub_dir/images"
printf '%s\n' "$*" >> "$TMPDIR_TEST/docker-calls.log"

_sanitize_tag() {
  printf '%s' "$1" | tr '/:' '__'
}

case "$1" in
  info)
    [ -f "$_stub_dir/daemon-down" ] && exit 1
    exit 0
    ;;
  image)
    if [ "$2" = "inspect" ]; then
      _tag=$(_sanitize_tag "$3")
      [ -f "$_stub_dir/images/$_tag" ] && exit 0
      exit 1
    fi
    exit 1
    ;;
  build)
    if [ -f "$_stub_dir/build-fails" ]; then
      printf 'stub-docker: build simulado falhou\n' >&2
      exit 1
    fi
    _prev=""
    for _arg in "$@"; do
      if [ "$_prev" = "-t" ]; then
        _tag=$(_sanitize_tag "$_arg")
        : > "$_stub_dir/images/$_tag"
      fi
      _prev="$_arg"
    done
    exit 0
    ;;
  rmi)
    _tag=$(_sanitize_tag "$3")
    rm -f "$_stub_dir/images/$_tag"
    exit 0
    ;;
  rm)
    if [ -f "$_stub_dir/rm-fails" ]; then
      printf 'Error: permission denied while trying to connect to the Docker daemon socket\n' >&2
      exit 1
    fi
    if [ -f "$_stub_dir/container-running" ]; then
      rm -f "$_stub_dir/container-running"
      exit 0
    fi
    printf 'Error: No such container: %s\n' "$3" >&2
    exit 1
    ;;
  run)
    if [ -f "$_stub_dir/run-port-conflict" ]; then
      printf 'docker: Error response from daemon: Ports are not available: listen tcp 0.0.0.0:5173: bind: address already in use.\n' >&2
      exit 1
    fi
    if [ -f "$_stub_dir/run-fails" ]; then
      printf 'docker: Error response from daemon: stub run simulado falhou\n' >&2
      exit 1
    fi
    : > "$_stub_dir/container-running"
    rm -f "$_stub_dir/container-stopped"
    printf 'fakecontainerid0123456789abcdef\n'
    exit 0
    ;;
  wait)
    # Por padrao retorna IMEDIATAMENTE (container "ja encerrou") -- rapido
    # para os scenarios que nao testam encerramento gracioso. So bloqueia
    # (poll ate container-stopped) quando o scenario cria
    # docker-stub/container-long-running ANTES de chamar
    # _serve_docker_main -- usado exclusivamente pelo teste de shutdown
    # (Ctrl+C simulado).
    if [ -f "$_stub_dir/container-long-running" ]; then
      _cnt=0
      while [ "$_cnt" -lt 100 ]; do
        if [ -f "$_stub_dir/container-stopped" ]; then
          break
        fi
        sleep 0.1 2>/dev/null || sleep 1
        _cnt=$((_cnt + 1))
      done
    fi
    if [ -f "$_stub_dir/container-exit" ]; then
      cat "$_stub_dir/container-exit"
    else
      printf '0\n'
    fi
    exit 0
    ;;
  stop)
    : > "$_stub_dir/container-stopped"
    rm -f "$_stub_dir/container-running"
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

# _mark_image_built TAG: simula uma imagem JA construida (docker image
# inspect TAG sucede) sem precisar rodar `docker build`.
_mark_image_built() {
  mkdir -p "$TMPDIR_TEST/docker-stub/images"
  _mib_tag=$(printf '%s' "$1" | tr '/:' '__')
  : > "$TMPDIR_TEST/docker-stub/images/$_mib_tag"
}

# _seed_cached_install PANEL_DIR TAG: popula o cache do modo alternativo
# (arvore-fonte + .panel-version) e marca a imagem correspondente como
# construida -- para scenarios que testam o caminho de REUSO (sem fetch/
# build), sem precisar stubar curl.
_seed_cached_install() {
  _sci_panel_dir="$1"
  _sci_tag="$2"
  _sci_src_dir="$(dirname -- "$_sci_panel_dir")/panel-docker-src"
  mkdir -p "$_sci_src_dir"
  printf '{}' > "$_sci_src_dir/package.json"
  printf '%s\n' "$_sci_tag" > "$_sci_src_dir/.panel-version"
  _mark_image_built "cstk-panel:${_sci_tag}"
}

# _docker_calls_log: imprime o conteudo de docker-calls.log (vazio se
# ausente -- nenhuma chamada ao stub ainda).
_docker_calls_log() {
  cat "$TMPDIR_TEST/docker-calls.log" 2>/dev/null || :
}

# _run_serve_docker_main PORT HOST UPDATE REINSTALL ALLOW_UNVERIFIED BYPASS_METHOD
# Executa _serve_docker_main em subshell isolado, sourceando AMBOS serve.sh
# + serve-docker.sh (a orquestracao real depende de funcoes definidas em
# serve.sh -- ver cabecalho do arquivo). PATH interno controlado via
# _SDM_INNER_PATH (default: PATH do harness, contendo os stubs +
# _isolated_sh_dir); CSTK_PANEL_DIR/CSTK_KNOWLEDGE_DB honram as variaveis
# ja exportadas pelo caller (mesmo padrao de _setup_serve_env/_run_serve
# em test_serve.sh).
_run_serve_docker_main() {
  capture env CSTK_LIB="$CSTK_LIB" HOME="$TMPDIR_TEST" \
    CSTK_PANEL_DIR="${CSTK_PANEL_DIR:-$TMPDIR_TEST/panel}" \
    CSTK_KNOWLEDGE_DB="${CSTK_KNOWLEDGE_DB:-}" \
    TMPDIR_TEST="$TMPDIR_TEST" \
    PATH="${_SDM_INNER_PATH:-$PATH}" \
    sh -c '. "$CSTK_LIB/serve.sh" && . "$CSTK_LIB/serve-docker.sh" && _serve_docker_main "$@"' serve_docker_main_test "$@"
}

# _assert_hardening_flags_in_run_line RUN_LINE LABEL
# Confere que RUN_LINE (uma linha 'run -d ...' ja capturada de
# _docker_calls_log) contem o conjunto INTEIRO de flags de hardening
# (research.md Decision 7; contracts/cli-docker-mode.md "Invariantes de
# seguranca"; checklists/security.md CHK006/CHK009). Extraido como helper
# compartilhado (tasks.md 3.1.3/3.1.5, CHK009 [Gap]) para que o MESMO
# conjunto seja verificado nos 3 gatilhos de (re)build (imagem ausente /
# --update rebuild / --reinstall) e no caminho de reuso sem rebuild —
# CHK009 exige que o hardening nao seja so "da primeira construcao". LABEL
# identifica o gatilho no nome da falha (mensagem acionavel de teste).
_assert_hardening_flags_in_run_line() {
  _ahf_line="$1"
  _ahf_label="$2"
  if [ -z "$_ahf_line" ]; then
    _fail "hardening_flags_${_ahf_label}" "nenhuma linha 'docker run -d' capturada para o gatilho $_ahf_label"
    return 1
  fi
  for _ahf_needle in \
    '--cap-drop ALL' \
    '--security-opt no-new-privileges' \
    '--read-only' \
    '--tmpfs /tmp:rw,noexec,nosuid,size=64m' \
  ; do
    case "$_ahf_line" in
      *"$_ahf_needle"*) : ;;
      *)
        _fail "hardening_flags_${_ahf_label}" "docker run ($_ahf_label) nao contem '$_ahf_needle': $_ahf_line"
        return 1
        ;;
    esac
  done
  return 0
}

# ---------------------------------------------------------------------------
# 1.1.1/1.1.2 — scaffold: lib sourceavel, interface de _serve_docker_main
# ---------------------------------------------------------------------------

scenario_lib_sources_cleanly_and_is_idempotent() {
  # NOTA: passar "sh -c '...'" como FUNC para _run_serve_docker_fn
  # dispararia um TERCEIRO shell aninhado (o "$@" da funcao ja e um "sh -c"
  # em si) -- esse shell aninhado nao herda as FUNCOES sourceadas pelo pai
  # (apenas env vars cruzam fork/exec), entao command -v sempre reportaria
  # NOTFOUND mesmo com a lib corretamente carregada. `command -v` sozinho
  # e um comando SIMPLES (sem subshell extra), entao pode ir direto.
  _run_serve_docker_fn command -v _serve_docker_main
  _assert_captured_exit 0 || return 1
  assert_stdout_contains "_serve_docker_main" || return 1
}

scenario_lib_guards_against_double_sourcing() {
  # Sourcing 2x no mesmo processo nao deve re-executar corpo/redefinir com
  # efeito colateral (mesmo padrao _SERVE_LOADED de serve.sh / _CSTK_*_LOADED
  # de trusted-hosts.sh) -- aqui validamos que a segunda carga nao falha.
  capture env CSTK_LIB="$CSTK_LIB" HOME="$TMPDIR_TEST" \
    sh -c '. "$CSTK_LIB/serve-docker.sh" && . "$CSTK_LIB/serve-docker.sh" && echo loaded-twice-ok'
  _assert_captured_exit 0 || return 1
  assert_stdout_contains "loaded-twice-ok" || return 1
}

scenario_interface_functions_all_defined() {
  # Logica multi-linha (for loop): NAO pode ir via _run_serve_docker_fn
  # (que ja envolve "$@" num "sh -c" -- passar OUTRO "sh -c" aninharia um
  # terceiro shell que perde as funcoes sourceadas, mesmo bug documentado
  # em scenario_lib_sources_cleanly_and_is_idempotent). Constroi o
  # capture diretamente, com o sourcing e o loop no MESMO script.
  capture env CSTK_LIB="$CSTK_LIB" HOME="$TMPDIR_TEST" sh -c '
    . "$CSTK_LIB/serve-docker.sh"
    for f in _serve_docker_main _serve_docker_image_tag \
             _serve_docker_write_dockerfile _serve_docker_write_entrypoint \
             _serve_docker_build_image; do
      command -v "$f" >/dev/null 2>&1 || { echo "MISSING:$f"; exit 1; }
    done
    echo all-defined
  '
  _assert_captured_exit 0 || return 1
  assert_stdout_contains "all-defined" || return 1
}

# _serve_docker_main deixou de ser esqueleto nesta FASE 2 (orquestracao
# completa abaixo, secao "FASE 2"). Este scenario cobre so a REGRESSAO de
# que a assinatura de 6 parametros continua sendo aceita/definida quando
# sourceada isoladamente (sem serve.sh) -- a orquestracao completa exige
# serve.sh (_run_serve_docker_main, testado extensivamente na secao FASE
# 2 abaixo).
scenario_main_function_is_defined_after_phase2_implementation() {
  _run_serve_docker_fn command -v _serve_docker_main
  _assert_captured_exit 0 || return 1
  assert_stdout_contains "_serve_docker_main" || return 1
}

# ---------------------------------------------------------------------------
# 1.1.3 — confinamento: "docker" so aparece em serve-docker.sh (carve-out
# Principio II condicao b), exceto (a) o parse da flag --docker em serve.sh
# e (b) o encaminhamento mecanico para serve-docker.sh (source + chamada de
# _serve_docker_main) que a flag decidida dispara — FASE 2. O cabecalho de
# serve-docker.sh documenta explicitamente que "o nome da flag em si nao
# conta como dependencia, so o encaminhamento para as funcoes daqui" —
# ambas exceções abaixo espelham essa frase; qualquer OUTRA mencao a
# "docker" em serve.sh (comentario, mensagem, etc.) continua proibida e
# cai fora dos 3 padroes exemptados.
# ---------------------------------------------------------------------------

scenario_docker_mentions_confined_to_serve_docker_lib() {
  # Escopo: cli/ (codigo do toolkit, onde o carve-out do Principio II se
  # aplica). global/ (skills/commands/agents), tests/, docs/, scripts/ e
  # CLAUDE.md/CHANGELOG.md ficam DE FORA de proposito -- mencionam "docker"
  # em prosa/testes sem violar o confinamento de DEPENDENCIA de codigo.
  _hits=$(grep -rniE 'docker' "$REPO_ROOT/cli" 2>/dev/null \
            | grep -v '/cli/lib/serve-docker\.sh:' \
            | grep -vE '/cli/lib/serve\.sh:[0-9]+: *-*-docker\)[[:space:]]*$' \
            | grep -vE '/cli/lib/serve\.sh:[0-9]+: *\. "\$\{CSTK_LIB\}/serve-docker\.sh"$' \
            | grep -vE '/cli/lib/serve\.sh:[0-9]+: *_serve_docker_main ' \
          || :)
  if [ -n "$_hits" ]; then
    _fail "docker_confinement" "mencoes a 'docker' fora de serve-docker.sh (ou dos 3 padroes exemptados do encaminhamento em serve.sh): $_hits"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# 1.2.6 — image_tag: local, deterministico (nunca registry remoto — FR-013)
# ---------------------------------------------------------------------------

scenario_image_tag_is_local_and_deterministic() {
  _run_serve_docker_fn _serve_docker_image_tag "v0.12.1"
  _assert_captured_exit 0 || return 1
  assert_stdout_contains "cstk-panel:v0.12.1" || return 1
  # FR-013: nunca aponta a um registry (sem "/" antes do nome, sem host:porta).
  case "$_CAPTURED_STDOUT" in
    */*) _fail "image_tag_no_registry" "tag nao deve conter '/' (indicaria registry remoto): $_CAPTURED_STDOUT"; return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# 1.2.1-1.2.6 — conteudo do Dockerfile gerado
# ---------------------------------------------------------------------------

scenario_dockerfile_pins_base_by_digest_not_floating_tag() {
  _out="$TMPDIR_TEST/Dockerfile"
  _run_serve_docker_fn _serve_docker_write_dockerfile "$_out"
  _assert_captured_exit 0 || return 1
  # Multi-stage alpine (dec-037): estagio de build fixado por digest + AS build.
  if ! grep -q '^FROM node:22-alpine@sha256:[0-9a-f]\{64\} AS build$' "$_out"; then
    _fail "dockerfile_digest_pin_build" "FROM do estagio de build nao fixa alpine por digest sha256 de 64 hex + AS build: $(grep '^FROM' "$_out")"
    return 1
  fi
  # Estagio de runtime fixado pela MESMA base alpine por digest (sem AS).
  if ! grep -q '^FROM node:22-alpine@sha256:[0-9a-f]\{64\}$' "$_out"; then
    _fail "dockerfile_digest_pin_runtime" "FROM do estagio de runtime nao fixa alpine por digest sha256 de 64 hex: $(grep '^FROM' "$_out")"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# 3.3 — npm ci fail-closed quando lockfile ausente (CHK014)
# ---------------------------------------------------------------------------

# _extract_npm_ci_guard_shell_cmd DOCKERFILE
# Extrai do Dockerfile GERADO (real, nao hand-copiado) a linha `RUN test -f
# package-lock.json || { ... }` sem o prefixo `RUN `, devolvendo um comando
# sh executavel isoladamente. Permite exercitar a MESMA logica que roda
# dentro do `docker build` sem precisar de daemon Docker (hermetico, task
# 3.3.3) -- zero risco de drift entre o que o teste afirma e o que o
# gerador realmente escreve, porque o comando vem do arquivo gerado, nao de
# uma copia mantida a mao no teste.
_extract_npm_ci_guard_shell_cmd() {
  grep '^RUN test -f package-lock\.json' "$1" | sed 's/^RUN //'
}

scenario_npm_ci_guard_precedes_npm_ci_in_dockerfile() {
  _out="$TMPDIR_TEST/Dockerfile"
  _run_serve_docker_fn _serve_docker_write_dockerfile "$_out"
  _assert_captured_exit 0 || return 1

  _guard_line_no=$(grep -n '^RUN test -f package-lock\.json' "$_out" | head -1 | cut -d: -f1)
  _npmci_line_no=$(grep -n '^RUN npm ci$' "$_out" | head -1 | cut -d: -f1)
  if [ -z "$_guard_line_no" ] || [ -z "$_npmci_line_no" ]; then
    _fail "npm_ci_guard_order_missing" "guard 'test -f package-lock.json' ou 'RUN npm ci' ausente no Dockerfile gerado"
    return 1
  fi
  if [ "$_guard_line_no" -ge "$_npmci_line_no" ]; then
    _fail "npm_ci_guard_order" "guard (linha $_guard_line_no) deve vir ANTES de 'RUN npm ci' (linha $_npmci_line_no) -- 3.3.2"
    return 1
  fi
}

scenario_npm_ci_guard_fails_closed_when_lockfile_absent() {
  _out="$TMPDIR_TEST/Dockerfile"
  _run_serve_docker_fn _serve_docker_write_dockerfile "$_out"
  _assert_captured_exit 0 || return 1

  _guard_cmd=$(_extract_npm_ci_guard_shell_cmd "$_out")
  if [ -z "$_guard_cmd" ]; then
    _fail "npm_ci_guard_missing" "Dockerfile gerado nao contem o guard fail-closed (task 3.3.2/CHK014)"
    return 1
  fi

  # Fixture de arvore extraida SEM package-lock.json (3.3.3): a MESMA linha
  # de shell do Dockerfile, executada de verdade contra um cwd sem o
  # lockfile, MUST falhar (exit != 0) com a mensagem acionavel -- nunca
  # degradar silenciosamente para npm install (nao ha npm install em
  # nenhum lugar deste comando; a falha e a UNICA saida possivel).
  _missing_dir="$TMPDIR_TEST/ctx-missing-lockfile"
  mkdir -p "$_missing_dir"
  _guard_out=$(cd "$_missing_dir" && sh -c "$_guard_cmd" 2>&1)
  _guard_exit=$?
  if [ "$_guard_exit" -eq 0 ]; then
    _fail "npm_ci_guard_should_fail" "guard nao falhou com lockfile ausente (exit 0): $_guard_out"
    return 1
  fi
  case "$_guard_out" in
    *"package-lock.json ausente"*"nunca degrada"*"npm install"*) : ;;
    *) _fail "npm_ci_guard_message" "mensagem do guard nao e a esperada/acionavel: $_guard_out"; return 1 ;;
  esac
}

scenario_npm_ci_guard_passes_through_when_lockfile_present() {
  _out="$TMPDIR_TEST/Dockerfile"
  _run_serve_docker_fn _serve_docker_write_dockerfile "$_out"
  _assert_captured_exit 0 || return 1

  _guard_cmd=$(_extract_npm_ci_guard_shell_cmd "$_out")
  if [ -z "$_guard_cmd" ]; then
    _fail "npm_ci_guard_missing" "Dockerfile gerado nao contem o guard fail-closed (task 3.3.2/CHK014)"
    return 1
  fi

  # Fixture de arvore extraida SAUDAVEL (lockfile presente): o guard MUST
  # sair 0 silenciosamente (sem stdout/stderr) e nunca bloquear o npm ci
  # real que viria a seguir no Dockerfile de verdade.
  _present_dir="$TMPDIR_TEST/ctx-with-lockfile"
  mkdir -p "$_present_dir"
  : > "$_present_dir/package-lock.json"
  _guard_out=$(cd "$_present_dir" && sh -c "$_guard_cmd" 2>&1)
  _guard_exit=$?
  if [ "$_guard_exit" -ne 0 ] || [ -n "$_guard_out" ]; then
    _fail "npm_ci_guard_should_passthrough" "guard nao deveria falhar/emitir saida com lockfile presente (exit=$_guard_exit saida=$_guard_out)"
    return 1
  fi
}

scenario_dockerfile_matches_contract_shape() {
  _out="$TMPDIR_TEST/Dockerfile"
  _run_serve_docker_fn _serve_docker_write_dockerfile "$_out"
  _assert_captured_exit 0 || return 1
  # Multi-stage alpine (dec-037): estagio de build compila better-sqlite3 p/
  # musl (toolchain apk) + workspaces; runtime slim copia --from=build e
  # instala so o socat do encaminhador. Ordem/presenca das linhas-chave.
  for _needle in \
    'FROM node:22-alpine@sha256:[0-9a-f]{64} AS build' \
    'RUN apk add --no-cache python3 make g\+\+' \
    'WORKDIR /app' \
    'COPY \. \.' \
    'RUN npm ci' \
    'RUN npm run build' \
    'RUN apk add --no-cache socat' \
    'COPY --from=build --chown=node:node /app /app' \
    'USER node' \
    'EXPOSE 8080' \
    'ENTRYPOINT \["/usr/local/bin/cstk-panel-entrypoint.sh"\]' \
  ; do
    if ! grep -qE -- "$_needle" "$_out"; then
      _fail "dockerfile_contract_shape" "Dockerfile nao contem padrao esperado: $_needle"
      return 1
    fi
  done
}

# 1.2.5: USER node MUST vir DEPOIS do `apk add socat` do runtime (que exige
# root) -- ordem importa, nao so presenca. (Multi-stage dec-037: o outro
# `apk add` — toolchain python3/make/g++ — vive no estagio de build, antes
# do FROM de runtime; o passo root-only que precede USER node e o do socat.)
scenario_dockerfile_user_node_after_root_only_steps() {
  _out="$TMPDIR_TEST/Dockerfile"
  _run_serve_docker_fn _serve_docker_write_dockerfile "$_out"
  _assert_captured_exit 0 || return 1
  _apk_line=$(grep -n 'apk add --no-cache socat' "$_out" | head -1 | cut -d: -f1)
  _user_line=$(grep -n '^USER node$' "$_out" | head -1 | cut -d: -f1)
  if [ -z "$_apk_line" ] || [ -z "$_user_line" ]; then
    _fail "dockerfile_user_order_missing" "nao encontrei as linhas apk-add-socat/USER node no Dockerfile gerado"
    return 1
  fi
  if [ "$_user_line" -le "$_apk_line" ]; then
    _fail "dockerfile_user_order" "USER node (linha $_user_line) deve vir DEPOIS do apk add socat (linha $_apk_line)"
    return 1
  fi
}

# research.md Decision 7 / FR-013: build estritamente local, nunca push.
scenario_dockerfile_never_contains_push() {
  _out="$TMPDIR_TEST/Dockerfile"
  _run_serve_docker_fn _serve_docker_write_dockerfile "$_out"
  _assert_captured_exit 0 || return 1
  if grep -qi 'docker push\|--network host\|--privileged' "$_out"; then
    _fail "dockerfile_no_push" "Dockerfile gerado NAO deve conter push/--network host/--privileged"
    return 1
  fi
}

# Regressao anti-mutacao: _serve_docker_write_dockerfile so escreve em
# DEST_PATH -- nao deve tocar o cwd nem criar lixo fora do tmpdir do
# scenario (assert_no_side_effect ja compara git status do repo).
scenario_write_dockerfile_has_no_side_effect_on_repo() {
  _out="$TMPDIR_TEST/Dockerfile"
  _run_serve_docker_fn _serve_docker_write_dockerfile "$_out"
  _assert_captured_exit 0 || return 1
  assert_no_side_effect || return 1
}

# ---------------------------------------------------------------------------
# 1.3.1/1.3.2 — conteudo do entrypoint gerado
# ---------------------------------------------------------------------------

scenario_entrypoint_matches_contract_shape() {
  _out="$TMPDIR_TEST/entrypoint.sh"
  _run_serve_docker_fn _serve_docker_write_entrypoint "$_out"
  _assert_captured_exit 0 || return 1
  for _needle in \
    '^#!/bin/sh$' \
    '^PORT=3001$' \
    '^export PORT$' \
    '^FORWARDER_PORT=8080$' \
    'node apps/server/dist/index\.js &' \
    'socat TCP-LISTEN:"\$FORWARDER_PORT",fork,reuseaddr TCP:127\.0\.0\.1:"\$PORT"' \
    "trap '_cstk_term_handler' TERM INT" \
  ; do
    if ! grep -qE -- "$_needle" "$_out"; then
      _fail "entrypoint_contract_shape" "entrypoint gerado nao contem padrao esperado: $_needle"
      return 1
    fi
  done
}

# O entrypoint roda AMBOS painel e encaminhador -- painel em background
# (para o encaminhador poder rodar em foreground/ser aguardado) -- valida
# a ORDEM: node ... & antes de socat ... &.
scenario_entrypoint_starts_panel_before_forwarder() {
  _out="$TMPDIR_TEST/entrypoint.sh"
  _run_serve_docker_fn _serve_docker_write_entrypoint "$_out"
  _assert_captured_exit 0 || return 1
  _node_line=$(grep -n 'node apps/server/dist/index.js &' "$_out" | head -1 | cut -d: -f1)
  _socat_line=$(grep -n '^socat TCP-LISTEN' "$_out" | head -1 | cut -d: -f1)
  if [ -z "$_node_line" ] || [ -z "$_socat_line" ]; then
    _fail "entrypoint_order_missing" "nao encontrei as linhas node/socat no entrypoint gerado"
    return 1
  fi
  if [ "$_socat_line" -le "$_node_line" ]; then
    _fail "entrypoint_order" "socat (linha $_socat_line) deve vir DEPOIS do node (linha $_node_line)"
    return 1
  fi
}

# task 1.3.3: TERM/INT MUST ser propagado a AMBOS os processos (painel +
# encaminhador) -- valida que o handler mata os dois PIDs, nao so um.
scenario_entrypoint_term_handler_kills_both_processes() {
  _out="$TMPDIR_TEST/entrypoint.sh"
  _run_serve_docker_fn _serve_docker_write_entrypoint "$_out"
  _assert_captured_exit 0 || return 1
  _handler=$(sed -n '/_cstk_term_handler() {/,/^}/p' "$_out")
  case "$_handler" in
    *'kill -TERM "$NODE_PID"'*) : ;;
    *) _fail "term_handler_node" "handler nao mata NODE_PID: $_handler"; return 1 ;;
  esac
  case "$_handler" in
    *'kill -TERM "$SOCAT_PID"'*) : ;;
    *) _fail "term_handler_socat" "handler nao mata SOCAT_PID: $_handler"; return 1 ;;
  esac
}

# O script gerado precisa ser POSIX sh valido -- roda dentro de uma base
# alpine cujo /bin/sh e o ash do BusyBox (nao bash); sh -n/dash -n bastam
# para pegar erro de sintaxe sem precisar executar (nem precisa de Docker).
scenario_entrypoint_is_valid_posix_sh() {
  _out="$TMPDIR_TEST/entrypoint.sh"
  _run_serve_docker_fn _serve_docker_write_entrypoint "$_out"
  _assert_captured_exit 0 || return 1
  capture sh -n "$_out"
  _assert_captured_exit 0 || return 1
  if command -v dash >/dev/null 2>&1; then
    capture dash -n "$_out"
    _assert_captured_exit 0 || return 1
  fi
}

# O Dockerfile embute o MESMO conteudo do entrypoint via heredoc BuildKit
# (COPY <<'EOF') -- garante que os dois geradores nao divergiram (DRY: uma
# unica fonte de verdade, _serve_docker_write_entrypoint, consumida por
# _serve_docker_write_dockerfile).
scenario_dockerfile_embeds_same_entrypoint_content() {
  _entrypoint_out="$TMPDIR_TEST/entrypoint.sh"
  _dockerfile_out="$TMPDIR_TEST/Dockerfile"
  _run_serve_docker_fn _serve_docker_write_entrypoint "$_entrypoint_out"
  _assert_captured_exit 0 || return 1
  _run_serve_docker_fn _serve_docker_write_dockerfile "$_dockerfile_out"
  _assert_captured_exit 0 || return 1
  # Extrai o corpo entre os marcadores de heredoc do Dockerfile gerado e
  # compara byte-a-byte com o entrypoint standalone.
  _extracted="$TMPDIR_TEST/extracted-entrypoint.sh"
  sed -n '/^COPY <<.CSTK_PANEL_ENTRYPOINT_EOF. \/usr\/local\/bin\/cstk-panel-entrypoint\.sh$/,/^CSTK_PANEL_ENTRYPOINT_EOF$/p' \
    "$_dockerfile_out" | sed '1d;$d' > "$_extracted"
  if ! diff -q "$_entrypoint_out" "$_extracted" >/dev/null 2>&1; then
    _fail "dockerfile_entrypoint_drift" "conteudo do entrypoint embutido no Dockerfile diverge do gerado standalone"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# 1.2.7 — _serve_docker_build_image: validacao de contrato SEM daemon real
# (o build real com Docker foi feito manualmente nesta wave -- ver nota no
# cabecalho do arquivo).
# ---------------------------------------------------------------------------

scenario_build_image_rejects_context_without_package_json() {
  _empty_ctx="$TMPDIR_TEST/empty-ctx"
  mkdir -p "$_empty_ctx"
  _run_serve_docker_fn _serve_docker_build_image "$_empty_ctx" "cstk-panel:test"
  _assert_captured_exit 1 || return 1
  assert_stderr_contains "package.json" || return 1
}

# ===========================================================================
# FASE 2 — orquestracao completa de _serve_docker_main
# ===========================================================================

# ---------------------------------------------------------------------------
# 2.2 — pre-flight fail-closed do runtime de container (FR-003/FR-004)
# ---------------------------------------------------------------------------

scenario_preflight_docker_absent_exit1_no_network() {
  CSTK_PANEL_DIR="$TMPDIR_TEST/panel"
  export CSTK_PANEL_DIR
  # PATH interno ISOLADO: nenhum `docker` nesse PATH, mesmo o binario real
  # existindo em /usr/local/bin no host (CLAUDE.md "PATH-stub nao esconde
  # binario de /usr/bin" vale identicamente para /usr/local/bin/docker).
  _pda_bin="$TMPDIR_TEST/stubs"
  mkdir -p "$_pda_bin"
  _SDM_INNER_PATH="$_pda_bin:$(_isolated_sh_dir)"
  _run_serve_docker_main "5173" "127.0.0.1" "0" "0" "0" ""
  _assert_captured_exit 1 || return 1
  assert_stderr_contains "docker" || return 1
  assert_stderr_contains "instale" || return 1
  # Nenhuma tentativa de usar um binario ausente alem do proprio docker
  # (confirma que nada de rede foi tentado antes do preflight, FR-003).
  case "$_CAPTURED_STDERR" in
    *"command not found"*|*": not found"*)
      _fail "preflight_no_network_before_check" "indicio de tentativa de uso de binario ausente antes do preflight: $_CAPTURED_STDERR"
      return 1
      ;;
  esac
}

scenario_preflight_daemon_down_distinct_message_exit1() {
  CSTK_PANEL_DIR="$TMPDIR_TEST/panel"
  export CSTK_PANEL_DIR
  _make_bin_dir
  _stub_docker "$_STUB_BIN"
  mkdir -p "$TMPDIR_TEST/docker-stub"
  : > "$TMPDIR_TEST/docker-stub/daemon-down"
  _run_serve_docker_main "5173" "127.0.0.1" "0" "0" "0" ""
  _assert_captured_exit 1 || return 1
  assert_stderr_contains "daemon" || return 1
  # Mensagem DISTINTA da de binario ausente (CHK008): esta nao sugere
  # instalar o docker, e sim iniciar o daemon/checar permissao.
  case "$_CAPTURED_STDERR" in
    *"instale o Docker"*)
      _fail "preflight_daemon_down_message_confusa" "mensagem de daemon parado nao deveria sugerir instalacao: $_CAPTURED_STDERR"
      return 1
      ;;
  esac
}

scenario_preflight_absent_and_down_messages_are_distinct() {
  CSTK_PANEL_DIR="$TMPDIR_TEST/panel"
  export CSTK_PANEL_DIR

  _pmd_bin="$TMPDIR_TEST/stubs-absent"
  mkdir -p "$_pmd_bin"
  _SDM_INNER_PATH="$_pmd_bin:$(_isolated_sh_dir)"
  _run_serve_docker_main "5173" "127.0.0.1" "0" "0" "0" ""
  _msg_absent="$_CAPTURED_STDERR"

  _make_bin_dir
  _stub_docker "$_STUB_BIN"
  mkdir -p "$TMPDIR_TEST/docker-stub"
  : > "$TMPDIR_TEST/docker-stub/daemon-down"
  _SDM_INNER_PATH="$PATH"
  _run_serve_docker_main "5173" "127.0.0.1" "0" "0" "0" ""
  _msg_down="$_CAPTURED_STDERR"

  if [ "$_msg_absent" = "$_msg_down" ]; then
    _fail "preflight_messages_distinct" "mensagens de docker-ausente e daemon-parado sao identicas (CHK008 exige distincao)"
    return 1
  fi
}

scenario_preflight_both_present_reaches_reconcile() {
  CSTK_PANEL_DIR="$TMPDIR_TEST/panel"
  export CSTK_PANEL_DIR
  _make_bin_dir
  _stub_docker "$_STUB_BIN"
  _seed_cached_install "$CSTK_PANEL_DIR" "v0.0.1"
  _run_serve_docker_main "5173" "127.0.0.1" "0" "0" "0" ""
  _assert_captured_exit 0 || return 1
  case "$(_docker_calls_log)" in
    *"info"*) : ;;
    *) _fail "preflight_info_called" "docker info nao foi chamado no pre-flight"; return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# 2.3 — reuso do fluxo de instalacao verificada (FR-006/FR-007, sem npm no host)
# ---------------------------------------------------------------------------

scenario_fetch_unverifiable_blocks_by_default() {
  CSTK_PANEL_DIR="$TMPDIR_TEST/panel"
  export CSTK_PANEL_DIR
  _make_bin_dir
  _stub_docker "$_STUB_BIN"
  _stub_curl_no_sha256 "$_STUB_BIN"
  _run_serve_docker_main "5173" "127.0.0.1" "0" "0" "0" ""
  _assert_captured_exit 1 || return 1
  assert_stderr_contains "integridade do pacote nao pode ser confirmada" || return 1
  case "$(_docker_calls_log)" in
    *"run -d"*) _fail "fetch_blocked_no_run" "docker run nao deveria ter ocorrido apos bloqueio de integridade"; return 1 ;;
  esac
}

scenario_fetch_allow_unverified_bypasses_and_proceeds() {
  CSTK_PANEL_DIR="$TMPDIR_TEST/panel"
  export CSTK_PANEL_DIR
  _make_bin_dir
  _stub_docker "$_STUB_BIN"
  _stub_curl_no_sha256 "$_STUB_BIN"
  _run_serve_docker_main "5173" "127.0.0.1" "0" "0" "1" "flag"
  _assert_captured_exit 0 || return 1
  case "$(_docker_calls_log)" in
    *"run -d"*) : ;;
    *) _fail "fetch_bypass_should_run" "docker run deveria ter ocorrido apos bypass explicito"; return 1 ;;
  esac
}

scenario_fetch_mismatch_blocks_even_with_allow_unverified() {
  # Regressao FR-010: mismatch de checksum NUNCA e bypassavel, nem com
  # --allow-unverified -- mesmo mecanismo do modo nativo (reuso, FR-007).
  CSTK_PANEL_DIR="$TMPDIR_TEST/panel"
  export CSTK_PANEL_DIR
  _make_bin_dir
  _stub_docker "$_STUB_BIN"
  _fmb_tarball="$SERVE_FIXTURE_DIR/panel-fixture.tar.gz"
  _fmb_wrong_sha=$(printf '0%.0s' $(seq 1 64))
  cat > "$_STUB_BIN/curl" <<STUB
#!/bin/sh
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
    _resp='{"tag_name":"v0.0.1","tarball_url":"https://github.com/JotJunior/cstk-panel/archive/v0.0.1.tar.gz","prerelease":false,"draft":false}'
    if [ -n "\$_output" ]; then printf '%s\n' "\$_resp" > "\$_output"; else printf '%s\n' "\$_resp"; fi
    ;;
  *github.com*.sha256*)
    if [ -n "\$_output" ]; then printf '%s  archive.tar.gz\n' "${_fmb_wrong_sha}" > "\$_output"; else printf '%s  archive.tar.gz\n' "${_fmb_wrong_sha}"; fi
    ;;
  *github.com*tar.gz*)
    if [ -n "\$_output" ]; then cp "${_fmb_tarball}" "\$_output"; else cat "${_fmb_tarball}"; fi
    ;;
  *) exit 1 ;;
esac
STUB
  chmod +x "$_STUB_BIN/curl"
  _run_serve_docker_main "5173" "127.0.0.1" "0" "0" "1" "flag"
  _assert_captured_exit 1 || return 1
  assert_stderr_contains "checksum SHA-256 nao confere" || return 1
}

# ---------------------------------------------------------------------------
# 2.4 — build/rebuild conforme --update/--reinstall (CHK012: precedencia)
# ---------------------------------------------------------------------------

scenario_build_trigger_absent_fetches_and_builds() {
  CSTK_PANEL_DIR="$TMPDIR_TEST/panel"
  export CSTK_PANEL_DIR
  _make_bin_dir
  _stub_docker "$_STUB_BIN"
  _stub_curl_ok "$_STUB_BIN"
  _run_serve_docker_main "5173" "127.0.0.1" "0" "0" "0" ""
  _assert_captured_exit 0 || return 1
  case "$(_docker_calls_log)" in
    *"build -f"*) : ;;
    *) _fail "build_trigger_absent" "docker build nao foi chamado com imagem ausente"; return 1 ;;
  esac
  # CHK009/3.1.3/3.1.5: o hardening nao e so da "primeira construcao" em
  # tese -- confere-se aqui, no gatilho REAL de primeira construcao.
  _assert_hardening_flags_in_run_line "$(_docker_calls_log | grep '^run -d')" "absent_first_build" || return 1
}

scenario_build_trigger_update_new_version_rebuilds() {
  CSTK_PANEL_DIR="$TMPDIR_TEST/panel"
  export CSTK_PANEL_DIR
  _make_bin_dir
  _stub_docker "$_STUB_BIN"
  _stub_curl_ok "$_STUB_BIN"
  _seed_cached_install "$CSTK_PANEL_DIR" "v0.0.0"
  _run_serve_docker_main "5173" "127.0.0.1" "1" "0" "0" ""
  _assert_captured_exit 0 || return 1
  assert_stdout_contains "atualizando painel: v0.0.0 -> v0.0.1" || return 1
  case "$(_docker_calls_log)" in
    *"build -f"*) : ;;
    *) _fail "build_trigger_update_new" "docker build nao foi chamado apos nova versao"; return 1 ;;
  esac
  # CHK009/3.1.3/3.1.5: mesmo conjunto de flags apos rebuild via --update.
  _assert_hardening_flags_in_run_line "$(_docker_calls_log | grep '^run -d')" "update_rebuild" || return 1
}

scenario_build_trigger_update_no_new_version_reuses() {
  CSTK_PANEL_DIR="$TMPDIR_TEST/panel"
  export CSTK_PANEL_DIR
  _make_bin_dir
  _stub_docker "$_STUB_BIN"
  _stub_curl_ok "$_STUB_BIN"
  _seed_cached_install "$CSTK_PANEL_DIR" "v0.0.1"
  _run_serve_docker_main "5173" "127.0.0.1" "1" "0" "0" ""
  _assert_captured_exit 0 || return 1
  assert_stdout_contains "ja esta na versao mais recente" || return 1
  case "$(_docker_calls_log)" in
    *"build -f"*) _fail "build_trigger_update_no_new" "docker build NAO deveria ocorrer (mesma versao)"; return 1 ;;
  esac
}

scenario_build_trigger_update_network_failure_keeps_installed() {
  # Best-effort (task 2.4.2/CHK010): falha de rede/API durante --update
  # mantem a imagem instalada e AINDA sobe o painel.
  CSTK_PANEL_DIR="$TMPDIR_TEST/panel"
  export CSTK_PANEL_DIR
  _make_bin_dir
  _stub_docker "$_STUB_BIN"
  cat > "$_STUB_BIN/curl" <<'STUB'
#!/bin/sh
printf 'curl: (7) Failed to connect\n' >&2
exit 7
STUB
  chmod +x "$_STUB_BIN/curl"
  _seed_cached_install "$CSTK_PANEL_DIR" "v0.0.1"
  _run_serve_docker_main "5173" "127.0.0.1" "1" "0" "0" ""
  _assert_captured_exit 0 || return 1
  case "$(_docker_calls_log)" in
    *"build -f"*) _fail "update_network_failure_no_rebuild" "nao deveria reconstruir com API indisponivel"; return 1 ;;
  esac
  case "$(_docker_calls_log)" in
    *"run -d"*) : ;;
    *) _fail "update_network_failure_still_runs" "painel deveria subir mesmo com falha de rede do --update"; return 1 ;;
  esac
}

scenario_build_trigger_reinstall_always_rebuilds_unconditionally() {
  CSTK_PANEL_DIR="$TMPDIR_TEST/panel"
  export CSTK_PANEL_DIR
  _make_bin_dir
  _stub_docker "$_STUB_BIN"
  _stub_curl_ok "$_STUB_BIN"
  _seed_cached_install "$CSTK_PANEL_DIR" "v0.0.1"
  _run_serve_docker_main "5173" "127.0.0.1" "0" "1" "0" ""
  _assert_captured_exit 0 || return 1
  case "$(_docker_calls_log)" in
    *"rmi -f cstk-panel:v0.0.1"*) : ;;
    *) _fail "reinstall_rmi" "docker rmi -f nao foi chamado no --reinstall"; return 1 ;;
  esac
  case "$(_docker_calls_log)" in
    *"build -f"*) : ;;
    *) _fail "reinstall_rebuild" "docker build nao foi chamado no --reinstall"; return 1 ;;
  esac
  # CHK009/3.1.3/3.1.5: mesmo conjunto de flags apos rebuild via --reinstall.
  _assert_hardening_flags_in_run_line "$(_docker_calls_log | grep '^run -d')" "reinstall_rebuild" || return 1
}

scenario_reinstall_wins_over_update_chk012() {
  CSTK_PANEL_DIR="$TMPDIR_TEST/panel"
  export CSTK_PANEL_DIR
  _make_bin_dir
  _stub_docker "$_STUB_BIN"
  _stub_curl_ok "$_STUB_BIN"
  _seed_cached_install "$CSTK_PANEL_DIR" "v0.0.1"
  # UPDATE=1 E REINSTALL=1 -- --reinstall MUST vencer: nunca imprime a
  # mensagem de checagem de --update (CHK012).
  _run_serve_docker_main "5173" "127.0.0.1" "1" "1" "0" ""
  _assert_captured_exit 0 || return 1
  assert_stdout_not_contains "verificando atualizacoes" || return 1
  case "$(_docker_calls_log)" in
    *"rmi -f cstk-panel:v0.0.1"*) : ;;
    *) _fail "reinstall_wins_rmi" "docker rmi -f nao foi chamado (--reinstall deveria vencer sobre --update)"; return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# 2.5 — docker run: nome, label, porta, mount, init, rm, hardening
# ---------------------------------------------------------------------------

scenario_docker_run_argv_contains_expected_flags() {
  CSTK_PANEL_DIR="$TMPDIR_TEST/panel"
  export CSTK_PANEL_DIR
  CSTK_KNOWLEDGE_DB="$TMPDIR_TEST/cstkdata/knowledge.db"
  export CSTK_KNOWLEDGE_DB
  _make_bin_dir
  _stub_docker "$_STUB_BIN"
  _seed_cached_install "$CSTK_PANEL_DIR" "v0.0.1"
  _run_serve_docker_main "5173" "127.0.0.1" "0" "0" "0" ""
  _assert_captured_exit 0 || return 1

  _run_line=$(_docker_calls_log | grep '^run -d')
  if [ -z "$_run_line" ]; then
    _fail "docker_run_missing" "nenhuma linha 'docker run -d' no log: $(_docker_calls_log)"
    return 1
  fi

  for _needle in \
    '--init' \
    '--rm' \
    '--name cstk-panel' \
    '--label cstk.managed=serve' \
    '-p 127.0.0.1:5173:8080' \
    "-v $TMPDIR_TEST/cstkdata:/data/knowledge-db:ro" \
    '-e CSTK_KNOWLEDGE_DB=/data/knowledge-db/knowledge.db' \
    'cstk-panel:v0.0.1' \
  ; do
    case "$_run_line" in
      *"$_needle"*) : ;;
      *) _fail "docker_run_argv" "docker run nao contem '$_needle': $_run_line"; return 1 ;;
    esac
  done

  # Subconjunto de hardening (CHK006) via helper compartilhado — mesma
  # assercao reusada pelos 3 gatilhos de build em 3.1.3/3.1.5 abaixo.
  _assert_hardening_flags_in_run_line "$_run_line" "reuse_cached" || return 1
}

scenario_docker_run_port_and_host_reflect_arguments() {
  CSTK_PANEL_DIR="$TMPDIR_TEST/panel"
  export CSTK_PANEL_DIR
  _make_bin_dir
  _stub_docker "$_STUB_BIN"
  _seed_cached_install "$CSTK_PANEL_DIR" "v0.0.1"
  _run_serve_docker_main "9999" "127.0.0.1" "0" "0" "0" ""
  _assert_captured_exit 0 || return 1
  case "$(_docker_calls_log | grep '^run -d')" in
    *"-p 127.0.0.1:9999:8080"*) : ;;
    *) _fail "port_reflect" "porta customizada nao refletida no docker run"; return 1 ;;
  esac
}

scenario_kdb_mount_defaults_to_claude_cstk_dir_when_env_unset() {
  CSTK_PANEL_DIR="$TMPDIR_TEST/panel"
  export CSTK_PANEL_DIR
  CSTK_KNOWLEDGE_DB=""
  _make_bin_dir
  _stub_docker "$_STUB_BIN"
  _seed_cached_install "$CSTK_PANEL_DIR" "v0.0.1"
  _run_serve_docker_main "5173" "127.0.0.1" "0" "0" "0" ""
  _assert_captured_exit 0 || return 1
  case "$(_docker_calls_log | grep '^run -d')" in
    *"-v $TMPDIR_TEST/.claude/cstk:/data/knowledge-db:ro"*) : ;;
    *) _fail "kdb_default_dir" "mount nao usou o default ~/.claude/cstk (HOME=\$TMPDIR_TEST): $(_docker_calls_log | grep '^run -d')"; return 1 ;;
  esac
}

scenario_serve_docker_never_emits_push_or_host_network_or_privileged() {
  # Verificacao ESTATICA sobre o codigo-fonte (nao so o Dockerfile gerado,
  # ja coberto por scenario_dockerfile_never_contains_push): a MONTAGEM do
  # `docker run`/`docker build` em si tambem nunca deve conter esses
  # padroes (FR-013 / research.md Decision 2 rejeita --network host).
  # CAP_NET_ADMIN incluido aqui por 3.1.4/CHK008: e a alternativa de design
  # que a escolha do encaminhador via socat elimina (vs. iptables/DNAT no
  # container, que exigiria essa capability) -- research.md Decision 2
  # "Alternatives considered". Linhas de comentario puro (explicando a
  # AUSENCIA -- ex.: "Nunca `docker push`", "sem CAP_NET_ADMIN") sao
  # excluidas: so codigo real conta como violacao.
  _hits=$(grep -vE '^[[:space:]]*#' "$REPO_ROOT/cli/lib/serve-docker.sh" \
            | grep -iE 'docker[[:space:]]+push|--network[[:space:]=]host|--privileged|CAP_NET_ADMIN' \
          || :)
  if [ -n "$_hits" ]; then
    _fail "no_push_no_host_network" "serve-docker.sh contem push/--network host/--privileged/CAP_NET_ADMIN em codigo (nao-comentario): $_hits"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# 2.6 — reconciliacao de container remanescente (FR-012-INFRA-IDEMP, CHK003)
# ---------------------------------------------------------------------------

scenario_reconcile_running_remnant_then_starts_normally() {
  CSTK_PANEL_DIR="$TMPDIR_TEST/panel"
  export CSTK_PANEL_DIR
  _make_bin_dir
  _stub_docker "$_STUB_BIN"
  _seed_cached_install "$CSTK_PANEL_DIR" "v0.0.1"
  mkdir -p "$TMPDIR_TEST/docker-stub"
  : > "$TMPDIR_TEST/docker-stub/container-running"
  _run_serve_docker_main "5173" "127.0.0.1" "0" "0" "0" ""
  _assert_captured_exit 0 || return 1
  case "$(_docker_calls_log)" in
    *"rm -f cstk-panel"*) : ;;
    *) _fail "reconcile_running" "docker rm -f nao foi chamado para reconciliar remanescente"; return 1 ;;
  esac
}

scenario_reconcile_absent_remnant_is_idempotent_noop() {
  CSTK_PANEL_DIR="$TMPDIR_TEST/panel"
  export CSTK_PANEL_DIR
  _make_bin_dir
  _stub_docker "$_STUB_BIN"
  _seed_cached_install "$CSTK_PANEL_DIR" "v0.0.1"
  # Sem marcador container-running -- stub simula "No such container".
  _run_serve_docker_main "5173" "127.0.0.1" "0" "0" "0" ""
  _assert_captured_exit 0 || return 1
}

scenario_reconcile_impossible_gives_actionable_message_exit1() {
  CSTK_PANEL_DIR="$TMPDIR_TEST/panel"
  export CSTK_PANEL_DIR
  _make_bin_dir
  _stub_docker "$_STUB_BIN"
  _seed_cached_install "$CSTK_PANEL_DIR" "v0.0.1"
  mkdir -p "$TMPDIR_TEST/docker-stub"
  : > "$TMPDIR_TEST/docker-stub/rm-fails"
  _run_serve_docker_main "5173" "127.0.0.1" "0" "0" "0" ""
  _assert_captured_exit 1 || return 1
  assert_stderr_contains "reconciliar" || return 1
  # NUNCA repassar o stack cru do runtime (US4 Acceptance Scenario 2).
  case "$_CAPTURED_STDERR" in
    *"trying to connect to the Docker daemon socket"*)
      _fail "reconcile_impossible_leaks_raw" "mensagem repassa stack cru do runtime: $_CAPTURED_STDERR"
      return 1
      ;;
  esac
  case "$(_docker_calls_log)" in
    *"run -d"*) _fail "reconcile_impossible_no_run" "docker run nao deveria ter ocorrido apos reconciliacao impossivel"; return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# 2.7 — encerramento gracioso (FR-011, SC-003)
# ---------------------------------------------------------------------------

# Ctrl+C simulado: envia SIGTERM ao processo rodando _serve_docker_main e
# confirma que `docker stop -t 5 cstk-panel` foi emitido, sem hang --
# paridade com tests/cstk/test_serve.sh::scenario_sigterm_graceful_kill
# (mesmo padrao: subshell em background + kill -TERM + poll com timeout).
scenario_graceful_shutdown_sends_docker_stop_with_grace_5s() {
  CSTK_PANEL_DIR="$TMPDIR_TEST/panel"
  export CSTK_PANEL_DIR
  _make_bin_dir
  _stub_docker "$_STUB_BIN"
  _seed_cached_install "$CSTK_PANEL_DIR" "v0.0.1"
  mkdir -p "$TMPDIR_TEST/docker-stub"
  : > "$TMPDIR_TEST/docker-stub/container-long-running"

  _result_file="$TMPDIR_TEST/dm_exit_code"
  (
    export CSTK_LIB CSTK_PANEL_DIR PATH HOME="$TMPDIR_TEST" TMPDIR_TEST
    . "$CSTK_LIB/serve.sh"
    . "$CSTK_LIB/serve-docker.sh"
    _serve_docker_main "5173" "127.0.0.1" "0" "0" "0" ""
    printf '%d\n' "$?" > "$_result_file"
  ) &
  _dm_pid=$!

  # Aguardar o container "subir" (marker criado pelo stub run) antes de
  # interromper -- evita mandar TERM antes do docker run ter ocorrido.
  _wait_cnt=0
  while [ "$_wait_cnt" -lt 40 ]; do
    [ -f "$TMPDIR_TEST/docker-stub/container-running" ] && break
    sleep 0.1 2>/dev/null || sleep 1
    _wait_cnt=$((_wait_cnt + 1))
  done

  kill -TERM "$_dm_pid" 2>/dev/null || :

  _wait_cnt=0
  while [ "$_wait_cnt" -lt 40 ]; do
    kill -0 "$_dm_pid" 2>/dev/null || break
    sleep 0.1 2>/dev/null || sleep 1
    _wait_cnt=$((_wait_cnt + 1))
  done

  if kill -0 "$_dm_pid" 2>/dev/null; then
    kill -KILL "$_dm_pid" 2>/dev/null || :
    wait "$_dm_pid" 2>/dev/null || :
    _fail "graceful_shutdown_hang" "_serve_docker_main nao encerrou dentro do timeout apos SIGTERM"
    return 1
  fi
  wait "$_dm_pid" 2>/dev/null || :

  case "$(_docker_calls_log)" in
    *"stop -t 5 cstk-panel"*) : ;;
    *) _fail "graceful_shutdown_stop_call" "docker stop -t 5 cstk-panel nao encontrado no log: $(_docker_calls_log)"; return 1 ;;
  esac
}

scenario_graceful_shutdown_rm_not_called_after_stop_because_of_auto_remove() {
  # task 2.7.2: --rm ja remove o container apos o stop bem-sucedido --
  # nenhum `docker rm` ADICIONAL deve ser emitido pelo proprio handler de
  # shutdown (so o `docker stop`).
  CSTK_PANEL_DIR="$TMPDIR_TEST/panel"
  export CSTK_PANEL_DIR
  _make_bin_dir
  _stub_docker "$_STUB_BIN"
  _seed_cached_install "$CSTK_PANEL_DIR" "v0.0.1"
  mkdir -p "$TMPDIR_TEST/docker-stub"
  : > "$TMPDIR_TEST/docker-stub/container-long-running"

  (
    export CSTK_LIB CSTK_PANEL_DIR PATH HOME="$TMPDIR_TEST" TMPDIR_TEST
    . "$CSTK_LIB/serve.sh"
    . "$CSTK_LIB/serve-docker.sh"
    _serve_docker_main "5173" "127.0.0.1" "0" "0" "0" ""
  ) &
  _dm_pid=$!

  _wait_cnt=0
  while [ "$_wait_cnt" -lt 40 ]; do
    [ -f "$TMPDIR_TEST/docker-stub/container-running" ] && break
    sleep 0.1 2>/dev/null || sleep 1
    _wait_cnt=$((_wait_cnt + 1))
  done

  kill -TERM "$_dm_pid" 2>/dev/null || :
  wait "$_dm_pid" 2>/dev/null || :

  # Conta linhas "rm -f cstk-panel" APOS o "stop" -- so a reconciliacao
  # PRE-run (antes do stop) e esperada; nenhuma pos-stop.
  _after_stop=$(_docker_calls_log | awk '/^stop /{f=1} f && /^rm -f cstk-panel$/{print}')
  if [ -n "$_after_stop" ]; then
    _fail "shutdown_extra_rm" "docker rm -f adicional apos o stop (redundante com --rm): $_after_stop"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# 2.8 — mensagens de erro acionaveis (CHK009: causa raiz + proximo passo)
# ---------------------------------------------------------------------------

scenario_message_docker_absent_is_actionable() {
  CSTK_PANEL_DIR="$TMPDIR_TEST/panel"
  export CSTK_PANEL_DIR
  _pda_bin="$TMPDIR_TEST/stubs-msg-absent"
  mkdir -p "$_pda_bin"
  _SDM_INNER_PATH="$_pda_bin:$(_isolated_sh_dir)"
  _run_serve_docker_main "5173" "127.0.0.1" "0" "0" "0" ""
  _assert_captured_exit 1 || return 1
  assert_stderr_contains "PATH" || return 1
  assert_stderr_contains "https://docs.docker.com" || return 1
}

scenario_message_daemon_down_is_actionable() {
  CSTK_PANEL_DIR="$TMPDIR_TEST/panel"
  export CSTK_PANEL_DIR
  _make_bin_dir
  _stub_docker "$_STUB_BIN"
  mkdir -p "$TMPDIR_TEST/docker-stub"
  : > "$TMPDIR_TEST/docker-stub/daemon-down"
  _run_serve_docker_main "5173" "127.0.0.1" "0" "0" "0" ""
  _assert_captured_exit 1 || return 1
  assert_stderr_contains "daemon" || return 1
  assert_stderr_contains "inicie" || return 1
}

scenario_message_port_in_use_is_actionable() {
  CSTK_PANEL_DIR="$TMPDIR_TEST/panel"
  export CSTK_PANEL_DIR
  _make_bin_dir
  _stub_docker "$_STUB_BIN"
  _seed_cached_install "$CSTK_PANEL_DIR" "v0.0.1"
  mkdir -p "$TMPDIR_TEST/docker-stub"
  : > "$TMPDIR_TEST/docker-stub/run-port-conflict"
  _run_serve_docker_main "5173" "127.0.0.1" "0" "0" "0" ""
  _assert_captured_exit 1 || return 1
  assert_stderr_contains "porta" || return 1
  assert_stderr_contains "--port" || return 1
}

scenario_message_reconcile_impossible_is_actionable() {
  CSTK_PANEL_DIR="$TMPDIR_TEST/panel"
  export CSTK_PANEL_DIR
  _make_bin_dir
  _stub_docker "$_STUB_BIN"
  _seed_cached_install "$CSTK_PANEL_DIR" "v0.0.1"
  mkdir -p "$TMPDIR_TEST/docker-stub"
  : > "$TMPDIR_TEST/docker-stub/rm-fails"
  _run_serve_docker_main "5173" "127.0.0.1" "0" "0" "0" ""
  _assert_captured_exit 1 || return 1
  assert_stderr_contains "permissao" || return 1
  assert_stderr_contains "tente novamente" || return 1
}

scenario_message_integrity_unconfirmed_matches_native_wording() {
  CSTK_PANEL_DIR="$TMPDIR_TEST/panel"
  export CSTK_PANEL_DIR
  _make_bin_dir
  _stub_docker "$_STUB_BIN"
  _stub_curl_no_sha256 "$_STUB_BIN"
  _run_serve_docker_main "5173" "127.0.0.1" "0" "0" "0" ""
  _assert_captured_exit 1 || return 1
  # Mesmo texto do modo nativo (FR-007 -- mesmo mecanismo compartilhado).
  assert_stderr_contains "integridade do pacote nao pode ser confirmada" || return 1
  assert_stderr_contains "use --allow-unverified" || return 1
}

scenario_all_five_error_messages_are_non_empty_and_distinct() {
  # CHK009 -- sanity check final: as 5 mensagens canonicas do contrato
  # (docker ausente / daemon inacessivel / porta em uso / reconciliacao
  # impossivel / integridade nao confirmada) sao todas NAO-VAZIAS e
  # mutuamente DISTINTAS entre si (nenhuma reaproveita o texto de outra).
  CSTK_PANEL_DIR="$TMPDIR_TEST/panel"
  export CSTK_PANEL_DIR

  _pda_bin="$TMPDIR_TEST/stubs-5msg"
  mkdir -p "$_pda_bin"
  _SDM_INNER_PATH="$_pda_bin:$(_isolated_sh_dir)"
  _run_serve_docker_main "5173" "127.0.0.1" "0" "0" "0" ""
  _m1="$_CAPTURED_STDERR"

  _make_bin_dir
  _stub_docker "$_STUB_BIN"
  _SDM_INNER_PATH="$PATH"
  mkdir -p "$TMPDIR_TEST/docker-stub"
  : > "$TMPDIR_TEST/docker-stub/daemon-down"
  _run_serve_docker_main "5173" "127.0.0.1" "0" "0" "0" ""
  _m2="$_CAPTURED_STDERR"

  rm -f "$TMPDIR_TEST/docker-stub/daemon-down"
  _seed_cached_install "$CSTK_PANEL_DIR" "v0.0.1"
  : > "$TMPDIR_TEST/docker-stub/run-port-conflict"
  _run_serve_docker_main "5173" "127.0.0.1" "0" "0" "0" ""
  _m3="$_CAPTURED_STDERR"

  rm -f "$TMPDIR_TEST/docker-stub/run-port-conflict"
  : > "$TMPDIR_TEST/docker-stub/rm-fails"
  _run_serve_docker_main "5173" "127.0.0.1" "0" "0" "0" ""
  _m4="$_CAPTURED_STDERR"

  rm -f "$TMPDIR_TEST/docker-stub/rm-fails"
  _stub_curl_no_sha256 "$_STUB_BIN"
  # _serve_docker_source_dir e SIBLING de dirname(CSTK_PANEL_DIR) -- trocar
  # so o leaf de CSTK_PANEL_DIR (ex.: "panel-fresh") NAO muda o sibling
  # (mesmo dirname). Preciso limpar o cache (arvore-fonte + marcador de
  # imagem) explicitamente para forcar um fetch de verdade nesta 5a chamada.
  rm -rf "$TMPDIR_TEST/panel-docker-src" "$TMPDIR_TEST/docker-stub/images"
  _run_serve_docker_main "5173" "127.0.0.1" "0" "0" "0" ""
  _m5="$_CAPTURED_STDERR"

  for _m in "$_m1" "$_m2" "$_m3" "$_m4" "$_m5"; do
    if [ -z "$_m" ]; then
      _fail "five_messages_non_empty" "uma das 5 mensagens canonicas veio vazia"
      return 1
    fi
  done

  # Distincao par-a-par (5 mensagens, 10 pares). NAO usar `sort -u | wc -l`
  # sobre a concatenacao: cada mensagem pode ter MULTIPLAS linhas (ex.: a
  # de integridade tem 2 printfs em stderr), entao ordenar por LINHA conta
  # fragmentos em vez de mensagens inteiras -- comparacao pairwise direta
  # da string completa evita esse falso-positivo.
  if [ "$_m1" = "$_m2" ] || [ "$_m1" = "$_m3" ] || [ "$_m1" = "$_m4" ] || [ "$_m1" = "$_m5" ] \
     || [ "$_m2" = "$_m3" ] || [ "$_m2" = "$_m4" ] || [ "$_m2" = "$_m5" ] \
     || [ "$_m3" = "$_m4" ] || [ "$_m3" = "$_m5" ] \
     || [ "$_m4" = "$_m5" ]; then
    _fail "five_messages_distinct" "duas ou mais das 5 mensagens canonicas sao identicas (CHK008/CHK009 exigem mensagens distintas por causa)"
    return 1
  fi
}

run_all_scenarios
