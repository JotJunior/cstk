# Research — new-schema

> **Feature**: `new-schema` — adapt `cstk-panel` to `knowledge.db` schema v7 (EN canonical columns).
> **Phase 0 output**. All NEEDS CLARIFICATION resolved below.
> **Source of truth (FROZEN)**: `../cstk/docs/specs/schema-en-migration/migration-map.md` §3.11.

---

## Decision 1 — Adopt the migration-map §3.11 as the only naming authority

**Decision**: Every pt→EN column/table rename applied to `cstk-panel` is traced
1:1 to a row in the frozen migration-map §3.11 (knowledge.db columns). The spec's
"Key Entities → Column rename surface" table is a copy of that map; where the two
ever disagree, the migration-map wins. No new column name is invented in the panel.

**Rationale**: The migration-map is explicitly FROZEN and is the authority for the
`cstk` toolkit that *produces* the DB. The panel only *consumes* it. Inventing a
name that diverges from what `recall.sh` writes would re-introduce the exact NULL/
crash class this feature exists to eliminate (migration-map §6 confirms recall.sh
emits the EN column names; verified empirically — see Decision 5).

**Alternatives considered**:
- *Re-derive names from the panel's existing pt-BR code* — rejected: produces drift
  the instant `cstk` changes the map again; violates the FROZEN single-source rule.
- *Wait for `cstk` to ship pt-BR read aliases at the SQL layer* — rejected: §3.11
  states the DB is dropped+recreated on the v6→v7 bump (no column aliases in SQL);
  the panel cannot rely on aliases that do not exist in the projected columns.

---

## Decision 2 — pt→EN rename decisions (the surface that changes)

**Decision**: Apply the renames exactly as enumerated in migration-map §3.11. The
full enumeration lives in `data-model.md`; the consolidated decision is:

- **Universal**: `execucao_id → execution_id` on every table and every JOIN.
- **Table rename**: `bloqueios → blocks` (+ `hasTable` guard for v6).
- **Per-table column renames** for `executions`, `waves`, `decisions`, `tasks`,
  `blocks`, `events`, `alert_signals`, `retros`, `skills`, `suggestions`.
- **Untouched (keep)**: provenance columns (`project`, `feature`, `wave`,
  `source_ts`, `source_id`, `ingested_at`), FTS columns (`body`, `type`, etc.),
  and metric proxies (`tool_calls_total`, `tool_calls`, `wallclock_seconds`,
  `n_skills`, `lint_ok`, `outcome`, `event_type`, `timestamp`, `status`, `score`).

**Rationale**: Renaming only the columns in §3.11 keeps the blast radius minimal and
traceable; keeping the provenance/FTS/proxy columns honors Constitution Principle III
(Honestidade de Metrica) — the `tool_calls` proxy is preserved verbatim, no metric
is invented or removed.

**Alternatives considered**:
- *`SELECT *` everywhere to dodge explicit column names* — rejected: the panel
  projects explicit columns precisely so that absent columns can be guarded with
  `NULL AS <col>` (Principle II); `SELECT *` would re-shape Row types unpredictably
  across v6/v7 and break the single-Row-shape invariant.

---

## Decision 3 — hasColumn / hasTable back-compat is extended, not redesigned

**Decision**: Reuse the existing `apps/server/src/db/columns.ts` helpers
(`hasColumn`, `hasTable`) — already proven for the v2→v3 additive columns
(`tasks.titulo`, `decisions.opcoes`) and the v4 `memories` table. For every renamed
column the panel projects explicitly, add a `hasColumn` guard projecting
`NULL AS <new_en_name>` (or `'' AS <new_en_name>` for non-null string helpers like
`tituloSelect → titleSelect`). For the `blocks` table, wrap the query in a
`hasTable(db, 'blocks')` guard returning `[]` when absent.

**Rationale**: The pattern is already the project's canonical mechanism for graceful
degradation (Principle II — "Degradar, Nunca Quebrar"). A v6 DB has the old pt-BR
column names; against it, `hasColumn(db, 'executions', 'termination_reason')`
returns `false` → the query projects `NULL AS termination_reason` → the page renders
an empty cell instead of a `5xx`. No new abstraction is introduced; this is the
existing per-column capability probe applied to a wider set of columns.

**Empirical confirmation of the existing pattern** (Decision 5 evidence):
`columns.ts` already implements a `WeakMap`-cached `PRAGMA table_info` probe and a
`sqlite_master` table probe; both swallow exceptions and return `false`, never throw.

