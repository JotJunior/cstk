# serve.sh — implementa o subcomando `cstk serve`.
#
# Uso: sourced por cli/cstk, entao chamado via serve_main "$@".
#
# Contrato publico:
#   serve_main [--port P] [--host H] [--reinstall] [--help]
#     exit 0  sucesso (painel rodando ou --help)
#     exit 1  erro geral (prereq ausente, download falhou, instalacao corrompida)
#     exit 2  uso incorreto (porta invalida, flag desconhecida)
#
# Dependencias internas (sourced via $CSTK_LIB):
#   http.sh    -> http_download, http_check_url
#   compat.sh  -> sha256_file
#
# Decisao de design (research.md D2):
#   cli/lib/tarball.sh::download_and_verify NAO e reutilizado porque exige
#   sha256_url e aborta na ausencia. cstk-panel nao publica .sha256 de forma
#   confiavel; serve.sh implementa fluxo proprio com integridade best-effort.
#
# POSIX sh puro — sem Bash-isms (nao usa [[ ]], arrays, local, source, <<<).
# Deps opcionais confinadas: npm, node (runtime do painel, nao do cstk).
# curl e usado via http.sh (nao diretamente).

if [ "${_SERVE_LOADED:-}" = "1" ]; then
  return 0
fi
_SERVE_LOADED=1

# Hosts autorizados para download do tarball do painel (S2/CHK-S03/FR-012).
# Qualquer tarball_url de host fora desta lista e rejeitada antes do download.
_SERVE_ALLOWED_HOSTS="github.com codeload.github.com objects.githubusercontent.com api.github.com"

# URL da API do GitHub para consultar o release mais recente.
_SERVE_GITHUB_API="https://api.github.com/repos/JotJunior/cstk-panel/releases/latest"

# _serve_check_host_allowlist URL
# Verifica que URL usa schema https:// e host autorizado.
# exit 0 = ok; exit 1 = rejeitado (mensagem em stderr).
_serve_check_host_allowlist() {
  _sca_url="$1"
  # CHK-S04: schema deve ser https://
  case "$_sca_url" in
    https://*) ;;
    *)
      printf 'cstk serve: erro: URL rejeita schema nao-HTTPS: %s\n' "$_sca_url" >&2
      return 1
      ;;
  esac
  # Extrair host: remover https:// e pegar ate a primeira /
  _sca_host=$(printf '%s' "$_sca_url" | sed 's|^https://||' | sed 's|/.*||')
  # S2/FR-012: verificar contra allowlist via case glob
  case "$_sca_host" in
    github.com|codeload.github.com|objects.githubusercontent.com|api.github.com)
      return 0
      ;;
    *)
      printf 'cstk serve: erro: host nao autorizado na allowlist: %s\n' "$_sca_host" >&2
      printf 'cstk serve: hosts permitidos: %s\n' "$_SERVE_ALLOWED_HOSTS" >&2
      return 1
      ;;
  esac
}

# _serve_is_installed PANEL_DIR
# Retorna 0 se o painel esta instalado (package.json presente e legivel).
# Retorna 1 caso contrario.
_serve_is_installed() {
  _sii_dir="$1"
  [ -f "$_sii_dir/package.json" ]
}

