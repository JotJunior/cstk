# serve.sh — implementa o subcomando `cstk serve`.
#
# Uso: sourced por cli/cstk, entao chamado via serve_main "$@".
#
# Contrato publico:
#   serve_main [--port P] [--host H] [--reinstall] [--update]
#              [--allow-unverified] [--help]
#     exit 0  sucesso (painel rodando ou --help)
#     exit 1  erro geral (prereq ausente, download falhou, instalacao
#             corrompida, integridade nao confirmada sem bypass explicito)
#     exit 2  uso incorreto (porta invalida, flag desconhecida)
#
# Dependencias internas (sourced via $CSTK_LIB):
#   http.sh    -> http_download, http_check_url
#   compat.sh  -> sha256_file
#
# Decisao de design (research.md D2):
#   cli/lib/tarball.sh::download_and_verify NAO e reutilizado porque exige
#   sha256_url e aborta na ausencia. cstk-panel nao publica .sha256 de forma
#   confiavel; serve.sh implementa fluxo proprio de integridade FAIL-CLOSED
#   (enforced-guards US2, research.md Decision 6, FR-008/009/010/011): sem
#   `.sha256` verificavel, BLOQUEIA por padrao (outcome unverifiable-blocked).
#   Bypass explicito via `--allow-unverified` ou `CSTK_SERVE_ALLOW_UNVERIFIED=1`
#   e o UNICO caminho para prosseguir (outcome unverifiable-bypassed), sempre
#   com aviso de alta visibilidade em stderr + linha auditavel em
#   `<cwd>/.claude/enforcement-log.jsonl` (mesmo arquivo do hook US1,
#   `source:"serve-integrity"` — contract enforcement-log.md). Divergencia de
#   checksum (`.sha256` presente mas nao confere) permanece bloqueio absoluto
#   (outcome mismatch-blocked) — o bypass NUNCA se aplica a esse caso.
#
# POSIX sh puro — sem Bash-isms (nao usa [[ ]], arrays, local, source, <<<).
# Deps opcionais confinadas: npm, node (runtime do painel, nao do cstk).
# curl e usado via http.sh (nao diretamente). SEM jq (Principio II — jq e um
# carve-out confinado a pretooluse-bash-guard.sh, research.md Decision 2, nao
# uma dependencia livre para todo o runtime); a linha JSONL de
# `enforcement-log.jsonl` e composta via printf + escaping manual
# (`_serve_json_escape`, mesmo padrao de global/skills/review-features/
# scripts/aggregate.sh::json_escape).

if [ "${_SERVE_LOADED:-}" = "1" ]; then
  return 0
fi
_SERVE_LOADED=1

# Allowlist de hosts confiaveis para download do tarball do painel
# (S2/CHK-S03/FR-012) agora vive em cli/lib/trusted-hosts.sh, compartilhada
# com install.sh/self-update.sh (enforced-guards US3, Decision 7 — reuso, nao
# 3 constantes divergentes). Sourced aqui em vez de function-local porque e
# so uma constante + funcao pura (sem I/O), consumida pelos 2 call sites de
# _serve_check_host_allowlist dentro de _serve_install.
# shellcheck source=/dev/null
. "${CSTK_LIB:?CSTK_LIB must be set}/trusted-hosts.sh"

# URL da API do GitHub para consultar o release mais recente.
_SERVE_GITHUB_API="https://api.github.com/repos/JotJunior/cstk-panel/releases/latest"

