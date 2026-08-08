# go-add-test

Add unit/integration tests to a GOB Go microservice following established project patterns.

## Triggers

- "add test", "add tests", "criar teste", "novo teste", "test coverage", "testar"
- "write tests for", "escrever testes para"
- Examples: "add tests for process-service service layer", "criar testes de domain para bulletin-service"

## Instructions

You generate Go tests for GOB microservices following the MockFunc pattern established in `gob-member-service` and `gob-auth-service`.

### Step 1: Identify Target

Parse the user request to determine:
- **Service**: which service in `services/` (e.g., `gob-process-service`)
- **Layer**: which layer to test: `domain`, `service`, `handler`, `repository`, `consumer`
- **Scope**: specific file/method or entire layer

If not specified, ask the user.

### Step 2: Pre-flight Reads

Before writing ANY test code, read these files in the target service:

1. **Repository interfaces** — `internal/repository/repository.go` or similar interface files
   - These define the methods you need to mock
2. **Target source file** — the file being tested (e.g., `internal/service/member_service.go`)
   - Understand every method signature, dependencies, and error paths
3. **Domain structs** — `internal/domain/*.go`
   - Needed for creating test fixtures
4. **Existing tests** — any `*_test.go` files in the target package
   - Follow existing patterns if tests already exist
5. **DTO structs** — `internal/dto/dto.go` if testing service/handler layer
   - Request/response types used by the methods

### Step 3: Generate Mocks (if `mocks_test.go` doesn't exist)

Create `mocks_test.go` in the same package as the tests. Use the **MockFunc pattern**:

```go
package service

import (
    "context"

    "github.com/google/uuid"
    "github.com/gob/{service}/internal/domain"
)

// --- MockXxxRepository ---

type MockXxxRepository struct {
    FindByIDFunc    func(ctx context.Context, id uuid.UUID) (*domain.Xxx, error)
    CreateFunc      func(ctx context.Context, entity *domain.Xxx) error
    UpdateFunc      func(ctx context.Context, entity *domain.Xxx) error
    DeleteFunc      func(ctx context.Context, id uuid.UUID) error
    ListFunc        func(ctx context.Context, limit, offset int) ([]*domain.Xxx, int, error)
    // Add one field per interface method
}

func (m *MockXxxRepository) FindByID(ctx context.Context, id uuid.UUID) (*domain.Xxx, error) {
    if m.FindByIDFunc != nil {
        return m.FindByIDFunc(ctx, id)
    }
    return nil, nil
}

func (m *MockXxxRepository) Create(ctx context.Context, entity *domain.Xxx) error {
    if m.CreateFunc != nil {
        return m.CreateFunc(ctx, entity)
    }
    return nil
}

// ... implement ALL interface methods with nil-check + safe default
```

