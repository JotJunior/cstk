#!/bin/sh
# state-ondas.sh — gerencia ciclo de vida de Ondas (FASE 3.4).
#
# Ref: docs/specs/agente-00c/data-model.md §Onda
#      docs/specs/agente-00c/spec.md FR-009
#      docs/specs/agente-00c/research.md Decision 1
#      docs/specs/agente-00c/tasks.md FASE 3.4
#
# Subcomandos:
#   state-ondas.sh start --state-dir DIR
#       — Append nova Onda em .waves com:
#           id = onda-NNN sequencial
#           started_at = ISO now
#           executed_stages = []
#           tool_calls = 0
#         Reseta .budgets.tool_calls_current_wave = 0 e
#         .budgets.current_wave_start = started_at.
#         Stdout: id da nova onda.
#
#   state-ondas.sh end --state-dir DIR --motivo-termino MOTIVO
#                      [--proxima-agendada-para ISO]
#                      [--add-etapa STAGE]
#       — Atualiza ultima Onda (.waves[-1]) com finished_at/wallclock_seconds/
#         tool_calls/termination_reason/next_wave_scheduled_for. Atualiza
#         accumulated_metrics (waves_total += 1, tool_calls_total +=
#         tool_calls da onda, wallclock_total_seconds += wallclock).
#         tool_calls da onda = .budgets.tool_calls_current_wave (ticks
#         manuais) + linhas do sidecar tool-call-ticks.log (ticks do hook
#         PostToolUse) — sidecar resetado apos o fechamento.
#         --add-etapa pode ser passada N vezes para append em executed_stages.
#
#   state-ondas.sh tool-call-tick --state-dir DIR
#       — Incrementa .budgets.tool_calls_current_wave (1 unidade).
#         Stdout: novo total da onda (SO o campo do state; nao inclui o
#         sidecar do hook). Caminho MANUAL/legado: o mecanismo primario de
#         contagem e o hook posttooluse-tool-call-tick.sh (sidecar
#         append-only) — nao use os dois em paralelo na mesma execucao ou
#         cada call contara em dobro.
#
#   state-ondas.sh current-id --state-dir DIR
#       — Imprime .waves[-1].id (ou "init" se nao ha onda).
#
#   state-ondas.sh record-skill --state-dir DIR --skill NAME
#                               [--decisao-id DEC-NNN] [--kind skill|gate]
#       — Registra invocacao da skill na onda corrente. Append em
#         .waves[-1].skills_invoked = [..., { skill, timestamp, decision_id,
#         kind }]. --kind (default: skill) separa SKILLS reais (invocadas
#         via tool Skill) de GATES deterministicos de script
#         (validate-tasks-template.sh etc.); entradas kind=gate sao
#         auditaveis no state.json mas NAO entram na metrica de skills da
#         knowledge.db (a ingestao filtra) — antes, gates e ate comandos de
#         build/lint poluiam a tabela `skills` como se fossem skills.
#         Permite review-task auditar "etapa X foi marcada completa mas a
#         skill Y nunca foi invocada via tool Skill" — defesa contra o
#         padrao da execucao-fonte onde orquestrador gerou artefatos
#         in-process sem chamar a skill canonica (dec-014: tasks.md sem
#         create-tasks invocada).
#         Idempotente para a mesma combinacao (skill + decisao_id na mesma
#         onda) — re-registro nao duplica entrada.
#         Stdout: numero total de skills invocadas nesta onda.
#
#   state-ondas.sh record-task --state-dir DIR --task-id ID --outcome pass|fail
#                              [--titulo T] [--wave-id ID] [--testes-rodados N]
#                              [--testes-passados N] [--lint-ok true|false]
#                              [--arquivos JSON] [--origem TAG] [--if-absent]
#       — Upsert idempotente de UMA entrada em .tasks[] (chave = task_id).
#         Caminho de escrita auditado (substitui o jq hand-rolled que vivia
#         na prosa dos orquestradores). Default sobrescreve; --if-absent so
#         insere se ausente. Stdout: total de entradas em .tasks[].
#
#   state-ondas.sh reconcile-tasks --state-dir DIR --tasks-md PATH
#                                  [--wave-id ID] [--dry-run]
#       — Rede de seguranca deterministica: le tasks.md e back-filla em
#         .tasks[] (via record-task --if-absent) toda task CONCLUIDA (heading
#         `### N.M` com todas as subtarefas-checkbox `[x]`) que esteja
#         faltando. NAO grava tasks pendentes/bloqueadas (sem outcome final).
#         Idempotente. Stdout: nº back-filled; --dry-run lista os faltantes.
#
#   state-ondas.sh wave-status --state-dir DIR
#       — Imprime o estado da ULTIMA onda (.waves[-1]):
#           "open"   se termination_reason == null (onda nao fechada)
#           "closed" se termination_reason != null
#           "none"   se nao ha onda
#         Primitiva idempotente que distingue "orquestrador fechou a onda"
#         de "orquestrador parou cedo e deixou a onda aberta" — sem ela, a
#         rede de seguranca do command pai (reconcile-wave) nao pode evitar
#         double-count em `end`.
#
#   state-ondas.sh reconcile-wave --state-dir DIR
#                                 [--phase PHASE] [--tasks-md PATH]
#                                 [--terminal-phase PHASE] [--dry-run]
#       — REDE DE SEGURANCA do command pai contra o bug recorrente "o
#         orquestrador retorna SEM fechar a onda nem emitir Schedule intent"
#         (ver "Contrato de conclusao de turno" no orchestrator .md). Faz a
#         recuperacao deterministica de UMA onda aberta, IDEMPOTENTE:
#           - se wave-status != "open" -> NO-OP (stdout "noop (<status>)",
#             exit 0). Esta guarda e o que torna seguro o pai chamar
#             reconcile-wave A CADA onda sem double-count em accumulated_metrics.
#           - se "open":
#               1. resolve a fase (--phase ou .current_stage)
#               2. fase == execute-task + --tasks-md -> reconcile-tasks
#                  (back-fill .tasks[] best-effort)
#               3. record-skill --skill <fase> (idempotente)
#               4. deriva proxima fase via pipeline.sh next-stage (ou
#                  --terminal-phase: feature-00c=review-task,
#                  agente-00c=review-features — sem isso pipeline.sh
#                  avancaria review-task->review-features erroneamente):
#                  - ha proxima  -> end(etapa_concluida_avancando) +
#                                   avanca current_stage/next_instruction
#                  - terminal    -> end(concluido) + promove
#                                   .execution.status=concluida (+ reason/
#                                   finished_at) + current_stage=concluida
#         --dry-run descreve a acao sem escrever. Stdout em recuperacao:
#         "reconciled (phase=... motivo=... [next=...|terminal])".
#
#   state-ondas.sh git-commit --state-dir DIR --projeto-alvo-path PATH
#                             --motivo MOTIVO [--onda-id ID]
#       — Faz `git add .` + `git commit -m 'chore(agente-00c): onda <ID> - <MOTIVO>'`
#         dentro de --projeto-alvo-path. NUNCA push (Principio V).
#         Idempotente: se nao ha mudancas para commitar, retorna 0 sem erro.
#         Sem fail-soft: se git nao existe / dir nao e repo, exit 1.
#
# Exit codes:
#   0 sucesso
#   1 erro generico (state ausente, git falhou)
#   2 uso incorreto
#
# POSIX sh + jq + git (apenas em git-commit).

