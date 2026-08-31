#!/bin/sh
# Fixture: wave-status falha (ex.: state.json ausente/corrompido).
set -eu
case "${1:-}" in
  wave-status)
    printf 'wave-status: state.json ausente em /data/state\n' >&2
    exit 1
    ;;
  *) exit 1 ;;
esac
