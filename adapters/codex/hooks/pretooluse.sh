#!/bin/sh
set -eu
. "$(dirname -- "$0")/_common.sh"
_pre_rc=0; cx_hook_scope || _pre_rc=$?
case "$_pre_rc" in 1) printf '{}\n'; exit 0 ;; 0) ;; *) cx_hook_deny 'CSTK: invalid envelope or unverified owned wave'; exit 0 ;; esac
_pre_tool=$(cx_default "$CX_HOOK_INPUT" /tool_name '')
CX_ARGS=$(cx_json_default "$CX_HOOK_INPUT" /tool_input null)
if [ "$(cj_type "$CX_ARGS")" != object ]; then cx_hook_deny 'CSTK: invalid tool input'; exit 0; fi
case "$_pre_tool" in
  mcp__cstk_pipeline__cstk_*)
    _pre_action=${_pre_tool#mcp__cstk_pipeline__cstk_}
    if ! cx_arguments "$_pre_action"; then cx_hook_deny 'CSTK: invalid pipeline MCP arguments'; exit 0; fi
    if [ "$_pre_action" = select_execution ] && cj_get "$CX_ARGS" /project >/dev/null 2>&1 && [ "$(cx_path "$(cj_get "$CX_ARGS" /project)")" != "$CX_HOOK_PROJECT" ]; then cx_hook_deny 'CSTK: MCP target differs from session project'
    else printf '{}\n'
    fi ;;
  Bash)
    if [ "$(cx_default "$CX_ARGS" /tty false)" != false ] || [ "$(cx_default "$CX_ARGS" /interactive false)" != false ]; then cx_hook_deny 'CSTK: interactive stdin is outside validated coverage'; exit 0; fi
    if [ "$(cx_text_length "$(cx_default "$CX_ARGS" /command '')")" = 0 ]; then cx_hook_deny 'CSTK: missing shell command'; exit 0; fi
    if _pre_result=$(printf '%s\n' "$CX_HOOK_INPUT" | CSTK_CODEX_HOOK_STATE_DIR="$CX_HOOK_STATE" sh "$CX_SOURCE/plugins/cstk/skills/agente-00c-runtime/hooks/pretooluse-bash-guard.sh"); then
      if [ -n "$_pre_result" ]; then cj_value "$_pre_result" || cx_hook_deny 'CSTK: invalid shared guard response'; else printf '{}\n'; fi
    else cx_hook_deny 'CSTK: shared Bash policy failed'
    fi ;;
  apply_patch)
    _pre_patch=$(cx_default "$CX_ARGS" /command '')
    [ "$(printf '%s\n' "$_pre_patch" | head -n 1)" = '*** Begin Patch' ] && [ "$(printf '%s\n' "$_pre_patch" | tail -n 1)" = '*** End Patch' ] || { cx_hook_deny 'CSTK: unrecognized patch format'; exit 0; }
    _pre_count=0
    while IFS= read -r _pre_line; do
      case "$_pre_line" in
        '*** Add File: '*|'*** Update File: '*|'*** Delete File: '*|'*** Move to: '*) _pre_raw=${_pre_line#*: } ;;
        *) continue ;;
      esac
      _pre_count=$((_pre_count+1))
      case "$_pre_raw" in /*) _pre_target=$_pre_raw ;; *) _pre_target=$CX_HOOK_PROJECT/$_pre_raw ;; esac
      _pre_target=$(cx_path "$_pre_target") || { cx_hook_deny 'CSTK: invalid patch path'; exit 0; }
      cx_within "$CX_HOOK_PROJECT" "$_pre_target" || { cx_hook_deny 'CSTK: patch escapes target project'; exit 0; }
      _pre_relative=${_pre_target#"$CX_HOOK_PROJECT"/}
      case "$_pre_relative" in .claude|.claude/*|.codex|.codex/*|.git|.git/*) cx_hook_deny 'CSTK: patch cannot change execution controls'; exit 0 ;; esac
    done <<EOF
$_pre_patch
EOF
    if [ "$_pre_count" -gt 0 ]; then printf '{}\n'; else cx_hook_deny 'CSTK: patch contains no file operations'; fi ;;
  *) cx_hook_deny 'CSTK: tool path has not been validated for the local pilot' ;;
esac