# _serve_check_host_allowlist URL
# Wrapper fino sobre trusted_host_check (cli/lib/trusted-hosts.sh). Mantido
# com o mesmo nome/assinatura para nao alterar os pontos de chamada
# existentes dentro de _serve_install nem o comportamento observavel (US3
# task 4.2 — a allowlist e a logica de comparacao agora vem da fonte
# compartilhada, mas o exit code e o formato geral da mensagem permanecem
# equivalentes em qualidade).
# exit 0 = ok; exit 1 = rejeitado (mensagem em stderr).
_serve_check_host_allowlist() {
  trusted_host_check "$1"
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

# _serve_json_escape STRING -> imprime STRING com \ e " escapados (sem jq —
# serve.sh permanece POSIX puro sem dependencia nova, Principio II). Mesmo
# padrao de global/skills/review-features/scripts/aggregate.sh::json_escape.
_serve_json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# _serve_write_integrity_log OUTCOME PACKAGE_URL EXPECTED ACTUAL BYPASS_METHOD
# Append best-effort de uma linha "serve-integrity" no MESMO
# <cwd>/.claude/enforcement-log.jsonl usado por pretooluse-bash-guard.sh
# (contract enforcement-log.md; data-model.md::IntegrityVerificationOutcome).
# OUTCOME esperado: unverifiable-blocked | unverifiable-bypassed |
# mismatch-blocked. NUNCA chamar para "verified" (task 3.3.3 — sucesso
# silencioso, sem linha; o caso feliz ja e coberto pelo printf informativo).
# EXPECTED/ACTUAL/BYPASS_METHOD: "" quando nao aplicavel -> vira `null` no
# JSON emitido (data-model.md: expected_sha256/actual_sha256/bypass_method
# sao nullable). <cwd> = diretorio de trabalho no momento da chamada — mesma
# convencao de <projeto-alvo>/.claude usada em todo o resto do contrato
# (dec-034: nao usar CSTK_PANEL_DIR, que e cache fixo COMPARTILHADO entre
# projetos, nao um "projeto-alvo").
# Falha de escrita NUNCA aborta o fluxo de serve — so aviso em stderr (mesma
# semantica best-effort do escritor US1 em pretooluse-bash-guard.sh).
_serve_write_integrity_log() {
  _swl_outcome="$1"
  _swl_pkg_url="$2"
  _swl_expected="$3"
  _swl_actual="$4"
  _swl_bypass="$5"

  _swl_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || _swl_ts=""
  _swl_dir="$(pwd)/.claude"

  _swl_url_j=$(_serve_json_escape "$_swl_pkg_url")

  if [ -n "$_swl_expected" ]; then
    _swl_expected_j="\"$(_serve_json_escape "$_swl_expected")\""
  else
    _swl_expected_j="null"
  fi
  if [ -n "$_swl_actual" ]; then
    _swl_actual_j="\"$(_serve_json_escape "$_swl_actual")\""
  else
    _swl_actual_j="null"
  fi
  if [ -n "$_swl_bypass" ]; then
    _swl_bypass_j="\"$(_serve_json_escape "$_swl_bypass")\""
  else
    _swl_bypass_j="null"
  fi

  _swl_line=$(printf '{"source":"serve-integrity","timestamp":"%s","outcome":"%s","package_url":"%s","expected_sha256":%s,"actual_sha256":%s,"bypass_method":%s}' \
    "$_swl_ts" "$_swl_outcome" "$_swl_url_j" "$_swl_expected_j" "$_swl_actual_j" "$_swl_bypass_j")

  mkdir -p "$_swl_dir" 2>/dev/null || :
  printf '%s\n' "$_swl_line" >>"$_swl_dir/enforcement-log.jsonl" 2>/dev/null \
    || printf 'cstk serve: aviso: falha ao gravar enforcement-log.jsonl\n' >&2
  return 0
}

# _serve_install PANEL_DIR [ALLOW_UNVERIFIED] [BYPASS_METHOD]
# Realiza o download e instalacao do painel em PANEL_DIR.
# Usa tmpdir privado; move atomicamente para PANEL_DIR apos sucesso.
# ALLOW_UNVERIFIED: "1" bypassa o bloqueio fail-closed quando a integridade
#   nao pode ser confirmada (default "0" — bloqueia). NUNCA bypassa
#   divergencia de checksum (mismatch — regressao FR-010, task 3.4).
# BYPASS_METHOD: "flag" | "env" | "" — origem do bypass, registrada no log
#   quando ALLOW_UNVERIFIED=1 (data-model.md::bypass_method).
# exit 0 = ok; exit 1 = falha (PANEL_DIR inalterado, inclusive por integridade
#   nao confirmada/divergente).
_serve_install() {
  _si_panel_dir="$1"
  _si_allow_unverified="${2:-0}"
  _si_bypass_method="${3:-}"

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

  # Integridade FAIL-CLOSED (enforced-guards US2 — FR-008/009/010/011):
  # por padrao, cstk serve MUST NOT iniciar a partir de um pacote cuja
  # integridade nao foi confirmada (task 3.1). Bypass explicito via
  # --allow-unverified/CSTK_SERVE_ALLOW_UNVERIFIED=1 e o UNICO caminho para
  # prosseguir sem .sha256 (task 3.2) — NUNCA aplicavel quando o .sha256
  # EXISTE mas diverge (mismatch permanece bloqueio absoluto, regressao
  # FR-010/task 3.4).
  _si_sha256_url="${_si_tarball}.sha256"
  _si_sha256_file="$_si_tmp/archive.tar.gz.sha256"
  _si_expected=""
  _si_actual=""

  if _serve_check_host_allowlist "$_si_sha256_url" 2>/dev/null && \
     http_download "$_si_sha256_url" "$_si_sha256_file" 2>/dev/null; then
    _si_expected=$(awk '{print $1}' "$_si_sha256_file" 2>/dev/null)
    _si_actual=$(sha256_file "$_si_archive" 2>/dev/null)
  fi

  if [ -n "$_si_expected" ] && [ -n "$_si_actual" ]; then
    # .sha256 obtido e ambos os hashes sao calculaveis -> comparacao definitiva.
    if [ "$_si_expected" != "$_si_actual" ]; then
      printf 'cstk serve: erro: checksum SHA-256 nao confere (integridade comprometida)\n' >&2
      _serve_write_integrity_log "mismatch-blocked" "$_si_tarball" "$_si_expected" "$_si_actual" ""
      rm -rf -- "$_si_tmp"
      return 1
    fi
    printf 'cstk serve: integridade verificada (SHA-256 ok)\n'
    # outcome=verified: sucesso silencioso, SEM linha no enforcement-log
    # (task 3.3.3 — caso feliz ja coberto pelo printf acima).
  else
    # Nao-verificavel: .sha256 ausente, host fora da allowlist, download
    # falhou, ou conteudo ilegivel/vazio. Fail-closed por padrao.
    if [ "$_si_allow_unverified" = "1" ]; then
      printf 'cstk serve: AVISO -- prosseguindo SEM verificacao de integridade (bypass=%s); o pacote baixado NAO foi confirmado\n' \
        "${_si_bypass_method:-desconhecido}" >&2
      _serve_write_integrity_log "unverifiable-bypassed" "$_si_tarball" "" "" "$_si_bypass_method"
    else
      printf 'cstk serve: erro: integridade do pacote nao pode ser confirmada (.sha256 indisponivel)\n' >&2
      printf 'cstk serve: use --allow-unverified ou defina CSTK_SERVE_ALLOW_UNVERIFIED=1 para prosseguir conscientemente (risco: pacote nao verificado)\n' >&2
      _serve_write_integrity_log "unverifiable-blocked" "$_si_tarball" "" "" ""
      rm -rf -- "$_si_tmp"
      return 1
    fi
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
  _serve_allow_unverified=0
  _serve_bypass_method=""

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
      --allow-unverified)
        _serve_allow_unverified=1
        _serve_bypass_method="flag"
        ;;
      --help|-h)
        cat <<'HELP'
