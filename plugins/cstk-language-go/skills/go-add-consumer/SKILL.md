---
name: go-add-consumer
description: Add a RabbitMQ event consumer to an existing GOB Go microservice
allowed-tools:
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - Bash
---

# Go Add Consumer

Add a RabbitMQ event consumer to an existing GOB Go microservice. Generates the consumer infrastructure, event handlers, and wires everything into main.go.

## Trigger Phrases

"add consumer", "add event consumer", "consumir eventos", "novo consumer", "listen to events", "subscribe to events"

## Arguments

$ARGUMENTS should specify:
- **Service name** (e.g., `gob-bulletin-service`) — required
- **Source exchanges** — which exchanges to bind to (e.g., `gob.processes`, `gob.members`)
- **Routing keys** — which events to listen to (e.g., `process.*`, `member.death`)
- **What to do** — description of what the handler should do when events arrive

## Pre-Flight Reads

Before generating code, read these files (in parallel):

1. **`go.mod`** — module path, check if `github.com/rabbitmq/amqp091-go` is already a dependency
2. **`cmd/api/main.go`** — existing wiring, check if a consumer already exists
3. **`internal/`** (ls) — check for existing `consumer/` or `messaging/` directory
4. **Existing consumer** in another service for reference pattern — e.g., `services/gob-bulletin-service/internal/messaging/consumer.go`

Determine:
- **Package name**: use `messaging` if the service already has that directory, otherwise `consumer`
- **Queue name**: `gob.{service-name}` (e.g., `gob.bulletin-service`)
- **Consumer tag**: `{service-name}` (e.g., `bulletin-service`)

## Known Exchange Names

| Exchange | Service that publishes | Event types |
|----------|----------------------|-------------|
| `gob.processes` | gob-process-service | process.created, process.submitted, process.approved, process.rejected, process.completed |
| `gob.members` | gob-member-service | member.created, member.updated, member.death, member.quit_placet, member.exclusion |
| `gob.bulletins` | gob-bulletin-service | bulletin.published, bulletin.closed |
| `gob.financial` | gob-financial-service | financial.payment, financial.charge |
| `gob.elections` | gob-election-service | election.started, election.completed |
| `gob.sessions` | gob-session-service | session.created, session.completed |
| `gob.auth` | gob-auth-service | auth.login, auth.password_reset |
| `gob.notifications` | gob-notification-service | notification.* |
| `gob.assistance` | gob-assistance-service | assistance.submitted, assistance.approved, assistance.rejected, assistance.paid |
| `gob.reports` | gob-report-service | report.requested, report.completed |
| `gob.audit` | audit middleware (all services) | audit.* |

## Files to Generate

### 1. Consumer — `internal/{pkg}/consumer.go`

