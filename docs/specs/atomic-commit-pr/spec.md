# Feature Specification: Atomic Commit + PR at Pipeline End

**Feature**: `atomic-commit-pr`
**Created**: 2026-06-13
**Status**: Draft

## Overview

Opt-in mode that, when accepted by the operator at pipeline startup, causes each pipeline stage (briefing, constitution, spec, plan, checklist, tasks) and each executed task to receive its own dedicated git commit. At the very end of the pipeline, the session branch is pushed to remote and a pull request is opened automatically. Tasks completed in a single run can be grouped into a single commit.

This mode affects both `agente-00c` and `feature-00c` orchestrators with full parity.

> Decisoes de infraestrutura: N/A (feature stateless, sem scheduling; commits sao operacoes locais POSIX git; PR e via `gh` CLI).

---

## User Scenarios & Testing

### User Story 1 - Opt-in at Pipeline Start (Priority: P1)

When the operator starts `agente-00c` or `feature-00c`, they are asked a single yes/no question: "Enable atomic commits? (each pipeline stage and task gets its own commit; PR opened at end)". If accepted, atomic-commit mode is activated for the entire pipeline run. If declined or skipped, the pipeline behaves exactly as today (no commits during the run).

**Why this priority**: This is the entry point — without the opt-in prompt, nothing else activates. It must be non-disruptive for operators who do not want the feature, preserving the existing default behavior.

**Independent Test**: Start `agente-00c` in a git repo, answer "no" to the atomic-commit prompt. The pipeline runs to completion with zero new commits created by the orchestrator. Start again and answer "yes" — atomic mode activates.

**Acceptance Scenarios**:

1. **Given** a project with `briefing.md` + `constitution.md` ratified, **When** the operator runs `/agente-00c` and answers "yes" to the atomic-commit prompt, **Then** the orchestrator marks `atomic_commit_enabled: true` in its persistent state and proceeds with the pipeline.
2. **Given** the same setup, **When** the operator answers "no" or presses Enter (default), **Then** `atomic_commit_enabled` stays `false` and the pipeline runs exactly as before — zero orchestrator-created commits.
3. **Given** a resumed run (`/agente-00c-resume`), **When** atomic mode was enabled in the original run, **Then** the resumed run inherits `atomic_commit_enabled: true` from state without asking again.
4. **Given** the same feature running under `/feature-00c`, **When** the operator answers "yes", **Then** atomic mode activates with identical behavior (full parity between both orchestrators).

---

### User Story 2 - Per-Stage Atomic Commit (Priority: P1)

When atomic-commit mode is active, each completed pipeline stage (specify, clarify, plan, checklist, create-tasks) results in a dedicated git commit on the session/feature branch before the wave closes. The commit message follows Conventional Commits format and names the stage.

**Why this priority**: This is the core value of the feature — a clean, auditable history where each pipeline artifact has its own commit.

**Independent Test**: Enable atomic mode and run the pipeline through `specify` and `plan`. Inspect `git log`: there should be exactly one commit per completed stage, each with a message like `docs(spec): generate spec.md for feature-foo` or `docs(plan): add plan.md for feature-foo`.

**Acceptance Scenarios**:

1. **Given** atomic mode is active, **When** the `specify` stage completes and generates `spec.md`, **Then** a commit is created containing only the artifacts of that stage, with a message identifying the stage and feature name.
2. **Given** atomic mode is active and a stage generates no new or changed files, **When** the commit is attempted, **Then** no empty commit is created (idempotent — skip if nothing to commit).
3. **Given** atomic mode is active, **When** the pipeline is interrupted mid-stage (before completion), **Then** no partial commit is created for that stage.
4. **Given** atomic mode is NOT active, **When** any stage completes, **Then** no commit is created by the orchestrator (behavior unchanged from today).

---

### User Story 3 - Per-Task Atomic Commit with Optional Grouping (Priority: P2)

