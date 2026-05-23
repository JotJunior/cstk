#!/bin/sh
# model-routing-report.sh — agregador read-only para Decisoes de selecao
# de modelo emitidas por `model-routing.sh invoke` + persistidas via
# `state-decisions.sh register`. Cumpre FR-018 (US-3, dec-006) da feature
# agente-00c-model-routing: agregacao real-time derivada de `.decisoes[]`
# (sem campo agregado em `.ondas`).
#
# Ref: docs/specs/agente-00c-model-routing/spec.md FR-018, SC-003, US-3
#      docs/specs/agente-00c-model-routing/tasks.md F5.1 (5.1.1..5.1.3)
#      docs/specs/agente-00c-model-routing/plan.md (Phase 5)
#      Decisao do clarify: dec-006 (jq real-time em vez de campo agregado)
#
# Subcomandos:
#   model-routing-report.sh aggregate --state-dir DIR [--json]
#       — Le state.json em <DIR>/state.json e produz agregado das Decisoes
#         cujo `.contexto` casa com `^Selecao de modelo para subagente `.
#         Default: tabela Markdown (renderizada por review-task).
#         Com `--json`: JSON canonico com counts, fallback_pct e breakdown
#         por subagent_type.
#       — Read-only sobre state.json (INV-4 herdada de model-routing.sh).
#       — Idempotente: mesmo input -> mesmo output (jq puro, sem timestamps
#         no payload).
#
#   model-routing-report.sh -h | --help
#       — Imprime USO em stderr e exit 2 (padrao do dispatch do runtime).
#
# Output JSON (--json):
#   {
#     "total": <int>,                    # total de Decisoes de selecao
#     "por_modelo": {                    # contagem por escolha
#       "haiku":            <int>,
#       "sonnet":           <int>,
#       "opus":             <int>,
#       "manter-atual":     <int>,
#       "fallback-default": <int>
#     },
#     "fallback_count": <int>,           # alias para por_modelo["fallback-default"]
#     "fallback_pct": "<float-1-casa>%", # ex: "12.5%" — 0.0% se total=0
#     "por_subagent_type": {             # breakdown subagent_type -> modelo -> count
#       "<TYPE>": { "haiku": <int>, "sonnet": <int>, ... },
#       ...
#     }
#   }
#
# Output Markdown (default — formato canonico para review-task — F5.2):
#   ## Selecao de modelo por subagente (model-routing)
#
#   | subagent_type | etapa | onda | modelo | score | fallback |
#   |---------------|-------|------|--------|-------|----------|
#   | ...           | ...   | ...  | ...    | ...   | ...      |
#
#   **Sumario**:
#   - Total: <N>
#   - haiku: <n>
#   - sonnet: <n>
#   - opus: <n>
#   - manter-atual: <n>
#   - fallback-default: <n> (<pct>%)
#
# Exit codes:
#   0 sucesso
#   1 erro generico (state.json ausente, jq ausente, parsing invalido)
#   2 uso incorreto (flag ausente, subcomando desconhecido)
#
# Invariantes:
#   IR-1: read-only sobre state.json — jq sem -i, sem redirecionamento ao
#         arquivo (auditavel via grep no codigo).
#   IR-2: idempotente — sem timestamps no payload; mesmo input -> mesmo
#         output byte-a-byte.
#   IR-3: helper completo respeita Principio II — #!/bin/sh, set -eu, deps
#         apenas em jq.
#
# POSIX sh + jq.

set -eu

_MRR_NAME="model-routing-report"

# ---------- Helpers privados ----------

_mrr_die_usage() {
  printf '%s: %s\n' "$_MRR_NAME" "$1" >&2
  _mrr_print_usage >&2
  exit 2
}

_mrr_die() {
  printf '%s: %s\n' "$_MRR_NAME" "$1" >&2
  exit "${2:-1}"
}

_mrr_print_usage() {
  cat <<'EOF'
USO:
  model-routing-report.sh aggregate --state-dir DIR [--json]
  model-routing-report.sh -h | --help
EOF
}

_mrr_require_jq() {
  command -v jq >/dev/null 2>&1 \
    || _mrr_die "jq nao encontrado no PATH" 1
}

# ---------- Subcomando: aggregate ----------

