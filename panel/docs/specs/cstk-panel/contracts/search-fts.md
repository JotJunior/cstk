# Contract: Busca FTS5 (`GET /api/v1/search`)

**Princípio V (FR-012)**: escaping de **duas camadas** — tokenização com aspas
(camada FTS5) + binding parametrizado SQL (camada SQL). Proibida interpolação de
string crua. Entrada hostil → resultado válido ou vazio, **nunca** `5xx`
(SC-005).

## Request

```
GET /api/v1/search?q=<termo>&type=<tipo>&project=<p>&feature=<f>&limit=<n>&offset=<o>
```

| Param | Regra (Zod) |
|-------|-------------|
| `q` | obrigatório, string, trim, máx ~200 chars |
| `type` | opcional (ex: `decision`) — filtra coluna UNINDEXED `type` |
| `project`/`feature` | opcionais — filtram colunas UNINDEXED |
| `limit` | `1..50` (default 20) — busca é mais custosa |
| `offset` | `>= 0` |

Rate-limit leve aplicado a este endpoint (FR-020).

## Pipeline de escaping (camada 1 — FTS5)

1. `trim` + validação de tamanho.
2. Tokenizar por whitespace.
3. Para cada token: escapar aspas duplas internas duplicando-as (`"` → `""`) e
   **envolver o token em aspas duplas** → vira *phrase token* literal.
4. Juntar os tokens com espaço (semântica FTS5 = AND implícito de frases).
5. Operadores FTS (`AND`/`OR`/`NEAR`/`*`/`(`/`)`) digitados pelo usuário são
   tratados como **texto literal** (dentro das aspas), não como sintaxe — evita
   erro de parser e injeção de operador.

Exemplo: entrada `read-only "ataque") OR 1=1` →
`"read-only" """ataque""" """ OR" "1=1"` (todos literais, nada quebra o parser).

## Pipeline de escaping (camada 2 — SQL)

A string FTS resultante é passada via **placeholder `?`**:

```sql
SELECT body, type, project, feature, wave, source_id, source_ts,
       bm25(knowledge_fts) AS rank
FROM knowledge_fts
WHERE knowledge_fts MATCH ?      -- string FTS escapada (camada 1)
  AND (? IS NULL OR type = ?)    -- filtros opcionais, todos parametrizados
ORDER BY rank
LIMIT ? OFFSET ?;
```

**Nunca** concatenar/interpolar a query. Todos os valores via binding.

## Response

```json
{
  "data": {
    "results": [
      {
        "body": "<corpo do match — UNTRUSTED, texto puro>",
        "type": "decision",
        "project": "claude-ai-tips",
        "feature": "cstk-panel",
        "wave": "onda-003",
        "sourceId": "dec-018",
        "sourceTs": "2026-05-24T...",
        "rank": -3.21
      }
    ],
    "pagination": { "limit": 20, "offset": 0, "total": 1019 }
  },
  "meta": { "degraded": false, "reason": null, "freshness": {...}, "schemaVersion": "2" }
}
```

- `rank`: score bm25 (menor = mais relevante; ordenação ascendente).
- `body` é **UNTRUSTED**: o FE renderiza como text node (sem `dangerouslySetInnerHTML`,
  sem interpretar markup — Princípio V / FR-011/FR-013).
- Drill-down: `(type, project, feature, wave, sourceId)` navega à fonte.

## Casos de degradação/borda

| Situação | Resposta |
|----------|----------|
| base ausente/corrompida | `200` + `data:{results:[],pagination}` + `meta.degraded=true` |
| `q` vazio após trim | `400` (validação — não é estado de dado) |
| FTS sem resultados | `200` + `results: []` (estado vazio, não erro) |
| sintaxe FTS hostil | `200` + resultados ou vazio (escaping garante) — **jamais** `5xx` |
