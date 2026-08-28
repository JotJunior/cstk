# Feature Specification: panel-schema-v3 — Suporte ao schema v3 da knowledge.db

**Feature**: `panel-schema-v3`
**Created**: 2026-05-26
**Status**: Draft
**Depende de**: `cstk-panel` (feature base) · cstk ≥ 4.2.0

> Fonte de verdade da mudança: `claude-ai-tips` CHANGELOG **[4.2.0] - 2026-05-25**
> (Enriquecimento da camada B do índice `knowledge.db`) + schema em
> `cli/lib/recall.sh` (`RECALL_SCHEMA_VERSION=3`).
>
> O cstk-panel é **consumidor derivado e read-only** da `knowledge.db`. As
> mudanças do v3 são **aditivas e retro-compatíveis**: índices v2 seguem
> funcionando; o índice é reconstruível via `cstk recall --reindex`.

## Contexto

O cstk foi atualizado para a v4.2.0 e bumpou `schema_version` de `2` → `3`.
As duas mudanças do v3:

1. **`tasks.titulo TEXT`** — nova coluna na tabela `tasks` com o título
   descritivo de cada task (heading do `tasks.md`). Migração idempotente via
   `ALTER TABLE tasks ADD COLUMN titulo TEXT`. Valor passa por `secrets-filter`
   na ingestão (único campo de texto livre da camada B). Ausente → `""`.
2. **Evento `recall_consulted`** — novo `event_type` na tabela `events` (sem
   mudança de DDL). Gravado a **cada** consulta do read-back loop
   (`cstk recall --context`) no início de `specify`/`plan`, **inclusive quando
   `hits=0`**. A `descricao` carrega `etapa=… hits=N`. É a métrica "quantas
   vezes o histórico foi consultado pelo orquestrador".

## Problema

Estado atual do painel contra uma `knowledge.db` v3:

- 🔴 **BLOQUEADOR**: `apps/server/src/db/open.ts` valida `schema_version === '2'`
  e degrada qualquer outra versão como `schema-mismatch`. **Uma base v3 derruba
  o painel inteiro** (todas as telas em modo degradado). O `envelope.ts` também
  emite `meta.schemaVersion` hardcoded como `'2'`.
- 🟡 **Correção**: o mapper de eventos tem allowlist de 4 tipos; tipo
  desconhecido cai no fallback `schedule_wait`. `recall_consulted` seria
  **silenciosamente reclassificado como `schedule_wait`**, poluindo o bucket de
  incidentes.
- 🟢 **Gap conhecido fechado**: `data-gaps.md` P1·#3 lista `tasks.titulo` como
  lacuna a preencher "em schema v3?"; `Tasks.tsx` tem nota explícita de que o
  schema v2 não tem título. O v3 entrega exatamente isso.
- 🟢 **Observabilidade nova**: `recall_consulted` é o propósito declarado do v3
  para o painel — habilita medir a saúde do read-back loop (consultas
  produtivas vs vazias).

## Princípios da constitution afetados

- **I — Read-Only Absoluto**: nenhuma mudança escreve na `knowledge.db`. A
  migração da *fixture de teste* não é a base de produção.
- **II — Degradar, Nunca Quebrar**: aceitar v2 **e** v3; versão desconhecida
  continua degradando como `schema-mismatch` (não erro).
- **III — Honestidade de Métrica**: a métrica de `recall_consulted` é uma
  **contagem direta** (não proxy, não aproximada) — `hits` vem da `descricao`.
  O split produtivas/vazias é exato.
- **VI — Snapshot que Muda**: a base pode ser reescrita por trás; o guard de
  abertura mantém o retry transitório.

## User Scenarios & Testing

### User Story 1 - Painel funciona contra base v3 (Priority: P1)

Como engenheiro com a `knowledge.db` já em schema v3, abro o painel e tudo
carrega normalmente — sem banner de degradação por `schema-mismatch`.

**Why this priority**: sem isto o painel inteiro fica inútil para qualquer
usuário que atualizou o cstk. É o bloqueador.

**Independent Test**: com uma base v3 válida e populada, `GET /overview`
retorna `data != null` e `meta.schemaVersion === '3'`.

**Acceptance Scenarios**:

1. **Given** uma `knowledge.db` v3, **When** abro qualquer tela, **Then** não
   há degradação `schema-mismatch`; os dados carregam.
2. **Given** uma base v2 (legada), **When** abro o painel, **Then** continua
   funcionando (retro-compat).
3. **Given** uma base com `schema_version` não suportada (ex.: `99`), **When**
   o BE abre, **Then** degrada como `schema-mismatch` (não erro 5xx).
4. **Given** o env `CSTK_SCHEMA_VERSIONS` definido, **When** o BE inicia,
   **Then** o conjunto de versões aceitas vem do env (não hardcoded).

