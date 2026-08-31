#!/bin/sh
# Fixture: simula rejeicao HUMAN_CONSENT_INVALID (R6, bloqueio inexistente/
# de outra execucao/aguardando — mesma tag nos 3 casos) do helper real
# [VERIFICADO: state-decisions.sh linha 166/170 (_sd_verify_consent_json),
# 194/199 (_sd_verify_consent_sqlite)].
set -eu
printf 'register: --consentimento block-999 nao encontrado nesta execucao (status: ausente) [consentimento-invalido]\n' >&2
exit 1
