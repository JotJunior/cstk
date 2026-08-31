#!/bin/sh
# Fixture state-ondas.sh (close_wave): wave-status=open, current-id=onda-013,
# `end` FALHA (simula mutacao rejeitada — ex.: motivo invalido chegando ate
# o helper). Usado para exercitar a compensacao (rollback da pre-imagem).
set -eu
case "${1:-}" in
  wave-status) printf 'open\n' ;;
  current-id)  printf 'onda-013\n' ;;
  end)         printf 'fake-close-wave-ondas-end-fails: end simulado falhou\n' >&2; exit 1 ;;
  *) printf 'fake-close-wave-ondas: subcomando desconhecido: %s\n' "${1:-}" >&2; exit 1 ;;
esac
