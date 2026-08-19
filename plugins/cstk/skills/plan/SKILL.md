---
name: plan
description: 'Technical implementation plan — the technical HOW: architecture, data model, API contracts, research, test scenarios. Use when the user wants the technical design of a feature (how to structure/build it, define contracts/schema), whether or not a formal spec.md exists yet. Triggers: "plan", "criar plano", "planejar implementacao", "desenho tecnico", "definir arquitetura/contratos/modelo de dados". Skip when defining WHAT/for-whom in natural language (use specify) or breaking work into tasks (create-tasks).'
argument-hint: "[caminho para spec ou descricao da feature]"
allowed-tools:
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - Bash
  - Agent
---

# Skill: Plano de Implementacao Tecnico

Gere um plano de implementacao completo a partir de uma feature spec, cobrindo
arquitetura, decisoes tecnicas, modelo de dados e contratos.

## Pre-requisitos

**Obrigatorio**: `docs/specs/{feature}/spec.md` ja existente. Sem spec, abortar.

**Recomendado**:
- `/clarify` executado (reduz NEEDS CLARIFICATION na Etapa 3)
- `docs/constitution.md` existente (usado como gate — violacoes sao bloqueantes)

## Proximos passos

1. `/checklist` — gerar quality gate antes de implementar
2. `/create-tasks` — decompor o plano em backlog executavel
3. `/analyze` — apos ter tasks, validar consistencia cross-artifact

## Argumentos

$ARGUMENTS

---

## Leitura de artefatos foundational (briefing + constitution)

Antes de ler `docs/briefing.md` (ou o legado
`docs/01-briefing-discovery/briefing.md`) ou `docs/constitution.md`
direto do disco, verifique se ha cache valido populado pelo agente-00c
ou feature-00c. Aditivo — se nao houver cache, leia direto do disco
conforme comportamento padrao (FR-CACHE-014).

1. **Detectar agente ativo**: variavel `AGENTE_00C_STATE_DIR` setada,
   OU `<projeto-alvo>/.claude/agente-00c-state/state.json` existente,
   OU `<projeto-alvo>/.claude/feature-00c-state/<short>/state.json`.

2. **Se ativo**, tente consumir o resumo via Bash:
   ```bash
   ~/.claude/skills/agente-00c-runtime/scripts/state-cache.sh get-resumo \
     --state-dir "$SD" --artifact briefing
   ```
   - **Exit 0** + stdout nao-vazio: use o resumo como conteudo.
   - **Exit 1**: cache miss (campo ausente, estrategia=passthrough,
     drift detectado) — caia em leitura direta.
   - **Exit 2**: erro fatal (state.json corrompido) — aborte com
     diagnostico do stderr.

   Mesmo protocolo para `--artifact constitution`. NOTA: esta skill
   tem dependencia HARD em `docs/constitution.md` (gate de violacoes
   na ETAPA 2). Se cache miss + arquivo source ausente em disco,
   isso eh erro de pre-requisito, nao falha do cache.

3. **Apos consumo** (hit ou miss), registre metrica via:
   ```bash
   ~/.claude/skills/agente-00c-runtime/scripts/state-cache.sh metrics-bump \
     --state-dir "$SD" --tipo <hit|miss-drift|miss-disabled> \
     [--chars-economizados N]
   ```
   onde N = `source_chars - resumo_chars` quando hit, ou 0 caso contrario.

4. **Standalone** (sem state.json): leia direto do disco. Comportamento
   identico a versao pre-cache.

Spec: `docs/specs/_archived/agente-00c-artifact-cache/spec.md` FR-CACHE-008.

---

## FLUXO DE EXECUCAO

```
1. CONTEXTO           Carregar spec, constitution e projeto
     |
2. CONSTITUTION CHECK Gate obrigatorio antes de prosseguir
     |
3. TECHNICAL CONTEXT  Preencher stack, deps, constraints
     |
4. PHASE 0 — RESEARCH Resolver unknowns, pesquisar libs
     |
5. PHASE 1 — DESIGN   Modelo de dados, contratos, quickstart
     |
6. PLAN DOCUMENT       Consolidar plano final
     |
7. RE-CHECK            Revalidar constitution pos-design
     |
8. SALVAMENTO          Salvar artefatos e reportar
```

---

## ETAPA 1: CONTEXTO

### 1.1 Localizar Spec

Use $ARGUMENTS para encontrar a spec:
1. **Caminho direto**: usar como fornecido
2. **Nome da feature**: buscar `docs/specs/{name}/spec.md`
3. **Glob**: listar `docs/specs/*/spec.md` e pedir ao usuario para escolher

