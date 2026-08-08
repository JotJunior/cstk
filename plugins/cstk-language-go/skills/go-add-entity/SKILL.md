---
name: go-add-entity
description: Add a full CRUD vertical slice (domain, DTO, repository, service, handler, migration, factory wiring) to an existing GOB Go microservice
allowed-tools:
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - Bash
---

# Go Add Entity

Generate a complete CRUD vertical slice for a new entity in an existing GOB Go microservice. This creates 8-10 files following all project conventions.

## Trigger Phrases

"add entity", "new entity", "nova entidade", "add CRUD", "adicionar recurso", "add resource"

## Arguments

$ARGUMENTS should specify:
- **Service name** (e.g., `gob-member-service`) — required
- **Entity name** (e.g., `ServiceGroup`, `Topic`) — required, in PascalCase
- **Fields/columns** — list of fields with types (can be informal, will be normalized)
- **Relations** (optional) — foreign keys to other entities
- **Features** (optional) — e.g., "with soft delete", "with status enum", "with search"

## Pre-Flight Reads

Before generating ANY code, read these files from the target service (in parallel):

1. **`go.mod`** — module path (e.g., `github.com/gob/gob-process-service`)
2. **`internal/factory/factory.go`** — existing repos, factory pattern in use
3. **`internal/repository/repository.go`** — existing interfaces, import paths
4. **`migrations/`** (ls directory) — next migration number
5. **`cmd/api/main.go`** — wiring point, existing services/handlers, route groups
6. **`internal/dto/dto.go`** — existing shared types (ErrorResponse, Response, Pagination)
7. **`internal/domain/`** (ls directory) — existing domain models for reference

Also determine:
- **Schema name** from service-to-schema mapping (see go-add-migration skill)
- **Table name**: plural snake_case of entity (e.g., `ServiceGroup` → `service_groups`)
- **Next migration number**: highest existing + 1, zero-padded to 3 digits

## Files to Generate

### 1. Domain Model — `internal/domain/{entity_snake}.go`

```go
package domain

import (
    "time"
    "github.com/google/uuid"
)

// {Entity} represents a {description}.
type {Entity} struct {
    ID          uuid.UUID  `json:"id" db:"id"`
    // ... fields with both json and db tags ...
    CreatedAt   time.Time  `json:"created_at" db:"created_at"`
    UpdatedAt   *time.Time `json:"updated_at,omitempty" db:"updated_at"`
}
```

**Rules**:
- Both `json:""` and `db:""` tags on every field
- `json` tags: `snake_case`, `omitempty` on optional/nullable fields
- `db` tags: `snake_case` matching exact DB column names
- Nullable fields: use pointers (`*string`, `*time.Time`, `*uuid.UUID`)
- UUID fields: `uuid.UUID` from `github.com/google/uuid`
- JSON columns: `json.RawMessage` with `omitempty`
- Status enums: define as `type {Entity}Status string` with constants
- Add domain helper methods if business logic applies

### 2. DTO — `internal/dto/{entity_snake}.go`

```go
package dto

import "github.com/google/uuid"

// Create{Entity}Request is the input for creating a new {entity}.
type Create{Entity}Request struct {
    // Fields without ID, CreatedAt, UpdatedAt
    // Use json tags in snake_case matching backend expectation
    Name        string     `json:"name" validate:"required"`
    Description string     `json:"description,omitempty"`
    ParentID    *uuid.UUID `json:"parent_id,omitempty"`
}

// Update{Entity}Request is the input for updating an existing {entity}.
type Update{Entity}Request struct {
    // Only updatable fields, all optional (pointers)
    Name        *string `json:"name,omitempty"`
    Description *string `json:"description,omitempty"`
}
```

**Rules**:
- Do NOT duplicate `ErrorResponse`, `Response`, `Pagination` — they exist in `dto.go`
- Request DTOs use `json` tags in `snake_case`
- Create requests: required fields as values, optional as pointers
- Update requests: ALL fields as pointers (partial update support)
- If a response DTO is needed (flattening relations), add `New{Entity}Response()` constructor
- Add `validate` tags for required fields if the service uses a validator

### 3. Repository Interface — append to `internal/repository/repository.go`

