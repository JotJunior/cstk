#!/bin/sh
# report.sh — gera relatorio do agente-00C com 6 secoes (FR-011, SC-001).
#
# Ref: docs/specs/agente-00c/contracts/report-format.md
#      docs/specs/agente-00c/spec.md FR-011, SC-001
#      docs/specs/agente-00c/tasks.md FASE 8.1 + 8.2
#      docs/specs/wave-token-metrics/contracts/wave-usage-report.md §6
#        (secoes 1/2 estendidas com consumo de subagente — FASE 4.2)
#
# Secoes 1 e 2 consomem `wave-usage-report.sh aggregate --json` (script
# irmao no mesmo diretorio) para exibir spawns/tokens observados por
# execucao e por onda. Best-effort: helper ausente/falhando NUNCA aborta
# o relatorio — degrada para "nao coletado nesta execucao"/"indisponivel"
# (ver _rp_wave_usage_json), nunca fabricando `0` (Principio VI).
#
# Subcomandos:
#   report.sh generate --state-dir DIR [--final] [--paragrafo-resumo TEXT]
#                      [--licoes-aprendidas TEXT]
#       — Renderiza relatorio em stdout. 6 secoes obrigatorias (cabecalho +
#         secoes 1..6 + apendice A). Secao 6 (Licoes Aprendidas) so e
#         preenchida se --final + --licoes-aprendidas; senao placeholder.
#         Secao 1 paragrafo so se --paragrafo-resumo passado; senao
#         placeholder neutro.
#       — IMPORTANTE: NAO aplica secrets-filter — caller deve fazer
#         externamente: `report.sh generate ... | secrets-filter.sh scrub
#         --env-file <PAP>/.env > <PAP>/.claude/agente-00c-report.md`
#
#   report.sh emit --flavor feature-00c|agente-00c --state-dir DIR
#                  [--short-name NAME] [--parcial|--final]
#                  [--paragrafo-resumo TEXT] [--licoes-aprendidas TEXT]
#                  [--env-file FILE] [--ignore-file FILE]
#       — Como generate, mas resolve o caminho de saida pelo flavor
#         (feature-00c -> <state-dir>/feature-00c-report.md; agente-00c ->
#         <state-dir>/../agente-00c-report.md), aplica secrets-filter
#         INTERNAMENTE e SEMPRE, e grava o arquivo (imprime o caminho em
#         stdout). secrets-filter ausente = erro (nunca grava nao-filtrado).
#         --parcial (default) = sem licoes; --final = secao 6 preenchida.
#
#   report.sh validate --report-file FILE
#       — Verifica presenca das 6 secoes obrigatorias via regex de headings.
#       — Exit 0 se completo, 1 se faltando alguma secao + nome em stderr.
#
# Exit codes:
#   0 sucesso
#   1 erro generico OU validacao falhou
#   2 uso incorreto
#   7 estado ausente (nem state.json nem state.db legivel no state-dir) em
#     generate|emit — contratual FR-008 (state-db-runtime-parity; alinha
#     "falha na geracao do relatorio: exit 7 + estado preservado" do
#     contrato cli-invocation.md do feature-00c). Falha de LEITURA de um
#     state.db presente (corrompido/sqlite3 ausente) segue propagando o
#     exit do `state-rw.sh read` (FR-012) — classe "falha generica".
#
# POSIX sh + jq.

set -eu

_RP_NAME="report"

_rp_die_usage() { printf '%s: %s\n' "$_RP_NAME" "$1" >&2; exit 2; }
_rp_die()       { printf '%s: %s\n' "$_RP_NAME" "$1" >&2; exit "${2:-1}"; }

_rp_require_jq() {
  command -v jq >/dev/null 2>&1 \
    || _rp_die "jq nao encontrado no PATH" 1
}

_rp_iso_now() { date -u +%FT%TZ; }

