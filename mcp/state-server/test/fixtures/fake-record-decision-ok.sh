#!/bin/sh
# Fixture: simula state-decisions.sh register com sucesso, imprimindo o
# id da decisao (padrao dec-NNN) em stdout [VERIFICADO: state-decisions.sh
# linha final de _sd_cmd_register: printf '%s\n' "$_id"].
set -eu
printf 'dec-042\n'
