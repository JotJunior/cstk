---
name: go-add-migration
description: Create properly named PostgreSQL migration files for GOB microservices
allowed-tools:
  - Read
  - Write
  - Glob
  - Grep
  - Bash
  - Edit
---

# Go Add Migration

Create properly named PostgreSQL migration files for a GOB microservice following all project conventions.

## Trigger Phrases

"add migration", "new migration", "criar migration", "nova migration", "create migration"

## Arguments

$ARGUMENTS should specify:
- **Service name** (e.g., `gob-member-service`) — required
- **Migration type** (create_table, add_column, create_index, seed, alter_table, custom) — inferred from description
- **Description** — what the migration does (e.g., "create notifications table", "add phone column to members", "seed default categories")

## Pre-Flight Checks

Before generating files, read:

1. **Existing migrations** — `ls services/{service}/migrations/` to determine the next 3-digit sequence number
2. **go.mod** — `services/{service}/go.mod` to confirm the service exists and get module path
3. **Schema name** — derive from the service-to-schema mapping below

## Service-to-Schema Mapping

| Service | Schema |
|---------|--------|
| gob-auth-service | auth |
| gob-member-service | member |
| gob-lodge-service | lodge |
| gob-session-service | session |
| gob-process-service | process |
| gob-election-service | election |
| gob-bulletin-service | bulletin |
| gob-partnership-service | partnership |
| gob-audit-service | audit |
| gob-report-service | report |
| gob-notification-service | notification |
| gob-financial-service | financial |
| gob-assistance-service | assistance |
| gob-whatsapp-service | whatsapp |
| gob-migration-service | migration |

If the service is not listed, extract the schema name from the service name by removing the `gob-` prefix and `-service` suffix.

## Migration Numbering

- List all files in `services/{service}/migrations/`
- Find the highest existing number prefix (e.g., `012_xxx.up.sql` → 12)
- The new migration number is `highest + 1`, zero-padded to 3 digits (e.g., `013`)
- Generate both `.up.sql` and `.down.sql` files

**File naming**: `{NNN}_{description_in_snake_case}.up.sql` and `{NNN}_{description_in_snake_case}.down.sql`

## Templates by Type

### create_table

**Up migration**:
```sql
-- {NNN}: Create {table_name} table
CREATE TABLE IF NOT EXISTS {schema}.{table_name} (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    -- entity-specific columns here --
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_{table_name}_{column} ON {schema}.{table_name}({column});

-- Comments
COMMENT ON TABLE {schema}.{table_name} IS '{description}';
```

**Down migration**:
```sql
DROP TABLE IF EXISTS {schema}.{table_name} CASCADE;
```

### add_column

**Up migration**:
```sql
-- {NNN}: Add {column_name} to {table_name}
ALTER TABLE {schema}.{table_name}
    ADD COLUMN IF NOT EXISTS {column_name} {type} {constraints};
```

**Down migration**:
```sql
ALTER TABLE {schema}.{table_name}
    DROP COLUMN IF EXISTS {column_name};
```

### create_index

**Up migration**:
```sql
-- {NNN}: Create index on {table_name}.{column}
CREATE INDEX IF NOT EXISTS idx_{table_name}_{column} ON {schema}.{table_name}({column});
```

**Down migration**:
```sql
DROP INDEX IF EXISTS {schema}.idx_{table_name}_{column};
```

### seed

**Up migration**:
```sql
-- {NNN}: Seed {table_name} with default data
INSERT INTO {schema}.{table_name} (col1, col2, ...)
VALUES
    ('value1', 'value2'),
    ('value3', 'value4')
ON CONFLICT DO NOTHING;
```

**Down migration**:
```sql
-- Remove seeded data
DELETE FROM {schema}.{table_name}
WHERE col1 IN ('value1', 'value3');
```

### alter_table (generic ALTER)

**Up migration**:
```sql
-- {NNN}: {description}
ALTER TABLE {schema}.{table_name}
    {alterations};
```

**Down migration**:
```sql
-- Revert: {description}
ALTER TABLE {schema}.{table_name}
    {reverse_alterations};
```

## Critical Rules

1. **Schema prefix**: ALWAYS use `{schema}.{table_name}` (e.g., `member.members`, `process.process_definitions`). Never use unqualified table names.

2. **CIMs**: When inserting CIM values, always use 7-digit zero-padded format. Use `LPAD(cim::text, 7, '0')` for JOINs with legacy data.

3. **Portuguese accents**: Always use proper accents in seed data text (e.g., "Administracao" is WRONG, "Administracao" is WRONG, "Administracao" -> use "Administrativo" etc.). Example correct values: "Iniciacao", "Elevacao", "Exaltacao", "Filiacao".

4. **Down migrations must be idempotent**: Always use `IF EXISTS`, `CASCADE` where appropriate. Running down twice must not error.

5. **Timestamps**: Use `TIMESTAMP NOT NULL DEFAULT NOW()` for `created_at`. Use `TIMESTAMP` (nullable) for `updated_at`.

6. **UUIDs**: Use `UUID PRIMARY KEY DEFAULT gen_random_uuid()` for primary keys.

7. **Enums**: Prefer `VARCHAR` or `TEXT` with CHECK constraints over PostgreSQL ENUM types. This avoids migration complexity when adding new values.

8. **Foreign keys**: Include `ON DELETE` behavior explicitly (CASCADE, SET NULL, or RESTRICT).

9. **Boolean defaults**: Always specify `DEFAULT false` or `DEFAULT true` for boolean columns.

10. **Naming conventions**:
    - Tables: `snake_case`, plural (e.g., `members`, `process_definitions`)
    - Columns: `snake_case` (e.g., `lodge_id`, `created_at`)
    - Indexes: `idx_{table}_{column}` (e.g., `idx_members_lodge_id`)
    - Unique indexes: `uniq_{table}_{column}` (e.g., `uniq_members_cim`)
    - Foreign keys: `fk_{table}_{referenced_table}` (e.g., `fk_members_lodges`)

## Output

After creating both files:
1. Show the full path and content of both migration files
2. Remind the user to run: `make migrate-up SERVICE={service-name}` (for local dev)
3. For production: `./scripts/migrate.sh --service={service-name} up`