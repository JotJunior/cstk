# Implementation Plan: Reorganização do Dashboard Principal e Página de Métricas

**Feature**: `dashboard-refactor` | **Date**: 2026-07-28 | **Spec**: [spec.md](./spec.md)
**Phase 0**: [research.md](./research.md) | **Phase 1**: [data-model.md](./data-model.md) · [quickstart.md](./quickstart.md) · [contracts/](./contracts/)

---

## Summary

Expor na UI o custo e o uso **medidos por modelo** — dado que já existe na
`knowledge.db` (tabela `wave_model_usage`, schema v12) e que **nenhuma rota do
painel lê hoje** — além de limpar dois cards obsoletos do dashboard e corrigir
dois gráficos ilegíveis da página de Métricas.

Abordagem técnica, derivada da pesquisa (Phase 0):

1. **Uma rota nova**, `GET /api/v1/metrics/model-usage` **[PROPOSTA]**, sobre
   `wave_model_usage`, com sonda `hasTable()` e degradação `table-empty`. É a
   única fonte com grão onda×modelo: `otel_cost_usd` (v11) é grão onda e
   `decisions.choice` é intenção derivada, sem custo.
2. **Rótulo de modelo permanece bruto** (`claude-sonnet-5`, `claude-fable-5`,
   `claude-opus-5[1m]` — valores reais no banco), sem tradução para as chaves
   curtas do `MODEL_COLOR` legado, que pertencem a outro domínio.
3. **Duas coberturas de amostra distintas**, porque no banco real elas divergem
   (36 ondas com breakdown por modelo vs. 46 com custo por onda, sobre 920).
4. **Remoção de renderização, não de contrato**: os cards saem do `Overview.tsx`;
   `funnel[]` e `leaderboard[]` continuam no payload de `/overview`.
5. **Correção de um defeito real**: o card "Mix de modelos por etapa" lê
   `r.etapa` num payload que traz `stage` — todas as etapas colapsam em `'?'`.
   Essa é a causa raiz do sintoma que originou a User Story 4.
6. **Toda regra nova em função pura** sob `apps/web/src/lib/`, porque `apps/web`
   não tem runner de componente — regra dentro de JSX seria regra não-testável.

---

## Technical Context

**Language/Version**: TypeScript 5.x, Node.js v22.17.0 (verificado: `node -v`)
**Primary Dependencies**: Fastify + `better-sqlite3` (server); React 18 + Vite 5 + HashRouter (web); Zod (schemas compartilhados); `mermaid` (apenas doc-viewer). **Sem lib de gráfico** — todos os charts são SVG inline (`apps/web/src/components/charts.tsx`: *"Sem dependencia de libs de grafico"*)
**Storage**: SQLite `knowledge.db` aberta **read-only** (`mode=ro&immutable=1`), schema v2–v12 (`DEFAULT_SCHEMA_VERSIONS`, `apps/server/src/config.ts:38`). Banco de referência: schema `12`
**Testing**: Vitest (`npm test` → `vitest run`), 3 configs (raiz, `apps/server`, `packages/shared-types`). Fixtures SQLite **reais** versionadas: `apps/server/test/knowledge-fixture.db` e `knowledge-fixture-v10.db`
**Target Platform**: localhost — server bind fixo `127.0.0.1:3001` (`config.ts:152-153`), web Vite `5173`. Em produção `npm start` serve o SPA de `apps/web/dist` na mesma porta
**Project Type**: web (monorepo npm workspaces: server + web + shared-types)
**Performance Goals**: SC-001 — modelo de maior custo identificável em < 10 s na tela. Sem meta de throughput (uso local, single-user)
**Constraints**: read-only absoluto; nenhum `5xx` por condição de dado; nenhum valor monetário estimado/derivado; `NULL` nunca vira `0`; versão de projeto `0.20.0`
**Scale/Scope**: banco real de referência com 920 ondas, 44 linhas em `wave_model_usage`, 3 modelos distintos. 2 telas alteradas (`Overview.tsx`, `Metrics.tsx`), 1 rota nova, 4 DTOs novos (× 2 declarações cada)

**NEEDS CLARIFICATION**: nenhum. Os 3 pontos abertos foram resolvidos na fase
`clarify` (spec §Clarifications) e os técnicos por sondagem empírica
(research.md §Sondagens, S1–S8).

---

## Constitution Check

*GATE: passou antes do Phase 0; re-checado após o Phase 1 (§Re-check).*

