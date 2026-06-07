#!/bin/sh
# circular.sh — deteccao de movimento circular (FR-014.b).
#
# Ref: docs/specs/agente-00c/spec.md FR-014.b
#      docs/specs/agente-00c/research.md Decision 4
#      docs/specs/agente-00c/tasks.md FASE 5.3
#
# Modelo: o orquestrador chama `push` a cada decisao de fix/correcao,
# passando (problema, solucao). O script normaliza ambos (lowercase,
# remove pontuacao, primeiras ~20 palavras semanticas), hashea via SHA-256
# e mantem buffer deslizante FIFO de capacidade 6 em
# .circular_movement_history.
#
# Definicao operacional de "movimento circular": o mesmo problem_hash
# aparece >=3 vezes no buffer (significa que o orquestrador esta voltando
# repetidamente ao mesmo problema com solucoes diferentes — ou variantes
# da mesma solucao — sem progresso real).
#
# Subcomandos:
#   circular.sh push --state-dir DIR --problema TEXT --solucao TEXT
#       — Normaliza, hashea, append em circular_movement_history (FIFO 6).
#       — Atualiza state.json (com backup).
#       — Stdout: TSV problem_hash\tsolution_hash\tbuffer_size_apos
#
#   circular.sh detect --state-dir DIR
#       — Exit 3 se algum problem_hash aparece >= 3 vezes no buffer.
#       — Exit 0 caso contrario.
#       — Stdout (em caso de exit 3): hash repetido + contagem.
#
#   circular.sh list --state-dir DIR
#       — TSV: index\tproblem_hash\tsolution_hash\ttimestamp
#
#   circular.sh clear --state-dir DIR
#       — Esvazia o buffer (caso o orquestrador queira "esquecer" historico
#         antigo apos resolver questao — ex: avanco para nova feature).
#
# Exit codes:
#   0 sucesso (ou nenhum movimento circular detectado)
#   1 erro generico
#   2 uso incorreto
#   3 movimento circular detectado (orquestrador deve abortar)
#
# POSIX sh + jq + sha256sum/shasum.

set -eu

_CC_NAME="circular"
_CC_BUFFER_MAX=6
_CC_REPEAT_THRESHOLD=3   # mesmo problem_hash >=3 vezes = circular

_cc_die_usage() { printf '%s: %s\n' "$_CC_NAME" "$1" >&2; exit 2; }
_cc_die()       { printf '%s: %s\n' "$_CC_NAME" "$1" >&2; exit "${2:-1}"; }

_cc_require_jq() {
  command -v jq >/dev/null 2>&1 \
    || _cc_die "jq nao encontrado no PATH" 1
}

_cc_state_file() { printf '%s/state.json\n' "$1"; }

_cc_atomic_write() {
  _dst=$1; _src=$2
  _tmp=$(mktemp -- "${_dst}.XXXXXX") || _cc_die "mktemp falhou" 1
  cp -- "$_src" "$_tmp" || { rm -f -- "$_tmp"; _cc_die "I/O cp" 1; }
  mv -f -- "$_tmp" "$_dst" || { rm -f -- "$_tmp"; _cc_die "mv" 1; }
}

_cc_update_sha() {
  _sf=$(_cc_state_file "$1")
  _shf="$1/state.json.sha256"
  if command -v sha256sum >/dev/null 2>&1; then
    _h=$(sha256sum -- "$_sf" | awk '{print $1}')
  else
    _h=$(shasum -a 256 -- "$_sf" | awk '{print $1}')
  fi
  printf '%s\n' "$_h" > "$_shf"
}

# _cc_normalize TEXT -> texto normalizado para hash
# 1. lowercase
# 2. troca pontuacao + sequencias nao-alfanumericas por espaco
# 3. colapsa whitespace
# 4. mantem so as primeiras 20 palavras semanticas
_cc_normalize() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | tr -c 'a-z0-9' ' ' \
    | tr -s ' ' \
    | awk '{
        n = (NF < 20) ? NF : 20;
        for (i = 1; i <= n; i++) printf "%s%s", $i, (i==n ? "" : " ");
      }'
}

_cc_sha256_text() {
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$1" | sha256sum | awk '{print $1}'
  else
    printf '%s' "$1" | shasum -a 256 | awk '{print $1}'
  fi
}

_cc_iso_now() { date -u +%FT%TZ; }

