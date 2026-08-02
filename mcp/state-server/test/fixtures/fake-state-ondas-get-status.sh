#!/bin/sh
# Fixture: simula state-ondas.sh para get_status (wave-status + current-id).
set -eu
case "${1:-}" in
  wave-status) printf 'open\n' ;;
  current-id)  printf 'onda-012\n' ;;
  *) printf 'fake-state-ondas-get-status: subcomando desconhecido: %s\n' "${1:-}" >&2; exit 1 ;;
esac
