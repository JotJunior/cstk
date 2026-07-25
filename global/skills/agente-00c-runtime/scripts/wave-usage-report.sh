#!/bin/sh
# wave-usage-report.sh — agregador read-only para consumo de tokens/tool-uses/
# duracao observado nos spawns de subagente de uma execucao agente-00c/
# feature-00c. Cumpre FR-005 (US1) da feature wave-token-metrics.
#
# Ref: docs/specs/wave-token-metrics/contracts/wave-usage-report.md §2/§3
#      docs/specs/wave-token-metrics/data-model.md
#        (Entity: SpawnUsage / WaveUsage; secao "Extensoes ao state.json")
#      docs/specs/wave-token-metrics/tasks.md FASE 4 (4.1.1, 4.1.2, 4.1.4)
#
# Por que um helper novo (e nao estender model-routing-report.sh): ver
# contracts/wave-usage-report.md §1 — model-routing-report.sh le SOMENTE
# .decisions[] e documenta explicitamente que nao le .waves; agregar
# .waves[].agent_usage la quebraria esse invariante publicado.
#
# Subcomandos:
#   wave-usage-report.sh aggregate --state-dir DIR [--json]
#       — Le state.json em <DIR>/state.json e agrega .waves[].agent_usage +
#         .waves[].agent_spawns[] (escritos por state-ondas.sh end, que por
#         sua vez consome o sidecar wave-agent-usage.jsonl do hook
#         posttooluse-agent-usage.sh). Read-only sobre state.json.
#         Default: Markdown canonico (colavel verbatim em review-task/
#         report.sh). Com --json: agregado maquina-legivel.
#
#   wave-usage-report.sh -h | --help
#       — Imprime USO em stderr e exit 2 (padrao do dispatch do runtime).
#
# NAO IMPLEMENTADO NESTE ARQUIVO (deliberado): o subcomando `backfill`
# (contracts/wave-usage-report.md §3, US4/FR-010/FR-011) e trabalho da
# FASE 7 do backlog (tasks.md 7.1.1-7.1.5 — heuristica de janela temporal +
# recusa explicita quando o transcript nao cobre a onda). A tarefa 4.1.3
# desta FASE 4 e um forward-reference explicito para aquela fase ("ver
# detalhamento na FASE 7") — implementar aqui uma leitura de transcript sem
# a heuristica/testes da FASE 7 fabricaria funcionalidade nao validada.
# Ate la, `backfill` cai no dispatch de "subcomando desconhecido" (exit 2).
#
# ---------------------------------------------------------------------
# Semantica de agregacao (decisoes de design desta implementacao — o
# contrato fornece exemplo ilustrativo mas nao formaliza a formula; ver
# Decisao auditavel dec-* registrada na onda de implementacao):
#
#   - Uma "onda" so entra em `por_onda`/na tabela Markdown quando
#     `.waves[N].agent_usage != null`, isto e: pelo menos 1 SpawnUsage foi
#     observado naquela onda (spawns_total > 0), MESMO que todos tenham
#     ficado `indisponivel`. Ondas com zero spawns (agent_usage null por
#     ausencia total de registro) sao OMITIDAS da tabela — nao ha o que
#     reportar sobre uma onda que nunca tentou spawnar subagente.
#   - `waves_total`/`waves_with_usage` (JSON) e "Ondas com metrica: X de Y"
#     (Markdown) usam Y = numero de ondas presentes na tabela (que TIVERAM
#     spawns observados) e X = quantas dessas tiveram spawns_with_usage>0
#     (dado de fato utilizavel, nao so tentativa). Bate exatamente com o
#     exemplo do contrato (2 ondas na tabela, 1 com uso real => "1 de 2").
#   - Formatacao "k" (milhares): valores >= 10000 sao renderizados como
#     "N.Nk" (1 casa decimal, truncada — nao arredondada); abaixo disso,
#     inteiro cru. Essa e a UNICA formula consistente com todos os valores
#     do exemplo do contrato (250900 -> "250.9k", 254000 -> "254.0k", mas
#     1049/1975/4/72 permanecem crus). Duracao usa segundos inteiros
#     truncados + sufixo "s" (923000ms -> "923s").
#   - `por_modelo` (JSON) agrupa TODOS os SpawnUsage (de todas as ondas com
#     `agent_usage != null`) pelo campo `.model`, que e SEMPRE presente no
#     schema (data-model.md: "nao-aplicavel" quando resolvedModel ausente
#     na fonte) — logo spawns `indisponivel` aparecem no balde
#     "nao-aplicavel" com todos os campos de uso em null, nunca omitidos.
#
# Campos numericos de uso (`total_tokens`, `input_tokens`, `output_tokens`,
# `cache_read_input_tokens`, `cache_creation_input_tokens`,
# `tool_use_count`, `duration_ms`) sao SOMAS apenas dos valores nao-null;
# ausencia total de dado produz `null` (JSON) / "indisponivel" (Markdown) —
# NUNCA `0` fabricado (FR-009/SC-004, Principio VI). Contadores literais de
# ocorrencia (`spawns_total`, `spawns_with_usage`, `spawns_unavailable`,
# `waves_total`, `waves_with_usage`) sao sempre inteiros — `0` ali e uma
# contagem real, nao uma fabricacao.
#
# Campo `metric_collected` (JSON, ADITIVO ao contrato — nao quebra
# consumidores que ignoram campos desconhecidos): `false` quando NENHUMA
# onda da execucao produziu `agent_usage != null` — isto e, o hook nunca
# gerou dado observavel em toda a execucao (research Decision 10: hook
# ausente/nao provisionado E "zero spawns em toda a execucao" sao
# indistinguiveis a partir do state.json; o campo apenas nomeia esse
# estado agregado para consumidores como report.sh/review-task, FASE 4.2 /
# FASE 6, que precisam decidir se mostram "0" ou uma mensagem de
# degradacao). Quando `metric_collected=false`, a saida Markdown NUNCA
# imprime uma tabela de zeros — imprime a frase explicita exigida pelo
# contrato §2.1 ponto 4.
#
# Exit codes (espelham model-routing-report.sh):
#   0 sucesso
#   1 erro generico (state.json ausente/ilegivel, jq ausente, parsing invalido)
#   2 uso incorreto (flag ausente, subcomando desconhecido)
#
# Invariantes:
#   IR-1: read-only sobre state.json — jq sem -i, sem redirecionamento ao
#         arquivo (auditavel via grep no codigo).
#   IR-2: idempotente — sem timestamps no payload; mesmo input -> mesmo
#         output byte-a-byte.
#   IR-3: Principio II — #!/bin/sh, set -eu, deps apenas em jq.
#
# POSIX sh + jq.

