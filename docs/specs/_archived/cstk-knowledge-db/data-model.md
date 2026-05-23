# Phase 1 — Data Model: cstk-knowledge-db

**Feature**: `cstk-knowledge-db` | **Date**: 2026-05-23 | **Spec**:
[spec.md](./spec.md) | **Research**: [research.md](./research.md)

Modelo de dados do indice de conhecimento (`~/.claude/cstk/knowledge.db`,
SQLite + FTS5). O indice e **derivado e reconstruivel** — nao e fonte de
verdade. Toda escrita e idempotente por chave de proveniencia.

> Convencao de naming: identificadores SQL em `snake_case`, em ingles.
> O DB e single-layer (CLI tool sobre SQLite) — sem fronteira
> backend/frontend, sem mapper layer.

---

## Entidade conceitual: KnowledgeRecord

Unidade recuperavel de conhecimento. Quatro subtipos concretos —
**decision**, **bloqueio**, **retro**, **skill** — cada um materializado
em sua propria tabela, mais uma tabela FTS5 unificada para busca.

### Atributos comuns (proveniencia — Provenance)

Presentes em todas as tabelas. Compoem (com `type` + `source_id`) a chave
de upsert. NUNCA passam pelo filtro de segredos (FR-017).

| Campo | Tipo | Origem no state.json | Notas |
|-------|------|----------------------|-------|
| `project` | TEXT NOT NULL | `execucao.projeto_alvo_path` → **basename** (default) | projeto de origem (FR-003); basename reduz captura de segredo em path (ver Security Considerations) |
| `feature` | TEXT NOT NULL | `short_name` | feature/short-name (FR-003) |
| `wave` | TEXT NOT NULL | id da onda (`onda-NNN`) | identificador da onda (FR-003) |
| `execucao_id` | TEXT NOT NULL | `execucao.id` | id da execucao (FR-003) |
| `source_ts` | TEXT NOT NULL | timestamp de origem do registro | ISO-8601 (FR-003) |
| `type` | TEXT NOT NULL | constante por tabela | `decision`\|`bloqueio`\|`retro`\|`skill` |
| `source_id` | TEXT NOT NULL | id do registro na origem | `dec-NNN`, `bloq-NNN`, sintetizado p/ retro/skill |
| `ingested_at` | TEXT NOT NULL | gerado na ingestao | ISO-8601; atualizado no upsert |

**Chave de upsert (UNIQUE)**: `(project, feature, wave, type, source_id)`
— FR-007. `type` e constante por tabela, mas faz parte da chave logica
para garantir unicidade cross-type quando ids colidem.

---

## Tabela: decisions

Decisoes auditaveis (`decisoes[]` do state.json).

| Coluna | Tipo | Filtro segredos | Notas |
|--------|------|-----------------|-------|
| `id` | INTEGER PK AUTOINCREMENT | — | rowid interno |
| `project` | TEXT NOT NULL | NAO | proveniencia |
| `feature` | TEXT NOT NULL | NAO | proveniencia |
| `wave` | TEXT NOT NULL | NAO | proveniencia |
| `execucao_id` | TEXT NOT NULL | NAO | proveniencia |
| `source_ts` | TEXT NOT NULL | NAO | proveniencia |
| `source_id` | TEXT NOT NULL | NAO | `dec-NNN` (chave) |
| `agente` | TEXT | NAO | enumerado/estruturado |
| `etapa` | TEXT | NAO | enumerado |
| `escolha` | TEXT | NAO | enumerado/curto |
| `score` | INTEGER | NAO | estruturado |
| `contexto` | TEXT | **SIM** | texto livre |
| `justificativa` | TEXT | **SIM** | texto livre |
| `evidencia` | TEXT | **SIM** | texto livre |
| `ingested_at` | TEXT NOT NULL | — | gerado |

`UNIQUE(project, feature, wave, source_id)` (type implicito = decision).

---

## Tabela: bloqueios

Bloqueios humanos (`bloqueios_humanos[]`).

