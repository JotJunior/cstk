**English** · [Português (pt-BR)](./sdd-pipeline.pt-BR.md)

# SDD Pipeline (Spec-Driven Development)

> Topic document from the [README](../README.md). Condensed skill catalog in
> the [Global Skills](../README.md#global-skills) section.

The SDD pipeline is the recommended sequence to take an idea from discovery all
the way to implementation. Each skill consumes the previous one's artifacts and
feeds the next.

```text
 ┌──────────────┐
 │  DISCOVERY   │
 └──────┬───────┘
        │
   ① briefing          Discovery interview → docs/briefing.md
        │                Gathers vision, users, scope, constraints and stack.
        │                Asks ONE question at a time (max 10).
        ▼
   ② constitution      Briefing → docs/constitution.md
        │                Defines MUST/SHOULD principles that govern every decision.
        │                Validated against existing artifacts (propagation).
        ▼
 ┌──────────────┐
 │ SPECIFICATION│
 └──────┬───────┘
        │
   ③ specify            Natural description → docs/specs/{feature}/spec.md
        │                Produces prioritized user stories, functional requirements,
        │                acceptance criteria and measurable success criteria.
        │                Focus on WHAT and WHY — never on HOW.
        │                Deterministic gate: every requirement needs >=1 scenario
        │                (requirement-coverage.sh, v5.22.0). Optional
        │                "## Delta Requirements" section declares the delta to apply
        │                to the living-specs corpus at archive time (v5.23.0).
        ▼
   ④ clarify            Spec → Refined spec (in-place)
        │                Scans for ambiguities by taxonomy (10 categories).
        │                Asks max 5 questions with options and a recommendation.
        │                Integrates answers directly into the spec.
        ▼
 ┌──────────────┐
 │   PLANNING   │
 └──────┬───────┘
        │
   ⑤ plan              Spec → docs/specs/{feature}/plan.md + research.md + data-model.md
        │                Researches technologies, defines the data model,
        │                API contracts and test scenarios.
        │                Validates against the constitution (mandatory gate).
        ▼
   ⑥ checklist          Plan + Spec → docs/specs/{feature}/checklists/{domain}.md
        │                "Unit Tests for English" — validates requirement QUALITY,
        │                not the implementation. Domains: ux, api, security, performance.
        │                Items with owner {auto}/{humano}; open gaps become
        │                tasks in create-tasks (gap → action loop).
        ▼
 ┌──────────────┐
 │IMPLEMENTATION│
 └──────┬───────┘
        │
   ⑦ create-tasks      Plan → Task backlog structured by phases
        │                Tasks with IDs, criticality and dependency matrix.
        ▼
   ⑧ execute-task      Task → Implemented code (9-step workflow)
        │                Analysis → Localization → Planning → Implementation →
        │                Tests → Validation → Lint → Conclusion → Update.
        ▼
   ⑨ converge          Spec + Plan + Tasks + real code → Reconciliation report
        │                Reconciles documented intent against the current code
        │                state; appends actionable gaps as a new task phase.
        ▼
   ⑩ review-task       Tasks → Status report with metrics and next actions
```

> `analyze` is not a numbered sequential step — it is a **read-only lateral
> cross-check** (spec/plan/tasks/constitution consistency) usable at any point
> after `create-tasks`, the same way `CONTRIBUTING.md` diagrams it
> (`analyze -. read-only cross-check .-> specify`).

## When to use each skill

| Moment | Skill | Input | Output |
|--------|-------|-------|--------|
| New project or large feature | `briefing` | Interactive conversation | `briefing.md` |
| After briefing | `constitution` | Briefing + context | `constitution.md` |
| New feature | `specify` | Natural-language description | `spec.md` |
| Spec with open questions | `clarify` | Existing `spec.md` | Updated `spec.md` |
| Spec ready | `plan` | `spec.md` | `plan.md`, `data-model.md`, `contracts/` |
| Before implementing | `checklist` | Spec + Plan | `checklists/{domain}.md` |
| Plan ready | `create-tasks` | `plan.md` | Structured backlog |
| Tasks created | `analyze` | All artifacts | Consistency report |
| Specific task | `execute-task` | Task ID | Code + report |
| Implementation "done" | `converge` | Spec + Plan + Tasks + real code | Actionable gaps as a new task phase |
| Tracking | `review-task` | Tasks file | Progress report |

## Shortcuts — you don't always need the full pipeline

- **Simple feature**: `specify` → `plan` → `create-tasks` → `execute-task`
- **Bug fix**: `bugfix` (standalone skill, no pipeline required)
- **Existing project without docs**: `briefing` → `constitution` (no scaffold needed — the skills create `docs/briefing.md` and `docs/constitution.md` themselves)
- **Only need tasks**: `create-tasks` directly (if you already have enough context)

`specify` also brings a triage guide "update an existing spec vs. open a new
feature" (v5.22.0): same intent/refinement → update the spec; intent changed
or scope exploded → new feature.

## Living Specs and Delta Requirements (v5.23.0)

Feature specs describe CHANGES and are archived under
`docs/specs/_archived/YYYY-MM-DD-<feature>/` once completed. So that the
knowledge of "how the system behaves NOW" does not evaporate into the archive,
there is a **canonical living-specs corpus** in `docs/specs/current/`
(one file per capability):

- A feature spec may declare an optional `## Delta Requirements` section
  with `ADDED/MODIFIED/REMOVED/RENAMED Requirements` subsections.
- At archive time (a `review-features` action), the delta is validated by
  `delta-gate.sh` (corpus structure, references, "a feature without a delta is
  invalid unless explicitly skipped") and applied to the corpus by `delta-merge.sh`
  (atomic per-capability merge).
- A conflict is NEVER merged silently — it becomes a block with a diagnostic
  (in the autonomous flow, recorded via `bloqueios.sh`).

Origin of the model: benchmark of [OpenSpec](https://github.com/Fission-AI/OpenSpec)
(separation `specs/` = current behavior vs `changes/` = proposed deltas).

## Workflow: execute-task

The `execute-task` skill enforces a complete 9-step workflow:

1. **Analysis** - Detect context and read documentation
2. **Localization** - Find the task in the tasks file
3. **Planning** - Define scope and identify patterns
4. **Implementation** - Execute the task
5. **Tests** - Run tests if applicable
6. **Validation** - Verify quality and consistency
7. **Lint** - Check formatting and standards
8. **Conclusion** - Generate execution report
9. **Update** - Mark the task as completed

## Protocol: bugfix

The `bugfix` skill implements an 8-step protocol distilled from the practice of
fixing bugs in multi-service architectures, focused on eliminating
"fix-reveals-fix" cycles:

- Classifies complexity (simple vs. multi-layer)
- Traces the full data flow before any change
- Maps DTOs, enums and field names across every boundary
- Implements fixes across all affected layers at once
