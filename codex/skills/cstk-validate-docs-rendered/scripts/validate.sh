#!/bin/sh
# validate.sh — valida que documentacao Markdown renderiza corretamente.
#
# Uso:
#   scripts/validate.sh [path]
#   scripts/validate.sh docs/
#   scripts/validate.sh docs/foo.md
#   scripts/validate.sh             # default: ./docs
#
# Checagens:
#   1. Diagramas Mermaid (sintaxe basica)
#   2. Links internos quebrados
#   3. Code blocks sem linguagem declarada
#   4. Frontmatter YAML malformado
#   5. Tabelas Markdown malformadas
#
# Exit code: 0 se zero ERROs, 1 se houver ERROs.
# POSIX sh — usa find/grep/awk/sed, sem dependencias exoticas.

set -eu

TARGET="${1:-docs}"
ERRORS=0
WARNINGS=0

if [ ! -e "$TARGET" ]; then
  printf 'Caminho nao encontrado: %s\n' "$TARGET" >&2
  exit 2
fi

# Coleta lista de arquivos .md
if [ -d "$TARGET" ]; then
  FILES=$(find "$TARGET" -type f -name '*.md' 2>/dev/null | sort)
else
  FILES="$TARGET"
fi

if [ -z "$FILES" ]; then
  printf 'Nenhum arquivo .md em %s\n' "$TARGET"
  exit 0
fi

FILE_COUNT=$(printf '%s\n' "$FILES" | wc -l | tr -d ' ')

# Temp files para acumular findings
FINDINGS=$(mktemp)
trap 'rm -f "$FINDINGS"' EXIT

report() {
  # report file line severity type message
  printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" >> "$FINDINGS"
  case "$3" in
    ERRO)  ERRORS=$((ERRORS + 1)) ;;
    AVISO) WARNINGS=$((WARNINGS + 1)) ;;
  esac
}

# --- Checagem 1: Diagramas Mermaid ---
# Detecta blocks ```mermaid e valida sintaxe minima.
# Estrategia: coletar lista de participants declarados, depois verificar
# que todo nome usado em setas esta nessa lista. Evita regex com word
# boundary (\b), que nao e portavel entre awk/mawk/gawk.
check_mermaid() {
  file="$1"
  awk -v file="$file" '
    function is_keyword(n) {
      return (n ~ /^(alt|else|end|loop|par|note|activate|deactivate|opt|rect|critical|break|autonumber|and)$/)
    }
    /^```mermaid/ { in_block=1; start=NR; block=""; delete declared; next }
    /^```/ && in_block {
      in_block=0
      if (block ~ /sequenceDiagram/) {
        # Passo 1: coletar participants/actors declarados
        n = split(block, lines, "\n")
        for (i=1; i<=n; i++) {
          line = lines[i]
          # "participant Name" ou "participant Name as Alias"
          if (match(line, /^[[:space:]]*(participant|actor)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*/)) {
            decl = substr(line, RSTART, RLENGTH)
            gsub(/^[[:space:]]*(participant|actor)[[:space:]]+/, "", decl)
            declared[decl] = 1
          }
        }
        # Passo 2: verificar usos em setas
        delete seen_err
        for (i=1; i<=n; i++) {
          line = lines[i]
          # Linhas em sequenceDiagram seguem padrao "Nome ARROW Outro : texto"
          # Extrai o primeiro identificador se a linha tem "->" ou "-->" ou "->>" etc.
          if (line ~ /--?>>?/) {
            # Remove leading whitespace
            clean = line
            sub(/^[[:space:]]+/, "", clean)
            # Pega o primeiro token alfanumerico
            if (match(clean, /^[A-Za-z_][A-Za-z0-9_]*/)) {
              name = substr(clean, RSTART, RLENGTH)
              if (!is_keyword(name) && !(name in declared) && !(name in seen_err)) {
                printf "%s\t%d\tERRO\tMermaid\tparticipant `%s` usado sem declaracao previa\n", file, start, name
                seen_err[name] = 1
              }
              # Pega o destino (depois da seta)
              if (match(clean, /--?>>?[[:space:]]*[A-Za-z_][A-Za-z0-9_]*/)) {
                dst_part = substr(clean, RSTART, RLENGTH)
                sub(/^--?>>?[[:space:]]*/, "", dst_part)
                if (!is_keyword(dst_part) && !(dst_part in declared) && !(dst_part in seen_err)) {
                  printf "%s\t%d\tERRO\tMermaid\tparticipant `%s` usado sem declaracao previa\n", file, start, dst_part
                  seen_err[dst_part] = 1
                }
              }
            }
          }
        }
      }
      # Checagem 1b: alt/else/loop/par sem end correspondente
      opens = gsub(/(^|\n)[[:space:]]*(alt|loop|par|opt|critical|rect)[[:space:]]/, "&", block)
      closes = gsub(/(^|\n)[[:space:]]*end[[:space:]]*(\n|$)/, "&", block)
      if (opens != closes) {
        printf "%s\t%d\tERRO\tMermaid\tbloco alt/loop/par/opt/rect sem `end` correspondente (%d abertos, %d fechados)\n", file, start, opens, closes
      }
      block = ""
      next
    }
    in_block { block = block "\n" $0 }
  ' "$file" >> "$FINDINGS"
}

