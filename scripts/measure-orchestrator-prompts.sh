#!/bin/sh
# measure-orchestrator-prompts.sh — mede o que uma onda carrega dos dois
# orquestradores autonomos (prompt-base + referencia de fase) num commit.
#
# Ref: docs/specs/orchestrator-slim/contracts/measure-cli.md
#      docs/specs/orchestrator-slim/spec.md FR-011, FR-012, FR-013, FR-017
#
# Script de DESENVOLVIMENTO (fora do catalogo instalado). Dependencias:
# git, wc, awk, sort. `sqlite3` e OPCIONAL e so entra na secao --observed
# (ausente => "indisponivel"); confinado a este arquivo (Principio II,
# carve-out 1.1.0). Nenhuma chamada de rede.
#
# Uso:
#   measure-orchestrator-prompts.sh --ref <git-ref> [--observed] [--db PATH]
#                                   [--since DATA] [--until DATA]
#
#   --ref REF      commit a medir; os arquivos sao lidos via `git show REF:path`
#                  (nunca da arvore de trabalho). Baseline oficial:
#                  9f97e994d5cde46d1447744c68c9def8da14e6e3
#   --observed     inclui consumo observado (knowledge.db, tabela waves)
#   --db PATH      default $HOME/.claude/cstk/knowledge.db (sqlite3 -readonly)
#   --since DATA   inicio da janela (started_at >= DATA); default: sem limite
#   --until DATA   fim da janela (started_at < DATA); default: data do commit
#                  de REF (ondas anteriores a esse commit)
#                  DATA = AAAA-MM-DD ou AAAA-MM-DDTHH:MM:SSZ (validada por
#                  regex antes de entrar em SQL; invalida => exit 2)
#
# Tokens: se ORCH_TOKEN_COUNTER estiver definida, e um comando (definido pelo
# operador) que le texto em stdin e imprime um inteiro; o relatorio registra o
# comando. Indefinida => "indisponivel". NUNCA deriva tokens de bytes.
#
# Exit: 0 sucesso (inclui secao observada indisponivel); 1 erro (ref
# inexistente, arquivo ausente no ref); 2 uso incorreto.

set -eu

BASELINE_SHA="9f97e994d5cde46d1447744c68c9def8da14e6e3"
PB_ROOT="plugins/cstk/agents/agente-00c-orchestrator.md"
PB_FEATURE="plugins/cstk/agents/agente-00c-feature-orchestrator.md"
REFDIR="plugins/cstk/skills/agente-00c-runtime/references/orchestrators"
PHASES_ROOT="bootstrap briefing constitution roadmap specify clarify plan checklist create-tasks execute-task converge review-features"
PHASES_FEATURE="bootstrap specify clarify plan checklist create-tasks execute-task converge toolkit-issue"

die() {
  printf 'measure-orchestrator-prompts: %s\n' "$1" >&2
  exit "${2:-1}"
}

usage() {
  sed -n '2,36p' "$0" | sed 's/^# \{0,1\}//'
}

REF=""
OBSERVED=0
DB=""
SINCE=""
UNTIL=""

while [ $# -gt 0 ]; do
  case "$1" in
    --ref)      [ $# -ge 2 ] || die "--ref exige valor" 2; REF=$2; shift 2 ;;
    --observed) OBSERVED=1; shift ;;
    --db)       [ $# -ge 2 ] || die "--db exige valor" 2; DB=$2; shift 2 ;;
    --since)    [ $# -ge 2 ] || die "--since exige valor" 2; SINCE=$2; shift 2 ;;
    --until)    [ $# -ge 2 ] || die "--until exige valor" 2; UNTIL=$2; shift 2 ;;
    -h|--help)  usage; exit 0 ;;
    *)          die "opcao desconhecida: $1" 2 ;;
  esac
done

[ -n "$REF" ] || die "--ref e obrigatorio" 2

# Datas entram em SQL: validar ANTES de qualquer uso (gate owasp-security S3).
DATE_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}(T[0-9]{2}:[0-9]{2}:[0-9]{2}Z)?$'
for _d in "$SINCE" "$UNTIL"; do
  if [ -n "$_d" ]; then
    printf '%s\n' "$_d" | grep -Eq "$DATE_RE" || die "data invalida (esperado AAAA-MM-DD ou AAAA-MM-DDTHH:MM:SSZ): $_d" 2
  fi
done

REPO=$(git rev-parse --show-toplevel 2>/dev/null) || die "fora de um repositorio git" 1
SHA=$(git -C "$REPO" rev-parse --verify --quiet "$REF^{commit}") || die "ref inexistente: $REF" 1

