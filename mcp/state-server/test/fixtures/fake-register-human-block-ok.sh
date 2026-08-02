#!/bin/sh
# Fixture: simula bloqueios.sh register com sucesso, imprimindo o id do
# bloqueio (padrao block-NNN) [VERIFICADO: bloqueios.sh linha final de
# _bl_cmd_register: printf '%s\n' "$_id"].
set -eu
printf 'block-005\n'
