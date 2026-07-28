# Quickstart / Cenários de Teste: dashboard-refactor

**Feature**: `dashboard-refactor` | **Date**: 2026-07-28 | **Phase**: 1
**Spec**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md)

---

## Ambiente de verificação

**Verificação de UI é no dev server local, NUNCA no `:8080`.**

```bash
cd /Users/jot/Projects/_lab/Jot/misc/cstk-panel
npm run dev
```

Sobe dois processos via `concurrently`:

| Processo | Comando | Endereço |
|----------|---------|----------|
| server | `tsx watch src/index.ts` | `http://127.0.0.1:3001` (host fixo, `config.ts:152-153`) |
| web | `vite` | `http://localhost:5173` (default do Vite 5) |

O front usa `BASE_URL = '/api/v1'` (`apps/web/src/lib/api.ts`) e depende do
proxy do Vite. Rotas do SPA usam **HashRouter**.

> ⚠️ **O `:8080` é o `cstk serve` global** — bundle próprio, publicado por
> release. Ele **não reflete o código local** e verificar mudanças ali produz
> falso-negativo ("mudei e não apareceu") ou falso-positivo (vendo a versão
> antiga funcionando). Sempre `npm run dev`.

**Gates antes de qualquer commit**:

```bash
npm run typecheck && npm run lint && npm run lint:readonly-check && npm test
```

---

## Cenário 0 — Roundtrip End-to-End contra payload REAL *(OBRIGATÓRIO)*

> **Por que este cenário é obrigatório e por que ele vem primeiro.**
> Nesta feature, `tsc` e `vitest` **mentem**. Três mecanismos, todos presentes
> neste repositório, produzem falso-verde em adição/renomeação de schema:
>
> 1. O cliente **não valida** `/overview` nem `/metrics/*` com Zod —
>    `OverviewDataSchema = z.object({}).passthrough()` e
>    `MetricDataSchema = z.unknown()` (`apps/web/src/lib/hooks.ts`). Um campo
>    com nome errado passa sem ruído.
> 2. As telas leem o payload via casts `as Record<string, unknown>` — o
>    compilador não tem o que checar.
> 3. Fixtures desatualizadas continuam passando: o teste valida o mock, não o
>    servidor.
>
> É exatamente esse o mecanismo do defeito já existente em
> `Metrics.tsx:726` (lê `r.etapa`, servidor manda `stage`), que atravessou o
> projeto sem quebrar nenhum teste. **Só o roundtrip empírico
> servidor-real-contra-banco-real expõe o drift.**

**Passos**:

1. Subir o servidor apontado para um banco **real** v12:
   `CSTK_KNOWLEDGE_DB=~/.claude/cstk/knowledge.db npm run dev -w @cstk-panel/server`
2. Chamar o endpoint novo de fato (sem mock, sem fixture):
   `curl -s 'http://127.0.0.1:3001/api/v1/metrics/model-usage?period=all' | jq .`
3. Capturar o payload retornado.
4. Comparar o shape campo a campo com
   [`contracts/model-usage-endpoint.md`](./contracts/model-usage-endpoint.md).
5. Fazer o mesmo com o payload consumido pela tela: abrir `http://localhost:5173`
   e conferir no DevTools que **os nomes de campo lidos pelo componente são os
   mesmos que o servidor enviou** (a armadilha `etapa` vs `stage`).

**Expected**:
- `data.byModel[]` presente, com as chaves `model`, `costUsd`, `totalTokens`, `waves`.
- Todas as chaves em **camelCase** — nenhuma `snake_case` vazando do row SQL.
- `data.coverage` com os três denominadores.
- `meta.schemaVersion === "12"`.
- Nenhum campo do contrato ausente; nenhum campo extra não documentado.
- O componente da tela lê exatamente essas chaves (zero `?? r.<nome_legado>`).

**Automação**: estender `apps/server/test/lib/roundtrip.test.ts` (Fastify real
sobre `apps/server/test/knowledge-fixture.db`, validando `RawApiEnvelopeSchema`
e checando camelCase) para incluir a rota nova. Reforçar a paridade DTO em
`packages/shared-types/src/__tests__/parity-real.test.ts`.

---

## Cenário 1 — Custo por modelo visível nas duas telas (US1, FR-003/004/005, SC-005)

1. Com o banco real v12, abrir `http://localhost:5173` (dashboard principal).
2. Localizar o indicador compacto de uso/custo por modelo na KPI row.
3. Navegar até a página de Métricas.
4. Comparar os valores para o **mesmo período/projeto**.

**Expected**:
- Dashboard mostra o **modelo de maior custo** identificável em < 10 s (SC-001).
  Com o banco real e `period=all`, esse modelo é `claude-sonnet-5`.
- O rótulo do modelo é a **string bruta** (`claude-sonnet-5`), não uma tradução
  para `sonnet`.
- Todo valor traz rótulo explícito de natureza — **medido** (SC-004), visualmente
  distinto do card `tool_calls` marcado **proxy** e do mix marcado **derivado**.
- Página de Métricas mostra os mesmos números, sem divergência (SC-005), com o
  detalhe completo por modelo.
- Nenhum indicador **soma** `costUsd` com `tool_calls` ou com `agent_*`.

---

## Cenário 2 — Cobertura da amostra é exibida e é honesta (FR-005, Princípio III)

1. Na página de Métricas, observar o rótulo de cobertura do card por modelo.
2. Comparar com o rótulo de cobertura do card de custo por onda (`otel-usage`).