Constitution: `docs/constitution.md` **v1.2.0** (emendada 2026-07-28 nesta
mesma execução, via bloqueio `block-001`/`dec-009`).

| Princípio | Status | Notas |
|-----------|--------|-------|
| **I. Read-Only Absoluto** (NON-NEGOTIABLE) | **PASS** | A rota nova é `GET` e emite apenas `SELECT`. FR-011 é explícito. Gate `npm run lint:readonly-check` permanece no fluxo (Cenário 7 do quickstart). Nenhum acesso a `state.json`, nenhuma reindexação |
| **II. Degradar, Nunca Quebrar** | **PASS** | Sonda `hasTable()` antes da query; tabela ausente → `200` + `meta.degraded=true`, `reason='table-empty'`. Três estados distintos especificados (não coletado / sem dado no período / medido). FR-010 alinhado. Quatro estados de tela reusam `apps/web/src/states/` |
| **III. Honestidade de Métrica** | **PASS** *(sob a emenda 1.2.0)* | `otel_cost_usd`/`cost_usd` são **medidos** na fonte — a exceção aberta pela emenda cobre exatamente isso. As três regras inegociáveis são atendidas: cobertura de amostra exibida (FR-005, com **dois** denominadores por serem divergentes no dado real), `NULL` nunca coalescido para `0`, e proibição de somar custo medido com `tool_calls`/`agent_*` (FR-004). Nenhum valor monetário é estimado ou convertido pelo painel. Correção adicional: o subtítulo "soma tool_calls" do throughput é factualmente falso e será corrigido |
| **IV. Não Reimplementar o que Tem Dono** | **PASS** *(com nota)* | Distinção material: o **mix de modelos** (intenção do roteador, derivada de `decisions.choice`) tem dono canônico externo — `model-routing-report.sh` — e esta feature **não** estende nem duplica essa heurística; os cards `model-mix`/`model-mix-by-stage` seguem rotulados `approximate` e apenas têm seu **consumo** corrigido (bug de nome de campo) e sua apresentação ordenada. Já `wave_model_usage` é **coluna medida do schema**, não heurística — lê-la é território do Princípio III, não do IV. Reuso em vez de duplicação também na ordenação (`SDD_STAGES` existente) e nos rótulos de cobertura (`otelCoverageLabel`) |
| **V. Conteúdo de Agente é UNTRUSTED** | **PASS** | Nenhum campo novo vem de saída de LLM. `wave_model_usage.model` vem de telemetria OTel e, **por desenho da fonte, não alimenta a FTS** (`config.ts:33-35`) — o plano não o reintroduz na busca. Renderização segue como texto puro |
| **VI. Snapshot que Muda** | **PASS** | A rota nova usa o mesmo `wrap()`/`meta.freshness` e a mesma política de ETag das demais; nenhuma conexão de longa duração nova |
| **Padrões de Segurança e Qualidade** | **PASS** | Sem auth nova; sem path vindo do cliente; envelope padrão; `nosniff` herdado. Paginação: não se aplica (agregado por modelo — 3 linhas no banco real, limitado pela cardinalidade de modelos, não por volume de tabela) |
| **Fidelidade de Design / 4 estados** | **PASS** | Reusa `KpiCard`, `MetricCard`, `Donut`/`StackedBars`, `LoadingState`/`EmptyState`/`ErrorState`/`DegradedBanner`. Sem componente visual fora do padrão |
| **Governance — Constitution Check como gate** | **PASS** | Este documento referencia e respeita I–VI, como exigido |

**Violações de MUST: nenhuma.** Nada a registrar em Complexity Tracking.

> Nota de rastreabilidade: a exibição de USD só é lícita porque a constitution
> foi **formalmente emendada** (1.1.0 → 1.2.0) antes deste plano, com
> autorização humana registrada. Sem essa emenda, FR-003 seria violação de MUST
> e este gate teria falhado.

---

## Project Structure

### Documentation (this feature)

```
docs/specs/dashboard-refactor/
├── spec.md
├── plan.md                          # This file
├── research.md                      # Phase 0
├── data-model.md                    # Phase 1
├── quickstart.md                    # Phase 1
└── contracts/                       # Phase 1
    ├── existing-endpoints.md        # REAL — extraído do código
    └── model-usage-endpoint.md      # [PROPOSTA]
```

### Source Code (repository root)

Árvore real verificada (`ls`), com marcação do que a feature toca:

