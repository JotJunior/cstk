# Briefing: cstk-panel

> **Consolidado em**: 2026-05-24
> **Fonte**: [`backend-brief.md`](./backend-brief.md) + [`frontend-brief.md`](./frontend-brief.md)
> **Protótipo de referência**: `docs/06-ui-ux-design/castk-panel/project/`
> **Método**: consolidação de documentos existentes (sem entrevista adicional)
> Inferências marcadas com `[INFERENCIA]`. Decisões em aberto marcadas com `[DECISAO-ABERTA]`.

---

## 1. Visão e Propósito

O **cstk-panel** é um **dashboard de observabilidade read-only** para acompanhar o andamento de projetos e features executados pelos orquestradores autônomos `agente-00c` / `feature-00c` (pipeline SDD: specify → clarify → plan → checklist → create-tasks → execute-task → review-task).

- **Tom visual**: ferramenta técnica de observabilidade. Referências: Grafana, Linear, Vercel Dashboard, Datadog. Densa em informação porém limpa. **Dark-mode-first**.
- **Natureza**: somente leitura. O painel nunca escreve nada. Não há CRUD, não há formulários de mutação. Só consulta, filtro, drill-down e busca.
- **Posição na arquitetura**: consumidor derivado da `knowledge.db` (índice SQLite+FTS5, schema v2), exatamente como o `cstk recall`. **A fonte da verdade é o `state.json` transacional** de cada execução; a `knowledge.db` é um índice derivado e reconstruível (`cstk recall --reindex`).

```
state.json (fonte da verdade, transacional, por feature)
   │  ingestão best-effort (hook fim-de-onda) / cstk recall --reindex
   ▼
knowledge.db (índice derivado, SQLite+FTS5, ~/.claude/cstk/)
   │  ABRE EM MODO RO ◄── back-end vive aqui (read-only)
   ▼
API HTTP/JSON ──► cstk-panel (SPA React)
```

---

## 2. Usuários e Stakeholders

- **Persona primária**: engenheiro / tech-lead que dispara execuções autônomas e precisa ver, num relance, **progresso, custo, alertas críticos e qualidade**.
- **Usuário**: individual (uso pessoal/ferramental do ecossistema cstk). [INFERENCIA: não há multi-tenant nem RBAC real no escopo MVP]
- **Sem autenticação real**: login decorativo no máximo.

---

## 3. Escopo

### MVP (em escopo)

1. **SPA front-end** (React 19 + Vite) com 9 telas principais + 2 auxiliares:
   - Visão Geral (overview/portfolio)
   - Projetos
   - Features
   - Execuções (detalhe — tela mais rica, com WavesTimeline)
   - Alertas
   - Métricas agregadas
   - Tarefas (cross-execução)
   - Incidentes (events timeline)
   - Busca de Conhecimento (FTS5 / bm25)
   - Detalhe de Decisão (modal/página)
   - Fonte de Dados (opcional — sobre / health)

2. **Back-end de API** (servidor HTTP read-only sobre `knowledge.db`):
   - Endpoints REST/JSON `GET /api/v1/*`
   - Abre SQLite em modo `mode=ro&immutable=1`
   - Serve frescor (`mtime` + `max(ingested_at)`), saúde, degradação
   - Paginação obrigatória em `decisions` e `search`

3. **Estados obrigatórios em toda tela**: carregando (skeletons), vazio, erro, degradado (banco ausente/parcial)

4. **Design pixel-perfect** conforme protótipo em `docs/06-ui-ux-design/castk-panel/`

### Fora de Escopo (explícito)

- Nenhuma escrita / edição de dados (read-only absoluto)
- Sem autenticação / RBAC reais
- Sem integração real com SQLite **no protótipo** (dados de exemplo apenas no protótipo; a implementação real lê o banco)
- Não exibir tokens/$ de custo (não existem — usar `tool_calls` como proxy)
- Não criar telas de configuração de orquestrador
- Não reimplementar a árvore de decisões (é da skill `decision-tree` sobre `state.json`)
- Não reimplementar o mix de modelos na knowledge.db (fonte canônica: `model-routing-report.sh`)
- Não tocar `state.json` nem reconstruir o índice (`--reindex`)