# Materializacao de estado backend-agnostica via helper comum
# _state-read.sh (state-db-runtime-parity FASE 2 lote 2.6 — substitui a
# copia local do padrao a06e747/v6.2.2, eliminando o drift entre as 2
# variantes). JSON: path direto do state.json; SQLite (state.db): tmp
# 0600 fora do state-dir. Falha de materializacao (sqlite3 ausente,
# state.db corrompido) agora PROPAGA via set -e (FR-012) em vez do
# antigo fallback mudo para "estado ausente".
# shellcheck source=./_state-read.sh
. "$(dirname -- "$0")/_state-read.sh"
trap state_read_cleanup EXIT INT TERM

# _rp_wave_usage_json STATE_DIR — agregado read-only de consumo de
# tokens/tool-uses/duracao de subagente (FASE 4.2 de wave-token-metrics,
# contracts/wave-usage-report.md §6). Delega ao helper irmao
# wave-usage-report.sh (le .waves[].agent_usage; nunca reimplementa a
# agregacao aqui). Best-effort: helper ausente/nao-executavel ou
# `aggregate` falhando NUNCA aborta o relatorio — produz um JSON neutro
# com metric_collected=false e campos numericos `null` (nunca `0`
# fabricado — Principio VI/FR-009). Este fallback e distinto do "0 spawns
# reais" que o proprio wave-usage-report.sh ja retorna corretamente
# (spawns_total=0 e uma contagem literal) quando roda com sucesso mas nao
# encontra nenhum agent_usage no state.json.
_rp_wave_usage_json() {
  _wu_script="$(dirname -- "$0")/wave-usage-report.sh"
  if [ -x "$_wu_script" ]; then
    if _wu_out=$("$_wu_script" aggregate --state-dir "$1" --json 2>/dev/null); then
      printf '%s' "$_wu_out"
      return 0
    fi
  fi
  printf '%s' '{"metric_collected":false,"spawns_total":null,"spawns_with_usage":null,"spawns_unavailable":null,"total_tokens":null,"coverage_pct":null,"por_onda":[]}'
}

