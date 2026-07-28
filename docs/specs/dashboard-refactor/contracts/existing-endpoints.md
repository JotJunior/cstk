# Contratos EXISTENTES tocados pela feature

**Feature**: `dashboard-refactor` | **Date**: 2026-07-28

> **Status: REAL.** Tudo neste arquivo foi extraído do código-fonte do
> servidor, com arquivo e linha citados. Nenhum campo foi suposto
> (Constitution VI). Contrato existente não se inventa.
>
> Endpoints marcados **INALTERADO** têm o contrato reproduzido apenas para
> referência do consumo no front — a feature não muda o payload.

---

## Envelope universal (todas as rotas)

Fonte: `apps/server/src/lib/envelope.ts` — `wrap()` / `wrapDegraded()`.

```jsonc
{
  "data": <payload da rota>,
  "meta": {
    "degraded": false,
    "reason": null,
    "freshness": { "mtime": "<ISO>", "maxIngestedAt": "<ISO>" },
    "schemaVersion": "12",
    "approximate": true   // presente apenas em métricas derivadas
  }
}
```

`DegradedReason` (`packages/shared-types/src/envelope.ts`): `db-missing`,
`db-corrupt`, `schema-mismatch`, `table-empty`, `project-path-unresolved`,
`project-path-inaccessible`.

**Superfície é exclusivamente `GET`** (Princípio I).

---

## `GET /api/v1/overview` — INALTERADO

Fonte: `apps/server/src/routes/overview.ts:50`. Suporta `ETag` / `If-None-Match` → `304`.

**Query params** (`QuerySchema`, `overview.ts:25`):

| Param | Tipo | Default | Notas |
|-------|------|---------|-------|
| `period` | `'24h' \| '7d' \| '30d' \| 'all'` | `'7d'` | — |
| `project` | `string` (1..200, trim) | — | opcional |

**`data`** (campos relevantes a esta feature):

| Campo | Shape |
|-------|-------|
| `kpis` | `{ totalExecutions, activeExecutions, completedExecutions, abortedExecutions, totalWaves, totalDecisions, toolCallsTotal, wallclockTotal, testsPassed, testsTotal, totalProjects, totalFeatures, agentUsage, otelUsage }` |
| `modelMix[]` | `{ model, n }` — DERIVADO de `decisions.choice` |
| `costSeries[]`, `tokenSeries[]`, `otelCostSeries[]` | `number[]` |
| `leaderboard[]` | `{ executionId, project, feature, status, toolCallsTotal, wavesTotal, decisionsTotal }` |
| `funnel[]` | `{ stage, count }` |
| `inProgress[]` | `{ executionId, project, feature, status, currentStage, startedAt, wavesTotal, toolCallsTotal, wallclockTotalSeconds }` |
| `recentAlerts[]` | `{ executionId, type, subtype, description, wave, consumedValue, thresholdValue }` |
| `recentActivity[]` | `{ executionId, project, feature, wave, eventType, timestamp, description }` |
| `projectRollups[]`, `featureRollups[]` | rollups por projeto / feature |

**Impacto da feature**: **nenhum no payload.** FR-001 e FR-002 removem apenas a
**renderização** dos cards que consomem `leaderboard[].toolCallsTotal` e
`funnel[]`. Os campos permanecem no contrato (research.md, Decision 9).

---

## `GET /api/v1/metrics/throughput-by-stage` — INALTERADO (payload)

Fonte: rota `apps/server/src/routes/metrics.ts:65`; query
`apps/server/src/db/queries/metrics.ts:85`.

**Query params**: **nenhum.** (Não aceita `period` nem `project`; o seletor
global de período da UI não afeta este card.)

**`data`**: `[{ "stage": string, "count": number }]`

SQL — **paráfrase semântica**, não transcrição literal:

```sql
SELECT stage, count(*) as count
FROM decisions
WHERE stage IS NOT NULL
GROUP BY stage
ORDER BY count DESC
```

> O código real (`db/queries/metrics.ts:89`) é
> `SELECT ${stageCol} as stage, count(*) as count`, com o nome da coluna
> **interpolado** a partir de uma sonda `hasColumn` (mesmo padrão degradante de
> `agentUsageSelect`/`otelUsageSelect`). A semântica é a acima; o texto não é
> literal. A interpolação é de **nome de coluna resolvido no servidor**, nunca
> de dado vindo do cliente.

