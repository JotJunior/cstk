#!/bin/sh
# posttooluse-jira-sync.sh — hook PostToolUse do plugin cstk-jira: gatilho do
# sync autonomo (US3, arquitetura A1 / dec-020, FR-005/FR-018-INFRA-SCHED).
#
# Ref: docs/specs/cstk-jira/contracts/hooks.md "Entradas do hooks.json" +
#      "Comportamento de posttooluse-jira-sync.sh"; data-model.md Entity
#      OutboxEvent; tasks.md 5.1.
#
# Invocacao (hooks.json passa o MODO como $1, nunca deriva de tool_name):
#   posttooluse-jira-sync.sh task   -> matcher mcp__.*__record_task
#   posttooluse-jira-sync.sh wave   -> matcher mcp__.*__close_wave
#   posttooluse-jira-sync.sh bash   -> matcher Bash (so age se
#                                       tool_input.command contem
#                                       "state-ondas.sh record-task" ou
#                                       "state-ondas.sh end")
#
# POLITICA: fail-open ABSOLUTO (mesma classe de posttooluse-tool-call-tick.sh
# do plugin cstk) — este hook NUNCA bloqueia, atrasa ou falha a tool do
# orquestrador. Por isso NAO usa `set -e`: cada passo trata a propria falha
# e o script sempre alcanca o `exit 0` final. `async: true` no hooks.json ja
# roda isto em background (timeout nao e aplicado a hooks async).
#
# POSIX sh, SEM jq/cliente HTTP neste arquivo (carve-out 1.1.0 do Principio
# II, condicao b: so plugins/cstk-jira/scripts/jira-io.sh referencia essas
# ferramentas). Extracao de campos JSON e feita via grep/sed puros — flat,
# tolerante a falha (valor nao encontrado = string vazia = ramo de no-op),
# nunca aborta.
#
# NAO-EXFILTRACAO (CHK013, FR-029 item 5.1.7): tool_input de
# record_task/close_wave carrega `session_id` (token de capacidade do
# servidor MCP de estado). Este script NUNCA extrai, loga ou repassa
# `session_id` — le SOMENTE task_id/outcome (modo task) ou nada (modo wave).
#
# NUNCA toca state.json/state.db da execucao (READ-ONLY quando precisa
# derivar canonical_project do agente-00c-state — nunca escreve nele).

set -u

_PJS_MODE="${1:-}"
case "$_PJS_MODE" in
  task | wave | bash) ;;
  *) exit 0 ;;
esac

_PJS_SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd) || exit 0
_PJS_ENGINE="$_PJS_SELF_DIR/../scripts/jira-sync.sh"
[ -r "$_PJS_ENGINE" ] || exit 0

# ==== Extracao JSON sem jq (flat, best-effort) ====

# _pjs_json_str JSON KEY -> valor de um campo string simples ("key":"value"),
# 1a ocorrencia. Serve para cwd/task_id/outcome (valores sem aspas internas).
_pjs_json_str() {
  printf '%s\n' "$1" | tr -d '\n' \
    | sed -n 's/.*"'"$2"'"[ 	]*:[ 	]*"\([^"]*\)".*/\1/p' | head -n 1
}

# _pjs_cmd_flag TEXT FLAG -> valor de uma flag de linha de comando
# (--flag VALUE ou --flag "VALUE") dentro de TEXT, tolerando que TEXT seja o
# JSON bruto (aspas do comando aparecem escapadas como \" — o backslash
# opcional antes da aspas cobre esse caso sem precisar isolar o campo
# "command" primeiro). Para de capturar em espaco/aspas/backslash.
_pjs_cmd_flag() {
  printf '%s\n' "$1" | tr -d '\n' \
    | sed -n 's/.*'"$2"'[ 	]*["\\]*\([^ 	"\\]*\).*/\1/p' | head -n 1
}

_PJS_INPUT=$(cat 2>/dev/null) || exit 0
[ -n "$_PJS_INPUT" ] || exit 0

_PJS_CWD=$(_pjs_json_str "$_PJS_INPUT" cwd)
[ -n "$_PJS_CWD" ] || exit 0
[ -d "$_PJS_CWD" ] || exit 0

# ==== 1. No-op de inatividade (FR-017/SC-006) — PRIMEIRA checagem real ====

_PJS_CONFIG="$_PJS_CWD/.claude/cstk-jira/config"
[ -f "$_PJS_CONFIG" ] || exit 0

if grep -q '^sync_autonomous=off[ 	]*$' "$_PJS_CONFIG" 2>/dev/null; then
  exit 0
fi

# ==== 2. Resolucao da execucao ativa ====

_PJS_HOOKLOG="$_PJS_CWD/.claude/cstk-jira/runtime/hook.log"