# --- primitivas de leitura no ref -------------------------------------------

exists_at_ref() {
  git -C "$REPO" cat-file -e "$SHA:$1" 2>/dev/null
}

show_at_ref() {
  git -C "$REPO" show "$SHA:$1"
}

bytes_of() {
  # $@ = paths existentes no ref (concatenados na ordem dada)
  for _p in "$@"; do show_at_ref "$_p"; done | wc -c | tr -d ' '
}

tokens_of() {
  # $@ = paths existentes no ref. Imprime inteiro ou "indisponivel".
  if [ -z "${ORCH_TOKEN_COUNTER:-}" ]; then
    printf 'indisponivel'
    return 0
  fi
  _out=$(for _p in "$@"; do show_at_ref "$_p"; done | sh -c "$ORCH_TOKEN_COUNTER" 2>/dev/null) || {
    printf 'indisponivel'
    return 0
  }
  _out=$(printf '%s' "$_out" | tr -d ' \n')
  case "$_out" in
    ''|*[!0-9]*) printf 'indisponivel' ;;
    *) printf '%s' "$_out" ;;
  esac
}

for _pb in "$PB_ROOT" "$PB_FEATURE"; do
  exists_at_ref "$_pb" || die "arquivo ausente em $REF: $_pb" 1
done

# --- cabecalho --------------------------------------------------------------

printf '# Medicao dos prompts dos orquestradores\n\n'
printf -- '- ref: `%s` (`%s`)\n' "$REF" "$SHA"
if [ "$SHA" = "$BASELINE_SHA" ]; then
  printf -- '- papel: baseline oficial da feature orchestrator-slim (FR-013)\n'
fi
printf -- '- data UTC da medicao: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf -- '- metodo de bytes: `git show <ref>:<path> | wc -c` (bytes do arquivo no commit)\n'
if [ -n "${ORCH_TOKEN_COUNTER:-}" ]; then
  printf -- '- metodo de tokens: comando externo `%s` (ORCH_TOKEN_COUNTER, stdin -> inteiro)\n' "$ORCH_TOKEN_COUNTER"
else
  printf -- '- metodo de tokens: indisponivel (ORCH_TOKEN_COUNTER nao definida; nenhum contador offline no ambiente). Gate de FR-018 avaliado em bytes (dec-010). Tokens NUNCA derivados de bytes.\n'
fi

# --- tabela do prompt-base --------------------------------------------------

printf '\n## Prompt-base\n\n'
printf '| orchestrator | bytes | tokens |\n|---|---|---|\n'
_b_root=$(bytes_of "$PB_ROOT")
_b_feat=$(bytes_of "$PB_FEATURE")
printf '| root | %s | %s |\n' "$_b_root" "$(tokens_of "$PB_ROOT")"
printf '| feature | %s | %s |\n' "$_b_feat" "$(tokens_of "$PB_FEATURE")"

# --- tabela por fase --------------------------------------------------------

phase_rows() {
  # $1 = root|feature ; $2 = prompt-base ; $3 = bytes do prompt-base ; $4 = fases
  _o=$1; _pb=$2; _bb=$3
  for _ph in $4; do
    _rp="$REFDIR/$_o/$_ph.md"
    if exists_at_ref "$_rp"; then
      _rb=$(bytes_of "$_rp")
      _tk=$(tokens_of "$_pb" "$_rp")
    else
      _rb=0
      _tk=$(tokens_of "$_pb")
    fi
    printf '| %s | %s | %s | %s | %s | %s |\n' "$_o" "$_ph" "$_bb" "$_rb" "$((_bb + _rb))" "$_tk"
  done
}

printf '\n## Por fase (o que uma onda da fase carrega: prompt-base + 1 referencia)\n\n'
printf '| orchestrator | phase | base_bytes | ref_bytes | loaded_bytes | tokens |\n|---|---|---|---|---|---|\n'
phase_rows root "$PB_ROOT" "$_b_root" "$PHASES_ROOT"
phase_rows feature "$PB_FEATURE" "$_b_feat" "$PHASES_FEATURE"
printf '\nFases sem arquivo de referencia no ref medido aparecem com `ref_bytes = 0` (no baseline, todas).\n'

# --- consumo observado ------------------------------------------------------

observed_unavailable() {
  printf '\n## Consumo observado (knowledge.db)\n\nindisponivel: %s\n' "$1"
}