```go
// {Entity}Repository defines persistence operations for {entities}.
type {Entity}Repository interface {
    FindByID(ctx context.Context, id uuid.UUID) (*domain.{Entity}, error)
    List(ctx context.Context, filter *{Entity}Filter) ([]*domain.{Entity}, error)
    Count(ctx context.Context, filter *{Entity}Filter) (int64, error)
    Create(ctx context.Context, entity *domain.{Entity}) error
    Update(ctx context.Context, entity *domain.{Entity}) error
    Delete(ctx context.Context, id uuid.UUID) error
}

// {Entity}Filter contains filtering and pagination options.
type {Entity}Filter struct {
    Search    string
    Status    string
    Limit     int
    Offset    int
    SortBy    string
    SortOrder string
}
```

**Rules**:
- `context.Context` is ALWAYS the first parameter
- `FindByID` returns `(*domain.{Entity}, error)` — nil/nil when not found
- Append to existing file, don't overwrite
- Import paths must match existing imports in the file
- Filter struct in same file, near the interface

### 4. Postgres Implementation — `internal/repository/postgres/{entity_snake}_repository.go`

```go
package postgres

import (
    "context"
    "database/sql"
    "fmt"
    "strings"
    "time"

    "github.com/google/uuid"
    "github.com/jmoiron/sqlx"

    "github.com/gob/gob-go-commons/pkg/logger"

    "github.com/gob/gob-{service}/internal/domain"
    "github.com/gob/gob-{service}/internal/repository"
)

type {Entity}Repository struct {
    db  *sqlx.DB
    log *logger.Logger
}

func New{Entity}Repository(db *sqlx.DB, log *logger.Logger) *{Entity}Repository {
    return &{Entity}Repository{db: db, log: log}
}

// Internal row struct for DB scanning
type {entity}Row struct {
    ID        uuid.UUID      `db:"id"`
    Name      string         `db:"name"`
    Desc      sql.NullString `db:"description"`
    CreatedAt time.Time      `db:"created_at"`
    UpdatedAt *time.Time     `db:"updated_at"`
}

func (r *{entity}Row) toDomain() *domain.{Entity} {
    return &domain.{Entity}{
        ID:          r.ID,
        Name:        r.Name,
        Description: r.Desc.String,
        CreatedAt:   r.CreatedAt,
        UpdatedAt:   r.UpdatedAt,
    }
}

func (r *{Entity}Repository) FindByID(ctx context.Context, id uuid.UUID) (*domain.{Entity}, error) {
    start := time.Now()
    r.log.WithField("entity", "{entity}").
        WithField("operation", "find_by_id").
        WithField("entity_id", id.String()).
        Debug("Querying database")

    var row {entity}Row
    query := `SELECT * FROM {schema}.{table} WHERE id = $1`
    if err := r.db.GetContext(ctx, &row, query, id); err != nil {
        if err == sql.ErrNoRows {
            r.log.WithField("entity", "{entity}").
                WithField("operation", "find_by_id").
                WithField("duration_ms", time.Since(start).Milliseconds()).
                Debug("Entity not found")
            return nil, nil
        }
        r.log.WithError(err).
            WithField("entity", "{entity}").
            WithField("operation", "find_by_id").
            WithField("duration_ms", time.Since(start).Milliseconds()).
            Error("Database query failed")
        return nil, err
    }

    r.log.WithField("entity", "{entity}").
        WithField("operation", "find_by_id").
        WithField("duration_ms", time.Since(start).Milliseconds()).
        Debug("Query completed")
    return row.toDomain(), nil
}

func (r *{Entity}Repository) List(ctx context.Context, filter *repository.{Entity}Filter) ([]*domain.{Entity}, error) {
    start := time.Now()
    r.log.WithField("entity", "{entity}").
        WithField("operation", "list").
        Debug("Querying database")

    var rows []*{entity}Row
    query := `SELECT * FROM {schema}.{table} WHERE 1=1`
    args := []any{}
    argIdx := 1

    if filter.Search != "" {
        query += fmt.Sprintf(` AND (name ILIKE $%d)`, argIdx)
        args = append(args, "%"+filter.Search+"%")
        argIdx++
    }

    if filter.Status != "" {
        query += fmt.Sprintf(` AND status = $%d`, argIdx)
        args = append(args, filter.Status)
        argIdx++
    }

    // Sorting
    sortBy := "created_at"
    sortOrder := "DESC"
    if filter.SortBy != "" {
        sortBy = filter.SortBy
    }
    if filter.SortOrder != "" {
        sortOrder = strings.ToUpper(filter.SortOrder)
    }
    query += fmt.Sprintf(` ORDER BY %s %s`, sortBy, sortOrder)

    // Pagination
    if filter.Limit > 0 {
        query += fmt.Sprintf(` LIMIT $%d`, argIdx)
        args = append(args, filter.Limit)
        argIdx++
    }
    if filter.Offset > 0 {
        query += fmt.Sprintf(` OFFSET $%d`, argIdx)
        args = append(args, filter.Offset)
        argIdx++
    }

    if err := r.db.SelectContext(ctx, &rows, query, args...); err != nil {
        r.log.WithError(err).
            WithField("entity", "{entity}").
            WithField("operation", "list").
            WithField("duration_ms", time.Since(start).Milliseconds()).
            Error("Database query failed")
        return nil, err
    }

    result := make([]*domain.{Entity}, len(rows))
    for i, row := range rows {
        result[i] = row.toDomain()
    }

    r.log.WithField("entity", "{entity}").
        WithField("operation", "list").
        WithField("result_count", len(result)).
        WithField("duration_ms", time.Since(start).Milliseconds()).
        Debug("Query completed")
    return result, nil
}

func (r *{Entity}Repository) Count(ctx context.Context, filter *repository.{Entity}Filter) (int64, error) {
    start := time.Now()
    query := `SELECT COUNT(*) FROM {schema}.{table} WHERE 1=1`
    args := []any{}
    argIdx := 1

    if filter.Search != "" {
        query += fmt.Sprintf(` AND (name ILIKE $%d)`, argIdx)
        args = append(args, "%"+filter.Search+"%")
        argIdx++
    }

    if filter.Status != "" {
        query += fmt.Sprintf(` AND status = $%d`, argIdx)
        args = append(args, filter.Status)
        argIdx++
    }

    var count int64
    if err := r.db.GetContext(ctx, &count, query, args...); err != nil {
        r.log.WithError(err).
            WithField("entity", "{entity}").
            WithField("operation", "count").
            WithField("duration_ms", time.Since(start).Milliseconds()).
            Error("Database count query failed")
        return 0, err
    }

    r.log.WithField("entity", "{entity}").
        WithField("operation", "count").
        WithField("result_count", count).
        WithField("duration_ms", time.Since(start).Milliseconds()).
        Debug("Count query completed")
    return count, nil
}

func (r *{Entity}Repository) Create(ctx context.Context, entity *domain.{Entity}) error {
    start := time.Now()
    r.log.WithField("entity", "{entity}").
        WithField("operation", "create").
        WithField("entity_id", entity.ID.String()).
        Debug("Inserting into database")

    query := `
        INSERT INTO {schema}.{table} (id, name, description, created_at)
        VALUES ($1, $2, $3, $4)`
    _, err := r.db.ExecContext(ctx, query,
        entity.ID, entity.Name, entity.Description, entity.CreatedAt)
    if err != nil {
        r.log.WithError(err).
            WithField("entity", "{entity}").
            WithField("operation", "create").
            WithField("duration_ms", time.Since(start).Milliseconds()).
            Error("Database insert failed")
        return err
    }

    r.log.WithField("entity", "{entity}").
        WithField("operation", "create").
        WithField("entity_id", entity.ID.String()).
        WithField("duration_ms", time.Since(start).Milliseconds()).
        Debug("Insert completed")
    return nil
}

func (r *{Entity}Repository) Update(ctx context.Context, entity *domain.{Entity}) error {
    start := time.Now()
    now := time.Now()
    entity.UpdatedAt = &now
    query := `
        UPDATE {schema}.{table}
        SET name = $2, description = $3, updated_at = $4
        WHERE id = $1`
    _, err := r.db.ExecContext(ctx, query,
        entity.ID, entity.Name, entity.Description, entity.UpdatedAt)
    if err != nil {
        r.log.WithError(err).
            WithField("entity", "{entity}").
            WithField("operation", "update").
            WithField("entity_id", entity.ID.String()).
            WithField("duration_ms", time.Since(start).Milliseconds()).
            Error("Database update failed")
        return err
    }

    r.log.WithField("entity", "{entity}").
        WithField("operation", "update").
        WithField("entity_id", entity.ID.String()).
        WithField("duration_ms", time.Since(start).Milliseconds()).
        Debug("Update completed")
    return nil
}

func (r *{Entity}Repository) Delete(ctx context.Context, id uuid.UUID) error {
    start := time.Now()
    query := `DELETE FROM {schema}.{table} WHERE id = $1`
    _, err := r.db.ExecContext(ctx, query, id)
    if err != nil {
        r.log.WithError(err).
            WithField("entity", "{entity}").
            WithField("operation", "delete").
            WithField("entity_id", id.String()).
            WithField("duration_ms", time.Since(start).Milliseconds()).
            Error("Database delete failed")
        return err
    }

    r.log.WithField("entity", "{entity}").
        WithField("operation", "delete").
        WithField("entity_id", id.String()).
        WithField("duration_ms", time.Since(start).Milliseconds()).
        Debug("Delete completed")
    return nil
}
```

