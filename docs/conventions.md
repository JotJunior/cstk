**English** · [Português (pt-BR)](./conventions.pt-BR.md)

# Naming conventions and documentation hierarchy

## Naming Conventions

| Type | Pattern | Example |
|------|---------|---------|
| Use Cases | `UC-{DOMAIN}-{NNN}` | UC-CAD-001 |
| Architecture Decisions | `ADR-{NNN}-{title}` | ADR-001-database |
| Business Rules | `RN{NN}` | RN01 |
| Test Cases | `CT{NN}` | CT01 |
| Exceptions | `E{NNN}` | E001 |

### Domain Codes

Domain codes are **defined per project**, not universal. Since 1.1.0, the
skills look up the real domains via:

1. `domains` field in `config.json` (when the project defines it explicitly)
2. Glob of existing UCs (when the project already has documentation)
3. Asking the user via AskUserQuestion (when both are absent)

Common examples in business projects: `AUTH` (authentication), `CAD`
(registration), `PED` (orders), `FIN` (financial). Use whatever makes sense in
your domain.

## Documentation Hierarchy

The `initialize-docs` skill creates the following structure:

```
docs/
├── 01-briefing-discovery/      # Initial requirements, PDFs
├── 02-requisitos-casos-uso/    # Use cases (UC-*)
├── 03-modelagem-dados/         # DERs, schemas
├── 04-arquitetura-sistema/     # ADRs, diagrams
├── 05-definicao-apis/          # REST, gRPC, Webhooks, Messaging
├── 06-ui-ux-design/            # Wireframes, mockups
├── 07-plano-testes/            # Test plans
├── 08-operacoes/               # Runbooks
└── 09-entregaveis/             # Release notes
```

## Feature specs (SDD)

Feature specs live in `docs/specs/<feature>/` (spec.md, plan.md, tasks.md,
checklists/, contracts/). Once completed, the feature is archived under
`docs/specs/_archived/YYYY-MM-DD-<feature>/` (date prefix since v5.22.0;
directories archived before that keep the name without a date) and its delta is
applied to the living-specs corpus in `docs/specs/current/` — see
[SDD Pipeline](./sdd-pipeline.md#living-specs-and-delta-requirements-v5230).
