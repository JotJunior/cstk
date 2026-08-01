#!/bin/sh
# Fixture de teste: simula mcp-session.sh resolve com SESSION_MISMATCH
# (exit 3, fail-closed) — token desconhecido/execucao terminal/colisao.
set -eu
printf 'mcp-session: resolve: SESSION_MISMATCH (token desconhecido)\n' >&2
exit 3
