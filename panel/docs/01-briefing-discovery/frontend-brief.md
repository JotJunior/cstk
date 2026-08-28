# cstk-panel — Brief de Front-End para Protótipo (Claude Design)

> **Objetivo deste documento**: servir de entrada para o Claude Design gerar um
> **protótipo navegável** do `cstk-panel` — todas as telas, métricas, gráficos,
> cards, menus e estados. É um brief de **design/UX + dados**, não de
> implementação. Toda métrica aqui é **aterrada no schema real** do banco que o
> painel consome (não invente campos: o que não está aqui, o painel não tem).

---

## 1. O que é o cstk-panel

Um **dashboard de observabilidade read-only** para acompanhar o andamento de
projetos e features executados pelos orquestradores autônomos `agente-00c` /
`feature-00c` (pipeline SDD: specify → clarify → plan → checklist → create-tasks
→ execute-task → review-task).

- **Persona**: engenheiro/tech-lead que dispara execuções autônomas e precisa
  ver, num relance, **progresso, custo, alertas críticos e qualidade**.
- **Natureza**: **somente leitura**. O painel nunca escreve nada. Não há CRUD,
  não há formulários de mutação. Só consulta, filtro, drill-down e busca.
- **Tom visual**: ferramenta técnica de observabilidade (referências: Grafana,
  Linear, Vercel Dashboard, Datadog). Densa em informação porém limpa;
  **dark-mode-first**.

### Escopo do protótipo

- Foco em **navegação + visualização**. Sem autenticação real (ou um login
  decorativo único, opcional).
- Popular com **dados de exemplo realistas** (ver §11) — o protótipo é
  navegável e "preenchido", não wireframe vazio.
- Cada tela deve ter os 4 estados: **carregado**, **vazio**, **carregando**,
  **erro/degradado** (ver §9).

---

## 2. Fonte de dados (o que o painel realmente tem)

O painel lê um índice **SQLite + FTS5** (`~/.claude/cstk/knowledge.db`, schema
**v2**), que é **derivado** das execuções dos orquestradores. Estritamente
read-only e best-effort (pode estar ausente/parcial → ver estados degradados).

### Hierarquia de proveniência (o "eixo" de navegação)

```
Projeto  (ex: claude-ai-tips)
  └─ Feature  (ex: knowledge-db-metrics)
       └─ Execução  (execucao_id, ex: feat-knowledge-db-metrics-20260524-022752)
            └─ Onda / Wave  (onda-001 … onda-010)
                 ├─ Decisões      (decisions)
                 ├─ Tarefas       (tasks)
                 ├─ Eventos       (events)
                 ├─ Alertas       (alert_signals)
                 ├─ Bloqueios     (bloqueios)
                 └─ Skills        (skills)
```

### Tabelas e campos (use exatamente estes nomes/semântica)

**`executions`** — uma linha por execução (grão mais alto de métrica):
`project`, `feature`, `execucao_id`, `status`, `motivo_termino`,
`etapa_corrente`, `iniciada_em`, `terminada_em`, `duracao_segundos`,
`stack_sugerida`, `ondas_total`, `tool_calls_total`,
`wallclock_total_segundos`, `subagentes_spawned`, `profundidade_max`,
`decisoes_total`, `bloqueios_humanos_total`, `sugestoes_skills_total`,
`issues_toolkit_abertas`.

**`waves`** — uma linha por onda: `wave` (id, ex: `onda-003`), `etapa`,
`inicio`, `fim`, `wallclock_seconds`, `tool_calls`, `motivo_termino`,
`n_etapas`, `n_skills`.

**`decisions`** — decisões auditáveis: `wave`, `etapa`, `agente`, `escolha`,
`score` (inteiro **0–3**), `contexto`, `justificativa`, `evidencia`.

**`tasks`** — outcome de tarefa do backlog: `wave`, `outcome` (**`pass`** |
`fail`), `testes_rodados`, `testes_passados`, `lint_ok` (0/1),
`arquivos_tocados` (contagem).

**`events`** — timeline de incidentes: `event_type` (conjunto fechado:
`lock_contention`, `validation_failed`, `wave_retry`, `schedule_wait`),
`timestamp`, `descricao`.

**`alert_signals`** — sinais de alerta: `tipo` (**`circular`** |
**`budget_breach`**), `subtipo`, `valor_consumido`, `valor_threshold`,
`descricao`, `wave`.

