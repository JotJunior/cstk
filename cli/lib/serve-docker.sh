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
# tests/cstk/test_serve-docker.sh via assercoes de conteudo — hermeticas, sem
# daemon Docker real no harness; a validacao empirica de build/run reais
# (tasks 1.2.7/1.3.5) foi EXECUTADA e CONFIRMADA nesta wave — ver nota mais
# abaixo e dec-037):
#   _serve_docker_image_tag PANEL_VERSION
#     Imprime a tag local deterministica da imagem (data-model.md "Panel
#     Image" image_tag). SEMPRE local — nunca registry remoto (FR-013).
#   _serve_docker_write_entrypoint DEST_PATH
#     Escreve o script de entrypoint (painel + encaminhador socat + trap de
#     sinal) em DEST_PATH. Fonte UNICA do conteudo — tambem consumida por
#     _serve_docker_write_dockerfile (heredoc BuildKit `COPY <<EOF`), para
#     nao duplicar o script em dois lugares.
#   _serve_docker_write_dockerfile DEST_PATH
#     Escreve o Dockerfile MULTI-STAGE completo (dec-037, supersede dec-011)
#     em DEST_PATH. Base `node:22-alpine` (musl) fixada por digest nos DOIS
#     estagios; o modulo nativo better-sqlite3 (sem prebuild musl) e compilado
#     do fonte no estagio de build (apk python3/make/g++) e o binding viaja
#     para o runtime via COPY --from=build; nunca versionado como arquivo
#     solto no repositorio — gerado sob demanda, confinado aqui.
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
# gerado usa heredocs em COPY (`COPY <<'EOF' ... EOF`) para embutir o
# entrypoint sem depender de um segundo arquivo no contexto de build (mantem
# o contexto intocado — extracted_tree_path permanece exatamente a arvore
# verificada, sem mutacao). NAO emitimos a diretiva `# syntax=docker/
# dockerfile:1`: o frontend BUILTIN do BuildKit (Docker >= 23) ja suporta
# heredocs nativamente, e o `# syntax` forcaria o daemon a PUXAR a imagem de
# frontend `docker/dockerfile:1` do registry ANTES de qualquer RUN — um pull
# que o `--network=host` do build NAO cobre (roda no caminho de pull do
# daemon, nao na rede de build). Omitir a diretiva remove essa dependencia
# de rede e torna o build mais hermetico (verificado empiricamente nesta
# wave: com a diretiva o build pendura em "resolve image config for docker/
# dockerfile:1"; sem ela, o frontend builtin constroi o heredoc e o build
# completa — dec-037).
#
# Estado da validacao empirica (Constitution VI — nao mascarar o que nao foi
# confirmado; agora CONFIRMADO): nesta wave (dec-037) o `docker build
# --network=host` da imagem alpine multi-stage foi executado de VERDADE e
# completou (exit 0) — better-sqlite3 compilou p/ musl no estagio de build
# (ldd do `better_sqlite3.node` aponta `libc.musl-aarch64.so.1`; `node -e
# require('better-sqlite3')` + create/insert/select retornou OK) e `npm run
# build` gerou apps/web/dist + apps/server/dist. O container rodou com
# `docker run --init`: o painel subiu (bind 127.0.0.1:3001) e um `curl` na
# porta publicada do host retornou HTTP 200 servindo o SPA (o encaminhador
# socat 0.0.0.0:8080 -> 127.0.0.1:3001 funciona). `docker stop` encerrou em
# ~0s com exit 0 (o trap `_cstk_term_handler` propagou TERM a node+socat;
# nao houve fallback de SIGKILL nem processo zumbi — tini como PID 1 via
# --init). Ou seja, as tasks 1.2.3/1.2.7/1.3.3/1.3.5 estao VERIFICADAS com
# evidencia real (ver dec-037). Nota historica: com a base glibc anterior
# (node:20-bookworm-slim, dec-011) o daemon deste ambiente pendurava no pull
# da base; a mudanca p/ alpine (bases ja cacheadas) + remocao da diretiva
# `# syntax` (que forcava pull do frontend) tornou o build possivel aqui.
#
# FASE 3 (task 3.1.2 — validacao empirica do hardening completo, RISCO #1):
# nesta wave o container rodou com o CONJUNTO INTEIRO de flags de hardening
# de producao (`--cap-drop ALL --security-opt no-new-privileges --read-only
# --tmpfs /tmp:rw,noexec,nosuid,size=64m --init --rm`) e o KNOWLEDGE.DB REAL
# (`~/.claude/cstk/`, WAL, com sidecars `-shm`/`-wal` pre-existentes) montado
# `:ro` — nao um fixture. Resultado: o painel + Fastify subiram e
# permaneceram estaveis (sem crash/restart) SEM nenhum ajuste adicional de
# `--tmpfs`/path gravavel alem do `/tmp` ja presente no codigo — nao havia
# nada mais para descobrir empiricamente aqui (Fastify usa pino->stdout,
# sem arquivo de log; nenhuma outra escrita em runtime). `GET /api/v1/health`
# e `GET /api/v1/overview` (ambos batem em `openDb({readonly:true})` sobre o
# mount `:ro`, ver apps/server/src/db/open.ts) retornaram HTTP 200 com
# `dbReachable:true`/`quickCheck:true`/dados NAO-vazios (executions=54,
# waves=693, decisions=2960 — conferidos byte-a-byte contra `sqlite3
# knowledge.db "SELECT count(*)..."` rodado no HOST, mesmos numeros). Ou
# seja: leitura WAL read-only sobre bind mount `:ro` SEM `immutable=1`
# (confirmado inalcancavel via better-sqlite3 — ver comentario em
# apps/server/src/db/open.ts) FUNCIONA na pratica, sem torn read/
# SQLITE_CANTOPEN — RISCO #1 EMPIRICAMENTE DISPROVEN sob este hardening.
# `--read-only` confirmado REAL (nao so declarado): `touch` dentro do
# container falhou com "Read-only file system" tanto no rootfs (/app) quanto
# no MESMO mount `:ro` do knowledge.db; `/tmp` (tmpfs) aceitou escrita
# normalmente; `id`/`whoami` confirmaram uid=1000(node), nao-root. Container
# encerrado via `docker stop` (exit 0, sem residuo — `--rm`). Evidencia
# completa registrada como Decisao pelo orquestrador desta wave (task 3.1).
# Contribui adiante para a verificacao formal de RISCO #1 na FASE 5 (tasks.md
# 5.1) — este achado e forte evidencia confirmatoria, nao substitui aquela
# tarefa (escopo formal + campo `wal_readonly_verified` do data-model ficam
# para a FASE 5).

