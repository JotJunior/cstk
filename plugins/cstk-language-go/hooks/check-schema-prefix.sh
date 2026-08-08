#!/bin/bash
# PreToolCall hook: Schema Prefix Checker
# Ensures SQL queries in Go files use schema-prefixed table names.
# Unqualified table names silently query the wrong schema in production.
#
# Pattern: FROM/INTO/UPDATE/JOIN followed by a bare table name without schema dot prefix

set -euo pipefail

FILE_PATH=$(echo "${CLAUDE_TOOL_INPUT:-}" | jq -r '.file_path // empty' 2>/dev/null)
[ -z "$FILE_PATH" ] && exit 0

# Only check Go files in repository layer
[[ "$FILE_PATH" != *.go ]] && exit 0
[[ "$FILE_PATH" != */repository/* ]] && exit 0

# Get content (works for Write tool)
CONTENT=$(echo "${CLAUDE_TOOL_INPUT:-}" | jq -r '.content // empty' 2>/dev/null)

# For Edit tool, get new_string
if [ -z "$CONTENT" ]; then
  CONTENT=$(echo "${CLAUDE_TOOL_INPUT:-}" | jq -r '.new_string // empty' 2>/dev/null)
fi

[ -z "$CONTENT" ] && exit 0

# Skip if no SQL keywords present
echo "$CONTENT" | grep -qiE '(SELECT|INSERT|UPDATE|DELETE|FROM|JOIN)\s' || exit 0

# Check for SQL table references without schema prefix
# Pattern: FROM/INTO/UPDATE/JOIN followed by a word that doesn't contain a dot
# Exclude: subqueries (FROM (), $), functions, aliases, common SQL keywords
VIOLATIONS=$(echo "$CONTENT" | grep -nE '(FROM|INTO|UPDATE|JOIN)\s+[a-z_]+[a-z_0-9]*\s' | \
  grep -vE '(FROM\s+\(|FROM\s+\$|FROM\s+ctx|FROM\s+err|FROM\s+row|FROM\s+sql|FROM\s+where|INTO\s+&|INTO\s+\$)' | \
  grep -vE '[a-z_]+\.[a-z_]+' | \
  grep -vE '(FROM\s+generate_series|FROM\s+unnest|FROM\s+json)' || true)

if [ -n "$VIOLATIONS" ]; then
  echo "WARNING: Possible SQL queries without schema prefix in $FILE_PATH:" >&2
  echo "$VIOLATIONS" >&2
  echo "" >&2
  echo "All table references MUST use schema prefix: schema.table_name" >&2
  echo "Example: SELECT * FROM member.members (not just 'members')" >&2
  echo "" >&2
  echo "If these are false positives (Go variables, not SQL), you can proceed." >&2
  # Exit 0 — warning only, don't block (too many false positives possible)
  exit 0
fi

exit 0