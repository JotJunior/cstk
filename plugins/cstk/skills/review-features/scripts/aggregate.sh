#!/bin/sh
# aggregate.sh — agrega metricas de varias features em um relatorio global.
#
# Uso:
#   scripts/aggregate.sh                       # default: docs/specs/
#   scripts/aggregate.sh path/to/features/     # diretorio customizado
#   scripts/aggregate.sh --json [DIR]          # apenas JSON-lines
#   scripts/aggregate.sh -h | --help
#
# Para cada subdiretorio de DIR contendo tasks.md, extrai:
#   - name           basename do diretorio
#   - description    1a linha nao-heading nao-vazia de spec.md (truncada 80c)
#   - pct_done       done * 100 / total_subtasks
#   - criticality    maior criticidade (C/A/M) com SUBTASKS pendentes
#   - mtime_days     dias desde ultima modificacao do tasks.md
#   - suggestion     ARQUIVAR | ABANDONAR | PRIORIZAR | CONTINUAR | INDEFINIDO
#
# Saida default: tabela markdown.
# Saida com --json: uma linha JSON por feature.
#
# Exit codes:
#   0  sucesso (mesmo se 0 features encontradas — apenas warning em stderr)
#   1  diretorio raiz nao existe
#   2  argumento invalido (uso incorreto)

set -eu

DEFAULT_ROOT="docs/specs"
ROOT=""
JSON_ONLY=false

# ==== Parse args ====

print_usage() {
  cat <<'EOF'
Uso: aggregate.sh [--json] [DIRETORIO]

Agrega metricas de features em DIRETORIO (default: docs/specs/).
Cada subdiretorio do DIRETORIO deve conter tasks.md (e opcionalmente spec.md)
para entrar no relatorio.

Opcoes:
  --json        Emite apenas JSON-lines (uma linha por feature), sem markdown
  -h, --help    Mostra esta ajuda

Saida default: tabela markdown + secao JSON-lines no fim.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --json)
      JSON_ONLY=true
      shift
      ;;
    -h|--help)
      print_usage
      exit 0
      ;;
    --*)
      printf 'aggregate.sh: opcao desconhecida: %s\n' "$1" >&2
      print_usage >&2
      exit 2
      ;;
    *)
      if [ -n "$ROOT" ]; then
        printf 'aggregate.sh: apenas um diretorio pode ser especificado\n' >&2
        exit 2
      fi
      ROOT="$1"
      shift
      ;;
  esac
done

[ -z "$ROOT" ] && ROOT="$DEFAULT_ROOT"

if [ ! -d "$ROOT" ]; then
  printf 'aggregate.sh: diretorio nao encontrado: %s\n' "$ROOT" >&2
  exit 1
fi

# ==== Helpers ====

# extract_description SPEC_PATH -> imprime 1a linha "util" do spec.md.
# "util" = nao-vazia, nao-heading (#), nao-frontmatter (---), nao-bullet (-/*).
# Trunca em 80 chars com sufixo "...".
# Substitui '|' por '/' para nao quebrar tabelas markdown.
# Escapa '"' e '\' para uso em JSON.
extract_description() {
  _spec="$1"
  if [ ! -f "$_spec" ]; then
    printf -- '-'
    return 0
  fi
  awk '
    BEGIN { in_fm = 0 }
    NR == 1 && /^---[[:space:]]*$/ { in_fm = 1; next }
    in_fm == 1 && /^---[[:space:]]*$/ { in_fm = 0; next }
    in_fm == 1 { next }
    /^[[:space:]]*$/ { next }
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*[-*]/ { next }
    {
      desc = $0
      sub(/^[[:space:]]+/, "", desc)
      if (length(desc) > 80) desc = substr(desc, 1, 77) "..."
      print desc
      exit
    }
  ' "$_spec"
}

# extract_metrics TASKS_PATH -> imprime: TOTAL DONE PENDING IN_PROGRESS BLOCKED PCT CRIT
# CRIT = C | A | M | -
# Pareia subtasks pendentes com a criticidade do task header (### N.N) corrente.
extract_metrics() {
  _file="$1"
  awk '
    BEGIN {
      pending = 0; done = 0; in_progress = 0; blocked = 0
      max_crit = 0   # 0=nenhum, 1=M, 2=A, 3=C
      cur_crit = 0
    }
    /^### [0-9]+\.[0-9]+/ {
      cur_crit = 0
      if ($0 ~ /`\[C\]`/) cur_crit = 3
      else if ($0 ~ /`\[A\]`/) cur_crit = 2
      else if ($0 ~ /`\[M\]`/) cur_crit = 1
      next
    }
    /^- \[ \] / {
      pending++
      if (cur_crit > max_crit) max_crit = cur_crit
      next
    }
    /^- \[~\] / {
      in_progress++
      if (cur_crit > max_crit) max_crit = cur_crit
      next
    }
    /^- \[!\] / {
      blocked++
      if (cur_crit > max_crit) max_crit = cur_crit
      next
    }
    /^- \[x\] / { done++; next }
    END {
      total = pending + done + in_progress + blocked
      pct = (total > 0) ? int(done * 100 / total) : 0
      crit = "-"
      if (max_crit == 3) crit = "C"
      else if (max_crit == 2) crit = "A"
      else if (max_crit == 1) crit = "M"
      printf "%d %d %d %d %d %d %s\n", total, done, pending, in_progress, blocked, pct, crit
    }
  ' "$_file"
}

