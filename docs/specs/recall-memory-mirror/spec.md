# Feature Specification: Recall Memory Mirror

**Feature**: `recall-memory-mirror`
**Created**: 2026-05-27
**Status**: Draft

## Overview

Espelho read-only das memorias do Claude Code (auto-memory: arquivos `.md` per-projeto
em `~/.claude/projects/<encoded-path>/memory/`, incluindo `MEMORY.md` como indice)
dentro do `knowledge.db` do cstk (`~/.claude/cstk/knowledge.db`, SQLite FTS5), para
acesso rapido cross-projeto via `cstk recall`.

As memorias continuam sendo a fonte canonica e seguem auto-injetadas no contexto
pelo harness a cada sessao. Esta feature cria uma copia DERIVADA na tabela `memories`
do `knowledge.db`, separada da telemetria existente, reconstruivel em qualquer momento
via `--reindex`.

## User Scenarios & Testing

### User Story 1 - Buscar memorias cross-projeto (Priority: P1)

Como usuario com multiplos projetos Claude Code, quero buscar por termo em todas
as memorias registradas (user-feedback, project notes, referencias) de qualquer
projeto, sem ter que lembrar em qual projeto aquela nota foi salva.

**Why this priority**: Memoria distribuida entre N projetos e inacessivel por default —
voce lembra que escreveu algo sobre "cstk install vs self-update" mas nao sabe em
qual projeto; hoje so a memoria do projeto ativo e visivel. E a razao de ser da feature.

**Independent Test**: Dado um banco `knowledge.db` com entradas na tabela `memories`
oriundas de dois projetos diferentes, `cstk recall "install self-update"` deve retornar
resultados de ambos os projetos em uma unica busca.

**Acceptance Scenarios**:

1. **Given** memorias indexadas de 2+ projetos, **When** `cstk recall "termo"`,
   **Then** resultados incluem entradas de todos os projetos que contem o termo,
   com proveniencia (projeto, slug, tipo) visiveis.

2. **Given** `--type memory` passado, **When** `cstk recall "termo" --type memory`,
   **Then** apenas entradas da tabela `memories` sao retornadas (nenhuma decision/skill).

3. **Given** `--project myproject` passado, **When** `cstk recall "termo" --project myproject --type memory`,
   **Then** apenas memorias do projeto especificado sao retornadas.

4. **Given** memoria com conteudo sensivel (token, senha), **When** indexada,
   **Then** o body armazenado no `knowledge.db` e scrubbed por `secrets-filter.sh`
   (o `.md` original permanece intacto).

---

### User Story 2 - Ingerir memorias de um projeto (Priority: P2)

Como orquestrador (agente-00c/feature-00c) ou operador, quero que as memorias do
projeto corrente sejam indexadas no `knowledge.db` ao rodar `cstk recall --ingest`,
para que estejam disponíveis na busca cross-projeto sem acao manual extra.

**Why this priority**: Sem ingestao as memorias existem mas nao aparecem na busca;
a indexacao e o passo que torna a feature utilizavel. Vem logo apos P1 porque
busca sem dado e vazia.

**Independent Test**: Dado um diretorio `~/.claude/projects/<enc>/memory/` com
`MEMORY.md` e outros `.md`, ao rodar `cstk recall --ingest --state-dir DIR` (ou
`cstk recall --ingest-memories --project-path PATH`), as entradas devem aparecer
na busca subsequente.

**Acceptance Scenarios**:

1. **Given** diretorio de memoria do projeto com 3 arquivos `.md`, **When** ingestao
   executada, **Then** tabela `memories` contem 3 entradas com projeto/slug/tipo corretos.

2. **Given** ingestao executada 2x sobre os mesmos arquivos, **When** segunda ingestao,
   **Then** nao ha duplicatas (operacao idempotente, upsert por chave natural `(project, slug)`).

3. **Given** `sqlite3` ausente no PATH, **When** ingestao executada,
   **Then** exit 0, aviso em stderr, nenhum aborto (degradacao graciosa).

4. **Given** arquivo `.md` vazio, **When** indexado, **Then** entrada criada com
   body vazio (sem erro).

---

### User Story 3 - Reconstruir indice sem perder memorias (Priority: P3)

