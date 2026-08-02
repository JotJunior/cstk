#!/bin/sh
# Fixture: simula TESTS_PASSED_EXCEEDS_RUN do helper real (defesa em
# profundidade -- o schema Zod ja bloqueia isso ANTES do handler na tool
# real; este fixture testa o handler chamado diretamente).
set -eu
case "${1:-}" in
  wave-status) printf 'open\n' ;;
  record-task)
    printf "state-ondas: record-task: --testes-passados (5) > --testes-rodados (3)\n" >&2
    exit 1
    ;;
  *) exit 1 ;;
esac