# --- Checagem 2: Links internos quebrados ---
# Estrategia: processar linha por linha, remover code spans (`...`) e code
# fences antes de procurar links. Isso evita falso positivo em exemplos de
# sintaxe dentro de backticks.
check_links() {
  file="$1"
  dir=$(dirname "$file")

  awk '
    /^```/ { in_fence = !in_fence; next }
    in_fence { next }
    {
      # Remove code spans `...` antes de analisar
      clean = $0
      while (match(clean, /`[^`]*`/)) {
        clean = substr(clean, 1, RSTART-1) substr(clean, RSTART+RLENGTH)
      }
      if (clean ~ /\]\([^)]+\.md/) {
        print NR "\t" clean
      }
    }
  ' "$file" | \
    while IFS="	" read -r lineno rest; do
      # Extrai cada link da linha
      printf '%s\n' "$rest" | grep -oE '\]\([^)]+\.md(#[^)]*)?\)' | \
        while read -r match; do
          target=$(printf '%s' "$match" | sed -E 's/^\]\(([^)]+)\)$/\1/')
          path=$(printf '%s' "$target" | sed 's/#.*//')

          case "$path" in
            http://*|https://*|mailto:*) continue ;;
          esac

          if [ "${path#/}" != "$path" ]; then
            resolved="$path"
          else
            resolved="$dir/$path"
          fi

          if [ ! -f "$resolved" ]; then
            printf '%s\t%s\tERRO\tLink\tArquivo nao encontrado: %s\n' "$file" "$lineno" "$path" >> "$FINDINGS"
          fi
        done
    done
}

# --- Checagem 3: Code blocks sem linguagem ---
check_codeblocks() {
  file="$1"
  awk -v file="$file" '
    /^```[[:space:]]*$/ && !in_block { in_block=1; start=NR; printf "%s\t%d\tAVISO\tCodeBlock\tFence sem linguagem declarada\n", file, NR; next }
    /^```$/ && in_block { in_block=0; next }
    /^```[a-zA-Z0-9_+-]+/ && !in_block { in_block=1; next }
    /^```/ && in_block { in_block=0 }
  ' "$file" >> "$FINDINGS"
}

# --- Checagem 4: Frontmatter YAML ---
check_frontmatter() {
  file="$1"
  # Primeira linha e "---"?
  first=$(head -n 1 "$file")
  if [ "$first" = "---" ]; then
    # Procura fechamento
    close_line=$(awk 'NR>1 && /^---[[:space:]]*$/ {print NR; exit}' "$file")
    if [ -z "$close_line" ]; then
      printf '%s\t1\tERRO\tFrontmatter\tAbre com `---` mas nao fecha\n' "$file" >> "$FINDINGS"
    fi
  fi
}

