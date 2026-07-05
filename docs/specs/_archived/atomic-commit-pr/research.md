# Phase 0 Research: atomic-commit-pr

**Feature**: `atomic-commit-pr` | **Date**: 2026-06-13

This document resolves the open technical questions before design. The feature
is a META-FEATURE: it modifies the cstk toolkit's own orchestrators
(`agente-00c` / `feature-00c`). All design decisions below are grounded in
empirical inspection of the existing source tree.

---

## Decision 1: New helper `commit-mode.sh` vs. extend `state-ondas.sh git-commit`

**Decision**: Create a NEW POSIX helper
`global/skills/agente-00c-runtime/scripts/commit-mode.sh`, and KEEP the
existing `state-ondas.sh git-commit` subcommand untouched (it serves the
abort/init local-commit path under the unchanged default behavior).

**Rationale**:

- The existing `state-ondas.sh git-commit` is hardcoded to one commit-message
  shape (`chore(agente-00c): <onda> - <motivo>`), stages `git add -- .`
  (everything), and has NO branch-default guard and NO push capability. Its
  doc string literally states "NUNCA `git push`". Bending it to also: detect
  opt-in mode, build Conventional-Commit messages per *stage* vs per *task*
  (with grouped ranges), guard the default branch, and trigger a terminal
  push+PR would overload a single subcommand with four orthogonal concerns and
  break its current contract used by the abort flow.
- A dedicated helper isolates the entire opt-in surface behind one auditable,
  independently testable unit (`test_commit-mode.sh`, mandated by
  `--check-coverage`). This matches the toolkit's "one helper, one concern"
  convention (see `bash-guard.sh`, `path-guard.sh`, `whitelist-validate.sh`).
- The helper composes existing primitives rather than reimplementing them:
  staging/message via the `commit` skill (operator-installed), terminal
  push+PR via `cstk session pr` (`cli/lib/session.sh::_session_pr`).

**Subcommands of `commit-mode.sh`** (detail in `contracts/commit-mode.md`):

| Subcommand | Concern |
|------------|---------|
| `is-enabled` | read `.atomic_commit_enabled` from state.json (default false) |
| `set-enabled` | persist the operator's opt-in choice at init |
| `guard-branch` | refuse if HEAD == default branch (exit non-zero) |
| `stage-message` | build a Conventional-Commit message for a stage |
| `task-message` | build a Conventional-Commit message for a task (or grouped range) |
| `finalize` | terminal push+PR, delegating to `cstk session pr` (idempotent) |

**Alternatives considered**:

- *Extend `state-ondas.sh git-commit`*: rejected — overloads a stable
  subcommand consumed by the abort path; mixes default-safe local commit with
  opt-in push semantics; harder to test in isolation.
- *Inline all logic in the orchestrator markdown*: rejected — the orchestrators
  are LLM-driven docs; the same failure mode that lets the LLM "forget" a step
  applies. Determinism requires a script (Principle II favors POSIX scripts as
  the deterministic substrate; cf. the `reconcile-tasks` backstop rationale).

---

## Decision 2: How the terminal `git push` escapes `bash-guard.sh`

**Context (empirical)**: `bash-guard.sh` lines 84-86 BLOCK any
`git push` unconditionally, emitting block reason `git-push` with the message
"git push bloqueado em qualquer remote (Principio V)". This is the enforcement
point of the original `agente-00c` spec FR-028.

**Decision**: The terminal push is performed by `cstk session pr` (the `cstk`
CLI binary calling `cli/lib/session.sh::_session_pr`), NOT by a `git push`
command the orchestrator constructs and passes through `bash-guard.sh`.
`bash-guard.sh` intercepts *Bash command strings the orchestrator builds from
input*; it does not (and must not) rewrite the internals of the trusted `cstk`
CLI. Therefore the carve-out is achieved by ROUTING the push through the
already-trusted `cstk session pr` path, while `bash-guard.sh` continues to
block ad-hoc `git push` strings.

**Refinement to `bash-guard.sh`**: keep the blanket block of raw `git push`,
but add a NARROW allow for the exact terminal invocation form
`cstk session pr` (which is a cstk subcommand, not a raw git push) — i.e.
`bash-guard.sh` already does not match `cstk session pr` against its
`git push` regex, so NO change to `bash-guard.sh` is strictly required for the
happy path. The plan documents this explicitly so a future hardener does not
"tighten" the guard to also catch `cstk session pr` and silently break the
feature. The guard's doc/help text (lines 314-315) is updated to note the
carve-out: raw `git push` stays blocked; terminal push is delegated to
`cstk session pr` under atomic mode + terminal success + non-default branch.