# _mrr_jq_program — programa jq compartilhado para extrair Decisoes de
# selecao + agregar. Retorna um objeto:
#   { total, por_modelo, fallback_count, fallback_pct, por_subagent_type, linhas }
# onde `linhas` e um array de registros (subagent_type, etapa, onda, modelo,
# score, fallback) para a tabela Markdown.
#
# Lead pattern do contexto: "Selecao de modelo para subagente <TYPE>"
# subagent_type e extraido via sub() — tudo apos o prefixo fixo.
_mrr_jq_program() {
  cat <<'JQ'
def labels: ["haiku","sonnet","opus","manter-atual","fallback-default"];

# Filtra apenas Decisoes de selecao de modelo (FR-018 + dec-004).
def selecoes:
  (.decisoes // [])
  | map(select(.contexto | test("^Selecao de modelo para subagente ")));

# Extrai subagent_type do contexto (tudo apos o prefixo fixo de 41 chars).
def subagent_of:
  .contexto | sub("^Selecao de modelo para subagente "; "");

# Counter inicializado com todos os labels em 0 (garante chaves estaveis).
def zero_counts:
  labels | map({(.): 0}) | add;

# Conta ocorrencias de cada label em uma lista de strings.
def count_labels(xs):
  reduce (xs[]) as $e (
    zero_counts;
    if (labels | index($e)) != null
    then .[$e] += 1
    else .                # ignora labels fora do enum (defesa)
    end
  );

selecoes as $s
| ($s | length) as $total
| ($s | map(.escolha)) as $escolhas
| (count_labels($escolhas)) as $por_modelo
| ($por_modelo["fallback-default"]) as $fb
| (if $total == 0 then "0.0%"
   else ((($fb * 1000) / $total | floor) / 10 | tostring) + "%"
   end) as $pct
| ($s
   | group_by(subagent_of)
   | map({
       key: (.[0] | subagent_of),
       value: count_labels(map(.escolha))
     })
   | from_entries) as $por_st
| ($s | map({
    subagent_type: subagent_of,
    etapa:         (.etapa // ""),
    onda:          (.onda_id // ""),
    modelo:        .escolha,
    score:         (.score_justificativa // 0),
    fallback:      (.escolha == "fallback-default")
  })) as $linhas
| {
    total:             $total,
    por_modelo:        $por_modelo,
    fallback_count:    $fb,
    fallback_pct:      $pct,
    por_subagent_type: $por_st,
    linhas:            $linhas
  }
JQ
}

# _mrr_render_md AGG_JSON
# Recebe o JSON agregado e renderiza tabela Markdown canonica (F5.2.2).
_mrr_render_md() {
  printf '%s' "$1" | jq -r '
    "## Selecao de modelo por subagente (model-routing)",
    "",
    "| subagent_type | etapa | onda | modelo | score | fallback |",
    "|---------------|-------|------|--------|-------|----------|",
    ( .linhas[]
      | "| \(.subagent_type) | \(.etapa) | \(.onda) | \(.modelo) | \(.score) | \(if .fallback then "yes" else "no" end) |"
    ),
    "",
    "**Sumario**:",
    "- Total: \(.total)",
    "- haiku: \(.por_modelo.haiku)",
    "- sonnet: \(.por_modelo.sonnet)",
    "- opus: \(.por_modelo.opus)",
    "- manter-atual: \(.por_modelo["manter-atual"])",
    "- fallback-default: \(.por_modelo["fallback-default"]) (\(.fallback_pct))"
  '
}

_mrr_cmd_aggregate() {
  _mrr_require_jq

  _mrr_state_dir=""
  _mrr_emit_json=0

  while [ $# -gt 0 ]; do
    case "$1" in
      --state-dir)
        [ $# -ge 2 ] || _mrr_die_usage "aggregate: --state-dir requer valor"
        _mrr_state_dir=$2
        shift 2
        ;;
      --state-dir=*)
        _mrr_state_dir=${1#--state-dir=}
        shift
        ;;
      --json)
        _mrr_emit_json=1
        shift
        ;;
      *)
        _mrr_die_usage "aggregate: argumento desconhecido: $1"
        ;;
    esac
  done

  [ -n "$_mrr_state_dir" ] \
    || _mrr_die_usage "aggregate: --state-dir obrigatorio"

  _mrr_state_file="$_mrr_state_dir/state.json"
  [ -f "$_mrr_state_file" ] \
    || _mrr_die "aggregate: state.json nao encontrado em $_mrr_state_file" 1

  # Read-only sobre state.json (IR-1) — jq sem -i, sem redir.
  _mrr_agg=$(jq -c "$(_mrr_jq_program)" "$_mrr_state_file") \
    || _mrr_die "aggregate: jq falhou ao processar state.json" 1

  if [ "$_mrr_emit_json" = 1 ]; then
    printf '%s\n' "$_mrr_agg" | jq '.'
  else
    _mrr_render_md "$_mrr_agg"
  fi
}

# ---------- Dispatch ----------

if [ $# -eq 0 ]; then
  _mrr_print_usage >&2
  exit 2
fi

case "$1" in
  -h|--help|help)
    _mrr_print_usage >&2
    exit 2
    ;;
  aggregate)
    shift
    _mrr_cmd_aggregate "$@"
    ;;
  *)
    printf '%s: subcomando desconhecido: %s\n' "$_MRR_NAME" "$1" >&2
    _mrr_print_usage >&2
    exit 2
    ;;
esac
