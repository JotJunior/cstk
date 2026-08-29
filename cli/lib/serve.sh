# serve.sh — implementa o subcomando `cstk serve`.
#
# Uso: sourced por cli/cstk, entao chamado via serve_main "$@".
#
# Contrato publico:
#   serve_main [--port P] [--host H] [--reinstall] [--update]
#              [--allow-unverified] [--help]
#     exit 0  sucesso (painel rodando ou --help)
#     exit 1  erro geral (prereq ausente, Node major fora da faixa suportada
#             para instalar, mismatch de ABI com o Node do install, download
#             falhou, instalacao corrompida, integridade nao confirmada sem
#             bypass explicito)
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
#   Fonte VERIFICAVEL preferida (complemento ao D2): o auto-tarball da API
#   (`tarball_url`) NUNCA tem `.sha256` — nao existe como publicar arquivo
#   nesse endpoint, entao por ele so saem outcomes unverifiable-*. Quando a
#   release publica um par de assets `<nome>.tar.gz` + `<nome>.tar.gz.sha256`
#   (mesma convencao do release.yml do proprio cstk),
#   _serve_download_verify_extract usa o ASSET como package_url — unica fonte
#   capaz de outcome `verified`. Sem par completo, fallback ao auto-tarball
#   (comportamento anterior; fail-closed intacto).
#
# POSIX sh puro — sem Bash-isms (nao usa [[ ]], arrays, local, source, <<<).
# Deps opcionais confinadas: npm, node (runtime do painel, nao do cstk).
# curl e usado via http.sh (nao diretamente). SEM jq (Principio II — jq e um
# carve-out confinado a pretooluse-bash-guard.sh, research.md Decision 2, nao
# uma dependencia livre para todo o runtime); a linha JSONL de
# `enforcement-log.jsonl` e composta via printf + escaping manual
# (`_serve_json_escape`, mesmo padrao de plugins/cstk/skills/review-features/
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

# Repositorio de origem das releases do painel (panel-monorepo FR-012).
# O painel deixou de ter repositorio proprio: passou a viver em `panel/` deste
# mesmo repositorio e a ser publicado nas releases do cstk. `CSTK_PANEL_REPO`
# existe para forks/ensaios e e paridade explicita com `CSTK_REPO` de
# cli/install.sh:44 e cli/lib/self-update.sh — antes deste ponto o serve era o
# unico dos tres com o repo hardcoded.
#
# Aceita SOMENTE `owner/repo`: o host permanece fixo em api.github.com por
# construcao da string (FR-013), nunca configuravel. Ver
# docs/specs/panel-monorepo/contracts/serve-asset-selection.md §1 e §7.
_SERVE_PANEL_REPO_DEFAULT="JotJunior/cstk"

# _serve_valid_repo_slug SLUG
# Valida `owner/repo` contra ^[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._-]*$
# em POSIX sh puro (sem grep -E: esta funcao roda no caminho quente do serve).
# Rejeita `..`, `@`, `%`, espaco, barra a mais/a menos e vazio.
# exit 0 = valido; exit 1 = invalido (silencioso; o caller emite a mensagem).
_serve_valid_repo_slug() {
  _svrs_v="$1"
  # Exatamente uma barra, e nao no fim.
  case "$_svrs_v" in
    */*/*|*/) return 1 ;;
    */*) : ;;
    *) return 1 ;;
  esac
  _svrs_owner="${_svrs_v%%/*}"
  _svrs_repo="${_svrs_v#*/}"
  [ -n "$_svrs_owner" ] || return 1
  [ -n "$_svrs_repo" ] || return 1
  # Primeiro caractere de cada parte MUST ser alfanumerico (barra `..` fora).
  case "$_svrs_owner" in [A-Za-z0-9]*) : ;; *) return 1 ;; esac
  case "$_svrs_repo" in [A-Za-z0-9]*) : ;; *) return 1 ;; esac
  # Conjunto de caracteres permitido no restante: [A-Za-z0-9._-].
  case "$_svrs_owner$_svrs_repo" in
    *[!A-Za-z0-9._-]*) return 1 ;;
  esac
  return 0
}

# _serve_panel_api_url [quiet]
# Ecoa a URL da API de release mais recente do repositorio efetivo do painel.
# Fail-closed (exit 1, stderr) quando CSTK_PANEL_REPO esta definido e fora do
# formato: cair silenciosamente no default mascararia configuracao errada
# (contrato §7.1). Valor nao-default e evento AUDITAVEL, nao preferencia
# silenciosa: emite aviso em stderr + linha no enforcement-log (§7.3).
#
# `quiet` suprime SO o anuncio (§7.3) -- nunca a validacao (§7.1) nem a
# allowlist (§7.2). Existe porque os dois call sites rodam na MESMA execucao
# de `--update` e o contrato pede UMA linha de auditoria, nao uma por chamada:
# _serve_latest_tag (best-effort, silencioso por contrato) passa `quiet`, e
# _serve_download_verify_extract -- o caminho que de fato BAIXA o pacote da
# origem sobrescrita, que e quando a proveniencia importa -- anuncia.
# Um guard por variavel NAO serviria aqui: ambos os call sites consomem esta
# funcao via $(...), e a atribuicao morreria no subshell.
_serve_panel_api_url() {
  _spau_quiet="${1:-}"
  _spau_repo="${CSTK_PANEL_REPO:-}"
  if [ -n "$_spau_repo" ]; then
    if ! _serve_valid_repo_slug "$_spau_repo"; then
      printf 'cstk serve: erro: CSTK_PANEL_REPO invalido: %s\n' "$_spau_repo" >&2
      printf 'cstk serve: formato esperado: owner/repo (ex.: %s); apenas [A-Za-z0-9._-], sem barra extra\n' \
        "$_SERVE_PANEL_REPO_DEFAULT" >&2
      printf 'cstk serve: corrija ou remova CSTK_PANEL_REPO do ambiente -- o default NAO e aplicado silenciosamente\n' >&2
      return 1
    fi
  else
    _spau_repo="$_SERVE_PANEL_REPO_DEFAULT"
  fi

  _spau_url="https://api.github.com/repos/${_spau_repo}/releases/latest"

  # §7.2: a URL composta passa pela MESMA allowlist antes do primeiro request,
  # nao so as URLs de asset. Redundante hoje (host literal na string) e defesa
  # em profundidade contra refatoracao futura.
  if ! _serve_check_host_allowlist "$_spau_url"; then
    return 1
  fi

  if [ "$_spau_repo" != "$_SERVE_PANEL_REPO_DEFAULT" ] && [ "$_spau_quiet" != "quiet" ]; then
    printf 'cstk serve: AVISO -- origem do painel sobrescrita via CSTK_PANEL_REPO=%s (default: %s)\n' \
      "$_spau_repo" "$_SERVE_PANEL_REPO_DEFAULT" >&2
    _serve_write_integrity_log "panel-repo-override" "$_spau_url" "" "" ""
  fi

  printf '%s' "$_spau_url"
  return 0
}