Como operador que precisa recriar o `knowledge.db` do zero (schema upgrade, DB
corrompido, migracao de maquina), quero que `cstk recall --reindex` reconstrua
tanto a telemetria (state.json's) quanto as memorias (arquivos `.md`), sem perda.

**Why this priority**: E a garantia de resiliencia da feature: sem isso, um `--reindex`
apagaria as memorias, tornando o dado fugaz e inutilizavel em migracao.

**Independent Test**: Dado `knowledge.db` populado com memorias e telemetria, ao
apagar o DB e rodar `--reindex`, as memorias devem reaparecer com o mesmo conteudo
(scrubbed) que tinham antes.

**Acceptance Scenarios**:

1. **Given** `knowledge.db` com 10 entradas de `memories`, **When** DB apagado e
   `--reindex` executado, **Then** tabela `memories` contem 10 entradas (reconstruida).

2. **Given** `--reindex` executado, **When** finalizado, **Then** tabela `memories`
   NAO contem entradas duplicadas (sem entradas do `state.json` ali).

3. **Given** projeto sem diretorio `memory/`, **When** `--reindex` executado,
   **Then** `--reindex` termina normalmente sem erro (nenhuma memoria para esse projeto = ok).

---

### User Story 4 - Listar memorias de um projeto especifico (Priority: P4)

Como usuario, quero listar todas as memorias indexadas de um projeto sem precisar
de um termo de busca, para ter visao geral do que foi capturado.

**Why this priority**: Complementar a busca; util para auditoria rapida. Menos
urgente que busca e ingestao — o usuario pode trabalhar sem ela.

**Independent Test**: `cstk recall --list-memories --project myproject` deve retornar
slug + descricao de cada entrada de `memories` do projeto, sem body.

**Acceptance Scenarios**:

1. **Given** 5 memorias indexadas para `myproject`, **When** `cstk recall --list-memories --project myproject`,
   **Then** 5 linhas com slug e descricao sao impressas em stdout.

2. **Given** projeto sem memorias indexadas, **When** `cstk recall --list-memories --project myproject`,
   **Then** saida vazia, exit 0 (sem erro).

---

### Edge Cases

- O que acontece quando `~/.claude/projects/` nao existe? A ingestao de memorias
  e um no-op silencioso (exit 0, aviso em stderr).
- O que acontece quando um `.md` tem conteudo adversarial (injection FTS5)?
  O mesmo `fts_phrase_escape`/`sql_escape` ja aplicado para outros tipos e aplicado aqui.
- O que acontece quando `MEMORY.md` referencia outros arquivos `.md` (e o indice)?
  Apenas o conteudo dos proprios `.md` e indexado; a estrutura de referencias nao e interpretada.
- O que acontece se o mesmo arquivo mudar entre duas ingestoes? O upsert por
  `(project, slug)` atualiza o body scrubbed com o conteudo mais recente.

## Requirements

### Functional Requirements

**Tabela e Schema**

- **FR-001**: O sistema MUST criar/manter tabela `memories` no `knowledge.db`, separada
  das tabelas de telemetria (`executions`, `waves`, `alert_signals`, `tasks`, `events`).
  Schema: `project TEXT NOT NULL, slug TEXT NOT NULL, type TEXT NOT NULL, description TEXT,
  body_scrubbed TEXT, path TEXT, indexed_at TEXT` com chave natural `(project, slug)`.

- **FR-002**: A tabela `memories` MUST ser incluida na FTS5 virtual table `knowledge_fts`
  para que buscas via `cstk recall <query>` tambem retornem memorias (usando o mesmo
  pipeline de busca existente).

- **FR-003**: O schema MUST ser idempotente (CREATE TABLE IF NOT EXISTS + INSERT OR REPLACE
  em schema_meta) — banco v3 pre-existente ganha a tabela sem perda de dado.

**Ingestao**

- **FR-004**: O sistema MUST ler arquivos `.md` do diretorio
  `~/.claude/projects/<encoded-path>/memory/` (onde `<encoded-path>` e derivado do
  `projeto_alvo_path` via codificacao canonicada de paths do harness).

- **FR-005**: O body de cada `.md` MUST ser filtrado por `secrets-filter.sh` antes de
  ser armazenado em `memories.body_scrubbed`. O arquivo `.md` original MUST permanecer
  intocado (read-only).

- **FR-006**: A ingestao MUST ser idempotente: segunda execucao sobre os mesmos
  arquivos produz o mesmo resultado (upsert por chave natural `(project, slug)`,
  sem duplicatas).

- **FR-007**: O campo `type` MUST ser derivado do prefixo/nome do arquivo conforme
  convencao: `MEMORY.md` → `index`; `feedback_*.md` → `feedback`; `project_*.md` → `project`;
  `reference_*.md` → `reference`; demais → `user`.

- **FR-008**: Ausencia de `sqlite3` ou `jq` MUST resultar em degradacao graciosa:
  aviso em stderr, exit 0, nenhuma onda/execucao abortada.

**Reconstrucao**

- **FR-009**: `cstk recall --reindex` MUST reconstruir a tabela `memories` lendo os
  arquivos `.md` de TODOS os projetos em `~/.claude/projects/` (nao do `state.json`).
  Um `--reindex` MUST preservar as memorias (reconstruindo-as dos `.md`).

- **FR-010**: A fonte de reconstrucao das memorias MUST ser os proprios arquivos `.md`
  (re-lidos no `--reindex`), NUNCA o `state.json`. Esta e a invariante critica que
  garante separacao entre telemetria e memorias.

**Busca e Filtragem**

- **FR-011**: `cstk recall <query>` MUST incluir resultados de `memories` junto com
  decisoes/bloqueios/retros/skills (mesma busca FTS5 unificada).

- **FR-012**: `cstk recall --type memory` MUST filtrar resultados para apenas entradas
  da tabela `memories`. O enum `RECALL_TYPE_ENUM` MUST ser extendido com `memory`.

- **FR-013**: `cstk recall --list-memories [--project P]` MUST listar slug + descricao
  de todas as memorias (ou apenas do projeto `P` quando especificado), sem body.

**Confinamento**

- **FR-014**: Toda referencia a `sqlite3`, `jq` e `secrets-filter.sh` para manipulacao
  de memorias MUST estar confinada em `cli/lib/recall.sh`. Nenhum outro arquivo do
  toolkit MUST ter acesso direto ao `knowledge.db` para leitura/escrita de `memories`.

**Cobertura de testes**

- **FR-015**: `tests/cstk/test_recall.sh` MUST ter cobertura para: criacao da tabela
  `memories`, ingestao idempotente, degradacao graciosa (sem sqlite3), `--reindex`
  preserva memorias, busca unificada retorna memorias, `--type memory` filtra
  corretamente, `--list-memories` lista sem body.

### Key Entities

- **Memory Entry**: representacao indexada de um arquivo `.md` de memoria do Claude Code.
  Atributos: `project` (nome do projeto, derivado do path codificado), `slug` (nome do
  arquivo sem extensao, ex: `feedback_skill_permissions_warmup`), `type`
  (`index`|`feedback`|`project`|`reference`|`user`), `description` (primeira linha nao-vazia
  do `.md` ou nome do slug humanizado), `body_scrubbed` (conteudo filtrado por
  secrets-filter), `path` (path absoluto do `.md` original, para rastreabilidade),
  `indexed_at` (ISO 8601 UTC).

- **Project Memory Directory**: diretorio `~/.claude/projects/<encoded-path>/memory/`
  onde o harness do Claude Code persiste auto-memories. `<encoded-path>` e a codificacao
  do path absoluto do projeto usada pelo harness (separadores `/` viram `-`).

## Success Criteria

### Measurable Outcomes

- **SC-001**: `cstk recall "termo"` retorna resultados de `memories` sem exigir nenhuma
  flag adicional — buscas existentes funcionam exatamente como antes, agora incluindo
  memorias.

- **SC-002**: Um `cstk recall --reindex` apos apagar o `knowledge.db` reconstroi as
  memorias sem perda — 100% das entradas pre-existentes voltam (contagem identica).

- **SC-003**: Ingestao idempotente: rodar `cstk recall --ingest` N vezes sobre o mesmo
  conjunto de arquivos produz sempre o mesmo numero de entradas em `memories` (sem
  crescimento por duplicatas).

- **SC-004**: Ausencia de `sqlite3` nunca produz exit != 0 em nenhum caminho de codigo
  que manipule memorias — degradacao graciosa e 100% coberta por testes automatizados.

- **SC-005**: `tests/cstk/test_recall.sh` passa na suite completa (`./tests/run.sh`)
  sem regressao nos cenarios existentes (zero quebras em cenarios pre-existentes).

> Decisoes de infraestrutura: N/A (feature stateless — leitura de arquivos locais e
> escrita em SQLite local; sem scheduling, sem sessoes persistentes, sem tokens externos,
> sem multi-replica).

## Constraints

- **C-001 (Constitution Principio II)**: toda referencia a `sqlite3`/`jq`/`secrets-filter.sh`
  para memorias confinada em `cli/lib/recall.sh` (carve-out opcional com fallback graceful,
  conforme amendment 1.1.0). Scripts POSIX sh puro (`#!/bin/sh`, `set -eu`, sem Bash-isms).

- **C-002 (Invariante fonte canonica)**: os arquivos `.md` em `~/.claude/projects/.../memory/`
  NAO sao movidos, editados, renomeados ou excluidos por esta feature. Acesso e estritamente
  read-only.

- **C-003 (Invariante separacao de tabelas)**: `memories` e uma tabela dedicada no
  `knowledge.db`. Seu conteudo NUNCA e misturado ou derivado de `executions`/`waves`/`tasks`/`events`.

- **C-004 (Invariante reindex)**: `--reindex` MUST reconstruir `memories` dos arquivos
  `.md` (nao do `state.json`). Apagar o `knowledge.db` e re-executar `--reindex` NAO
  pode resultar em memorias perdidas.

- **C-005 (Fora de escopo)**: a visualizacao das memorias no `cstk-panel` esta FORA
  desta feature. Esta feature prepara o dado (tabela `memories` populada); a UI
  e demanda separada.

## Clarifications

Fase clarify executada em 2026-05-27. Duas decisoes de design resolvidas autonomamente
com score 3 (evidencia empirica). Nenhum bloqueio humano necessario.

### CQ1 — Derivacao do campo `project` para a tabela `memories` (dec-006, score 3)

**Decisao**: usar `basename(projeto_alvo_path)` como campo `project`, identico a
convencao ja adotada na telemetria (`decisions`, `waves`, etc.).

**Como localizar o diretorio `memory/`**: aplicar a formula forward-encoding
`sed 's|^/||; s|[/_]|-|g; s|^|-|'` sobre o `projeto_alvo_path` para obter o
`<encoded-path>`, entao ler `~/.claude/projects/<encoded-path>/memory/`.

**Evidencia empirica**: formula verificada contra 4 projetos reais com resultado
correto em todos:
- `/Users/jot` → `-Users-jot`
- `/Users/jot/Projects/_lab/Jot/misc/claude-ai-tips` → `-Users-jot-Projects--lab-Jot-misc-claude-ai-tips`
- `/Users/jot/Projects/_lab/Jot/misc/cstk-panel` → `-Users-jot-Projects--lab-Jot-misc-cstk-panel`
- `/Users/jot/Projects/_arquivo/CodexCode/troncodigital` → `-Users-jot-Projects--arquivo-CodexCode-troncodigital`

**Contexto de `--ingest --state-dir`**: `state.json` contem `projeto_alvo_path` →
`project = basename(projeto_alvo_path)` (paridade com telemetria, sem ambiguidade).

**Contexto de `--reindex`**: sem `state.json` disponivel para cada `<encoded-path>`,
o `project` e derivado do proprio `<encoded-path>` usando o mesmo `basename`
calculado como `basename(sed 's|^-||; s|.*-||' <<< encoded)`. Limitacao conhecida e
documentada: projetos cujo basename original continha underscore (ex: `my_project`)
terao `project = my-project` no reindex (inconsistente com o ingest normal).
Esta limitacao e aceitavel porque: (a) o `--ingest --state-dir` e o caminho principal
(orquestradores), e (b) o reindex e operacao de reconstrucao corretiva, nao operacao
critica de producao.

**Impacto em FR-004**: o FR-004 e atualizado para especificar explicitamente a formula
forward-encoding como mecanismo canonico de localizacao do `memory/` dir.

### CQ2 — Escopo do `--ingest`: aditivo dentro do existente (dec-007, score 3)

**Decisao**: a ingestao de memories e um passo ADITIVO dentro do `recall_mode_ingest`
existente. Nenhum subcomando separado (`--ingest-memories`) e criado.

**Mecanismo**: ao final de `recall_mode_ingest`, apos ingerir o `state.json`, chamar
`recall_ingest_memories "$_ing_state_dir" "$_ing_db"`. Esta funcao:
1. Le `projeto_alvo_path` do `state.json` (ja lido no contexto do ingest).
2. Calcula o `encoded-path` via forward-encoding.
3. Varre `~/.claude/projects/<encoded-path>/memory/*.md`.
4. Para cada `.md`: scrub + upsert na tabela `memories` por chave `(project, slug)`.

**Justificativa**: zero breaking change para os orquestradores que ja invocam
`cstk recall --ingest --state-dir`. Surface de API menor. O `projeto_alvo_path` ja
esta disponivel em `_ing_state_dir/state.json` no contexto do ingest, tornando a
adicao natural. Evidencia: `recall_mode_ingest` em `cli/lib/recall.sh` L1263-1315 ja
le `state.json`; adicionar a chamada a `recall_ingest_memories` ao final da funcao e
o unico ponto de modificacao necessario.

**Impacto**: o output do `--ingest` sera acrescido de `N memories` na linha de status
(ex: `ingested: 3 decisions, ... 5 memories`). Sem mudanca nos campos existentes.

## Security & Performance Decisions

As decisoes abaixo fecham os gaps identificados pelo checklist (CHK020, CHK025, CHK026).

### CHK020 — Ausencia de auth no `knowledge.db` local (security)

**Decisao consciente de escopo (single-user dev local)**

O `knowledge.db` e um arquivo SQLite em `~/.claude/cstk/knowledge.db` — escopo
estritamente local, per-usuario, single-machine. Nenhuma rede, sem multi-tenant,
sem acesso remoto. A ausencia de autenticacao/ACL e uma decisao de escopo, nao
uma lacuna de seguranca ignorada:

- O arquivo e protegido pelas permissoes normais do SO (`~/.claude/` pertence ao usuario).
- O modelo de ameaca relevante e acesso fisico/root — fora do escopo de ferramenta CLI dev.
- Adicionar auth adicionaria dependencia (ex: libsqlcipher) sem beneficio para o caso de uso.
- Mesma politica de todos os indices SQLite locais de ferramentas dev (ex: SQLite browsers, npm cache).

**Esta decisao esta documentada aqui e e considerada encerrada. Nao requer acao futura
dentro desta feature.**

### CHK025 — SLA de duracao do `--reindex` (performance)

**Decisao: SLA de duracao nao e requisito para ferramenta dev local**

O `cstk recall --reindex` e uma operacao administrativa/corretiva, nao um hot path.
O contexto de uso e "reconstruir o indice apos corrompimento ou mudanca de maquina" —
executado raramente, sem expectativa de SLA. "Trivial" (alguns segundos para N tipico
de projetos de um usuario) e suficiente como criteiro operacional.

- Um SLA numerico (ex: "< 30s para 100 state files") criaria trabalho de benchmark e
  manutencao sem valor para o usuario final.
- O limite pratico e o numero de projetos do usuario local — tipicamente < 20.
- Se performance virar problema, o `--reindex` pode usar transacao unica (ja usa) e
  batch inserts — a arquitetura nao impede otimizacao futura.

**Esta decisao esta documentada aqui e e considerada encerrada. Nao requer acao futura
dentro desta feature.**

### CHK026 — `body_scrubbed` sem ceiling de tamanho (performance/storage)

**Decisao: body sem ceiling aceito para o escopo atual**

O FTS5 do SQLite nao tem limite pratico de tamanho de texto por linha. Os arquivos
`.md` de auto-memoria do Claude Code tipicamente tem < 5 KB (notas de feedback,
decisoes de projeto). Arquivos de 100 KB seriam atipicos e ainda assim manuseados
corretamente pelo SQLite.

- Impacto de storage: cada `body_scrubbed` ocupa espaco proporcional ao `.md` original.
  Para o escopo dev-local (dezenas de arquivos, tipicamente < 100 KB total), isso e
  irrelevante.
- Um ceiling (ex: 50 KB) seria arbitrario e poderia truncar memorias legitimas
  sem nenhum beneficio concreto para o usuario atual.
- Se o escopo mudar para multi-usuario ou sync remoto, um ceiling SHOULD ser adicionado
  como requisito de nova feature.

**Esta decisao esta documentada aqui e e considerada encerrada. Nao requer acao futura
dentro desta feature.**