```
apps/
├── server/
│   ├── src/
│   │   ├── config.ts                     # DEFAULT_SCHEMA_VERSIONS (v2..v12)
│   │   ├── index.ts                      # registro de plugins sob /api/v1
│   │   ├── db/
│   │   │   ├── open.ts                   # validação de schema_version
│   │   │   ├── columns.ts                # hasColumn / hasTable      [USA]
│   │   │   └── queries/
│   │   │       ├── metrics.ts            # queries de métrica        [ALTERA]
│   │   │       ├── waves.ts              # AGENT_/OTEL_USAGE_COLUMNS
│   │   │       └── overview.ts
│   │   ├── lib/envelope.ts               # wrap / wrapDegraded
│   │   ├── mappers/                      # Row snake_case -> DTO camelCase
│   │   ├── routes/
│   │   │   ├── metrics.ts                # + rota model-usage        [ALTERA]
│   │   │   └── overview.ts               # payload INALTERADO
│   │   ├── docs/  watchers/
│   └── test/
│       ├── knowledge-fixture.db          # DB real v12               [USA]
│       ├── knowledge-fixture-v10.db      # DB real v10 (degradação)  [USA]
│       ├── lib/roundtrip.test.ts         # roundtrip real            [ALTERA]
│       └── lib/  mappers/  watchers/  docs/  integration/
└── web/
    └── src/
        ├── screens/
        │   ├── Overview.tsx              # remove 2 cards + KPI novo [ALTERA]
        │   └── Metrics.tsx               # throughput, mix, card novo[ALTERA]
        ├── components/
        │   ├── charts.tsx                # remove FunnelChart        [ALTERA]
        │   ├── index.ts                  # remove export órfão       [ALTERA]
        │   ├── KpiCard.tsx  AgentUsage.tsx  OtelUsage.tsx            [USA]
        ├── lib/
        │   ├── constants.ts              # SDD_STAGES                [USA]
        │   ├── overview-select.ts        # remove maxToolCalls/maxFunnel [ALTERA]
        │   ├── hooks.ts                  # useMetric
        │   └── (novos módulos puros)     #                          [CRIA]
        ├── states/  hooks/  styles/
packages/
└── shared-types/src/
    ├── entities.ts                       # interfaces manuais        [ALTERA]
    ├── schemas/entities.ts               # Zod espelhado             [ALTERA]
    ├── envelope.ts  index.ts
    └── __tests__/parity-real.test.ts     # paridade DTO              [ALTERA]
docs/  scripts/  tmp/
```

**Structure Decision**: nenhuma estrutura nova. A feature se encaixa nas
camadas existentes do monorepo (query → mapper → DTO dual-def → hook → tela).
O único acréscimo é um ou mais módulos puros em `apps/web/src/lib/`, seguindo o
precedente de `overview-select.ts` e `token-source.ts` — escolha ditada pela
ausência de runner de componente em `apps/web` (research.md, Decision 5).

---

## Convenções de Borda

> Obrigatório: esta feature atravessa DB → backend → API → frontend.

| Camada | Case style | Validação | Fonte da verdade |
|--------|------------|-----------|------------------|
| Colunas SQLite (`knowledge.db`) | `snake_case` | nenhuma (read-only; fonte tem dono externo — `cstk recall`) | o próprio arquivo; sondagem via `PRAGMA table_info` |
| Row types no servidor | `snake_case` | tipo TS manual | `apps/server/src/db/queries/*.ts` (ex.: `WaveRow`, `waves.ts:90`) |
| Mapper (Row → DTO) | conversão explícita | — | `apps/server/src/mappers/*.ts` (`wave.ts`, `execution.ts`, `agent-usage.ts`, `otel-usage.ts`) |
| DTO compartilhado | `camelCase` | **dual-def obrigatória** | `packages/shared-types/src/entities.ts` **+** `packages/shared-types/src/schemas/entities.ts` |
| Payload de API (response) | `camelCase` **com exceção legada** (ver abaixo) | Zod no **servidor**; **não** no cliente | `docs/specs/dashboard-refactor/contracts/*.md` |
| Query params de URL | `camelCase` simples (`project`, `feature`, `period`) | Zod (`parseUsageQuery`, `routes/metrics.ts:209`) | `apps/server/src/routes/metrics.ts` |
| View model do front | `camelCase` | nenhuma (tipo TS) | `apps/web/src/lib/overview-select.ts` e módulos puros novos |