Usage: cstk serve [--port PORT] [--host HOST] [--update] [--reinstall]
                  [--allow-unverified]

Start the cstk panel web interface. On first run, downloads the latest
release from GitHub and installs it locally. Subsequent runs reuse the
cached installation.

The panel compiles the workspace packages (npm run build) and then runs
`npm run start`: a single Fastify process (requires cstk-panel >= 0.2.0)
that serves both the API and the built SPA on one port. Open
http://127.0.0.1:5173 (or --port) in your browser.

Options:
  --port PORT           Port to listen on (integer 1024-65535; also reads
                        $PORT). The panel server binds this port directly.
  --host HOST           Hostname/IP to bind to (default: 127.0.0.1).
                        Note: only 127.0.0.1 is fully supported; other
                        values are accepted but may not affect the binding.
  --update              Check GitHub for a newer panel release and
                        reinstall only if one exists (otherwise reuse the
                        cached version). Best-effort: if it fails
                        (offline/API error), the installed version is kept
                        and the panel still starts.
  --reinstall           Remove the existing installation and reinstall
                        from the latest GitHub release (unconditional;
                        ignores --update).
  --allow-unverified    Start even when the downloaded package's integrity
                        cannot be confirmed (no .sha256 published). Without
                        this flag (or the env var below), cstk serve
                        refuses to start from an unverified package. A
                        high-visibility warning is always printed to
                        stderr when this bypass is used, and the decision
                        is logged to .claude/enforcement-log.jsonl. Never
                        bypasses a checksum MISMATCH (a published .sha256
                        that does not match the download) -- that always
                        blocks.
  --help, -h            Show this help and exit.

