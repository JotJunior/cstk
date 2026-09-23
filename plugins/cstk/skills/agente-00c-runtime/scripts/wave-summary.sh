#!/bin/sh
# wave-summary.sh — resumo deterministico read-only de fechamento de onda,
# consumido pelos 4 commands pai (feature-00c, feature-00c-resume,
# agente-00c, agente-00c-resume) logo apos `reconcile-wave` para compor a
# mensagem final entregue ao operador. Cumpre a feature wave-close-summary.
#
# Ref: docs/specs/wave-close-summary/spec.md (FR-001..FR-014)
#      docs/specs/wave-close-summary/plan.md §Technical Context
#      docs/specs/wave-close-summary/data-model.md (Entity: WaveSummary)
#      docs/specs/wave-close-summary/contracts/wave-summary-cli.md
#      docs/specs/wave-close-summary/research.md Decisions 1-9
#      docs/specs/wave-close-summary/tasks.md FASE 1-4
#
# Subcomando:
#   wave-summary.sh emit --state-dir DIR [--wave ID] [--json]
#       — Le o estado de <DIR> (state.json, ou state.db materializado via
#         _state-read.sh sob backend SQLite), resolve a onda-alvo (default:
#         ultima entrada de .waves[]; ou a entrada cujo id casa --wave) e
#         imprime um resumo deterministico: motivo de termino, etapas
#         executadas/etapa atual/status, contagem de decisoes/bloqueios
#         pendentes, chamadas de ferramenta, duracao, consumo OTel, tarefas
#         e a proxima instrucao (saneada). Default: Markdown compacto
#         (<= 14 linhas). Com --json: objeto JSON (chaves em ingles,
#         data-model.md).
#
#   wave-summary.sh -h | --help
#       — Imprime USO em stderr e exit 2.
#
# Regra "nao medido" por campo (research.md Decision 3, FR-010, SC-002):
#   - Custo/tokens: medido somente quando `otel_usage` e objeto nao-nulo E
#     `total_tokens` e nao-nulo; senao `nao medido` (JSON: null + measured
#     false). Zero de fato medido imprime "0", nunca confundido com ausencia.
#   - Duracao: medido somente quando a onda esta fechada E
#     `wallclock_seconds` e numerico; senao `nao medido`.
#   - Chamadas de ferramenta: medido quando `tool_calls > 0`, OU quando
#     `tool_calls == 0` E `guard-hooks-status.sh tick-mode` retorna `hook`
#     (contador ativo); senao `nao medido` — 0 sem hook ativo e
#     indistinguivel de "nao contado".
#   - Tarefas: `nao aplicavel` (nunca "nao medido") quando a onda nao
#     executou `execute-task` e nao ha `.tasks[]` com esse `wave_id`.
#
# Seguranca da saida (research.md Decision 9, gate owasp-security):
#   - SEC-M1: `next_instruction` sai em inline code, sem crases no valor;
#     o pai trata o bloco como DADO de exibicao, nunca instrucao.
#   - SEC-L1: `executed_stages`, `current_stage`, `execution_status` e
#     `id`s de bloqueio pendente sao validados contra
#     `^[A-Za-z0-9._-]{1,64}$`; fora do padrao -> "(valor invalido omitido)".
#   - SEC-L2: `next_instruction` passa por `secrets-filter.sh scrub`
#     (best-effort — "passou pelo scrub != nao contem segredo"); se o
#     filtro falhar/estiver indisponivel, o campo sai como
#     "nao disponivel (filtro indisponivel)" (fail-closed so nesse campo).
#   - SEC-L3: stderr de sub-ferramentas (`jq`, `state-rw.sh`, `tick-mode`,
#     `scrub`) descartado; a unica linha de stderr em falha e a mensagem
#     propria deste helper.
#   - SEC-I2: `.execution.target_project_path` e repassado como argumento
#     citado a `guard-hooks-status.sh tick-mode` — nunca via `eval`.
#   - FR-012 (I-2 do data-model): nenhum campo `context`/`rationale`/
#     `evidence`/`options_considered`/`choice` (decisao) nem `question`/
#     `context_for_answer`/`human_answer` (bloqueio) e lido ou impresso —
#     so contagens e `id`s de bloqueio.
#
# Exit codes (contracts/wave-summary-cli.md §Exit codes e streams):
#   0 resumo composto (stdout = bloco; stderr vazio)
#   1 falha de leitura (estado ausente/corrompido, jq/sqlite3 ausente,
#     materializacao falhou) — stdout vazio, stderr exatamente 1 linha
#     "wave-summary: <motivo>"
#   2 uso incorreto — stdout vazio, uso em stderr
#   3 onda inexistente (.waves[] vazio ou --wave nao encontrada) — stdout
#     vazio, stderr exatamente 1 linha "wave-summary: <motivo>"
#
# Invariantes:
#   I-3 (determinismo): mesma entrada -> stdout byte-identico; nenhuma
#       leitura de relogio/ambiente alem do estado e do tick-mode.
#   I-4 (read-only): nenhum arquivo criado dentro do --state-dir; nenhum
#       lock adquirido; nenhum acesso a rede; hash do estado inalterado.
#
# POSIX sh + jq. Dependencias opcionais (chamadas best-effort, nunca
# obrigatorias para o exit 0): secrets-filter.sh, guard-hooks-status.sh.

