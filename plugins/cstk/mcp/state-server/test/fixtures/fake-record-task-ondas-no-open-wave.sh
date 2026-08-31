#!/bin/sh
# Fixture: wave-status != open. record-task NUNCA deve ser chamado (a tool
# impoe a precondicao NO_OPEN_WAVE antes de delegar -- gap corrigido em
# relacao ao helper real, que nao checa isso sozinho).
set -eu
case "${1:-}" in
  wave-status) printf 'closed\n' ;;
  *) printf 'fake-record-task-ondas-no-open-wave: nao deveria ter chamado %s\n' "${1:-}" >&2; exit 1 ;;
esac
