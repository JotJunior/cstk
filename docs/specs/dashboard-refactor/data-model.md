# Data Model: dashboard-refactor

**Feature**: `dashboard-refactor` | **Date**: 2026-07-28 | **Phase**: 1
**Spec**: [spec.md](./spec.md) | **Research**: [research.md](./research.md)

> O painel é **read-only** (Princípio I). Este documento não define migrations,
> não cria tabelas e não altera a fonte. Descreve (a) a estrutura REAL já
> existente na `knowledge.db` que a feature passa a ler, e (b) os DTOs
> derivados que a feature introduz na borda API↔UI.

---

## Parte A — Estruturas de origem (JÁ EXISTEM, read-only)

### Entity: `wave_model_usage` (tabela, schema v12)

Grão: **onda × modelo**. Origem: `cstk recall --ingest` a partir da telemetria
OTel do Claude Code (cstk 5.33.0, feature `otel-model-breakdown`).

DDL verificado por sondagem direta no banco real (não transcrito de memória):

| Campo | Tipo SQLite | Nulo? | Notas |
|-------|-------------|-------|-------|
| `id` | INTEGER | NOT NULL | PK AUTOINCREMENT |
| `project` | TEXT | NOT NULL | nome canônico do projeto |
| `feature` | TEXT | NOT NULL | short-name da feature |
| `wave` | TEXT | NOT NULL | id da onda (ex.: `onda-004`) |
| `execution_id` | TEXT | NOT NULL | id da execução |
| `source_ts` | TEXT | NOT NULL | timestamp da origem |
| `source_id` | TEXT | NOT NULL | id do registro na origem |
| `model` | TEXT | **NULLABLE** | **string BRUTA do OTel** (ver Decision 2) |
| `cost_usd` | REAL | **NULLABLE** | custo MEDIDO em USD, fracionário |
| `total_tokens` | INTEGER | **NULLABLE** | tokens MEDIDOS |
| `ingested_at` | TEXT | NOT NULL | quando o índice absorveu a linha |

**Constraint**: `UNIQUE(project, feature, wave, source_id)`.

**Valores reais observados em `model`** (sondagem S3 do research.md):
`claude-sonnet-5`, `claude-fable-5`, `claude-opus-5[1m]`. São strings brutas —
**não** as chaves curtas `haiku`/`sonnet`/`opus` usadas por `MODEL_COLOR` no
front, que vêm de outro domínio (`decisions.choice`).

**Não alimenta a FTS**: por desenho da fonte, o rótulo de modelo vem de fonte
externa e nunca deve alcançar contexto de LLM (`apps/server/src/config.ts:33-35`).

**Estados possíveis** (os três MUST permanecer distintos — Princípio III):

| Estado | Como se manifesta | Renderização exigida |
|--------|-------------------|----------------------|
| tabela ausente | banco v2–v11; `hasTable()` falso | `meta.degraded=true`, `reason='table-empty'`; card "métrica não coletada nesta fonte" |
| tabela presente, sem linha no recorte | `count(*) = 0` para o filtro | "sem dado para este período/projeto" |
| medido | linhas com `cost_usd`/`total_tokens` não nulos | valor + cobertura da amostra |

`cost_usd`/`total_tokens` nulos numa linha existente **não** viram `0`.

---

### Entity: `waves` — colunas `otel_*` (schema v11) e `agent_*` (schema v10)

Grão: **onda**. Já consumidas hoje (`OtelUsageRollup`, `AgentUsageRollup`).
Relevantes aqui apenas como **denominador de cobertura** e como grandeza
vizinha que NÃO pode ser somada à nova.

- v11 (`OTEL_USAGE_COLUMNS`, `apps/server/src/db/queries/waves.ts:65`):
  `otel_cost_usd`, `otel_cost_main_usd`, `otel_cost_subagent_usd`,
  `otel_total_tokens`, `otel_subagent_tokens` — custo REAL por **onda**,
  sem quebra por modelo.
- v10 (`AGENT_USAGE_COLUMNS`, `waves.ts:16`): 9 colunas `agent_*` — consumo
  medido de subagentes.
- v12 acrescenta 8 colunas `otel_{main,subagent}_{input,output,cache_read,cache_creation}_tokens`
  (verificadas por `PRAGMA table_info(waves)`), **fora do escopo desta feature**.

**Invariante de não-soma (Princípio III, emenda 1.2.0)**: `otel_cost_usd`,
`agent_*` e `tool_calls` são três grandezas distintas e **MUST NOT** ser
somadas ou substituídas entre si num mesmo indicador.

---

### Entity: `decisions` — origem do mix DERIVADO (inalterada)

Alimenta `throughput-by-stage` (`count(*) … GROUP BY stage`), `model-mix` e
`model-mix-by-stage` (`choice LIKE 'model:%'`). Continua sendo **derivada** e
rotulada `meta.approximate=true`. Esta feature **não** altera essas queries;
apenas corrige o consumo do campo `stage` no front (Decision 6) e aplica
truncamento/ordenação na apresentação.

---

## Parte B — DTOs introduzidos pela feature

> **Regra de borda inegociável**: cada DTO abaixo exige **duas** declarações —
> interface manual em `packages/shared-types/src/entities.ts` **e** schema Zod
> espelhado em `packages/shared-types/src/schemas/entities.ts`. Ver
> `plan.md` §Convenções de Borda.

Todos marcados **[PROPOSTA — a validar na implementação]**: são shapes novos,
projetados aqui, não contratos existentes.

### DTO: `ModelUsageEntry` [PROPOSTA]

Uma linha do breakdown por modelo, já agregada no recorte pedido.

