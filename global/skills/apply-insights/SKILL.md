---
name: apply-insights
description: 'Apply Claude Code usage insights to current project — improve CLAUDE.md, hooks, workflows. Triggers: "aplicar insights", "otimizar fluxo", "melhorar claude.md". Consumes the native /insights output (~/.claude/usage-data/facets/*.json) as PRIMARY data source via scripts/digest-facets.sh; falls back to curated ~/.claude/insights/usage-insights.md. This is the APPLY step, not the native /insights command.'
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

## Step 1: Load Insights (data-driven first)

There are TWO possible sources. **Prefer the facets digest** — it reflects the
user's ACTUAL recent sessions (current, structured, project-specific), whereas
the curated `.md` is hand-written and often stale / from a different project.

### Primary: facets digest (native `/insights` output)

The native `/insights` command writes per-session analyses to
`~/.claude/usage-data/facets/*.json` (fields: `goal_categories`, `outcome`,
`friction_counts`, `friction_detail`, `claude_helpfulness`,
`user_satisfaction_counts`, …). Aggregate them into a digest:

```bash
# Resolve the skill dir: installed copy first, repo source when developing.
DIGEST="$HOME/.claude/skills/apply-insights/scripts/digest-facets.sh"
[ -x "$DIGEST" ] || DIGEST="$(git rev-parse --show-toplevel 2>/dev/null)/global/skills/apply-insights/scripts/digest-facets.sh"
"$DIGEST"            # markdown digest on stdout; optional: --top N --samples N
```

If it prints a digest (non-empty stdout), use it as the **primary, data-driven
input**. The ranked `friction_counts` + concrete `friction_detail` samples are
the key signal for recommendations (which friction recurs, with examples).

### Fallback chain (graceful)

`digest-facets.sh` exits 0 with **empty stdout** when `jq` or the facets dir are
absent — so branch on emptiness:

1. **Facets digest** non-empty → use it (preferred).
2. Else read `~/.claude/insights/usage-insights.md` (curated; may be stale) — and
   say so to the user.
3. Else neither exists → general best practices, **explicitly labeled as generic
   / not data-driven**.

When both exist, prefer the digest (current data); you may cross-check the
curated `.md` for narrative context. Tell the user WHICH source you used.

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
and propose skills that would remove friction the insights data documents
(ranked `friction_counts` + `friction_detail` samples in the facets digest).

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

### Data source: facets digest first, curated .md fallback, then generic

Prefer `scripts/digest-facets.sh` (aggregates the native `/insights` facets —
current and project-specific). Only when its stdout is empty (no `jq`, no facets
dir) fall back to the curated `~/.claude/insights/usage-insights.md`; when that
too is missing, use general best practices but **label them clearly as generic /
not data-driven**. Don't pretend insights exist when they don't, and don't lean
on a stale curated `.md` when fresh facets are available — that was the original
bug (April-era summary applied to a different stack).

### Skill gaps must be derived from actual friction, not a fixed list

Do not assume every project needs `/bugfix`, `/review-pr`, etc. Look at the insights data (the facets digest's `friction_counts` / `friction_detail`, or the curated file): which tasks keep getting re-explained? Which workflows have friction logged? THOSE are the skill candidates — not a checklist copied from another project.