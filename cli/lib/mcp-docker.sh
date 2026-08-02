# mcp-docker.sh — uso de Docker confinado do servidor MCP de estado
# (feature state-mcp-server, FASE 5 task 5.2).
#
# **CONFINAMENTO DE `docker` (Constitution v1.3.0, Principio II, amendment
# 1.1.0 §carve-out condicao b)**: leitura adotada pelo operador em dec-074
# (resposta a block-005, task 5.1) — a condicao "um unico arquivo
# identificavel" e por PAR (dependencia, feature), com precedente em
# `cstk serve` -> `cli/lib/serve-docker.sh`. Este arquivo e o UNICO ponto
# de invocacao FUNCIONAL de `docker` (docker run/build/ps/stop/rm/inspect/
# exec/images/pull/network/volume/cp/kill/logs) desta feature
# (state-mcp-server). Mencoes literais da palavra "docker" em outros
# arquivos do toolkit (guards, comentarios, `cli/lib/mcp.sh`) NAO contam
# como referenciar a dependencia — apenas invocacao funcional conta.
# `cli/lib/serve-docker.sh` continua sendo o UNICO arquivo autorizado para
# a feature `panel-docker`; nenhuma consolidacao entre os dois arquivos e
# exigida (dec-074).
#
# Ref: docs/specs/state-mcp-server/contracts/mcp-session-lifecycle.md
#        §Contrato do container / §Montagens
#      docs/specs/state-mcp-server/plan.md §Seguranca (SEC-H2, SEC-M4)
#      docs/specs/state-mcp-server/tasks.md FASE 5 task 5.2
#      docs/specs/state-mcp-server/data-model.md §Entity: Orchestrator
#        Server Session (mcp-server.json)
#
# Espelha o precedente VERIFICADO `cli/lib/serve-docker.sh` (build local a
# partir de arvore ja presente no disco, hardening por default, `--rm` +
# reconciliacao idempotente por nome), com DUAS diferencas deliberadas:
#   1. Contexto de build e a arvore-fonte DESTE REPO (`mcp/state-server/`),
#      nao uma release baixada — nao ha fluxo de fetch/integridade aqui.
#   2. Nenhuma porta publicada (`-i`, transporte `stdio` — contracts/
#      mcp-session-lifecycle.md, research.md Decision 2/5). O container
#      sobe DETACHED (`-d -i`, stdin mantido aberto) para o launcher
#      (`mcp-launch.sh`, task 6.1.2 — FORA do escopo desta task) poder
#      `docker attach` mais tarde; a montagem/hardening/build ja e
#      responsabilidade completa deste arquivo.
#
# Funcoes publicas:
#   _mcp_docker_preflight
#   _mcp_docker_image_name
#   _mcp_docker_image_tag VERSION
#   _mcp_docker_container_name SESSION_ID
#   _mcp_docker_write_dockerfile DEST_PATH
#   _mcp_docker_build_image CONTEXT_DIR IMAGE_TAG
#   _mcp_docker_reconcile_container NAME
#   _mcp_docker_ensure_enforcement_log_file PATH
#   _mcp_docker_run CONTAINER_NAME IMAGE_TAG STATE_DIR_HOST SCRIPTS_DIR_HOST \
#                    ENFORCEMENT_LOG_HOST PROJECT_PATH TOKEN
#   _mcp_docker_stop CONTAINER_NAME
#
# POSIX sh puro. Sem bash-isms.

if [ -n "${_CSTK_MCP_DOCKER_LOADED:-}" ]; then
  return 0 2>/dev/null
fi
_CSTK_MCP_DOCKER_LOADED=1

if [ -n "${CSTK_LIB:-}" ] && [ -f "$CSTK_LIB/common.sh" ]; then
  # shellcheck source=./common.sh
  . "$CSTK_LIB/common.sh"
fi

