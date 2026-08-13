# Security Policy

cstk installs hooks that intercept tool calls, a CLI that downloads release
tarballs, and an autonomous orchestrator that edits a target project. Each of
those is a legitimate reason to ask "what exactly does this run on my
machine?" — this document answers that, with pointers to the enforcing code.

## Reporting a vulnerability

Open an issue at <https://github.com/JotJunior/cstk/issues>. For reports that
should not be public (e.g. an exploitable flaw in the guard hooks or in the
release-integrity path), open the issue **without** technical details and ask
for a private channel; the maintainer will follow up.

## Security model at a glance

- **Local-first, zero remote collection.** Everything cstk records (execution
  state, metrics, knowledge index) stays on your machine. The toolkit has no
  telemetry endpoint of its own and never uploads state, reports or metrics.
- **Fail-closed where it matters.** Release-integrity checks and the Bash
  guard block on failure instead of warning-and-proceeding — including when
  the check mechanism itself breaks.
- **Defense in depth, not a sandbox.** The guard hooks add a deterministic
  enforcement layer on top of Claude Code's own permission system. They do
  not replace it, and cstk does not claim to confine a malicious model — it
  confines the *documented failure modes* of autonomous runs.

## The three guard hooks

Registered by `cstk hooks install` (classic path) or shipped inside the
plugin (`plugins/cstk/hooks/hooks.json`). Source lives under
`plugins/cstk/skills/agente-00c-runtime/hooks/`.

| Hook | Event / matcher | What it does |
|------|-----------------|--------------|
| `pretooluse-bash-guard.sh` | `PreToolUse` / `Bash` | Delegates every Bash command to `bash-guard.sh check` **only while an autonomous 00c execution is active** (state with `status: em_andamento`). Outside an active execution it exits `0` and interferes with nothing. Violations block the command; a failure of the guard mechanism itself (missing `jq`, unreadable script, invalid stdin) **also blocks** (`MECANISMO_FALHOU`), never silently passes. |
| `posttooluse-tool-call-tick.sh` | `PostToolUse` / `*` | Appends one line to a local sidecar file so each wave can report its real `tool_calls` count. It matches `*` because its whole job is counting **every** tool call — a narrower matcher would undercount. It writes only to the sidecar (never to `state.json`/`state.db`), emits nothing on stdout/stderr and always exits `0`; it cannot block or alter any tool call. |
| `posttooluse-agent-usage.sh` | `PostToolUse` / `Agent` | Records per-subagent token usage to a local sidecar for per-wave cost metrics. Same contract: sidecar-only, silent, always exit `0`. |

Directory hubs flag the `*` matcher as a critical signal — correctly, as a
prompt to read what the hook does. The answer here: it is a passive local
counter with an empty-output/always-zero-exit contract, enforced by its test
suite (`tests/test_posttooluse-tool-call-tick.sh`).

### What the Bash guard blocks

During an active autonomous execution, `bash-guard.sh` blocks (among others):
`git push` (raw push stays blocked even in atomic-commit mode; push happens
only through the confined `finalize` path), `git reset --hard`,
`git clean -f`, recursive+forced `rm` against `~`, `$HOME`, `..` or `.git`,
`kubectl apply`, `terraform apply/destroy`, `docker push`, `helm
install/upgrade`, mutating cloud CLIs, and network commands
(`curl`/`wget`/`gh`/`git fetch|clone`) whose host is not on the execution's
URL whitelist. Every decision — allow or block — is appended as a line to
`<target-project>/.claude/enforcement-log.jsonl`, with the command scrubbed
by `secrets-filter.sh` **before** being truncated and written.

## Release & supply-chain integrity

- **Checksum, fail-closed.** `cstk serve` refuses to install a downloaded
  panel package without its `.sha256` (`unverifiable-blocked`); a checksum
  mismatch always blocks, with no bypass flag. The explicit bypass for the
  *missing*-checksum case (`--allow-unverified`) prints a high-visibility
  warning and is audited to the same enforcement log.
- **Fixed host allowlist.** `cli/lib/trusted-hosts.sh` defines
  `CSTK_TRUSTED_RELEASE_HOSTS` as a constant that env vars cannot override.
  Matching is exact and case-insensitive with userinfo stripped first —
  `github.com.evil.com` and `user@evil.com` lookalikes (CWE-290) do not
  match. `install`, `self-update` and `serve` all check the host **before**
  any download; plain `http://` is rejected.
- **Two delivery paths, comparable but distinct guarantees.** The classic
  path (`curl | sh` + `cstk install`) is protected by the checksum + host
  allowlist above, applied by cstk's own code. The native plugin path is
  pinned by the Claude Code harness via the marketplace repo's git commit
  SHA and installed only after the harness's own consent dialog. Neither
  path is claimed to be identical to the other — see
  `docs/specs/claude-plugin-packaging/` for the honest comparison table.

## Data handling

- **Execution state** lives inside the target project
  (`.claude/agente-00c-state/`, `.claude/feature-00c-state/`). Wave backups
  pass through `secrets-filter.sh` before touching disk.
- **Knowledge index** (`~/.claude/cstk/knowledge.db`) is a derived, purely
  local SQLite index; content is scrubbed at ingestion and the whole base is
  reconstructible from local state (`cstk recall --reindex`).
- **Cost/token metrics (OTel)** are opt-in via environment variables. The
  Prometheus exporter binds `127.0.0.1` only, and identity labels are
  stripped before anything is written to disk. Absent measurements stay
  `null` — never a fabricated zero.
- **Loose-usage capture** (consumption outside orchestrator runs) is a
  separate opt-in (`cstk hooks install --with-loose-usage`); it is never
  bundled silently with the guard hooks, and its sidecar files are written
  with restrictive permissions (`700`/`600`) with a retention TTL and a
  `prune` command.

## MCP state server confinement

The optional `cstk mcp` layer runs one Docker container per execution:

- The container mounts **only** that execution's state dir, the runtime
  scripts (read-only) and that execution's enforcement log — never another
  execution's state, never `knowledge.db`.
- Every tool call must present the execution's capability token (≥128-bit
  CSPRNG, stored in the state dir). Missing/mismatched/terminal-execution
  tokens are rejected fail-closed (`SESSION_MISMATCH`) — there is no
  fallback to "the most likely active execution".
- The Node→POSIX boundary uses `execFile` with argv arrays; no free-text
  field ever reaches a shell.
- Docker unavailable degrades to the plain Bash path with none of the above
  — the MCP layer adds confinement, it is not the source of it.

## Autonomous orchestrator blast radius

Orchestrator writes are confined to the target project directory. The single
sanctioned external side effect is `gh issue create` against this repository
(automatic bug reports for toolkit defects), and the project's constitution
(Principle VI) forbids fabricated factual data in any generated artifact —
missing data becomes a human block, not a plausible guess.

## Scope and non-goals

- The guard hooks act only during active 00c executions; your interactive
  sessions are untouched.
- Hook copies under `.claude/hooks/` are snapshots: re-run
  `cstk hooks install` after upgrades that touch them, and audit state with
  `guard-hooks-status.sh check` (a stale guard is as bad as a missing one).
- This is not a substitute for reviewing what you install. The relevant
  code is small and deliberately POSIX-plain: start at
  `plugins/cstk/skills/agente-00c-runtime/scripts/bash-guard.sh` and
  `plugins/cstk/hooks/hooks.json`.
