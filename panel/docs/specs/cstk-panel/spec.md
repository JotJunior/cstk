# Feature Specification: cstk-panel — Dashboard de Observabilidade Read-Only

**Feature**: `cstk-panel`
**Created**: 2026-05-24
**Status**: Draft

> Fonte de verdade: `docs/01-briefing-discovery/briefing.md` (consolidado) +
> `docs/constitution.md` (v1.0.0) + protótipo visual em
> `docs/06-ui-ux-design/castk-panel/project/`.
>
> O cstk-panel observa a `knowledge.db` (índice SQLite + FTS5, schema v2)
> das execuções dos orquestradores `agente-00c` / `feature-00c`. É um
> **consumidor derivado e read-only** — a fonte da verdade transacional é o
> `state.json` de cada execução; a `knowledge.db` é índice reconstruível.

## Clarifications

### Session 2026-05-24

- Q: Stack do back-end de API (D1) — Go / Node-TS / Python? → A: Node.js +
  TypeScript. Decidido (score 2, in-process): a `stack_sugerida` do operador
  inclui `nodejs` e o front-end é React 19 + Vite (toolchain Node único),
  permitindo compartilhar tipos e ferramentas; SQLite read-only síncrono via
  driver Node maduro (`better-sqlite3`) atende o painel read-only. O briefing
  (§14) afirma que "o brief não depende desta escolha" e a constitution é
  agnóstica de linguagem — nenhuma opção viola princípio.

## User Scenarios & Testing

### User Story 1 - Visão Geral / Portfólio com drill-down (Priority: P1)

O engenheiro abre o painel e vê, num relance, o estado do portfólio:
quantas execuções estão em andamento, quantos alertas críticos existem,
custo agregado (proxy: tool calls), taxa de conclusão, leaderboard e funil
de etapas. A partir de qualquer KPI ou item ele desce a hierarquia
`Projeto → Feature → Execução → Onda → Decisão | Tarefa | Evento | Alerta`.

**Why this priority**: é a porta de entrada e a razão de existir do painel —
"ver progresso, custo, alertas e qualidade num relance". Sem ela não há MVP.

**Independent Test**: com a `knowledge.db` populada, abrir a visão geral e
confirmar que cada KPI exibido é navegável até o nível mais granular, sem
depender das demais telas.

**Acceptance Scenarios**:

1. **Given** uma `knowledge.db` com execuções em andamento e concluídas,
   **When** o usuário abre a Visão Geral, **Then** vê KPIs de progresso,
   alertas recentes, execuções em andamento, leaderboard e funil, com o
   período selecionável (24h / 7d / 30d / tudo).
2. **Given** a Visão Geral carregada, **When** o usuário clica num projeto,
   feature ou execução, **Then** navega para o detalhe correspondente
   mantendo o contexto (breadcrumb navegável).
3. **Given** custo agregado exibido, **When** o usuário inspeciona o rótulo,
   **Then** está rotulado como "proxy: tool calls" — nunca como `$`/`USD`/tokens.

---

### User Story 2 - Detalhe de Execução com WavesTimeline e Decisões (Priority: P1)

O engenheiro abre uma execução específica e vê a linha do tempo de ondas
(`WavesTimeline`): cada onda com etapa, duração, tool_calls e motivo de
término. A partir dali inspeciona decisões (com contexto, justificativa,
evidência, score), tarefas (pass/fail), eventos, alertas, bloqueios humanos
e skills invocadas — cada lista paginada e filtrável.

**Why this priority**: é a tela mais rica e o caso de uso central de
diagnóstico — entender *como* uma execução progrediu e *por que* o agente
decidiu o que decidiu.

**Independent Test**: abrir o detalhe de uma execução conhecida e validar
que a WavesTimeline reflete as ondas reais e que a lista de decisões abre o
detalhe de uma decisão individual, independentemente das outras telas.

**Acceptance Scenarios**:

1. **Given** uma execução com N ondas, **When** o usuário abre seu detalhe,
   **Then** vê a WavesTimeline com etapa, duração, tool_calls e motivo de
   término por onda.
2. **Given** a lista de decisões da execução, **When** o usuário filtra por
   onda, etapa ou score, **Then** a lista reflete o filtro e permanece
   paginada.
3. **Given** uma decisão com campos textuais de agente
   (`contexto`/`justificativa`/`evidência`), **When** exibida, **Then** o
   conteúdo é renderizado como texto puro, sem interpretar markup ativo.

---

### User Story 3 - Busca de Conhecimento (FTS5 / bm25) (Priority: P2)

