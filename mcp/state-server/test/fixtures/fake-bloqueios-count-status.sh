#!/bin/sh
# Fixture: simula bloqueios.sh count --pending-only.
set -eu
case "${1:-}" in
  count) printf '0\n' ;;
  *) printf 'fake-bloqueios-count-status: subcomando desconhecido: %s\n' "${1:-}" >&2; exit 1 ;;
esac
