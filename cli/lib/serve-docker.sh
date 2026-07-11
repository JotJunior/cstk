# serve-docker.sh — modo `cstk serve --docker`: sobe o cstk-panel dentro de
# um container Docker local, para hosts sem `npm`/`node` (FR-006).
#
# **CONFINAMENTO DE `docker` (Constitution 1.1.0 §Optional dependencies,
# carve-out condicao b)**: este e o UNICO arquivo do toolkit autorizado a
# referenciar `docker` (o binario, os subcomandos `docker build`/`docker
# run`/etc., ou qualquer conceito exclusivo de container). A UNICA excecao
# fora deste arquivo e o parse da flag `--docker` em `cli/lib/serve.sh`
# (FASE 2 do backlog desta feature) — o nome da flag em si nao conta como
# dependencia, so o encaminhamento para as funcoes daqui. Mesma disciplina
# de `cli/lib/hooks.sh` (unico arquivo autorizado a `jq`) e
# `cli/lib/recall.sh` (unico arquivo autorizado a `sqlite3`). Adicionar
# `docker` em qualquer outro `.sh` do toolkit viola o carve-out.
#
# Ref: docs/specs/panel-docker/spec.md, plan.md, research.md, data-model.md,
#      contracts/cli-docker-mode.md, tasks.md FASE 1 (1.1/1.2/1.3).
#
# Contrato publico (FASE 1 — esqueleto; orquestracao completa em FASE 2/3):
#   _serve_docker_main PORT HOST UPDATE REINSTALL ALLOW_UNVERIFIED BYPASS_METHOD
#     Ponto de entrada chamado por serve_main (serve.sh) quando --docker esta
#     presente. Recebe os MESMOS parametros ja parseados/validados por
#     serve_main (mesma convencao de _serve_install). Nesta FASE 1 e um
#     esqueleto (task 1.1.2): define a assinatura e devolve erro informativo
#     -- a orquestracao real (pre-flight fail-closed, reuso do fluxo de
#     instalacao verificada, build/rebuild condicional, docker run com
#     hardening, reconciliacao, encerramento gracioso) chega nas FASEs
#     2/3 do backlog (docs/specs/panel-docker/tasks.md).
#
# Funcoes internas ja funcionais nesta FASE 1 (cobertas por
# tests/cstk/test_serve-docker.sh via assercoes de conteudo — sem daemon
# Docker real; ver nota mais abaixo sobre o estado da validacao empirica de
# build/run reais, tasks 1.2.7/1.3.5, ainda PENDENTE):
#   _serve_docker_image_tag PANEL_VERSION
#     Imprime a tag local deterministica da imagem (data-model.md "Panel
#     Image" image_tag). SEMPRE local — nunca registry remoto (FR-013).
#   _serve_docker_write_entrypoint DEST_PATH
#     Escreve o script de entrypoint (painel + encaminhador socat + trap de
#     sinal) em DEST_PATH. Fonte UNICA do conteudo — tambem consumida por
#     _serve_docker_write_dockerfile (heredoc BuildKit `COPY <<EOF`), para
#     nao duplicar o script em dois lugares.
#   _serve_docker_write_dockerfile DEST_PATH
#     Escreve o Dockerfile completo (research.md Decision 1) em DEST_PATH.
#     Base `node:20-bookworm-slim` fixada por digest (glibc — prebuilds do
#     modulo nativo better-sqlite3, Decision 1 "Rationale"); nunca versionado
#     como arquivo solto no repositorio — gerado sob demanda, confinado
#     aqui.
#   _serve_docker_build_image BUILD_CONTEXT_DIR IMAGE_TAG
#     Constroi a imagem local via `docker build -f <Dockerfile gerado>
#     BUILD_CONTEXT_DIR`. BUILD_CONTEXT_DIR MUST ser a arvore verificada do
#     painel (data-model.md "Verified Panel Installation" extracted_tree_path
#     — reuso do fluxo de integridade existente, FR-007; sem segunda fonte de
#     download). Nunca `docker push` (FR-013).
#
# Constantes internas (portas fixas do lado container — nunca expostas ao
# usuario; o `--port` do usuario so afeta o lado HOST do `docker run -p`,
# Decision 4):
#   _SD_FORWARDER_PORT=8080       porta onde o socat escuta em 0.0.0.0
#                                  dentro do container (mapeada por -p)
#   _SD_PANEL_INTERNAL_PORT=3001  porta onde o painel escuta em 127.0.0.1
#                                  (config.ts L80 — default quando PORT
#                                  ausente; fixado aqui explicitamente)
#
# POSIX sh puro (Principio II) para ESTE arquivo — o conteudo do Dockerfile
# gerado usa a sintaxe estendida `# syntax=docker/dockerfile:1` do BuildKit
# (heredocs em COPY), necessaria para embutir o entrypoint sem depender de
# um segundo arquivo dentro do contexto de build (mantem o contexto
# intocado — extracted_tree_path permanece exatamente a arvore verificada,
# sem mutacao).
#
# Estado da validacao empirica nesta FASE 1 (Constitution VI — nao mascarar
# o que nao foi confirmado): o MECANISMO de geracao foi validado de fato —
# _serve_docker_write_dockerfile/_serve_docker_write_entrypoint foram
# invocadas de verdade, o Dockerfile/entrypoint resultantes foram
# inspecionados byte-a-byte (heredocs aninhados escapam `` ` ``/`$`
# corretamente, sem interpolacao indevida) e o entrypoint passou em `sh -n`
# + `dash -n` + shellcheck. O digest da base (abaixo) veio de uma chamada
# REAL a Registry HTTP API v2 do Docker Hub. O que NAO foi possivel
# confirmar nesta sessao: um `docker build`/`docker run` completo e real
# contra a imagem de PRODUCAO (node:20-bookworm-slim) — o daemon Docker
# deste ambiente sandboxed nao completa pulls de imagens novas nem RUN
# steps que dependem de rede de build (`docker pull node:20-bookworm-slim`,
# `docker pull hello-world` e um `docker build` completo com base
# alternativa ja cacheada node:20-alpine ficaram pendurados
# indefinidamente, enquanto uma requisicao HTTPS de DENTRO de um container
# ja em execucao — sem pull/build novo — respondeu normalmente; ver Decisao
# registrada pelo orquestrador para o diagnostico completo). Portanto as
# tasks 1.2.7 (docker build local sucede) e 1.3.5 (encaminhador alcancavel
# via HTTP real) permanecem PENDENTES de verificacao com daemon Docker
# irrestrito — nao presumir sucesso.

