#!/bin/sh
# Fixture de teste: simula state-ondas.sh record-skill sem onda aberta —
# reproduz o envelope diagnostico real emitido por _diag.sh::diag_emit
# [VERIFICADO: state-ondas.sh:920-922].
set -eu
printf 'DIAG|error|no-open-wave|record-skill: nenhuma onda em andamento (rode state-ondas.sh start primeiro)|rode state-ondas.sh start antes de record-skill\n' >&2
printf 'state-ondas: record-skill: nenhuma onda em andamento (rode state-ondas.sh start primeiro)\n' >&2
exit 1
