#!/bin/sh
# Fixture combinada state-ondas.sh (close_wave, happy path): wave-status=open,
# current-id=onda-013, end sempre sucesso (exit 0, sem stdout).
set -eu
case "${1:-}" in
  wave-status) printf 'open\n' ;;
  current-id)  printf 'onda-013\n' ;;
  end)         exit 0 ;;
  *) printf 'fake-close-wave-ondas: subcomando desconhecido: %s\n' "${1:-}" >&2; exit 1 ;;
esac
