#!/bin/sh
# bloqueios.sh — gerencia ciclo de vida de BloqueioHumano (FASE 4.4).
#
# Ref: docs/specs/agente-00c/spec.md FR-015, FR-016
#      docs/specs/agente-00c/data-model.md §BloqueioHumano
#      docs/specs/agente-00c/tasks.md FASE 4.4
#
# Subcomandos:
#   bloqueios.sh register --state-dir DIR --decisao-id DEC
#       --pergunta TEXT --contexto-para-resposta TEXT
#       [--opcoes-recomendadas JSON-ARR]
#       — Cria BloqueioHumano com id `block-NNN` sequencial.
#       — Atualiza .execution.status = "aguardando_humano" (FR-016).
#       — Incrementa .accumulated_metrics.human_blocks_total.
#       — Stdout: id do bloqueio criado.
#
#   bloqueios.sh respond --state-dir DIR --block-id ID --resposta TEXT
#       — Marca bloqueio como `respondido`, registra human_answer e
#         answered_at.
#       — Se NAO restar nenhum bloqueio com status=aguardando, atualiza
#         .execution.status para "em_andamento".
#
#   bloqueios.sh list --state-dir DIR [--status STATUS]
#       — TSV: id\tdecision_id\tstatus\ttriggered_at\tpergunta
#
#   bloqueios.sh count --state-dir DIR [--pending-only]
#       — Imprime total (ou total pendente).
#
#   bloqueios.sh next-id --state-dir DIR
#       — Imprime proximo block-NNN sem registrar.
#
#   bloqueios.sh get --state-dir DIR --block-id ID
#       — Imprime JSON do bloqueio (use jq externamente para extrair campos).
#
# Exit codes:
#   0 sucesso
#   1 erro generico (state ausente, bloqueio nao encontrado)
#   2 uso incorreto
#
# POSIX sh + jq.

set -eu

_BL_NAME="bloqueios"
_BL_DIR=$(cd "$(dirname -- "$0")" && pwd)

# Envelope diagnostico aditivo (openspec-hygiene FR-012/FR-015 — escopo-piloto).
# shellcheck source=./_diag.sh
. "$_BL_DIR/_diag.sh"

# Backend dual (feature state-db-foundation, FASE 3 task 3.5): presenca de
# <state-dir>/state.db seleciona SQLite; senao, backend JSON (comportamento
# historico, intacto abaixo). Ver contracts/primitives.md §C1/C2. Reusa os
# primitivos ja testados de _state-rw-db.sh (_sr_backend/_sr_db_file/
# _sr_exec_id/_sr_sql_quote) em vez de duplica-los — mesmo racional de C8
# para sql_escape/strip_nul (paridade com state-decisions.sh/state-ondas.sh).
# shellcheck source=./_state-db.sh
. "$_BL_DIR/_state-db.sh"
# shellcheck source=./_state-rw-db.sh
. "$_BL_DIR/_state-rw-db.sh"
# shellcheck source=./_bloqueios-db.sh
. "$_BL_DIR/_bloqueios-db.sh"

# Shim para _state-rw-db.sh (_sr_exec_id/_sr_sql_quote nao chamam _sr_die em
# seus caminhos normais, mas o shim protege contra qualquer caminho de erro
# latente sem duplicar a logica de _bl_die).
_sr_die() { _bl_die "$1" "${2:-1}"; }

_bl_die_usage() { printf '%s: %s\n' "$_BL_NAME" "$1" >&2; exit 2; }
_bl_die()       { printf '%s: %s\n' "$_BL_NAME" "$1" >&2; exit "${2:-1}"; }

_bl_require_jq() {
  command -v jq >/dev/null 2>&1 \
    || _bl_die "jq nao encontrado no PATH (brew install jq | apt install jq)" 1
}

_bl_iso_now() { date -u +%FT%TZ; }
_bl_state_file() { printf '%s/state.json\n' "$1"; }

_bl_atomic_write() {
  _dst=$1; _src=$2
  _tmp=$(mktemp -- "${_dst}.XXXXXX") || _bl_die "mktemp falhou" 1
  cp -- "$_src" "$_tmp" || { rm -f -- "$_tmp"; _bl_die "I/O cp" 1; }
  mv -f -- "$_tmp" "$_dst" || { rm -f -- "$_tmp"; _bl_die "mv" 1; }
}