**`bloqueios`** — bloqueios humanos: `status`, `pergunta`,
`contexto_para_resposta`, `resposta`, `decisao_id`, `disparado_em`,
`respondido_em`, `latencia_segundos`.

**`skills`** — skills invocadas: `skill_name`, `decisao_id`, `wave`.

**`retros`** — retrospectivas livres: `texto`, `wave`.

**Mix de modelos** (não é tabela; é agregação derivada): distribuição de
seleção de modelo por subagente — `haiku` / `sonnet` / `opus` / `manter-atual`
(fallback) + taxa de fallback.

### ⚠️ Honestidade de métrica (IMPORTANTE no design)

- **Custo NÃO é em tokens/$**. O harness não expõe consumo de tokens. O proxy de
  custo é **`tool_calls`**. Rotule sempre como **"Custo (proxy: tool calls)"** ou
  **"Tool calls"** — **nunca** invente `$`, `USD` ou "tokens".
- **`wallclock`** é tempo de parede em segundos (formate como `2m 13s`, `1h 04m`).
- O índice é **derivado e best-effort**: pode faltar (banco ausente) ou estar
  parcial. O design precisa de estados vazio/degradado de primeira classe.

### Vocabulário canônico de valores

- **Status de execução**: `em_andamento`, `aguardando_humano`, `concluida`,
  `abortada`.
- **Etapas (pipeline SDD)**: `briefing`, `constitution`, `specify`, `clarify`,
  `plan`, `checklist`, `create-tasks`, `execute-task`, `review-task`.
- **Motivo de término de onda**: `etapa_concluida_avancando`,
  `threshold_proxy_atingido`, `bloqueio_humano`, `aborto`, `concluido`.
- **Score de decisão**: 0 (pausa/humano) · 1 (pausa) · 2 (decide por contexto) ·
  3 (decide com evidência empírica).

---

## 3. Identidade visual

| Aspecto | Direção |
|--------|---------|
| **Tema** | Dark-mode-first; tema claro como alternativa. Fundo grafite/quase-preto (`#0E1116`-ish), superfícies elevadas em tons de cinza-azulado. |
| **Acento** | Um acento âmbar/dourado (alusão a "beer"/cstk) **OU** azul-ciano técnico. Usar com parcimônia (CTAs, seleção, séries primárias de gráfico). |
| **Semânticas** | Sucesso = verde; atenção/breach = âmbar; crítico = vermelho; info/neutro = azul; "em andamento" = ciano pulsante. |
| **Tipografia** | Sans geométrica para UI (Inter/Geist). **Mono** (JetBrains Mono / Geist Mono) para IDs, `execucao_id`, `tool_calls`, scores, trechos de evidência. |
| **Densidade** | Alta mas respirável. Cards com cantos suaves (8–12px), bordas de 1px sutis, sombras discretas. Grid de 8px. |
| **Dataviz** | Paleta de série categórica consistente (haiku/sonnet/opus com cores fixas). Gráficos minimalistas, sem 3D, sem gradientes berrantes. Sparklines em cards. |
| **Microcopy** | PT-BR, técnico mas claro. Tooltips explicam termos do glossário (§13). |

---

## 4. Arquitetura de navegação

**Layout base**: sidebar fixa à esquerda + topbar + área de conteúdo.

