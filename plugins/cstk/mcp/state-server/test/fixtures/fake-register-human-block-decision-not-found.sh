#!/bin/sh
# Fixture: simula DECISION_NOT_FOUND (decisao_id referenciada nao existe)
# [VERIFICADO: bloqueios.sh:183 (path json) -- a mesma mensagem e produzida
# pelo path sqlite ao mapear FOREIGN KEY constraint failed].
set -eu
printf "register: decisao_id nao existe: dec-999 (use state-decisions.sh register antes)\n" >&2
exit 1
