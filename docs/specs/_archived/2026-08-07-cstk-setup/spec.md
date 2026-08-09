# Feature Specification: Guided Project Setup Wizard

**Feature**: `cstk-setup`
**Created**: 2026-08-07
**Status**: Draft

## Clarifications

### Session 2026-08-07

- Q: O 'guided setup wizard' e implementado como um novo subcomando 'cstk setup' do binario CLI, ou como uma skill/slash-command do Claude Code? → A: Novo subcomando `cstk setup` no binario CLI (`cli/lib/setup.sh`), interativo — nao e skill/slash-command do Claude Code.
- Q: Quais marcadores concretos definem 'diretorio de projeto gerenciado pelo toolkit' para o gate de recusa do FR-011? → A: Raiz de repositorio git (presenca de `.git`, arquivo ou diretorio — worktrees contam); nao exige artefatos do toolkit, para evitar circularidade com o proprio onboarding.
- Q: No modo nao-interativo, a area de MCP deve tentar aplicar `cstk mcp install` por padrao mesmo sem Docker detectado, ou pular a area? → A: Tenta aplicar mesmo sem Docker (registro fica inerte sem Docker; start das execucoes ja degrada sozinho para bash-fallback), emitindo aviso claro de Docker ausente.

### Sessao 2026-08-07 — gate de seguranca (fase plan, bloqueio HIGH)

- Q: A deteccao das areas `hooks`/`mcp` e por presenca de chave/basename e nao distingue configuracao legitima de hostil preexistente; o wizard reportaria "already configured" sobre um controle de seguranca redirecionado. Endurecer, reduzir o escopo da garantia, ou aceitar o risco? → A: **Endurecer a deteccao** — antes de reportar como ja configurado, verificar que o path registrado aponta para o script real do catalogo provisionado pelo cstk; registro com path divergente vira status `divergente` com remediacao, nunca "already configured". Formalizado em FR-016.

## User Scenarios & Testing

### User Story 1 - Guided first-time setup (Priority: P1)

A developer who just cloned or installed the toolkit into a project wants
to bring that project up to the recommended configuration baseline
without hunting through documentation for the individual commands that
each configure one piece (hooks, state backend, MCP integration,
telemetry). They run a single guided command and are walked, one area at
a time, through what is currently configured, what is missing, and
whether they want it applied now.

**Why this priority**: This is the core value of the feature — replacing
tribal knowledge of 3-4 separate commands with one entry point. Without
this, the rest of the feature has nothing to guide.

**Independent Test**: Run the guided command on a project with none of
the four areas configured; confirm the user is walked through all four in
order, each with a clear current-status statement and an explicit
choice, and that choosing "apply" for an area leaves that area correctly
configured afterward.

**Acceptance Scenarios**:

1. **Given** a project with no hooks installed, no state backend chosen,
   no MCP integration registered, and no telemetry active, **When** the
   user runs the guided setup interactively, **Then** each of the four
   areas is presented in turn with its current status and a choice to
   apply or skip it.
2. **Given** the user accepts the offer for the hooks area, **When** the
   step completes, **Then** the project's hooks configuration reflects the
   applied change and the wizard reports it as "applied" before moving to
   the next area.
3. **Given** the user declines an area, **When** the step completes,
   **Then** no change is made for that area and the wizard reports it as
   "skipped by user" before moving to the next area.

---

### User Story 2 - Idempotent status awareness on re-run (Priority: P2)

A developer who already ran the guided setup (or configured areas
individually beforehand) runs it again — out of habit, after onboarding a
teammate, or to check whether anything drifted. They expect the wizard to
recognize what is already in place and report it, rather than re-applying
it, erroring out, or offering to overwrite an existing choice.

**Why this priority**: Idempotency is what makes the wizard safe to run
repeatedly and recommend as a standard onboarding step; without it, a
second run risks corrupting or force-migrating an already-initialized
project, which existing individual commands explicitly guard against.

**Independent Test**: Run the guided setup twice in a row on the same
project without any change in between; confirm the second run reports
every area as already configured, applies nothing, and exits the same way
whether the first run happened seconds or weeks earlier.

**Acceptance Scenarios**:

1. **Given** a project where all four areas are already configured,
   **When** the user runs the guided setup again, **Then** every area is
   reported as "already configured" and no underlying configuration is
   modified.
2. **Given** a project where only some areas are configured, **When** the
   user runs the guided setup, **Then** already-configured areas are
   reported and skipped automatically while unconfigured areas are still
   offered normally.
3. **Given** a project that was deliberately configured to use a
   different backend than the wizard's default (e.g. state backend kept
   at the legacy option on purpose), **When** the user runs the guided
   setup, **Then** the wizard does not force a migration and reports the
   existing choice as already configured.

---

### User Story 3 - Non-interactive setup for automation (Priority: P3)

A developer scripting project onboarding (a bootstrap script, a CI job
that provisions a fresh workspace, or a teammate who just wants the
recommended defaults without reading each prompt) wants to run the same
guided setup without answering prompts, and separately wants a way to see
exactly what would happen before committing to it.