_cc_cmd_push() {
  _sd=""
  _prob=""
  _sol=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir) _sd=$2;   shift 2 ;;
      --problema)  _prob=$2; shift 2 ;;
      --solucao)   _sol=$2;  shift 2 ;;
      *) _cc_die_usage "push: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sd" ]   || _cc_die_usage "push: --state-dir obrigatorio"
  [ -n "$_prob" ] || _cc_die_usage "push: --problema obrigatorio"
  [ -n "$_sol" ]  || _cc_die_usage "push: --solucao obrigatorio"
  _cc_require_jq

  _sf=$(_cc_state_file "$_sd")
  [ -f "$_sf" ] || _cc_die "push: state.json ausente" 1

  _ph=$(_cc_sha256_text "$(_cc_normalize "$_prob")")
  _sh=$(_cc_sha256_text "$(_cc_normalize "$_sol")")
  _now=$(_cc_iso_now)

  # Writer (schema-en-migration): grava chave EN do container
  # (.circular_movement_history) e folhas EN (problem_hash/solution_hash).
  # Reader do append com fallback (.en // .pt) p/ acumular sobre states pt-BR
  # vivos antes do migrate convergir o disco para EN.
  _new_state=$(mktemp) || _cc_die "mktemp falhou" 1
  jq \
    --arg ph "$_ph" \
    --arg sh "$_sh" \
    --arg ts "$_now" \
    --argjson max "$_CC_BUFFER_MAX" '
    .circular_movement_history =
      (
        (((.circular_movement_history // .historico_movimento_circular) // []) + [{
          problem_hash: $ph,
          solution_hash: $sh,
          timestamp: $ts
        }])
        | (if length > $max then .[length - $max:] else . end)
      )
  ' "$_sf" > "$_new_state" || { rm -f -- "$_new_state"; _cc_die "jq update falhou" 1; }
  _cc_atomic_write "$_sf" "$_new_state"
  rm -f -- "$_new_state" 2>/dev/null || :
  _cc_update_sha "$_sd"

  _bsize=$(jq '(.circular_movement_history // .historico_movimento_circular) | length' "$_sf")
  printf '%s\t%s\t%s\n' "$_ph" "$_sh" "$_bsize"
}

_cc_cmd_detect() {
  _sd=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir) _sd=$2; shift 2 ;;
      *) _cc_die_usage "detect: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sd" ] || _cc_die_usage "detect: --state-dir obrigatorio"
  _cc_require_jq
  _sf=$(_cc_state_file "$_sd")
  [ -f "$_sf" ] || _cc_die "detect: state.json ausente" 1

  # Reader (schema-en-migration): container EN + fallback (.en // .pt); folha
  # problem_hash com fallback p/ problema_hash. Encontra hash com count >= threshold.
  _result=$(jq -r --argjson t "$_CC_REPEAT_THRESHOLD" '
    ((.circular_movement_history // .historico_movimento_circular) // [])
    | group_by(.problem_hash // .problema_hash)
    | map(select(length >= $t))
    | map({hash: (.[0].problem_hash // .[0].problema_hash), count: length})
    | .[]
    | "\(.hash)\t\(.count)"
  ' "$_sf")

  if [ -z "$_result" ]; then
    exit 0
  fi
  printf '%s\n' "$_result"
  printf '%s: movimento circular detectado (problem_hash repetido >=%s vezes)\n' \
    "$_CC_NAME" "$_CC_REPEAT_THRESHOLD" >&2
  exit 3
}

_cc_cmd_list() {
  _sd=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir) _sd=$2; shift 2 ;;
      *) _cc_die_usage "list: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sd" ] || _cc_die_usage "list: --state-dir obrigatorio"
  _cc_require_jq
  _sf=$(_cc_state_file "$_sd")
  [ -f "$_sf" ] || _cc_die "list: state.json ausente" 1
  # Reader (schema-en-migration): container EN + fallback; folhas problem_hash/
  # solution_hash com fallback p/ problema_hash/solucao_hash.
  jq -r '
    ((.circular_movement_history // .historico_movimento_circular) // [])
    | to_entries
    | .[]
    | "\(.key)\t\(.value.problem_hash // .value.problema_hash)\t\(.value.solution_hash // .value.solucao_hash)\t\(.value.timestamp)"
  ' "$_sf"
}

_cc_cmd_clear() {
  _sd=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir) _sd=$2; shift 2 ;;
      *) _cc_die_usage "clear: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sd" ] || _cc_die_usage "clear: --state-dir obrigatorio"
  _cc_require_jq
  _sf=$(_cc_state_file "$_sd")
  [ -f "$_sf" ] || _cc_die "clear: state.json ausente" 1
  # Writer (schema-en-migration): zera container EN e remove eventual chave pt-BR
  # residual (clear = "esquecer historico", precisa valer mesmo pre-migrate).
  _new_state=$(mktemp) || _cc_die "mktemp falhou" 1
  jq '.circular_movement_history = [] | del(.historico_movimento_circular)' "$_sf" > "$_new_state" \
    || { rm -f -- "$_new_state"; _cc_die "jq update falhou" 1; }
  _cc_atomic_write "$_sf" "$_new_state"
  rm -f -- "$_new_state" 2>/dev/null || :
  _cc_update_sha "$_sd"
}

# ---------- Dispatch ----------

if [ "$#" -lt 1 ]; then
  cat >&2 <<'HELP'
circular.sh — deteccao de movimento circular (FR-014.b).

USO:
  circular.sh push --state-dir DIR --problema TEXT --solucao TEXT
  circular.sh detect --state-dir DIR
  circular.sh list   --state-dir DIR
  circular.sh clear  --state-dir DIR

Buffer FIFO capacidade 6. Detect = mesmo problem_hash >= 3 vezes.

EXIT (detect):
  0 sem movimento circular
  3 movimento circular detectado (orquestrador deve abortar)
HELP
  exit 2
fi

_CC_SUBCMD=$1
shift

case "$_CC_SUBCMD" in
  push)            _cc_cmd_push "$@" ;;
  detect)          _cc_cmd_detect "$@" ;;
  list)            _cc_cmd_list "$@" ;;
  clear)           _cc_cmd_clear "$@" ;;
  -h|--help|help)  exit 0 ;;
  *) _cc_die_usage "subcomando desconhecido: $_CC_SUBCMD" ;;
esac
