#!/bin/sh
# run.sh — codigo de brinquedo da fixture reconcile-docs.
set -eu
. "$(dirname "$0")/config.sh"

verbose=0
input=""
while [ $# -gt 0 ]; do
  case "$1" in
    --limit) LIMIT="$2"; shift ;;
    --verbose) verbose=1 ;;
    *) input="$1" ;;
  esac
  shift
done

[ "$verbose" = 1 ] && printf 'limit=%s\n' "$LIMIT"
printf 'input=%s\n' "$input"
exit 0
