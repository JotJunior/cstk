**English** · [Português (pt-BR)](./README.pt-BR.md)

# Claude Code Toolkit

[![Latest Release](https://img.shields.io/github/v/release/JotJunior/cstk?label=latest%20release&color=blue)](https://github.com/JotJunior/cstk/releases/latest)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](./LICENSE)
[![SemVer](https://img.shields.io/badge/SemVer-5.x-orange.svg)](./CHANGELOG.md)
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
labels are stripped before touching disk. Details, measured numbers and how to
change the port: [Real per-wave cost](#real-per-wave-cost-otel-usagesh).

## Structure

```
├── global/                     # Global skills (language-independent)
│   └── skills/                 # 24 global skills (each skill is a folder)
│       ├── advisor/
│       ├── agente-00c-runtime/ # internal POSIX runtime (not user-invocable)
│       ├── analyze/
│       ├── apply-insights/
│       ├── briefing/
│       ├── bugfix/
│       ├── checklist/
│       ├── clarify/
│       ├── constitution/
│       ├── converge/           # reconciles spec/plan/tasks vs actual code
│       ├── create-tasks/
│       ├── decision-tree/      # ⚠️ DEPRECATED (remove_in 6.0.0) — use cstk-panel (cstk serve)
│       ├── e2e-integration-flow/ # full-stack E2E integration tests (Playwright)
│       ├── execute-task/
│       ├── image-generation/   # ⚠️ DEPRECATED (remove_in 6.0.0) — out of toolkit scope
│       ├── initialize-docs/
│       ├── model-selector/     # model routing heuristic (suggester)
│       ├── owasp-security/
│       ├── plan/
│       ├── review-features/
│       ├── review-task/
│       ├── specify/
│       ├── validate-docs-rendered/
│       └── validate-documentation/
├── language-related/           # Language-specific skills and hooks
│   └── go/                     # Go — ver docs/go-toolkit.md
├── cli/                        # cstk binary + POSIX libs
└── docs/                       # Topic-based documentation (see index below)
```

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

Skills in `global/skills/`, independent of language or framework.

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
| **analyze** | "analyze", "analisar consistência" | Read-only cross-artifact consistency analysis |
| **execute-task** | "executar tarefa", "execute task" | Executes a task following the mandatory 9-step workflow |
| **review-task** | "revisar tarefas", "status das tarefas" | Status report with progress and recommendations |

### Complementary Skills

| Skill | Trigger | Description |
|-------|---------|-----------|
| **advisor** | "me aconselhe", "analise estratégica" | Brutally honest advisor that dissects reasoning and generates action plans |
| **bugfix** | "bugfix", "fix bug", "debug" | Structured multi-layer bug-fixing protocol |
| **converge** | "converge", "o código bate com a spec?" | Reconciles spec/plan/tasks against the CURRENT code and appends gaps as a new task phase. Unconditional gate between execute-task and review-task in the orchestrators |
| **e2e-integration-flow** | "e2e", "playwright", "validar fluxo completo" | Full-stack E2E integration tests (UI → API → database → queue → side effects) |
| **initialize-docs** | "inicializar docs", "setup documentação" | Creates the standard documentation hierarchy with 9 levels |
| **apply-insights** | "aplicar insights", "melhorar claude.md" | Applies proven usage insights to CLAUDE.md, hooks and workflows — see [Usage insights](#usage-insights) |
| **owasp-security** | When reviewing security | Checklist-guided review (OWASP Top 10:2025, ASVS 5.0, LLM/Agentic, NIST, OAuth 2.1...). Does not replace audit/pentest |
| **review-features** | "status global", "comparar features" | Cross-feature report suggesting archive/abandon/prioritize; the archive action applies deltas to the living-specs corpus |
| **validate-documentation** | "validar documentação", "verificar UC" | Validates individual documents against structural standards |
| **validate-docs-rendered** | "validar renderização", "verificar diagramas" | Validates that the Markdown renders (Mermaid, links, frontmatter, tables) |
| **image-generation** | When generating images | ⚠️ DEPRECATED (remove_in 6.0.0) |

## Advanced track (autonomous orchestrator)

> **Experimental** — functional and in use by the maintainer, with no support
> guarantees for external adoption.

`/agente-00c` drives the entire SDD pipeline over a target project, pausing
only on real blockers; `/feature-00c` does the same for ONE feature in an
existing project. Subsystems: per-wave model routing, atomic-commit mode
(automatic commits + push/PR at finalize), enforced guards (fail-closed hook),
parallel sessions in worktrees, and cross-feature knowledge memory consulted
before deciding.

| Topic | Document |
|--------|-----------|
| `/agente-00c` + `/feature-00c` orchestrators, model-routing, atomic-commit, guards | [docs/agente-00c.md](./docs/agente-00c.md) |
| Parallel sessions (`cstk session`) | [docs/cstk-session.md](./docs/cstk-session.md) |
| Knowledge memory (`cstk recall`) | [docs/cstk-recall.md](./docs/cstk-recall.md) |
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
cstk install --profile all           # installs ALL 31 skills (includes language-go)
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
| `complementary` | 13 independent skills (advisor, bugfix, e2e-integration-flow, etc.) | Complements the SDD pipeline |
| `all` | All 31 skills (sdd + complementary + language-go) | Full installation |
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

### 00c runtime hooks (`cstk hooks`)

The three 00c runtime hooks — `pretooluse-bash-guard.sh` (fail-closed Bash
guard), `posttooluse-tool-call-tick.sh` and `posttooluse-agent-usage.sh`
(per-wave metrics) — only run in a target project once they are copied into
`.claude/hooks/` **and** registered in `.claude/settings.json`.

`cstk install --scope project agente-00c-runtime` does that, but it also
copies the skill, 6 commands and 7 agents into the repo. When you only want
the hooks, use:

```bash
cd ~/projects/my-target-project
cstk hooks install                    # touches .claude/hooks/ + settings.json only
cstk hooks install --dry-run          # show the plan without writing
cstk hooks install --project-path ../other-project
```

Without this step the Bash guard is inert and `tool_calls`/`agent_usage`
stay at zero for every wave. To check the current state without writing
anything:

```bash
guard-hooks-status.sh check --projeto-alvo-path .
```

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

**Interactive mode** (numbered selector in a TTY) and **dry-run**:

```bash
cstk install --interactive   # lists numbered profiles + skills; selection via toggle
cstk install --dry-run --profile all
cstk update --dry-run
```

### Manual installation (deprecated, still supported)

Directly copying the directories still works (`cp -r global/skills/
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
| `complementary` | 13 independent skills (advisor, bugfix, e2e-integration-flow, etc.) | Complements the SDD pipeline |
| `all` | All 31 skills (sdd + complementary + language-go) | Full installation |
| `language-go` | Go-specific skills + hooks | Only in Go projects |

Default profile when none is given: `sdd`. Details in `cstk install --help`.
<!-- --8<-- [end:profiles-section] -->

## Documentation by topic

| Topic | Document |
|--------|-----------|
| SDD Pipeline: full flow, when to use each skill, shortcuts, living specs | [docs/sdd-pipeline.md](./docs/sdd-pipeline.md) |
| Autonomous orchestrator (agente-00c / feature-00c) | [docs/agente-00c.md](./docs/agente-00c.md) |
| Parallel sessions (`cstk session`) | [docs/cstk-session.md](./docs/cstk-session.md) |
| Knowledge memory (`cstk recall`) | [docs/cstk-recall.md](./docs/cstk-recall.md) |
| Web panel (`cstk serve`) | [docs/cstk-serve.md](./docs/cstk-serve.md) |
| Go skills and hooks | [docs/go-toolkit.md](./docs/go-toolkit.md) |
| Naming conventions and docs hierarchy | [docs/conventions.md](./docs/conventions.md) |
| Browsable manual (site) | [jotjunior.github.io/cstk](https://jotjunior.github.io/cstk/) |

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