---

## 4. Prioridades e Trade-offs

- **Honestidade de métrica**: custo = `tool_calls` (nunca `$`, `USD`, `tokens`). Rotular sempre como "proxy: tool calls".
- **Degradar, nunca quebrar**: banco ausente/vazio/corrompido = estado de primeira classe com resposta `200` + sinal de degradação. Nunca 500 por condição de dado.
- **Read-only reforçado**: banco aberto com `mode=ro&immutable=1`. Nenhum caminho de código emite `INSERT/UPDATE/DELETE`.
- **Não reinventar**: mix de modelos, árvore de decisões e `--reindex` têm donos canônicos fora do painel.
- **Drill-down** como padrão de navegação: tudo clicável até o nível mais granular.

---

## 5. Restrições

- **Técnica — banco de dados**: somente-leitura absoluto sobre SQLite+FTS5 `knowledge.db` schema v2
- **Técnica — sem tokens/custo**: harness não expõe consumo de tokens; proxy é `tool_calls`
- **Técnica — conteúdo UNTRUSTED**: campos textuais (`contexto`, `justificativa`, `evidencia`, `pergunta`, `resposta`, `body` FTS) vêm de saídas de agentes, já passaram por scrub de segredos na ingestão, mas devem ser tratados como não-confiáveis
- **Técnica — FTS5 injection**: escaping obrigatório de duas camadas (FTS5 + SQL parametrizado) na busca
- **Técnica — sem autenticação real no protótipo**: bind em `localhost` por padrão; CORS restrito à origem do front-end

---

## 6. Stack Técnica

### Front-end (definido)
- **Framework**: React 19 + Vite
- **Runtime**: Node.js
- **Tipografia**: Inter (UI) + JetBrains Mono (IDs, valores numéricos, evidências)
- **Tema**: dark-mode-first; tema claro como alternativa
- **Design tokens**: ver `docs/06-ui-ux-design/castk-panel/project/styles.css`
  - Fundo: `#0B0D11`, superfícies: `#11141A` a `#262C38`
  - Acento âmbar: `#E8B341`
  - Semânticas: sucesso `#4ADE80`, atenção `#F59E0B`, crítico `#F0656A`, info `#60A5FA`, em andamento `#22D3EE`
  - Modelos (cores fixas): haiku `#60A5FA`, sonnet `#A78BFA`, opus `#F472B6`, fallback `#6C7480`
  - Score: 0 `#F0656A`, 1 `#F59E0B`, 2 `#FACC15`, 3 `#4ADE80`
- **Fonte de verdade do design**: `docs/06-ui-ux-design/castk-panel/project/` (recriar pixel-perfect; não copiar estrutura interna)

### Back-end [DECISAO-ABERTA: stack]
- **Candidatos** (em ordem de menor atrito):
  1. **Go** — coerente com ecossistema CashBeer/microsserviços; `mattn/go-sqlite3` ou `modernc.org/sqlite`; binário único [recomendação default dos briefs]
  2. **Node/TS** — coerente com front-end React/TS; `better-sqlite3` síncrono
  3. **Python** — `sqlite3` stdlib + FastAPI; FTS5 nativo
- **Empacotamento** [DECISAO-ABERTA]: subcomando `cstk panel serve` vs serviço standalone separado
- **Mix de modelos** [DECISAO-ABERTA]: Opção A (omitir — leitor puro de knowledge.db) vs Opção B (delegar a `model-routing-report.sh` com acesso a state-dirs)

### Banco de dados
- SQLite 3 + FTS5, schema v2
- Caminho: flag/config explícita > `$CSTK_KNOWLEDGE_DB` > `~/.claude/cstk/knowledge.db`
- DSN: `file:/abs/path/knowledge.db?mode=ro&immutable=1&_busy_timeout=5000`
- `PRAGMA quick_check` na inicialização / endpoint de saúde