if [ "$OBSERVED" -eq 1 ]; then
  [ -n "$DB" ] || DB="$HOME/.claude/cstk/knowledge.db"
  DB_SHOWN=$(printf '%s' "$DB" | sed "s|^$HOME|~|")
  if ! command -v sqlite3 >/dev/null 2>&1; then
    observed_unavailable "sqlite3 ausente no PATH"
  elif [ ! -f "$DB" ]; then
    observed_unavailable "banco nao encontrado em $DB_SHOWN"
  else
    if [ -z "$UNTIL" ]; then
      UNTIL=$(TZ=UTC git -C "$REPO" show -s --date=format-local:%Y-%m-%dT%H:%M:%SZ --format=%cd "$SHA")
    fi
    _where="started_at IS NOT NULL AND started_at < '$UNTIL'"
    if [ -n "$SINCE" ]; then
      _where="$_where AND started_at >= '$SINCE'"
    fi
    _rows=$(sqlite3 -readonly -separator '	' "$DB" "
      SELECT
        CASE WHEN execution_id LIKE 'feat-%' THEN 'feature-00c'
             WHEN execution_id LIKE '%agente-00c%' THEN 'agente-00c'
             ELSE NULL END AS grp,
        CASE WHEN stages IS NULL OR stages = '' OR instr(stages, ',') > 0
             THEN '(multi-etapa ou vazio)' ELSE stages END AS stage,
        IFNULL(otel_total_tokens, ''),
        IFNULL(otel_subagent_cache_creation_tokens, ''),
        IFNULL(otel_main_cache_creation_tokens, '')
      FROM waves
      WHERE $_where
        AND (execution_id LIKE 'feat-%' OR execution_id LIKE '%agente-00c%');
    " 2>/dev/null) || _rows="__ERRO__"
    if [ "$_rows" = "__ERRO__" ]; then
      observed_unavailable "falha ao consultar a tabela waves em $DB_SHOWN"
    elif [ -z "$_rows" ]; then
      printf '\n## Consumo observado (knowledge.db)\n\n'
      printf -- '- fonte: tabela `waves` de `%s`\n' "$DB_SHOWN"
      printf -- '- janela: started_at >= %s e < %s\n\n' "${SINCE:-(sem limite)}" "$UNTIL"
      printf 'indisponivel: nenhuma onda na janela informada (n = 0).\n'
    else
      printf '\n## Consumo observado (knowledge.db)\n\n'
      printf -- '- fonte: tabela `waves` de `%s` (somente leitura)\n' "$DB_SHOWN"
      printf -- '- janela: started_at >= %s e < %s\n' "${SINCE:-(sem limite)}" "$UNTIL"
      printf -- '- grupos: `feature-00c` = execution_id `feat-*`; `agente-00c` = execution_id contendo `agente-00c`\n'
      printf -- '- fase = valor exato de `waves.stages`; ondas com varias etapas ou sem etapa ficam em `(multi-etapa ou vazio)`\n'
      printf -- '- cada coluna: `k/n` = ondas com valor / ondas do grupo+fase; mediana so sobre as ondas com valor (n par: media dos dois centrais, truncada); `indisponivel` quando k = 0\n'
      printf -- '- nota: cache_creation inclui resultados de tool e turnos; nao isola o prompt-base\n\n'
      printf '| grupo | fase | n | otel_total_tokens (k/n; mediana) | otel_subagent_cache_creation_tokens (k/n; mediana) | otel_main_cache_creation_tokens (k/n; mediana) |\n|---|---|---|---|---|---|\n'
      printf '%s\n' "$_rows" | awk -F '\t' '
        function med(arr, k,   i, j, t, a) {
          for (i = 1; i <= k; i++) a[i] = arr[i] + 0
          for (i = 2; i <= k; i++) { t = a[i]; j = i - 1
            while (j >= 1 && a[j] > t) { a[j+1] = a[j]; j-- }
            a[j+1] = t }
          if (k % 2) return a[(k + 1) / 2]
          return int((a[k / 2] + a[k / 2 + 1]) / 2)
        }
        {
          key = $1 "\t" $2
          n[key]++
          for (c = 3; c <= 5; c++) {
            if ($c != "") { k[key, c]++; v[key, c, k[key, c]] = $c }
          }
          keys[key] = 1
        }
        END {
          for (key in keys) {
            split(key, kp, "\t")
            line = "| " kp[1] " | " kp[2] " | " n[key]
            for (c = 3; c <= 5; c++) {
              kk = k[key, c] + 0
              if (kk == 0) { line = line " | indisponivel (0/" n[key] ")"; continue }
              delete tmp
              for (i = 1; i <= kk; i++) tmp[i] = v[key, c, i]
              line = line " | " kk "/" n[key] "; " med(tmp, kk)
            }
            print line " |"
          }
        }' | sort
    fi
  fi
fi