# Imagem base node:22-alpine pinada por digest — MESMO digest ja em
# producao em cli/lib/serve-docker.sh::_SD_BASE_IMAGE (mesma imagem base;
# reaproveitar o digest evita uma segunda fonte de verdade divergente
# para a mesma tag upstream). [VERIFICADO: serve-docker.sh]
_MD_BASE_IMAGE="node:22-alpine@sha256:16e22a550f3863206a3f701448c45f7912c6896a62de43add43bb9c86130c3e2"

# piso ja vigente no toolkit para sqlite3 dentro do container (helpers do
# runtime exigem >= 3.45.1 no backend sqlite). [VERIFICADO:
# global/skills/agente-00c-runtime/scripts/state-backend.sh
# _SB_MIN_SQLITE_VERSION]
_MD_MIN_SQLITE_VERSION="3.45.1"

_MD_MANAGEMENT_LABEL="cstk.managed=mcp-state"
_MD_STOP_GRACE_SECONDS="5"

# Destinos de montagem DENTRO do container — MESMOS defaults ja
# implementados pelo servidor Node (mcp/state-server/src/runtime/exec.ts
# DEFAULT_SCRIPTS_DIR/DEFAULT_ENFORCEMENT_LOG_PATH), nunca reinventados
# aqui.
_MD_STATE_CONTAINER_DIR="/data/state"
_MD_SCRIPTS_CONTAINER_DIR="/opt/cstk/scripts"
_MD_ENFORCEMENT_LOG_CONTAINER_PATH="/data/enforcement-log.jsonl"

# _mcp_docker_image_name -> imprime o nome LOCAL da imagem (nunca aponta a
# registry remoto — FR-013, mesma disciplina de serve-docker.sh).
_mcp_docker_image_name() {
  printf 'cstk-mcp-state\n'
}

# _mcp_docker_image_tag VERSION -> imprime a tag local deterministica
# "cstk-mcp-state:<version>" (paridade com
# serve-docker.sh::_serve_docker_image_tag).
_mcp_docker_image_tag() {
  printf '%s:%s\n' "$(_mcp_docker_image_name)" "$1"
}

# _mcp_docker_container_name SESSION_ID -> imprime o nome do container
# dedicado desta execucao (contracts/mcp-session-lifecycle.md §Contrato do
# container: "cstk-mcp-state-<session_id>", um por execucao — FR-016).
_mcp_docker_container_name() {
  printf 'cstk-mcp-state-%s\n' "$1"
}

# _mcp_docker_preflight
# Pre-flight fail-closed (paridade com
# serve-docker.sh::_serve_docker_preflight, SC-006): verifica que o
# binario `docker` esta no PATH e que o daemon esta acessivel ANTES de
# qualquer operacao. exit 0 = pronto; exit 1 = bloqueado (mensagem
# acionavel ja emitida em stderr).
_mcp_docker_preflight() {
  if ! command -v docker >/dev/null 2>&1; then
    printf 'cstk mcp: erro: docker nao encontrado no PATH; instale o Docker Engine ou o Docker Desktop (https://docs.docker.com/get-docker/) e tente novamente\n' >&2
    return 1
  fi

  if ! docker info >/dev/null 2>&1; then
    printf 'cstk mcp: erro: docker esta instalado mas o daemon nao esta acessivel (parado, sem permissao, ou contexto invalido); inicie o Docker (Docker Desktop, ou "systemctl start docker" no Linux), confirme que seu usuario tem permissao (grupo "docker" no Linux) e tente novamente\n' >&2
    return 1
  fi

  return 0
}

