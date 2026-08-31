#!/bin/sh
# Fixture de state-rw.sh: responde 'get --field "(.waves // []) | map(.id)"'
# com uma lista fixa de wave ids existentes -- usada para testar o fechamento
# do gap CHK016 (WAVE_ID_NOT_FOUND).
set -eu
case "${1:-}" in
  get) printf '["onda-001","onda-002"]\n' ;;
  *) printf 'fake-state-rw-waves-ids: subcomando desconhecido: %s\n' "${1:-}" >&2; exit 1 ;;
esac