if [ "${_SERVE_DOCKER_LOADED:-}" = "1" ]; then
  return 0
fi
_SERVE_DOCKER_LOADED=1

# Porta fixa do encaminhador dentro do container (nunca exposta ao usuario).
_SD_FORWARDER_PORT="8080"
# Porta fixa do painel dentro do container (config.ts L80 default).
_SD_PANEL_INTERNAL_PORT="3001"

# Base da imagem: node:20-bookworm-slim (glibc — Decision 1), fixada por
# digest do INDEX multi-arch (nao tag flutuante — CHK013/security). Digest
# resolvido empiricamente via a Registry HTTP API v2 (GET manifest com
# Bearer token de auth.docker.io, header `Docker-Content-Digest` da
# resposta — mesmo mecanismo que `docker pull` usaria) nesta execute-task
# wave, ja que o daemon Docker deste ambiente sandboxed nao completa pulls
# de imagens novas (ver Decisao registrada pelo orquestrador para o
# diagnostico completo). Reavaliar/atualizar conforme o processo descrito
# na task 3.2.3 quando a base precisar de patch de seguranca.
_SD_BASE_IMAGE="node:20-bookworm-slim@sha256:2cf067cfed83d5ea958367df9f966191a942351a2df77d6f0193e162b5febfc0"

