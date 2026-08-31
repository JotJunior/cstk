#!/bin/sh
# Fixture: simula rejeicao CONSTITUTION_CONFLICT_SCORE do helper real
# [VERIFICADO: state-decisions.sh linha ~225-235].
set -eu
printf 'register: violacao protocolo constitution-conflict -- opcoes contem as 3 strings canonicas do BloqueioHumano pre-flight, portanto esta e a decisao pre-flight obrigatoria e EXIGE --score 0 (pause-humano).\n' >&2
exit 1
