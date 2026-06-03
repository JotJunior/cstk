#!/bin/sh
# collect.sh — monta o payload {catalog, queries} para o runner trigger-eval.
#
#   catalog : descriptions VIVAS de cada global/skills/<n>/SKILL.md (o artefato sob teste)
#   queries : uniao de global/skills/*/evals/triggers.jsonl + tests/trigger-eval/negatives.jsonl
#
# Saida: JSON compacto (uma linha) em stdout, pronto para virar o `args` do Workflow.
# Requer jq. Uso:
#   sh tests/trigger-eval/collect.sh > /tmp/trigger-payload.json
#
# Nao roda evals (isso e o Workflow run.workflow.js); so agrega o dado de disco.
set -eu

ROOT=${CSTK_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)}
cd "$ROOT"

command -v jq >/dev/null 2>&1 || { printf 'collect.sh: jq e obrigatorio\n' >&2; exit 2; }

cat_tmp=$(mktemp)
q_tmp=$(mktemp)
trap 'rm -f "$cat_tmp" "$q_tmp"' EXIT INT TERM

# --- catalog: name + description de cada SKILL.md ---
for f in global/skills/*/SKILL.md; do
  [ -f "$f" ] || continue
  name=$(basename "$(dirname "$f")")
  # primeira linha `description:` dentro do bloco de frontmatter (entre o 1o e o 2o '---')
  desc=$(awk '
    /^---[[:space:]]*$/ { d++; if (d==2) exit; next }
    d==1 && /^description:/ { sub(/^description:[[:space:]]*/, ""); print; exit }
  ' "$f")
  # remove aspas YAML externas (simples/duplas) e desescapa '' -> '
  desc=$(printf '%s' "$desc" | sed -e "s/^'//" -e "s/'[[:space:]]*\$//" -e "s/''/'/g" -e 's/^"//' -e 's/"[[:space:]]*$//')
  jq -n --arg n "$name" --arg d "$desc" '{name:$n, description:$d}'
done | jq -s '.' > "$cat_tmp"

# --- queries: todas as triggers.jsonl + negatives.jsonl ---
{
  for f in global/skills/*/evals/triggers.jsonl tests/trigger-eval/negatives.jsonl; do
    [ -f "$f" ] || continue
    grep -v '^[[:space:]]*$' "$f" || true
  done
} | jq -c 'select(.query and .expect)' | jq -s '.' > "$q_tmp"

jq -c -n --slurpfile c "$cat_tmp" --slurpfile q "$q_tmp" \
  '{catalog: $c[0], queries: $q[0]}'
