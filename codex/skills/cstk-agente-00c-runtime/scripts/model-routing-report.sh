#!/bin/sh
# model-routing-report.sh — agregador read-only para Decisoes de selecao
# de modelo emitidas por `model-routing.sh invoke` + persistidas via
# `state-decisions.sh register`. Cumpre FR-018 (US-3, dec-006) da feature
# agente-00c-model-routing: agregacao real-time derivada de `.decisions[]`
# (sem campo agregado em `.waves`).
#
# Ref: docs/specs/agente-00c-model-routing/spec.md FR-018, SC-003, US-3
#      docs/specs/agente-00c-model-routing/tasks.md F5.1 (5.1.1..5.1.3)
#      docs/specs/agente-00c-model-routing/plan.md (Phase 5)
#      Decisao do clarify: dec-006 (jq real-time em vez de campo agregado)
#
# Subcomandos:
#   model-routing-report.sh aggregate --state-dir DIR [--json]
#       — Le state.json em <DIR>/state.json e produz agregado das Decisoes
#         cujo `.context` casa com `^Selecao de modelo para subagente `.
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
# Duas geracoes de Decisao de model-routing sao agregadas SEM colisao
# (feature model-routing-por-onda, FASE 6 — FR-012, FR-021, SC-006):
#
#   (L) LEGADO audit-only (feature agente-00c-model-routing):
#       context = "Selecao de modelo para subagente <TYPE>"
#       choice  ∈ {haiku,sonnet,opus,manter-atual,fallback-default}
#       NAO carrega modelo_aplicado/origem -> contabilizado como
#       origem=fallback (nao aplicado), distinto na agregacao por onda.
#
#   (N) NOVO por-onda (DecisaoDeRoteamentoPorOnda):
#       context = "Selecao de modelo para onda <N> (fase <f>)"
#       choice  = "model:<aplicado>" | "manter-atual"
#       rationale codifica tokens parseaveis no PREFIXO (dec-006):
#         "sugerido=<m> aplicado=<m> origem=<o> | <texto livre>"
#       origem   ∈ {mapa, refino, override-operador, fallback}
#
# Output JSON (--json):
#   {
#     # ---- Bloco LEGADO (compat F5.1.3 — inalterado) ----
#     "total": <int>,                    # total de Decisoes de selecao LEGADAS
#     "por_modelo": {                    # contagem por escolha (sugerido)
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
#     },
#
#     # ---- Bloco NOVO por-onda (FASE 6 — FR-012/021/SC-006) ----
#     "ondas": {
#       "total": <int>,                  # total de DecisoesDeRoteamentoPorOnda
#       "por_modelo_aplicado": {         # distribuicao do modelo APLICADO
#         "haiku": <int>, "sonnet": <int>, "opus": <int>, "manter-atual": <int>
#       },
#       "por_origem": {                  # contagem por origem rotulada
#         "mapa": <int>, "refino": <int>,
#         "override-operador": <int>, "fallback": <int>
#       },
#       "fallback_count": <int>,         # origem=fallback (== manter-atual aplicado)
#       "fallback_pct": "<f>%",          # sobre ondas.total
#       "override_count": <int>,         # origem=override-operador
#       "override_pct": "<f>%",          # sobre ondas.total
#       "divergencias": <int>,           # sugerido != aplicado (todas)
#       "divergencias_rotuladas": <int>, # divergencias com origem ∈
#                                        # {override-operador,fallback}
#       "divergencias_sem_rotulo": <int> # SC-006 DEVE ser 0
#     },
#     "linhas_onda": [                   # uma linha por DecisaoDeRoteamentoPorOnda
#       { "onda": "<id>", "etapa": "<f>", "sugerido": "<m>",
#         "aplicado": "<m>", "origem": "<o>", "divergente": <bool> }, ...
#     ]
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
#   <quando ha DecisoesDeRoteamentoPorOnda, segue a secao por-onda:>
#
#   ## Selecao de modelo por onda (sugerido vs aplicado)
#
#   | onda | etapa | sugerido | aplicado | origem | divergente |
#   |------|-------|----------|----------|--------|------------|
#   | ...  | ...   | ...      | ...      | ...    | ...        |
#
#   **Sumario por onda**:
#   - Total de ondas roteadas: <N>
#   - aplicado haiku/sonnet/opus/manter-atual: <n>/<n>/<n>/<n>
#   - origem mapa/refino/override-operador/fallback: <n>/<n>/<n>/<n>
#   - fallback (manter-atual): <n> (<pct>%)
#   - override do operador: <n> (<pct>%)
#   - divergencias sugerido!=aplicado: <n> (rotuladas: <n>, sem rotulo: <n>)
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
# Lead pattern do .context: "Selecao de modelo para subagente <TYPE>"
# subagent_type e extraido via sub() — tudo apos o prefixo fixo.
_mrr_jq_program() {
  cat <<'JQ'
def labels: ["haiku","sonnet","opus","manter-atual","fallback-default"];

# Modelos VALIDOS para o campo aplicado por onda (sem fallback-default —
# o legado audit-only; a geracao por-onda usa manter-atual como fallback).
def applied_labels: ["haiku","sonnet","opus","manter-atual"];

# Origens rotuladas da DecisaoDeRoteamentoPorOnda (data-model §origem).
def origem_labels: ["mapa","refino","override-operador","fallback"];

# Origens nas quais sugerido != aplicado e LEGITIMO (SC-006 / data-model
# invariante linha 63-64). Divergencia fora destas = "sem rotulo".
def origem_diverg_ok: ["override-operador","fallback"];

# pct com 1 casa decimal sobre um total (string "<f>%"; "0.0%" se total=0).
def pct1($n; $tot):
  if $tot == 0 then "0.0%"
  else (((($n * 1000) / $tot) | floor) / 10 | tostring) + "%"
  end;

# ---- Geracao LEGADA: contexto "...para subagente <T>" ----
# Reader de state.json: chave EN canonica com fallback pt-BR (.en // .pt).
def selecoes_legado:
  ((.decisions // .decisoes) // [])
  | map(select(((.context // .contexto) // "") | test("^Selecao de modelo para subagente ")));

def subagent_of:
  (.context // .contexto) | sub("^Selecao de modelo para subagente "; "");

def zero_counts:
  labels | map({(.): 0}) | add;

def count_labels(xs):
  reduce (xs[]) as $e (
    zero_counts;
    if (labels | index($e)) != null
    then .[$e] += 1
    else .                # ignora labels fora do enum (defesa)
    end
  );

# ---- Geracao NOVA por-onda: contexto "...para onda <N> (fase <f>)" ----
# Readers de state.json: chave EN canonica com fallback pt-BR (.en // .pt).
def selecoes_onda:
  ((.decisions // .decisoes) // [])
  | map(select(((.context // .contexto) // "") | test("^Selecao de modelo para onda ")));

# Extrai etapa do contexto "...para onda <N> (fase <f>)". Defesa: "" se
# o padrao nao casar (tolera evolucao do formato — FR-021).
def etapa_of_onda:
  (((.context // .contexto) // "") | capture("\\(fase (?<f>[^)]*)\\)").f) // "";

# Sugerido: token sugerido=<m> do rationale; defesa "" se ausente.
def sugerido_of:
  (((.rationale // .justificativa) // "") | capture("sugerido=(?<m>[a-z-]+)").m) // "";

# Aplicado: token aplicado=<m> do rationale; fallback p/ choice
# (model:<m> -> <m>; manter-atual). Defesa "manter-atual".
def aplicado_of:
  (((.rationale // .justificativa) // "") | capture("aplicado=(?<m>[a-z-]+)").m)
  // (((.choice // .escolha) // "manter-atual") | sub("^model:"; ""));

# Origem: token origem=<o> do rationale; defesa "fallback" (a
# Decisao legada sem token cai aqui via selecoes_onda? Nao — legada
# nunca casa selecoes_onda. Mas Decisao por-onda sem token e tratada
# como fallback conservador).
def origem_of:
  (((.rationale // .justificativa) // "") | capture("origem=(?<o>[a-z-]+)").o) // "fallback";

def zero_applied:
  applied_labels | map({(.): 0}) | add;

def zero_origem:
  origem_labels | map({(.): 0}) | add;

def count_applied(xs):
  reduce (xs[]) as $e (
    zero_applied;
    if (applied_labels | index($e)) != null then .[$e] += 1 else . end
  );

def count_origem(xs):
  reduce (xs[]) as $e (
    zero_origem;
    if (origem_labels | index($e)) != null then .[$e] += 1 else . end
  );

# ===== Agregacao LEGADA (bloco compat F5.1.3) =====
# NOTA migracao EN: as CHAVES dos objetos construidos abaixo (subagent_type,
# etapa, onda, modelo, score, fallback) sao keys de OUTPUT (relatorio em
# stdout) — FOLLOW-UP D, permanecem pt-BR. Ja os VALORES lidos a direita
# (.choice, .stage, .wave_id, .justification_score) vem de state.json:
# chave EN canonica + fallback pt-BR (.en // .pt).
selecoes_legado as $s
| ($s | length) as $total
| ($s | map(.choice // .escolha)) as $escolhas
| (count_labels($escolhas)) as $por_modelo
| ($por_modelo["fallback-default"]) as $fb
| pct1($fb; $total) as $pct
| ($s
   | group_by(subagent_of)
   | map({
       key: (.[0] | subagent_of),
       value: count_labels(map(.choice // .escolha))
     })
   | from_entries) as $por_st
| ($s | map({
    subagent_type: subagent_of,
    etapa:         ((.stage // .etapa) // ""),
    onda:          ((.wave_id // .onda_id) // ""),
    modelo:        (.choice // .escolha),
    score:         ((.justification_score // .score_justificativa) // 0),
    fallback:      ((.choice // .escolha) == "fallback-default")
  })) as $linhas

# ===== Agregacao NOVA por-onda (FR-012/021/SC-006) =====
| selecoes_onda as $w
| ($w | length) as $wtotal
| ($w | map({
    onda:       ((.wave_id // .onda_id) // ""),
    etapa:      etapa_of_onda,
    sugerido:   sugerido_of,
    aplicado:   aplicado_of,
    origem:     origem_of
  })
  | map(. + { divergente: (.sugerido != .aplicado and .sugerido != "") })
 ) as $linhas_onda
| (count_applied($linhas_onda | map(.aplicado))) as $por_aplicado
| (count_origem($linhas_onda | map(.origem))) as $por_origem
| ($por_origem["fallback"]) as $wfb
| ($por_origem["override-operador"]) as $wovr
| ([$linhas_onda[] | select(.divergente)]) as $diverg
| ($diverg | length) as $ndiverg
| ([$diverg[]
    | .origem as $o
    | select((origem_diverg_ok | index($o)) != null)]
   | length) as $ndiverg_rot
| ($ndiverg - $ndiverg_rot) as $ndiverg_sem

| {
    total:             $total,
    por_modelo:        $por_modelo,
    fallback_count:    $fb,
    fallback_pct:      $pct,
    por_subagent_type: $por_st,
    linhas:            $linhas,
    ondas: {
      total:                   $wtotal,
      por_modelo_aplicado:     $por_aplicado,
      por_origem:              $por_origem,
      fallback_count:          $wfb,
      fallback_pct:            pct1($wfb; $wtotal),
      override_count:          $wovr,
      override_pct:            pct1($wovr; $wtotal),
      divergencias:            $ndiverg,
      divergencias_rotuladas:  $ndiverg_rot,
      divergencias_sem_rotulo: $ndiverg_sem
    },
    linhas_onda:       $linhas_onda
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
    "- fallback-default: \(.por_modelo["fallback-default"]) (\(.fallback_pct))",

    # Secao por-onda (sugerido vs aplicado) — emitida APENAS quando ha
    # DecisoesDeRoteamentoPorOnda (ondas.total > 0). Mantem o relatorio
    # legado byte-identico quando nao ha geracao nova (compat F5.1.3).
    ( if (.ondas.total // 0) > 0 then
        (
          "",
          "## Selecao de modelo por onda (sugerido vs aplicado)",
          "",
          "| onda | etapa | sugerido | aplicado | origem | divergente |",
          "|------|-------|----------|----------|--------|------------|",
          ( .linhas_onda[]
            | "| \(.onda) | \(.etapa) | \(.sugerido) | \(.aplicado) | \(.origem) | \(if .divergente then "yes" else "no" end) |"
          ),
          "",
          "**Sumario por onda**:",
          "- Total de ondas roteadas: \(.ondas.total)",
          "- aplicado haiku/sonnet/opus/manter-atual: \(.ondas.por_modelo_aplicado.haiku)/\(.ondas.por_modelo_aplicado.sonnet)/\(.ondas.por_modelo_aplicado.opus)/\(.ondas.por_modelo_aplicado["manter-atual"])",
          "- origem mapa/refino/override-operador/fallback: \(.ondas.por_origem.mapa)/\(.ondas.por_origem.refino)/\(.ondas.por_origem["override-operador"])/\(.ondas.por_origem.fallback)",
          "- fallback (manter-atual): \(.ondas.fallback_count) (\(.ondas.fallback_pct))",
          "- override do operador: \(.ondas.override_count) (\(.ondas.override_pct))",
          "- divergencias sugerido!=aplicado: \(.ondas.divergencias) (rotuladas: \(.ondas.divergencias_rotuladas), sem rotulo: \(.ondas.divergencias_sem_rotulo))"
        )
      else empty end
    )
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
