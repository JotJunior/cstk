---
name: go-review-service
description: Audit a GOB Go microservice against all project conventions and patterns
allowed-tools:
  - Read
  - Glob
  - Grep
  - Bash
---

# Go Review Service

Perform a comprehensive read-only audit of a GOB Go microservice, checking 17 conventions. Outputs a structured PASS/FAIL/WARNING report with line references.

## Trigger Phrases

"review service", "audit service", "validar servico", "check service", "verificar servico", "checar servico"

## Arguments

$ARGUMENTS should specify:
- **Service name** (e.g., `gob-member-service`) — required
- **Focus area** (optional) — e.g., "middleware", "routes", "repository" to narrow the audit

## Pre-Flight

Determine the service root:
```
services/{service-name}/
```

Read these files first (in parallel where possible):
1. `cmd/api/main.go` — middleware order, wiring, shutdown
2. `internal/factory/factory.go` — repository factory
3. `internal/repository/repository.go` — interfaces
4. `internal/handler/*.go` — route registration
5. `go.mod` — module path, dependencies
6. `migrations/` — list files for schema reference

## Checks (17 total)

For each check, output one of:
- **PASS** — convention followed correctly
- **FAIL** — convention violated (include file:line reference and what's wrong)
- **WARNING** — partially followed or uncertain (include details)
- **N/A** — not applicable to this service

---

### Check 1: Middleware Order in main.go

**Expected order** (top to bottom in main.go):
1. `recover.New()`
2. `requestid.New()`
3. `apmfiber.Middleware(apmfiber.WithTracer(tracer))` — after requestid, before logging (unconditional/nil-safe; rollout-window dual-accept detailed in Check 3)
4. `middleware.LoggingWithLogger(log)` or `middleware.Logging()`
5. `cors.New(...)` — with AllowOrigins, AllowHeaders, AllowMethods, AllowCredentials
6. `middleware.DryRun(...)` — if service supports dry-run
7. `middleware.DryRunFinalizer()` — if dry-run present
8. `middleware.AuditPublisher(...)` — after cors/dryrun, before endpoints

**Search**: Look for `app.Use(` calls in main.go. Verify order matches.

### Check 2: Audit Middleware

- Separate RabbitMQ connection (`rabbitmq.NewFromURL`)
- Uses `middleware.AuditExchange` constant
- Non-blocking: wrapped in `if rmqURL != ""` with warning on failure
- Placed AFTER cors and BEFORE health/ready/version endpoints
- `defer auditRMQ.Close()` present

**Search**: `AuditPublisher` in main.go.

### Check 3: Elastic APM

- `observability.ElasticAPMTracer(cfg, log)` called, returns `(tracer, err)` (non-fatal on error — Resilience Class A: degraded/non-recording, not a boot failure)
- `apmfiber.Middleware(apmfiber.WithTracer(tracer))` present, unconditional — `WithTracer(nil)` is nil-safe (falls back to `apm.DefaultTracer()`), no `!= nil` guard needed
- `defer observability.ShutdownElasticAPM(tracer)` present
- Placed after `requestid` and before `logging` middleware

**Rollout-window dual-accept (FR-007)**: while the platform-wide code migration to
Elastic APM is in progress across the 20 repositories (commons + 19 services), this
check PASSes if the service shows the Elastic signals above **OR** the legacy signals
below in isolation — it FAILs only when **neither** is present. This is a documented,
temporary exception to the zero-New-Relic-references goal (spec.md SC-001), ratified to
close once code migration completes (spec.md Clarifications — "aperto final").

- Legacy signals (accepted ONLY during the rollout window): `observability.NewRelicApp(serviceName, cfg, log)` called; `nrfiber.Middleware(nrApp)` present (historically conditional on `nrApp != nil`); `defer observability.ShutdownNewRelic(nrApp)` present.

**Search**: Elastic — `ElasticAPMTracer`, `apmfiber`, `ShutdownElasticAPM` in main.go.
Legacy (rollout window only) — `NewRelicApp`, `nrfiber`, `ShutdownNewRelic` in main.go.

**Aperto final (runbook task 6.5)**: once the operator confirms code migration is
complete across all 20 repositories, DELETE the "Legacy signals" bullet and the second
half of the Search line above — this check then requires the Elastic signals
exclusively and FAILs any service still showing New Relic wiring.

### Check 4: Route Registration Order

For each handler's `RegisterRoutes()` method:
- Static routes (e.g., `/types`, `/counts`, `/search`) MUST come BEFORE parameterized routes (`/:id`)
- Sub-groups (e.g., `/groups`) MUST be registered BEFORE `/:id` catch-all

**FAIL if**: Any `/:id` or `/:param` route appears before a static route at the same level.

**Search**: All `RegisterRoutes` methods in `internal/handler/`.

### Check 5: Repository Interfaces

- `context.Context` is the first parameter in every method
- `FindByID` returns `(*domain.X, error)` — nil/nil when not found
- Filter structs exist for List methods
- Count methods present where List exists
- Interfaces are in `internal/repository/repository.go`

**Search**: `repository.go` file, look for interface definitions.

### Check 6: Postgres Implementation

- Uses `GetContext` (single row) and `SelectContext` (multiple rows)
- `sql.ErrNoRows` returns `nil, nil` (not wrapped as error)
- Schema prefix on all table references (e.g., `member.members`)
- Uses `$1, $2, ...` positional parameters (not `?`)
- Row structs with `db:""` tags separate from domain structs
- `toDomain()` converter methods on row structs

**Search**: `internal/repository/postgres/*.go` files.

### Check 7: Service Error Patterns

- Package-level sentinel errors: `var ErrXxxNotFound = errors.New("...")`
- No HTTP status codes in service layer
- Services return domain objects, not DTOs
- Constructor accepts repository interfaces (not concrete types)

**Search**: `internal/service/*.go` files, look for `var Err` and return types.

### Check 8: Handler Error Dispatch

- Uses `errors.Is()` for sentinel error matching
- Returns `dto.ErrorResponse` with appropriate HTTP status codes
- Claims extraction via `middleware.GetUserID(c)`, `middleware.GetClaims(c)`
- Proper `c.Status(xxx).JSON(dto.ErrorResponse{...})` pattern

**Search**: `internal/handler/*.go` for `errors.Is` and `ErrorResponse`.

### Check 9: Factory Pattern

- `Repositories` struct holds all repo instances
- `NewRepositories(db)` constructor creates all repos
- `NewDryRunRepositories(db)` for dry-run mode (if applicable)
- Getter methods for each repository
- `RepositoryFactory` with `isDryRun` flag (if dry-run supported)

**Search**: `internal/factory/factory.go`.

### Check 10: JSON/DB Tag Conventions

- JSON tags: `snake_case` (e.g., `json:"lodge_id"`)
- DB tags: `snake_case` matching column names (e.g., `db:"lodge_id"`)
- `omitempty` on optional/nullable fields
- `db:"-"` on computed/relation fields
- No `json:"-"` on fields that should be visible in API

**Search**: Domain structs in `internal/domain/*.go`, check tags.

### Check 11: Health/Ready/Version Endpoints

All three must be present:
- `GET /health` — returns 200 OK
- `GET /ready` — pings DB (`db.PingContext`) and returns health status
- `GET /version` — returns service version info

**Search**: `/health`, `/ready`, `/version` in main.go.

### Check 12: Fiber Configuration

- `EnableTrustedProxyCheck: true`
- `TrustedProxies` configured (e.g., private network ranges)
- `ProxyHeader: "X-Real-Ip"` or `"X-Forwarded-For"`
- These are in `fiber.Config{}` in main.go

**Search**: `fiber.New(` or `fiber.Config` in main.go.

### Check 13: Graceful Shutdown

- Signal handling: `signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)`
- Context cancellation for background goroutines
- Consumer stop (`consumer.Stop()`) if RabbitMQ consumer exists
- Server shutdown: `app.ShutdownWithContext(ctx)` or `app.Shutdown()`
- Deferred resource cleanup (DB close, RabbitMQ close, APM shutdown)

**Search**: `signal.Notify`, `Shutdown`, `defer` in main.go.

### Check 14: go.mod Module Path

- Must follow pattern: `github.com/gob/gob-{service-name}`
- Example: `github.com/gob/gob-process-service`
- Go version should be 1.21+

**Search**: First line of `go.mod`.

### Check 15: Storage Integration (if S3/file uploads used)

- Uses `storage.Storage` interface from `gob-go-commons/pkg/storage/`
- Factory creates storage via `storage.NewFromConfig(cfg)` (auto-selects S3 or local)
- Upload method: `Upload(ctx, key, reader, size, contentType)` — NOT `Put`
- Presigned URL: `PresignedGetURL(ctx, key, expiry)` — NOT `GetPresignedURL`
- Key pattern: `{service}/{category}/{entityID}/{uuid}-{filename}.ext`
- File validation: uses `storage.ValidateFileType()` and `storage.ValidateFileSize()`
- Handler constructor accepts `storage.Storage` parameter

**Search**: `storage.Storage` in handler/service files.
**N/A** if service doesn't handle file uploads.

### Check 16: Publisher Pattern (if RabbitMQ publishing)

- Uses `AMQPPublisher` + `NoopPublisher` (graceful degradation when RabbitMQ unavailable)
- Service has `SetPublisher()` method or accepts publisher in constructor
- Publisher interface defined in service layer (not importing messaging package directly)
- Best-effort publish: errors logged as Warning, not returned to caller
- Exchange declared as `topic` and `durable`

**Search**: `Publisher`, `AMQPPublisher`, `NoopPublisher` in service and messaging files.
**N/A** if service doesn't publish events.

### Check 17: Structured Logging

Verify logging follows the project standards (see CLAUDE.md "Structured Logging Standards"):

**15a. Repository layer has logger injected**:
- Every repository struct must have a `log *logger.Logger` field
- Constructor must accept `*logger.Logger` parameter
- **FAIL** if any repository struct has no logger field

**15b. Repository methods have entry/exit/duration logging**:
- Every public method must log on entry (Debug) with `entity`, `operation`
- Every public method must log on exit (Debug) with `duration_ms`
- Error paths must log with `WithError(err)` before returning
- `FindByID` not-found path must log Debug (not Error)
- **FAIL** if any public method has no logging at all
- **WARNING** if logging exists but is missing `duration_ms`

**15c. Service layer has logging**:
- Every service struct must have a `log *logger.Logger` field
- Create/Update/Delete methods must log Info on success with `entity_id`
- Error paths must log with `WithError(err)`
- **FAIL** if service has no logger, **WARNING** if methods are partially logged

**15d. Handler layer has logging**:
- Error paths must log with `WithRequestID(requestID)`, `WithError(err)`
- Must use `entity`, `operation` fields
- **WARNING** if handlers don't log errors (they may rely on middleware, which is acceptable)

**15e. No anti-patterns**:
- No `fmt.Println` or `log.Println` (standard library) — must use `logger.Logger`
- No `logger.Default()` in production code (inject via constructor)
- No sensitive data in logs (CPF, password, token, email)
- **FAIL** if `fmt.Println` or `log.Println` found in non-test code

**Search**: All `.go` files in `internal/`, look for `log.`, `logger.`, `fmt.Print`, `log.Print`.

---

## Output Format

```
# Service Audit: {service-name}
Date: {current date}

## Summary
PASS: X/17 | FAIL: Y/17 | WARNING: Z/17 | N/A: W/17

## Results

### 1. Middleware Order
**PASS** — Correct order: recover → requestid → apmfiber → logging → cors → dryrun → audit
(main.go:45-82)

### 2. Audit Middleware
**FAIL** — Missing separate RabbitMQ connection. Audit reuses existing connection.
(main.go:95)

### 3. Elastic APM
**PASS** — Elastic signals present: `apmfiber.Middleware(apmfiber.WithTracer(tracer))` unconditional/nil-safe, `ElasticAPMTracer`/`ShutdownElasticAPM` wired
(main.go:104-108, 375)

... (continue for all 17 checks)

## Recommendations
1. [Highest priority fixes]
2. [Medium priority improvements]
3. [Low priority suggestions]
```

## Important Notes

- This skill is **read-only** — it does NOT modify any files
- Always provide file:line references for FAIL and WARNING results
- When a check has sub-items, list which sub-items pass and which fail
- If the service doesn't have certain features (e.g., no RabbitMQ consumer), mark related checks as N/A
- Focus on actual convention violations, not style preferences