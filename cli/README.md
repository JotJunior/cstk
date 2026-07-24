**English** · [Português (pt-BR)](./README.pt-BR.md)

# cstk — Claude Specs Toolkit CLI

A POSIX sh CLI to install, update and audit the toolkit's skills. This directory
contains the CLI's source code; the full design documentation lives in
[`../docs/specs/cstk-cli/`](../docs/specs/_archived/cstk-cli/).

**Current status**: PHASES 0-9.2 of the backlog complete — all subcommands
(`install`, `update`, `self-update`, `list`, `doctor`, `serve`) implemented and
tested, with an automated release pipeline. Pending: PHASES 9.3 (coverage check),
10 (end-to-end integration tests) and 11 (docs + first public release).

## Layout

```
cli/
├── cstk         # main executable (POSIX sh)
├── VERSION      # version tag (dev: "0.0.0-dev"; release: filled in by the build)
├── lib/         # modular libraries per subcommand
└── README.md    # this file
```

## Dev usage (before a release)

```sh
# From the repo root:
./cli/cstk --version        # → cstk 0.0.0-dev
./cli/cstk --help
./cli/cstk help install     # points to the contract
```

## Installation via one-liner

Once a public release is available, install `cstk` on a new machine with:

```sh
curl -fsSL https://github.com/JotJunior/cstk/releases/latest/download/install.sh | sh
```

The bootstrap downloads the latest release tarball, validates the SHA-256
(FR-010a), copies `cstk` to `~/.local/bin/` and `cli/lib/` to
`~/.local/share/cstk/lib/`. After that:

```sh
cstk --version           # confirms installation
cstk install             # installs the sdd profile into ~/.claude/skills/
cstk self-update         # updates its own binary when a new release exists
```

## Release process

The pipeline in [`.github/workflows/release.yml`](../.github/workflows/release.yml)
publishes releases automatically when a SemVer tag is pushed.

```sh
# Local: create and push the tag
git tag -a v0.1.0 -m "cstk v0.1.0"
git push origin v0.1.0
```

The pipeline (on `ubuntu-latest`):

1. Validates the tag format (`vX.Y.Z[-suffix]`)
2. Runs `./tests/run.sh` (global suite) — failure aborts the release
3. Runs each `tests/cstk/test_*.sh` — failure aborts the release
4. Executes `./scripts/build-release.sh <tag>` (deterministic build —
   see [scripts/build-release.sh](../scripts/build-release.sh))
5. Creates the GitHub Release via `gh release create`, uploading:
   - `cstk-<bare-version>.tar.gz`
   - `cstk-<bare-version>.tar.gz.sha256`
   - `cli/install.sh` (standalone asset for the one-liner)

Release notes are generated automatically by `gh release create
--generate-notes` (list of PRs/commits since the last tag).

**Re-running an already-published release fails** — `gh release create` does not
overwrite. To fix it, delete the release in the GitHub UI and re-push the tag (or
use a new tag, preferred).

## Subcommands

| Subcommand | Description | Lib |
|------------|-----------|-----|
| `install` | Installs profiles/skills into `~/.claude/` | `lib/install.sh` |
| `update` | Applies new releases while preserving local edits | `lib/install.sh` |
| `self-update` | Updates the `cstk` binary + `cli/lib/` | `lib/self-update.sh` |
| `list` | Lists installed skills + status | `lib/list.sh` |
| `doctor` | Detects drift between manifest and disk | `lib/doctor.sh` |
| `session` | Creates/lists/ends sessions with an isolated worktree | `lib/session.sh` |
| `recall` | Cross-feature memory: search/ingest/reindex | `lib/recall.sh` |
| `serve` | Starts the local web panel (lazy-install + npm start) | `lib/serve.sh` |

### `cstk serve`

Downloads and runs the cstk panel web interface. On the first run it queries the
GitHub Releases API, downloads the latest tarball from `JotJunior/cstk-panel`,
extracts it and runs `npm install`. Subsequent runs reuse the cache (no
download).

```sh
cstk serve                   # starts on the default port 5173
cstk serve --port 8080       # custom port
cstk serve --reinstall       # force reinstall
PORT=4000 cstk serve         # port via environment variable
```

Options: `--port PORT` (1024-65535), `--host HOST` (default: 127.0.0.1),
`--reinstall`, `--help`. Override the directory via `$CSTK_PANEL_DIR`.

## Conventions

- POSIX sh: `#!/bin/sh`, `set -eu`, no bash-isms (Constitution 1.1.0 §II).
- Data output on stdout; human messages + summaries on stderr.
- Exit codes: 0 OK, 1 general error, 2 usage, 3 lock, 4 local edit, 10 check-available.
- `$CSTK_LIB` override locates lib/ during tests.
- `$CSTK_VERSION_FILE` override locates VERSION during tests.

## Development

See [`../docs/specs/cstk-cli/tasks.md`](../docs/specs/_archived/cstk-cli/tasks.md) for
the backlog. Running tests:

```sh
sh tests/cstk/test_cstk-main.sh    # direct (PHASE 1.1)
./tests/run.sh cstk                # via the suite (after PHASE 9.3.1)
```
