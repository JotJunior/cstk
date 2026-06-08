# Feature Specification: Plugin System for cstk

**Feature**: `cstk-plugins`
**Created**: 2026-06-08
**Status**: Draft

## Context

The cstk toolkit ships skills and runtime scripts via a single curated catalog
(`~/.claude/skills/`). A community PR adapting skills for a different LLM
(Codex) was declined for merge into the main repo — the maintainer does not
want third-party LLM adaptations or language-specific skill bundles in the
core catalog.

This feature introduces a **plugin system** that lets external repositories
(following the naming convention `cstk-plugin-<name>`) be installed, validated,
and activated alongside the core toolkit, without merging their content into the
main repo. Security is ensured by a manifest + checksum scheme verified at
install time and optionally at activation time.

## User Scenarios & Testing

### User Story 1 — Install a Plugin from a Remote Repository (Priority: P1)

A developer wants to use Codex-adapted skills with the cstk pipeline. They run
`cstk plugin-add codex`, which fetches the plugin from the well-known repository
`cstk-plugin-codex`, verifies the manifest and checksum, and installs it into
the user-local plugin store. After installation the developer can invoke the
pipeline with `--llm codex` to use the installed skills.

**Why this priority**: This is the primary motivation for the feature. Without
this story nothing else in the plugin system has value.

**Independent Test**: With internet access (or a local mirror), run
`cstk plugin-add codex`; verify that
`~/.claude/plugins/codex/manifest.json` exists, checksum matches, and skills
are installed under `~/.claude/skills/` (or equivalent plugin directory).

**Acceptance Scenarios**:

1. **Given** no plugin named `codex` is installed, **When** the user runs
   `cstk plugin-add codex`, **Then** the toolkit resolves the canonical
   repository URL for `cstk-plugin-codex`, downloads the plugin bundle,
   verifies the manifest signature and checksum, and reports success with the
   installed version.

2. **Given** the download succeeds but the checksum does not match the manifest,
   **When** the install process validates integrity, **Then** the plugin is
   rejected, no files are written to the plugin store, and the user receives a
   clear error identifying the mismatch.

3. **Given** a plugin named `codex` is already installed at version X, **When**
   the user runs `cstk plugin-add codex` again, **Then** the toolkit reports
   the currently installed version and asks for confirmation before overwriting
   (or accepts a `--force` flag to skip the prompt).

4. **Given** the remote repository is unreachable, **When** the user runs
   `cstk plugin-add codex`, **Then** the toolkit exits with a clear network
   error and no partial state is written to the plugin store.

---

### User Story 2 — Run the 00c Pipeline with a Specific LLM Plugin (Priority: P2)

A developer has installed the `codex` plugin. They want to run the full SDD
pipeline (feature-00c or agente-00c) using Codex-adapted skills instead of the
default Claude skills. They invoke the pipeline with `--llm codex`.

**Why this priority**: This is the integration point between the plugin system
and the existing pipeline. Without it, installed plugins are inert.

**Independent Test**: With the `codex` plugin installed, invoke any pipeline
entrypoint with `--llm codex`; verify the pipeline loads skills from the plugin
directory rather than the core catalog for the skills that the plugin overrides.

**Acceptance Scenarios**:

1. **Given** the `codex` plugin is installed and provides a `specify` skill
   override, **When** the user starts the pipeline with `--llm codex`,
   **Then** the pipeline uses the plugin's `specify` skill for all skill
   dispatches that the plugin declares, and falls back to the core catalog for
   skills the plugin does not override.

2. **Given** no `--llm` flag is supplied, **When** the user starts any pipeline
   entrypoint, **Then** the pipeline behaves exactly as today (default `claude`
   routing — no behavior change).

3. **Given** `--llm codex` is supplied but the `codex` plugin is not installed,
   **When** the pipeline starts, **Then** it exits immediately with a clear
   error message pointing the user to `cstk plugin-add codex`.

4. **Given** `--llm codex` is supplied and the plugin is installed but its
   manifest checksum fails re-validation at activation time, **When** the
   pipeline starts, **Then** it refuses to activate the plugin and exits with
   an integrity error.

---

### User Story 3 — Manage Installed Plugins (Priority: P3)