_bl_update_sha() {
  _sf=$(_bl_state_file "$1")
  _shf="$1/state.json.sha256"
  if command -v sha256sum >/dev/null 2>&1; then
    _h=$(sha256sum -- "$_sf" | awk '{print $1}')
  else
    _h=$(shasum -a 256 -- "$_sf" | awk '{print $1}')
  fi
  printf '%s\n' "$_h" > "$_shf"
}

_bl_backup_current() {
  _sf=$(_bl_state_file "$1")
  [ -f "$_sf" ] || return 0
  _hd="$1/state-history"
  mkdir -p -- "$_hd" 2>/dev/null || _bl_die "mkdir state-history falhou" 1
  _curr=$(jq -r '
    ((.waves // .ondas) // []) as $w
    | if ($w | length) > 0 then ($w[-1].id // "init") else "init" end
  ' "$_sf" 2>/dev/null) || _curr="init"
  _ts=$(date -u +%Y%m%dT%H%M%SZ)
  _bk="$_hd/${_curr}-${_ts}.json"
  mv -- "$_sf" "$_bk" || _bl_die "backup falhou" 1
}

_bl_next_block_id() {
  _sf=$(_bl_state_file "$1")
  # Command substitution + strip de CR (issues #122/#123): o jq nativo do
  # Windows emite CRLF e o antigo `| { read -r _max; ... }` preservava o \r
  # residual, corrompendo a aritmetica ('invalid arithmetic operator').
  # O tr remove o CR independente do jq do host; o case garante fallback 0
  # para saida vazia/nao-numerica (jq ausente, state corrompido).
  _max=$(jq -r '
    ((.human_blocks // .bloqueios_humanos) // []) as $hb
    | if ($hb | length) == 0 then 0
    else ([$hb[].id // ""] | map(sub("^block-0*"; "") | tonumber? // 0) | max)
    end' "$_sf" 2>/dev/null | tr -d '\r')
  case "$_max" in '' | *[!0-9]*) _max=0 ;; esac
  printf 'block-%03d\n' "$((_max + 1))"
}

# _bl_decisao_exists STATE_DIR DEC_ID -> 0 if exists, 1 otherwise
_bl_decisao_exists() {
  _sf=$(_bl_state_file "$1")
  jq -e --arg id "$2" '
    ((.decisions // .decisoes) // []) | map(.id) | index($id) != null
  ' "$_sf" >/dev/null 2>&1
}

# ---------- Subcomandos ----------

_bl_cmd_register() {
  _sd=""
  _dec=""
  _perg=""
  _ctx=""
  _opcoes="null"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir)              _sd=$2;     shift 2 ;;
      --decisao-id)             _dec=$2;    shift 2 ;;
      --pergunta)               _perg=$2;   shift 2 ;;
      --contexto-para-resposta) _ctx=$2;    shift 2 ;;
      --opcoes-recomendadas)    _opcoes=$2; shift 2 ;;
      *) _bl_die_usage "register: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sd" ]   || _bl_die_usage "register: --state-dir obrigatorio"
  [ -n "$_dec" ]  || _bl_die_usage "register: --decisao-id obrigatorio"
  [ -n "$_perg" ] || _bl_die_usage "register: --pergunta obrigatorio"
  [ -n "$_ctx" ]  || _bl_die_usage "register: --contexto-para-resposta obrigatorio"
  _bl_require_jq

  # Validacao de tamanho minimo (data-model: pergunta>=20, contexto>=1) —
  # comum aos dois backends, roda ANTES do dispatch (paridade de
  # comportamento, mesmo padrao de state-decisions.sh).
  if [ "$(printf '%s' "$_perg" | wc -c | tr -d ' ')" -lt 20 ]; then
    _bl_die "register: pergunta muito curta (<20 chars). Humano precisa entender sem releitura." 1
  fi
  if [ -z "$_ctx" ]; then
    _bl_die "register: contexto-para-resposta vazio" 1
  fi

  # Valida --opcoes-recomendadas (se passado, deve ser array; null ou ausente OK)
  case "$_opcoes" in
    null) ;;
    *)
      printf '%s' "$_opcoes" | jq -e 'type == "array"' >/dev/null 2>&1 \
        || _bl_die "register: --opcoes-recomendadas precisa ser JSON array (ou omitido)" 2
      ;;
  esac

  if [ "$(_sr_backend "$_sd")" = "sqlite" ]; then
    _bl_db_register "$_sd" "$_dec" "$_perg" "$_ctx" "$_opcoes"
    return 0
  fi

  _sf=$(_bl_state_file "$_sd")
  [ -f "$_sf" ] || _bl_die "register: state.json ausente em $_sd" 1

  # FK integrity: decisao referenciada precisa existir (path JSON — sob
  # SQLite a FK real do schema ja garante isto, ver _bl_db_register/C3).
  if ! _bl_decisao_exists "$_sd" "$_dec"; then
    _bl_die "register: decisao_id nao existe: $_dec (use state-decisions.sh register antes)" 1
  fi

  _id=$(_bl_next_block_id "$_sd")
  _now=$(_bl_iso_now)

  _new=$(mktemp) || _bl_die "mktemp falhou" 1
  jq \
    --arg id "$_id" \
    --arg dec "$_dec" \
    --arg perg "$_perg" \
    --arg ctx "$_ctx" \
    --arg now "$_now" \
    --argjson opcoes "$_opcoes" '
    .human_blocks += [{
      id: $id,
      decision_id: $dec,
      question: $perg,
      context_for_answer: $ctx,
      recommended_options: $opcoes,
      status: "aguardando",
      human_answer: null,
      answered_at: null,
      triggered_at: $now
    }]
    | .execution.status = "aguardando_humano"
    | .accumulated_metrics.human_blocks_total =
        ((.accumulated_metrics.human_blocks_total // 0) + 1)
  ' "$_sf" > "$_new" || { rm -f -- "$_new"; _bl_die "jq update falhou" 1; }

  _bl_backup_current "$_sd"
  _bl_atomic_write "$_sf" "$_new"
  rm -f -- "$_new" 2>/dev/null || :
  _bl_update_sha "$_sd"
  printf '%s\n' "$_id"
}

_bl_cmd_respond() {
  _sd=""
  _bid=""
  _resp=""
  _resp_set=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir) _sd=$2;  shift 2 ;;
      --block-id)  _bid=$2; shift 2 ;;
      --resposta)  _resp=$2; _resp_set=1; shift 2 ;;
      *) _bl_die_usage "respond: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sd" ]    || _bl_die_usage "respond: --state-dir obrigatorio"
  [ -n "$_bid" ]   || _bl_die_usage "respond: --block-id obrigatorio"
  [ "$_resp_set" = 1 ] || _bl_die_usage "respond: --resposta obrigatorio (use '' para resposta vazia explicita)"
  _bl_require_jq

  if [ "$(_sr_backend "$_sd")" = "sqlite" ]; then
    _bl_db_respond "$_sd" "$_bid" "$_resp"
    return 0
  fi

  _sf=$(_bl_state_file "$_sd")
  [ -f "$_sf" ] || _bl_die "respond: state.json ausente em $_sd" 1

  # Verifica que bloqueio existe e esta aguardando
  _status=$(jq -r --arg id "$_bid" '
    ((.human_blocks // .bloqueios_humanos) // []) | map(select(.id == $id)) | .[0].status // "ausente"
  ' "$_sf")
  case "$_status" in
    aguardando) ;;
    ausente)
      diag_emit error bloqueio-not-found "respond: bloqueio nao encontrado: $_bid" \
        "confira o id com bloqueios.sh list --state-dir $_sd (block-id invalido ou ja respondido)" || :
      _bl_die "respond: bloqueio nao encontrado: $_bid" 1
      ;;
    *) _bl_die "respond: bloqueio $_bid nao esta em status aguardando (status=$_status)" 1 ;;
  esac

  _now=$(_bl_iso_now)

  _new=$(mktemp) || _bl_die "mktemp falhou" 1
  jq \
    --arg id "$_bid" \
    --arg resp "$_resp" \
    --arg now "$_now" '
    .human_blocks = (.human_blocks // [] | map(
      if .id == $id then
        . + { status: "respondido", human_answer: $resp, answered_at: $now }
      else . end
    ))
    | (if (.human_blocks | map(select(.status == "aguardando")) | length) == 0
       then .execution.status = "em_andamento"
       else . end)
  ' "$_sf" > "$_new" || { rm -f -- "$_new"; _bl_die "jq update falhou" 1; }

  _bl_backup_current "$_sd"
  _bl_atomic_write "$_sf" "$_new"
  rm -f -- "$_new" 2>/dev/null || :
  _bl_update_sha "$_sd"
}

