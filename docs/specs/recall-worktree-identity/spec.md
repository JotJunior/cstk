# Feature Specification: Recall Worktree Identity

**Feature**: `recall-worktree-identity`
**Created**: 2026-06-05
**Status**: Draft

## Context

The `cstk session start` command creates isolated git worktrees at
`<parent>/<repo-name>-<session-name>` (e.g., `cstk-minha-feature`). When
agente-00c or feature-00c runs inside such a worktree, the knowledge.db
ingest derives `project = basename(target_project_path)`, recording a phantom
project name (`cstk-minha-feature`) instead of the canonical project (`cstk`).
This corrupts cross-feature search results, anti-echo filtering, and `--reindex`
reliability.

## User Scenarios & Testing

### User Story 1 - Ingestao atribui execucao ao projeto canonico (Priority: P1)

Como operador do cstk, ao rodar agente-00c/feature-00c dentro de uma worktree
de sessao (ex: `cstk-minha-feature/`), quero que as entradas ingeridas no
knowledge.db sejam atribuidas ao projeto canonico (`cstk`), para que pesquisas
posteriores via `cstk recall` retornem os achados corretamente agrupados pelo
projeto real — nao por um nome fantasma descartavel.

**Why this priority**: e o problema-raiz descrito. Sem isso, o indice de
conhecimento cross-feature fica fragmentado e inacessivel por projeto canonico.

**Independent Test**: criar state.json com `target_project_path` apontando para
um path de worktree (`/tmp/cstk-minha-feature`), executar ingestao, checar que a
coluna `project` na tabela `executions` do knowledge.db contém `cstk` (nao
`cstk-minha-feature`).

**Acceptance Scenarios**:

1. **Given** state.json com `target_project_path=/home/user/projects/cstk-minha-feature` e `.git` sendo ARQUIVO (indicador de worktree), **When** o campo `canonical_project = "cstk"` esta congelado no state.json, **Then** a ingestao usa `cstk` como valor de `project` na knowledge.db.

2. **Given** state.json antigo (pre-feature) com worktree ainda existente no disco, **When** a ingestao nao encontra `canonical_project` no state.json e `.git` e arquivo no path real, **Then** a ingestao resolve o projeto canonico via `git rev-parse --git-common-dir` ao vivo e usa o resultado como `project`.

3. **Given** state.json antigo e worktree JA removida do disco, **When** a ingestao nao encontra `canonical_project` e nao pode resolver git ao vivo, **Then** a ingestao usa `basename(target_project_path)` como fallback (comportamento anterior — retrocesso gracioso sem quebrar).

4. **Given** state.json num projeto-raiz normal (sem worktree), **When** a ingestao roda, **Then** o comportamento e identico ao atual — nenhuma regressao para execucoes fora de sessao.

---

### User Story 2 - Proveniencia de sessao preservada no schema (Priority: P2)

Como operador do cstk, quero saber quais execucoes do knowledge.db vieram de
uma sessao de worktree (e qual nome de sessao), para poder auditar e filtrar
resultados por sessao quando necessario.

**Why this priority**: corrigir o nome do projeto sem preservar a proveniencia de
sessao perde informacao valiosa. A sessao e um contexto de trabalho identificavel
que o operador nao deveria perder ao consultar o historico.

**Independent Test**: criar state.json com `session_name = "minha-feature"`, ingeri-lo, checar que a coluna `session` (ou equivalente) na tabela `executions` contem `"minha-feature"`.

**Acceptance Scenarios**:

1. **Given** state.json com `session_name = "minha-feature"` congelado pelo bootstrap, **When** a ingestao roda, **Then** a coluna `session` em `executions` e `waves` contem `"minha-feature"`.

2. **Given** state.json de projeto nao-sessao (sem `session_name`), **When** a ingestao roda, **Then** a coluna `session` fica NULL/vazia — sem regressao de esquema para execucoes sem sessao.

3. **Given** `cstk recall "minha-query"`, **When** resultados de sessao sao exibidos, **Then** a UI/output indica a sessao de origem quando disponivel (ex: campo `session` visivel no resultado ou na busca filtrada).

---

### User Story 3 - Bootstrap/init congela proveniencia canonica no state.json (Priority: P2)

Como orquestrador agente-00c ou feature-00c inicializando dentro de uma
worktree, quero que o state.json criado no init contenha campos `canonical_project`
e `session_name` ja resolvidos, para que qualquer ingestao futura — inclusive apos
a worktree ser removida — produza atribuicao correta no knowledge.db.

**Why this priority**: o campo congelado e o que garante que `--reindex`
(req. 2 do operador) funcione mesmo apos a worktree desaparecer. Sem isso, o
fallback de resolucao git ao vivo (US1 cenario 2) falharia silenciosamente.

**Independent Test**: invocar `state-rw.sh init` (ou equivalente de bootstrap
dos commands 00C) num diretorio de worktree simulado; ler o state.json gerado;
verificar presenca dos campos `execution.canonical_project` e `execution.session_name`.

**Acceptance Scenarios**:

