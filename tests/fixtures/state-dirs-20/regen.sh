#!/bin/sh
# shellcheck shell=sh
#
# regen.sh — regenera (idempotente) os 20 state.json mockados desta
# fixture, garantindo invariantes documentadas no README.md:
#
#   - exatamente 20 arquivos state.json (feat-01..feat-20/state.json)
#   - cada arquivo >= 2048 bytes e <= 10240 bytes (CHK018)
#   - >= 5 com metricas_acumuladas.model_selector populado (na pratica: 10)
#
# Uso: sh regen.sh  (do diretorio que contem este script — sem args)
#
# Implementado em POSIX puro (mesmo padrao da skill model-selector):
# nada de bash-isms, jq, ou utilitarios nao-POSIX.

set -eu

_DIR=$(cd -- "$(dirname -- "$0")" && pwd)

# -------------------------------------------------------------------
# Bloco de "decisoes" reutilizavel — texto que empurra cada state.json
# acima de 2KB. Cada decisao mock tem ~250-320 bytes; usaremos 5
# decisoes (~1.5KB) + esqueleto + metricas (~600 bytes) = ~2.1-2.5KB
# tipico. Conferido com `wc -c` no fim.
# -------------------------------------------------------------------

_emit_decisoes() {
  # _emit_decisoes <feat_id>
  # Imprime ARRAY JSON com 5 decisoes mockadas representativas.
  _f=$1
  cat <<EOF
[
    { "id": "dec-001", "agente": "agente-00c-feature-orchestrator",
      "etapa": "specify", "score": 2,
      "contexto": "Inicio da execucao para feature ${_f} apos briefing+constitution ratificados; escopo: MVP do model-selector com 15 sinais.",
      "opcoes": ["iniciar","abortar"], "escolha": "iniciar",
      "justificativa": "Briefing+constitution disponiveis; aspectos-chave alinhados.",
      "timestamp": "2026-05-20T10:00:00Z" },
    { "id": "dec-002", "agente": "agente-00c-feature-orchestrator",
      "etapa": "clarify", "score": 2,
      "contexto": "Ambiguidade em FR-002 sobre rotulos de modelo — abstratos vs concretos.",
      "opcoes": ["abstratos","concretos","ambos"], "escolha": "abstratos",
      "justificativa": "Decision 5 do research suporta rotulos abstratos por hedge a evolucao de versoes.",
      "timestamp": "2026-05-20T11:15:30Z" },
    { "id": "dec-003", "agente": "agente-00c-feature-orchestrator",
      "etapa": "plan", "score": 3,
      "contexto": "Carve-out 1.1.0 para jq opcional apenas em report.sh — confirmado por grep no codigo.",
      "opcoes": ["jq-banido","carve-out-1.1.0","jq-em-tudo"], "escolha": "carve-out-1.1.0",
      "justificativa": "grep -rn jq plugins/cstk/skills/model-selector/scripts/ retornou 1 arquivo apenas (report.sh) confirmando confinamento",
      "evidencia": "grep -rn jq scripts/: scripts/report.sh:38 if command -v jq",
      "timestamp": "2026-05-20T14:00:00Z" },
    { "id": "dec-004", "agente": "agente-00c-feature-orchestrator",
      "etapa": "create-tasks", "score": 2,
      "contexto": "Decomposicao em 6 fases canonicas com 4-5 sub-tasks por fase.",
      "opcoes": ["6-fases","8-fases","tudo-linear"], "escolha": "6-fases",
      "justificativa": "Fases acompanham pipeline SDD do agente-00c (specify->execute-task).",
      "timestamp": "2026-05-20T15:42:10Z" },
    { "id": "dec-005", "agente": "agente-00c-feature-orchestrator",
      "etapa": "execute-task", "score": 2,
      "contexto": "Tarefa 4.5 — fixture state-dirs-20 para teste de performance.",
      "opcoes": ["gerar-via-script","mockar-a-mao","fork-de-outra-fixture"], "escolha": "gerar-via-script",
      "justificativa": "Script idempotente reduz drift e facilita regeneracao apos schema changes futuros.",
      "timestamp": "2026-05-21T09:30:00Z" }
  ]
EOF
}

# -------------------------------------------------------------------
# _emit_populated <feat_id> <short_name> <h> <s> <o> <m> <aceitas> <rejeitadas>
# Emite state.json com metricas_acumuladas.model_selector populado.
# -------------------------------------------------------------------