**Why this priority**: Automation and preview are what make the wizard
usable outside a single interactive terminal session — without them the
feature only serves the one-off manual case already covered by P1.

**Independent Test**: Run the guided setup with the non-interactive flag
on an unconfigured project and confirm it completes with no prompts,
applying the recommended default for every area; separately, run it with
the preview flag and confirm the project is left completely unchanged
while the same information that would have been applied is shown.

**Acceptance Scenarios**:

1. **Given** an unconfigured project, **When** the user runs the guided
   setup with the non-interactive flag, **Then** the wizard applies the
   recommended default for each area without waiting for input and
   reports the outcome of each at the end.
2. **Given** an unconfigured project, **When** the user runs the guided
   setup with the preview flag, **Then** the wizard prints what it would
   do for each area and exits without changing anything.
3. **Given** both the non-interactive and preview flags are supplied
   together, **When** the user runs the guided setup, **Then** preview
   behavior takes precedence and nothing is applied.

---

### User Story 4 - Granular opt-in for optional usage capture (Priority: P4)

A developer going through the hooks area of the guided setup wants the
mandatory hooks installed, but wants to decide separately and explicitly
whether to also opt in to the optional loose usage capture hook, since it
has a different privacy/footprint trade-off than the mandatory ones.

**Why this priority**: This preserves an existing explicit opt-in
guarantee (loose usage capture must never be silently bundled) inside the
new guided flow; it is a refinement of the hooks area from P1, not a
standalone flow, so it ranks after the core stories.

**Independent Test**: Run the guided setup's hooks area and confirm the
mandatory hooks question and the optional usage-capture question are
presented as two distinct choices, and that declining the optional one
still applies the mandatory hooks.

**Acceptance Scenarios**:

1. **Given** the user is in the hooks area of the guided setup, **When**
   they are asked about optional loose usage capture, **Then** the
   question is presented separately from the mandatory hooks question,
   with a clear explanation of what it captures.
2. **Given** the user declines the optional loose usage capture,
   **When** the hooks area completes, **Then** the mandatory hooks are
   still installed and the optional capture remains inactive.

---

### Edge Cases

- What happens when a required underlying tool for one area (e.g. the
  dependency needed for the state backend check) is missing or below the
  minimum supported version? The wizard MUST report that specific area as
  failed/unavailable with the reason, and MUST continue offering the
  remaining areas rather than stopping the whole run.
- How does the wizard behave when it is run inside a directory that is
  not a toolkit-managed project (i.e. not the root of a git repository —
  see FR-011)? It MUST say so clearly and MUST NOT create partial
  configuration in an unrelated directory.
- How does the wizard behave when the terminal is not interactive (e.g.
  piped input, no TTY) and neither the non-interactive nor the preview
  flag was supplied? It MUST detect the non-interactive terminal and
  fail with a clear message asking the user to pick one of the two
  flags, rather than hanging on a prompt no one can answer.
- What happens if one area's underlying action fails partway (e.g. a
  step that touches project files is interrupted)? The wizard MUST leave
  that area's configuration in a state consistent with what individually
  running that area's existing dedicated command would leave it in on
  the same failure, and MUST still report the failure and proceed to the
  remaining areas.
- What happens for the telemetry area, whose activation ultimately
  depends on values exported in the user's own shell session rather than
  anything the wizard can persist inside the project? The wizard MUST
  only diagnose and display the exact values/instructions needed and
  MUST NOT modify any file outside the project directory to activate it.

## Requirements

### Functional Requirements

- **FR-001**: The guided setup MUST offer, in a fixed order, exactly four
  configuration areas: mandatory project hooks (with the optional loose
  usage capture as a nested choice), the global state backend, the MCP
  state-server registration, and telemetry activation.
- **FR-002**: For each area, before offering to apply anything, the
  guided setup MUST first determine and display that area's current
  status in the project (already configured / not configured / divergent
  / unavailable) using the same detection logic as that area's existing
  dedicated command.
- **FR-003**: The guided setup MUST NOT re-apply, modify, or force a
  migration for any area already reported as configured — a
  fully-configured project run through the wizard again MUST result in
  zero configuration changes.
- **FR-004**: The guided setup MUST support a preview mode that displays,
  for every area, what would be applied without changing any file or
  persisted configuration.
- **FR-005**: The guided setup MUST support a non-interactive mode that
  applies the recommended default outcome for every not-yet-configured
  area without waiting for a prompt.
- **FR-006**: When both preview mode and non-interactive mode are
  requested together, preview MUST take precedence and no changes MUST be
  applied.
- **FR-007**: When run with neither preview nor non-interactive mode in a
  non-interactive terminal, the guided setup MUST fail fast with a
  message directing the user to one of those two flags, instead of
  waiting indefinitely for input.
- **FR-008**: The hooks area MUST present the decision to install the
  optional loose usage capture hook as a distinct choice from the
  mandatory hooks, never bundling it silently into a single yes/no.
