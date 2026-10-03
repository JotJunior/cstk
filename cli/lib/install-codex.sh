#!/bin/sh
# Native Codex installer. POSIX boundary; preserves operator configuration.
set -eu
IC_LIB=$(CDPATH='' cd -P -- "$(dirname -- "$0")" && pwd -P)
. "$IC_LIB/codex-json.sh"
. "$IC_LIB/codex-common.sh"
IC_SOURCE='' IC_PACKAGE='' IC_HOME=${CODEX_HOME:-$HOME/.codex} IC_DB=${CSTK_KNOWLEDGE_DB:-$HOME/.claude/cstk/knowledge.db} IC_DRY=false
IC_TEMP='' IC_LOCK=false
ic_cleanup() { [ -z "$IC_TEMP" ] || rm -r -- "$IC_TEMP"; if [ "$IC_LOCK" = true ]; then rmdir -- "$IC_MANAGED/.install-lock"; fi; }
trap 'ic_cleanup' 0
trap 'exit 130' INT TERM
while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run) IC_DRY=true; shift; continue ;;
    --source-tree|--package|--codex-home|--knowledge-db) [ "$#" -ge 2 ] || exit 2 ;;
    *) cx_fail "unknown installer option: $1" 2; exit 2 ;;
  esac
  case "$1" in --source-tree) IC_SOURCE=$2 ;; --package) IC_PACKAGE=$2 ;; --codex-home) IC_HOME=$2 ;; --knowledge-db) IC_DB=$2 ;; esac
  shift 2
