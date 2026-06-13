# Quickstart / Test Scenarios: atomic-commit-pr

**Feature**: `atomic-commit-pr` | **Date**: 2026-06-13

Critical flows with explicit expected outcomes. Each scenario maps to a user
story and to assertions in `tests/test_commit-mode.sh` (helper) and the
existing `tests/test_state-ondas.sh` / `tests/cstk/test_session.sh`.

This is a single-layer feature (POSIX shell + git/gh CLI). N/A for backend↔
frontend roundtrip — see plan.md §Convencoes de Borda.

---

## Scenario 1: Opt-out preserves current behavior (US1, SC-002)

1. Start `/agente-00c` (or `/feature-00c`) on a session branch.
2. At the opt-in prompt "Enable atomic commits? [s/N]", press Enter (default).
3. Run the pipeline through `specify` and `plan`.

- **Expected**: `state.json` has `.atomic_commit_enabled == false`. `git log`
  shows ZERO commits created by the orchestrator. No push, no PR. Behavior is
  byte-for-byte identical to today.

---

## Scenario 2: Opt-in activates and persists (US1 AC1/AC3)

1. Start `/feature-00c`, answer "s" (yes) at the prompt.
2. Inspect `state.json`.
3. Crash/interrupt, then `/feature-00c-resume`.

- **Expected**: after step 2, `.atomic_commit_enabled == true`. After step 3,
  the resume reads `true` from state and does NOT re-prompt (FR-002). The
  resumed run proceeds in atomic mode.

---

## Scenario 3: Per-stage commit on session branch (US2 AC1)

1. Enable atomic mode on a session branch (non-default).
2. Let `specify` complete and write `spec.md`.

- **Expected**: exactly one commit on the session branch with a message like
  `docs(spec): generate spec.md for <feature>`, containing only that stage's
  artifacts. `commit-mode.sh guard-branch` returned exit 0 (non-default).

---

## Scenario 4: No empty commit when nothing changed (US2 AC2, FR-006)

1. Atomic mode on. A stage runs but produces no new/changed files.
2. The commit step runs.

- **Expected**: `git diff --cached --quiet` is clean ⇒ no commit created
  (StagedCommit.outcome = `noop-empty`). `git log` unchanged. No `--allow-empty`.

---

## Scenario 5: Default-branch guard blocks commit/push (US4 AC3, SC-004)

1. Atomic mode on, but HEAD is the repository default branch (e.g. `main`).
2. A stage completes and the commit step runs; later, finalize runs.

- **Expected**: `commit-mode.sh guard-branch` returns exit 3 ⇒ the commit is
  SKIPPED with a warning (StagedCommit.outcome = `skipped-default-branch`).
  At finalize, `PushPRResult.status = skipped-default-branch`, no push occurs.
  The pipeline continues (non-fatal). 100% of default-branch cases are
  protected (SC-004).

---

## Scenario 6: Per-task commits with optional grouping (US3 AC1/AC2)

1. Atomic mode on, session branch. `execute-task` runs tasks 3.1 and 3.2 in the
   same wave, both outcome=pass.
2a. Grouping OFF: inspect `git log`.
2b. Grouping ON: inspect `git log`.

- **Expected (2a)**: two commits, `feat: task 3.1 …` and `feat: task 3.2 …`,
  each containing only that task's files.
- **Expected (2b)**: one commit `feat: tasks 3.1-3.2 …` covering both.
- A task with outcome=fail in the wave produces NO commit (US3 AC3).

---

## Scenario 7: Terminal push + PR on success (US4 AC1)

1. Atomic mode on, session branch with new commits.
2. Pipeline reaches terminal success (all tasks pass + review-task green).
3. Finalize runs.

- **Expected**: `cstk session pr <name>` pushes the branch and opens a PR
  against the default branch. `git log --remotes` shows the branch pushed;
  `gh pr list` shows an open PR. `PushPRResult.status = pr-opened`, `pr_url`
  recorded. Completes in < 30s for < 50 changed files (SC-003).

---

## Scenario 8: Idempotent finalize on resume (US4 AC2, FR-009)

1. After Scenario 7, the PR already exists. Resume the run and re-reach
   terminal success; finalize runs again.

- **Expected**: `_session_pr` detects the existing OPEN/MERGED PR and returns
  the existing URL without creating a duplicate. `PushPRResult.status =
  pr-exists`. Exactly one PR exists for the branch.

---

## Scenario 9: gh missing / unauth is non-fatal (US4 AC4, FR-010)

1. Atomic mode on, session branch with commits. `gh` is not installed (or not
   authenticated). Pipeline reaches terminal success; finalize runs.

- **Expected**: finalize records `PushPRResult.status = skipped-gh-missing`
  (or `skipped-gh-unauth`), logs a clear actionable warning, and returns exit
  0. The pipeline COMPLETES successfully; local commits remain intact. PR
  creation failure never blocks completion.

---

## Scenario 10: Abort does not push/PR (Edge Case, FR-011)

1. Atomic mode on, several stage/task commits created. Operator runs
   `/agente-00c-abort` (or `/feature-00c-abort`).

- **Expected**: local commits remain intact. NO push, NO PR. The abort command
  documents this explicitly (`PushPRResult.status = skipped-abort` or simply no
  finalize invocation on the abort path).

---

## Scenario 11: Raw `git push` stays blocked (Constitution carve-out integrity)

1. With atomic mode on, the orchestrator (or any path) constructs a raw
   `git push` Bash string and passes it through `bash-guard.sh check`.

- **Expected**: `bash-guard.sh` still BLOCKS it (`git-push` reason). The ONLY
  permitted push path is `cstk session pr` invoked at terminal success. The
  carve-out is the routed trusted path, not a relaxation of the raw-push guard.
