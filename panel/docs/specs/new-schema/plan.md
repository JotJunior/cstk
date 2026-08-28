# Implementation Plan — new-schema

> **Feature**: `new-schema` — adapt `cstk-panel` (primary consumer) to `knowledge.db`
> schema v7, which normalised all column names from pt-BR to English (`snake_case`
> EN canonical).
> **Spec**: `docs/specs/new-schema/spec.md`
> **Source of truth (FROZEN)**: `../cstk/docs/specs/schema-en-migration/migration-map.md` §3.11
> **Constitution**: `docs/constitution.md` v1.0.0 (gate below)

---

## Summary

`cstk` released `knowledge.db` schema v7 (commit `c004ff3`), renaming every column
from pt-BR to EN `snake_case` (47 mappings) and renaming the `bloqueios` table to
`blocks`. The panel currently references the old pt-BR names across four layers —
SQL queries, TypeScript Row interfaces, shared-types DTOs/Zod schemas, and server
mappers — and will silently return `NULL` or crash against a v7 DB.

**Technical approach**: a *vocabulary migration*, not a feature. Rename, layer by
layer, every pt-BR identifier to its EN equivalent traced 1:1 to migration-map §3.11.
The DB edge stays `snake_case` (Row interfaces mirror columns); the DTO/Zod/web edge
becomes `camelCase` EN; the existing mapper layer is the sole snake↔camel bridge.
Back-compat with a v6 DB is preserved by extending the already-proven
`hasColumn`/`hasTable` pattern (`apps/server/src/db/columns.ts`) so absent columns
project `NULL AS <new_en_name>` and the absent `blocks` table degrades to `[]` — no
DB-version detection, no crash, `200` always (Constitution Principle II). The
integration gate is `tsc --noEmit` = 0 errors plus zero vitest regressions, validated
by a real roundtrip against the installed v7 DB.

---

## Technical Context

| Field | Value |
|---|---|
| Language | TypeScript 5.4, ESM |
| Runtime | Node.js (pnpm/npm workspaces monorepo) |
| Backend | Fastify 5, `better-sqlite3` 9 (read-only DSN `mode=ro&immutable=1`) |
| Frontend | React 19 (Vite) |
| Shared contract | `packages/shared-types` (DTO interfaces + Zod 3.23 schemas) |
| Storage | SQLite `knowledge.db` (v7, EN columns) — READ-ONLY, derived index |
| Testing | vitest 1.6 (`pnpm -r test`) + `tsc --noEmit` type gate |
| Workspaces | `apps/server`, `apps/web`, `packages/shared-types` |
| DB version (installed) | v7 confirmed (`schema_meta.schema_version=7`) — see research §Decision 5 |
| Source of truth | migration-map §3.11 (FROZEN); no column invented (SC-6) |

No NEEDS CLARIFICATION remain — all resolved in `research.md` Phase 0.

---

## Constitution Check

*GATE: must pass before Phase 0. Re-checked after Phase 1 (§Re-check below).*

| Principle | Status | Notes |
|---|---|---|
| I. Read-Only Absoluto (NON-NEGOTIABLE) | PASS | Migration touches only `SELECT` column names + Row/DTO/mapper types. Zero mutation verbs introduced; `mode=ro&immutable=1` DSN unchanged. |
| II. Degradar, Nunca Quebrar | PASS | v6 back-compat via `hasColumn`/`hasTable` → `NULL AS <col>` / `[]`; every endpoint stays `200`. No version gate, no `5xx` (FR-007, P2). |
| III. Honestidade de Metrica | PASS | `tool_calls*` proxy columns kept verbatim; no `$`/token/cost added; no column invented (SC-6). Metric queries (FR-008) only rename existing columns. |
| IV. Nao Reimplementar o que Tem Dono | PASS | No model-routing/decision-tree/reindex logic touched. Column names are owned by `cstk` migration-map (FROZEN); panel consumes, never re-derives. |
| V. Conteudo de Agente e UNTRUSTED | PASS | Renamed text fields (`context`/`rationale`/`evidence`/`question`/`answer`/`description`) remain rendered as plain text; FTS layer untouched (FR-012) so the two-level escaping invariant is preserved. |
| VI. Snapshot que Muda | PASS | No long-lived connection assumption changed; `meta.freshness` envelope untouched. |
| Padroes Seg/Qualidade | PASS | Pagination on `decisions`/`search` preserved; envelope `{data, meta:{degraded,reason,freshness,schema_version}}` unchanged; localhost bind unchanged. |
| Fidelidade de Design | N/A | No visual/UX change — fields keep the same display, only their source key is renamed. |

**Result**: PASS on all MUST/NON-NEGOTIABLE principles. No Complexity Tracking
entries required (no constitution violation to justify).

---

## Project Structure

### Documentation (this feature)
```
docs/specs/new-schema/
  spec.md          # ratified
  plan.md          # this file
  research.md      # Phase 0 — pt→EN decisions, back-compat strategy
  data-model.md    # Phase 1 — rename surface per entity (10 tables)
  quickstart.md    # Phase 1 — tsc gate + REAL v7 roundtrip + v6 degradation
```