```go
package messaging // or consumer

import (
    "context"
    "encoding/json"
    "fmt"
    "sync"

    amqp "github.com/rabbitmq/amqp091-go"
    "github.com/gob/gob-go-commons/pkg/logger"
)

const (
    consumerQueue = "gob.{service-name}"
    consumerTag   = "{service-name-without-gob}"
)

// Default bindings — exchanges and routing keys to listen to.
// Uses ExchangeDeclarePassive so we don't create other service's exchanges.
var defaultBindings = []QueueBinding{
    {Exchange: "{exchange1}", RoutingKey: "{routing_key1}"},
    {Exchange: "{exchange2}", RoutingKey: "{routing_key2}"},
}

type QueueBinding struct {
    Exchange   string
    RoutingKey string
}

// IncomingEvent is the generic event envelope from RabbitMQ.
type IncomingEvent struct {
    EventID   string          `json:"event_id"`
    EventType string          `json:"event_type"`
    Source    string           `json:"source,omitempty"`
    ProcessID string          `json:"process_id,omitempty"`
    MemberID  string          `json:"member_id,omitempty"`
    LodgeID   string          `json:"lodge_id,omitempty"`
    UserID    string          `json:"user_id,omitempty"`
    UserName  string          `json:"user_name,omitempty"`
    Data      any             `json:"data,omitempty"`
    RawBody   json.RawMessage `json:"-"`
}

type EventHandler func(ctx context.Context, event *IncomingEvent) error

type EventConsumer struct {
    conn     *amqp.Connection
    channel  *amqp.Channel
    log      *logger.Logger
    handlers map[string]EventHandler
    mu       sync.RWMutex
    done     chan struct{}
}

func NewEventConsumer(amqpURL string, log *logger.Logger) (*EventConsumer, error) {
    conn, err := amqp.Dial(amqpURL)
    if err != nil {
        return nil, fmt.Errorf("failed to connect to RabbitMQ: %w", err)
    }

    ch, err := conn.Channel()
    if err != nil {
        _ = conn.Close()
        return nil, fmt.Errorf("failed to open channel: %w", err)
    }

    // Prefetch — process 10 messages at a time
    if err := ch.Qos(10, 0, false); err != nil {
        _ = ch.Close()
        _ = conn.Close()
        return nil, fmt.Errorf("failed to set QoS: %w", err)
    }

    // Declare our own durable queue
    _, err = ch.QueueDeclare(
        consumerQueue,
        true,  // durable
        false, // auto-delete
        false, // exclusive
        false, // no-wait
        nil,
    )
    if err != nil {
        _ = ch.Close()
        _ = conn.Close()
        return nil, fmt.Errorf("failed to declare queue: %w", err)
    }

    // Bind to source exchanges using ExchangeDeclarePassive
    // This does NOT create the exchange — it only verifies it exists
    for _, binding := range defaultBindings {
        if err := ch.ExchangeDeclarePassive(
            binding.Exchange, "topic", true, false, false, false, nil,
        ); err != nil {
            log.WithField("exchange", binding.Exchange).
                Warn("Exchange not found, skipping binding")
            // Channel is closed after passive declare failure — reopen
            ch, err = conn.Channel()
            if err != nil {
                _ = conn.Close()
                return nil, fmt.Errorf("failed to reopen channel: %w", err)
            }
            if err := ch.Qos(10, 0, false); err != nil {
                _ = ch.Close()
                _ = conn.Close()
                return nil, fmt.Errorf("failed to set QoS after reopen: %w", err)
            }
            continue
        }

        if err := ch.QueueBind(
            consumerQueue, binding.RoutingKey, binding.Exchange, false, nil,
        ); err != nil {
            log.WithField("exchange", binding.Exchange).
                WithField("routing_key", binding.RoutingKey).
                WithError(err).Warn("Failed to bind queue")
        } else {
            log.WithField("exchange", binding.Exchange).
                WithField("routing_key", binding.RoutingKey).
                Info("Bound queue to exchange")
        }
    }

    return &EventConsumer{
        conn:     conn,
        channel:  ch,
        log:      log,
        handlers: make(map[string]EventHandler),
        done:     make(chan struct{}),
    }, nil
}

// RegisterHandler registers a handler for a routing key pattern.
// Use "*" prefix for wildcard matching (e.g., "process.*" matches "process.approved").
func (c *EventConsumer) RegisterHandler(pattern string, handler EventHandler) {
    c.mu.Lock()
    defer c.mu.Unlock()
    c.handlers[pattern] = handler
}

// Start begins consuming messages. Blocks until ctx is cancelled or Stop() is called.
func (c *EventConsumer) Start(ctx context.Context) error {
    deliveries, err := c.channel.Consume(
        consumerQueue,
        consumerTag,
        false, // auto-ack: false (manual ack)
        false, // exclusive
        false, // no-local
        false, // no-wait
        nil,
    )
    if err != nil {
        return fmt.Errorf("failed to start consuming: %w", err)
    }

    c.log.WithField("queue", consumerQueue).Info("Consumer started")

    for {
        select {
        case <-ctx.Done():
            c.log.Info("Consumer context cancelled, stopping")
            return nil
        case <-c.done:
            c.log.Info("Consumer stop signal received")
            return nil
        case delivery, ok := <-deliveries:
            if !ok {
                c.log.Warn("Delivery channel closed")
                return nil
            }
            c.handleDelivery(ctx, delivery)
        }
    }
}

func (c *EventConsumer) handleDelivery(ctx context.Context, delivery amqp.Delivery) {
    var event IncomingEvent
    if err := json.Unmarshal(delivery.Body, &event); err != nil {
        c.log.WithError(err).Warn("Failed to unmarshal event, acking to discard")
        _ = delivery.Ack(false)
        return
    }

    // Store raw body for handlers that need to re-parse
    event.RawBody = delivery.Body

    // Find matching handler by routing key
    c.mu.RLock()
    handler := c.findHandler(delivery.RoutingKey)
    c.mu.RUnlock()

    if handler == nil {
        c.log.WithField("routing_key", delivery.RoutingKey).
            Debug("No handler for routing key, acking")
        _ = delivery.Ack(false)
        return
    }

    if err := handler(ctx, &event); err != nil {
        c.log.WithError(err).
            WithField("routing_key", delivery.RoutingKey).
            WithField("event_type", event.EventType).
            Warn("Handler returned error, nacking for requeue")
        _ = delivery.Nack(false, true) // requeue on transient errors
        return
    }

    _ = delivery.Ack(false)
}

// findHandler matches a routing key against registered patterns.
// Supports simple wildcard: "process.*" matches "process.anything".
func (c *EventConsumer) findHandler(routingKey string) EventHandler {
    // Exact match first
    if h, ok := c.handlers[routingKey]; ok {
        return h
    }

    // Wildcard match: "prefix.*"
    for pattern, h := range c.handlers {
        if len(pattern) > 2 && pattern[len(pattern)-2:] == ".*" {
            prefix := pattern[:len(pattern)-2]
            if len(routingKey) > len(prefix) && routingKey[:len(prefix)] == prefix {
                return h
            }
        }
        // Catch-all "#"
        if pattern == "#" {
            return h
        }
    }

    return nil
}

// Stop signals the consumer to stop processing.
func (c *EventConsumer) Stop() {
    close(c.done)
    if c.channel != nil {
        _ = c.channel.Cancel(consumerTag, false)
        _ = c.channel.Close()
    }
    if c.conn != nil {
        _ = c.conn.Close()
    }
}
```

