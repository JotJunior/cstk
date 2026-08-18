**English** · [Português (pt-BR)](./cstk-session.pt-BR.md)

# Parallel sessions (`cstk session`)

> **Advanced track** — support for the [autonomous orchestrator](./agente-00c.md).

Lets you work on multiple features simultaneously in the same repository without
colliding on the working tree, HEAD branch, or `.claude/agente-00c-state/`. It
isolates each session in a git worktree that is a sibling of the main repo.

```bash
# Start a new session (creates worktree + branch + filtered .claude/)
cstk session start iniciacao-membro
# → creates <parent>/<repo>-iniciacao-membro/ with branch iniciacao-membro

# List active sessions
cstk session list
# NAME              BRANCH              IDLE  STATUS   PATH
# iniciacao-membro  iniciacao-membro    0d    CURRENT  /home/jot/Projects/meta-gob-ms-iniciacao-membro
# oauth2-refresh    feat/oauth2         2d    *        /home/jot/Projects/meta-gob-ms-oauth2-refresh

# Open a PR via gh (idempotent)
cstk session pr iniciacao-membro

# End the session (with guards for dirty/unpushed/open PR)
cstk session end iniciacao-membro
# Or force without prompts:
cstk session end iniciacao-membro --force
```

## Subcommands

- `start <name> [--reset|--reuse] [--force]` — creates worktree + branch + filtered
  `.claude/` (excludes `agente-00c-state/`, `agente-00c-archive/`, `insights/`,
  `settings.local.json`, `agente-00c-whitelist`, `agente-00c-report.md`,
  `agente-00c-suggestions.md`, `.agente-00c-state.lock`)
- `list [--json]` — table with `NAME BRANCH IDLE STATUS PATH`; combinable
  markers `CURRENT,*,STALE`
- `end <name> [--force]` — removes worktree + local branch; prompts if there are
  uncommitted changes, unpushed commits, or an open PR
- `pr <name> [--draft] [--title T] [--body B] [--reviewer USER]` — push + opens
  a PR via `gh pr create`; idempotent (returns the existing URL if the PR is
  already created)

**Requirements**: `git >= 2.36`, `gh` (required only for `pr`; optional for `end`).

> **Programmatic consumer (since 8.2.0)**: the parallel wave offered by
> `/agente-00c` after roadmap mode composes `cstk session start <short>`
> through `plugins/cstk/skills/agente-00c-runtime/scripts/parallel-launch.sh
> emit` (it prints the commands; the parent command runs them). The script
> mirrors the worktree derivation of `cli/lib/session.sh`
> (`<parent-of-repo>/<repo>-<short>`) but never sources or edits it — if you
> change `start`'s signature or the worktree naming, update the composer and
> `tests/test_parallel-launch.sh` too. See
> [docs/agente-00c.md](./agente-00c.md#roadmap-mode-and-parallel-feature-waves).

## Full documentation

- [`specs/_archived/cstk-session/spec.md`](./specs/_archived/cstk-session/spec.md) — user stories, FRs, success criteria
- [`specs/_archived/cstk-session/contracts/cli-session.md`](./specs/_archived/cstk-session/contracts/cli-session.md) — exit codes (5-15), flags, output formats
