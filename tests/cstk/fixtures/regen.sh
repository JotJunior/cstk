#!/bin/sh
# regen.sh — reconstroi fixtures de release a partir do catalog atual do repo.
#
# Ref: docs/specs/cstk-cli/tasks.md FASE 10.1.4
#
# Produz:
#   tests/cstk/fixtures/releases/v0.1.0/cstk-0.1.0.tar.gz       (+ .sha256)
#   tests/cstk/fixtures/releases/v0.1.0/install.sh
#   tests/cstk/fixtures/releases/v0.2.0/cstk-0.2.0.tar.gz       (+ .sha256)
#   tests/cstk/fixtures/releases/v0.2.0/install.sh
#
# v0.1.0 espelha o catalog atual (build padrao via scripts/build-release.sh).
# v0.2.0 e v0.1.0 + sentinel marker em plugins/cstk/skills/specify/SKILL.md, para
# habilitar testes de update detection (hash difere entre as duas versoes).
#
# Idempotente: rodar 2x produz exatamente os mesmos artefatos (build-release.sh
# garante determinismo via mtime normalization + gzip -n).
#
# Pre-requisitos: scripts/build-release.sh (FASE 9.1), cli/install.sh (FASE 3.2).
#
# POSIX sh + tar/cp/sed/mktemp.

set -eu

FIXTURES_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(cd -- "$FIXTURES_DIR/../../.." && pwd)
RELEASES_DIR="$FIXTURES_DIR/releases"
BUILD_SCRIPT="$REPO_ROOT/scripts/build-release.sh"
BOOTSTRAP_SCRIPT="$REPO_ROOT/cli/install.sh"

[ -f "$BUILD_SCRIPT" ] || {
  printf 'regen: %s ausente — FASE 9.1 esta instalada?\n' "$BUILD_SCRIPT" >&2
  exit 1
}
[ -f "$BOOTSTRAP_SCRIPT" ] || {
  printf 'regen: %s ausente — FASE 3.2 esta instalada?\n' "$BOOTSTRAP_SCRIPT" >&2
  exit 1
}

mkdir -p "$RELEASES_DIR/v0.1.0" "$RELEASES_DIR/v0.2.0"

# ==== v0.1.0: build padrao ====
printf '==> regen v0.1.0 (catalog atual)\n' >&2
sh "$BUILD_SCRIPT" v0.1.0 --out "$RELEASES_DIR/v0.1.0" >/dev/null
cp -- "$BOOTSTRAP_SCRIPT" "$RELEASES_DIR/v0.1.0/install.sh"

# ==== v0.2.0: catalog modificado (sentinel marker em specify) ====
# Estrategia: stage uma copia do REPO_ROOT em tempdir, modifica o source
# que queremos diferenciar, invoca build-release.sh com REPO_ROOT override.
printf '==> regen v0.2.0 (catalog + sentinel marker)\n' >&2
WORK=$(mktemp -d 2>/dev/null) || {
  printf 'regen: mktemp falhou\n' >&2
  exit 1
}
trap 'rm -rf -- "$WORK"' EXIT INT TERM
STAGED="$WORK/source"
mkdir -p "$STAGED"

# Copiamos apenas o que build-release.sh consome.
cp -R -- "$REPO_ROOT/cli" "$STAGED/cli"
cp -R -- "$REPO_ROOT/plugins" "$STAGED/plugins"
cp -R -- "$REPO_ROOT/language-related" "$STAGED/language-related"
cp -R -- "$REPO_ROOT/scripts" "$STAGED/scripts"
[ -f "$REPO_ROOT/CHANGELOG.md" ] && cp -- "$REPO_ROOT/CHANGELOG.md" "$STAGED/CHANGELOG.md" || :

# Sentinel: marker que diferencia v0.2.0 de v0.1.0 (hash da skill specify
# muda; outras skills permanecem identicas, permitindo testes mistos).
{
  printf '\n'
  printf '<!-- v0.2.0-fixture-sentinel: DO NOT REMOVE FROM TESTS -->\n'
} >> "$STAGED/plugins/cstk/skills/specify/SKILL.md"

REPO_ROOT="$STAGED" sh "$STAGED/scripts/build-release.sh" v0.2.0 \
  --out "$RELEASES_DIR/v0.2.0" >/dev/null
cp -- "$BOOTSTRAP_SCRIPT" "$RELEASES_DIR/v0.2.0/install.sh"

printf '==> regen complete\n' >&2
ls -la "$RELEASES_DIR/v0.1.0/" "$RELEASES_DIR/v0.2.0/" >&2
