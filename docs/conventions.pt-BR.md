[English](./conventions.md) · **Português (pt-BR)**

# Convenções de nomenclatura e hierarquia de documentação

## Convenções de Nomenclatura

| Tipo | Padrão | Exemplo |
|------|--------|---------|
| Casos de Uso | `UC-{DOMÍNIO}-{NNN}` | UC-CAD-001 |
| Decisões de Arquitetura | `ADR-{NNN}-{título}` | ADR-001-database |
| Regras de Negócio | `RN{NN}` | RN01 |
| Casos de Teste | `CT{NN}` | CT01 |
| Exceções | `E{NNN}` | E001 |

### Códigos de Domínio

Os códigos de domínio são **definidos por projeto**, não universais. A partir
de 1.1.0, as skills consultam os domínios reais via:

1. Campo `domains` em `config.json` (quando o projeto define explicitamente)
2. Glob de UCs existentes (quando o projeto já tem documentação)
3. Pergunta ao usuário via AskUserQuestion (quando ambos ausentes)

Exemplos comuns em projetos de negócio: `AUTH` (autenticação), `CAD`
(cadastros), `PED` (pedidos), `FIN` (financeiro). Use o que faz sentido no
seu domínio.

## Hierarquia de Documentação

**LEGADO** — a estrutura numerada abaixo vinha de uma skill de scaffold
removida na v7. Projetos novos usam o layout SDD:
`docs/briefing.md` + `docs/constitution.md` + `docs/specs/<feature>/`. O
pipeline aceita os dois layouts.

```
docs/
├── 01-briefing-discovery/      # Requisitos iniciais, PDFs
├── 02-requisitos-casos-uso/    # Casos de uso (UC-*)
├── 03-modelagem-dados/         # DERs, schemas
├── 04-arquitetura-sistema/     # ADRs, diagramas
├── 05-definicao-apis/          # REST, gRPC, Webhooks, Messaging
├── 06-ui-ux-design/            # Wireframes, mockups
├── 07-plano-testes/            # Planos de teste
├── 08-operacoes/               # Runbooks
└── 09-entregaveis/             # Release notes
```

## Specs de feature (SDD)

Specs de feature vivem em `docs/specs/<feature>/` (spec.md, plan.md, tasks.md,
checklists/, contracts/). Ao concluir, a feature é arquivada em
`docs/specs/_archived/YYYY-MM-DD-<feature>/` (prefixo de data desde v5.22.0;
diretórios arquivados antes disso mantêm o nome sem data) e seu delta é
aplicado ao corpus de specs vivas em `docs/specs/current/` — ver
[Pipeline SDD](./sdd-pipeline.pt-BR.md#specs-vivas-e-delta-requirements-v5230).
