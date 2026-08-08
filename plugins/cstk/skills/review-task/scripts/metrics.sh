#!/bin/sh
# metrics.sh — extrai metricas de progresso de um arquivo tasks.md.
#
# Uso:
#   scripts/metrics.sh tasks.md
#   scripts/metrics.sh docs/specs/foo/tasks.md
#
# Saida (stdout): metricas formatadas em tabela + resumo em JSON-like para
# consumo programatico por outras skills.
#
# Contagens baseadas nos marcadores do template: [ ] [~] [x] [!]

set -eu

if [ $# -lt 1 ]; then
  printf 'Uso: metrics.sh tasks.md\n' >&2
  exit 2
fi

FILE="$1"

if [ ! -f "$FILE" ]; then
  printf 'Arquivo nao encontrado: %s\n' "$FILE" >&2
  exit 1
fi

# Conta checkboxes por status
# Formato: "- [X] N.N.N descricao" onde X pode ser espaco, x, ~ ou !
PENDING=$(grep -cE '^\- \[ \] ' "$FILE" 2>/dev/null) || PENDING=0
DONE=$(grep -cE '^\- \[x\] ' "$FILE" 2>/dev/null) || DONE=0
IN_PROGRESS=$(grep -cE '^\- \[~\] ' "$FILE" 2>/dev/null) || IN_PROGRESS=0
BLOCKED=$(grep -cE '^\- \[!\] ' "$FILE" 2>/dev/null) || BLOCKED=0

TOTAL=$((PENDING + DONE + IN_PROGRESS + BLOCKED))

if [ "$TOTAL" -eq 0 ]; then
  printf 'Nenhuma subtarefa (checkbox) encontrada em %s\n' "$FILE"
  exit 0
fi

# Percentagem concluida (inteiro, sem casas decimais)
PCT=$((DONE * 100 / TOTAL))

# Conta tarefas (headers ### N.N) e fases (## FASE N)
TASKS=$(grep -cE '^### [0-9]+\.[0-9]+ ' "$FILE" 2>/dev/null) || TASKS=0
PHASES=$(grep -cE '^## FASE [0-9]+' "$FILE" 2>/dev/null) || PHASES=0

# Conta criticidade (tags [C], [A], [M] em linhas de header)
CRITICAL=$(grep -cE '^### [0-9.]+ .* `\[C\]`' "$FILE" 2>/dev/null) || CRITICAL=0
HIGH=$(grep -cE '^### [0-9.]+ .* `\[A\]`' "$FILE" 2>/dev/null) || HIGH=0
MEDIUM=$(grep -cE '^### [0-9.]+ .* `\[M\]`' "$FILE" 2>/dev/null) || MEDIUM=0

# Output formatado
cat <<EOF
## Metricas: $FILE

| Metrica       | Valor |
|---------------|-------|
| Fases         | $PHASES |
| Tarefas       | $TASKS |
| Subtarefas    | $TOTAL |
| Concluidas    | $DONE ($PCT%) |
| Em andamento  | $IN_PROGRESS |
| Pendentes     | $PENDING |
| Bloqueadas    | $BLOCKED |

### Criticidade (tarefas)

| Nivel | Qtd |
|-------|-----|
| [C] Critico | $CRITICAL |
| [A] Alto    | $HIGH |
| [M] Medio   | $MEDIUM |

### JSON

{"file":"$FILE","phases":$PHASES,"tasks":$TASKS,"subtasks":$TOTAL,"done":$DONE,"in_progress":$IN_PROGRESS,"pending":$PENDING,"blocked":$BLOCKED,"pct_done":$PCT,"critical":$CRITICAL,"high":$HIGH,"medium":$MEDIUM}
EOF
