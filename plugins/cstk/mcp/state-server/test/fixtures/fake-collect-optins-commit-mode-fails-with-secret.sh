#!/bin/sh
# Fixture: simula commit-mode.sh set-enabled falhando SEMPRE, com stderr
# contendo o marcador SECRETXYZ789 (o mesmo que fake-secrets-filter-scrub.sh
# redige) — usada para provar (L1, task 9.4.1) que o `reason` persistido em
# `.optin_responses[]` passa por secrets-filter.sh scrub ANTES do write
# (nao so o `reason` devolvido no envelope da tool, ja coberto por
# sanitizeForLlmContext).
set -eu
_cmd="${1:-}"
case "$_cmd" in
  set-enabled)
    printf 'erro ao gravar: token SECRETXYZ789 invalido\n' >&2
    exit 1
    ;;
  *)
    printf 'fake-collect-optins-commit-mode-fails-with-secret: subcomando desconhecido: %s\n' "$_cmd" >&2
    exit 1
    ;;
esac
