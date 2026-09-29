[English](./go-toolkit.md) · **Português (pt-BR)**

# Skills e hooks para Go

Skills em `plugins/cstk-language-go/skills/` para projetos Go:

| Skill | Trigger | Descrição |
|-------|---------|-----------|
| **commit** | "commit", "commitar" | Commits com conventional commits, suporte a submodules e mudanças multi-serviço |
| **go-add-entity** | "criar entidade", "novo agregado" | Adiciona CRUD vertical slice completo (domain, DTO, repo, service, handler, migration, wiring) |
| **go-add-migration** | "nova migration", "criar tabela" | Cria nova migration SQL com naming/numeração corretos |
| **go-add-test** | "adicionar testes", "cobertura" | Gera testes para handler/service seguindo convenções do projeto |
| **go-add-consumer** | "novo consumer", "subscribe evento" | Adiciona consumer de mensagens RabbitMQ |
| **go-review-pr** | "review pr", "quality gate" | Quality gate pré-PR, diff-aware, com revisão em 8 etapas |
| **go-review-service** | "review service", "auditar serviço" | Audita microserviço Go contra todas as convenções do projeto |

Estas skills são acionadas automaticamente pelos orchestrators quando o stack
detectado for Go — ver seção 4.2.1 de `execute-task` e "Atalhos de auditoria
por stack" em `review-task`.

## Hooks para Go

Hooks em `plugins/cstk-language-go/hooks/` para validações automáticas:

| Hook | Descrição |
|------|-----------|
| **go-build-gate.sh** | `PostToolUse` (Write/Edit em `.go`): roda `go build ./...` no serviço afetado e devolve a falha ao Claude |
| **check-uncommitted.sh** | `Stop`: lembra de commitar quando há alterações staged |
| **check-schema-prefix.sh** | `PreToolUse` (Write/Edit em `*/repository/*.go`): avisa sobre SQL sem prefixo de schema (não bloqueia) |
| **check-route-order.sh** | `PreToolUse` (Write em `*_handler.go`): bloqueia rota estática registrada depois de `/:id` (conflito no trie do Fiber) |

Instalação em projeto Go (skills + hooks + merge de settings.json):

```bash
cd ~/projetos/meu-app-go
cstk install --scope project --profile language-go
```

Hooks de language-* são instalados **apenas** em `--scope project` (em
`--scope global` são omitidos com aviso no summary — FR-009c).