# _serve_latest_tag
# Ecoa a tag_name da release mais recente do painel (via API GitHub) e retorna 0.
# Retorna 1 (silenciosamente) se a rede/API falhar, o JSON nao tiver tag, ou a
# release for prerelease/draft. Best-effort: usado por --update para decidir se
# reinstala — qualquer falha mantem a versao instalada (nunca aborta o serve).
_serve_latest_tag() {
  # shellcheck source=/dev/null
  . "${CSTK_LIB}/http.sh"
  _slt_tmp=$(mktemp -d 2>/dev/null) || return 1
  if ! http_download "$_SERVE_GITHUB_API" "$_slt_tmp/release.json" 2>/dev/null; then
    rm -rf -- "$_slt_tmp"
    return 1
  fi
  _slt_tag=$(grep -o '"tag_name"[[:space:]]*:[[:space:]]*"[^"]*"' "$_slt_tmp/release.json" \
    | sed 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' | head -1)
  _slt_pre=$(grep -o '"prerelease"[[:space:]]*:[[:space:]]*[a-z]*' "$_slt_tmp/release.json" \
    | sed 's/.*:[[:space:]]*//' | head -1)
  _slt_draft=$(grep -o '"draft"[[:space:]]*:[[:space:]]*[a-z]*' "$_slt_tmp/release.json" \
    | sed 's/.*:[[:space:]]*//' | head -1)
  rm -rf -- "$_slt_tmp"
  [ "$_slt_pre" = "true" ] && return 1
  [ "$_slt_draft" = "true" ] && return 1
  [ -n "$_slt_tag" ] || return 1
  printf '%s\n' "$_slt_tag"
}

# _serve_shutdown: handler de sinal para SIGINT/SIGTERM.
# Envia SIGTERM ao filho, aguarda ate 5s, entao SIGKILL se necessario.
_serve_shutdown() {
  printf '\ncstk serve: encerrando painel...\n'
  if [ -n "${_SERVE_NPM_PID:-}" ]; then
    kill -TERM "$_SERVE_NPM_PID" 2>/dev/null || :
    # Aguardar ate 5 segundos (checando a cada 0.5s aproximado)
    _srv_i=0
    while [ "$_srv_i" -lt 10 ]; do
      if ! kill -0 "$_SERVE_NPM_PID" 2>/dev/null; then
        break
      fi
      sleep 0.5 2>/dev/null || sleep 1
      _srv_i=$((_srv_i + 1))
    done
    # SIGKILL se ainda vivo (CHK-R06)
    if kill -0 "$_SERVE_NPM_PID" 2>/dev/null; then
      kill -KILL "$_SERVE_NPM_PID" 2>/dev/null || :
    fi
  fi
}

# _serve_install PANEL_DIR
# Realiza o download e instalacao do painel em PANEL_DIR.
# Usa tmpdir privado; move atomicamente para PANEL_DIR apos sucesso.
# exit 0 = ok; exit 1 = falha (PANEL_DIR inalterado).
_serve_install() {
  _si_panel_dir="$1"

  # Sourcear helpers de rede e checksum
  # shellcheck source=/dev/null
  . "${CSTK_LIB}/http.sh"
  # shellcheck source=/dev/null
  . "${CSTK_LIB}/compat.sh"

  # Tmpdir privado com cleanup garantido via trap
  _si_tmp=$(mktemp -d 2>/dev/null) || {
    printf 'cstk serve: erro: nao foi possivel criar tmpdir\n' >&2
    return 1
  }
  trap 'rm -rf -- "$_si_tmp"' EXIT INT TERM

  printf 'cstk serve: consultando GitHub para release mais recente...\n'

  # Consulta API GitHub (CHK-R26: falha HTTP -> exit 1)
  _si_api_file="$_si_tmp/release.json"
  if ! http_download "$_SERVE_GITHUB_API" "$_si_api_file"; then
    printf 'cstk serve: erro: falha ao consultar API do GitHub\n' >&2
    rm -rf -- "$_si_tmp"
    return 1
  fi

  # Extrair tag_name e tarball_url via grep/sed POSIX (sem jq)
  _si_tag=$(grep -o '"tag_name"[[:space:]]*:[[:space:]]*"[^"]*"' "$_si_api_file" \
    | sed 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' | head -1)
  _si_tarball=$(grep -o '"tarball_url"[[:space:]]*:[[:space:]]*"[^"]*"' "$_si_api_file" \
    | sed 's/.*"tarball_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' | head -1)

  if [ -z "$_si_tag" ] || [ -z "$_si_tarball" ]; then
    printf 'cstk serve: erro: API nao retornou tag_name ou tarball_url\n' >&2
    rm -rf -- "$_si_tmp"
    return 1
  fi

  # CHK-R02: rejeitar prerelease ou draft
  _si_prerelease=$(grep -o '"prerelease"[[:space:]]*:[[:space:]]*[a-z]*' "$_si_api_file" \
    | sed 's/.*:[[:space:]]*//' | head -1)
  _si_draft=$(grep -o '"draft"[[:space:]]*:[[:space:]]*[a-z]*' "$_si_api_file" \
    | sed 's/.*:[[:space:]]*//' | head -1)
  if [ "$_si_prerelease" = "true" ] || [ "$_si_draft" = "true" ]; then
    printf 'cstk serve: erro: release mais recente eh prerelease ou draft; nao instalando\n' >&2
    rm -rf -- "$_si_tmp"
    return 1
  fi

  printf 'cstk serve: instalando versao %s...\n' "$_si_tag"

  # S2/CHK-S03/CHK-S04: validar host e schema da tarball_url
  if ! _serve_check_host_allowlist "$_si_tarball"; then
    rm -rf -- "$_si_tmp"
    return 1
  fi

  # Download do tarball (CHK-R03: timeouts via http.sh)
  _si_archive="$_si_tmp/archive.tar.gz"
  if ! http_download "$_si_tarball" "$_si_archive"; then
    printf 'cstk serve: erro: falha ao baixar tarball do painel\n' >&2
    rm -rf -- "$_si_tmp"
    return 1
  fi

  # CHK-R23: verificar tamanho minimo do tarball (>= 1024 bytes)
  _si_size=$(wc -c < "$_si_archive" 2>/dev/null | tr -d ' ')
  if [ "${_si_size:-0}" -lt 1024 ] 2>/dev/null; then
    printf 'cstk serve: erro: tarball baixado parece vazio ou truncado (%s bytes)\n' \
      "${_si_size:-0}" >&2
    rm -rf -- "$_si_tmp"
    return 1
  fi

  # Integridade best-effort (FR-008): tentar .sha256 asset
  _si_sha256_url="${_si_tarball}.sha256"
  _si_sha256_file="$_si_tmp/archive.tar.gz.sha256"
  if _serve_check_host_allowlist "$_si_sha256_url" 2>/dev/null && \
     http_download "$_si_sha256_url" "$_si_sha256_file" 2>/dev/null; then
    _si_expected=$(awk '{print $1}' "$_si_sha256_file" 2>/dev/null)
    _si_actual=$(sha256_file "$_si_archive" 2>/dev/null)
    if [ -n "$_si_expected" ] && [ -n "$_si_actual" ]; then
      if [ "$_si_expected" != "$_si_actual" ]; then
        printf 'cstk serve: erro: checksum SHA-256 nao confere (integridade comprometida)\n' >&2
        rm -rf -- "$_si_tmp"
        return 1
      fi
      printf 'cstk serve: integridade verificada (SHA-256 ok)\n'
    fi
  else
    printf 'cstk serve: aviso: arquivo .sha256 nao disponivel; continuando sem verificacao de integridade\n'
  fi

  # Extracao com strip-components=1
  _si_extract="$_si_tmp/extracted"
  mkdir -p "$_si_extract"
  if ! tar -xzf "$_si_archive" --strip-components 1 -C "$_si_extract" 2>/dev/null; then
    printf 'cstk serve: erro: falha ao extrair tarball (arquivo corrompido ou sem espaco em disco)\n' >&2
    rm -rf -- "$_si_tmp"
    return 1
  fi

  # Verificar que package.json existe apos extracao
  if [ ! -f "$_si_extract/package.json" ]; then
    printf 'cstk serve: erro: package.json ausente apos extracao (estrutura de tarball inesperada)\n' >&2
    rm -rf -- "$_si_tmp"
    return 1
  fi

  # npm install (CHK: falha -> exit 1)
  printf 'cstk serve: executando npm install...\n'
  if ! (cd "$_si_extract" && npm install) 2>&1; then
    printf 'cstk serve: erro: npm install falhou\n' >&2
    rm -rf -- "$_si_tmp"
    return 1
  fi

  # Move atomico para panel_dir (apos extrair + npm install)
  mkdir -p "$(dirname -- "$_si_panel_dir")"
  if ! mv -- "$_si_extract" "$_si_panel_dir"; then
    printf 'cstk serve: erro: nao foi possivel mover painel para %s\n' "$_si_panel_dir" >&2
    rm -rf -- "$_si_tmp"
    return 1
  fi

  # Gravar .panel-version com tag_name
  printf '%s\n' "$_si_tag" > "$_si_panel_dir/.panel-version"

  # Limpar tmpdir (trap cuida de EXIT mas chamamos explicitamente aqui)
  rm -rf -- "$_si_tmp"
  trap - EXIT INT TERM
  return 0
}

# serve_main "$@"
# Ponto de entrada do subcomando `cstk serve`.
serve_main() {
  # Valores default
  _serve_port="${PORT:-5173}"
  _serve_host="127.0.0.1"
  _serve_reinstall=0
  _serve_update=0

  # Parse de flags POSIX (while/case/shift)
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --port)
        shift
        _serve_port="${1:-}"
        ;;
      --port=*)
        _serve_port="${1#--port=}"
        ;;
      --host)
        shift
        _serve_host="${1:-}"
        ;;
      --host=*)
        _serve_host="${1#--host=}"
        ;;
      --reinstall)
        _serve_reinstall=1
        ;;
      --update)
        _serve_update=1
        ;;
      --help|-h)
        cat <<'HELP'