done
[ -n "$IC_SOURCE" ] && [ -z "$IC_PACKAGE" ] || { [ -z "$IC_SOURCE" ] && [ -n "$IC_PACKAGE" ]; } || { cx_fail 'select exactly one source tree or package'; exit 2; }
IC_HOME=$(cx_path "$IC_HOME"); IC_DB=$(cx_path "$IC_DB"); IC_MANAGED=$IC_HOME/cstk
if cx_within "$IC_MANAGED" "$IC_DB" || [ -d "$IC_DB" ]; then cx_fail 'knowledge_db must be a file outside the managed installation'; exit 2; fi
ic_tree_hash() (
  [ -d "$1" ] && [ ! -L "$1" ] || exit 4
  [ -z "$(find "$1" -type l -print)" ] || { cx_fail 'symlink in managed plugin tree' 4; exit 4; }
  # Control bytes cannot be represented in the sorted line inventory.
  find "$1" -type f -exec sh -c 'for p do
    if printf "%s" "$p" | LC_ALL=C grep "[[:cntrl:]]" >/dev/null; then exit 1; fi
  done' sh {} + || exit 4
  # Legacy receipts sorted Path components: foo/a precedes foo-bar/a.
  # SOH as the component separator preserves that order with POSIX sort.
  _ith_files=$(cd -- "$1" && find . -type f ! -name '*.pyc' ! -path '*/__pycache__/*' \
    | awk '{key=$0;gsub(/\//,"\001",key);printf "%s\t%s\n",key,$0}' \
    | LC_ALL=C sort | cut -f2-)
  _ith_input=$(mktemp); trap 'rm -f -- "$_ith_input"' 0
  while IFS= read -r _ith_path; do
    [ -n "$_ith_path" ] || continue
    printf '%s\000' "${_ith_path#./}" >> "$_ith_input"
    cat -- "$1/${_ith_path#./}" >> "$_ith_input" || exit 4
    printf '\000' >> "$_ith_input"
  done <<EOF
$_ith_files
EOF
  cx_sha "$_ith_input"
)
ic_validate() {
  _iv_doc=$(cx_read "$1/plugin.json") || return
  [ "$(cj_get "$_iv_doc" /name)" = cstk-codex-pilot ] || { cx_fail 'unexpected Codex plugin identity'; return 1; }
  for _iv_skill in feature-00c feature-00c-resume feature-00c-abort agente-00c agente-00c-resume agente-00c-abort; do
    [ -f "$1/skills/$_iv_skill/SKILL.md" ] || { cx_fail "missing workflow: $_iv_skill"; return 1; }
  done
  for _iv_asset in mcp.json hooks/hooks.json cli/VERSION cli/lib/codex-json.sh plugins/cstk/skills/agente-00c-runtime/scripts/pipeline.sh skills/feature-00c/scripts/mcp-bridge.sh; do
    [ -f "$1/$_iv_asset" ] || { cx_fail "incomplete self-contained package: $_iv_asset"; return 1; }
  done
}
ic_invoke() {
  if cx_timeout 60 env CODEX_HOME="$IC_HOME" "$IC_CODEX" "$@" > "$IC_TEMP/output" 2> "$IC_TEMP/error"; then IC_OUTPUT=$(cat "$IC_TEMP/output")
  else cx_fail "Codex $*: $(cat "$IC_TEMP/error")"; return 1
  fi
}
ic_hooks_prepare() {
  IC_HOOKS='{}'; [ ! -f "$IC_HOME/hooks.json" ] || IC_HOOKS=$(cx_read "$IC_HOME/hooks.json") || return 4
  [ "$(cj_type "$IC_HOOKS")" = object ] && [ "$(cj_type "$(cx_json_default "$IC_HOOKS" /hooks '{}')")" = object ] || { cx_fail 'existing Codex hook configuration is invalid' 4; return 4; }
  _ih_keys=$(cj_keys "$(cx_json_default "$IC_HOOKS" /hooks '{}')")
  while IFS= read -r _ih_key; do
    [ -n "$_ih_key" ] || continue
    _ih_event=$(cj_get "$_ih_key"); _ih_groups=$(cj_value "$IC_HOOKS" "/hooks/$_ih_event")
    [ "$(cj_type "$_ih_groups")" = array ] || return 4
    _ih_list=$(cj_each "$_ih_groups")
    while IFS= read -r _ih_group; do
      [ -n "$_ih_group" ] || continue
      [ "$(cj_type "$_ih_group")" = object ] && [ "$(cj_type "$_ih_group" /hooks)" = array ] || return 4
      _ih_handlers=$(cj_each "$_ih_group" /hooks)
      while IFS= read -r _ih_handler; do [ -z "$_ih_handler" ] || [ "$(cj_type "$_ih_handler")" = object ] || return 4; done <<EOF
$_ih_handlers
EOF
    done <<EOF
$_ih_list
EOF
  done <<EOF
$_ih_keys
EOF
  IC_ENTRIES='{}'
  for _ih_event in PreToolUse PostToolUse; do
    _ih_script=pretooluse.sh; [ "$_ih_event" = PreToolUse ] || _ih_script=posttooluse.sh
    _ih_old=$(cx_json_default "$IC_RECEIPT" "/hook_entries/$_ih_event" null)
    _ih_command=''; [ "$_ih_old" = null ] || _ih_command=$(cj_get "$_ih_old" /hooks/0/command) || return 4
    _ih_matches=0; _ih_kept='[]'; _ih_list=$(cj_each "$(cx_json_default "$IC_HOOKS" "/hooks/$_ih_event" '[]')")
    while IFS= read -r _ih_group; do
      [ -n "$_ih_group" ] || continue
      _ih_found=false
      if [ -n "$_ih_command" ]; then
        _ih_handlers=$(cj_each "$_ih_group" /hooks)
        while IFS= read -r _ih_handler; do
          [ -n "$_ih_handler" ] || continue
          if [ "$(cx_default "$_ih_handler" /command '')" = "$_ih_command" ]; then _ih_found=true; fi
        done <<EOF
$_ih_handlers
EOF
      fi
      if [ "$_ih_found" = true ]; then
        cj_equal "$_ih_group" "$_ih_old" || { cx_fail "CSTK hook changed locally: $_ih_event" 4; return 4; }
        _ih_matches=$((_ih_matches+1))
      else _ih_kept=$(cj_append "$_ih_kept" '' "$_ih_group")
      fi
    done <<EOF
$_ih_list
EOF
    if [ "$_ih_old" != null ] && [ "$_ih_matches" != 1 ]; then cx_fail "CSTK hook removed or duplicated: $_ih_event" 4; return 4; fi
    # Prepared before any native mutation; IC_DEST is finalized afterward.
    IC_ENTRIES=$(cj_set "$IC_ENTRIES" "/$_ih_event" "$_ih_kept")
  done
}
if [ -n "$IC_SOURCE" ]; then
  IC_SOURCE=$(cx_path "$IC_SOURCE"); IC_INPUT=$IC_SOURCE
  IC_MANIFEST=$(cx_read "$IC_SOURCE/adapters/codex/plugin.json")