_bl_cmd_list() {
  _sd=""
  _st=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir) _sd=$2; shift 2 ;;
      --status)    _st=$2; shift 2 ;;
      *) _bl_die_usage "list: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sd" ] || _bl_die_usage "list: --state-dir obrigatorio"
  _bl_require_jq
  if [ "$(_sr_backend "$_sd")" = "sqlite" ]; then
    _bl_db_list "$_sd" "$_st"
    return 0
  fi
  _sf=$(_bl_state_file "$_sd")
  [ -f "$_sf" ] || _bl_die "list: state.json ausente" 1
  jq -r --arg s "$_st" '
    ((.human_blocks // .bloqueios_humanos) // [])
    | map(select($s == "" or .status == $s))
    | .[]
    | [.id, (.decision_id // .decisao_id), .status, (.triggered_at // .disparado_em), (.question // .pergunta)] | @tsv
  ' "$_sf"
}

_bl_cmd_count() {
  _sd=""
  _pending=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir)    _sd=$2; shift 2 ;;
      --pending-only) _pending=1; shift ;;
      *) _bl_die_usage "count: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sd" ] || _bl_die_usage "count: --state-dir obrigatorio"
  _bl_require_jq
  if [ "$(_sr_backend "$_sd")" = "sqlite" ]; then
    _bl_db_count "$_sd" "$([ "$_pending" = 1 ] && printf '1' || printf '')"
    return 0
  fi
  _sf=$(_bl_state_file "$_sd")
  [ -f "$_sf" ] || _bl_die "count: state.json ausente" 1
  if [ "$_pending" = 1 ]; then
    jq '((.human_blocks // .bloqueios_humanos) // []) | map(select(.status == "aguardando")) | length' "$_sf"
  else
    jq '((.human_blocks // .bloqueios_humanos) // []) | length' "$_sf"
  fi
}

