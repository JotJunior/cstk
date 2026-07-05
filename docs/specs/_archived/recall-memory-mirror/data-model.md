# Data Model: Recall Memory Mirror

**Feature**: `recall-memory-mirror` | **Date**: 2026-05-27 | **Phase**: 1 (Design)

Modelo de dados da camada de espelhamento de memorias no `knowledge.db` (SQLite + FTS5).
Aditivo ao schema existente (v3 → v4). Nenhuma tabela existente muda de schema.

## Entity: Memory Entry (`memories`)

Representacao indexada de um arquivo `.md` de auto-memoria do Claude Code. Tabela
relacional DEDICADA, separada da telemetria (C-003). Chave natural `(project, slug)`.

### Schema da tabela `memories`

```sql
CREATE TABLE IF NOT EXISTS memories (
  project       TEXT NOT NULL,   -- basename(projeto_alvo_path) — paridade c/ telemetria
  slug          TEXT NOT NULL,   -- nome do .md sem extensao (ex: feedback_code_in_english)
  type          TEXT NOT NULL,   -- index|feedback|project|reference|user (derivado do prefixo)
  description   TEXT,            -- 1a linha nao-vazia do .md (scrubbed) ou slug humanizado
  body_scrubbed TEXT,            -- conteudo do .md filtrado por secrets-filter.sh
  path          TEXT,            -- path absoluto do .md original (rastreabilidade)
  indexed_at    TEXT,            -- ISO 8601 UTC do momento da indexacao
  PRIMARY KEY (project, slug)
);
```

> `PRIMARY KEY (project, slug)` = chave natural. Garante upsert idempotente via
> `INSERT OR REPLACE` / `INSERT ... ON CONFLICT(project,slug) DO UPDATE` (FR-006, SC-003).

### Campos

| Campo | Tipo | Obrigatorio | Filtrado (scrub) | Notas |
|-------|------|-------------|------------------|-------|
| `project` | TEXT | sim | nao (estruturado) | `basename(projeto_alvo_path)` no ingest; `basename(encoded-segment)` no reindex (limitacao CQ1) |
| `slug` | TEXT | sim | nao (estruturado) | `basename .md` sem extensao; compoe a chave natural |
| `type` | TEXT | sim | nao (enum) | `index`\|`feedback`\|`project`\|`reference`\|`user` (FR-007) |
| `description` | TEXT | nao | SIM (texto-livre) | 1a linha nao-vazia do `.md`; fallback = slug humanizado |
| `body_scrubbed` | TEXT | nao | SIM (texto-livre) | conteudo completo do `.md` apos `secrets-filter.sh scrub` |
| `path` | TEXT | nao | nao (estruturado) | path absoluto do `.md`; passa por `sql_escape` como todo valor |
| `indexed_at` | TEXT | nao | nao (timestamp) | `date -u +%Y-%m-%dT%H:%M:%SZ` |

### Derivacao de `type` (FR-007)

```
basename do .md          -> type
-----------------------     ------
MEMORY.md                -> index
feedback_*.md            -> feedback
project_*.md             -> project
reference_*.md           -> reference
(qualquer outro)         -> user
```
Implementado via `case "$_basename" in MEMORY.md) ...; feedback_*) ...; ...; *) user;; esac`
(POSIX, sem regex/deps).

### Derivacao de `description`

- Primeira linha NAO-vazia do `.md` (apos strip de markdown heading `#`/whitespace),
  passada por `recall_scrub`.
- Fallback (arquivo vazio / so-whitespace, edge case US2 cenario 4): slug humanizado
  (`tr '_-' '  '`). Entrada criada com `body_scrubbed=''` sem erro.

## Relacao com `knowledge_fts` (FTS5 virtual existente)

`memories` ALIMENTA a FTS5 `knowledge_fts` (nao cria FTS propria). Cada memoria gera UMA
linha em `knowledge_fts` com `type='memory'`, espelhando o padrao de decisions/bloqueios:

