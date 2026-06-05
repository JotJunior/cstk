# Data Model: Recall Worktree Identity

**Feature**: `recall-worktree-identity` | **Date**: 2026-06-05
**Spec**: [spec.md](./spec.md) | **Research**: [research.md](./research.md)

Dois stores afetados: o `state.json` transacional (campos novos congelados no
init) e o `knowledge.db` derivado (schema v7→v8, coluna `session`). Nenhuma
entidade existente muda de semantica — mudancas sao estritamente aditivas.

---

## Entity: `execution.canonical_project` (state.json — campo novo)

| Atributo | Valor |
|----------|-------|
| Path JSON | `.execution.canonical_project` |
| Tipo | string nao-vazia |
| Obrigatorio | NAO (opcional; ausente em states pre-feature e quando init omite a flag) |
| Origem | flag `--canonical-project` do `state-rw.sh init`, passada pelo command pai |
| Quando presente | sempre que o command pai detecta worktree (`.git` arquivo) OU decide congelar explicitamente; em projeto normal o command PODE congelar `basename(target_project_path)` (US3 AC2 — valor identico ao fallback) |
| Imutabilidade | congelado no init; NUNCA reescrito por onda/resume (e proveniencia, nao estado de progresso) |
| Consumidores | ingest (`recall_ingest_state_json`, `recall_ingest_memories`), `--reindex`, derivacao de `EXCLUDE_FEATURE` no agente-00c-orchestrator |

Semantica: basename do diretorio que contem o `.git` COMUM do repositorio
(resolvido via `git rev-parse --git-common-dir` — research Decision 1).
Representa o projeto REAL ao qual a execucao pertence, independente do path
descartavel da worktree.

## Entity: `execution.session_name` (state.json — campo novo)

| Atributo | Valor |
|----------|-------|
| Path JSON | `.execution.session_name` |
| Tipo | string nao-vazia (dado textual livre; sem parsing downstream — edge case da spec) |
| Obrigatorio | NAO (opcional; ausente fora de sessao e quando o naming `<repo>-<name>` nao casa) |
| Origem | flag `--session-name` do `state-rw.sh init`, derivada pelo command pai (sufixo apos `<canonical>-` no basename do worktree — research Decision 2) |
| Imutabilidade | congelado no init; nunca reescrito |
| Consumidores | ingest (popula coluna `session` em `executions` e `waves`) |

Relacionamento: `session_name` so existe quando `canonical_project` existe
(nao ha sessao sem deteccao de worktree). O inverso nao vale: worktree fora
da convencao de naming gera `canonical_project` sem `session_name`.

### Regras de presenca (matriz de cenarios do init)

| Cenario | `canonical_project` | `session_name` |
|---------|--------------------|----------------|
| Projeto raiz normal (`.git` dir) | ausente OU igual ao basename (command decide; ambos validos por US3 AC2) | ausente |
| Worktree `cstk session` (`<repo>-<name>`) | basename do repo raiz (ex: `cstk`) | `<name>` (ex: `minha-feature`) |
| Worktree fora da convencao de naming | basename do repo raiz | ausente |
| git indisponivel/falha na deteccao (FR-008) | ausente (fallback silencioso) | ausente |

---

## Entity: coluna `session` (knowledge.db v8 — `executions` e `waves`)

| Atributo | Valor |
|----------|-------|
| Tabelas | `executions`, `waves` |
| Tipo SQL | `TEXT` (NULL quando execucao sem sessao — US2 AC2) |
| Origem | `.execution.session_name` do state.json no momento do ingest |
| Migracao | v7→v8: `ALTER TABLE <t> ADD COLUMN session TEXT` guardado por `PRAGMA table_info` (padrao existente `recall.sh:638-648`); DDL fresco ja inclui a coluna |
| FTS | **fora da `knowledge_fts`** (FTS5 nao suporta ADD COLUMN; drop destruiria conhecimento de worktrees removidas — research Decision 6) |
| Constraint | nenhuma nova; `UNIQUE(project, feature, wave, source_id)` existente inalterada |
| Upsert | adicionada ao `ON CONFLICT ... DO UPDATE SET` existente das duas tabelas (`session=excluded.session`) |

`schema_meta.schema_version` passa a `'8'`. DBs v7 existentes recebem apenas
os 2 ALTERs (sem DROP, sem perda — FR-009/SC-006). DBs pre-v7 seguem o caminho
de migracao v7 existente (DROP one-time) e ja renascem com o DDL v8.

---

## Derivation rules: `project` e `feature` no ingest (3 camadas)

Funcao unica de derivacao (uma fonte de verdade, reutilizada por
`recall_ingest_state_json`, `recall_ingest_memories` e `--reindex`):

```
derive_canonical(state.json, target_project_path):
  1. .execution.canonical_project (presente e nao-vazio)  → usa  [FR-003]
  2. senao, se <target_project_path>/.git e ARQUIVO
     e `git rev-parse --git-common-dir` resolve            → usa  [FR-004 camada viva]
  3. senao                                                 → basename(target_project_path)  [FR-004 final; comportamento atual]
```

| Coluna | Layout `feature-00c-state/<short>/` | Layout `agente-00c-state/` |
|--------|--------------------------------------|-----------------------------|
| `project` | `derive_canonical(...)` | `derive_canonical(...)` |
| `feature` | `short_name` (INALTERADO — nao depende de path) | `derive_canonical(...)` (antes: basename bruto; paridade anti-eco — research Decision 7) |
| `session` | `.execution.session_name // NULL` | `.execution.session_name // NULL` |

**Invariante de paridade (FR-007)**: `EXCLUDE_FEATURE` do
agente-00c-orchestrator = MESMO valor de `feature` que o ingest produz
(`.execution.canonical_project // basename`); `--exclude-feature` do
feature-00c-orchestrator = `short_name`. Quebra de paridade = eco do proprio
conhecimento no read-back loop (bug v4.7.2).

### State transitions

N/A — campos congelados (write-once no init) e colunas de proveniencia
(escritas no ingest, atualizadas por upsert idempotente). Nenhuma maquina de
estados nova.

---

## Retro-compatibilidade (FR-010)

| Caso legado | Comportamento |
|-------------|---------------|
| State antigo sem `canonical_project`, projeto normal | camada 3 = identico ao atual (zero regressao) |
| State antigo sem `canonical_project`, worktree viva | camada 2 corrige ao vivo (US1 AC2) |
| State antigo sem `canonical_project`, worktree removida | camada 3 = nome fantasma preservado (retrocesso gracioso, US1 AC3); registros antigos do DB nao sao reescritos |
| DB v7 existente | 2 ALTERs idempotentes; dados intactos (SC-006) |
| Execucao sem sessao | `session = NULL` (US2 AC2) |
