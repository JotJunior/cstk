---
name: bugfix
description: 'Multi-layer bug investigation and fix (traces across services before patching). Triggers: "bugfix", "fix bug", "corrigir bug", "debug", "investigar bug". Skip for new feature work (use execute-task/specify).'
argument-hint: "[description of the bug, error message, or screenshot path]"
allowed-tools:
  - Read
  - Glob
  - Grep
  - Bash
  - Edit
  - Write
  - Agent
  - TaskCreate
  - TaskUpdate
---

# Bug Fix Skill

Structured bug fix protocol designed to eliminate cascading fix-reveal-fix cycles
by mapping the full data flow before touching any layer. Stack-agnostic — adapt
the commands and layer names to the project you are working in.

## Arguments

$ARGUMENTS should describe the bug: error message, observed behavior, expected
behavior, or path to a screenshot.

## Step 0: Determine Complexity

Assess bug scope before starting:

| Complexity | Signals | Approach |
|------------|---------|----------|
| **Single-layer** | Error in one file, one service | Sequential trace (Steps 1-8) |
| **Multi-service** | DTOs, enums, or events cross service boundaries | Parallel agent investigation (Step 3b) |
| **Ghost bug** | "Works on my machine", intermittent, post-deploy | Stale artifact focus (Step 2) |

For multi-service bugs, create tasks to track progress across services.

## Step 1: Understand the Bug

1. Read the error message or user description carefully
2. Identify which service/layer reported the error
3. If a screenshot was provided, analyze it
4. **Ask which layer owns the responsibility** before assuming where the fix goes
5. **For frontend-reported bugs**: verify whether the fix should be backend-side first — the most common wrong initial approach is fixing the frontend when the backend is the root cause

## Step 2: Check for Stale Artifacts

Before any debugging, eliminate ghost bugs. Use the commands appropriate to the
project stack — the pattern is "force rebuild + verify source matches running":

```bash
# Force rebuild (stack-specific)
# Examples:
#   Go:         go build ./...
#   Node:       rm -rf node_modules/.cache && npm run build
#   Rust:       cargo clean && cargo build
#   Java/JVM:   mvn clean compile
#   Python:     rm -rf __pycache__ dist build *.egg-info

# Verify dependencies haven't drifted
# Examples: go mod verify, npm ls, pip freeze, cargo tree

# Always check git state regardless of stack
git status --short
git log --oneline -3

# For production bugs, confirm deployed commit matches source
```

If stale artifacts found, warn the user before proceeding.

## Step 3: Trace the Full Data Flow

**CRITICAL**: Do NOT fix any single layer yet. Map the complete path first.

For each affected entity/endpoint, trace through ALL layers. Adapt the layer
names to the stack in use — the principle is "follow the data end-to-end":

### Server / backend layers (typical)
1. **Entry point / handler** — request parsing, routing, response shape
2. **DTO / request-response model** — field names, types, serialization tags
3. **Service / business logic** — validation, state transitions, enum values
4. **Repository / data access** — queries, column names, schema/namespace prefixes
5. **Schema / migration** — table definition, constraints, enum types
6. **Events / messaging** — publisher payload matches consumer expectations

### Client / frontend layers (typical)
1. **API client** — endpoint URL, request body shape, field names
2. **Type definitions** — types match server DTOs, case convention (camelCase vs snake_case)
3. **State layer** — query keys, cache invalidation, response transformations
4. **View / component** — data binding, error states, loading states

### Cross-boundary checks
1. **Inter-service clients** — other services calling the affected endpoint
2. **Event/message payloads** — publish/consume schemas align
3. **Shared enum values** — match across all layers (server code, database constraints, client code)
4. **Gateway / proxy** — routing rules, auth interception, CORS

### Step 3b: Parallel Agent Investigation (for multi-service bugs)

For complex bugs spanning 2+ services, launch parallel agents:

```
Agent 1: Backend contract audit
  - Read handlers, DTOs, migrations, enum CHECK constraints
  - List all field names and types at each boundary

Agent 2: Frontend contract audit
  - Read API service files, hooks, component types
  - List all field names and expected shapes

Agent 3: Event/messaging audit (if events involved)
  - Read publishers, consumers, event models
  - Verify routing keys and payload shapes
```

Synthesize findings from all agents BEFORE making any edits.

## Step 4: Identify ALL Mismatches

Create a list of every discrepancy found. Common categories (adapt to stack):

- **Field name mismatches** across case conventions (e.g., `full_name` vs `fullName` vs `FullName`)
- **Enum value mismatches** between code, database constraints, and API contract
- **Missing fields** in request/response models
- **Wrong types** at boundaries (string vs UUID, number vs string, nullable vs required)
- **Missing namespace/schema prefix** in database queries
- **Route ordering issues** (static routes must come before dynamic params in most routers)
- **Serialization tag mismatches** between server structs and client expectations
- **Case conversion** in middleware (client sends snake_case, server expects camelCase, or vice versa)
- **Optional field handling** (null vs omitted vs empty string)