### 2. Event Handler — `internal/{pkg}/{source}_handler.go`

```go
package messaging

import (
    "context"
    "fmt"

    "github.com/google/uuid"
    "github.com/gob/gob-go-commons/pkg/logger"
)

// {Source}EventData contains typed fields from the event payload.
type {Source}EventData struct {
    ProcessType   string `json:"process_type,omitempty"`
    ProcessNumber string `json:"process_number,omitempty"`
    MemberID      string `json:"member_id,omitempty"`
    MemberName    string `json:"member_name,omitempty"`
    LodgeID       string `json:"lodge_id,omitempty"`
    Status        string `json:"status,omitempty"`
}

// Dependency interfaces — what the handler needs from the service layer.
// Using interfaces prevents import cycles.
type {ActionInterface} interface {
    // Define methods the handler needs to call
    DoSomething(ctx context.Context, input *SomeInput) error
}

type {Source}EventHandler struct {
    actor {ActionInterface}
    log   *logger.Logger
}

func New{Source}EventHandler(actor {ActionInterface}, log *logger.Logger) *{Source}EventHandler {
    return &{Source}EventHandler{actor: actor, log: log}
}

// Handle dispatches {source}.* events.
func (h *{Source}EventHandler) Handle(ctx context.Context, event *IncomingEvent) error {
    switch event.EventType {
    case "approved", "completed":
        return h.handleApproved(ctx, event)
    case "rejected":
        return h.handleRejected(ctx, event)
    default:
        h.log.WithField("event_type", event.EventType).
            Debug("Ignoring unrecognized event type")
        return nil // Don't retry unknown events
    }
}

func (h *{Source}EventHandler) handleApproved(ctx context.Context, event *IncomingEvent) error {
    // Safe type assertion on polymorphic Data field
    data, ok := event.Data.(map[string]any)
    if !ok {
        h.log.Warn("Event data is not a map, ignoring")
        return nil // Don't retry bad data
    }

    // Extract fields with safe type assertions and fallbacks
    processType, _ := data["process_type"].(string)
    memberID, _ := data["member_id"].(string)

    // Parse UUIDs safely
    var parsedMemberID *uuid.UUID
    if memberID != "" {
        if id, err := uuid.Parse(memberID); err == nil {
            parsedMemberID = &id
        }
    }

    h.log.WithField("event_type", event.EventType).
        WithField("process_type", processType).
        WithField("event_id", event.EventID).
        Info("Processing event")

    // Call the service layer via interface
    if err := h.actor.DoSomething(ctx, &SomeInput{
        // ... build input from event data
    }); err != nil {
        h.log.WithError(err).
            WithField("event_id", event.EventID).
            Warn("Failed to process event")
        return err // Return error for transient failures (triggers requeue)
    }

    return nil
}

func (h *{Source}EventHandler) handleRejected(ctx context.Context, event *IncomingEvent) error {
    // Similar pattern...
    return nil
}
```

