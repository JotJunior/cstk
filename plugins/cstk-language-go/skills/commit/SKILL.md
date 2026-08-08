---
name: commit
description: |
  Commit staged and unstaged changes with a well-crafted conventional commit message.
  Handles submodule updates, multi-service changes, and follows project conventions.
  Triggers: "/commit", "commit", "commitar", "fazer commit", "commit changes".
allowed-tools:
  - Bash
  - Glob
  - Grep
  - Read
---

# Commit

Create a git commit for the current changes following project conventions.

## Steps

### 1. Gather context (run in parallel)

Run these three commands simultaneously:

- `git status` (never use `-uall` flag)
- `git diff --staged` and `git diff` to see all changes
- `git log --oneline -5` to match the repository's commit message style

### 2. Analyze changes

Review all staged and unstaged changes. Determine:

- **Scope**: Which services/areas are affected?
- **Type**: What kind of change? (feat, fix, refactor, docs, chore, test, build)
- **Submodules**: Are any `services/*` submodules modified? If yes, summarize what changed in each.

### 3. Stage files

- If there are unstaged changes, stage them with `git add` specifying individual files.
- **NEVER** use `git add -A` or `git add .` — always add files by name.
- **NEVER** commit files that likely contain secrets: `.env`, `.env.*`, `credentials.json`, private keys, etc. Warn the user if they exist.
- **NEVER** commit temporary files like `t.txt`, `*.tmp`, scratch files.
- If only some changes should be committed, ask the user which files to include.

### 4. Draft commit message

Follow **Conventional Commits** format matching the repo's style:

```
<type>: <short summary in English, imperative mood, under 72 chars>

<optional body: bullet points describing key changes>

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
```

**Types**: `feat`, `fix`, `refactor`, `docs`, `chore`, `test`, `build`, `ci`, `perf`

**Rules**:
- Summary in English, imperative mood ("add X" not "added X")
- If multiple services changed, list them in the body
- For submodule-only updates, use: `feat: update submodules with <summary>`
- Always end with `Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>`

**Examples from this repo**:
- `feat: update submodules with position rules, accent-insensitive collation, and multi-lodge inactive periods`
- `fix: update submodules with proxy header config for real client IPs`
- `docs: atualizar casos de uso`

### 5. Commit

Use a HEREDOC to preserve formatting:

```bash
git commit -m "$(cat <<'EOF'
<type>: <summary>

<body>

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

### 6. Verify

Run `git status` after commit to confirm success. Report the commit hash and summary to the user.

### 7. Push (only if asked)

**NEVER** push automatically. Only push if the user explicitly says "push", "e push", "e faz push", or similar.

## Pre-commit hook failures

If the commit fails due to a pre-commit hook:
1. Read the error output
2. Fix the issue
3. Re-stage the fixed files
4. Create a **NEW** commit (never use `--amend` unless explicitly asked)

## Submodule commits

If submodules have uncommitted changes inside them (shown as "modified content" or "untracked content" in `git status`):
1. Warn the user that submodules have internal changes
2. Ask if they want to commit inside the submodules first
3. If yes, `cd` into each submodule, commit, and push
4. Then update the submodule references in the meta-repo