# _mcp_docker_write_dockerfile DEST_PATH
# Escreve em DEST_PATH o Dockerfile de estagio unico do servidor MCP de
# estado (contracts/mcp-session-lifecycle.md §Contrato do container,
# plan.md SEC-M4). Sem toolchain de compilacao nativa: as dependencias
# (@modelcontextprotocol/sdk, zod) sao JS puro — diferenca deliberada
# frente ao multi-stage de serve-docker.sh (que compila better-sqlite3
# nativo). `jq`/`sqlite` sao exigidos pelos HELPERS POSIX que o servidor
# invoca via execFile (runtime/exec.ts), nao pelo servidor Node em si.
_mcp_docker_write_dockerfile() {
  _mdwd_dest="$1"

  cat <<CSTK_MCP_DOCKERFILE_EOF >"$_mdwd_dest"
# Dockerfile gerado por cli/lib/mcp-docker.sh::_mcp_docker_write_dockerfile
# (cstk mcp start). Nao versionado como arquivo solto -- fonte confinada
# em mcp-docker.sh (Principio II, carve-out condicao b, leitura por par
# dependencia+feature, dec-074). Build LOCAL a partir da arvore-fonte
# deste repo (mcp/state-server/) -- sem fetch remoto (transporte stdio,
# zero superficie de rede).

FROM $_MD_BASE_IMAGE

# jq + sqlite (>= $_MD_MIN_SQLITE_VERSION, piso ja vigente no toolkit):
# exigidos pelos helpers POSIX invocados via execFile (runtime/exec.ts),
# nao pelo processo Node em si. Versao pinada via apk (repositorio alpine
# ja fixa a versao por release da base).
RUN apk add --no-cache jq "sqlite>=$_MD_MIN_SQLITE_VERSION-r0"

WORKDIR /app

# Contexto de build = arvore-fonte de mcp/state-server/ (SEC-M4: primeira
# arvore Node do repo -- supply chain minima, sem segunda fonte externa).
COPY . .

# Fail-closed explicito (paridade com serve-docker.sh:356, CHK014): nunca
# degrada silenciosamente para \`npm install\` se o lockfile estiver
# ausente -- quebraria a garantia de reprodutibilidade de \`npm ci\`.
RUN test -f package-lock.json || { printf 'cstk mcp: erro fail-closed no build da imagem: package-lock.json ausente em mcp/state-server/; o build nunca degrada silenciosamente para npm install (reprodutibilidade)\n' >&2; exit 1; }

# SEC-M4: \`npm ci --ignore-scripts\` (nunca \`npm install\`) -- elimina
# lifecycle scripts arbitrarios de dependencia no build (A03/ASI04/
# CICD-SEC-3). As deps desta arvore (@modelcontextprotocol/sdk, zod) sao
# JS puro e nao exigem scripts de post-install para funcionar.
RUN npm ci --ignore-scripts

# Compila TypeScript -> dist/ (mesmo comando de \`npm run build\` do
# package.json).
RUN npm run build

# Non-root -- a imagem oficial node ja traz o usuario 'node' pronto
# (mesma disciplina de serve-docker.sh).
USER node

# Transporte stdio (research.md Decision 2/5): zero porta exposta, zero
# listener de rede -- diferenca deliberada frente a serve-docker.sh (que
# expõe \$_SD_FORWARDER_PORT).
ENTRYPOINT ["node", "dist/src/index.js"]
CSTK_MCP_DOCKERFILE_EOF
}

# _mcp_docker_build_image CONTEXT_DIR IMAGE_TAG
# Constroi a imagem local a partir de CONTEXT_DIR (esperado:
# mcp/state-server/ deste repo) usando o Dockerfile gerado por
# _mcp_docker_write_dockerfile. Nunca `docker push`; tag SEMPRE local
# (FR-013). exit 0 = build ok; exit 1 = contexto invalido ou `docker
# build` falhou.
_mcp_docker_build_image() {
  _mdbi_context="$1"
  _mdbi_tag="$2"

  if [ ! -f "$_mdbi_context/package.json" ]; then
    printf 'cstk mcp: erro: contexto de build sem package.json (%s)\n' \
      "$_mdbi_context" >&2
    return 1
  fi

  _mdbi_tmp=$(mktemp -d 2>/dev/null) || {
    printf 'cstk mcp: erro: nao foi possivel criar tmpdir para o Dockerfile\n' >&2
    return 1
  }
  trap 'rm -rf -- "$_mdbi_tmp"' EXIT INT TERM

  _mcp_docker_write_dockerfile "$_mdbi_tmp/Dockerfile"

  if ! docker build -f "$_mdbi_tmp/Dockerfile" -t "$_mdbi_tag" "$_mdbi_context"; then
    printf 'cstk mcp: erro: docker build falhou (imagem %s)\n' "$_mdbi_tag" >&2
    rm -rf -- "$_mdbi_tmp"
    trap - EXIT INT TERM
    return 1
  fi

  rm -rf -- "$_mdbi_tmp"
  trap - EXIT INT TERM
  return 0
}

