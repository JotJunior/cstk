# Contrato: `GET /api/v1/metrics/model-usage`

**Feature**: `dashboard-refactor` | **Date**: 2026-07-28

> ## [PROPOSTA — a validar na implementação]
>
> **Este endpoint NÃO EXISTE hoje.** Todo o shape de request/response abaixo
> foi **projetado** nesta fase de plano, não extraído de código existente.
> Distinção exigida pela Constitution VI: afirmar como real algo inventado é
> a falha grave; projetar um contrato ainda inexistente é legítimo **desde que
> rotulado**.
>
> O que é **FACTUAL** aqui: a tabela de origem `wave_model_usage`, seu DDL e os
> valores reais observados (verificados por sondagem direta na `knowledge.db`
> v12 — ver research.md §Sondagens, S1–S5).
> O que é **PROPOSTO**: path, query params e nomes dos campos da resposta.
>
> A forma final MUST ser confirmada na implementação pelo cenário
> **Roundtrip End-to-End** do [quickstart.md](../quickstart.md).

---

## Motivação

A granularidade **onda × modelo** existe medida na fonte desde o schema v12
(`wave_model_usage`, cstk 5.33.0) e é aceita na abertura do banco
(`DEFAULT_SCHEMA_VERSIONS` inclui `'12'`, `apps/server/src/config.ts:38`), mas
**nenhuma rota de produção a lê** — a única referência no repositório é o teste
opt-in `apps/server/test/lib/smoke-v12-real.test.ts`, skipado sem `CSTK_SMOKE_DB`.

Nenhum endpoint existente entrega custo por modelo:
`otel-usage` e `otel-cost-over-time` agregam no grão **onda**; `model-mix` e
`model-mix-by-stage` são **derivados** de `decisions.choice` (intenção do
roteador) e não carregam custo nem tokens. Daí a necessidade de rota nova
para FR-003.

---

## Request [PROPOSTA]

```
GET /api/v1/metrics/model-usage
```

Método `GET` exclusivamente (Princípio I — nenhuma rota não-`GET`).

**Query params** — reusar `parseUsageQuery` (`apps/server/src/routes/metrics.ts:209`),
já usado por `otel-usage`, `otel-cost-over-time`, `tokens-over-time` e
`tokens-by-wave`. Não inventar um parser novo:

| Param | Tipo | Default | Obrigatório |
|-------|------|---------|-------------|
| `project` | `string` (1..200, trim) | — | não |
| `feature` | `string` (1..200, trim) | — | não |
| `period` | `'24h' \| '7d' \| '30d' \| 'all'` | `'7d'` | não |

**Rationale de consistência**: `model-mix` e `throughput-by-stage` hoje **não**
aceitam params, o que impede filtrar por projeto/período. O endpoint novo
segue a família `otel-*`/`tokens-*` (que aceita), porque FR-003 fala em
"disponíveis na fonte para o projeto/período selecionado" e SC-005 exige
consistência entre duas telas que compartilham o mesmo seletor.

---

## Response 200 [PROPOSTA]

Envelope padrão (`wrap()`), `data` = `ModelUsageResult`:

```jsonc
{
  "data": {
    "byModel": [
      { "model": "claude-sonnet-5",   "costUsd": 465.3943, "totalTokens": 1127119533, "waves": 36 },
      { "model": "claude-fable-5",    "costUsd": 23.5946,  "totalTokens": 13884110,   "waves": 7  },
      { "model": "claude-opus-5[1m]", "costUsd": 6.1439,   "totalTokens": 6864604,    "waves": 1  }
    ],
    "byStage": [],
    "coverage": {
      "wavesTotal": 920,
      "wavesWithModelUsage": 36,
      "wavesWithOtelCost": 46
    }
  },
  "meta": {
    "degraded": false,
    "reason": null,
    "freshness": { "mtime": "<ISO>", "maxIngestedAt": "<ISO>" },
    "schemaVersion": "12"
  }
}
```

> Os **valores** do exemplo acima são reais (sondagem S3/S5 sobre
> `~/.claude/cstk/knowledge.db`, `period=all`, sem filtro de projeto), não
> placeholders inventados. Os **nomes dos campos** são a proposta.

