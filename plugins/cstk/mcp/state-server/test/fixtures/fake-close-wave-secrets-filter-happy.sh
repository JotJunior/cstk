#!/bin/sh
# Fixture secrets-filter.sh (close_wave, happy path): `for-backup` le stdin
# (descarta) e imprime um envelope JSON minimo em stdout.
set -eu
case "${1:-}" in
  for-backup)
    cat >/dev/null
    printf '{"wave_number":13,"captured_at":"2026-08-01T00:00:00Z","state_sha256_self":"deadbeef","state_snapshot":{}}'
    ;;
  *) printf 'fake-close-wave-secrets-filter: subcomando desconhecido: %s\n' "${1:-}" >&2; exit 1 ;;
esac