---

## 7. Arquitetura de Navegação

**Layout base**: sidebar fixa 232px (esquerda) + topbar + área de conteúdo

### Sidebar
- Seção "observar": Visão Geral, Projetos, Features, Execuções
- Seção "diagnosticar": Alertas (badge de contagem crítica), Métricas, Tarefas, Incidentes, Busca de Conhecimento
- Rodapé: `DataFreshnessIndicator` ("índice atualizado há Xm") + estado do banco + toggle de tema

### Topbar
- Breadcrumb contextual navegável
- Seletor global de período: 24h / 7d / 30d / tudo
- Busca rápida (atalho `/`)
- Filtro global de projeto

### Hierarquia de drill-down
```
Projeto → Feature → Execução → Onda → Decisão | Tarefa | Evento | Alerta
```

---

## 8. Schema (fonte de verdade — tabelas v2)

| Tabela | Grão | Campos principais |
|--------|------|-------------------|
| `executions` | 1 por execução | `project`, `feature`, `execucao_id`, `status`, `motivo_termino`, `etapa_corrente`, `iniciada_em`, `terminada_em`, `duracao_segundos`, `ondas_total`, `tool_calls_total`, `wallclock_total_segundos`, `subagentes_spawned`, `profundidade_max`, `decisoes_total`, `bloqueios_humanos_total`, `sugestoes_skills_total`, `issues_toolkit_abertas` |
| `waves` | 1 por onda | `wave`, `etapa`, `inicio`, `fim`, `wallclock_seconds`, `tool_calls`, `motivo_termino`, `n_etapas`, `n_skills` |
| `decisions` | 1 por decisão | `wave`, `etapa`, `agente`, `escolha`, `score` (0–3), `contexto`, `justificativa`, `evidencia` |
| `tasks` | 1 por tarefa | `wave`, `outcome` (`pass`\|`fail`), `testes_rodados`, `testes_passados`, `lint_ok`, `arquivos_tocados` |
| `events` | 1 por incidente | `event_type` (`lock_contention`\|`validation_failed`\|`wave_retry`\|`schedule_wait`), `timestamp`, `descricao` |
| `alert_signals` | 1 por alerta | `tipo` (`circular`\|`budget_breach`), `subtipo`, `valor_consumido`, `valor_threshold`, `descricao`, `wave` |
| `bloqueios` | 1 por bloqueio | `status`, `pergunta`, `contexto_para_resposta`, `resposta`, `decisao_id`, `disparado_em`, `respondido_em`, `latencia_segundos` |
| `skills` | 1 por invocação | `skill_name`, `decisao_id`, `wave` |
| `retros` | 1 por retrospectiva | `texto`, `wave` |
| `knowledge_fts` | espelho FTS5 | `body` (indexada), `type`, `project`, `feature`, `wave`, `source_id`, `source_ts` (UNINDEXED) |
| `schema_meta` | metadata | `key=schema_version` (= `2`) |

**Colunas de proveniência** (presentes em todas as tabelas-fonte):
`project`, `feature`, `wave`, `execucao_id`, `source_ts`, `source_id`, `ingested_at`

**Chave natural de deduplicação**: `UNIQUE(project, feature, wave, source_id)`

**Vocabulário canônico**:
- Status: `em_andamento`, `aguardando_humano`, `concluida`, `abortada`
- Etapas SDD: `briefing`, `constitution`, `specify`, `clarify`, `plan`, `checklist`, `create-tasks`, `execute-task`, `review-task`
- Motivo de término de onda: `etapa_concluida_avancando`, `threshold_proxy_atingido`, `bloqueio_humano`, `aborto`, `concluido`
- Score de decisão: 0 (pausa/humano) · 1 (pausa) · 2 (decide por contexto) · 3 (decide com evidência)

---

## 9. Princípios Inegociáveis