Usage: cstk serve [--port PORT] [--host HOST] [--update] [--reinstall]

Start the cstk panel web interface. On first run, downloads the latest
release from GitHub and installs it locally. Subsequent runs reuse the
cached installation.

The panel runs in dev mode: the API (Fastify, port 3001) and the web
frontend (Vite, port 5173) are started together, with Vite proxying
/api to the API. Open http://127.0.0.1:5173 in your browser.

Options:
  --port PORT     Validated (integer 1024-65535) for compatibility, but in
                  dev mode the UI is served by Vite on port 5173 and this
                  flag does not change it (a notice is printed if != 5173).
  --host HOST     Hostname/IP to bind to (default: 127.0.0.1).
                  Note: only 127.0.0.1 is fully supported; other values
                  are accepted but may not affect the panel binding.
  --update        Check GitHub for a newer panel release and reinstall only
                  if one exists (otherwise reuse the cached version). The
                  check is best-effort: if it fails (offline/API error), the
                  installed version is kept and the panel still starts.
  --reinstall     Remove the existing installation and reinstall from
                  the latest GitHub release (unconditional; ignores --update).
  --help, -h      Show this help and exit.

Exit codes:
  0   Panel started (or --help shown).
  1   General error (prereq missing, download failed, install corrupt).
  2   Usage error (invalid port, unknown flag).

