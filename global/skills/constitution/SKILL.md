---
name: constitution
description: 'Create/update immutable project governance principles. Triggers: "constitution", "criar constituicao", "principios do projeto", "governance". For point-in-time technical decisions, use ADRs instead.'
argument-hint: "[descricao do projeto ou principios desejados]"
allowed-tools:
  - Read
  - Write
  - Edit
  - Glob
  - Grep
---

# Skill: Constituicao do Projeto

Crie ou atualize a constituicao do projeto — o documento de principios imutaveis que governa
decisoes de arquitetura, qualidade e processo.

## Pre-requisitos

**Recomendado**: `/briefing` executado antes. A constituicao deriva principios do
contexto do projeto (visao, prioridades, restricoes) — sem briefing, os
principios ficam genericos.

**Opcional**: `docs/constitution.md` existente (para atualizar em vez de criar
do zero). A skill versiona via SemVer (MAJOR/MINOR/PATCH).

## Proximos passos

1. `/specify` — especificar features alinhadas aos principios
2. `/plan` — planos tecnicos vao respeitar a constitution (Constitution Check como gate)
3. `/analyze` — apos ter specs/plans/tasks, validar alinhamento contra a constitution

## Argumentos

$ARGUMENTS

---

## FLUXO DE EXECUCAO

```
1. CONTEXTO        Detectar projeto e constituicao existente
     |
2. COLETA          Coletar/derivar principios
     |
3. GERACAO         Preencher template com valores concretos
     |
4. PROPAGACAO      Verificar alinhamento com outros artefatos
     |
5. SALVAMENTO      Salvar e reportar
```

---

## ETAPA 1: CONTEXTO

### 1.1 Detectar Projeto

Leia os seguintes arquivos (se existirem) para entender o contexto:

```
SEMPRE LER (se existirem):
-- README.md
-- CLAUDE.md
-- docs/constitution.md (constituicao existente)
-- docs/specs/*/spec.md (specs existentes)
-- package.json, go.mod, pyproject.toml (stack tecnica)
```

### 1.2 Verificar Constituicao Existente

Procure constituicao existente nesta ordem:
1. `docs/constitution.md`
2. `constitution.md`

Se encontrada:
- Carregar conteudo atual
- Identificar placeholders `[ALL_CAPS_IDENTIFIER]` nao preenchidos
- Propor atualizacoes baseadas no input do usuario

Se nao encontrada:
- Seguir para coleta de principios (Etapa 2)

---

## ETAPA 2: COLETA DE PRINCIPIOS

### 2.1 Fontes de Principios

Analise o argumento fornecido ($ARGUMENTS). Ele pode ser:

1. **Descricao do projeto**: Inferir principios a partir do contexto
2. **Lista de principios**: Usar diretamente
3. **Numero de principios**: Respeitar a quantidade solicitada
4. **Vazio**: Inferir do contexto do projeto e perguntar ao usuario

### 2.2 Derivar Valores

Para cada placeholder no template:
- Se o usuario forneceu valor: usar diretamente
- Se inferivel do contexto (README, docs, stack): derivar e documentar a inferencia
- Se desconhecido: marcar como `TODO(<CAMPO>): explicacao` e incluir no relatorio

### 2.3 Datas e Versionamento

- `RATIFICATION_DATE`: data original de adocao (se desconhecida, perguntar ou marcar TODO)
- `LAST_AMENDED_DATE`: data de hoje se mudancas foram feitas
- `CONSTITUTION_VERSION`: incrementar seguindo versionamento semantico:
  - **MAJOR**: Remocao ou redefinicao incompativel de principios
  - **MINOR**: Novo principio ou expansao material de secao
  - **PATCH**: Clarificacoes, correcoes de texto, refinamentos nao-semanticos
- Se tipo de bump ambiguo: propor raciocinio ao usuario antes de finalizar

---

## ETAPA 3: GERACAO

### 3.1 Template da Constituicao

Usar `templates/constitution.md` (mesmo diretorio desta skill) e substituir
TODOS os placeholders `[ALL_CAPS]` por texto concreto. Estrutura:

- **Core Principles** — 3-5 principios declarativos e testaveis
- Secoes opcionais conforme o projeto (ex: Quality Standards, Architecture Decisions)
- **Governance** — regras de amendment, versioning, exception handling
- Rodape com **Version / Ratified / Last Amended**

### 3.2 Regras de Preenchimento

- O usuario pode pedir mais ou menos principios que o template — ajustar conforme necessario
- Cada principio deve ser: **declarativo, testavel e livre de linguagem vaga**
  - Trocar "should" por MUST/SHOULD com rationale quando apropriado
