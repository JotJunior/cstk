#!/bin/sh
# whitelist-validate.sh — valida formato de whitelist de URLs (FR-031).
#
# Ref: docs/specs/agente-00c/spec.md FR-031
#      docs/specs/agente-00c/research.md Decision 5
#      docs/specs/agente-00c/threat-model.md T5
#      docs/specs/agente-00c/tasks.md FASE 6.7
#
# Formato esperado (uma URL/pattern por linha):
#   - Comentarios comecam com `#` (ignorados)
#   - Linhas vazias ignoradas
#   - Cada entry deve ser uma URL `http://` ou `https://` com dominio
#     explicito
#   - Globos simples permitidos no path: `/foo/*`, `/repos/owner/**`
#   - Glob no SUBDOMINIO permitido com prefixo `*.`: `https://*.example.com/path`
#
# Padroes REJEITADOS (overly broad — risco de leak):
#   - `**` puro como entry inteira (sem dominio)
#   - `*://*` (qualquer scheme + qualquer host)
#   - `https?://[*]` ou `https?://*` sem dominio explicito (ex: `https://*`)
#   - URLs sem scheme ou sem host
#
# Subcomandos:
#   whitelist-validate.sh check --whitelist-file FILE
#       — Valida formato. Exit 0 se OK; exit 1 se alguma entry invalida.
#       — Mensagens de erro em stderr indicam linha + motivo.
#
#   whitelist-validate.sh list --whitelist-file FILE
#       — Lista entries validas (uma por linha) em stdout. Comentarios e
#         linhas vazias filtradas.
#
# Exit codes:
#   0 OK (todas validas) ou lista bem-sucedida
#   1 alguma entry invalida (check)
#   2 uso incorreto / arquivo nao encontrado
#
# POSIX sh + grep -E.

set -eu

_WV_NAME="whitelist-validate"

_wv_die_usage() { printf '%s: %s\n' "$_WV_NAME" "$1" >&2; exit 2; }

# _wv_validate_line LINE -> "OK" se valida, motivo em stdout caso contrario.
# Retorna 0 se OK, 1 se invalida.
_wv_validate_line() {
  _l=$1
  # Trim
  _l=$(printf '%s' "$_l" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
  [ -z "$_l" ] && return 0  # vazio = OK (sera ignorado)

  # 1. Rejeicao: ** puro
  if [ "$_l" = "**" ]; then
    printf '%s\n' "padrao **\n puro sem dominio (cobre tudo)"
    return 1
  fi

  # 2. Rejeicao: *://*  (scheme glob)
  case "$_l" in
    '*://'*) printf '%s\n' "scheme com glob (\`*://*\`) — exija http(s) explicito"; return 1 ;;
  esac

  # 3. Verifica scheme http(s)
  case "$_l" in
    http://*|https://*) ;;
    *) printf '%s\n' "sem scheme http(s):// explicito"; return 1 ;;
  esac

  # 4. Extrai host (entre `://` e proximo `/`)
  _rest=${_l#*://}
  _host=${_rest%%/*}
  if [ -z "$_host" ]; then
    printf '%s\n' "host vazio (URL malformada)"
    return 1
  fi

  # 5. Rejeicao: host puro `*` ou `[*]`
  case "$_host" in
    '*'|'[*]'|'[*]:'*)
      printf '%s\n' "host \`*\` ou \`[*]\` cobre qualquer dominio"
      return 1
      ;;
  esac

  # 6. Wildcard no host so e permitido como prefixo `*.`
  # `host` pode ser: `dominio.com`, `*.dominio.com`, `dominio.com:8080`
  # Rejeita: `*dominio.com`, `dominio.*`, `*.*`
  case "$_host" in
    *'*'*)
      # Tem wildcard. Aceita SO se for prefixo `*.` seguido de dominio
      # com pelo menos 2 partes
      case "$_host" in
        '*.'?*'.'?*)
          # OK: *.foo.com, *.foo.example.com
          ;;
        *)
          printf '%s\n' "wildcard no host fora do padrao \`*.dominio.tld\` (overly broad)"
          return 1
          ;;
      esac
      ;;
  esac

  return 0
}

_wv_cmd_check() {
  _wl=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --whitelist-file) _wl=$2; shift 2 ;;
      *) _wv_die_usage "check: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_wl" ] || _wv_die_usage "check: --whitelist-file obrigatorio"
  if [ ! -f "$_wl" ]; then
    printf '%s: arquivo nao encontrado: %s\n' "$_WV_NAME" "$_wl" >&2
    exit 2
  fi

  _lineno=0
  _errors=0
  while IFS= read -r _line || [ -n "$_line" ]; do
    _lineno=$((_lineno + 1))
    # Pula comentarios e vazias
    case "$_line" in
      ''|\#*) continue ;;
    esac
    # Trim antes da validacao (a propria funcao tambem faz, mas stderr fica
    # mais legivel se mostramos a linha original).
    _trim=$(printf '%s' "$_line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    case "$_trim" in
      ''|\#*) continue ;;
    esac
    if _reason=$(_wv_validate_line "$_trim"); then
      :
    else
      printf '%s: linha %s INVALIDA — %s\n' "$_WV_NAME" "$_lineno" "$_reason" >&2
      printf '  conteudo: %s\n' "$_trim" >&2
      _errors=$((_errors + 1))
    fi
  done < "$_wl"

  if [ "$_errors" -gt 0 ]; then
    printf '%s: %s entry(ies) invalida(s) em %s\n' "$_WV_NAME" "$_errors" "$_wl" >&2
    exit 1
  fi
  exit 0
}

_wv_cmd_list() {
  _wl=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --whitelist-file) _wl=$2; shift 2 ;;
      *) _wv_die_usage "list: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_wl" ] || _wv_die_usage "list: --whitelist-file obrigatorio"
  [ -f "$_wl" ] || { printf '%s: arquivo nao encontrado: %s\n' "$_WV_NAME" "$_wl" >&2; exit 2; }
  while IFS= read -r _line || [ -n "$_line" ]; do
    case "$_line" in
      ''|\#*) continue ;;
    esac
    _trim=$(printf '%s' "$_line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    [ -n "$_trim" ] && printf '%s\n' "$_trim"
  done < "$_wl"
}

# ---------- Dispatch ----------

if [ "$#" -lt 1 ]; then
  cat >&2 <<'HELP'
whitelist-validate.sh — valida formato de whitelist (FR-031).

USO:
  whitelist-validate.sh check --whitelist-file FILE
  whitelist-validate.sh list  --whitelist-file FILE

Rejeita patterns "overly broad": ** puro, *://*, https://*, etc.
Wildcards no host: somente prefixo *.dominio.tld.
HELP
  exit 2
fi

_WV_SUBCMD=$1
shift

case "$_WV_SUBCMD" in
  check)           _wv_cmd_check "$@" ;;
  list)            _wv_cmd_list "$@" ;;
  -h|--help|help)  exit 0 ;;
  *) _wv_die_usage "subcomando desconhecido: $_WV_SUBCMD" ;;
esac
