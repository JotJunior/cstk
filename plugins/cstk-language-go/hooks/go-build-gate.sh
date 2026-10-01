#!/bin/bash
# PostToolUse hook: Go Build Gate
# After any Write/Edit to a .go file, runs `go build ./...` in the affected service.
# Catches compilation errors immediately instead of at session end.
#
# Input: hook JSON on stdin (.tool_input.file_path)

set -euo pipefail

HOOK_INPUT=$(cat)

cd "$CLAUDE_PROJECT_DIR" 2>/dev/null || exit 0

# Extract file_path from tool input JSON
FILE_PATH=$(printf '%s' "$HOOK_INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# Only process .go files
[[ "$FILE_PATH" != *.go ]] && exit 0

# Skip migration SQL files that might have .go in path
[[ "$FILE_PATH" == */migrations/* ]] && exit 0

# Find the service directory (services/gob-xxx-service)
SERVICE_DIR=$(echo "$FILE_PATH" | grep -oE 'services/[^/]+' || true)

# If not in a service directory, skip
[ -z "$SERVICE_DIR" ] && exit 0

FULL_SERVICE_DIR="$CLAUDE_PROJECT_DIR/$SERVICE_DIR"
[ ! -d "$FULL_SERVICE_DIR" ] && exit 0

# Check if go.mod exists (valid Go module)
[ ! -f "$FULL_SERVICE_DIR/go.mod" ] && exit 0

# Run go build
BUILD_OUTPUT=$(cd "$FULL_SERVICE_DIR" && go build ./... 2>&1) || {
  echo "BUILD FAILED in $SERVICE_DIR:" >&2
  echo "$BUILD_OUTPUT" >&2
  echo "" >&2
  echo "Fix the compilation errors before continuing." >&2
  # exit 2 em PostToolUse = stderr volta ao Claude como feedback
  exit 2
}

exit 0