- Remover comentarios HTML do template ao preencher
- Manter hierarquia de headings exatamente como no template
- Nao deixar nenhum placeholder `[...]` sem justificativa explicita

---

## ETAPA 4: PROPAGACAO

### 4.1 Checklist de Consistencia

Apos gerar a constituicao, verificar alinhamento com outros artefatos:

- [ ] `CLAUDE.md`: Principios refletidos nas instrucoes do projeto?
- [ ] `docs/specs/*/plan.md`: Plans existentes referenciam principios?
- [ ] `docs/specs/*/tasks.md`: Tasks refletem quality gates da constituicao?

### 4.2 Sync Impact Report

Gerar relatorio de impacto (como comentario HTML no topo do arquivo):

```markdown
<!--
Sync Impact Report
- Version: old → new
- Principios modificados: [lista]
- Secoes adicionadas: [lista]
- Secoes removidas: [lista]
- Artefatos que precisam atualizacao: [lista com status]
- TODOs pendentes: [lista]
-->
```

---

## ETAPA 5: SALVAMENTO

### 5.1 Validacao Final

Antes de salvar:
- [ ] Nenhum placeholder `[...]` sem justificativa
- [ ] Versao consistente com relatorio de impacto
- [ ] Datas em formato ISO YYYY-MM-DD
- [ ] Principios sao declarativos e testaveis
- [ ] Sem trailing whitespace

### 5.2 Salvar

Salvar em `docs/constitution.md` (ou caminho especificado pelo usuario).

### 5.3 Relatorio

Apresentar ao usuario:
- Nova versao e rationale do bump
- Principios criados/modificados
- Artefatos que precisam atualizacao manual
- Sugestao de commit message (ex: `docs: create project constitution v1.0.0`)

---

## EXEMPLOS DE PRINCIPIOS

Os exemplos abaixo ilustram formato — adaptar ao dominio do projeto, nao copiar literalmente.

**Principios de arquitetura:**
- Library-First: Features comecam como bibliotecas standalone
- Modularidade: Servicos comunicam via contratos, nao memoria compartilhada
- Simplicity: YAGNI — nao abstrair prematuramente

**Principios de qualidade:**
- Test-First (NON-NEGOTIABLE): TDD obrigatorio, Red-Green-Refactor
- Integration Testing: Testes contra sistema real, nao mocks
- Observability: Logging estruturado obrigatorio em todas as operacoes criticas

**Principios de UX/acessibilidade:**
- Component-First: UI construida de componentes reutilizaveis
- Accessibility: WCAG 2.1 AA como minimo
- Progressive Enhancement: Funcionalidade core funciona sem JS

**Principios de seguranca/compliance:**
- Security: OWASP Top 10 como baseline
- Deny by Default: Permissoes explicitas em vez de implicitas
- Data Minimization: Coletar/persistir so o necessario

**Principios de processo:**
- Documentation: Codigo auto-documentado, comentarios para o "por que"
- Reviewable Changes: PRs pequenos e focados, nao merges gigantes

---

## Gotchas

### Principios devem ser declarativos, testaveis e livres de linguagem vaga

"Sistema deve ser robusto" nao e principio, e aspiracao. Trocar por MUST/SHOULD com rationale: "MUST: toda operacao de escrita em banco deve ser idempotente (Why: retry sem corrupcao de estado)".

### Versao segue SemVer — e o bump deve ser justificado

- MAJOR: remove ou redefine principio de forma incompativel
- MINOR: adiciona principio ou expande secao materialmente
- PATCH: clarifica texto sem mudar semantica

Se o bump e ambiguo, propor rationale ao usuario antes de finalizar — datas e versao sao auditadas.

### Placeholders `[ALL_CAPS]` nao sobrevivem no documento final

Todo placeholder no template tem que ser preenchido com conteudo concreto ou marcado como `TODO(<CAMPO>): explicacao`. Placeholders nao-resolvidos em produto final e indicador de constituicao incompleta.

### Principios conflitantes invalidam a constituicao

Se "Moving Fast" e "Zero Bugs" coexistem como principios MUST, o projeto nao tem governanca — tem contradicao. Detectar conflitos antes de salvar e pedir ao usuario para resolver a tensao (tipicamente promovendo um a MUST e rebaixando outro a SHOULD com trade-off documentado).

### Sync Impact Report e obrigatorio em atualizacoes

Bumps MAJOR/MINOR precisam listar quais artefatos (CLAUDE.md, plans, tasks) precisam atualizacao. Sem isso, a constituicao desinterna-se dos outros documentos silenciosamente.
