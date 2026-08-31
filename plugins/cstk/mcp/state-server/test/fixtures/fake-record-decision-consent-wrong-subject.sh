#!/bin/sh
# Fixture: simula rejeicao HUMAN_CONSENT_INVALID (R6, vinculo de assunto
# divergente) do helper real [VERIFICADO: state-decisions.sh linha 175/203,
# tag [consentimento-de-outro-assunto]].
set -eu
printf "register: --consentimento block-005 respondido para o assunto 'axis:persistencia' mas esta Decisao e do eixo 'axis:arquitetura' -- consentimento de um eixo nao autoriza outro [consentimento-de-outro-assunto]\n" >&2
exit 1