### Source code (real tree — verified)
```
apps/server/src/
  db/
    columns.ts             # hasColumn/hasTable — REUSED, extended to renamed cols
    queries/
      executions.ts        # FR-001/008/011 — EN cols + rollups
      waves.ts             # FR-001
      decisions.ts         # FR-001 (paginated)
      tasks.ts             # FR-001/010 — titleSelect helper
      bloqueios.ts         # -> rename file content: BlockRow + blocks table (FR-002/003)
      events.ts            # FR-001 — descricao→description
      alerts.ts            # FR-001
      retros.ts            # FR-001
      skills.ts            # FR-001
      suggestions.ts       # FR-001 (hasTable already)
      overview.ts          # FR-008 — metric cols
      metrics.ts           # FR-008 — metric cols + JOIN on execution_id
      cross.ts             # FR-001 — execution_id JOINs
      memories.ts          # UNCHANGED (already EN)
  mappers/
    execution.ts decision.ts wave.ts task.ts bloqueio.ts(->block) event.ts
    alert.ts skill.ts suggestion.ts status.ts index.ts   # FR-006 snake→camel
packages/shared-types/src/
  entities.ts              # FR-004 — DTO interfaces -> camelCase EN
  schemas/entities.ts      # FR-005 — Zod z.object fields match DTOs
apps/web/                  # FR-009 — components/hooks consuming renamed DTO fields
```

---

## Convenções de Borda

| Camada | Case style | Validação | Fonte da verdade |
|---|---|---|---|
| DB columns (`knowledge.db` v7) | `snake_case` EN | `PRAGMA table_info` via `hasColumn` | `../cstk/.../migration-map.md` §3.11 (FROZEN) — owned by `cstk` |
| Server Row interfaces (`db/queries/*.ts`) | `snake_case` (mirrors DB) | `tsc --noEmit` | DB column = Row field, 1:1 |
| Server DTO (`packages/shared-types/src/entities.ts`) | `camelCase` EN | TS interface + Zod parse | `entities.ts` (shared-types) |
| Zod schemas (`schemas/entities.ts`) | `camelCase` EN | `z.object({…})` fields == DTO fields | `schemas/entities.ts` |
| Frontend DTO (`apps/web/`) | `camelCase` EN | re-export of shared-types DTO | `packages/shared-types` (single source) |
| API payload (response) | `camelCase` EN | envelope `{data, meta}` | DTO contract (above) |
| URL path/query params | unchanged by this feature | router | existing routes |

**Mapper layer (DB ↔ DTO)** — the SOLE snake↔camel translation point:
- Location: `apps/server/src/mappers/<entity>.ts`.
- Responsibility: read a `snake_case` Row field, write the `camelCase` DTO field.
  A mapper MUST NOT reference an old pt-BR Row field for a renamed column.
- ORM auto-mapping: **NO** — hand-written `better-sqlite3` prepared statements with
  explicit Row interfaces; the mapper does the casing bridge by hand.

**Validação Zod**:
- Edge: **response** side (server serialises DTO; `apps/web` Zod-parses on fetch).
- Shared schema: **YES** — `packages/shared-types/src/schemas/entities.ts`, imported by
  both server (shape assertion) and web (runtime parse). Renaming a DTO field WITHOUT
  renaming its Zod field is caught by `tsc` (field-name mismatch) and at runtime by a
  parse error — this is the guard that prevents the historical snake↔camel drift.

---

## Phase ordering (dependency-correct sweep)

The four layers have a strict dependency chain; renaming bottom-up avoids transient
`tsc` storms:

1. **shared-types** (`entities.ts` DTOs + `schemas/entities.ts` Zod) — FR-004/005.
   Renaming DTO fields first makes every downstream mapper/web reference a *compile
   error*, turning `tsc` into the worklist for steps 2–3.
2. **server queries** (`db/queries/*.ts` — Row interfaces + SQL column names + the
   `bloqueios→blocks` table/file rename + `hasColumn`/`hasTable` guards) — FR-001/002/
   003/007/008/010/011.
3. **server mappers** (`mappers/*.ts`) — bridge renamed Row → renamed DTO — FR-006.
4. **web** (`apps/web/`) — update destructured field names — FR-009.

Integration gate after each step: `pnpm --filter <ws> exec tsc --noEmit`. Final gate:
full-monorepo `tsc --noEmit` = 0 (FR-013) + `pnpm -r test` no regression (FR-014) +
real v7 roundtrip (quickstart Scenario B).

---

## Re-check (post-design)

Re-running the Constitution gate after Phase 1 design: the design introduces NO new
layer, NO new service, NO new abstraction — it reuses `columns.ts` and the existing
mapper layer. Blast radius is confined to renames within existing files (+ one file
content rename `bloqueios.ts`→`BlockRow`). All MUST principles remain PASS. No
Complexity Tracking required.

---

## Complexity Tracking

N/A — no constitution violation; no justified-complexity entry.

---

## Next Steps

1. `/checklist` — quality gate for the requirements before implementing.
2. `/create-tasks` — decompose this plan into an executable backlog (layer-ordered).
3. `/analyze` — cross-artifact consistency (spec ↔ plan ↔ tasks ↔ constitution).
