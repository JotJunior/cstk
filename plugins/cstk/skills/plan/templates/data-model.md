# Data Model: [FEATURE]

## Entity: [Name]

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| id | UUID | PK | Auto-generated |
| name | string | NOT NULL, min 3 chars | |
| status | enum | CHECK (active, inactive) | Default: active |
| created_at | timestamp | NOT NULL | Auto-set |

### Relationships

- [Entity A] 1:N [Entity B] via `entity_a_id`
- [Entity C] N:M [Entity D] via `entity_c_entity_d` join table

### State Transitions (if applicable)

```
draft → active → suspended → archived
```
