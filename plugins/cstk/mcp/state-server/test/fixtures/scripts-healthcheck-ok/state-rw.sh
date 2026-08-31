#!/bin/sh
# Fixture: state-rw.sh get --field X -> valor fixo por campo.
set -eu
_field=""
_prev=""
for _a in "$@"; do
  if [ "$_prev" = "--field" ]; then
    _field=$_a
  fi
  _prev=$_a
done
case "$_field" in
  .execution.status) printf 'em_andamento\n' ;;
  .current_stage) printf 'execute-task\n' ;;
  *) printf '\n' ;;
esac
