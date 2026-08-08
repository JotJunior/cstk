#!/bin/sh
# digest-facets.sh — agrega os facets per-sessao do `/insights` nativo do Claude
# Code (~/.claude/usage-data/facets/*.json) num digest markdown DATA-DRIVEN,
# consumido pela skill apply-insights como fonte PRIMARIA (mais fresca e do
# projeto corrente que o resumo curado a mao em ~/.claude/insights/).
#
# Cada facet (gerado pelo /insights) tem campos estruturados:
#   underlying_goal, goal_categories{}, outcome, friction_counts{},
#   friction_detail, claude_helpfulness, session_type, user_satisfaction_counts{},
#   primary_success, brief_summary, session_id
#
# Uso:
#   digest-facets.sh [--facets-dir DIR] [--samples N]
#
#   --facets-dir DIR   raiz dos *.json (default: $HOME/.claude/usage-data/facets)
#   --samples N        amostras de friction_detail por tipo + tipos amostrados
#                      (default: 3)
#
# Saida: digest markdown em stdout.
#
# Degradacao GRACIOSA (best-effort — a skill cai no fallback se stdout vazio):
#   - jq ausente            -> aviso em stderr, stdout vazio, exit 0
#   - diretorio inexistente  -> aviso em stderr, stdout vazio, exit 0
#   - nenhum *.json          -> aviso em stderr, stdout vazio, exit 0
#   - jq falha (json invalido) -> aviso em stderr, stdout vazio, exit 0
#
# POSIX sh puro. Dep OPCIONAL: jq. Read-only sobre os facets.

FACETS_DIR="${HOME:-/tmp}/.claude/usage-data/facets"
SAMPLES=3
TOP=15

usage() {
  cat <<'USAGE'
Uso: digest-facets.sh [--facets-dir DIR] [--samples N] [--top N]

  --facets-dir DIR   raiz dos facets *.json
                     (default: $HOME/.claude/usage-data/facets)
  --samples N        amostras de friction_detail por tipo (inteiro > 0; default 3)
  --top N            teto de linhas por distribuicao — corta a cauda longa de
                     alta cardinalidade (ex: goal_categories); default 15
  -h, --help         esta ajuda

Emite um digest markdown agregando os facets do /insights nativo. Saida vazia
(exit 0) quando jq/diretorio/facets ausentes — a skill cai no fallback.
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --facets-dir)
      [ $# -ge 2 ] || { printf 'digest-facets: --facets-dir exige valor\n' >&2; exit 2; }
      FACETS_DIR="$2"; shift 2 ;;
    --samples)
      [ $# -ge 2 ] || { printf 'digest-facets: --samples exige valor\n' >&2; exit 2; }
      case "$2" in
        ''|*[!0-9]*) printf 'digest-facets: --samples invalido: %s\n' "$2" >&2; exit 2 ;;
      esac
      [ "$2" -gt 0 ] || { printf 'digest-facets: --samples deve ser > 0\n' >&2; exit 2; }
      SAMPLES="$2"; shift 2 ;;
    --top)
      [ $# -ge 2 ] || { printf 'digest-facets: --top exige valor\n' >&2; exit 2; }
      case "$2" in
        ''|*[!0-9]*) printf 'digest-facets: --top invalido: %s\n' "$2" >&2; exit 2 ;;
      esac
      [ "$2" -gt 0 ] || { printf 'digest-facets: --top deve ser > 0\n' >&2; exit 2; }
      TOP="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'digest-facets: argumento desconhecido: %s\n' "$1" >&2; exit 2 ;;
  esac
done

# ---- guards de degradacao (todos exit 0, stdout vazio) ----
if ! command -v jq >/dev/null 2>&1; then
  printf 'digest-facets: jq ausente — digest pulado (fallback)\n' >&2
  exit 0
fi
if [ ! -d "$FACETS_DIR" ]; then
  printf 'digest-facets: diretorio de facets ausente (%s) — digest pulado\n' "$FACETS_DIR" >&2
  exit 0
fi
_count=$(find "$FACETS_DIR" -maxdepth 1 -type f -name '*.json' 2>/dev/null | wc -l | tr -d ' ')
case "$_count" in ''|*[!0-9]*) _count=0 ;; esac
if [ "$_count" -eq 0 ]; then
  printf 'digest-facets: nenhum facet *.json em %s — digest pulado\n' "$FACETS_DIR" >&2
  exit 0
fi

# Filtro jq: input = array de TODOS os facets (slurp via `-s`). `find -exec cat +`
# evita ARG_MAX em diretorios grandes; jq -s reagrupa o stream de objetos.
_JQ='
def fmt: (length) as $tot
  | if $tot == 0 then "(nenhum)"
    else ((.[0:$top] | map("- \(.k): \(.n)") | join("\n"))
          + (if $tot > $top then "\n- … (+\($tot - $top) mais de \($tot))" else "" end))
    end;
def scalardist(k): ([ .[] | .[k] ] | map(select(. != null)) | group_by(.) | map({k: .[0], n: length}) | sort_by(-.n));
def mapsum(k): ([ .[] | (.[k] // {}) | to_entries[] ] | group_by(.key) | map({k: .[0].key, n: (map(.value) | add)}) | sort_by(-.n));

. as $a
| ($a | length) as $n
| ($a | mapsum("friction_counts")) as $fric
| "# Usage Facets Digest (data-driven)\n"
+ "\nFonte: ~/.claude/usage-data/facets — \($n) sessoes analisadas pelo /insights nativo.\n"
+ "\n## Categorias de objetivo (desc)\n" + ($a | mapsum("goal_categories") | fmt)
+ "\n\n## Outcomes\n" + ($a | scalardist("outcome") | fmt)
+ "\n\n## Padroes de friccao (desc) — sinal-chave para recomendacoes\n" + ($fric | fmt)
+ "\n\n## Ajuda percebida (claude_helpfulness)\n" + ($a | scalardist("claude_helpfulness") | fmt)
+ "\n\n## Satisfacao do usuario\n" + ($a | mapsum("user_satisfaction_counts") | fmt)
+ "\n\n## Amostras de friction_detail (top tipos de friccao)\n"
+ ( [ $fric[0:$samples][]
      | .k as $fk | .n as $fn
      | "\n### \($fk) (\($fn))\n"
      + ( [ $a[] | select((.friction_counts // {}) | has($fk)) | .friction_detail ]
          | map(select(. != null and . != "")) | map(gsub("\n"; " ")) | unique | .[0:$samples]
          | if length == 0 then ["(sem detalhe textual)"] else . end
          | map("- " + .) | join("\n") )
    ] | join("\n") )
+ "\n"
'

_out=$(find "$FACETS_DIR" -maxdepth 1 -type f -name '*.json' -exec cat {} + 2>/dev/null \
        | jq -s -r --argjson samples "$SAMPLES" --argjson top "$TOP" "$_JQ" 2>/dev/null) || {
  printf 'digest-facets: jq falhou ao agregar (json invalido?) — digest pulado\n' >&2
  exit 0
}

[ -n "$_out" ] || {
  printf 'digest-facets: agregacao vazia — digest pulado\n' >&2
  exit 0
}

printf '%s\n' "$_out"
