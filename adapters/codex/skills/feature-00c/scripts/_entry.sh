#!/bin/sh
# Common entrypoint setup and transports; never starts a second model.
# Globals below are consumed by sourced entrypoints.
# shellcheck disable=SC2034
set -eu
CX_ENTRY_DIR=${CX_ENTRY_DIR:-$(dirname -- "$0")}
_ce_root=$(CDPATH='' cd -P -- "$CX_ENTRY_DIR" && pwd -P)
while [ "$_ce_root" != / ] && [ ! -f "$_ce_root/cli/lib/codex-json.sh" ]; do _ce_root=$(dirname -- "$_ce_root"); done
[ -f "$_ce_root/cli/lib/codex-json.sh" ] || { printf 'CSTK assets unavailable\n' >&2; exit 1; }
. "$_ce_root/cli/lib/codex-json.sh"
. "$_ce_root/cli/lib/codex-common.sh"
CX_TEMP=$(mktemp -d); chmod 700 "$CX_TEMP"
. "$CX_ENTRY_DIR/_session.sh"
. "$CX_ENTRY_DIR/_tools.sh"
CX_TOOLS=$(cx_tools)
CX_RESUME_OPEN=true

cx_cleanup() {
  if [ "$CX_LOCKED" = true ]; then
    if [ -n "$CX_WAVE" ]; then cx_close threshold_proxy_atingido "Continuar etapa $CX_STAGE: onda interrompida; conferir artefatos." false || :; fi
    cx_release || :
  fi
  rm -r -- "$CX_TEMP"
}
trap 'cx_cleanup' 0
trap 'exit 130' INT TERM