When atomic-commit mode is active and the pipeline reaches `execute-task`, each completed task receives its own commit. Tasks completed in a single orchestrator run (wave) can optionally be grouped into a single commit with a range description (e.g., "tasks 1.1.4–1.1.5: implement X and Y").

**Why this priority**: Per-task commits are the highest-granularity value; grouping is a UX convenience. Both behaviors serve the same audit goal but P2 because they depend on P1 being active.

**Independent Test**: Enable atomic mode, run `execute-task` through tasks 2.1 and 2.2 in the same wave. Inspect `git log`: exactly two commits (one per task) OR one grouped commit covering both, depending on whether grouping is in effect.

**Acceptance Scenarios**:

1. **Given** atomic mode is active and task 3.1 completes successfully, **When** the wave closes, **Then** a commit is created for task 3.1 containing only the files changed by that task.
2. **Given** atomic mode is active and tasks 3.1 and 3.2 both complete in the same wave, **When** grouping is enabled, **Then** a single commit is created covering both tasks with a range message (e.g., `feat: tasks 3.1–3.2 implement X`).
3. **Given** a task fails (outcome=fail), **When** the wave closes, **Then** no commit is created for that task (only passing tasks are committed).
4. **Given** atomic mode is NOT active, **When** tasks complete, **Then** no per-task commits are created.

---

### User Story 4 - Push + PR at Pipeline End (Priority: P1)

When atomic-commit mode is active and the pipeline reaches its terminal state (all tasks complete + review-task passes), the session branch is pushed to the remote and a pull request is opened automatically using the existing `cstk session pr` mechanism.

**Why this priority**: Completing the loop from local commits to an auditable PR is the other half of the feature's value. Without this, atomic commits are useful but the collaboration/review path is not closed.

**Independent Test**: Enable atomic mode, run the full pipeline to completion on a session branch. After the last task completes, confirm `git log --remotes` shows the branch pushed, and `gh pr list` shows an open PR for the session branch.

**Acceptance Scenarios**:

1. **Given** atomic mode is active and the pipeline completes successfully (all tasks pass + review-task exits green), **When** the final wave closes, **Then** the session branch is pushed to the remote and a PR is opened against the default branch.
2. **Given** the PR was already opened (resumed run), **When** push+PR is attempted again, **Then** the operation is idempotent — the existing PR is reused, no duplicate PR is created.
3. **Given** the current HEAD is the default branch (not a session/feature branch), **When** atomic mode attempts push+PR, **Then** the operation is blocked with a clear error message and no push occurs.
4. **Given** `gh` is not installed or not authenticated, **When** PR creation is attempted, **Then** a clear, actionable error is reported; the pipeline completes successfully with commits intact (PR creation failure is non-fatal, reported as a warning).
5. **Given** atomic mode is NOT active, **When** the pipeline completes, **Then** no push and no PR are created (behavior unchanged from today).

---

### Edge Cases

- What happens if the session branch has no new commits at push time (e.g., operator ran pipeline with no changes)? Push is skipped; PR creation is also skipped.
- What happens if the remote already has the branch (force-push scenario)? Force-push is NOT used; if the branch already exists remotely with divergent history, the push fails gracefully with a clear error.
- What happens if atomic mode is enabled but the pipeline aborts midway? Commits created up to the abort point remain; no push/PR is triggered on abort (only on successful completion).
- What happens if a stage's commit conflicts with a concurrent change on the remote? The push at end is what triggers conflict detection; per-stage commits are always local.
- What happens on `agente-00c-abort`? The abort command documents that local commits remain intact; push/PR are NOT performed on abort — only on clean completion.

---

## Requirements

### Functional Requirements