_pjs_log() {
  _pjs_log_dir=$(dirname -- "$_PJS_HOOKLOG") 2>/dev/null
  mkdir -p "$_pjs_log_dir" 2>/dev/null || return 0
  _pjs_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || _pjs_ts="ts"
  printf '%s %s\n' "$_pjs_ts" "$1" >> "$_PJS_HOOKLOG" 2>/dev/null || :
}

# _pjs_resolve_canonical_project PROJECT_DIR -> canonical_project derivado
# (mesma derivacao do orquestrador: .execution.canonical_project com
# fallback basename(target_project_path)) — READ-ONLY, nunca escreve. Ramo
# state.db (task 13.1.1 / Constitution II carve-out 1.1.0): este hook NUNCA
# chama `sqlite3` diretamente — delega ao UNICO ponto do plugin que le
# campos de state.db, o subcomando `resolve-state-field` de `jira-sync.sh`
# (`$_PJS_ENGINE`, ja resolvido acima), que por sua vez so consome o
# `state-rw.sh` do runtime `agente-00c-runtime` quando localizavel.
_pjs_resolve_canonical_project() {
  _pjs_rc_dir="$1/.claude/agente-00c-state"
  _pjs_rc_val=""
  if [ -f "$_pjs_rc_dir/state.json" ]; then
    _pjs_rc_val=$(_pjs_json_str "$(cat "$_pjs_rc_dir/state.json" 2>/dev/null)" canonical_project 2>/dev/null) || _pjs_rc_val=""
  elif [ -f "$_pjs_rc_dir/state.db" ]; then
    _pjs_rc_val=$("$_PJS_ENGINE" resolve-state-field --dir "$_pjs_rc_dir" --field canonical_project 2>/dev/null) || _pjs_rc_val=""
  fi
  if [ -z "$_pjs_rc_val" ] || [ "$_pjs_rc_val" = "null" ]; then
    basename -- "$1"
  else
    printf '%s' "$_pjs_rc_val"
  fi
}

_PJS_CANDIDATES=0
_PJS_FEATURE=""