set -eu

_SO_NAME="state-ondas"
_SO_DIR=$(cd "$(dirname -- "$0")" && pwd)

# Envelope diagnostico aditivo (openspec-hygiene FR-012/FR-015 — escopo-piloto).
# Nota: o contrato propos 2 codes (wave-already-open, no-open-wave), mas a
# leitura do codigo real (task 4.4.1) confirmou que "start" NAO tem guarda
# fatal para onda-ja-aberta (nao-idempotente por desenho — cabe ao CALLER
# checar `wave-status` antes, ver contrato "GUARDA ANTI-DUPLICACAO" no
# agente-00c-feature-orchestrator.md). Migrado apenas `no-open-wave`, real
# em 2 pontos de falha: `end` (nenhuma onda para fechar) e `record-skill`
# (nenhuma onda para registrar a skill).
# shellcheck source=./_diag.sh
. "$_SO_DIR/_diag.sh"

_so_die_usage() { printf '%s: %s\n' "$_SO_NAME" "$1" >&2; exit 2; }
_so_die()       { printf '%s: %s\n' "$_SO_NAME" "$1" >&2; exit "${2:-1}"; }
_so_log()       { printf '%s: %s\n' "$_SO_NAME" "$1" >&2; }

_so_require_jq() {
  command -v jq >/dev/null 2>&1 \
    || _so_die "jq nao encontrado no PATH" 1
}

_so_iso_now() { date -u +%FT%TZ; }
_so_state_file() { printf '%s/state.json\n' "$1"; }

# Diretorio do proprio script — resolve scripts irmaos (pipeline.sh, state-rw.sh)
# usados por reconcile-wave. Deriva de $0 (mesmo padrao de model-routing.sh).
_so_self_dir() {
  CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd -P
}

_so_atomic_write() {
  _dst=$1; _src=$2
  _tmp=$(mktemp -- "${_dst}.XXXXXX") || _so_die "mktemp falhou" 1
  cp -- "$_src" "$_tmp" || { rm -f -- "$_tmp"; _so_die "I/O cp" 1; }
  mv -f -- "$_tmp" "$_dst" || { rm -f -- "$_tmp"; _so_die "mv" 1; }
}

_so_update_sha() {
  _sf=$(_so_state_file "$1")
  _shf="$1/state.json.sha256"
  if command -v sha256sum >/dev/null 2>&1; then
    _h=$(sha256sum -- "$_sf" | awk '{print $1}')
  else
    _h=$(shasum -a 256 -- "$_sf" | awk '{print $1}')
  fi
  printf '%s\n' "$_h" > "$_shf"
}

