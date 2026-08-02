#!/bin/sh
# Fixture de teste: simula state-ondas.sh record-skill com sucesso, imprimindo
# a CONTAGEM de skills_invoked (comportamento VERIFICADO do helper real —
# ver nota em src/tools/record_skill.ts), nao um wave_id.
set -eu
printf '4\n'