1. **Read-only absoluto**: banco aberto com `mode=ro&immutable=1`. Zero `INSERT/UPDATE/DELETE/CREATE`.
2. **Degradar, nunca quebrar**: banco ausente/vazio/corrompido = `200` com sinal de degradação. Nunca 500 por estado de dado.
3. **Honestidade de métrica**: sem `$`, `USD`, `tokens`. Custo = `tool_calls` como proxy. Não inventar campos que não existem no schema.
4. **Não reimplementar o que tem dono**: mix de modelos (`model-routing-report.sh`), árvore de decisões (skill `decision-tree`), reindex (`cstk recall --reindex`).
5. **Conteúdo UNTRUSTED**: campos textuais de agentes servidos como texto puro, sem interpretação. Front-end escapa na renderização (LLM01/ASI09).
6. **Snapshot que muda**: tratar `knowledge.db` como arquivo que pode ser reescrito por trás (ingestão best-effort). Não segurar conexão assumindo imutabilidade total.
7. **Sem autenticação real**: bind `localhost` por padrão. CORS restrito à origem do front-end.

---

## 10. Superfície de API (contrato completo)

Prefixo: `/api/v1`. Todos os endpoints são `GET`. Filtros globais: `project`, `feature`, `status`, `period` (`24h|7d|30d|all`), `q`. Paginação por `limit`+`offset` ou cursor.

Envelope padrão de resposta:
```json
{
  "data": "...",
  "meta": {
    "degraded": false,
    "reason": null,
    "freshness": { "mtime": "...", "max_ingested_at": "..." },
    "schema_version": "2"
  }
}
```

| Endpoint | Tela |
|----------|------|
| `GET /api/v1/health` | saúde, frescor, contagens |
| `GET /api/v1/overview?period=` | Visão Geral — KPIs, alertas recentes, execuções em andamento, leaderboard, funil |
| `GET /api/v1/projects` | lista de projetos com rollup |
| `GET /api/v1/projects/{project}` | detalhe do projeto |
| `GET /api/v1/features?project=&status=` | lista de features |
| `GET /api/v1/features/{project}/{feature}` | detalhe da feature |
| `GET /api/v1/executions/{execucao_id}` | detalhe da execução |
| `GET /api/v1/executions/{execucao_id}/waves` | WavesTimeline |
| `GET /api/v1/executions/{execucao_id}/decisions?wave=&etapa=&score=` | decisões (UNTRUSTED textuais) |
| `GET /api/v1/executions/{execucao_id}/tasks` | tarefas + KPI pass rate |
| `GET /api/v1/executions/{execucao_id}/events` | eventos / incidentes |
| `GET /api/v1/executions/{execucao_id}/alerts` | alertas |
| `GET /api/v1/executions/{execucao_id}/bloqueios` | bloqueios humanos (UNTRUSTED textuais) |
| `GET /api/v1/executions/{execucao_id}/skills` | skills invocadas |
| `GET /api/v1/alerts?tipo=&project=&feature=&period=` | central de alertas |
| `GET /api/v1/metrics/cost-over-time?project=&period=` | custo ao longo do tempo |
| `GET /api/v1/metrics/throughput-by-stage` | throughput por etapa |
| `GET /api/v1/metrics/test-pass-rate` | taxa de testes |
| `GET /api/v1/metrics/human-latency` | latência humana |
| `GET /api/v1/metrics/clarify-resolution` | clarify auto-resolution rate (derivada/aproximada) |
| `GET /api/v1/metrics/decisions-by-score` | decisões por score |
| `GET /api/v1/metrics/execution-duration` | duração de execuções |
| `GET /api/v1/metrics/depth-subagents` | profundidade × subagentes |
| `GET /api/v1/tasks?project=&feature=&outcome=` | tarefas cross-execução |
| `GET /api/v1/events?event_type=&project=&period=` | incidentes cross-execução |
| `GET /api/v1/search?q=&type=&project=&feature=&limit=` | busca FTS5 (bm25, UNTRUSTED body) |

---

## 11. Componentes de Front-end (design system)

