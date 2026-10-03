#!/bin/sh
# One schema inventory is used by the MCP transport and native hook allowlist.
set -eu

cx_tools() { cat "$CX_ENTRY_DIR/tools.json"; }
cx_tool_definition() {
  _td_name=$1
  _td_entries=$(cj_each "$CX_TOOLS")
  while IFS= read -r _td_entry; do
    if [ "$(cj_get "$_td_entry" /name)" = "cstk_$_td_name" ]; then cj_value "$_td_entry" /inputSchema; return 0; fi
  done <<EOF
$_td_entries
EOF
  return 1
}
cx_arguments() {
  _ta_definition=$(cx_tool_definition "$1") || { cx_fail 'unknown tool'; return 1; }
  [ "$(cj_type "$CX_ARGS")" = object ] || { cx_fail 'arguments must be an object'; return 1; }
  _ta_keys=$(cj_keys "$CX_ARGS"); _ta_required=$(cj_each "$_ta_definition" /required)
  while IFS= read -r _ta_key; do
    [ -n "$_ta_key" ] || continue
    _ta_key=$(cj_get "$_ta_key")
    _ta_kind=$(cj_value "$_ta_definition" "/properties/$_ta_key/type" 2>/dev/null) || { cx_fail 'unknown argument'; return 1; }
    _ta_actual=$(cj_type "$CX_ARGS" "/$_ta_key") || return
    case "$_ta_kind" in
      '"string"'|'"boolean"') [ "$(cj_get "$_ta_kind")" = "$_ta_actual" ] || { cx_fail "invalid argument type: $_ta_key"; return 1; } ;;
      '"integer"') _ta_number=$(cj_get "$CX_ARGS" "/$_ta_key"); [ "$_ta_actual" = number ] && printf '%s\n' "$_ta_number" | grep -Eq '^-?(0|[1-9][0-9]*)$' || { cx_fail "integer required: $_ta_key"; return 1; } ;;
      '"array"')
        [ "$_ta_actual" = array ] || { cx_fail "string array required: $_ta_key"; return 1; }
        _ta_items=$(cj_each "$CX_ARGS" "/$_ta_key")
        while IFS= read -r _ta_item; do [ -z "$_ta_item" ] || [ "$(cj_type "$_ta_item")" = string ] || { cx_fail "array item must be a string: $_ta_key"; return 1; }; done <<EOF
$_ta_items
EOF
        ;;
      '["boolean","string"]') case "$_ta_actual" in boolean|string) ;; *) cx_fail "invalid opt-in value type: $_ta_key"; return 1 ;; esac ;;
      *) cx_fail 'unsupported internal schema'; return 1 ;;
    esac
  done <<EOF
$_ta_keys
EOF
  while IFS= read -r _ta_key; do
    [ -n "$_ta_key" ] || continue
    _ta_key=$(cj_get "$_ta_key")
    cj_type "$CX_ARGS" "/$_ta_key" >/dev/null 2>&1 || { cx_fail "missing required argument: $_ta_key"; return 1; }
  done <<EOF
$_ta_required
EOF
}