A developer wants to audit which plugins are installed, check their versions and
integrity status, and remove a plugin they no longer use.

**Why this priority**: Operational hygiene — without list/remove, the plugin
store becomes unauditable accumulation. Lower priority than install+activate
because the system is still usable without it.

**Independent Test**: After installing one or more plugins, run `cstk plugin-list`
and verify each installed plugin appears with its name, version, and integrity
status. Then run `cstk plugin-remove codex` and verify the plugin is gone from
the store and `cstk plugin-list` no longer shows it.

**Acceptance Scenarios**:

1. **Given** two plugins are installed, **When** the user runs
   `cstk plugin-list`, **Then** each plugin is shown with its name, installed
   version, declared plugin type (llm | lang), and current integrity status
   (ok | tampered | unknown).

2. **Given** a plugin's files have been modified since install, **When** the
   user runs `cstk plugin-list`, **Then** that plugin's status is shown as
   `tampered` (checksum re-verification failed).

3. **Given** a plugin named `codex` is installed, **When** the user runs
   `cstk plugin-remove codex`, **Then** all plugin files and the manifest
   entry are removed from the plugin store and the user receives a confirmation
   message.

4. **Given** no plugins are installed, **When** the user runs `cstk plugin-list`,
   **Then** the command exits 0 with a message indicating no plugins are
   installed (not an error).

---

### User Story 4 — Install a Language Plugin (Priority: P4)

A developer working in a .NET project installs the `lang-dotnet` plugin, which
provides `.NET`-specific skills (e.g., go-add-entity equivalent for .NET). The
install and validation flow is identical to the LLM plugin flow.

**Why this priority**: Validates that the plugin type system is extensible
beyond LLM adapters. Lower priority because the LLM plugin type (P1–P2)
must be proven first.

**Independent Test**: Run `cstk plugin-add lang-dotnet`; verify the plugin
installs and `cstk plugin-list` shows type `lang` for it.

**Acceptance Scenarios**:

1. **Given** no `lang-dotnet` plugin is installed, **When** the user runs
   `cstk plugin-add lang-dotnet`, **Then** the installation, manifest
   validation, and checksum verification flow is identical to the LLM plugin
   (P1) — same security guarantees, same error handling.

2. **Given** the `lang-dotnet` plugin is installed, **When** the user runs
   `cstk plugin-list`, **Then** it appears with `type: lang`.

---

### Edge Cases

- What happens when `plugin-add` is invoked without network access and no local
  cache exists? → Clear error, no partial state written, exit non-zero.
- What happens when the plugin repository name contains path traversal characters
  (e.g., `../evil`)? → The toolkit must reject names that do not match the
  `^[a-z][a-z0-9-]{0,63}$` pattern before any filesystem or network operation.
- What happens when two plugins both provide the same skill override and
  `--llm` selects one of them? → Only the selected plugin's skill is active;
  the other plugin's override is ignored for that invocation.
- What happens when a plugin manifest declares a schema version the toolkit does
  not understand? → Reject with a clear "unsupported manifest version" error and
  suggest updating the toolkit.
- What happens when `plugin-remove` is called while a pipeline is running with
  `--llm <plugin>`? → The running pipeline is not interrupted (skills already
  loaded into context). The plugin store entry is removed; the pipeline finishes
  with the in-memory skills.

## Requirements

### Functional Requirements

**Plugin discovery and naming**

- **FR-001**: The toolkit MUST derive the canonical repository URL for a plugin
  named `<name>` from the pattern `cstk-plugin-<name>` using a configurable
  hosting base. The default base is `https://github.com/JotJunior/` (maintainer's
  namespace). Users MAY override the base via the environment variable
  `CSTK_PLUGIN_REGISTRY` (e.g., `CSTK_PLUGIN_REGISTRY=https://github.com/myorg/`)
  or via a local config file (`~/.cstk/config`, POSIX sh key=value format).
  When the override is set, the toolkit fetches from
  `<base>/cstk-plugin-<name>` instead of the default. The default base is
  always used when neither override is present.

- **FR-002**: Plugin names MUST match the pattern `^[a-z][a-z0-9-]{0,63}$`.
  Any `plugin-add` or `plugin-remove` invocation with a name that fails this
  pattern MUST be rejected before any filesystem or network operation.

