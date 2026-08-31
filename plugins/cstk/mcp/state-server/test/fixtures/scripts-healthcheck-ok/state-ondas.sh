#!/bin/sh
set -eu
case "$1" in
  wave-status) printf 'open\n' ;;
  current-id) printf 'onda-016\n' ;;
  *) exit 1 ;;
esac
