**English** · [Português (pt-BR)](./agente-00c.pt-BR.md)

# Agente-00C — autonomous orchestrator of the SDD pipeline

> **Advanced track.** Not required for basic use of the toolkit (see
> [Start here](../README.md#start-here)). Supporting subsystems:
> [Parallel sessions](./cstk-session.md) and
> [Knowledge memory](./cstk-recall.md).

> **Status: functional and in use by the maintainer** — but **without an
> automated test suite for the custom agents** (validated by real runs, a
> conscious decision from the briefing). For external adoption, treat it as
> **experimental**: it is a personal experiment in autonomous orchestration,
> not a product with support guarantees. The original backlog (already
> completed) is in [`specs/_archived/agente-00c/`](./specs/_archived/agente-00c/)
> (44 tasks, 9 phases); the feature has evolved a lot since then — see
> feature-00c, model-routing and the knowledge memory.

`agente-00C` is an **autonomous orchestrator** of the toolkit's SDD pipeline:
you invoke `/agente-00c` with a short POC/MVP description and it runs
`briefing → constitution → specify → clarify → plan → checklist →
create-tasks → execute-task → review-task → review-features`, **pausing only
on real blocks** (decisions that require a human) and between scheduled waves
— it is **not** "fire-and-forget". The primary deliverable is an **auditable
report** rich in decisions, blocks and lessons learned: it exists precisely so
you can review the route, instead of blindly trusting the chain of steps.

> **Tip — ideal briefing prompt**: the more complete the initial description,
> the fewer questions the agent asks in the `briefing` step. Use the fillable
> template at
> [`templates/briefing-prompt-ideal.md`](./templates/briefing-prompt-ideal.md)
> — mapped 1:1 with the briefing sections, with extra blocks for complex
> architectures and a pruning guide for simple deliverables.

## Exposed commands

| Command | Function |
|---------|----------|
| `cstk 00c <path>` | **Recommended shortcut**: interactive bootstrap (creates the directory, collects parameters and invokes `claude` with `/agente-00c` already assembled) |
| `/agente-00c <descricao> [--stack ...] [--whitelist ...] [--projeto-alvo-path ...]` | Direct invocation in claude (alternative to `cstk 00c`) |
| `/agente-00c-resume [--projeto-alvo-path ...] [--resposta-bloqueio <id>:<resp>]` | Resume after a pause or schedule |
| `/agente-00c-abort [--projeto-alvo-path ...]` | Manual abort |

> **`cstk 00c <path>`** is the preferred path to start a new POC/MVP: it
> validates the path, creates the directory, collects description/stack/whitelist
> via prompts and runs `exec claude` with the slash command auto-submitted. It
> requires an interactive TTY and only operates on new or empty paths — to
> resume an existing run, use `/agente-00c-resume` directly in claude. Details in
> [`specs/_archived/cstk-cli/contracts/cstk-00c.md`](./specs/_archived/cstk-cli/contracts/cstk-00c.md).

## Prerequisites

- **Claude Code** (Opus 4.x or Sonnet 4.6 recommended), **Auto mode**
  enabled to reduce interruptions.
- **Authenticated `gh` CLI** (only needed when *you* publish a toolkit bug
  report — FR-021: the orchestrator only **drafts** the issue under
  `<target>/.claude/agente-00c-issues/<sug>.md`, with project context
  redacted; you review and run `issue.sh publish --from <file>`).
- **`git` on the PATH** (local commit between waves).
- **Local Docker** (only if the suggested stack uses containers; the
  orchestrator refuses any `docker push`/external deploy — Principle V of the
  feature).
- **Toolkit installed via `cstk install`** so the slash commands and custom
  agents are available.

## Known limitations

- **Schedule limited to 60-3600s via `ScheduleWakeup`**: cross-session
  continuation uses `ScheduleWakeup`; for long pauses (>=1h or blocks that
  will only be answered in hours/days), the partial report suggests creating a
  manual routine via `/schedule` that survives laptop suspend/restart
  (Anthropic cloud).
- **No native observability of consumed tokens**: the session budget uses
  proxies (wave tool calls, wallclock, state size).
- **No raw `git push`, no external deploy, no `sudo`**: by the feature's
  constitution, the blast radius is confined to `--projeto-alvo-path`. The
  confined push+PR path exists only in the atomic-commit mode finalize.
- **Automated test suite**: validation happens through real runs with manual
  scenarios
  ([`specs/_archived/agente-00c/quickstart.md`](./specs/_archived/agente-00c/quickstart.md)).
- **State schema without automatic migration across major versions**: pending
  runs must be completed or aborted before upgrading.

Full details (briefing, constitution, spec with 31 FRs, plan, research,
threat-model, contracts, quickstart) in
[`specs/_archived/agente-00c/`](./specs/_archived/agente-00c/).

## Feature-00C — individual-feature scope variant

Since v3.13.0, the toolkit offers `/feature-00c` as a variant of agente-00c
focused on **one feature** within a project that ALREADY has ratified
`briefing.md` + `docs/constitution.md`. Reduced pipeline:
`specify → clarify → plan → checklist → create-tasks → execute-task →
review-task` (without briefing/constitution/review-features, which are
prerequisites validated in FR-PRE-001..004).

| Command | When to use |
|---------|-------------|
| `/feature-00c "<descricao>" [<short-name>]` | Add a new feature to an existing project |
| `/feature-00c "<incremento>" --reopen=<short-name>` | Reopen a completed feature to receive an increment (v7.3.0 — see below) |
| `/feature-00c-resume <short-name> [--resposta-bloqueio "..."]` | Resume after a pause or schedule |
| `/feature-00c-abort <short-name> [--purge-backups]` | Manual abort (SIGTERM + 60s grace period) |

Co-existence with `/agente-00c`: isolated namespaces
(`agente-00c-state/` vs `feature-00c-state/<short_name>/`). Parallel features
in the same project are allowed; concurrency with an active agente-00c is
blocked (FR-026). Full reuse of the shared POSIX runtime
(`agente-00c-runtime`). Details in
[`specs/_archived/feature-00c/`](./specs/_archived/feature-00c/).

### Reopening a completed feature (`--reopen`)

Until v7.3.0 a completed feature was a dead end: re-invoking `/feature-00c`
with the same short-name died at init because the state already existed, and
the only way out was editing state by hand or opening a parallel feature —
fragmenting the spec and losing the identity of what is, conceptually, the
same capability. `/feature-00c "<incremento>" --reopen=<short-name>` fixes
that:

- **The previous execution is preserved as an immutable round** and the new
  execution starts pointing at it. Rotation primitive: `state-rounds.sh`
  (`next-label`, `rotate`, `recover`, `list`); the rotation commit is a
  single directory `mv` (POSIX's only atomic primitive) with journal +
  staging, and `recover` resolves an interruption by command — no manual
  file editing. Rounds are zero-padded (`r01`, `r02`) for correct
  lexicographic ordering.
- **The increment lands in the existing spec, not in a parallel one**: the
  archived spec is restored and `specify` records the increment as
  `## Delta Requirements`; `create-tasks` detects the reopening and
  **appends** a new phase to `tasks.md`, preserving completed tasks
  (phase number computed by `next-task-id.sh --phase`).
- **Advisory opinion + human block before touching disk**: the command
  issues a reopen-vs-new-feature opinion and pauses for the human decision
  before any write.
- **Pending-work probe fail-closed**: `commit-mode.sh probe-pending-work`
  checks for non-integrated work (branch not merged into the default, open
  PR). A field only receives a concrete value from a successful, parsed
  read; any other outcome keeps `unknown` + `probe_status=skipped-*` — it
  never infers `merged=no` from a failure.
- **Round provenance in the knowledge index**: `cstk recall --reindex`
  namespaces provenance per round, so preserved rounds are never counted as
  active executions nor double-counted (including rounds on the SQLite
  backend).

Spec: [`specs/feature-reopen/`](./specs/feature-reopen/)
([`contracts/reopen-flow.md`](./specs/feature-reopen/contracts/reopen-flow.md),
[`contracts/state-rounds.md`](./specs/feature-reopen/contracts/state-rounds.md),
[`contracts/pending-work-probe.md`](./specs/feature-reopen/contracts/pending-work-probe.md)).

## Per-wave model routing (model-routing)

> **BREAKING v4.0.0** — model-routing **is no longer audit-only** (the v3.15.0
> premise, revoked): the current harness accepts `model` on subagent spawn, and
> the model is now **APPLIED** on every wave.

At the start of each wave, the **parent command** (`/agente-00c`, `/feature-00c`
and their resumes) calls `model-routing.sh wave-select` and applies the returned
model on the orchestrator's spawn. The base is a deterministic phase→model map
(`references/phase-model-map.txt`, pure POSIX):

| Phase | Tier | Floor model |
|-------|------|-------------|
| `plan`, `analyze`, `constitution` | deep | **opus** |
| `specify`, `clarify`, `checklist`, `create-tasks`, `briefing` | medium | **sonnet** |
| `execute-task` | shallow | **sonnet** (floor; refinable ↑opus / ↓haiku) |
| `validate-docs`, `review-task` | shallow | **haiku** |
| phase not listed | — | `manter-atual` (never an error) |

Resolution precedence:
`operator manual override > mid-wave escalation (opus) > model-selector refinement > phase→model map`.

The **model-selector** skill became an optional refinement layer (only in
`execute-task` with `--task-text`): it can raise to opus or lower to haiku over
the map's floor, citing signals. The **suggest-only** contract is preserved:
the skill never switches the model on its own — the parent command applies it.
Suggested-vs-applied auditing via `model-routing-report.sh aggregate`
(consumed by `review-task` §4.5).

Specs: [`specs/_archived/model-routing-por-onda/`](./specs/_archived/model-routing-por-onda/)
(current mechanism) and
[`specs/_archived/agente-00c-model-routing/`](./specs/_archived/agente-00c-model-routing/)
(original feature, revoked audit-only).

## Atomic-commit mode (opt-in)

Since v5.12.0, the orchestrators offer an opt-in **atomic-commit** mode: each
artifact step generates an automatic Conventional Commits commit, and each
group of `execute-task` tasks with `outcome=pass` generates a ranged commit at
the end of the wave. The terminal finalize triggers push + PR via
`cstk session pr` (direct push remains blocked by `bash-guard.sh`).

Since v5.23.0, staging is **by a derived allowlist** from the wave's diff
(`snapshot`/`stage-derived` subcommands of `commit-mode.sh`) — never
`git add -A`: untracked files unrelated to the run never enter the automatic
commits.

| Component | Location |
|-----------|----------|
| POSIX helper (`is-enabled`, `set-enabled`, `guard-branch`, `stage-message`, `task-message`, `snapshot`, `stage-derived`, `finalize`) | `plugins/cstk/skills/agente-00c-runtime/scripts/commit-mode.sh` |
| Tests | `tests/test_commit-mode.sh` |
| Spec | [`specs/_archived/atomic-commit-pr/`](./specs/_archived/atomic-commit-pr/) |

## Roadmap mode and parallel feature waves

Roadmap mode (opt-in at `/agente-00c` start) shortens the chain to
`briefing → constitution → roadmap`: the orchestrator writes
`docs/roadmap.md` (ordered entries with `depende-de`, an acyclic dependency
DAG) and the execution ends with `termination_reason=concluido_roadmap`.
Since the `roadmap-parallel-launch` feature the **coordinator session does
not stop there**: the parent command (`agente-00c.md` §6.ter / resume §9.ter)
computes the *frontier* — entries `nao-iniciada` whose dependencies are all
`concluida`, status derived from `docs/specs/` by `roadmap-status.sh`, never
from a `status` field in the roadmap — and offers a **parallel wave**:

1. `roadmap-frontier.sh --specs-dir docs/specs [--json]
   [--exclude-active-from-repo <repo>]` lists eligible candidates (worktrees
   already active are filtered out); an *overlap hint* ("entries X and Y both
   mention `<token>`") may be printed from the roadmap prose, sanitized and
   labelled `roadmap-prose-untrusted` — never phrased as a confirmed conflict.
2. The operator is asked whether to launch, with the **default cap of 2**
   features per wave (also a blast-radius limit — a worktree is filesystem
   isolation, **not** a security sandbox: children share `.git`, `$HOME`,
   `~/.claude` and credentials) and, above the cap, which ones.
3. `parallel-launch.sh emit --repo <repo> --feature <short> [...]` **only
   prints** the launch commands per feature — `cstk session start <short>` +
   `tmux new-window ... claude --name ... "/feature-00c <short>"`, or the
   degraded `cd ... && claude ...` form when `check-tmux` says tmux is
   absent (exit 3). The parent runs them; the script never executes anything
   and never touches `cli/lib/session.sh`.
4. When a child execution reaches a terminal state (`concluida`, `abortada`
   or `aguardando_humano`) `feature-00c.md` §5.quater sends, best-effort via
   the Claude Code `SendMessage` tool, the opaque trigger
   `[cstk-parallel] feature=<short> outcome=<...> repo=<repo>`. The
   coordinator (`agente-00c.md` §6.quater) parses it fail-closed with
   `parallel-notification-parse.sh check` (whole-message anchored regex,
   any extra text ⇒ exit 1) and **recomputes the frontier** before offering
   the next wave — a forged notification can at most cause a redundant
   recompute (INV-8).

Empirically verified (dec-037 of the feature): an idle Claude Code session
(13 h idle) woke up on `SendMessage` and answered in ~30 s without human
intervention. Kill switch: `tmux kill-window -t <pane>` + `cstk session end
<short>`. Manual verification path: `cstk session list`,
`roadmap-status.sh --json`, `tmux list-panes -a` (§6.bis).

| Component | Location |
|-----------|----------|
| Frontier + overlap hint | `plugins/cstk/skills/review-features/scripts/roadmap-frontier.sh` |
| Launch composition (`emit`, `check-tmux`) | `plugins/cstk/skills/agente-00c-runtime/scripts/parallel-launch.sh` |
| Notification parser (fail-closed) | `plugins/cstk/skills/agente-00c-runtime/scripts/parallel-notification-parse.sh` |
| Parent-command prose | `plugins/cstk/commands/agente-00c.md` §6.ter/§6.quater, `agente-00c-resume.md` §9.ter/§9.quater, `feature-00c.md` §5.quater |
| Tests | `tests/test_roadmap-frontier.sh`, `tests/test_parallel-launch.sh`, `tests/test_parallel-notification-parse.sh`, `tests/test_command-spawn-parallel-launch.sh` |
| Specs | [`specs/roadmap-mode/`](./specs/roadmap-mode/), [`specs/roadmap-parallel-launch/`](./specs/roadmap-parallel-launch/) |

## Enforced guards (PreToolUse hook + integrity + host allowlist)

The runtime's security guards (`bash-guard.sh`, panel checksum, URL scheme)
used to be **advisory**. Three fronts became **enforced** (they no longer
depend on the orchestrator remembering):

1. **Fail-closed `PreToolUse`/`Bash` hook**: intercepts every Bash command of
   an active `agente-00c`/`feature-00c` run and delegates to
   `bash-guard.sh check` — it never reimplements the rule. Failure of the
   mechanism itself also blocks (`MECANISMO_FALHOU`, distinguishable from
   `REGRA_VIOLADA`). The operator's manual sessions stay intact. Auditable
   decisions in `.claude/enforcement-log.jsonl` (secrets scrubbed before
   truncation).
2. **`cstk serve` fail-closed by default**: absence of the package's `.sha256`
   blocks (`unverifiable-blocked`); explicit and audited bypass via
   `--allow-unverified`/`CSTK_SERVE_ALLOW_UNVERIFIED=1`; a checksum mismatch
   always blocks, with no bypass.
3. **Trusted-host allowlist** (`CSTK_TRUSTED_RELEASE_HOSTS`, exact
   case-insensitive match, `file://` exempt) applied in `cstk serve`,
   `cstk install --from` and `cstk self-update --from`.

| Component | Location |
|-----------|----------|
| Hook + settings snippet | `plugins/cstk/skills/agente-00c-runtime/hooks/pretooluse-bash-guard.sh` + `settings.snippet.json` |
| Automatic provisioning | `apply_guard_hooks()` in `cli/lib/hooks.sh` (`project` scope) |
| Shared host allowlist | `cli/lib/trusted-hosts.sh` |
| Auditable log | `.claude/enforcement-log.jsonl` (per target project) |
| Spec | [`specs/_archived/2026-07-28-enforced-guards/`](./specs/_archived/2026-07-28-enforced-guards/) |

Runtime complements: `PostToolUse` tool-call metric hook (append-only sidecar,
v5.21.0) and the `DIAG|severity|code|message|fix` diagnostic envelope in the
POSIX helpers (`_diag.sh`, v5.22.0) — the `fix` field states the next
actionable step for the agent.