# _rp_render_header STATE_FILE GERADO_EM
# READER de state.json: paths EN + fallback (.en // .pt) (schema-en-migration).
_rp_render_header() {
  jq -r --arg now "$2" '
    (.execution // .execucao) as $exec
    | "# Relatorio do Agente-00C — \($exec.id)",
    "",
    "**Gerado em**: \($now)",
    "**Status no momento**: \($exec.status)",
    "**Versao do schema**: \(.schema_version)",
    "",
    "---",
    ""
  ' "$1"
}

# _rp_render_secao_1 STATE_FILE PARAGRAFO WAVE_USAGE_JSON
_rp_render_secao_1() {
  _para=$2
  [ -n "$_para" ] || _para="(Paragrafo de resumo nao fornecido — orquestrador deve gerar via --paragrafo-resumo na invocacao final.)"
  jq -r --arg para "$_para" --argjson wu "$3" '
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
    (.execution // .execucao) as $exec
    | (.accumulated_metrics // .metricas_acumuladas) as $met
    | "## 1. Resumo Executivo",
    "",
    "| Campo | Valor |",
    "|-------|-------|",
    "| ID Execucao | \($exec.id) |",
    "| Projeto-Alvo | \($exec.target_project_path // $exec.projeto_alvo_path) |",
    "| Descricao | \($exec.target_project_description // $exec.projeto_alvo_descricao) |",
    "| Stack final | \(($exec.suggested_stack // $exec.stack_sugerida) // (if (($exec.status // "") == "abortada") then "nao aplicavel — execucao abortada antes de definir" else "nao aplicavel (herdada do projeto / nao definida)" end)) |",
    "| Status | \($exec.status) |",
    "| Motivo termino | \(($exec.termination_reason // $exec.motivo_termino) // "(em andamento)") |",
    "| Iniciada em | \($exec.started_at // $exec.iniciada_em) |",
    "| Terminada em | \(($exec.finished_at // $exec.terminada_em) // "ainda em andamento") |",
    "| Ondas executadas | \(($met.waves_total // $met.ondas_total) // 0) |",
    "| Tool calls totais | \($met.tool_calls_total // 0) |",
    "| Decisoes registradas | \(($met.decisions_total // $met.decisoes_total) // (((.decisions // .decisoes) // []) | length)) |",
    "| Bloqueios humanos | \(($met.human_blocks_total // $met.bloqueios_humanos_total) // (((.human_blocks // .bloqueios_humanos) // []) | length)) |",
    "| Sugestoes para skills globais | \(($met.global_skill_suggestions_total // $met.sugestoes_skills_globais_total) // (((.suggestions // .sugestoes) // []) | length)) |",
    "| Issues abertas no toolkit | \(($met.toolkit_issues_opened // $met.issues_toolkit_abertas) // 0) |",
    "| Profundidade max de subagentes | \(($met.max_depth_reached // $met.profundidade_max_atingida) // 1) |",
    "| Spawns de subagente | \(if ($wu.metric_collected // false) then "\($wu.spawns_total) (\($wu.spawns_with_usage) com uso; \($wu.spawns_unavailable) indisponiveis)" else "nao coletado nesta execucao" end) |",
    "| Tokens totais (observados) | \(if ($wu.metric_collected // false) then fmt_tokens($wu.total_tokens) else "nao coletado nesta execucao" end) |",
    "| Cobertura da metrica | \(if ($wu.metric_collected // false) then (($wu.coverage_pct) // "n/a (sem spawns indisponiveis)") else "nao coletado nesta execucao" end) |",
    "",
    $para,
    ""
  ' "$1"
}

# _rp_render_secao_2 STATE_FILE WAVE_USAGE_JSON
_rp_render_secao_2() {
  jq -r --argjson wu "$2" '
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
    (($wu.por_onda // []) | map({(.onda): .}) | add // {}) as $wu_by_onda
    | ((.waves // .ondas) // []) as $waves
    | "## 2. Linha do Tempo",
    "",
    "| Onda | Inicio | Fim | Etapas | Tool calls | Wallclock | Spawns | Tokens | Termino |",
    "|------|--------|-----|--------|------------|-----------|--------|--------|---------|",
    (
      if $waves | length == 0 then
        "| - | - | - | (nenhuma onda completa ainda) | - | - | - | - | - |"
      else
        ($waves[] |
          . as $w
          | ($wu_by_onda[$w.id] // null) as $u
          | "| \($w.id) | \($w.started_at // $w.inicio) | \(($w.finished_at // $w.fim) // "-") | \((($w.executed_stages // $w.etapas_executadas) // []) | join(", ")) | \($w.tool_calls // 0) | \($w.wallclock_seconds // 0)s | \(if $u == null then "indisponivel" else "\($u.spawns_total) (\($u.spawns_with_usage) c/uso)" end) | \(if $u == null then "indisponivel" else fmt_tokens($u.total_tokens) end) | \((($w.termination_reason // $w.motivo_termino)) // "(em andamento)") |"
        )
      end
    ),
    ""
  ' "$1"
}

# _rp_render_secao_3 STATE_FILE
_rp_render_secao_3() {
  jq -r '
    ((.decisions // .decisoes) // []) as $decs
    | "## 3. Decisoes",
      "",
      "Total: \($decs | length) decisoes registradas.",
      "",
      "### 3.1 Por agente",
      "",
      "| Agente | Quantidade |",
      "|--------|------------|"
      ,
      (
        if ($decs | length) == 0 then
          "| (nenhuma) | 0 |"
        else
          ($decs | map(.agent // .agente) | group_by(.) | map({agente: .[0], n: length}) |
            .[] | "| \(.agente) | \(.n) |")
        end
      ),
      "",
      "### 3.2 Lista detalhada",
      "",
      (
        if ($decs | length) == 0 then
          "(Nenhuma decisao registrada nesta execucao.)"
        else
          ($decs[] |
            "#### \(.id) — \(.stage // .etapa) — \(.agent // .agente) — \(.timestamp)",
            "",
            "**Contexto**: \(.context // .contexto)",
            "",
            "**Opcoes consideradas**: \(((.options_considered // .opcoes_consideradas) // []) | join(" / "))",
            "",
            "**Escolha**: \(.choice // .escolha)",
            "",
            "**Justificativa**: \(.rationale // .justificativa)",
            "",
            "**Score**: \((.justification_score // .score_justificativa) as $sc | if $sc == null then "(n/a — decisao do orquestrador)" else ($sc | tostring) end)",
            "",
            "**Referencias**: \(((.references // .referencias) // []) | if length == 0 then "(nenhuma)" else (map(if type == "string" then . else (to_entries | map("\(.key)=\(.value)") | join(" ")) end) | join(", ")) end)",
            "",
            "**Artefato originador**: \((.originating_artifact // .artefato_originador) // "(nenhum)")",
            ""
          )
        end
      ),
      ""
  ' "$1"
}

# _rp_render_secao_4 STATE_FILE
_rp_render_secao_4() {
  jq -r '
    ((.human_blocks // .bloqueios_humanos) // []) as $blocks
    | "## 4. Bloqueios Humanos",
      "",
      "Total: \($blocks | length) bloqueios.",
      "",
      "### 4.1 Pendentes (aguardando resposta)",
      "",
      (
        ($blocks | map(select(.status == "aguardando"))) as $pending
        | if ($pending | length) == 0 then
            "(Nenhum bloqueio pendente neste momento.)"
          else
            ($pending[] |
              "#### \(.id) — disparado em \(.triggered_at // .disparado_em)",
              "",
              "**Pergunta**: \(.question // .pergunta)",
              "",
              "**Contexto para resposta**: \(.context_for_answer // .contexto_para_resposta)",
              "",
              "**Opcoes recomendadas**:",
              (((.recommended_options // .opcoes_recomendadas) // [])
               | if length == 0 then "- (sem opcoes especificas)"
                 else (map("- " + .) | join("\n")) end),
              "",
              "**Status**: \(.status)",
              ""
            )
          end
      ),
      "",
      "### 4.2 Respondidos",
      "",
      (
        ($blocks | map(select(.status == "respondido"))) as $resp
        | if ($resp | length) == 0 then
            "(Nenhum bloqueio respondido nesta execucao.)"
          else
            ($resp[] |
              "#### \(.id) — disparado em \(.triggered_at // .disparado_em)",
              "",
              "**Pergunta**: \(.question // .pergunta)",
              "",
              "**Resposta humana**: \((.human_answer // .resposta_humana) // "?")",
              "",
              "**Respondido em**: \((.answered_at // .respondido_em) // "?")",
              ""
            )
          end
      ),
      "",
      "### 4.3 Sem bloqueios",
      "",
      (if ($blocks | length) == 0 then
         "Nenhum bloqueio humano nesta execucao."
       else
         "(Esta secao se aplica apenas a execucoes sem bloqueios — \($blocks | length) registrados acima.)"
       end),
      ""
  ' "$1"
}

# _rp_render_secao_5 STATE_FILE
_rp_render_secao_5() {
  jq -r '
    ((.suggestions // .sugestoes) // []) as $sugs
    | "## 5. Sugestoes para Skills Globais",
      "",
      "Total: \($sugs | length) sugestoes.",
      "",
      "### 5.1 Severidade impeditiva (viraram issues)",
      "",
      (
        ($sugs | map(select((.severity // .severidade) == "impeditiva"))) as $imp
        | if ($imp | length) == 0 then
            "(Nenhuma sugestao impeditiva nesta execucao.)"
          else
            ($imp[] |
              "#### \(.id) — skill `\(.affected_skill // .skill_afetada)` — issue \((.issue_opened // .issue_aberta) // "(nao aberta)")",
              "",
              "**Diagnostico**: \(.diagnosis // .diagnostico)",
              "",
              "**Proposta**: \(.proposal // .proposta)",
              ""
            )
          end
      ),
      "",
      "### 5.2 Severidade aviso",
      "",
      (
        ($sugs | map(select((.severity // .severidade) == "aviso"))) as $av
        | if ($av | length) == 0 then
            "(Nenhuma sugestao com severidade aviso.)"
          else
            ($av[] |
              "#### \(.id) — skill `\(.affected_skill // .skill_afetada)`",
              "",
              "**Diagnostico**: \(.diagnosis // .diagnostico)",
              "",
              "**Proposta**: \(.proposal // .proposta)",
              ""
            )
          end
      ),
      "",
      "### 5.3 Severidade informativa",
      "",
      (
        ($sugs | map(select((.severity // .severidade) == "informativa"))) as $inf
        | if ($inf | length) == 0 then
            "(Nenhuma sugestao informativa.)"
          else
            ($inf[] |
              "#### \(.id) — skill `\(.affected_skill // .skill_afetada)`",
              "",
              "**Diagnostico**: \(.diagnosis // .diagnostico)",
              "",
              "**Proposta**: \(.proposal // .proposta)",
              ""
            )
          end
      ),
      "",
      "### 5.4 Sem sugestoes",
      "",
      (if ($sugs | length) == 0 then
         "Nenhuma sugestao para skills globais nesta execucao."
       else
         "(Esta secao se aplica apenas a execucoes sem sugestoes — \($sugs | length) registradas acima.)"
       end),
      ""
  ' "$1"
}

# _rp_render_secao_6 LICOES IS_FINAL
_rp_render_secao_6() {
  printf '## 6. Licoes Aprendidas\n\n'
  if [ "$2" = 1 ] && [ -n "$1" ]; then
    printf '%s\n\n' "$1"
  elif [ "$2" = 1 ]; then
    printf '(Relatorio final invocado sem --licoes-aprendidas — operador deve preencher esta secao manualmente OU re-invocar com flag.)\n\n'
  else
    printf '(Sera preenchido no relatorio final.)\n\n'
  fi
}

# _rp_render_apendice STATE_FILE
_rp_render_apendice() {
  jq -r '
    ((.execution // .execucao).target_project_path
     // (.execution // .execucao).projeto_alvo_path) as $pap
    | "---",
    "",
    "**Apendice A — Caminhos relevantes**",
    "",
    "- Estado: `\($pap)/.claude/agente-00c-state/state.json`",
    "- Backups de estado: `\($pap)/.claude/agente-00c-state/state-history/`",
    "- Sugestoes detalhadas: `\($pap)/.claude/agente-00c-suggestions.md`",
    "- Whitelist: `\($pap)/.claude/agente-00c-whitelist`",
    "- Artefatos da pipeline: `\($pap)/docs/specs/<feature>/`",
    ""
  ' "$1"
}

_rp_cmd_generate() {
  _sd=""
  _final=0
  _para=""
  _licoes=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir)          _sd=$2;     shift 2 ;;
      --final)              _final=1;   shift ;;
      --paragrafo-resumo)   _para=$2;   shift 2 ;;
      --licoes-aprendidas)  _licoes=$2; shift 2 ;;
      *) _rp_die_usage "generate: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sd" ] || _rp_die_usage "generate: --state-dir obrigatorio"
  _rp_require_jq
  _sf=$(state_read_materialize "$_sd")
  [ -f "$_sf" ] || _rp_die "generate: estado ausente (state.json/state.db) em $_sd" 7

  _now=$(_rp_iso_now)
  _wu_json=$(_rp_wave_usage_json "$_sd")
  _rp_render_header "$_sf" "$_now"
  _rp_render_secao_1 "$_sf" "$_para" "$_wu_json"
  _rp_render_secao_2 "$_sf" "$_wu_json"
  _rp_render_secao_3 "$_sf"
  _rp_render_secao_4 "$_sf"
  _rp_render_secao_5 "$_sf"
  _rp_render_secao_6 "$_licoes" "$_final"
  _rp_render_apendice "$_sf"
}

_rp_cmd_validate() {
  _rf=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --report-file) _rf=$2; shift 2 ;;
      *) _rp_die_usage "validate: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_rf" ] || _rp_die_usage "validate: --report-file obrigatorio"
  [ -f "$_rf" ] || _rp_die "validate: report-file nao existe: $_rf" 1

  _missing=""
  for _h in '## 1. Resumo Executivo' \
            '## 2. Linha do Tempo' \
            '## 3. Decisoes' \
            '## 4. Bloqueios Humanos' \
            '## 5. Sugestoes para Skills Globais' \
            '## 6. Licoes Aprendidas'; do
    if ! grep -qF -- "$_h" "$_rf"; then
      _missing="$_missing
  - $_h"
    fi
  done

  if [ -z "$_missing" ]; then
    return 0
  fi
  printf '%s: relatorio incompleto — secoes faltando:%s\n' \
    "$_RP_NAME" "$_missing" >&2
  exit 1
}

# _rp_emit_do_scrub RAW OUT ENV IGNORE — aplica secrets-filter (usa $_sf_script).
# Variantes de flags sem concatenacao de strings (paths podem ter espaco).
_rp_emit_do_scrub() {
  if [ -n "$3" ] && [ -n "$4" ]; then
    "$_sf_script" scrub --env-file "$3" --ignore-file "$4" < "$1" > "$2"
  elif [ -n "$3" ]; then
    "$_sf_script" scrub --env-file "$3" < "$1" > "$2"
  elif [ -n "$4" ]; then
    "$_sf_script" scrub --ignore-file "$4" < "$1" > "$2"
  else
    "$_sf_script" scrub < "$1" > "$2"
  fi
}

# _rp_cmd_emit — gera + filtra (secrets) + grava o relatorio, resolvendo o
# caminho pelo flavor (FR-018). Diferente de `generate` (que escreve em stdout
# para o caller filtrar), `emit` aplica secrets-filter INTERNAMENTE e SEMPRE e
# grava o arquivo. Centraliza o concern de relatorio do feature-00c: resume/
# abort/orquestrador nao repetem o pipeline nem podem esquecer o scrub — o
# relatorio e persistido (e tipicamente commitado), entao um vazamento seria
# permanente. Por isso secrets-filter ausente = erro, nunca passthrough.
_rp_cmd_emit() {
  _flavor=""
  _sd=""
  _final=0
  _para=""
  _licoes=""
  _env=""
  _ignore=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --flavor)             _flavor=$2; shift 2 ;;
      --short-name)         shift 2 ;;   # aceito p/ compat de doc; titulo vem do state.json
      --state-dir)          _sd=$2;     shift 2 ;;
      --final)              _final=1;   shift ;;
      --parcial)            _final=0;   shift ;;
      --paragrafo-resumo)   _para=$2;   shift 2 ;;
      --licoes-aprendidas)  _licoes=$2; shift 2 ;;
      --env-file)           _env=$2;    shift 2 ;;
      --ignore-file)        _ignore=$2; shift 2 ;;
      *) _rp_die_usage "emit: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_flavor" ] || _rp_die_usage "emit: --flavor obrigatorio (feature-00c|agente-00c)"
  [ -n "$_sd" ]     || _rp_die_usage "emit: --state-dir obrigatorio"

  case "$_flavor" in
    feature-00c) _out="$_sd/feature-00c-report.md" ;;
    agente-00c)  _out="$_sd/../agente-00c-report.md" ;;
    *) _rp_die_usage "emit: --flavor invalido: $_flavor (esperado feature-00c|agente-00c)" ;;
  esac

  _rp_require_jq
  _sf=$(state_read_materialize "$_sd")
  [ -f "$_sf" ] || _rp_die "emit: estado ausente (state.json/state.db) em $_sd" 7

  # secrets-filter OBRIGATORIO (ver doc da funcao): ausencia/inacessibilidade
  # = erro, NUNCA grava relatorio nao-filtrado.
  _sf_script="$(dirname -- "$0")/secrets-filter.sh"
  [ -x "$_sf_script" ] \
    || _rp_die "emit: secrets-filter.sh ausente/nao-executavel em $(dirname -- "$0") — abortando para nao gravar relatorio nao-filtrado" 1

  _raw=$(mktemp) || _rp_die "emit: mktemp falhou" 1
  _scrubbed=$(mktemp) || { rm -f -- "$_raw"; _rp_die "emit: mktemp falhou" 1; }

  _now=$(_rp_iso_now)
  _wu_json=$(_rp_wave_usage_json "$_sd")
  {
    _rp_render_header "$_sf" "$_now"
    _rp_render_secao_1 "$_sf" "$_para" "$_wu_json"
    _rp_render_secao_2 "$_sf" "$_wu_json"
    _rp_render_secao_3 "$_sf"
    _rp_render_secao_4 "$_sf"
    _rp_render_secao_5 "$_sf"
    _rp_render_secao_6 "$_licoes" "$_final"
    _rp_render_apendice "$_sf"
  } > "$_raw"

  if ! _rp_emit_do_scrub "$_raw" "$_scrubbed" "$_env" "$_ignore"; then
    rm -f -- "$_raw" "$_scrubbed"
    _rp_die "emit: secrets-filter scrub falhou — relatorio NAO gravado" 1
  fi
  rm -f -- "$_raw"

  mv -- "$_scrubbed" "$_out" \
    || { rm -f -- "$_scrubbed"; _rp_die "emit: falha ao gravar $_out" 1; }
  printf '%s\n' "$_out"
}

# ---------- Dispatch ----------

if [ "$#" -lt 1 ]; then
  cat >&2 <<'HELP'
report.sh — gera relatorio do agente-00C com 6 secoes (FR-011, SC-001).

USO:
  report.sh generate --state-dir DIR [--final] [--paragrafo-resumo TEXT]
                                      [--licoes-aprendidas TEXT]
  report.sh emit --flavor feature-00c|agente-00c --state-dir DIR
                 [--short-name NAME] [--parcial|--final]
                 [--paragrafo-resumo TEXT] [--licoes-aprendidas TEXT]
                 [--env-file FILE] [--ignore-file FILE]
  report.sh validate --report-file FILE

generate: escreve o relatorio em stdout — o CALLER aplica secrets-filter:
  report.sh generate --state-dir <SD> [...] \
    | secrets-filter.sh scrub --env-file <PAP>/.env \
    > <PAP>/.claude/agente-00c-report.md

emit: resolve o caminho pelo flavor, aplica secrets-filter INTERNAMENTE
(sempre) e grava o arquivo; imprime o caminho gravado em stdout.

EXIT (validate):
  0 todas as 6 secoes presentes
  1 alguma secao faltando (lista em stderr)
HELP
  exit 2
fi

_RP_SUBCMD=$1
shift

case "$_RP_SUBCMD" in
  generate)        _rp_cmd_generate "$@" ;;
  emit)            _rp_cmd_emit "$@" ;;
  validate)        _rp_cmd_validate "$@" ;;
  -h|--help|help)  exit 0 ;;
  *) _rp_die_usage "subcomando desconhecido: $_RP_SUBCMD" ;;
esac