**Security: manifest and checksum**

- **FR-003**: Every plugin repository MUST contain a `plugin-manifest.json` at
  its root, declaring at minimum: `name`, `version`, `type` (`llm` | `lang`),
  `schema_version`, and a `sha256` checksum of the plugin bundle (the set of
  files delivered by the plugin, excluding the manifest itself).

- **FR-004**: The toolkit MUST verify the bundle checksum against the manifest
  `sha256` field before writing any plugin file to the plugin store. A checksum
  mismatch MUST abort the install, remove any partial downloads, and exit
  non-zero.

- **FR-005**: The toolkit MUST re-verify the checksum of an installed plugin's
  files at activation time (`--llm <name>` or `plugin-list` integrity check).
  An activation-time mismatch MUST block the pipeline from loading the plugin
  and report a `tampered` status.

- **FR-006**: Network access for `plugin-add` MUST be initiated only when the
  user explicitly invokes the command — never as a background or automatic
  update. (Upholds Constitution Principle IV: zero remote collection.)

**Installation**

- **FR-007**: Installed plugins MUST be stored under a user-local directory
  (default: `~/.claude/plugins/<name>/`). The toolkit MUST NOT write plugin
  files into the core catalog (`~/.claude/skills/`) to avoid conflating plugin
  content with toolkit-shipped content.

  When `--llm <name>` activates a plugin, skill resolution uses **path-prepending**:
  the pipeline dispatcher consults the plugin's skills directory
  (`~/.claude/plugins/<name>/skills/`) first for each skill lookup, falling
  back to the core catalog (`~/.claude/skills/`) for skills the plugin does
  not provide. No files are copied or symlinked into `~/.claude/skills/`; the
  core catalog remains immutable during plugin activation.

- **FR-008**: The installation MUST be atomic: files are staged in a temporary
  directory and moved to the final location only after checksum verification
  passes. On failure or interruption the temporary directory is cleaned up and
  the plugin store is left unchanged.

- **FR-009**: If a plugin with the same name is already installed, `plugin-add`
  MUST inform the user and require explicit confirmation (interactive prompt or
  `--force` flag) before overwriting.

**CLI subcommands**

- **FR-010**: The toolkit MUST expose three new subcommands: `plugin-add <name>`,
  `plugin-remove <name>`, and `plugin-list`. These MUST follow the existing
  dispatch convention (`cli/lib/<subcommand>.sh` with a `<subcommand_main>`
  function).

- **FR-011**: `plugin-list` MUST display, for each installed plugin: name,
  version, type, and integrity status (ok | tampered | unknown). Output MUST
  be human-readable (plain text); machine-readable output (e.g., JSON) is
  out of scope for this feature.

- **FR-012**: `plugin-remove <name>` MUST remove all files under
  `~/.claude/plugins/<name>/` and update the local plugin registry. It MUST
  exit non-zero if the named plugin is not found, with a clear error.

**Pipeline integration (`--llm` flag)**

- **FR-013**: The `feature-00c` and `agente-00c` pipeline entrypoints MUST
  accept a `--llm <name>` flag (default: `claude`). When `--llm claude` (or no
  flag), behavior is identical to today.

- **FR-014**: When `--llm <name>` is set and the named plugin is installed,
  the pipeline MUST resolve skill paths by consulting the plugin's skill
  directory first, falling back to the core catalog for skills the plugin does
  not override.

- **FR-015**: When `--llm <name>` is set and the named plugin is not installed,
  the pipeline MUST exit immediately (before creating any state) with a clear
  message: "Plugin '<name>' not installed — run `cstk plugin-add <name>` first."

- **FR-016**: The `--llm` flag value MUST be recorded in the pipeline's
  `state.json` (field `execution.llm_plugin`) for auditability and resumability.
  On resume, if the recorded plugin is no longer installed or fails integrity
  check, the pipeline MUST surface a human block.

**Constitution compliance**

