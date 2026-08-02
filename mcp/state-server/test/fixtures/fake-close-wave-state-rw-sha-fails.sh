#!/bin/sh
# Fixture state-rw.sh (close_wave): `read` sucesso, `sha256-update` FALHA —
# exercitada DEPOIS de `end` ja ter mutado o state.json (ver
# fake-close-wave-ondas-end-mutates.sh). Prova a compensacao pos-mutacao
# (task 4.1.3: "se backup ou hash falharem apos o state-ondas.sh end
# gravar, reverter para um estado observavel consistente").
set -eu
case "${1:-}" in
  read)          printf '{"waves":[{"id":"onda-013"}]}' ;;
  sha256-update) printf 'fake-close-wave-state-rw-sha-fails: sha256-update simulado falhou\n' >&2; exit 1 ;;
  *) printf 'fake-close-wave-state-rw: subcomando desconhecido: %s\n' "${1:-}" >&2; exit 1 ;;
esac