# _serve_valid_bare_tag BARE
# Invariante I5 do contrato §3.2: `tag_name` vem da resposta da API (entrada
# nao confiavel) e vira DOIS nomes de caminho -- o asset esperado (§3.2) e o
# diretorio de topo exigido do tarball (§8.3). Logo a forma e validada ANTES
# de qualquer derivacao: ^[0-9A-Za-z][0-9A-Za-z.+-]*$.
# exit 0 = valido; exit 1 = invalido (silencioso; o caller emite a mensagem).
_serve_valid_bare_tag() {
  _svbt_v="$1"
  [ -n "$_svbt_v" ] || return 1
  case "$_svbt_v" in [0-9A-Za-z]*) : ;; *) return 1 ;; esac
  case "$_svbt_v" in *[!0-9A-Za-z.+-]*) return 1 ;; esac
  return 0
}

# _serve_asset_basename URL
# Ecoa o basename da URL apos remover `#fragment` e `?query` (invariante I2).
# A comparacao de §3.2(a) e sobre ESTE valor, nunca sobre a URL inteira.
_serve_asset_basename() {
  _sab_v="$1"
  _sab_v="${_sab_v%%#*}"
  _sab_v="${_sab_v%%\?*}"
  _sab_v="${_sab_v##*/}"
  printf '%s' "$_sab_v"
}

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