_PJS_F00C_ROOT="$_PJS_CWD/.claude/feature-00c-state"
if [ -d "$_PJS_F00C_ROOT" ]; then
  for _pjs_d in "$_PJS_F00C_ROOT"/*/; do
    [ -d "$_pjs_d" ] || continue
    if [ -d "${_pjs_d}.lock" ]; then
      _PJS_CANDIDATES=$((_PJS_CANDIDATES + 1))
      _PJS_FEATURE=$(basename -- "${_pjs_d%/}")
    fi
  done
fi

_PJS_A00C_LOCK="$_PJS_CWD/.claude/agente-00c-state/.lock"
if [ -d "$_PJS_A00C_LOCK" ]; then
  _PJS_CANDIDATES=$((_PJS_CANDIDATES + 1))
  _PJS_FEATURE=$(_pjs_resolve_canonical_project "$_PJS_CWD")
fi

if [ "$_PJS_CANDIDATES" -ne 1 ] || [ -z "$_PJS_FEATURE" ]; then
  _pjs_log "no-op: candidatos=$_PJS_CANDIDATES (esperado exatamente 1)"
  exit 0
fi

# ==== 3. Filtro de feature convertida (US1 e pre-requisito) ====

[ -f "$_PJS_CWD/docs/specs/$_PJS_FEATURE/jira-map.tsv" ] || exit 0

# ==== 4. Enfileirar OutboxEvent conforme o modo ====

_PJS_LOCAL_KEY=""
_PJS_STATE=""
_PJS_SOURCE=""

case "$_PJS_MODE" in
  task)
    _PJS_LOCAL_KEY=$(_pjs_json_str "$_PJS_INPUT" task_id)
    _PJS_STATE=$(_pjs_json_str "$_PJS_INPUT" outcome)
    _PJS_SOURCE="hook-record-task"
    ;;
  wave)
    _PJS_LOCAL_KEY="*"
    _PJS_STATE="reconcile"
    _PJS_SOURCE="hook-close-wave"
    ;;
  bash)
    # Deteccao de substring roda sobre o PAYLOAD BRUTO (_PJS_INPUT) — nunca
    # sobre o campo "command" isolado — para nao depender do isolamento
    # exato (aspas internas do comando aparecem escapadas no JSON).
    case "$_PJS_INPUT" in
      *'state-ondas.sh record-task'*)
        _PJS_LOCAL_KEY=$(_pjs_cmd_flag "$_PJS_INPUT" "--task-id")
        _PJS_STATE=$(_pjs_cmd_flag "$_PJS_INPUT" "--outcome")
        _PJS_SOURCE="hook-record-task"
        ;;
      *'state-ondas.sh end'*)
        _PJS_LOCAL_KEY="*"
        _PJS_STATE="reconcile"
        _PJS_SOURCE="hook-close-wave"
        ;;
      *) exit 0 ;;
    esac
    ;;
esac

[ -n "$_PJS_LOCAL_KEY" ] || exit 0
case "$_PJS_STATE" in
  pending | in_progress | pass | fail | reconcile) ;;
  *) exit 0 ;;
esac

# ==== 5. Drenar (subshell: cwd real, nunca o do processo do hook) ====

# FASE 12 tarefa 12.7.1 (FR-016 / data-model.md Entity ConflictRecord —
# "consumido ... pelo resumo emitido pelo hook no fechamento de onda"): o
# diagnostico de stderr do drain (gate auth_failed/FR-016, ProjectConfig
# invalido, conflito detectado) deixava de existir para o operador na
# execucao autonoma (`>/dev/null 2>&1` descartava tudo). Agora e anexado a
# `runtime/hook.log`, junto de um resumo curto (conflict/auth_failed/
# deferred) via `jira-sync.sh status` — subcomando 100% LOCAL, sem
# rede/titulo do Jira (mesma garantia documentada em `_js_cmd_status`), por
# isso nada aqui precisa do rotulo UNTRUSTED (nunca se ecoa texto do Jira).
# `_pjs_log` ja e best-effort (mkdir/redirect com `|| :`) — continua
# fail-open, o hook NUNCA falha por causa deste passo.

_PJS_DRAIN_DIAG=$(
  cd "$_PJS_CWD" 2>/dev/null || exit 0
  sh "$_PJS_ENGINE" enqueue --feature "$_PJS_FEATURE" --local-key "$_PJS_LOCAL_KEY" \
    --state "$_PJS_STATE" --source "$_PJS_SOURCE" >/dev/null 2>&1 || :
  sh "$_PJS_ENGINE" drain --feature "$_PJS_FEATURE" 2>&1 >/dev/null
)
if [ -n "$_PJS_DRAIN_DIAG" ]; then
  _pjs_log "drain: $(printf '%s' "$_PJS_DRAIN_DIAG" | tr '\n' ' ' | cut -c1-500)"
fi

# task 13.4.1 (FR-016 / data-model ConflictRecord "resumo emitido pelo
# hook no fechamento de onda"): a contagem de conflito do resumo NUNCA vem
# mais do outbox (`conflict=` da linha `queued=...` — eventos, so cobre
# conflitos originados de drain direto e, antes de 13.3.1, nunca esquecia
# um ja resolvido) — vem do `pending=N` de ConflictRecords PENDENTES
# (runtime/conflicts.tsv), que `jira-sync.sh status` ja expoe e cobre TODA
# origem (drain, reconcile via close_wave, convert) e nunca acusa um
# conflito ja fechado por `resolve` (qualquer --choice).
_PJS_STATUS_OUT=$(
  cd "$_PJS_CWD" 2>/dev/null || exit 0
  sh "$_PJS_ENGINE" status --feature "$_PJS_FEATURE" 2>/dev/null
)
_PJS_OUTBOX_LINE=$(printf '%s\n' "$_PJS_STATUS_OUT" | grep '^queued=')
_PJS_Q=$(printf '%s\n' "$_PJS_OUTBOX_LINE" | sed -n 's/^queued=\([0-9]*\).*/\1/p')
_PJS_D=$(printf '%s\n' "$_PJS_OUTBOX_LINE" | sed -n 's/.*deferred=\([0-9]*\).*/\1/p')
_PJS_A=$(printf '%s\n' "$_PJS_OUTBOX_LINE" | sed -n 's/.*auth_failed=\([0-9]*\).*/\1/p')
[ -n "$_PJS_Q" ] || _PJS_Q=0
[ -n "$_PJS_D" ] || _PJS_D=0
[ -n "$_PJS_A" ] || _PJS_A=0
_PJS_CONFLICT_PENDING=$(printf '%s\n' "$_PJS_STATUS_OUT" | sed -n 's/^pending=\([0-9]*\)$/\1/p')
[ -n "$_PJS_CONFLICT_PENDING" ] || _PJS_CONFLICT_PENDING=0

if [ "$_PJS_D" != "0" ] || [ "$_PJS_CONFLICT_PENDING" != "0" ] || [ "$_PJS_A" != "0" ]; then
  _pjs_log "resumo pos-drain ($_PJS_FEATURE): queued=$_PJS_Q deferred=$_PJS_D conflict=$_PJS_CONFLICT_PENDING auth_failed=$_PJS_A"
fi

# ==== 6. Fail-open absoluto ====
exit 0