if [ "${_SERVE_DOCKER_LOADED:-}" = "1" ]; then
  return 0
fi
_SERVE_DOCKER_LOADED=1

# Porta fixa do encaminhador dentro do container (nunca exposta ao usuario).
_SD_FORWARDER_PORT="8080"
# Porta fixa do painel dentro do container (config.ts L80 default).
_SD_PANEL_INTERNAL_PORT="3001"

# Base da imagem (build E runtime): node:22-alpine (musl — dec-037, supersede
# dec-011), fixada por digest (nao tag flutuante — CHK013/security). A base
# alpine casa `engines.node >=20.0.0` (package.json L28; node 22 satisfaz) e
# mantem a imagem final slim; better-sqlite3 (modulo nativo, sem prebuild
# musl) e COMPILADO do fonte no estagio de build (apk add python3/make/g++)
# e o binding resultante viaja para o runtime via COPY --from=build (mesmo
# ABI: os dois estagios usam ESTA mesma base). Digest lido do proprio cache
# local (`docker inspect node:22-alpine --format '{{index .RepoDigests 0}}'`
# — fonte rastreavel, nunca inventado; Constitution VI) e resolvido a partir
# do cache SEM pull (probe real desta wave: `#N ... CACHED`, sem contato com
# registry).
#
# Processo de atualizacao do digest (task 3.2.3 — quando a base precisar de
# patch de seguranca; NUNCA copiar um digest de outra fonte que nao seja
# resolvido ao vivo, Constitution VI):
#   1. `docker pull node:22-alpine` (ou a tag major/minor vigente) para
#      trazer a imagem mais recente da mesma linha `node:22-alpine`.
#   2. `docker inspect node:22-alpine --format '{{index .RepoDigests 0}}'`
#      para ler o NOVO digest resolvido de verdade (mesmo comando usado para
#      fixar o valor atual acima — fonte rastreavel).
#   3. Se a atualizacao trocar a linha MAJOR/MINOR da tag (ex.: 22 -> 24),
#      revalidar contra `engines.node >=20.0.0` (package.json da arvore do
#      painel) antes de prosseguir — nao presumir compatibilidade.
#   4. Substituir o valor de `_SD_BASE_IMAGE` abaixo (UNICA linha-fonte; os
#      dois estagios do Dockerfile gerado a referenciam via variavel, entao
#      um digest desatualizado nunca fica divergente entre build/runtime).
#   5. Rebuildar localmente (`_serve_docker_build_image` ou
#      `cstk serve --docker --reinstall`) e reexecutar a validacao empirica
#      de hardening (tasks.md 3.1.2 — subir com o conjunto completo de
#      `--cap-drop`/`--read-only`/etc. e confirmar que o painel + o
#      encaminhador socat continuam funcionais; uma base nova pode mudar
#      paths graváveis assumidos pelo runtime).
#   6. `./tests/run.sh test_serve-docker` — o teste de pin
#      (`scenario_dockerfile_pins_base_by_digest_not_floating_tag`) so
#      confirma o FORMATO (`@sha256:` de 64 hex), nao a atualidade; a
#      atualidade e responsabilidade deste processo manual.
#   7. Registrar a troca no CHANGELOG.md (motivo — ex.: CVE/patch de
#      seguranca — e o novo digest) para nao virar divida tecnica silenciosa.
_SD_BASE_IMAGE="node:22-alpine@sha256:16e22a550f3863206a3f701448c45f7912c6896a62de43add43bb9c86130c3e2"