1. **Given** o comando `feature-00c` (ou `agente-00c`) rodando em path de worktree `<parent>/<repo>-<sessao>`, **When** o init do state.json executa, **Then** `execution.canonical_project` contem o basename do repo raiz (ex: `cstk`) e `execution.session_name` contem o nome da sessao (ex: `minha-feature`).

2. **Given** o init rodando em projeto nao-worktree, **When** o init executa, **Then** `execution.canonical_project` contem o mesmo valor que `basename(target_project_path)` e `execution.session_name` fica ausente ou vazio.

3. **Given** `.git` sendo diretorio (projeto raiz), **When** o bootstrap detecta que nao e worktree, **Then** nenhum overhead de deteccao e visivel para o operador — deteccao e silenciosa e nao-bloqueante.

---

### User Story 4 - Anti-eco EXCLUDE_FEATURE continua funcional com proveniencia corrigida (Priority: P3)

Como orquestrador agente-00c/feature-00c usando `cstk recall --context` com
`--exclude-feature`, quero que o filtro anti-eco continue casando corretamente
com a derivacao da ingestao, mesmo apos a correcao de proveniencia — para que
execucoes rodando em worktree nao vejam seus proprios achados no read-back loop.

**Why this priority**: o bug v4.7.2 documentado mostra que uma dessincronizacao
entre a derivacao da ingestao e o valor de `--exclude-feature` gera eco dos
proprios resultados no read-back loop, poluindo o contexto de decisao.

**Independent Test**: ingerir state.json de worktree (com `canonical_project = "cstk"`), depois executar `cstk recall --context "termos" --exclude-feature cstk`; confirmar que os achados ingeridos sao excluidos do resultado.

**Acceptance Scenarios**:

1. **Given** ingestao de execucao de worktree atribuida ao projeto canonico `cstk`, **When** o orquestrador chama `recall --context "..." --exclude-feature cstk`, **Then** os achados dessa execucao SAO excluidos (anti-eco funciona).

2. **Given** ingestao de execucao de worktree atribuida ao projeto canonico `cstk`, **When** o orquestrador chama `recall --context "..." --exclude-feature cstk-minha-feature` (nome fantasma), **Then** os achados NAO sao excluidos (nenhum achado tem `project = cstk-minha-feature` apos a correcao).

---

### User Story 5 - Memorias de worktree documentadas e tratadas (Priority: P4)

Como operador do cstk, quero entender como as memorias em
`~/.claude/projects/<encoded-worktree-path>/memory/` sao tratadas quando a
ingestao roda em contexto de worktree, para nao perder memorias relevantes nem
poluir o indice com entradas orfas.

**Why this priority**: a fragmentacao de memorias foi listada pelo operador como
requisito minimo de tratamento (no minimo documentar). E P4 porque nao bloqueia
os cenarios principais de correcao de atribuicao de projeto.

**Independent Test**: verificar no spec/plan a decisao tomada sobre fragmentacao de memorias de worktree; confirmar que existe documentacao clara do comportamento esperado e, se implementado, testes de regressao cobrindo a atribuicao de memorias ao projeto canonico.

**Acceptance Scenarios**:

1. **Given** memorias em `~/.claude/projects/<encoded-worktree>/memory/` existentes, **When** o `--reindex` roda, **Then** o comportamento esta documentado: as memorias SAO atribuidas ao projeto canonico OU sao mantidas por path e documentadas como "memorias de sessao" — sem silencio sobre o comportamento.

2. **Given** worktree ja removida mas memorias ainda em disco, **When** `cstk recall --list-memories` e invocado, **Then** memorias de sessions removidas sao identificaveis (ex: by path) e o usuario consegue remover/migrar manualmente.

---

### Edge Cases

- O que acontece quando `git rev-parse --git-common-dir` falha (git nao instalado, path fora de repositorio, permissao negada)? → fallback para `basename(target_project_path)` sem erro fatal.
- O que acontece quando o nome da sessao contem caracteres especiais (espacos, unicode, `/`)? → campo `session_name` e tratado como dado textual; a derivacao do projeto canonico nao depende de parsing do session_name.
- O que acontece quando `--reindex` e invocado e existem states antigos com worktree removida E sem `canonical_project`? → aplica fallback gracioso (basename), sem abort.
- O que acontece quando dois orquestradores rodam em sessoes diferentes do mesmo projeto simultaneamente? → cada ingestao usa seu proprio `canonical_project` congelado; nao ha colisao — o indice e append/upsert por `execution_id`.
- O que acontece com o schema do knowledge.db em instancias existentes (pre-v7)? → bump de schema implica migracao idiomatica (CREATE TABLE IF NOT EXISTS + ALTER TABLE ADD COLUMN guardado por PRAGMA), sem DROP de dados existentes.

## Requirements

### Functional Requirements