cx_action() {
  _ax_action=$1
  cx_arguments "$_ax_action" || return
  case "$_ax_action" in
    select_execution) cx_select; return ;;
    context) if [ -n "$CX_PROJECT" ]; then cx_prepare || return; CX_RESULT=$CX_CONTEXT; else CX_RESULT='{"execution_selected":false,"autonomous_ready":false}'; fi; return ;;
  esac
  [ -n "$CX_STATE" ] || { cx_fail 'select an execution before changing state'; return 1; }
  case "$_ax_action" in
    decision|complete|pause|block) [ -n "$CX_WAVE" ] || { cx_fail 'open a wave before recording execution'; return 1; } ;;
    status|abort) ;;
    *) [ -z "$CX_WAVE" ] || { cx_fail 'close the owned wave before changing session setup'; return 1; } ;;
  esac
  if [ "$CX_LOCKED" = false ]; then cx_acquire || return; fi
  _ax_rc=0
  case "$_ax_action" in
    bootstrap) cx_bootstrap || _ax_rc=$? ;;
    optin) cx_optin || _ax_rc=$? ;;
    open_wave) cx_wave_open || _ax_rc=$? ;;
    status) cx_validate true true true true && cx_describe || _ax_rc=$? ;;
    resume)
      if cx_resume; then
        if [ "$CX_RESUME_OPEN" = true ] && [ "$(cj_get "$CX_RESULT" /terminal)" = false ] && [ "$(cj_length "$CX_RESULT" /pending_blocks)" = 0 ]; then cx_wave_open || _ax_rc=$?; fi
      else _ax_rc=$?
      fi ;;
    abort) cx_abort || _ax_rc=$? ;;
    handoff) cx_handoff || _ax_rc=$? ;;
    reconcile_governance) cx_reconcile || _ax_rc=$? ;;
    recover) cx_recover || _ax_rc=$? ;;
    decision) cx_decision || _ax_rc=$? ;;
    complete) cx_complete || _ax_rc=$? ;;
    block) cx_block || _ax_rc=$? ;;
    pause) cx_close threshold_proxy_atingido "$(cj_get "$CX_ARGS" /instruction)" false || _ax_rc=$? ;;
  esac
  _ax_error=$CX_ERROR
  if [ "$_ax_rc" != 0 ]; then
    case "$_ax_action" in open_wave|resume)
      if [ -n "$CX_WAVE" ]; then cx_close threshold_proxy_atingido "Continuar etapa $CX_STAGE: falha ao despachar; conferir evidencias." false || :; fi ;;
    esac
  fi
  if [ -z "$CX_WAVE" ]; then cx_release || _ax_rc=1; fi
  if [ "$_ax_rc" != 0 ]; then CX_ERROR=$_ax_error; fi
  return "$_ax_rc"
}
cx_cli() {
  _cl_action=$1; shift
  _cl_selection='{"kind":"feature"}'; CX_ARGS='{}'
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --help|-h) printf 'Uso: %s --project PATH --short-name SLUG [--kind feature|project] [opcoes da operacao]\n' "$0"; return 0 ;;
      --purge-backups) CX_ARGS=$(cj_set "$CX_ARGS" /purge_backups true); shift; continue ;;
      --*) [ "$#" -ge 2 ] || { cx_fail "value required: $1" 2; return 2; } ;;
      *) cx_fail "unknown argument: $1" 2; return 2 ;;
    esac
    _cl_flag=$1; _cl_value=$2; shift 2
    case "$_cl_flag" in
      --project|--projeto) _cl_selection=$(cj_set "$_cl_selection" /project "$(cj_quote "$_cl_value")") ;;
      --short-name) _cl_selection=$(cj_set "$_cl_selection" /short_name "$(cj_quote "$_cl_value")") ;;
      --kind) _cl_selection=$(cj_set "$_cl_selection" /kind "$(cj_quote "$_cl_value")") ;;
      --knowledge-db) _cl_selection=$(cj_set "$_cl_selection" /knowledge_db "$(cj_quote "$_cl_value")") ;;
      --source-root) cx_fail 'source root is anchored to the installed script; use a built package' 2; return 2 ;;
      --description|--canonical-project|--channel|--response-source|--block-id|--answer|--resposta-bloqueio|--reason|--motivo|--expected-runtime|--rationale|--observed-model|--field)
        case "$_cl_flag" in --resposta-bloqueio) _cl_key=answer ;; --motivo) _cl_key=reason ;; --observed-model) _cl_key=model ;; *) _cl_key=$(printf '%s' "${_cl_flag#--}" | tr '-' '_') ;; esac
        CX_ARGS=$(cj_set "$CX_ARGS" "/$_cl_key" "$(cj_quote "$_cl_value")") ;;
      --atomic-commit|--value)
        case "$_cl_value" in true|false) _cl_json=$_cl_value ;; *) _cl_json=$(cj_quote "$_cl_value") ;; esac
        CX_ARGS=$(cj_set "$CX_ARGS" /value "$_cl_json") ;;
      --abandoned-owner-pid)
        case "$_cl_value" in ''|*[!0-9]*) cx_fail 'invalid owner PID' 2; return 2 ;; esac
        CX_ARGS=$(cj_set "$CX_ARGS" /abandoned_owner_pid "$_cl_value") ;;
      --expected-hash) _cl_hashes=$(cx_json_default "$CX_ARGS" /expected_hashes '[]'); CX_ARGS=$(cj_set "$CX_ARGS" /expected_hashes "$(cj_append "$_cl_hashes" '' "$(cj_quote "$_cl_value")")") ;;
      --init-aspects|--init-aspectos|--technical-aspects|--init-aspectos-tecnicos|--operational-aspects|--init-aspectos-operacionais)
        case "$_cl_flag" in --init-aspects|--init-aspectos) _cl_key=init_aspects ;; --technical-aspects|--init-aspectos-tecnicos) _cl_key=technical_aspects ;; *) _cl_key=operational_aspects ;; esac
        _cl_json=$(cj_value "$_cl_value") || return; CX_ARGS=$(cj_set "$CX_ARGS" "/$_cl_key" "$_cl_json") ;;
      *) cx_fail "unknown option: $_cl_flag" 2; return 2 ;;
    esac
  done
  _cl_request=$CX_ARGS; CX_ARGS=$_cl_selection
  cx_action select_execution || return
  CX_ARGS=$_cl_request
  case "$_cl_action" in
    context) cx_action context || return; printf '%s\n' "$CX_RESULT"; [ "$(cj_get "$CX_RESULT" /prerequisites_ready)" = true ]; return ;;
    serve) cx_action open_wave || return; printf '%s\n' "$CX_RESULT"; cx_jsonl; return ;;
    controller-resume) CX_RESUME_OPEN=true; cx_action resume || return; printf '%s\n' "$CX_RESULT"; if [ -n "$CX_WAVE" ]; then cx_jsonl; fi; return ;;
    resume|status|bootstrap|optin|abort|handoff|recover|reconcile_governance) CX_RESUME_OPEN=false; cx_action "$_cl_action" || return ;;
    session-resume) cx_acquire && cx_validate && cx_describe && cx_release || return ;;
    phase)
      cx_acquire && cx_validate || return
      _cl_stage=$(cj_get "$CX_DOC" /current_stage); _cl_reference=null
      case "$_cl_stage" in review-task|review-features) ;; *) _cl_flavor=feature; [ "$CX_KIND" != project ] || _cl_flavor=root; cx_rt orchestrator-refs.sh path --orchestrator "$_cl_flavor" --phase "$_cl_stage" || return; _cl_reference=$(cj_quote "$CX_OUTPUT") ;; esac
      CX_RESULT=$(printf '{"stage":%s,"skill_path":%s,"phase_reference":%s,"knowledge_db":%s,"autonomous_ready":false}' "$(cj_quote "$_cl_stage")" "$(cj_quote "$CX_SOURCE/plugins/cstk/skills/$_cl_stage/SKILL.md")" "$_cl_reference" "$(cj_quote "$CSTK_KNOWLEDGE_DB")")
      cx_release || return ;;
    *) cx_fail 'unknown operation' 2; return 2 ;;
  esac
  printf '%s\n' "$CX_RESULT"
  if [ "$_cl_action" = resume ] && [ "$(cj_length "$CX_RESULT" /pending_blocks)" -gt 0 ]; then return 5; fi
}
cx_jsonl() {
  while IFS= read -r _jl_line || [ -n "$_jl_line" ]; do
    _jl_doc=$(cj_value "$_jl_line") || return
    _jl_action=$(cj_get "$_jl_doc" /action) || return
    CX_ARGS=$(cj_delete "$_jl_doc" /action) || return
    if [ "$_jl_action" = tick ]; then
      [ "$(cj_length "$CX_ARGS")" = 0 ] || { cx_fail 'tick accepts no arguments'; return 1; }
      cx_assert_wave || return
      [ ! -s "$CX_STATE/tool-call-ticks.log" ] || { cx_fail 'native ticks observed; manual metering would double count'; return 1; }
      cx_rt state-ondas.sh tool-call-tick --state-dir "$CX_STATE" || return
      CX_RESULT=$(printf '{"tool_calls":%s}' "$CX_OUTPUT"); cx_rt budget.sh check --state-dir "$CX_STATE" || return
    else cx_action "$_jl_action" || return
    fi
    printf '%s\n' "$CX_RESULT"
    [ -n "$CX_WAVE" ] || break
  done
}
