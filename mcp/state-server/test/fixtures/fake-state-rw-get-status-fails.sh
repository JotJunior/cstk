#!/bin/sh
# Fixture: leitura falha (ex.: state.json ausente).
set -eu
printf 'get: state.json ausente em /data/state\n' >&2
exit 1
