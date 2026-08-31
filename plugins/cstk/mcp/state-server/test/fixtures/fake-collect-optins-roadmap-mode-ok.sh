#!/bin/sh
# Fixture: simula roadmap-mode.sh set-enabled — sempre sucesso.
set -eu
_cmd="${1:-}"
case "$_cmd" in
  set-enabled) exit 0 ;;
  *) printf 'fake-collect-optins-roadmap-mode-ok: subcomando desconhecido: %s\n' "$_cmd" >&2; exit 1 ;;
esac
