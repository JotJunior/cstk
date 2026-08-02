#!/bin/sh
# Fixture combinada para state-ondas.sh: wave-status=open + record-task ok
# (imprime a CONTAGEM total de tasks -- comportamento VERIFICADO do helper
# real, ver nota em src/tools/record_task.ts).
set -eu
case "${1:-}" in
  wave-status)  printf 'open\n' ;;
  record-task)  printf '19\n' ;;
  *) printf 'fake-record-task-ondas-open-ok: subcomando desconhecido: %s\n' "${1:-}" >&2; exit 1 ;;
esac