**Rules**:
- Separate `{entity}Row` struct for DB scanning (use `sql.NullString`, `sql.NullInt64`, `[]byte` for JSON)
- `toDomain()` method on row struct to convert to domain model
- `GetContext` for single row, `SelectContext` for multiple rows
- `sql.ErrNoRows` → return `nil, nil` (NOT an error)
- Schema-prefixed tables: `{schema}.{table}` (e.g., `process.service_groups`)
- Positional parameters: `$1, $2, $3...` (NOT `?`)
- Dynamic WHERE builder with `argIdx` counter for filter queries
- Sort column whitelist (validate sortBy against allowed columns)

### 5. Service — `internal/service/{entity_snake}_service.go`

```go
package service

import (
    "context"
    "errors"
    "time"

    "github.com/google/uuid"
    "github.com/gob/gob-go-commons/pkg/logger"

    "github.com/gob/gob-{service}/internal/domain"
    "github.com/gob/gob-{service}/internal/repository"
)

var (
    Err{Entity}NotFound = errors.New("{entity} not found")
)

type {Entity}Service struct {
    repo repository.{Entity}Repository
    log  *logger.Logger
}

func New{Entity}Service(repo repository.{Entity}Repository, log *logger.Logger) *{Entity}Service {
    return &{Entity}Service{repo: repo, log: log}
}

func (s *{Entity}Service) GetByID(ctx context.Context, id uuid.UUID) (*domain.{Entity}, error) {
    entity, err := s.repo.FindByID(ctx, id)
    if err != nil {
        return nil, err
    }
    if entity == nil {
        return nil, Err{Entity}NotFound
    }
    return entity, nil
}

func (s *{Entity}Service) List(ctx context.Context, filter *repository.{Entity}Filter) ([]*domain.{Entity}, int64, error) {
    entities, err := s.repo.List(ctx, filter)
    if err != nil {
        return nil, 0, err
    }
    total, err := s.repo.Count(ctx, filter)
    if err != nil {
        return nil, 0, err
    }
    return entities, total, nil
}

func (s *{Entity}Service) Create(ctx context.Context, input *Create{Entity}Input) (*domain.{Entity}, error) {
    entity := &domain.{Entity}{
        ID:        uuid.New(),
        Name:      input.Name,
        CreatedAt: time.Now(),
    }
    if err := s.repo.Create(ctx, entity); err != nil {
        return nil, err
    }
    return entity, nil
}

func (s *{Entity}Service) Update(ctx context.Context, id uuid.UUID, input *Update{Entity}Input) (*domain.{Entity}, error) {
    entity, err := s.repo.FindByID(ctx, id)
    if err != nil {
        return nil, err
    }
    if entity == nil {
        return nil, Err{Entity}NotFound
    }

    // Apply partial updates
    if input.Name != nil {
        entity.Name = *input.Name
    }

    if err := s.repo.Update(ctx, entity); err != nil {
        return nil, err
    }
    return entity, nil
}

func (s *{Entity}Service) Delete(ctx context.Context, id uuid.UUID) error {
    entity, err := s.repo.FindByID(ctx, id)
    if err != nil {
        return err
    }
    if entity == nil {
        return Err{Entity}NotFound
    }
    return s.repo.Delete(ctx, id)
}

// Input types for service methods
type Create{Entity}Input struct {
    Name        string
    Description string
}

type Update{Entity}Input struct {
    Name        *string
    Description *string
}
```

