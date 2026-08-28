# Implementation Plan: cstk-panel — Dashboard de Observabilidade Read-Only

**Feature**: `cstk-panel`
**Branch/Dir**: `docs/specs/cstk-panel/`
**Created**: 2026-05-24
**Spec**: [`spec.md`](./spec.md)
**Constitution**: [`../../constitution.md`](../../constitution.md) (v1.0.0)
**Input**: spec.md (6 user stories, 23 FR, 8 SC) + constitution v1.0.0 (6 Core
Principles MUST) + briefing consolidado + protótipo visual

## Summary

Requisito primário: um **dashboard de observabilidade read-only** sobre a
`knowledge.db` (índice SQLite + FTS5, schema v2) das execuções dos
orquestradores `agente-00c` / `feature-00c`. O painel **apenas observa** — não
escreve, não muta, não reconstrói o índice.

Abordagem técnica: monorepo Node.js + TypeScript com duas aplicações — um
**back-end HTTP read-only** (`better-sqlite3` síncrono, DSN
`mode=ro&immutable=1`) expondo 29 endpoints `GET /api/v1/*` num envelope padrão
`{ data, meta }`, e um **front-end SPA React 19 + Vite** que recria
pixel-perfect o protótipo de referência. Um pacote `shared-types` compartilha as
definições TypeScript dos DTOs entre as duas camadas (toolchain Node único). Os
6 princípios constitucionais são tratados como invariantes de design, não como
features opcionais.

## Technical Context

| Campo | Valor |
|-------|-------|
| **Linguagem/Runtime** | TypeScript 5.x sobre Node.js 20+ LTS (ambas camadas) |
| **Back-end HTTP** | Fastify 5 (overhead baixo, schema-first, hooks de cache/headers nativos) |
| **Driver SQLite** | `better-sqlite3` (síncrono, maduro, suporta `readonly`+`fileMustExist` e PRAGMA) |
| **Front-end** | React 19 + Vite 5 + TypeScript; SWC |
| **Estado/fetch FE** | TanStack Query (cache, `If-None-Match`/304, estados loading/error de 1ª classe) |
| **Roteamento FE** | React Router v6 (hash router para paridade com protótipo) |
| **Validação** | Zod (query params no BE; parse de resposta no FE) |
| **Tipos compartilhados** | pacote `packages/shared-types` (DTOs + envelope) |
| **Storage** | SQLite 3 + FTS5, schema v2, somente-leitura imutável. **Sem persistência própria.** |
| **Testing** | Vitest (unit + integração com `knowledge.db` real read-only); Playwright opcional p/ smoke de UI |
| **Platform** | macOS/Linux dev; bind `localhost` por padrão; sem container obrigatório no MVP |
| **Performance** | Resposta de leitura síncrona < 50ms p95 em base de ~3MB; busca FTS5 com rate-limit leve |
| **Escala** | Uso individual/ferramental; base atual ~12 execuções / 875 decisões / 1019 FTS rows |
| **NEEDS CLARIFICATION restantes** | 0 (D1 resolvido em clarify; D2/D3/D5 resolvidos como decisões de plano em `research.md`) |

> Stack inferida e confirmada: D1 (Node/TS) já decidido em clarify (dec-016).
> Não há `package.json`/`go.mod`/`pyproject.toml` no projeto-alvo ainda — código
> a criar do zero. Schema v2 verificado **empiricamente** via `sqlite3` em
> `mode=ro&immutable=1` sobre `~/.claude/cstk/knowledge.db`.

## Constitution Check

*GATE: Deve passar antes do Phase 0. Re-checado após Phase 1 (§Re-check).*

| Princípio | Status | Notas |
|-----------|--------|-------|
| **I. Read-Only Absoluto (NON-NEGOTIABLE)** | PASS | Conexão única `better-sqlite3` com `{ readonly: true, fileMustExist: false }` + PRAGMA `query_only=1`; DSN `mode=ro&immutable=1`. Zero `prepare()` com verbos de mutação; superfície só `GET /api/v1/*`. Lint custom + teste de grep (SC-003) garantem ausência de `INSERT/UPDATE/DELETE/CREATE/DROP`. State.json e `--reindex` fora do código. |
| **II. Degradar, Nunca Quebrar** | PASS | Camada `db/open.ts` captura ausência/corrupção e retorna handle degradado; toda rota responde `200` com `meta.degraded=true`+`meta.reason`. `PRAGMA quick_check` na saúde. FE: 4 estados por tela (loading/empty/error/degraded). Nunca `5xx` por condição de dado. |
| **III. Honestidade de Métrica** | PASS | Custo = `tool_calls` rotulado "proxy: tool calls"; zero `$`/`USD`/`token` em DTO ou UI. Métricas mapeiam 1:1 a colunas v2 reais; derivadas (clarify-resolution) rotuladas `meta.approximate=true`. |
| **IV. Não Reimplementar o que Tem Dono** | PASS | Mix de modelos → **Opção A** (card "indisponível nesta fonte"); árvore de decisões → delega à skill `decision-tree`; reindex → não existe no painel. Decisão registrada em `research.md` (D3). |
| **V. Conteúdo de Agente é UNTRUSTED** | PASS | Campos textuais servidos como string crua (sem render server-side); FE renderiza via `textContent`/JSX text node (nunca `dangerouslySetInnerHTML`). FTS5 com escaping de 2 camadas (tokenização aspas + binding `?`). |
| **VI. Snapshot que Muda** | PASS | `meta.freshness = { mtime, max_ingested_at }` em todo envelope; conexão reaberta/`statvfs` por requisição (sem long-lived assumindo imutabilidade); `ETag` derivado de `mtime`+`max(ingested_at)` → `If-None-Match`/`304`. |