**Exceção legada pt-BR no payload (NÃO uniformizar nesta feature)**: a migração
pt-BR→EN do schema v7 não alcançou todos os aliases de projeção. Convivem hoje:

| Rota | Campo pt-BR vivo | Campo en no mesmo objeto |
|------|------------------|--------------------------|
| `GET /metrics/model-mix` | `modelo` | — |
| `GET /metrics/model-mix-by-stage` | `modelo` | `stage` |
| `GET /overview` (`modelMix[]`) | — | `model` |

Ou seja, **`modelo` e `model` coexistem em rotas diferentes para o mesmo
conceito**, e `model-mix-by-stage` mistura os dois idiomas no mesmo objeto.
O FR-009 consome exatamente esse payload: ler `model` ali quebraria o card.
Renomear é mudança incompatível de contrato, fora do escopo (research.md,
Decision 6). Os DTOs **novos** desta feature usam `model` (en), consistente com
a regra global de sintaxe em inglês.

**Mapper layer (DB ↔ DTO)**: `apps/server/src/mappers/`. **ORM auto-mapping: NÃO** —
`better-sqlite3` cru, mapeamento manual e explícito. Consequência: cada campo
novo exige edição manual em cada camada; nada é inferido.

**Validação Zod**:
- **Borda de resposta (servidor)**: sim.
- **Borda de consumo (cliente)**: **NÃO** — `OverviewDataSchema = z.object({}).passthrough()`
  e `MetricDataSchema = z.unknown()` (`apps/web/src/lib/hooks.ts`). **Este é o
  ponto cego declarado desta arquitetura**: drift de nome de campo entre
  servidor e tela falha **em silêncio**, sem erro de tipo nem de runtime.
- Schema compartilhado: sim, `packages/shared-types/`.

> ⚠️ **Risco de borda nº 1, com precedente concreto neste repositório.** O ponto
> cego acima já produziu um defeito vivo: `Metrics.tsx:726` lê `r.etapa`
> enquanto o servidor projeta `stage` (`db/queries/metrics.ts:374`), colapsando
> todas as etapas numa barra `'?'` — e nenhum teste pegou, porque
> `throughput-by-stage` e `model-mix` **não têm cobertura alguma**. Mitigação
> obrigatória: o **Cenário 0 (Roundtrip End-to-End)** do quickstart, que compara
> o payload real do servidor com o contrato e com o que a tela de fato lê.

**Repetição de shape em até 5 camadas** (Row → mapper → DTO dual-def → tipo Raw
do front → fixture de teste): custo estrutural aceito, herdado do projeto. Para
cada DTO novo desta feature, as 5 devem ser percorridas conscientemente — em
especial os *result types* do servidor (`AgentUsageResult`, `OtelUsageResult`,
`metrics.ts:410,508`), que **não importam** de `shared-types` e duplicam o shape
campo a campo.

---

## Ordem de implementação sugerida

Deriva das prioridades da spec (P1 → P3) e da independência declarada em cada
User Story. Detalhamento fino é responsabilidade de `/create-tasks`.

| Ordem | Bloco | Stories / FRs | Por quê nesta posição |
|-------|-------|---------------|------------------------|
| 1 | Backend do custo por modelo: query + rota + DTOs dual-def + roundtrip | US1 / FR-003, 004, 005, 010, 011 | É o P1 e a razão de ser da feature; entrega valor sozinho e estabelece o contrato que as duas telas consomem |
| 2 | Consumo nas duas telas (KPI compacto + detalhe) | US1 / FR-003, 004, 005; SC-001, 004, 005 | Depende de 1; SC-005 exige agregador puro **compartilhado**, não cálculo por tela |
| 3 | Remoção dos dois cards + limpeza de órfãos | US2 / FR-001, 002; SC-003 | Independente e de baixo risco; feito após 2 para o layout ser recalculado já com o KPI novo no lugar |
| 4 | Truncamento top-10 + "Outros" (função pura) + correção do subtítulo † | US3 / FR-006, 007, 008; SC-002 | Independente das demais; puro, testável isoladamente |
| 5 | Correção `stage` + ordenação por pipeline no mix por etapa | US4 / FR-009 | P3; é correção de defeito, e o teste de regressão fecha a lacuna de cobertura |

