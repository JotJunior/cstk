# Privacy Policy — cstk

**Effective date:** 2026-08-08 · **Applies to:** the `cstk` and `cstk-language-go`
Claude Code plugins, and the `cstk` command-line tool.

## Summary

**cstk collects no personal data, has no servers, and sends nothing anywhere.**
It is a local toolkit: every artifact it produces stays on the machine that ran
it. There is no account, no analytics, no telemetry upload, and no
phone-home — including for crash reports or usage statistics.

## What cstk writes, and where

All of it is local to your machine. Nothing is transmitted.

| Data | Location | Purpose |
|------|----------|---------|
| Execution state (waves, decisions, task outcomes, human blocks) | `<project>/.claude/agente-00c-state/` and `<project>/.claude/feature-00c-state/` | Lets an autonomous run be paused, audited and resumed |
| Knowledge index (decisions, blocks, retrospectives, skills used, memories) | `~/.claude/cstk/knowledge.db` (SQLite) | Lets past runs inform new work (`cstk recall`) |
| Guard decisions (allowed/blocked commands) | `<project>/.claude/enforcement-log.jsonl` | Audit trail for the enforced Bash guard |
| Loose usage counters (tokens/cost of interactive sessions) | `~/.claude/cstk/loose-usage/` | **Opt-in only** (`cstk hooks install --with-loose-usage`); off by default |
| Documentation artifacts (specs, plans, checklists, task backlogs) | `<project>/docs/` | The deliverables you asked the toolkit to produce |

Everything above lives in ordinary files you own. Delete the directories and the
data is gone; nothing is retained elsewhere.

## Secret handling

Content captured into state files, logs and the knowledge index is passed
through a redaction filter (`secrets-filter.sh`) before being written. It
targets common credential shapes — API keys and tokens, private key blocks,
and basic-auth credentials embedded in URLs — replacing them with `[REDACTED]`.

This reduces exposure but is **not a guarantee**: a secret in an unusual format
may not be recognized. Treat `.claude/` state directories as you would any local
working file — do not commit them to a public repository without reviewing them.

## Network access

The plugin makes **no outbound network requests**. Its only HTTP call targets
`http://127.0.0.1` — the local OpenTelemetry metrics endpoint exposed by your own
Claude Code process, used to measure the cost of a run. That endpoint binds to
loopback; nothing leaves the machine, and this measurement is opt-in (it does
nothing unless you enable telemetry yourself).

The `cstk` command-line tool reaches the network only when **you explicitly run
an install or update command** (`cstk install`, `cstk update`, `cstk self-update`,
`cstk serve`). Those download release artifacts from GitHub, restricted to an
allowlist of trusted hosts and verified by SHA-256 checksum. No data about you or
your projects is sent as part of those requests.

If you enable the optional MCP state server, it runs as a Docker container on
your machine, mounting only that run's own state directory. It exposes no
external port.

## Third parties

cstk has no third-party integrations, no advertising, and no data processors.

Note the boundary: cstk runs *inside* Claude Code, and Claude Code sends your
conversation to Anthropic in order to work. That data flow is governed by
[Anthropic's Privacy Policy](https://www.anthropic.com/legal/privacy) and exists
whether or not cstk is installed — cstk neither adds to it nor has access to it.
Likewise, if a skill you invoke asks Claude Code to call an external service
(for example, `gh` to open a pull request), that request is made by that tool
under its own terms.

## Children

cstk is a developer tool and is not directed at children under 13.

## Changes

Changes to this policy are published in this file, in the repository's public
history. The effective date above reflects the most recent revision.

## Contact

Questions or concerns: open an issue at
<https://github.com/JotJunior/cstk/issues>.