_so_backup_current() {
  _sf=$(_so_state_file "$1")
  [ -f "$_sf" ] || return 0
  _hd="$1/state-history"
  mkdir -p -- "$_hd" 2>/dev/null || _so_die "mkdir state-history falhou" 1
  _curr=$(jq -r '
    ((.waves // .ondas) // []) as $w
    | if ($w | length) > 0 then ($w[-1].id // "init") else "init" end
  ' "$_sf" 2>/dev/null) || _curr="init"
  _ts=$(date -u +%Y%m%dT%H%M%SZ)
  _bk="$_hd/${_curr}-${_ts}.json"
  mv -- "$_sf" "$_bk" || _so_die "backup falhou" 1
}

_so_next_onda_num() {
  _sf=$(_so_state_file "$1")
  jq -r '
    ((.waves // .ondas) // []) as $w
    | if ($w | length) == 0 then 1
    else (([$w[].id // ""] | map(sub("^onda-0*"; "") | tonumber? // 0) | max) + 1)
    end' "$_sf" 2>/dev/null
}

# ---------- Sidecar de ticks (hook PostToolUse) ----------
#
# O hook posttooluse-tool-call-tick.sh NAO pode fazer read-modify-write no
# state.json (dispara concorrente aos writes transacionais do orquestrador —
# risco de clobber); ele appenda 1 linha por tool call em
# <state-dir>/tool-call-ticks.log. Aqui esse sidecar e AGREGADO (end soma ao
# campo .budgets.tool_calls_current_wave, que segue existindo para ticks
# manuais via `tool-call-tick`) e RESETADO (start e end delimitam a janela
# de contagem da onda). budget.sh faz a mesma soma mid-onda.

_so_ticks_file() { printf '%s/tool-call-ticks.log\n' "$1"; }

# _so_ticks_count DIR -> nº de linhas do sidecar (0 se ausente/ilegivel).
_so_ticks_count() {
  _tf=$(_so_ticks_file "$1")
  [ -f "$_tf" ] || { printf '0\n'; return 0; }
  _n=$(wc -l < "$_tf" 2>/dev/null | tr -d '[:space:]') || _n=0
  case "$_n" in
    '' | *[!0-9]*) printf '0\n' ;;
    *) printf '%s\n' "$_n" ;;
  esac
}

# _so_ticks_reset DIR -> remove o sidecar (best-effort; hook recria no
# proximo tick). Ticks appendados na exata fronteira do reset se perdem —
# aceitavel para proxy de custo.
_so_ticks_reset() {
  rm -f -- "$(_so_ticks_file "$1")" 2>/dev/null || :
}

# ---------- Subcomandos ----------

_so_cmd_start() {
  _sdir=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir) _sdir=$2; shift 2 ;;
      *) _so_die_usage "start: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sdir" ] || _so_die_usage "start: --state-dir obrigatorio"
  _so_require_jq
  _sf=$(_so_state_file "$_sdir")
  [ -f "$_sf" ] || _so_die "start: state.json ausente em $_sdir" 1

  _num=$(_so_next_onda_num "$_sdir")
  _id=$(printf 'onda-%03d' "$_num")
  _now=$(_so_iso_now)

  _new=$(mktemp) || _so_die "mktemp falhou" 1
  jq --arg id "$_id" --arg ts "$_now" '
    .waves += [{
      id: $id,
      started_at: $ts,
      finished_at: null,
      executed_stages: [],
      tool_calls: 0,
      wallclock_seconds: 0,
      termination_reason: null,
      next_wave_scheduled_for: null,
      skills_invoked: []
    }]
    | .budgets.tool_calls_current_wave = 0
    | .budgets.current_wave_start = $ts
  ' "$_sf" > "$_new" || { rm -f -- "$_new"; _so_die "jq update falhou" 1; }

  _so_backup_current "$_sdir"
  _so_atomic_write "$_sf" "$_new"
  rm -f -- "$_new" 2>/dev/null || :
  _so_update_sha "$_sdir"
  # Janela de contagem do sidecar comeca zerada junto com a onda (ticks
  # entre o end anterior e este start pertencem a fechamento/overhead do
  # orquestrador, nao a onda nova).
  _so_ticks_reset "$_sdir"

  # Baseline de untracked (living-specs FASE 5, FR-014/data-model.md
  # UntrackedBaseline: "escrito por commit-mode.sh snapshot no inicio da
  # onda"). Best-effort: git-commit (passo 10 de toda onda) delega a
  # `stage-derived`, que so inclui untracked NOVOS desde este baseline —
  # capturar aqui, ANTES de qualquer trabalho da onda mutar o repo, e o
  # UNICO ponto onde "pre-existente" (alheio) vs "novo desta onda" pode
  # ser distinguido corretamente. Nunca bloqueia `start`: ausencia de git,
  # de target_project_path, ou de commit-mode.sh apenas deixa o baseline
  # ausente (git-commit cai no fail-closed existente, sem regressao no
  # ciclo de vida da onda).
  _so_start_snapshot_baseline "$_sdir"

  printf '%s\n' "$_id"
}

# Best-effort: deriva o projeto-alvo do proprio state.json e chama
# commit-mode.sh snapshot. Isolado em funcao propria para nunca poluir o
# fluxo principal de start com `set -e` (toda falha aqui e silenciosa).
_so_start_snapshot_baseline() {
  _ssb_sdir="$1"
  _ssb_sf=$(_so_state_file "$_ssb_sdir")
  command -v git >/dev/null 2>&1 || return 0

  _ssb_pap=$(jq -r '.execution.target_project_path // ""' "$_ssb_sf" 2>/dev/null) || _ssb_pap=""
  [ -n "$_ssb_pap" ] && [ -d "$_ssb_pap" ] || return 0

  _ssb_selfdir=$(_so_self_dir) || return 0
  _ssb_cm="$_ssb_selfdir/commit-mode.sh"
  [ -f "$_ssb_cm" ] || return 0

  sh "$_ssb_cm" snapshot --state-dir "$_ssb_sdir" --projeto-alvo-path "$_ssb_pap" \
    >/dev/null 2>&1 || _so_log "start: snapshot de baseline nao gravado (best-effort, sem impacto na onda)"
  return 0
}

# Calcula wallclock em segundos entre dois timestamps ISO.
# Implementa fallback portavel: tenta `date -d` (GNU), depois `date -j -f` (BSD).
_so_wallclock() {
  _start=$1
  _fim=$2
  if _se=$(date -u -d "$_start" +%s 2>/dev/null) && _fe=$(date -u -d "$_fim" +%s 2>/dev/null); then
    printf '%s\n' "$((_fe - _se))"
    return 0
  fi
  if _se=$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$_start" +%s 2>/dev/null) \
     && _fe=$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$_fim" +%s 2>/dev/null); then
    printf '%s\n' "$((_fe - _se))"
    return 0
  fi
  printf '0\n'
  return 1
}

_so_cmd_end() {
  _sdir=""
  _motivo=""
  _proxima="null"
  _etapas=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir)             _sdir=$2; shift 2 ;;
      --motivo-termino)        _motivo=$2; shift 2 ;;
      --proxima-agendada-para) _proxima=$2; shift 2 ;;
      --add-etapa)             _etapas="$_etapas
