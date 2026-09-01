**English** · [Português (pt-BR)](./cstk-serve.pt-BR.md)

# Web panel (`cstk serve`)

Starts the cstk panel web interface locally. The panel is distributed as part
of the [JotJunior/cstk](https://github.com/JotJunior/cstk) releases (package
`panel/` in this same repository) — it no longer has a separate repository.
On first run, it automatically downloads the panel asset from the latest
`cstk` release and installs it in `~/.local/share/cstk/panel`. Subsequent
runs reuse the cached installation.

`cstk serve` builds the workspaces (`npm run build` — shared-types, server, and
web) and then starts a **single Fastify process** (`npm run start`) that serves
the **API and the built SPA** (`apps/web/dist`) on the **same port**. There is
no dev mode nor Vite proxy. Open **http://127.0.0.1:5173** (or the `--port` port)
in the browser. Requires `cstk-panel >= 0.2.0`.

**Dependencies**: `curl` always; `npm` and `node` (Node.js) only in native mode
(default). With `--docker` (below), `npm`/`node` are **not** required on the
host: you only need Docker Engine/Desktop installed **and** the daemon running.

```bash
cstk serve                      # builds and starts the panel (API + SPA on the same port)
cstk serve --update             # updates the panel if there is a new release, then starts
cstk serve --reinstall          # removes and reinstalls from scratch, then starts
cstk serve --docker             # runs the panel in a local Docker container (no npm/node on host)
```

## Options

| Flag | Default | Description |
|------|---------|-------------|
| `--update` | — | Queries GitHub and reinstalls the panel **only** if there is a newer release (best-effort: a network/API failure keeps the installed version). With `--docker`, rebuilds the local **image**. |
| `--reinstall` | — | Removes the existing installation and reinstalls from GitHub (unconditional; wins over `--update`). With `--docker`, rebuilds the **image** from scratch. |
| `--port PORT` | `5173` | Port the Fastify server listens on (integer 1024–65535; also reads `$PORT`). |
| `--host HOST` | `127.0.0.1` | Bind host (only loopback is fully supported). |
| `--docker` | — | Runs the panel inside a local Docker container (opt-in; absent = native behavior 100% preserved). |
| `--help`, `-h` | — | Prints help and exits. |

## Environment variables

- `CSTK_PANEL_DIR` — Overrides the installation directory (default:
  `~/.local/share/cstk/panel`).
- `PORT` — Default port when `--port` is not provided.
- `CSTK_KNOWLEDGE_DB` — Path to `knowledge.db`; with `--docker`, the
  **directory** of this file is mounted read-only in the container
  (default: `~/.claude/cstk/knowledge.db`).
- `CSTK_PANEL_REPO` — Overrides the source repository of the panel release
  (`owner/repo` format only; the host stays fixed at `api.github.com`).
  Intended for forks/rehearsals, same override pattern as `CSTK_REPO` in
  `cstk install`/`cstk self-update` (default: `JotJunior/cstk`). A non-default
  value is audited: a warning is printed to stderr and logged to
  `.claude/enforcement-log.jsonl`.

**Exit codes**: `0` success · `1` general error (missing prereq, download/build
failed, corrupted installation; with `--docker` also: Docker missing/daemon
unreachable, image build failed, unreconcilable leftover container) ·
`2` usage error (invalid port, unknown flag).

**Security**: only URLs from `api.github.com`, `github.com`,
`codeload.github.com`, `objects.githubusercontent.com`, and
`release-assets.githubusercontent.com` are authorized for the download (SSRF
allowlist). The allowlist is re-checked on **every redirect hop**, not just on
the initial URL: the download walks the chain one hop at a time and refuses a
`Location` pointing outside the list before issuing any request to it. Integrity is **fail-closed by default**: a package
without `.sha256` blocks (`unverifiable-blocked`); explicit and audited bypass
via `--allow-unverified`/`CSTK_SERVE_ALLOW_UNVERIFIED=1`; a checksum mismatch
always blocks. Host `127.0.0.1` is the only fully supported one.

## Docker mode (`cstk serve --docker`)

Runs the panel inside a **local Docker container** instead of natively on the
host — useful when `npm`/`node` are not available (or not wanted) on the machine.

**Prerequisites**: Docker Engine or Docker Desktop installed **and** the daemon
running. Both are checked before any network access, with distinct messages for
"Docker not installed" vs "daemon stopped/unreachable".

**What happens**: on the first run (or on `--reinstall`, or on `--update` when
there is a new release), it builds a local image (`cstk-panel:<version>`,
**never** published to a registry) from the same verified source tree used in
native mode — same fail-closed integrity mechanism. Subsequent builds reuse the
already-built image. The container runs with hardening by default (non-root user,
`--cap-drop ALL`, `--security-opt no-new-privileges`, read-only rootfs) and a
deterministic name (`cstk-panel`) — a leftover container from a previous run is
automatically reconciled.

**Data parity with native mode**: the `~/.claude/cstk/` directory (or the
directory of `$CSTK_KNOWLEDGE_DB`, if set) is mounted **read-only** inside the
container — the containerized panel reads the **same** `knowledge.db` as native
mode, byte for byte. Concurrent writes on the host become visible on the next
request, **without needing to restart** the container.

`Ctrl+C` shuts down the container gracefully (`docker stop`, same grace period
as native mode). Full details:
[`specs/panel-docker/spec.md`](./specs/panel-docker/spec.md).
