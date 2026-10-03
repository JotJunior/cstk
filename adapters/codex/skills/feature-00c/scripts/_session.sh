#!/bin/sh
# POSIX session/controller implementation. Calls canonical helpers for all state.
set -eu

CX_SOURCE=$(cx_discover "$CX_ENTRY_DIR/context.sh")
CX_RUNTIME=$CX_SOURCE/plugins/cstk/skills/agente-00c-runtime/scripts
CX_PROJECT='' CX_STATE='' CX_SHORT='' CX_KIND=feature CX_CONTEXT='{}'
CX_LOCKED=false CX_PROJECT_LOCK=false CX_WAVE='' CX_STAGE='' CX_MODE=default CX_TERMINAL=review-task
CX_OFFERED='[]' CX_RESULT='{}' CX_ERROR='' CX_ARGS='{}'
unset CLAUDE_CODE_ENABLE_TELEMETRY
CSTK_LIB=$CX_SOURCE/cli/lib CLAUDE_PLUGIN_ROOT=$CX_SOURCE/plugins/cstk
export CSTK_LIB CLAUDE_PLUGIN_ROOT

cx_owner() {
  [ "$CX_LOCKED" = true ] || { cx_fail 'session lock required'; return 1; }
  [ ! -L "$CX_STATE/.lock/owner" ] || { cx_fail 'symlinked lock owner'; return 1; }
  _co_pid=$(sed -n 's/^pid=\([0-9][0-9]*\)$/\1/p' "$CX_STATE/.lock/owner") || return 1
  [ "$_co_pid" = "$$" ] || { cx_fail 'session lock owner changed; refusing mutation or release'; return 1; }
}
# Unlike cx_run, the script name is not forwarded as a runtime argument.
cx_rt() {
  _cr_script=$1; shift
  if [ "$CX_LOCKED" = true ]; then cx_owner || return 1; fi
  if (cd -- "$CX_PROJECT" && sh "$CX_RUNTIME/$_cr_script" "$@") > "$CX_TEMP/result" 2> "$CX_TEMP/error"; then
    CX_OUTPUT=$(cat "$CX_TEMP/result")
  else
    cx_fail "$_cr_script: $(cat "$CX_TEMP/error")"; return 1
  fi
}
cx_state_read() { cx_rt state-rw.sh read --state-dir "$CX_STATE" || return; CX_DOC=$CX_OUTPUT; }
cx_write() { cx_owner || return; printf '%s\n' "$1" | (cd -- "$CX_PROJECT" && sh "$CX_RUNTIME/state-rw.sh" write --state-dir "$CX_STATE") > "$CX_TEMP/result" 2> "$CX_TEMP/error" || { cx_fail "state-rw.sh: $(cat "$CX_TEMP/error")"; return 1; }; }
cx_field() { cx_rt state-rw.sh set --state-dir "$CX_STATE" --field "$1" --value "$2"; }
cx_artifact() {
  _ca_file=$(cx_path "$1") || return
  cx_within "$CX_PROJECT" "$_ca_file" || { cx_fail 'governance path escapes project'; return 1; }
  if [ -f "$_ca_file" ]; then _ca_exists=true; _ca_sha=$(cj_quote "$(cx_sha "$_ca_file")") || return
  else _ca_exists=false; _ca_sha=null
  fi
  printf '{"path":%s,"exists":%s,"sha256":%s}' "$(cj_quote "$_ca_file")" "$_ca_exists" "$_ca_sha"
}
cx_prepare() {
  _cp_brief=$CX_PROJECT/docs/briefing.md
  [ -f "$_cp_brief" ] || _cp_brief=$CX_PROJECT/docs/01-briefing-discovery/briefing.md
  CX_ARTIFACTS=$(printf '{"briefing":%s,"constitution":%s}' "$(cx_artifact "$_cp_brief")" "$(cx_artifact "$CX_PROJECT/docs/constitution.md")") || return
  cj_value "$CX_ARTIFACTS" >/dev/null || return
  CX_STAGES='[]'
  _cp_stages=$(sh "$CX_RUNTIME/pipeline.sh" stages --mode "$CX_MODE") || return
  while IFS= read -r _cp_stage; do
    if [ "$CX_KIND" = feature ]; then
      case "$_cp_stage" in briefing|constitution|review-features|roadmap) continue ;; esac
    fi
    CX_STAGES=$(cj_append "$CX_STAGES" '' "$(cj_quote "$_cp_stage")") || return
  done <<EOF
