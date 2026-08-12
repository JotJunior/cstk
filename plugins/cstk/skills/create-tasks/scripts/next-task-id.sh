#!/bin/sh
# next-task-id.sh — calcula o proximo ID hierarquico dentro de uma fase ou
# tarefa em um arquivo tasks.md, ou o proximo numero de FASE (--phase).
#
# Uso:
#   scripts/next-task-id.sh FASE tasks.md            # proxima tarefa na FASE (ex: 1.3)
#   scripts/next-task-id.sh TAREFA tasks.md          # proxima subtarefa na tarefa (ex: 1.2.4)
#   scripts/next-task-id.sh --phase tasks.md [PREFIX] # proximo numero de FASE (ex: 3)
#
# Exemplo:
#   next-task-id.sh 1 docs/tasks.md              → 1.5  (proxima tarefa na Fase 1)
#   next-task-id.sh 1.2 docs/tasks.md            → 1.2.4  (proxima subtarefa de 1.2)
#   next-task-id.sh --phase docs/tasks.md        → 3  (proxima FASE, default PREFIX="FASE")
#   next-task-id.sh --phase docs/tasks.md PHASE  → 3  (heading customizado "## PHASE N")
#
# Se o prefixo nao existe, retorna {prefix}.1. Em --phase, arquivo sem
# nenhuma FASE existente retorna 1 (primeira fase apendada).

set -eu

if [ $# -lt 2 ]; then
  cat <<'USAGE' >&2
Uso: next-task-id.sh PREFIX tasks.md
     next-task-id.sh --phase tasks.md [PHASE_PREFIX]

Exemplos:
  next-task-id.sh 1 tasks.md          # proxima tarefa na Fase 1
  next-task-id.sh 1.2 tasks.md        # proxima subtarefa de 1.2
  next-task-id.sh 3.5 tasks.md        # proxima subtarefa de 3.5
  next-task-id.sh --phase tasks.md    # proximo numero de FASE (append deterministico)
USAGE
  exit 2
fi

if [ "$1" = "--phase" ]; then
  FILE="$2"
  PHASE_PREFIX="${3:-FASE}"

  if [ ! -f "$FILE" ]; then
    printf 'Arquivo nao encontrado: %s\n' "$FILE" >&2
    exit 1
  fi

  ESC_PHASE_PREFIX=$(printf '%s' "$PHASE_PREFIX" | sed 's/\./\\./g')

  # Heading de fase: "## FASE {N} - {Nome}" (config.json phase_prefix,
  # default "FASE" — 6.2/next-task-id-phase, mesma convencao do
  # validate-tasks-template.sh).
  MAX=$(grep -oE "^## ${ESC_PHASE_PREFIX} [0-9]+" "$FILE" 2>/dev/null \
    | grep -oE '[0-9]+$' \
    | sort -n \
    | tail -n 1 || printf '0')

  MAX=${MAX:-0}
  NEXT=$((MAX + 1))

  printf '%d\n' "$NEXT"
  exit 0
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