### 3. Main.go Wiring — edit `cmd/api/main.go`

Add the consumer initialization in the appropriate section of main.go:

```go
// === Event Consumer (non-blocking) ===
var eventConsumer *messaging.EventConsumer
if rmqURL := cfg.GetDefault("RABBITMQ_URL", ""); rmqURL != "" {
    consumer, err := messaging.NewEventConsumer(rmqURL, log)
    if err != nil {
        log.WithError(err).Warn("RabbitMQ consumer unavailable, event processing disabled")
    } else {
        eventConsumer = consumer

        // Create handler with service dependencies
        {source}Handler := messaging.New{Source}EventHandler(someSvc, log)

        // Register handler for routing key pattern
        eventConsumer.RegisterHandler("{source}.*", {source}Handler.Handle)

        // Start consumer in background goroutine
        schedulerCtx, schedulerCancel := context.WithCancel(context.Background())
        defer schedulerCancel()

        go func() {
            if err := eventConsumer.Start(schedulerCtx); err != nil {
                log.WithError(err).Error("Event consumer stopped with error")
            }
        }()

        log.Info("Event consumer started")
    }
}
```

In the graceful shutdown section, add:
```go
// Stop event consumer
if eventConsumer != nil {
    eventConsumer.Stop()
}
```

**IMPORTANT**: The consumer initialization must be:
- AFTER all services are created (handler needs service references)
- BEFORE `app.Listen()` (so it starts consuming before accepting HTTP requests)
- Non-blocking: if RabbitMQ is unavailable, the service starts without event processing

## Critical Rules

1. **ExchangeDeclarePassive**: NEVER use `ExchangeDeclare` for exchanges owned by other services. Use `ExchangeDeclarePassive` to verify the exchange exists without creating it. If it doesn't exist, skip the binding and log a warning.

2. **Channel reopen after passive failure**: When `ExchangeDeclarePassive` fails, the AMQP channel is closed by the broker. You MUST reopen the channel before trying the next exchange.

3. **Return nil for unrecognized events**: Unknown event types or malformed data should be acknowledged (not retried). Return `nil` to ack.

4. **Return error only for transient failures**: If a database call fails or a service is temporarily unavailable, return an error to trigger NACK + requeue.

5. **Consumer goroutine context**: Use a separate `schedulerCtx` (not the main server context), cancelled in graceful shutdown.

6. **Interface-based dependencies**: Event handlers should depend on interfaces, not concrete service types. This prevents import cycles (consumer package should not import service package directly).

7. **Safe type assertions**: Event `Data` field is `any` (usually `map[string]any` after JSON unmarshal). Always use the `value, ok := x.(type)` pattern with fallbacks.

8. **UUID parsing**: Always parse UUIDs with error handling. Invalid UUIDs should be logged and skipped, not cause a crash.

9. **RawBody field**: Set `event.RawBody = delivery.Body` in `handleDelivery` so handlers can re-parse the raw JSON if the generic `Data` field is insufficient.

10. **QoS prefetch**: Use `Qos(10, 0, false)` to limit concurrent message processing. Adjust if the handler does heavy I/O.

## Post-Generation Steps

1. Run `go mod tidy` to add `github.com/rabbitmq/amqp091-go` dependency
2. Run `go build ./...` to verify compilation
3. Ensure `RABBITMQ_URL` is set in ETCD for the service
4. Test by publishing a test event to the source exchange