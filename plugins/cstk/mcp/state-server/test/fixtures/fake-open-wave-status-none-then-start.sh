#!/bin/sh
# Fixture combinada: atende AMBOS os subcomandos usados por open_wave.ts
# (wave-status e start) via o mesmo --helperPath, dispatch pelo primeiro
# argv (mesma convencao do helper real state-ondas.sh).
set -eu
case "${1:-}" in
  wave-status) printf 'none\n' ;;
  start)       printf 'onda-013\n' ;;
  *) printf 'fake-open-wave: subcomando desconhecido: %s\n' "${1:-}" >&2; exit 1 ;;
esac