$2"; shift 2 ;;
      *) _so_die_usage "end: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sdir" ]   || _so_die_usage "end: --state-dir obrigatorio"
  [ -n "$_motivo" ] || _so_die_usage "end: --motivo-termino obrigatorio"
  case "$_motivo" in
    etapa_concluida_avancando|threshold_proxy_atingido|bloqueio_humano|aborto|concluido) ;;
    *) _so_die "end: motivo invalido: $_motivo" 2 ;;
  esac
  _so_require_jq
  _sf=$(_so_state_file "$_sdir")
  [ -f "$_sf" ] || _so_die "end: state.json ausente em $_sdir" 1

  _now=$(_so_iso_now)
  _start=$(jq -r '
    ((.waves // .ondas) // []) as $w
    | if ($w | length) > 0 then (($w[-1].started_at // $w[-1].inicio) // "") else "" end
  ' "$_sf")
  if [ -z "$_start" ]; then
    diag_emit error no-open-wave "end: nao ha onda em andamento" \
      "rode state-ondas.sh start antes de end, ou confira se .waves ja foi fechado por outra chamada" || :
    _so_die "end: nao ha onda em andamento" 1
  fi
  _wc=$(_so_wallclock "$_start" "$_now") || true
  # tool_calls da onda = campo do state (ticks manuais via tool-call-tick)
  # + sidecar do hook PostToolUse (ver "Sidecar de ticks" acima).
  _tc_field=$(jq -r '(.budgets.tool_calls_current_wave // .orcamentos.tool_calls_onda_corrente) // 0' "$_sf")
  _tc_side=$(_so_ticks_count "$_sdir")
  _tc=$((_tc_field + _tc_side))

  # Monta JSON array das etapas adicionais (uma por linha, ignora linhas vazias).
  _etapas_json=$(printf '%s\n' "$_etapas" \
    | sed '/^$/d' \
    | jq -R . \
    | jq -s .)

  _proxima_json="null"
  if [ "$_proxima" != "null" ]; then
    _proxima_json="\"$_proxima\""
  fi

  _new=$(mktemp) || _so_die "mktemp falhou" 1
  jq \
    --arg now "$_now" \
    --arg motivo "$_motivo" \
    --argjson wc "$_wc" \
    --argjson tc "$_tc" \
    --argjson etapas "$_etapas_json" \
    --argjson prox "$_proxima_json" '
    (.waves[-1] |= (
      .finished_at = $now
      | .wallclock_seconds = $wc
      | .tool_calls = $tc
      | .termination_reason = $motivo
      | .next_wave_scheduled_for = $prox
      | .executed_stages += $etapas
    ))
    | .accumulated_metrics.waves_total = ((.accumulated_metrics.waves_total // 0) + 1)
    | .accumulated_metrics.tool_calls_total = ((.accumulated_metrics.tool_calls_total // 0) + $tc)
    | .accumulated_metrics.wallclock_total_seconds =
        ((.accumulated_metrics.wallclock_total_seconds // 0) + $wc)
  ' "$_sf" > "$_new" || { rm -f -- "$_new"; _so_die "jq update falhou" 1; }

  _so_backup_current "$_sdir"
  _so_atomic_write "$_sf" "$_new"
  rm -f -- "$_new" 2>/dev/null || :
  _so_update_sha "$_sdir"
  # Sidecar consumido por esta onda; zera para nao vazar para a proxima.
  _so_ticks_reset "$_sdir"
  _so_log "end: onda finalizada (motivo=$_motivo, wallclock=${_wc}s, tool_calls=$_tc)"
}

_so_cmd_tool_call_tick() {
  _sdir=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir) _sdir=$2; shift 2 ;;
      *) _so_die_usage "tool-call-tick: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sdir" ] || _so_die_usage "tool-call-tick: --state-dir obrigatorio"
  _so_require_jq
  _sf=$(_so_state_file "$_sdir")
  [ -f "$_sf" ] || _so_die "tool-call-tick: state.json ausente" 1

  _curr=$(jq -r '(.budgets.tool_calls_current_wave // .orcamentos.tool_calls_onda_corrente) // 0' "$_sf")
  _next=$((_curr + 1))

  _new=$(mktemp) || _so_die "mktemp falhou" 1
  jq --argjson n "$_next" '.budgets.tool_calls_current_wave = $n' "$_sf" > "$_new" \
    || { rm -f -- "$_new"; _so_die "jq update falhou" 1; }
  # tool-call-tick e operacao de alta frequencia; backup so a cada 10 ticks
  # para nao explodir state-history/. Em ticks intermediarios o atomic_write
  # ja sobrescreve via `mv -f` — nao precisa rm.
  if [ "$((_next % 10))" = 0 ]; then
    _so_backup_current "$_sdir"
  fi
  _so_atomic_write "$_sf" "$_new"
  rm -f -- "$_new" 2>/dev/null || :
  _so_update_sha "$_sdir"
  printf '%s\n' "$_next"
}

_so_cmd_record_skill() {
  _sdir=""
  _skill=""
  _dec=""
  _kind="skill"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir)  _sdir=$2;  shift 2 ;;
      --skill)      _skill=$2; shift 2 ;;
      --decisao-id) _dec=$2;   shift 2 ;;
      --kind)       _kind=$2;  shift 2 ;;
      *) _so_die_usage "record-skill: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sdir" ]  || _so_die_usage "record-skill: --state-dir obrigatorio"
  [ -n "$_skill" ] || _so_die_usage "record-skill: --skill obrigatorio"
  case "$_kind" in
    skill|gate) ;;
    *) _so_die_usage "record-skill: --kind deve ser skill|gate (recebido: $_kind)" ;;
  esac
  _so_require_jq
  _sf=$(_so_state_file "$_sdir")
  [ -f "$_sf" ] || _so_die "record-skill: state.json ausente em $_sdir" 1

  # Verifica que existe onda em andamento
  _has_onda=$(jq -r 'if ((.waves // .ondas) // []) | length > 0 then "yes" else "no" end' "$_sf")
  if [ "$_has_onda" != "yes" ]; then
    diag_emit error no-open-wave "record-skill: nenhuma onda em andamento (rode state-ondas.sh start primeiro)" \
      "rode state-ondas.sh start antes de record-skill" || :
    _so_die "record-skill: nenhuma onda em andamento (rode state-ondas.sh start primeiro)" 1
  fi

  _now=$(_so_iso_now)
  _dec_json="null"
  if [ -n "$_dec" ]; then
    _dec_json=$(printf '%s' "$_dec" | jq -R .)
  fi

  _new=$(mktemp) || _so_die "mktemp falhou" 1
  jq \
    --arg skill "$_skill" \
    --arg ts "$_now" \
    --arg kind "$_kind" \
    --argjson dec "$_dec_json" '
    (.waves[-1].skills_invoked //= [])
    | (.waves[-1].skills_invoked |=
        (if (any(.[]; .skill == $skill and ((.decision_id // .decisao_id) // null) == $dec))
         then .
         else . + [{
           skill: $skill,
           timestamp: $ts,
           decision_id: $dec,
           kind: $kind
         }]
         end))
  ' "$_sf" > "$_new" || { rm -f -- "$_new"; _so_die "jq update falhou" 1; }

  _so_atomic_write "$_sf" "$_new"
  rm -f -- "$_new" 2>/dev/null || :
  _so_update_sha "$_sdir"
  _count=$(jq -r '((.waves // .ondas)[-1].skills_invoked) | length' "$_sf")
  printf '%s\n' "$_count"
}

# record-task: upsert idempotente de UMA entrada em .tasks[] (top-level).
# Chave natural dentro de um state.json (= uma execucao) = task_id. Substitui
# o snippet jq hand-rolled que vivia SO na prosa dos orquestradores (§5.d.ter):
# caminho de escrita auditado, atomico (state-history backup + sha256),
# idempotente. Diferente de record-skill, NAO exige onda em andamento —
# .tasks[] e top-level e pode ser gravado tambem na fase review-task.
#
# Default = UPSERT (sobrescreve a entrada existente com dados frescos — usado
# pelo execute-task, que conhece o outcome real). --if-absent = so insere se
# AUSENTE (no-op se ja existe; usado pelo back-fill reconcile-tasks, para nao
# clobberar uma entrada real com uma derivada).
#
# Campos `recorded_at`/`source` sao ADITIVOS — a ingestao knowledge.db
# (recall.sh) seleciona apenas os 8 campos do contrato layer-b e ignora o
# resto; servem para o review-task distinguir entradas reais de back-filled.
# Stdout: total de entradas em .tasks[] apos a operacao.
_so_cmd_record_task() {
  _sdir=""; _tid=""; _ttl=""; _wid=""; _oc=""
  _tr="0"; _tp="0"; _lk=""; _af="[]"; _origem=""; _ifabsent="no"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir)       _sdir=$2; shift 2 ;;
      --task-id)         _tid=$2;  shift 2 ;;
      --titulo)          _ttl=$2;  shift 2 ;;
      --wave-id)         _wid=$2;  shift 2 ;;
      --outcome)         _oc=$2;   shift 2 ;;
      --testes-rodados)  _tr=$2;   shift 2 ;;
      --testes-passados) _tp=$2;   shift 2 ;;
      --lint-ok)         _lk=$2;   shift 2 ;;
      --arquivos)        _af=$2;   shift 2 ;;
      --origem)          _origem=$2; shift 2 ;;
      --if-absent)       _ifabsent="yes"; shift ;;
      *) _so_die_usage "record-task: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sdir" ] || _so_die_usage "record-task: --state-dir obrigatorio"
  [ -n "$_tid" ]  || _so_die_usage "record-task: --task-id obrigatorio"
  [ -n "$_oc" ]   || _so_die_usage "record-task: --outcome obrigatorio"
  case "$_oc" in pass|fail) : ;; *) _so_die_usage "record-task: --outcome deve ser pass|fail" ;; esac
  case "$_tr" in ''|*[!0-9]*) _so_die_usage "record-task: --testes-rodados deve ser inteiro >= 0" ;; esac
  case "$_tp" in ''|*[!0-9]*) _so_die_usage "record-task: --testes-passados deve ser inteiro >= 0" ;; esac
  [ "$_tp" -le "$_tr" ] || _so_die_usage "record-task: --testes-passados ($_tp) > --testes-rodados ($_tr)"
  case "$_lk" in
    true|1)  _lk_json=true ;;
    false|0) _lk_json=false ;;
    '')      _lk_json=null ;;
    *) _so_die_usage "record-task: --lint-ok deve ser true|false (ou vazio)" ;;
  esac
  _so_require_jq
  _sf=$(_so_state_file "$_sdir")
  [ -f "$_sf" ] || _so_die "record-task: state.json ausente em $_sdir" 1
  printf '%s' "$_af" | jq -e 'type == "array"' >/dev/null 2>&1 \
    || _so_die_usage "record-task: --arquivos deve ser um array JSON (ex: '[]')"

  # wave-id default = onda corrente (proveniencia best-effort)
  if [ -z "$_wid" ]; then
    _wid=$(jq -r '((.waves // .ondas) // []) as $w | if ($w | length) > 0 then ($w[-1].id // "") else "" end' "$_sf" 2>/dev/null) || _wid=""
  fi

  _now=$(_so_iso_now)
  _origem_json=null
  [ -n "$_origem" ] && _origem_json=$(printf '%s' "$_origem" | jq -R .)

  _new=$(mktemp) || _so_die "mktemp falhou" 1
  jq \
    --arg tid "$_tid" --arg ttl "$_ttl" --arg wid "$_wid" --arg oc "$_oc" \
    --argjson tr "$_tr" --argjson tp "$_tp" --argjson lk "$_lk_json" \
    --argjson af "$_af" --arg ts "$_now" --argjson origem "$_origem_json" \
    --arg ifabsent "$_ifabsent" '
    (.tasks //= [])
    | {task_id:$tid, title:$ttl, wave_id:$wid, outcome:$oc,
       tests_run:$tr, tests_passed:$tp, lint_ok:$lk,
       touched_files:$af, recorded_at:$ts, source:$origem} as $e
    | if any(.tasks[]; .task_id == $tid)
      then (if $ifabsent == "yes" then .
            else .tasks |= map(if .task_id == $tid then $e else . end) end)
      else .tasks += [$e]
      end
  ' "$_sf" > "$_new" || { rm -f -- "$_new"; _so_die "record-task: jq update falhou" 1; }

  _so_atomic_write "$_sf" "$_new"
  rm -f -- "$_new" 2>/dev/null || :
  _so_update_sha "$_sdir"
  jq -r '(.tasks // []) | length' "$_sf"
}