| Coluna `knowledge_fts` | Valor para memoria |
|------------------------|--------------------|
| `body` | `description + ' ' + body_scrubbed` (scrubbed; buscavel) |
| `type` | `'memory'` (literal — discrimina no filtro `--type memory`) |
| `project` | `project` da memoria |
| `feature` | `'memory'` (literal — `memories` nao tem conceito de feature) |
| `wave` | `'-'` |
| `source_id` | `slug` |
| `source_ts` | `indexed_at` |

Upsert em FTS replica o padrao existente (recall.sh L970-972):
```sql
DELETE FROM knowledge_fts
  WHERE type='memory' AND project='<proj>' AND feature='memory'
    AND wave='-' AND source_id='<slug>';
INSERT INTO knowledge_fts(body,type,project,feature,wave,source_id,source_ts)
  VALUES('<desc + body scrubbed>','memory','<proj>','memory','-','<slug>','<indexed_at>');
```

> Razao do `feature='memory'`: as memorias nao pertencem a uma feature SDD. Usar o literal
> `'memory'` mantem a coluna `feature` (UNINDEXED) preenchida e legivel na renderizacao de
> busca (`[memory] <proj> / memory / - / <ts> (<slug>)`), sem inventar acoplamento.

## Entity: Project Memory Directory (conceitual, nao persistido)

Diretorio `~/.claude/projects/<encoded-path>/memory/` onde o harness persiste auto-memories.

| Atributo | Derivacao |
|----------|-----------|
| `<encoded-path>` (ingest) | `printf '%s' "$projeto_alvo_path" \| sed 's\|^/\|\|; s\|[/_]\|-\|g; s\|^\|-\|'` |
| `project` (ingest) | `basename "$projeto_alvo_path"` |
| `<encoded-path>` (reindex) | varrido de `~/.claude/projects/*/memory/` (já é o encoded) |
| `project` (reindex / reverse) | `basename` do segmento final do encoded-path (ver limitacao) |

### Reverse-derivation no reindex (limitacao CQ1, aceita)

No reindex nao ha `state.json` para mapear encoded→path-original. O `project` e derivado
do proprio encoded-path. Projetos com underscore no basename original ficam inconsistentes
(`my_project` indexado via ingest como `my_project` mas via reindex como `my-project`).
Aceito: ingest e o caminho principal; reindex e reconstrucao corretiva. Documentado em
research.md Decision 3.

## State transitions

`memories` nao tem maquina de estados — e indice derivado, sem ciclo de vida proprio:

```
.md no disco (fonte canonica, imutavel)
        |  ingest / reindex
        v
recall_scrub(body) + derive(type, slug, description, indexed_at)
        |  upsert por (project, slug)
        v
linha em `memories`  ──alimenta──>  linha em `knowledge_fts` (type='memory')
        |  --reindex (rm db + re-le .md)
        v
reconstruida 100% dos .md (SC-002) — NUNCA do state.json (C-004)
```

Operacoes:
- **insert/update**: upsert idempotente por `(project, slug)`. Re-ingest do mesmo arquivo
  atualiza `body_scrubbed`/`description`/`indexed_at`; nunca duplica (SC-003).
- **delete**: NAO implementado nesta feature. Um `.md` removido do disco permanece no
  indice ate o proximo `--reindex` (que recria o DB do zero). Aceito — indice e derivado
  e o reindex e a reconciliacao canonica.
- **read**: via `cstk recall <query>` (FTS unificada) ou `--list-memories` (SELECT direto).

## Constantes de schema afetadas

| Constante (recall.sh) | Antes | Depois |
|-----------------------|-------|--------|
| `RECALL_SCHEMA_VERSION` | `3` | `4` |
| `RECALL_TYPE_ENUM` | `"decision bloqueio retro skill"` | `"decision bloqueio retro skill memory"` |
| DDL (`recall_schema_ddl`) | 9 tabelas + knowledge_fts + schema_meta | + `CREATE TABLE IF NOT EXISTS memories` |