# Nome/label deterministicos do container (data-model.md "Containerized
# Panel Instance" [a fixar], FIXADOS nesta FASE 2 — dec pendente de registro
# pelo orquestrador): chave de idempotencia = uma instancia do modo
# alternativo por host (FR-012-INFRA-IDEMP), sem TTL. `docker rm -f
# $_SD_CONTAINER_NAME` a cada invocacao (idempotente) reconcilia qualquer
# remanescente antes de subir um novo.
_SD_CONTAINER_NAME="cstk-panel"
_SD_MANAGEMENT_LABEL="cstk.managed=serve"

# Diretorio ONDE o mount read-only do indice de conhecimento e montado
# DENTRO do container (data-model.md "Knowledge DB Mount" container_target
# [a fixar]). Caminho interno arbitrario (nao ha contrato externo sobre
# ele — o painel resolve o arquivo exclusivamente via a env
# CSTK_KNOWLEDGE_DB, nunca por convencao de path fixo).
_SD_KDB_CONTAINER_DIR="/data/knowledge-db"

# Grace period (segundos) do `docker stop -t` no encerramento gracioso —
# alinhado ao grace de 5s ja em producao no modo nativo
# (_serve_shutdown, serve.sh L103-123, research.md Decision 6).
_SD_STOP_GRACE_SECONDS="5"

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
# Escreve em DEST_PATH o Dockerfile MULTI-STAGE alpine do modo `cstk serve
# --docker` (dec-037, supersede dec-011; data-model.md "Panel Image"). O
# entrypoint e embutido via heredoc BuildKit (`COPY <<'EOF' ... EOF`),
# reusando o MESMO conteudo de _serve_docker_write_entrypoint — nao ha COPY
# relativo ao contexto de build para o entrypoint, entao extracted_tree_path
# (a arvore verificada) nunca e mutada por este processo.
#
# Contrato do Dockerfile (todas as linhas aterradas — ver cabecalho do
# arquivo e research.md Decision 1/2/7):
#   ESTAGIO build (AS build):
#     FROM node:22-alpine@sha256:... AS build   musl, digest fixo (nao tag)
#     RUN apk add python3 make g++              toolchain p/ compilar
#                                                better-sqlite3 (sem prebuild
#                                                musl) — SO no build
#     WORKDIR /app + COPY . .                   contexto = arvore verificada
#     RUN test -f package-lock.json || ...      fail-closed explicito (task
#                                                3.3, CHK014): aborta com
#                                                mensagem cstk acionavel ANTES
#                                                de `npm ci` se o lockfile
#                                                estiver ausente -- nunca
#                                                degrada para `npm install`
#     RUN npm ci                                lockfile (nao npm install) —
#                                                reprodutibilidade (Decision 7)
#     RUN npm run build                         compila shared-types+server+web
#                                                (gera apps/server/dist/ e
#                                                apps/web/dist/, consumidos em
#                                                runtime pelo entrypoint/painel)
#   ESTAGIO runtime (slim — sem toolchain de build):
#     FROM node:22-alpine@sha256:...            mesma base/ABI musl
#     RUN apk add socat                         encaminhador (Decision 2);
#                                                roda ANTES de USER node (apk
#                                                exige root)
#     COPY --from=build /app /app               arvore construida (node_modules
#                                                com better-sqlite3 ja compilado
#                                                p/ musl + dist dos workspaces)
#     COPY heredoc entrypoint + chmod +x
#     USER node                                 non-root (Decision 7)
#     EXPOSE 8080                               porta fixa do encaminhador
#     ENTRYPOINT [entrypoint script]
_serve_docker_write_dockerfile() {
  _sdwd_dest="$1"

  _sdwd_entrypoint_tmp=$(mktemp 2>/dev/null) || {
    printf 'cstk serve --docker: erro: nao foi possivel criar tmpfile para o entrypoint\n' >&2
    return 1
  }
  _serve_docker_write_entrypoint "$_sdwd_entrypoint_tmp"

  # ATENCAO -- ARMADILHA REAL (encontrada empiricamente na wave da task 3.3):
  # o heredoc abaixo e DELIBERADAMENTE nao-quotado (\`<<CSTK_..._HEAD\`, sem
  # aspas no delimitador) para permitir a expansao de ${_SD_BASE_IMAGE}/
  # ${_SD_FORWARDER_PORT}. ISSO TAMBEM significa que QUALQUER crase (`) no
  # texto do heredoc dispara SUBSTITUICAO DE COMANDO DE VERDADE -- executada
  # AGORA, no HOST, durante a GERACAO do Dockerfile (nao dentro do container,
  # nao em build-time do Docker). Um bug real desta classe (crases sem
  # escapar num comentario novo) fez este gerador executar `npm install`/
  # `npm ci`/`cstk serve --docker` de verdade no host repetidas vezes,
  # causando explosao de processos. Toda crase dentro deste heredoc (HEAD e
  # TAIL, ate a linha ~389) MUST vir escapada (\` -- barra invertida antes da
  # crase) para virar texto literal no Dockerfile gerado. Ao editar/adicionar
  # comentarios aqui, gerar o Dockerfile e grep por crase NAO-escapada antes
  # de commitar: grep -n '`' cli/lib/serve-docker.sh | awk -F: '$1>=304 && $1<=389' —
  # qualquer ocorrencia sem \\ imediatamente antes e um risco de execucao real.
  {
    cat <<CSTK_SERVE_DOCKER_DOCKERFILE_HEAD
# Dockerfile gerado por cli/lib/serve-docker.sh::_serve_docker_write_dockerfile
# (cstk serve --docker). Nao versionado como arquivo solto -- fonte
# confinada em serve-docker.sh (Principio II, carve-out condicao b). Build
# LOCAL a partir da arvore-fonte JA verificada pelo fluxo de integridade
# existente (_serve_install ate a extracao) -- sem segunda fonte de
# download (research.md Decision 1, FR-006/FR-007). Multi-stage alpine
# (dec-037, supersede dec-011): o estagio de build compila o modulo nativo
# better-sqlite3 p/ musl; o runtime fica slim (so o necessario p/ rodar).
# Heredocs em COPY usam o frontend BUILTIN do BuildKit (Docker >= 23) -- sem
# diretiva \`# syntax\` (evita o pull do frontend externo; ver cabecalho).

# ---- Estagio de build: compila better-sqlite3 (musl) + workspaces ----
FROM ${_SD_BASE_IMAGE} AS build

# better-sqlite3 ^9.6.0 (dep de @cstk-panel/server) e modulo nativo e nao tem
# prebuild musl publicado -> compila do fonte. O toolchain (python3/make/g++)
# vive SO neste estagio; o runtime nao o carrega (imagem final slim).
RUN apk add --no-cache python3 make g++

WORKDIR /app

# Contexto de build = arvore verificada do painel (extracted_tree_path,
# data-model.md "Verified Panel Installation"). host_npm_used MUST ser
# false (FR-006) -- todo o npm roda aqui dentro, nunca no host.
COPY . .

# Fail-closed EXPLICITO (task 3.3.1/3.3.2, checklists/security.md CHK014):
# resolve a contradicao entre research.md Decision 1 ("condicionar a
# presenca de package-lock.json") e Decision 7 ("MUST usar npm ci
# incondicional") SEM presumir que o lockfile sera eterno em releases
# futuras do painel -- se ausente, o build MUST abortar com mensagem
# acionavel, e NUNCA degradar silenciosamente para \`npm install\` (que
# quebraria a garantia de reprodutibilidade de \`npm ci\`). \`npm ci\` sozinho
# ja falharia neste caso, mas com a mensagem generica do npm; este guard
# antecipa a checagem com uma mensagem no mesmo padrao das demais mensagens
# acionaveis de \`cstk serve --docker\` (CHK009 tabela de causa-raiz).
RUN test -f package-lock.json || { printf 'cstk serve --docker: erro fail-closed no build da imagem: package-lock.json ausente na arvore extraida do painel; o build nunca degrada silenciosamente para npm install (reprodutibilidade); reinstale com --reinstall ou verifique se esta release do cstk-panel publica o lockfile\n' >&2; exit 1; }

# npm ci (nao npm install) a partir do package-lock.json da arvore extraida
# -- reprodutibilidade (research.md Decision 7). O guard acima ja garante
# fail-closed com mensagem acionavel antes deste passo.
RUN npm ci

# Compila os workspaces (shared-types + server + web) -- gera
# apps/server/dist/ (consumido pelo entrypoint) e apps/web/dist/ (servido
# estaticamente pelo Fastify). Roda no build da imagem (FR-006), nao a cada
# start do container -- diferenca face ao modo nativo, que reconstroi a
# cada \`cstk serve\` (aqui a imagem cacheia o resultado; rebuild so em
# --update/--reinstall, FASE 2).
RUN npm run build

# ---- Estagio de runtime: slim, sem toolchain de build ----
FROM ${_SD_BASE_IMAGE}

# socat: encaminhador in-container 0.0.0.0 -> 127.0.0.1 (FR-005,
# research.md Decision 2). Roda como root (apk add) -- ANTES de USER node.
RUN apk add --no-cache socat

WORKDIR /app

# Arvore ja construida vinda do estagio de build: node_modules com o binding
# better-sqlite3 compilado p/ musl + dist dos workspaces. Runtime nao carrega
# o toolchain de compilacao -> imagem final slim. --chown=node:node porque o
# processo roda como 'node' (non-root) mais abaixo.
COPY --from=build --chown=node:node /app /app

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

# _serve_docker_source_dir PANEL_DIR
# Imprime o diretorio onde a arvore-fonte VERIFICADA do painel (extraida,
# SEM npm/node_modules -- FR-006/host_npm_used=false) fica cacheada entre
# invocacoes do modo alternativo, e que serve de contexto ao `docker
# build` (data-model.md "Verified Panel Installation" extracted_tree_path).
# Sibling do diretorio de instalacao NATIVO (PANEL_DIR) -- NUNCA o MESMO
# caminho: uma instalacao nativa ja em cache MUST permanecer intocada
# quando o modo alternativo roda pela primeira vez (US1 Acceptance
# Scenario 2).
_serve_docker_source_dir() {
  printf '%s/panel-docker-src\n' "$(dirname -- "$1")"
}

# _serve_docker_preflight
# Pre-flight fail-closed do runtime de container (FR-003/FR-004/SC-006):
# ANTES de qualquer operacao de rede, verifica (a) o binario esta no PATH
# e (b) o daemon esta acessivel. Nenhum dos dois passos faz I/O de rede
# (binario: lookup de PATH local; daemon: sonda contra o socket/named
# pipe local do proprio host) -- satisfaz SC-006 por construcao, nao por
# temporizador externo. Mensagens DISTINTAS e acionaveis para cada causa
# (CHK008/CHK009 -- citam a causa raiz e sugerem o proximo passo).
# exit 0 = runtime pronto para uso; exit 1 = bloqueado (mensagem ja
# emitida em stderr; NUNCA repassa stack cru do runtime ao usuario).
_serve_docker_preflight() {
  if ! command -v docker >/dev/null 2>&1; then
    printf 'cstk serve --docker: erro: docker nao encontrado no PATH; instale o Docker Engine ou o Docker Desktop (https://docs.docker.com/get-docker/) e rode novamente\n' >&2
    return 1
  fi

  # Sonda de daemon: `docker info` fala com o daemon LOCAL (socket/named
  # pipe, nunca rede) e retorna rapido com exit != 0 se ele estiver
  # parado, inacessivel por permissao, ou com contexto invalido
  # (research.md Decision 5 -- comando fixado nesta FASE 2). A saida
  # bruta e descartada -- so o exit code importa aqui.
  if ! docker info >/dev/null 2>&1; then
    printf 'cstk serve --docker: erro: docker esta instalado mas o daemon nao esta acessivel (parado, sem permissao, ou contexto invalido); inicie o Docker (Docker Desktop, ou "systemctl start docker" no Linux), confirme que seu usuario tem permissao (grupo "docker" no Linux) e tente novamente\n' >&2
    return 1
  fi

  return 0
}

# _serve_docker_kdb_host_dir
# Imprime o diretorio HOST que contem o knowledge.db a montar read-only
# (FR-008/FR-009): dirname de $CSTK_KNOWLEDGE_DB se setada (mesma
# resolucao do painel, config.ts L49), senao ~/.claude/cstk/ (config.ts
# L53, default do painel). Monta-se o DIRETORIO inteiro (nunca so o
# arquivo) por causa dos sidecars WAL -shm/-wal (research.md Decision 3)
# -- granularidade fixada em 2.5.3.
_serve_docker_kdb_host_dir() {
  if [ -n "${CSTK_KNOWLEDGE_DB:-}" ]; then
    dirname -- "$CSTK_KNOWLEDGE_DB"
  else
    printf '%s/.claude/cstk\n' "$HOME"
  fi
}

# _serve_docker_reconcile_container NAME
# Reconciliacao automatica de um container remanescente de mesmo nome
# (FR-012-INFRA-IDEMP, data-model.md "Reconcile pre-run"): `docker rm -f`
# tolerando "No such container" (idempotente -- cobre remanescente parado
# OU rodando, CHK002). Qualquer OUTRA falha (permissao negada ao daemon,
# daemon caiu no meio da operacao, container preso em estado "removing")
# e reportada como reconciliacao IMPOSSIVEL (checklists/infra.md CHK003):
# mensagem cstk acionavel, NUNCA o stack cru do runtime (US4 Acceptance
# Scenario 2). exit 0 = reconciliado (ou nada a reconciliar); exit 1 =
# impossivel (mensagem ja emitida em stderr).
_serve_docker_reconcile_container() {
  _sdrc_name="$1"

  # `|| _sdrc_exit=$?`: sob o `set -eu` do binario, `_x=$(cmd)` herda o exit
  # de `cmd` — sem isso um "No such container" abortaria a funcao quando
  # chamada fora de contexto condicional (classe da issue #139).
  _sdrc_exit=0
  _sdrc_out=$(docker rm -f "$_sdrc_name" 2>&1) || _sdrc_exit=$?

  if [ "$_sdrc_exit" -eq 0 ]; then
    return 0
  fi

  case "$_sdrc_out" in
    *"No such container"*)
      # Idempotente: nada remanescente para reconciliar.
      return 0
      ;;
    *)
      printf 'cstk serve --docker: erro: nao foi possivel reconciliar (remover) o container remanescente "%s"; verifique se seu usuario tem permissao para acessar o daemon Docker (grupo "docker" no Linux) e se o daemon nao caiu no meio da operacao, depois tente novamente\n' \
        "$_sdrc_name" >&2
      return 1
      ;;
  esac
}

