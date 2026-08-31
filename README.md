**English** · [Português (pt-BR)](./README.pt-BR.md)

# Claude Code Toolkit

[![Latest Release](https://img.shields.io/github/v/release/JotJunior/cstk?label=latest%20release&color=blue)](https://github.com/JotJunior/cstk/releases/latest)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](./LICENSE)
[![SemVer](https://img.shields.io/badge/SemVer-7.x-orange.svg)](./CHANGELOG.md)
[![Docs Site](https://img.shields.io/badge/docs-jotjunior.github.io/cstk-blue?logo=readthedocs)](https://jotjunior.github.io/cstk/)
[![Publish Site](https://github.com/JotJunior/cstk/actions/workflows/publish-site.yml/badge.svg?branch=main)](https://github.com/JotJunior/cstk/actions/workflows/publish-site.yml)

A set of tools to boost day-to-day development productivity with
[Claude Code](https://claude.ai/code): **skills** and **hooks** for
documentation, development, security and code quality.

> **Who maintains it / who it's for.** Maintained by a single person, optimized
> first for the maintainer's workflow (Go microservices). The concrete parts —
> skills, hooks, CLI — are general-purpose; the **advanced track** (autonomous
> orchestrator) is more experimental.

> **Current version:** [latest release](https://github.com/JotJunior/cstk/releases/latest)
> · history in [CHANGELOG.md](./CHANGELOG.md). Installation recommended via
> the `cstk` CLI (see [Installation](#installation)).

![cstk panel — execution detail: 16-wave timeline with stage, tool calls, tokens, wallclock and real cost per wave, decisions by score and most-invoked skills](./docs/screenshots/panel-exec.png)

*An autonomous `agente-00c` run seen from the [web panel](#screenshots): per-wave
timeline with real cost, decision scores and invoked skills — every number
measured locally, never fabricated. More shots in [Screenshots](#screenshots).*

## Start here

Two tracks, depending on what you're looking for:

| Track | For whom | Where to go |
|--------|-----------|---------|
| **Basic** | Wants day-to-day productivity — specify, review, fix, document with a few skills | This section + [Global Skills](#global-skills) |
| **Advanced** | Wants the autonomous orchestrator running the whole SDD pipeline on its own | [Advanced track](#advanced-track-autonomous-orchestrator) |

### Basic track in 3 steps

```bash
# 1. Install (once per machine)
curl -fsSL https://github.com/JotJunior/cstk/releases/latest/download/install.sh | sh
```

```text
# 2. Open Claude Code in your project and invoke a skill via its trigger:
#    "especifica essa feature: ..."   → specify  (idea → spec)
#    "revisa a segurança desse código" → owasp-security
#    "corrige esse bug: ..."          → bugfix   (multi-layer investigation)
#    "me aconselhe sobre esse plano"  → advisor  (strategic critique)
```

```text
# 3. Done. Skills are auto-invoked by context — you describe the
#    intent in natural language and the trigger fires the right skill.
```

> You don't need the autonomous orchestrator to get started. It's the advanced
> track — adopt it when you want the SDD pipeline to run end to end without you
> driving each step.

### After installing: turn on cost and token capture

Two environment variables — **no API key, no Admin key, no organization**;
works on subscription plans:

```bash
export CLAUDE_CODE_ENABLE_TELEMETRY=1
export OTEL_METRICS_EXPORTER=prometheus
```

With these, every orchestrator wave records its **real** consumption (cost and
tokens, separating `main` from `subagent`) in `.waves[N].otel_usage`, and the
panel shows per-wave spend. Without them everything is a no-op and the field
stays `null` — absent, never a fabricated zero. Put them in your
`~/.zshrc`/`~/.bashrc` so you don't lose waves to forgetfulness.

Nothing leaves the machine (exporter binds `127.0.0.1:9464`) and identity
labels are stripped before touching disk.

> **Running more than one Claude Code process at a time?** Only the first can
> bind the fixed port — the others silently measure nothing (`otel_usage`
> `null` on every wave). Use the per-process port launcher shown in
> [Real per-wave cost](#real-per-wave-cost-otel-usagesh) to give each process
> its own exporter automatically.

## Screenshots

| | |
|---|---|
| ![Panel overview: plan quota, real cost, subagent tokens, active projects, running executions, model mix](./docs/screenshots/panel-home.png) *Panel overview (`cstk serve`): plan quota, real cost, running executions, model mix.* | ![Per-execution task list with outcome, tests and lint per task](./docs/screenshots/panel-tasks.png) *Tasks of an execution: outcome, tests and lint per task, 100% pass rate.* |
| ![cstk recall searching the cross-project knowledge base from the terminal](./docs/screenshots/cstk-recall.png) *`cstk recall`: full-text memory across every past execution, with provenance (project/feature/wave/date).* | ![The review-features skill generating a feature portfolio report inside Claude Code](./docs/screenshots/cstk-review-features.png) *The `review-features` skill building a cross-feature portfolio report inside Claude Code.* |
| ![cstk doctor reporting the installed catalog in sync, 32 OK, zero drift](./docs/screenshots/cstk-doctor.png) *`cstk doctor`: installed catalog audited against the manifest — zero drift.* | |

## Structure

```
├── plugins/                     # Catalog, packaged as installable Claude Code plugins
│   ├── cstk/                    # Default plugin (marketplace entry "cstk")
│   │   ├── commands/            # The 7 /agente-00c*, /feature-00c*, /roadmap-wave slash commands
│   │   ├── agents/              # Orchestrators, clarify asker/answerer, data-veracity
│   │   ├── hooks/hooks.json     # 3 enforced guard hooks (bash-guard, tool-call-tick, agent-usage)
│   │   ├── .mcp.json            # registers the cstk-state MCP server (auto-starts on the plugin path)
│   │   ├── mcp/state-server/    # MCP server source (Node/TS, stdio) — ships INSIDE the plugin
│   │   ├── evals/               # `claude plugin eval` suite (generated from the skills' triggers.jsonl)
│   │   └── skills/               # 21 global skills (each skill is a folder)
│   │       ├── advisor/
│   │       ├── agente-00c-runtime/ # internal POSIX runtime (not user-invocable)
│   │       ├── analyze/
│   │       ├── apply-insights/
│   │       ├── briefing/
│   │       ├── bugfix/
│   │       ├── checklist/
│   │       ├── clarify/
│   │       ├── constitution/
│   │       ├── converge/           # reconciles spec/plan/tasks vs actual code
│   │       ├── create-tasks/
│   │       ├── e2e-integration-flow/ # full-stack E2E integration tests (Playwright)
│   │       ├── execute-task/
│   │       ├── model-selector/     # model routing heuristic (suggester)
│   │       ├── owasp-security/
│   │       ├── plan/
│   │       ├── review-features/
│   │       ├── review-task/
│   │       ├── specify/
│   │       ├── validate-docs-rendered/
│   │       └── validate-documentation/
│   └── cstk-language-go/        # Go-profile plugin (marketplace entry "cstk-language-go")
│       ├── hooks/                # Go-specific hooks
│       └── skills/               # Go — see docs/go-toolkit.md
├── .claude-plugin/marketplace.json  # Marketplace manifest (2 entries: cstk, cstk-language-go)
├── cli/                          # cstk binary + POSIX libs (not shipped by the plugin — FR-006)
└── docs/                         # Topic-based documentation (see index below)
```

> Installed via the classic `cstk` CLI, this same content lands in
> `~/.claude/skills/`, `~/.claude/commands/` and `~/.claude/agents/`
> (flattened, no `plugins/cstk/` prefix). Installed via the native
> Claude Code plugin, it materializes under the harness's own
> `installPath` (see [Installation](#installation) for both paths).

### Anatomy of a skill

Each skill is a folder with a `SKILL.md` (entry point) and, as needed,
subfolders consulted on demand (*progressive disclosure* — the model
pays only for the context needed at invocation time):

```
skills/<name>/
├── SKILL.md             # When to invoke, high-level rules, gotchas
├── templates/           # Fill-in templates
├── examples/            # Concrete cases (good.md vs bad.md)
├── references/          # Supporting documentation
├── scripts/             # Deterministic POSIX scripts
└── config.json          # Per-project configuration (optional)
```

Not every skill uses all subfolders — simple skills are just a `SKILL.md`.

## Global Skills

Skills in `plugins/cstk/skills/`, independent of language or framework.

### SDD Pipeline (Spec-Driven Development)

Recommended sequence to take an idea from discovery to implementation.
Details, flow diagram and shortcuts in
[docs/sdd-pipeline.md](./docs/sdd-pipeline.md).

| Skill | Trigger | Description |
|-------|---------|-----------|
| **briefing** | "briefing", "discovery", "novo projeto" | Structured discovery interview (vision, users, constraints, stack) |
| **constitution** | "constitution", "princípios do projeto" | Immutable governance principles that guide decisions |
| **specify** | "specify", "criar spec", "nova feature" | Natural description → SDD feature spec (stories, requirements, success criteria). Gate: every requirement needs >=1 scenario; optional Delta Requirements section (living specs) |
| **clarify** | "clarify", "resolver ambiguidades" | Resolves spec ambiguities via structured questions (max 5) |
| **plan** | "plan", "plano técnico" | Implementation plan: research, data model, contracts |
| **checklist** | "checklist", "quality gate" | "Unit Tests for English" — validates REQUIREMENT quality; gaps become tasks |
| **create-tasks** | "criar tarefas", "criar backlog" | Task backlog by phases with dependencies and criticality |
| **execute-task** | "executar tarefa", "execute task" | Executes a task following the mandatory 9-step workflow |
| **converge** | "converge", "o código bate com a spec?" | Reconciles spec/plan/tasks against the CURRENT code and appends gaps as a new task phase. Regular pipeline stage between execute-task and review-task in the orchestrators |
| **review-task** | "revisar tarefas", "status das tarefas" | Status report with progress and recommendations |

> `analyze` is not a numbered sequential step — it is a **read-only lateral
> cross-check** (spec/plan/tasks/constitution), usable at any point from
> `create-tasks` onward.

### Complementary Skills

| Skill | Trigger | Description |
|-------|---------|-----------|
| **advisor** | "me aconselhe", "analise estratégica" | Brutally honest advisor that dissects reasoning and generates action plans |
| **analyze** | "analyze", "analisar consistência" | Read-only cross-artifact consistency analysis |
| **bugfix** | "bugfix", "fix bug", "debug" | Structured multi-layer bug-fixing protocol |
| **e2e-integration-flow** | "e2e", "playwright", "validar fluxo completo" | Full-stack E2E integration tests (UI → API → database → queue → side effects) |
| **apply-insights** | "aplicar insights", "melhorar claude.md" | Applies proven usage insights to CLAUDE.md, hooks and workflows — see [Usage insights](#usage-insights) |
| **owasp-security** | When reviewing security | Checklist-guided review (OWASP Top 10:2025, ASVS 5.0, LLM/Agentic, NIST, OAuth 2.1...). Does not replace audit/pentest |
| **review-features** | "status global", "comparar features" | Cross-feature report suggesting archive/abandon/prioritize; the archive action applies deltas to the living-specs corpus |
| **validate-documentation** | "validar documentação", "verificar UC" | Validates individual documents against structural standards |
| **validate-docs-rendered** | "validar renderização", "verificar diagramas" | Validates that the Markdown renders (Mermaid, links, frontmatter, tables) |

## Advanced track (autonomous orchestrator)

> **Experimental** — functional and in use by the maintainer, with no support
> guarantees for external adoption.

`/agente-00c` drives the entire SDD pipeline over a target project, pausing
only on real blockers; `/feature-00c` does the same for ONE feature in an
existing project. Subsystems: per-wave model routing, atomic-commit mode
(automatic commits + push/PR at finalize), enforced guards (fail-closed hook),
parallel sessions in worktrees, roadmap mode (briefing → constitution →
`docs/roadmap.md` with a dependency DAG) that can end by **offering a
parallel wave** of independent features — each opened as a `cstk session`
worktree + named `claude` session (tmux pane when available), with the child
sessions notifying the coordinator via cross-session messaging so the next
wave is offered as soon as the frontier moves — and cross-feature knowledge
memory consulted before deciding.

Since v7.3.0 a finished feature is no longer a dead end:
`/feature-00c "<increment>" --reopen=<short-name>` preserves the previous
execution as an immutable round, records the increment as
`## Delta Requirements` in the existing spec, and appends a new task phase
instead of regenerating the backlog — with an advisory opinion (reopen vs new
feature) and a human block before anything touches disk.

| Topic | Document |
|--------|-----------|
| `/agente-00c` + `/feature-00c` orchestrators, model-routing, atomic-commit, guards | [docs/agente-00c.md](./docs/agente-00c.md) |
| Parallel sessions (`cstk session`) | [docs/cstk-session.md](./docs/cstk-session.md) |
| Roadmap mode + parallel wave of features (post-roadmap offer, notification, next wave) | [docs/agente-00c.md](./docs/agente-00c.md#roadmap-mode-and-parallel-feature-waves) |
| Knowledge memory (`cstk recall`) | [docs/cstk-recall.md](./docs/cstk-recall.md) |
| Loose usage tracking (`cstk usage`) | [docs/cstk-usage.md](./docs/cstk-usage.md) |
| Web metrics panel (`cstk serve`) | [docs/cstk-serve.md](./docs/cstk-serve.md) |

## Usage insights

The `apply-insights` skill is **prescriptive**: it reads your playbook
(`~/.claude/insights/usage-insights.md`, per user — generate it via Claude
Code's native `/insights`) and applies it to the project. Distinct from the
native `/insights`, which is **introspective** (analyzes your sessions).

<!-- --8<-- [start:install-section] -->
## Installation

### Via cstk CLI (recommended)

The toolkit is installed via `cstk` — a POSIX shell CLI that downloads,
validates (SHA-256), installs and updates skills without requiring a clone of
the repository.

**Bootstrap one-liner** (installs `cstk` into `~/.local/bin/`):

```bash
curl -fsSL https://github.com/JotJunior/cstk/releases/latest/download/install.sh | sh
```

After that, typical commands:

```bash
cstk --version                       # confirms installation
cstk install                         # installs the 'sdd' profile into ~/.claude/skills/
cstk install --profile all           # installs ALL 28 skills (includes language-go)
cstk install advisor bugfix          # cherry-pick by name
cstk update                          # applies new releases preserving local edits
cstk update --force                  # overwrites locally edited skills
cstk list                            # lists installed skills + status
cstk doctor                          # detects drift between manifest and disk
cstk self-update                     # updates the cstk binary itself + cli/lib
```

> **`install`/`update` touch only the catalog** (skills/commands/agents in
> `~/.claude/`); the runtime (`cli/lib/*.sh` + binary) updates via
> **`cstk self-update`**.

**Available profiles:**

| Profile | Content | Typical use |
|--------|----------|------------|
| `sdd` | 17 skills: complete Spec-Driven Development pipeline (briefing → review-features) + internal runtime, model-selector and the orchestrators' 4 quality gates | Default global installation |
| `complementary` | 10 independent skills (advisor, bugfix, e2e-integration-flow, etc.) | Complements the SDD pipeline |
| `all` | All 28 skills (sdd + complementary + language-go) | Full installation |
| `language-go` | Go-specific skills + hooks | Only in Go projects |

Default profile when none is given: `sdd`.

**Project scope** (`./.claude/skills/` in the CWD instead of `~/.claude/skills/`):

```bash
# In a Go project: installs skills + hooks + settings.json merge
cd ~/projects/my-go-app
cstk install --scope project --profile language-go

# Cherry-pick in project scope
cstk install --scope project advisor owasp-security

# language-* hooks ARE installed only in --scope project
# (in --scope global, hooks are omitted with a warning in the summary — FR-009c)
```

### Via Claude Code plugin (native, no binary)

Since v6.9.0 the catalog is also distributable as a native [Claude Code
plugin](https://docs.claude.com/en/docs/claude-code/plugins) — no `cstk`
binary, no clone, no `curl` bootstrap:

```text
/plugin marketplace add JotJunior/cstk
/plugin install cstk@cstk
# optional, Go projects only:
/plugin install cstk-language-go@cstk
```

Enable the plugin and open a new session in any project — skills, the 7
`/agente-00c*`/`/feature-00c*`/`/roadmap-wave` commands and the enforced guard hooks
(`pretooluse-bash-guard`, `posttooluse-tool-call-tick`,
`posttooluse-agent-usage`) activate automatically, with **no**
`cstk hooks install` step (confirmed empirically — see
[`docs/specs/_archived/2026-08-08-claude-plugin-packaging/spec.md`](docs/specs/_archived/2026-08-08-claude-plugin-packaging/spec.md)
§Clarifications, assumption A1). `posttooluse-loose-usage.sh` (opt-in
consumption capture) is deliberately **not** part of the plugin's
`hooks.json` — it stays an explicit opt-in via `cstk hooks install
--with-loose-usage`, and it also needs `CSTK_OTEL_ENDPOINT` in the `claude`
process environment or it captures nothing
([docs/cstk-usage.md](./docs/cstk-usage.md#requirements)).

**Choosing between the two paths:**

| | Classic (`cstk` CLI) | Plugin (native) |
|---|---|---|
| Install step | bootstrap one-liner + `cstk install` | `/plugin marketplace add` + `/plugin install` |
| Provides the `cstk` binary (`recall`, `usage`, `mcp`, `session`, `serve`, `self-update`) | Yes | **No** — the plugin format does not install a persistent binary on `PATH` (FR-006); use the classic bootstrap for these |
| `cstk-state` MCP server (the 7 state tools) | Mirrored to `~/.claude/mcp/state-server` by `cstk install`; registered per project with `cstk mcp install` | Ships inside the plugin and is registered by its own `.mcp.json` — **auto-starts, no per-project step** |
| Guard hooks activation | Requires `cstk hooks install` per project | Automatic on session start, zero per-project step |
| Integrity verification | SHA-256 of the tarball, fail-closed (`serve-integrity`), fixed trusted-host allowlist | Commit pin (`gitCommitSha`) recorded by the harness + its own "Will install" trust dialog |
| Update propagation | `cstk update` (explicit, per invocation) | **Not automatic**: `claude plugin marketplace update` then `claude plugin update cstk --scope <scope>`, plus a session restart — the plugin CLI itself prints `Restart to apply changes.` |

Both paths are equally official (no third, ungoverned distribution
mechanism — see `FR-017` in
[`docs/specs/current/guards-defense-in-depth.md`](docs/specs/current/guards-defense-in-depth.md))
and deliver the same auditable content with **comparable protection, not
identical mechanisms** — pick the plugin for the fastest zero-binary
onboarding of skills + guard hooks, the classic CLI when you need
`recall`/`usage`/`mcp`/`session`/`serve`, or **both together**: `cstk
doctor`/`cstk hooks install` detect the plugin and automatically avoid
double-registering the guard hooks (plugin wins; `cstk doctor` reports
`aligned`/`diverged`/`duplicated-hooks` with an actionable fix for each).

### 00c runtime hooks (`cstk hooks`)

The three 00c runtime hooks — `pretooluse-bash-guard.sh` (fail-closed Bash
guard), `posttooluse-tool-call-tick.sh` and `posttooluse-agent-usage.sh`
(per-wave metrics) — only run in a target project once they are copied into
`.claude/hooks/` **and** registered in `.claude/settings.json`.

`cstk install --scope project agente-00c-runtime` does that, but it also
copies the skill, 7 commands and 7 agents into the repo. When you only want
the hooks, use:

```bash
cd ~/projects/my-target-project
cstk hooks install                    # touches .claude/hooks/ + settings.json only
cstk hooks install --dry-run          # show the plan without writing
cstk hooks install --project-path ../other-project
cstk hooks install --remove-classic   # de-duplicate against the plugin, no prompt
cstk hooks install --local            # register in settings.local.json (third-party repos)
cstk hooks status                     # read-only: where is each hook registered?
```

**Third-party repos** (`--local`, issue #135): when the client's team
versions `.claude/settings.json` on purpose, a personal tool has no business
in it. `--local` writes the *registration* to `.claude/settings.local.json`
instead — Claude Code **sums** hooks across scopes, and the local file is
normally gitignored — so the hooks fire only for you and the team's file
stays byte-for-byte untouched. The scripts still land in `.claude/hooks/`;
keep them out of the client's `git status` without touching their
`.gitignore`:

```bash
printf '.claude/hooks/\n.claude/settings.local.json\n.claude/*.bak\n.claude/*.bak-pre-dedup\n' >> .git/info/exclude
```

The two `.bak` patterns cover the backups the command **itself** writes —
`settings.json.bak` / `settings.local.json.bak` when it merges the
registration, and `settings.json.bak-pre-dedup` when it removes a duplicate
classic block. Without them the backup shows up in the client's
`git status` and rides along in a distracted `git add -A` (issue #163).

Idempotent like the default flow. If the *other* file already registers
the 00c hooks (both would fire, double-counting every tool call) the
command warns and offers the same removal as the plugin dedup
(`--remove-classic` skips the prompt). `cstk hooks status` and
`guard-hooks-status.sh check` read both files, so `tick-mode` keeps
answering `hook` and the orchestrator does not tick by hand on top of an
active hook.

When the plugin already provides the hooks, `cstk hooks install` skips the
classic provisioning (plugin wins) and, if the project **still** carries a
classic registration in `settings.json`, both layers would fire. In that
case it asks whether to remove the classic block, deleting only the 00c
hook entries — third-party hooks and every other key in the file are
preserved — and writing a backup to `settings.json.bak-pre-dedup`. Use
`--remove-classic` to skip the prompt (scripts/CI). Without a TTY and
without the flag the block is **kept**, with a warning: `settings.json`
belongs to the operator and is never rewritten without explicit consent.

Without this step the Bash guard is inert and `tool_calls`/`agent_usage`
stay at zero for every wave. To check the current state without writing
anything:

```bash
guard-hooks-status.sh check --projeto-alvo-path .
# <hook>  present|missing  registered|unregistered  current|stale|unknown
```

Re-run `cstk hooks install` after every cstk upgrade that touches the hooks:
the copies under `.claude/hooks/` are snapshots and nothing reconciles them
with the catalog. A **stale** copy is as harmful as a missing one — it runs
an older ruleset. That is a real regression, not a hypothetical: after the
`state.json` → `state.db` cutover, projects kept a tick hook that only knew
how to read `state.json`, so `tool_calls` was 0 for every wave while the
check still reported "3/3 hooks active". The fourth column exists to make
that visible, and `tick-mode` falls back to `manual` in exactly that pairing
(backend-blind copy + `state.db`) so the metric survives until you
re-provision.

### Real per-wave cost (`otel-usage.sh`)

Claude Code's native OpenTelemetry counters are incremented **on every API
request** and carry a `query_source` label (`main` / `subagent` /
`auxiliary`). A snapshot at wave start and another at wave end gives the
exact consumption of that wave — including the orchestrator's own spend,
which the spawn hook can never capture (the orchestrator's spawn *encloses*
the wave, so its `tool_result` arrives after the wave is already closed).

Opt in with two environment variables — **no API key, no Admin key, no
organization**; works on subscription plans:

```bash
export CLAUDE_CODE_ENABLE_TELEMETRY=1
export OTEL_METRICS_EXPORTER=prometheus
```

`state-ondas.sh start`/`end` then populate `.waves[N].otel_usage`
automatically. Without the variables everything is a no-op and the field is
`null` — **absent, never a fabricated zero**.

Measured on a delegated task: `main` $0.156, `subagent` $0.141,
`auxiliary` $0.001 — the subagent was ~47% of the spend, exactly the slice
the panel used to show as `—`.

The exporter binds `127.0.0.1:9464`; nothing leaves the machine. Identity
labels (`user_email`, `user_id`, `user_account_*`, `organization_id`) are
stripped at snapshot time and never reach disk. Override the endpoint with
`CSTK_OTEL_ENDPOINT` if you changed the exporter port.

**Multiple Claude Code processes at once? Give each one its own port.** Only
ONE process can bind the fixed port `9464` — the first one launched wins.
Every other process (another terminal tab, another project) fails the bind
silently: its metrics are exposed nowhere, the per-wave snapshots scrape the
*winner's* stale sessions, and the delta guard correctly discards the result —
so `otel_usage` comes out `null` for **every wave** of that execution, with the
panel showing no cost at all. Real case: a two-day-old `claude -c` from an
unrelated project held the port and an entire 16-wave run measured nothing.

The fix is a launcher function in your `~/.zshrc` (or `~/.bashrc`) that asks
the OS for a free port at every launch (binding port `0` lets the kernel pick)
and points the cstk scraper at it via `CSTK_OTEL_ENDPOINT` — hooks and runtime
scripts run inside the Claude process, so they inherit both variables.

> Since v6.9.0 you rarely need to do this by hand: `cstk install` offers this
> wrapper as an **opt-in** on first install (writes it to your shell rc between
> `# >>> cstk telemetry >>>` markers, only with explicit consent — never in
> non-interactive environments), and `cstk help telemetry` prints the canonical
> ready-to-paste block if you declined or want to set it up later.

```zsh
# One OTel exporter per claude process: OS picks a free port at each launch.
claude() {
  local _otel_port
  _otel_port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()' 2>/dev/null)
  if [ -n "$_otel_port" ]; then
    OTEL_EXPORTER_PROMETHEUS_PORT=$_otel_port \
    CSTK_OTEL_ENDPOINT="http://127.0.0.1:${_otel_port}/metrics" \
    command claude "$@"
  else
    command claude "$@"   # no python3: fall back to the fixed default port
  fi
}
```

> **The wrapper is also a hard requirement for loose-usage capture**
> (`cstk usage`, issue #162), not just a multi-process convenience:
> `posttooluse-loose-usage.sh` gates on `CSTK_OTEL_ENDPOINT` and exits `0`
> in silence without it. Unlike the per-wave path — which falls back to the
> fixed default port — loose capture has **no** fallback, so without the
> variable (or an equivalent manual `export`) it stays inert and `cstk usage`
> answers `nao medido`. See
> [docs/cstk-usage.md](./docs/cstk-usage.md#requirements).

Zero per-session configuration: each `claude` you type gets an isolated
exporter and an isolated measurement. As a bonus, the delta's
"exactly-one-session-grew" guard only ever sees that process's sessions, so
ambiguity discards (`null` from concurrent sessions) all but disappear.

> **The wrapper only covers `claude` TYPED in your shell.** It is a shell
> *function*, and `exec` never resolves one — so until v9.4.0 every session
> started by `cstk session start --claude`, `cstk 00c` or the roadmap's
> parallel wave ran with **no** telemetry at all, which is exactly what
> issue #168 measured. Since v9.4.0 those three launchers set the variables
> themselves (one drawn port per process), so they no longer depend on your
> rc, your shell or tmux — and neither does the native-plugin install, which
> provisions no wrapper. Turn that off with `CSTK_TELEMETRY_AUTO=0`; an
> explicit `CSTK_OTEL_ENDPOINT` or `CLAUDE_CODE_ENABLE_TELEMETRY` already in
> the environment also wins. Anything launched outside both paths (IDE,
> desktop app) still uses the fixed default port.

Quick diagnosis when the panel shows no cost for any wave: check who owns the
port and whether its working directory is the project you're actually running:

```bash
lsof -nP -iTCP:9464 -sTCP:LISTEN     # who owns the exporter port?
lsof -p <PID> | grep cwd             # ...and from which project?
```

Or let the runtime decide: `otel-usage.sh preflight` answers "will THIS
session be measured?" deterministically — `status=ok` (exporter owned by an
ancestor of this process), `port-conflict` with the owner's PID and cwd
(exit 3), `exporter-down` (exit 4), `disabled` or `unverified`. The 00c
launcher commands run it in their pre-flight diagnostics and relay any
warning to the operator before wave 001.

**Interactive mode** (numbered selector in a TTY) and **dry-run**:

```bash
cstk install --interactive   # lists numbered profiles + skills; selection via toggle
cstk install --dry-run --profile all
cstk update --dry-run
```

### Plan usage gauge (`cstk statusline` + `cstk plan-usage`)

Since v7.2.0 the toolkit can also capture the plan usage gauge you see in
`/usage` — no OAuth credential, no API key: Claude Code already sends
`rate_limits.five_hour`/`seven_day` in the statusline payload on every
render, so the capture hook just reads what is already passing by and
persists it locally in the `plan_usage` table of
`~/.claude/cstk/knowledge.db`.

```bash
cstk statusline install    # wires the capture hook into ~/.claude/settings.json
cstk statusline status     # is the capture active (and settings.json still valid)?
cstk plan-usage            # latest capture per scope (five_hour / seven_day)
cstk plan-usage history    # time series; reuses --scope/--limit/--since from cstk usage
```

Opt-in by construction — nothing is captured until you run `statusline
install` — and 100% local. An existing custom statusline command is preserved
and chained as a mandatory stdout pass-through, never silently overwritten. A
scope without measurement prints `nao medido` (`null` with `--json`) — never
a fabricated zero.

### Manual installation (deprecated, still supported)

Directly copying the directories still works (`cp -r plugins/cstk/skills/
~/.claude/skills/`), but **does not track versions or detect drift** — see
[`CLAUDE.md`](./CLAUDE.md) §"Installed vs Source Drift". `cstk` solves
this via manifest + hash_dir.

### Complete cstk documentation

- [`cli/README.md`](./cli/README.md) — technical overview, conventions, release process
- [`docs/specs/_archived/cstk-cli/`](docs/specs/_archived/cstk-cli/) — spec, plan, contracts, quickstart
<!-- --8<-- [end:install-section] -->

<!-- --8<-- [start:profiles-section] -->
### Installation profiles (summary)

| Profile | Content | Typical use |
|--------|----------|------------|
| `sdd` | 17 skills: complete Spec-Driven Development pipeline (briefing → review-features) + internal runtime, model-selector and the orchestrators' 4 quality gates | Default global installation |
| `complementary` | 10 independent skills (advisor, bugfix, e2e-integration-flow, etc.) | Complements the SDD pipeline |
| `all` | All 28 skills (sdd + complementary + language-go) | Full installation |
| `language-go` | Go-specific skills + hooks | Only in Go projects |

Default profile when none is given: `sdd`. Details in `cstk install --help`.
<!-- --8<-- [end:profiles-section] -->

## Documentation by topic

| Topic | Document |
|--------|-----------|
| SDD Pipeline: full flow, when to use each skill, shortcuts, living specs | [docs/sdd-pipeline.md](./docs/sdd-pipeline.md) |
| Autonomous orchestrator (agente-00c / feature-00c) | [docs/agente-00c.md](./docs/agente-00c.md) |
| Parallel sessions (`cstk session`) | [docs/cstk-session.md](./docs/cstk-session.md) |
| Roadmap mode + parallel wave of features (post-roadmap offer, notification, next wave) | [docs/agente-00c.md](./docs/agente-00c.md#roadmap-mode-and-parallel-feature-waves) |
| Knowledge memory (`cstk recall`) | [docs/cstk-recall.md](./docs/cstk-recall.md) |
| Loose usage tracking (`cstk usage`) | [docs/cstk-usage.md](./docs/cstk-usage.md) |
| Web panel (`cstk serve`) | [docs/cstk-serve.md](./docs/cstk-serve.md) |
| Go skills and hooks | [docs/go-toolkit.md](./docs/go-toolkit.md) |
| Naming conventions and docs hierarchy | [docs/conventions.md](./docs/conventions.md) |
| Browsable manual (site) | [jotjunior.github.io/cstk](https://jotjunior.github.io/cstk/) |

## Security

cstk ships hooks that intercept tool calls (including one that matches
**all** tools — a passive, silent, always-exit-0 local counter), a Bash
guard that is fail-closed **only during autonomous 00c executions**, and a
CLI that refuses unverified release downloads (sha256 + fixed host
allowlist). Nothing cstk records ever leaves your machine.

What each hook does, what the guard blocks, how release integrity works and
how to report a vulnerability: **[SECURITY.md](./SECURITY.md)**.

## Contributing

Contributions are welcome. The complete guide — the system's mental model,
development flow, versioning policy and the **global toolkit scope principle**
(skills published here must not name specific clients, companies or projects) —
is in [CONTRIBUTING.md](./CONTRIBUTING.md). Summary for adding a skill:

1. Follow the folder structure of an existing skill (see [Anatomy of a skill](#anatomy-of-a-skill))
2. Lean `SKILL.md` as the entry point; heavy content in subfolders
3. **description** as a trigger condition, not a summary
4. **Gotchas** documented — the most valuable content of a skill
5. Scripts in POSIX sh for deterministic operations; every new `.sh` requires `tests/test_<name>.sh`
6. Generalize: if it references something from a specific project, it belongs in `<project>/.claude/skills/`, not in this toolkit
7. Test with Claude Code before submitting

## Versioning

This project follows [Semantic Versioning](https://semver.org/) and keeps a
[CHANGELOG.md](./CHANGELOG.md) with the change history.

## Credits & Attributions

Part of the SDD pipeline is adapted from the [GitHub Spec Kit](https://github.com/github/spec-kit)
(MIT) — in particular the step vocabulary and the constitution template. The
living-specs model with delta requirements was inspired by
[OpenSpec](https://github.com/Fission-AI/OpenSpec). Other skills had conceptual
inspiration from [obra/superpowers](https://github.com/obra/superpowers)
and from Claude Code conventions. Public standards (OWASP, NIST, IETF, W3C,
MITRE) are cited as reference. Details and license notices in
[THIRD-PARTY-NOTICES.md](./THIRD-PARTY-NOTICES.md).

## License

Distributed under the MIT license. See the [LICENSE](./LICENSE) file for the
full text.
