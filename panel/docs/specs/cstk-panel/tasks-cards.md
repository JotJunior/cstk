# tasks-cards.md — Auditoria card-a-card · protótipo vs implementação

**Data:** 2026-05-25
**Protótipo de referência:** `docs/06-ui-ux-design/castk-panel/project/` (`app.jsx`,
`screens_main.jsx`, `screens_aux.jsx`)
**Implementação:** `apps/web/src/` (screens + components)
**Método:** inventário de cada *card* / bloco visual do protótipo, com checagem de
presença e fidelidade na implementação. Complementa as tarefas pendentes
`5.1.5`, `5.2.4` e `8.2.6` do `tasks.md` (verificação visual lado a lado / SC-006).

## Legenda de status

| Status | Significado |
|--------|-------------|
| ✅ OK | Implementado fielmente ao protótipo |
| ⚠️ DIVERGENTE | Presente, mas com diferença visual/estrutural a reconciliar |
| ❌ AUSENTE | Card do protótipo não existe na implementação |
| 🔵 INTENCIONAL | Divergência por decisão documentada (constituição / honestidade de métrica / schema v2) |

---

## 0. Shell — Sidebar + Topbar (`app.jsx`)

| ID | Card / bloco | Status | Nota |
|----|--------------|--------|------|
| CARD-SHELL-01 | Sidebar · brand | ✅ | Feito (2026-05-25). `brand-tag` restaurou `observabilidade · v3.19`. |
| CARD-SHELL-02 | Sidebar · nav (observar 4 + diagnosticar 5) | ✅ | Rotas e agrupamento conferem. |
| CARD-SHELL-03 | Sidebar · rodapé de frescor (índice atualizado) | ✅ | Feito (2026-05-25). `App.tsx` fia `freshness` (via `useHealth`) + `alertCount` (críticos via `useAlerts`). |
| CARD-SHELL-04 | Sidebar · link "fonte de dados" | ✅ | Feito (2026-05-25). Navega para `/source` (ver §12). |
| CARD-SHELL-05 | Sidebar · toggle de tema (sun/moon) | ✅ | Feito (2026-05-25). Presente, persiste `data-theme`; rotulado "tema (decorativo)" — paleta light é trabalho futuro (dark-mode-first). |
| CARD-SHELL-06 | Topbar · breadcrumbs | ✅ | Componente `Breadcrumb`. |
| CARD-SHELL-07 | Topbar · period tabs (24h/7d/30d/tudo) | ✅ | |
| **CARD-SHELL-08** | **Topbar · filtro de projeto (`select` "Todos os projetos")** | ✅ | **Implementado (2026-05-25).** `Topbar.tsx`: select populado por `useProjects()`, valor derivado da rota (`useMatch('/projects/:project')`); selecionar navega ao detalhe, "Todos" → `/projects`. Escopar todas as telas por projeto fica para o item planejado de filtro global. |
| CARD-SHELL-09 | Topbar · busca rápida + atalho `/` | ✅ | Enter navega para `/search?q=`. |

---

## 1. Visão Geral (`OverviewScreen`)

| ID | Card | Status | Nota |
|----|------|--------|------|
| CARD-OV-01 | KPI row (6 cards) | ✅ | Projetos, Em andamento, Alertas críticos, Custo·proxy, Tempo de parede, Test pass rate. |
| CARD-OV-02 | Execuções em andamento | ✅ | |
| CARD-OV-03 | Alertas críticos recentes | ✅ | |
| CARD-OV-04 | Funil do pipeline (9 etapas SDD) | ✅ | |
| CARD-OV-05 | Mix de modelos (donut) | ✅ | Rotulado `derivado · decisões` (FR-010). Já exibia o mix derivado — agora consistente com Métricas (D3 revisado 2026-05-25). |
| CARD-OV-06 | Custo por feature · proxy (BarH) | ✅ | |
| CARD-OV-07 | Atividade recente | ✅ | |

> Tela mais fiel ao protótipo. Sem pendências.

---

## 2. Projetos (`ProjectsScreen`)