### Campos

| Campo | Tipo | Nulo? | Semântica |
|-------|------|-------|-----------|
| `byModel[].model` | `string` | não | **string BRUTA do OTel**, sem normalização. `model IS NULL` na origem vira o rótulo literal `'(desconhecido)'` — nunca descartado |
| `byModel[].costUsd` | `number \| null` | **sim** | `sum(cost_usd)`. MEDIDO. `null` = não medido; `0` = medido e deu zero |
| `byModel[].totalTokens` | `number \| null` | **sim** | `sum(total_tokens)`. MEDIDO |
| `byModel[].waves` | `number` | não | ondas distintas que contribuíram |
| `byStage[]` | `ModelUsageByStage[]` | não (pode ser `[]`) | ver §byStage |
| `coverage.wavesTotal` | `number` | não | denominador: ondas do recorte |
| `coverage.wavesWithModelUsage` | `number` | não | ondas com linha em `wave_model_usage` |
| `coverage.wavesWithOtelCost` | `number` | não | ondas com `otel_cost_usd IS NOT NULL` |

**Ordenação**: `byModel` por `costUsd` desc, com `null` por último (SC-001 —
o modelo de maior custo precisa ser o primeiro item).

**`meta.approximate` NÃO é emitido**: o dado é MEDIDO na fonte, não derivado —
diferente de `model-mix`, que emite `approximate: true`.

### §byStage

`wave_model_usage` **não tem coluna de etapa**. O recorte depende de
correlacionar `(project, feature, wave, execution_id)` com `waves` e de a onda
expor a etapa — correlação **não verificada empiricamente** nesta fase.

**Regra dura**: se a junção não render dado confiável na implementação,
`byStage` MUST retornar `[]` (estado "sem dado"), **nunca** um valor derivado
por suposição. FR-009 é atendida independentemente, pela correção do card
existente que usa `decisions` (ver `existing-endpoints.md`).

---

## Response 200 degradado

Princípio II — condição de dado nunca é `5xx`.

| Condição | Detecção | Resposta |
|----------|----------|----------|
| tabela ausente (banco v2–v11) | `hasTable(db,'wave_model_usage')` falso (`apps/server/src/db/columns.ts`) | `data` com `byModel: []`, `byStage: []` e `coverage` com os três campos **`null`** (nunca `0` — ver invariante 1); `meta.degraded=true`, `meta.reason='table-empty'` |
| exceção em **query-time** (ex.: `SQLITE_CORRUPT` mid-read, coluna ausente na junção de `byStage`) | `catch` em volta da query | `200` + `wrapDegraded('db-corrupt', …)` — **nunca** deixar a exceção escapar (ver invariante 7) |
| banco ausente / corrompido / schema fora da lista | caminho já existente de `openDb` (`db/open.ts:94-149`) | `wrapDegraded()` com `db-missing` / `db-corrupt` / `schema-mismatch` |
| tabela presente, zero linhas no recorte | `count(*) = 0` | `200` **não degradado**, `byModel: []` — "sem dado no período" ≠ "métrica não coletada" |

A distinção da última linha é obrigatória: são estados diferentes e a UI já os
trata separadamente via `emptyFallback` do `MetricCard`
(`apps/web/src/screens/Metrics.tsx:169-175`).

**Nenhum `5xx` por condição de dado.**

---

## Invariantes de implementação

1. **`NULL` nunca vira `0`.** Usar `sum()` sem `coalesce` — o `NULL` do SQLite
   quando nenhuma linha tem valor é exatamente a semântica desejada (padrão já
   comentado em `apps/server/src/db/queries/metrics.ts:476-477`). Zod **sem**
   `.default(null)`, seguindo `schemas/entities.ts:48-51`.
2. **Read-only.** Somente `SELECT`. O gate `npm run lint:readonly-check`
   (grep por `INSERT|UPDATE|DELETE|CREATE|DROP|ALTER` em `apps/server/src`)
   MUST continuar verde.