- **FR-001**: Both `agente-00c` and `feature-00c` MUST present the atomic-commit opt-in prompt to the operator before the first pipeline stage begins. The prompt MUST default to "no" (opt-out preserves current behavior).
- **FR-002**: The operator's choice MUST be persisted in the orchestrator's `state.json` (`atomic_commit_enabled: bool`) so that resumed runs inherit the mode without re-prompting.
- **FR-003**: When `atomic_commit_enabled = true`, the orchestrator MUST create one git commit per completed pipeline stage, using the existing `commit` skill invocation, immediately after the stage's artifacts are written and before the wave closes.
- **FR-004**: When `atomic_commit_enabled = true`, the orchestrator MUST create one git commit per successfully completed task (outcome=pass) during `execute-task`, or a grouped commit for tasks completed in the same wave when grouping is in effect.
- **FR-005**: Commits MUST be created only on a dedicated session or feature branch. The orchestrator MUST check that HEAD is not the default branch before every commit attempt; if it is, the commit MUST be skipped and a warning logged.
- **FR-006**: If a stage or task generates no file changes (nothing to commit), the commit step MUST be a no-op (no empty commits).
- **FR-007**: Commit messages MUST follow Conventional Commits format and include the pipeline stage name, feature/project name, and a brief description. The orchestrator MUST reuse the `commit` skill for message generation and staging.
- **FR-008**: When `atomic_commit_enabled = true` and the pipeline reaches terminal success, the orchestrator MUST push the session branch to the remote and open a PR via `cstk session pr`.
- **FR-009**: The push+PR step MUST be idempotent: if the branch is already pushed and a PR already exists, the step succeeds without creating a duplicate.
- **FR-010**: If `gh` is unavailable or unauthenticated at PR-creation time, the orchestrator MUST log a clear warning and continue (pipeline completion is not blocked by PR creation failure).
- **FR-011**: The push+PR step MUST NOT execute on pipeline abort, on partial completion, or when `atomic_commit_enabled = false`.
- **FR-012**: The existing prohibition on `git push` in the orchestrator documentation MUST be updated: push is now permitted exclusively in atomic-commit mode, only at pipeline terminal success, and only on a non-default branch.
- **FR-013**: Both orchestrators (`agente-00c` and `feature-00c`) MUST implement this feature with full behavioral parity — identical prompt, state field, commit logic, and push+PR logic.
- **FR-014**: All new shell logic (prompt, commit trigger, push guard) MUST be POSIX sh compliant (Principle II of constitution).
- **FR-015**: A test MUST be added covering: (a) opt-in prompt behavior, (b) per-stage commit creation, (c) branch-default guard, (d) idempotent push+PR.

### Key Entities

- **AtomicCommitConfig**: The `atomic_commit_enabled` boolean field added to `state.json` for both orchestrators. Persisted at opt-in time; read by every stage and task execution.
- **StagedCommit**: A git commit created by the orchestrator after a pipeline stage or task completes. Identified by stage/task name and wave ID in the commit message.
- **PushPRResult**: The outcome of the terminal push+PR step — branch pushed, PR URL, or skip/error reason. Recorded in state for auditability.

---

## Success Criteria

### Measurable Outcomes

- **SC-001**: Operators who opt in to atomic-commit mode have a complete, stage-by-stage git history after a full pipeline run — every completed stage and task corresponds to exactly one commit (or one grouped commit for multi-task waves).
- **SC-002**: Operators who do not opt in (or skip the prompt) observe zero changes in pipeline behavior — no new commits, no push, no PR.
- **SC-003**: The push+PR step at pipeline end succeeds in under 30 seconds on a project with under 50 files changed across all stages.
- **SC-004**: The branch-default guard prevents any push or commit to the default branch in 100% of cases where HEAD is on the default branch.
- **SC-005**: The implementation introduces zero regressions to the existing `agente-00c` and `feature-00c` test suites.
- **SC-006**: The opt-in prompt adds no observable latency to pipeline startup when the operator declines (default path unchanged).

---

## Clarifications

> No `[NEEDS CLARIFICATION]` items — all critical design decisions were pre-ratified by the operator:
> 1. Scope: both orchestrators, full parity.
> 2. Push semantics: local commits per wave; push+PR only at terminal success on session branch.
> 3. Reuse existing `commit` skill and `cstk session pr`; no new agent/subagent.
> 4. Branch guard: refuse commit/push on default branch.
