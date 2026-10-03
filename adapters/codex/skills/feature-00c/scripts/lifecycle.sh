#!/bin/sh
set -eu
_lifecycle_mode=${1:-}; [ "$#" -eq 0 ] || shift
. "$(dirname -- "$0")/_entry.sh"
case "$_lifecycle_mode" in status|resume|abort|handoff) cx_cli "$_lifecycle_mode" "$@" ;; reconcile-governance) cx_cli reconcile_governance "$@" ;; *) cx_fail 'use status, resume, abort, handoff or reconcile-governance' 2 ;; esac