# _mcp_docker_reconcile_container NAME
# Reconciliacao idempotente de um container remanescente de mesmo nome
# (paridade com serve-docker.sh::_serve_docker_reconcile_container):
# `docker rm -f` tolerando "No such container". Qualquer OUTRA falha
# (permissao negada, daemon caiu no meio) e reportada como impossivel.
# exit 0 = reconciliado (ou nada a reconciliar); exit 1 = impossivel.
_mcp_docker_reconcile_container() {
  _mdrc_name="$1"

  _mdrc_out=$(docker rm -f "$_mdrc_name" 2>&1)
  _mdrc_exit=$?

  if [ "$_mdrc_exit" -eq 0 ]; then
    return 0
  fi

  case "$_mdrc_out" in
    *"No such container"*)
      return 0
      ;;
    *)
      printf 'cstk mcp: erro: nao foi possivel reconciliar (remover) o container remanescente "%s"; verifique se seu usuario tem permissao para acessar o daemon Docker e se o daemon nao caiu no meio da operacao, depois tente novamente\n' \
        "$_mdrc_name" >&2
      return 1
      ;;
  esac
}

# _mcp_docker_ensure_enforcement_log_file PATH
# Garante que PATH existe como ARQUIVO (nunca diretorio) com permissao
# 600, ANTES do `docker run` que o monta (SEC-H2: bind-mount de arquivo
# inexistente faria o Docker criar um DIRETORIO no host — exatamente o
# que este helper existe para prevenir). Idempotente: nao trunca
# conteudo existente. exit 0 = arquivo pronto; exit 1 = PATH ja existe
# como diretorio, ou falha de IO.
_mcp_docker_ensure_enforcement_log_file() {
  _mdef_path="$1"

  if [ -d "$_mdef_path" ]; then
    printf 'cstk mcp: erro: %s ja existe como diretorio; o mount de enforcement-log.jsonl exige um ARQUIVO (SEC-H2)\n' \
      "$_mdef_path" >&2
    return 1
  fi

  _mdef_dir=$(dirname -- "$_mdef_path")
  mkdir -p "$_mdef_dir" 2>/dev/null || {
    printf 'cstk mcp: erro: nao foi possivel criar %s\n' "$_mdef_dir" >&2
    return 1
  }

  if [ ! -f "$_mdef_path" ]; then
    : >"$_mdef_path" 2>/dev/null || {
      printf 'cstk mcp: erro: nao foi possivel criar %s\n' "$_mdef_path" >&2
      return 1
    }
  fi

  chmod 600 "$_mdef_path" 2>/dev/null || :
  return 0
}