else IC_PACKAGE=$(cx_path "$IC_PACKAGE"); IC_INPUT=$IC_PACKAGE; ic_validate "$IC_PACKAGE"; IC_MANIFEST=$(cx_read "$IC_PACKAGE/plugin.json")
fi
IC_VERSION=$(cj_get "$IC_MANIFEST" /version)
case "$IC_VERSION" in ''|*[!a-zA-Z0-9._-]*) cx_fail 'unsafe plugin version'; exit 2 ;; esac
IC_CODEX=$(command -v codex || :)
IC_REPORT=$(printf '{"cli":"codex","codex_home":%s,"knowledge_db":%s,"plugin_id":"cstk-codex-pilot@cstk-codex-pilot-local","skills":["feature-00c","feature-00c-resume","feature-00c-abort","agente-00c","agente-00c-resume","agente-00c-abort"],"dependencies":{"codex":%s,"sh":%s},"dry_run":%s,"hook_trust":"operator_review_required","plugin_version":%s,"source":%s}' "$(cj_quote "$IC_HOME")" "$(cj_quote "$IC_DB")" "$(cj_quote "$IC_CODEX")" "$(cj_quote "$(command -v sh)")" "$IC_DRY" "$(cj_quote "$IC_VERSION")" "$(cj_quote "$IC_INPUT")")
if [ "$IC_DRY" = true ]; then printf '%s\n' "$IC_REPORT"; exit; fi
[ -n "$IC_CODEX" ] || { cx_fail 'missing Codex installation dependency: codex'; exit 1; }
IC_TEMP=$(mktemp -d); chmod 700 "$IC_TEMP"
cx_timeout 15 env CODEX_HOME="$IC_TEMP/probe" "$IC_CODEX" plugin add --help > /dev/null 2>&1 || { cx_fail 'installed Codex does not support plugin add'; exit 1; }
for _ic_path in "$IC_MANAGED" "$IC_MANAGED/packages" "$IC_MANAGED/.agents" "$IC_MANAGED/.agents/plugins" "$IC_MANAGED/.agents/plugins/marketplace.json" "$IC_MANAGED/install.json" "$IC_HOME/hooks.json"; do
  [ ! -L "$_ic_path" ] || { cx_fail 'symlinked installation control' 4; exit 4; }
done
mkdir -p -- "$IC_MANAGED"
mkdir -- "$IC_MANAGED/.install-lock" 2>/dev/null || { cx_fail 'another installation owns .install-lock' 3; exit 3; }; IC_LOCK=true
IC_RECEIPT='{}'
if [ -f "$IC_MANAGED/install.json" ]; then
  IC_RECEIPT=$(cx_read "$IC_MANAGED/install.json")
  for _ic_prefix in source cache; do
    _ic_previous=$(cj_get "$IC_RECEIPT" "/${_ic_prefix}_path")
    _ic_sha=$(ic_tree_hash "$_ic_previous") || exit 4
    [ "$_ic_sha" = "$(cj_get "$IC_RECEIPT" "/${_ic_prefix}_sha256")" ] || { cx_fail "local edits in managed Codex $_ic_prefix; reconcile before reinstalling" 4; exit 4; }
  done
  _ic_previous=$(cx_default "$IC_RECEIPT" /marketplace_path '')
  if [ -n "$_ic_previous" ]; then
    [ ! -L "$_ic_previous" ] && [ -f "$_ic_previous" ] && [ "$(cx_sha "$_ic_previous")" = "$(cj_get "$IC_RECEIPT" /marketplace_sha256)" ] || { cx_fail 'managed marketplace changed locally' 4; exit 4; }
  fi
fi
ic_hooks_prepare || { cx_fail 'managed hook configuration requires reconciliation' 4; exit 4; }
if [ -n "$IC_SOURCE" ]; then sh "$IC_SOURCE/scripts/build-codex-plugin.sh" --out "$IC_TEMP/package" > /dev/null
else cp -R -- "$IC_PACKAGE" "$IC_TEMP/package"
fi
IC_STAGE=$IC_TEMP/package; ic_validate "$IC_STAGE"
for _ic_manifest in plugin.json .codex-plugin/plugin.json; do
  _ic_doc=$(cx_read "$IC_STAGE/$_ic_manifest"); _ic_pointer=/hooks
  [ "$_ic_manifest" != plugin.json ] || _ic_pointer=/extensions/com.openai/hooks
  cx_atomic "$IC_STAGE/$_ic_manifest" "$(cj_set "$_ic_doc" "$_ic_pointer" '[]')"
