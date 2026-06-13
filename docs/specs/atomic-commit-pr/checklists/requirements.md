# Requirements Checklist: Atomic Commit + PR at Pipeline End

**Purpose**: Validate the quality, completeness, clarity, and consistency of the
requirements for the `atomic-commit-pr` feature — across functional, security,
and CLI-contract dimensions.
**Created**: 2026-06-13
**Feature**: [spec.md](../spec.md) | [plan.md](../plan.md) | [data-model.md](../data-model.md)
**Domains covered**: requirements, security (push carve-out + branch guard), api (git/gh CLI contracts)

---

## Completeness of Functional Requirements

- [x] CHK001 - Are opt-in prompt requirements defined for BOTH orchestrators (`agente-00c`
  and `feature-00c`) with identical behavior? [Completude, Spec §FR-001/FR-013] {auto}
  > Evidence: FR-001 explicitly lists "Both `agente-00c` and `feature-00c`"; FR-013 mandates
  > "full behavioral parity — identical prompt, state field, commit logic, and push+PR logic".

- [x] CHK002 - Is the default opt-out value (prompt default "no") explicitly specified so
  operators who skip get unchanged behavior? [Completude, Spec §FR-001/SC-002] {auto}
  > Evidence: FR-001 "The prompt MUST default to 'no'"; SC-002 "Operators who do not opt in…
  > observe zero changes in pipeline behavior".

