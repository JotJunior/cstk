# mcp.sh — subcomando `cstk mcp` (feature state-mcp-server, FASE 1 fundacao
# + FASE 5 task 5.3 start/stop + task 5.4 gc).
#
# Ref: docs/specs/state-mcp-server/contracts/mcp-session-lifecycle.md
#        §CLI: `cstk mcp` / §`cstk mcp status` / §`cstk mcp start`/`stop` /
#        §Limpeza de containers orfaos (`cstk mcp gc`)
#      docs/specs/state-mcp-server/data-model.md
#        §Entity: Orchestrator Server Session
#      docs/specs/state-mcp-server/tasks.md FASE 1 task 1.4, FASE 5 tasks
#        5.3, 5.4
#
# `status`: reporta o descritor `<state-dir>/mcp-server.json` quando existe;
# sem `--state-dir`, resolve a execucao ativa do projeto-alvo pela MESMA
# precedencia do hook PreToolUse (agente-00c vence; entre feature-00c,
# menor short-name lexicografico —
# global/skills/agente-00c-runtime/hooks/pretooluse-bash-guard.sh). Essa
# precedencia e leitura de CONVENIENCIA, read-only — nunca roteia mutacao
# (isso e por token de capacidade, ver
# global/skills/agente-00c-runtime/scripts/mcp-session.sh resolve; SEC-H3,
# contracts/mcp-session-lifecycle.md §SEC-H3).
#
# `start`/`stop`: invocados PELO COMMAND PAI (nao pelo operador no caminho
# normal). Este arquivo apenas ORQUESTRA — toda invocacao FUNCIONAL de
# `docker` fica confinada em cli/lib/mcp-docker.sh (Principio II carve-out
# condicao b, dec-074). `start` gera o token de capacidade (session_id,
# CSPRNG >= 128 bits), builda/reusa a imagem, sobe o container e roda o
# health check ANTES de reportar sucesso (FR-011); qualquer falha (docker
# ausente, daemon fora do ar, build/run falho, health check falho) grava
# `mode=bash-fallback` e retorna exit 3 SEM abortar a execucao (FR-007).
# O descritor e escrito ANTES do `docker run` (nao depois): o processo PID1
# do servidor (mcp/state-server/src/index.ts::bootstrap) resolve a propria
# sessao no startup e precisa achar `<state-dir>/mcp-server.json` com o
# `session_id` ja no disco.
#
# `status --live` (task 5.3.3, FR-010): quando a sessao esta ativa e
# mode=docker, roda um health check DE VERDADE (mesmo handshake MCP real de
# `start`) em vez de so ecoar o descritor — usado pelo command pai em cada
# `-resume` para reverificar saude SEM reiniciar o container.
#
# `gc` (task 5.4, CHK064): detecta e remove containers gerenciados cujo
# state-dir dono esta em estado terminal ou nao existe mais — ver comentario
# de _mcp_cmd_gc abaixo para o racional completo (fail-safe: nunca remove
# por suposicao).
#
# `install` (FASE 6 task 6.1): registra a entrada ESTATICA e UNICA
# `mcpServers.cstk-state` no `.mcp.json` do projeto-alvo, apontando para o
# entrypoint stdio `mcp-launch.sh` (resolvido do catalogo — mesmo helper
# `_mcp_runtime_script_path` ja usado por status/start/stop/gc). Roda UMA
# VEZ por projeto, nao por execucao (research.md Decision 2). Recusa
# `--project-path $HOME` (mesma guarda de `cstk hooks install`,
# `hooks.sh` linha ~414). Merge via `merge_settings`/`print_paste_block`
# de `hooks.sh` — jq permanece CONFINADO aquele arquivo (Constitution
# carve-out condicao b); `mcp.sh` NUNCA chama `jq` diretamente.
#
# Subcomandos:
#   cstk mcp status [--state-dir DIR] [--project-path PATH] [--live]
#   cstk mcp start --state-dir DIR
#   cstk mcp stop --state-dir DIR
#   cstk mcp gc [--dry-run]
#   cstk mcp install [--project-path PATH] [--dry-run]
#
# Saida (stdout, uma chave por linha — mesmo estilo de `state-backend.sh
# resolve`):
#   status=active|stopped|unavailable
#   reason=<motivo>            # presente quando != active
#   container=<nome>|-
#   session_id=<id>|-
#   mode=docker|bash-fallback|-
#
# Exit codes (status):
#   0 consulta bem-sucedida (inclusive status=unavailable — NAO e erro)
#   1 erro inesperado (path invalido)
#   2 uso incorreto
#
# Exit codes (start/stop):
#   0 sucesso (start: mode=docker ativo; stop: parado ou ja estava parado)
#   1 erro inesperado (jq ausente, --state-dir invalido, IO)
#   2 uso incorreto
#   3 indisponivel (start): mode=bash-fallback gravado, NAO e erro fatal —
#     o pai deve seguir com o caminho Bash de hoje (FR-007)
#
# Exit codes (install):
#   0 entrada mcpServers.cstk-state criada/ja presente (idempotente), ou
#     --dry-run
#   1 erro de IO/merge, ou catalogo sem mcp-launch.sh
#   2 uso incorreto
#   3 recusa: --project-path aponta para $HOME
#
# POSIX sh puro. Sem bash-isms. `jq` NAO e referenciado neste arquivo —
# `install` delega merge de JSON a hooks.sh (UNICO arquivo autorizado a
# invocar jq, Constitution carve-out condicao b).

if [ -n "${_CSTK_MCP_LOADED:-}" ]; then
  return 0 2>/dev/null
fi
_CSTK_MCP_LOADED=1

if [ -n "${CSTK_LIB:-}" ] && [ -f "$CSTK_LIB/common.sh" ]; then
  # shellcheck source=./common.sh
  . "$CSTK_LIB/common.sh"
fi