set -eu

# Materializacao de estado legivel (feature state-db-runtime-parity):
# backend JSON devolve o proprio state.json; backend SQLite materializa via
# state-rw.sh read num tmp 0600 fora do state-dir.
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/_state-read.sh"
trap state_read_cleanup EXIT INT TERM

_WSM_NAME="wave-summary"

# ---------- Helpers privados ----------

_wsm_die_usage() {
  printf '%s: %s\n' "$_WSM_NAME" "$1" >&2
  _wsm_print_usage >&2
  exit 2
}

_wsm_die() {
  printf '%s: %s\n' "$_WSM_NAME" "$1" >&2
  exit "${2:-1}"
}

_wsm_print_usage() {
  cat <<'EOF'
USO:
  wave-summary.sh emit --state-dir DIR [--wave ID] [--json]
  wave-summary.sh -h | --help
EOF
}

_wsm_require_jq() {
  command -v jq >/dev/null 2>&1 \
    || _wsm_die "jq nao encontrado no PATH" 1
}

# Diretorio do proprio script (mesma receita de _wur_self_dir em
# wave-usage-report.sh) — usado para localizar scripts irmaos best-effort.
_wsm_self_dir() {
  CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd -P
}

# _wsm_tick_mode PATH -> "hook" | "manual" (sempre; best-effort, nunca
# aborta). PATH vazio ou script ausente -> "manual" (conservador: nao
# medido). SEC-I2: PATH citado como argumento, nunca via eval.
_wsm_tick_mode() {
  _twm_path=$1
  if [ -z "$_twm_path" ]; then
    printf 'manual\n'
    return 0
  fi
  _twm_self=$(_wsm_self_dir) || { printf 'manual\n'; return 0; }
  _twm_script="$_twm_self/guard-hooks-status.sh"
  if [ ! -f "$_twm_script" ]; then
    printf 'manual\n'
    return 0
  fi
  _twm_out=$(sh "$_twm_script" tick-mode --projeto-alvo-path "$_twm_path" 2>/dev/null) || _twm_out="manual"
  case "$_twm_out" in
    hook) printf 'hook\n' ;;
    *) printf 'manual\n' ;;
  esac
}

