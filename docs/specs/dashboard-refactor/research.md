# Research: dashboard-refactor

**Feature**: `dashboard-refactor` | **Date**: 2026-07-28 | **Phase**: 0
**Spec**: [spec.md](./spec.md)

> Todas as afirmações factuais deste documento foram extraídas do código-fonte
> ou de sondagem direta da `knowledge.db` real, com o comando/arquivo citado.
> Nada aqui é suposto.
>
> Base normativa: **Princípio III — Honestidade de Métrica** da
> `docs/constitution.md` deste projeto ("metrica inventada e pior que metrica
> ausente"), reforçado pela regra global de engenharia *"jamais inventar
> dados"*. (Não confundir com o Princípio VI do projeto, que é **"Snapshot que
> Muda"** — frescor do índice.)

---

## Sondagens executadas (evidência de base)

| # | Comando / arquivo | Resultado observado |
|---|-------------------|---------------------|
| S1 | `sqlite3 'file:~/.claude/cstk/knowledge.db?mode=ro' "SELECT value FROM schema_meta WHERE key='schema_version'"` | `12` |
| S2 | `SELECT sql FROM sqlite_master WHERE name='wave_model_usage'` | DDL completo (ver Decision 1) |
| S3 | `SELECT model, count(*), round(sum(cost_usd),4), sum(total_tokens) FROM wave_model_usage GROUP BY model` | `claude-sonnet-5` (36 linhas, 465.3943 USD, 1.127.119.533 tok); `claude-fable-5` (7, 23.5946 USD, 13.884.110 tok); `claude-opus-5[1m]` (1, 6.1439 USD, 6.864.604 tok) |
| S4 | `SELECT count(*) FROM wave_model_usage` | `44` |
| S5 | cobertura: `waves` total / com `otel_cost_usd` / com linha em `wave_model_usage` | `920` / `46` / `36` |
| S6 | `PRAGMA table_info(waves)` | 5 colunas `otel_*` (v11) + 9 `agent_*` (v10) + 8 `otel_{main,subagent}_*_tokens` (v12) |
| S7 | `apps/server/src/config.ts:38` | `DEFAULT_SCHEMA_VERSIONS = ['2'…'12']` |
| S8 | `grep -r wave_model_usage apps/server/src` | zero ocorrências em código de produção |

---

## Decision 1 — Fonte de dados do custo POR MODELO

**Decision**: usar a tabela `wave_model_usage` (schema v12) como única fonte do
custo e dos tokens por modelo. Ela é lida por um endpoint NOVO
(`GET /api/v1/metrics/model-usage`, ver `contracts/`), marcado
`[PROPOSTA — a validar na implementação]`.

DDL real (S2), reproduzido literalmente:

```sql
CREATE TABLE wave_model_usage (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  project TEXT NOT NULL,
  feature TEXT NOT NULL,
  wave TEXT NOT NULL,
  execution_id TEXT NOT NULL,
  source_ts TEXT NOT NULL,
  source_id TEXT NOT NULL,
  model TEXT,
  cost_usd REAL,
  total_tokens INTEGER,
  ingested_at TEXT NOT NULL,
  UNIQUE(project, feature, wave, source_id)
)
```

**Rationale**: FR-003 pede custo/uso **por modelo**. As colunas `otel_*` de
`waves` (v11) são de grão **onda**, não onda×modelo — `otel_cost_usd` sozinho
não responde "qual modelo custou mais". O grão onda×modelo só existe em
`wave_model_usage`. A tabela já é aceita na abertura do banco (S7) mas
nenhuma rota a lê (S8): é dado medido, presente na fonte e invisível na UI —
exatamente o problema que a User Story 1 descreve.

**Alternatives considered**:

- *Derivar de `decisions.choice LIKE 'model:%'`* (fonte dos endpoints
  `model-mix` e `model-mix-by-stage`): **rejeitado**. Isso é a *intenção* do
  roteador, não consumo medido; é rotulado `meta.approximate=true` e tem dono
  canônico fora do painel (`model-routing-report.sh`, Princípio IV). Não
  carrega custo nem tokens.
- *Estimar custo multiplicando tokens por tabela de preço*: **rejeitado, viola
  Princípio III** (valor monetário estimado/convertido pelo painel permanece
  proibido mesmo após a emenda 1.2.0).
- *Somar `otel_cost_usd` e ratear por modelo proporcionalmente aos tokens*:
  **rejeitado** — rateio é derivação inventada; produziria número que não
  existe em nenhuma coluna.

---

## Decision 2 — Rótulo de modelo: string BRUTA do OTel

**Decision**: exibir o rótulo de modelo **exatamente como vem** da coluna
`wave_model_usage.model`, sem normalizar para as chaves curtas da UI atual.
Cor por modelo resolvida por *match* de substring com fallback neutro.

**Rationale (achado empírico decisivo)**: os valores reais na coluna (S3) são
`claude-sonnet-5`, `claude-fable-5` e `claude-opus-5[1m]` — strings brutas do
OTel. O `apps/server/src/config.ts:29-35` documenta isso explicitamente
("`model` como string BRUTA do OTel"). Já a UI existente tem
`MODEL_ORDER = ['haiku','sonnet','opus','manter-atual']` e `MODEL_COLOR`
(`apps/web/src/screens/Metrics.tsx:24,29-34`; `Overview.tsx:49`) chaveados em
nomes curtos, que derivam de `decisions.choice` — **domínio diferente**.
Aplicar `MODEL_COLOR['claude-sonnet-5']` retorna `undefined`: as duas famílias
de rótulo não são intercambiáveis.

Normalizar `claude-sonnet-5 → sonnet` seria uma tradução inventada pelo painel
(e `claude-fable-5` não tem sequer equivalente em `MODEL_ORDER`, nem
`opus-5[1m]` mapeia sem descartar o sufixo `[1m]`, que é informação real de
janela de contexto). Manter o bruto preserva veracidade e evita colapsar dois
modelos distintos num mesmo rótulo.

**Alternatives considered**:

- *Normalizar via regex para haiku/sonnet/opus*: **rejeitado** — perde
  `fable`, perde `[1m]`, e cria um dicionário de tradução mantido pelo painel
  que dessincroniza a cada modelo novo.
- *Reaproveitar `MODEL_COLOR` diretamente*: **rejeitado** — chaves não casam
  (todas as barras/fatias sairiam com a mesma cor de fallback).

**Consequência de design**: a função de cor para esta feature é nova e vive
junto da lógica pura (Decision 5), separada de `MODEL_COLOR` legado. O card
existente de "Mix de modelos · total" (derivado de `decisions`) **não muda** e
continua usando `MODEL_COLOR` — são duas grandezas distintas exibidas lado a
lado, cada uma com seu rótulo de natureza (Princípio III).

---

## Decision 3 — Duas coberturas de amostra distintas, nunca uma só

**Decision**: FR-005 é satisfeito com **dois denominadores independentes**,
nunca fundidos:

- custo agregado por onda (`otel_cost_usd`): `ondas com custo medido / ondas do período`;
- custo por modelo (`wave_model_usage`): `ondas com breakdown por modelo / ondas do período`.

**Rationale**: a sondagem S5 mostra que os dois **divergem** no banco real —
`920` ondas no total, `46` com `otel_cost_usd`, mas apenas `36` ondas
distintas presentes em `wave_model_usage`. Ou seja, há 10 ondas com custo
total medido e sem breakdown por modelo. Usar "46" como denominador do card
por modelo apresentaria parcial como completo — o que o Princípio III proíbe
literalmente ("Total sem denominador apresenta parcial como completo").

Também expõe que a cobertura é baixa (~5% e ~3,9%): o estado "sem dado" **não
é** caminho de exceção nesta feature, é o caso comum. A UI precisa ser
projetada a partir dele, não com ele como afterthought.

**Alternatives considered**:

- *Um único `coverage` global*: **rejeitado**, mascara a divergência de 10 ondas.
- *Assumir que `otel_cost_usd IS NOT NULL` implica linhas em `wave_model_usage`*:
  **rejeitado** — refutado empiricamente por S5.

**Reuso**: o padrão de rótulo já existe e é reaproveitado, não reescrito —
`otelCoverageLabel()` (`apps/web/src/components/OtelUsage.tsx:47-48`, formato
"7 de 12 ondas medidas") e `CoverageBadge`
(`apps/web/src/components/AgentUsage.tsx:99-100`).

---

## Decision 4 — Degradação por ausência de tabela (não só de coluna)

**Decision**: o endpoint novo sonda `hasTable(db, 'wave_model_usage')` antes de
qualquer query e, na ausência, responde `200` com `data` vazio e
`meta.degraded=true`, `meta.reason='table-empty'`. Bancos v2–v11 (sem a tabela)
continuam funcionando sem erro.

**Rationale**: `apps/server/src/db/columns.ts` já expõe `hasTable(db, table)` e
`hasColumn(db, table, column)` com cache em `WeakMap` via `PRAGMA table_info` —
a primitiva existe e é o padrão da casa (`hasAgentUsage`/`hasOtelUsage` em
`apps/server/src/db/queries/waves.ts:45,60`). `DegradedReason` já inclui
`table-empty` (`packages/shared-types/src/envelope.ts`, mapeado em
`apps/web/src/states/DegradedBanner.tsx`). Princípio II exige `200` degradado,
nunca `5xx`, por condição de dado.

**Alternatives considered**:

- *`try/catch` em torno do `SELECT`*: **rejeitado** — trata condição esperada
  como exceção e não distingue "tabela ausente" de "erro real de I/O".
- *Elevar a versão mínima de schema para 12*: **rejeitado, quebraria bancos
  v10/v11 existentes* (e a fixture `knowledge-fixture-v10.db` do próprio
  repositório).

---

## Decision 5 — Toda lógica nova em função pura testável, fora do `.tsx`

**Decision**: truncamento top-10 + "Outros" (FR-006/007/008), ordenação por
etapa do pipeline (FR-009) e agregação por modelo ficam em módulos puros sob
`apps/web/src/lib/`, consumidos pelas telas. Nenhuma dessas regras vive dentro
de JSX.

**Rationale**: `apps/web` **não tem** script `test` no `package.json` nem
React Testing Library nas devDependencies — os testes de web existentes são de
funções puras em ambiente `node` (ex.: `apps/web/src/lib/overview-select.test.ts`,
`apps/web/src/lib/token-source.ts`). Regra que mora no `.tsx` é regra
não-testável neste projeto. SC-002 ("nunca mais de 11 barras") só é verificável
automaticamente se a regra for uma função.

**Alternatives considered**:

- *Truncar no servidor (SQL `LIMIT 10` + linha "Outros")*: **rejeitado**. O
  endpoint `throughput-by-stage` não aceita `period` nem `project` e é
  consumido só por este card; mas mover a regra para SQL tornaria o
  comportamento "Outros" invisível ao teste puro do front e acoplaria a regra
  de apresentação à camada de dados. Além disso o `LIMIT` no SQL descartaria o
  excedente em vez de somá-lo — teria que virar duas queries.
- *Adicionar React Testing Library*: **rejeitado nesta feature** — dependência
  nova e mudança de infraestrutura de teste fora do escopo da spec.

---

## Decision 6 — Bug real de campo em `model-mix-by-stage` (causa da User Story 4)

**Decision**: corrigir a leitura de campo como parte do FR-009, e cobrir com
teste (hoje inexistente).

**Rationale (evidência de código)**: o servidor devolve a coluna `stage`
(`apps/server/src/db/queries/metrics.ts:374`, `SELECT stage as stage, …`), mas
o consumidor lê `r.etapa`:

- `apps/web/src/screens/Metrics.tsx:726` — `const etapa = (r.etapa as string | null) ?? '?';`
  **sem** fallback para `r.stage`.

Consequência: toda linha cai em `'?'` e o `StackedBars` renderiza **uma única
barra sem contexto de etapa** — exatamente o sintoma que a User Story 4
descreve como "duplica visualmente o donut ao lado". O card de throughput, na
linha 491, tem o fallback (`r.etapa ?? r.stage`) e por isso não sofre do mesmo
problema.

`etapa` e `tool_calls` são nomes legados do schema pré-v7 (a migração
pt-BR→EN é o v7, documentada em `config.ts:21`) e **esses dois** não existem
no payload atual.

> ⚠️ **A migração pt→EN não foi total — não generalizar.** O campo `modelo`
> (pt) continua **vivo** no payload de `/metrics/model-mix` e
> `/metrics/model-mix-by-stage`: a projeção real é
> `SELECT ${stageCol} as stage, replace(${choiceCol}, 'model:', '') as modelo,
> count(*) as n` (`apps/server/src/db/queries/metrics.ts:374` — note que os
> nomes de coluna são **interpolados** por sonda `hasColumn`, não literais).
> Ou seja, o mesmo payload mistura `stage` (en) e `modelo` (pt). O consumidor
> MUST ler `stage` **e** `modelo` — trocar `modelo` por `model` quebraria o
> card. Assumir "tudo virou inglês no v7" é justamente o tipo de suposição que
> produziu o defeito acima.

Isso confirma que a User Story 4 é **um defeito**, não um problema de design —
e valida a clarificação (manter o card + dar contexto de etapa) como a
correção certa.

**Por que não foi pego antes**: o cliente não valida `/metrics/*` com Zod
(`MetricDataSchema = z.unknown()` em `apps/web/src/lib/hooks.ts`), então o
drift de nome de campo falha em silêncio, sem erro de tipo nem de runtime.
Reforça a exigência do cenário Roundtrip do quickstart.

**Alternatives considered**:

- *Renomear `modelo` → `model` no servidor para uniformizar*: **rejeitado
  nesta feature** — mudança incompatível de contrato, sem requisito que a
  peça, e ampliaria o blast radius para consumidores fora do painel.
- *Adicionar fallback `r.etapa ?? r.stage` (como no card de throughput)*:
  **rejeitado** — mascara o problema em vez de corrigi-lo e perpetua o nome
  legado. Ler o campo correto é a correção; o fallback é dívida.

---

## Decision 7 — Ordem do pipeline: reusar `SDD_STAGES`, não criar constante nova

**Decision**: importar `SDD_STAGES` de `apps/web/src/lib/constants.ts` para
ordenar as etapas (FR-009). Etapas presentes no dado e ausentes da constante
vão para o fim, em ordem de volume decrescente, preservando o rótulo real.

**Rationale**: a constante já existe com as 9 etapas
(`briefing, constitution, specify, clarify, plan, checklist, create-tasks,
execute-task, review-task`) e já é consumida por `PipelineProgress.tsx` e pelo
funil do `Overview.tsx`. `Metrics.tsx` hoje **não** a importa. Criar uma
segunda lista de ordenação produziria duas fontes de verdade divergentes. A
FR-009 cita 7 etapas (do `specify` ao `review-task`); a constante tem essas 7
mais `briefing` e `constitution` — superconjunto compatível, sem conflito.

Não descartar etapas fora da constante é exigência de veracidade: o dado real
pode conter etapas que a constante não prevê (ex.: `converge`), e omiti-las
esconderia volume medido.

**Alternatives considered**:

- *Criar uma constante de ordenação própria na página de Métricas*:
  **rejeitado** — duas fontes de verdade para a mesma ordem, que divergem no
  primeiro pipeline que mudar.
- *Filtrar o dado para apenas as etapas de `SDD_STAGES`*: **rejeitado** —
  esconderia volume real medido, o oposto do Princípio III.
- *Mover a constante para `shared-types` e ordenar no servidor*: **rejeitado
  nesta feature** — ordenação é decisão de apresentação; mover ampliaria o
  escopo sem ganho para os FRs em jogo.

---

## Decision 8 — Órfãos após a remoção dos dois cards (FR-001/FR-002)

**Decision**: remover junto o que fica sem consumidor; **não** remover o que
ainda tem consumidor. Levantamento verificado por busca de referências:

| Símbolo | Local | Após remoção | Ação |
|---------|-------|--------------|------|
| `FunnelChart`, `FunnelDatum` | `apps/web/src/components/charts.tsx:123`, exportados em `components/index.ts:25-26` | órfãos (único consumidor era `Overview.tsx`) | remover, junto do export |
| `maxToolCalls`, `maxFunnel` | `apps/web/src/lib/overview-select.ts` | sem consumidor | remover do VM + ajustar `overview-select.test.ts` |
| `BarH` | `charts.tsx:101` | **mantém consumidor**: `ExecutionDetail.tsx:853` | manter |
| `SDD_STAGES` | `lib/constants.ts` | **mantém consumidores**: `PipelineProgress.tsx` (4 usos) e, após FR-009, `Metrics.tsx` | manter |
| campo `funnel` / `leaderboard` no payload de `/overview` | `apps/server/src/routes/overview.ts:105-115, 92-100` | ver Decision 9 | manter no servidor |

**Rationale**: remover `BarH` ou `SDD_STAGES` quebraria telas fora do escopo
desta spec.

**Alternatives considered**:

- *Deixar todos os símbolos órfãos no código*: **rejeitado** — código morto
  que o `lint` sinaliza e que sugere falsamente que o funil ainda existe.
- *Remover tudo que o card tocava (incluindo `BarH` e `SDD_STAGES`)*:
  **rejeitado, quebraria** `ExecutionDetail.tsx:853` e `PipelineProgress.tsx`,
  ambos fora do escopo desta spec.

---

## Decision 9 — Não alterar o payload de `/api/v1/overview` na remoção de cards

**Decision**: os campos `funnel[]` e `leaderboard[]` **permanecem** no contrato
de `GET /api/v1/overview`. A remoção é exclusivamente de renderização.

**Rationale**: FR-001 e FR-002 falam do que o dashboard **exibe**, não do que a
API serve. `leaderboard` é montado por SQL inline em `overview.ts:92-100` e não
é usado só pelo card removido — remover campo de contrato é mudança
incompatível sem requisito que a peça, e ampliaria o blast radius para
consumidores fora do painel. `meta.freshness`/ETag e os testes de roundtrip
existentes (`apps/server/test/lib/roundtrip.test.ts`) validam o shape completo:
mexer no payload exigiria atualizar fixtures sem ganho.

**Alternatives considered**: *remover `funnel` do SQL para economizar uma
query*: **rejeitado** — otimização não pedida, com custo de contrato.

---

## Decision 10 — Escopo do indicador em cada tela

**Decision**: dashboard principal recebe **um KPI compacto agregado** (modelo
de maior custo no período + total medido + cobertura); a página de Métricas
recebe o **detalhe completo** (todos os modelos, com custo e tokens, e o
recorte por etapa).

**Rationale**: é literalmente o que a clarificação da spec decidiu (Session
2026-07-28, Q3: "resumo compacto/agregado no dashboard principal; detalhe
completo por modelo e por etapa na página de Métricas"), e o que SC-001 mede
("identificar o modelo de maior custo em menos de 10 segundos, sem navegar").
A KPI row do `Overview.tsx:143` já é um `grid-7` de `KpiCard` — o formato
compacto tem componente pronto.

**Restrição de consistência (SC-005)**: as duas telas MUST derivar do mesmo
endpoint e do mesmo agregador puro, para não divergirem de valor. Por isso o
agregador é função pura compartilhada (Decision 5), não cálculo duplicado por
tela.

**Alternatives considered**:

- *Detalhe completo nas duas telas*: **rejeitado** — polui o dashboard, que é
  visão de topo, e contraria a clarificação Q3 da spec.
- *Custo por modelo só na página de Métricas*: **rejeitado** — violaria FR-003
  (que cita as duas telas) e SC-001 (identificar o modelo de maior custo **sem
  navegar** para outra tela).
- *Cada tela agregando por conta própria a partir do payload bruto*:
  **rejeitado** — é exatamente como duas telas passam a divergir de valor,
  quebrando SC-005.

---

## NEEDS CLARIFICATION restantes

**Nenhum.** Os três pontos abertos na spec foram resolvidos na fase `clarify`
(seção `## Clarifications`, Session 2026-07-28) e os pontos técnicos
levantados nesta pesquisa foram fechados por sondagem empírica (S1–S8).

Um ponto é registrado como **risco conhecido**, não como unknown: o endpoint
novo é `[PROPOSTA]` e sua forma final (nomes de campos da resposta) só é
confirmada na implementação, contra o banco real — é exatamente o que o
cenário Roundtrip do `quickstart.md` verifica.