# _mcp_docker_run CONTAINER_NAME IMAGE_TAG STATE_DIR_HOST SCRIPTS_DIR_HOST \
#                  ENFORCEMENT_LOG_HOST PROJECT_PATH TOKEN
#
# `docker run -d -i` do container dedicado desta execucao — stdin mantido
# aberto (`-i`, sem `-t`) para o launcher (mcp-launch.sh, task 6.1.2)
# fazer `docker attach` mais tarde; NUNCA `-p` (zero porta publicada,
# stdio). Montagens EXATAS de contracts/mcp-session-lifecycle.md
# §Montagens — a lista E o perimetro de blast radius (FR-008); nenhuma
# outra montagem e permitida:
#   STATE_DIR_HOST        -> /data/state                    rw
#   SCRIPTS_DIR_HOST       -> /opt/cstk/scripts               ro
#   ENFORCEMENT_LOG_HOST   -> /data/enforcement-log.jsonl     rw (ARQUIVO,
#                             nunca o diretorio .claude -- SEC-H2)
# knowledge.db NUNCA montado (FR-013) -- ausencia por construcao, nao ha
# flag para monta-lo neste arquivo.
#
# Hardening herdado do precedente VERIFICADO
# (serve-docker.sh:712-724/contracts/mcp-session-lifecycle.md §Contrato do
# container): --init --rm --cap-drop ALL --security-opt no-new-privileges
# --read-only --tmpfs /tmp:rw,noexec,nosuid. --network nunca setado (sem
# rede alguma -- superficie zero, mais forte que --network none seria
# redundante pois nao ha -p nem --network host).
#
# exit 0 = container subiu; exit 1 = ENFORCEMENT_LOG_HOST nao e arquivo
# valido, ou `docker run` falhou (mensagem ja emitida em stderr).
_mcp_docker_run() {
  _mdr_name="$1"
  _mdr_image="$2"
  _mdr_state_dir="$3"
  _mdr_scripts_dir="$4"
  _mdr_enforcement_log="$5"
  _mdr_project_path="$6"
  _mdr_token="$7"

  if ! _mcp_docker_ensure_enforcement_log_file "$_mdr_enforcement_log"; then
    return 1
  fi

  _mdr_out=$(mktemp 2>/dev/null) || {
    printf 'cstk mcp: erro: nao foi possivel criar arquivo temporario\n' >&2
    return 1
  }

  if ! docker run -d \
        -i \
        --init \
        --rm \
        --name "$_mdr_name" \
        --label "$_MD_MANAGEMENT_LABEL" \
        -v "${_mdr_state_dir}:${_MD_STATE_CONTAINER_DIR}" \
        -v "${_mdr_scripts_dir}:${_MD_SCRIPTS_CONTAINER_DIR}:ro" \
        -v "${_mdr_enforcement_log}:${_MD_ENFORCEMENT_LOG_CONTAINER_PATH}" \
        -e "CSTK_MCP_PROJECT_PATH=${_mdr_project_path}" \
        -e "CSTK_MCP_SCRIPTS_DIR=${_MD_SCRIPTS_CONTAINER_DIR}" \
        -e "CSTK_MCP_ENFORCEMENT_LOG_PATH=${_MD_ENFORCEMENT_LOG_CONTAINER_PATH}" \
        -e "MCP_SESSION_TOKEN=${_mdr_token}" \
        --cap-drop ALL \
        --security-opt no-new-privileges \
        --read-only \
        --tmpfs /tmp:rw,noexec,nosuid,size=64m \
        "$_mdr_image" >"$_mdr_out" 2>&1
  then
    printf 'cstk mcp: erro: docker run falhou ao iniciar o servidor MCP de estado; verifique o daemon Docker (espaco em disco, permissoes) e tente novamente\n' >&2
    cat "$_mdr_out" >&2
    rm -f "$_mdr_out"
    return 1
  fi

  rm -f "$_mdr_out"
  return 0
}

# _mcp_docker_stop CONTAINER_NAME
# `docker stop -t 5` (mesmo grace de serve-docker.sh, alinhado ao modo
# nativo). Idempotente: parar o que ja esta parado ou inexistente e
# exit 0 (best-effort — paridade com o encerramento de serve-docker.sh).
_mcp_docker_stop() {
  docker stop -t "$_MD_STOP_GRACE_SECONDS" "$1" >/dev/null 2>&1 || :
  return 0
}
