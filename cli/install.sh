#!/bin/sh
# install.sh — bootstrap one-liner installer para `cstk`.
#
# Uso esperado:
#   curl -fsSL https://github.com/JotJunior/cstk/releases/latest/download/install.sh | sh
#
# Comportamento:
#   1. Descobre tag da ultima release via API do GitHub (ou usa $CSTK_RELEASE_URL
#      como override para fixtures de teste).
#   2. Baixa `cstk-<tag>.tar.gz` + `.sha256`; valida checksum (FR-010a).
#   3. Extrai em tempdir; copia `cli/cstk` para `$INSTALL_BIN` (default
#      `~/.local/bin/`) e `cli/lib/*` para `$INSTALL_LIB/lib/` (default
#      `~/.local/share/cstk/lib/`).
#   4. Escreve `$INSTALL_LIB/VERSION` com a tag baixada.
#   5. Avisa se `$INSTALL_BIN` nao esta no PATH (sem modificar shell rc).
#
# NAO exige sudo, NAO baixa toolchain de build, NAO modifica shell rc do usuario.
#
# Variaveis de ambiente honradas (todas opcionais):
#   CSTK_RELEASE_URL  — URL exata do tarball (skipa GitHub API). Sha vem de URL+".sha256".
#   CSTK_REPO         — owner/repo no GitHub. Default: JotJunior/cstk.
#   INSTALL_BIN       — onde colocar o binario `cstk`. Default: ~/.local/bin.
#   INSTALL_LIB       — onde colocar lib/+VERSION. Default: ~/.local/share/cstk.
#
# POSIX sh puro. Deps: curl, tar, mktemp, sha256sum OU shasum, sed, grep, head,
# mkdir, mv, cp, rm, find, dirname, basename, command, printf, cat.
#
# Ref: docs/specs/cstk-cli/spec.md FR-005a, FR-010a; tasks.md 3.2

set -eu

# ==== Configuracao ====

CSTK_REPO="${CSTK_REPO:-JotJunior/cstk}"
INSTALL_BIN="${INSTALL_BIN:-${HOME:?HOME nao setado}/.local/bin}"
INSTALL_LIB="${INSTALL_LIB:-${HOME}/.local/share/cstk}"

# ==== Helpers ====

log_info() { printf '[info] %s\n' "$*" >&2; }
log_warn() { printf '[warn] %s\n' "$*" >&2; }
log_error() { printf '[error] %s\n' "$*" >&2; }

die() {
  log_error "$@"
  exit 1
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    die "comando obrigatorio ausente: $1"
  fi
}

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -- "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 -- "$1" | awk '{print $1}'
  else
    die "nem sha256sum nem shasum encontrados"
  fi
}

# parse_tag_from_api: extrai "tag_name" do JSON da API GitHub releases.
# Sem `jq` (Constitution Principio II + carve-out 1.1.0 confina jq a hooks.sh).
# Regex foca no primeiro `tag_name` do payload.
parse_tag_from_api() {
  grep -o '"tag_name":[[:space:]]*"[^"]*"' \
    | head -n 1 \
    | sed 's/.*"\([^"]*\)"$/\1/'
}

# ==== Resolucao de URLs ====

