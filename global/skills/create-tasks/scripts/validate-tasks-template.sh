#!/bin/sh
# validate-tasks-template.sh — gate deterministico de fidelidade ao template
# da skill create-tasks (templates/tasks.md).
#
# Motivacao: o gate validate-docs-rendered so checa render (Mermaid, links,
# frontmatter), nunca conformidade estrutural. Quando o backlog e gerado inline
# (subagente "esquece" o template), o drift — checkboxes ausentes, sem prefixo
# FASE, sem legendas, sem Escopo Coberto/Excluido, sem matriz — passa silencioso
# ate um humano notar. Este script e a checagem deterministica que faltava.
#
# Uso:
#   validate-tasks-template.sh FILE [--phase-prefix PREFIX] [--config CONFIG_JSON]
#
#   --phase-prefix PREFIX  Sobrepoe o prefixo de fase (default: FASE, ou o
#                          phase_prefix do --config quando presente).
#   --config CONFIG_JSON   config.json da skill (le phase_prefix sem jq).
#
# Saida (stdout): uma linha por finding mais um resumo, ambas machine-friendly:
#   FINDING|<severity>|<code>|<mensagem>
#   RESULT|<file>|critical=<N>|warning=<M>
#   severity ∈ {critical, warning}
#
# Severidade:
#   critical  drift que quebra downstream (execute-task / review-task metrics):
#             sem heading de fase, sem checkbox, sem tag de criticidade.
#   warning   drift de metadados/conformidade ao template: legendas, matriz de
#             dependencias, resumo quantitativo, escopo coberto/excluido.
#
# Exit: 0 conformante; 1 drift (>=1 finding, qualquer severidade);
#       2 uso incorreto / arquivo inexistente.

set -eu

FILE=""
PREFIX_OVERRIDE=""
CONFIG=""

usage() {
  cat <<'USAGE' >&2
Uso: validate-tasks-template.sh FILE [--phase-prefix PREFIX] [--config CONFIG_JSON]

Valida se FILE (um tasks.md) conforma ao template canonico da skill
create-tasks. Emite linhas FINDING|severity|code|msg e um RESULT final.
Exit: 0 conformante; 1 drift; 2 uso/arquivo.
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --phase-prefix)
      [ $# -ge 2 ] || { usage; exit 2; }
      PREFIX_OVERRIDE="$2"; shift 2 ;;
    --phase-prefix=*)
      PREFIX_OVERRIDE="${1#--phase-prefix=}"; shift ;;
    --config)
      [ $# -ge 2 ] || { usage; exit 2; }
      CONFIG="$2"; shift 2 ;;
    --config=*)
      CONFIG="${1#--config=}"; shift ;;
    -h|--help)
      usage; exit 2 ;;
    --*)
      printf 'Opcao desconhecida: %s\n' "$1" >&2; usage; exit 2 ;;
    *)
      if [ -z "$FILE" ]; then FILE="$1"; shift
      else printf 'Argumento extra: %s\n' "$1" >&2; usage; exit 2; fi ;;
  esac
done

if [ -z "$FILE" ]; then
  usage; exit 2
fi
if [ ! -f "$FILE" ]; then
  printf 'Arquivo nao encontrado: %s\n' "$FILE" >&2
  exit 2
fi

# --- Resolve o prefixo de fase (override > config > default) ---
PREFIX="FASE"
if [ -n "$PREFIX_OVERRIDE" ]; then
  PREFIX="$PREFIX_OVERRIDE"
elif [ -n "$CONFIG" ] && [ -f "$CONFIG" ]; then
  # Le phase_prefix do JSON sem jq (POSIX puro).
  _pp=$(grep -oE '"phase_prefix"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG" 2>/dev/null \
    | sed -E 's/.*"phase_prefix"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/' \
    | head -n 1 || printf '')
  [ -n "$_pp" ] && PREFIX="$_pp"
fi

# Escapa metacaracteres ERE do prefixo (ex: ponto) para uso em regex.
ESC_PREFIX=$(printf '%s' "$PREFIX" | sed 's/[].[^$*\\/]/\\&/g')

CRIT=0
WARN=0

emit() { # emit SEVERITY CODE MSG
  printf 'FINDING|%s|%s|%s\n' "$1" "$2" "$3"
  if [ "$1" = "critical" ]; then CRIT=$((CRIT + 1)); else WARN=$((WARN + 1)); fi
}

# Helper: conta linhas casando um ERE (0 se nenhuma). grep -c ja imprime "0" e
# sai 1 quando nao ha match — o || apenas absorve o exit, sem reimprimir.
count() { _c=$(grep -cE "$1" "$FILE" 2>/dev/null) || _c=0; printf '%s' "$_c"; }

# ==== Checagens CRITICAL (skeleton que downstream depende) ====

# C1 — pelo menos um heading de fase "## PREFIX <N>"
if [ "$(count "^##[[:space:]]+${ESC_PREFIX}[[:space:]]")" -eq 0 ]; then
  emit critical no-phase "Nenhum heading de fase '## ${PREFIX} <N>' encontrado"
fi

# C2 — pelo menos uma subtarefa em formato checkbox "- [ ]" / "- [x]" / etc.
if [ "$(count '^- \[[ x~!]\]')" -eq 0 ]; then
  emit critical no-checkbox "Nenhuma subtarefa em formato checkbox '- [ ]' encontrada"
fi

# C3 — pelo menos um heading de tarefa "### ..." com tag de criticidade `[X]`
if [ "$(count '^###[[:space:]].*`\[[A-Z]+\]`')" -eq 0 ]; then
  emit critical no-criticality "Nenhuma tarefa com tag de criticidade '\`[C|A|M]\`' encontrada"
fi

# ==== Checagens WARNING (metadados / conformidade ao template) ====

has() { grep -qiE "$1" "$FILE" 2>/dev/null; }

has 'Legenda de status'         || emit warning no-status-legend     "Bloco 'Legenda de status' ausente"
has 'Legenda de criticidade'    || emit warning no-crit-legend       "Bloco 'Legenda de criticidade' ausente"
has 'Matriz de Depend'          || emit warning no-dependency-matrix  "Secao 'Matriz de Dependencias' ausente"
has 'Resumo Quantitativo'       || emit warning no-summary            "Secao 'Resumo Quantitativo' ausente"
has 'Escopo Coberto'            || emit warning no-scope-covered       "Secao 'Escopo Coberto' ausente"
has 'Escopo Exclu'              || emit warning no-scope-excluded      "Secao 'Escopo Excluido' ausente"

printf 'RESULT|%s|critical=%d|warning=%d\n' "$FILE" "$CRIT" "$WARN"

if [ "$CRIT" -gt 0 ] || [ "$WARN" -gt 0 ]; then
  exit 1
fi
exit 0
