# Contract: API Read-Only `GET /api/v1/*`

**Prefixo**: `/api/v1`. **Todos os endpoints são `GET`** (Princípio I — zero
mutação). Todos retornam o envelope de [`envelope.md`](./envelope.md).
Filtros globais aplicáveis: `project`, `feature`, `status`, `period`, `q`.

> O `data` descrito é o shape em **camelCase** (saída do mapper). Tipos completos
> em `packages/shared-types/src/entities.ts`. Detalhe de cada coluna em
> [`../data-model.md`](../data-model.md).

## Saúde e visão geral

| Endpoint | `data` (shape resumido) |
|----------|-------------------------|
| `GET /health` | `{ ok, dbReachable, quickCheck, counts: { executions, waves, decisions, ... } }` (sempre 200, mesmo degradado) |
| `GET /overview?period=` | `{ kpis: {...}, recentAlerts: AlertSignal[], inProgress: Execution[], leaderboard: [...], funnel: [...] }` |

`overview.kpis` inclui custo agregado como `toolCallsTotal` rotulado "proxy:
tool calls" (Princípio III — nunca `$`/tokens).

## Projetos e features

| Endpoint | `data` |
|----------|--------|
| `GET /projects` | `ProjectRollup[]` (project + contadores agregados) |
| `GET /projects/{project}` | `{ project, rollup, features: FeatureRollup[] }` |
| `GET /features?project=&status=` | `FeatureRollup[]` |
| `GET /features/{project}/{feature}` | `{ feature, rollup, executions: Execution[] }` |

## Execução (detalhe e sub-recursos)

| Endpoint | `data` |
|----------|--------|
| `GET /executions/{execucaoId}` | `Execution` (+ rollups) |
| `GET /executions/{execucaoId}/waves` | `Wave[]` (WavesTimeline) |
| `GET /executions/{execucaoId}/decisions?wave=&etapa=&score=&limit=&offset=` | `Decision[]` **paginado** (UNTRUSTED) |
| `GET /executions/{execucaoId}/tasks` | `{ tasks: Task[], passRate }` |
| `GET /executions/{execucaoId}/events` | `Event[]` |
| `GET /executions/{execucaoId}/alerts` | `AlertSignal[]` |
| `GET /executions/{execucaoId}/bloqueios` | `Bloqueio[]` (UNTRUSTED) |
| `GET /executions/{execucaoId}/skills` | `Skill[]` |

## Cross-execução

| Endpoint | `data` |
|----------|--------|
| `GET /alerts?tipo=&project=&feature=&period=` | `AlertSignal[]` (+ drill-down refs) |
| `GET /tasks?project=&feature=&outcome=` | `Task[]` |
| `GET /events?event_type=&project=&period=` | `Event[]` |

## Métricas agregadas

| Endpoint | `data` | `meta.approximate` |
|----------|--------|--------------------|
| `GET /metrics/cost-over-time?project=&period=` | série `[{ day, toolCalls }]` ("proxy: tool calls") | false |
| `GET /metrics/throughput-by-stage` | `[{ etapa, count }]` | false |
| `GET /metrics/test-pass-rate` | `{ pass, fail, rate }` | false |
| `GET /metrics/human-latency` | `[{ bucket, latenciaSegundos }]` | false |
| `GET /metrics/clarify-resolution` | `{ rate, ... }` | **true** (derivada/aproximada) |
| `GET /metrics/decisions-by-score` | `[{ score: 0..3, count }]` | false |
| `GET /metrics/execution-duration` | `[{ execucaoId, duracaoSegundos }]` | false |
| `GET /metrics/depth-subagents` | `[{ profundidadeMax, subagentesSpawned }]` | false |

> Mix de modelos **não tem endpoint** — Princípio IV / D3 Opção A. A UI exibe
> card "indisponível nesta fonte" (`reason: unavailable-in-source`).

## Busca

| Endpoint | `data` |
|----------|--------|
| `GET /search?q=&type=&project=&feature=&limit=&offset=` | `{ results: FtsHit[], pagination }` — ver [`search-fts.md`](./search-fts.md) |

## Invariantes de superfície (auditáveis — SC-003)

- Nenhuma rota não-`GET`. Nenhum verbo SQL de mutação no código.
- Toda resposta passa pelo wrapper de envelope + headers de [`envelope.md`].
- Listas `decisions` e `search` **sempre** paginadas (SC-008).