† **Correção incidental, sem FR próprio.** O subtítulo do card de throughput
diz *"soma tool_calls por etapa SDD"* (`apps/web/src/screens/Metrics.tsx:487`)
enquanto a query faz `count(*)` sobre `decisions`. **Nenhum FR da spec cobre
esse rótulo** — é rastreado aqui como correção incidental, justificada
diretamente pelo Princípio III (natureza do número explícita), não por
requisito. Se o operador preferir escopo estrito, é o item removível sem
impacto em nenhum FR ou SC.

---

## Re-check de Constitution (pós-Phase 1)

Revalidação após o design, conforme exigido:

- **Complexidade introduzida?** Uma rota, quatro DTOs e módulos puros — nenhum
  serviço, camada, dependência ou runner novo. `package.json` não muda.
- **Princípio III continua respeitado após o design?** Sim, e o design o
  **reforça**: a decisão de manter dois denominadores de cobertura (em vez de
  um agregado mais simples) existe justamente porque o dado real os mostra
  divergentes — simplificar ali seria apresentar parcial como completo.
- **Princípio IV continua respeitado?** Sim. O design isola explicitamente o
  ramo **medido** (`wave_model_usage`) do ramo **derivado com dono externo**
  (`decisions.choice`), e proíbe somá-los ou apresentá-los como equivalentes.
- **Princípio II continua respeitado?** Sim, e o design trata "sem dado" como
  caso **comum**, não excepcional — a cobertura real é de 36 ondas em 920.
- **Algum MUST passou a ser violado pelo design?** Não.

**Resultado do re-check: PASS.** Complexity Tracking permanece vazio.

---

## Complexity Tracking

> Preencher apenas se o Constitution Check tiver violações que precisem de justificativa.

**N/A — nenhuma violação de princípio.** Nenhuma exceção a registrar.

---

## Riscos conhecidos

| # | Risco | Mitigação |
|---|-------|-----------|
| R1 | O contrato do endpoint é **[PROPOSTA]**; nomes de campo podem mudar na implementação | Cenário 0 (Roundtrip) valida contra o payload real antes de fechar |
| R2 | `byStage` do endpoint novo depende de uma junção `wave_model_usage`×`waves` **não verificada empiricamente** | Regra dura já especificada: se não render dado confiável, retorna `[]` ("sem dado"), nunca valor suposto. FR-009 não depende disso |
| R3 | Cobertura real baixíssima (36/920 ondas) pode fazer a feature "parecer quebrada" em uso normal | Estados de "sem dado" e rótulos de cobertura são requisito de primeira classe (FR-005/FR-010), não afterthought |
| R4 | Rótulos brutos de modelo (`claude-opus-5[1m]`) podem crescer/variar sem aviso da fonte | Não há dicionário de tradução mantido pelo painel; rótulo é passado adiante como veio, cor por match com fallback neutro |
| R5 | Remoção de órfãos pode quebrar telas fora do escopo | Levantamento de referências já feito (research.md, Decision 8): `BarH` e `SDD_STAGES` **permanecem**; só `FunnelChart` e `maxToolCalls`/`maxFunnel` saem |
| R6 | **Exceção em query-time vira `500` cru** — rotas de métrica usam `try/finally` sem `catch` e não há `setErrorHandler` (verificado por grep); o contrato só previa degradação no *open*. Violaria o Princípio II | Invariante 7 do contrato do endpoint: `catch` → `wrapDegraded('db-corrupt', …)`. Gate de segurança classificou como MEDIUM (A10) |
| R7 | Payload de `model-mix-by-stage` mistura `stage` (en) e `modelo` (pt); consumir `model` por analogia quebraria o card | Exceção legada documentada em §Convenções de Borda e em `contracts/existing-endpoints.md`; Cenário 0 do quickstart compara os nomes reais |

---

## Artefatos

| Arquivo | Status |
|---------|--------|
| `docs/specs/dashboard-refactor/plan.md` | Criado |
| `docs/specs/dashboard-refactor/research.md` | Criado |
| `docs/specs/dashboard-refactor/data-model.md` | Criado |
| `docs/specs/dashboard-refactor/quickstart.md` | Criado |
| `docs/specs/dashboard-refactor/contracts/existing-endpoints.md` | Criado |
| `docs/specs/dashboard-refactor/contracts/model-usage-endpoint.md` | Criado |

**Constitution**: PASS (v1.2.0) · **NEEDS CLARIFICATION restantes**: 0

### Próximos passos

1. `/checklist` — quality gate dos requisitos antes de implementar
2. `/create-tasks` — decompor este plano em backlog executável
3. `/analyze` — validar consistência spec ↔ plan ↔ tasks