**Rules**:
- Package-level sentinel errors: `var Err{Entity}NotFound = errors.New("...")`
- NO HTTP status codes in service layer
- Returns domain objects, NOT DTOs
- Constructor accepts repository INTERFACE, not concrete type
- Input structs for Create/Update (can be in same file or separate)
- `FindByID` returns nil → wrap as sentinel error in service
- Setter injection for optional dependencies (publisher, etc.)

### 6. Handler — `internal/handler/{entity_snake}_handler.go`

```go
package handler

import (
    "errors"
    "net/http"

    "github.com/gofiber/fiber/v2"
    "github.com/google/uuid"
    "github.com/gob/gob-go-commons/pkg/middleware"

    "github.com/gob/gob-{service}/internal/dto"
    "github.com/gob/gob-{service}/internal/repository"
    "github.com/gob/gob-{service}/internal/service"
)

type {Entity}Handler struct {
    svc *service.{Entity}Service
    log *logger.Logger
}

func New{Entity}Handler(svc *service.{Entity}Service, log *logger.Logger) *{Entity}Handler {
    return &{Entity}Handler{svc: svc, log: log}
}

func (h *{Entity}Handler) RegisterRoutes(router fiber.Router) {
    // STATIC routes FIRST
    router.Get("/", h.List)
    router.Post("/", h.Create)

    // PARAMETERIZED routes LAST
    router.Get("/:id", h.Get)
    router.Put("/:id", h.Update)
    router.Delete("/:id", h.Delete)
}

func (h *{Entity}Handler) List(c *fiber.Ctx) error {
    filter := &repository.{Entity}Filter{
        Search:    c.Query("search"),
        Status:    c.Query("status"),
        Limit:     c.QueryInt("limit", 20),
        Offset:    c.QueryInt("offset", 0),
        SortBy:    c.Query("sort_by", "created_at"),
        SortOrder: c.Query("sort_order", "desc"),
    }

    entities, total, err := h.svc.List(c.Context(), filter)
    if err != nil {
        return c.Status(http.StatusInternalServerError).JSON(dto.ErrorResponse{
            Error:   "internal_error",
            Message: "Failed to list {entities}",
        })
    }

    return c.JSON(dto.Response{
        Data:  entities,
        Total: total,
    })
}

func (h *{Entity}Handler) Get(c *fiber.Ctx) error {
    id, err := uuid.Parse(c.Params("id"))
    if err != nil {
        return c.Status(http.StatusBadRequest).JSON(dto.ErrorResponse{
            Error:   "invalid_id",
            Message: "Invalid {entity} ID",
        })
    }

    entity, err := h.svc.GetByID(c.Context(), id)
    if err != nil {
        if errors.Is(err, service.Err{Entity}NotFound) {
            return c.Status(http.StatusNotFound).JSON(dto.ErrorResponse{
                Error:   "not_found",
                Message: "{Entity} not found",
            })
        }
        return c.Status(http.StatusInternalServerError).JSON(dto.ErrorResponse{
            Error:   "internal_error",
            Message: "Failed to get {entity}",
        })
    }

    return c.JSON(entity)
}

func (h *{Entity}Handler) Create(c *fiber.Ctx) error {
    var req dto.Create{Entity}Request
    if err := c.BodyParser(&req); err != nil {
        return c.Status(http.StatusBadRequest).JSON(dto.ErrorResponse{
            Error:   "invalid_request",
            Message: "Invalid request body",
        })
    }

    input := &service.Create{Entity}Input{
        Name:        req.Name,
        Description: req.Description,
    }

    entity, err := h.svc.Create(c.Context(), input)
    if err != nil {
        return c.Status(http.StatusInternalServerError).JSON(dto.ErrorResponse{
            Error:   "internal_error",
            Message: "Failed to create {entity}",
        })
    }

    return c.Status(http.StatusCreated).JSON(entity)
}

func (h *{Entity}Handler) Update(c *fiber.Ctx) error {
    id, err := uuid.Parse(c.Params("id"))
    if err != nil {
        return c.Status(http.StatusBadRequest).JSON(dto.ErrorResponse{
            Error:   "invalid_id",
            Message: "Invalid {entity} ID",
        })
    }

    var req dto.Update{Entity}Request
    if err := c.BodyParser(&req); err != nil {
        return c.Status(http.StatusBadRequest).JSON(dto.ErrorResponse{
            Error:   "invalid_request",
            Message: "Invalid request body",
        })
    }

    input := &service.Update{Entity}Input{
        Name:        req.Name,
        Description: req.Description,
    }

    entity, err := h.svc.Update(c.Context(), id, input)
    if err != nil {
        if errors.Is(err, service.Err{Entity}NotFound) {
            return c.Status(http.StatusNotFound).JSON(dto.ErrorResponse{
                Error:   "not_found",
                Message: "{Entity} not found",
            })
        }
        return c.Status(http.StatusInternalServerError).JSON(dto.ErrorResponse{
            Error:   "internal_error",
            Message: "Failed to update {entity}",
        })
    }

    return c.JSON(entity)
}

func (h *{Entity}Handler) Delete(c *fiber.Ctx) error {
    id, err := uuid.Parse(c.Params("id"))
    if err != nil {
        return c.Status(http.StatusBadRequest).JSON(dto.ErrorResponse{
            Error:   "invalid_id",
            Message: "Invalid {entity} ID",
        })
    }

    if err := h.svc.Delete(c.Context(), id); err != nil {
        if errors.Is(err, service.Err{Entity}NotFound) {
            return c.Status(http.StatusNotFound).JSON(dto.ErrorResponse{
                Error:   "not_found",
                Message: "{Entity} not found",
            })
        }
        return c.Status(http.StatusInternalServerError).JSON(dto.ErrorResponse{
            Error:   "internal_error",
            Message: "Failed to delete {entity}",
        })
    }

    return c.SendStatus(http.StatusNoContent)
}
```