**Sem `LIMIT`** — a resposta traz todas as etapas distintas.

**Nota de veracidade (defeito de rótulo)**: o subtítulo exibido hoje na UI diz
*"soma tool_calls por etapa SDD"* (`apps/web/src/screens/Metrics.tsx:487`), mas
a query **conta decisões**, não soma `tool_calls`. O rótulo está factualmente
errado e MUST ser corrigido junto com FR-006/007/008 — exibir "tool_calls" para
uma contagem de decisões viola o Princípio III (natureza do número explícita).

**Impacto da feature**: truncamento top-10 + "Outros" é aplicado **no
consumidor** (função pura), sem mudar o payload (research.md, Decision 5).

---

## `GET /api/v1/metrics/model-mix` — INALTERADO

Fonte: `apps/server/src/routes/metrics.ts:169`; query `db/queries/metrics.ts:355`.

**Query params**: nenhum.
**`data`**: `[{ "modelo": string, "n": number }]`
**`meta.approximate`**: `true`

Derivado de `decisions.choice LIKE 'model:%'` com `replace(choice,'model:','')`.
É **intenção do roteador**, não consumo medido. Dono canônico da lógica de
model-routing é externo ao painel (`model-routing-report.sh`, Princípio IV) —
esta feature **não** estende nem reimplementa a heurística.

> Atenção ao nome do campo: `modelo` (pt), diferente de `model` (en) usado em
> `/overview.modelMix[]`. Divergência REAL do código atual, reproduzida aqui
> como está. Não é alterada por esta feature.

---

## `GET /api/v1/metrics/model-mix-by-stage` — payload INALTERADO, consumo CORRIGIDO

Fonte: `apps/server/src/routes/metrics.ts:180`; query `db/queries/metrics.ts:369`.

**Query params**: nenhum.
**`data`**: `[{ "stage": string, "modelo": string, "n": number }]`
**`meta.approximate`**: `true`

SQL projeta a coluna como `stage`. Linha real (`db/queries/metrics.ts:374`):

```sql
SELECT ${stageCol} as stage, replace(${choiceCol}, 'model:', '') as modelo, count(*) as n
```

> **Payload MISTO pt/en — atenção.** O mesmo objeto traz `stage` (inglês) e
> `modelo` (português). A migração pt-BR→EN do schema v7 **não** alcançou este
> alias. Consumir `model` em vez de `modelo` aqui quebra o card.

**Defeito de consumo a corrigir (FR-009)**: o front lê `r.etapa`
(`apps/web/src/screens/Metrics.tsx:726`) **sem fallback** para `r.stage` —
nome legado do schema pré-v7. Resultado: todas as linhas colapsam no rótulo
`'?'` e o gráfico empilhado perde o contexto de etapa. É a causa raiz do
sintoma descrito na User Story 4. Ver research.md, Decision 6.

**Impacto da feature**: corrigir a leitura para `stage` + ordenar por
`SDD_STAGES`. Payload inalterado.

---

## `GET /api/v1/metrics/otel-usage` — INALTERADO

Fonte: `apps/server/src/routes/metrics.ts:240`; params via `parseUsageQuery`
(`metrics.ts:209`): `project`, `feature`, `period`.

**`data`**: `OtelUsageResult` (7 campos), agregado no grão **onda** — **sem**
quebra por modelo. Guarda de versão: `if (!hasOtelUsage(db)) return { ...EMPTY_OTEL_USAGE }`
(`db/queries/metrics.ts:539`), com todos os campos `null`, nunca `0`.

**Relevância**: é o denominador `wavesWithOtelCost` da cobertura (FR-005) e a
grandeza que **MUST NOT** ser somada ao custo por modelo.

---

## `GET /api/v1/metrics/otel-cost-over-time` — INALTERADO

Fonte: `apps/server/src/routes/metrics.ts:252`. Params: `project`, `feature`, `period`.

**`data`**: `[{ day, costUsd, costMainUsd, costSubagentUsd, wavesWithOtel }]`

Séries **omitem** dias sem medição (`WHERE otel_cost_usd IS NOT NULL`,
`db/queries/metrics.ts:582`) — dia sem dado não vira `0`.