# _serve_docker_shutdown: handler de sinal para SIGINT/SIGTERM (FR-011,
# paridade com _serve_shutdown em serve.sh). Emite `docker stop` com
# grace period alinhado ao nativo (5s, $_SD_STOP_GRACE_SECONDS) -- SIGTERM
# ao PID1 (tini) do container, que o entrypoint propaga a painel +
# encaminhador (_serve_docker_write_entrypoint), com SIGKILL de ultima
# instancia gerenciado pelo PROPRIO `docker stop -t` (nao precisamos
# reimplementar o loop de poll manual do modo nativo -- o daemon ja faz
# isso). `--rm` remove o container apos o stop bem-sucedido -- nenhum
# `docker rm` adicional aqui (task 2.7.2). Best-effort (`|| :`): nunca
# deixa o handler falhar de forma ruidosa durante um encerramento.
_serve_docker_shutdown() {
  printf '\ncstk serve --docker: encerrando painel...\n'
  docker stop -t "$_SD_STOP_GRACE_SECONDS" "$_SD_CONTAINER_NAME" >/dev/null 2>&1 || :
}

# _serve_docker_main PORT HOST UPDATE REINSTALL ALLOW_UNVERIFIED BYPASS_METHOD
#   PORT              porta host publicada (--port, ja validada 1024-65535)
#   HOST              lado host do publish (--host, default 127.0.0.1)
#   UPDATE            "1"|"0" (--update)
#   REINSTALL         "1"|"0" (--reinstall)
#   ALLOW_UNVERIFIED  "1"|"0" (--allow-unverified / CSTK_SERVE_ALLOW_UNVERIFIED)
#   BYPASS_METHOD     "flag"|"env"|"" (origem do bypass, p/ o enforcement-log)
#
# Ponto de entrada do modo `cstk serve --docker` (FASE 2 -- orquestracao
# completa). PORT/HOST ja chegam validados pelo caller (serve_main roda a
# mesma validacao 1024-65535 + aviso de host nao-loopback ANTES do
# despacho -- research.md Decision 4/5, evita duplicar a logica aqui).
#
# Sequencia (contracts/cli-docker-mode.md "Sequencia"):
#   1. pre-flight fail-closed do runtime (2.2) -- ANTES de qualquer rede.
#   2. resolver arvore-fonte cacheada + imagem correspondente; decidir se
#      precisa (re)buscar/(re)construir conforme --update/--reinstall
#      (2.4, CHK012: --reinstall SEMPRE vence sobre --update).
#   3. reusar o fluxo de instalacao verificada ATE a extracao quando
#      precisar buscar (2.3, FR-007 -- mesmo mecanismo do modo nativo).
#   4. (re)construir a imagem local quando precisar (2.4).
#   5. reconciliar container remanescente pelo nome deterministico (2.6).
#   6. `docker run` com hardening + mount read-only do knowledge.db (2.5).
#   7. bloquear ate o container encerrar; trap host INT/TERM -> `docker
#      stop` gracioso (2.7).
#
# exit 0 = painel subiu e encerrou de forma limpa (ou o proprio processo
#   containerizado saiu 0); exit 1 = qualquer falha (pre-flight, download/
#   integridade, build, reconciliacao impossivel, `docker run` falhou) ou
#   o processo containerizado encerrou com exit != 0 (paridade com o modo
#   nativo, serve.sh L616-619).
_serve_docker_main() {
  _sdm_port="$1"
  _sdm_host="$2"
  _sdm_update="${3:-0}"
  _sdm_reinstall="${4:-0}"
  _sdm_allow_unverified="${5:-0}"
  _sdm_bypass_method="${6:-}"

  # 2.2 -- pre-flight fail-closed ANTES de qualquer operacao de rede
  # (FR-003/FR-004). Mensagem ja emitida por _serve_docker_preflight.
  if ! _serve_docker_preflight; then
    return 1
  fi

  # 2.3/2.4 -- resolver a arvore-fonte cacheada (se houver) e a imagem
  # correspondente. _sdm_panel_dir e o MESMO calculo que serve_main usa
  # para o modo nativo (CSTK_PANEL_DIR ou default) -- usado SOMENTE para
  # derivar o diretorio SIBLING do modo alternativo (nunca lido/escrito
  # diretamente, US1 Acceptance Scenario 2).
  _sdm_panel_dir="${CSTK_PANEL_DIR:-${HOME}/.local/share/cstk/panel}"
  _sdm_src_dir=$(_serve_docker_source_dir "$_sdm_panel_dir")

  _sdm_tag=""
  if [ -f "$_sdm_src_dir/.panel-version" ]; then
    _sdm_tag=$(cat "$_sdm_src_dir/.panel-version" 2>/dev/null | tr -d ' \n')
  fi
  _sdm_image=""
  if [ -n "$_sdm_tag" ]; then
    _sdm_image=$(_serve_docker_image_tag "$_sdm_tag")
  fi

  _sdm_need_fetch=0
  _sdm_need_build=0

  if [ "$_sdm_reinstall" = "1" ]; then
    # 2.4.3/2.4.4 (CHK012): --reinstall e SEMPRE incondicional e VENCE
    # sobre --update quando ambos presentes -- nem consultamos a rede de
    # --update aqui (paridade com o "ignores --update" ja documentado no
    # --help do modo nativo). Decisao de precedencia registrada pelo
    # orquestrador desta onda.
    printf 'cstk serve --docker: removendo instalacao containerizada existente (--reinstall)...\n'
    if [ -n "$_sdm_image" ]; then
      docker rmi -f "$_sdm_image" >/dev/null 2>&1 || :
    fi
    _sdm_need_fetch=1
    _sdm_need_build=1
  elif [ -z "$_sdm_tag" ] || [ -z "$_sdm_image" ] || ! docker image inspect "$_sdm_image" >/dev/null 2>&1; then
    # 2.4.1: imagem ausente (nunca instalada, ou removida por fora) ->
    # construir, independente de --update.
    _sdm_need_fetch=1
    _sdm_need_build=1
  elif [ "$_sdm_update" = "1" ]; then
    # 2.4.2: ja instalado -- checar release mais nova (best-effort; falha
    # de rede/API mantem a imagem instalada e AINDA sobe o painel,
    # paridade com o modo nativo, serve.sh L541-556).
    printf 'cstk serve --docker: verificando atualizacoes do painel...\n'
    _sdm_latest=$(_serve_latest_tag) || _sdm_latest=""
    if [ -n "$_sdm_latest" ] && [ "$_sdm_latest" != "$_sdm_tag" ]; then
      printf 'cstk serve --docker: atualizando painel: %s -> %s\n' "$_sdm_tag" "$_sdm_latest"
      _sdm_need_fetch=1
      _sdm_need_build=1
    else
      printf 'cstk serve --docker: painel ja esta na versao mais recente (%s)\n' "$_sdm_tag"
    fi
  fi

  # 2.3 -- reusar o MESMO mecanismo de download+allowlist+integridade
  # fail-closed do modo nativo, ate a extracao (FR-007). Sem npm no host
  # (FR-006/host_npm_used=false) -- _serve_download_verify_extract nunca
  # roda `npm install`. _sdm_src_dir e sempre recriado do zero por ela.
  if [ "$_sdm_need_fetch" = "1" ]; then
    if ! _serve_download_verify_extract "$_sdm_src_dir" "$_sdm_allow_unverified" "$_sdm_bypass_method"; then
      return 1
    fi
    _sdm_tag=$(cat "$_sdm_src_dir/.panel-version" 2>/dev/null | tr -d ' \n')
    _sdm_image=$(_serve_docker_image_tag "$_sdm_tag")
  fi

  if [ "$_sdm_need_build" = "1" ]; then
    printf 'cstk serve --docker: construindo imagem local (%s)...\n' "$_sdm_image"
    if ! _serve_docker_build_image "$_sdm_src_dir" "$_sdm_image"; then
      return 1
    fi
  else
    printf 'cstk serve --docker: usando imagem containerizada ja construida (%s)\n' "$_sdm_image"
  fi

  # 2.6 -- reconciliar remanescente ANTES de subir (idempotente, roda
  # SEMPRE -- nao so apos build/--reinstall).
  if ! _serve_docker_reconcile_container "$_SD_CONTAINER_NAME"; then
    return 1
  fi

  # 2.5.3 -- diretorio de dados do cstk no host, criado se ausente (US2
  # Acceptance Scenario 2: indice inexistente NUNCA pode falhar a
  # inicializacao; sem mkdir, `docker run -v` criaria o dir como root em
  # versoes antigas do daemon -- gotcha conhecido evitado aqui).
  _sdm_kdb_host_dir=$(_serve_docker_kdb_host_dir)
  mkdir -p "$_sdm_kdb_host_dir" 2>/dev/null || :

  printf 'cstk serve --docker: iniciando painel em http://%s:%s  (Ctrl+C para encerrar)\n' \
    "$_sdm_host" "$_sdm_port"

  # 2.7 -- trap registrado ANTES de subir o container: cobre tambem uma
  # eventual interrupcao durante o proprio `docker run -d` (data-model.md
  # "Interrupcao durante build/start") -- seguro mesmo se nada existe
  # ainda (docker stop de um nome inexistente falha silenciosamente,
  # `|| :` dentro de _serve_docker_shutdown).
  trap '_serve_docker_shutdown' INT TERM

  _sdm_run_out=$(mktemp 2>/dev/null) || {
    printf 'cstk serve --docker: erro: nao foi possivel criar arquivo temporario\n' >&2
    trap - INT TERM
    return 1
  }

  # 2.5/3.1 -- docker run: nome/label deterministicos (FR-012-INFRA-IDEMP),
  # publish no HOST informado (loopback por default, Decision 4), mount
  # RO do diretorio de dados (FR-008/FR-009), --init (tini PID1 -- Decision
  # 6) + --rm (happy-path sem vestigio), hardening por default (non-root
  # ja herdado da imagem -- USER node -- + cap-drop ALL/no-new-privileges/
  # rootfs read-only com tmpfs efemero para /tmp -- research.md Decision
  # 7). FR-013: nunca --network host, --privileged, nem push (checagem
  # estatica em tests/cstk/test_serve-docker.sh).
  if ! docker run -d \
        --init \
        --rm \
        --name "$_SD_CONTAINER_NAME" \
        --label "$_SD_MANAGEMENT_LABEL" \
        -p "${_sdm_host}:${_sdm_port}:${_SD_FORWARDER_PORT}" \
        -v "${_sdm_kdb_host_dir}:${_SD_KDB_CONTAINER_DIR}:ro" \
        -e "CSTK_KNOWLEDGE_DB=${_SD_KDB_CONTAINER_DIR}/knowledge.db" \
        --cap-drop ALL \
        --security-opt no-new-privileges \
        --read-only \
        --tmpfs /tmp:rw,noexec,nosuid,size=64m \
        "$_sdm_image" >"$_sdm_run_out" 2>&1
  then
    _sdm_run_err=$(cat "$_sdm_run_out" 2>/dev/null)
    rm -f "$_sdm_run_out"
    case "$_sdm_run_err" in
      *"port is already allocated"*|*"address already in use"*|*"Bind for"*)
        printf 'cstk serve --docker: erro: a porta %s ja esta em uso (por outro processo ou container); escolha outra com --port <N> ou libere a porta em uso e tente novamente\n' \
          "$_sdm_port" >&2
        ;;
      *)
        printf 'cstk serve --docker: erro: docker run falhou ao iniciar o painel containerizado; verifique o daemon Docker (espaco em disco, permissoes) e tente novamente\n' >&2
        ;;
    esac
    trap - INT TERM
    return 1
  fi
  rm -f "$_sdm_run_out"

  # Bloquear ate o container encerrar. `docker wait` roda em BACKGROUND
  # para o trap poder interromper o bloqueio via `docker stop` -- que faz
  # o `docker wait` retornar naturalmente (o evento que ele observa
  # aconteceu), sem race nem necessidade de matar o processo `docker
  # wait` diretamente. Mesma filosofia de _SERVE_NPM_PID/wait em
  # serve.sh, adaptada para o container.
  _sdm_wait_out=$(mktemp 2>/dev/null) || {
    printf 'cstk serve --docker: erro: nao foi possivel criar arquivo temporario\n' >&2
    docker stop -t "$_SD_STOP_GRACE_SECONDS" "$_SD_CONTAINER_NAME" >/dev/null 2>&1 || :
    trap - INT TERM
    return 1
  }

  docker wait "$_SD_CONTAINER_NAME" >"$_sdm_wait_out" 2>&1 &
  _SERVE_DOCKER_WAIT_PID=$!

  wait "$_SERVE_DOCKER_WAIT_PID"

  trap - INT TERM

  _sdm_container_exit=$(cat "$_sdm_wait_out" 2>/dev/null | tr -d ' \n')
  rm -f "$_sdm_wait_out"
  case "$_sdm_container_exit" in
    ''|*[!0-9]*) _sdm_container_exit=0 ;;
  esac

  # Mensagem de encerramento inesperado (paridade com serve.sh L616-619).
  if [ "$_sdm_container_exit" -ne 0 ]; then
    printf 'cstk serve --docker: painel encerrou inesperadamente (exit %d)\n' "$_sdm_container_exit" >&2
  fi

  return "$_sdm_container_exit"
}
