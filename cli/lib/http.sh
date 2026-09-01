# http.sh — wrappers curl com error mapping, usados para fetch de GitHub Releases.
#
# Funcoes exportadas:
#   http_download <url> <dest>   — baixa URL para arquivo local
#   http_check_url <url>         — HEAD para verificar disponibilidade (0/1)
#
# Convencoes de curl:
#   -f   fail em 4xx/5xx (sem gerar output "normal")
#   -s   silent (sem progress bar)
#   -S   mostra mensagem em caso de erro
#
# Redirects SEM `-L` (issue #178): o `-L` seguia a cadeia inteira dentro do
# curl, e a allowlist de hosts (cli/lib/trusted-hosts.sh) so era aplicada
# pelo caller sobre a URL INICIAL. Um host confiavel que redirecionasse para
# fora da allowlist nao era revalidado — funcionava por coincidencia da
# configuracao do GitHub (objects.githubusercontent.com ja esta na lista),
# nao por verificacao. Agora a cadeia e caminhada MANUALMENTE, um salto por
# vez: cada URL (a inicial e cada `Location`) passa por trusted_host_check
# ANTES da requisicao correspondente. Salto fora da allowlist => nenhuma
# requisicao e feita a esse host (nao ha "baixa e descarta depois").
#
# Regras da caminhada:
#   - a URL INICIAL pode ser file:// (fluxo de dev, FR-014 de trusted-hosts)
#     ou https:// com host na allowlist;
#   - saltos subsequentes MUST ser https:// na allowlist — um redirect para
#     file:// e recusado (leria arquivo local passando por download);
#   - teto de _HTTP_MAX_REDIRS saltos (curl default seria 50);
#   - 3xx sem `Location` legivel => erro (nunca tratar o corpo do redirect
#     como se fosse o payload).
#
# Timeouts conservadores (por SALTO):
#   --connect-timeout 10   nao esperar mais de 10s para conectar
#   --max-time 300         tarball de release nao deve demorar mais de 5min
#
# Error mapping (curl exit -> usuario):
#   6  nao consegui resolver host (DNS down / offline)
#   7  nao consegui conectar (firewall / host offline)
#   22 servidor retornou 4xx/5xx
#   28 timeout
#   resto: generic
#
# Retornos:
#   0  sucesso
#   1  erro de rede, HTTP, curl ausente, host fora da allowlist ou arg problema
#   2  uso incorreto (argumentos faltando)
#
# POSIX sh puro. Deps: curl, printf, command; cli/lib/trusted-hosts.sh.

if [ -n "${_CSTK_HTTP_LOADED:-}" ]; then
  return 0 2>/dev/null
fi
_CSTK_HTTP_LOADED=1

# Allowlist compartilhada (constante estatica, nao overridable via env).
# Idempotente: trusted-hosts.sh tem guarda de carga propria.
# shellcheck source=./trusted-hosts.sh
. "${CSTK_LIB:?CSTK_LIB must be set (http.sh depende de trusted-hosts.sh)}/trusted-hosts.sh"

# Teto de saltos de redirect aceitos numa unica transferencia.
_HTTP_MAX_REDIRS=10

# _http_map_error <curl_exit> <url> — imprime a mensagem de erro mapeada.
_http_map_error() {
  case "$1" in
    6)  printf 'http: nao foi possivel resolver host de %s (offline?)\n' "$2" >&2 ;;
    7)  printf 'http: falha ao conectar em %s\n' "$2" >&2 ;;
    22) printf 'http: servidor retornou erro HTTP para %s\n' "$2" >&2 ;;
    28) printf 'http: timeout ao baixar %s\n' "$2" >&2 ;;
    *)  printf 'http: download falhou (curl exit %s): %s\n' "$1" "$2" >&2 ;;
  esac
}