> **Resultado do GATE: PASS** em todos os 6 princípios MUST. Nenhuma violação;
> `Complexity Tracking` permanece vazio (sem exceções a justificar).

## Project Structure

### Documentação (feature)

```
docs/specs/cstk-panel/
├── spec.md              # (existente)
├── plan.md              # este arquivo
├── research.md          # Phase 0 — D2/D3/D5 + driver + FTS5 + cache
├── data-model.md        # Phase 1 — 10 entidades + mapper layer DB→DTO
├── quickstart.md        # Phase 1 — cenários (inclui Roundtrip E2E real)
└── contracts/
    ├── envelope.md       # envelope padrão + headers + degradação + 304
    ├── api-read.md       # 29 endpoints GET /api/v1/* (params, shape data)
    └── search-fts.md     # contrato da busca FTS5 (escaping 2 camadas)
```

### Código-fonte (a criar — projeto-alvo hoje só tem `.claude/` + `docs/`)

```
cstk-panel/                       # raiz = /Users/jot/Projects/_lab/Jot/misc/cstk-panel
├── package.json                  # workspaces npm (raiz do monorepo)
├── tsconfig.base.json
├── packages/
│   └── shared-types/             # DTOs + envelope compartilhados BE↔FE
│       ├── package.json
│       └── src/
│           ├── envelope.ts        # ApiEnvelope<T>, Meta, Freshness
│           ├── entities.ts        # ExecutionDTO, WaveDTO, DecisionDTO, ...
│           └── index.ts
├── apps/
│   ├── server/                   # back-end Node/TS read-only
│   │   ├── package.json
│   │   ├── src/
│   │   │   ├── index.ts           # bootstrap Fastify + bind localhost
│   │   │   ├── config.ts          # resolução de path do DB (canonicalizado)
│   │   │   ├── db/
│   │   │   │   ├── open.ts        # abre RO imutável + quick_check + degradação
│   │   │   │   ├── freshness.ts   # mtime + max(ingested_at) + ETag
│   │   │   │   └── queries/       # SQL read-only por entidade (prepared)
│   │   │   ├── mappers/           # DB-row (snake_case) → DTO (camelCase)
│   │   │   │   ├── execution.ts   # lint_ok int→bool, etc.
│   │   │   │   └── ...
│   │   │   ├── routes/            # 1 arquivo por grupo de endpoints
│   │   │   │   ├── health.ts
│   │   │   │   ├── overview.ts
│   │   │   │   ├── projects.ts
│   │   │   │   ├── features.ts
│   │   │   │   ├── executions.ts
│   │   │   │   ├── alerts.ts
│   │   │   │   ├── metrics.ts
│   │   │   │   ├── tasks.ts
│   │   │   │   ├── events.ts
│   │   │   │   └── search.ts      # FTS5 escaping 2 camadas + rate-limit
│   │   │   ├── lib/
│   │   │   │   ├── envelope.ts    # wrap { data, meta }
│   │   │   │   ├── pagination.ts  # limit/offset validados (Zod)
│   │   │   │   └── fts.ts         # tokenização + quoting FTS5
│   │   │   └── plugins/           # cors localhost, headers nosniff, ratelimit
│   │   └── test/                  # Vitest (integração com DB real RO)
│   └── web/                      # front-end SPA React 19 + Vite
│       ├── package.json
│       ├── vite.config.ts
│       ├── index.html
│       └── src/
│           ├── main.tsx
│           ├── App.tsx            # shell: sidebar 232px + topbar + router
│           ├── styles/tokens.css  # design tokens (recriados de styles.css)
│           ├── lib/
│           │   ├── api.ts          # fetch tipado + If-None-Match/304
│           │   └── query.ts        # TanStack Query client
│           ├── components/         # KpiCard, StatusBadge, ScoreChip, ...
│           ├── states/             # Loading/Empty/Error/Degraded (4 estados)
│           └── screens/            # Overview, Projects, Features, Execution, ...
└── README.md
```

> **Padrão de estrutura**: monorepo npm workspaces (`packages/` + `apps/`).
> Justificativa: toolchain Node único permite `shared-types` consumido por BE e
> FE sem duplicar definições — alinhado à decisão D1 e à mitigação de drift de
> case (ver Convenções de Borda).

## Convenções de Borda