_emit_populated() {
  _f=$1; _sn=$2; _h=$3; _s=$4; _o=$5; _m=$6; _ac=$7; _re=$8
  _total=$((_h + _s + _o + _m))
  _decs=$(_emit_decisoes "$_sn")
  cat <<EOF
{
  "schema_version": "1.0.0",
  "execucao": {
    "short_name": "$_sn",
    "projeto_alvo_path": "/Users/mock/projects/$_sn",
    "iniciada_em": "2026-05-19T08:00:00Z",
    "terminada_em": null,
    "status": "em_andamento"
  },
  "metricas_acumuladas": {
    "ondas_total": 18,
    "decisoes_total": 72,
    "tool_calls_total": 4200,
    "tempo_wallclock_total_segundos": 23150,
    "model_selector": {
      "sugestoes_total": $_total,
      "por_modelo_sugerido": {
        "haiku": $_h,
        "sonnet": $_s,
        "opus": $_o,
        "manter-atual": $_m
      },
      "por_resultado": {
        "aceitas": $_ac,
        "rejeitadas": $_re,
        "no_op_ja_no_modelo": 0
      },
      "ultima_invocacao_iso": "2026-05-21T10:00:00Z"
    }
  },
  "ondas": [],
  "decisoes": $_decs,
  "bloqueios": []
}
EOF
}

# -------------------------------------------------------------------
# _emit_populated_bag_zero <feat_id> <short_name> <total> <aceitas> <rejeitadas>
# Variante: total > 0 mas por_modelo_sugerido todo-zerado (mode=(sem dados))
# -------------------------------------------------------------------

_emit_populated_bag_zero() {
  _f=$1; _sn=$2; _total=$3; _ac=$4; _re=$5
  _decs=$(_emit_decisoes "$_sn")
  cat <<EOF
{
  "schema_version": "1.0.0",
  "execucao": {
    "short_name": "$_sn",
    "projeto_alvo_path": "/Users/mock/projects/$_sn",
    "iniciada_em": "2026-05-19T08:00:00Z",
    "terminada_em": null,
    "status": "em_andamento"
  },
  "metricas_acumuladas": {
    "ondas_total": 12,
    "decisoes_total": 50,
    "tool_calls_total": 3100,
    "tempo_wallclock_total_segundos": 18500,
    "model_selector": {
      "sugestoes_total": $_total,
      "por_modelo_sugerido": {
        "haiku": 0,
        "sonnet": 0,
        "opus": 0,
        "manter-atual": 0
      },
      "por_resultado": {
        "aceitas": $_ac,
        "rejeitadas": $_re,
        "no_op_ja_no_modelo": 0
      },
      "ultima_invocacao_iso": "2026-05-21T10:00:00Z"
    }
  },
  "ondas": [],
  "decisoes": $_decs,
  "bloqueios": []
}
EOF
}

# -------------------------------------------------------------------
# _emit_lazy <feat_id> <short_name>
# state.json SEM o sub-campo model_selector (perfil L: lazy null)
# -------------------------------------------------------------------

_emit_lazy() {
  _f=$1; _sn=$2
  _decs=$(_emit_decisoes "$_sn")
  cat <<EOF
{
  "schema_version": "1.0.0",
  "execucao": {
    "short_name": "$_sn",
    "projeto_alvo_path": "/Users/mock/projects/$_sn",
    "iniciada_em": "2026-05-19T08:00:00Z",
    "terminada_em": null,
    "status": "em_andamento"
  },
  "metricas_acumuladas": {
    "ondas_total": 14,
    "decisoes_total": 58,
    "tool_calls_total": 3600,
    "tempo_wallclock_total_segundos": 20100
  },
  "ondas": [],
  "decisoes": $_decs,
  "bloqueios": []
}
EOF
}

# -------------------------------------------------------------------
# _emit_zero <feat_id> <short_name>
# Perfil Z: model_selector presente mas sugestoes_total=0 (tudo zero)
# -------------------------------------------------------------------