# --- Checagem 5: Tabelas malformadas ---
# Estado:
#   in_table: 0 = fora de tabela; 1 = acabou de ver header; 2 = no corpo
#   prev_cols: numero de colunas da ultima linha, para detectar inconsistencia
check_tables() {
  file="$1"
  awk -v file="$file" '
    /^\|.*\|$/ {
      cols = gsub(/\|/, "|")
      is_sep = ($0 ~ /^\|[[:space:]]*:?-+:?[[:space:]]*(\|[[:space:]]*:?-+:?[[:space:]]*)+\|$/)
      if (in_table == 0) {
        # Primeira linha da tabela — assumir que e header
        in_table = 1
        prev_cols = cols
      } else if (in_table == 1) {
        # Linha apos header — deveria ser separator
        if (!is_sep) {
          printf "%s\t%d\tAVISO\tTabela\tHeader sem linha separadora\n", file, NR-1
        }
        in_table = 2
        prev_cols = cols
      } else {
        # Corpo da tabela — checar consistencia de colunas
        if (cols != prev_cols) {
          printf "%s\t%d\tAVISO\tTabela\tNumero de colunas inconsistente (%d vs %d)\n", file, NR, cols, prev_cols
        }
      }
      next
    }
    # Linha nao-tabela reseta estado
    { in_table = 0; prev_cols = 0 }
  ' "$file" >> "$FINDINGS"
}

# Roda todas as checagens em cada arquivo
printf '%s\n' "$FILES" | while read -r file; do
  [ -z "$file" ] && continue
  check_mermaid "$file"
  check_links "$file"
  check_codeblocks "$file"
  check_frontmatter "$file"
  check_tables "$file"
done

# Recalcula contadores do arquivo de findings
# (devido a pipe em while que executa em subshell)
#
# Padrao defeituoso HISTORICO corrigido aqui (analogo ao fix em metrics.sh,
# commit ead1b68): o antigo `$(... || printf '0')` concatenava "0\n0" quando
# grep -c nao encontrava matches (grep -c imprime "0" e sai codigo 1,
# disparando o fallback em adicao ao "0" ja emitido). O resultado era
# aritmetica invalida em `[ "$VAR" -gt 0 ]` mais abaixo e poluicao de
# stderr com "integer expression expected". O padrao seguro e
# `VAR=$(grep -c ...) || VAR=0` que so dispara fallback no exit code nao-zero.
ERRORS=$(grep -c '	ERRO	' "$FINDINGS" 2>/dev/null) || ERRORS=0
WARNINGS=$(grep -c '	AVISO	' "$FINDINGS" 2>/dev/null) || WARNINGS=0
# Defesa-em-profundidade (FR-008): preservadas deliberadamente apos o fix
# da causa raiz acima. Se o padrao vier a ser alterado no futuro, estas
# atribuicoes continuam protegendo contra variavel vazia. Remocao nao
# traria ganho operacional e ampliaria diff desnecessariamente.
ERRORS=${ERRORS:-0}
WARNINGS=${WARNINGS:-0}

# --- Relatorio ---
printf '## Rendering Validation Report\n\n'
printf '**Escopo**: %s\n' "$TARGET"
printf '**Arquivos analisados**: %s\n\n' "$FILE_COUNT"

printf '### Resumo\n\n'
printf '| Severidade | Quantidade |\n'
printf '|------------|------------|\n'
printf '| ERRO       | %s |\n' "$ERRORS"
printf '| AVISO      | %s |\n' "$WARNINGS"
printf '\n'

if [ -s "$FINDINGS" ]; then
  printf '### Findings\n\n'
  printf '| Arquivo | Linha | Severidade | Tipo | Mensagem |\n'
  printf '|---------|-------|------------|------|----------|\n'
  sort -t'	' -k3,3 -k1,1 -k2,2n "$FINDINGS" | \
    awk -F'	' '{printf "| %s | %s | %s | %s | %s |\n", $1, $2, $3, $4, $5}'
  printf '\n'
else
  printf 'Nenhum issue encontrado.\n\n'
fi

printf '### Proximos Passos\n\n'
if [ "$ERRORS" -gt 0 ]; then
  printf '%s\n' "- Corrigir $ERRORS ERRO(s) antes de commitar"
fi
if [ "$WARNINGS" -gt 0 ]; then
  printf '%s\n' "- $WARNINGS AVISO(s) podem ser agendados para proximo cleanup"
fi
if [ "$ERRORS" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
  printf '%s\n' "- Nenhuma acao necessaria. Documentacao renderiza corretamente."
fi

# Exit code para uso em CI/hooks
if [ "$ERRORS" -gt 0 ]; then
  exit 1
fi
exit 0