# mcp-docker.sh: UNICO arquivo autorizado a invocar `docker` funcionalmente
# (dec-074). Sourced aqui (nao so dentro de start/stop) porque `status` nao
# precisa dele, mas start/stop sempre precisam e o custo de source e
# desprezivel (guard _CSTK_MCP_DOCKER_LOADED evita dupla-carga).
if [ -n "${CSTK_LIB:-}" ] && [ -f "$CSTK_LIB/mcp-docker.sh" ]; then
  # shellcheck source=./mcp-docker.sh
  . "$CSTK_LIB/mcp-docker.sh"
fi

# hooks.sh: UNICO arquivo do toolkit autorizado a referenciar `jq`
# (Constitution carve-out condicao b). `install` reusa merge_settings/
# detect_jq/print_paste_block de la — nenhum mecanismo de merge JSON novo
# (mesma mecanica ja usada por `cstk hooks install`/`cstk install`).
if [ -n "${CSTK_LIB:-}" ] && [ -f "$CSTK_LIB/hooks.sh" ]; then
  # shellcheck source=./hooks.sh
  . "$CSTK_LIB/hooks.sh"
fi

# _mcp_runtime_script_path NAME -> imprime o path do script NAME do
# runtime agente-00c-runtime. Mesmo padrao de _state_migrate_script_path
# (cli/lib/state.sh): (1) PATH; (2) layout de repo relativo a CSTK_LIB
# (cli/lib -> ../../global/skills/agente-00c-runtime/scripts); (3) layout
# instalado em ~/.claude. Necessario porque testes/CI rodam o CLI da
# arvore do repo (CSTK_LIB=cli/lib), sem o runtime em ~/.claude.
_mcp_runtime_script_path() {
  _mrs_name=$1
  if command -v "$_mrs_name" >/dev/null 2>&1; then
    command -v "$_mrs_name"
    return 0
  fi
  if [ -n "${CSTK_LIB:-}" ]; then
    _mrs_repo="$CSTK_LIB/../../global/skills/agente-00c-runtime/scripts/$_mrs_name"
    if [ -f "$_mrs_repo" ]; then
      printf '%s\n' "$_mrs_repo"
      return 0
    fi
  fi
  _mrs_default="${HOME:-/tmp}/.claude/skills/agente-00c-runtime/scripts/$_mrs_name"
  if [ -f "$_mrs_default" ]; then
    printf '%s\n' "$_mrs_default"
    return 0
  fi
  return 1
}

_mcp_is_active_status() {
  case "$1" in
    em_andamento | aguardando_humano) return 0 ;;
    *) return 1 ;;
  esac
}

