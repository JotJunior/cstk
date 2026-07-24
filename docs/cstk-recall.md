**English** · [Português (pt-BR)](./cstk-recall.pt-BR.md)

# Knowledge memory (`cstk recall`)

> **Advanced track** — subsystem of the [autonomous orchestrator](./agente-00c.md).

An **additive** cross-feature memory layer: a global SQLite index
(`~/.claude/cstk/knowledge.db`, full-text via FTS5) fed automatically at the end
of each wave of the `agente-00c`/`feature-00c` orchestrators. It lets you search
decisions, blockers, retro-executions, invoked skills, and **memories**
(Claude Code `.md` files) from **any project or feature already executed**, with
provenance (project / feature / wave / date).

Since **schema v2** (backward-compatible index, additive and silent migration),
ingestion also derives **dashboard metrics** from `state.json` into dedicated
tables: `executions` (status / reason / duration per execution), `waves`
(lifecycle, `tool_calls`, `wallclock` per wave), `alert_signals` (circular /
budget breach signals), `tasks` (outcome pass|fail, tests, lint, touched files),
and `events`. Metrics such as human latency, clarify-rate, and model mix are
**derivable** from these tables — consumed by [`cstk serve`](./cstk-serve.md)
(read-only dashboard). The 4 original textual tables
(`decisions`/`bloqueios`/`retros`/`skills`) remain unchanged.

The index is purely **derived** — the transactional `state.json` remains the
source of truth, intact and off the critical path (ingestion reads it in
**read-only** mode, never writes). The whole database is disposable: it can be
rebuilt at any time via `--reindex` from the existing
`state.json`/`state-history`.

```bash
# Search (full-text, ordered by bm25 relevance)
cstk recall "lock contention"

# Filter by project, record type, and limit results
cstk recall "secrets-filter" --project cstk --type decision --limit 5

# Filter only memories (Claude Code .md files)
cstk recall "setup" --type memory

# Filter only suggestions (meta-pattern learning: diagnosis + proposal)
cstk recall "websocket auth" --type suggestion

# Rebuild the index from scratch from existing states (includes memories)
cstk recall --reindex

# Manual ingestion of a specific feature (normally the hook does this)
cstk recall --ingest --state-dir .claude/feature-00c-state/<short-name>

# Read-for-context (read-back loop): markdown block ready for injection
cstk recall --context "cache fts query" --limit 4 \
  --exclude-feature minha-feature-corrente --max-bytes 2000

# List indexed memories (slug + description, no body)
cstk recall --list-memories [--project P]
```

## Search-mode flags

- `--project P` — filters by source project
- `--type T` — `decision` | `bloqueio` | `retro` | `skill` | `memory` | `suggestion`
- `--limit N` — maximum results (positive integer; default 20)
- `--db PATH` — alternative index (default `$CSTK_KNOWLEDGE_DB` or
  `~/.claude/cstk/knowledge.db`)

## `--context` mode (read-back loop)

Closes the memory loop — instead of showing results for human reading, it
returns a **lean markdown block** ready for injection into a prompt's context.
The `agente-00c`/`feature-00c` orchestrators invoke it automatically at the start
of the `specify` and `plan` phases (PRE-DECISION step), injecting learning from
past executions **before** deciding. Differences from search mode: **OR**
composition between terms (higher recall over the feature's kebab keywords),
anti-echo `--exclude-feature` (omits the current feature so it does not echo its
own writes), and a hard byte ceiling.

- `--exclude-feature NAME` — anti-echo: omits findings from feature `NAME` (in SQL)
- `--limit N` — maximum findings (default **4**; recommended range 3-5)
- `--max-bytes N` — byte ceiling for the block (default **2000**; cuts by whole
  finding, never in the middle)
- `--type T` / `--project P` / `--db PATH` — same as search mode

It is **read-only** and **best-effort**: any degradation (no `sqlite3`, missing/
corrupted index, zero findings) results in a **silent no-op** (empty stdout,
exit 0) — it never gates a wave. Against prompt-injection via retrieved memory
there are **two layers** (ASI09/LLM01): (1) secret *scrubbing* at **ingestion**
(a real technical control) and (2) injection with an **UNTRUSTED /
non-authoritative** label — a defense-in-depth **mitigation**, **not a
guarantee**. The residual risk of an old record *instructing* the model remains;
that is why the content is never treated as an instruction.

**Graceful degradation**: the absence of `sqlite3` or `jq` **never** aborts a
wave — the ingestion hook and `recall` exit with status 0 emitting only a
warning. The index is isolated in `~/.claude/cstk/`, separate from the
per-project transactional state.

## Full documentation

- [`specs/_archived/cstk-knowledge-db/spec.md`](./specs/_archived/cstk-knowledge-db/spec.md) — user stories, FRs, success criteria
- [`specs/_archived/cstk-knowledge-db/contracts/cstk-recall.md`](./specs/_archived/cstk-knowledge-db/contracts/cstk-recall.md) — modes, flags, exit codes, FTS5 schema
- [`specs/_archived/knowledge-db-metrics/spec.md`](./specs/_archived/knowledge-db-metrics/spec.md) — metrics ingestion (schema v2)
- [`specs/_archived/knowledge-db-metrics/data-model.md`](./specs/_archived/knowledge-db-metrics/data-model.md) — table DDL and natural keys