set -eu

_WUR_NAME="wave-usage-report"

# ---------- Helpers privados ----------

_wur_die_usage() {
  printf '%s: %s\n' "$_WUR_NAME" "$1" >&2
  _wur_print_usage >&2
  exit 2
}

_wur_die() {
  printf '%s: %s\n' "$_WUR_NAME" "$1" >&2
  exit "${2:-1}"
}

_wur_print_usage() {
  cat <<'EOF'
USO:
  wave-usage-report.sh aggregate --state-dir DIR [--json]
  wave-usage-report.sh -h | --help
EOF
}

_wur_require_jq() {
  command -v jq >/dev/null 2>&1 \
    || _wur_die "jq nao encontrado no PATH" 1
}

# ---------- Subcomando: aggregate ----------

# _wur_jq_program — programa jq compartilhado. Le .waves[] do state.json e
# produz o agregado descrito no cabecalho deste arquivo. Read-only (IR-1).
_wur_jq_program() {
  cat <<'JQ'
# soma so os valores nao-null de xs; [] ou so-nulls -> null (nunca 0
# fabricado — Principio VI / FR-009).
def sum_or_null(xs):
  ([xs[] | select(. != null)]) as $vals
  | if ($vals | length) > 0 then ($vals | add) else null end;

# "N.Nk" (>=10000, 1 casa truncada) ou inteiro cru (<10000); null -> null.
# Formula documentada no cabecalho do arquivo.
def fmt_tokens_num(v):
  if v == null then null
  elif v >= 10000 then
    (v / 100 | floor) as $tenths
    | ($tenths / 10 | floor) as $whole
    | ($tenths - ($whole * 10)) as $dec
    | (($whole | tostring) + "." + ($dec | tostring) + "k")
  else
    (v | tostring)
  end;

def fmt_tokens(v): (fmt_tokens_num(v)) // "indisponivel";

def fmt_duration(ms):
  if ms == null then "indisponivel"
  else (((ms / 1000) | floor | tostring) + "s")
  end;

# pct com 1 casa truncada; tot=0 -> null (0/0 indefinido, nao "0.0%").
def pct1_or_null(n; tot):
  if tot == 0 then null
  else
    ((n * 1000 / tot) | floor) as $t
    | ($t / 10 | floor) as $whole
    | ($t - ($whole * 10)) as $dec
    | (($whole | tostring) + "." + ($dec | tostring) + "%")
  end;

(.waves // []) as $waves

# Ondas com pelo menos 1 SpawnUsage observado (agent_usage != null).
| ($waves | map(select((.agent_usage // null) != null))) as $rows_src

| ($rows_src | map({
    onda:                         .id,
    spawns_total:                 .agent_usage.spawns_total,
    spawns_with_usage:            .agent_usage.spawns_with_usage,
    spawns_unavailable:           .agent_usage.spawns_unavailable,
    total_tokens:                 .agent_usage.total_tokens,
    input_tokens:                 .agent_usage.input_tokens,
    output_tokens:                .agent_usage.output_tokens,
    cache_read_input_tokens:      .agent_usage.cache_read_input_tokens,
    cache_creation_input_tokens:  .agent_usage.cache_creation_input_tokens,
    tool_use_count:               .agent_usage.tool_use_count,
    duration_ms:                  .agent_usage.duration_ms
  })) as $por_onda

| ($por_onda | length) as $waves_total
| ($por_onda | map(select(.spawns_with_usage > 0)) | length) as $waves_with_usage
| (($por_onda | map(.spawns_total) | add) // 0) as $spawns_total
| (($por_onda | map(.spawns_with_usage) | add) // 0) as $spawns_with_usage
| ($spawns_total - $spawns_with_usage) as $spawns_unavailable

| sum_or_null($por_onda | map(.total_tokens))                as $total_tokens
| sum_or_null($por_onda | map(.input_tokens))                as $input_tokens
| sum_or_null($por_onda | map(.output_tokens))               as $output_tokens
| sum_or_null($por_onda | map(.cache_read_input_tokens))     as $cache_read_input_tokens
| sum_or_null($por_onda | map(.cache_creation_input_tokens)) as $cache_creation_input_tokens
| sum_or_null($por_onda | map(.tool_use_count))               as $tool_use_count
| sum_or_null($por_onda | map(.duration_ms))                  as $duration_ms

# por_modelo: agrupa TODOS os SpawnUsage brutos (de ondas com agent_usage
# != null) pelo campo .model (sempre presente no schema — "nao-aplicavel"
# quando o harness nao expos resolvedModel).
| ($rows_src | map(.agent_spawns // []) | add // []) as $all_spawns
| ( $all_spawns
    | group_by(.model // "nao-aplicavel")
    | map({
        key: ((.[0].model // "nao-aplicavel")),
        value: {
          spawns:                        (. | length),
          spawns_with_usage:             ([.[] | select(.status != "indisponivel")] | length),
          total_tokens:                  sum_or_null(map(.total_tokens)),
          input_tokens:                  sum_or_null(map(.input_tokens)),
          output_tokens:                 sum_or_null(map(.output_tokens)),
          cache_read_input_tokens:       sum_or_null(map(.cache_read_input_tokens)),
          cache_creation_input_tokens:   sum_or_null(map(.cache_creation_input_tokens)),
          tool_use_count:                sum_or_null(map(.tool_use_count)),
          duration_ms:                   sum_or_null(map(.duration_ms))
        }
      })
    | from_entries
  ) as $por_modelo

| {
    waves_total:                  $waves_total,
    waves_with_usage:             $waves_with_usage,
    spawns_total:                 $spawns_total,
    spawns_with_usage:            $spawns_with_usage,
    spawns_unavailable:           $spawns_unavailable,
    coverage_pct:                 pct1_or_null($spawns_with_usage; $spawns_total),
    total_tokens:                 $total_tokens,
    input_tokens:                 $input_tokens,
    output_tokens:                $output_tokens,
    cache_read_input_tokens:      $cache_read_input_tokens,
    cache_creation_input_tokens:  $cache_creation_input_tokens,
    tool_use_count:               $tool_use_count,
    duration_ms:                  $duration_ms,
    por_onda:                     $por_onda,
    por_modelo:                   $por_modelo,
    metric_collected:             ($waves_total > 0)
  }
JQ
}

# _wur_render_md AGG_JSON
# Recebe o JSON agregado e renderiza a saida Markdown canonica (contract §2.1).
_wur_render_md() {
  printf '%s' "$1" | jq -r '
    def fmt_tokens_num(v):
      if v == null then null
      elif v >= 10000 then
        (v / 100 | floor) as $tenths
        | ($tenths / 10 | floor) as $whole
        | ($tenths - ($whole * 10)) as $dec
        | (($whole | tostring) + "." + ($dec | tostring) + "k")
      else
        (v | tostring)
      end;
    def fmt_tokens(v): (fmt_tokens_num(v)) // "indisponivel";
    def fmt_duration(ms):
      if ms == null then "indisponivel"
      else (((ms / 1000) | floor | tostring) + "s")
      end;

    "## Consumo por onda (tokens / tool-uses / duracao)",
    "",
    ( if .metric_collected then
        (
          "| onda | spawns | com uso | tokens | input | output | cache-read | cache-creation | tool-uses | duracao |",
          "|------|--------|---------|--------|-------|--------|------------|----------------|-----------|---------|",
          ( .por_onda[]
            | "| \(.onda) | \(.spawns_total) | \(.spawns_with_usage) | \(fmt_tokens(.total_tokens)) | \(fmt_tokens(.input_tokens)) | \(fmt_tokens(.output_tokens)) | \(fmt_tokens(.cache_read_input_tokens)) | \(fmt_tokens(.cache_creation_input_tokens)) | \(fmt_tokens(.tool_use_count)) | \(fmt_duration(.duration_ms)) |"
          ),
          "",
          "**Sumario**:",
          "- Ondas com metrica: \(.waves_with_usage) de \(.waves_total)",
          "- Spawns observados: \(.spawns_total) (com uso: \(.spawns_with_usage); indisponiveis: \(.spawns_unavailable))",
          "- Tokens totais: \(fmt_tokens(.total_tokens)) (input \(fmt_tokens(.input_tokens)) / output \(fmt_tokens(.output_tokens)) / cache-read \(fmt_tokens(.cache_read_input_tokens)) / cache-creation \(fmt_tokens(.cache_creation_input_tokens)))",
          ( if .spawns_unavailable > 0 then
              "- Cobertura da metrica: \(.coverage_pct // "indisponivel") dos spawns"
            else empty end
          )
        )
      else
        (
          "Metrica de uso de subagente nao foi coletada nesta execucao (hook `posttooluse-agent-usage.sh` ausente/nao provisionado, ou nenhum subagente foi spawnado ate agora). Nao reportar como \"0 tokens\" — o dado simplesmente nao foi observado."
        )
      end
    )
  '
}

_wur_cmd_aggregate() {
  _wur_require_jq

  _wur_state_dir=""
  _wur_emit_json=0

  while [ $# -gt 0 ]; do
    case "$1" in
      --state-dir)
        [ $# -ge 2 ] || _wur_die_usage "aggregate: --state-dir requer valor"
        _wur_state_dir=$2
        shift 2
        ;;
      --state-dir=*)
        _wur_state_dir=${1#--state-dir=}
        shift
        ;;
      --json)
        _wur_emit_json=1
        shift
        ;;
      *)
        _wur_die_usage "aggregate: argumento desconhecido: $1"
        ;;
    esac
  done

  [ -n "$_wur_state_dir" ] \
    || _wur_die_usage "aggregate: --state-dir obrigatorio"

  _wur_state_file="$_wur_state_dir/state.json"
  [ -f "$_wur_state_file" ] \
    || _wur_die "aggregate: state.json nao encontrado em $_wur_state_file" 1

  # Read-only sobre state.json (IR-1) — jq sem -i, sem redir.
  _wur_agg=$(jq -c "$(_wur_jq_program)" "$_wur_state_file") \
    || _wur_die "aggregate: jq falhou ao processar state.json" 1

  if [ "$_wur_emit_json" = 1 ]; then
    printf '%s\n' "$_wur_agg" | jq '.'
  else
    _wur_render_md "$_wur_agg"
  fi
}

# ---------- Dispatch ----------

if [ $# -eq 0 ]; then
  _wur_print_usage >&2
  exit 2
fi

case "$1" in
  -h|--help|help)
    _wur_print_usage >&2
    exit 2
    ;;
  aggregate)
    shift
    _wur_cmd_aggregate "$@"
    ;;
  *)
    printf '%s: subcomando desconhecido: %s\n' "$_WUR_NAME" "$1" >&2
    _wur_print_usage >&2
    exit 2
    ;;
esac
