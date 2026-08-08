#!/bin/bash
# Stop hook: check for uncommitted changes and remind to commit
# Only checks staged changes (git add'd files), not pre-existing unstaged/untracked files
# Uses a snooze file to avoid nagging if user already declined in this session

cd "$CLAUDE_PROJECT_DIR" 2>/dev/null || cd "$(pwd)"

SNOOZE_FILE="/tmp/.claude-commit-snooze-$(echo "$CLAUDE_PROJECT_DIR" | md5sum | cut -c1-8 2>/dev/null || echo "$CLAUDE_PROJECT_DIR" | md5 -q 2>/dev/null || echo "default")"
SNOOZE_TTL=1800  # 30 minutes

# If snoozed recently, skip silently
if [ -f "$SNOOZE_FILE" ]; then
  SNOOZE_AGE=$(( $(date +%s) - $(stat -f %m "$SNOOZE_FILE" 2>/dev/null || stat -c %Y "$SNOOZE_FILE" 2>/dev/null || echo 0) ))
  if [ "$SNOOZE_AGE" -lt "$SNOOZE_TTL" ]; then
    exit 0
  fi
  rm -f "$SNOOZE_FILE"
fi

# Check only staged changes (files explicitly added with git add)
STAGED=$(git diff --cached --name-only 2>/dev/null)

if [ -n "$STAGED" ]; then
  # Create snooze file so we don't nag again for 30 min
  touch "$SNOOZE_FILE"
  echo "Ha alteracoes staged nao commitadas. Pergunte ao usuario se deseja commitar usando /commit." >&2
  exit 2
fi

exit 0