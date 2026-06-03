#!/bin/sh
# build-release.sh — build deterministico do tarball de release do cstk.
#
# Ref: docs/specs/cstk-cli/research.md Decisions 5, 6, 10
#      docs/specs/cstk-cli/tasks.md FASE 9.1
#
# Uso:
#   scripts/build-release.sh <version> [--out <dir>]
#
# Produz em <dir> (default: ./dist):
#   cstk-<bare-version>.tar.gz
#   cstk-<bare-version>.tar.gz.sha256
#
# <version> aceita "v0.1.0" ou "0.1.0"; o prefixo "v" e removido para o filename.
#
# Determinismo: rodar 2x consecutivamente produz os mesmos bytes (verificavel
# via SHA-256 identico). Estrategia:
#   - Stage em tempdir (mktemp -d), so depois empacota
#   - mtime de TODOS os arquivos do staged tree normalizado para 1980-01-01
#   - File order: find ... | LC_ALL=C sort  (idem GNU e BSD)
#   - uid/gid normalizados para 0 (flags variam GNU vs BSD; deteccao automatica)
#   - gzip -n para suprimir filename+mtime do header gzip
#   - Sanitizacao de artefatos macOS (.DS_Store, ._*) que poluiriam o tarball
#
# Layout do tarball gerado (alinhado com cli/install.sh e cli/lib/self-update.sh):
#   cstk-<version>/
#   ├── cli/
#   │   ├── cstk
#   │   └── lib/*.sh
#   ├── catalog/
#   │   ├── VERSION
#   │   ├── profiles.txt
#   │   ├── skills/        (espelho de global/skills/)
#   │   ├── commands/      (espelho de global/commands/ — opcional, .md soltos)
#   │   ├── agents/        (espelho de global/agents/   — opcional, .md soltos)
#   │   └── language/      (espelho de language-related/)
#   └── CHANGELOG.md
#
# POSIX sh + tar/gzip/find/sort/touch/sha256sum|shasum.

set -eu

REPO_ROOT="${REPO_ROOT:-$(cd -- "$(dirname -- "$0")/.." && pwd)}"

usage() {
  cat >&2 <<'USAGE'
Uso: scripts/build-release.sh <version> [--out <dir>]

Constroi tarball deterministico de release do cstk.

ARGS:
  <version>     Versao SemVer (ex: v0.1.0 ou 0.1.0)

OPCOES:
  --out DIR     Diretorio de saida. Default: <repo>/dist
  -h, --help    Imprime esta mensagem

SAIDAS:
  <out>/cstk-<version>.tar.gz
  <out>/cstk-<version>.tar.gz.sha256
USAGE
}

VERSION=""
OUT_DIR=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --out)
      [ "$#" -ge 2 ] || { usage; exit 2; }
      OUT_DIR=$2
      shift 2
      ;;
    --out=*)
      OUT_DIR=${1#--out=}
      shift
      ;;
    -*)
      printf 'build-release: flag desconhecida: %s\n' "$1" >&2
      exit 2
      ;;
    *)
      if [ -n "$VERSION" ]; then
        printf 'build-release: VERSION ja fornecida (%s); recebido extra: %s\n' \
          "$VERSION" "$1" >&2
        exit 2
      fi
      VERSION=$1
      shift
      ;;
  esac
done

if [ -z "$VERSION" ]; then
  usage
  exit 2
fi

# Strip leading "v" para o filename; manter ambos para o conteudo.
VERSION_BARE=${VERSION#v}
case "$VERSION_BARE" in
  ""|*[!0-9A-Za-z._-]*)
    printf 'build-release: VERSION invalida: %s\n' "$VERSION" >&2
    exit 2
    ;;
esac

OUT_DIR=${OUT_DIR:-"$REPO_ROOT/dist"}
TARBALL_NAME="cstk-${VERSION_BARE}"
TARBALL_PATH="$OUT_DIR/${TARBALL_NAME}.tar.gz"
SHA_PATH="${TARBALL_PATH}.sha256"

mkdir -p -- "$OUT_DIR"

# ==== Deteccao de tar flavor ====
if tar --version 2>&1 | head -n 1 | grep -qi 'gnu tar'; then
  TAR_FLAVOR=gnu
else
  TAR_FLAVOR=bsd
fi

# ==== sha256 helper ====
if command -v sha256sum >/dev/null 2>&1; then
  _sha256_of() { sha256sum "$1"; }
