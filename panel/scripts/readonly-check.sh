#!/bin/sh
# readonly-check.sh — gate automatizado do Principio I da constitution
# ("Read-Only sobre o Corpus"). Procura verbos de mutacao SQL no codigo do
# back-end.
#
# POR QUE ESTE SCRIPT EXISTE E NAO E UM GREP INLINE
#
# A versao anterior era um `grep -rniE` direto no package.json e tinha dois
# defeitos, ambos medidos:
#
#   1. FALSO-POSITIVO: por ser case-insensitive e sem nocao de sintaxe, um
#      COMENTARIO contendo a palavra "update" reprovava o gate. Medido:
#      `// Este comentario menciona update` => FAIL. Isso treina a equipe a
#      ignorar a saida do gate, que e pior que nao ter gate.
#
#   2. RELATORIO CEGO: imprimia "OK: no mutation verbs" sem dizer QUANTOS
#      arquivos leu. "OK" vindo de lugar nenhum nao distingue "varri 120
#      arquivos e nao achei nada" de "nao varri nada". Um gate que reporta
#      sucesso sem declarar cobertura e a classe de defeito mais recorrente
#      que encontramos neste toolkit (ver docs/constitution.md, Principio I,
#      clausula Testavel).
#
# O QUE MUDOU E O QUE NAO MUDOU
#
#   NAO mudou: o escopo varrido (apps/server/src inteiro) nem a lista de
#   verbos. A constitution 2.0.x diz que o escopo so se estreita JUNTO com o
#   primeiro codigo de `bridge/` — o gate nao pode afrouxar antes de existir
#   o que ele passa a permitir.
#
#   Mudou: linhas cujo primeiro caractere nao-branco e `//` ou `*` sao
#   classificadas como COMENTARIO e nao reprovam — comentario nao executa
#   SQL. Comentario no fim da linha (apos codigo) CONTINUA reprovando, de
#   proposito: na duvida, reprovar.
#
#   Mudou: a saida declara a cobertura (arquivos varridos) tanto no sucesso
#   quanto na falha.
set -eu

SCOPE="${1:-apps/server/src}"
VERBS='INSERT|UPDATE|DELETE|CREATE|DROP|ALTER'

if [ ! -d "$SCOPE" ]; then
  printf 'readonly-check: escopo inexistente: %s\n' "$SCOPE" >&2
  exit 2
fi

files=$(find "$SCOPE" -type f \( -name '*.ts' -o -name '*.tsx' -o -name '*.js' \) | wc -l | tr -d ' ')
hits=$(grep -rniE "\\b($VERBS)[[:space:]]" "$SCOPE" || true)

if [ -z "$hits" ]; then
  printf 'OK: 0 verbos de mutacao em %s arquivos sob %s\n' "$files" "$SCOPE"
  exit 0
fi

# Separa ocorrencias em linha de comentario (nao executam) das demais.
code_hits=$(printf '%s\n' "$hits" | grep -vE '^[^:]+:[0-9]+:[[:space:]]*(//|\*)' || true)
comment_hits=$(printf '%s\n' "$hits" | grep -cE '^[^:]+:[0-9]+:[[:space:]]*(//|\*)' || true)

if [ -z "$code_hits" ]; then
  printf 'OK: 0 verbos de mutacao em codigo, %s arquivos sob %s (%s ocorrencia(s) em comentario, ignoradas)\n' \
    "$files" "$SCOPE" "$comment_hits"
  exit 0
fi

printf 'FAIL: verbo de mutacao em codigo (%s arquivos varridos sob %s)\n' "$files" "$SCOPE" >&2
printf '%s\n' "$code_hits" >&2
printf '\nSe a ocorrencia estiver dentro de um comentario no FIM da linha, o gate\nreprova de proposito — mova o comentario para linha propria.\n' >&2
exit 1