**Alternatives considered**:
- *Detect DB schema version via `schema_meta` and branch query text* — rejected:
  Constitution Principle II and the migration-map §362 both forbid explicit version
  detection in the panel ("No cstk-panel code path attempts to detect the DB schema
  version explicitly — capability is probed per-column"). Per-column probing is more
  robust to partial/hand-edited DBs than a single version gate.

---

## Decision 4 — Back-compat strategy: graceful degradation, no version gate

**Decision**: The panel never asserts a DB version. A v7 DB shows full data; a v6 DB
(pt-BR columns, `bloqueios` table) degrades per-column to `NULL`/`[]`. `meta.degraded`
in the envelope may remain `false` (the panel does not *know* the version) — the
contract is "no crash, 200 always", satisfied by the `hasColumn`/`hasTable` guards.

**Rationale**: Aligns with Principle II (degradation is first-class, not an error)
and matches the panel's existing v2→v3 behavior. A v6 operator who has not yet run
`cstk recall --reindex` sees empty cells, not a `500` — exactly the P2 scenario.

**Alternatives considered**:
- *Hard-require v7 (throw on missing column)* — rejected: violates Principle II and
  the P2 user scenario (graceful v6 degradation).
- *Dual-read both column names per query* — rejected: doubles every projection and
  re-introduces pt-BR names into the codebase, defeating Success Criterion 5
  (single vocabulary).

---

## Decision 5 — The roundtrip target is a REAL v7 knowledge.db, not a mock

**Decision**: The quickstart's End-to-End roundtrip scenario runs the real Fastify
server against the installed `~/.claude/cstk/knowledge.db`, which is already v7.

**Rationale**: The plan skill mandates a real-backend roundtrip because 40 historical
waves masked a snake_case↔camelCase drift by parsing mocks. Only a real payload
exposes that class of divergence. The installed DB is confirmed v7 with ingested data.

**Evidence (empirical sonda, 2026-05-30)**:
```
$ sqlite3 ~/.claude/cstk/knowledge.db "SELECT value FROM schema_meta WHERE key='schema_version';"
7
$ sqlite3 ~/.claude/cstk/knowledge.db "PRAGMA table_info(executions);" | grep -E 'execution_id|termination_reason|current_stage|started_at'
4|execution_id|TEXT|1||0
8|termination_reason|TEXT|0||0
9|current_stage|TEXT|0||0
10|started_at|TEXT|0||0
$ sqlite3 ~/.claude/cstk/knowledge.db "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('blocks','bloqueios');"
blocks
$ for t in executions waves decisions events; do echo -n "$t="; sqlite3 ~/.claude/cstk/knowledge.db "SELECT count(*) FROM $t;"; done
executions=1 waves=2 decisions=6 events=1
```
The DB carries the `new-schema` feature's own execution (1 execution, 2 waves,
6 decisions, 1 event) — a live, non-mock roundtrip fixture.

**Alternatives considered**:
- *Synthetic in-memory fixture* — rejected by the plan skill's §5.3 mandate; a
  fixture would not exercise the real `better-sqlite3` projection path.

---

## Decision 6 — Two-edge convention: DB snake_case EN ↔ DTO camelCase EN

**Decision**: The DB column is `snake_case` EN (e.g. `current_stage`); the TS/Zod DTO
field is `camelCase` EN (e.g. `currentStage`). The mapper layer
(`apps/server/src/mappers/*.ts`) is the SINGLE translation point between the two
casings. Row interfaces mirror DB `snake_case`; DTOs and Zod schemas mirror
`camelCase`. No layer mixes an old pt-BR name with a new EN name.

**Rationale**: This is the exact failure mode the plan skill's "Convenções de Borda"
section was added to prevent (dec-172/dec-173: a snake↔camel drift that survived 40
waves because the convention was never declared upfront). Declaring the source of
truth per edge makes any future drift a one-line table lookup, not an archaeology dig.

**Alternatives considered**:
- *Auto-mapping ORM (kysely/sqlc)* — rejected: the panel uses hand-written
  `better-sqlite3` prepared statements with explicit Row interfaces; introducing an
  ORM is out of scope and would violate "minimal blast radius".

---

## Decision 7 — FTS / search layer is explicitly out of scope (FR-012)

**Decision**: `lib/fts.ts` and `knowledge_fts` are unchanged. Columns `body`, `type`,
`project`, `feature`, `wave`, `source_id`, `source_ts` are not renamed in v7
(migration-map §3.11 lists FTS columns as keep). FR-012 is a confirmation of
unchanged scope, not a work item.

**Rationale**: Touching the FTS layer would risk the two-level escaping invariant
(Principle V — FTS5 tokenization + parameterized SQL) for zero benefit, since no FTS
column changed name.

---

## Resolved NEEDS CLARIFICATION

| Unknown | Resolution |
|---|---|
| Is the installed knowledge.db actually v7? | YES — `schema_meta.schema_version=7`, EN columns + `blocks` table confirmed empirically (Decision 5). |
| Does v6 back-compat need a new mechanism? | NO — extend existing `hasColumn`/`hasTable` (Decision 3). |
| Should the panel detect schema version? | NO — per-column capability probe only (Decision 4, Principle II). |
| Casing convention authority per edge? | DB=snake_case EN; DTO/Zod=camelCase EN; mapper is the sole bridge (Decision 6). |
| Is the FTS layer affected? | NO — FR-012, out of scope (Decision 7). |
| Roundtrip fixture: mock or real? | REAL — installed v7 DB with live data (Decision 5). |