| Coluna | Tipo | Filtro segredos | Notas |
|--------|------|-----------------|-------|
| `id` | INTEGER PK AUTOINCREMENT | — | rowid |
| `project`,`feature`,`wave`,`execucao_id`,`source_ts` | TEXT NOT NULL | NAO | proveniencia |
| `source_id` | TEXT NOT NULL | NAO | `bloq-NNN` (chave) |
| `status` | TEXT | NAO | enumerado (pendente/respondido) |
| `pergunta` | TEXT | **SIM** | texto livre |
| `contexto_para_resposta` | TEXT | **SIM** | texto livre |
| `resposta` | TEXT | **SIM** | texto livre (pode mudar entre ondas → upsert reflete o mais recente, FR-008) |
| `ingested_at` | TEXT NOT NULL | — | gerado |

`UNIQUE(project, feature, wave, source_id)`.

---

## Tabela: retros

Retro-execucoes (`retro` / contador de retros do state.json).

| Coluna | Tipo | Filtro segredos | Notas |
|--------|------|-----------------|-------|
| `id` | INTEGER PK AUTOINCREMENT | — | rowid |
| `project`,`feature`,`wave`,`execucao_id`,`source_ts` | TEXT NOT NULL | NAO | proveniencia |
| `source_id` | TEXT NOT NULL | NAO | sintetizado: `retro-<wave>-<idx>` (chave) |
| `texto` | TEXT | **SIM** | texto livre |
| `ingested_at` | TEXT NOT NULL | — | gerado |

`UNIQUE(project, feature, wave, source_id)`.

> `source_id` sintetizado de forma estavel (wave + indice) porque retros
> nao tem id proprio garantido. Estabilidade = reingestao nao duplica.

---

## Tabela: skills

Skills invocadas (`ondas[].skills_invoked[]`).

| Coluna | Tipo | Filtro segredos | Notas |
|--------|------|-----------------|-------|
| `id` | INTEGER PK AUTOINCREMENT | — | rowid |
| `project`,`feature`,`wave`,`execucao_id`,`source_ts` | TEXT NOT NULL | NAO | proveniencia |
| `source_id` | TEXT NOT NULL | NAO | sintetizado: `skill-<wave>-<idx>` (chave) |
| `skill_name` | TEXT NOT NULL | NAO | nome de skill — estruturado, NAO filtrado |
| `decisao_id` | TEXT | NAO | ref a `dec-NNN` (estruturado) |
| `ingested_at` | TEXT NOT NULL | — | gerado |

`UNIQUE(project, feature, wave, source_id)`.

> `skill_name` NAO passa pelo filtro (FR-017: nomes de skill sao
> estruturados). E busca-vel via FTS apenas no campo textual replicado.

---

## Tabela virtual: knowledge_fts (FTS5)

Indice unificado de busca full-text (FR-004). Tabela "externa" (content
rowid apontando para as tabelas-fonte) OU tabela FTS5 standalone com
colunas de proveniencia replicadas para filtragem. **Decisao**: FTS5
standalone (mais simples de reconstruir e filtrar), populada no mesmo
upsert.

| Coluna FTS5 | Conteudo | Indexada |
|-------------|----------|----------|
| `type` | `decision`\|`bloqueio`\|`retro`\|`skill` | UNINDEXED (filtro, nao busca) |
| `project` | proveniencia | UNINDEXED |
| `feature` | proveniencia | UNINDEXED |
| `wave` | proveniencia | UNINDEXED |
| `source_id` | id de origem | UNINDEXED |
| `source_ts` | timestamp | UNINDEXED |
| `body` | texto pesquisavel concatenado (ja filtrado p/ texto livre) | indexada (FTS) |

`body` por tipo:

- decision: `escolha` + `contexto` + `justificativa` + `evidencia`
- bloqueio: `pergunta` + `contexto_para_resposta` + `resposta`
- retro: `texto`
- skill: `skill_name`

`UNIQUE` logico via `source_id`+proveniencia: como FTS5 nao suporta
constraint UNIQUE, a idempotencia e garantida por `DELETE` da linha
matching (por proveniencia+source_id, comparados em colunas UNINDEXED)
ANTES do `INSERT` no mesmo upsert transacional — equivalente a upsert.

> Filtro por projeto/tipo (FR-012): `WHERE knowledge_fts MATCH ? AND
> project = ? AND type = ?`. Limite (FR-012): `LIMIT ?`. Ordenacao por
> relevancia (FR-010): `ORDER BY bm25(knowledge_fts)`.

