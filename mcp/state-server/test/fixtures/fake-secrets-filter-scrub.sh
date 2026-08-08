#!/bin/sh
# Fake secrets-filter.sh for audit-log tests: implements only `scrub`
# (stdin -> stdout), replacing the literal marker SECRETXYZ789 with
# [REDACTED]. Standing in for the real
# plugins/cstk/skills/agente-00c-runtime/scripts/secrets-filter.sh (fixtures POSIX
# reais, sem mocks JS -- mesma filosofia de fake-mcp-session-ok.sh).
set -eu

case "${1:-}" in
  scrub) sed 's/SECRETXYZ789/[REDACTED]/g' ;;
  *) printf 'fake-secrets-filter-scrub: subcomando desconhecido: %s\n' "${1:-}" >&2; exit 1 ;;
esac
