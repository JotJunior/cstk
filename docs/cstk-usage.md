**English** · [Português (pt-BR)](./cstk-usage.pt-BR.md)

# Loose usage tracking (`cstk usage`)

> **Advanced track** — opt-in, complements [Knowledge memory](./cstk-recall.md).

Tracks Claude Code token/cost consumption that happens **outside** any
`agente-00c`/`feature-00c` execution — regular interactive sessions. Opt-in via
the same native local telemetry configuration Claude Code already uses (no
second toggle): a `PostToolUse` hook writes a local TSV sidecar per
process/segment, throttled and silent by design (never blocks or slows down
the session). `cstk usage` reads that sidecar plus the `loose_usage` table in
`knowledge.db` to report consumption by project/model, and to compare it
against pipeline (orchestrator) consumption.

```bash
# Enable the capture hook (opt-in, default OFF)
cstk hooks install --with-loose-usage

# List loose consumption by project/model
cstk usage
cstk usage --project my-project --since 2026-08-01 --json

# Compare loose vs pipeline consumption for a project (mix + blended cost/Mtok)
cstk usage compare --project my-project

# Prune sidecar segments + indexed rows past the retention TTL
cstk usage prune --dry-run
cstk usage prune --older-than-days 30
```

## Subcommands

- `usage [--project P] [--since ISO] [--limit N] [--json] [--db PATH]` —
  one section per project, one line per model (model, tokens, cost, share).
  A field with no measurement prints `nao medido` (text) / `null` (`--json`),
  never `0`.
- `usage compare [--project P] [--since ISO] [--json] [--db PATH]` —
  `loose` (from `loose_usage`) vs `pipeline` (from `wave_model_usage`)
  side by side; aggregated per category, never joined row-by-row (different
  granularities). Includes `blended_cost_per_mtok`
  (`SUM(cost_usd)/SUM(total_tokens)*1e6`; `null` when the sum is zero/absent).
- `usage prune [--dry-run] [--older-than-days N] [--db PATH]` — removes
  **closed** sidecar segments older than the TTL
  (`CSTK_LOOSE_USAGE_RETENTION_DAYS`, default `90`) plus the corresponding
  `loose_usage` rows. Open segments are never eligible. `--dry-run` reports
  the same selection without any side effect.

**Requirements**: `sqlite3`, `jq`. Capture requires the hook to be installed
(`cstk hooks install --with-loose-usage`, opt-in, default OFF — never bundled
with the mandatory guard hooks).

## Data captured

Only cost/token/model metadata — `project`, `project_path`, `process_key`,
`segment_id`, `model`, `cost_usd`, `total_tokens`, `segment_open`,
`captured_at`, `ingested_at`. No prompt/conversation content field exists in
the schema. Sidecar directory/files use restrictive permissions (`chmod 700`
on directories, `chmod 600` on files), same posture as `knowledge.db`.

## Plan usage gauge (`cstk statusline` + `cstk plan-usage`)

Since v7.2.0 the same `knowledge.db` also stores the **plan usage gauge** you
see in `/usage` — no OAuth credential, no API key: Claude Code already sends
`rate_limits.five_hour`/`seven_day` in the `statusLine.command` payload on
every render, so the capture hook (`statusline-plan-usage.sh`) just reads
what is already passing by and persists it in the `plan_usage` table
(additive schema migration 13→14).

```bash
# Enable the capture (opt-in, default OFF)
cstk statusline install

# Is the capture active (and settings.json still valid)?
cstk statusline status

# Latest capture per scope (five_hour / seven_day)
cstk plan-usage [--json] [--db PATH]

# Time series per scope
cstk plan-usage history [--scope five_hour|seven_day] [--limit N] [--since ISO] [--json] [--db PATH]
```

- `statusline install` — writes/updates `statusLine.command` in
  `~/.claude/settings.json` pointing at the capture hook. An existing custom
  statusline command is preserved in `CSTK_STATUSLINE_INNER_COMMAND` and
  chained as a mandatory stdout pass-through — never silently overwritten.
  Idempotent (running it twice does not nest wrapper over wrapper); since
  v7.2.1 it also **repairs** a broken state (missing `statusLine.type`, which
  makes the harness discard the whole file) and preserves the file's
  original permissions.
- `statusline status` — reports the current state; prints `INVALIDO` with
  the remediation (exit 1) when `settings.json` is in a state the harness
  would reject.
- `plan-usage` / `plan-usage history` — latest capture per scope / time
  series; `history` literally reuses `--limit`/`--since` from `cstk usage`
  (no new pagination convention). A scope with no measurement prints
  `nao medido` (text) / `null` (`--json`) — never a fabricated `0`.

Capture semantics (Principle VI): total absence of `rate_limits` in the
payload never generates a row; partial absence of a field within a present
scope writes an explicit `NULL`, never `0`. A throttle compares against the
**last persisted record** of that scope with 2-decimal tolerance on
`used_percentage`, so harness float noise does not create new rows.

Spec: [`specs/plan-usage-capture/`](./specs/plan-usage-capture/)
([`contracts/cli-plan-usage.md`](./specs/plan-usage-capture/contracts/cli-plan-usage.md),
[`contracts/statusline-hook.md`](./specs/plan-usage-capture/contracts/statusline-hook.md),
[`data-model.md`](./specs/plan-usage-capture/data-model.md)).

## Full documentation

- [`specs/_archived/2026-08-08-loose-usage-capture/spec.md`](./specs/_archived/2026-08-08-loose-usage-capture/spec.md) — user stories, FRs, success criteria
- [`specs/_archived/2026-08-08-loose-usage-capture/contracts/cli-usage.md`](./specs/_archived/2026-08-08-loose-usage-capture/contracts/cli-usage.md) — flags, exit codes, output formats
- [`specs/_archived/2026-08-08-loose-usage-capture/contracts/hook-loose-usage.md`](./specs/_archived/2026-08-08-loose-usage-capture/contracts/hook-loose-usage.md) — capture hook contract
- [`specs/_archived/2026-08-08-loose-usage-capture/data-model.md`](./specs/_archived/2026-08-08-loose-usage-capture/data-model.md) — schema + retention policy