done
cx_atomic "$IC_STAGE/mcp.json" "$(cj_set "$(cx_read "$IC_STAGE/mcp.json")" /mcpServers/cstk_pipeline/env/CSTK_KNOWLEDGE_DB "$(cj_quote "$IC_DB")")"
IC_SHA=$(ic_tree_hash "$IC_STAGE"); IC_DEST=$IC_MANAGED/packages/$IC_VERSION-$(printf '%.16s' "$IC_SHA")
mkdir -p -- "$IC_MANAGED/packages"
if [ -e "$IC_DEST" ]; then [ "$(ic_tree_hash "$IC_DEST")" = "$IC_SHA" ] || { cx_fail 'managed package changed locally' 4; exit 4; }
else cp -R -- "$IC_STAGE" "$IC_DEST"
fi
ic_invoke plugin marketplace list --json; _ic_list=$(cj_each "$IC_OUTPUT" /marketplaces)
while IFS= read -r _ic_market; do
  [ -n "$_ic_market" ] || continue
  if [ "$(cj_get "$_ic_market" /name)" = cstk-codex-pilot-local ]; then
    _ic_root=$(cx_path "$(cj_get "$_ic_market" /root)")
    if [ "$_ic_root" != "$IC_MANAGED" ]; then
      [ "$_ic_root" = "$(cx_default "$IC_RECEIPT" /source_path '')" ] || { cx_fail 'CSTK marketplace belongs to another source' 4; exit 4; }
      ic_invoke plugin marketplace remove cstk-codex-pilot-local
    fi
  fi
done <<EOF
$_ic_list
EOF
IC_MARKET=$IC_MANAGED/.agents/plugins/marketplace.json; mkdir -p -- "$(dirname -- "$IC_MARKET")"
IC_CATALOG=$(cx_read "$IC_DEST/.agents/plugins/marketplace.json")
_ic_old_market=''; [ ! -f "$IC_MARKET" ] || _ic_old_market=$(cat "$IC_MARKET")
cx_atomic "$IC_MARKET" "$(cj_set "$IC_CATALOG" /plugins/0/source/path "$(cj_quote "./packages/${IC_DEST##*/}")")"
if ic_invoke plugin marketplace add "$IC_MANAGED" && ic_invoke plugin add cstk-codex-pilot@cstk-codex-pilot-local; then :
else [ -z "$_ic_old_market" ] || cx_atomic "$IC_MARKET" "$_ic_old_market"; exit 1
fi
IC_CACHE=$IC_HOME/plugins/cache/cstk-codex-pilot-local/cstk-codex-pilot/$IC_VERSION
[ "$(ic_tree_hash "$IC_CACHE")" = "$IC_SHA" ] || { cx_fail 'native cache does not match the prepared package'; exit 1; }
_ic_hook_entries='{}'
for _ic_event in PreToolUse PostToolUse; do
  _ic_script=pretooluse.sh; [ "$_ic_event" = PreToolUse ] || _ic_script=posttooluse.sh
  _ic_entry=$(printf '{"matcher":"*","hooks":[{"type":"command","command":%s,"timeout":10}]}' "$(cj_quote "sh $(cx_quote_shell "$IC_DEST/hooks/$_ic_script")")")
  _ic_hook_entries=$(cj_set "$_ic_hook_entries" "/$_ic_event" "$_ic_entry")
  IC_HOOKS=$(cj_set "$IC_HOOKS" "/hooks/$_ic_event" "$(cj_append "$(cj_value "$IC_ENTRIES" "/$_ic_event")" '' "$_ic_entry")")
done
cx_atomic "$IC_HOME/hooks.json" "$IC_HOOKS"
IC_RECEIPT=$(printf '{"source_path":%s,"source_sha256":%s,"cache_path":%s,"cache_sha256":%s,"plugin_id":"cstk-codex-pilot@cstk-codex-pilot-local","knowledge_db":%s,"marketplace_path":%s,"marketplace_sha256":%s,"hook_entries":%s}' "$(cj_quote "$IC_DEST")" "$(cj_quote "$IC_SHA")" "$(cj_quote "$IC_CACHE")" "$(cj_quote "$IC_SHA")" "$(cj_quote "$IC_DB")" "$(cj_quote "$IC_MARKET")" "$(cj_quote "$(cx_sha "$IC_MARKET")")" "$_ic_hook_entries")
cx_atomic "$IC_MANAGED/install.json" "$IC_RECEIPT"
IC_REPORT=$(cj_set "$IC_REPORT" /installed true)
IC_REPORT=$(cj_set "$IC_REPORT" /plugin_path "$(cj_quote "$IC_CACHE")")
IC_REPORT=$(cj_set "$IC_REPORT" /managed_source "$(cj_quote "$IC_DEST")")
IC_REPORT=$(cj_set "$IC_REPORT" /next_step '"Inicie nova sessao Codex e revise os hooks em /hooks."')
printf '%s\n' "$IC_REPORT"
