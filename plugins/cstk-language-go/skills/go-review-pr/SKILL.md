---
name: go-review-pr
description: |
  Review all changes in the current branch against GOB project conventions before opening a PR.
  Diff-aware: only analyzes what changed, not the entire codebase.
  Triggers: "review pr", "revisar pr", "pre-pr check", "review branch", "revisar branch",
  "checar antes do pr", "quality gate".
argument-hint: "[base branch, default: main]"
allowed-tools:
  - Read
  - Glob
  - Grep
  - Bash
---

# Go Review PR

Perform a diff-aware quality review of ALL changes in the current branch before opening a PR. This is the final quality gate — it checks everything that `go-review-service` checks, but scoped to the diff only.

## Arguments

$ARGUMENTS should specify:
- **Base branch** (optional, default: `main`) — the branch to compare against

## Step 1: Gather the Diff

```bash
# Get the base branch (default: main)
BASE=${1:-main}

# All changed files in this branch vs base
git diff --name-only $BASE...HEAD

# Full diff for context
git diff $BASE...HEAD

# Commits in this branch
git log --oneline $BASE..HEAD
```

Categorize changed files:
- **Go source files** (*.go, excluding *_test.go)
- **Go test files** (*_test.go)
- **Migration files** (migrations/*.sql)
- **Frontend files** (*.ts, *.tsx)
- **Config files** (*.json, *.yaml, *.toml, go.mod, go.sum)
- **Documentation** (*.md)

## Step 2: Per-Service Analysis

For each service with changed files, read the changed files and run these checks:

### Check A: Compilation
```bash
cd services/{service} && go build ./...
```

### Check B: Tests Pass
```bash
cd services/{service} && go test ./... -count=1 -timeout 60s
```

### Check C: Lint
```bash
cd services/{service} && golangci-lint run ./... 2>&1 || true
```

## Step 3: Convention Checks (on diff only)

For each changed Go file, verify:

### 3.1 Code in English
- All new variable names, function names, comments, error messages are in English
- **FAIL** if Portuguese found in code (excluding string literals for user-facing messages)

### 3.2 JSON Tags snake_case
- All new struct fields with `json:""` tags use snake_case
- **FAIL** if camelCase or PascalCase found in json tags

### 3.3 DB Tags Match Columns
- All new struct fields with `db:""` tags use snake_case matching column names
- Cross-reference with migration files if available

### 3.4 Schema Prefix in SQL
- All SQL queries in repository files use `{schema}.{table}` format
- **FAIL** if any bare table name found (e.g., `FROM members` instead of `FROM member.members`)

### 3.5 Route Registration Order
- In handler files: static routes BEFORE parameterized `/:id` routes
- Sub-groups BEFORE `/:id` catch-all
- **FAIL** if order is wrong (Fiber trie conflict)

### 3.6 Error Patterns
- Service layer: sentinel errors (`var ErrXxxNotFound`), no HTTP codes
- Handler layer: `errors.Is()` dispatch, `dto.ErrorResponse` returns
- Repository layer: `sql.ErrNoRows` → `nil, nil`

### 3.7 Import Hierarchy
Verify no import cycles:
```
domain → (nothing)
dto → domain (if needed)
repository → domain
service → repository + domain
handler → service + dto + domain
factory → repository + postgres
```
**FAIL** if handler imports repository directly, or service imports handler, etc.

### 3.8 Context First Parameter
- All repository and service methods have `context.Context` as first parameter
- **FAIL** if any public method is missing context

### 3.9 Middleware Order (if main.go changed)
Verify order: recover → requestid → nrfiber → logging → cors → [dryrun] → audit → endpoints

### 3.10 Test Coverage
- Every new .go file (excluding main.go, migrations, mocks) should have a corresponding _test.go
- New service methods should have test cases for: happy path, not found, validation error, repo error

## Step 4: Migration Checks (if migrations changed)

### 4.1 Naming Convention
- Format: `{NNN}_{descriptive_name}.up.sql` / `{NNN}_{descriptive_name}.down.sql`
- Number is sequential (no gaps, no duplicates)
- Up and down files exist as pairs

### 4.2 Schema Prefix
- CREATE TABLE uses `{schema}.{table_name}`
- All references use schema prefix

### 4.3 Rollback Safety
- Down migration has `DROP TABLE IF EXISTS ... CASCADE` or appropriate reversal
- Down migration reverses ALL changes in up migration

### 4.4 CIM Format
- Any CIM values in seed data use 7-digit zero-padded format (e.g., `'0051522'`)
- Uses `LPAD` if converting from integer sources

### 4.5 Idempotency
- Uses `IF NOT EXISTS` for CREATE TABLE/INDEX
- Uses `DO $$ ... IF NOT EXISTS` for enum types

## Step 5: Frontend Checks (if frontend files changed)

### 5.1 API Client Usage
- Uses `apiClient` (not raw fetch/axios/ky)
- snake_case in request bodies (backend expects it)
- FormData uploads use `{ body: data }` (not `{ json: data }`)
- `transformResponse` camelCase conversion accounted for in types

### 5.2 Portuguese Accents
- UI text uses proper Portuguese accents (é, ã, ç, ô, í)
- Lodge display format: "No {number} - {name}" (not just name)

### 5.3 Type Safety
- No `any` types where a proper type could be used
- Response types match backend DTOs
- Query key factories pattern used (`fooKeys.all/lists/detail`)

### 5.4 Shared Components
- Uses `PageHeader` for page titles (not custom headers)
- Uses `ServerPagination` for tables (not custom pagination)
- Uses `useConfirmDialog` for destructive actions (not inline confirm)
- CRUD forms on dedicated pages, NOT modals

### 5.5 Navigation
- Parent nav items use `end: true` to prevent highlight on child routes
- New routes registered in `src/config/navigation.ts`

## Step 6: Cross-Cutting Checks

### 6.1 go.mod Consistency
- No replace directives (unless justified — `go-commons` replace is expected)
- `go mod tidy` was run (no extra/missing deps)

### 6.2 Submodule State
- If changes span multiple services, submodule pointers are updated

### 6.3 CLAUDE.md Updates
- If new routes/endpoints added, check if routing table in CLAUDE.md needs update
- If new service added, check if service table needs update

### 6.4 Storage API (if S3/storage used)
- Uses `storage.Storage` interface (not direct S3 calls)
- Key pattern: `{service}/{category}/{entityID}/{uuid}-{filename}.ext`
- Upload uses `Upload(ctx, key, reader, size, contentType)` — NOT `Put`
- Presigned URL uses `PresignedGetURL(ctx, key, expiry)` — NOT `GetPresignedURL`

### 6.5 RabbitMQ Events (if publisher/consumer changed)
- Publisher uses `AMQPPublisher` + `NoopPublisher` (graceful degradation)
- Consumer uses `ExchangeDeclarePassive` for foreign exchanges (not `ExchangeDeclare`)
- Channel reopened after passive declare failure
- Return `nil` for unrecognized event routing keys (not error)

### 6.6 Inter-Service Clients (if client/ changed)
- Authenticated with `X-Internal-Key` header
- Key from ETCD `INTERNAL_API_KEY` or `SHARED_INTERNAL_API_KEY`
- Graceful degradation: service continues if external service unavailable

## Output Format

```markdown
# PR Review: {branch-name}
Date: {date}
Base: {base-branch}
Changes: {N} files across {M} services

## Build & Test
| Service | Build | Tests | Lint |
|---------|-------|-------|------|
| gob-xxx-service | PASS | PASS (12/12) | PASS |
| gob-yyy-service | FAIL | - | - |

## Convention Checks
| # | Check | Status | Details |
|---|-------|--------|---------|
| A | Code in English | PASS | |
| B | JSON tags snake_case | FAIL | dto/member.go:45 — `firstName` should be `first_name` |
| C | Schema prefix | PASS | |
| ... | ... | ... | ... |

## Migration Checks
| # | Check | Status | Details |
|---|-------|--------|---------|
| 1 | Naming | PASS | |
| 2 | Rollback | WARNING | 015_add_column.down.sql missing |
| ... | ... | ... | ... |

## Summary
- **PASS**: X checks
- **FAIL**: Y checks (must fix before merge)
- **WARNING**: Z checks (review recommended)

## Required Actions
1. [List of things that MUST be fixed]

## Recommendations
1. [List of things that SHOULD be fixed]
```

## Important Notes

- This skill is **read-only** — it does NOT modify any files
- Always provide `file:line` references for FAIL and WARNING results
- If the branch has no Go changes, skip Go-specific checks
- If the branch has no migration changes, skip migration checks
- Run Build & Test checks first — if build fails, skip convention checks for that service
- Be thorough but avoid false positives — when uncertain, use WARNING not FAIL