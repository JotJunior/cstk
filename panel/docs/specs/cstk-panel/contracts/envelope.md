# Contract: Envelope Padrão, Headers e Degradação

**Aplica-se a**: todos os 29 endpoints `GET /api/v1/*`.

## Envelope de resposta (FR-023)

Toda resposta de leitura usa o envelope:

```json
{
  "data": "<payload tipado por endpoint>",
  "meta": {
    "degraded": false,
    "reason": null,
    "freshness": { "mtime": "2026-05-24T13:31:00Z", "maxIngestedAt": "2026-05-24T13:30:58Z" },
    "schemaVersion": "2",
    "approximate": false,
    "pagination": { "limit": 50, "offset": 0, "total": 875 }
  }
}
```

Regras:
- `data`: payload do endpoint. Em degradação, `data` é o vazio **tipado** do
  recurso (`[]` para listas, `null`/objeto vazio para detalhes) — nunca ausente.
- `meta.degraded` (boolean) + `meta.reason` (string|null): sinal de 1ª classe.
- `meta.freshness`: `mtime` do arquivo da base + `maxIngestedAt`
  (`max(ingested_at)` do recurso). **Sempre presente** (Princípio VI).
- `meta.schemaVersion`: `"2"`. Se a base tiver outra versão → `degraded:true`,
  `reason:"schema-mismatch"`.
- `meta.approximate` (boolean): `true` em métricas derivadas/aproximadas
  (clarify-resolution, severidade derivada). (Princípio III / FR-009)
- `meta.pagination`: presente em `decisions`, `search` e demais listas paginadas.

## Razões de degradação (`meta.reason`)

| reason | Quando | data |
|--------|--------|------|
| `db-missing` | arquivo da base ausente | vazio tipado |
| `db-corrupt` | `PRAGMA quick_check` ≠ `ok` | vazio tipado |
| `schema-mismatch` | `schema_version` ≠ `2` | vazio tipado |
| `table-empty` | recurso sem linhas | `[]` |
| `unavailable-in-source` | dado com dono externo (mix de modelos) | `null` + card UI (Princípio IV) |

> **Nunca** `5xx` por condição de dado (Princípio II / SC-001). `5xx` reservado a
> falhas de programação genuínas (bug), não a estado da base.

## Headers (FR-019, FR-016)

| Header | Valor |
|--------|-------|
| `Content-Type` | `application/json; charset=utf-8` |
| `X-Content-Type-Options` | `nosniff` |
| `ETag` | `W/"<mtime_epoch>-<maxIngestedAt>"` (por recurso) |
| `Cache-Control` | `no-cache` (revalidação obrigatória via ETag) |

`If-None-Match` casando o `ETag` corrente → **`304 Not Modified`** (corpo
vazio). Invalidação por `mtime` + `max(ingested_at)` (Princípio VI).

## CORS e bind (FR-017)

- Servidor faz bind em `127.0.0.1` por padrão (configurável, mas não `0.0.0.0`
  por default).
- CORS restrito à origem do front-end (ex: `http://localhost:5173` em dev).
- Sem autenticação/RBAC reais no MVP (login decorativo, se existir).

## Validação de entrada (Zod, FR-018, FR-020)

| Param | Regra |
|-------|-------|
| `period` | enum `24h \| 7d \| 30d \| all` (default `7d`) |
| `limit` | inteiro `1..200` (default `50`) |
| `offset` | inteiro `>= 0` (default `0`) |
| `score` | inteiro `0..3` |
| `q` | string, tamanho máximo (ex: 200 chars), trim |
| path do DB | **canonicalizado e confinado** (config > `$CSTK_KNOWLEDGE_DB` > default); **nunca** vindo do cliente |

Entrada inválida → `400` com envelope de erro de **validação** (não de dado);
isso não viola Princípio II (é erro de requisição malformada, não de estado da
base).
