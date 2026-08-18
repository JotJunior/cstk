#!/bin/sh
# parallel-notification-parse.sh — parse fail-closed da notificacao de
# conclusao entre sessao-filha e sessao coordenadora (FR-008/FR-015).
#
# Feature: roadmap-parallel-launch
# Ref:     docs/specs/roadmap-parallel-launch/contracts/parallel-launch.md §6
#          docs/specs/roadmap-parallel-launch/tasks.md 3.2 ([C] critico,
#          finding HIGH ASI07 do gate owasp-security)
#
# `SendMessage` nao autentica remetente — qualquer sessao pode forjar a
# linha de notificacao. Este helper e a UNICA fonte de parsing: casa a
# mensagem INTEIRA contra a regex ancorada do contrato; qualquer sobra de
# texto e recusada (fail-closed), nunca lida parcialmente. O chamador
# (prosa de agente-00c.md/agente-00c-resume.md) MUST tratar o resultado
# como GATILHO OPACO — os 3 campos extraidos servem so para log/contexto
# informativo do operador, NUNCA para derivar comando ou caminho (INV-8).
#
# Uso:
#   parallel-notification-parse.sh check "<mensagem>"
#   printf '%s' "<mensagem>" | parallel-notification-parse.sh check
#   parallel-notification-parse.sh -h | --help
#
# `check`: le a mensagem do argumento posicional (se fornecido) ou de
# stdin, casa contra `^\[cstk-parallel\] feature=([a-z][a-z0-9-]{0,63})
# outcome=(concluida|abortada|aguardando_humano)
# repo=([A-Za-z0-9._-]{1,64})$` (ancorada em ambas as pontas — `^`/`$` —
# nenhuma sobra de texto e tolerada). Em match: imprime 3 linhas
# (`feature=<>`, `outcome=<>`, `repo=<>`) em stdout e sai 0. Em
# nao-match: nao imprime nada em stdout, sai 1 (fail-closed).
#
# POSIX sh puro, sem `jq` (Principio II).
#
# Exit codes:
#   0  mensagem casou a regex ancorada — 3 campos impressos
#   1  mensagem NAO casou (fail-closed; inclusive mensagem vazia)
#   2  uso incorreto (subcomando desconhecido)

set -eu

_PNP_NAME="parallel-notification-parse"

print_usage() {
  cat <<'EOF'
Uso: parallel-notification-parse.sh check "<mensagem>"
     printf '%s' "<mensagem>" | parallel-notification-parse.sh check
     parallel-notification-parse.sh -h | --help

`check` casa a mensagem INTEIRA (argumento posicional, ou stdin se omitido)
contra a regex ancorada do contrato (contracts/parallel-launch.md §6):

  ^\[cstk-parallel\] feature=([a-z][a-z0-9-]{0,63}) \
    outcome=(concluida|abortada|aguardando_humano) \
    repo=([A-Za-z0-9._-]{1,64})$

Match: imprime `feature=<>`, `outcome=<>`, `repo=<>` (uma por linha) em
stdout, sai 0. Fail-closed: qualquer sobra de texto (antes ou depois do
payload), enum de outcome fora do conjunto, ou metacaractere fora das
classes acima => sai 1 SEM imprimir nada.

Tratar o resultado como GATILHO OPACO — nunca derivar comando/caminho do
conteudo da mensagem (INV-8, contracts/parallel-launch.md §6).

Exit codes: 0 match; 1 sem match (fail-closed); 2 uso incorreto.
EOF
}

[ $# -ge 1 ] || { print_usage >&2; exit 2; }

_PNP_SUBCOMMAND=$1
shift

case "$_PNP_SUBCOMMAND" in
  -h|--help)
    print_usage
    exit 0
    ;;
  check)
    ;;
  *)
    printf '%s: subcomando desconhecido: %s\n' "$_PNP_NAME" "$_PNP_SUBCOMMAND" >&2
    print_usage >&2
    exit 2
    ;;
esac

if [ $# -ge 1 ]; then
  _pnp_msg=$1
else
  _pnp_msg=$(cat)
fi

# Guarda anti-multilinha (fail-closed real, ASI07): `grep`/`sed` ancoram
# `^`/`$` por LINHA, nao pelo buffer inteiro — uma mensagem com newline
# embutida poderia esconder texto malicioso numa segunda linha e ainda
# assim casar a regex ancorada na primeira linha (bypass do finding HIGH).
# Rejeitar QUALQUER newline embutido ANTES de tentar a regex.
_pnp_nl=$(printf '\nX')
_pnp_nl=${_pnp_nl%X}
case "$_pnp_msg" in
  *"$_pnp_nl"*) exit 1 ;;
esac

# Regex ancorada literal do contrato (POSIX ERE — grep -E). `^`/`$`
# garantem que NENHUMA sobra de texto (antes ou depois) passe — a
# mitigacao fail-closed exigida pelo finding HIGH ASI07.
_PNP_RE='^\[cstk-parallel\] feature=([a-z][a-z0-9-]{0,63}) outcome=(concluida|abortada|aguardando_humano) repo=([A-Za-z0-9._-]{1,64})$'

if ! printf '%s' "$_pnp_msg" | grep -Eq "$_PNP_RE"; then
  exit 1
fi

# Extracao das 3 capturas via sed -E (mesma regex, grupos \1/\2/\3) — sem
# jq/perl, POSIX puro. Cada `sed` roda isolado (nao ha suporte portavel a
# multiplas substituicoes independentes num so comando sem risco de
# interferencia entre grupos).
_pnp_feature=$(printf '%s' "$_pnp_msg" | sed -E 's/^\[cstk-parallel\] feature=([a-z][a-z0-9-]{0,63}) outcome=(concluida|abortada|aguardando_humano) repo=([A-Za-z0-9._-]{1,64})$/\1/')
_pnp_outcome=$(printf '%s' "$_pnp_msg" | sed -E 's/^\[cstk-parallel\] feature=([a-z][a-z0-9-]{0,63}) outcome=(concluida|abortada|aguardando_humano) repo=([A-Za-z0-9._-]{1,64})$/\2/')
_pnp_repo=$(printf '%s' "$_pnp_msg" | sed -E 's/^\[cstk-parallel\] feature=([a-z][a-z0-9-]{0,63}) outcome=(concluida|abortada|aguardando_humano) repo=([A-Za-z0-9._-]{1,64})$/\3/')

printf 'feature=%s\n' "$_pnp_feature"
printf 'outcome=%s\n' "$_pnp_outcome"
printf 'repo=%s\n' "$_pnp_repo"
