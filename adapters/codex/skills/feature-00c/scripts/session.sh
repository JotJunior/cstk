#!/bin/sh
set -eu
_session_mode=${1:-}; [ "$#" -eq 0 ] || shift
. "$(dirname -- "$0")/_entry.sh"
case "$_session_mode" in bootstrap) cx_cli bootstrap "$@" ;; resume) cx_cli session-resume "$@" ;; *) cx_fail 'use bootstrap or resume' 2 ;; esac