Exit codes:
  0   Panel started (or --help shown).
  1   General error (prereq missing, download failed, install corrupt,
      integrity unverified/mismatched without --allow-unverified).
  2   Usage error (invalid port, unknown flag).

Examples:
  cstk serve                         # build + start (UI on http://127.0.0.1:5173)
  cstk serve --port 8080             # listen on port 8080
  cstk serve --update                # update panel if a newer release exists, then start
  cstk serve --reinstall             # force reinstall then start
  cstk serve --allow-unverified      # proceed even without a confirmed checksum
  cstk serve --help                  # show this help

Environment:
  CSTK_PANEL_DIR                Override install directory
                                (default: ~/.local/share/cstk/panel)
  PORT                          Default port if --port is not given
                                (default: 5173)
  CSTK_SERVE_ALLOW_UNVERIFIED   Set to 1 as a non-interactive equivalent
                                of --allow-unverified (scripts/CI). Same
                                high-visibility warning + audit log applies.
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

  # CSTK_SERVE_ALLOW_UNVERIFIED=1 (env) e um bypass equivalente a
  # --allow-unverified, para uso nao-interativo/scripts/CI (task 3.2.1). A
  # flag explicita tem precedencia se ambos estiverem presentes (o
  # bypass_method registrado reflete a origem que efetivamente decidiu).
  if [ "$_serve_allow_unverified" != "1" ] && [ "${CSTK_SERVE_ALLOW_UNVERIFIED:-}" = "1" ]; then
    _serve_allow_unverified=1
    _serve_bypass_method="env"
  fi

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
    if ! _serve_install "$_serve_panel_dir" "$_serve_allow_unverified" "$_serve_bypass_method"; then
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

  # A partir do cstk-panel >= 0.2.0 o servidor Fastify registra @fastify/static
  # e serve a API + o SPA buildado (apps/web/dist) no MESMO processo e porta —
  # `npm run start` (node apps/server/dist/index.js) sobe tudo, sem modo dev nem
  # proxy do Vite. Exportamos PORT (o servidor le process.env.PORT, default
  # 3001) para que ele binde a porta voltada ao usuario.
  export PORT="$_serve_port"

  # `npm run build` ANTES do start: o tarball baixado e a ARVORE-FONTE (sem
  # dist/). `npm run start` roda o JS compilado e serve `apps/web/dist`; o build
  # compila os workspaces (shared-types + server + web). Sem ele, faltam dist/ do
  # servidor e do SPA. Idempotente; roda a cada start para cobrir instalacoes
  # sem build.
  printf 'cstk serve: compilando painel (npm run build)...\n'
  if ! (cd "$_serve_panel_dir" && npm run build); then
    printf 'cstk serve: erro: npm run build falhou; tente --reinstall\n' >&2
    return 1
  fi

  printf 'cstk serve: iniciando painel em http://127.0.0.1:%s  (Ctrl+C para encerrar)\n' "$_serve_port"

  # Registrar handler de sinal ANTES de iniciar o filho
  trap '_serve_shutdown' INT TERM

  # `npm run start` (processo Fastify unico: API + SPA na mesma porta) em
  # background para capturar o PID e aguardar; _serve_shutdown propaga SIGTERM.
  (cd "$_serve_panel_dir" && npm run start) &
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
