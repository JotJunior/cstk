#!/bin/sh
set -eu
. "$(dirname -- "$0")/_native.sh"
cn_request hooks/list "$(printf '{"cwds":[%s]}' "$(cj_quote "$CN_PROJECT")")"
_cn_entries=$(cj_each "$CN_RESULT" /data); _cn_hooks='[]'; _cn_errors='[]'; _cn_warnings='[]'; _cn_events=''; _cn_trusted=true
_cn_receipt='{}'; [ ! -f "$CN_HOME/cstk/install.json" ] || _cn_receipt=$(cx_read "$CN_HOME/cstk/install.json")
_cn_commands='[]'
for _cn_event in PreToolUse PostToolUse; do
  _cn_command=$(cx_json_default "$_cn_receipt" "/hook_entries/$_cn_event/hooks/0/command" null)
  [ "$_cn_command" = null ] || _cn_commands=$(cj_append "$_cn_commands" '' "$_cn_command")
done
while IFS= read -r _cn_entry; do
  [ -n "$_cn_entry" ] || continue
  for _cn_field in errors warnings hooks; do
    _cn_items=$(cj_each "$(cx_json_default "$_cn_entry" "/$_cn_field" '[]')")
    while IFS= read -r _cn_item; do
      [ -n "$_cn_item" ] || continue
      case "$_cn_field" in
        errors) _cn_errors=$(cj_append "$_cn_errors" '' "$_cn_item") ;;
        warnings) _cn_warnings=$(cj_append "$_cn_warnings" '' "$_cn_item") ;;
        hooks)
          _cn_match=false
          [ "$(cx_default "$_cn_item" /pluginId '')" != cstk-codex-pilot@cstk-codex-pilot-local ] || _cn_match=true
          _cn_list=$(cj_each "$_cn_commands")
          while IFS= read -r _cn_command; do
            [ -z "$_cn_command" ] || ! cj_equal "$_cn_command" "$(cx_json_default "$_cn_item" /command null)" || _cn_match=true
          done <<EOF
$_cn_list
EOF
          [ "$_cn_match" = true ] || continue
          _cn_hooks=$(cj_append "$_cn_hooks" '' "$_cn_item"); _cn_events="$_cn_events $(cj_get "$_cn_item" /eventName)"
          case "$(cj_get "$_cn_item" /trustStatus)" in trusted|managed) ;; *) _cn_trusted=false ;; esac
          [ "$(cx_default "$_cn_item" /enabled false)" = true ] || _cn_trusted=false
          ;;
      esac
    done <<EOF
$_cn_items
EOF
  done
done <<EOF
$_cn_entries
EOF
_cn_loaded=false
case " $_cn_events " in *' preToolUse '*) case " $_cn_events " in *' postToolUse '*) _cn_loaded=true ;; esac ;; esac
[ "$_cn_loaded" = true ] || _cn_trusted=false
_cn_next='Review the plugin with /hooks in Codex'; [ "$_cn_trusted" != true ] || _cn_next='Validate real tool coverage'
printf '{"project":%s,"native_hooks_loaded":%s,"native_hooks_trusted":%s,"hooks":%s,"errors":%s,"warnings":%s,"autonomous_ready":false,"next_step":%s}\n' "$(cj_quote "$CN_PROJECT")" "$_cn_loaded" "$_cn_trusted" "$_cn_hooks" "$_cn_errors" "$_cn_warnings" "$(cj_quote "$_cn_next")"