# _wsm_sanitize_ni RAW -> stdout = valor saneado (string, pode ser vazia).
# Ordem (research.md Decision 5 / tasks.md 3.1.1-3.1.4):
#   1. Remove caracteres de controle (inclusive ESC)
#   2. Colapsa quebras de linha em espaco
#   3. Aplica secrets-filter.sh scrub (fail-closed so neste campo)
#   4. Remove crases; trunca em 200 chars com sufixo "..."
_wsm_sanitize_ni() {
  _sni_raw=$1
  if [ -z "$_sni_raw" ]; then
    printf ''
    return 0
  fi
  # 2) colapsa \n e \r em espaco ANTES de remover controles (evita que a
  #    remocao de controle absorva o proprio LF/CR sem deixar separador).
  _sni_s1=$(printf '%s' "$_sni_raw" | tr '\n\r' '  ')
  # 1) remove os demais caracteres de controle C0 (inclui ESC=033 octal) e DEL.
  _sni_s2=$(printf '%s' "$_sni_s1" | LC_ALL=C tr -d '\000-\037\177')

  # 3) secrets-filter.sh scrub (best-effort; fail-closed so neste campo).
  _sni_self=$(_wsm_self_dir) || _sni_self=""
  _sni_sf="$_sni_self/secrets-filter.sh"
  if [ -n "$_sni_self" ] && [ -f "$_sni_sf" ]; then
    _sni_s3=$(printf '%s' "$_sni_s2" | sh "$_sni_sf" scrub 2>/dev/null) || _sni_s3=""
    if [ -z "$_sni_s3" ] && [ -n "$_sni_s2" ]; then
      # scrub falhou (saida vazia para entrada nao-vazia) -> fail-closed.
      printf 'nao disponivel (filtro indisponivel)'
      return 0
    fi
  else
    printf 'nao disponivel (filtro indisponivel)'
    return 0
  fi

  # 4) remove crases (octal 140) e trunca em 200 chars com sufixo "...".
  _sni_s4=$(printf '%s' "$_sni_s3" | tr -d '\140')
  _sni_len=$(printf '%s' "$_sni_s4" | wc -c | tr -d ' ')
  if [ "$_sni_len" -gt 200 ]; then
    printf '%.200s...' "$_sni_s4"
  else
    printf '%s' "$_sni_s4"
  fi
}

# ---------- Subcomando: emit ----------