- **FR-009**: A failure or unavailable dependency in one area MUST NOT
  prevent the guided setup from offering the remaining areas; each area's
  outcome is independent.
- **FR-010**: At the end of a run, the guided setup MUST present a
  summary listing, for each of the four areas, one of: applied, already
  configured, skipped by user, or failed (with reason).
- **FR-011**: The guided setup MUST refuse to run, with a clear
  diagnostic, when invoked outside a recognizable toolkit-managed project
  directory — defined as the root of a git repository (presence of a
  `.git` file or directory; git worktrees count) — and MUST NOT write any
  configuration in that case. No toolkit-specific artifact (e.g.
  `.claude/`, `docs/constitution.md`) is required as a marker, since the
  guided setup is itself part of onboarding a project onto the toolkit.
- **FR-012**: The telemetry area MUST only diagnose current activation
  status and display the exact instructions/values needed to activate it
  manually; it MUST NOT write to any file outside the project directory.
- **FR-013**: (INFRA-IDEMP) Idempotency for every area is achieved by
  re-checking that area's live current status immediately before acting,
  every run — never by a persisted "setup already ran" flag. Scope: the
  four areas listed in FR-001, checked fresh on every invocation.
- **FR-014**: The guided setup MUST be implemented as a new subcommand of
  the CLI binary (`cstk setup`, backed by `cli/lib/setup.sh`), interactive
  by default — not as a Claude Code skill or slash-command.
- **FR-015**: In non-interactive mode, the MCP state-server area MUST
  attempt `cstk mcp install` as its recommended default even when Docker
  is not detected — the resulting registration is inert without Docker,
  and execution start already degrades gracefully to bash-fallback on its
  own — while emitting a clear warning that Docker was not found.
- **FR-016**: (SECURITY) For the hooks and MCP areas, the guided setup
  MUST NOT report an area as configured based on the mere presence of a
  key or file name in the project's configuration. It MUST verify that
  the registered entry actually invokes the toolkit-provisioned script,
  and MUST report an entry that names the hook or server but points
  elsewhere as **divergent** — never as already configured. A divergent
  area MUST be reported with its remediation, MUST NOT be silently
  overwritten by the wizard, and MUST make the run's outcome
  unambiguously non-successful.
- **FR-017**: The state backend area MUST state explicitly, before
  applying and in preview, that its change is written to **global**
  user-level configuration affecting every project on the machine — not
  to the project directory being set up. The other three areas are
  project-scoped and MUST NOT be presented with that label.
- **FR-018**: The guided setup MUST NOT expose, accept, or set any option
  that redirects where provisioned scripts — or the reference copies they
  are compared against — are read from. It always provisions from the
  toolkit's own installed catalog. When such a redirection is already
  present in the invoking environment, the guided setup MUST NOT report
  an area as configured on the strength of a redirected reference; it
  MUST say the verification was made against a non-default source.

> Decisoes de infraestrutura adicionais: N/A — feature nao introduz
> scheduling, rotacao de chaves, refresh de token externo, mutex
> multi-processo nem backup; FR-013 cobre a unica decisao de
> infraestrutura relevante (idempotencia).

### Key Entities

- **Configuration Area**: One of the four things the wizard walks
  through (hooks, state backend, MCP integration, telemetry). Has a
  current status (configured / not configured / divergent / unavailable)
  and, after a run, an outcome (applied / already configured / skipped /
  failed).
- **Setup Run Summary**: The end-of-run report listing every
  Configuration Area's outcome for that invocation, used to confirm
  results in both interactive and non-interactive modes.

## Success Criteria

### Measurable Outcomes

- **SC-001**: A developer starting from a completely unconfigured project
  can review and decide on all four configuration areas through a single
  guided command in under 2 minutes of interactive time.
- **SC-002**: Running the guided setup twice in a row on the same project
  with no changes in between results in zero configuration changes on the
  second run, for 100% of areas.
- **SC-003**: 100% of the changes a non-preview run would apply are
  visible in preview mode beforehand, in the same order and detail.
- **SC-004**: A fully non-interactive run on an unconfigured project
  completes with a final summary and zero unresolved prompts, 100% of the
  time.
- **SC-005**: 100% of runs — interactive or not, successful or partially
  failed — end with a per-area outcome summary that a user can read to
  know exactly what changed and what did not.
- **SC-006**: In a project whose configuration names a mandatory hook or
  the MCP state server but routes it to something other than the
  toolkit-provisioned script, 100% of runs report that area as divergent
  with remediation, and 0% report it as already configured.

## Delta Requirements

**Skip**: Nova capacidade — nao existe entrada correspondente em `docs/specs/current/*.md` para um wizard consolidado de setup, nem para os passos individuais que ele orquestra (hooks/state-backend/mcp/otel) como capacidade documentada; a feature nao altera o comportamento ativo de nenhuma capability existente, apenas oferece um novo ponto de entrada guiado sobre comandos ja existentes — agente-00c-feature-orchestrator, 2026-08-07