3. **Sem soma entre grandezas.** `costUsd` (medido) nunca é somado a
   `tool_calls` (proxy) nem a `agent_*` (tokens de subagente) — Princípio III,
   emenda 1.2.0.
4. **Rótulo de modelo não alcança contexto de LLM.** `wave_model_usage` não
   alimenta a FTS por desenho da fonte (`config.ts:33-35`); o endpoint não a
   reintroduz na busca.
5. **Dual-def obrigatória.** `ModelUsageResult`, `ModelUsageEntry`,
   `ModelUsageByStage` e `ModelUsageCoverage` exigem interface em
   `packages/shared-types/src/entities.ts` **e** schema Zod espelhado em
   `packages/shared-types/src/schemas/entities.ts`.
6. **Caso de teste ausente hoje.** Nem `throughput-by-stage` nem `model-mix`
   têm teste. O endpoint novo MUST nascer coberto no roundtrip real
   (`apps/server/test/lib/roundtrip.test.ts`).

### Invariantes acrescentadas pelo gate de segurança (owasp-security)

7. **Exceção em query-time nunca vira `5xx`** *(MEDIUM — A10, viola Princípio II)*.
   As rotas de métrica hoje usam `try { … } finally { db.close() }` **sem
   `catch`**, e **não existe `setErrorHandler`** em `apps/server/src/index.ts`
   (verificado: `grep -n setErrorHandler apps/server/src/index.ts` → sem
   resultado). Logo, uma exceção durante a leitura escapa para o handler
   default do Fastify e vira `500` com a mensagem crua do `better-sqlite3` —
   enquanto o contrato só previa degradação no *open*. O endpoint novo MUST
   envolver a query em `catch` → `wrapDegraded('db-corrupt', …)`.
   Recomendado (fora do escopo mínimo): `setErrorHandler` global devolvendo o
   envelope padrão sem detalhe interno.
8. **Binding parametrizado, sem exceção** *(LOW — A05; hoje não há defeito,
   vira invariante de contrato)*. `project` e `feature` MUST ir por `?` com
   `.all(...params)`; `period` MUST passar pelo `switch` de `periodToFilter`
   (`db/queries/metrics.ts:26-34`), que devolve SQL constante. **Nenhum** query
   param pode ser interpolado em template SQL. Nota: `wave_model_usage` **não
   tem** coluna de timestamp de início equivalente a `started_at`, então o
   recorte por período exige um scope novo — é justamente aí que o risco de
   interpolação apareceria.
9. **Cardinalidade não é garantida pelo schema** *(LOW — API4/LLM10)*.
   `model` é string externa de telemetria; hoje são 3 valores no banco real,
   mas nada no schema limita isso. Aplicar `LIMIT` no servidor com bucket
   `'(outros)'` — precedente existente: `tokens-by-wave`
   (`db/queries/metrics.ts:685`, `LIMIT ?`).
10. **Rótulo externo não indexa objeto literal** *(LOW — A03/CWE-1321)*. O
    padrão atual `MODEL_COLOR[m] ?? fallback` (`Metrics.tsx:27`,
    `Overview.tsx:55`) sobre `Record<string,string>` com **chave externa bruta**
    deixa passar chaves da cadeia de protótipo (`constructor`, `toString`),
    cujo valor não-string escapa do `??` e vai para atributo SVG. A função de
    cor desta feature MUST usar `Object.hasOwn`, `Map` ou objeto com protótipo
    `null`.
11. **Resposta degradada não vaza caminho interno** *(LOW — A02)*.
    `GET /api/v1/health` expõe `path: config.dbPath` absoluto
    (`routes/health.ts:58,100`) — pré-existente e fora do escopo, mas **não
    replicar**. O caminho degradado deste endpoint já está correto:
    `wrapDegraded` com `db=null` produz `freshness` vazio e não expõe `dbPath`.

> **Aceito pelo modelo de ameaça, sem ação**: custo em USD por projeto sem
> autenticação (mitigado por bind fixo `127.0.0.1` em `config.ts:152-153` +
> CORS de origem única) e ausência de rate-limit em `/metrics/*` (uso local,
> single-user). Registrado para não ser redescoberto como "novo" depois.