- [x] CHK003 - Is state persistence of the opt-in choice defined for the resume path (no
  re-prompting on resumed runs)? [Completude, Spec §FR-002/US1-AC3] {auto}
  > Evidence: FR-002 "persisted in the orchestrator's `state.json` (`atomic_commit_enabled:
  > bool`) so that resumed runs inherit the mode without re-prompting"; US1 AC3 confirms.

- [x] CHK004 - Are per-stage commit requirements defined for all named pipeline stages
  (specify, clarify, plan, checklist, create-tasks)? [Completude, Spec §FR-003/US2] {auto}
  > Evidence: FR-003 "one git commit per completed pipeline stage"; contracts/commit-mode.md
  > `stage-message` lists all stage→scope mappings (`specify→spec`, `plan→plan`,
  > `clarify→spec`, `checklist→checklist`, `create-tasks→tasks`).

- [x] CHK005 - Is the per-task commit requirement defined including the grouping variant
  (tasks completed in same wave → single ranged commit)? [Completude, Spec §FR-004/US3] {auto}
  > Evidence: FR-004 "one git commit per successfully completed task (outcome=pass)… or a
  > grouped commit for tasks completed in the same wave when grouping is in effect";
  > US3 AC2 and contracts/commit-mode.md `task-message` cover single + range + list forms.

- [x] CHK006 - Are the terminal push+PR requirements defined, including the specific
  triggering condition (terminal success = all tasks pass + review-task green)? [Completude,
  Spec §FR-008/US4-AC1] {auto}
  > Evidence: FR-008 "pipeline reaches terminal success"; US4 AC1 "all tasks complete +
  > review-task passes"; plan.md Constitution Exception §2 "Pipeline reached TERMINAL success".

- [x] CHK007 - Is the "no push/PR on abort or partial completion" requirement explicitly
  stated? [Completude, Spec §FR-011/Edge Cases] {auto}
  > Evidence: FR-011 "MUST NOT execute on pipeline abort, on partial completion, or when
  > `atomic_commit_enabled = false`"; Edge Cases "commits created up to the abort point
  > remain; no push/PR is triggered on abort".

- [x] CHK008 - Is the requirement to update the existing push-prohibition documentation
  (`bash-guard.sh`, orchestrator docs) captured? [Completude, Spec §FR-012] {auto}
  > Evidence: FR-012 explicitly requires updating "The existing prohibition on `git push`";
  > plan.md Project Structure lists `bash-guard.sh` and both orchestrator docs as files touched.

- [x] CHK009 - Is the test coverage requirement specific enough to be actionable (what to
  cover)? [Completude, Spec §FR-015] {auto}
  > Evidence: FR-015 enumerates four named test areas: "(a) opt-in prompt behavior, (b)
  > per-stage commit creation, (c) branch-default guard, (d) idempotent push+PR". The plan
  > names the test file `tests/test_commit-mode.sh` and maps each to INV-1..8.

---

## Clarity of Requirements

- [x] CHK010 - Is "completed pipeline stage" unambiguously defined (what counts as
  completion — artifact written + wave closed, not mid-stage)? [Clareza, Spec §FR-003/US2-AC3] {auto}
  > Evidence: US2 AC3 "if the pipeline is interrupted mid-stage (before completion), then
  > no partial commit is created" — completion = stage artifact written before wave closes,
  > not mid-stage. Contracts also place the commit "immediately after the stage's artifacts
  > are written and before the wave closes".

- [x] CHK011 - Is "grouping" for per-task commits defined precisely (same wave = same run,
  not manual selection)? [Clareza, Spec §FR-004/US3-AC2] {auto}
  > Evidence: FR-004 "tasks completed in the same wave"; US3 "Tasks completed in a single
  > orchestrator run (wave) can optionally be grouped". "Wave" is already a precisely defined
  > concept in the cstk runtime. Clear.

- [x] CHK012 - Is "terminal success" quantified with both conditions (tasks pass AND
  review-task green, not either/or)? [Clareza, Spec §US4-AC1/FR-008] {auto}
  > Evidence: US4 AC1 "all tasks complete + review-task passes" — dual condition, explicitly
  > conjunctive. Spec edge case "What happens if atomic mode is enabled but the pipeline
  > aborts midway?" reinforces the terminal-only trigger.

- [x] CHK013 - Is the "idempotent push+PR" behavior defined precisely (what "idempotent"
  means — existing PR reused, no duplicate)? [Clareza, Spec §FR-009/US4-AC2] {auto}
  > Evidence: FR-009 "if the branch is already pushed and a PR already exists, the step
  > succeeds without creating a duplicate"; data-model.md `PushPRResult.status=pr-exists`
  > with mapping to `_session_pr` exit; contracts/commit-mode.md `finalize` step 3 documents
  > delegation to idempotent `_session_pr`.

- [x] CHK014 - Is "no empty commits" behavior clearly tied to a verifiable condition
  (nothing staged = no commit, not "no changes in general")? [Clareza, Spec §FR-006/US2-AC2] {auto}
  > Evidence: FR-006 "If a stage or task generates no file changes (nothing to commit),
  > the commit step MUST be a no-op"; plan.md D5 specifies `git diff --cached --quiet`
  > as the mechanism. Clear and verifiable.

- [x] CHK015 - Is "non-default branch" clearly defined (default branch resolved dynamically,
  not hardcoded to "main")? [Clareza, Spec §FR-005/SC-004] {auto}
  > Evidence: contracts/commit-mode.md `guard-branch` "Resolves default branch using the
  > same logic as `cli/lib/session.sh::_session_default_branch` (remote HEAD ⇒ fallback
  > `main`/`master`)". Dynamic resolution documented; SC-004 "100% of cases".

- [x] CHK016 - Is the "non-fatal" contract for `gh` failures stated with explicit expected
  behavior (pipeline still completes, commits intact)? [Clareza, Spec §FR-010/US4-AC4] {auto}
  > Evidence: FR-010 "log a clear warning and continue (pipeline completion is not blocked
  > by PR creation failure)"; US4 AC4 "pipeline completes successfully with commits intact
  > (PR creation failure is non-fatal, reported as a warning)"; contracts `finalize` step 5.

- [ ] CHK017 - Is "grouping is in effect" (FR-004) defined — who controls whether grouping
  is on or off, and what is the default? [Clareza, Spec §FR-004] [Gap] {humano}
  > FR-004 says "when grouping is in effect" without specifying how it is enabled or what the
  > default is. US3 says "can optionally be grouped" but does not define the toggle. Is
  > grouping always on when multiple tasks complete in the same wave? Is it a separate
  > opt-in flag? This needs a decision before `create-tasks` to know whether a state field
  > or parameter is required.

---

## Consistency of Requirements

- [x] CHK018 - Is there a conflict between FR-005 ("commit MUST be skipped" on default
  branch) and FR-008 ("MUST push" at terminal success) — do both guards apply to push? [Consistencia,
  Spec §FR-005/FR-008] {auto}
  > Evidence: No conflict. FR-005 guards the per-stage/per-task local commits. FR-008 push
  > is also gated by `guard-branch` inside `finalize` (contracts step 2). Both guards share
  > the same `guard-branch` subcommand. Consistent.

- [x] CHK019 - Do the spec's edge cases align with the data-model's `PushPRResult.status`
  enum (every edge case maps to a status value)? [Consistencia, Spec §Edge Cases / data-model.md] {auto}
  > Evidence: "session branch has no new commits" → `skipped-no-commits` ✓; "force-push
  > scenario" → not needed (plain push fails gracefully, maps to `error`) ✓; "abort midway"
  > → `skipped-abort` ✓; "gh unavailable" → `skipped-gh-missing` / `skipped-gh-unauth` ✓.
  > Full coverage.

- [x] CHK020 - Is the "reuse existing `commit` skill" requirement consistent with FR-007's
  requirement to follow Conventional Commits format — does the `commit` skill enforce it? [Consistencia,
  Spec §FR-007/plan.md D8] {auto}
  > Evidence: The cstk `commit` skill is documented to produce Conventional Commit messages.
  > `commit-mode.sh stage-message`/`task-message` supply the intent subject; the `commit`
  > skill finalizes staging and message. Consistent — the skill is the single source of
  > format enforcement.

- [x] CHK021 - Is the POSIX sh requirement (FR-014/Constitution Principle II) consistent
  across all named implementation artifacts (`commit-mode.sh`, `state-rw.sh` additions)? [Consistencia,
  Spec §FR-014/plan.md §Constitution Check] {auto}
  > Evidence: Constitution Check II "PASS — `commit-mode.sh` is POSIX sh; `jq`/`git`/`gh`
  > are OPTIONAL with documented graceful fallback". Consistent across all artifacts listed.

- [x] CHK022 - Is the "bash-guard.sh blocks raw `git push`" requirement consistent with the
  carve-out via `cstk session pr`? Are both invariants stated without contradiction? [Consistencia,
  Spec §FR-005/plan.md §Constitution Exception] {auto}
  > Evidence: plan.md "Raw `git push` strings remain BLOCKED by `bash-guard.sh` (Scenario 11).
  > The push is performed EXCLUSIVELY through the trusted `cstk session pr` path." No regex
  > change to `bash-guard.sh` required (plan.md §bash-guard.sh "doc/help text note only").
  > Consistent — two non-overlapping code paths.

---

## Quality of Acceptance Criteria

- [x] CHK023 - Are acceptance criteria for US1 (opt-in prompt) independently testable
  without depending on later stages completing? [Mensurabilidade, Spec §US1-ACs] {auto}
  > Evidence: US1 AC1 tests only "orchestrator marks `atomic_commit_enabled: true` in
  > persistent state"; AC2 tests "zero orchestrator-created commits" independently. Each AC
  > is self-contained and verifiable.

- [x] CHK024 - Is SC-001 ("exactly one commit per stage/task") objectively measurable
  with `git log`? [Mensurabilidade, Spec §SC-001] {auto}
  > Evidence: US2 Independent Test "Inspect `git log`: there should be exactly one commit
  > per completed stage". Counting commits in `git log` is a standard, objective assertion.

- [x] CHK025 - Is SC-003 (push+PR < 30s for < 50 changed files) measurable and realistic
  given the delegation to `cstk session pr`? [Mensurabilidade, Spec §SC-003] {auto}
  > Evidence: SC-003 is stated as a wall-clock bound on the terminal step. The mechanism
  > is a `git push` + `gh pr create` — both are network I/O operations whose timing depends
  > on remote latency. The bound is measurable (wall-clock timer around `finalize`), and
  > 30s is a conservative target for a single-branch push of < 50 files. Reasonable.

- [x] CHK026 - Is SC-004 (100% default-branch protection) falsifiable — can a test assert
  it deterministically? [Mensurabilidade, Spec §SC-004] {auto}
  > Evidence: contracts/commit-mode.md INV-2 "`guard-branch` on default branch ⇒ exit 3,
  > no commit" — this is a deterministic unit test assertion, not probabilistic. SC-004 is
  > falsifiable via the test.

- [x] CHK027 - Are SC-005 (zero regressions) and SC-006 (no added latency on default path)
  falsifiable with the existing `tests/run.sh` harness? [Mensurabilidade, Spec §SC-005/SC-006] {auto}
  > Evidence: SC-005 is gated by `tests/run.sh` (existing suite). SC-006 is verifiable
  > because the default path (opt-out) adds zero code branches — `is-enabled` returns `false`
  > on absent field, the entire commit logic is skipped. Measurable as "no new code
  > executed on the default path".

---

## Scenario Coverage

- [x] CHK028 - Is the "resume mid-wave after per-stage commit" scenario covered? What
  happens if the commit succeeded but the wave did not close before an abort? [Cobertura, Spec §US1-AC3/Edge Cases] {auto}
  > Evidence: Edge Cases "commits created up to the abort point remain"; US1 AC3 "resumed
  > run inherits `atomic_commit_enabled: true` from state". The per-stage commit is
  > idempotent if the stage already produced its commit — FR-006 (no empty commits) prevents
  > re-committing an already-committed stage. Covered by construction.

- [x] CHK029 - Is the "execute-task stage with zero passing tasks" scenario covered
  (wave runs but all tasks fail — no per-task commit)? [Cobertura, Spec §US3-AC3] {auto}
  > Evidence: US3 AC3 "Given a task fails (outcome=fail), no commit is created for that
  > task". Zero passing tasks in a wave = zero commits for that wave. Explicitly stated.

- [x] CHK030 - Is the scenario "pipeline runs multiple execute-task waves" covered —
  does each wave get its own commits independently? [Cobertura, Spec §FR-004] {auto}
  > Evidence: FR-004 "one git commit per successfully completed task (outcome=pass) during
  > execute-task". The trigger is per-task/per-wave independently; there is no cross-wave
  > grouping constraint. Each wave is self-contained by the wave-loop architecture.

- [x] CHK031 - Is the "PR already merged (not just open)" idempotency scenario covered?
  data-model.md mentions `pr-exists` for "OPEN/MERGED" — is this intentional? [Cobertura,
  data-model.md §PushPRResult] {auto}
  > Evidence: data-model.md `pr-exists: "idempotent reuse of an existing OPEN/MERGED PR"`.
  > The `_session_pr` already handles this case. Including MERGED is intentional: if a PR
  > was merged and the operator re-runs, the status is `pr-exists` (not `pr-opened`), which
  > is correct — no duplicate PR. Covered.

- [ ] CHK032 - Is the scenario "atomic mode enabled + `cstk session` not in use (operator
  runs pipeline directly on a non-session branch)" covered? [Cobertura, Spec §FR-005] [Gap] {humano}
  > FR-005 and `guard-branch` check that HEAD is not the default branch, but do not require
  > that the branch was created by `cstk session`. An operator might be on any feature branch.
  > Is `finalize` expected to work on any non-default branch, or only on branches created
  > via `cstk session start`? The spec says "session branch" in several places but FR-008
  > delegates to `cstk session pr` which requires a session name. Needs clarification.

---

## Edge Case Coverage

- [x] CHK033 - Is the "nothing to commit at push time (zero new commits vs default)" edge
  case handled at the push layer, not just at the per-stage commit layer? [Edge Cases,
  Spec §Edge Cases/data-model.md] {auto}
  > Evidence: Spec Edge Cases "If the session branch has no new commits at push time…
  > Push is skipped; PR creation is also skipped." data-model.md `PushPRResult.status=
  > skipped-no-commits` via `CSTK_SESSION_EXIT_NO_COMMITS` mapping. Covered at both layers.

- [x] CHK034 - Is the "force-push scenario" explicitly rejected with stated behavior
  (fail gracefully, not silently succeed)? [Edge Cases, Spec §Edge Cases] {auto}
  > Evidence: Spec Edge Cases "Force-push is NOT used; if the branch already exists
  > remotely with divergent history, the push fails gracefully with a clear error." Status
  > maps to `error` (non-fatal; commits intact). Clear rejection documented.

- [x] CHK035 - Is the "stage generates artifact but git has no changes" edge case distinct
  from "stage generates no artifact" — both result in no-commit? [Edge Cases, Spec §FR-006] {auto}
  > Evidence: FR-006 "If a stage or task generates no file changes (nothing to commit),
  > the commit step MUST be a no-op." The check is at the git layer (`git diff --cached
  > --quiet`), so whether the stage ran or not, if nothing is staged, no commit occurs.
  > Both cases handled by the same mechanism. Clear.

- [x] CHK036 - Is the "atomic mode enabled but `git` is not installed" edge case handled
  (or explicitly out of scope)? [Edge Cases, contracts/commit-mode.md] {auto}
  > Evidence: contracts/commit-mode.md `guard-branch` "Exit 1 — not a git repo / git
  > missing (caller skips, logs)". The `git` optional-dep fallback is consistent with
  > constitution amendment 1.1.0. Handled — graceful no-op + log.

---

## Non-Functional Requirements

- [x] CHK037 - Is the security constraint (push only through trusted `cstk session pr`,
  never raw `git push`) enforced at the architectural level (not just convention)? [Seguranca,
  plan.md §Constitution Exception] {auto}
  > Evidence: plan.md "Raw `git push` strings remain BLOCKED by `bash-guard.sh`
  > (Scenario 11)… The push is performed EXCLUSIVELY through the trusted `cstk session pr`
  > path." The guard is enforced at runtime (bash-guard.sh) independent of the orchestrator
  > code following convention. Architectural enforcement confirmed.

- [x] CHK038 - Is the "no telemetry / no author endpoint" non-functional constraint
  explicitly documented so future contributors do not add analytics to `finalize`? [Seguranca,
  plan.md §Constitution Check IV] {auto}
  > Evidence: plan.md Constitution Check IV "No telemetry. The only network action is
  > `git push` + `gh pr create` to the user's OWN remote, opt-in, terminal-only." Documented
  > as a PASS on an explicit MUST. Future contributors see this in the plan Constitution Check.

- [x] CHK039 - Is the POSIX sh constraint documented in a location where it enforces
  reviewers to check all new shell code, not just the stated helper? [Seguranca, Spec §FR-014] {auto}
  > Evidence: FR-014 "All new shell logic (prompt, commit trigger, push guard) MUST be
  > POSIX sh compliant"; Constitution Check II covers all listed artifacts. The test
  > `test_commit-mode.sh` is the executable gate.

- [x] CHK040 - Is retro-compatibility (pre-feature `state.json` with absent
  `atomic_commit_enabled`) explicitly specified as "treated as false, not an error"? [Nao-Funcional,
  data-model.md §Retro-compatibility] {auto}
  > Evidence: data-model.md "`.atomic_commit_enabled` absent ⇒ `false` ⇒ today's behavior
  > (no commits, no push, no PR). SC-002 / SC-005 hold by construction." contracts
  > `is-enabled` "absent ⇒ false". Clear retro-compatibility guarantee.

---

## Dependencies and Assumptions

- [x] CHK041 - Is the dependency on `cli/lib/session.sh::_session_pr` documented as a
  REUSE (not re-implement) constraint, and is the exit-code contract pinned? [Dependencias,
  data-model.md §Mapping] {auto}
  > Evidence: data-model.md §Mapping table pins all `_session_pr` exit codes to
  > `PushPRResult.status` values; contracts `finalize` §Reused contracts documents
  > "`push + PR (idempotent, default-branch resolve, gh status) — cli/lib/session.sh::_session_pr`".
  > REUSE constraint is explicit; contract is pinned.

- [x] CHK042 - Is the assumption that `cstk session pr` is idempotent (PR-exists reuse +
  push no-op when in sync) verified against the existing implementation? [Suposicao,
  plan.md/data-model.md] {auto}
  > Evidence: plan.md "which is idempotent (PR-exists reuse, push no-op when in sync)";
  > the existing `tests/cstk/test_session.sh` covers `_session_pr`. The assumption is backed
  > by an existing test suite, not just documentation.

- [x] CHK043 - Is the dependency on the installed `commit` skill (for message + staging)
  documented with a graceful fallback if the skill is absent? [Dependencias, Spec §FR-007] {auto}
  > Evidence: plan.md "The technical approach reuses existing, battle-tested primitives —
  > the installed `commit` skill for message/staging." The `commit` skill is part of the
  > cstk toolkit and always present after `cstk install`. The constitution amendment 1.1.0
  > cumulative carve-out covers `jq`/`git`/`gh`; the `commit` skill is an internal
  > dependency, not an external dep. No fallback documented for absent `commit` skill.
  > [Gap] — If `commit` skill is absent (e.g., stale install), no fallback is specified.
  > Likely low-risk (skill is bundled), but the assumption should be documented explicitly.

- [x] CHK044 - Is the assumption that `state-rw.sh sha256-update` runs after every write
  (ensuring hash verification catches tampering) carried through to the new
  `set-enabled`/`finalize` writes? [Suposicao, contracts/commit-mode.md §INV-8] {auto}
  > Evidence: contracts INV-8 "every write goes through `state-rw.sh set` (state-history +
  > sha256), never `echo`/`cp` into state.json." The audited path includes sha256 update by
  > construction. Verified.

---

## Ambiguities and Conflicts

- [ ] CHK045 - CHK017 above flags "grouping is in effect" as undefined. Is the intended
  default "always group tasks in the same wave" (automatic, no flag needed)?
  [Ambiguity, Spec §FR-004] {humano}
  > This is the most likely interpretation (same-wave = same group by default), but FR-004
  > says "when grouping is in effect" as a conditional, implying a toggle. Needs a decision:
  > (a) always group, or (b) a separate `group_tasks` flag.

- [ ] CHK046 - CHK032 above flags that `commit-mode.sh finalize` calls `cstk session pr
  "$NAME"` but the session NAME must come from somewhere. Where is the session name stored
  and how does the orchestrator know it at terminal finalize time? [Ambiguity, contracts §finalize] {humano}
  > The `finalize` subcommand signature requires `--session NAME`. For `feature-00c` the
  > session name is the short_name; for `agente-00c` it is the project name. Neither
  > `state.json` nor `data-model.md` documents where the session name is stored or how
  > `finalize` retrieves it. This must be resolved in `create-tasks`.

- [ ] CHK047 - FR-003 says the orchestrator MUST use "the existing `commit` skill
  invocation" but the commit skill is interactive (it prompts for confirmation if staged
  files look suspicious). Is the commit skill expected to run non-interactively in atomic
  mode? [Ambiguity, Spec §FR-003/FR-007] {humano}
  > In an automated pipeline, a human confirmation prompt inside the `commit` skill would
  > stall the orchestrator. The spec says "reuse the `commit` skill" but does not specify
  > whether a `--no-prompt` / `--batch` flag is needed. If the skill is always non-blocking,
  > this is a non-issue; but if it prompts, atomic mode would require either a new flag or
  > a different invocation path.

---

## Notes

- Items `{auto}` are resolved by the agent with cited evidence (`[x]`), or marked `[Gap]`/`[Ambiguity]`/`[Conflict]`.
- Items `{humano}` remain `[ ]` awaiting a product-owner decision.
- Gaps/ambiguities are consolidated below for routing to `create-tasks`.

---

## Gap / Ambiguity Consolidation (for `create-tasks` consumption)

| Item | Type | Action |
|------|------|--------|
| CHK017 | [Gap] | Define default grouping behavior: always-on per-wave vs. separate flag. Produce a decision in `clarify` or directly as a task "specify grouping default in FR-004". |
| CHK032 | [Gap] | Clarify whether `finalize` works on any non-default branch or only on `cstk session`-created branches. Update FR-008 / contracts `finalize` accordingly. |
| CHK043 | [Gap] | Document the fallback or explicit assumption for absent `commit` skill. Add a note to `commit-mode.sh` contract §Dependencies. |
| CHK045 | [Ambiguity] | FR-004 "when grouping is in effect" — decide if grouping is always-on or a flag. If a flag, add it to the data model and `state-rw.sh init`. |
| CHK046 | [Ambiguity] | `finalize --session NAME` source: document where session name is read from state.json (or passed by the orchestrator) for both `agente-00c` and `feature-00c`. |
| CHK047 | [Ambiguity] | `commit` skill interactivity in pipeline context: confirm the skill runs non-interactively or specify the flag/invocation path needed for atomic mode. |

**Summary**: 6 open items (3 `{humano}` decisions, 3 `[Gap]`/`[Ambiguity]` for `create-tasks`).
These are targeted, implementation-level ambiguities — the core feature design is sound
and the gaps do not block `create-tasks` phase (they become explicit tasks within it).