elif command -v shasum >/dev/null 2>&1; then
  _sha256_of() { shasum -a 256 "$1"; }
else
  printf 'build-release: sha256sum/shasum nao encontrado\n' >&2
  exit 1
fi

# ==== Stage em tempdir ====
STAGE_PARENT=$(mktemp -d 2>/dev/null) || {
  printf 'build-release: mktemp -d falhou\n' >&2
  exit 1
}
trap 'rm -rf -- "$STAGE_PARENT"' EXIT INT TERM
STAGE_ROOT="$STAGE_PARENT/$TARBALL_NAME"
mkdir -p -- "$STAGE_ROOT"

# Desabilita xattrs do macOS no cp (evita ._foo files que quebrariam
# determinismo cross-machine).
COPYFILE_DISABLE=1
export COPYFILE_DISABLE

# ==== 1. cli/cstk + cli/lib/ ====
mkdir -p -- "$STAGE_ROOT/cli/lib"
cp -- "$REPO_ROOT/cli/cstk" "$STAGE_ROOT/cli/cstk"
chmod 755 "$STAGE_ROOT/cli/cstk"
# Copia somente *.sh e README.md de cli/lib/ (nao queremos lixo).
for _f in "$REPO_ROOT/cli/lib/"*.sh; do
  [ -f "$_f" ] || continue
  cp -- "$_f" "$STAGE_ROOT/cli/lib/"
done
if [ -f "$REPO_ROOT/cli/lib/README.md" ]; then
  cp -- "$REPO_ROOT/cli/lib/README.md" "$STAGE_ROOT/cli/lib/"
fi

# ==== 2. catalog/skills/ (mirror de global/skills/) ====
mkdir -p -- "$STAGE_ROOT/catalog/skills"
for _skdir in "$REPO_ROOT/global/skills/"*/; do
  [ -d "$_skdir" ] || continue
  # Trailing slash em "$_skdir" faria cp -R copiar so o conteudo. Calculamos
  # explicitamente o destino para preservar o nome da skill como subdir.
  _skname=$(basename -- "${_skdir%/}")
  cp -R -- "${_skdir%/}" "$STAGE_ROOT/catalog/skills/$_skname"
done

# ==== 2b. catalog/commands/ (mirror de global/commands/, opcional) ====
# Commands sao .md soltos (1 arquivo = 1 command). Diretorio so e criado se
# global/commands/ tiver pelo menos 1 .md — manter o tarball minimal quando o
# toolkit nao expoe commands.
if [ -d "$REPO_ROOT/global/commands" ]; then
  _has_cmd=0
  for _f in "$REPO_ROOT/global/commands/"*.md; do
    [ -f "$_f" ] || continue
    if [ "$_has_cmd" = 0 ]; then
      mkdir -p -- "$STAGE_ROOT/catalog/commands"
      _has_cmd=1
    fi
    cp -- "$_f" "$STAGE_ROOT/catalog/commands/"
  done
fi

# ==== 2c. catalog/agents/ (mirror de global/agents/, opcional) ====
if [ -d "$REPO_ROOT/global/agents" ]; then
  _has_agent=0
  for _f in "$REPO_ROOT/global/agents/"*.md; do
    [ -f "$_f" ] || continue
    if [ "$_has_agent" = 0 ]; then
      mkdir -p -- "$STAGE_ROOT/catalog/agents"
      _has_agent=1
    fi
    cp -- "$_f" "$STAGE_ROOT/catalog/agents/"
  done
fi

# ==== 3. catalog/language/ (mirror de language-related/) ====
mkdir -p -- "$STAGE_ROOT/catalog/language"
for _langdir in "$REPO_ROOT/language-related/"*/; do
  [ -d "$_langdir" ] || continue
  _lang=$(basename -- "${_langdir%/}")
  cp -R -- "${_langdir%/}" "$STAGE_ROOT/catalog/language/$_lang"
done

# ==== 4. catalog/VERSION ====
printf '%s\n' "$VERSION_BARE" > "$STAGE_ROOT/catalog/VERSION"