$_cp_stages
EOF
  _cp_missing='[]'
  if [ "$CX_KIND" = feature ]; then
    for _cp_name in briefing constitution; do
      if [ "$(cj_get "$CX_ARTIFACTS" "/$_cp_name/exists")" != true ]; then _cp_missing=$(cj_append "$_cp_missing" '' "$(cj_quote "$_cp_name")"); fi
    done
  fi
  _cp_state_runtime=true
  if ! sh "$CX_RUNTIME/state-rw.sh" check-dependencies --state-dir "$CX_STATE" >/dev/null 2>&1; then _cp_missing=$(cj_append "$_cp_missing" '' '"state_runtime"'); _cp_state_runtime=false; fi
  _cp_exists=false; [ ! -f "$CX_STATE/state.json" ] && [ ! -f "$CX_STATE/state.db" ] || _cp_exists=true
  _cp_ready=true; [ "$(cj_length "$_cp_missing")" = 0 ] || _cp_ready=false
  CX_CONTEXT=$(printf '{"adapter_version":2,"runtime":"codex","model":null,"kind":%s,"source_root":%s,"runtime_root":%s,"project":%s,"short_name":%s,"state_dir":%s,"state_exists":%s,"artifacts":%s,"stages":%s,"knowledge_db":%s,"knowledge_best_effort":true,"missing_prerequisites":%s,"prerequisites_ready":%s,"autonomous_ready":false}' \
    "$(cj_quote "$CX_KIND")" "$(cj_quote "$CX_SOURCE")" "$(cj_quote "${CX_RUNTIME%/scripts}")" "$(cj_quote "$CX_PROJECT")" "$(cj_quote "$CX_SHORT")" "$(cj_quote "$CX_STATE")" "$_cp_exists" "$CX_ARTIFACTS" "$CX_STAGES" "$(cj_quote "$CSTK_KNOWLEDGE_DB")" "$_cp_missing" "$_cp_ready")
  CX_CONTEXT=$(cj_set "$CX_CONTEXT" /dependencies "$(printf '{"sh":true,"state_runtime":%s}' "$_cp_state_runtime")") || return
  CX_CONTEXT=$(cj_set "$CX_CONTEXT" /implemented_capabilities '["supervised_wave_controller","explicit_optin_capture","precedent_audit","native_hook_discovery","resume_with_human_response","audited_abort","explicit_runtime_handoff","governance_reconciliation","posix_adapter","owned_hook_binding"]') || return
  CX_CONTEXT=$(cj_set "$CX_CONTEXT" /pending_capabilities '["codex_hook_trust_and_coverage","native_end_to_end_validation","claude_cross_review"]')
}
cx_scope() {
  [ -n "$CX_PROJECT" ] && [ -d "$CX_PROJECT" ] || { cx_fail 'select an existing project directory'; return 1; }
  _cs_path=$(cx_path "$CX_STATE") || return
  [ "$_cs_path" = "$CX_STATE" ] && cx_within "$CX_PROJECT" "$_cs_path" || { cx_fail 'state directory escapes project'; return 1; }
  for _cs_name in state.json state.json.sha256 state.db state.db-wal state.db-shm .lock .lock/owner state-history .write-probe .gitignore; do
    [ ! -L "$CX_STATE/$_cs_name" ] || { cx_fail 'symlinked execution control'; return 1; }
  done
  cx_rt path-guard.sh validate-target --projeto-alvo-path "$CX_PROJECT"
}
cx_select() {
  [ "$CX_LOCKED" = false ] || { cx_fail 'close the owned wave before selecting an execution'; return 1; }
  _cs_project=$(cj_get "$CX_ARGS" /project 2>/dev/null || printf '%s' "$CX_PROJECT")
  case "$_cs_project" in /*) ;; *) cx_fail 'project must be an explicit absolute path'; return 1 ;; esac
  _cs_project=$(cx_path "$_cs_project") || return
  [ -z "$CX_PROJECT" ] || [ "$CX_PROJECT" = "$_cs_project" ] || { cx_fail 'server is already bound to another project'; return 1; }
  CX_SHORT=$(cj_get "$CX_ARGS" /short_name) || return
  printf '%s\n' "$CX_SHORT" | LC_ALL=C grep -Eq '^[a-z0-9]+(-[a-z0-9]+)*$' || { cx_fail 'short-name must be kebab-case'; return 1; }
  CX_KIND=$(cj_get "$CX_ARGS" /kind) || return
  case "$CX_KIND" in feature|project) ;; *) cx_fail 'kind must be feature or project'; return 1 ;; esac
  CX_PROJECT=$_cs_project
  if [ "$CX_KIND" = feature ]; then CX_STATE=$CX_PROJECT/.claude/feature-00c-state/$CX_SHORT; CX_TERMINAL=review-task
  else CX_STATE=$CX_PROJECT/.claude/agente-00c-state; CX_TERMINAL=review-features
  fi
  CSTK_KNOWLEDGE_DB=$(cx_default "$CX_ARGS" /knowledge_db "${CSTK_KNOWLEDGE_DB:-${HOME:-/tmp}/.claude/cstk/knowledge.db}")
  case "$CSTK_KNOWLEDGE_DB" in /*) ;; *) cx_fail 'knowledge_db must be absolute'; return 1 ;; esac
  CSTK_KNOWLEDGE_DB=$(cx_path "$CSTK_KNOWLEDGE_DB") || return
  [ ! -d "$CSTK_KNOWLEDGE_DB" ] && ! cx_within "$CX_STATE" "$CSTK_KNOWLEDGE_DB" || { cx_fail 'derived index must be outside canonical state'; return 1; }
  AGENTE_00C_STATE_DIR=$CX_STATE; export AGENTE_00C_STATE_DIR CSTK_KNOWLEDGE_DB
  cx_scope || return
  cx_prepare || return
  CX_RESULT=$CX_CONTEXT
}
cx_acquire() {
  cx_scope || return
  [ "$CX_LOCKED" = false ] || { cx_fail 'nested session lock'; return 1; }
  _ca_abandoned=$(cx_default "$CX_ARGS" /abandoned_owner_pid '')
  set -- acquire --state-dir "$CX_STATE" --owner-pid "$$"
  if [ -n "$_ca_abandoned" ]; then
    [ ! -L "$CX_STATE/.lock/owner" ] || return 1
    _ca_pid=$(sed -n 's/^pid=\([0-9][0-9]*\)$/\1/p' "$CX_STATE/.lock/owner") || return
    [ "$_ca_pid" = "$_ca_abandoned" ] && cx_dead "$_ca_pid" || { cx_fail 'abandoned owner must match and be proven dead'; return 1; }
    set -- "$@" --force-abandoned
  fi
  cx_rt state-lock.sh "$@" || return
  CX_LOCKED=true
}
cx_release() {
  [ "$CX_LOCKED" = true ] || return 0
  cx_owner || return
  cx_rt state-lock.sh release --state-dir "$CX_STATE" || return
  CX_LOCKED=false
  cx_unbind
}
cx_unbind() {
  if [ "$CX_PROJECT_LOCK" = true ]; then
    _cu_dir=$CX_PROJECT/.claude/.cstk-codex-wave-lock
    _cu_doc=$(cx_read "$_cu_dir/owner.json") || return
    [ "$(cj_get "$_cu_doc" /pid)" = "$$" ] && [ "$(cj_get "$_cu_doc" /state_dir)" = "$CX_STATE" ] || { cx_fail 'project wave owner changed'; return 1; }
    rm -- "$_cu_dir/owner.json" && rmdir -- "$_cu_dir" || return
    CX_PROJECT_LOCK=false
  fi
}
cx_bind() {
  _cb_dir=$CX_PROJECT/.claude/.cstk-codex-wave-lock
  [ ! -L "$_cb_dir" ] || { cx_fail 'symlinked wave binding'; return 1; }
  if [ -d "$_cb_dir" ]; then
    _cb_old=$(cx_read "$_cb_dir/owner.json") || return
    _cb_pid=$(cx_default "$CX_ARGS" /abandoned_owner_pid '')
    [ -n "$_cb_pid" ] && [ "$(cj_get "$_cb_old" /pid)" = "$_cb_pid" ] && [ "$(cj_get "$_cb_old" /state_dir)" = "$CX_STATE" ] && cx_dead "$_cb_pid" || { cx_fail 'another or abandoned Codex wave owns this project; recover explicitly'; return 1; }
    rm -- "$_cb_dir/owner.json" && rmdir -- "$_cb_dir" || return
  fi
  mkdir -- "$_cb_dir" || { cx_fail 'another Codex wave owns this project'; return 1; }
  _cb_binding=$(printf '{"pid":%s,"project":%s,"state_dir":%s}' "$$" "$(cj_quote "$CX_PROJECT")" "$(cj_quote "$CX_STATE")")
  cx_atomic "$_cb_dir/owner.json" "$_cb_binding" || { rmdir -- "$_cb_dir"; return 1; }
  CX_PROJECT_LOCK=true
}
cx_validate() {
  # parameters: permit open wave, terminal, other runtime, skip governance
  cx_owner || return
  cx_rt state-validate.sh --state-dir "$CX_STATE" || return
  cx_state_read || return
  [ "${3:-false}" = true ] || [ "$(cx_default "$CX_DOC" /execution_provenance/runtime '')" = codex ] || { cx_fail 'runtime mismatch; explicit handoff required'; return 1; }
  [ "$(cx_path "$(cj_get "$CX_DOC" /execution/target_project_path)")" = "$CX_PROJECT" ] || { cx_fail 'execution belongs to another project'; return 1; }
  if [ "$CX_KIND" = feature ]; then _cv_identity=$(cx_default "$CX_DOC" /short_name '')
  else _cv_identity=$(cx_default "$CX_DOC" /execution/canonical_project '')
  fi
  [ "$_cv_identity" = "$CX_SHORT" ] || { cx_fail 'execution identity mismatch'; return 1; }
  _cv_status=$(cj_get "$CX_DOC" /execution/status)
  case "$_cv_status" in em_andamento|aguardando_humano) ;; *) [ "${2:-false}" = true ] || { cx_fail 'terminal execution cannot be resumed'; return 1; } ;; esac
  _cv_waves=$(cj_each "$(cx_json_default "$CX_DOC" /waves '[]')")
  if [ "${1:-false}" != true ]; then
    while IFS= read -r _cv_wave; do
      [ -z "$_cv_wave" ] || [ "$(cx_default "$_cv_wave" /finished_at null)" != null ] || { cx_fail 'open wave requires explicit recovery'; return 1; }
    done <<EOF
$_cv_waves
EOF
  fi
  cx_rt state-rw.sh sha256-verify --state-dir "$CX_STATE" || return
  if [ "$CX_KIND" = project ]; then
    cx_rt roadmap-mode.sh is-enabled --state-dir "$CX_STATE" || return
    CX_MODE=default; [ "$CX_OUTPUT" != true ] || CX_MODE=roadmap
  fi
  cx_prepare || return
  [ "${4:-false}" != true ] || return 0
  for _cv_name in briefing constitution; do
    if [ "$CX_KIND" = feature ]; then _cv_old=$(cx_json_default "$CX_DOC" "/prerequisites/$_cv_name" null)
    else _cv_old=$(cx_json_default "$CX_DOC" "/codex_governance/$_cv_name" null); [ "$_cv_old" != null ] || continue
    fi
    _cv_new=$(cj_value "$CX_ARTIFACTS" "/$_cv_name")
    _cv_path=$(cj_get "$_cv_old" /path) || return
    case "$_cv_path" in /*) ;; *) _cv_path=$CX_PROJECT/$_cv_path ;; esac
    [ "$(cx_path "$_cv_path")" = "$(cj_get "$_cv_new" /path)" ] && [ "$(cj_get "$_cv_old" /sha256)" = "$(cj_get "$_cv_new" /sha256)" ] || { cx_fail "$_cv_name drift requires reconciliation"; return 1; }
  done
}
cx_pending() {
  CX_PENDING='[]'
  _cp_blocks=$(cj_each "$(cx_json_default "$CX_DOC" /human_blocks '[]')")
  while IFS= read -r _cp_block; do
    if [ -n "$_cp_block" ] && [ "$(cj_get "$_cp_block" /status)" = aguardando ]; then CX_PENDING=$(cj_append "$CX_PENDING" '' "$_cp_block"); fi
  done <<EOF
$_cp_blocks
EOF
}
cx_describe() {
  cx_state_read || return
  cx_pending || return
  _cd_terminal=false
  case "$(cj_get "$CX_DOC" /execution/status)" in concluida|abortada) _cd_terminal=true ;; esac
  CX_RESULT=$(printf '{"execution_id":%s,"kind":%s,"short_name":%s,"status":%s,"current_stage":%s,"next_instruction":%s,"execution_provenance":%s,"pending_blocks":%s,"waves_total":%s,"terminal":%s,"knowledge_db":%s,"autonomous_ready":false}' \
    "$(cj_value "$CX_DOC" /execution/id)" "$(cj_quote "$CX_KIND")" "$(cj_quote "$CX_SHORT")" "$(cj_value "$CX_DOC" /execution/status)" "$(cj_value "$CX_DOC" /current_stage)" "$(cx_json_default "$CX_DOC" /next_instruction null)" "$(cx_json_default "$CX_DOC" /execution_provenance null)" "$CX_PENDING" "$(cj_length "$(cx_json_default "$CX_DOC" /waves '[]')")" "$_cd_terminal" "$(cj_quote "$CSTK_KNOWLEDGE_DB")")
  _cd_open='[]'; _cd_waves=$(cj_each "$(cx_json_default "$CX_DOC" /waves '[]')")
  while IFS= read -r _cd_wave; do
    if [ -n "$_cd_wave" ] && [ "$(cx_default "$_cd_wave" /finished_at null)" = null ]; then _cd_open=$(cj_append "$_cd_open" '' "$_cd_wave"); fi
  done <<EOF
$_cd_waves
EOF
  CX_RESULT=$(cj_set "$CX_RESULT" /open_waves "$_cd_open")
}
cx_event() {
  cx_state_read || return
  _ce_events=$(cx_json_default "$CX_DOC" /events '[]')
  _ce_events=$(cj_append "$_ce_events" '' "$(printf '{"event_type":%s,"timestamp":%s,"description":%s}' "$(cj_quote "$1")" "$(cj_quote "$(cx_now)")" "$(cj_quote "$2")")") || return
  cx_field .events "$_ce_events"
}
cx_operator() { [ "$(cj_length "$(cj_quote "$1")")" -ge 10 ] || { cx_fail 'reference to actual operator response required'; return 1; }; }
cx_lifecycle_decision() {
  [ "$(cj_length "$(cj_quote "$2")")" -ge 20 ] || { cx_fail 'concrete rationale of at least 20 characters required'; return 1; }
  cx_state_read || return
  cx_rt state-decisions.sh register --state-dir "$CX_STATE" --agente codex-lifecycle-orchestrator --etapa "$(cj_get "$CX_DOC" /current_stage)" --contexto "Operacao explicita de ciclo de vida: $1" --opcoes "[$(cj_quote "$1"),\"preservar-estado\"]" --escolha "$1" --justificativa "$2" --score 2 --referencias "${3:-[]}" || return
  CX_DECISION=$CX_OUTPUT
}

cx_bootstrap() {
  cx_prepare || return
  [ "$(cj_get "$CX_CONTEXT" /prerequisites_ready)" = true ] || { cx_fail 'missing prerequisites'; return 1; }
  [ ! -f "$CX_STATE/state.json" ] && [ ! -f "$CX_STATE/state.db" ] || { cx_fail 'execution already exists; use resume'; return 1; }
  _cb_description=$(cj_get "$CX_ARGS" /description) || return
  _cb_identity=$(cj_get "$CX_ARGS" /canonical_project) || return
  [ "$(cx_text_length "$_cb_description")" -ge 10 ] && [ "$(cx_text_length "$_cb_identity")" -gt 0 ] || { cx_fail 'description and canonical project identity required'; return 1; }
  _cb_id="codex-$(cx_now)-$$-$(basename "$CX_TEMP")"
  set -- init --state-dir "$CX_STATE" --execucao-id "$_cb_id" --projeto-alvo-path "$CX_PROJECT" --descricao "$_cb_description" --canonical-project "$_cb_identity" --runtime codex --toolkit-version "$(cat "$CX_SOURCE/cli/VERSION")"
  if [ "$CX_KIND" = project ]; then
    [ "$_cb_identity" = "$CX_SHORT" ] || { cx_fail 'project slug must match canonical identity'; return 1; }
    _cb_feature=$(cx_path "$CX_PROJECT/docs/specs/$CX_SHORT") || return
    cx_within "$CX_PROJECT" "$_cb_feature" || { cx_fail 'artifact directory escapes target'; return 1; }
    mkdir -p -- "$_cb_feature" || return
  else
    _cb_constitution=$(cj_get "$CX_ARTIFACTS" /constitution/path)
    _cb_version=$(sed -n 's/^\*\*Version\*\*:[[:space:]]*\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\).*$/\1/p' "$_cb_constitution" | head -n 1)
    [ -n "$_cb_version" ] || { cx_fail 'constitution requires **Version**: X.Y.Z'; return 1; }
    set -- "$@" --short-name "$CX_SHORT" --briefing-path "$(cj_get "$CX_ARTIFACTS" /briefing/path)" --briefing-sha256 "$(cj_get "$CX_ARTIFACTS" /briefing/sha256)" --constitution-path "$_cb_constitution" --constitution-sha256 "$(cj_get "$CX_ARTIFACTS" /constitution/sha256)" --constitution-version "$_cb_version"
  fi
  if cj_get "$CX_ARGS" /model >/dev/null 2>&1; then set -- "$@" --observed-model "$(cj_get "$CX_ARGS" /model)"; fi
  cx_rt state-rw.sh "$@" || return
  cx_validate || return
  CX_RESULT=$CX_DOC
}
cx_optin() {
  cx_validate || return
  _ci_field=$(cx_default "$CX_ARGS" /field atomic_commit)
  _ci_channel=$(cj_get "$CX_ARGS" /channel) || return
  _ci_source=$(cj_get "$CX_ARGS" /response_source) || return
  _ci_value=$(cj_get "$CX_ARGS" /value) || return
  cx_operator "$_ci_source" || return
  case "$_ci_channel" in structured|prose) ;; *) cx_fail 'observed response channel required'; return 1 ;; esac
  case "$_ci_field" in
    atomic_commit|roadmap_mode) [ "$(cj_type "$CX_ARGS" /value)" = boolean ] || { cx_fail 'boolean opt-in required'; return 1; } ;;
    delivery_tier) case "$_ci_value" in local|internal-network|cloud-internal|cloud-public) ;; *) cx_fail 'invalid delivery tier'; return 1 ;; esac ;;
    *) cx_fail 'unknown opt-in field'; return 1 ;;
  esac
  [ "$_ci_field" = atomic_commit ] || [ "$CX_KIND" = project ] || { cx_fail 'project opt-in requires project execution'; return 1; }
  _ci_responses=$(cx_json_default "$CX_DOC" /optin_responses '[]')
  _ci_each=$(cj_each "$_ci_responses")
  while IFS= read -r _ci_previous; do
    if [ -n "$_ci_previous" ] && [ "$(cj_get "$_ci_previous" /field)" = "$_ci_field" ]; then
      [ "$(cj_get "$_ci_previous" /applied_value)" = "$_ci_value" ] || { cx_fail 'opt-in already resolved; explicit reconciliation required'; return 1; }
      CX_RESULT=$_ci_previous; return 0
    fi
  done <<EOF
$_ci_each
EOF
  [ "$(cj_length "$(cx_json_default "$CX_DOC" /waves '[]')")" = 0 ] || { cx_fail 'initial opt-ins must precede first wave'; return 1; }
  case "$_ci_field" in
    atomic_commit) cx_rt commit-mode.sh set-enabled --state-dir "$CX_STATE" --value "$_ci_value" || return ;;
    roadmap_mode) cx_rt roadmap-mode.sh set-enabled --state-dir "$CX_STATE" --value "$_ci_value" || return ;;
    delivery_tier) cx_rt delivery-tier.sh set --state-dir "$CX_STATE" --value "$_ci_value" --allow-downgrade || return ;;
  esac
  CX_RESULT=$(printf '{"field":%s,"channel":%s,"outcome":"accepted","applied_value":%s,"recorded_at":%s,"reason":null,"response_source":%s}' "$(cj_quote "$_ci_field")" "$(cj_quote "$_ci_channel")" "$(cj_quote "$_ci_value")" "$(cj_quote "$(cx_now)")" "$(cj_quote "$_ci_source")")
  _ci_responses=$(cj_append "$_ci_responses" '' "$CX_RESULT") || return
  cx_field .optin_responses "$_ci_responses"
}
cx_assert_wave() {
  cx_owner || return
  [ -n "$CX_WAVE" ] || { cx_fail 'no owned open wave'; return 1; }
  cx_state_read || return
  [ "$(cj_get "$CX_DOC" /current_stage)" = "$CX_STAGE" ] && [ "$(cj_get "$CX_DOC" /waves/-1/id)" = "$CX_WAVE" ] && [ "$(cx_default "$CX_DOC" /waves/-1/finished_at null)" = null ] || { cx_fail 'wave changed outside controller'; return 1; }
}
cx_wave_open() {
  cx_validate || return
  cx_pending || return
  [ "$(cj_length "$CX_PENDING")" = 0 ] || { cx_fail 'pending human block must be answered'; return 1; }
  _cw_feature=$(cx_path "$CX_PROJECT/docs/specs/$CX_SHORT") || return
  cx_within "$CX_PROJECT" "$_cw_feature" || { cx_fail 'feature directory escapes project'; return 1; }
  CX_STAGE=$(cj_get "$CX_DOC" /current_stage)
  _cw_stages=$(cj_each "$CX_STAGES")
  printf '%s\n' "$_cw_stages" | grep -Fx "$(cj_quote "$CX_STAGE")" >/dev/null || { cx_fail 'phase outside pipeline'; return 1; }
  CX_TERMINAL=$(cj_get "$CX_STAGES" /-1)
  cx_bind || return
  for _cw_script in cycles circular drift retro; do
    _cw_operation=check; [ "$_cw_script" != circular ] || _cw_operation=detect
    cx_rt "$_cw_script.sh" "$_cw_operation" --state-dir "$CX_STATE" || return
  done
  cx_rt state-ondas.sh start --state-dir "$CX_STATE" || return
  CX_WAVE=$CX_OUTPUT
  cx_atomic "$CX_PROJECT/.claude/.cstk-codex-wave-lock/owner.json" "$(cj_set "$(cx_read "$CX_PROJECT/.claude/.cstk-codex-wave-lock/owner.json")" /wave_id "$(cj_quote "$CX_WAVE")")" || return
  cx_rt cycles.sh tick --state-dir "$CX_STATE" || return
  cx_rt budget.sh check --state-dir "$CX_STATE" || return
  _cw_skill=$CX_SOURCE/plugins/cstk/skills/$CX_STAGE/SKILL.md
  [ -f "$_cw_skill" ] || [ "$CX_STAGE" = roadmap ] || { cx_fail 'shared stage skill missing'; return 1; }
  _cw_reference=null
  case "$CX_STAGE" in review-task|review-features) ;; *)
    _cw_flavor=feature; [ "$CX_KIND" != project ] || _cw_flavor=root
    cx_rt orchestrator-refs.sh path --orchestrator "$_cw_flavor" --phase "$CX_STAGE" || return
    _cw_reference=$(cj_quote "$CX_OUTPUT") ;;
  esac
  _cw_recall_status=not_requested; _cw_precedents=null; CX_OFFERED='[]'
  case "$CX_STAGE" in specify|plan)
    _cw_terms=$(cj_get "$CX_DOC" /execution/target_project_description)
    if (cd -- "$CX_PROJECT" && cx_timeout 15 sh "$CX_SOURCE/cli/cstk" recall --context "$_cw_terms" --exclude-feature "$CX_SHORT" --limit 4 --include-source-ids) > "$CX_TEMP/recall" 2> "$CX_TEMP/recall-error"; then _cw_recall_status=queried
    else _cw_recall_status=degraded
    fi
    [ ! -s "$CX_TEMP/recall-error" ] || _cw_recall_status=degraded
    _cw_precedents=$(cj_quote "$(cat "$CX_TEMP/recall")")
    # Match only the generated suffix of an actual rendered entry.
    _cw_sources=$(sed -n 's/^- \*\*\[[^]]*\]\*\* .* \[source: \([^]]*\)\]$/\1/p' "$CX_TEMP/recall")
    while IFS= read -r _cw_source; do [ -z "$_cw_source" ] || CX_OFFERED=$(cj_append "$CX_OFFERED" '' "$(cj_quote "$_cw_source")"); done <<EOF
$_cw_sources
EOF
    cx_event recall_consulted "$(printf '{"status":%s,"sources":%s}' "$(cj_quote "$_cw_recall_status")" "$CX_OFFERED")" || return
    cx_briefing_gate || return
    ;;
  esac
  if [ "$CX_KIND" = project ] && [ "$CX_STAGE" = constitution ]; then
    _cw_rc=0
    (cd -- "$CX_PROJECT" && sh "$CX_RUNTIME/pipeline.sh" constitution-conflict --projeto-alvo-path "$CX_PROJECT" --feature-dir "$_cw_feature") > "$CX_TEMP/conflict" 2>&1 || _cw_rc=$?
    case "$_cw_rc" in
      0) ;; 1|2)
        if ! cx_rt pipeline.sh require-blockade-resolved --state-dir "$CX_STATE" --etapa constitution; then
          CX_ARGS='{"context":"Conflito entre constitution global e do projeto detectado pelo pre-flight canonico","question":"Escolha atualizar-global-via-bump-SemVer, criar-feature-delta-com-sync-impact-report ou abortar-feature-sem-principios-proprios.","rationale":"A constitution existente exige resposta humana antes de executar a skill.","options":["atualizar-global-via-bump-SemVer","criar-feature-delta-com-sync-impact-report","abortar-feature-sem-principios-proprios"]}'
          cx_block || return
          cx_fail 'constitution conflict requires an authorized human response'; return 1
        fi ;;
      *) cx_fail 'constitution pre-flight failed'; return 1 ;;
    esac
  fi
  [ "$CX_STAGE" = roadmap ] || cx_rt state-ondas.sh record-skill --state-dir "$CX_STATE" --skill "$CX_STAGE" || return
  _cw_orchestrator=agente-00c-feature-orchestrator.md; [ "$CX_KIND" != project ] || _cw_orchestrator=agente-00c-orchestrator.md
  _cw_skill_json=$(cj_quote "$_cw_skill"); [ "$CX_STAGE" != roadmap ] || _cw_skill_json=null
  CX_RESULT=$(printf '{"execution_id":%s,"stage":%s,"skill_path":%s,"phase_reference":%s,"orchestrator_path":%s,"runtime_root":%s,"feature_dir":%s,"knowledge_db":%s,"precedents":%s,"recall_status":%s,"wave_id":%s,"execution_mode":"supervised","metering":"owned_wave","precedent_sources":%s,"controller_pid":%s,"autonomous_ready":false}' \
    "$(cj_value "$CX_DOC" /execution/id)" "$(cj_quote "$CX_STAGE")" "$_cw_skill_json" "$_cw_reference" "$(cj_quote "$CX_SOURCE/plugins/cstk/agents/$_cw_orchestrator")" "$(cj_quote "${CX_RUNTIME%/scripts}")" "$(cj_quote "$_cw_feature")" "$(cj_quote "$CSTK_KNOWLEDGE_DB")" "$_cw_precedents" "$(cj_quote "$_cw_recall_status")" "$(cj_quote "$CX_WAVE")" "$CX_OFFERED" "$$")
  if [ "$CX_KIND" = project ]; then cx_rt delivery-tier.sh get --state-dir "$CX_STATE" || return; CX_RESULT=$(cj_set "$CX_RESULT" /delivery_tier "$(cj_quote "$CX_OUTPUT")"); fi
}
cx_briefing_gate() {
  cx_rt briefing-items.sh list-high --briefing "$(cj_get "$CX_ARTIFACTS" /briefing/path)" || return
  _bg_lines=$CX_OUTPUT; _bg_status=$(printf '%s\n' "$_bg_lines" | tail -n 1 | cut -f2)
  [ "$_bg_status" = ok ] || return 0
  _bg_lines=$(printf '%s\n' "$_bg_lines" | sed '$d')
  while IFS="$(printf '\t')" read -r _bg_key _bg_item _bg_dimension; do
    [ -n "$_bg_key" ] || continue
    cx_rt bloqueios.sh list --state-dir "$CX_STATE" --status respondido --chave-assunto "briefing-item:$_bg_key" || return
    if [ -z "$CX_OUTPUT" ]; then
      CX_ARGS=$(printf '{"context":%s,"question":%s,"rationale":"Item de impacto Alto exige resposta do operador antes da fase.","subject":%s}' "$(cj_quote "Item Alto do briefing ainda sem decisao: $_bg_item")" "$(cj_quote "Item Alto do briefing: $_bg_item ($_bg_dimension). Como decidir?")" "$(cj_quote "briefing-item:$_bg_key")")
      cx_block || return
      cx_fail 'high-impact briefing item requires an operator response'; return 1
    fi
  done <<EOF
$_bg_lines
EOF
}
cx_decision() {
  cx_assert_wave || return
  _cd_agent=codex-feature-orchestrator; [ "$CX_KIND" != project ] || _cd_agent=codex-project-orchestrator
  set -- register --state-dir "$CX_STATE" --agente "$_cd_agent" --etapa "$CX_STAGE" --contexto "$(cj_get "$CX_ARGS" /context)" --opcoes "$(cj_value "$CX_ARGS" /options)" --escolha "$(cj_get "$CX_ARGS" /choice)" --justificativa "$(cj_get "$CX_ARGS" /rationale)" --score "$(cx_default "$CX_ARGS" /score 2)" --classe "$(cx_default "$CX_ARGS" /decision_class operacional)"
  for _cd_pair in evidence:evidencia axis:eixo consent:consentimento references:referencias; do
    _cd_key=${_cd_pair%%:*}; _cd_flag=${_cd_pair#*:}
    if cj_get "$CX_ARGS" "/$_cd_key" >/dev/null 2>&1; then
      if [ "$_cd_key" = references ]; then _cd_value=$(cj_value "$CX_ARGS" "/$_cd_key"); else _cd_value=$(cj_get "$CX_ARGS" "/$_cd_key"); fi
      set -- "$@" "--$_cd_flag" "$_cd_value"
    fi
  done
  cx_rt state-decisions.sh "$@" || return
  CX_DECISION=$CX_OUTPUT; CX_RESULT=$(printf '{"decision_id":%s}' "$(cj_quote "$CX_DECISION")")
}
cx_block() {
  _cb_saved=$CX_ARGS
  _cb_options=$(cx_json_default "$CX_ARGS" /options '["bloqueio-humano-fonte-ausente"]')
  _cb_choice=bloqueio-humano-fonte-ausente
  [ "$(cx_json_default "$CX_ARGS" /options null)" = null ] || _cb_choice=pause-humano
  CX_ARGS=$(printf '{"context":%s,"options":%s,"choice":%s,"rationale":%s,"score":0}' "$(cj_value "$_cb_saved" /context)" "$_cb_options" "$(cj_quote "$_cb_choice")" "$(cj_value "$_cb_saved" /rationale)")
  cx_decision || return
  set -- register --state-dir "$CX_STATE" --decisao-id "$CX_DECISION" --pergunta "$(cj_get "$_cb_saved" /question)" --contexto-para-resposta "$(cj_get "$_cb_saved" /context)"
  if cj_get "$_cb_saved" /subject >/dev/null 2>&1; then set -- "$@" --chave-assunto "$(cj_get "$_cb_saved" /subject)"; fi
  cx_rt bloqueios.sh "$@" || return
  _cb_id=$CX_OUTPUT
  cx_close bloqueio_humano "Responder bloqueio humano e continuar etapa $CX_STAGE" false || return
  CX_ARGS=$_cb_saved; CX_RESULT=$(printf '{"block_id":%s}' "$(cj_quote "$_cb_id")")
}
cx_backup() {
  cx_owner || return
  cx_state_read || return
  _cb_directory=$(cx_path "$CX_STATE/backups") || return
  cx_within "$CX_STATE" "$_cb_directory" && [ ! -L "$CX_STATE/backups" ] || { cx_fail 'backup directory escapes execution scope'; return 1; }
  mkdir -p -- "$_cb_directory" || return
  _cb_name=${1:-$CX_WAVE}
  case "$_cb_name" in ''|*[!a-zA-Z0-9_-]*) cx_fail 'invalid backup name'; return 1 ;; esac
  _cb_target=$_cb_directory/$_cb_name.json
  [ ! -L "$_cb_target" ] || { cx_fail 'backup file is a symlink'; return 1; }
  [ ! -f "$_cb_target" ] || return 0
  printf '%s\n' "$CX_DOC" | sh "$CX_RUNTIME/secrets-filter.sh" for-backup --wave-number "$(cj_length "$(cx_json_default "$CX_DOC" /waves '[]')")" --env-file "$CX_PROJECT/.env" > "$CX_TEMP/backup" || return
  cx_atomic "$_cb_target" "$(cat "$CX_TEMP/backup")"
}
cx_after_close() {
  _ac_status=ingested
  if ! (cd -- "$CX_PROJECT" && cx_timeout 30 sh "$CX_SOURCE/cli/cstk" recall --ingest --state-dir "$CX_STATE") > "$CX_TEMP/ingest" 2> "$CX_TEMP/ingest-error"; then _ac_status=degraded; fi
  [ ! -s "$CX_TEMP/ingest-error" ] || _ac_status=degraded
  if [ "$_ac_status" = degraded ]; then cx_event knowledge_ingest_degraded 'Indice derivado indisponivel; estado canonico preservado.' || return; fi
  cx_state_read || return
  _ac_flavor=feature-00c; _ac_report=$CX_STATE/feature-00c-report.md
  [ "$CX_KIND" != project ] || { _ac_flavor=agente-00c; _ac_report=$CX_PROJECT/.claude/agente-00c-report.md; }
  [ ! -L "$_ac_report" ] || { cx_fail 'symlinked report path'; return 1; }
  _ac_final=--parcial; [ "$(cj_get "$CX_DOC" /execution/status)" != concluida ] || _ac_final=--final
  cx_rt report.sh emit --flavor "$_ac_flavor" --state-dir "$CX_STATE" --short-name "$CX_SHORT" "$_ac_final" --env-file "$CX_PROJECT/.env" || return
  CX_RESULT=$(printf '{"wave_id":%s,"current_stage":%s,"status":%s,"knowledge_status":%s,"report":%s,"schedule_intent":"none","autonomous_ready":false}' "$(cj_quote "${CX_FINISHED_WAVE:-$CX_WAVE}")" "$(cj_value "$CX_DOC" /current_stage)" "$(cj_value "$CX_DOC" /execution/status)" "$(cj_quote "$_ac_status")" "$(cj_quote "$CX_OUTPUT")")
}
cx_close() {
  cx_assert_wave || return
  cx_backup || return
  _cc_advance=${3:-false}
  set -- end --state-dir "$CX_STATE" --motivo-termino "$1" --next-instruction "$2"
  if [ "$_cc_advance" = true ]; then set -- "$@" --advance --terminal-phase "$CX_TERMINAL" --add-etapa "$CX_STAGE" --mode "$CX_MODE"; fi
  cx_rt state-ondas.sh "$@" || return
  CX_FINISHED_WAVE=$CX_WAVE; CX_WAVE=
  cx_after_close
}

cx_complete() {
  _cc_request=$CX_ARGS
  cx_assert_wave || return
  cx_pending || return
  [ "$(cj_length "$CX_PENDING")" = 0 ] || { cx_fail 'pending human block prevents completion'; return 1; }
  cx_validate true || return
  cx_rt budget.sh check --state-dir "$CX_STATE" || return
  _cc_used=$(cx_json_default "$CX_ARGS" /used_sources '[]')
  _cc_sources=$(cj_each "$_cc_used")
  _cc_offered=$(cj_each "$CX_OFFERED")
  while IFS= read -r _cc_source; do
    [ -z "$_cc_source" ] || printf '%s\n' "$_cc_offered" | grep -Fx "$_cc_source" >/dev/null || { cx_fail 'precedent not returned in this wave'; return 1; }
  done <<EOF
$_cc_sources
EOF
  _cc_paths=$(cj_value "$CX_ARGS" /evidence_paths) || return
  [ "$(cj_length "$_cc_paths")" -gt 0 ] || { cx_fail 'completion requires persisted evidence'; return 1; }
  _cc_paths=$(cj_each "$_cc_paths"); _cc_evidence='[]'; _cc_evidence_text=
  while IFS= read -r _cc_raw; do
    [ -n "$_cc_raw" ] || continue
    _cc_raw=$(cj_get "$_cc_raw")
    case "$_cc_raw" in /*) _cc_path=$_cc_raw ;; *) _cc_path=$CX_PROJECT/$_cc_raw ;; esac
    _cc_path=$(cx_path "$_cc_path") || return
    cx_within "$CX_PROJECT" "$_cc_path" && [ -f "$_cc_path" ] || { cx_fail 'evidence must be a file within target project'; return 1; }
    _cc_relative=${_cc_path#"$CX_PROJECT"/}
    case "$_cc_relative" in .git|.git/*|.claude|.claude/*|.codex|.codex/*) cx_fail 'execution controls cannot be completion evidence'; return 1 ;; esac
    _cc_record="$_cc_relative sha256=$(cx_sha "$_cc_path")"
    _cc_evidence=$(cj_append "$_cc_evidence" '' "$(cj_quote "$_cc_record")")
    _cc_evidence_text="$_cc_evidence_text; $_cc_record"
  done <<EOF
$_cc_paths
EOF
  _cc_feature=$CX_PROJECT/docs/specs/$CX_SHORT
  cx_rt pipeline.sh detect-completion --feature-dir "$_cc_feature" --stage "$CX_STAGE" --projeto-alvo-path "$CX_PROJECT" --mode "$CX_MODE" || return
  if [ "$CX_STAGE" = clarify ] && [ "$CX_KIND" = feature ]; then cx_rt feature-00c-preflight.sh check --state-dir "$CX_STATE" || return; fi
  case "$CX_STAGE" in execute-task|review-task)
    if grep -Eq '^[[:space:]]*-[[:space:]]*\[[ ~!]\]' "$_cc_feature/tasks.md"; then cx_fail 'unfinished or blocked tasks prevent completion'; return 1; fi
    cx_rt state-ondas.sh reconcile-tasks --state-dir "$CX_STATE" --tasks-md "$_cc_feature/tasks.md" || return ;;
  esac
  [ "$CX_STAGE" != review-task ] || cx_rt pipeline.sh detect-completion --feature-dir "$_cc_feature" --stage converge || return
  _cc_refs=$_cc_used
  _cc_records=$(cj_each "$_cc_evidence")
  while IFS= read -r _cc_record; do [ -z "$_cc_record" ] || _cc_refs=$(cj_append "$_cc_refs" '' "$_cc_record"); done <<EOF
$_cc_records
EOF
  CX_ARGS=$(printf '{"context":%s,"options":["concluir-etapa","continuar-etapa"],"choice":"concluir-etapa","rationale":%s,"score":3,"evidence":%s,"references":%s}' "$(cj_quote "Verificar conclusao da etapa $CX_STAGE pela pipeline canonica")" "$(cj_value "$_cc_request" /rationale)" "$(cj_quote "Arquivos lidos: $_cc_evidence_text")" "$_cc_refs")
  cx_decision || return
  _cc_decision=$CX_DECISION
  if [ "$(cj_length "$_cc_used")" -gt 0 ]; then cx_event recall_used "$(printf '{"decision_id":%s,"sources":%s}' "$(cj_quote "$_cc_decision")" "$_cc_used")" || return; fi
  cx_rt cycles.sh reset --state-dir "$CX_STATE" || return
  if [ "$CX_KIND" = project ]; then
    case "$CX_STAGE" in briefing|constitution)
      cx_prepare || return
      _cc_info=$(cj_value "$CX_ARTIFACTS" "/$CX_STAGE")
      [ "$(cj_get "$_cc_info" /exists)" = true ] || { cx_fail 'root governance artifact required before advancing'; return 1; }
      cx_state_read || return
      _cc_governance=$(cj_set "$(cx_json_default "$CX_DOC" /codex_governance '{}')" "/$CX_STAGE" "$_cc_info") || return
      cx_field .codex_governance "$_cc_governance" || return ;;
    esac
  fi
  if [ "$CX_STAGE" = "$CX_TERMINAL" ]; then
    cx_backup || return
    cx_rt state-ondas.sh end --state-dir "$CX_STATE" --motivo-termino concluido --add-etapa "$CX_STAGE" || return
    CX_FINISHED_WAVE=$CX_WAVE; CX_WAVE=
    cx_rt state-rw.sh set --state-dir "$CX_STATE" --field .execution.status --value '"concluida"' --field .execution.termination_reason --value '"concluido"' --field .execution.finished_at --value "$(cj_quote "$(cx_now)")" --field .current_stage --value '"concluida"' --field .next_instruction --value '"Execucao concluida — nenhuma proxima etapa."' || return
    cx_after_close || return
  else cx_close etapa_concluida_avancando "Continuar pipeline depois da etapa $CX_STAGE" true || return
  fi
  CX_ARGS=$_cc_request
}
cx_recover() {
  cx_validate true || return
  _cr_waves=$(cx_json_default "$CX_DOC" /waves '[]')
  if [ "$(cj_length "$_cr_waves")" = 0 ] || [ "$(cx_default "$_cr_waves" /-1/finished_at null)" != null ]; then CX_RESULT='{"recovered":false}'; return 0; fi
  CX_WAVE=$(cj_get "$_cr_waves" /-1/id); CX_STAGE=$(cj_get "$CX_DOC" /current_stage)
  cx_bind || return
  cx_event wave_retry 'Recuperacao explicita apos interrupcao; fase nao avancada.' || return
  cx_close threshold_proxy_atingido "Continuar etapa $CX_STAGE: recuperada sem inferir conclusao pelos artefatos." false
}
cx_resume() {
  cx_validate false true true true || return
  case "$(cj_get "$CX_DOC" /execution/status)" in concluida|abortada) cx_describe || return; CX_RESULT=$(cj_set "$CX_RESULT" /resumed false); return 0 ;; esac
  cx_validate || return
  _cr_request=$CX_ARGS
  _cr_answer=$(cx_default "$CX_ARGS" /answer ''; printf '.'); _cr_answer=${_cr_answer%.}
  _cr_block=$(cx_default "$CX_ARGS" /block_id '')
  _cr_source=$(cx_default "$CX_ARGS" /response_source '')
  _cr_aspects=$(cx_json_default "$CX_ARGS" /init_aspects null)
  _cr_changed=false
  if [ -n "$_cr_answer" ]; then
    cx_operator "$_cr_source" || return
    [ "$(cj_length "$(cj_quote "$_cr_answer")")" -le 2000 ] && [ "$(cx_text_length "$_cr_answer")" -gt 0 ] || { cx_fail 'human answer must contain 1..2000 characters'; return 1; }
    cx_pending || return
    if [ -z "$_cr_block" ]; then
      [ "$(cj_length "$CX_PENDING")" = 1 ] || { cx_fail 'explicit block_id required unless exactly one block pending'; return 1; }
      _cr_block=$(cj_get "$CX_PENDING" /0/id)
    fi
    _cr_blocks=$(cj_each "$(cx_json_default "$CX_DOC" /human_blocks '[]')"); _cr_found=false
    while IFS= read -r _cr_item; do
      if [ -n "$_cr_item" ] && [ "$(cj_get "$_cr_item" /id)" = "$_cr_block" ]; then
        _cr_found=true
        case "$(cj_get "$_cr_item" /status)" in
          respondido) [ "$(cj_get "$_cr_item" /human_answer)" = "$_cr_answer" ] || { cx_fail 'block already answered; refusing replacement'; return 1; } ;;
          aguardando)
            cx_rt bloqueios.sh respond --state-dir "$CX_STATE" --block-id "$_cr_block" --resposta "$_cr_answer" || return
            cx_lifecycle_decision registrar-resposta-humana "Resposta recebida do operador para o bloqueio $_cr_block; conteudo preservado sem inferir conclusao." "[$(cj_quote "$_cr_block"),$(cj_quote "$_cr_source")]" || return
            cx_event human_response "$(printf '{"block_id":%s,"decision_id":%s,"response_source":%s}' "$(cj_quote "$_cr_block")" "$(cj_quote "$CX_DECISION")" "$(cj_quote "$_cr_source")")" || return
            _cr_changed=true ;;
          *) cx_fail 'block is not pending'; return 1 ;;
        esac
      fi
    done <<EOF
$_cr_blocks
EOF
    [ "$_cr_found" = true ] || { cx_fail 'unknown block_id'; return 1; }
  else
    [ -z "$_cr_block" ] && { [ -z "$_cr_source" ] || [ "$_cr_aspects" != null ]; } || { cx_fail 'block/source requires actual answer'; return 1; }
  fi
  if [ "$_cr_aspects" != null ]; then
    [ "$CX_KIND" = project ] || { cx_fail 'aspect initialization requires project'; return 1; }
    cx_operator "$_cr_source" || return
    [ "$(cj_length "$_cr_aspects")" -ge 3 ] && [ "$(cj_length "$_cr_aspects")" -le 7 ] || { cx_fail 'initial aspects must contain 3..7 strings'; return 1; }
    [ "$(cj_length "$(cx_json_default "$CX_DOC" /initial_key_aspects '[]')")" = 0 ] || { cx_fail 'initial aspects already recorded'; return 1; }
    _cr_technical=$(cx_json_default "$CX_ARGS" /technical_aspects '[]'); _cr_operational=$(cx_json_default "$CX_ARGS" /operational_aspects '[]')
    for _cr_values in "$_cr_aspects" "$_cr_technical" "$_cr_operational"; do
      [ "$(cj_length "$_cr_values")" -le 7 ] || { cx_fail 'aspect list exceeds seven entries'; return 1; }
      _cr_entries=$(cj_each "$_cr_values")
      while IFS= read -r _cr_entry; do [ -z "$_cr_entry" ] || [ "$(cx_text_length "$(cj_get "$_cr_entry")")" -gt 0 ] || { cx_fail 'empty aspect'; return 1; }; done <<EOF
$_cr_entries
EOF
    done
    cx_rt drift.sh init --state-dir "$CX_STATE" --aspectos "$_cr_aspects" --tecnicos "$_cr_technical" --operacionais "$_cr_operational" || return
    cx_lifecycle_decision inicializar-aspectos-legados 'O operador forneceu aspectos para verificar finalidade antes da retomada.' "[$(cj_quote "$_cr_source")]" || return
    cx_event aspects_initialized "$(printf '{"decision_id":%s,"response_source":%s}' "$(cj_quote "$CX_DECISION")" "$(cj_quote "$_cr_source")")" || return
    _cr_changed=true
  elif [ "$(cx_json_default "$CX_ARGS" /technical_aspects null)" != null ] || [ "$(cx_json_default "$CX_ARGS" /operational_aspects null)" != null ]; then cx_fail 'technical/operational aspects require init_aspects'; return 1
  fi
  [ "$_cr_changed" != true ] || cx_after_close || return
  CX_ARGS=$_cr_request; cx_describe || return
  CX_RESULT=$(cj_set "$CX_RESULT" /resumed true)
}
cx_abort() {
  cx_validate true true true true || return
  case "$(cj_get "$CX_DOC" /execution/status)" in concluida|abortada) cx_describe || return; CX_RESULT=$(cj_set "$CX_RESULT" /aborted false); return 0 ;; esac
  cx_validate true false false true || return
  _ca_reason=$(cx_default "$CX_ARGS" /reason 'aborto manual')
  [ "$(cx_text_length "$_ca_reason")" -gt 0 ] && [ "$(cj_length "$(cj_quote "$_ca_reason")")" -le 2000 ] || { cx_fail 'abort reason must contain 1..2000 characters'; return 1; }
  _ca_purge=$(cx_default "$CX_ARGS" /purge_backups false)
  _ca_backup=$(cx_path "$CX_STATE/backups") || return
  [ ! -L "$CX_STATE/backups" ] && cx_within "$CX_STATE" "$_ca_backup" || { cx_fail 'unsafe backups directory'; return 1; }
  _ca_last=$(cx_json_default "$CX_DOC" /waves/-1 null)
  if [ "$_ca_last" != null ] && [ "$(cx_default "$_ca_last" /finished_at null)" = null ]; then
    CX_WAVE=$(cj_get "$_ca_last" /id); CX_STAGE=$(cj_get "$CX_DOC" /current_stage)
    if [ "$CX_PROJECT_LOCK" != true ]; then cx_bind || return; fi
    cx_assert_wave || return; cx_backup || return
  fi
  cx_lifecycle_decision abortar-execucao "O operador solicitou encerrar esta execucao: $_ca_reason" || return
  _ca_decision=$CX_DECISION
  if [ -n "$CX_WAVE" ]; then
    cx_rt state-ondas.sh end --state-dir "$CX_STATE" --motivo-termino aborto --next-instruction "Execucao abortada: $_ca_reason" || return
    CX_FINISHED_WAVE=$CX_WAVE; CX_WAVE=
  fi
  cx_state_read || return
  _ca_doc=$(cj_set "$CX_DOC" /execution/status '"abortada"')
  _ca_doc=$(cj_set "$_ca_doc" /execution/finished_at "$(cj_quote "$(cx_now)")")
  _ca_doc=$(cj_set "$_ca_doc" /execution/termination_reason "$(cj_quote "$_ca_reason")")
  _ca_doc=$(cj_set "$_ca_doc" /next_instruction "$(cj_quote "Execucao abortada: $_ca_reason")")
  _ca_events=$(cx_json_default "$_ca_doc" /events '[]')
  _ca_detail=$(printf '{"reason":%s,"decision_id":%s,"purge_backups":%s}' "$(cj_quote "$_ca_reason")" "$(cj_quote "$_ca_decision")" "$_ca_purge")
  _ca_events=$(cj_append "$_ca_events" '' "$(printf '{"event_type":"execution_aborted","timestamp":%s,"description":%s}' "$(cj_quote "$(cx_now)")" "$(cj_quote "$_ca_detail")")")
  _ca_doc=$(cj_set "$_ca_doc" /events "$_ca_events")
  cx_write "$_ca_doc" || return
  cx_backup abort-final || return
  if [ "$_ca_purge" = true ] && [ -d "$_ca_backup" ]; then rm -r -- "$_ca_backup" || return; fi
  cx_after_close || return
  _ca_result=$CX_RESULT; _ca_commit=disabled
  cx_rt commit-mode.sh is-enabled --state-dir "$CX_STATE" || return
  if [ "$CX_OUTPUT" = true ]; then
    if cx_rt state-ondas.sh git-commit --state-dir "$CX_STATE" --projeto-alvo-path "$CX_PROJECT" --motivo "$_ca_reason"; then _ca_commit=completed
    else _ca_commit=degraded; cx_event abort_commit_degraded "$CX_ERROR" || return; cx_after_close || return; _ca_result=$CX_RESULT
    fi
  fi
  CX_RESULT=$(cj_set "$_ca_result" /aborted true); CX_RESULT=$(cj_set "$CX_RESULT" /commit_status "$(cj_quote "$_ca_commit")")
}
cx_handoff() {
  _ch_source=$(cj_get "$CX_ARGS" /response_source) || return
  _ch_expected=$(cj_get "$CX_ARGS" /expected_runtime) || return
  _ch_rationale=$(cj_get "$CX_ARGS" /rationale) || return
  cx_operator "$_ch_source" || return
  case "$_ch_expected" in claude-code|unattributed) ;; *) cx_fail 'invalid handoff source'; return 1 ;; esac
  cx_validate false false true || return
  _ch_before=$(cx_json_default "$CX_DOC" /execution_provenance null)
  _ch_runtime=$(cx_default "$_ch_before" /runtime unattributed)
  if [ "$_ch_runtime" = codex ]; then
    _ch_previous=$(cx_json_default "$CX_DOC" /runtime_handoffs/-1 null)
    [ "$(cx_default "$_ch_previous" /from_runtime '')" = "$_ch_expected" ] && [ "$(cx_default "$_ch_previous" /response_source '')" = "$_ch_source" ] || { cx_fail 'execution already owned by Codex'; return 1; }
    cx_describe || return; CX_RESULT=$(cj_set "$CX_RESULT" /handed_off false); return 0
  fi
  [ "$_ch_runtime" = "$_ch_expected" ] || { cx_fail 'handoff runtime does not match origin'; return 1; }
  cx_lifecycle_decision transferir-execucao-para-codex "$_ch_rationale" "[$(cj_quote "$_ch_source")]" || return
  _ch_transfer=$(printf '{"from_runtime":%s,"to_runtime":"codex","previous_provenance":%s,"response_source":%s,"rationale":%s,"decision_id":%s,"timestamp":%s}' "$(cj_quote "$_ch_runtime")" "$_ch_before" "$(cj_quote "$_ch_source")" "$(cj_quote "$_ch_rationale")" "$(cj_quote "$CX_DECISION")" "$(cj_quote "$(cx_now)")")
  _ch_fresh=$(printf '{"runtime":"codex","model":%s,"toolkit_version":%s}' "$(cx_json_default "$CX_ARGS" /model null)" "$(cj_quote "$(cat "$CX_SOURCE/cli/VERSION")")")
  cx_state_read || return
  _ch_doc=$(cj_set "$CX_DOC" /execution_provenance "$_ch_fresh")
  _ch_doc=$(cj_set "$_ch_doc" /runtime_handoffs "$(cj_append "$(cx_json_default "$CX_DOC" /runtime_handoffs '[]')" '' "$_ch_transfer")")
  [ "$CX_KIND" != project ] || _ch_doc=$(cj_set "$_ch_doc" /codex_governance "$CX_ARTIFACTS")
  cx_write "$_ch_doc" || return
  cx_event runtime_handoff "$_ch_transfer" || return
  cx_after_close || return
  cx_describe || return; CX_RESULT=$(cj_set "$CX_RESULT" /handed_off true)
}
cx_reconcile() {
  _cg_source=$(cj_get "$CX_ARGS" /response_source) || return
  _cg_rationale=$(cj_get "$CX_ARGS" /rationale) || return
  _cg_expected=$(cj_value "$CX_ARGS" /expected_hashes) || return
  cx_operator "$_cg_source" || return
  cx_validate false false false true || return
  _cg_before_doc=$CX_DOC; _cg_actual=
  for _cg_name in briefing constitution; do
    [ "$(cj_get "$CX_ARTIFACTS" "/$_cg_name/exists")" = true ] || { cx_fail 'both governance artifacts required'; return 1; }
    _cg_actual="$_cg_actual$(cj_quote "$_cg_name:$(cj_get "$CX_ARTIFACTS" "/$_cg_name/sha256")")
"
  done
  _cg_actual=$(printf '%s' "$_cg_actual" | LC_ALL=C sort)
  [ "$(cj_each "$_cg_expected" | LC_ALL=C sort)" = "$_cg_actual" ] || { cx_fail 'expected hashes must match both current artifacts'; return 1; }
  _cg_version=$(sed -n 's/^\*\*Version\*\*:[[:space:]]*\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\).*$/\1/p' "$(cj_get "$CX_ARTIFACTS" /constitution/path)" | head -n 1)
  [ -n "$_cg_version" ] || { cx_fail 'constitution requires **Version**: X.Y.Z'; return 1; }
  _cg_field=prerequisites; [ "$CX_KIND" != project ] || _cg_field=codex_governance
  _cg_before=$(cx_json_default "$_cg_before_doc" "/$_cg_field" '{}')
  _cg_new=$(cj_set "$CX_ARTIFACTS" /constitution/version "$(cj_quote "$_cg_version")")
  cx_lifecycle_decision reconciliar-governanca "$_cg_rationale" "$(cj_append "$_cg_expected" '' "$(cj_quote "$_cg_source")")" || return
  _cg_entry=$(printf '{"timestamp":%s,"previous":%s,"current":%s,"response_source":%s,"rationale":%s,"decision_id":%s}' "$(cj_quote "$(cx_now)")" "$_cg_before" "$_cg_new" "$(cj_quote "$_cg_source")" "$(cj_quote "$_cg_rationale")" "$(cj_quote "$CX_DECISION")")
  cx_state_read || return
  _cg_doc=$(cj_set "$CX_DOC" "/$_cg_field" "$_cg_new")
  _cg_doc=$(cj_set "$_cg_doc" /governance_reconciliations "$(cj_append "$(cx_json_default "$CX_DOC" /governance_reconciliations '[]')" '' "$_cg_entry")")
  cx_write "$_cg_doc" || return
  cx_event governance_reconciled "$_cg_entry" || return
  cx_validate || return; cx_after_close || return
  cx_describe || return; CX_RESULT=$(cj_set "$CX_RESULT" /reconciled true)
}
