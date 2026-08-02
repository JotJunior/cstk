#!/bin/sh
# Fixture state-rw.sh (close_wave, happy path): `read` imprime um JSON
# minimo (consumido via stdin por secrets-filter.sh for-backup);
# `sha256-update` sempre sucesso.
set -eu
case "${1:-}" in
  read)          printf '{"waves":[{"id":"onda-013"}]}' ;;
  sha256-update) exit 0 ;;
  *) printf 'fake-close-wave-state-rw: subcomando desconhecido: %s\n' "${1:-}" >&2; exit 1 ;;
esac
