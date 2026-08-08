# Contracts: [FEATURE]

Contratos de interface externa (APIs, CLI, eventos). Um arquivo por grupo de
endpoints quando aplicavel.

## [Endpoint/Command/Event]

**Method**: POST /api/v1/resource
**Auth**: Required (JWT)

### Request

| Field | Type | Required | Validation |
|-------|------|----------|------------|
| name | string | yes | min 3, max 100 |

### Response (200)

| Field | Type | Description |
|-------|------|-------------|
| id | uuid | Created resource ID |

### Error Responses

| Status | Code | Description |
|--------|------|-------------|
| 400 | VALIDATION_ERROR | Invalid input |
| 409 | CONFLICT | Resource already exists |