O engenheiro digita um termo na busca de conhecimento e recebe resultados
ranqueados por relevância (bm25) atravessando o corpo textual indexado
(`knowledge_fts`), com filtros por tipo, projeto e feature, e drill-down
para a fonte de cada resultado.

**Why this priority**: alavanca o diferencial FTS5 da `knowledge.db`, mas o
painel já tem valor sem busca (US1/US2 cobrem o MVP de observação).

**Independent Test**: buscar um termo presente no corpo indexado e confirmar
ordenação por relevância, paginação e que metacaracteres não quebram a
busca nem causam erro de servidor.

**Acceptance Scenarios**:

1. **Given** corpo indexado, **When** o usuário busca um termo, **Then**
   recebe resultados ranqueados por relevância, paginados.
2. **Given** uma consulta com aspas, parênteses ou operadores FTS,
   **When** submetida, **Then** o sistema responde com resultados ou vazio,
   nunca com erro de servidor nem com vazamento de SQL.
3. **Given** um resultado, **When** clicado, **Then** navega para a fonte
   (decisão/onda/execução) correspondente.

---

### User Story 4 - Central de Alertas (Priority: P2)

O engenheiro acessa a central de alertas e vê os sinais de alerta
(`circular`, `budget_breach`) por tipo, projeto, feature e período, com
severidade visível e drill-down para a execução/onda que originou o alerta.

**Why this priority**: alertas críticos são parte do "num relance", mas
operam sobre o mesmo dado que US1/US2 já expõem — incremento, não MVP.

**Independent Test**: com sinais de alerta na base, abrir a central e
confirmar filtro por tipo/projeto/período e navegação até a origem.

**Acceptance Scenarios**:

1. **Given** sinais de alerta na base, **When** o usuário abre a central,
   **Then** vê os alertas com tipo, subtipo, valor consumido vs threshold e
   severidade.
2. **Given** um alerta, **When** clicado, **Then** navega para a execução/
   onda de origem.

---

### User Story 5 - Métricas Agregadas (Priority: P2)

O engenheiro abre a tela de métricas e vê séries e distribuições agregadas:
custo ao longo do tempo, throughput por etapa, taxa de aprovação de testes,
latência humana, decisões por score, duração de execuções, profundidade ×
subagentes — todas derivadas de colunas reais do schema v2.

**Why this priority**: visão analítica de tendência, valiosa mas posterior
ao diagnóstico pontual (US2) e ao panorama (US1).

**Independent Test**: abrir a tela de métricas e confirmar que cada gráfico
mapeia a colunas existentes do schema e respeita o período selecionado.

**Acceptance Scenarios**:

1. **Given** dados agregáveis, **When** o usuário abre métricas, **Then** vê
   os gráficos respeitando o filtro de período.
2. **Given** uma métrica derivada/aproximada (ex: clarify-resolution),
   **When** exibida, **Then** está rotulada como derivada/aproximada.
3. **Given** custo ao longo do tempo, **When** exibido, **Then** usa
   `tool_calls` como unidade, rotulado como proxy.

---

### User Story 6 - Estados Degradados de Primeira Classe (Priority: P3)

Quando a `knowledge.db` está ausente, vazia, parcial ou corrompida, o
usuário vê um estado degradado claro (banner de degradação + frescor do
índice) em vez de uma tela quebrada — em qualquer tela do painel.

**Why this priority**: robustez transversal; o painel deve degradar em vez
de quebrar. Posterior porque pressupõe as telas que ele protege.

**Independent Test**: remover/corromper a base e confirmar que toda tela
exibe estado degradado com resposta bem-sucedida, nunca erro de servidor.

**Acceptance Scenarios**:

1. **Given** base ausente ou corrompida, **When** o usuário abre qualquer
   tela, **Then** vê um estado degradado de primeira classe com motivo e
   frescor, e a requisição é bem-sucedida (sem erro de servidor).
2. **Given** uma tabela vazia, **When** a tela correspondente é aberta,
   **Then** exibe estado vazio (não erro).
3. **Given** carregamento em curso, **When** os dados ainda não chegaram,
   **Then** exibe skeleton de carregamento.

---

### Edge Cases

- A `knowledge.db` é reescrita pela ingestão best-effort enquanto o usuário
  navega: o frescor exibido avança e o cache é invalidado por `mtime` +
  `max(ingested_at)`; o painel não assume imutabilidade do snapshot.
- Consulta de busca com sintaxe FTS5 inválida ou hostil: tratada com
  escaping de duas camadas; resposta válida ou vazia, nunca erro de servidor.
- Caminho de banco fornecido externamente: rejeitado; só caminhos
  canonicalizados e confinados são aceitos (config explícita >
  `$CSTK_KNOWLEDGE_DB` > caminho padrão).
