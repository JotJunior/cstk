#!/bin/sh
# Fixture de teste: simula uma saida inesperada (nao numerica) do helper —
# cobre o ramo defensivo de handleRecordSkill quando o stdout nao pode ser
# interpretado como contagem inteira.
set -eu
printf 'not-a-number\n'
