**English** · [Português (pt-BR)](./go-toolkit.pt-BR.md)

# Skills and hooks for Go

Skills in `language-related/go/skills/` for Go projects:

| Skill | Trigger | Description |
|-------|---------|-------------|
| **commit** | "commit", "commitar" | Commits following conventional commits, with submodule support and multi-service changes |
| **go-add-entity** | "criar entidade", "novo agregado" | Adds a complete vertical-slice CRUD (domain, DTO, repo, service, handler, migration, wiring) |
| **go-add-migration** | "nova migration", "criar tabela" | Creates a new SQL migration with correct naming/numbering |
| **go-add-test** | "adicionar testes", "cobertura" | Generates tests for handler/service following the project's conventions |
| **go-add-consumer** | "novo consumer", "subscribe evento" | Adds a RabbitMQ message consumer |
| **go-review-pr** | "review pr", "quality gate" | Pre-PR quality gate, diff-aware, with an 8-step review |
| **go-review-service** | "review service", "auditar serviço" | Audits a Go microservice against all of the project's conventions |

These skills are triggered automatically by the orchestrators when the detected
stack is Go — see section 4.2.1 of `execute-task` and "Audit shortcuts by
stack" in `review-task`.

## Hooks for Go

Hooks in `language-related/go/hooks/` for automatic validations:

| Hook | Description |
|------|-------------|
| **go-build-gate.sh** | Validates the build before operations |
| **check-uncommitted.sh** | Checks for uncommitted changes |
| **check-schema-prefix.sh** | Validates the schema prefix in migrations |
| **check-route-order.sh** | Checks route ordering in the router |

Installation in a Go project (skills + hooks + settings.json merge):

```bash
cd ~/projetos/meu-app-go
cstk install --scope project --profile language-go
```

language-* hooks are installed **only** with `--scope project` (with
`--scope global` they are omitted with a warning in the summary — FR-009c).