# _mcp_detect_active_dir PROJECT_PATH -> imprime o state-dir da execucao
# ativa (precedencia agente-00c > menor short-name feature-00c) em stdout;
# stdout vazio se nenhuma execucao ativa. Read-only. Reusa a MESMA regra
# de precedencia de hooks/pretooluse-bash-guard.sh sem reimportar codigo
# (duplicacao textual e o padrao ja praticado pelos 3 consumidores
# existentes da regra: pretooluse-bash-guard.sh,
# posttooluse-agent-usage.sh, posttooluse-tool-call-tick.sh — nenhum dos
# tres a fatorou num helper compartilhado).
_mcp_detect_active_dir() {
  _mda_proj=$1
  _mda_rw=$(_mcp_runtime_script_path state-rw.sh) || return 0

  _mda_agente="$_mda_proj/.claude/agente-00c-state"
  if [ -f "$_mda_agente/state.json" ] || [ -f "$_mda_agente/state.db" ]; then
    _mda_status=$("$_mda_rw" get --state-dir "$_mda_agente" --field '.execution.status' 2>/dev/null) || _mda_status=""
    if _mcp_is_active_status "$_mda_status"; then
      printf '%s' "$_mda_agente"
      return 0
    fi
  fi

  _mda_feat_root="$_mda_proj/.claude/feature-00c-state"
  if [ -d "$_mda_feat_root" ]; then
    _mda_shorts=""
    for _mda_d in "$_mda_feat_root"/*/; do
      [ -d "$_mda_d" ] || continue
      { [ -f "${_mda_d}state.json" ] || [ -f "${_mda_d}state.db" ]; } || continue
      _mda_status=$("$_mda_rw" get --state-dir "${_mda_d%/}" --field '.execution.status' 2>/dev/null) || continue
      _mcp_is_active_status "$_mda_status" || continue
      _mda_shorts="${_mda_shorts}$(basename "$_mda_d")
"
    done
    if [ -n "$_mda_shorts" ]; then
      # Ordem lexicografica byte-wise (C locale), deterministica —
      # mesma disciplina de pretooluse-bash-guard.sh (CHK007).
      _mda_first=$(printf '%s' "$_mda_shorts" | LC_ALL=C sort | sed -n '1p')
      printf '%s' "$_mda_feat_root/$_mda_first"
      return 0
    fi
  fi

  return 0
}

# _mcp_print_unavailable REASON -> emite o bloco de 5 linhas com
# status=unavailable. Sempre exit 0 (contrato de nao-falha: unavailable
# nao e erro).
_mcp_print_unavailable() {
  printf 'status=unavailable\n'
  printf 'reason=%s\n' "$1"
  printf 'container=-\n'
  printf 'session_id=-\n'
  printf 'mode=-\n'
}

# _mcp_print_status_from_descriptor STATE_DIR [LIVE] -> le
# <STATE_DIR>/mcp-server.json (se existir) e emite o bloco de 5 linhas.
#
# LIVE="1" (task 5.3.3, FR-010): quando a sessao esta ativa E mode=docker,
# roda um health check de VERDADE (`_mcp_docker_healthcheck`, mesmo
# handshake MCP real ponta a ponta de `cstk mcp start` — FR-011) em vez de
# so ecoar o descritor gravado em disco. NUNCA reinicia o container (FR-010:
# "reverifica saude SEM reiniciar") — so degrada o STATUS REPORTADO para
# unavailable/health-timeout se a sonda falhar; o descritor em disco (e o
# container, se ainda vivo) permanecem intocados. Sem LIVE (default), o
# comportamento e IDENTICO ao de antes desta task — leitura pura do
# descritor, zero custo de latencia/Docker.
_mcp_print_status_from_descriptor() {
  _desc="$1/mcp-server.json"
  _live="${2:-}"
  if [ ! -f "$_desc" ]; then
    _mcp_print_unavailable "no-active-execution"
    return 0
  fi
  if ! command -v jq >/dev/null 2>&1; then
    _mcp_print_unavailable "jq-ausente"
    return 0
  fi
  _stopped=$(jq -r '.stopped_at // ""' "$_desc" 2>/dev/null) || _stopped=""
  _container=$(jq -r '.container_name // "-"' "$_desc" 2>/dev/null) || _container="-"
  _sid=$(jq -r '.session_id // "-"' "$_desc" 2>/dev/null) || _sid="-"
  _mode=$(jq -r '.mode // "-"' "$_desc" 2>/dev/null) || _mode="-"

  if [ -n "$_stopped" ]; then
    printf 'status=stopped\n'
    printf 'reason=stopped\n'
    printf 'container=%s\n' "$_container"
    printf 'session_id=%s\n' "$_sid"
    printf 'mode=%s\n' "$_mode"
    return 0
  fi

  if [ "$_live" = "1" ] && [ "$_mode" = "docker" ] && [ "$_container" != "-" ] \
     && command -v _mcp_docker_healthcheck >/dev/null 2>&1; then
    if ! _mcp_docker_healthcheck "$_container" 2>/dev/null; then
      printf 'status=unavailable\n'
      printf 'reason=health-timeout\n'
      printf 'container=%s\n' "$_container"
      printf 'session_id=%s\n' "$_sid"
      printf 'mode=%s\n' "$_mode"
      return 0
    fi
  fi

  printf 'status=active\n'
  printf 'reason=-\n'
  printf 'container=%s\n' "$_container"
  printf 'session_id=%s\n' "$_sid"
  printf 'mode=%s\n' "$_mode"
}

# _mcp_gen_token -> imprime em stdout um token hex de 32 bytes (256 bits,
# >= 128 bits exigidos por data-model.md §Entity: Orchestrator Server
# Session) lido de /dev/urandom (fonte CSPRNG). exit 1 se /dev/urandom
# indisponivel (ambiente restrito) — nunca degrada para fonte fraca
# (date/PID/etc.), pois o session_id e um TOKEN DE CAPACIDADE (SEC-H3),
# nao um mero identificador.
_mcp_gen_token() {
  if [ ! -r /dev/urandom ]; then
    printf 'cstk mcp: erro: /dev/urandom indisponivel — nao e possivel gerar session_id CSPRNG\n' >&2
    return 1
  fi
  od -An -N32 -tx1 /dev/urandom 2>/dev/null | tr -d ' \t\n'
}

# _mcp_resolve_execution_kind STATE_DIR -> imprime "KIND<TAB>SHORT_NAME"
# (SHORT_NAME="-" quando agente-00c). Deriva do LAYOUT do state-dir (mesma
# disciplina do restante deste arquivo — agente-00c-state/ vs
# feature-00c-state/<short>/), nunca de conteudo do state.json (o layout e
# a fonte de verdade estrutural; o schema de state.json entre os dois
# layouts nao e identico).
_mcp_resolve_execution_kind() {
  _mrek_dir=$1
  _mrek_base=$(basename -- "$_mrek_dir")
  _mrek_parent=$(basename -- "$(dirname -- "$_mrek_dir")")
  _mrek_tab=$(printf '\t')
  if [ "$_mrek_parent" = "feature-00c-state" ]; then
    printf 'feature-00c%s%s\n' "$_mrek_tab" "$_mrek_base"
    return 0
  fi
  printf 'agente-00c%s-\n' "$_mrek_tab"
}

# _mcp_context_dir -> imprime o path do contexto de build (arvore-fonte
# mcp/state-server/, com package.json) em stdout; exit 1 se nao encontrado.
# Mesmo padrao de resolucao em 3 camadas de _mcp_runtime_script_path:
#   1. override explicito $CSTK_MCP_CONTEXT_DIR (testes/dev)
#   2. layout de repo relativo a CSTK_LIB (cli/lib -> ../../mcp/state-server)
#   3. layout instalado (~/.claude/mcp/state-server) — reservado para
#      quando o build/instalacao passar a empacotar a arvore-fonte; ainda
#      nao provisionado por install.sh/build-release.sh nesta fase.
_mcp_context_dir() {
  if [ -n "${CSTK_MCP_CONTEXT_DIR:-}" ] && [ -f "${CSTK_MCP_CONTEXT_DIR}/package.json" ]; then
    printf '%s\n' "$CSTK_MCP_CONTEXT_DIR"
    return 0
  fi
  if [ -n "${CSTK_LIB:-}" ]; then
    _mcd_repo="$CSTK_LIB/../../mcp/state-server"
    if [ -f "$_mcd_repo/package.json" ]; then
      printf '%s\n' "$_mcd_repo"
      return 0
    fi
  fi
  _mcd_default="${HOME:-/tmp}/.claude/mcp/state-server"
  if [ -f "$_mcd_default/package.json" ]; then
    printf '%s\n' "$_mcd_default"
    return 0
  fi
  return 1
}

# _mcp_write_descriptor STATE_DIR SESSION_ID KIND SHORT_NAME TARGET_PATH \
#                        CONTAINER MODE UNAVAIL_REASON STARTED_AT STOPPED_AT
# Escreve <STATE_DIR>/mcp-server.json (chmod 600 — data-model.md). Campos
# "-" viram `null` no JSON (SHORT_NAME, CONTAINER, UNAVAIL_REASON,
# STOPPED_AT sao nullable pelo schema).
_mcp_write_descriptor() {
  _mwd_state_dir="$1"
  _mwd_session_id="$2"
  _mwd_kind="$3"
  _mwd_short="$4"
  _mwd_target_path="$5"
  _mwd_container="$6"
  _mwd_mode="$7"
  _mwd_unavail="$8"
  _mwd_started_at="$9"
  shift 9
  _mwd_stopped_at="$1"

  jq -n \
    --arg sid "$_mwd_session_id" \
    --arg kind "$_mwd_kind" \
    --arg short "$_mwd_short" \
    --arg sd "$_mwd_state_dir" \
    --arg tp "$_mwd_target_path" \
    --arg cn "$_mwd_container" \
    --arg mode "$_mwd_mode" \
    --arg ur "$_mwd_unavail" \
    --arg sa "$_mwd_started_at" \
    --arg spa "$_mwd_stopped_at" \
    '{
      session_id: $sid,
      execution_kind: $kind,
      short_name: (if $short == "-" then null else $short end),
      state_dir: $sd,
      target_project_path: $tp,
      container_name: (if $cn == "-" then null else $cn end),
      mode: $mode,
      unavailable_reason: (if $ur == "-" then null else $ur end),
      started_at: $sa,
      stopped_at: (if $spa == "-" then null else $spa end)
    }' >"$_mwd_state_dir/mcp-server.json" || return 1
  chmod 600 "$_mwd_state_dir/mcp-server.json" 2>/dev/null || :
  return 0
}

_mcp_cmd_status() {
  _mcp_state_dir=""
  _mcp_project_path=""
  _mcp_live=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir) _mcp_state_dir=$2; shift 2 ;;
      --project-path) _mcp_project_path=$2; shift 2 ;;
      --live) _mcp_live="1"; shift ;;
      *)
        printf 'cstk mcp status: flag desconhecida: %s\n' "$1" >&2
        return 2
        ;;
    esac
  done

  if [ -n "$_mcp_state_dir" ]; then
    if [ ! -d "$_mcp_state_dir" ]; then
      printf 'cstk mcp status: --state-dir nao existe: %s\n' "$_mcp_state_dir" >&2
      return 1
    fi
    _mcp_print_status_from_descriptor "$_mcp_state_dir" "$_mcp_live"
    return 0
  fi

  if [ -n "$_mcp_project_path" ]; then
    if [ ! -d "$_mcp_project_path" ]; then
      printf 'cstk mcp status: --project-path nao existe: %s\n' "$_mcp_project_path" >&2
      return 1
    fi
    _mcp_dir=$(_mcp_detect_active_dir "$_mcp_project_path")
    if [ -z "$_mcp_dir" ]; then
      _mcp_print_unavailable "no-active-execution"
      return 0
    fi
    _mcp_print_status_from_descriptor "$_mcp_dir" "$_mcp_live"
    return 0
  fi

  printf 'cstk mcp status: forneca --state-dir DIR ou --project-path PATH\n' >&2
  return 2
}

# _mcp_cmd_start --state-dir DIR
#
# Ciclo completo (contracts/mcp-session-lifecycle.md §`cstk mcp start`):
#   preflight docker -> build/reuso de imagem -> reconcile de container
#   remanescente -> docker run -> health check ANTES de reportar sucesso
#   (FR-011) -> grava mcp-server.json.
#
# Qualquer etapa que falhar grava mode=bash-fallback + unavailable_reason
# e retorna exit 3 (indisponivel, NAO e erro fatal — FR-007): o command pai
# segue com o caminho Bash de hoje, zero regressao.
_mcp_cmd_start() {
  _mst_state_dir=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir) _mst_state_dir=$2; shift 2 ;;
      *)
        printf 'cstk mcp start: flag desconhecida: %s\n' "$1" >&2
        return 2
        ;;
    esac
  done
  if [ -z "$_mst_state_dir" ]; then
    printf 'cstk mcp start: forneca --state-dir DIR\n' >&2
    return 2
  fi
  if [ ! -d "$_mst_state_dir" ]; then
    printf 'cstk mcp start: --state-dir nao existe: %s\n' "$_mst_state_dir" >&2
    return 1
  fi
  if ! command -v jq >/dev/null 2>&1; then
    printf 'cstk mcp start: jq nao encontrado no PATH; instale jq (brew install jq | apt install jq)\n' >&2
    return 1
  fi
  if ! command -v _mcp_docker_preflight >/dev/null 2>&1; then
    printf 'cstk mcp start: mcp-docker.sh nao carregado (CSTK_LIB invalido?)\n' >&2
    return 1
  fi

  # path absoluto — mesma convencao do resto do descritor (state.json).
  _mst_state_dir=$(cd "$_mst_state_dir" && pwd) || {
    printf 'cstk mcp start: nao foi possivel resolver --state-dir\n' >&2
    return 1
  }

  _mst_rw=$(_mcp_runtime_script_path state-rw.sh) || _mst_rw=""
  _mst_target_path="-"
  if [ -n "$_mst_rw" ]; then
    _mst_target_path=$("$_mst_rw" get --state-dir "$_mst_state_dir" --field '.execution.target_project_path' 2>/dev/null) || _mst_target_path=""
    [ -n "$_mst_target_path" ] || _mst_target_path="-"
  fi

  _mst_kind_line=$(_mcp_resolve_execution_kind "$_mst_state_dir")
  _mst_kind=$(printf '%s' "$_mst_kind_line" | cut -f1)
  _mst_short=$(printf '%s' "$_mst_kind_line" | cut -f2)

  _mst_token=$(_mcp_gen_token) || return 1
  _mst_started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || _mst_started_at="1970-01-01T00:00:00Z"
  _mst_container=$(_mcp_docker_container_name "$_mst_token")

  # preflight (docker no PATH + daemon acessivel) — falha => bash-fallback.
  if ! _mcp_docker_preflight; then
    if command -v docker >/dev/null 2>&1; then
      _mst_reason="daemon-unreachable"
    else
      _mst_reason="docker-absent"
    fi
    _mcp_write_descriptor "$_mst_state_dir" "$_mst_token" "$_mst_kind" "$_mst_short" \
      "$_mst_target_path" "-" "bash-fallback" "$_mst_reason" "$_mst_started_at" "-"
    printf 'status=unavailable\n'
    printf 'reason=%s\n' "$_mst_reason"
    printf 'container=-\n'
    printf 'session_id=%s\n' "$_mst_token"
    printf 'mode=bash-fallback\n'
    return 3
  fi

  # contexto de build (arvore-fonte mcp/state-server/). Reason DISTINTO de
  # image-build-failed: aqui nada chegou a buildar — a fonte do servidor nao
  # esta instalada (fix pos-6.2.1: o tarball passou a empacotar
  # catalog/mcp/state-server e o install/update a espelhar em
  # ~/.claude/mcp/state-server; reason server-source-missing indica
  # instalacao antiga => rode `cstk update`).
  if ! _mst_context=$(_mcp_context_dir); then
    printf 'cstk mcp start: aviso: fonte do servidor (mcp/state-server/) nao instalada — rode `cstk update`; mode=bash-fallback\n' >&2
    _mcp_write_descriptor "$_mst_state_dir" "$_mst_token" "$_mst_kind" "$_mst_short" \
      "$_mst_target_path" "-" "bash-fallback" "server-source-missing" "$_mst_started_at" "-"
    printf 'status=unavailable\n'
    printf 'reason=server-source-missing\n'
    printf 'container=-\n'
    printf 'session_id=%s\n' "$_mst_token"
    printf 'mode=bash-fallback\n'
    return 3
  fi

  _mst_version=$(jq -r '.version // "0.0.0"' "$_mst_context/package.json" 2>/dev/null) || _mst_version="0.0.0"
  _mst_image=$(_mcp_docker_image_tag "$_mst_version")

  if ! _mcp_docker_build_image "$_mst_context" "$_mst_image"; then
    _mcp_write_descriptor "$_mst_state_dir" "$_mst_token" "$_mst_kind" "$_mst_short" \
      "$_mst_target_path" "-" "bash-fallback" "image-build-failed" "$_mst_started_at" "-"
    printf 'status=unavailable\n'
    printf 'reason=image-build-failed\n'
    printf 'container=-\n'
    printf 'session_id=%s\n' "$_mst_token"
    printf 'mode=bash-fallback\n'
    return 3
  fi

  # reconcilia eventual container remanescente do mesmo nome (colisao
  # praticamente impossivel com token CSPRNG, mas barato e seguro).
  _mcp_docker_reconcile_container "$_mst_container" || :

  _mst_scripts_dir=$(_mcp_runtime_script_path state-rw.sh 2>/dev/null) || _mst_scripts_dir=""
  if [ -n "$_mst_scripts_dir" ]; then
    _mst_scripts_dir=$(dirname -- "$_mst_scripts_dir")
  else
    _mst_scripts_dir="${HOME:-/tmp}/.claude/skills/agente-00c-runtime/scripts"
  fi
  _mst_enforcement_log="${_mst_target_path}/.claude/enforcement-log.jsonl"

  # GRAVA O DESCRITOR ANTES do `docker run` (achado empirico validado nesta
  # task, sonda: `docker logs` do container recem-subido acusando
  # "mcp-session: resolve: SESSION_MISMATCH" quando a escrita acontecia
  # DEPOIS): o processo PID1 (mcp/state-server/src/index.ts::bootstrap) faz
  # `resolveActiveSession` UMA vez no proprio startup, fail-closed — ele
  # PRECISA encontrar `<state-dir>/mcp-server.json` com o `session_id`
  # batendo o token ja no disco no instante em que o container sobe. Se o
  # descritor so existisse apos o `docker run` retornar, o servidor real
  # (e a instancia efemera do healthcheck) sempre veriam SESSION_MISMATCH.
  # mode=docker gravado aqui reflete a fase "starting" do ciclo de vida
  # (data-model.md §State Transitions) — nao ha valor de enum dedicado
  # para "starting"; o campo `mode` so distingue transporte final
  # (docker|bash-fallback), e o status derivado (active/stopped) vem de
  # `stopped_at`, nao de `mode`.
  _mcp_write_descriptor "$_mst_state_dir" "$_mst_token" "$_mst_kind" "$_mst_short" \
    "$_mst_target_path" "$_mst_container" "docker" "-" "$_mst_started_at" "-"

  if ! _mcp_docker_run "$_mst_container" "$_mst_image" "$_mst_state_dir" \
        "$_mst_scripts_dir" "$_mst_enforcement_log" "$_mst_target_path" "$_mst_token"; then
    _mcp_write_descriptor "$_mst_state_dir" "$_mst_token" "$_mst_kind" "$_mst_short" \
      "$_mst_target_path" "-" "bash-fallback" "container-start-failed" "$_mst_started_at" "-"
    printf 'status=unavailable\n'
    printf 'reason=container-start-failed\n'
    printf 'container=-\n'
    printf 'session_id=%s\n' "$_mst_token"
    printf 'mode=bash-fallback\n'
    return 3
  fi

  # health check ANTES de reportar sucesso (FR-011: "antes da primeira
  # chamada de ferramenta"). Falha => derruba o container recem-subido
  # (evita orfao saudavel-de-mentirinha) e cai para bash-fallback.
  if ! _mcp_docker_healthcheck "$_mst_container"; then
    _mcp_docker_stop "$_mst_container"
    _mcp_write_descriptor "$_mst_state_dir" "$_mst_token" "$_mst_kind" "$_mst_short" \
      "$_mst_target_path" "-" "bash-fallback" "health-timeout" "$_mst_started_at" "-"
    printf 'status=unavailable\n'
    printf 'reason=health-timeout\n'
    printf 'container=-\n'
    printf 'session_id=%s\n' "$_mst_token"
    printf 'mode=bash-fallback\n'
    return 3
  fi

  _mcp_write_descriptor "$_mst_state_dir" "$_mst_token" "$_mst_kind" "$_mst_short" \
    "$_mst_target_path" "$_mst_container" "docker" "-" "$_mst_started_at" "-"
  printf 'status=active\n'
  printf 'reason=-\n'
  printf 'container=%s\n' "$_mst_container"
  printf 'session_id=%s\n' "$_mst_token"
  printf 'mode=docker\n'
  return 0
}

# _mcp_cmd_stop --state-dir DIR
#
# Idempotente (contracts/mcp-session-lifecycle.md §`cstk mcp stop`): parar
# o que ja esta parado, ou --state-dir sem descritor algum, e exit 0. So
# invoca `docker stop` quando mode=docker E stopped_at ainda nulo.
_mcp_cmd_stop() {
  _msp_state_dir=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir) _msp_state_dir=$2; shift 2 ;;
      *)
        printf 'cstk mcp stop: flag desconhecida: %s\n' "$1" >&2
        return 2
        ;;
    esac
  done
  if [ -z "$_msp_state_dir" ]; then
    printf 'cstk mcp stop: forneca --state-dir DIR\n' >&2
    return 2
  fi
  if [ ! -d "$_msp_state_dir" ]; then
    printf 'cstk mcp stop: --state-dir nao existe: %s\n' "$_msp_state_dir" >&2
    return 1
  fi
  if ! command -v jq >/dev/null 2>&1; then
    printf 'cstk mcp stop: jq nao encontrado no PATH; instale jq (brew install jq | apt install jq)\n' >&2
    return 1
  fi

  _msp_desc="$_msp_state_dir/mcp-server.json"
  if [ ! -f "$_msp_desc" ]; then
    return 0
  fi

  _msp_stopped=$(jq -r '.stopped_at // ""' "$_msp_desc" 2>/dev/null) || _msp_stopped=""
  if [ -n "$_msp_stopped" ]; then
    return 0
  fi

  _msp_mode=$(jq -r '.mode // "-"' "$_msp_desc" 2>/dev/null) || _msp_mode="-"
  _msp_container=$(jq -r '.container_name // "-"' "$_msp_desc" 2>/dev/null) || _msp_container="-"
  if [ "$_msp_mode" = "docker" ] && [ "$_msp_container" != "-" ] && [ -n "$_msp_container" ]; then
    _mcp_docker_stop "$_msp_container"
  fi

  _msp_stopped_at=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || _msp_stopped_at="1970-01-01T00:00:00Z"
  _msp_tmp=$(mktemp 2>/dev/null) || {
    printf 'cstk mcp stop: erro: nao foi possivel criar arquivo temporario\n' >&2
    return 1
  }
  jq --arg spa "$_msp_stopped_at" '.stopped_at = $spa' "$_msp_desc" >"$_msp_tmp" \
    && mv "$_msp_tmp" "$_msp_desc" \
    && chmod 600 "$_msp_desc" 2>/dev/null || :
  rm -f "$_msp_tmp" 2>/dev/null || :
  return 0
}

# _mcp_cmd_gc [--dry-run]
#
# GC de containers orfaos (task 5.4, CHK064,
# contracts/mcp-session-lifecycle.md §Ciclo de vida ->
# §Limpeza de containers orfaos). Detecta containers gerenciados (label
# $_MD_MANAGEMENT_LABEL) cujo state-dir dono (label
# cstk.mcp.state_dir, gravado por _mcp_docker_run desde a task 5.4)
# esta em estado TERMINAL (execution.status=concluida|abortada) ou nao
# existe mais no disco, e os remove (`docker rm -f`, via
# _mcp_docker_reconcile_container, ja idempotente).
#
# Decisao (5.4.1): fecha a lacuna que o lock (state-lock.sh) deixa em
# aberto de proposito (research.md: "sem deteccao de stale") em vez de
# replica-la aqui -- o custo de nao limpar e assimetrico: um lock preso
# so bloqueia a PROXIMA tentativa de aquisicao (falha rapida e visivel,
# exit 3), mas um container orfao consome CPU/memoria/disco do host
# indefinidamente e sem sinal nenhum para o operador. Dedicado (nao uma
# extensao de `status`) porque remover container e uma acao MUTANTE --
# `status` documenta-se como leitura pura.
#
# Fail-safe por design: container SEM o label cstk.mcp.state_dir (gerado
# por uma versao anterior a esta task, ou por qualquer origem que nao
# _mcp_docker_run) NUNCA e removido aqui -- sem o label nao ha como
# confirmar que o state-dir dono chegou a estado terminal, e a ausencia
# de evidencia nunca vira remocao (Principio VI: nunca supor). Idem
# quando a leitura de status falha (state-rw.sh indisponivel/erro): o
# container e preservado (--dry-run mental por padrao), nunca removido
# por suposicao.
#
# --dry-run: reporta o que SERIA removido (action=would-remove) sem
# chamar `docker rm -f`.
#
# Saida (stdout, uma linha por container):
#   action=removed|would-remove|remove-failed name=<container> reason=<motivo> state_dir=<path>
#   action=kept name=<container> reason=ativo:<status>|status-indisponivel state_dir=<path>
#   action=skipped name=<container> reason=sem-label
# Linha final:
#   summary=examined:N removed:R kept:K skipped:S
#
# exit 0 SEMPRE (best-effort/nao-fatal, mesma disciplina de `status`):
# docker ausente/daemon indisponivel = nada a fazer, nao e erro.
_mcp_cmd_gc() {
  _mgc_dry_run=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --dry-run) _mgc_dry_run="1"; shift ;;
      *)
        printf 'cstk mcp gc: flag desconhecida: %s\n' "$1" >&2
        return 2
        ;;
    esac
  done

  if ! command -v _mcp_docker_list_managed >/dev/null 2>&1; then
    printf 'cstk mcp gc: mcp-docker.sh nao carregado (CSTK_LIB invalido?)\n' >&2
    return 1
  fi

  if ! _mcp_docker_preflight 2>/dev/null; then
    printf 'summary=docker-indisponivel examined:0 removed:0 kept:0 skipped:0\n'
    return 0
  fi

  _mgc_rw=$(_mcp_runtime_script_path state-rw.sh) || _mgc_rw=""

  _mgc_list_file=$(mktemp 2>/dev/null) || {
    printf 'cstk mcp gc: erro: nao foi possivel criar arquivo temporario\n' >&2
    return 1
  }
  _mcp_docker_list_managed >"$_mgc_list_file" 2>/dev/null || :

  _mgc_examined=0
  _mgc_removed=0
  _mgc_kept=0
  _mgc_skipped=0
  _mgc_tab=$(printf '\t')

  # `while read ... < arquivo` (redirecao, NUNCA pipe) para os contadores
  # sobreviverem fora do loop -- um pipe rodaria o corpo num subshell e
  # descartaria todo incremento (mesmo padrao ja usado no runtime: ver
  # state-backend.sh::_sb_read_config_from, commit-mode.sh).
  while IFS="$_mgc_tab" read -r _mgc_name _mgc_sd; do
    [ -n "$_mgc_name" ] || continue
    _mgc_examined=$((_mgc_examined + 1))
    _mgc_action="kept"
    _mgc_reason="status-indisponivel"

    if [ -z "$_mgc_sd" ] || [ "$_mgc_sd" = "-" ]; then
      _mgc_action="skipped"
      _mgc_reason="sem-label"
    elif [ ! -d "$_mgc_sd" ]; then
      _mgc_action="orphan"
      _mgc_reason="state-dir-ausente"
    elif [ ! -f "$_mgc_sd/state.json" ] && [ ! -f "$_mgc_sd/state.db" ]; then
      _mgc_action="orphan"
      _mgc_reason="state-dir-sem-estado"
    elif [ -n "$_mgc_rw" ]; then
      _mgc_status=$("$_mgc_rw" get --state-dir "$_mgc_sd" --field '.execution.status' 2>/dev/null) || _mgc_status=""
      case "$_mgc_status" in
        concluida | abortada)
          _mgc_action="orphan"
          _mgc_reason="terminal:$_mgc_status"
          ;;
        em_andamento | aguardando_humano)
          _mgc_action="kept"
          _mgc_reason="ativo:$_mgc_status"
          ;;
        *)
          _mgc_action="kept"
          _mgc_reason="status-indisponivel"
          ;;
      esac
    fi

    case "$_mgc_action" in
      orphan)
        if [ -n "$_mgc_dry_run" ]; then
          printf 'action=would-remove name=%s reason=%s state_dir=%s\n' \
            "$_mgc_name" "$_mgc_reason" "$_mgc_sd"
          _mgc_removed=$((_mgc_removed + 1))
        elif _mcp_docker_reconcile_container "$_mgc_name" 2>/dev/null; then
          printf 'action=removed name=%s reason=%s state_dir=%s\n' \
            "$_mgc_name" "$_mgc_reason" "$_mgc_sd"
          _mgc_removed=$((_mgc_removed + 1))
        else
          printf 'action=remove-failed name=%s reason=%s state_dir=%s\n' \
            "$_mgc_name" "$_mgc_reason" "$_mgc_sd"
        fi
        ;;
      skipped)
        printf 'action=skipped name=%s reason=%s\n' "$_mgc_name" "$_mgc_reason"
        _mgc_skipped=$((_mgc_skipped + 1))
        ;;
      *)
        printf 'action=kept name=%s reason=%s state_dir=%s\n' \
          "$_mgc_name" "$_mgc_reason" "$_mgc_sd"
        _mgc_kept=$((_mgc_kept + 1))
        ;;
    esac
  done <"$_mgc_list_file"
  rm -f "$_mgc_list_file" 2>/dev/null || :

  printf 'summary=ok examined:%d removed:%d kept:%d skipped:%d\n' \
    "$_mgc_examined" "$_mgc_removed" "$_mgc_kept" "$_mgc_skipped"
  return 0
}

# _mcp_cmd_install [--project-path PATH] [--dry-run]
#
# Registra a entrada ESTATICA `mcpServers.cstk-state` em `<PATH>/.mcp.json`
# (contracts/mcp-session-lifecycle.md §`cstk mcp install`). Roda uma vez
# por projeto, nao por execucao. `command` aponta para `mcp-launch.sh`
# resolvido do catalogo via `_mcp_runtime_script_path` (mesma resolucao
# PATH -> repo -> ~/.claude ja usada pelos demais subcomandos). Sem
# `env` interpolado (task 1.2: sintaxe de expansao em .mcp.json e
# [NAO-VERIFICADO] — mcp-launch.sh descobre tudo do disco/PATH).
#
# Merge via hooks.sh (target vence em conflito — mesma politica de
# merge_settings): entrada ja presente e equivalente => idempotente,
# exit 0. Sem jq, imprime bloco para colagem manual (print_paste_block)
# em vez de falhar — carve-out de dep opcional preservado.
_mcp_cmd_install() {
  _mci_project_path="."
  _mci_dry_run=""

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --project-path) _mci_project_path=$2; shift 2 ;;
      --dry-run) _mci_dry_run="1"; shift ;;
      *)
        printf 'cstk mcp install: flag desconhecida: %s\n' "$1" >&2
        return 2
        ;;
    esac
  done

  if [ ! -d "$_mci_project_path" ]; then
    printf 'cstk mcp install: --project-path nao e diretorio: %s\n' "$_mci_project_path" >&2
    return 1
  fi

  # Normaliza para path absoluto (resolve symlinks/relativos), no mesmo
  # espirito de `cstk hooks install` — sem depender de `realpath` (nem
  # todo ambiente POSIX tem).
  _mci_abs=$(CDPATH= cd -- "$_mci_project_path" 2>/dev/null && pwd -P) || {
    printf 'cstk mcp install: nao consegui resolver %s\n' "$_mci_project_path" >&2
    return 1
  }

  if [ -n "${HOME:-}" ] && [ "$_mci_abs" = "${HOME%/}" ]; then
    printf 'cstk mcp install: --project-path aponta para $HOME — recusado.\n' >&2
    printf 'cstk mcp install: cstk-state e escopo de PROJETO; aponte para a raiz de um projeto-alvo.\n' >&2
    return 3
  fi

  _mci_launcher=$(_mcp_runtime_script_path mcp-launch.sh) || {
    printf 'cstk mcp install: mcp-launch.sh nao encontrado no catalogo (rode "cstk install" ou "cstk update")\n' >&2
    return 1
  }

  _mci_target="$_mci_abs/.mcp.json"

  if [ -n "$_mci_dry_run" ]; then
    printf 'cstk mcp install: [dry-run] registraria mcpServers.cstk-state em %s -> %s\n' \
      "$_mci_target" "$_mci_launcher"
    return 0
  fi

  _mci_tmp_src=$(mktemp "${TMPDIR:-/tmp}/cstk-mcp-install.XXXXXX") || {
    printf 'cstk mcp install: mktemp falhou\n' >&2
    return 1
  }

  # Forma da entrada [contracts/mcp-session-lifecycle.md §`cstk mcp
  # install`]: chaves type/command/args conforme doc oficial do .mcp.json.
  # POSIX puro (sem jq) — o payload e estatico, sem dado dinamico alem do
  # path resolvido do launcher.
  cat > "$_mci_tmp_src" <<MCPJSON
{
  "mcpServers": {
    "cstk-state": {
      "type": "stdio",
      "command": "$_mci_launcher",
      "args": []
    }
  }
}
MCPJSON

  if ! detect_jq; then
    print_paste_block "$_mci_target" "$_mci_tmp_src"
    rm -f "$_mci_tmp_src" 2>/dev/null || :
    printf 'cstk mcp install: jq ausente — cole manualmente o bloco acima em %s\n' "$_mci_target" >&2
    return 0
  fi

  if ! merge_settings "$_mci_target" "$_mci_tmp_src"; then
    rm -f "$_mci_tmp_src" 2>/dev/null || :
    printf 'cstk mcp install: merge falhou para %s\n' "$_mci_target" >&2
    return 1
  fi

  rm -f "$_mci_tmp_src" 2>/dev/null || :
  printf 'cstk mcp install: mcpServers.cstk-state registrado em %s\n' "$_mci_target"
  return 0
}

_mcp_usage() {
  cat <<'HELP'
cstk mcp — operacoes sobre o servidor MCP de estado das execucoes 00c

USO:
  cstk mcp status [--state-dir DIR] [--project-path PATH] [--live]
      Reporta status=active|stopped|unavailable sem inspecionar Docker
      diretamente. Sem --state-dir, resolve a execucao ativa do
      projeto-alvo pela mesma precedencia do hook PreToolUse (consulta de
      conveniencia, read-only — nunca usada para roteamento de mutacao).
      Com --live (FR-010), quando mode=docker roda um health check DE
      VERDADE em vez de so ecoar o descritor — usado em cada -resume para
      reverificar saude SEM reiniciar o container.

  cstk mcp start --state-dir DIR
      Invocado PELO COMMAND PAI (nao pelo operador). Builda/reusa a
      imagem, sobe o container dedicado e roda o health check ANTES de
      reportar sucesso (FR-011). Falha em qualquer etapa (docker ausente,
      daemon fora do ar, build/run falho, health timeout) grava
      mode=bash-fallback em mcp-server.json e retorna exit 3 — NAO e erro
      fatal, o pai segue com o caminho Bash de hoje (FR-007).

  cstk mcp stop --state-dir DIR
      Invocado PELO COMMAND PAI. Para o container (grace 5s) e preenche
      stopped_at. Idempotente: parar o que ja esta parado, ou --state-dir
      sem descritor algum, e exit 0.

  cstk mcp gc [--dry-run]
      GC de containers orfaos (task 5.4, CHK064): remove containers
      gerenciados cujo state-dir esta em estado terminal
      (concluida/abortada) ou nao existe mais. Container sem label de
      state-dir NUNCA e removido (fail-safe). --dry-run so reporta, sem
      remover. Best-effort: docker indisponivel e exit 0, nao erro.

  cstk mcp install [--project-path PATH] [--dry-run]
      Registra a entrada estatica mcpServers.cstk-state em
      <PATH>/.mcp.json, apontando para mcp-launch.sh do catalogo. Roda
      uma vez por projeto. Idempotente: entrada ja presente e
      equivalente nao gera erro. Recusa --project-path $HOME (exit 3).
      Sem jq, imprime bloco para colagem manual em vez de falhar.

EXIT CODES (status):
  0 consulta bem-sucedida (inclusive status=unavailable)
  1 erro inesperado
  2 uso incorreto

EXIT CODES (start/stop):
  0 sucesso
  1 erro inesperado (jq ausente, --state-dir invalido, IO)
  2 uso incorreto
  3 indisponivel (so em start): mode=bash-fallback gravado, nao fatal

EXIT CODES (gc):
  0 sempre (best-effort; ver linha summary= no stdout)
  1 erro inesperado (mcp-docker.sh nao carregado, IO de tmpfile)
  2 uso incorreto

EXIT CODES (install):
  0 entrada criada/ja presente (idempotente), ou --dry-run
  1 erro de IO/merge, ou catalogo sem mcp-launch.sh
  2 uso incorreto
  3 recusa: --project-path aponta para $HOME
HELP
}

mcp_main() {
  _mcp_sub="${1:-}"
  [ "$#" -ge 1 ] && shift || :

  case "$_mcp_sub" in
    ''|-h|--help|help)
      _mcp_usage
      return 0
      ;;
    status)
      _mcp_cmd_status "$@"
      return $?
      ;;
    start)
      _mcp_cmd_start "$@"
      return $?
      ;;
    stop)
      _mcp_cmd_stop "$@"
      return $?
      ;;
    gc)
      _mcp_cmd_gc "$@"
      return $?
      ;;
    install)
      _mcp_cmd_install "$@"
      return $?
      ;;
    *)
      printf 'cstk mcp: subcomando desconhecido: %s\n' "$_mcp_sub" >&2
      printf 'Subcomandos validos: status, start, stop, gc, install\n' >&2
      return 2
      ;;
  esac
}