**Rationale**: This preserves the default-safe posture (no ad-hoc push ever),
reuses the battle-tested idempotent push+PR in `_session_pr` (default-branch
resolution, no-commits guard, PR-exists idempotency, gh missing/unauth handling
with clear exit codes), and keeps the carve-out auditable (one named code path).

**Alternatives considered**:

- *Relax `bash-guard.sh` to allow `git push` when a flag is set*: rejected —
  introduces a mutable bypass of a safety guard reachable from arbitrary Bash
  strings; far wider blast radius than routing through one trusted subcommand.
- *Add a brand-new push function in the runtime*: rejected — `_session_pr`
  already implements every FR-008/009/010 requirement; reimplementing is
  duplicate surface and duplicate test burden.

---

## Decision 3: Where the opt-in prompt is injected and how it is persisted

**Decision**: Inject the single yes/no prompt in the entry commands
`/agente-00c` (`global/commands/agente-00c.md`, after §0 warm-up, before the
`state-rw.sh init`) and `/feature-00c` (`global/commands/feature-00c.md`,
after §0 warm-up, before the `state-rw.sh init` at lines 183-192). The default
is "no" (Enter / empty / non-affirmative => disabled). The choice is written to
state at init time via a new `--atomic-commit <true|false>` flag on
`state-rw.sh init`, which sets `.atomic_commit_enabled` (default `false` when
the flag is omitted — preserving current behavior and old state files).

**Rationale**:

- The warm-up §0 is the canonical "operator is present" window (per the
  recall-injected memory: batch all human authorization at start). Placing the
  opt-in there guarantees the operator answers while present, and the rest of
  the run stays autonomous.
- Persisting at init (not lazily) means every subsequent wave and every resume
  reads a stable boolean. Resume commands (`agente-00c-resume.md`,
  `feature-00c-resume.md`) MUST read `.atomic_commit_enabled` from state and
  MUST NOT re-prompt (FR-002 idempotency).
- Defaulting to `false` when the field is absent makes the change
  retro-compatible: existing state.json files (pre-feature) read as disabled,
  exactly the current behavior (SC-002, SC-005 zero-regression).

**Alternatives considered**:

- *Prompt inside the orchestrator (subagent)*: rejected — the orchestrator runs
  autonomously and may be a subagent without an interactive operator; the
  prompt would block or be unanswerable.
- *Separate sidecar config file*: rejected — splits the source of truth;
  state.json is the canonical, hash-verified, resume-surviving store.

---

## Decision 4: Per-stage vs per-task commit triggering points in the loop

**Decision**:

- **Per-stage commit (FR-003)**: triggered in each orchestrator's wave loop
  AFTER the stage artifacts are written and the quality gates run, and BEFORE
  the wave closes (`state-ondas.sh end`) and the backup is taken — i.e. between
  the existing "advance phase" step and the "backup" step. For the
  feature-orchestrator this is between step 7 (advance phase) and step 8
  (backup); for `agente-00c-orchestrator.md` the analogous local-commit point
  is ~lines 1388-1391 (currently `state-ondas.sh git-commit ... NUNCA push`).
- **Per-task commit (FR-004)**: triggered during `execute-task` after each task
  reaches outcome=pass (the same point where `.tasks[]` outcome is appended,
  step 7). Tasks that passed in the same wave MAY be grouped into one commit
  with a range message; failed tasks (outcome=fail) are NEVER committed.
- **Terminal push+PR (FR-008)**: triggered ONLY when the pipeline reaches
  terminal success (all tasks pass + review-task green), inside the
  closing/finalization of the terminal wave, BEFORE emitting the final report.
  NOT on abort, NOT on partial completion, NOT when disabled (FR-011).

**Rationale**: These points already exist in both orchestrator loops as the
natural "artifact is durable" boundaries; the per-stage local commit point even
exists today for `agente-00c`. Reusing them avoids inventing new control flow
and keeps the commit strictly after the artifact is real (so an interrupted
mid-stage run leaves no partial commit — FR US2 AC3).

**Alternatives considered**:

- *Commit at wave start*: rejected — would commit incomplete/partial artifacts.
- *Single squashed commit at end*: rejected — defeats the per-stage/per-task
  auditable-history value (US2/US3).

---