## Step 5: Plan the Fix

Present the complete fix plan to the user BEFORE implementing:
- List every file that needs changes
- Describe what changes in each file
- Identify the correct order of changes
- Flag any migration needs (show SQL, never run without approval)

## Step 6: Implement

Apply changes in dependency order:
1. Database migrations (if needed) — show SQL, wait for approval
2. Backend domain/DTO changes
3. Backend service/repository changes
4. Backend handler changes
5. Frontend type changes
6. Frontend API/hook changes
7. Frontend component changes

**STOP-AND-REMAP RULE**: If implementing a fix reveals a new issue in another
layer, STOP immediately. Do not chase the new issue. Go back to Step 3, re-map
all remaining layers, update the fix plan, then continue. This prevents the
cascading fix-reveal-fix cycle that wastes the most time.

## Step 7: Verify

After implementing, run the stack-appropriate verification chain:

```bash
# Build (stack-specific)
#   Go:      go build ./...
#   Node:    npm run build   (or tsc --noEmit for TS)
#   Rust:    cargo build
#   Python:  python -m compileall .

# Tests (stack-specific)
#   Go:      go test ./... -count=1
#   Node:    npm test
#   Rust:    cargo test
#   Python:  pytest

# Lint / static analysis (stack-specific)
#   Go:      golangci-lint run ./... && go vet ./...
#   Node:    npm run lint && tsc --noEmit
#   Rust:    cargo clippy -- -D warnings
#   Python:  ruff check . && mypy .

# Grep for residual references to old code (any stack)
# Use Grep tool with the old identifier and appropriate file filter
```

### Test-Driven Verification (for recurring or complex bugs)

When the bug is subtle or has regressed before:
1. Write a failing test that captures the exact bug scenario
2. Write edge case tests for correct expected behavior
3. Implement the minimal fix
4. Run tests — iterate until all pass
5. Run full lint/build verification

## Step 8: Summarize

```markdown
## Bug Fix Summary

**Bug**: {description}
**Root cause**: {what was actually wrong}
**Services affected**: {list}

### Changes
| File | Change |
|------|--------|
| path/to/file.go | Fixed field name from X to Y |
| ... | ... |

### Verify after deploy
- [ ] {what to check in staging/production}
```

## Important Rules

- **NEVER fix just one layer and declare done** — always trace the full path
- **NEVER run migrations or destructive DB operations** without showing the SQL/commands and getting user approval
- **When a fix reveals another issue, STOP and re-map** before continuing (Step 6 rule)
- **Always grep for residual references** after any rename/refactor
- **For client-reported issues, check if the fix should be server-side first** — this is the #1 wrong initial approach
- **Don't overwrite complete files with minimal stubs** — preserve existing code
- **Check persistence-layer fields match code models** — missing fields in scan/bind targets cause silent bugs
- **Verify enum values match across all layers** (code, database constraints, client types) — mismatches are the most frequent multi-service bug

---

## Gotchas

### STOP-AND-REMAP when a fix reveals a new issue

If implementing a fix surfaces a problem in another layer, STOP. Do not chase the new issue. Go back to Step 3, re-map remaining layers, update the plan, then continue. Chasing emergent issues without remapping is the #1 cause of fix-reveal-fix cycles that burn hours.

### Don't fix one layer and declare done

The temptation is strong: one edit in the handler, tests green, ship. But the bug almost always crosses layers. Always trace the full path (request → persistence → response) before declaring the fix complete.

### For client-reported bugs, investigate server-side FIRST

The most common wrong approach: user reports "form shows wrong value", dev fixes client. Actual root cause: server response has wrong field name. Always ask "which layer owns this responsibility?" before editing.

### Always grep for residual references after rename/refactor

The old name lives in a config file, a comment, a test fixture, a generated type you forgot. Run a grep with the old identifier across the entire repo — not just the language you edited.

### NEVER run destructive DB operations without approval

Showing the SQL and waiting for explicit "go" is non-negotiable. Even in dev environments. A forgotten `WHERE` clause or a wrong schema name wipes data. The skill shows, approves, then runs — never the reverse.

### Enum drift across layers is silent and deadly

Server defines `status = "ACTIVE"`, database CHECK constraint allows `"active"`, client type uses `"Active"`. None throws a compile error, all three mismatch at runtime. When reviewing a bug that involves a state field, check all three spellings explicitly.

### Route order matters in most routers

In many routers (Chi, Fiber, Express), static routes must be registered before dynamic-param routes — otherwise `/users/me` gets captured by `/users/:id`. If debugging a 404 on what should be a static route, check the registration order.

### Don't overwrite files with minimal stubs

When editing, preserve existing code. Rewriting a 500-line handler with a 20-line stub "to simplify" destroys context the bug fix depends on. Use Edit for surgical changes; reserve Write for truly new files.

### Check DB binding fields match the code model

A struct with 8 fields scanning a 10-column row will bind only 8 and silently drop the other 2. The bug is invisible until a user notices missing data. Verify field-to-column alignment in scan/bind sites.