**Rules**:
- `RegisterRoutes()` method — static routes BEFORE parameterized `/:id`
- Sub-groups BEFORE `/:id` catch-all (Fiber trie conflict)
- `errors.Is()` for sentinel error dispatch
- `dto.ErrorResponse` for all error responses
- `dto.Response` with `Data` + `Total` for list endpoints
- `c.BodyParser()` for request body
- `c.Params("id")` + `uuid.Parse()` for path params
- `c.Query()` / `c.QueryInt()` for query params
- Claims via `middleware.GetUserID(c)`, `middleware.GetClaims(c)`
- HTTP 201 for Create, 204 for Delete, 200 for everything else

### 7. Migration Files

Generate using the same conventions as the `go-add-migration` skill:
- Auto-detect next number
- Schema prefix
- `gen_random_uuid()` for PKs
- `TIMESTAMP NOT NULL DEFAULT NOW()` for created_at
- Down migration with `DROP TABLE IF EXISTS ... CASCADE`

### 8. Factory Wiring — edit `internal/factory/factory.go`

Add to the `Repositories` struct:
```go
{Entity} repository.{Entity}Repository
```

Add to `NewRepositories()`:
```go
{Entity}: postgres.New{Entity}Repository(db, log),
```

Add to `NewDryRunRepositories()` if it exists:
```go
{Entity}: postgres.New{Entity}Repository(db, log), // read-only uses real repo
```