---

## Tabela: schema_meta

Metadados do indice (versao de schema, para reindex/migracao).

| Coluna | Tipo | Notas |
|--------|------|-------|
| `key` | TEXT PK | ex: `schema_version` |
| `value` | TEXT | ex: `1` |

> Mudanca de schema do indice → bump `schema_version` → `--reindex`
> recria do zero (FR-014). Indice e descartavel.

---

## Pragmas de conexao (FR-016)

Aplicados em TODA conexao de escrita/leitura:

```sql
PRAGMA journal_mode=WAL;
PRAGMA busy_timeout=5000;
PRAGMA foreign_keys=OFF;   -- tabelas independentes, sem FK
```

Retry/backoff limitado (camada shell) em "database is locked" alem do
busy_timeout: ate N tentativas (ex: 3) com sleep crescente; esgotado →
degradacao graciosa (aviso + skip, FR-018). NAO usa state-lock.sh.

---

## State transitions

O indice e append/upsert-only do ponto de vista de ingestao. Estados de
um registro:

```
(ausente) --ingest--> (presente, versao V1)
(presente V1) --ingest com mesmo conteudo--> (presente V1)   [idempotente, FR-007]
(presente V1) --ingest com conteudo novo (mesma chave)--> (presente V2)  [upsert, FR-008]
(qualquer)   --reindex--> (reconstruido a partir de state.json/history)  [FR-014/015]
(corrompido) --reindex--> (reconstruido)   [US3/FR-014]
```

---

## Security Considerations (A05 Injection, A02, Principio IV)

- **SQL/FTS injection (A05 / CWE-89)**: o `sqlite3` CLI NAO tem bind
  parameters via argv. Toda composicao de SQL (ingestao e busca) escapa
  aspas simples (`'`→`''`, camada SQL) e, na busca, trata a query como
  frase FTS5 com `"`→`""`. O escaping e a defesa primaria — nenhum valor
  (texto livre OU proveniencia) e concatenado cru. Ver contratos.
- **Segredo em campo estruturado/proveniencia (A02)**: campos de
  proveniencia (ex: `project` derivado de `projeto_alvo_path`) e
  estruturados NAO passam pelo filtro de segredos (FR-017, para preservar
  a chave de upsert). Risco residual: um path pode conter um segredo
  (ex: token embutido em URL/path). Mitigacao: (1) `project` armazena o
  **basename** do projeto-alvo por padrao, nao o path absoluto completo,
  reduzindo a chance de capturar segredo em path; (2) o indice e 100%
  local (Principio IV) — nenhum dado sai do ambiente, entao o risco e de
  exposicao local, nao remota; (3) `source_id`/ids/scores/timestamps sao
  enumerados/numericos/curtos, sem superficie pratica para segredo. Esta
  decisao de basename e registrada como Decisao auditavel da onda.
- **Privacidade (Principio IV)**: zero rede, zero upload; `secrets-filter`
  e defesa em profundidade sobre texto livre; nada e transmitido.
- **Degradacao graciosa NAO mascara falha de seguranca**: o exit 0 em
  degradacao graciosa cobre indisponibilidade operacional (dep ausente,
  lock, dir nao-gravavel). Erro de USO (flags) retorna exit 2. Falha de
  escaping nao e "degradada" — e prevenida por construcao (escaping
  obrigatorio + teste adversarial), nao tratada em runtime.

## Invariantes

- **INV-DM-1**: o `state.json` e artefatos transacionais nunca sao
  escritos pela camada de conhecimento (FR-009, SC-006). Toda interacao
  com a fonte e read-only (`jq` so le).
- **INV-DM-2**: reingerir a mesma onda N vezes nao muda a contagem de
  linhas (FR-007, SC-002) — garantido por UNIQUE + ON CONFLICT (tabelas)
  e DELETE-before-INSERT por chave (FTS5).
- **INV-DM-3**: campos da chave de upsert (proveniencia + type +
  source_id) e nomes de skill nunca passam pelo filtro de segredos
  (FR-017). So texto livre e filtrado.
- **INV-DM-4**: o indice e reconstruivel — `--reindex` a partir de
  state.json/history produz conteudo equivalente a ingestao incremental
  (FR-015, SC-005).
