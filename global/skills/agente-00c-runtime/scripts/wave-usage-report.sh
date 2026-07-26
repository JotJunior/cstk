#!/bin/sh
# wave-usage-report.sh — agregador read-only para consumo de tokens/tool-uses/
# duracao observado nos spawns de subagente de uma execucao agente-00c/
# feature-00c. Cumpre FR-005 (US1) da feature wave-token-metrics.
#
# Ref: docs/specs/wave-token-metrics/contracts/wave-usage-report.md §2/§3
#      docs/specs/wave-token-metrics/data-model.md
#        (Entity: SpawnUsage / WaveUsage; secao "Extensoes ao state.json")
#      docs/specs/wave-token-metrics/research.md
#        Decision 9 — Backfill por janela temporal, com recusa explicita
#      docs/specs/wave-token-metrics/tasks.md FASE 4 (4.1.1, 4.1.2, 4.1.4)
#        e FASE 7 (7.1.1-7.1.5 — subcomando backfill)
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
#   wave-usage-report.sh backfill --state-dir DIR --transcript PATH [--dry-run]
#       — US4/FR-010/FR-011 (contracts §3, research Decision 9). Reconstroi
#         SpawnUsage retroativamente a partir de um transcript JSONL de
#         sessao ja encerrada, para execucoes anteriores a esta feature (ou
#         com hook nao provisionado no momento). Algoritmo:
#           1. Extrai do transcript os pares tool_use(name="Agent") + o
#              tool_result correspondente (mesmo tool_use_id) cujo
#              toolUseResult carrega agentId — mesmos campos do hook
#              posttooluse-agent-usage.sh (agentId, status, resolvedModel,
#              modelsUsed, totalTokens, usage.*, totalToolUseCount,
#              totalDurationMs), com a MESMA derivacao de `status`
#              (completo/parcial/indisponivel) e a MESMA regra de
#              null-nao-fabricado (Principio VI/FR-009).
#           2. Atribui cada SpawnUsage a onda cuja janela
#              `started_at <= ts < finished_at` o contem (ts = timestamp do
#              registro de tool_result no transcript). HEURISTICA, nao
#              chave — o transcript nao carrega id de onda (Decision 9).
#              Spawns fora de toda janela sao descartados (nao pertencem a
#              esta execucao ou ao intervalo coberto pelo transcript).
#           3. Todo SpawnUsage gravado leva `source: "backfill"` (nunca
#              "live") — proveniencia obrigatoria.
#           4. Dedup por chave natural `(wave_id, agent_id)`: spawns ja
#              presentes em `.waves[].agent_spawns` (de qualquer source) sao
#              ignorados — reexecutar sobre o mesmo transcript e idempotente
#              (byte-idêntico, sem novo write).
#           5. `--dry-run`: imprime o que seria aplicado (onda destino +
#              agent_id por spawn) e sai 0, sem escrever nada.
#         Recusa explicita (FR-011, exit 3) quando: (a) --transcript esta
#         ausente/ilegivel, ou (b) o transcript foi lido mas NENHUM spawn
#         correlacionado cai dentro de nenhuma janela de onda desta
#         execucao (transcript nao cobre a execucao). Em ambos os casos,
#         NENHUM campo de metrica e escrito — nunca estimado/sintetico.
#         Escrita (quando ha >=1 spawn novo): delega a
#         `state-rw.sh write --state-dir DIR` (stdin = state.json completo
#         apos o merge) — reusa o caminho canonico de escrita do runtime
#         (backup em state-history/ + escrita atomica + recomputo de
#         state.json.sha256), a mesma garantia que `state-ondas.sh end` ja
#         oferece para a captura ao vivo.
#
#   wave-usage-report.sh -h | --help
#       — Imprime USO em stderr e exit 2 (padrao do dispatch do runtime).
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
# Exit codes de `aggregate` (espelham model-routing-report.sh):
#   0 sucesso
#   1 erro generico (state.json ausente/ilegivel, jq ausente, parsing invalido)
#   2 uso incorreto (flag ausente, subcomando desconhecido)
#
# Exit codes de `backfill` (contracts §3):
#   0 backfill aplicado, ou 0 novos spawns (idempotente), ou --dry-run OK
#   1 erro generico (state.json ausente/ilegivel, jq ausente)
#   2 uso incorreto (flag ausente)
#   3 recusa explicita FR-011 (transcript ausente/ilegivel, ou transcript
#     nao cobre nenhuma onda desta execucao) — NUNCA escreve valor estimado
#
# Invariantes:
#   IR-1: `aggregate` e read-only sobre state.json — jq sem -i, sem
#         redirecionamento ao arquivo (auditavel via grep no codigo).
#         `backfill` e a UNICA excecao documentada: quando ha >=1 spawn
#         novo, escreve via `state-rw.sh write` (backup + atomic write +
#         sha256 update no caminho canonico do runtime — nunca io direto
#         no arquivo por este script).
#   IR-2: `aggregate` e idempotente — sem timestamps no payload; mesmo
#         input -> mesmo output byte-a-byte. `backfill` e idempotente por
#         dedup de chave natural (wave_id, agent_id): reexecutar sobre o
#         mesmo transcript produz 0 novos spawns e nenhum write.
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
  wave-usage-report.sh backfill --state-dir DIR --transcript PATH [--dry-run]
  wave-usage-report.sh -h | --help