| Campo | Tipo TS | Nulo? | Origem | Notas |
|-------|---------|-------|--------|-------|
| `model` | `string` | não | `wave_model_usage.model` | string BRUTA; linhas com `model IS NULL` viram o rótulo literal `'(desconhecido)'`, nunca são descartadas |
| `costUsd` | `number \| null` | **sim** | `sum(cost_usd)` | `null` = não medido; `0` = medido e deu zero |
| `totalTokens` | `number \| null` | **sim** | `sum(total_tokens)` | idem |
| `waves` | `number` | não | `count(DISTINCT project || feature || wave)` | quantas ondas contribuíram |

**Invariante**: `sum()` do SQLite retorna `NULL` quando nenhuma linha tem
valor — semântica desejada, **sem** `coalesce` (mesmo padrão comentado em
`apps/server/src/db/queries/metrics.ts:476-477`).

### DTO: `ModelUsageCoverage` [PROPOSTA]

Cobertura da amostra — exigida por FR-005 e pelo Princípio III.

| Campo | Tipo TS | Nulo? | Notas |
|-------|---------|-------|-------|
| `wavesTotal` | `number \| null` | **sim** | ondas do recorte (denominador) |
| `wavesWithModelUsage` | `number \| null` | **sim** | ondas com linha em `wave_model_usage` |
| `wavesWithOtelCost` | `number \| null` | **sim** | ondas com `otel_cost_usd IS NOT NULL` |

**O objeto `coverage` está sempre presente; seus campos, não.** No estado
degradado (`table-empty`, banco ausente/corrompido) os três campos são `null`,
**nunca `0`** — a mesma invariante que vale para `costUsd`/`totalTokens`. Um
`wavesTotal: 0` num banco que tem 920 ondas seria fabricação: afirmaria "o
denominador é zero" quando o correto é "não foi possível medir". `null` no
denominador faz a UI cair no estado "métrica não coletada", que é o fato.

**Por que três números e não uma razão**: a sondagem S5 mostra que
`wavesWithOtelCost` (46) ≠ `wavesWithModelUsage` (36) sobre `wavesTotal` (920)
no banco real. Fundir num único `coverage` esconderia as 10 ondas com custo
total medido e sem breakdown por modelo (research.md, Decision 3).

### DTO: `ModelUsageResult` [PROPOSTA]

Corpo de `data` do endpoint novo.

| Campo | Tipo TS | Notas |
|-------|---------|-------|
| `byModel` | `ModelUsageEntry[]` | ordenado por `costUsd` desc, `null` por último |
| `byStage` | `ModelUsageByStage[]` | recorte adicional (ver abaixo); `[]` quando não resolvível |
| `coverage` | `ModelUsageCoverage` | sempre presente |

### DTO: `ModelUsageByStage` [PROPOSTA]

| Campo | Tipo TS | Nulo? | Notas |
|-------|---------|-------|-------|
| `stage` | `string` | não | etapa do pipeline |
| `model` | `string` | não | string bruta |
| `costUsd` | `number \| null` | sim | idem `ModelUsageEntry` |
| `totalTokens` | `number \| null` | sim | idem |

> **Aviso de viabilidade [PROPOSTA]**: `wave_model_usage` **não tem** coluna de
> etapa. O recorte por etapa depende de correlacionar `(project, feature, wave,
> execution_id)` com a onda correspondente em `waves`, e de a onda expor a
> etapa. Essa correlação **não foi verificada empiricamente nesta fase** — se
> na implementação a junção não render dado confiável, `byStage` MUST retornar
> `[]` (estado "sem dado") em vez de um valor derivado por suposição.
> A FR-009 (mix por etapa com contexto) é atendida independentemente disso
> pela correção do card existente, que usa `decisions` — ver Decision 6.

---

## Parte C — View models puros do front

Não são DTOs de borda; são o resultado das funções puras (Decision 5),
testáveis sem React.

### `TruncatedBars` — FR-006/007/008

| Campo | Tipo | Notas |
|-------|------|-------|
| `bars` | `{ label: string; value: number }[]` | no máximo 11 itens |
| `othersLabel` | `string \| null` | `'Outros'` quando houve agregação; `null` caso contrário |
| `othersMembers` | `string[]` | etapas somadas em "Outros" (FR-007 + cenário 3 da User Story 3: o usuário precisa saber quais foram) |

**Regras**: entrada ordenada por volume desc; ficam nomeadas as 10 maiores; da
11ª em diante somam-se numa barra `Outros`. Com exatamente 10 entradas,
`othersLabel` é `null` (edge case explícito da spec). Com 11, a barra `Outros`
existe representando uma única etapa (edge case explícito da spec).
**Invariante SC-002**: `bars.length <= 11` sempre.

### `StageOrdered` — FR-009

Ordenação por `SDD_STAGES` (`apps/web/src/lib/constants.ts`); etapas fora da
constante vão ao fim por volume desc, com o rótulo real preservado
(research.md, Decision 7).

---

## Relacionamentos

```
executions 1 ─── N waves
                   │ (project, feature, wave, execution_id)
                   └── N wave_model_usage        [grão onda × modelo]
                        └── model (string bruta OTel), cost_usd, total_tokens

decisions ─── stage, choice LIKE 'model:%'  [DERIVADO — dono externo]
```

Fronteira semântica que o plano MUST preservar: o ramo `wave_model_usage` é
**medido**; o ramo `decisions` é **derivado/aproximado** e tem dono canônico
fora do painel (`model-routing-report.sh`, Princípio IV). Os dois nunca são
somados nem apresentados como a mesma coisa.

---

## State transitions

**N/A** — feature read-only. Nenhuma entidade muda de estado por ação do
painel (Princípio I). A única "transição" observável é a da fonte: uma onda
sem breakdown passa a tê-lo quando `cstk recall --ingest` roda — o que a UI
reflete como mudança de cobertura, jamais como escrita.