**Rules for mocks**:
- One `MockXxxRepository` struct per repository interface
- Field name = method name + `Func` suffix
- Safe defaults: return `nil, nil` for pointer returns, `nil` for error-only returns
- Mocks live in `mocks_test.go` in the SAME package (not a separate mocks directory)
- Build tag: none needed (they're `_test.go` files)

### Step 4: Generate Setup Helper

Create a setup function that wires the service with all mock dependencies:

```go
func setupXxxService() (*XxxService, *MockAaaRepository, *MockBbbRepository) {
    aaaRepo := &MockAaaRepository{}
    bbbRepo := &MockBbbRepository{}

    // Match the actual constructor signature
    service := NewXxxService(aaaRepo, bbbRepo)
    // OR if the service uses a Repositories struct:
    // repos := &Repositories{aaa: aaaRepo, bbb: bbbRepo}
    // service := NewXxxService(repos)

    return service, aaaRepo, bbbRepo
}
```

**Rules**:
- Return the service AND all individual mock repos (so tests can configure Func fields)
- Match the real constructor — check `NewXxxService()` signature
- If the service takes a config, create a `testConfig()` helper too

### Step 5: Generate Tests

#### Domain Tests (`internal/domain/*_test.go`)

Pure unit tests — no mocks needed:

```go
func TestXxx_MethodName(t *testing.T) {
    tests := []struct {
        name    string
        // input fields
        wantErr error
    }{
        {
            name:    "valid case",
            wantErr: nil,
        },
        {
            name:    "invalid - reason",
            wantErr: ErrSpecificError,
        },
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            entity := &Xxx{/* fields */}
            err := entity.MethodName()

            if tt.wantErr != nil {
                if err != tt.wantErr {
                    t.Errorf("MethodName() error = %v, want %v", err, tt.wantErr)
                }
                return
            }
            if err != nil {
                t.Errorf("MethodName() unexpected error: %v", err)
            }
        })
    }
}
```

#### Service Tests (`internal/service/*_test.go`)

```go
func TestXxxService_Create(t *testing.T) {
    service, xxxRepo, _ := setupXxxService()
    ctx := context.Background()

    t.Run("success", func(t *testing.T) {
        xxxRepo.CreateFunc = func(ctx context.Context, entity *domain.Xxx) error {
            return nil
        }

        req := &dto.CreateXxxRequest{
            Name: "Test",
        }

        result, err := service.Create(ctx, req)
        if err != nil {
            t.Fatalf("Create() error = %v", err)
        }
        if result.Name != "Test" {
            t.Errorf("Create() Name = %v, want %v", result.Name, "Test")
        }
    })

    t.Run("validation error - empty name", func(t *testing.T) {
        req := &dto.CreateXxxRequest{
            Name: "",
        }

        _, err := service.Create(ctx, req)
        if err == nil {
            t.Error("Create() expected validation error")
        }
    })

    t.Run("repository error", func(t *testing.T) {
        xxxRepo.CreateFunc = func(ctx context.Context, entity *domain.Xxx) error {
            return errors.New("db connection failed")
        }

        req := &dto.CreateXxxRequest{
            Name: "Test",
        }

        _, err := service.Create(ctx, req)
        if err == nil {
            t.Error("Create() expected error when repo fails")
        }
    })
}
```

#### Handler Tests (`internal/handler/*_test.go`)

```go
func TestXxxHandler_Create(t *testing.T) {
    app := fiber.New()

    mockService := &MockXxxService{}
    handler := NewXxxHandler(mockService)

    app.Post("/xxx", handler.Create)

    t.Run("success - 201", func(t *testing.T) {
        mockService.CreateFunc = func(ctx context.Context, req *dto.CreateXxxRequest) (*dto.XxxResponse, error) {
            return &dto.XxxResponse{ID: uuid.New(), Name: req.Name}, nil
        }

        body := `{"name": "Test"}`
        req := httptest.NewRequest("POST", "/xxx", strings.NewReader(body))
        req.Header.Set("Content-Type", "application/json")

        resp, err := app.Test(req)
        if err != nil {
            t.Fatalf("app.Test() error = %v", err)
        }
        if resp.StatusCode != fiber.StatusCreated {
            t.Errorf("status = %d, want %d", resp.StatusCode, fiber.StatusCreated)
        }
    })

    t.Run("bad request - invalid JSON", func(t *testing.T) {
        req := httptest.NewRequest("POST", "/xxx", strings.NewReader("{invalid"))
        req.Header.Set("Content-Type", "application/json")

        resp, err := app.Test(req)
        if err != nil {
            t.Fatalf("app.Test() error = %v", err)
        }
        if resp.StatusCode != fiber.StatusBadRequest {
            t.Errorf("status = %d, want %d", resp.StatusCode, fiber.StatusBadRequest)
        }
    })
}
```

#### Consumer/Messaging Tests (`internal/messaging/*_test.go`)

```go
func TestProcessHandler_HandleEvent(t *testing.T) {
    mockService := &MockXxxService{}
    handler := NewProcessHandler(mockService)

    t.Run("process.created event", func(t *testing.T) {
        var called bool
        mockService.HandleProcessCreatedFunc = func(ctx context.Context, event *domain.ProcessEvent) error {
            called = true
            return nil
        }

        payload := []byte(`{"process_id": "` + uuid.New().String() + `", "action": "created"}`)
        err := handler.Handle(context.Background(), payload)

        if err != nil {
            t.Fatalf("Handle() error = %v", err)
        }
        if !called {
            t.Error("HandleProcessCreated was not called")
        }
    })
}
```

### Step 6: Test Coverage Cases

For EVERY method tested, always include these scenarios:

1. **Happy path** — valid input, expected output
2. **Validation errors** — missing required fields, invalid values
3. **Not found** — entity doesn't exist (return nil from repo)
4. **Repository/dependency errors** — database failures, external service failures
5. **Authorization** (if applicable) — wrong scope, missing permissions
6. **Edge cases** — empty lists, zero values, UUID nil, boundary values

### Conventions

| Rule | Value |
|------|-------|
| Test framework | Standard `testing` package only (NO testify) |
| Mock library | Hand-written MockFunc pattern (NO mockgen, gomock) |
| Test file location | Same package as source (`_test` suffix) |
| Mock file | `mocks_test.go` per package |
| Naming | `Test{Type}_{Method}` (e.g., `TestMemberService_Create`) |
| Structure | Table-driven with `t.Run()` subtests |
| Assertions | `if got != want { t.Errorf(...) }` |
| Fatal vs Error | `t.Fatalf` for setup failures, `t.Errorf` for assertion failures |
| Context | Always use `context.Background()` |
| UUIDs | Use `uuid.New()` for test IDs |
| Time | Use `time.Now()` or fixed `time.Date()` for deterministic tests |

### Anti-patterns to AVOID

- Do NOT use `github.com/stretchr/testify`
- Do NOT generate mocks with `mockgen` or any code generator
- Do NOT put mocks in a separate `mocks/` directory
- Do NOT use `reflect.DeepEqual` — compare fields individually
- Do NOT test private functions directly — test through public API
- Do NOT create `TestMain` unless writing integration tests with DB
- Do NOT add build tags for unit tests

### Verification

After generating tests, run:

```bash
cd services/{service-name} && go test ./internal/{layer}/... -v -count=1
```

If compilation fails, fix immediately. Common issues:
- Missing mock method (interface not fully implemented)
- Wrong import path
- Struct field mismatch (check domain structs again)
- Constructor signature changed

### Reference Services

- **Best example**: `services/gob-member-service/internal/service/` — full MockFunc pattern, setup helpers, table-driven tests
- **Auth patterns**: `services/gob-auth-service/internal/service/` — in-memory store mocks, complex scenario tests
- **Domain only**: `services/gob-election-service/internal/domain/` — pure domain validation tests