# reconcile-tasks: rede de seguranca DETERMINISTICA contra perda de tasks.
# Le tasks.md (fonte de verdade do backlog) e garante que toda TASK CONCLUIDA
# tenha entrada em .tasks[]. Uma task = heading `### N.M {Titulo}`; esta
# CONCLUIDA quando tem >=1 subtarefa-checkbox e TODAS marcadas `[x]`. Tasks
# pendentes/em-andamento/bloqueadas NAO sao gravadas (nao ha outcome final —
# evita fabricar pass/fail). Back-fill via record-task --if-absent: NUNCA
# clobbera entrada real ja gravada pelo execute-task. Idempotente.
#
# Tambem CURA titulos vazios: entradas ja presentes em .tasks[] com
# title=="" (sintoma de onda execute-task longa gravada em lote sem
# --titulo) recebem o titulo do heading em tasks.md (fonte rastreavel,
# nunca inventada). Nao toca tests_run/tests_passed (sem fonte por task ->
# nao fabrica). So fora de --dry-run; nao afeta a contagem de stdout.
#
# Stdout (default): numero de tasks back-filled nesta chamada.
# --dry-run: NAO escreve; imprime os task_id que SERIAM back-filled (um por
#   linha) — usado pelo gate de completude do review-task.
_so_cmd_reconcile_tasks() {
  _rc_sdir=""; _rc_md=""; _rc_wid=""; _rc_dry="no"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir) _rc_sdir=$2; shift 2 ;;
      --tasks-md)  _rc_md=$2;   shift 2 ;;
      --wave-id)   _rc_wid=$2;  shift 2 ;;
      --dry-run)   _rc_dry="yes"; shift ;;
      *) _so_die_usage "reconcile-tasks: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_rc_sdir" ] || _so_die_usage "reconcile-tasks: --state-dir obrigatorio"
  [ -n "$_rc_md" ]   || _so_die_usage "reconcile-tasks: --tasks-md obrigatorio"
  _so_require_jq
  _rc_sf=$(_so_state_file "$_rc_sdir")
  [ -f "$_rc_sf" ] || _so_die "reconcile-tasks: state.json ausente em $_rc_sdir" 1
  [ -f "$_rc_md" ] || _so_die "reconcile-tasks: tasks.md ausente: $_rc_md" 1

  if [ -z "$_rc_wid" ]; then
    _rc_wid=$(jq -r '((.waves // .ondas) // []) as $w | if ($w | length) > 0 then ($w[-1].id // "") else "" end' "$_rc_sf" 2>/dev/null) || _rc_wid=""
  fi

  # --- Cura de titulos vazios -------------------------------------------
  # Entradas ja presentes em .tasks[] com title vazio/null (sintoma de onda
  # execute-task longa que gravou record-task em lote sem --titulo) recebem
  # o titulo do heading correspondente em tasks.md. A FONTE e rastreavel
  # (heading do backlog) — nunca inventada (Principio VI). Roda so fora de
  # --dry-run e NAO altera a contagem de back-fill (contrato de stdout
  # preservado: continua sendo o nº de tasks AUSENTES back-filled abaixo).
  if [ "$_rc_dry" != "yes" ]; then
    # Mapa id->titulo a partir de tasks.md em DUAS granularidades, porque
    # as ondas gravam tasks ora no nivel do heading (### N.M Titulo), ora no
    # nivel do checkbox (- [x] N.M.K texto). Heading tem precedencia sobre
    # checkbox para o mesmo id (na pratica nao colidem: heading e N.M,
    # checkbox e N.M.K). Em ambos os casos a FONTE e o backlog — rastreavel,
    # nunca inventado (Principio VI).
    _rc_titlemap=$(awk '
      { sub(/\r$/, "") }
      /^### / {
        line = $0; sub(/^### +/, "", line)
        split(line, a, /[ \t]+/); id = a[1]
        if (id ~ /^[0-9]+(\.[0-9]+)+(-bis(\.[0-9]+)*)?$/) {
          t = line; sub(/^[^ \t]+[ \t]+/, "", t)
          gsub(/`/, "", t); sub(/[ \t]*\[[CAM]\][ \t]*$/, "", t)
          gsub(/\t/, " ", t); gsub(/  +/, " ", t)
          sub(/^ +/, "", t); sub(/ +$/, "", t)
          if (t != "") heading[id] = t
        }
        next
      }
      /^- \[.\] / {
        line = $0; sub(/^- \[.\][ \t]+/, "", line)
        split(line, a, /[ \t]+/); id = a[1]
        if (id ~ /^[0-9]+(\.[0-9]+)+(-bis(\.[0-9]+)*)?$/) {
          t = line; sub(/^[^ \t]+[ \t]+/, "", t)
          gsub(/`/, "", t); gsub(/\t/, " ", t); gsub(/  +/, " ", t)
          sub(/^ +/, "", t); sub(/ +$/, "", t)
          if (t != "" && !(id in checkbox)) checkbox[id] = t
        }
        next
      }
      END {
        for (k in checkbox) if (!(k in heading)) print k "\t" checkbox[k]
        for (k in heading) print k "\t" heading[k]
      }
    ' "$_rc_md")
    if [ -n "$_rc_titlemap" ]; then
      _rc_mapjson=$(printf '%s\n' "$_rc_titlemap" \
        | jq -R 'split("\t") | {(.[0]): .[1]}' 2>/dev/null \
        | jq -s 'add' 2>/dev/null) || _rc_mapjson=""
      if [ -n "$_rc_mapjson" ]; then
        _rc_heal=$(mktemp) || _so_die "mktemp falhou" 1
        if jq --argjson m "$_rc_mapjson" '
              .tasks = ((.tasks // []) | map(
                if ((.title // "") == "") and (($m[.task_id] // null) != null)
                then .title = $m[.task_id] else . end))
            ' "$_rc_sf" > "$_rc_heal" 2>/dev/null \
            && ! cmp -s "$_rc_heal" "$_rc_sf"; then
          _so_atomic_write "$_rc_sf" "$_rc_heal"
          _so_update_sha "$_rc_sdir"
        fi
        rm -f -- "$_rc_heal" 2>/dev/null || :
      fi
    fi
  fi

  # task_ids ja presentes em .tasks[] (snapshot)
  _rc_exfile=$(mktemp) || _so_die "mktemp falhou" 1
  jq -r '(.tasks // [])[].task_id // empty' "$_rc_sf" > "$_rc_exfile" 2>/dev/null || :

  # awk: parseia tasks.md -> emite "id<TAB>titulo" para cada task CONCLUIDA
  # ainda AUSENTE de .tasks[]. O seen-set vem do primeiro arquivo (_rc_exfile);
  # comparamos por FILENAME (nao FNR==NR) porque o exfile pode estar VAZIO
  # (.tasks[] ainda sem entradas) — FNR==NR falharia consumindo o tasks.md
  # inteiro como seen-set.
  _rc_missing=$(awk -v exf="$_rc_exfile" '
    { sub(/\r$/, "") }
    FILENAME == exf { seen[$0] = 1; next }
    function flush() {
      if (cur != "" && nsub > 0 && ndone == nsub && !(cur in seen)) {
        print cur "\t" titulo
      }
      cur = ""; titulo = ""; nsub = 0; ndone = 0
    }
    /^#/ {
      flush()
      if ($0 ~ /^### /) {
        line = $0; sub(/^### +/, "", line)
        split(line, a, /[ \t]+/); id = a[1]
        if (id ~ /^[0-9]+(\.[0-9]+)+(-bis(\.[0-9]+)*)?$/) {
          cur = id
          t = line; sub(/^[^ \t]+[ \t]+/, "", t)
          gsub(/`/, "", t); sub(/[ \t]*\[[CAM]\][ \t]*$/, "", t)
          gsub(/\t/, " ", t)
          titulo = t
        }
      }
      next
    }
    /^- \[.\] / {
      if (cur != "") {
        st = substr($0, 4, 1)
        nsub++
        if (st == "x" || st == "X") ndone++
      }
      next
    }
    END { flush() }
  ' "$_rc_exfile" "$_rc_md")
  rm -f -- "$_rc_exfile" 2>/dev/null || :

  if [ -z "$_rc_missing" ]; then
    [ "$_rc_dry" = "yes" ] || printf '0\n'
    return 0
  fi

  if [ "$_rc_dry" = "yes" ]; then
    printf '%s\n' "$_rc_missing" | cut -f1
    return 0
  fi

  # Loop via here-doc (roda no shell corrente, nao em subshell — contador
  # persiste). record-task usa vars sem prefixo _rc_, entao nao colide com
  # _rc_id/_rc_ttl/_rc_count/_rc_missing do loop.
  _rc_count=0
  while IFS="$(printf '\t')" read -r _rc_id _rc_ttl; do
    [ -n "$_rc_id" ] || continue
    _so_cmd_record_task --state-dir "$_rc_sdir" --task-id "$_rc_id" \
      --titulo "$_rc_ttl" --wave-id "$_rc_wid" --outcome pass \
      --testes-rodados 0 --testes-passados 0 \
      --arquivos '[]' --origem reconcile --if-absent >/dev/null \
      || _so_die "reconcile-tasks: record-task falhou para $_rc_id" 1
    _rc_count=$((_rc_count + 1))
  done <<EOF
$_rc_missing
EOF
  printf '%s\n' "$_rc_count"
}

_so_cmd_current_id() {
  _sdir=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir) _sdir=$2; shift 2 ;;
      *) _so_die_usage "current-id: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sdir" ] || _so_die_usage "current-id: --state-dir obrigatorio"
  _so_require_jq
  _sf=$(_so_state_file "$_sdir")
  [ -f "$_sf" ] || _so_die "current-id: state.json ausente" 1
  jq -r '
    ((.waves // .ondas) // []) as $w
    | if ($w | length) > 0 then ($w[-1].id // "init") else "init" end
  ' "$_sf"
}

# git-commit: faz commit local no projeto-alvo (NUNCA push — Principio V).
_so_cmd_git_commit() {
  _sdir=""
  _pap=""
  _motivo=""
  _onda=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir)         _sdir=$2; shift 2 ;;
      --projeto-alvo-path) _pap=$2;  shift 2 ;;
      --motivo)            _motivo=$2; shift 2 ;;
      --onda-id)           _onda=$2; shift 2 ;;
      *) _so_die_usage "git-commit: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sdir" ]   || _so_die_usage "git-commit: --state-dir obrigatorio"
  [ -n "$_pap" ]    || _so_die_usage "git-commit: --projeto-alvo-path obrigatorio"
  [ -n "$_motivo" ] || _so_die_usage "git-commit: --motivo obrigatorio"
  command -v git >/dev/null 2>&1 || _so_die "git-commit: git nao encontrado no PATH" 1
  [ -d "$_pap" ] || _so_die "git-commit: projeto-alvo-path nao existe: $_pap" 1
  # Worktree-safe: em git worktree o `.git` e um ARQUIVO (`gitdir: ...`), nao
  # diretorio — `[ -d .git ]` daria falso-negativo e quebraria `cstk session`.
  # `rev-parse` cobre repo normal, worktree e submodulo (mesma checagem de
  # commit-mode.sh).
  if ! git -C "$_pap" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    _so_die "git-commit: $_pap nao e repositorio git (init manual antes)" 1
  fi
  if [ -z "$_onda" ]; then
    _onda=$(_so_cmd_current_id --state-dir "$_sdir")
  fi
  # Sanitiza motivo: remove newlines + limita a 100 chars
  _motivo_safe=$(printf '%s' "$_motivo" | tr '\n\r' '  ' | cut -c 1-100)

  # Staging por allowlist derivada (living-specs FASE 5, FR-014):
  # delega a commit-mode.sh stage-derived em vez de `git add -- .` — o
  # wave-commit pode tocar qualquer path do repo (sem --scope-dir), mas o
  # staging fica explicito por allowlist (tracked mudados + untracked
  # NOVOS desde o ultimo snapshot da onda), nunca staging amplo.
  _sog_selfdir=$(_so_self_dir) || _sog_selfdir="."
  _sog_cm="$_sog_selfdir/commit-mode.sh"
  [ -f "$_sog_cm" ] || _so_die "git-commit: commit-mode.sh nao encontrado em $_sog_selfdir" 1

  # O baseline (commit-baseline.txt) e capturado no INICIO da onda por
  # `state-ondas.sh start` (best-effort, via .execution.target_project_path
  # do proprio state.json — data-model.md UntrackedBaseline: "escrito...
  # no inicio da onda"). Snapshotar aqui, no momento do commit (fim da
  # onda), seria tarde demais: todo trabalho da onda ja teria acontecido,
  # entao o baseline capturaria o MESMO untracked que stage-derived tentaria
  # marcar como "novo" — diff sempre vazio. Se `start` nao gravou baseline
  # (target_project_path ausente/invalido, git ausente), stage-derived cai
  # no fail-closed documentado: untracked fica fora, tracked segue incluido.
  _sog_stage_rc=0
  sh "$_sog_cm" stage-derived --state-dir "$_sdir" --projeto-alvo-path "$_pap" \
    || _sog_stage_rc=$?

  if [ "$_sog_stage_rc" = 3 ]; then
    # Allowlist vazia: preserva o comportamento atual de "nada para
    # commitar" (no-op), sem quebrar o contrato existente.
    _so_log "git-commit: nada para commitar (no-op)"
    return 0
  fi
  [ "$_sog_stage_rc" = 0 ] || _so_die "git-commit: stage-derived falhou (exit $_sog_stage_rc) em $_pap" 1

  ( cd -- "$_pap" \
    && if git diff --cached --quiet; then
         _so_log "git-commit: nada para commitar (no-op)"
       else
         git commit -m "chore(agente-00c): $_onda - $_motivo_safe" >/dev/null \
           || _so_die "git commit falhou em $_pap" 1
         _so_log "git-commit: commit feito ($_onda)"
       fi
  ) || exit 1
}

# ---------- Dispatch ----------

if [ "$#" -lt 1 ]; then
  cat >&2 <<'HELP'
state-ondas.sh — ciclo de vida de Ondas (FASE 3.4).

USO:
  state-ondas.sh start          --state-dir DIR
  state-ondas.sh end            --state-dir DIR --motivo-termino MOTIVO
                                [--proxima-agendada-para ISO]
                                [--add-etapa STAGE]...
  state-ondas.sh tool-call-tick --state-dir DIR
  state-ondas.sh record-skill   --state-dir DIR --skill NAME
                                [--decisao-id DEC-NNN]
  state-ondas.sh record-task    --state-dir DIR --task-id ID --outcome pass|fail
                                [--titulo T] [--wave-id ID] [--testes-rodados N]
                                [--testes-passados N] [--lint-ok true|false]
                                [--arquivos JSON-ARRAY] [--origem TAG] [--if-absent]
  state-ondas.sh reconcile-tasks --state-dir DIR --tasks-md PATH
                                [--wave-id ID] [--dry-run]
  state-ondas.sh current-id     --state-dir DIR
  state-ondas.sh git-commit     --state-dir DIR --projeto-alvo-path PATH
                                --motivo MOTIVO [--onda-id ID]

Motivos validos para `end`:
  etapa_concluida_avancando | threshold_proxy_atingido | bloqueio_humano |
  aborto | concluido

EXIT:
  0 sucesso
  1 erro generico
  2 uso incorreto

NUNCA `git push` — Principio V (Blast Radius Confinado).
HELP
  exit 2
fi

_so_cmd_wave_status() {
  _ws_sdir=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir) _ws_sdir=$2; shift 2 ;;
      *) _so_die_usage "wave-status: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_ws_sdir" ] || _so_die_usage "wave-status: --state-dir obrigatorio"
  _so_require_jq
  _ws_sf=$(_so_state_file "$_ws_sdir")
  [ -f "$_ws_sf" ] || _so_die "wave-status: state.json ausente em $_ws_sdir" 1
  jq -r '
    ((.waves // .ondas) // []) as $w
    | if   ($w | length) == 0                  then "none"
      elif ($w[-1].termination_reason // null) == null then "open"
      else "closed" end
  ' "$_ws_sf"
}

_so_cmd_reconcile_wave() {
  _rcw_sdir=""; _rcw_phase=""; _rcw_md=""; _rcw_dry="no"; _rcw_terminal=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir)      _rcw_sdir=$2; shift 2 ;;
      --phase)          _rcw_phase=$2; shift 2 ;;
      --tasks-md)       _rcw_md=$2; shift 2 ;;
      --terminal-phase) _rcw_terminal=$2; shift 2 ;;
      --dry-run)        _rcw_dry="yes"; shift ;;
      *) _so_die_usage "reconcile-wave: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_rcw_sdir" ] || _so_die_usage "reconcile-wave: --state-dir obrigatorio"
  _so_require_jq
  _rcw_sf=$(_so_state_file "$_rcw_sdir")
  [ -f "$_rcw_sf" ] || _so_die "reconcile-wave: state.json ausente em $_rcw_sdir" 1

  # Guarda de idempotencia: so recupera onda ABERTA. Onda fechada/inexistente
  # = no-op (exit 0). E o que torna seguro o pai chamar a CADA onda sem
  # double-count em accumulated_metrics (que `end` incrementa por chamada).
  _rcw_status=$(jq -r '
    ((.waves // .ondas) // []) as $w
    | if   ($w | length) == 0                  then "none"
      elif ($w[-1].termination_reason // null) == null then "open"
      else "closed" end
  ' "$_rcw_sf")
  if [ "$_rcw_status" != "open" ]; then
    printf 'noop (%s)\n' "$_rcw_status"
    return 0
  fi

  # Resolve a fase que a onda rodou. current_stage == fase corrente ate o
  # fechamento (init grava current_stage = fase a rodar; o avanco do ponteiro
  # so ocorre ao fechar a onda). --phase permite ao pai fixar explicitamente.
  if [ -z "$_rcw_phase" ]; then
    _rcw_phase=$(jq -r '(.current_stage // .etapa_corrente) // ""' "$_rcw_sf")
  fi
  [ -n "$_rcw_phase" ] || _so_die "reconcile-wave: nao foi possivel resolver a fase (--phase ou .current_stage)" 1

  # Proxima fase do pipeline (vazio = fase terminal). A terminalidade depende
  # do FLAVOR: feature-00c termina em review-task; agente-00c em review-features.
  # pipeline.sh next-stage usa a lista COMPLETA (agente-00c), entao para
  # feature-00c o pai passa --terminal-phase review-task — quando a fase
  # corrente == terminal-phase, tratamos como terminal (next vazio) sem
  # consultar pipeline.sh (que avancaria erroneamente para review-features).
  _rcw_selfdir=$(_so_self_dir) || _rcw_selfdir="."
  _rcw_pipeline="$_rcw_selfdir/pipeline.sh"
  _rcw_rw="$_rcw_selfdir/state-rw.sh"
  if [ -n "$_rcw_terminal" ] && [ "$_rcw_phase" = "$_rcw_terminal" ]; then
    _rcw_next=""
  elif [ -f "$_rcw_pipeline" ]; then
    _rcw_next=$(sh "$_rcw_pipeline" next-stage --current "$_rcw_phase" 2>/dev/null) || _rcw_next=""
  else
    _rcw_next=""
  fi

  if [ "$_rcw_dry" = "yes" ]; then
    if [ -n "$_rcw_next" ]; then
      printf 'would reconcile: phase=%s -> next=%s motivo=etapa_concluida_avancando\n' "$_rcw_phase" "$_rcw_next"
    else
      printf 'would reconcile: phase=%s (terminal) -> status=concluida motivo=concluido\n' "$_rcw_phase"
    fi
    return 0
  fi

  # 1. execute-task: back-fill .tasks[] (senao recall ingere 0 tasks). Best-effort.
  if [ "$_rcw_phase" = "execute-task" ] && [ -n "$_rcw_md" ]; then
    _so_cmd_reconcile_tasks --state-dir "$_rcw_sdir" --tasks-md "$_rcw_md" >/dev/null 2>&1 || :
  fi

  # 2. registrar a skill da fase (idempotente) — senao some do audit.
  _so_cmd_record_skill --state-dir "$_rcw_sdir" --skill "$_rcw_phase" >/dev/null 2>&1 || :

  # 3. fechar a onda com motivo derivado (fail-loud: end usa _so_die/exit).
  if [ -n "$_rcw_next" ]; then
    _rcw_motivo="etapa_concluida_avancando"
  else
    _rcw_motivo="concluido"
  fi
  _so_cmd_end --state-dir "$_rcw_sdir" --motivo-termino "$_rcw_motivo" >/dev/null

  # 4. avancar ponteiro (ou promover status terminal). end NAO faz isto.
  [ -f "$_rcw_rw" ] || _so_die "reconcile-wave: state-rw.sh nao encontrado em $_rcw_selfdir" 1
  if [ -n "$_rcw_next" ]; then
    sh "$_rcw_rw" set --state-dir "$_rcw_sdir" \
      --field '.current_stage' --value "\"$_rcw_next\"" >/dev/null
    _rcw_instr=$(printf 'Iniciar etapa %s — retomada pela rede de seguranca do command pai (onda anterior fechada sem Schedule intent).' "$_rcw_next" | jq -R .)
    sh "$_rcw_rw" set --state-dir "$_rcw_sdir" \
      --field '.next_instruction' --value "$_rcw_instr" >/dev/null
  else
    _rcw_now=$(_so_iso_now)
    sh "$_rcw_rw" set --state-dir "$_rcw_sdir" --field '.execution.status' --value '"concluida"' >/dev/null
    sh "$_rcw_rw" set --state-dir "$_rcw_sdir" --field '.execution.termination_reason' --value '"concluido"' >/dev/null
    sh "$_rcw_rw" set --state-dir "$_rcw_sdir" --field '.execution.finished_at' --value "\"$_rcw_now\"" >/dev/null
    sh "$_rcw_rw" set --state-dir "$_rcw_sdir" --field '.current_stage' --value '"concluida"' >/dev/null
    sh "$_rcw_rw" set --state-dir "$_rcw_sdir" --field '.next_instruction' --value '"Execucao concluida — nenhuma proxima etapa."' >/dev/null
  fi

  if [ -n "$_rcw_next" ]; then
    printf 'reconciled (phase=%s motivo=%s next=%s)\n' "$_rcw_phase" "$_rcw_motivo" "$_rcw_next"
  else
    printf 'reconciled (phase=%s motivo=%s terminal)\n' "$_rcw_phase" "$_rcw_motivo"
  fi
}

_SO_SUBCMD=$1
shift

case "$_SO_SUBCMD" in
  start)            _so_cmd_start "$@" ;;
  end)              _so_cmd_end "$@" ;;
  tool-call-tick)   _so_cmd_tool_call_tick "$@" ;;
  record-skill)     _so_cmd_record_skill "$@" ;;
  record-task)      _so_cmd_record_task "$@" ;;
  reconcile-tasks)  _so_cmd_reconcile_tasks "$@" ;;
  wave-status)      _so_cmd_wave_status "$@" ;;
  reconcile-wave)   _so_cmd_reconcile_wave "$@" ;;
  current-id)       _so_cmd_current_id "$@" ;;
  git-commit)       _so_cmd_git_commit "$@" ;;
  -h|--help|help)   exit 0 ;;
  *) _so_die_usage "subcomando desconhecido: $_SO_SUBCMD" ;;
esac