- **FR-017**: All new scripts (`cli/lib/plugin-add.sh`, `plugin-remove.sh`,
  `plugin-list.sh`, `cli/lib/plugin-common.sh`) MUST be POSIX sh (`#!/bin/sh`,
  `set -eu`, no Bash-isms, no mandatory external tools beyond POSIX canon).
  `sha256sum` (or `shasum -a 256` as fallback) MAY be used as an optional
  dependency under the Constitution 1.1.0 §II amendment, with graceful
  degradation documented and tested.

- **FR-018**: No plugin lifecycle operation (add, remove, list, activate) MUST
  make any network request other than the explicit user-triggered `plugin-add`
  download. In particular, `plugin-list` and activation MUST work fully offline.

### Key Entities

- **Plugin Manifest** (`plugin-manifest.json`): Declares identity and integrity
  of a plugin. Key fields: `name` (matches repo suffix), `version` (SemVer),
  `type` (`llm` | `lang`), `schema_version` (for forward compat), `sha256`
  (hex digest of the bundle), `skills` (list of skill names provided/overridden
  by the plugin).

- **Plugin Store**: User-local directory (`~/.claude/plugins/`) holding one
  subdirectory per installed plugin. Each subdirectory contains the plugin's
  files and a copy of the verified manifest.

- **Plugin Registry**: A lightweight index file (`~/.claude/plugins/registry.json`
  or equivalent) recording installed plugins and their verified state, used by
  `plugin-list` and activation-time lookups without re-scanning directories.

- **Plugin Type**: Enum `llm | lang`. LLM plugins adapt skills for a different
  AI model (e.g., Codex). Language plugins provide language-specific skill
  bundles (e.g., .NET). The type is informational for display and for future
  routing logic.

## Success Criteria

> Decisoes de infraestrutura: N/A for plugin-add/remove/list (stateless CLI
> operations, no scheduling). The `--llm` pipeline flag stores one field in
> `state.json` (FR-016) using the existing state write path — no new
> infrastructure.

### Measurable Outcomes

- **SC-001**: A developer can complete a full `cstk plugin-add <name>` →
  integrity-verified install → `cstk --llm <name>` pipeline invocation in under
  60 seconds on a normal broadband connection.

- **SC-002**: A checksum mismatch during `plugin-add` is detected 100% of the
  time (deterministic: the verification is always executed before any file is
  written to the plugin store).

- **SC-003**: Running the pipeline with no `--llm` flag (default `claude`) is
  indistinguishable in behavior from the current pipeline — zero regressions for
  existing users.

- **SC-004**: `cstk plugin-list` completes in under 2 seconds regardless of the
  number of installed plugins (re-verification is on-demand, not batched at
  list time unless `--verify` flag is passed).

- **SC-005**: All new POSIX sh scripts pass `shellcheck -s sh` with zero
  warnings (or each warning is suppressed with an inline comment explaining the
  exception), satisfying Constitution Principle II.

- **SC-006**: A user who installs a plugin and then runs `plugin-list` without
  network access sees each plugin's status correctly (either `ok` from cached
  checksum or `tampered` from local re-verification) — no network call is made.

## Clarifications

_Resolved in the `/clarify` phase (2026-06-08). Decision IDs: dec-005 (FR-001), dec-006 (FR-007)._

1. **FR-001** — Canonical hosting base: **RESOLVED** — Configurable with a
   sensible default. Default base is `https://github.com/JotJunior/`
   (maintainer's namespace, same trust model as the toolkit itself). Users MAY
   override via `CSTK_PLUGIN_REGISTRY` env var or `~/.cstk/config`
   (POSIX key=value). This keeps the default secure (points to the same GitHub
   org as the toolkit) while allowing community registries without hardcoding
   the namespace forever. A fully fixed URL would couple FR-001 to the
   maintainer's GitHub account permanently; full config-only would add
   over-engineering for MVP. (dec-005, score 2)

2. **FR-007** — Skill resolution model: **RESOLVED** — Path-prepending only.
   The pipeline dispatcher consults `~/.claude/plugins/<name>/skills/` first,
   then falls back to the core catalog. No files are written to or symlinked
   into `~/.claude/skills/`. This is the only model consistent with FR-007's
   explicit prohibition ("MUST NOT write plugin files into the core catalog").
   Copy/symlink was eliminated because it directly violates FR-007. (dec-006,
   score 3)