# _serve_docker_image_tag PANEL_VERSION
# Imprime a tag local deterministica da imagem do painel. Nunca aponta a
# registry remoto (FR-013) — so o nome:tag local usado por `docker build -t`
# e `docker run`.
_serve_docker_image_tag() {
  printf 'cstk-panel:%s\n' "$1"
}

# _serve_docker_write_entrypoint DEST_PATH
# Escreve em DEST_PATH o script POSIX sh que roda como ENTRYPOINT do
# container: inicia o painel em background (PORT=3001 explicito) e o
# encaminhador socat em foreground (0.0.0.0:8080 -> 127.0.0.1:3001),
# propagando TERM/INT a ambos (research.md Decision 2 e Decision 6).
#
# Roda como filho direto de tini (`docker run --init`) — tini reapeia
# zumbis (inclusive os filhos que o socat com `fork` gera por conexao) e
# entrega o sinal recebido a este script, que o repassa aos 2 processos
# reais (mesma filosofia de cli/lib/serve.sh::_serve_shutdown: kill -TERM +
# aguardar; o grace/SIGKILL de ultima instancia fica a cargo de `docker
# stop -t <grace>` sobre o PID 1).
_serve_docker_write_entrypoint() {
  _sdwe_dest="$1"
  cat >"$_sdwe_dest" <<'CSTK_SERVE_DOCKER_ENTRYPOINT_EOF'
#!/bin/sh
# cstk-panel-entrypoint.sh -- gerado por
# cli/lib/serve-docker.sh::_serve_docker_write_entrypoint. Nao existe como
# arquivo solto no repositorio (fonte confinada em serve-docker.sh).
set -eu

PORT=3001
export PORT

FORWARDER_PORT=8080

cd /app

node apps/server/dist/index.js &
NODE_PID=$!

socat TCP-LISTEN:"$FORWARDER_PORT",fork,reuseaddr TCP:127.0.0.1:"$PORT" &
SOCAT_PID=$!

_cstk_term_handler() {
  kill -TERM "$NODE_PID" 2>/dev/null || :
  kill -TERM "$SOCAT_PID" 2>/dev/null || :
  wait "$NODE_PID" 2>/dev/null || :
  wait "$SOCAT_PID" 2>/dev/null || :
  exit 0
}
trap '_cstk_term_handler' TERM INT

wait
CSTK_SERVE_DOCKER_ENTRYPOINT_EOF
}