# ==== 5. catalog/profiles.txt (manual + auto) ====
{
  if [ -f "$REPO_ROOT/scripts/profiles.txt.in" ]; then
    cat -- "$REPO_ROOT/scripts/profiles.txt.in"
  else
    printf '# profiles.txt.in ausente — apenas auto-generated abaixo\n'
  fi
  printf '\n# auto-generated: all + language-*\n'
  # all := every skill in catalog/skills/ + every skill in catalog/language/*/skills/
  {
    for _skdir in "$STAGE_ROOT/catalog/skills/"*/; do
      [ -d "$_skdir" ] || continue
      _skname=$(basename -- "$_skdir")
      printf 'all:%s\n' "$_skname"
    done
    for _langdir in "$STAGE_ROOT/catalog/language/"*/; do
      [ -d "$_langdir/skills" ] || continue
      _lang=$(basename -- "$_langdir")
      for _skdir in "$_langdir/skills/"*/; do
        [ -d "$_skdir" ] || continue
        _skname=$(basename -- "$_skdir")
        printf 'all:%s\n' "$_skname"
        printf 'language-%s:%s\n' "$_lang" "$_skname"
      done
    done
  } | LC_ALL=C sort
} > "$STAGE_ROOT/catalog/profiles.txt"

# ==== 6. CHANGELOG.md + avisos legais (LICENSE, THIRD-PARTY-NOTICES) ====
if [ -f "$REPO_ROOT/CHANGELOG.md" ]; then
  cp -- "$REPO_ROOT/CHANGELOG.md" "$STAGE_ROOT/CHANGELOG.md"
fi
# O tarball carrega o template de constituição adaptado do github/spec-kit
# (MIT); o MIT exige preservar o aviso de copyright nas porções distribuidas.
# Empacotamos LICENSE (do proprio cstk) e THIRD-PARTY-NOTICES junto.
if [ -f "$REPO_ROOT/LICENSE" ]; then
  cp -- "$REPO_ROOT/LICENSE" "$STAGE_ROOT/LICENSE"
fi
if [ -f "$REPO_ROOT/THIRD-PARTY-NOTICES.md" ]; then
  cp -- "$REPO_ROOT/THIRD-PARTY-NOTICES.md" "$STAGE_ROOT/THIRD-PARTY-NOTICES.md"
fi

# ==== 7. Sanitizar artefatos do macOS ====
find "$STAGE_ROOT" \( -name '.DS_Store' -o -name '._*' \) -exec rm -f -- {} +

# ==== 8. Normalizar mtimes (determinismo) ====
# `touch -t YYYYMMDDhhmm.SS` e portavel BSD+GNU. 1980-01-01 e seguro
# para todos os formatos de arquivo (zip, tar, etc.). Aplicamos a TODOS os
# entries (arquivos + diretorios).
find "$STAGE_ROOT" -exec touch -t 198001010000.00 -- {} +

# ==== 9. Empacotar (tar -> stdout -> gzip -n) ====
cd -- "$STAGE_PARENT"
case "$TAR_FLAVOR" in
  gnu)
    tar --sort=name \
        --owner=0 --group=0 --numeric-owner \
        --mtime='1980-01-01 00:00:00 UTC' \
        --format=ustar \
        -cf - "$TARBALL_NAME" \
      | gzip -n > "$TARBALL_PATH"
    ;;
  bsd)
    # bsdtar com -T expande diretorios automaticamente, perdendo a ordem.
    # --no-recursion desabilita essa expansao e respeita a ordem do listfile.
    LISTFILE="$STAGE_PARENT/.filelist"
    find "$TARBALL_NAME" -print | LC_ALL=C sort > "$LISTFILE"
    tar --uid 0 --gid 0 \
        --uname '' --gname '' \
        --format=ustar \
        --no-recursion \
        -cf - -T "$LISTFILE" \
      | gzip -n > "$TARBALL_PATH"
    rm -f -- "$LISTFILE"
    ;;
esac
cd -- "$REPO_ROOT"

# ==== 10. Checksum (formato compativel com -c de sha256sum/shasum) ====
(
  cd -- "$OUT_DIR"
  _sha256_of "${TARBALL_NAME}.tar.gz" > "${TARBALL_NAME}.tar.gz.sha256"
)

# ==== 11. Summary ====
{
  printf '==> build-release: cstk %s\n' "$VERSION_BARE"
  printf '  tarball: %s\n' "$TARBALL_PATH"
  printf '  sha256:  %s\n' "$SHA_PATH"
  printf '  flavor:  %s\n' "$TAR_FLAVOR"
} >&2

exit 0