resolve_urls() {
  if [ -n "${CSTK_RELEASE_URL:-}" ]; then
    TARBALL_URL=$CSTK_RELEASE_URL
    SHA_URL="${CSTK_RELEASE_URL}.sha256"
    # Tag derivavel do filename (cstk-<tag>.tar.gz). Fallback "fixture" se nao casar.
    TAG=$(printf '%s' "$CSTK_RELEASE_URL" \
            | sed -n 's|.*/cstk-\([^/]*\)\.tar\.gz$|\1|p')
    if [ -z "$TAG" ]; then
      TAG="fixture-local"
    fi
    log_info "usando CSTK_RELEASE_URL (tag inferida: $TAG)"
    return 0
  fi

  log_info "consultando ultima release de $CSTK_REPO via API GitHub..."
  api_url="https://api.github.com/repos/$CSTK_REPO/releases/latest"
  api_response=$(curl -fsSL --connect-timeout 10 --max-time 60 "$api_url" 2>/dev/null) \
    || die "falha ao consultar $api_url (offline ou repo sem releases?)"

  TAG=$(printf '%s\n' "$api_response" | parse_tag_from_api)
  if [ -z "$TAG" ]; then
    die "nao encontrei tag_name em $api_url"
  fi

  # build-release.sh strip o prefixo "v" do filename (TARBALL_NAME=cstk-${VERSION#v}).
  # Tag remota mantem o "v"; o nome do asset NAO tem. Match obrigatorio.
  TAG_BARE=${TAG#v}
  TARBALL_URL="https://github.com/$CSTK_REPO/releases/download/$TAG/cstk-$TAG_BARE.tar.gz"
  SHA_URL="${TARBALL_URL}.sha256"
  log_info "ultima release: $TAG"
  return 0
}

# ==== Download + verificacao ====

download_and_verify() {
  STAGED=$(mktemp -d 2>/dev/null) || die "mktemp -d falhou"
  trap 'rm -rf -- "$STAGED" 2>/dev/null || :' EXIT INT TERM

  TAR_FILE="$STAGED/cstk.tar.gz"
  SHA_FILE="$STAGED/cstk.tar.gz.sha256"

  log_info "baixando tarball: $TARBALL_URL"
  curl -fsSL --connect-timeout 10 --max-time 300 -o "$TAR_FILE" "$TARBALL_URL" \
    || die "download do tarball falhou: $TARBALL_URL"

  log_info "baixando .sha256: $SHA_URL"
  curl -fsSL --connect-timeout 10 --max-time 60 -o "$SHA_FILE" "$SHA_URL" \
    || die "download do .sha256 falhou: $SHA_URL"

  expected=$(awk 'NF>=1 {print $1; exit}' "$SHA_FILE")
  [ -n "$expected" ] || die "$SHA_URL vazio ou malformado"

  actual=$(sha256_of "$TAR_FILE")
  if [ "$expected" != "$actual" ]; then
    log_error "checksum MISMATCH (FR-010a) — abortando sem escrita"
    log_error "  esperado: $expected"
    log_error "  obtido:   $actual"
    exit 1
  fi
  log_info "checksum OK ($expected)"
}

# ==== Extracao + instalacao ====

extract_and_install() {
  EXTRACT_DIR="$STAGED/extracted"
  mkdir -p "$EXTRACT_DIR"
  tar -xzf "$TAR_FILE" -C "$EXTRACT_DIR" 2>/dev/null \
    || die "falha ao extrair $TAR_FILE"

  # Localiza cli/cstk e cli/lib/ na arvore extraida (tarball pode ter dir-raiz
  # cstk-<tag>/ ou nao, dependendo de como foi empacotado).
  src_cstk=$(find "$EXTRACT_DIR" -type f -path '*/cli/cstk' 2>/dev/null | head -1)
  src_lib=$(find "$EXTRACT_DIR" -type d -path '*/cli/lib' 2>/dev/null | head -1)

  [ -n "$src_cstk" ] && [ -f "$src_cstk" ] || die "tarball nao contem cli/cstk"
  [ -n "$src_lib" ] && [ -d "$src_lib" ] || die "tarball nao contem cli/lib/"

  log_info "instalando em $INSTALL_BIN/cstk e $INSTALL_LIB/lib/"

  mkdir -p -- "$INSTALL_BIN" || die "nao foi possivel criar $INSTALL_BIN"
  mkdir -p -- "$INSTALL_LIB/lib" || die "nao foi possivel criar $INSTALL_LIB/lib"

  # Substituicao atomica do binario: stage com sed do CSTK_EMBEDDED_VERSION,
  # depois mv. Embedded version e essencial pro boot-check de FASE 5 (FR-006c).
  sed "s/^CSTK_EMBEDDED_VERSION=.*/CSTK_EMBEDDED_VERSION=\"$TAG\"/" \
    "$src_cstk" > "$INSTALL_BIN/cstk.new" || die "sed do cstk falhou"
  chmod +x "$INSTALL_BIN/cstk.new"
  mv -f -- "$INSTALL_BIN/cstk.new" "$INSTALL_BIN/cstk" \
    || die "mv atomico do cstk falhou"

  # Substituicao da lib: limpa antiga + copia nova (bootstrap, primeira inst.,
  # atomicidade par bin+lib estrita fica no `cstk self-update` da FASE 5).
  rm -rf -- "$INSTALL_LIB/lib" 2>/dev/null || :
  mkdir -p -- "$INSTALL_LIB/lib"
  cp -R -- "$src_lib"/. "$INSTALL_LIB/lib/" || die "cp da lib falhou"

  # VERSION em DUAS posicoes:
  #   $INSTALL_LIB/lib/VERSION — atomic-com-lib; usado pelo boot-check (FR-006c)
  #   $INSTALL_LIB/VERSION     — legado/display; usado por `cstk --version`
  # Ambos contem a mesma tag; self-update mantem ambos sincronizados.
  printf '%s\n' "$TAG" > "$INSTALL_LIB/lib/VERSION" || die "escrita de lib/VERSION falhou"
  printf '%s\n' "$TAG" > "$INSTALL_LIB/VERSION" || die "escrita de VERSION falhou"

  log_info "cstk $TAG instalado"
}

# ==== PATH check ====

path_check() {
  case ":${PATH:-}:" in
    *":$INSTALL_BIN:"*)
      log_info "$INSTALL_BIN ja esta no PATH"
      ;;
    *)
      log_warn "$INSTALL_BIN NAO esta no PATH"
      cat >&2 <<EOF

Para usar 'cstk' diretamente, adicione esta linha ao seu shell rc
(.bashrc, .zshrc, .profile — escolha o que voce usa):

    export PATH="\$HOME/.local/bin:\$PATH"

Depois rode \`source <arquivo>\` ou abra um novo terminal.
EOF
      ;;
  esac
}

# ==== Main ====

main() {
  require_cmd curl
  require_cmd tar
  require_cmd mktemp

  resolve_urls
  download_and_verify
  extract_and_install
  path_check

  log_info "bootstrap concluido. Teste com: $INSTALL_BIN/cstk --version"
}

main "$@"