# _wsm_jq_extract_program — le o documento de estado (input `.`) mais a
# variavel --arg want (id da onda pedida via --wave, ou "" para default) e
# produz o WaveSummary bruto (SEC-L1 ja aplicado; next_instruction/
# tool_calls ainda brutos — completados no shell, que precisa chamar
# secrets-filter.sh/guard-hooks-status.sh). Read-only (I-4).
_wsm_jq_extract_program() {
  cat <<'JQ'
def valid_token: test("^[A-Za-z0-9._-]{1,64}$");
def sanitize_token:
  if . == null then null
  elif ((. | type) == "string") and (. | valid_token) then .
  else "(valor invalido omitido)"
  end;

(.waves // []) as $waves
| ($waves | length) as $wcount
| (if $want != "" then ($waves | map(select(.id == $want)) | first)
   else ($waves | last)
   end) as $target
| if $wcount == 0 then
    {error: "no_waves"}
  elif $target == null then
    {error: "wave_not_found"}
  else
    ($target.termination_reason) as $tr
    | ((.human_blocks // []) | map(select(.status == "aguardando"))) as $pending
    | ($pending | length) as $pending_count
    | ($pending | map(.id)) as $pending_ids_raw
    | ((.decisions // []) | map(select(.wave_id == $target.id)) | length) as $dcount
    | ((.tasks // []) | map(select(.wave_id == $target.id))) as $wtasks
    | ($target.executed_stages // []) as $stages_raw
    | ((($stages_raw | index("execute-task")) != null) or (($wtasks | length) > 0)) as $tasks_applicable
    | ($target.wallclock_seconds // null) as $wc_raw
    | (($tr != null) and (($wc_raw | type) == "number")) as $wc_measured
    | ($target.otel_usage // null) as $otel
    | ($otel != null) as $otel_present
    | (if $otel == null then null else ($otel.total_tokens // null) end) as $tt_raw
    | (if $otel == null then null else ($otel.total_cost_usd // null) end) as $tc_raw
    | ($otel_present and ($tt_raw != null)) as $cost_measured
    | {
        error: null,
        wave_id: $target.id,
        wave_closed: ($tr != null),
        termination_reason: $tr,
        attention_required: (($pending_count > 0) or ($tr == "bloqueio_humano")),
        executed_stages: ($stages_raw | map(sanitize_token)),
        current_stage: ((.current_stage // null) | sanitize_token),
        execution_status: ((.execution.status // null) | sanitize_token),
        next_instruction_raw: (.next_instruction // null),
        decisions_count: $dcount,
        pending_blocks: {
          count: $pending_count,
          ids: ($pending_ids_raw | map(sanitize_token))
        },
        tool_calls_raw: ($target.tool_calls // null),
        wallclock_seconds: {
          value: (if $wc_measured then $wc_raw else null end),
          measured: $wc_measured
        },
        cost: {
          total_tokens: (if $cost_measured then $tt_raw else null end),
          total_cost_usd: (if $cost_measured then $tc_raw else null end),
          measured: $cost_measured
        },
        tasks: {
          applicable: $tasks_applicable,
          passed: (if $tasks_applicable then ($wtasks | map(select(.outcome=="pass")) | length) else null end),
          failed: (if $tasks_applicable then ($wtasks | map(select(.outcome=="fail")) | length) else null end)
        },
        target_project_path: (.execution.target_project_path // null)
      }
  end
JQ
}

# _wsm_render_md FINAL_JSON -> Markdown canonico (contracts/wave-summary-cli.md).
_wsm_render_md() {
  printf '%s' "$1" | jq -r '
    def label_motivo(tr):
      if tr == "etapa_concluida_avancando" then "etapa concluida, avancando"
      elif tr == "threshold_proxy_atingido" then "pausa por limite operacional (retomada agendada)"
      elif tr == "bloqueio_humano" then "bloqueio humano pendente"
      elif tr == "aborto" then "execucao abortada"
      elif tr == "concluido" then "execucao concluida"
      elif tr == null then "onda ainda aberta (nao fechada)"
      else tr
      end;

    def fmt_duration(w):
      if w.measured != true then "nao medido"
      else
        (w.value) as $s
        | ($s / 60 | floor) as $m
        | ($s - ($m * 60)) as $r
        | "\($m)m \($r)s"
      end;

    def fmt_cost(c):
      if c.measured != true then "nao medido"
      else
        (c.total_tokens | tostring) as $tok
        | (if c.total_cost_usd == null then "custo indisponivel"
           else ("US$ " + ((((c.total_cost_usd * 100) | round) / 100) | tostring))
           end) as $usd
        | "\($tok) tokens, \($usd)"
      end;

    def fmt_stages(xs):
      if (xs | length) == 0 then "(nenhuma)" else (xs | join(", ")) end;

    def fmt_tool_calls(tc):
      if tc.measured != true then "nao medido" else (tc.value | tostring) end;

    def fmt_pending(pb):
      if pb.count == 0 then "0"
      else "\(pb.count) (\(pb.ids | join(", ")))"
      end;

    def fmt_tasks(t):
      if t.applicable != true then "nao aplicavel"
      else "\(t.passed) concluidas, \(t.failed) falharam"
      end;

    def fmt_next(ni):
      if ni == null or ni == "" then "nao definida" else "`\(ni)`" end;

    (label_motivo(.termination_reason)) as $lbl
    | (if .attention_required then " [ATENCAO: requer resposta do operador]" else "" end) as $att
    | (.current_stage // "nao definida") as $cs
    | (.execution_status // "nao definida") as $es
    |
    "### Resumo da onda \(.wave_id)",
    "- Termino: \($lbl)\($att)",
    "- Etapas executadas: \(fmt_stages(.executed_stages)) | Etapa atual: \($cs) | Status: \($es)",
    "- Decisoes registradas na onda: \(.decisions_count)",
    "- Bloqueios pendentes: \(fmt_pending(.pending_blocks))",
    "- Chamadas de ferramenta: \(fmt_tool_calls(.tool_calls))",
    "- Duracao: \(fmt_duration(.wallclock_seconds))",
    "- Consumo (OTel): \(fmt_cost(.cost))",
    "- Tarefas: \(fmt_tasks(.tasks))",
    "- Proxima instrucao: \(fmt_next(.next_instruction))"
  '
}

_wsm_cmd_emit() {
  _wsm_require_jq

  _wsm_state_dir=""
  _wsm_wave=""
  _wsm_json=0

  while [ $# -gt 0 ]; do
    case "$1" in
      --state-dir)
        [ $# -ge 2 ] || _wsm_die_usage "emit: --state-dir requer valor"
        _wsm_state_dir=$2
        shift 2
        ;;
      --state-dir=*)
        _wsm_state_dir=${1#--state-dir=}
        shift
        ;;
      --wave)
        [ $# -ge 2 ] || _wsm_die_usage "emit: --wave requer valor"
        _wsm_wave=$2
        shift 2
        ;;
      --wave=*)
        _wsm_wave=${1#--wave=}
        shift
        ;;
      --json)
        _wsm_json=1
        shift
        ;;
      *)
        _wsm_die_usage "emit: argumento desconhecido: $1"
        ;;
    esac
  done

  [ -n "$_wsm_state_dir" ] \
    || _wsm_die_usage "emit: --state-dir obrigatorio"

  if [ -n "$_wsm_wave" ]; then
    printf '%s' "$_wsm_wave" | grep -Eq '^onda-[0-9]{3,}$' \
      || _wsm_die_usage "emit: --wave invalido (esperado ^onda-[0-9]{3,}\$): $_wsm_wave"
  fi

  # Materializa via _state-read.sh; falha (state-dir vazio, sqlite3
  # ausente, state.db corrompido) propaga como exit != 0 sem stdout extra.
  _wsm_state_file=$(state_read_materialize "$_wsm_state_dir" 2>/dev/null) \
    || _wsm_die "emit: falha ao materializar estado em $_wsm_state_dir" 1
  [ -f "$_wsm_state_file" ] \
    || _wsm_die "emit: state.json nao encontrado em $_wsm_state_file" 1

  # Extracao read-only (IR-1/I-4): jq sem -i, sem redirecionamento ao
  # arquivo. Estado corrompido (JSON invalido) cai aqui com exit != 0.
  _wsm_extracted=$(jq -c --arg want "$_wsm_wave" "$(_wsm_jq_extract_program)" "$_wsm_state_file" 2>/dev/null) \
    || _wsm_die "emit: estado ilegivel/corrompido em $_wsm_state_file" 1

  _wsm_error=$(printf '%s' "$_wsm_extracted" | jq -r '.error // empty')
  case "$_wsm_error" in
    no_waves)
      _wsm_die "emit: nenhuma onda registrada em $_wsm_state_dir" 3
      ;;
    wave_not_found)
      _wsm_die "emit: onda '$_wsm_wave' nao encontrada em $_wsm_state_dir" 3
      ;;
  esac

  # Campos que exigem chamada externa best-effort (nao computaveis so em jq).
  _wsm_ni_raw=$(printf '%s' "$_wsm_extracted" | jq -r '.next_instruction_raw // ""')
  _wsm_ni=$(_wsm_sanitize_ni "$_wsm_ni_raw")

  _wsm_tc_raw=$(printf '%s' "$_wsm_extracted" | jq -r '.tool_calls_raw // "null"')
  _wsm_tpp=$(printf '%s' "$_wsm_extracted" | jq -r '.target_project_path // ""')

  if [ "$_wsm_tc_raw" != "null" ] && [ "$_wsm_tc_raw" -gt 0 ] 2>/dev/null; then
    _wsm_tc_measured=true
    _wsm_tc_value=$_wsm_tc_raw
  elif [ "$_wsm_tc_raw" = "0" ]; then
    _wsm_tick=$(_wsm_tick_mode "$_wsm_tpp")
    if [ "$_wsm_tick" = "hook" ]; then
      _wsm_tc_measured=true
      _wsm_tc_value=0
    else
      _wsm_tc_measured=false
      _wsm_tc_value=null
    fi
  else
    _wsm_tc_measured=false
    _wsm_tc_value=null
  fi

  _wsm_final=$(printf '%s' "$_wsm_extracted" | jq -c \
    --arg ni "$_wsm_ni" \
    --argjson ni_empty "$([ -z "$_wsm_ni_raw" ] && printf 'true' || printf 'false')" \
    --argjson tcv "$_wsm_tc_value" \
    --argjson tcm "$_wsm_tc_measured" \
    '{
      wave_id, wave_closed, termination_reason, attention_required,
      executed_stages, current_stage, execution_status,
      next_instruction: (if $ni_empty then null else $ni end),
      decisions_count, pending_blocks,
      tool_calls: { value: $tcv, measured: $tcm },
      wallclock_seconds, cost, tasks
    }') \
    || _wsm_die "emit: falha ao compor resumo final" 1

  if [ "$_wsm_json" = 1 ]; then
    printf '%s' "$_wsm_final" | jq '.'
  else
    _wsm_render_md "$_wsm_final"
  fi
}

# ---------- Dispatch ----------

if [ $# -eq 0 ]; then
  _wsm_print_usage >&2
  exit 2
fi

case "$1" in
  -h|--help|help)
    _wsm_print_usage >&2
    exit 2
    ;;
  emit)
    shift
    _wsm_cmd_emit "$@"
    ;;
  *)
    printf '%s: subcomando desconhecido: %s\n' "$_WSM_NAME" "$1" >&2
    _wsm_print_usage >&2
    exit 2
    ;;
esac