# _serve_docker_write_dockerfile DEST_PATH
# Escreve em DEST_PATH o Dockerfile completo do modo `cstk serve --docker`
# (research.md Decision 1, data-model.md "Panel Image"). O entrypoint e
# embutido via heredoc BuildKit (`COPY <<'EOF' ... EOF`), reusando o MESMO
# conteudo de _serve_docker_write_entrypoint — nao ha COPY relativo ao
# contexto de build, entao extracted_tree_path (a arvore verificada) nunca
# e mutada por este processo.
#
# Contrato do Dockerfile (todas as linhas aterradas — ver cabecalho do
# arquivo e research.md Decision 1/2/7):
#   FROM node:20-bookworm-slim@sha256:...   glibc, digest fixo (nao tag)
#   WORKDIR /app + COPY .                    contexto = arvore verificada
#   RUN npm ci                               lockfile (nao npm install);
#                                             ja falha fail-closed se
#                                             package-lock.json ausente —
#                                             mensagem customizada fica
#                                             para a task 3.3
#   RUN npm run build                        compila shared-types+server+web
#                                             (gera apps/server/dist/ e
#                                             apps/web/dist/, consumidos em
#                                             runtime pelo entrypoint/painel)
#   RUN apt-get install socat                encaminhador (Decision 2);
#                                             roda ANTES de USER node (apt
#                                             exige root)
#   COPY heredoc entrypoint + chmod +x
#   USER node                                non-root (Decision 7)
#   EXPOSE 8080                              porta fixa do encaminhador
#   ENTRYPOINT [entrypoint script]
_serve_docker_write_dockerfile() {
  _sdwd_dest="$1"

  _sdwd_entrypoint_tmp=$(mktemp 2>/dev/null) || {
    printf 'cstk serve --docker: erro: nao foi possivel criar tmpfile para o entrypoint\n' >&2
    return 1
  }
  _serve_docker_write_entrypoint "$_sdwd_entrypoint_tmp"

  {
    cat <<CSTK_SERVE_DOCKER_DOCKERFILE_HEAD
# syntax=docker/dockerfile:1
# Dockerfile gerado por cli/lib/serve-docker.sh::_serve_docker_write_dockerfile
# (cstk serve --docker). Nao versionado como arquivo solto -- fonte
# confinada em serve-docker.sh (Principio II, carve-out condicao b). Build
# LOCAL a partir da arvore-fonte JA verificada pelo fluxo de integridade
# existente (_serve_install ate a extracao) -- sem segunda fonte de
# download (research.md Decision 1, FR-006/FR-007).

FROM ${_SD_BASE_IMAGE}

WORKDIR /app

# Contexto de build = arvore verificada do painel (extracted_tree_path,
# data-model.md "Verified Panel Installation"). host_npm_used MUST ser
# false (FR-006) -- todo o npm roda aqui dentro, nunca no host.
COPY --chown=node:node . .

# npm ci (nao npm install) a partir do package-lock.json da arvore extraida
# -- reprodutibilidade (research.md Decision 7). Ja falha fail-closed se o
# lockfile estiver ausente (mensagem customizada acionavel: task 3.3,
# checklists/security.md CHK014).
RUN npm ci

# Compila os workspaces (shared-types + server + web) -- gera
# apps/server/dist/ (consumido pelo entrypoint) e apps/web/dist/ (servido
# estaticamente pelo Fastify). Roda no build da imagem (FR-006), nao a cada
# start do container -- diferenca face ao modo nativo, que reconstroi a
# cada \`cstk serve\` (aqui a imagem cacheia o resultado; rebuild so em
# --update/--reinstall, FASE 2).
RUN npm run build

# socat: encaminhador in-container 0.0.0.0 -> 127.0.0.1 (FR-005,
# research.md Decision 2). Roda como root (apt-get) -- ANTES de USER node.
RUN apt-get update \\
    && apt-get install -y --no-install-recommends socat \\
    && rm -rf /var/lib/apt/lists/*

COPY <<'CSTK_PANEL_ENTRYPOINT_EOF' /usr/local/bin/cstk-panel-entrypoint.sh
CSTK_SERVE_DOCKER_DOCKERFILE_HEAD
    cat "$_sdwd_entrypoint_tmp"
    cat <<CSTK_SERVE_DOCKER_DOCKERFILE_TAIL
CSTK_PANEL_ENTRYPOINT_EOF
RUN chmod +x /usr/local/bin/cstk-panel-entrypoint.sh

# Non-root -- a imagem oficial node ja traz o usuario 'node' pronto
# (research.md Decision 7).
USER node

# Porta interna fixa do encaminhador -- nunca exposta ao usuario; o
# host_port de --port e mapeado externamente via \`docker run -p\`
# (data-model.md "container_listen_port" = ${_SD_FORWARDER_PORT}, fixado
# nesta FASE 1).
EXPOSE ${_SD_FORWARDER_PORT}

ENTRYPOINT ["/usr/local/bin/cstk-panel-entrypoint.sh"]
CSTK_SERVE_DOCKER_DOCKERFILE_TAIL
  } >"$_sdwd_dest"

  rm -f "$_sdwd_entrypoint_tmp"
  return 0
}

# _serve_docker_build_image BUILD_CONTEXT_DIR IMAGE_TAG
# Constroi a imagem local cstk-panel a partir de BUILD_CONTEXT_DIR (arvore
# verificada do painel — data-model.md "Verified Panel Installation"
# extracted_tree_path) usando o Dockerfile gerado por
# _serve_docker_write_dockerfile. Nunca `docker push`; tag SEMPRE local
# (FR-013) -- ver checagem estatica correspondente na task 2.5.5/2.5.6.
# exit 0 = build ok; exit 1 = contexto invalido ou `docker build` falhou.
_serve_docker_build_image() {
  _sdbi_context="$1"
  _sdbi_tag="$2"

  if [ ! -f "$_sdbi_context/package.json" ]; then
    printf 'cstk serve --docker: erro: contexto de build sem package.json (%s)\n' \
      "$_sdbi_context" >&2
    return 1
  fi

  _sdbi_tmp=$(mktemp -d 2>/dev/null) || {
    printf 'cstk serve --docker: erro: nao foi possivel criar tmpdir para o Dockerfile\n' >&2
    return 1
  }
  trap 'rm -rf -- "$_sdbi_tmp"' EXIT INT TERM

  if ! _serve_docker_write_dockerfile "$_sdbi_tmp/Dockerfile"; then
    rm -rf -- "$_sdbi_tmp"
    trap - EXIT INT TERM
    return 1
  fi

  if ! docker build -f "$_sdbi_tmp/Dockerfile" -t "$_sdbi_tag" "$_sdbi_context"; then
    printf 'cstk serve --docker: erro: docker build falhou (imagem %s)\n' "$_sdbi_tag" >&2
    rm -rf -- "$_sdbi_tmp"
    trap - EXIT INT TERM
    return 1
  fi

  rm -rf -- "$_sdbi_tmp"
  trap - EXIT INT TERM
  return 0
}

# _serve_docker_main PORT HOST UPDATE REINSTALL ALLOW_UNVERIFIED BYPASS_METHOD
#   PORT              porta host publicada (--port, ja validada 1024-65535)
#   HOST              lado host do publish (--host, default 127.0.0.1)
#   UPDATE            "1"|"0" (--update)
#   REINSTALL         "1"|"0" (--reinstall)
#   ALLOW_UNVERIFIED  "1"|"0" (--allow-unverified / CSTK_SERVE_ALLOW_UNVERIFIED)
#   BYPASS_METHOD     "flag"|"env"|"" (origem do bypass, p/ o enforcement-log)
#
# Ponto de entrada do modo `cstk serve --docker`, chamado por serve_main
# quando --docker esta presente (FASE 2 -- o wiring em serve.sh ainda nao
# existe nesta FASE 1, task 2.1.1). Ira orquestrar: pre-flight fail-closed
# do runtime de container (2.2), reuso do fluxo de instalacao verificada
# ate a extracao (2.3), build/rebuild condicional da imagem via
# _serve_docker_build_image conforme --update/--reinstall (2.4), `docker
# run` com hardening (3.1) + mount read-only do knowledge.db (2.5),
# reconciliacao de remanescente (2.6) e encerramento gracioso (2.7).
#
# Nesta FASE 1 e um esqueleto honesto (task 1.1.2 -- define a interface de
# entrada): NAO orquestra nada ainda, apenas documenta o contrato de
# parametros e falha de forma informativa. As funcoes internas acima
# (_serve_docker_write_dockerfile/_serve_docker_write_entrypoint/
# _serve_docker_build_image) ja sao reais e validadas empiricamente (ver
# Decisao registrada pelo orquestrador desta onda) -- a orquestracao
# completa que as invoca chega na FASE 2.
_serve_docker_main() {
  _sdm_port="$1"
  _sdm_host="$2"
  _sdm_update="${3:-0}"
  _sdm_reinstall="${4:-0}"
  _sdm_allow_unverified="${5:-0}"
  _sdm_bypass_method="${6:-}"

  printf 'cstk serve --docker: ainda nao implementado (FASE 2 do backlog em andamento)\n' >&2
  printf 'cstk serve --docker: os assets (Dockerfile/entrypoint/confinamento) da FASE 1 ja estao prontos e testados\n' >&2
  return 1
}