Add getter method:
```go
func (r *Repositories) Get{Entity}Repository() repository.{Entity}Repository {
    return r.{Entity}
}
```

### 9. Main.go Wiring — edit `cmd/api/main.go`

Add after existing services/handlers (find the wiring section):
```go
// {Entity}
{entity}Svc := service.New{Entity}Service(repos.Get{Entity}Repository(), log)
{entity}Handler := handler.New{Entity}Handler({entity}Svc, log)
```

Register route group. **CRITICAL**: if there's an existing `/:id` handler at the same router level, the new group must be registered BEFORE it:
```go
{entity}Group := api.Group("/{entities}")
{entity}Handler.RegisterRoutes({entity}Group)
```

## Post-Generation Steps

After all files are created:

1. Run `go mod tidy` in the service directory
2. Run `go build ./...` to verify compilation
3. Remind user to run migrations: `make migrate-up SERVICE={service-name}`
4. If the service has dry-run support, mention that the dry-run repo wrapper may need to be created

## Critical Gotchas (Embedded Knowledge)

1. **Fiber trie conflict**: NEVER register a sub-group (e.g., `/groups`) after a `/:id` catch-all at the same level. Static paths MUST come first. This is the #1 cause of mysterious 404s.

2. **sql.ErrNoRows**: In repository, return `nil, nil`. In service, check nil and return sentinel error. NEVER let `sql.ErrNoRows` propagate as an unhandled error.

3. **JSONB columns**: Use `json.RawMessage` in domain, `[]byte` in row struct, convert in `toDomain()`. For writes, may need `jsonbParam()` helper.

4. **Service returns domain, NOT DTOs**: The handler is responsible for converting domain → DTO/response.

5. **Import cycle prevention**: Domain → nothing. DTO → domain (if needed). Repository → domain. Service → repository + domain. Handler → service + dto + domain. Factory → repository + postgres.

6. **go mod tidy**: ALWAYS run after adding new imports. The service may not have all dependencies yet.

7. **Schema prefix**: EVERY SQL query must use `{schema}.{table}` format. Unqualified table names will hit the wrong schema or fail.

8. **Portuguese accents**: Seed data and user-facing messages must use proper accents (e, a, c, o, i).