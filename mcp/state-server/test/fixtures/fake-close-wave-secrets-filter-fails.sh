#!/bin/sh
# Fixture secrets-filter.sh (close_wave): `for-backup` FALHA (simula erro de
# filtro/serializacao) — exercitada ANTES de `end` (ordem research.md
# Decision 3: backup antes da mutacao), entao nada foi mutado ainda.
set -eu
case "${1:-}" in
  for-backup)
    cat >/dev/null
    printf 'fake-close-wave-secrets-filter-fails: for-backup simulado falhou\n' >&2
    exit 1
    ;;
  *) printf 'fake-close-wave-secrets-filter: subcomando desconhecido: %s\n' "${1:-}" >&2; exit 1 ;;
esac