### User Story 2 - Título de tarefa visível (Priority: P2)

Como engenheiro inspecionando tarefas, vejo o **título descritivo** de cada
task (não apenas `feature · onda`), na tela Tarefas e na aba Tarefas do detalhe
de execução.

**Independent Test**: com base v3 contendo `tasks.titulo` populado, `GET /tasks`
e `GET /executions/:id/tasks` retornam `titulo` em cada item; a UI o exibe.

**Acceptance Scenarios**:

1. **Given** uma task com `titulo` não-vazio, **When** abro a tela Tarefas,
   **Then** o título aparece como identidade primária da linha.
2. **Given** uma task de base v2 (sem `titulo`) ou `titulo=""`, **When** a UI
   renderiza, **Then** faz fallback para `feature · onda` (sem quebrar).
3. **Given** `titulo` é texto livre (untrusted), **When** renderizado, **Then**
   é exibido via `textContent`/`TextRaw` (nunca `innerHTML`).

### User Story 3 - Métrica de consultas ao histórico (Priority: P2)

Como engenheiro avaliando o read-back loop, vejo na tela Métricas quantas vezes
o orquestrador consultou o histórico, com split entre consultas **produtivas**
(`hits>0`) e **vazias** (`hits=0`).

**Independent Test**: com base v3 contendo eventos `recall_consulted`,
`GET /metrics/recall-consultations` retorna `{ total, produtivas, vazias }`
exatos; a UI exibe o card.

**Acceptance Scenarios**:

1. **Given** N eventos `recall_consulted`, **When** consulto a métrica, **Then**
   `total === N` e `produtivas + vazias === total`.
2. **Given** eventos `recall_consulted`, **When** abro a tela Incidentes,
   **Then** eles **não** aparecem como incidentes (são informativos).
3. **Given** uma `descricao` sem `hits=` parseável, **When** agregado, **Then**
   conta no `total` mas não infla `produtivas` (degrada para `vazias`/indefinido
   sem quebrar).

## Functional Requirements

- **FR-V3-001**: O BE DEVE aceitar `schema_version ∈ {2, 3}` na abertura da
  base. O conjunto de versões aceitas DEVE vir do env `CSTK_SCHEMA_VERSIONS`
  (CSV; default `2,3`), nunca hardcoded inline no guard.
- **FR-V3-002**: Versão fora do conjunto aceito DEVE degradar como
  `schema-mismatch` (Princípio II), sem lançar exceção.
- **FR-V3-003**: `meta.schemaVersion` no envelope DEVE refletir a versão **real**
  lida da base (não literal fixo).
- **FR-V3-004**: O DTO de Task DEVE expor `titulo: string` (texto livre,
  untrusted). Ausência na base → `""`.
- **FR-V3-005**: As queries de task (por-execução e cross) DEVEM selecionar
  `titulo` de forma tolerante a bases v2 (coluna ausente → `""`).
- **FR-V3-006**: O DTO de Event DEVE reconhecer `recall_consulted` como tipo
  válido; o mapper NÃO DEVE reclassificá-lo como `schedule_wait`.
- **FR-V3-007**: DEVE existir endpoint `GET /metrics/recall-consultations`
  retornando `{ total, produtivas, vazias }`, contagem **exata** (Princípio III),
  derivando `hits` da `descricao` (`hits=N`).
- **FR-V3-008**: A tela Incidentes NÃO DEVE listar `recall_consulted` como
  incidente operacional.
- **FR-V3-009**: A UI DEVE exibir `titulo` na tela Tarefas e na aba Tarefas do
  detalhe de execução, com fallback para `feature · onda` quando vazio.
- **FR-V3-010**: A fixture de teste DEVE ser migrada para v3 (coluna `titulo` +
  eventos `recall_consulted`) de forma determinística, sem depender da base real
  da máquina do desenvolvedor.

## Success Criteria

- **SC-V3-001**: `GET /overview` contra base v3 retorna `data != null` e
  `meta.schemaVersion === '3'`.
- **SC-V3-002**: `GET /overview` contra base v2 segue funcional (retro-compat).
- **SC-V3-003**: Nenhum evento `recall_consulted` é contado como `schedule_wait`.
- **SC-V3-004**: `recall-consultations`: `produtivas + vazias === total`.
- **SC-V3-005**: Suíte de testes (`vitest`) verde, incluindo casos v3 novos.

## Out of Scope

- Mudar a ingestão/escrita da `knowledge.db` (pertence ao cstk, não ao painel).
- Expor `titulo` em busca FTS (já indexado pelo cstk; sem mudança no painel).
- Histórico/série temporal de `recall_consulted` (card é contagem agregada).
