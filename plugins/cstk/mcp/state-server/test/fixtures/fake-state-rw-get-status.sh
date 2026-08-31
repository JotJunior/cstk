#!/bin/sh
# Fixture: simula state-rw.sh get, respondendo por --field. Usado por
# get_status.ts para .execution.status e .current_stage.
set -eu
_field=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --field) _field="$2"; shift 2 ;;
    *) shift ;;
  esac
done
case "$_field" in
  .execution.status) printf 'em_andamento\n' ;;
  .current_stage)    printf 'execute-task\n' ;;
  *) printf 'fake-state-rw-get-status: campo desconhecido: %s\n' "$_field" >&2; exit 1 ;;
esac