| Componente | Descrição |
|------------|-----------|
| `KpiCard` | rótulo, valor grande, delta, sparkline, ícone, cor semântica |
| `StatusBadge` | `em_andamento` (ciano pulsante), `aguardando_humano` (âmbar), `concluida` (verde), `abortada` (vermelho/cinza) |
| `ScoreChip` | 0–3 com escala de cor + tooltip |
| `SeverityBadge` | crítico/atenção/info |
| `PipelineProgress` | trilho com 9 etapas SDD |
| `WavesTimeline` / Gantt | faixas por onda com etapa, duração, tool_calls, motivo_termino |
| `BudgetGauge` | `valor_consumido` / `valor_threshold` com zona de estouro |
| `OutcomePill` | pass/fail |
| `EventIcon` | ícone+cor por `event_type` |
| `ProvenanceCrumb` | `projeto / feature / execução / onda` |
| `DataTable` | ordenável, filtrável, denso, com row-expand |
| Charts | Donut, BarH, BarV, Line/Area, Histogram, Gauge, Sparkline, Funnel |
| `FilterBar` | período + projeto + feature + tipo |
| `EmptyState` / `LoadingSkeleton` / `ErrorState` / `DegradedBanner` | 4 estados obrigatórios |
| `DataFreshnessIndicator` | "índice atualizado há Xm" + status do banco |

---

## 12. Qualidade e Segurança

- **FTS5 escaping**: dois níveis obrigatórios — tokenização com aspas + binding parametrizado SQL
- **Path traversal**: caminho do banco canonicalizado e confinado; não aceitar path arbitrário do cliente
- **Content-Type**: `application/json`, `X-Content-Type-Options: nosniff`
- **Cache**: `ETag` / `Last-Modified`; `If-None-Match` → `304`. Invalidar por `mtime` + `max(ingested_at)`
- **Paginação obrigatória**: `decisions` (≈856 linhas) e `search`
- **Rate-limit leve** na busca FTS5 (pode ser custosa)
- **Subprocesso (Opção B mix-modelos)**: executar `model-routing-report.sh` com argumentos validados, sem shell-string interpolada, timeout, captura de stderr

---

## 13. Visão de Futuro [INFERENCIA]

- Integração real com `knowledge.db` (a implementação React usa a API; o protótipo usa dados de exemplo)
- Possível empacotamento como subcomando `cstk panel serve` (ponto de decisão em aberto)
- Mix de modelos via Opção B se houver acesso aos state-dirs
- Suporte a múltiplos projetos simultâneos já previsto no schema (coluna `project` em todas as tabelas)

---

## 14. Decisões em Aberto

| # | Decisão | Opções | Impacto |
|---|---------|--------|---------|
| D1 | **Stack do back-end** | Go (recomendado) / Node/TS / Python | Definir antes de codar. O brief não depende desta escolha. |
| D2 | **Empacotamento** | `cstk panel serve` (subcomando) / serviço standalone | Afeta distribuição e documentação de instalação |
| D3 | **Mix de modelos** | Opção A: omitir (card "indisponível nesta fonte") / Opção B: delegar a `model-routing-report.sh` | Opção B amplia superfície (acesso a state-dirs, exec de subprocesso) |
| D4 | **Formato de API** | REST/JSON (assumido) / GraphQL | GraphQL não traz ganho claro para painel read-only |
| D5 | **Granularidade de séries temporais** | por dia / por execução | Depende do volume real de dados — validar com dados reais |

---

## 15. Não-Objetivos (síntese)

- Nenhuma escrita no `knowledge.db`
- Não tocar `state.json`
- Não reimplementar mix de modelos (FR-017 da feature `knowledge-db-metrics`)
- Não reimplementar árvore de decisões
- Não expor tokens/$ de custo
- Sem auth/RBAC real, sem mutação, sem config de orquestrador
- O painel (e seu back-end) só **observam**

---

*Consolidado de `backend-brief.md` + `frontend-brief.md` (schema v2 real, cstk v3.19.x).
Protótipo de referência: `docs/06-ui-ux-design/castk-panel/project/`.
Stack alvo: React 19 + Vite + Node.js.*