A feature atravessa três fronteiras: **SQLite (snake_case PT-BR)** → **backend
DTO (camelCase)** → **API JSON (camelCase)** → **frontend TS (camelCase)**.
Declaração explícita da fonte da verdade por convenção (mitiga o drift histórico
snake↔camel — dec-172/dec-173, 40 ondas de retrabalho):

| Camada | Case style | Validação | Fonte da verdade |
|--------|------------|-----------|------------------|
| Colunas SQLite (`knowledge.db`) | `snake_case` PT-BR (`execucao_id`, `tool_calls_total`, `motivo_termino`) | schema v2 **imutável** (não migramos — read-only) | `~/.claude/cstk/knowledge.db` (dono externo: `cstk recall`) |
| Linhas brutas no BE (`better-sqlite3` row) | `snake_case` (espelha colunas) | — (transiente, nunca cruza a borda HTTP) | `apps/server/src/db/queries/*` |
| Backend DTO (saída do mapper) | `camelCase` (`execucaoId`, `toolCallsTotal`, `motivoTermino`) | Zod schema em `shared-types` | `packages/shared-types/src/entities.ts` |
| API payload (response) | `camelCase` dentro de `{ data, meta }` | Zod no BE (saída) e no FE (parse) | `contracts/envelope.md` + `contracts/api-read.md` |
| Frontend DTO (TS) | `camelCase` | `import` direto de `shared-types` (sem redefinir) | `packages/shared-types` (re-export) |
| URL query/path params | `kebab-case`/`snake` conforme briefing §10 (`cost-over-time`, `event_type`, `execucao_id`) | router + Zod query schema | `contracts/api-read.md` |

**Fonte da verdade de dados**: a `knowledge.db` **read-only** é a única fonte
do painel. O `state.json` transacional é a fonte canônica do *dado*, mas está
**FORA do escopo** desta feature — o painel nunca o lê nem o toca (Princípio I/IV).

**Mapper layer (DB-row ↔ DTO)** — localização e responsável:
- Backend: `apps/server/src/mappers/*.ts`, um por entidade. Converte
  `snake_case` → `camelCase` **e normaliza tipos divergentes do schema**:
  - `tasks.lint_ok`: `INTEGER` (0/1) → `boolean`
  - `tasks.arquivos_tocados`: **`INTEGER` (contagem)** → `number` (NÃO é array;
    nomear o campo DTO `arquivosTocadosCount` para evitar a leitura errada do
    briefing §8, que sugeria string-array)
  - `decisions.score`: `INTEGER` 0–3 → `number` (0..3) tipado como union
  - `waves.etapas`: `TEXT` (string única de etapas) → `string` (NÃO array)
  - timestamps `TEXT` ISO-8601 → `string` (mantém ISO; FE formata)
  - colunas de proveniência (`source_ts`/`source_id`/`ingested_at`) **não** são
    expostas nos DTOs de domínio (uso interno: freshness/dedup), salvo
    `ingested_at` agregado em `meta.freshness`.
- ORM auto-mapping: **NÃO**. Mapeamento explícito por função pura (testável,
  auditável, sem mágica) — preferido a kysely/drizzle para manter a superfície
  read-only trivialmente auditável (Princípio I).

**Validação Zod**:
- Borda de entrada (request): query/path params validados no BE com Zod
  (`limit`/`offset` numéricos com teto, `period ∈ {24h,7d,30d,all}`, `score ∈
  0..3`, `q` string com tamanho máximo).
- Borda de saída (response): DTOs definidos em `shared-types` com schema Zod;
  o FE faz `safeParse` da resposta (defesa em profundidade contra drift).
- Schema compartilhado: SIM — `packages/shared-types/` é importado por ambos os
  lados; nenhuma definição duplicada.

## Complexity Tracking

*Vazio — Constitution Check PASS sem exceções. Nenhuma violação de MUST a
justificar.*

## Phase 0 — Research

Resolvido em [`research.md`](./research.md). Decisões fechadas: D2
(empacotamento), D3 (mix de modelos), D5 (granularidade de séries), driver
SQLite, escaping FTS5 de 2 camadas, estratégia de cache `ETag`/304. **0 NEEDS
CLARIFICATION restantes.**

## Phase 1 — Design

- Modelo de dados + mapper layer: [`data-model.md`](./data-model.md)
- Contratos de API: [`contracts/`](./contracts/)
- Cenários de teste (inclui Roundtrip E2E real): [`quickstart.md`](./quickstart.md)

## Re-check (pós-Phase 1)

Re-validação após o design: o design **não** introduziu camada de escrita,
serviço adicional, nem reimplementação de dono canônico. A escolha por mapper
explícito (vs ORM) **reforça** o Princípio I (auditabilidade da superfície
read-only). O pacote `shared-types` reduz complexidade de manutenção (evita
duplicação de DTOs) em vez de aumentá-la. **Constitution Check permanece PASS
nos 6 princípios.**

## Próximos Passos

1. `/checklist` — quality gate dos requisitos antes de decompor.
2. `/create-tasks` — decompor este plano em backlog executável.
3. `/analyze` — validar consistência spec ↔ plan ↔ tasks ↔ constitution.
