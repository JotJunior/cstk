# Phase 1 — Data Model: recall-autoconsume

**Feature**: `recall-autoconsume` | **Date**: 2026-05-23 | **Spec**: [spec.md](./spec.md)

Esta feature **LE** o indice de conhecimento; nao define nem altera o schema
persistido. As entidades de armazenamento (`KnowledgeRecord`, `Provenance`,
`KnowledgeIndex`) sao **herdadas** da spec arquivada
[`cstk-knowledge-db`](../_archived/cstk-knowledge-db/spec.md) e estao
documentadas aqui apenas como referencia de leitura (read-only). As entidades
NOVAS desta feature sao transientes (de processo), nao persistidas: `QueryTerms`,
`ContextBlock`, e o evento auditavel `ConsumptionRecord`.

---

## Entity (herdada, read-only): KnowledgeRecord / knowledge_fts

Tabela virtual FTS5 do indice (`~/.claude/cstk/knowledge.db`), populada pela
ingestao da spec arquivada. O modo `--context` LE desta tabela; NAO a altera
(Out of Scope: "mudanca no schema do indice").

| Campo | Tipo | Indexado | Uso no `--context` |
|-------|------|----------|--------------------|
| `body` | TEXT | FTS (indexado) | conteudo casado pela query; truncado no ContextBlock |
| `type` | TEXT | UNINDEXED | proveniencia + filtro `--type` |
| `project` | TEXT | UNINDEXED | proveniencia + filtro `--project` |
| `feature` | TEXT | UNINDEXED | proveniencia + **filtro anti-eco** `--exclude-feature` (FR-005) |
| `wave` | TEXT | UNINDEXED | proveniencia |
| `source_id` | TEXT | UNINDEXED | proveniencia (id de origem) |
| `source_ts` | TEXT | UNINDEXED | proveniencia (timestamp) |

> Schema completo em `cli/lib/recall.sh::recall_schema_ddl`. A coluna `feature`
> ja existe UNINDEXED — anti-eco NAO requer mudanca de schema.

**Ordenacao**: `ORDER BY bm25(knowledge_fts)` (ASC — mais relevante primeiro),
identica ao modo busca. SEM piso de score (FR-007, Decision 1 do research).

---

## Entity (nova, transiente): QueryTerms

Conjunto de termos derivados da feature corrente, usado como entrada do modo
`--context`. NAO persistido — montado em memoria pelo passo PRE-DECISAO do
orquestrador.

| Campo | Tipo | Origem | Regra |
|-------|------|--------|-------|
| `terms` | lista de tokens | `aspectos_chave_iniciais` (primario) ou `descricao_curta` (fallback) | FR-009; teto **<=8 termos** |
| `source_kind` | enum {`aspectos`, `descricao`} | qual fonte foi usada | fallback so se aspectos vazio/degenerado |
| `escaped` | string FTS5 | `terms` apos escape OR | cada token via `fts_phrase_escape`, juntados com ` OR ` (Decision 1) |

**Derivacao** (no orquestrador, via jq):
1. `aspectos_chave_iniciais | .[0:8] | join(" ")` => normaliza kebab (`tr '-' ' '`).
2. Se vazio/so-stopwords => fallback `descricao_curta` (mesmo teto).
3. Se ainda degenerado => query vazia => **zero resultados / no-op** (FR-009).

**State transitions**: `raw (state.json) -> derived (<=8 tokens) -> escaped (FTS5
OR) -> consumida pela query | degenerada -> no-op`.

---

## Entity (nova, transiente): ContextBlock

Artefato de saida do modo `--context` — bloco markdown enxuto, auto-contido,
pronto para injecao em prompt. NAO persistido; emitido em stdout.

| Campo | Tipo | Regra |
|-------|------|-------|
| `header` | linha markdown (blockquote) | `> Aprendizado recuperado (read-back loop) — K achados...` |
| `findings` | lista de linhas | ate **N** (`--limit`, default 4) KnowledgeRecords formatados |
| `finding.line` | string | `- **[<type>]** <project>/<feature>/<wave> (<ts>): <body truncado>` |
| `total_bytes` | int | <= `--max-bytes` (default 2000) — teto duro (FR-006/SC-004) |

**Invariantes**:
- K=0 (sem achados) => ContextBlock **vazio** (stdout vazio, sem header) — no-op.
- `total_bytes` NUNCA excede `--max-bytes` (SC-004): para de adicionar achados ao
  atingir o teto; trunca pelo ultimo achado inteiro que cabe (nao no meio).
- `body` por achado tambem truncado (ex: 280 chars) para um achado gigante nao
  estourar sozinho.
- Achados da feature corrente NAO aparecem (anti-eco, SC-002).

**State transitions**: `query result rows -> [filtro anti-eco aplicado no SQL] ->
montagem linha-a-linha sob teto bytes -> ContextBlock (K achados) | vazio (K=0)`.

---

## Entity (nova): ConsumptionRecord (Decisao auditavel no state.json)

Evento auditavel registrado pelo ORQUESTRADOR (nao pelo modo `--context`) quando
o consumo injeta K>=1 achados. Reusa a entidade `Decisao` ja existente do runtime
(`state-decisions.sh register`) — NAO um formato novo.

| Campo (mapeado p/ Decisao) | Conteudo |
|----------------------------|----------|
| `etapa` | `specify` ou `plan` (fase consumidora) |
| `contexto` | "read-back PRE-DECISAO: K=<n> achados injetados, anti-eco feature=<short>" |
| `justificativa` / `evidencia` | termos derivados (QueryTerms) |
| `escolha` | `injetar-achados` (K>0) |
| `score` | tipicamente 2 (suporte de contexto) |

**Distincao K>0 vs K=0** (FR-017): consumo efetivo (K>0) => registra Decisao.
No-op (K=0) => NAO registra Decisao dedicada (evita ruido); opcionalmente
marcacao leve. Consumido por `review-task` (mede eficacia do read-back loop).

**Localizacao**: `state.json` transacional do runtime (gerenciado pelo
orquestrador). O modo `--context` permanece read-only sobre o `state.json`
(FR-014).

---

## Relacionamentos

```
state.json (feature corrente)
   |  aspectos_chave_iniciais / descricao_curta
   v
QueryTerms (<=8, OR-escaped)
   |  cstk recall --context "<termos>" --exclude-feature <short> --limit N --max-bytes M
   v
knowledge_fts (LE, bm25 ASC, anti-eco feature != <short>)   [read-only, herdada]
   |  top-N rows
   v
ContextBlock (markdown, <= max-bytes)  --> injetado no contexto da onda
   |  se K>0
   v
ConsumptionRecord (Decisao no state.json)  --> auditado por review-task
```

## Premissas de seguranca (FR-015)

O `body` lido ja foi tratado por `secrets-filter.sh scrub` na fronteira de
**ingestao** (FR-017 da spec arquivada). A leitura NAO re-scrub — segura por
construcao. O consumo permanece estritamente local (Principio IV — zero coleta
remota).
