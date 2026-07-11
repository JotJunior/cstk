#!/bin/sh
# test_serve-docker.sh — cobre cli/lib/serve-docker.sh (modo `cstk serve --docker`)
#
# Ref: docs/specs/panel-docker/tasks.md FASE 1 (1.1.4, 1.2.7, 1.3.5)
#
# Escopo desta FASE (1.1-1.3 do backlog): scaffold + os geradores de
# Dockerfile/entrypoint ja funcionais (_serve_docker_write_dockerfile,
# _serve_docker_write_entrypoint, _serve_docker_image_tag,
# _serve_docker_build_image) + o esqueleto de _serve_docker_main + o
# confinamento de `docker` num unico arquivo (task 1.1.3). Todos os
# scenarios abaixo sao FAST e HERMETICOS (sem daemon Docker real) --
# mesma filosofia de stub de tests/cstk/test_serve.sh (curl/npm stubados,
# nunca rede real). A validacao EMPIRICA com `docker build`/`docker run`
# reais (tasks 1.2.7/1.3.5) foi feita manualmente durante a execute-task
# wave desta FASE (ver Decisao registrada pelo orquestrador) -- um
# fixture sintetico que mimetizasse o monorepo real do cstk-panel so para
# permitir um `docker build` real e continuo no harness POSIX seria mais
# peso do que esta FASE pede (o proprio backlog, task 4.1.1, ja planeja
# cobertura de Scenario 1 com stub de docker, nao com build real -- este
# arquivo antecipa exatamente essa filosofia). Cenarios adicionais
# (flags, composicao --update/--reinstall, mensagens de erro, etc.) chegam
# nas FASEs 2-4 conforme cada peca de _serve_docker_main for implementada.
#
# Estrategia de teste: sourcing direto do lib (sem stub de rede -- nenhuma
# funcao testada aqui faz I/O de rede) + assercoes de CONTEUDO sobre os
# arquivos gerados (Dockerfile/entrypoint) em tmpdir isolado por scenario.

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

# _serve_docker_main e um esqueleto honesto nesta FASE 1 (task 1.1.2): define
# a assinatura de 6 parametros mas nao orquestra nada ainda (FASE 2). Deve
# falhar de forma informativa, nunca fingir sucesso.
scenario_main_is_honest_skeleton_not_yet_implemented() {
  _run_serve_docker_fn _serve_docker_main "5173" "127.0.0.1" "0" "0" "0" ""
  _assert_captured_exit 1 || return 1
  assert_stderr_contains "nao implementado" || return 1
}

# ---------------------------------------------------------------------------
# 1.1.3 — confinamento: "docker" so aparece em serve-docker.sh (carve-out
# Principio II condicao b), exceto o parse da flag --docker em serve.sh
# (FASE 2 -- ainda inexistente nesta FASE 1, entao o grep abaixo deve ser
# vazio ate la).
# ---------------------------------------------------------------------------

scenario_docker_mentions_confined_to_serve_docker_lib() {
  # Escopo: cli/ (codigo do toolkit, onde o carve-out do Principio II se
  # aplica). global/ (skills/commands/agents), tests/, docs/, scripts/ e
  # CLAUDE.md/CHANGELOG.md ficam DE FORA de proposito -- mencionam "docker"
  # em prosa/testes sem violar o confinamento de DEPENDENCIA de codigo.
  _hits=$(grep -rniE 'docker' "$REPO_ROOT/cli" 2>/dev/null \
            | grep -v '/cli/lib/serve-docker\.sh:' \
            | grep -vE '/cli/lib/serve\.sh:[0-9]+: *-*-docker\)[[:space:]]*$' \
          || :)
  if [ -n "$_hits" ]; then
    _fail "docker_confinement" "mencoes a 'docker' fora de serve-docker.sh (ou do parse --docker em serve.sh): $_hits"
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
  if ! grep -q '^FROM node:20-bookworm-slim@sha256:[0-9a-f]\{64\}$' "$_out"; then
    _fail "dockerfile_digest_pin" "FROM nao fixa a base por digest sha256 de 64 hex: $(grep '^FROM' "$_out")"
    return 1
  fi
}

scenario_dockerfile_matches_contract_shape() {
  _out="$TMPDIR_TEST/Dockerfile"
  _run_serve_docker_fn _serve_docker_write_dockerfile "$_out"
  _assert_captured_exit 0 || return 1
  for _needle in \
    'WORKDIR /app' \
    'COPY --chown=node:node . .' \
    'RUN npm ci' \
    'RUN npm run build' \
    'apt-get install -y --no-install-recommends socat' \
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

# 1.2.5: USER node MUST vir DEPOIS do apt-get (que exige root) -- ordem
# importa, nao so presenca.
scenario_dockerfile_user_node_after_root_only_steps() {
  _out="$TMPDIR_TEST/Dockerfile"
  _run_serve_docker_fn _serve_docker_write_dockerfile "$_out"
  _assert_captured_exit 0 || return 1
  _apt_line=$(grep -n 'apt-get install' "$_out" | head -1 | cut -d: -f1)
  _user_line=$(grep -n '^USER node$' "$_out" | head -1 | cut -d: -f1)
  if [ -z "$_apt_line" ] || [ -z "$_user_line" ]; then
    _fail "dockerfile_user_order_missing" "nao encontrei as linhas apt-get/USER node no Dockerfile gerado"
    return 1
  fi
  if [ "$_user_line" -le "$_apt_line" ]; then
    _fail "dockerfile_user_order" "USER node (linha $_user_line) deve vir DEPOIS do apt-get install (linha $_apt_line)"
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
# debian-slim cujo /bin/sh e dash (nao bash); sh -n/dash -n bastam para
# pegar erro de sintaxe sem precisar executar (nem precisa de Docker).
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

run_all_scenarios
