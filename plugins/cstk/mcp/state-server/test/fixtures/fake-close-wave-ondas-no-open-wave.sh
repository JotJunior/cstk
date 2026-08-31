#!/bin/sh
# Fixture state-ondas.sh (close_wave): wave-status=none -> NO_OPEN_WAVE
# precondicao; `end` NUNCA deveria ser chamado (falha alto se for).
set -eu
case "${1:-}" in
  wave-status) printf 'none\n' ;;
  current-id)  printf 'fake-close-wave-ondas-no-open-wave: current-id nao deveria ser chamado\n' >&2; exit 1 ;;
  end)         printf 'fake-close-wave-ondas-no-open-wave: end nao deveria ser chamado\n' >&2; exit 1 ;;
  *) printf 'fake-close-wave-ondas: subcomando desconhecido: %s\n' "${1:-}" >&2; exit 1 ;;
esac
