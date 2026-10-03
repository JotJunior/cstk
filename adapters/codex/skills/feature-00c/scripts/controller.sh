#!/bin/sh
set -eu
_controller_mode=${1:-}; [ "$#" -eq 0 ] || shift
. "$(dirname -- "$0")/_entry.sh"
case "$_controller_mode" in serve|recover) cx_cli "$_controller_mode" "$@" ;; resume) cx_cli controller-resume "$@" ;; *) cx_fail 'use serve, resume or recover' 2 ;; esac