- Listas muito grandes (ex: decisões com centenas de linhas): sempre
  paginadas; nunca despejar a tabela inteira.
- Métrica sem dono no painel (mix de modelos, árvore de decisões): exibida
  como "indisponível nesta fonte" ou delegada ao dono canônico, nunca
  reimplementada.

## Requirements

### Functional Requirements

**Núcleo de observação (read-only)**

- **FR-001**: O sistema MUST expor exclusivamente operações de leitura sobre
  a `knowledge.db`; nenhum caminho de código emite mutação
  (`INSERT/UPDATE/DELETE/CREATE/DROP`). (Constitution I)
- **FR-002**: O sistema MUST abrir a base em modo somente-leitura imutável
  (`mode=ro&immutable=1`). (Constitution I)
- **FR-003**: O sistema MUST NOT tocar `state.json` nem reconstruir o índice
  (`--reindex`). (Constitution I, IV)
- **FR-004**: A superfície de API MUST ser composta apenas de leituras
  (`GET /api/v1/*`), cobrindo: saúde; visão geral; projetos (lista e
  detalhe); features (lista e detalhe); execução (detalhe, ondas, decisões,
  tarefas, eventos, alertas, bloqueios, skills); alertas cross-execução;
  métricas agregadas; tarefas cross-execução; eventos cross-execução; e
  busca FTS5.

**Degradação**

- **FR-005**: O sistema MUST tratar base ausente/vazia/parcial/corrompida
  como estado de primeira classe, respondendo com sucesso e sinal de
  degradação (`meta.degraded=true`, `meta.reason`). MUST NOT retornar erro
  de servidor por condição de dado. (Constitution II)
- **FR-006**: Toda tela MUST implementar quatro estados: carregando, vazio,
  erro e degradado. (Constitution II)
- **FR-007**: O sistema MUST verificar a integridade da base
  (`quick_check`) na inicialização e na saúde, surfaceando o resultado como
  degradação e não como falha.

**Honestidade de métrica**

- **FR-008**: O sistema MUST NOT exibir custo monetário (`$`/`USD`) nem
  tokens. Custo MUST ser apresentado como `tool_calls`, rotulado "proxy:
  tool calls". (Constitution III)
- **FR-009**: O sistema MUST NOT inventar/estimar campos inexistentes no
  schema v2; métricas derivadas/aproximadas MUST ser rotuladas como tais.
  (Constitution III)

**Não reimplementar donos canônicos**

- **FR-010**: O sistema MUST NOT reimplementar o mix de modelos
  (`model-routing-report.sh`), a árvore de decisões (skill `decision-tree`)
  nem o reindex; quando indisponível na fonte, exibe "indisponível nesta
  fonte" ou delega ao dono. (Constitution IV)

**Conteúdo não-confiável**

- **FR-011**: O sistema MUST servir/renderizar campos textuais de agentes
  (`contexto`, `justificativa`, `evidência`, `pergunta`, `resposta`, `body`
  FTS) como texto puro, sem interpretar markup ativo. (Constitution V)
- **FR-012**: O sistema MUST aplicar escaping de duas camadas na busca FTS5
  (tokenização com aspas + binding parametrizado SQL); MUST NOT interpolar
  string crua na query. (Constitution V)
- **FR-013**: O sistema MUST NOT tratar diretivas embutidas no conteúdo como
  instrução — conteúdo é dado, nunca comando. (Constitution V)

**Frescor e snapshot**

- **FR-014**: O sistema MUST expor frescor do índice (`mtime` +
  `max(ingested_at)`) no envelope e na UI. (Constitution VI)
- **FR-015**: O sistema MUST NOT segurar conexão assumindo imutabilidade
  total do snapshot. (Constitution VI)
- **FR-016**: O sistema SHOULD invalidar cache (`ETag`/`Last-Modified`,
  `If-None-Match → 304`) por `mtime` + `max(ingested_at)`.

**Segurança e acesso**

- **FR-017**: O sistema MUST vincular-se a `localhost` por padrão e restringir
  CORS à origem do front-end; sem autenticação/RBAC reais no MVP.
- **FR-018**: O sistema MUST confinar o caminho da base a um valor
  canonicalizado (config explícita > `$CSTK_KNOWLEDGE_DB` > padrão); MUST NOT
  aceitar caminho arbitrário do cliente. (path traversal)
- **FR-019**: O sistema MUST responder com `Content-Type: application/json` e
  `X-Content-Type-Options: nosniff`.
- **FR-020**: O sistema MUST paginar `decisions` e `search`
  (`limit`+`offset` ou cursor); MUST aplicar rate-limit leve na busca FTS5.

