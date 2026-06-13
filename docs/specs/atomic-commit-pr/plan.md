# Implementation Plan: Atomic Commit + PR at Pipeline End

**Feature**: `atomic-commit-pr` | **Date**: 2026-06-13 | **Spec**: [spec.md](./spec.md)

## Summary

Add an OPT-IN "atomic commit" mode to both the `agente-00c` and `feature-00c`
orchestrators. When the operator opts in at pipeline start (single yes/no
prompt, default "no"), each completed pipeline stage and each passing task gets
its own git commit on the session branch, and at terminal success the branch is
pushed and a PR is opened. When the operator declines (the default), pipeline
behavior is byte-for-byte unchanged. The technical approach reuses existing,
battle-tested primitives — the installed `commit` skill for message/staging and
`cstk session pr` (`cli/lib/session.sh::_session_pr`) for the idempotent
push+PR — behind one new POSIX helper `commit-mode.sh` that owns the opt-in
surface (mode detection, message intent, default-branch guard, terminal
finalize). The persisted state is a single boolean `.atomic_commit_enabled`
plus a recorded `.push_pr_result`.

## Technical Context

**Language/Version**: POSIX sh (Principle II NON-NEGOTIABLE — no bashisms)
**Primary Dependencies**: none mandatory. Optional, with graceful fallback
(constitution amendment 1.1.0): `jq` (state read/write), `git` (commit/branch),
`gh` (via `cstk session pr`, terminal PR only).
**Storage**: orchestrator `state.json` (canonical, hash-verified). No DB, no new
files. Additive fields only.
**Testing**: `tests/run.sh` harness; `tests/test_commit-mode.sh` (new helper) +
existing `tests/test_state-ondas.sh`, `tests/cstk/test_session.sh`. `--check-
coverage` gates any new `.sh`.
**Target Platform**: developer macOS/Linux shells; the cstk toolkit itself.
**Project Type**: meta-feature — modifies the toolkit's own orchestrators (CLI
+ markdown agent docs + POSIX runtime helpers).
**Performance Goals**: terminal push+PR < 30s for < 50 changed files (SC-003);
zero added latency on the opt-out (default) path (SC-006).
**Constraints**: zero regressions to existing suites (SC-005); 100% default-
branch protection (SC-004); retro-compatible with pre-feature state.json.
**Scale/Scope**: ~1 new helper, ~6 command/agent docs touched, 1 new state
field + 1 recorded result, 1 new test file.

## Constitution Check

*GATE: passed before Phase 0. Re-checked after Phase 1 (§Re-check below).*

| Principio | Status | Notas |
|-----------|--------|-------|
| I. SDD aplica-se recursivamente (MUST) | PASS | spec→plan→tasks chain followed; this plan traces every FR to a design decision. |
| II. Scripts POSIX sh puros, zero dep obrigatoria (MUST) | PASS | `commit-mode.sh` is POSIX sh; `jq`/`git`/`gh` are OPTIONAL with documented graceful fallback (no-op or recorded skip, never abort) — satisfies the amendment 1.1.0 cumulative carve-out. New test `test_commit-mode.sh` covers the fallback paths. |
| III. Formato canonico de skill (MUST) | N/A | No new skill; reuses installed `commit`. Helper follows runtime-script conventions (subcommand dispatch, `--state-dir`, `_log.sh`). |
| IV. Zero coleta remota de uso/dados (MUST) | PASS | No telemetry. The only network action is `git push` + `gh pr create` to the user's OWN remote, opt-in, terminal-only — this is the user's repo, not an author endpoint. Not a Principle IV concern. |
| V. Profundidade acima de adocao (SHOULD) | PASS w/ exception | See §Constitution Exception. The blanket "NUNCA git push" (agente-00c spec FR-028, enforced by `bash-guard.sh`) was framed under Principle V's "blast radius confinado"; this feature introduces a NARROW, opt-in, terminal-only carve-out. Principle V is a SHOULD, not a MUST — the carve-out is allowed with a documented exception. |

**No FAIL on any MUST.** Gate passes.

