#!/bin/sh
# Fixture state-rw.sh (close_wave): `read` FALHA (simula state.json corrompido
# ou ausente) — exercitada ANTES de `end` (nada foi mutado ainda), compensacao
# devolve rollback trivial (pre-imagem == estado atual).
set -eu
case "${1:-}" in
  read)          printf 'fake-close-wave-state-rw-read-fails: read simulado falhou\n' >&2; exit 1 ;;
  sha256-update) printf 'fake-close-wave-state-rw-read-fails: sha256-update nao deveria ser chamado\n' >&2; exit 1 ;;
  *) printf 'fake-close-wave-state-rw: subcomando desconhecido: %s\n' "${1:-}" >&2; exit 1 ;;
esac