# _serve_check_npm_interop NPM_PATH
# Guard contra o npm do WINDOWS vazando via interop de PATH do WSL: quando
# Node.js nao esta instalado DENTRO da distro WSL, `command -v npm` resolve
# para o binario do Windows (ex.: /mnt/c/Program Files/nodejs/npm). Esse npm
# enxerga a arvore Linux pelo caminho UNC \\wsl.localhost\<distro>\... onde
# symlinks de workspaces falham (EISDIR em node_modules/@cstk-panel/*) e o
# cleanup falha (EPERM rmdir) — npm install quebra SEMPRE. Fail-fast aqui com
# orientacao acionavel em vez de deixar o npm morrer no meio da instalacao.
# Fora do WSL retorna 0 sem verificar nada (Git Bash/MSYS no Windows usa npm
# nativo sobre filesystem local — cenario nao afetado).
# NPM_PATH = caminho resolvido de `command -v npm`.
# exit 0 = npm utilizavel; exit 1 = npm do Windows sob WSL (mensagem em stderr).
_serve_check_npm_interop() {
  _scni_npm="$1"
  # Deteccao de WSL: WSL_DISTRO_NAME e exportada por padrao nas sessoes WSL2;
  # /proc/version contendo "microsoft" cobre contextos sem a env (sudo, cron).
  if [ -z "${WSL_DISTRO_NAME:-}" ] && ! grep -qi microsoft /proc/version 2>/dev/null; then
    return 0
  fi
  # Binario do Windows via interop: vive sob o automount (/mnt/<drive>/ por
  # padrao) ou termina em .exe/.cmd. npm instalado na distro (/usr/bin,
  # ~/.nvm/...) nunca casa com esses padroes.
  case "$_scni_npm" in
    /mnt/*|*.exe|*.cmd) ;;
    *) return 0 ;;
  esac
  printf 'cstk serve: erro: o npm encontrado no PATH e o npm do WINDOWS (%s) acessado via interop do WSL\n' "$_scni_npm" >&2
  printf 'cstk serve: o npm do Windows nao consegue instalar dependencias na arvore de arquivos do Linux (symlinks de workspaces falham no caminho \\\\wsl.localhost\\...)\n' >&2
  printf 'cstk serve: instale Node.js DENTRO da distro WSL (ex.: sudo apt install nodejs npm, ou via nvm) ou use: cstk serve --docker\n' >&2
  return 1
}

# _serve_is_installed PANEL_DIR
# Retorna 0 se o painel esta instalado (package.json presente e legivel).
# Retorna 1 caso contrario.
_serve_is_installed() {
  _sii_dir="$1"
  [ -f "$_sii_dir/package.json" ]
}

# Majors de Node suportados pela instalacao do painel (issue #113).
# Fonte: engines do cstk-panel >= 0.28.0 ("20.x || 22.x || 23.x || 24.x"),
# que espelha o suporte declarado pelo better-sqlite3@12.x (prebuilds ABI
# v115/v127/v131/v137 verificados nos assets das releases v12.4.1+ de
# WiseLibs/better-sqlite3). Atualizar em sincronia quando o painel mudar a
# faixa. Constante fixa, NAO overridable via env (mesmo racional de
# CSTK_TRUSTED_RELEASE_HOSTS: muda so em release nova do cstk).
_SERVE_SUPPORTED_NODE_MAJORS="20 22 23 24"

# _serve_node_major
# Ecoa o major da versao do node encontrado no PATH (ex.: "24" para
# v24.19.0). exit 1 (sem eco) se node ausente ou saida fora do formato
# vN.N.N — o caller decide o que fazer com "indetectavel".
_serve_node_major() {
  command -v node >/dev/null 2>&1 || return 1
  _snm_v=$(node -v 2>/dev/null | head -1 | tr -d ' \r\n')
  case "$_snm_v" in
    v[0-9]*) ;;
    *) return 1 ;;
  esac
  _snm_major="${_snm_v#v}"
  _snm_major="${_snm_major%%.*}"
  case "$_snm_major" in
    ''|*[!0-9]*) return 1 ;;
  esac
  printf '%s\n' "$_snm_major"
}

# _serve_node_preflight
# Gate de INSTALACAO (issue #113): valida que o major do Node corrente esta
# na faixa suportada pelo painel ANTES de qualquer download/npm install —
# falha cedo com mensagem acionavel em vez de vazar centenas de linhas de
# node-gyp (better-sqlite3 sem prebuild para o ABI corrente cai em
# compilacao nativa; na linha 9.6.0 do painel < 0.28.0, Node 24 nem
# compilava — APIs de V8 removidas).
# Node indetectavel NAO bloqueia (aviso + prossegue): este e um guard de UX
# de instalacao, nao de seguranca — o npm install continua sendo o
# verificador final. So roda nos caminhos que INSTALAM; servir um painel ja
# instalado e coberto pelo check de mismatch de ABI (.panel-node-major).
# exit 0 = prossegue; exit 1 = major fora da faixa (mensagem em stderr).
_serve_node_preflight() {
  _snp_major=$(_serve_node_major) || {
    printf 'cstk serve: aviso: nao foi possivel detectar a versao do Node; prosseguindo com a instalacao\n' >&2
    return 0
  }
  for _snp_ok in $_SERVE_SUPPORTED_NODE_MAJORS; do
    if [ "$_snp_major" = "$_snp_ok" ]; then
      return 0
    fi
  done
  _snp_list=$(printf '%s' "$_SERVE_SUPPORTED_NODE_MAJORS" | tr ' ' '/')
  printf 'cstk serve: erro: o painel requer Node %s (detectado: Node %s)\n' \
    "$_snp_list" "$_snp_major" >&2
  printf 'cstk serve: use uma versao suportada (ex.: nvm use 22) e tente novamente\n' >&2
  return 1
}

# _serve_latest_tag
# Ecoa a tag_name da release mais recente do painel (via API GitHub) e retorna 0.
# Retorna 1 (silenciosamente) se a rede/API falhar, o JSON nao tiver tag, ou a
# release for prerelease/draft. Best-effort: usado por --update para decidir se
# reinstala — qualquer falha mantem a versao instalada (nunca aborta o serve).
_serve_latest_tag() {
  # shellcheck source=/dev/null
  . "${CSTK_LIB}/http.sh"
  _slt_api=$(_serve_panel_api_url quiet) || return 1
  _slt_tmp=$(mktemp -d 2>/dev/null) || return 1
  if ! http_download "$_slt_api" "$_slt_tmp/release.json" 2>/dev/null; then
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
# padrao de plugins/cstk/skills/review-features/scripts/aggregate.sh::json_escape.
_serve_json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# _serve_write_integrity_log OUTCOME PACKAGE_URL EXPECTED ACTUAL BYPASS_METHOD
# Append best-effort de uma linha "serve-integrity" no MESMO
# <cwd>/.claude/enforcement-log.jsonl usado por pretooluse-bash-guard.sh
# (contract enforcement-log.md; data-model.md::IntegrityVerificationOutcome).
# OUTCOME esperado: unverifiable-blocked | unverifiable-bypassed |
# mismatch-blocked | wrong-payload-blocked | panel-repo-override (os dois
# ultimos de panel-monorepo, contrato serve-asset-selection.md §5 e §7.3; o
# consumidor pretooluse-bash-guard.sh filtra por `source`, sem validar enum
# fechado, entao acrescentar valor e retrocompativel).
# NUNCA chamar para "verified" (task 3.3.3 — sucesso
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

# _serve_validate_tarball_members ARCHIVE EXPECTED_TOPDIR
# Validacao PRE-extracao (contrato §8). Roda apos o checksum e ANTES de
# `tar -x`: checar `package.json` so depois de extrair tem dois defeitos --
# (i) `package.json` presente nao significa "e o painel" (qualquer tarball
# npm passa) e (ii) quando a checagem roda, a arvore hostil JA foi escrita
# em disco.
#
# EXPECTED_TOPDIR = "" desliga SOMENTE a exigencia de nome do diretorio de
# topo (§8.3), preservando §8.2. Usado no fallback ao auto-tarball da API,
# cujo diretorio de topo e `<owner>-<repo>-<sha>/` -- nome que a API escolhe,
# nao derivavel da tag. As checagens estruturais de §8.2 valem em TODO
# caminho de extracao.
#
# Ordem: §8.2 (caminho absoluto, `..`, symlink/hardlink/device) roda ANTES de
# §8.3, para rejeitar `..`/caminho-absoluto antes de `<bare>` entrar em
# comparacao de caminho.
#
# exit 0 = aceito; exit 1 = rejeitado (motivo em stderr, no formato
# `cstk serve: erro: ...`). O caller e quem grava wrong-payload-blocked.
_serve_validate_tarball_members() {
  _svtm_archive="$1"
  _svtm_expect="$2"

  _svtm_names=$(tar -tzf "$_svtm_archive" 2>/dev/null) || {
    printf 'cstk serve: erro: nao foi possivel listar os membros do tarball (arquivo corrompido)\n' >&2
    return 1
  }
  if [ -z "$_svtm_names" ]; then
    printf 'cstk serve: erro: tarball sem membros (pacote vazio)\n' >&2
    return 1
  fi

  # §8.2a -- caminho absoluto ou componente `..` em qualquer membro.
  _svtm_bad=$(printf '%s\n' "$_svtm_names" | awk '
    /^\// { print "absoluto: " $0; exit }
    /(^|\/)\.\.(\/|$)/ { print "componente ..: " $0; exit }
  ')
  if [ -n "$_svtm_bad" ]; then
    printf 'cstk serve: erro: tarball contem caminho inseguro (%s)\n' "$_svtm_bad" >&2
    return 1
  fi

  # §8.2b -- tipos de entrada. Aceitos SOMENTE `-` (arquivo regular) e `d`
  # (diretorio); `l` symlink, `h` hardlink, `c`/`b` device, `p` fifo, `s`
  # socket sao rejeitados. A coluna de tipo e o 1o caractere de cada linha de
  # `tar -tv`, formato comum a bsdtar e GNU tar (verificado empiricamente em
  # bsdtar 3.5.3/libarchive 3.7.4). O NOME nao e parseado daqui (a linha traz
  # ` -> alvo` / ` link to alvo`); nomes vem de `tar -tzf`, acima.
  _svtm_type=$(tar -tvzf "$_svtm_archive" 2>/dev/null | awk '
    { t = substr($0, 1, 1) }
    t != "-" && t != "d" { print t; exit }
  ')
  if [ -n "$_svtm_type" ]; then
    printf 'cstk serve: erro: tarball contem entrada de tipo nao permitido (%s -- symlink/hardlink/device)\n' \
      "$_svtm_type" >&2
    return 1
  fi

  # §8.3 -- um unico diretorio de topo, com o nome exato exigido.
  _svtm_tops=$(printf '%s\n' "$_svtm_names" | sed 's|/.*||' | sort -u | sed '/^$/d')
  _svtm_ntops=$(printf '%s\n' "$_svtm_tops" | wc -l | tr -d ' ')
  if [ "${_svtm_ntops:-0}" != "1" ]; then
    printf 'cstk serve: erro: tarball tem %s diretorios de topo; esperado exatamente 1\n' \
      "${_svtm_ntops:-0}" >&2
    return 1
  fi
  if [ -n "$_svtm_expect" ] && [ "$_svtm_tops" != "$_svtm_expect" ]; then
    printf 'cstk serve: erro: diretorio de topo do tarball e "%s"; esperado "%s"\n' \
      "$_svtm_tops" "$_svtm_expect" >&2
    return 1
  fi

  return 0
}

# _serve_download_verify_extract DEST_DIR [ALLOW_UNVERIFIED] [BYPASS_METHOD]
# Baixa a release mais recente do painel via API GitHub (asset de release
# verificavel preferido; fallback ao auto-tarball — ver "Fonte VERIFICAVEL
# preferida" no cabecalho), aplica a mesma
# allowlist de hosts confiaveis + integridade FAIL-CLOSED ja em producao
# (enforced-guards US2 — FR-008/009/010/011), e extrai o tarball em
# DEST_DIR (sempre recriado do zero — qualquer conteudo pre-existente em
# DEST_DIR e removido ANTES da extracao, garantindo arvore limpa
# independente do estado anterior do caller). Grava DEST_DIR/.panel-version
# com a tag instalada. NAO roda `npm install` nem move nada para fora de
# DEST_DIR — e responsabilidade exclusiva do caller.
#
# Extraido de _serve_install (ate a extracao) para ser reusado por DOIS
# callers sem duplicar o mecanismo de download/verificacao (FR-007):
#   (a) _serve_install (modo nativo, abaixo): apos extrair, roda `npm
#       install` dentro de DEST_DIR, move atomicamente para PANEL_DIR e
#       reconcilia os links de workspace ja no destino.
#   (b) o ponto de entrada do modo alternativo baseado em container (vive
#       no arquivo confinado pelo carve-out do Principio II condicao b,
#       FASE 2 do backlog correspondente): apos extrair, usa DEST_DIR
#       diretamente como contexto de build da imagem local, SEM rodar npm
#       no host (FR-006/host_npm_used=false).
# Nenhum segundo mecanismo de download/allowlist/integridade — MESMO code
# path para os dois modos.
#
# Janela de sinal (Ctrl+C/SIGTERM durante rede/extracao): esta funcao arma
# e desarma seu PROPRIO trap EXIT/INT/TERM sobre o tmpdir efemero de
# download (nao o DEST_DIR do caller), limpo em qualquer saida com erro.
# Em sucesso, o trap e desarmado ANTES de retornar — o caller fica livre
# para armar o proprio trap para a janela seguinte (ex.: npm install) sem
# risco de um trap sobrescrever o outro (nenhuma sobreposicao de posse).
#
# ALLOW_UNVERIFIED: "1" bypassa o bloqueio fail-closed quando a integridade
#   nao pode ser confirmada (default "0" — bloqueia). NUNCA bypassa
#   divergencia de checksum (mismatch — regressao FR-010, task 3.4).
# BYPASS_METHOD: "flag" | "env" | "" — origem do bypass, registrada no log
#   quando ALLOW_UNVERIFIED=1 (data-model.md::bypass_method).
# exit 0 = ok (DEST_DIR populado + .panel-version); exit 1 = falha (DEST_DIR
#   pode ter sido removido/recriado vazio, nunca deixado pela metade).
_serve_download_verify_extract() {
  _sdve_dest="$1"
  _sdve_allow_unverified="${2:-0}"
  _sdve_bypass_method="${3:-}"

  # Sourcear helpers de rede e checksum
  # shellcheck source=/dev/null
  . "${CSTK_LIB}/http.sh"
  # shellcheck source=/dev/null
  . "${CSTK_LIB}/compat.sh"

  # Tmpdir privado (SOMENTE para release.json/archive.tar.gz -- nunca
  # DEST_DIR, que e o caminho persistente escolhido pelo caller) com
  # cleanup garantido via trap durante toda a janela de rede.
  _sdve_tmp=$(mktemp -d 2>/dev/null) || {
    printf 'cstk serve: erro: nao foi possivel criar tmpdir\n' >&2
    return 1
  }
  trap 'rm -rf -- "$_sdve_tmp"' EXIT INT TERM

  printf 'cstk serve: consultando GitHub para release mais recente...\n'

  # Consulta API GitHub (CHK-R26: falha HTTP -> exit 1). A URL vem de
  # _serve_panel_api_url: CSTK_PANEL_REPO validado fail-closed + allowlist de
  # host aplicada ANTES do primeiro request (contrato §7).
  _sdve_api_url=$(_serve_panel_api_url) || {
    rm -rf -- "$_sdve_tmp"
    return 1
  }
  _sdve_api_file="$_sdve_tmp/release.json"
  if ! http_download "$_sdve_api_url" "$_sdve_api_file"; then
    printf 'cstk serve: erro: falha ao consultar API do GitHub\n' >&2
    rm -rf -- "$_sdve_tmp"
    return 1
  fi

  # Extrair tag_name e tarball_url via grep/sed POSIX (sem jq)
  _sdve_tag=$(grep -o '"tag_name"[[:space:]]*:[[:space:]]*"[^"]*"' "$_sdve_api_file" \
    | sed 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' | head -1)
  _sdve_tarball=$(grep -o '"tarball_url"[[:space:]]*:[[:space:]]*"[^"]*"' "$_sdve_api_file" \
    | sed 's/.*"tarball_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' | head -1)

  if [ -z "$_sdve_tag" ] || [ -z "$_sdve_tarball" ]; then
    printf 'cstk serve: erro: API nao retornou tag_name ou tarball_url\n' >&2
    rm -rf -- "$_sdve_tmp"
    return 1
  fi

  # CHK-R02: rejeitar prerelease ou draft
  _sdve_prerelease=$(grep -o '"prerelease"[[:space:]]*:[[:space:]]*[a-z]*' "$_sdve_api_file" \
    | sed 's/.*:[[:space:]]*//' | head -1)
  _sdve_draft=$(grep -o '"draft"[[:space:]]*:[[:space:]]*[a-z]*' "$_sdve_api_file" \
    | sed 's/.*:[[:space:]]*//' | head -1)
  if [ "$_sdve_prerelease" = "true" ] || [ "$_sdve_draft" = "true" ]; then
    printf 'cstk serve: erro: release mais recente eh prerelease ou draft; nao instalando\n' >&2
    rm -rf -- "$_sdve_tmp"
    return 1
  fi

  printf 'cstk serve: instalando versao %s...\n' "$_sdve_tag"

  # Fonte verificavel preferida (fecha o gap do research.md D2): o
  # auto-tarball da API nao tem como ter `.sha256` publicado; um par de
  # assets `<nome>.tar.gz` + `<nome>.tar.gz.sha256` na release e a UNICA
  # fonte capaz de outcome `verified`.
  #
  # Selecao NAME-BOUND (panel-monorepo FR-008; contrato §3.2). A regra
  # anterior era POSICIONAL -- "primeiro asset .tar.gz com sibling .sha256"
  # -- e quebrou quando o painel passou a ser publicado nas releases do
  # proprio cstk, que ja carregam `cstk-<bare>.tar.gz` + `.sha256`: o awk
  # escolhia o tarball do TOOLKIT, o checksum CONFERIA (o par esta correto,
  # so e o pacote errado), o outcome virava `verified` -- que por desenho
  # NAO grava no enforcement-log -- e a falha so aparecia depois, em
  # "package.json ausente apos extracao". Carimbo de integridade sobre o
  # pacote errado, sem rastro.
  #
  #   EXPECTED = "cstk-panel-" + bare(tag_name) + ".tar.gz"
  #   (a) basename(URL), sem ?query/#fragment, IGUAL a EXPECTED   [I1, I2]
  #   (b) URL + ".sha256" existe na MESMA release (igualdade de string)
  #
  # I1: igualdade, NUNCA prefixo/substring -- `cstk-` e prefixo proprio de
  # `cstk-panel-`, e `cstk-panel-` e prefixo de `cstk-panel-docs-`; relaxar
  # para prefixo reabre a confusao de asset por outra porta.
  # I3: sem candidato satisfazendo (a)+(b), fallback ao auto-tarball --
  # NUNCA selecionar outro asset. "Nao achei o do painel" jamais vira
  # "entao levo esse outro".
  # I4: como EXPECTED deriva da tag, o nome fica vinculado a VERSAO da
  # release: asset de painel de outra versao na mesma release nao casa.
  _sdve_bare="${_sdve_tag#v}"
  _sdve_asset_pkg=""
  _sdve_is_panel_asset=0

  # I5: `tag_name` vem da API (entrada nao confiavel) e vira nome de caminho
  # em DOIS lugares (EXPECTED aqui, diretorio de topo em §8.3). Forma
  # validada ANTES de qualquer derivacao; fora do formato = fail-closed para
  # o auto-tarball, com linha em stderr.
  if ! _serve_valid_bare_tag "$_sdve_bare"; then
    printf 'cstk serve: aviso: tag_name da release ("%s") fora do formato esperado; ignorando assets e usando o tarball da API\n' \
      "$_sdve_tag" >&2
  else
    _sdve_expected_asset="cstk-panel-${_sdve_bare}.tar.gz"
    _sdve_assets=$(grep -o '"browser_download_url"[[:space:]]*:[[:space:]]*"[^"]*"' "$_sdve_api_file" \
      | sed 's/.*"browser_download_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
    _sdve_asset_pkg=$(printf '%s\n' "$_sdve_assets" \
      | awk -v want="$_sdve_expected_asset" '
      { seen[$0] = 1; url[NR] = $0 }
      END {
        for (i = 1; i <= NR; i++) {
          u = url[i]
          b = u
          sub(/#.*$/, "", b)
          sub(/\?.*$/, "", b)
          sub(/^.*\//, "", b)
          # I2: basename com `%` e rejeitado, para nao casar via
          # percent-encoding.
          if (index(b, "%") > 0) continue
          if (b == want && ((u ".sha256") in seen)) { print u; exit }
        }
      }')
  fi

  if [ -n "$_sdve_asset_pkg" ]; then
    _sdve_pkg_url="$_sdve_asset_pkg"
    _sdve_sha256_url="${_sdve_asset_pkg}.sha256"
    _sdve_is_panel_asset=1
    printf 'cstk serve: release publica asset verificavel; baixando %s\n' "$_sdve_pkg_url"
  else
    _sdve_pkg_url="$_sdve_tarball"
    _sdve_sha256_url="${_sdve_tarball}.sha256"
  fi

  # S2/CHK-S03/CHK-S04: validar host e schema da URL do pacote (asset ou
  # auto-tarball — ambas vem do JSON da API e passam pela MESMA allowlist)
  if ! _serve_check_host_allowlist "$_sdve_pkg_url"; then
    rm -rf -- "$_sdve_tmp"
    return 1
  fi

  # Download do pacote (CHK-R03: timeouts via http.sh)
  _sdve_archive="$_sdve_tmp/archive.tar.gz"
  if ! http_download "$_sdve_pkg_url" "$_sdve_archive"; then
    printf 'cstk serve: erro: falha ao baixar tarball do painel\n' >&2
    rm -rf -- "$_sdve_tmp"
    return 1
  fi

  # CHK-R23: verificar tamanho minimo do tarball (>= 1024 bytes)
  _sdve_size=$(wc -c < "$_sdve_archive" 2>/dev/null | tr -d ' ')
  if [ "${_sdve_size:-0}" -lt 1024 ] 2>/dev/null; then
    printf 'cstk serve: erro: tarball baixado parece vazio ou truncado (%s bytes)\n' \
      "${_sdve_size:-0}" >&2
    rm -rf -- "$_sdve_tmp"
    return 1
  fi

  # Integridade FAIL-CLOSED (enforced-guards US2 — FR-008/009/010/011):
  # por padrao, cstk serve MUST NOT iniciar a partir de um pacote cuja
  # integridade nao foi confirmada (task 3.1). Bypass explicito via
  # --allow-unverified/CSTK_SERVE_ALLOW_UNVERIFIED=1 e o UNICO caminho para
  # prosseguir sem .sha256 (task 3.2) — NUNCA aplicavel quando o .sha256
  # EXISTE mas diverge (mismatch permanece bloqueio absoluto, regressao
  # FR-010/task 3.4). Mesma semantica no modo alternativo (FR-007).
  # _sdve_sha256_url ja resolvida acima, em par com _sdve_pkg_url (asset
  # sibling ou `<tarball_url>.sha256` no fallback).
  _sdve_sha256_file="$_sdve_tmp/archive.tar.gz.sha256"
  _sdve_expected=""
  _sdve_actual=""

  if _serve_check_host_allowlist "$_sdve_sha256_url" 2>/dev/null && \
     http_download "$_sdve_sha256_url" "$_sdve_sha256_file" 2>/dev/null; then
    _sdve_expected=$(awk '{print $1}' "$_sdve_sha256_file" 2>/dev/null)
    _sdve_actual=$(sha256_file "$_sdve_archive" 2>/dev/null)
  fi

  if [ -n "$_sdve_expected" ] && [ -n "$_sdve_actual" ]; then
    # .sha256 obtido e ambos os hashes sao calculaveis -> comparacao definitiva.
    if [ "$_sdve_expected" != "$_sdve_actual" ]; then
      printf 'cstk serve: erro: checksum SHA-256 nao confere (integridade comprometida)\n' >&2
      _serve_write_integrity_log "mismatch-blocked" "$_sdve_pkg_url" "$_sdve_expected" "$_sdve_actual" ""
      rm -rf -- "$_sdve_tmp"
      return 1
    fi
    printf 'cstk serve: integridade verificada (SHA-256 ok)\n'
    # outcome=verified: sucesso silencioso, SEM linha no enforcement-log
    # (task 3.3.3 — caso feliz ja coberto pelo printf acima).
  else
    # Nao-verificavel: .sha256 ausente, host fora da allowlist, download
    # falhou, ou conteudo ilegivel/vazio. Fail-closed por padrao.
    if [ "$_sdve_allow_unverified" = "1" ]; then
      printf 'cstk serve: AVISO -- prosseguindo SEM verificacao de integridade (bypass=%s); o pacote baixado NAO foi confirmado\n' \
        "${_sdve_bypass_method:-desconhecido}" >&2
      _serve_write_integrity_log "unverifiable-bypassed" "$_sdve_pkg_url" "" "" "$_sdve_bypass_method"
    else
      printf 'cstk serve: erro: integridade do pacote nao pode ser confirmada (.sha256 indisponivel)\n' >&2
      printf 'cstk serve: use --allow-unverified ou defina CSTK_SERVE_ALLOW_UNVERIFIED=1 para prosseguir conscientemente (risco: pacote nao verificado)\n' >&2
      _serve_write_integrity_log "unverifiable-blocked" "$_sdve_pkg_url" "" "" ""
      rm -rf -- "$_sdve_tmp"
      return 1
    fi
  fi

  # Validacao PRE-extracao (contrato §8; FR-009). O checksum ja conferiu --
  # e conferir o checksum prova apenas que o pacote e o que o publicador
  # assinou, NUNCA que e o painel. Rejeitar ANTES de escrever a arvore em
  # disco. O nome do diretorio de topo so e exigido quando a fonte e o asset
  # name-bound: o auto-tarball da API tem topo `<owner>-<repo>-<sha>/`, que
  # nao deriva da tag (§8.3 nao se aplica a ele; §8.2 sim).
  if [ "$_sdve_is_panel_asset" = "1" ]; then
    _sdve_expect_top="cstk-panel-${_sdve_bare}"
  else
    _sdve_expect_top=""
  fi
  if ! _serve_validate_tarball_members "$_sdve_archive" "$_sdve_expect_top"; then
    # Linha DISTINTA em stderr alem do motivo ja emitido pelo validador: o
    # enforcement-log e best-effort e escreve em $(pwd)/.claude, entao um
    # bloqueio de seguranca nunca pode depender so dele (§8, nota final).
    printf 'cstk serve: erro: pacote baixado rejeitado antes da extracao (payload nao e o painel); nada foi escrito em disco\n' >&2
    # expected/actual sao iguais e nao-nulos quando o checksum conferiu --
    # e precisamente essa igualdade que documenta o ponto de FR-009: o
    # checksum conferiu e ainda assim o pacote estava errado. No caminho de
    # bypass explicito nao houve verificacao, e ambos ficam null (honesto).
    _serve_write_integrity_log "wrong-payload-blocked" "$_sdve_pkg_url" \
      "$_sdve_expected" "$_sdve_actual" ""
    rm -rf -- "$_sdve_tmp"
    return 1
  fi

  # Extracao com strip-components=1 -- direto em DEST_DIR (do caller), SEMPRE
  # limpo antes (garante arvore fresca mesmo se DEST_DIR ja existia de uma
  # execucao anterior, ex.: cache do modo alternativo entre invocacoes).
  # --no-same-owner/--no-same-permissions: nao honrar uid/gid nem setuid/
  # setgid vindos do arquivo (§8.4).
  rm -rf -- "$_sdve_dest"
  mkdir -p "$_sdve_dest"
  if ! tar -xzf "$_sdve_archive" --strip-components 1 \
       --no-same-owner --no-same-permissions -C "$_sdve_dest" 2>/dev/null; then
    printf 'cstk serve: erro: falha ao extrair tarball (arquivo corrompido ou sem espaco em disco)\n' >&2
    rm -rf -- "$_sdve_tmp"
    return 1
  fi

  # Backstop pos-extracao (§8.5): package.json na raiz extraida. Deixou de
  # ser a UNICA deteccao -- o outcome wrong-payload-blocked cobre os dois
  # pontos.
  if [ ! -f "$_sdve_dest/package.json" ]; then
    printf 'cstk serve: erro: package.json ausente apos extracao (estrutura de tarball inesperada)\n' >&2
    printf 'cstk serve: erro: pacote baixado rejeitado (payload nao e o painel)\n' >&2
    _serve_write_integrity_log "wrong-payload-blocked" "$_sdve_pkg_url" \
      "$_sdve_expected" "$_sdve_actual" ""
    rm -rf -- "$_sdve_dest"
    rm -rf -- "$_sdve_tmp"
    return 1
  fi

  # Gravar .panel-version com tag_name (viaja com DEST_DIR para onde quer
  # que o caller o mova/use em seguida).
  printf '%s\n' "$_sdve_tag" > "$_sdve_dest/.panel-version"

  rm -rf -- "$_sdve_tmp"
  trap - EXIT INT TERM
  return 0
}

# _serve_reconcile_workspaces DIR
# Reexecuta `npm install` em DIR para reescrever os links de workspace
# apontando para o caminho REAL da arvore (portabilidade Windows).
#
# Por que: o `npm install` da instalacao roda dentro do tmpdir de extracao e
# a arvore e movida depois. Em POSIX o npm materializa os workspaces como
# symlinks RELATIVOS, que sobrevivem intactos ao `mv`; no Windows materializa
# como junctions de caminho ABSOLUTO para o diretorio de origem — que e
# removido em seguida, deixando `node_modules/@cstk-panel/*` pendurado e o
# build morrendo com `TS2307: Cannot find module '@cstk-panel/shared-types'`.
#
# TODO caminho que MOVE a arvore precisa chamar isto DEPOIS do ultimo `mv`:
# a instalacao nova (`_serve_install`, um mv) e o `--update`, que move duas
# vezes (tmpdir -> staging dentro de `_serve_install`, staging -> panel_dir
# no swap). Reconciliar so no staging deixaria os junctions apontando para um
# caminho `.stage.$$` que deixa de existir — o mesmo bug, so que no update.
#
# Custo em POSIX: praticamente no-op (node_modules ja populado) e roda uma
# vez por INSTALACAO, nao por execucao.
#
# NAO remove DIR em caso de falha — a politica de cleanup/rollback e do
# caller (a instalacao nova descarta o dir; o update devolve a versao antiga).
# exit 0 = ok; exit 1 = falha.
_serve_reconcile_workspaces() {
  _srw_dir="$1"
  printf 'cstk serve: reconciliando workspaces em %s...\n' "$_srw_dir"
  if ! (cd "$_srw_dir" && npm install) 2>&1; then
    printf 'cstk serve: erro: reconciliacao dos workspaces falhou\n' >&2
    return 1
  fi
  return 0
}

# _serve_install PANEL_DIR [ALLOW_UNVERIFIED] [BYPASS_METHOD]
# Realiza o download e instalacao do painel em PANEL_DIR.
# Usa tmpdir privado; move atomicamente para PANEL_DIR apos sucesso e entao
# reconcilia os links de workspace no destino (necessario no Windows, onde o
# npm materializa workspaces como junctions de caminho absoluto — ver o
# comentario no ponto da reconciliacao).
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

  _si_wrapper_tmp=$(mktemp -d 2>/dev/null) || {
    printf 'cstk serve: erro: nao foi possivel criar tmpdir\n' >&2
    return 1
  }
  _si_extract="$_si_wrapper_tmp/extracted"

  # Download+allowlist+integridade+extracao (mesmo mecanismo do modo
  # alternativo — FR-007): gerencia seu PROPRIO trap durante a janela de
  # rede, ja desarmado quando retorna (ver cabecalho de _serve_download_verify_extract).
  if ! _serve_download_verify_extract "$_si_extract" "$_si_allow_unverified" "$_si_bypass_method"; then
    rm -rf -- "$_si_wrapper_tmp"
    return 1
  fi

  # A partir daqui armamos NOSSO trap para a janela de npm install + mv
  # (a janela anterior ja foi coberta e desarmada pela funcao acima —
  # nenhuma sobreposicao de posse do trap).
  trap 'rm -rf -- "$_si_wrapper_tmp"' EXIT INT TERM

  # npm install (CHK: falha -> exit 1)
  printf 'cstk serve: executando npm install...\n'
  if ! (cd "$_si_extract" && npm install) 2>&1; then
    printf 'cstk serve: erro: npm install falhou\n' >&2
    rm -rf -- "$_si_wrapper_tmp"
    trap - EXIT INT TERM
    return 1
  fi

  # Registrar o major do Node que rodou o npm install: modulos nativos
  # (better-sqlite3) ficam presos ao ABI desse Node. Consumido no start para
  # detectar mismatch e sugerir --reinstall em vez de estourar erro cru de
  # dlopen (issue #113). Best-effort: node indetectavel -> arquivo ausente
  # -> check no start e pulado (nunca fabricar o valor — Constitution VI).
  if _si_node_major=$(_serve_node_major); then
    printf '%s\n' "$_si_node_major" > "$_si_extract/.panel-node-major"
  fi

  # Move atomico para panel_dir (apos extrair + npm install)
  mkdir -p "$(dirname -- "$_si_panel_dir")"
  if ! mv -- "$_si_extract" "$_si_panel_dir"; then
    printf 'cstk serve: erro: nao foi possivel mover painel para %s\n' "$_si_panel_dir" >&2
    rm -rf -- "$_si_wrapper_tmp"
    trap - EXIT INT TERM
    return 1
  fi

  # .panel-version ja foi escrito por _serve_download_verify_extract dentro
  # de _si_extract, que agora VIVE em _si_panel_dir (o mv leva o arquivo).

  # Reconciliar os links de workspace no diretorio onde a arvore acabou de
  # pousar (ver cabecalho de _serve_reconcile_workspaces). Falha aqui remove
  # o panel_dir para preservar a invariante do caller (`_serve_is_installed`
  # verdadeiro => instalacao completa e utilizavel).
  if ! _serve_reconcile_workspaces "$_si_panel_dir"; then
    [ -n "$_si_panel_dir" ] && rm -rf -- "$_si_panel_dir"
    rm -rf -- "$_si_wrapper_tmp"
    trap - EXIT INT TERM
    return 1
  fi

  # Limpar tmpdir (trap cuida de EXIT mas chamamos explicitamente aqui)
  rm -rf -- "$_si_wrapper_tmp"
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
  _serve_container_mode=0

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
      --docker)
        _serve_container_mode=1
        ;;
      --help|-h)
        cat <<'HELP'
Usage: cstk serve [--port PORT] [--host HOST] [--update] [--reinstall]
                  [--allow-unverified] [--docker]

Start the cstk panel web interface. On first run, downloads the latest
release from GitHub and installs it locally. Subsequent runs reuse the
cached installation. Installing requires a supported Node major
(20/22/23/24 — checked before any download; the panel's native modules
must match better-sqlite3's prebuilt targets). The Node major used at
install time is recorded (.panel-node-major) and checked on later runs:
running under a different major would break the native modules' ABI, so
cstk serve fails early and suggests --reinstall instead of crashing at
startup. When the release publishes a <name>.tar.gz asset
with a matching <name>.tar.gz.sha256, that verifiable asset is preferred
and its SHA-256 is enforced; otherwise the API auto-tarball is used,
whose integrity cannot be confirmed (see --allow-unverified).

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
                        and the panel still starts. The new version is
                        staged in a sibling directory and only swapped in
                        after its npm install succeeds — a failed update
                        never destroys the working installation.
                        With --docker, rebuilds the local image instead of
                        the install directory (same "only if newer"
                        semantics).
  --reinstall           Remove the existing installation and reinstall
                        from the latest GitHub release (unconditional;
                        ignores --update).
                        With --docker, removes the local image and
                        rebuilds it from scratch instead (still always
                        wins over --update, regardless of flag order).
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
  --docker              Run the panel inside a local Docker container
                        instead of natively on the host (opt-in; default
                        behavior is unchanged when this flag is absent).
                        Requires Docker Engine/Desktop installed AND the
                        daemon running, checked before any network access
                        (distinct errors for "not installed" vs "daemon
                        not reachable"). npm/node are never required on
                        the host: a local image is built from the same
                        verified source tree used natively and is never
                        pushed to a registry. Publishes on --host:--port
                        like above (same 127.0.0.1-only-supported caveat).
                        Mounts the knowledge.db directory read-only
                        (~/.claude/cstk, or the directory of
                        $CSTK_KNOWLEDGE_DB) so the panel reflects live
                        index writes without a restart. Runs hardened
                        (non-root, capabilities dropped, read-only rootfs)
                        as a container named "cstk-panel"; a stale one is
                        auto-replaced on each run. Ctrl+C stops it
                        gracefully.
  --help, -h            Show this help and exit.

Exit codes:
  0   Panel started (or --help shown).
  1   General error (prereq missing, unsupported Node major for install,
      Node major differs from the one recorded at install time (native
      ABI mismatch — use --reinstall), download failed, install corrupt,
      integrity unverified/mismatched without --allow-unverified; with
      --docker also: Docker not installed/daemon unreachable, image build
      failed, or a stale container could not be reconciled).
  2   Usage error (invalid port, unknown flag).

Examples:
  cstk serve                         # build + start (UI on http://127.0.0.1:5173)
  cstk serve --port 8080             # listen on port 8080
  cstk serve --update                # update panel if a newer release exists, then start
  cstk serve --reinstall             # force reinstall then start
  cstk serve --allow-unverified      # proceed even without a confirmed checksum
  cstk serve --docker                # run the panel in a local Docker container
  cstk serve --docker --update       # rebuild the image if a newer release exists
  cstk serve --help                  # show this help

Environment:
  CSTK_PANEL_DIR                Override install directory
                                (default: ~/.local/share/cstk/panel)
  PORT                          Default port if --port is not given
                                (default: 5173)
  CSTK_SERVE_ALLOW_UNVERIFIED   Set to 1 as a non-interactive equivalent
                                of --allow-unverified (scripts/CI). Same
                                high-visibility warning + audit log applies.
  CSTK_KNOWLEDGE_DB             Path to knowledge.db; with --docker, its
                                directory is what gets mounted read-only into
                                the container (default:
                                ~/.claude/cstk/knowledge.db).
  CSTK_PANEL_REPO               Override the source repository of the panel
                                release (owner/repo only; the host stays
                                fixed at api.github.com). For forks/
                                rehearsals; same override pattern as
                                CSTK_REPO in cstk install/self-update
                                (default: JotJunior/cstk). A non-default
                                value is audited: warning on stderr + line
                                in .claude/enforcement-log.jsonl.
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

  # Pre-req check (ANTES de qualquer rede ou filesystem — FR-006/2.2.3).
  # curl e exigido em AMBOS os modos (download+verificacao do painel); npm
  # so no modo nativo, abaixo (FR-006 -- o modo alternativo NUNCA precisa
  # de npm no host).
  if ! command -v curl >/dev/null 2>&1; then
    printf 'cstk serve: erro: curl nao encontrado no PATH; instale curl para usar este comando\n' >&2
    return 1
  fi

  # Despacho para o modo alternativo de execucao (flag parseada acima no
  # case): delega 100% da orquestracao ao arquivo confinado pelo carve-out
  # do Principio II condicao b — ver o cabecalho daquele arquivo para o
  # contrato completo, incluindo por que este encaminhamento nao conta como
  # violacao do confinamento. O caminho padrao (flag ausente) abaixo segue
  # 100% inalterado (FR-002); nada aqui e avaliado quando a flag nao foi
  # informada.
  if [ "$_serve_container_mode" = "1" ]; then
    # shellcheck source=/dev/null
    . "${CSTK_LIB}/serve-docker.sh"
    _serve_docker_main "$_serve_port" "$_serve_host" "$_serve_update" "$_serve_reinstall" "$_serve_allow_unverified" "$_serve_bypass_method"
    return $?
  fi

  if ! command -v npm >/dev/null 2>&1; then
    printf 'cstk serve: erro: npm nao encontrado no PATH; instale Node.js em https://nodejs.org\n' >&2
    return 1
  fi

  # Sob WSL, um npm "presente" pode ser o npm do Windows via interop de
  # PATH — inutilizavel sobre a arvore Linux (ver _serve_check_npm_interop).
  if ! _serve_check_npm_interop "$(command -v npm)"; then
    return 1
  fi

  # Resolver diretorio do painel (FR-007)
  _serve_panel_dir="${CSTK_PANEL_DIR:-${HOME}/.local/share/cstk/panel}"

  # Preflight de Node ANTES de qualquer caminho que va instalar (issue #113):
  # cobre a primeira instalacao e o --reinstall (checar DEPOIS do rm abaixo
  # destruiria a instalacao antes de descobrir que o Node corrente nao
  # consegue instalar a nova). O caminho --update faz o proprio preflight
  # adiante, so quando existe versao nova de fato.
  if [ "$_serve_reinstall" = "1" ] || ! _serve_is_installed "$_serve_panel_dir"; then
    if ! _serve_node_preflight; then
      return 1
    fi
  fi

  # --reinstall: remover instalacao existente antes de qualquer check
  if [ "$_serve_reinstall" = "1" ]; then
    rm -rf -- "$_serve_panel_dir"
  fi

  # --update: se ja instalado, consultar a release mais recente e reinstalar SO
  # se houver versao nova (comparando com .panel-version). Best-effort: se a
  # checagem falhar (offline/API), mantem a versao instalada. Sem efeito quando
  # combinado com --reinstall (o dir ja foi removido acima -> instala a latest).
  #
  # A versao instalada NUNCA e destruida antes de a nova estar completa
  # (issue #113): a nova e instalada num diretorio staging IRMAO e so entra
  # no lugar apos npm install bem-sucedido. Falha na instalacao da nova =>
  # aviso + segue servindo a instalada (mesma semantica best-effort da
  # checagem). O rm -rf antecipado anterior deixava o usuario sem painel
  # nenhum quando o npm install da nova falhava (ex.: Node 24 x painel com
  # better-sqlite3 9.6.0).
  if [ "$_serve_update" = "1" ] && _serve_is_installed "$_serve_panel_dir"; then
    printf 'cstk serve: verificando atualizacoes do painel...\n'
    _serve_latest=$(_serve_latest_tag)
    if [ -n "$_serve_latest" ]; then
      _serve_current=$(cat "$_serve_panel_dir/.panel-version" 2>/dev/null | tr -d ' \n')
      if [ "$_serve_latest" != "$_serve_current" ]; then
        printf 'cstk serve: atualizando painel: %s -> %s\n' \
          "${_serve_current:-desconhecida}" "$_serve_latest"
        # Preflight de Node ANTES de baixar/instalar (issue #113): update
        # explicito com Node fora da faixa e erro acionavel, nao um npm
        # install fadado a falhar depois do download.
        if ! _serve_node_preflight; then
          return 1
        fi
        _serve_stage="${_serve_panel_dir}.stage.$$"
        rm -rf -- "$_serve_stage"
        if _serve_install "$_serve_stage" "$_serve_allow_unverified" "$_serve_bypass_method"; then
          _serve_old="${_serve_panel_dir}.old.$$"
          rm -rf -- "$_serve_old"
          if mv -- "$_serve_panel_dir" "$_serve_old" \
            && mv -- "$_serve_stage" "$_serve_panel_dir"; then
            # A arvore acabou de ser movida do staging para o destino: os
            # links de workspace criados dentro de `.stage.$$` precisam ser
            # reescritos para o caminho definitivo (ver
            # _serve_reconcile_workspaces). Sem isto, o update reproduz no
            # Windows exatamente o TS2307 que a instalacao nova ja corrige.
            if _serve_reconcile_workspaces "$_serve_panel_dir"; then
              rm -rf -- "$_serve_old"
            else
              # Mesma invariante da falha de instalacao (issue #113): a
              # versao instalada so e descartada quando a nova esta pronta.
              # Nova incompleta => descartar a nova e devolver a antiga.
              rm -rf -- "$_serve_panel_dir"
              mv -- "$_serve_old" "$_serve_panel_dir" || :
              printf 'cstk serve: aviso: reconciliacao da versao nova falhou; mantendo a versao instalada (%s)\n' \
                "${_serve_current:-desconhecida}" >&2
            fi
          else
            # Swap parou no meio: devolver a versao antiga ao lugar se ela
            # saiu e a nova nao entrou.
            if [ ! -d "$_serve_panel_dir" ] && [ -d "$_serve_old" ]; then
              mv -- "$_serve_old" "$_serve_panel_dir" || :
            fi
            rm -rf -- "$_serve_stage"
            printf 'cstk serve: aviso: falha ao trocar para a versao nova; mantendo a versao instalada (%s)\n' \
              "${_serve_current:-desconhecida}" >&2
          fi
        else
          rm -rf -- "$_serve_stage"
          printf 'cstk serve: aviso: instalacao da versao nova falhou; mantendo a versao instalada (%s)\n' \
            "${_serve_current:-desconhecida}" >&2
        fi
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

  # Lazy-install: so instalar se nao instalado (o preflight de Node deste
  # caminho ja rodou acima, antes do --reinstall poder destruir qualquer
  # coisa).
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

  # Mismatch de ABI entre o Node do install e o Node corrente (issue #113):
  # modulos nativos (better-sqlite3) ficam presos ao ABI do Node que rodou o
  # npm install — cada major de Node tem NODE_MODULE_VERSION distinto, entao
  # major divergente = dlopen falhando com erro criptico no start. Detectar
  # aqui e orientar. So checa quando o install registrou .panel-node-major
  # (instalacoes anteriores a este check nao tem o arquivo -> sem checagem,
  # nunca inferir) e quando o Node corrente e detectavel.
  if [ -f "$_serve_panel_dir/.panel-node-major" ]; then
    _serve_inst_major=$(tr -d ' \n' < "$_serve_panel_dir/.panel-node-major" 2>/dev/null)
    _serve_cur_major=$(_serve_node_major) || _serve_cur_major=""
    if [ -n "$_serve_inst_major" ] && [ -n "$_serve_cur_major" ] \
      && [ "$_serve_inst_major" != "$_serve_cur_major" ]; then
      printf 'cstk serve: erro: o painel instalado foi compilado com Node %s, mas o Node corrente e o %s (modulos nativos sao incompativeis entre majors)\n' \
        "$_serve_inst_major" "$_serve_cur_major" >&2
      printf 'cstk serve: use o Node do install (ex.: nvm use %s) ou reinstale com o Node corrente: cstk serve --reinstall\n' \
        "$_serve_inst_major" >&2
      return 1
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