Examples:
  cstk serve                         # start API + web (UI on http://127.0.0.1:5173)
  cstk serve --update                # update panel if a newer release exists, then start
  cstk serve --reinstall             # force reinstall then start
  cstk serve --help                  # show this help

Environment:
  CSTK_PANEL_DIR   Override install directory (default: ~/.local/share/cstk/panel)
  PORT             Default port if --port is not given (default: 5173)
HELP
        return 0
        ;;
      --)
        shift
        break
        ;;
      -*)
        printf 'cstk serve: erro: flag desconhecida: %s\n' "$1" >&2
        printf 'Use: cstk serve --help\n' >&2
        return 2
        ;;
      *)
        printf 'cstk serve: erro: argumento inesperado: %s\n' "$1" >&2
        printf 'Use: cstk serve --help\n' >&2
        return 2
        ;;
    esac
    shift
  done

  # Validar porta: deve ser inteiro puro (CHK 2.1.3)
  # Passo 1: inteiro?
  case "$_serve_port" in
    ''|*[!0-9]*)
      printf 'cstk serve: erro: porta invalida: "%s" (deve ser um inteiro entre 1024 e 65535)\n' \
        "$_serve_port" >&2
      return 2
      ;;
  esac

  # Passo 2: intervalo 1-65535?
  if [ "$_serve_port" -lt 1 ] || [ "$_serve_port" -gt 65535 ] 2>/dev/null; then
    printf 'cstk serve: erro: porta fora do intervalo valido: %s (deve ser 1-65535)\n' \
      "$_serve_port" >&2
    return 2
  fi

  # Passo 3: porta privilegiada < 1024? (CHK-R12) — exit 1, nao exit 2
  if [ "$_serve_port" -lt 1024 ]; then
    printf 'cstk serve: erro: porta %s requer privilegio de root no Linux; tente --port 5173 ou porta acima de 1024\n' \
      "$_serve_port" >&2
    return 1
  fi

  # Aviso para host diferente de loopback (FR-004)
  case "$_serve_host" in
    127.0.0.1|localhost) ;;
    *)
      printf 'cstk serve: aviso: --host %s especificado; apenas 127.0.0.1 tem suporte completo no momento\n' \
        "$_serve_host"
      ;;
  esac

  # Pre-req check (ANTES de qualquer rede ou filesystem — FR-006/2.2.3)
  if ! command -v curl >/dev/null 2>&1; then
    printf 'cstk serve: erro: curl nao encontrado no PATH; instale curl para usar este comando\n' >&2
    return 1
  fi
  if ! command -v npm >/dev/null 2>&1; then
    printf 'cstk serve: erro: npm nao encontrado no PATH; instale Node.js em https://nodejs.org\n' >&2
    return 1
  fi

  # Resolver diretorio do painel (FR-007)
  _serve_panel_dir="${CSTK_PANEL_DIR:-${HOME}/.local/share/cstk/panel}"

  # --reinstall: remover instalacao existente antes de qualquer check
  if [ "$_serve_reinstall" = "1" ]; then
    rm -rf -- "$_serve_panel_dir"
  fi

  # --update: se ja instalado, consultar a release mais recente e reinstalar SO
  # se houver versao nova (comparando com .panel-version). Best-effort: se a
  # checagem falhar (offline/API), mantem a versao instalada. Sem efeito quando
  # combinado com --reinstall (o dir ja foi removido acima -> instala a latest).
  if [ "$_serve_update" = "1" ] && _serve_is_installed "$_serve_panel_dir"; then
    printf 'cstk serve: verificando atualizacoes do painel...\n'
    _serve_latest=$(_serve_latest_tag)
    if [ -n "$_serve_latest" ]; then
      _serve_current=$(cat "$_serve_panel_dir/.panel-version" 2>/dev/null | tr -d ' \n')
      if [ "$_serve_latest" != "$_serve_current" ]; then
        printf 'cstk serve: atualizando painel: %s -> %s\n' \
          "${_serve_current:-desconhecida}" "$_serve_latest"
        rm -rf -- "$_serve_panel_dir"
      else
        printf 'cstk serve: painel ja esta na versao mais recente (%s)\n' "$_serve_current"
      fi
    else
      printf 'cstk serve: aviso: nao foi possivel verificar atualizacoes; usando a versao instalada\n' >&2
    fi
  fi

  # Deteccao de instalacao corrompida: dir existe mas sem package.json
  if [ -d "$_serve_panel_dir" ] && ! _serve_is_installed "$_serve_panel_dir"; then
    printf 'cstk serve: erro: diretorio do painel existe mas esta incompleto ou corrompido: %s\n' \
      "$_serve_panel_dir" >&2
    printf 'cstk serve: use --reinstall para reinstalar do zero\n' >&2
    return 1
  fi

  # Lazy-install: so instalar se nao instalado
  if ! _serve_is_installed "$_serve_panel_dir"; then
    if ! _serve_install "$_serve_panel_dir"; then
      return 1
    fi
  fi

  # Exibir versao instalada se .panel-version presente
  if [ -f "$_serve_panel_dir/.panel-version" ]; then
    _serve_version=$(cat "$_serve_panel_dir/.panel-version" 2>/dev/null)
    if [ -n "$_serve_version" ]; then
      printf 'cstk serve: usando painel ja instalado (%s)\n' "$_serve_version"
    fi
  fi

  # Modo dev: sobe a API (Fastify, :3001) e o frontend (Vite, :5173) em paralelo
  # via o script `dev` do painel (concurrently). O Vite serve o SPA e proxia
  # /api -> :3001. O painel NAO possui serving estatico em producao (o server
  # Fastify nao registra @fastify/static), por isso `npm run start` — que sobe
  # apenas a API — devolve o envelope JSON 404 em / e nao exibe a interface.
  # NAO exportamos PORT: isso moveria a API para fora de :3001 e quebraria o
  # proxy do Vite. A porta voltada ao usuario e a do Vite (5173).
  if [ "$_serve_port" != "5173" ]; then
    printf 'cstk serve: aviso: em modo dev a UI e servida pelo Vite na porta 5173; --port %s sera ignorado\n' \
      "$_serve_port" >&2
  fi

  printf 'cstk serve: iniciando painel (API + frontend) em http://127.0.0.1:5173  (Ctrl+C para encerrar)\n'

  # Registrar handler de sinal ANTES de iniciar o filho
  trap '_serve_shutdown' INT TERM

  # `npm run dev` (concurrently: API + web) em background para capturar o PID e
  # aguardar; o _serve_shutdown propaga SIGTERM ao grupo (concurrently encerra
  # ambos os filhos).
  (cd "$_serve_panel_dir" && npm run dev) &
  _SERVE_NPM_PID=$!

  # Aguardar filho; propagar exit code
  wait "$_SERVE_NPM_PID"
  _serve_exit=$?

  # Limpar trap
  trap - INT TERM

  # Mensagem de encerramento inesperado (CHK-R07)
  if [ "$_serve_exit" -ne 0 ]; then
    printf 'cstk serve: painel encerrou inesperadamente (exit %d)\n' "$_serve_exit" >&2
  fi

  return "$_serve_exit"
}