_bl_cmd_next_id() {
  _sd=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir) _sd=$2; shift 2 ;;
      *) _bl_die_usage "next-id: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sd" ] || _bl_die_usage "next-id: --state-dir obrigatorio"
  _bl_require_jq
  if [ "$(_sr_backend "$_sd")" = "sqlite" ]; then
    _bl_db_next_id "$_sd"
    return 0
  fi
  _sf=$(_bl_state_file "$_sd")
  [ -f "$_sf" ] || _bl_die "next-id: state.json ausente" 1
  _bl_next_block_id "$_sd"
}

_bl_cmd_get() {
  _sd=""
  _bid=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir) _sd=$2; shift 2 ;;
      --block-id)  _bid=$2; shift 2 ;;
      *) _bl_die_usage "get: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sd" ]  || _bl_die_usage "get: --state-dir obrigatorio"
  [ -n "$_bid" ] || _bl_die_usage "get: --block-id obrigatorio"
  _bl_require_jq
  if [ "$(_sr_backend "$_sd")" = "sqlite" ]; then
    _bl_db_get "$_sd" "$_bid"
    return 0
  fi
  _sf=$(_bl_state_file "$_sd")
  [ -f "$_sf" ] || _bl_die "get: state.json ausente" 1
  _out=$(jq --arg id "$_bid" '
    ((.human_blocks // .bloqueios_humanos) // []) | map(select(.id == $id)) | .[0] // null
  ' "$_sf")
  if [ "$_out" = "null" ]; then
    _bl_die "get: bloqueio nao encontrado: $_bid" 1
  fi
  printf '%s\n' "$_out"
}

# ---------- Dispatch ----------

if [ "$#" -lt 1 ]; then
  cat >&2 <<'HELP'
bloqueios.sh — ciclo de vida de BloqueioHumano (FASE 4.4).

USO:
  bloqueios.sh register --state-dir DIR --decisao-id DEC \
    --pergunta TEXT --contexto-para-resposta TEXT [--opcoes-recomendadas JSON-ARR]
  bloqueios.sh respond  --state-dir DIR --block-id ID --resposta TEXT
  bloqueios.sh list     --state-dir DIR [--status STATUS]
  bloqueios.sh count    --state-dir DIR [--pending-only]
  bloqueios.sh next-id  --state-dir DIR
  bloqueios.sh get      --state-dir DIR --block-id ID

EXIT:
  0 sucesso
  1 erro generico
  2 uso incorreto
HELP
  exit 2
fi

_BL_SUBCMD=$1
shift

case "$_BL_SUBCMD" in
  register)        _bl_cmd_register "$@" ;;
  respond)         _bl_cmd_respond "$@" ;;
  list)            _bl_cmd_list "$@" ;;
  count)           _bl_cmd_count "$@" ;;
  next-id)         _bl_cmd_next_id "$@" ;;
  get)             _bl_cmd_get "$@" ;;
  -h|--help|help)  exit 0 ;;
  *) _bl_die_usage "subcomando desconhecido: $_BL_SUBCMD" ;;
esac
