#!/bin/bash
# PreToolUse hook: Route Order Sentinel
# Checks if handler files have /:id routes before static routes (Fiber trie conflict).
# Only runs on *_handler.go files.
#
# This prevents the #1 gotcha: Fiber matches /:id before /static-path

set -euo pipefail

# Entrada do hook chega via stdin (JSON com .tool_input), nao via env var.
HOOK_INPUT=$(cat)

FILE_PATH=$(printf '%s' "$HOOK_INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE_PATH" ] && exit 0

# Only check handler files
[[ "$FILE_PATH" != *_handler.go ]] && exit 0

# Get the new content being written
# For Write tool: new_string or content field
# For Edit tool: no full content available before the edit — skip
CONTENT=$(printf '%s' "$HOOK_INPUT" | jq -r '.tool_input.content // empty' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0

# Look for RegisterRoutes function and check route order
# Extract lines with router.Get/Post/Put/Delete/Patch
ROUTE_LINES=$(echo "$CONTENT" | grep -nE 'router\.(Get|Post|Put|Delete|Patch)\(' || true)
[ -z "$ROUTE_LINES" ] && exit 0

# Check if any parameterized route (/:) appears before a static route
FOUND_PARAM=false
PARAM_LINE=""

while IFS= read -r line; do
  if echo "$line" | grep -qE '"/:'; then
    FOUND_PARAM=true
    PARAM_LINE="$line"
  elif $FOUND_PARAM && echo "$line" | grep -qE '"/[a-z]'; then
    # Static route AFTER parameterized route — potential Fiber trie conflict
    echo "WARNING: Potential Fiber trie conflict in $FILE_PATH" >&2
    echo "  Parameterized route: $PARAM_LINE" >&2
    echo "  Static route after it: $line" >&2
    echo "" >&2
    echo "Static routes MUST be registered BEFORE /:id routes in Fiber." >&2
    echo "Move static routes above parameterized routes in RegisterRoutes()." >&2
    # exit 2 = bloqueia a tool call e devolve o stderr ao Claude
    exit 2
  fi
done <<< "$ROUTE_LINES"

exit 0