Se spec nao encontrada: instruir usuario a rodar `/specify` primeiro.

### 1.2 Carregar Documentos

```
OBRIGATORIO:
-- Feature spec (spec.md)

OPCIONAL (se existirem):
-- docs/constitution.md (principios de governanca)
-- CLAUDE.md (convencoes do projeto)
-- README.md (contexto geral)
-- docs/specs/{feature}/research.md (pesquisa previa, se rerrun)
```

### 1.3 Extrair da Spec

- User stories com prioridades
- Functional requirements
- Key entities
- Success criteria
- Edge cases
- [NEEDS CLARIFICATION] pendentes (devem ser resolvidos antes ou durante Phase 0)

---

## ETAPA 2: CONSTITUTION CHECK

### 2.1 Gate Obrigatorio

Se `docs/constitution.md` existe:

1. Carregar todos os principios MUST/SHOULD
2. Para cada principio, verificar se a feature spec esta em conformidade
3. Documentar resultado:

```markdown
## Constitution Check

*GATE: Deve passar antes do Phase 0. Re-checar apos Phase 1.*

| Principio | Status | Notas |
|-----------|--------|-------|
| [Nome] | PASS / FAIL / N/A | [Detalhes] |
```

4. Se FAIL em principio MUST: **ERROR** — nao prosseguir ate resolver

Se constitution nao existe: pular esta etapa e documentar "No constitution found".

---

## ETAPA 3: TECHNICAL CONTEXT

### 3.1 Preencher Contexto

Ver secao **Technical Context** em `templates/plan.md` (mesmo diretorio desta
skill). Preencher cada campo detectando do projeto e da spec — marcar unknowns
como `NEEDS CLARIFICATION` apenas apos tentar inferir do codebase.

### 3.2 Inferencia

Antes de marcar NEEDS CLARIFICATION, tentar inferir de:
- `go.mod`, `package.json`, `pyproject.toml`, `Cargo.toml` — linguagem e deps
- `Dockerfile`, `docker-compose.yml`, K8s manifests — platform
- `CLAUDE.md` — convencoes e stack
- Patterns existentes no projeto — testing, storage

---

## ETAPA 4: PHASE 0 — RESEARCH

### 4.0 Modo autonomo: NEEDS CLARIFICATION estrutural NAO se resolve aqui (FR-009)

Antes de resolver qualquer unknown, detecte execucao autonoma pelo mesmo
criterio da secao "Leitura de artefatos foundational" acima: variavel
`AGENTE_00C_STATE_DIR` setada, OU
`<projeto-alvo>/.claude/agente-00c-state/state.json` existente, OU
`<projeto-alvo>/.claude/feature-00c-state/<short>/state.json` existente.

**Fora de execucao autonoma** (uso interativo direto da skill): comportamento
atual preservado, sem mudanca — siga para 4.1 normalmente.

**Em execucao autonoma**: para cada `NEEDS CLARIFICATION` do Technical
Context que corresponda a um dos eixos estruturais (linguagem/runtime, stack/
frameworks, arquitetura de alto nivel, persistencia principal, ambiente de
execucao alvo, tier de entrega — ver `## Definicao: classe estrutural` da
spec `structural-decision-human-gate`), o Phase 0 desta skill **NAO o
resolve por inferencia**: deixe o campo como `NEEDS CLARIFICATION` em
`research.md`/no Technical Context e retorne o controle ao orquestrador. Nao
e responsabilidade desta skill decidir por conta propria uma stack, arquitetura
ou plataforma-alvo — isso e responsabilidade do operador via bloqueio humano
(`state-decisions.sh register --classe estrutural --eixo <token>` +
`bloqueios.sh register`, ver a prosa do orquestrador). O gate de qualidade
ja existente da tabela de gates (`## Quality Gates complementares`, secao
`plan`/`owasp-security`+`doc-quality`) barra o artefato se um eixo
estrutural ficar sem consentimento registrado — esta skill nao precisa
implementar o gate, so **nao antecipar** a resolucao.

NEEDS CLARIFICATION fora dos eixos estruturais (detalhe de implementacao,
biblioteca dentro de uma stack ja decidida, nome de convencao) seguem
normalmente para 4.1 — a excecao e so para os 6 eixos fechados.

### 4.1 Resolver Unknowns

Para cada NEEDS CLARIFICATION no Technical Context:
- Pesquisar no projeto por evidencias
- Se nao resolvivel: criar task de pesquisa

Para cada dependencia/tecnologia:
- Verificar best practices para o contexto