_emit_zero() {
  _f=$1; _sn=$2
  _decs=$(_emit_decisoes "$_sn")
  cat <<EOF
{
  "schema_version": "1.0.0",
  "execucao": {
    "short_name": "$_sn",
    "projeto_alvo_path": "/Users/mock/projects/$_sn",
    "iniciada_em": "2026-05-19T08:00:00Z",
    "terminada_em": null,
    "status": "em_andamento"
  },
  "metricas_acumuladas": {
    "ondas_total": 8,
    "decisoes_total": 30,
    "tool_calls_total": 1800,
    "tempo_wallclock_total_segundos": 12000,
    "model_selector": {
      "sugestoes_total": 0,
      "por_modelo_sugerido": {
        "haiku": 0,
        "sonnet": 0,
        "opus": 0,
        "manter-atual": 0
      },
      "por_resultado": {
        "aceitas": 0,
        "rejeitadas": 0,
        "no_op_ja_no_modelo": 0
      },
      "ultima_invocacao_iso": null
    }
  },
  "ondas": [],
  "decisoes": $_decs,
  "bloqueios": []
}
EOF
}

# -------------------------------------------------------------------
# _write <feat_id> <body...>
# -------------------------------------------------------------------

_write_state() {
  _id=$1
  _path="$_DIR/$_id"
  mkdir -p -- "$_path"
  shift
  "$@" > "$_path/state.json"
}

# -------------------------------------------------------------------
# Pipeline principal — 20 features
# -------------------------------------------------------------------

# Perfis P1..P10 (populados)
_write_state feat-01 _emit_populated feat-01 alpha-feat   3 1 1 0 4 1
_write_state feat-02 _emit_populated feat-02 bravo-feat   1 4 1 0 5 1
_write_state feat-03 _emit_populated feat-03 charlie-feat 0 1 3 0 3 1
_write_state feat-04 _emit_populated feat-04 delta-feat   0 1 0 2 2 1
_write_state feat-05 _emit_populated feat-05 echo-feat    8 2 1 1 11 1
_write_state feat-06 _emit_populated feat-06 foxtrot-feat 2 6 1 1 8 2
_write_state feat-07 _emit_populated feat-07 golf-feat    3 3 0 0 5 1   # tie-break -> haiku
_write_state feat-08 _emit_populated_bag_zero feat-08 hotel-feat 5 3 2  # bag zero, total>0
_write_state feat-09 _emit_populated feat-09 india-feat   4 2 0 0 6 0
_write_state feat-10 _emit_populated feat-10 juliett-feat 0 2 3 0 4 1

# Perfis L1..L5 (lazy — sem model_selector)
_write_state feat-11 _emit_lazy feat-11 kilo-feat
_write_state feat-12 _emit_lazy feat-12 lima-feat
_write_state feat-13 _emit_lazy feat-13 mike-feat
_write_state feat-14 _emit_lazy feat-14 november-feat
_write_state feat-15 _emit_lazy feat-15 oscar-feat

# Perfis Z1..Z5 (zero sugestoes)
_write_state feat-16 _emit_zero feat-16 papa-feat
_write_state feat-17 _emit_zero feat-17 quebec-feat
_write_state feat-18 _emit_zero feat-18 romeo-feat
_write_state feat-19 _emit_zero feat-19 sierra-feat
_write_state feat-20 _emit_zero feat-20 tango-feat

# -------------------------------------------------------------------
# Validacao das invariantes
# -------------------------------------------------------------------

_total_count=0
_violations=0
for _i in 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16 17 18 19 20; do
  _f="$_DIR/feat-$_i/state.json"
  if [ ! -f "$_f" ]; then
    printf 'regen: ERRO arquivo ausente: %s\n' "$_f" >&2
    _violations=$((_violations + 1))
    continue
  fi
  _sz=$(wc -c < "$_f" | tr -d ' ')
  if [ "$_sz" -lt 2048 ] || [ "$_sz" -gt 10240 ]; then
    printf 'regen: ERRO tamanho fora de faixa em feat-%s: %s bytes\n' \
      "$_i" "$_sz" >&2
    _violations=$((_violations + 1))
  fi
  _total_count=$((_total_count + 1))
done

if [ "$_total_count" != "20" ]; then
  printf 'regen: ERRO esperava 20 state.json, obtive: %s\n' \
    "$_total_count" >&2
  exit 1
fi
if [ "$_violations" != "0" ]; then
  printf 'regen: ERRO %s violacoes de invariante detectadas\n' \
    "$_violations" >&2
  exit 1
fi

printf 'regen: OK — 20 state.json gerados (todos entre 2KB e 10KB)\n'
