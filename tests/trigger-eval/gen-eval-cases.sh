#!/bin/sh
# gen-eval-cases.sh — converte as queries de trigger-eval (formato proprio do
# repo) em cases do harness NATIVO `claude plugin eval`.
#
#   entrada : plugins/cstk/skills/*/evals/triggers.jsonl
#             tests/trigger-eval/negatives.jsonl
#   saida   : plugins/cstk/evals/<expect>/<NNN>/case.yaml
#
# A fonte de verdade continua sendo o `.jsonl` (editado a mao, por skill).
# Este script SO deriva — nunca edite `plugins/cstk/evals/**/case.yaml` a mao:
# a proxima geracao sobrescreve.
#
# Schema do case (`schema_version`, `name`, `tags`, `execution.prompt`,
# `runs`, `graders[]` com `type: tool_used` + `tool`/`input_match`/`min`/`max`)
# VERIFICADO contra o validador zod embarcado no binario do Claude Code
# 2.1.251 — nao ha doc publica do formato (a feature esta em early access).
# Cada campo emitido aqui existe naquele validador; nenhum foi suposto.
#
# CAVEAT de execucao: sob `--ablation with-without` (default do `plugin eval`
# quando um plugin resolve) um grader `tool_used: Skill` vira INDICADOR de
# "plugin disparou" e sai do score. Para que estes cases sejam de fato
# PONTUADOS, rode com `--ablation none`:
#
#   claude plugin eval plugins/cstk --ablation none
#
# Uso:
#   sh tests/trigger-eval/gen-eval-cases.sh            # (re)gera
#   sh tests/trigger-eval/gen-eval-cases.sh --check    # exit 1 se fora de sync
#   sh tests/trigger-eval/gen-eval-cases.sh --out-dir DIR
set -eu

ROOT=${CSTK_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)}
cd "$ROOT"

command -v jq >/dev/null 2>&1 || { printf 'gen-eval-cases.sh: jq e obrigatorio\n' >&2; exit 2; }

OUT_DIR="plugins/cstk/evals"
MODE=generate

while [ $# -gt 0 ]; do
  case "$1" in
    --check)   MODE=check ;;
    --out-dir) shift; [ $# -gt 0 ] || { printf 'gen-eval-cases.sh: --out-dir exige valor\n' >&2; exit 2; }; OUT_DIR=$1 ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *)         printf 'gen-eval-cases.sh: flag desconhecida: %s\n' "$1" >&2; exit 2 ;;
  esac
  shift
done

_cleanup_dir=""
# shellcheck disable=SC2064
trap 'if [ -n "$_cleanup_dir" ]; then rm -rf -- "$_cleanup_dir"; fi' EXIT INT TERM

if [ "$MODE" = check ]; then
  _cleanup_dir=$(mktemp -d) || { printf 'gen-eval-cases.sh: mktemp falhou\n' >&2; exit 2; }
  TARGET=$_cleanup_dir
else
  TARGET=$OUT_DIR
  # regeneracao limpa: so os grupos derivados, preservando o README.md do dir
  if [ -d "$TARGET" ]; then
    find "$TARGET" -mindepth 1 -maxdepth 1 -type d -exec rm -rf -- {} +
  fi
  mkdir -p -- "$TARGET"
fi

TAB=$(printf '\t')

# --- coleta: "<expect>\t<json>" por query, agrupado por expect --------------
# `sort -k1,1 -s` e ESTAVEL: preserva a ordem de leitura dentro de cada grupo,
# entao a numeracao NNN e deterministica (glob de skills ja e ordenado).
_rows=$(
  {
    for f in plugins/cstk/skills/*/evals/triggers.jsonl tests/trigger-eval/negatives.jsonl; do
      [ -f "$f" ] || continue
      grep -v '^[[:space:]]*$' "$f" || true
    done
  } | jq -r 'select(.query and .expect) | "\(.expect)\t\(tojson)"' | sort -t"$TAB" -k1,1 -s
)

[ -n "$_rows" ] || { printf 'gen-eval-cases.sh: nenhuma query encontrada\n' >&2; exit 1; }

printf '%s\n' "$_rows" | {
  _prev=""
  _idx=0
  while IFS="$TAB" read -r _expect _json; do
    [ -n "$_expect" ] || continue
    if [ "$_expect" != "$_prev" ]; then _idx=0; _prev=$_expect; fi
    _idx=$((_idx + 1))
    _nnn=$(printf '%03d' "$_idx")
    _case_dir="$TARGET/$_expect/$_nnn"
    mkdir -p -- "$_case_dir"

    printf '%s' "$_json" | jq -r --arg expect "$_expect" --arg name "$_expect-$_nnn" '
      def y: tojson;                      # string JSON = escalar YAML valido
      ((.tier // "base")) as $tier
      | (if $expect == "none"
         then "  - type: tool_used\n    name: \"no-skill-fires\"\n    tool: \"Skill\"\n    max: 0"
         else "  - type: tool_used\n    name: " + (("fires-" + $expect)|y)
              + "\n    tool: \"Skill\"\n    input_match: " + ($expect|y) + "\n    min: 1"
         end) as $grader
      | [ "# GERADO por tests/trigger-eval/gen-eval-cases.sh — nao edite a mao.",
          "# Fonte: plugins/cstk/skills/*/evals/triggers.jsonl + tests/trigger-eval/negatives.jsonl",
          "schema_version: \"1.0\"",
          "name: " + ($name|y),
          "description: " + ((if $expect == "none"
                              then "trigger eval: a query NAO deve disparar skill alguma"
                              else "trigger eval: a query deve disparar a skill " + $expect end)|y),
          "tags: [" + ((["trigger", $expect, $tier]) | map(y) | join(", ")) + "]",
          "execution:",
          "  prompt: " + (.query|y),
          "  max_turns: 3",
          "  timeout_seconds: 120",
          "runs: 1",
          "graders:",
          $grader
        ] | join("\n")
    ' > "$_case_dir/case.yaml"
  done
}

if [ "$MODE" = check ]; then
  if diff -r -x README.md -- "$OUT_DIR" "$TARGET" >/dev/null 2>&1; then
    printf 'gen-eval-cases.sh: %s em sync com os triggers.jsonl\n' "$OUT_DIR"
    exit 0
  fi
  printf 'gen-eval-cases.sh: %s FORA DE SYNC — rode "sh tests/trigger-eval/gen-eval-cases.sh"\n' "$OUT_DIR" >&2
  diff -r -x README.md -- "$OUT_DIR" "$TARGET" >&2 || true
  exit 1
fi

printf 'gen-eval-cases.sh: %s cases gerados em %s\n' \
  "$(find "$TARGET" -name case.yaml -type f | wc -l | tr -d ' ')" "$OUT_DIR"