### 4.2 Dispatch de Research (para unknowns complexos)

Para projetos complexos, usar Agent para pesquisa paralela:

```
Agent 1: "Research {unknown} for {feature context}"
Agent 2: "Find best practices for {tech} in {domain}"
```

### 4.3 Consolidar em research.md

Use `templates/research.md` como base. Uma secao `## Decision N` por unknown
resolvido, com **Decision / Rationale / Alternatives considered**.

**Output**: `docs/specs/{feature}/research.md` com todos os NEEDS CLARIFICATION resolvidos.

---

## ETAPA 5: PHASE 1 — DESIGN

**Prerequisito**: research.md completo (todos os NEEDS CLARIFICATION resolvidos)

### 5.1 Modelo de Dados

Base: `templates/data-model.md`. Extrair entidades da spec, uma secao
`## Entity: Name` por entidade, com tabela de campos, relacionamentos e state
transitions.

**Output**: `docs/specs/{feature}/data-model.md`

### 5.2 Contratos de Interface

Se o projeto expoe interfaces externas (APIs, CLI, eventos), use
`templates/contracts.md` — um arquivo por grupo de endpoints em
`docs/specs/{feature}/contracts/`.

Pular se projeto e puramente interno (build scripts, one-off tools).

**Output**: `docs/specs/{feature}/contracts/*.md`

> **INEGOCIAVEL — contrato de interface EXISTENTE nao se inventa (Constitution VI).**
> Ao documentar uma API/evento que JA EXISTE, as assinaturas de request/response
> (nomes de campos, tipos, estrutura), URLs, endpoints e querystrings DEVEM ser
> extraidos da fonte real: codigo-fonte do servico, OpenAPI/Swagger, doc oficial, ou
> uma chamada de fato observada. Se voce nao tem o contrato e nao tem de onde busca-lo,
> **PARE e registre bloqueio humano** — nunca suponha nomes de propriedades nem rotas.
> (Projetar do zero um contrato AINDA inexistente e legitimo — marque-o explicitamente
> como `[PROPOSTA — a validar na implementacao]`, distinto de um contrato afirmado como
> real. O perigo e afirmar como real algo que voce inventou.)

### 5.3 Quickstart / Cenarios de Teste

Base: `templates/quickstart.md`. Um cenario por fluxo critico (happy path +
ao menos um error case), no formato "1. Passo → 2. Passo → **Expected**: resultado".

**Output**: `docs/specs/{feature}/quickstart.md`

**Obrigatorio para features com borda backend↔frontend**: incluir cenario
"Roundtrip End-to-End" que faz uma chamada REAL ao backend (nao mock,
nao fixture), captura o payload de resposta e compara o shape contra o
contrato declarado em §5.4. Razao: 40 ondas historicas mascararam um
drift snake_case vs camelCase porque os testes parseavam mocks (nao o
payload real do backend) — apenas roundtrip empirico expoe esse tipo
de divergencia antes do drift se acumular.

### 5.4 Convencoes de Borda (obrigatorio para features com 2+ camadas)

Quando a feature atravessa fronteiras (backend ↔ frontend, DB ↔
backend, broker ↔ consumer), declarar EXPLICITAMENTE em uma tabela no
`plan.md` qual e a fonte da verdade de cada convencao. Razao: dec-172
e dec-173 da execucao-fonte resolveram em FASE 8 (onda-040) uma
divergencia snake_case vs camelCase que existia desde o contrato
(dec-064). 40 ondas de retrabalho porque a convencao nao foi declarada
upfront.

Estrutura obrigatoria do `plan.md` (secao nova entre "Project Structure"
e "Complexity Tracking"):