**Expected**:
- Aparece um denominador no formato "N de M ondas medidas"
  (padrão `otelCoverageLabel()`, `apps/web/src/components/OtelUsage.tsx:47-48`).
- Os **dois cards podem mostrar denominadores diferentes** — e isso é correto.
  No banco real: 36 ondas com breakdown por modelo vs. 46 com custo por onda,
  sobre 920 ondas. Um único número global para os dois seria falso.
- Nenhum total agregado aparece sem denominador.

---

## Cenário 3 — Estado "sem dado" ≠ zero (US1 cenário 2, FR-010, Princípio II)

**3a — tabela ausente (banco v10/v11)**

1. Subir o servidor com `CSTK_KNOWLEDGE_DB=apps/server/test/knowledge-fixture-v10.db`.
2. `curl -s 'http://127.0.0.1:3001/api/v1/metrics/model-usage' | jq '.meta'`
3. Abrir as duas telas.

**Expected**: HTTP **200** (jamais `5xx`), `meta.degraded=true`,
`meta.reason="table-empty"`. As telas mostram "métrica não coletada nesta
fonte". **Nenhum `0` e nenhum `$0.00`** onde não há medição. As demais métricas
da tela continuam funcionando (degradação é localizada, não global).

**3b — tabela presente, período sem linhas**

1. Selecionar um período sem execuções com breakdown (ex.: `24h`).

**Expected**: `200` **não degradado**, `byModel: []`, e a UI diz "sem dado
para este período/projeto" — texto **diferente** do de 3a. Confundir os dois
estados é o defeito que `emptyFallback` (`Metrics.tsx:169-175`) existe para
evitar.

**3c — valor medido igual a zero**

**Expected**: `costUsd: 0` renderiza como `$0` (via `fmtUsd`, que usa 4 casas
abaixo de `$0.01` justamente para não confundir), enquanto `costUsd: null`
renderiza `—`. Os dois **nunca** colapsam no mesmo pixel.

---

## Cenário 4 — Cards obsoletos removidos (US2, FR-001/002, SC-003)

1. Abrir o dashboard principal.
2. Procurar por "Custo por feature · proxy" e por "Funil do pipeline".
3. Inspecionar o layout resultante.

**Expected**:
- Nenhum dos dois cards aparece (SC-003: 0 de 2 remanescentes).
- Layout recalculado sem buraco vazio nem card desproporcional (US2 cenário 3).
- `GET /api/v1/overview` **continua** retornando `funnel[]` e `leaderboard[]` —
  a remoção é de renderização, não de contrato (research.md, Decision 9).
- `FunnelChart` não tem mais consumidor e foi removido junto; `BarH` **continua
  existindo** (usado em `ExecutionDetail.tsx:853`); `SDD_STAGES` **continua
  existindo** (usado em `PipelineProgress.tsx`).
- `npm run typecheck` e `npm test` verdes — `overview-select.test.ts` ajustado
  para o VM sem `maxToolCalls`/`maxFunnel`.

---

## Cenário 5 — Truncamento top-10 + "Outros" (US3, FR-006/007/008, SC-002)

Testes de **função pura** (a regra não vive no `.tsx` — research.md, Decision 5):

| Entrada | Expected |
|---------|----------|
| 14 etapas distintas | 10 barras nomeadas (as de maior volume) + 1 barra `Outros`; `Outros` = soma das 4 restantes; total = 11 barras |
| exatamente 10 etapas | 10 barras nomeadas, **nenhuma** barra `Outros` |
| exatamente 11 etapas | 10 nomeadas + `Outros` representando a **única** etapa excedente |
| 0 etapas | `[]`, estado vazio da tela, sem erro |

**Expected adicional**:
- SC-002 como invariante: `bars.length <= 11` para **qualquer** entrada.
- A barra `Outros` permite identificar quais etapas foram agregadas
  (`othersMembers`) — US3 cenário 3.
- O subtítulo do card deixa de dizer "soma tool_calls" e passa a refletir o que
  a query faz (contagem de decisões) — ver `contracts/existing-endpoints.md`.

---

## Cenário 6 — Mix de modelos por etapa com contexto real (US4, FR-009)

1. Abrir a página de Métricas e localizar "Mix de modelos por etapa".
2. Comparar com o donut "Mix de modelos · total" ao lado.

**Expected**:
- As barras trazem **rótulo de etapa real** (`specify`, `clarify`, `plan`, …) —
  e **não** uma única barra `'?'`, que é o comportamento atual causado pela
  leitura de `r.etapa` num payload que traz `stage`.
- Etapas ordenadas pela ordem do pipeline (`SDD_STAGES`), não por volume.
- Etapas presentes no dado e ausentes de `SDD_STAGES` aparecem ao fim, com o
  rótulo real preservado (nunca descartadas).
- O card aporta informação que o donut não mostra (US4 cenário 1) — o donut
  agrega, este quebra por etapa.
- Ambos permanecem rotulados **derivado** (`meta.approximate=true`), distintos
  do card **medido** por modelo.

**Regressão**: adicionar teste para `model-mix-by-stage` — endpoint hoje sem
nenhuma cobertura, o que permitiu o defeito passar.

---

## Cenário 7 — Read-only preservado (FR-011, Princípio I)

1. `npm run lint:readonly-check`
2. Revisar a superfície de rotas adicionada.

**Expected**: gate verde (zero `INSERT|UPDATE|DELETE|CREATE|DROP|ALTER` em
`apps/server/src`); a rota nova é `GET`; nenhuma escrita em `state.json` nem
reindexação; conexão segue `mode=ro&immutable=1`.
