#!/bin/sh
set -eu
. "$(dirname -- "$0")/_entry.sh"
cx_cli context "$@"