```markdown
## Convencoes de Borda

| Camada | Case style | Validacao | Fonte da verdade |
|--------|------------|-----------|------------------|
| DB columns (PostgreSQL) | snake_case | constraint check + migration | `migrations/*.sql` |
| Backend DTO (Go/TS) | camelCase | json tags / Zod | `internal/dto/*.go` ou `src/types/*.ts` |
| Frontend DTO (TS) | camelCase | Zod parse no fetch | `web/src/types/*.ts` (re-export de shared-types) |
| API payload (request/response) | camelCase | Zod em ambos os lados | `contracts/*.md` |
| URL query/path params | kebab-case | router | `routes.ts` ou equivalente |

**Mapper layer (DB ↔ DTO)**: localizacao + responsavel:
- Backend: `internal/repository/mapper.go` (snake_case ↔ camelCase)
- ORM auto-mapping: SIM/NAO — se SIM, citar lib (gorm, sqlc, kysely)

**Validacao Zod**:
- Em qual borda? request, response, ambos?
- Schema compartilhado? localizar em `packages/shared-types/`?
```

Se a feature e single-layer (ex: biblioteca pura, CLI tool, script),
pular essa secao com nota explicita "N/A — single-layer".

**Output**: `docs/specs/{feature}/plan.md` §Convencoes de Borda

---

## ETAPA 6: PLAN DOCUMENT

### 6.1 Template do Plano

Consolidar tudo em `templates/plan.md` preenchido com:

- **Summary** — requisito primario + abordagem tecnica da pesquisa
- **Technical Context** — da Etapa 3, com NEEDS CLARIFICATION ja resolvidos
- **Constitution Check** — da Etapa 2
- **Project Structure** — documentacao (feature dir) + source code (arvore real do projeto)
- **Complexity Tracking** — preencher APENAS se houve violacoes de constitution que precisam justificativa

**Output**: `docs/specs/{feature}/plan.md`

---

## ETAPA 7: RE-CHECK

### 7.1 Revalidar Constitution

Se constitution existe, re-checar principios apos design:
- Design introduziu complexidade nao justificada?
- Principios MUST continuam respeitados?
- Atualizar tabela de Constitution Check se necessario

---

## ETAPA 8: SALVAMENTO

### 8.1 Artefatos Gerados

Listar todos os arquivos criados:

```markdown
## Artefatos

| Arquivo | Status |
|---------|--------|
| docs/specs/{feature}/plan.md | Criado |
| docs/specs/{feature}/research.md | Criado |
| docs/specs/{feature}/data-model.md | Criado |
| docs/specs/{feature}/contracts/*.md | Criado (se aplicavel) |
| docs/specs/{feature}/quickstart.md | Criado |
```

### 8.2 Reportar

```markdown
## Plano Criado

**Feature**: [short-name]
**Diretorio**: docs/specs/{feature}/
**Artefatos**: [N] arquivos gerados
**Constitution**: PASS / N/A
**NEEDS CLARIFICATION restantes**: 0

### Proximos Passos

1. `/checklist` — Gerar quality gate antes de implementar
2. `/create-tasks` — Decompor plano em tarefas executaveis
3. `/analyze` — Validar consistencia entre spec, plan e tasks (apos tasks)
```

---

## REGRAS IMPORTANTES

- **NEVER gerar codigo nesta fase** — apenas documentacao tecnica
- **NEEDS CLARIFICATION devem ser resolvidos** no Phase 0 (nao deixar para implementacao)
- **Constitution violations sao bloqueantes** — nao prosseguir sem resolver
- **Usar Agent para pesquisa paralela** em projetos complexos com multiplas unknowns
- **Paths devem ser reais** — verificar existencia de diretorios antes de referenciar
- **Phase 0 vem antes de Phase 1** — nao projetar modelo de dados com unknowns pendentes

---

## Gotchas

### NUNCA gerar codigo nesta fase

Plano e documentacao tecnica, nao implementacao. Se o impulso e escrever uma funcao ou SQL concreto, pare — vai para `/execute-task`. O plano descreve contratos, schemas e estrutura, nao implementa.

### NEEDS CLARIFICATION devem morrer no Phase 0, nao em Phase 1

Projetar modelo de dados ou contratos com unknowns pendentes e retrabalho garantido. Se Phase 0 nao resolveu, interromper e voltar ao usuario — nao prosseguir para design com lacunas tecnicas.

### Violacao de constitution em principio MUST e bloqueante

Nao tente "documentar a violacao em Complexity Tracking e seguir". MUST nao negocia. Se o plano precisa violar um MUST, revisar escopo ou emendar constituicao primeiro.

### Paths no Project Structure devem ser REAIS

Listar diretorios inventados ("/src/features/x") que nao existem no projeto cria plano desalinhado com o codebase. Sempre verificar estrutura existente antes de desenhar a arvore no plano.

### Re-check de constitution apos Phase 1 nao e formalidade

Design pode introduzir complexidade nao justificada (4o servico, camada adicional) que viola principios. O re-check e o gate final — rode serio, nao marque "PASS" por inercia.

### Technical Context com "NEEDS CLARIFICATION" em campo inferivel e desleixo

Antes de marcar unknown, tentar inferir de `go.mod`, `package.json`, `Dockerfile`, `CLAUDE.md`. Marcar "NEEDS CLARIFICATION: linguagem" num repo com `pyproject.toml` e sinal de que o Phase 0 nao leu o projeto.
