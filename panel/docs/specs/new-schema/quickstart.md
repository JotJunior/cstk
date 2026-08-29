# Quickstart — new-schema

> Critical-flow validation scenarios for the v7 schema adaptation. Each scenario is
> numbered-step → **Expected**. The Roundtrip End-to-End scenario runs against the
> REAL installed `~/.claude/cstk/knowledge.db` (v7, with live data), not a mock.

---

## Scenario A — tsc gate (primary integration gate, FR-013)

1. From the monorepo root, run the full type-check:
   ```bash
   pnpm -r exec tsc --noEmit
   # or, per workspace: pnpm --filter @cstk-panel/shared-types exec tsc --noEmit
   #                    pnpm --filter @cstk-panel/server       exec tsc --noEmit
   #                    pnpm --filter @cstk-panel/web          exec tsc --noEmit
   ```
2. **Expected**: zero TypeScript errors across `shared-types`, `apps/server`,
   `apps/web`. A leftover pt-BR Row/DTO/mapper reference for a renamed column surfaces
   here as a type error (e.g. `Property 'execucaoId' does not exist on type 'BlockDTO'`).

---

## Scenario B — Roundtrip End-to-End against the REAL v7 knowledge.db

> Exposes snake_case↔camelCase drift that mocks hide (plan §5.3 mandate). Uses the
> live DB confirmed at `schema_meta.schema_version = 7` carrying the `new-schema`
> execution (1 execution, 2 waves, 6 decisions, 1 event).

1. Confirm the target DB is v7:
   ```bash
   sqlite3 ~/.claude/cstk/knowledge.db \
     "SELECT value FROM schema_meta WHERE key='schema_version';"   # -> 7
   ```
2. Start the real Fastify server pointed at the installed DB:
   ```bash
   CSTK_KNOWLEDGE_DB="$HOME/.claude/cstk/knowledge.db" \
     pnpm --filter @cstk-panel/server dev   # binds localhost (Principle: localhost-only)
   ```
3. Hit the Executions endpoint and capture the REAL payload:
   ```bash
   curl -s http://localhost:<port>/api/v1/executions | tee /tmp/exec.json | jq '.data[0]'
   ```
4. **Expected**: the first row carries `camelCase` EN fields with non-null values —
   `executionId`, `currentStage`, `terminationReason`, `startedAt`, `finishedAt`,
   `wavesTotal`, `decisionsTotal`. No `execucaoId`/`etapaCorrente`/`motivoTermino`
   key appears anywhere in the payload (grep the captured file):
   ```bash
   ! grep -E 'execucaoId|etapaCorrente|motivoTermino|iniciadaEm' /tmp/exec.json
   ```
5. Drill into the waves of that execution:
   ```bash
   curl -s "http://localhost:<port>/api/v1/executions/<execution_id>/waves" | jq '.data'
   ```
6. **Expected**: two waves, each with `startedAt`, `finishedAt`, `stages`,
   `terminationReason`, `nStages`, `nSkills` populated (non-null where the wave is
   closed). No blank column that used to show data.
7. Page the decisions:
   ```bash
   curl -s "http://localhost:<port>/api/v1/executions/<execution_id>/decisions?limit=5&offset=0" \
     | jq '.data | length, .[0]'
   ```
8. **Expected**: 5 rows returned (6 total, paging works); each row has `agent`,
   `stage`, `choice`, `context`, `rationale`, `evidence`. The `meta` envelope carries
   `degraded`, `reason`, `freshness`, `schema_version` (Principle VI / envelope std).

---

## Scenario C — blocks table rename + hasTable guard (FR-002, FR-007)

1. Against the v7 DB (which has the `blocks` table, currently 0 rows):
   ```bash
   curl -s "http://localhost:<port>/api/v1/executions/<execution_id>/blocks" -o /tmp/b.json -w '%{http_code}\n'
   ```
2. **Expected**: HTTP `200`, body `data: []` (no exception, empty list).
3. Simulate a v6 DB (no `blocks` table) — use a fixture copy with the table absent,
   point the server at it, and re-hit the same endpoint.
4. **Expected**: HTTP `200`, `data: []` — `hasTable(db,'blocks')` returns `false`,
   the query degrades to an empty list instead of throwing (Principle II).

---

## Scenario D — v6 graceful degradation for renamed columns (P2, FR-007)

1. Point the server at a v6-style DB where `executions` has the pt-BR column
   `motivo_termino` but NOT `termination_reason`.
2. Hit `GET /api/v1/executions`.
3. **Expected**: HTTP `200`. `hasColumn(db,'executions','termination_reason')`
   returns `false` → the query projects `NULL AS termination_reason` → the DTO field
   `terminationReason` is `null`. The page renders an empty cell, no `5xx`.
4. **Expected**: no uncaught exception; `meta.degraded` may be `false` (the panel
   does not detect the version) — the contract is "no crash, 200 always".

---

## Scenario E — Single-vocabulary grep gate (Success Criterion 5)

1. Grep the server and shared-types sources for the 10 most common pt-BR column names:
   ```bash
   grep -rnE 'execucao_id|motivo_termino|etapa_corrente|iniciada_em|\betapas\b|\bescolha\b|justificativa|\bpergunta\b|testes_rodados' \
     apps/server/src packages/shared-types/src \
     | grep -vE 'hasColumn|hasTable|//|/\*|\.test\.|__tests__'
   ```
2. **Expected**: zero results outside back-compat guards, comments, or test fixtures.
   (The migration-map §4.6 mandates keeping ≥1 pt-BR fixture per layer to prove the
   v6 fallback still reads — those are excluded by the `__tests__`/`.test.` filter.)

---

## Scenario F — vitest regression (FR-014)

1. Run the existing suites:
   ```bash
   pnpm -r test
   ```
2. **Expected**: every suite that passed before the migration still passes. New
   back-compat tests (v6 fixture without the new columns/table) MAY be added; the
   pre-existing pass count does not decrease.