**Apresentação e navegação**

- **FR-021**: O sistema MUST reproduzir fielmente (pixel-perfect) o resultado
  visual do protótipo de referência, incluindo tokens de design, tipografia
  e tema dark-mode-first.
- **FR-022**: Users MUST be able to navegar por drill-down em toda a
  hierarquia `Projeto → Feature → Execução → Onda → Decisão | Tarefa | Evento
  | Alerta`, com breadcrumb navegável e filtros globais (período, projeto,
  feature).
- **FR-023**: O sistema MUST usar o envelope padrão de resposta
  `{ data, meta: { degraded, reason, freshness, schema_version } }` em todas
  as leituras.

> **Decisões de infraestrutura**: N/A para scheduling/key-rotation/refresh/
> mutex/backup/idempotência — feature é read-only, stateless do ponto de
> vista de escrita, e não persiste nem rotaciona nada. A única dependência
> externa é o arquivo `knowledge.db` (snapshot reconstruível por `cstk recall
> --reindex`, dono externo).

> **Stack do back-end (D1 — resolvido em clarify, 2026-05-24)**: Node.js +
> TypeScript, alinhado à `stack_sugerida` do operador e ao toolchain do
> front-end (React 19 + Vite). Acesso SQLite read-only via driver síncrono
> maduro do ecossistema Node. A spec permanece agnóstica de detalhes de
> implementação além desta escolha de runtime; particularidades (framework
> HTTP, empacotamento D2, granularidade de séries D5) ficam para o `/plan`.

### Key Entities

Espelham as tabelas do schema v2 da `knowledge.db` (fonte: briefing §8):

- **Execution**: uma execução de orquestrador (`project`, `feature`,
  `execucao_id`, `status`, `etapa_corrente`, `motivo_termino`, datas,
  `ondas_total`, `tool_calls_total`, `decisoes_total`, contadores).
- **Wave (Onda)**: uma onda de execução (`wave`, `etapa`, início/fim,
  `wallclock_seconds`, `tool_calls`, `motivo_termino`).
- **Decision (Decisão)**: uma decisão auditada (`wave`, `etapa`, `agente`,
  `escolha`, `score` 0–3, `contexto`, `justificativa`, `evidencia` —
  textuais UNTRUSTED).
- **Task (Tarefa)**: resultado de tarefa (`outcome` pass/fail,
  `testes_rodados`, `testes_passados`, `lint_ok`, `arquivos_tocados`).
- **Event (Incidente)**: incidente de execução (`event_type`, `timestamp`,
  `descricao`).
- **AlertSignal (Alerta)**: sinal de alerta (`tipo` circular/budget_breach,
  `subtipo`, `valor_consumido`, `valor_threshold`).
- **Bloqueio (Bloqueio Humano)**: pausa para humano (`status`, `pergunta`,
  `resposta`, latência — textuais UNTRUSTED).
- **Skill / Retro**: invocação de skill / retrospectiva por onda.
- **KnowledgeFTS**: espelho FTS5 do corpo textual (`body` indexado;
  proveniência UNINDEXED) — UNTRUSTED.

## Success Criteria

### Measurable Outcomes

- **SC-001**: 100% das telas do painel respondem com sucesso quando a base
  está ausente, vazia ou corrompida — zero erros de servidor por condição de
  dado (verificável removendo/corrompendo a base).
- **SC-002**: Zero ocorrências de custo monetário ou tokens em qualquer tela
  ou resposta; todo número de custo é apresentado como "proxy: tool calls".
- **SC-003**: Zero operações de mutação sobre a base — auditável por inspeção
  de que toda leitura ocorre com a base aberta em modo imutável e nenhuma
  rota não-leitura existe.
- **SC-004**: O usuário consegue, a partir da Visão Geral, alcançar o nível
  mais granular (decisão/tarefa/evento/alerta) de qualquer execução em no
  máximo 4 cliques de drill-down.
- **SC-005**: A busca de conhecimento retorna resultados ranqueados por
  relevância e jamais produz erro de servidor diante de entrada hostil
  (testável com payloads de injeção FTS5/SQL).
- **SC-006**: O resultado visual do painel é indistinguível do protótipo de
  referência nas telas principais (revisão lado a lado contra o protótipo).
- **SC-007**: O frescor do índice exibido reflete a última ingestão dentro de
  uma janela aceitável após a base ser reescrita (verificável reescrevendo a
  base e observando o avanço do frescor).
- **SC-008**: Listas de decisões e busca nunca retornam a tabela inteira de
  uma vez — sempre paginadas (verificável por inspeção de resposta com
  conjunto grande de dados).