- **Sidebar (menu principal)**, com ícones + rótulos:
  1. **Visão Geral** (overview/portfolio) — `home`
  2. **Projetos** — `folder`
  3. **Features** — `git-branch`
  4. **Execuções** — `activity`
  5. **Alertas** — `alert-triangle` (com badge de contagem crítica)
  6. **Métricas** — `bar-chart`
  7. **Tarefas** — `check-square`
  8. **Incidentes** — `zap`
  9. **Busca de Conhecimento** — `search`
  - rodapé da sidebar: indicador de **frescor dos dados** ("índice atualizado há
    Xm") + estado do banco (ok/degradado) + toggle de tema.

- **Topbar**: breadcrumb contextual (`Projetos / claude-ai-tips /
  knowledge-db-metrics / onda-007`), seletor global de período (24h / 7d / 30d /
  tudo), busca rápida (atalho `/`), e filtro global de projeto.

- **Drill-down** é o padrão central: tudo é clicável até o nível mais granular
  (decisão, tarefa, evento, alerta).

### Mapa de telas

```
Visão Geral ─┬─> Projetos ──> [Projeto] ──> Features ──> [Feature] ──> [Execução]
             │                                                              │
             ├─> Alertas ───────────────────────────────────> [Execução] ──┤
             ├─> Métricas (analytics agregadas)                             │
             ├─> Tarefas (cross-execução) ──────────────────> [Execução] ──┤
             ├─> Incidentes (timeline global) ──────────────> [Execução] ──┤
             └─> Busca ──> [Decisão] / [Bloqueio] / [Retro] ──────────────> │
                                                                            v
                                              [Execução] ──> [Onda] ──> [Decisão|Tarefa|Evento|Alerta]
```

---

## 5. Telas (screen-by-screen)

Para **cada** tela: propósito, layout, componentes, métricas/gráficos e
data-binding (de qual tabela vem). Inclua os 4 estados (§9).

### 5.1 Visão Geral (Overview / Portfolio) — *tela inicial*

**Propósito**: panorama de tudo num relance.

- **Faixa de KPIs (cards no topo, 5–6)**:
  - Projetos ativos (count distinct `project`)
  - Features totais (count distinct `feature`)
  - Execuções: **em andamento** / concluídas / abortadas (donut ou stacked)
  - Alertas críticos abertos (count `alert_signals`) — card vermelho/âmbar
  - Custo total (Σ `tool_calls_total`) — rótulo "proxy: tool calls" + sparkline
  - Tempo total (Σ `wallclock_total_segundos`, formatado)
- **Coluna esquerda**:
  - **Alertas críticos recentes** (lista compacta: tipo, projeto/feature, onda,
    consumido/threshold) → clique vai ao detalhe da execução.
  - **Execuções em andamento** (cards com etapa_corrente, progresso de pipeline,
    custo corrente, mini-timeline de ondas).
- **Coluna direita**:
  - **Mix de modelos** (donut haiku/sonnet/opus/manter-atual + taxa de fallback).
  - **Atividade recente** (feed cronológico: execuções iniciadas/concluídas,
    bloqueios respondidos, alertas).
  - **Leaderboard de custo** (top features por `tool_calls_total`, barra horizontal).
- **Faixa inferior**: **funil do pipeline** — quantas features paradas em cada
  `etapa_corrente` (specify → … → review-task), como funil/barras.

### 5.2 Projetos

**Propósito**: lista/grid de projetos com rollup.

- Tabela/grid de cards, um por `project`: nome, nº de features, nº de execuções
  por status, custo agregado, alertas abertos, última atividade.
- Ordenável por custo, atividade, alertas. Busca por nome.
- Clique → tela do Projeto (lista de features daquele projeto + métricas
  agregadas do projeto).

### 5.3 Features (cross-project) e [Feature]

**Lista de Features**:
- Tabela: feature, projeto, **status** (badge), **progresso do pipeline** (barra
  por etapa), nº de ondas, custo (`tool_calls_total`), duração, nº de decisões,
  bloqueios, alertas. Filtros por projeto/status. Ordenação.

**[Feature] (detalhe)**:
- Header: nome, projeto, status, stack_sugerida (chips).
- Lista de **execuções** daquela feature (normalmente 1, mas pode haver
  re-execuções) → cada uma leva ao detalhe da execução.
- Métricas agregadas da feature + retrospectivas (`retros`) em destaque.

### 5.4 Detalhe da Execução — *tela mais rica (deep-dive)*

**Propósito**: tudo sobre uma execução (`execucao_id`).

- **Header de execução**: status (badge animado se `em_andamento`),
  `etapa_corrente`, duração (`duracao_segundos`), custo (`tool_calls_total`),
  ondas (`ondas_total`), subagentes (`subagentes_spawned`),
  profundidade_max, `motivo_termino` (se terminal). Botão "ver árvore de
  decisões".
- **Linha do tempo de ondas (Waves Timeline)** — componente central:
  - Estilo **gantt/stepper horizontal**: uma faixa por onda (`onda-001`…), com
    `etapa`, duração (`wallclock_seconds`), `tool_calls` (largura/intensidade),
    `motivo_termino` (cor), nº de skills/etapas. Marcar ondas que bateram
    `threshold_proxy_atingido` (pausa por orçamento).
  - Clique na onda → painel lateral com decisões/tarefas/eventos/alertas daquela
    onda.
- **Abas dentro da execução**:
  - **Decisões** (`decisions`): tabela/cronologia com `etapa`, `agente`,
    `escolha`, **score** (chip 0–3 colorido), e expand para
    `contexto`/`justificativa`/`evidencia` (mono). Filtro por score/etapa.
  - **Tarefas** (`tasks`): tabela com `outcome` (pass/fail badge),
    `testes_passados`/`testes_rodados` (ex: 1043/1043), `lint_ok`,
    `arquivos_tocados`. KPI de **test pass rate** no topo.
  - **Eventos** (`events`): timeline vertical de incidentes (ícone por
    `event_type`, `timestamp`, `descricao`).
  - **Alertas** (`alert_signals`): cards com `tipo`, `subtipo`,
    `valor_consumido` vs `valor_threshold` (mini-gauge), `wave`.
  - **Bloqueios** (`bloqueios`): pergunta/resposta, status, **latência humana**
    (`latencia_segundos` — destaque), link à decisão resultante.
- **Mini-cards laterais**: decisões por score (mini-bar), skills mais invocadas,
  sugestões ao toolkit (`sugestoes_skills_total`), issues abertas.

### 5.5 Alertas (Critical Alerts)

**Propósito**: central de alertas acionáveis.

- Feed/tabela de `alert_signals`, agrupável por `tipo`:
  - **Movimento circular** (`circular`) — sinal de loop/sofrimento do agente.
    Severidade alta. Mostrar `descricao`, projeto/feature/onda.
  - **Breach de orçamento** (`budget_breach`) — `subtipo` (tool_calls, wallclock,
    ciclos, recursão, estado), com **gauge `valor_consumido` / `valor_threshold`**
    e % de estouro.
- Filtros: tipo, projeto, feature, período. Ordenar por severidade/recência.
- Cada item → detalhe da execução na onda correspondente.
- Card de resumo no topo: total por tipo, tendência (sparkline 7d).

### 5.6 Métricas (Analytics agregadas)

**Propósito**: tendências e distribuições cross-execução.

Grade de gráficos (ver §8 para tipos):
- **Custo ao longo do tempo** (`tool_calls_total` por execução/data) — linha/área.
- **Throughput por onda** (`tool_calls` e `wallclock_seconds` por `etapa`) —
  qual etapa consome mais — barras.
- **Test pass rate** (Σ`testes_passados`/Σ`testes_rodados`) — gauge + tendência.
- **Taxa de auto-resolução do clarify** — derivada: proporção de bloqueios/itens
  de clarify resolvidos por decisão com `score>=2` vs escalados a humano.
- **Latência humana** (`latencia_segundos` dos bloqueios) — histograma/box.
- **Mix de modelos** — donut + barra empilhada por etapa; taxa de fallback
  (`manter-atual`).
- **Duração de execução** (`duracao_segundos`) — distribuição/leaderboard.
- **Profundidade de recursão / subagentes** — scatter ou barras.

Cada gráfico com seletor de período (topbar) e filtro por projeto/feature.

### 5.7 Tarefas (cross-execução)

**Propósito**: qualidade da entrega de tarefas.

- KPIs: total de tasks, **pass rate**, fail rate, média de `arquivos_tocados`,
  % com `lint_ok`.
- Tabela cross-execução: task, projeto/feature, onda, outcome, testes, lint,
  arquivos. Filtro por outcome (mostrar só `fail` para triagem).
- Gráfico de pass/fail ao longo do tempo.

### 5.8 Incidentes (Events timeline global)

**Propósito**: timeline operacional de incidentes.

- Timeline global de `events`, ícone/cor por `event_type`:
  `lock_contention`, `validation_failed`, `wave_retry`, `schedule_wait`.
- Agrupar por dia; filtro por tipo/projeto. KPI: contagem por tipo (7d).
- Item → execução/onda de origem.

### 5.9 Busca de Conhecimento (Knowledge Search)

**Propósito**: full-text sobre o conhecimento acumulado (o coração do `cstk recall`).

- Barra de busca proeminente + filtros: **tipo** (decisão / bloqueio / retro /
  skill), **projeto**, **feature**, período.
- Resultados rankeados (bm25): cada hit mostra tipo, proveniência
  (`projeto / feature / onda · data`), e trecho do corpo com termos destacados.
- Clique → detalhe (decisão/bloqueio/retro).
- Empty-state didático ("busque por 'lock contention', 'cache', 'snake_case'…").

### 5.10 Detalhe de Decisão (modal/página)

- `escolha`, `score` (0–3 com legenda), `etapa`, `agente`, `wave`, timestamp.
- `contexto`, `justificativa`, `evidencia` (mono, formatável).
- Link para a árvore de decisões da execução (decision-tree) e para a onda.

### 5.11 (Opcional) Sobre / Fonte de Dados

- Card read-only: caminho do banco, schema_version (2), frescor, contagens por
  tabela, nota "índice derivado e best-effort — reconstruível via `--reindex`".

---

## 6. Componentes reutilizáveis (design system)

- **KpiCard**: rótulo, valor grande, delta opcional, sparkline opcional, ícone,
  cor semântica.
- **StatusBadge**: `em_andamento` (ciano pulsante), `aguardando_humano` (âmbar),
  `concluida` (verde), `abortada` (vermelho/cinza).
- **ScoreChip**: 0–3 com escala de cor (0 vermelho → 3 verde) + tooltip.
- **SeverityBadge**: crítico/atenção/info.
- **PipelineProgress**: trilho com as 9 etapas SDD, etapa corrente destacada,
  concluídas preenchidas.
- **WavesTimeline / Gantt**: faixas por onda (ver §5.4).
- **BudgetGauge**: `valor_consumido` / `valor_threshold` com zona de estouro.
- **OutcomePill**: pass/fail.
- **EventIcon**: ícone+cor por `event_type`.
- **ProvenanceCrumb**: `projeto / feature / execução / onda`.
- **DataTable**: ordenável, filtrável, denso, com row-expand.
- **Charts**: Donut, BarH, BarV, Line/Area, Histogram, Gauge, Sparkline, Funnel.
- **FilterBar**: período + projeto + feature + tipo.
- **EmptyState / LoadingSkeleton / ErrorState / DegradedBanner** (§9).
- **DataFreshnessIndicator**: "índice atualizado há Xm" + status do banco.

---

## 7. Cards e métricas — catálogo (com derivação)

| Card / Métrica | Derivação (tabela.campo) |
|---|---|
| Custo (proxy: tool calls) | Σ `executions.tool_calls_total` |
| Tempo de parede total | Σ `executions.wallclock_total_segundos` |
| Execuções por status | count `executions` por `status` |
| Alertas críticos abertos | count `alert_signals` |
| Movimento circular | count `alert_signals` where `tipo='circular'` |
| Breach de orçamento | `alert_signals` where `tipo='budget_breach'` (`valor_consumido`/`valor_threshold`) |
| Test pass rate | Σ `tasks.testes_passados` / Σ `tasks.testes_rodados` |
| Task pass/fail | count `tasks.outcome` |
| Latência humana | `bloqueios.latencia_segundos` (avg/p50/p95) |
| Clarify auto-resolution | decisões `score>=2` na etapa `clarify` vs bloqueios escalados |
| Mix de modelos | agregação de seleção (haiku/sonnet/opus/manter-atual) |
| Decisões por score | count `decisions.score` (0–3) |
| Profundidade / subagentes | `executions.profundidade_max`, `subagentes_spawned` |
| Sugestões ao toolkit | `executions.sugestoes_skills_total` |
| Skills mais invocadas | count `skills.skill_name` |
| Funil de pipeline | count features por `executions.etapa_corrente` |

---

## 8. Gráficos (tipo por métrica)

- **Donut**: status de execução; mix de modelos.
- **Barra horizontal**: leaderboard de custo; throughput por etapa; skills.
- **Linha/Área**: custo no tempo; pass rate no tempo; incidentes no tempo.
- **Histograma/Box**: latência humana; duração de execução.
- **Gauge**: budget breach (consumido/threshold); test pass rate.
- **Funnel**: features por etapa do pipeline.
- **Gantt/Stepper**: timeline de ondas (por execução).
- **Sparkline**: dentro dos KpiCards (tendência compacta).

Cores de série **fixas e consistentes** para modelos: haiku, sonnet, opus,
manter-atual (cada um uma cor estável em todo o app).

---

## 9. Estados (obrigatórios em toda tela com dados)

- **Carregando**: skeletons (não spinners) com a forma do conteúdo.
- **Vazio (sem dados)**: ilustração + texto contextual ("Nenhuma execução ainda"
  / "Nenhum alerta — tudo sob controle").
- **Erro**: mensagem clara + ação de retry.
- **Degradado (banco ausente/parcial)**: banner não-bloqueante no topo — "Índice
  de conhecimento indisponível ou parcial. Os dados podem estar incompletos."
  (reflete a natureza best-effort/derivada do banco). A UI **não quebra**: mostra
  o que tem.

---

## 10. Fluxos de navegação (para o protótipo ligar as telas)

1. **Triagem por alerta**: Visão Geral → card de alerta → Detalhe da Execução na
   onda afetada → aba Alertas/Decisões.
2. **Acompanhar feature**: Features → [Feature] → [Execução] → WavesTimeline →
   clica onda → decisões/tarefas.
3. **Auditar qualidade**: Tarefas → filtra `fail` → [Execução] → aba Tarefas.
4. **Investigar incidente**: Incidentes → item → [Execução]/[Onda].
5. **Recuperar conhecimento**: Busca → "lock contention" → [Decisão] → árvore de
   decisões.
6. **Custo**: Métricas → custo no tempo → drill por projeto → leaderboard.

Todo breadcrumb é navegável; todo ID (`execucao_id`, `onda-NNN`) é clicável.

---

## 11. Dados de exemplo (popule o protótipo com isto)

**Projeto**: `claude-ai-tips` (fonte da verdade do ecossistema cstk).

**Features** (status / ondas / decisões / bloqueios / custo aproximado):
- `knowledge-db-metrics` — **concluida** · 10 ondas · 43 decisões · 0 bloqueios ·
  alto custo (feature longa) · pass rate 100% (suíte 1043/1043).
- `recall-autoconsume` — concluida · ~7 ondas · médio.
- `cstk-knowledge-db` — concluida · arquivada.
- `agente-00c-model-routing` — concluida · com decisões de seleção de modelo
  (bom para popular o mix de modelos).
- 1 feature fictícia **em_andamento** parada em `plan` (para card "em andamento").
- 1 feature fictícia **abortada** com `motivo_termino` (para status abortado).

**Alertas de exemplo**:
- `budget_breach` / subtipo `tool_calls`: consumido 96, threshold 80 (onda-005).
- `budget_breach` / subtipo `wallclock`: consumido 5600s, threshold 5400s.
- `circular`: "movimento circular detectado em clarify" (numa feature fictícia
  travada).

**Eventos**: `schedule_wait` (entre ondas), `wave_retry`, `validation_failed`,
`lock_contention`.

**Mix de modelos**: ex. haiku 40% / sonnet 35% / opus 15% / manter-atual 10%
(fallback 10%).

**Etapas para o funil**: distribua features pelas etapas SDD.

---

## 12. Não-objetivos (fora do protótipo)

- Nenhuma escrita/edição de dados (read-only absoluto).
- Sem autenticação/RBAC reais (login decorativo no máximo).
- Sem integração real com o SQLite no protótipo — use os dados de exemplo (§11).
- Não exibir tokens/$ de custo (não existem — use tool_calls como proxy).
- Não criar telas de configuração de orquestrador (o painel só observa).

---

## 13. Glossário (rótulos e tooltips)

| Termo | Significado |
|---|---|
| **Execução** | Uma rodada do orquestrador sobre uma feature (`execucao_id`). |
| **Onda (wave)** | Bloco de trabalho entre pausas/agendamentos (`onda-NNN`). |
| **Etapa** | Fase do pipeline SDD (specify, clarify, plan, …). |
| **Decisão** | Escolha auditável do agente, com `score` 0–3 e evidência. |
| **Score** | Confiança/autonomia da decisão: 0–1 pausa, 2 contexto, 3 evidência. |
| **Bloqueio humano** | Ponto em que o agente pausa e pede resposta humana. |
| **Latência humana** | Tempo entre disparar o bloqueio e ser respondido. |
| **Movimento circular** | Sinal de que o agente entrou em loop (alerta). |
| **Breach de orçamento** | Consumo (tool_calls/wallclock/ciclos) acima do threshold. |
| **Tool calls** | Proxy de custo (tokens não são expostos pelo harness). |
| **Mix de modelos** | Distribuição de seleção de modelo (haiku/sonnet/opus/manter-atual). |
| **Clarify rate** | % de ambiguidades auto-resolvidas (score≥2) vs escaladas. |
| **Skill** | Capacidade invocada pelo agente (specify, plan, …). |
| **Retro** | Retrospectiva/aprendizado registrado ao fim de uma onda. |

---

*Brief gerado a partir do schema v2 real do `knowledge.db` (feature
`knowledge-db-metrics`, cstk v3.19.x). O `cstk-panel` é consumidor read-only;
este repositório (`claude-ai-tips`) é a fonte da verdade dos dados.*
