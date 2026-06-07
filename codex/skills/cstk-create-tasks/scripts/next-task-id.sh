#!/bin/sh
# next-task-id.sh — calcula o proximo ID hierarquico dentro de uma fase ou
# tarefa em um arquivo tasks.md.
#
# Uso:
#   scripts/next-task-id.sh FASE tasks.md           # proxima tarefa na FASE (ex: 1.3)
#   scripts/next-task-id.sh TAREFA tasks.md         # proxima subtarefa na tarefa (ex: 1.2.4)
#
# Exemplo:
#   next-task-id.sh 1 docs/tasks.md          → 1.5  (proxima tarefa na Fase 1)
#   next-task-id.sh 1.2 docs/tasks.md        → 1.2.4  (proxima subtarefa de 1.2)
#
# Se o prefixo nao existe, retorna {prefix}.1

set -eu

if [ $# -lt 2 ]; then
  cat <<'USAGE' >&2
Uso: next-task-id.sh PREFIX tasks.md

Exemplos:
  next-task-id.sh 1 tasks.md        # proxima tarefa na Fase 1
  next-task-id.sh 1.2 tasks.md      # proxima subtarefa de 1.2
  next-task-id.sh 3.5 tasks.md      # proxima subtarefa de 3.5
USAGE
  exit 2
fi

PREFIX="$1"
FILE="$2"

if [ ! -f "$FILE" ]; then
  printf 'Arquivo nao encontrado: %s\n' "$FILE" >&2
  exit 1
fi

# Escapa ponto no regex
ESC_PREFIX=$(printf '%s' "$PREFIX" | sed 's/\./\\./g')

# IDs aparecem em dois contextos no tasks.md:
#   - Header de tarefa:   "### 1.3 Nome [A]"
#   - Checkbox:           "- [ ] 1.2.5 descricao"
# Regex procura pelos contextos especificos para evitar match espurio
# (ex: grep cru de "2\." casaria o "2.2" dentro de "1.2.2").
MAX=$(grep -oE "(^### |\- \[[ x~!]\] )${ESC_PREFIX}\.[0-9]+" "$FILE" 2>/dev/null \
  | sed -E "s/^(### |- \[[ x~!]\] )//" \
  | sed -E "s/^${ESC_PREFIX}\.//" \
  | sort -n \
  | tail -n 1 || printf '0')

MAX=${MAX:-0}
NEXT=$((MAX + 1))

printf '%s.%d\n' "$PREFIX" "$NEXT"