## Decision 5: No-op / empty-commit and branch-guard semantics

**Decision**:

- **No-op (FR-006)**: before committing, the helper checks
  `git diff --cached --quiet` (after staging); if nothing is staged, the commit
  is skipped with a log line, never `--allow-empty`. This mirrors the existing
  `state-ondas.sh git-commit` no-op behavior, which is the proven pattern.
- **Branch guard (FR-005)**: `commit-mode.sh guard-branch` resolves the default
  branch (reusing the same logic as `_session_default_branch` in
  `cli/lib/session.sh`) and compares against current HEAD. If HEAD == default,
  the commit/push is SKIPPED and a warning logged — never an abort (the
  pipeline continues; commits just don't happen). This protects SC-004 (100%
  default-branch protection) without making a session-branch misconfiguration
  fatal.

**Rationale**: Fail-safe, fail-loud-but-non-fatal. A misconfigured branch
should not crash an autonomous run; it should refuse to write history to the
wrong place and say so. The no-op guard prevents empty-commit noise.

**Alternatives considered**:

- *Hard abort on default branch*: rejected — too brittle for autonomous runs;
  a warning + skip is the safer default and still satisfies SC-004 (no push
  to default ever occurs).

---

## Decision 6: gh unavailable / unauthenticated at PR time (FR-010)

**Decision**: Delegate entirely to `_session_pr`, which already distinguishes
`CSTK_SESSION_EXIT_GH_MISSING` and `CSTK_SESSION_EXIT_GH_UNAUTH` and emits
clear, actionable error messages. The orchestrator treats a non-zero return
from `commit-mode.sh finalize` as a NON-FATAL warning: local commits remain
intact, the pipeline completes successfully, and the warning is recorded in
state (`PushPRResult.status = "skipped-gh-missing" | "skipped-gh-unauth" |
"error"`).

**Rationale**: PR creation failure must never block pipeline completion
(FR-010 explicit). `_session_pr` already returns granular exit codes; the
helper maps them to a recorded `PushPRResult` for auditability.

**Alternatives considered**:

- *Retry loop on gh auth*: rejected — autonomous run cannot complete an
  interactive `gh auth login`; a clear one-shot warning is correct.

---

## Decision 7: Idempotency of terminal push+PR on resume (FR-009)

**Decision**: `_session_pr` is already idempotent — it checks for an existing
OPEN/MERGED PR via `gh pr view` and returns success (reusing the URL) without
creating a duplicate, and `git push` is a no-op when already in sync. A resumed
run that re-reaches terminal success therefore re-invokes `finalize` safely.
The recorded `PushPRResult.pr_url` is also consulted as a fast-path to skip the
gh round-trip when already populated.

**Rationale**: Resume must not create duplicate PRs (FR-009, US4 AC2). The
existing idempotency in `_session_pr` plus the recorded `PushPRResult` give two
layers of protection.

---

## Decision 8: Reuse of the `commit` skill for message generation

**Decision**: For staging + message crafting, the orchestrator invokes the
installed `commit` skill (Conventional Commits, never `git add -A`/`.`, secret
file warnings). `commit-mode.sh stage-message` / `task-message` provide the
*intent string* (stage/task/feature name + brief) that the orchestrator passes
to the `commit` skill, so message format stays consistent with the rest of the
toolkit and secret-file protection is inherited.

**Rationale**: FR-007 mandates reuse of the `commit` skill. The helper does not
reimplement message crafting; it only supplies the structured intent and the
no-op/branch guards around it.

---

## Summary of resolved unknowns

| # | Question | Resolution |
|---|----------|-----------|
| 1 | new helper vs extend | new `commit-mode.sh`, keep `git-commit` |
| 2 | push vs bash-guard | route via `cstk session pr` (trusted path); raw `git push` stays blocked |
| 3 | prompt location + persistence | after §0 warm-up; `state-rw.sh init --atomic-commit`; default false |
| 4 | trigger points | per-stage before wave close; per-task on pass; push+PR on terminal success only |
| 5 | no-op + branch guard | `git diff --cached --quiet` no-op; guard skips (non-fatal) on default branch |
| 6 | gh missing/unauth | non-fatal via `_session_pr` exit codes; record PushPRResult |
| 7 | resume idempotency | `_session_pr` PR-exists check + recorded pr_url |
| 8 | commit message | reuse installed `commit` skill; helper supplies intent only |

**Zero NEEDS CLARIFICATION remaining.**