## Constitution Exception (Principle V — Blast Radius / "NUNCA git push")

The original `agente-00c` spec (FR-028) prohibited `git push` unconditionally,
enforced by `bash-guard.sh` (lines 84-86, block reason `git-push`) and stated as
"NUNCA git push — Principio V" across the orchestrator/command docs. This plan
introduces a bounded carve-out.

**Scope of the exception (all conditions CUMULATIVE — push happens only when ALL hold):**

1. `atomic_commit_enabled == true` (explicit operator opt-in; default is no push).
2. Pipeline reached TERMINAL success (all tasks pass + review-task green) — NOT
   on abort, NOT on partial completion.
3. HEAD is a NON-default (session/feature) branch — the default-branch guard
   blocks 100% of default-branch cases (SC-004).
4. The push is performed EXCLUSIVELY through the trusted `cstk session pr`
   path (`_session_pr`), which is idempotent and resolves the default branch.
   Raw `git push` strings remain BLOCKED by `bash-guard.sh` (Scenario 11).

**Why allowed**: Principle V is a SHOULD favoring depth/reduced-rework over
adoption; it does not forbid the operator from pushing their own work to their
own remote. The feature reduces rework (auditable history + ready PR) precisely
in real projects where the toolkit is applied — squarely the intent of
Principle V. No MUST (I/II/IV) is touched: no telemetry, no author endpoint, no
non-POSIX shell, SDD chain intact.

**Sunset / review**: The exception is scoped to the conditions above. If a
future change wants push outside these four conditions, it requires a fresh
Constitution Exception (or amendment). The carve-out is auditable as a single
named code path (`commit-mode.sh finalize` → `cstk session pr`); a reviewer can
verify the four conditions by reading that one function.

## Project Structure

### Documentation (this feature)

```
docs/specs/atomic-commit-pr/
├── spec.md
├── plan.md          # This file
├── research.md      # Phase 0 output
├── data-model.md    # Phase 1 output
├── quickstart.md    # Phase 1 output
└── contracts/
    └── commit-mode.md   # Phase 1 output — new helper contract
```

### Source Code (repository root) — files touched

```
global/
├── agents/
│   ├── agente-00c-orchestrator.md          # wave loop: per-stage/per-task commit hook
│   │                                       #   (~lines 1388-1391 local-commit point;
│   │                                       #    helpers table ~line 117); terminal finalize
│   └── agente-00c-feature-orchestrator.md  # PARITY: same hooks, steps 7→8 boundary,
│                                           #   terminal finalize before final report
├── commands/
│   ├── agente-00c.md                       # opt-in prompt after §0 warm-up (~line 32);
│   │                                       #   wire --atomic-commit into init
│   ├── feature-00c.md                      # opt-in prompt after §0 warm-up (~line 33);
│   │                                       #   wire --atomic-commit into init (~lines 183-192)
│   ├── agente-00c-resume.md                # READ .atomic_commit_enabled; never re-prompt
│   ├── feature-00c-resume.md               # PARITY: read mode from state; never re-prompt
│   ├── agente-00c-abort.md                 # update "NUNCA git push" text (~lines 139-146):
│   │                                       #   commits intact, no push/PR on abort
│   └── feature-00c-abort.md                # PARITY (~line 122)
└── skills/agente-00c-runtime/scripts/
    ├── commit-mode.sh                       # NEW helper (subcommands: is-enabled,
    │                                        #   set-enabled, guard-branch, stage-message,
    │                                        #   task-message, finalize)
    ├── state-rw.sh                          # add --atomic-commit flag to init
    │                                        #   (~lines 297-455 modo-feature)
    ├── state-ondas.sh                       # git-commit subcommand UNCHANGED (default path)
    ├── bash-guard.sh                        # doc/help text note (lines 314-315):
    │                                        #   raw git push stays blocked; carve-out via
    │                                        #   cstk session pr (NO regex change required)
    └── state-validate.sh                    # accept new bool .atomic_commit_enabled +
                                             #   optional .push_pr_result

cli/lib/
└── session.sh                               # _session_pr REUSED as-is (no change)

tests/
├── test_commit-mode.sh                      # NEW — covers FR-015 (a/b/c/d) + INV-1..8
├── test_state-ondas.sh                      # extend if git-commit path touched (it isn't)
├── test_state-rw.sh                         # extend: init --atomic-commit default false
└── cstk/test_session.sh                     # _session_pr already covered; no change

global/skills/agente-00c-runtime/references/  (none)
```

