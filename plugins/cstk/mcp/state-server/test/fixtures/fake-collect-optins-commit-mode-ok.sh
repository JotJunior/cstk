#!/bin/sh
# Fixture: simula commit-mode.sh set-enabled — sempre sucesso.
set -eu
_cmd="${1:-}"
case "$_cmd" in
  set-enabled) exit 0 ;;
  *) printf 'fake-collect-optins-commit-mode-ok: subcomando desconhecido: %s\n' "$_cmd" >&2; exit 1 ;;
esac
