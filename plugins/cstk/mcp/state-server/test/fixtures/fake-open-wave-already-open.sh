#!/bin/sh
# Fixture: simula wave-status == open (onda ja aberta). open_wave.ts nunca
# deve chegar a invocar 'start' com este fixture -- se chegasse, cairia no
# ramo 'default' abaixo e falharia o teste por texto de erro inesperado.
set -eu
case "${1:-}" in
  wave-status) printf 'open\n' ;;
  *) printf 'fake-open-wave-already-open: nao deveria ter chamado start apos onda aberta: %s\n' "${1:-}" >&2; exit 1 ;;
esac