| ID | Card | Status | Nota |
|----|------|--------|------|
| CARD-PRJ-01 | Cards de rollup por projeto (grid-3) | 🔵 | **Divergência aceita (2026-05-25):** `description`/`repo` não existem no schema v2 — mantido como mock do protótipo. Lacuna registrada em [data-gaps.md](data-gaps.md) (P2·#7) para instrumentar no orquestrador. |
| CARD-PRJ-02 | "Todas as features" (tabela) | ✅ | `FeaturesTable`. |
| CARD-PRJ-03 | Filtros da tabela (busca + select projeto + select status) | ✅ | Feito (2026-05-25). `FeaturesFilterBar` + `filterFeatures()` (client-side). |

---

## 3. Detalhe de Projeto (`ProjectDetailScreen`)

| ID | Card | Status | Nota |
|----|------|--------|------|
| CARD-PRJD-01 | 5 KPIs (Features, Em andamento, Tool calls, Wallclock, Alertas) | ✅ | |
| CARD-PRJD-02 | Features de {project} (tabela) | ✅ | |

---

## 4. Features · lista (`FeaturesListScreen`)

| ID | Card | Status | Nota |
|----|------|--------|------|
| CARD-FT-01 | "Features · todas" (tabela) | ✅ | |
| CARD-FT-02 | Filtros (busca + select projeto + select status) | ✅ | Feito (2026-05-25). Reusa `FeaturesFilterBar`. |

---

## 5. Detalhe de Feature (`FeatureDetailScreen`)

| ID | Card | Status | Nota |
|----|------|--------|------|
| CARD-FTD-01 | Header (status, título, breadcrumb) | ✅ | |
| CARD-FTD-02 | Chips de stack (`stack_sugerida`) | ✅ | Feito (2026-05-25). Lê `stackSugerida` da 1ª execução com stack. |
| CARD-FTD-03 | Botões de header ("Ver execução", "Árvore de decisões") | ✅ | Feito (2026-05-25). "Ver execução" navega à execução recente; "Árvore" decorativo. |
| CARD-FTD-04 | Grid de stats (6) | ✅ | `Subagentes` trocado por `Execuções` — aceitável. |
| CARD-FTD-05 | Execuções (tabela) | ✅ | |
| CARD-FTD-06 | Retrospectivas (card) | ✅ | Feito (2026-05-25). Endpoint `/features/:p/:f` agora embute `retros` (query+rota); card renderiza. |

---

## 6. Detalhe de Execução (`ExecutionScreen`)

| ID | Card | Status | Nota |
|----|------|--------|------|
| CARD-EX-01 | Header (status, execId, título, breadcrumb, stats, pipeline, stack chips) | ✅ | Inclui chips de stack aqui (≠ FeatureDetail). |
| CARD-EX-02 | Botões de header ("árvore de decisões", "abrir no recall") | ✅ | Feito (2026-05-25). Decorativos (`disabled` + tooltip) — recursos externos ao painel. |
| CARD-EX-03 | Linha do tempo de ondas (gantt) | ✅ | Seleção de onda + legenda. |
| CARD-EX-04 | Card lateral "Decisões por score" | ✅ | Feito (2026-05-25). Endpoint `/executions/:id/score-distribution` + card 0..3. |
| CARD-EX-05 | Card lateral "Skills mais invocadas" | ✅ | Feito (2026-05-25). Voltou a card lateral (BarH); aba "Skills" removida; layout 2 colunas (`.exec-grid`). |
| CARD-EX-06 | Card lateral "Sugestões ao toolkit / Issues abertas" | ✅ | Feito (2026-05-25). `sugestoesSkillsTotal` + `issuesToolkitAbertas` do DTO. |
| CARD-EX-07 | Tabs (Decisões/Tarefas/Eventos/Alertas/Bloqueios) | ✅ | Aba "Skills" removida (virou card lateral). |
| CARD-EX-08 | DecisionModal (detalhe de decisão) | 🔵 | **Divergência aceita (2026-05-25):** expand inline mostra contexto/justificativa/evidência; modal considerado redundante. |

> Observação: o protótipo usa layout 2 colunas (gantt à esquerda + 3 cards de stats
> à direita). A impl é coluna única (gantt full-width → tabs), suprimindo os 3 cards
> laterais (CARD-EX-04/05/06).

---

## 7. Alertas (`AlertsScreen`)

| ID | Card | Status | Nota |
|----|------|--------|------|
| CARD-AL-01 | 4 KPIs (Total, Mov. circular, Breach, Severidades) | ✅ | |
| CARD-AL-02 | Central de alertas (tabela + filtros) | ✅ | Feito (2026-05-25). Filtro de projeto agora é `select` (via `useProjects`). Coluna "Quando" mantida como "Onda": `AlertSignalDTO` **não expõe timestamp** (exigiria mexer no DTO+parity); divergência aceita. Botão "mais filtros" omitido (decorativo). |

---

## 8. Métricas (`MetricsScreen`)

| ID | Card | Status | Nota |
|----|------|--------|------|
| CARD-MT-01 | 4 KPIs | ✅ | |
| CARD-MT-02 | Custo no tempo · proxy (AreaChart) | ✅ | |
| CARD-MT-03 | Test pass rate · 14d (AreaChart) | ✅ | Feito (2026-05-25). Endpoint novo `/metrics/test-pass-rate-series` (agrupa por `date(iniciada_em)`) + AreaChart. |
| CARD-MT-04 | Throughput por etapa (BarH) | ✅ | |
| CARD-MT-05 | Mix de modelos por etapa (StackedBars) | ✅ | Feito (2026-05-25, D3 revisado). Endpoint `/metrics/model-mix-by-stage` derivado de `decisions.escolha='model:%'`; rotulado "intenção do roteador · derivado". |
| CARD-MT-06 | Latência humana (Histograma) | ✅ | Feito (2026-05-25). `Histogram` (charts.tsx) + resumo p50/p95/max. |
| CARD-MT-07 | Mix de modelos · total (Donut) | ✅ | Feito (2026-05-25, D3 revisado). Endpoint `/metrics/model-mix` (donut), rotulado e `meta.approximate=true`. |
| CARD-MT-08 | Profundidade · subagentes (Scatter) | ✅ | Feito (2026-05-25). `ScatterChart` (charts.tsx) + resumo. |
| CARD-MT-09 | Decisões por score (BarH) | ✅ | |
| CARD-MT-10 | Duração das execuções | 🔵 | **Adicional** da impl (não existe no protótipo) — manter. |

---

## 9. Tarefas (`TasksScreen`)

| ID | Card | Status | Nota |
|----|------|--------|------|
| CARD-TK-01 | 5 KPIs | ✅ | |
| CARD-TK-02 | "Pass / fail no tempo" (StackedBars) | 🔵 | Omitido por decisão (comentário no código: séries temporais vivem em Métricas). |
| CARD-TK-03 | "Test pass rate · 14d" (AreaChart) | 🔵 | Idem. |
| CARD-TK-04 | Tarefas (tabela + filtros) | ✅ | Feito (2026-05-25). Tabs de outcome + `select` de projeto. |

---

## 10. Incidentes (`IncidentsScreen`)

| ID | Card | Status | Nota |
|----|------|--------|------|
| CARD-IN-01 | 4 KPIs (lock/validation/retry/schedule) | ✅ | |
| CARD-IN-02 | "Incidentes ao longo do tempo" (StackedBars) | ✅ | Feito (2026-05-25). `StackedBars` agregando `/events` por dia × tipo. |
| CARD-IN-03 | Timeline global (agrupada por data + filtro de tipo) | ✅ | |

---

## 11. Busca de Conhecimento (`SearchScreen`)

| ID | Card | Status | Nota |
|----|------|--------|------|
| CARD-SR-01 | Caixa de busca + chips de tipo (bm25) | ✅ | |
| CARD-SR-02 | Resultados (lista com highlight) | ✅ | Clique em decisão usa navegação (não modal — ver CARD-EX-08). |

---

## 12. Fonte de Dados (`SourceScreen`)

| ID | Card | Status | Nota |
|----|------|--------|------|
| CARD-SC-01 | Card "Fonte de dados" (caminho, schema, frescor, banner derivado) | ✅ | Feito (2026-05-25). `screens/Source.tsx` consome `/health` (expandido com path, sizeBytes e 11 contagens). |
| CARD-SC-02 | Card "Contagens por tabela" | ✅ | Feito (2026-05-25). 11 tabelas; coluna de tamanho por tabela omitida (não disponível na fonte). |

> **Resolvido (2026-05-25):** criada `screens/Source.tsx` + rota `/source` + link na
> Sidebar. `/health` foi expandido (backend) com `path`, `sizeBytes` e contagens das
> 11 tabelas. Tamanho por tabela individual não é exposto — coluna omitida.

---

## Resumo

| Status | Qtde |
|--------|------|
| ✅ OK | 48 |
| ⚠️ DIVERGENTE | 0 |
| ❌ AUSENTE | 0 |
| 🔵 INTENCIONAL / aceita | 5 |

> **Plano de cards concluído (2026-05-25).** Nenhum card ausente ou divergente
> em aberto. As 8 divergências 🔵 são decisões conscientes (Princípio III/IV,
> dados não disponíveis na fonte) — lacunas de dados catalogadas em
> [data-gaps.md](data-gaps.md) para instrumentação futura no orquestrador.

### Lacunas reais a endereçar (❌ + ⚠️ não-intencionais)

Ordenadas por impacto:

1. [x] **CARD-SHELL-08** — filtro de projeto no Topbar *(reportado pelo usuário; feito 2026-05-25)*
2. [x] **CARD-SC-01/02** — tela "Fonte de dados" + rota `/source` + link na Sidebar *(feito 2026-05-25)*
3. [x] **CARD-PRJ-03 / CARD-FT-02 / CARD-TK-04** — filtros nas tabelas de features e tarefas *(feito 2026-05-25)*
4. [x] **CARD-EX-02/04/05/06** — botões decorativos + cards laterais (score, skills, sugestões/issues) + layout 2 colunas *(feito 2026-05-25)*
5. [x] **CARD-FTD-02/03/06** — chips de stack, botões de header e card de Retrospectivas *(feito 2026-05-25)*
6. [x] **CARD-IN-02** — card "Incidentes ao longo do tempo" *(feito 2026-05-25)*
7. [x] **CARD-MT-03/06/08** — charts restaurados (área 14d, histograma, scatter) *(feito 2026-05-25)*
8. [x] **CARD-SHELL-03** — `freshness` + `alertCount` fiados no `<Sidebar />` *(feito 2026-05-25)*
9. [x] **CARD-EX-08** — mantido expand inline (modal redundante); divergência aceita *(2026-05-25)*
10. [x] **CARD-AL-02** — filtro projeto vira select; coluna "Onda" aceita (DTO sem timestamp) *(feito 2026-05-25)*
11. [x] **CARD-SHELL-01** ✅ feito (Lote B) · **CARD-PRJ-01** mantido como mock; lacuna em [data-gaps.md](data-gaps.md) *(2026-05-25)*

### Divergências aceitas (🔵 — não mexer sem revisar a decisão)

- ~~Mix de modelos → "indisponível"~~ **Revisado (2026-05-25):** agora exibido como mix DERIVADO rotulado em Overview e Métricas (D3 revisado; FR-010). Gap remanescente = mix *confirmado* (fallback), em data-gaps.md #5.
- Séries temporais em Tarefas (CARD-TK-02/03) → consolidadas em Métricas.
- CARD-MT-10 (Duração das execuções) → extra útil, manter.

### Como reauditar

Reabrir este arquivo após cada lote de correção e marcar `[x]` nas lacunas
resolvidas. Para a validação pixel-perfect final (tarefas `5.1.5` e `8.2.6` do
`tasks.md`), abrir cada tela ao lado do `cstk-panel.html` do protótipo.
