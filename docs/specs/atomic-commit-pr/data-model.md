# Data Model: atomic-commit-pr

**Feature**: `atomic-commit-pr` | **Date**: 2026-06-13

The feature is stateless except for ONE persisted config flag plus two
in-flight result records. All state lives in the orchestrator's `state.json`
(the canonical, hash-verified, resume-surviving store). No database, no new
files. Fields below are ADDITIVE — existing state.json semantics are unchanged
and absent fields read as their documented defaults (retro-compatible).

---

## Entity: AtomicCommitConfig

The single persisted opt-in flag. Written once at init; read by every stage,
task, resume, and the terminal finalize step.

| Field | Type | Required | Default | Notes |
|-------|------|----------|---------|-------|
| `atomic_commit_enabled` | bool | no | `false` | Top-level key in `state.json`. Set at init from the operator's opt-in answer. Absent => `false` (retro-compat). |

**Persistence**: top-level `.atomic_commit_enabled` in
`<state-dir>/state.json`. Written by `state-rw.sh init --atomic-commit
<true|false>` (new flag; omitted => `false`). Read by `commit-mode.sh
is-enabled`.

**Lifecycle**:

```
init (operator answers prompt)
   │
   ├── "yes"  → .atomic_commit_enabled = true   (persisted)
   └── "no"/∅ → .atomic_commit_enabled = false  (persisted; == today)

resume → READ .atomic_commit_enabled (never re-prompt)  [FR-002]
```

**Validation**: strictly boolean. `state-validate.sh` accepts `true`, `false`,
or absent (treated as `false`). Any other value is a schema error.

---

## Entity: StagedCommit (in-flight, not persisted as a list)

A git commit created by the orchestrator after a stage or task completes. It is
a transient runtime concept — the durable record is the git history itself, not
a state.json array. The orchestrator MAY append a lightweight audit note to the
existing `.events[]` timeline (additive), but StagedCommit is NOT a new
top-level array.

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `kind` | enum `stage` \| `task` | yes | what triggered the commit |
| `ref` | string | yes | stage name (`specify`,`plan`,…) or task id(s) (`3.1` or `3.1-3.2`) |
| `wave_id` | string | yes | wave in which the commit was made (provenance) |
| `feature` | string | yes | feature/project short name (message subject) |
| `message` | string | yes | Conventional-Commit message built by `commit-mode.sh stage-message`/`task-message`; committed directly via `git commit -m` (pipeline non-interactive mode) |
| `outcome` | enum `committed` \| `noop-empty` \| `skipped-default-branch` | yes | result of the attempt |

**Message format (FR-007)**:

- Stage: `docs(<scope>): <stage> <feature>` — e.g.
  `docs(spec): generate spec.md for atomic-commit-pr`,
  `docs(plan): add plan.md for atomic-commit-pr`.
- Task (single): `<type>: task <id> <brief>` — e.g.
  `feat: task 3.1 add commit-mode helper`.
- Task (grouped): `<type>: tasks <id-range> <brief>` — e.g.
  `feat: tasks 3.1-3.2 add helper + wire orchestrators`.

The `<type>`/`<scope>` and final wording are produced by `commit-mode.sh
stage-message` / `task-message` and committed directly via `git commit -m`
(pipeline non-interactive mode). The `commit` skill is NOT used in automated
pipeline mode (interactive prompts incompatible with autonomous execution).

**Task grouping (always-on per wave)**: tasks completed with outcome=pass in
the same wave are ALWAYS grouped into a single commit. No separate `group_tasks`
flag. Single-task waves receive an individual commit. Grouping uses the
range/list format of `task-message` (contiguous ids → range; non-contiguous →
list).

**State transitions**:

```
attempt
  ├── nothing staged            → noop-empty            (FR-006; no empty commit)
  ├── HEAD == default branch    → skipped-default-branch (FR-005; warn, non-fatal)
  └── staged changes on session → committed
```

---

## Entity: PushPRResult (persisted, single record)

The outcome of the terminal push+PR step, recorded for auditability (US4).
Stored as a single top-level object `.push_pr_result` (additive). Absent until
the terminal finalize runs.

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `status` | enum (below) | yes | terminal outcome |
| `branch` | string | no | session branch that was pushed |
| `pr_url` | string | no | URL of the opened/reused PR (when status=`pr-opened` or `pr-exists`) |
| `reason` | string | no | human-readable detail for skip/error statuses |
| `recorded_at` | string (ISO 8601) | yes | timestamp |

**`status` enum**:

| Value | Meaning |
|-------|---------|
| `pr-opened` | branch pushed, new PR created |
| `pr-exists` | idempotent reuse of an existing OPEN/MERGED PR (FR-009) |
| `skipped-disabled` | atomic mode off — no push/PR (FR-011) |
| `skipped-no-commits` | session branch had no new commits vs default |
| `skipped-default-branch` | HEAD was the default branch (FR-005) |
| `skipped-abort` | pipeline aborted — no push/PR on abort (FR-011) |
| `skipped-gh-missing` | `gh` not installed (FR-010, non-fatal) |
| `skipped-gh-unauth` | `gh` not authenticated (FR-010, non-fatal) |
| `error` | other non-fatal failure; commits remain intact |

**State transitions**:

```
terminal finalize
  ├── disabled                  → skipped-disabled
  ├── abort path                → skipped-abort
  ├── HEAD == default           → skipped-default-branch
  ├── no new commits            → skipped-no-commits
  ├── gh missing                → skipped-gh-missing   (non-fatal warning)
  ├── gh unauth                 → skipped-gh-unauth    (non-fatal warning)
  ├── PR already open/merged    → pr-exists            (idempotent, FR-009)
  ├── push + create ok          → pr-opened
  └── push ok / create failed   → error                (non-fatal; commits intact)
```

**Mapping to `_session_pr` exit codes** (`cli/lib/session.sh`):

| `_session_pr` exit | PushPRResult.status |
|--------------------|---------------------|
| 0 (created) | `pr-opened` |
| 0 (existing reused) | `pr-exists` |
| `CSTK_SESSION_EXIT_NO_COMMITS` | `skipped-no-commits` |
| `CSTK_SESSION_EXIT_GH_MISSING` | `skipped-gh-missing` |
| `CSTK_SESSION_EXIT_GH_UNAUTH` | `skipped-gh-unauth` |
| other non-zero | `error` |

---

## Retro-compatibility

- `.atomic_commit_enabled` absent ⇒ `false` ⇒ today's behavior (no commits, no
  push, no PR). SC-002 / SC-005 hold by construction.
- `.push_pr_result` absent ⇒ feature never reached terminal finalize (or was
  never enabled). No reader assumes its presence.
- `.events[]` additions are optional audit notes consumed only by the
  knowledge-db ingestion and the panel; absence is a no-op.
