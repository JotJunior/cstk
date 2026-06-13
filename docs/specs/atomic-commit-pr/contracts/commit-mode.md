# Contract: `commit-mode.sh`

**Feature**: `atomic-commit-pr`
**File**: `global/skills/agente-00c-runtime/scripts/commit-mode.sh`
**Style**: POSIX sh (Principle II NON-NEGOTIABLE), zero mandatory deps.
**Optional deps**: `jq` (state read/write), `git` (branch/commit), `gh` via
`cstk session pr` (terminal PR). Absence of an optional dep ⇒ graceful no-op
or recorded skip status, NEVER an aborted wave (constitution amendment 1.1.0).

This helper encapsulates the entire opt-in atomic-commit surface. It is the
single auditable, testable unit for the feature. Existing `state-ondas.sh
git-commit` is NOT modified.

---

## Global conventions

- Every subcommand requires `--state-dir DIR`.
- Exit codes: `0` success / handled, `1` generic error, `2` usage error,
  `3` guard refusal (branch/disabled — NON-fatal to the caller; caller logs
  and continues).
- All stdout is machine-consumable (single token or JSON object as documented).
- All diagnostics go to stderr via the `_log.sh` helpers (`log_err`/`log_out`),
  which apply the secrets filter (FR-036 parity).

---

## `commit-mode.sh is-enabled --state-dir DIR`

Read the persisted opt-in flag.

- **Reads**: `.atomic_commit_enabled` from `<DIR>/state.json` (absent ⇒ false).
- **stdout**: `true` or `false` (exactly one token).
- **Exit**: `0` always (read-only; missing state ⇒ `false`, exit 0).

---

## `commit-mode.sh set-enabled --state-dir DIR --value <true|false>`

Persist the operator's opt-in choice (called once at init by the entry command,
OR encapsulated behind `state-rw.sh init --atomic-commit`).

- **Writes**: `.atomic_commit_enabled = <value>` via the audited
  `state-rw.sh set` path (state-history backup + sha256 update).
- **Validation**: `--value` MUST be `true` or `false`; else exit `2`.
- **Exit**: `0` on success, `1` on write failure, `2` on usage error.

> NOTE: the canonical injection is `state-rw.sh init --atomic-commit
> <true|false>` (new flag, default `false`). `set-enabled` exists for the
> resume/repair path and for symmetry; init is the primary writer.

---

## `commit-mode.sh guard-branch --state-dir DIR --projeto-alvo-path PATH`

Refuse if HEAD is the default branch (FR-005, SC-004).

- **Resolves**: default branch using the same logic as
  `cli/lib/session.sh::_session_default_branch` (remote HEAD ⇒ fallback
  `main`/`master`).
- **Compares**: current HEAD branch (`git -C PATH rev-parse --abbrev-ref HEAD`)
  against default.
- **stdout**: current branch name (informational).
- **Exit**:
  - `0` — HEAD is a non-default (session/feature) branch ⇒ safe to commit/push.
  - `3` — HEAD == default branch ⇒ caller MUST skip the commit/push and log a
    warning (NON-fatal; pipeline continues).
  - `1` — not a git repo / git missing (caller skips, logs).

---

## `commit-mode.sh stage-message --feature NAME --stage STAGE`

Build the *intent string* for a per-stage commit (FR-003/FR-007). The helper
does NOT commit — it returns the structured intent the orchestrator hands to
the installed `commit` skill.

- **stdout**: a single line, e.g.
  `docs(spec): generate spec.md for atomic-commit-pr`.
- The scope is derived from the stage (`specify`→`spec`, `plan`→`plan`,
  `clarify`→`spec`, `checklist`→`checklist`, `create-tasks`→`tasks`).
- **Exit**: `0`; `2` on missing args.

---

## `commit-mode.sh task-message --feature NAME --task-ids "ID[,ID...]" [--brief TEXT]`

Build the intent string for a per-task or grouped-task commit (FR-004/FR-007).

- **Single id** (`--task-ids 3.1`): `feat: task 3.1 <brief>`.
- **Multiple ids** (`--task-ids 3.1,3.2`): collapse contiguous ids into a range
  ⇒ `feat: tasks 3.1-3.2 <brief>`; non-contiguous ⇒ list form
  `feat: tasks 3.1, 3.4 <brief>`.
- `<brief>` defaults to empty (the `commit` skill fills detail from the diff).
- **stdout**: single line.
- **Exit**: `0`; `2` on missing args.

> The `commit` skill produces the FINAL message and performs staging
> (`git add` by name, never `-A`/`.`, with secret-file warnings). This helper
> only supplies the canonical subject so format stays consistent.

---

## `commit-mode.sh finalize --state-dir DIR --projeto-alvo-path PATH --session NAME [--title T] [--body B]`

Terminal push+PR (FR-008/009/010/011). Called ONLY on terminal success, only
when `is-enabled` is true and HEAD is non-default.

**Algorithm**:

1. If `is-enabled` == false ⇒ record `PushPRResult.status=skipped-disabled`,
   exit `0` (no-op).
2. `guard-branch`; if exit `3` ⇒ record `skipped-default-branch`, exit `0`.
3. Delegate to `cstk session pr "$NAME" [--title …] [--body …]`
   (`cli/lib/session.sh::_session_pr`), which is idempotent (PR-exists reuse,
   push no-op when in sync) and resolves the default branch and gh status.
4. Map the `_session_pr` exit code to `PushPRResult.status` (see
   `data-model.md` mapping table) and persist `.push_pr_result` via the audited
   `state-rw.sh set` path (status/branch/pr_url/reason/recorded_at).
5. **Non-fatal contract (FR-010)**: any failure of step 3 ⇒ record the mapped
   skip/error status, log a clear warning, return `0` (pipeline completion is
   NEVER blocked by push/PR failure). Local commits remain intact.

- **stdout**: JSON object mirroring the persisted `PushPRResult`.
- **Exit**: `0` in all handled cases (skips, gh-missing, gh-unauth, error are
  all non-fatal); `2` on usage error.

---

## Default-safe invariants (tested in `tests/test_commit-mode.sh`)

| Invariant | Assertion |
|-----------|-----------|
| INV-1 | `is-enabled` on a state with no field ⇒ `false`, exit 0 |
| INV-2 | `guard-branch` on default branch ⇒ exit 3, no commit |
| INV-3 | `finalize` when disabled ⇒ `skipped-disabled`, exit 0, no `gh`/`git push` invoked |
| INV-4 | `finalize` non-fatal: gh missing ⇒ `skipped-gh-missing`, exit 0 |
| INV-5 | `finalize` idempotent: PR already open ⇒ `pr-exists`, no duplicate |
| INV-6 | `stage-message`/`task-message` emit Conventional-Commit subjects |
| INV-7 | grouped contiguous ids collapse to a range; non-contiguous list form |
| INV-8 | every write goes through `state-rw.sh set` (state-history + sha256), never `echo`/`cp` into state.json |

---

## Reused contracts (NOT re-implemented)

| Concern | Reused from |
|---------|-------------|
| push + PR (idempotent, default-branch resolve, gh status) | `cli/lib/session.sh::_session_pr` |
| commit message + staging + secret-file warnings | installed `commit` skill |
| state read/write (audited, hashed) | `state-rw.sh get` / `set` / `init` |
| secrets-filtered logging | `_log.sh` (`log_err` / `log_out`) |
| default-branch resolution | `_session_default_branch` (same logic) |