- **FR-001**: O bootstrap/init do state.json MUST detectar se o `target_project_path` e uma worktree git (`.git` sendo arquivo, nao diretorio) e, quando positivo, resolver o projeto canonico via `git rev-parse --git-common-dir` e congelar `execution.canonical_project` no state.json.
- **FR-002**: O bootstrap/init MUST congelar `execution.session_name` no state.json quando detectar worktree criada por `cstk session start` (derivado do nome da sessao — sufixo apos `<repo>-`).
- **FR-003**: A ingestao (recall.sh) MUST preferir `execution.canonical_project` do state.json como valor de `project` quando o campo estiver presente e nao-vazio.
- **FR-004**: A ingestao MUST implementar fallback em duas camadas quando `execution.canonical_project` estiver ausente: primeiro tentativa de resolucao git ao vivo; segundo `basename(target_project_path)` (comportamento atual — preservado para compatibilidade).
- **FR-005**: O schema do knowledge.db MUST incluir coluna `session` (ou equivalente) nas tabelas `executions` e `waves`, populada a partir de `execution.session_name` do state.json quando disponivel (NULL para execucoes sem sessao).
- **FR-006**: O `--reindex` MUST usar o campo `canonical_project` congelado no state.json para reindexar corretamente mesmo quando a worktree nao existe mais no disco no momento do reindex.
- **FR-007**: A logica de derivacao de `project` para anti-eco (`--exclude-feature` / `EXCLUDE_FEATURE`) MUST usar o mesmo valor que a ingestao produz para `project`, garantindo sincronismo entre ingestao e filtragem.
- **FR-008**: Toda falha na deteccao de worktree (git indisponivel, permissao, path invalido) MUST ser tratada como fallback silencioso — nenhum abort, nenhum erro fatal propagado para a onda do orquestrador.
- **FR-009**: O bump de schema do knowledge.db (de v7 para v8 ou superior) MUST ser idempotente: DBs pre-existentes recebem a coluna `session` via `ALTER TABLE ADD COLUMN` guardado por PRAGMA, sem DROP de dados existentes.
- **FR-010**: O comportamento de ingestao e anti-eco para execucoes fora de worktree (projetos normais) MUST ser identico ao comportamento pre-feature — zero regressao.

### Key Entities

- **canonical_project**: campo congelado no state.json no momento do bootstrap/init, representando o basename do repositorio git raiz. Chave de agrupamento primaria na knowledge.db para busca por projeto.
- **session_name**: campo opcional congelado no state.json quando a execucao corre dentro de uma sessao (`cstk session start`). Metadado de proveniencia que permite auditoria por sessao sem substituir o projeto canonico.
- **worktree detection signal**: indicador de que o diretorio corrente e uma worktree git — derivado da verificacao de que `.git` e ARQUIVO (nao diretorio) no `target_project_path`.

## Decisoes de Infraestrutura

| Tipo | Decisao |
|------|---------|
| Schema change | Bump de versao de schema do knowledge.db (v7 -> v8), com migracao idempotente via ALTER TABLE ADD COLUMN guardado por PRAGMA. --reindex repopula a nova coluna. |
| Compatibilidade retroativa | Fallback em 3 camadas preserva comportamento atual para states sem campo canonico e para projetos nao-worktree. |
| POSIX puro | Deteccao de worktree via `test -f .git` (POSIX) + invocacao opcional de `git rev-parse --git-common-dir` (com fallback gracioso se git indisponivel). |
| Deps opcionais | `git` ja e prereq de uso do toolkit; a invocacao opcional ao vivo (fallback 1) satisfaz a condicao (a) do amendment 1.1.0 da constitution — a feature funciona sem ela via campo congelado. |

> Nenhum scheduler, key rotation, mutex multi-pod ou backup adicional e introduzido por esta feature (estateless alem do schema bump).

## Success Criteria

### Measurable Outcomes

- **SC-001**: 100% das execucoes iniciadas dentro de worktrees de sessao produzem entradas no knowledge.db com `project = <repo-canonico>`, verificavel por query SQL direta apos ingestao de state.json de worktree simulado.
- **SC-002**: `cstk recall "query" --project cstk` retorna resultados de execucoes que correram em worktrees de sessao `cstk-*`, sem precisar de filtro por nome fantasma.
- **SC-003**: `--reindex` reindexado sobre states com campo `canonical_project` congelado produz resultado identico independente de a worktree existir ou nao no disco.
- **SC-004**: Anti-eco `--exclude-feature cstk` (nome canonico) exclui corretamente resultados de execucoes de worktree; nenhuma regressao no filtro para execucoes de projetos normais.
- **SC-005**: Suite de testes existente (`tests/cstk/test_recall.sh`) passa sem regressao apos a mudanca; novos cenarios cobrindo worktree detection, fallback em 3 camadas e coluna `session` sao adicionados a suite.
- **SC-006**: O schema bump (coluna `session`) e aplicado idempotentemente a um DB v7 pre-existente sem perda de dados, verificavel por teste automatizado com DB fixture.

## Clarifications

> Nenhum item `[NEEDS CLARIFICATION]` — todos os pontos criticos foram definidos pelo operador na descricao da feature. Abordagem B+A fallback, esquema da coluna `session`, requisitos de anti-eco e compatibilidade retroativa estao especificados acima.
