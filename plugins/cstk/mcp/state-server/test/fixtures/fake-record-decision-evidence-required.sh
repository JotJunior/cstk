#!/bin/sh
# Fixture: simula rejeicao EVIDENCE_REQUIRED do helper real (path de defesa
# em profundidade — na tool real, o schema Zod ja bloqueia isso ANTES do
# handler; este fixture testa o handler chamado diretamente, contornando o
# schema) [VERIFICADO: state-decisions.sh linha ~205-207].
set -eu
printf 'register: violacao Principio I -- score=3 (decide_sem_clarificar) EXIGE --evidencia com comando + fragmento literal do output (sem evidencia, score maximo permitido e 2)\n' >&2
exit 1