# mtime_days FILE -> imprime dias desde ultima modificacao (inteiro >= 0).
# Imprime 0 se stat indisponivel ou falhar.
mtime_days() {
  _f="$1"
  if [ ! -f "$_f" ]; then
    printf '0'
    return 0
  fi
  _now=$(date +%s)
  _ts=""
  if _ts=$(stat -f %m "$_f" 2>/dev/null); then
    :
  elif _ts=$(stat -c %Y "$_f" 2>/dev/null); then
    :
  else
    printf '0'
    return 0
  fi
  if [ -z "$_ts" ]; then
    printf '0'
    return 0
  fi
  printf '%d' $(( (_now - _ts) / 86400 ))
}

# suggest PCT CRIT MTIME TOTAL -> imprime sugestao.
suggest() {
  _pct="$1"; _crit="$2"; _mtime="$3"; _total="$4"
  if [ "$_total" -eq 0 ]; then
    printf 'INDEFINIDO'
    return 0
  fi
  if [ "$_pct" -ge 100 ]; then
    printf 'ARQUIVAR'
    return 0
  fi
  if [ "$_pct" -eq 0 ] && [ "$_mtime" -gt 90 ]; then
    printf 'ABANDONAR'
    return 0
  fi
  if [ "$_crit" = "C" ] && [ "$_pct" -lt 50 ]; then
    printf 'PRIORIZAR'
    return 0
  fi
  printf 'CONTINUAR'
}

# json_escape STRING -> imprime string com " e \ escapados.
json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# md_escape STRING -> imprime string com '|' substituido por '/'.
md_escape() {
  printf '%s' "$1" | sed 's/|/\//g'
}

# ==== Processamento ====

_features_json=""
_features_md=""
_count=0

# Lista deterministica de subdirs em arquivo temp (evita conflitos de IFS).
_dirs_tmp=$(mktemp -t agg.XXXXXX) || {
  printf 'aggregate.sh: falha ao criar tmpfile\n' >&2
  exit 2
}
# shellcheck disable=SC2064
trap "rm -f '$_dirs_tmp'" EXIT INT TERM
find "$ROOT" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort > "$_dirs_tmp"

if [ ! -s "$_dirs_tmp" ]; then
  if $JSON_ONLY; then
    : # silencio em modo JSON
  else
    printf '## Relatorio Global de Features\n\n'
    printf '**Diretorio:** %s\n\n' "$ROOT"
    printf '_Nenhum subdiretorio encontrado em %s._\n' "$ROOT"
  fi
  exit 0
fi

while IFS= read -r _dir; do
  _tasks="$_dir/tasks.md"
  _spec="$_dir/spec.md"
  [ -f "$_tasks" ] || continue

  _name=$(basename "$_dir")
  _desc=$(extract_description "$_spec")
  _metrics=$(extract_metrics "$_tasks")

  # IFS default (whitespace) no corpo do while, entao set -- divide por espaco.
  # shellcheck disable=SC2086
  set -- $_metrics
  _total="$1"; _done="$2"; _pending="$3"; _in_progress="$4"; _blocked="$5"; _pct="$6"; _crit="$7"

  _mtime=$(mtime_days "$_tasks")
  _sugg=$(suggest "$_pct" "$_crit" "$_mtime" "$_total")

  _name_j=$(json_escape "$_name")
  _desc_j=$(json_escape "$_desc")
  _name_m=$(md_escape "$_name")
  _desc_m=$(md_escape "$_desc")

  _json_line=$(printf '{"name":"%s","description":"%s","pct_done":%d,"criticality":"%s","mtime_days":%d,"suggestion":"%s","total":%d,"done":%d,"pending":%d,"in_progress":%d,"blocked":%d}' \
    "$_name_j" "$_desc_j" "$_pct" "$_crit" "$_mtime" "$_sugg" "$_total" "$_done" "$_pending" "$_in_progress" "$_blocked")

  _md_line=$(printf '| %s | %s | %d%% | %s | %s |' \
    "$_name_m" "$_desc_m" "$_pct" "$_crit" "$_sugg")

  _features_json="${_features_json}${_json_line}
"
  _features_md="${_features_md}${_md_line}
"
  _count=$((_count + 1))
done < "$_dirs_tmp"

# ==== Output ====

if $JSON_ONLY; then
  printf '%s' "$_features_json"
  exit 0
fi

if [ "$_count" -eq 0 ]; then
  printf '## Relatorio Global de Features\n\n'
  printf '**Diretorio:** %s\n\n' "$ROOT"
  printf '_Nenhuma feature com tasks.md encontrada em %s._\n' "$ROOT"
  exit 0
fi

cat <<EOF
## Relatorio Global de Features

**Diretorio:** $ROOT
**Features analisadas:** $_count

| Feature | Descricao | % Concluida | Criticidade Pendente | Sugestao |
|---------|-----------|-------------|----------------------|----------|
EOF

printf '%s' "$_features_md"

cat <<EOF

### Legenda de sugestoes

- **ARQUIVAR**: feature 100% concluida — candidata a mover para arquivo morto
- **ABANDONAR**: 0% concluida e sem atualizacao ha mais de 90 dias
- **PRIORIZAR**: tem subtasks criticas pendentes (C) e menos de 50% concluida
- **CONTINUAR**: em andamento saudavel
- **INDEFINIDO**: tasks.md vazio (nenhuma subtask reconhecida)

### JSON

EOF

printf '%s' "$_features_json"