**Structure Decision**: One new isolated POSIX helper (`commit-mode.sh`) owns
the opt-in surface; the existing `state-ondas.sh git-commit` is left untouched
to preserve the default-safe local-commit path used by abort/init. The
push+PR is delegated to the existing trusted `cstk session pr`. This minimizes
new surface, maximizes reuse, and keeps every behavioral change behind a single
testable unit. Both orchestrators integrate the helper at identical hook points
for full parity (FR-013).

## Convencoes de Borda

**N/A — single-layer.** This feature is pure POSIX shell + CLI (git/gh)
operating on local state and a git remote. There is no backend↔frontend
boundary, no DB↔DTO mapping, no message-broker contract. The only "contract"
is the internal `commit-mode.sh` subcommand interface (documented in
`contracts/commit-mode.md`) and the reused `_session_pr` exit-code mapping
(documented in `data-model.md`). No snake_case/camelCase concern applies.

## Requirement → Design traceability

| FR | Design element |
|----|----------------|
| FR-001 prompt both orchestrators, default no | opt-in prompt after §0 warm-up in `agente-00c.md` + `feature-00c.md`; default "no" (research D3) |
| FR-002 persist + resume no re-prompt | `.atomic_commit_enabled` via `state-rw.sh init --atomic-commit`; resume reads it (D3) |
| FR-003 per-stage commit | wave-loop hook before wave close; `commit-mode.sh stage-message` + `commit` skill (D4, D8) |
| FR-004 per-task commit + grouping | `execute-task` on outcome=pass; `task-message` single/range (D4) |
| FR-005 branch-default guard | `commit-mode.sh guard-branch` exit 3 ⇒ skip+warn (D5) |
| FR-006 no empty commits | `git diff --cached --quiet` no-op (D5) |
| FR-007 Conventional Commits + reuse `commit` skill | message intent from helper, finalized by `commit` skill (D8) |
| FR-008 terminal push+PR | `commit-mode.sh finalize` → `cstk session pr` (D2, D4) |
| FR-009 idempotent push+PR | `_session_pr` PR-exists reuse + recorded `pr_url` (D7) |
| FR-010 gh missing/unauth non-fatal | `_session_pr` exit-code mapping → recorded skip, exit 0 (D6) |
| FR-011 no push on abort/partial/disabled | finalize guards: disabled/abort/non-terminal ⇒ skip (D4, D6) |
| FR-012 update push-prohibition docs | conditioned text in abort/orchestrator docs; `bash-guard.sh` help note (D2) |
| FR-013 parity | identical hooks in both orchestrators (Project Structure) |
| FR-014 POSIX sh | `commit-mode.sh` POSIX; Constitution Check II PASS |
| FR-015 tests | `test_commit-mode.sh` covers (a) prompt persist, (b) per-stage commit, (c) branch guard, (d) idempotent push+PR |

## Re-check (post Phase 1)

Design introduced exactly one new script and additive state fields — no extra
service, no extra layer, no non-POSIX dependency. The only constitution tension
(Principle V "NUNCA push") is a SHOULD, handled by the documented, bounded
Constitution Exception above. All MUSTs (I/II/IV) remain PASS. No Complexity
Tracking entries required.

## Complexity Tracking

> No constitution MUST violations. The single SHOULD carve-out is documented in
> §Constitution Exception (not a complexity violation — an intentional, bounded
> policy exception with cumulative conditions and a review/sunset clause).

| Violacao | Por Que Necessario | Alternativa Simples Rejeitada Porque |
|----------|-------------------|--------------------------------------|
| (none) | — | — |