EOF
}

_wur_require_jq() {
  command -v jq >/dev/null 2>&1 \
    || _wur_die "jq nao encontrado no PATH" 1
}

# Diretorio do proprio script (mesma receita de _so_self_dir em
# state-ondas.sh) — usado por backfill para localizar state-rw.sh irmao.
_wur_self_dir() {
  CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd -P
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

# ---------- Subcomando: backfill ----------

# _wur_backfill_jq_program — programa jq compartilhado do subcomando
# backfill. Le o transcript ja parseado (array de registros JSONL, injetado
# via --slurpfile tr, $tr[0]) e o state.json (input principal `.`) e produz
# UM objeto: { refuse, extracted_total, covered_total, new_total,
# duplicate_total, by_wave, state }. `state` e o state.json COMPLETO apos o
# merge (identico ao original quando new_total == 0 — o chamador so escreve
# quando new_total > 0, preservando IR-2/idempotencia).
#
# Extracao: mesma correlacao tool_use(name="Agent") <-> tool_result via
# tool_use_id, e a MESMA derivacao de status/campos-null que
# posttooluse-agent-usage.sh usa para a captura ao vivo (contracts §3:
# "verificado 6/6 nesta sessao" — Decision 1/2 do research). Atribuicao de
# onda por janela temporal (Decision 9): heuristica, primeiro match vence.
_wur_backfill_jq_program() {
  cat <<'JQ'
. as $ORIG_STATE |
def strip_ms(ts): if ts == null then null else (ts | sub("\\.[0-9]+Z$"; "Z")) end;
def epoch(ts): (strip_ms(ts)) as $s | if $s == null then null else (try ($s | fromdateiso8601) catch null) end;

def sum_field(arr; f): ([arr[] | select(f != null) | f]) as $vals
  | if ($vals|length) > 0 then ($vals|add) else null end;

# Mesma formula de agregacao de _so_cmd_end (state-ondas.sh) — WaveUsage a
# partir de um array de SpawnUsage. spawns=[] -> null (nunca onda fantasma).
def wave_usage_of(spawns):
  (spawns | length) as $total
  | ([spawns[] | select(.status != "indisponivel")] | length) as $with_usage
  | ($total - $with_usage) as $unavail
  | if $total > 0 then {
      spawns_total: $total, spawns_with_usage: $with_usage, spawns_unavailable: $unavail,
      total_tokens: sum_field(spawns; .total_tokens),
      input_tokens: sum_field(spawns; .input_tokens),
      output_tokens: sum_field(spawns; .output_tokens),
      cache_read_input_tokens: sum_field(spawns; .cache_read_input_tokens),
      cache_creation_input_tokens: sum_field(spawns; .cache_creation_input_tokens),
      tool_use_count: sum_field(spawns; .tool_use_count),
      duration_ms: sum_field(spawns; .duration_ms)
    } else null end;

def add_null(existing; delta): if delta == null then existing else ((existing // 0) + delta) end;

($tr[0] // []) as $records

# tool_use(name="Agent") -> agent_type, indexado por tool_use_id.
| ([$records[] | select(.type=="assistant") | (.message.content // [])[]
     | select(.type=="tool_use" and .name=="Agent")
     | {id: .id, agent_type: (.input.subagent_type // null)}]) as $agent_calls
| ($agent_calls | map({(.id): .agent_type}) | add // {}) as $agent_type_by_id

# tool_result cujo tool_use_id casa com uma chamada Agent E cujo
# toolUseResult carrega agentId (mesma condicao de "empty" do hook: sem
# agentId -> sem SpawnUsage).
| ([$records[]
     | select(.type=="user" and .toolUseResult != null)
     | . as $rec
     | (((.message.content // [])[] | select(.type=="tool_result") | .tool_use_id) // null) as $tuid
     | select($tuid != null and ($agent_type_by_id | has($tuid)))
     | ($rec.toolUseResult) as $trr
     | ($trr.agentId // null) as $aid
     | select($aid != null)
     | ($trr.status // "") as $status_raw
     | (if $status_raw == "completed" and ($trr.totalTokens != null) then "completo"
        elif $status_raw == "completed" then "parcial"
        else "indisponivel" end) as $derived
     | {
         agent_id: $aid,
         agent_type: ($agent_type_by_id[$tuid] // null),
         status: $derived,
         model: ($trr.resolvedModel // "nao-aplicavel"),
         models_used: ($trr.modelsUsed // null),
         total_tokens: (if $derived=="indisponivel" then null else ($trr.totalTokens // null) end),
         input_tokens: (if $derived=="indisponivel" then null else ($trr.usage.input_tokens // null) end),
         output_tokens: (if $derived=="indisponivel" then null else ($trr.usage.output_tokens // null) end),
         cache_read_input_tokens: (if $derived=="indisponivel" then null else ($trr.usage.cache_read_input_tokens // null) end),
         cache_creation_input_tokens: (if $derived=="indisponivel" then null else ($trr.usage.cache_creation_input_tokens // null) end),
         tool_use_count: (if $derived=="indisponivel" then null else ($trr.totalToolUseCount // null) end),
         duration_ms: (if $derived=="indisponivel" then null else ($trr.totalDurationMs // null) end),
         source: "backfill",
         observed_at: ($rec.timestamp // null),
         _ts_epoch: epoch($rec.timestamp)
       }
   ]) as $extracted

| (.waves // []) as $waves_orig
| ($waves_orig | map({id: .id, s: epoch(.started_at), f: epoch(.finished_at)})) as $windows

# Atribuicao por janela temporal: started_at <= ts < finished_at (onda
# aberta, finished_at=null -> sem limite superior). Primeiro match vence
# (ondas nao se sobrepoem em condicoes normais).
| ($extracted | map(
     . as $sp
     | (reduce $windows[] as $w (null;
         if . == null and $w.s != null and $sp._ts_epoch != null
            and $sp._ts_epoch >= $w.s and ($w.f == null or $sp._ts_epoch < $w.f)
         then $w.id else . end)) as $wid
     | $sp + {wave_id: $wid}
   )) as $assigned_all

| ($assigned_all | map(select(.wave_id != null))) as $covered
| ($waves_orig | map({(.id): ([(.agent_spawns // [])[] | .agent_id])}) | add // {}) as $existing_ids_by_wave
# Dedup por (wave_id, agent_id) — chave natural (data-model.md §"Chave
# natural"); spawn ja presente (de qualquer source) nao entra de novo.
| ($covered | map(. as $c | select( ((($existing_ids_by_wave[$c.wave_id]) // []) | index($c.agent_id)) == null ))) as $new_spawns

| ($extracted | length) as $extracted_total
| ($covered | length) as $covered_total
| ($new_spawns | length) as $new_total
| ($covered_total - $new_total) as $duplicate_total
| ($new_spawns | group_by(.wave_id) | map({wave_id: .[0].wave_id, count: length, agent_ids: map(.agent_id)})) as $by_wave

# FR-011: transcript nao cobre NENHUMA onda desta execucao -> recusa.
# Distinto de "0 novos" (idempotencia): covered_total==0 e sobre o transcript
# em si, nao sobre o que ja foi persistido.
| (if $covered_total == 0 then true else false end) as $refuse

| (
    if $new_total == 0 then $ORIG_STATE
    else
      ($ORIG_STATE
        | .waves = (.waves | map(
            . as $w
            | (($new_spawns | map(select(.wave_id == $w.id)) | map(del(.wave_id, ._ts_epoch)))) as $add
            | if ($add | length) > 0 then
                (.agent_spawns = ((.agent_spawns // []) + $add))
                | (.agent_usage = wave_usage_of(.agent_spawns))
              else . end
          ))
        | (wave_usage_of($new_spawns | map(del(.wave_id, ._ts_epoch)))) as $delta
        | .accumulated_metrics.agent_spawns_total = ((.accumulated_metrics.agent_spawns_total // 0) + $new_total)
        | .accumulated_metrics.agent_spawns_with_usage_total =
            ((.accumulated_metrics.agent_spawns_with_usage_total // 0) + ([$new_spawns[] | select(.status != "indisponivel")] | length))
        | .accumulated_metrics.agent_tokens_total = add_null(.accumulated_metrics.agent_tokens_total; $delta.total_tokens)
        | .accumulated_metrics.agent_tool_use_count_total = add_null(.accumulated_metrics.agent_tool_use_count_total; $delta.tool_use_count)
        | .accumulated_metrics.agent_duration_ms_total = add_null(.accumulated_metrics.agent_duration_ms_total; $delta.duration_ms)
      )
    end
  ) as $new_state

| {
    refuse: $refuse,
    extracted_total: $extracted_total,
    covered_total: $covered_total,
    new_total: $new_total,
    duplicate_total: $duplicate_total,
    by_wave: $by_wave,
    state: $new_state
  }
JQ
}

_wur_cmd_backfill() {
  _wur_require_jq

  _wur_bt_state_dir=""
  _wur_bt_transcript=""
  _wur_bt_dry_run=0

  while [ $# -gt 0 ]; do
    case "$1" in
      --state-dir)
        [ $# -ge 2 ] || _wur_die_usage "backfill: --state-dir requer valor"
        _wur_bt_state_dir=$2
        shift 2
        ;;
      --state-dir=*)
        _wur_bt_state_dir=${1#--state-dir=}
        shift
        ;;
      --transcript)
        [ $# -ge 2 ] || _wur_die_usage "backfill: --transcript requer valor"
        _wur_bt_transcript=$2
        shift 2
        ;;
      --transcript=*)
        _wur_bt_transcript=${1#--transcript=}
        shift
        ;;
      --dry-run)
        _wur_bt_dry_run=1
        shift
        ;;
      *)
        _wur_die_usage "backfill: argumento desconhecido: $1"
        ;;
    esac
  done

  [ -n "$_wur_bt_state_dir" ] \
    || _wur_die_usage "backfill: --state-dir obrigatorio"
  [ -n "$_wur_bt_transcript" ] \
    || _wur_die_usage "backfill: --transcript obrigatorio"

  _wur_bt_state_file="$_wur_bt_state_dir/state.json"
  [ -f "$_wur_bt_state_file" ] \
    || _wur_die "backfill: state.json nao encontrado em $_wur_bt_state_file" 1

  # Rotulo da execucao para a mensagem de recusa (FR-011: "nomeando a
  # execucao que nao pode ser reconstruida"). Fallback ao basename do
  # state-dir quando .execution.id ausente (state antigo).
  _wur_bt_label=$(jq -r '.execution.id // empty' "$_wur_bt_state_file" 2>/dev/null) || _wur_bt_label=""
  [ -n "$_wur_bt_label" ] || _wur_bt_label=$(basename -- "$_wur_bt_state_dir")

  # FR-011, exit 3: transcript ausente/ilegivel — recusa explicita, NUNCA
  # estimar. Checado ANTES de qualquer tentativa de parse.
  if [ ! -f "$_wur_bt_transcript" ] || [ ! -r "$_wur_bt_transcript" ]; then
    _wur_die "backfill: recusado — transcript ausente/ilegivel: $_wur_bt_transcript; execucao $_wur_bt_label (state-dir: $_wur_bt_state_dir) nao pode ser reconstruida a partir deste arquivo" 3
  fi

  # Parse tolerante do transcript JSONL (mesmo idioma de _so_agent_usage_read
  # em state-ondas.sh): linhas corrompidas sao descartadas silenciosamente,
  # nunca abortam o arquivo inteiro (Principio VI — degradacao graciosa).
  _wur_bt_parsed=$(mktemp) || _wur_die "backfill: mktemp falhou" 1
  if ! jq -R -n '[inputs | fromjson?]' "$_wur_bt_transcript" > "$_wur_bt_parsed" 2>/dev/null; then
    rm -f -- "$_wur_bt_parsed"
    _wur_die "backfill: falha ao ler transcript (jq falhou sobre $_wur_bt_transcript)" 1
  fi

  _wur_bt_out=$(jq -c --slurpfile tr "$_wur_bt_parsed" "$(_wur_backfill_jq_program)" "$_wur_bt_state_file") \
    || { rm -f -- "$_wur_bt_parsed"; _wur_die "backfill: jq falhou ao processar transcript/state.json" 1; }
  rm -f -- "$_wur_bt_parsed"

  _wur_bt_refuse=$(printf '%s' "$_wur_bt_out" | jq -r '.refuse')
  if [ "$_wur_bt_refuse" = "true" ]; then
    _wur_die "backfill: recusado — transcript $_wur_bt_transcript nao cobre nenhuma onda da execucao $_wur_bt_label (state-dir: $_wur_bt_state_dir); nenhum SpawnUsage sintetico foi gravado" 3
  fi

  _wur_bt_extracted=$(printf '%s' "$_wur_bt_out" | jq -r '.extracted_total')
  _wur_bt_covered=$(printf '%s' "$_wur_bt_out" | jq -r '.covered_total')
  _wur_bt_new=$(printf '%s' "$_wur_bt_out" | jq -r '.new_total')
  _wur_bt_dup=$(printf '%s' "$_wur_bt_out" | jq -r '.duplicate_total')

  if [ "$_wur_bt_dry_run" = 1 ]; then
    printf 'backfill --dry-run (%s):\n' "$_wur_bt_label"
    printf '  spawns extraidos do transcript: %s\n' "$_wur_bt_extracted"
    printf '  cobertos por alguma janela de onda: %s\n' "$_wur_bt_covered"
    printf '  ja registrados (duplicados, seriam ignorados): %s\n' "$_wur_bt_dup"
    printf '  NOVOS a aplicar: %s\n' "$_wur_bt_new"
    printf '%s' "$_wur_bt_out" | jq -r '
      .by_wave[] | "    \(.wave_id): +\(.count) spawn(s) (source=backfill) — agent_id: \(.agent_ids | join(", "))"
    '
    printf 'Nenhuma escrita realizada (--dry-run).\n'
    return 0
  fi

  if [ "$_wur_bt_new" = 0 ]; then
    printf 'backfill (%s): 0 spawns novos — %s cobertos, todos ja registrados (idempotente); nenhuma escrita realizada\n' \
      "$_wur_bt_label" "$_wur_bt_covered"
    return 0
  fi

  # Escrita via caminho canonico do runtime (IR-1: unica excecao
  # documentada) — backup em state-history/ + atomic write + sha256 update,
  # tudo dentro de state-rw.sh write.
  _wur_selfdir=$(_wur_self_dir) || _wur_die "backfill: nao foi possivel resolver o diretorio do script" 1
  _wur_state_rw="$_wur_selfdir/state-rw.sh"
  [ -f "$_wur_state_rw" ] \
    || _wur_die "backfill: state-rw.sh nao encontrado em $_wur_selfdir (runtime incompleto)" 1

  printf '%s' "$_wur_bt_out" | jq -c '.state' \
    | sh "$_wur_state_rw" write --state-dir "$_wur_bt_state_dir" \
    || _wur_die "backfill: state-rw.sh write falhou — nenhuma garantia sobre o estado do arquivo, verifique state-history/" 1

  printf 'backfill (%s): %s spawn(s) novo(s) aplicado(s) (source=backfill), %s duplicado(s) ignorado(s)\n' \
    "$_wur_bt_label" "$_wur_bt_new" "$_wur_bt_dup"
  printf '%s' "$_wur_bt_out" | jq -r '
    .by_wave[] | "  \(.wave_id): +\(.count) spawn(s) — agent_id: \(.agent_ids | join(", "))"
  '
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
  backfill)
    shift
    _wur_cmd_backfill "$@"
    ;;
  *)
    printf '%s: subcomando desconhecido: %s\n' "$_WUR_NAME" "$1" >&2
    _wur_print_usage >&2
    exit 2
    ;;
esac
