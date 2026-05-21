---
name: apply-insights
description: 'Apply Claude Code usage insights to current project — improve CLAUDE.md, hooks, workflows. Triggers: "aplicar insights", "otimizar fluxo", "melhorar claude.md". Requires ~/.claude/insights/usage-insights.md. Not the native /insights command.'
argument-hint: "[area especifica: bugfix | migrations | conventions | hooks | all]"
allowed-tools:
  - Read
  - Glob
  - Grep
  - Bash
  - Edit
  - Write
---

# Skill: Apply Usage Insights

Analyze the current project and apply relevant insights from usage patterns
to improve Claude Code effectiveness.

## Arguments

$ARGUMENTS should optionally specify a focus area:
- **bugfix** — Apply bug fix protocol and debugging improvements
- **migrations** — Apply database migration safety guidelines
- **conventions** — Apply code convention checks (enum/DTO matching)
- **hooks** — Suggest hooks for automated quality gates
- **all** — Full analysis and recommendations (default)

## Step 1: Load Insights

Read the insights file (search dynamically):
```bash
# Find insights file in user's .claude directory
ls ~/.claude/insights/
```

If the file is at `~/.claude/insights/usage-insights.md`, read it.
If not found, inform user and proceed with built-in best practices.

## Step 2: Analyze Current Project

1. Read the project's `CLAUDE.md` (if exists) to understand current state
2. Check `.claude/settings.json` or `.claude/settings.local.json` for existing hooks
3. Check for project-level skills in `.claude/skills/`
4. Identify project type by looking for signal files:
   - Go: `go.mod`, `internal/`, `cmd/`
   - Node/TypeScript: `package.json`, `tsconfig.json`, build config (vite/webpack/next)
   - Python: `requirements.txt`, `pyproject.toml`, `setup.py`
   - Rust: `Cargo.toml`, `src/main.rs`
   - Java/Kotlin: `pom.xml`, `build.gradle`, `build.gradle.kts`
   - .NET: `*.csproj`, `*.sln`
   - Monorepo: `.gitmodules`, `pnpm-workspace.yaml`, `lerna.json`, or multiple service dirs
5. Map the project's build/test/lint commands (from `Makefile`, `package.json` scripts, `README`, or CI config)

## Step 3: Gap Analysis

Compare what the project already has vs. what the insights recommend:

### 3.1 CLAUDE.md Gaps
Check if the project's CLAUDE.md includes:
- [ ] Multi-service architecture awareness (if monorepo)
- [ ] Database migration safety rules (if has migrations/)
- [ ] Bug fix protocol
- [ ] Fixing approach (residual references, backend-first)
- [ ] Code conventions (enum/DTO matching)

### 3.2 Hook Gaps
Check if `.claude/settings.json` or `.claude/settings.local.json` has hooks for
the project's stack. Common patterns (suggest only ones relevant to the detected stack):
- [ ] PostToolUse: build/typecheck verification after editing source files
- [ ] PreToolUse: guards against destructive operations (rm -rf, DROP TABLE, force-push)
- [ ] PreToolUse: stack-specific safety checks (route ordering, schema prefixes, migration safety)
- [ ] Stop: uncommitted changes warning (with snooze pattern)
- [ ] Stop: missing test file warning for new source files

### 3.3 Skill Gaps
Check if the project has relevant skills in `.claude/skills/` or referenced via
global skills. Suggest gaps based on the project's workflow — not a fixed list:
- [ ] `/bugfix` — structured multi-layer bug fix protocol
- [ ] Task/backlog workflow skills (create-tasks, execute-task, review-task)
- [ ] SDD pipeline skills if the project uses spec-driven development
- [ ] Project-specific generators (migration scaffolds, component scaffolds, test scaffolds)

**Do not recommend skills by fixed name.** Look at the project's actual workflow
and propose skills that would remove friction the insights file documents.

### 3.4 Memory Gaps
Check if `~/.claude/projects/*/memory/` has relevant memories:
- [ ] Architecture patterns documented
- [ ] Common gotchas captured
- [ ] UX preferences recorded

## Step 4: Generate Recommendations

Based on the gap analysis, generate a prioritized list:

### Priority 1: CLAUDE.md Additions
For each missing section, propose the exact text to add, adapted to the
project's specific stack and structure. Do NOT add generic text — tailor it:
- Use the project's actual service names
- Reference the project's actual build commands
- Match the project's language and framework

### Priority 2: Hook Suggestions
For each missing hook, propose the exact JSON to add to settings.json.
Only suggest hooks relevant to the project's actual stack. Examples:
- Source-file edits trigger the project's build/typecheck command
- Destructive-command guards (requires confirmation for rm -rf, DROP TABLE, force-push, etc.)
- Stack-specific safety hooks derived from the project's CI rules

### Priority 3: Workflow Improvements
Based on the project's characteristics, suggest:
- Parallel agent patterns for multi-service debugging
- Test-driven fix workflows
- Pre-deploy verification checklists

## Step 5: Apply (with confirmation)

For each recommendation:
1. Show the user what will be added/changed
2. Wait for confirmation before applying
3. Apply changes via Edit/Write tools
4. Summarize what was applied

## Output Format

```markdown
# Insights Analysis: {project-name}

## Current State
- Project type: {type}
- CLAUDE.md: {exists/missing}
- Hooks: {count} configured
- Skills: {count} available

## Recommendations

### CLAUDE.md ({N} additions suggested)
1. **{section name}** — {why it's relevant}
   > {proposed text preview}

### Hooks ({N} suggestions)
1. **{hook name}** — {what it does}
   > {JSON preview}

### Workflows ({N} patterns)
1. **{pattern name}** — {when to use}

## Apply?
Reply with the numbers you want to apply, or "all" to apply everything.
```

## Important Notes

- This skill is **interactive** — it proposes changes and waits for confirmation
- Tailor all recommendations to the specific project (don't copy generic text)
- Skip recommendations the project already implements
- Focus on highest-impact items first (based on friction frequency in insights)
- If the project already has comprehensive CLAUDE.md and hooks, say so

---

## Gotchas

### Never propose GENERIC recommendations

Every suggestion must be tailored to the current project: real service names, real build commands, real language conventions. Generic boilerplate ("Add a bug fix section to CLAUDE.md") produces noise, not value.

### Interactive: propose and wait for confirmation

Don't apply changes directly. Show the proposed diff, wait for "apply 1,2,4" or "all", and only then edit files. Auto-applying destroys trust in the skill.

### Skip recommendations the project already implements

Duplicating existing CLAUDE.md sections or re-adding hooks the project has is ruido. Read the current state first, diff against insights, propose only the delta.

### If the project is already in good shape, say so

Not every project needs recommendations. A project with comprehensive CLAUDE.md, relevant hooks, and appropriate skills should hear "your setup looks solid — nothing to add" instead of forced suggestions. Honesty > output volume.

### Insights file is required — without it, fall back to best practices explicitly

If `~/.claude/insights/usage-insights.md` (or the path in args) is missing, inform the user and use general best practices — but label clearly that recommendations are generic, not data-driven. Don't pretend insights exist when they don't.

### Skill gaps must be derived from actual friction, not a fixed list

Do not assume every project needs `/bugfix`, `/review-pr`, etc. Look at the insights file: which tasks keep getting re-explained? Which workflows have friction logged? THOSE are the skill candidates — not a checklist copied from another project.