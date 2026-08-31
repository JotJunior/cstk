#!/bin/sh
# Fixture state-ondas.sh (close_wave, wave-close-advance FR-002): `end`
# SUCEDE somente se o argv contiver --advance E --terminal-phase — prova
# empirica de que a tool repassa os campos advance/terminal_phase ao helper
# (o exec-mapper-parity cobre a presenca literal da flag no fonte; este
# fixture cobre o passthrough em runtime).
set -eu
case "${1:-}" in
  wave-status) printf 'open\n' ;;
  current-id)  printf 'onda-013\n' ;;
  end)
    _saw_advance=0
    _saw_terminal=0
    for _a in "$@"; do
      case "$_a" in
        --advance)        _saw_advance=1 ;;
        --terminal-phase) _saw_terminal=1 ;;
      esac
    done
    if [ "$_saw_advance" = 1 ] && [ "$_saw_terminal" = 1 ]; then
      exit 0
    fi
    printf 'fake-close-wave-ondas-requires-advance: argv de end sem --advance/--terminal-phase\n' >&2
    exit 1
    ;;
  *) printf 'fake-close-wave-ondas-requires-advance: subcomando desconhecido: %s\n' "${1:-}" >&2; exit 1 ;;
esac