# _http_hop_allowed <url> <hop_n> — 0 se a URL pode ser requisitada neste
# salto. Salto 0 (URL inicial) aceita file://; saltos >0 exigem https na
# allowlist (um redirect NUNCA pode virar leitura de arquivo local).
_http_hop_allowed() {
  if [ "$2" -gt 0 ]; then
    case "$1" in
      file://*)
        printf 'http: redirect para file:// recusado (salto %s): %s\n' "$2" "$1" >&2
        return 1
        ;;
    esac
  fi
  trusted_host_check "$1" || return 1
  return 0
}

http_download() {
  # POSIX sh NAO tem local vars — usamos prefixo _http_ para evitar colisao
  # com variaveis do caller (ex: _dest em tarball.sh).
  if [ "$#" -ne 2 ]; then
    printf 'http: http_download espera 2 argumentos (url, dest)\n' >&2
    return 2
  fi
  _http_url=$1
  _http_dest=$2
  if ! command -v curl >/dev/null 2>&1; then
    printf 'http: curl nao encontrado no PATH\n' >&2
    return 1
  fi

  _http_hop_url=$_http_url
  _http_hop_n=0
  while :; do
    if ! _http_hop_allowed "$_http_hop_url" "$_http_hop_n"; then
      if [ "$_http_hop_n" -gt 0 ]; then
        printf 'http: cadeia de redirects abortada (origem: %s)\n' "$_http_url" >&2
      fi
      [ -f "$_http_dest" ] && rm -f -- "$_http_dest"
      return 1
    fi

    # Sem -L: um salto por invocacao. `-w` devolve codigo HTTP + a proxima
    # URL (curl ja resolve Location relativo para absoluto).
    _http_ec=0
    _http_meta=$(curl -fsS --connect-timeout 10 --max-time 300 \
      -w '%{http_code} %{redirect_url}' \
      -o "$_http_dest" -- "$_http_hop_url" 2>/dev/null) || _http_ec=$?
    if [ "$_http_ec" -ne 0 ]; then
      _http_map_error "$_http_ec" "$_http_hop_url"
      [ -f "$_http_dest" ] && rm -f -- "$_http_dest"
      return 1
    fi

    _http_code=${_http_meta%% *}
    _http_next=${_http_meta#* }

    if [ -z "$_http_next" ]; then
      case "$_http_code" in
        3??)
          printf 'http: resposta %s sem Location utilizavel em %s\n' "$_http_code" "$_http_hop_url" >&2
          [ -f "$_http_dest" ] && rm -f -- "$_http_dest"
          return 1
          ;;
      esac
      return 0
    fi

    _http_hop_n=$((_http_hop_n + 1))
    if [ "$_http_hop_n" -gt "$_HTTP_MAX_REDIRS" ]; then
      printf 'http: excedido o teto de %s redirects a partir de %s\n' \
        "$_HTTP_MAX_REDIRS" "$_http_url" >&2
      [ -f "$_http_dest" ] && rm -f -- "$_http_dest"
      return 1
    fi
    _http_hop_url=$_http_next
  done
}

http_check_url() {
  if [ "$#" -ne 1 ]; then
    printf 'http: http_check_url espera 1 argumento (url)\n' >&2
    return 2
  fi
  if ! command -v curl >/dev/null 2>&1; then
    printf 'http: curl nao encontrado no PATH\n' >&2
    return 1
  fi

  # Mesma caminhada manual do http_download, sem corpo (-I / HEAD).
  _http_cu_url=$1
  _http_cu_hop=0
  while :; do
    _http_hop_allowed "$_http_cu_url" "$_http_cu_hop" || return 1
    _http_cu_meta=$(curl -fsSI --connect-timeout 10 --max-time 30 \
      -w '%{http_code} %{redirect_url}' \
      -o /dev/null -- "$_http_cu_url" 2>/dev/null) || return 1
    _http_cu_next=${_http_cu_meta#* }
    [ -n "$_http_cu_next" ] || return 0
    _http_cu_hop=$((_http_cu_hop + 1))
    [ "$_http_cu_hop" -le "$_HTTP_MAX_REDIRS" ] || return 1
    _http_cu_url=$_http_cu_next
  done
}
