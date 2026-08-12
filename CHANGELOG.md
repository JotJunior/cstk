# Changelog

Todas as mudanças notáveis deste projeto são documentadas neste arquivo.

O formato é baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/),
e este projeto adere ao [Versionamento Semântico](https://semver.org/lang/pt-BR/).

## [0.27.0] - 2026-08-12

### Adicionado

- **FAQ no menu lateral** (rota `/faq`): 10 perguntas em 6 categorias
  (Instalação, Plugin do Claude Code, Painel, Tokens e custo, MCP e estado,
  Manutenção) com respostas em passo-a-passo — mais fáceis de achar do que
  varrer as tabelas de comandos do Cheat Sheet. Campo de filtro client-side
  (ignora acentos, busca em pergunta + resposta; resultados já abrem
  expandidos) e acordeão acessível por pergunta. Conteúdo estático derivado
  de fontes reais: help do `cstk v7.3.1`, README/CHANGELOG do repo
  JotJunior/cstk e docs oficiais do Claude Code sobre plugins; respostas
  renderizadas pelo `MarkdownView` (renderer seguro do painel).

### Alterado

- **Cheat Sheet sincronizado com o `cstk v7.3.1`** (estava na v6.6.0):
  seção nova do plugin nativo do Claude Code (v7.0.0) com o dedup de hooks
  da v7.1.0 (`--remove-classic`, "plugin vence"); comandos novos `cstk
  setup` (wizard das 4 áreas), `cstk statusline` e `cstk recall
  --list-memories`; flags novas (`update --force/--keep/--prune`,
  `self-update --check`, `list --available`, tipo `suggestion` no recall);
  `initialize-docs` marcada como removida (a v6.6 ainda dizia
  "deprecated"); schema da `knowledge.db` corrigido de v13 para v14; e
  link cruzado para o FAQ novo.

## [0.26.0] - 2026-08-10

### Alterado

- **KPI row da Visão Geral em 4 colunas × 2 linhas**: os 8 cards ficavam
  lado a lado num grid de 8 colunas — em tela comum cada card era estreito
  demais e o rodapé (cobertura da amostra, janela da cota) quebrava em
  várias linhas. Passam a ocupar duas linhas de quatro.
- **Ordem dos cards agrupada por eixo**, não pela ordem em que cada um
  entrou no schema: a primeira linha é consumo (cota do plano, custo,
  tokens de subagentes, tempo de parede) e a segunda é estado do portfólio
  (projetos ativos, em andamento, alertas críticos, test pass rate).
  Nenhum valor, rodapé ou tooltip mudou — só posição e layout.

## [0.25.0] - 2026-08-10

### Corrigido

- **Painel voltava degradado inteiro contra `knowledge.db` v14**: o guard de
  abertura (`DEFAULT_SCHEMA_VERSIONS`) parava na v13, então uma base já
  migrada pelo cstk ≥ 7.2.0 respondia `schema-mismatch` em **todos** os
  endpoints — não só nas features novas. A lista passa a aceitar até a v14.

### Adicionado

- **Breakdown de tokens por fonte e tipo (schema v12, cstk ≥ 5.33.0)**: as 8
  colunas `otel_{main,subagent}_{input,output,cache_read,cache_creation}_tokens`
  estavam no schema desde a v12 mas o painel nunca as lia — daquela migração
  só a tabela `wave_model_usage` tinha sido adotada. Agora aparecem no card de
  custo real (Métricas), nos rollups de projeto e feature e no detalhe da
  onda, com barra de composição por tipo e a fatia de **cache read**.
  A leitura que só elas permitem: uma onda de 8,78M tokens sendo ~95% contexto
  relido é uma onda **longa**, não uma onda cara.
- **Cobertura de amostra separada por fonte**: `main` e `subagent` são coletas
  independentes e divergem materialmente na base real (27 ondas contra 257, de
  1182). Cada lado exibe o próprio denominador — um número único apresentaria
  como medido um lado que nunca foi coletado.
- **Cota do plano (schema v14, `plan_usage`, cstk ≥ 7.2.0)**: nova métrica
  `GET /metrics/plan-usage` e card em Métricas com o percentual consumido das
  janelas de 5h e 7d, pico do recorte, reset e série temporal por janela. KPI
  compacto na Visão Geral mostra a janela mais apertada, dizendo qual é.
  É uma grandeza nova — quota da **conta**, não esforço, dinheiro ou token —
  e por isso não se soma nem se compara com as demais.
- **Estados honestos para as duas fontes novas**: "tabela ausente na base"
  (v < 14) e "captura opt-in não ligada" (`cstk statusline install`) são
  telas distintas, e nenhuma das duas renderiza `0%`.

### Alterado

- **Constituição 1.2.0 → 1.3.0** (emenda autorizada pelo operador em
  2026-08-10): terceira expansão do Princípio III, cobrindo o breakdown por
  fonte (denominadores separados; proibição de usar `otel_total_tokens` como
  denominador dentro de um lado) e a cota do plano (quarta grandeza, escopos
  nunca mesclados, ausência nunca renderizada como `0%`). Corrige também a
  lista de tabelas da knowledge.db no `MUST NOT` de "campos que não existem",
  defasada desde a v12 — faltavam `wave_model_usage`, `loose_usage` e
  `plan_usage`.

## [0.24.0] - 2026-08-07

### Adicionado

- **Filtro de tarefas por onda no detalhe da execução**: ao clicar numa
  onda na timeline, a aba Tarefas passa a ser filtrada pela onda
  selecionada — mesma semântica já aplicada às Decisões — permitindo ver
  lado a lado o que foi decidido e o que foi efetivamente executado
  naquela onda. Os cards de resumo do painel (Tarefas, Pass rate,
  Lint OK, Fails) refletem apenas a onda filtrada, e o empty state
  diferencia "sem tarefas nesta onda" (com dica para limpar o filtro) de
  "sem tarefas registradas". Filtro aplicado no cliente: o endpoint
  devolve todas as tarefas da execução, sem paginação.

## [0.23.1] - 2026-08-07

### Alterado

- **Cheat sheet sincronizado com o cstk v6.6.0** (a tela estava derivada
  da v6.2.0): nova seção "Consumo avulso (`cstk usage`)" — subcomandos
  `usage`/`usage compare`/`usage prune`, hook opt-in
  `cstk hooks install --with-loose-usage`, schema v13 (`loose_usage`) e a
  regra `nao medido`/`null` (nunca `0` fabricado); briefing canônico em
  `docs/briefing.md` (legado só como fallback) e deprecation do
  `initialize-docs` (remoção na v7); notas das 6.3–6.5 que faltavam
  (hooks backend-agnósticos e gotcha de cópia stale — `tool_calls=0` sob
  state.db). O passo a passo do setup COMPLETO ganha o passo
  `cstk install` (catálogo: skills + commands + agents), ausente até
  então — o one-liner `install.sh` instala só o runtime, e sem o
  catálogo os slash commands não existem na sessão.

## [0.23.0] - 2026-08-07

### Adicionado

- **Consumo avulso (`loose_usage`, schema v13 / cstk 6.6.0)**: o painel
  passa a exibir os tokens/custo das sessões interativas comuns do Claude
  Code — capturados fora de qualquer execução 00c pelo hook opt-in
  `cstk hooks install --with-loose-usage` — no novo card "Consumo avulso ·
  fora do pipeline" da tela Métricas: rollup por projeto (com segmentos/
  processos e marcador `*` para segmento ainda em captura), rollup por
  modelo (rótulo bruto do OTel) e comparação **avulso × pipeline** com
  custo blended por Mtok. Novo endpoint `GET /api/v1/metrics/loose-usage`
  (filtros `project`/`period`; sem `feature` — a origem não tem a
  dimensão), DTOs `LooseUsage*` no shared-types e view-model puro
  `loose-usage-select.ts`. Semânticas preservadas da fonte: `NULL` nunca
  vira 0; tabela presente e vazia = "sem medição" (captura é opt-in),
  estado distinto de "fonte não coleta" (base v2-v12, `table-empty`);
  comparação agregada lado a lado por categoria, nunca JOIN linha a linha;
  `blendedCostPerMtok` nulo quando a soma de tokens é 0/`NULL`. Validado
  por roundtrip empírico contra a `knowledge.db` v13 real.

## [0.22.1] - 2026-08-07

### Corrigido

- **Aceita `knowledge.db` schema v13** (`loose-usage-capture`, cstk 6.6.0):
  `'13'` adicionado a `DEFAULT_SCHEMA_VERSIONS`. A migração v13 é aditiva
  (tabela `loose_usage`, consumo avulso fora de execuções 00c) e roda
  automaticamente no primeiro `cstk recall`/ingest após o upgrade — sem esta
  entrada o painel degradava com `schema-mismatch` em bases já migradas. O
  painel ainda não exibe os dados de `loose_usage`; todas as telas seguem
  operando sobre as tabelas existentes. Smoke real atualizado para aceitar
  v12 ou v13.

## [0.22.0] - 2026-08-02

### Adicionado

- **Tela "Cheat Sheet"** (rota `/cheatsheet`, novo item de menu na seção
  *diagnosticar*, ícone `help`): referência rápida dos comandos do CLI
  `cstk` (v6.2.0) — instalação/manutenção (com o gotcha catálogo vs
  runtime), estado transacional 00c (`enable-sqlite`/`migrate`), servidor
  MCP (`install/status/start/stop/gc` + `MCP_MAX_TOOL_CALLS`), pipelines
  autônomas (slash commands), sessões/recall/hooks — mais os dois
  passo-a-passos de setup: **completo** (MCP + state.db) e **básico**
  (Bash + state.json), com o caminho de upgrade entre eles. Conteúdo
  estático derivado do help real do binário, renderizado pelo
  `MarkdownView` (renderer seguro: GFM, sem HTML bruto, allowlist de
  esquemas de URL).

## [0.21.1] - 2026-07-29

### Corrigido

- **"Custo por modelo · detalhe" exibia um texto de 2766 caracteres como se
  fosse um cabeçalho de etapa**: o card agrupa por `waves.stages`, e uma onda
  na base real gravou um resumo narrativo inteiro nessa coluna em vez de um
  token (`execute-task`, `create-tasks`, …). O rótulo agora é validado como
  lista de tokens separados por vírgula (sem espaços, ≤40 chars por token — o
  formato legítimo `execute-task-F3.1,execute-task-F3.2` segue aceito); o que
  não passa aparece como *"etapa não registrada na origem"*, com o valor bruto
  encurtado a 160 caracteres apenas no `title`. O custo da linha continua
  visível: nenhuma etapa é inventada para a onda e nenhum valor medido é
  descartado (Princípio III + "jamais inventar dado"). A causa raiz está na
  escrita do `cstk`, não no painel — aqui trata-se apenas do degrade.

### Alterado

- **"Mix de modelos por etapa" passa a empilhar na horizontal**: com
  `execute-task` valendo 29 contra 2–3 das demais etapas, o formato vertical
  reduzia todas as outras a barras de 1px, e o eixo X ainda truncava o rótulo
  a 8 caracteres (`create-tasks` virava `create-t`) alternando labels
  par/ímpar. Cada etapa agora ocupa uma linha com `rótulo | barra empilhada |
  total`, com o nome inteiro e a ordem canônica do pipeline SDD preservada.
  Novo componente `StackedBarsH` (DOM, pelo mesmo motivo do `BarH`: ellipsis +
  `title`); o `StackedBars` vertical permanece onde a categoria é tempo
  (Incidentes).

## [0.21.0] - 2026-07-28

### Adicionado

- **Custo real por modelo (USD medido)**: novo endpoint
  `GET /api/v1/metrics/model-usage` sobre a tabela `wave_model_usage` (schema
  v12), com agregados por modelo (`byModel`, top-10 + bucket `(outros)`), por
  etapa do pipeline (`byStage`) e cobertura honesta da amostra (nem toda onda
  tem breakdown OTel — os denominadores divergentes são exibidos, não
  escondidos). Na UI: card compacto "Custo por modelo" (top-3) no dashboard
  principal e painel de detalhe por modelo/etapa na página Métricas. Os três
  estados (`measured`/`empty`/`degraded`) nunca colapsam num `$0` enganoso —
  ausência de dado é `—`, não zero. Exibição de valor monetário MEDIDO
  ratificada pela emenda 1.2.0 da constitution (Princípio III); valor
  estimado/convertido segue proibido.
- **Throughput por etapa truncado em top-10 + "Outros"**: a página Métricas
  passa a mostrar as 10 maiores etapas e agrega o restante numa barra
  "Outros" expansível (clique/toque ou Enter/Espaço revela os membros),
  preservando a soma total.

### Corrigido

- **"Mix de modelos por etapa" colapsava todas as etapas em `?`**: o card lia
  `r.etapa` num payload que sempre projetou `stage` (exceção legada da
  migração v7 pt→EN), somando tudo numa única barra sem rótulo. A leitura usa
  o campo real, a lógica foi extraída para módulo puro testável
  (`model-mix-by-stage-select.ts`) e as barras agora seguem a ordem do
  pipeline SDD (etapas fora da constante ao final, por volume), com rótulos
  reais — o contexto de etapa que faltava para o card se justificar ao lado
  do donut de mix total.

### Removido

- **Cards "Custo por feature · proxy" e "Funil do pipeline"** do dashboard
  principal — remoção apenas de renderização: `leaderboard[]` e `funnel[]`
  seguem no payload de `/overview` (Princípio II, sem quebra de contrato).
  `FunnelChart` órfão removido de `charts.tsx`.

## [0.20.0] - 2026-07-28

### Adicionado

- **Aceita `knowledge.db` schema v12** (`otel-model-breakdown`, cstk 5.33.0):
  `DEFAULT_SCHEMA_VERSIONS` passa a incluir `'12'`. O v12 adiciona a tabela
  `wave_model_usage` (grão onda × modelo: `model` como string **bruta** do
  OTel, `cost_usd`, `total_tokens`) e 8 colunas
  `otel_{main,subagent}_{input,output,cache_read,cache_creation}_tokens` em
  `waves`, tornando possível custo por modelo (opus vs sonnet) e cache-hit
  ratio — antes impossíveis, porque o ingest do cstk projetava apenas 5
  escalares e descartava o `by_model` inteiro.

  Sem este bump, uma base já migrada para v12 era rejeitada com
  `schema-mismatch` e ~50 rotas degradavam. Todas as mudanças do v12 são
  aditivas (Princípio II): as telas existentes seguem operando e os recursos
  novos aparecem só quando a tabela/coluna está presente.

  Validado contra uma `knowledge.db` v12 real (916 ondas, 41 linhas em
  `wave_model_usage`).

## [0.19.2] - 2026-07-27

### Corrigido

- **Etapa longa quebrava a linha do tempo de ondas**: a célula `Etapa` renderiza
  `waves.stages` cru, e em casos raros de erro o orquestrador grava ali um
  parágrafo inteiro em vez do nome da etapa (observado: `onda-029` com o texto
  completo da conclusão da task). Numa coluna de grid de 120px o texto quebrava
  em dezenas de linhas, esticando a linha da onda e empurrando o restante da
  tabela para fora da tela. A célula passa a truncar em uma única linha
  (`overflow`/`text-overflow`/`white-space`, com `min-width: 0` por ser item de
  grid) e mantém o valor íntegro no `title` — nada é descartado, só contido.

## [0.19.1] - 2026-07-26

### Corrigido

- **Token exibido `—` ao lado de custo medido**: a célula `Tokens` da linha do
  tempo de ondas (e os equivalentes em Projeto, Feature e Métricas) lia apenas
  `agent_total_tokens` — o schema v10, alimentado pelo hook `agent-usage`. Em
  projeto onde esse hook nunca foi provisionado, a coluna ficava vazia ao lado
  de um custo real medido, porque o custo vem da fonte OTel (v11). Caso
  observado: onda com `otel_total_tokens = 7.228.603` e `otel_cost_usd = 3.14`
  com todas as `agent_*` em `NULL` — duas fontes diferentes na mesma linha,
  uma populada e a outra não.
  Novo `lib/token-source.ts` centraliza a preferência **OTel (v11, loop
  principal + subagentes) > hook de spawn (v10, só spawns observados)**,
  aplicada nos quatro pontos afetados; `Overview` já a fazia e serviu de
  referência. Os estados honestos ficam intactos: ausência continua `—` ou
  `s/ dado`, **nunca 0**, a cobertura acompanha o número e o marcador de
  amostra `*` segue exclusivo da v10, a única amostral. Onde a fonte é OTel o
  rótulo passa a "Tokens · medidos" — ali o número não é só de subagente.

## [0.19.0] - 2026-07-26

### Adicionado

- **Custo real por onda chega à UI (schema v11 da knowledge.db)**: o suporte
  anterior à v11 parava no agregado — `getOtelUsage` somava o custo, a rota
  `/overview` mandava no payload e **nada exibia o valor** (`fmtUsd` e
  `subagentShare` eram código morto em `Overview.tsx`). Agora:
  - `WaveDTO` ganha os 5 campos `otel*` (interface manual + schema Zod), e
    `listWavesByExecution` projeta as colunas — com degradação para `NULL` em
    base v<11, como as `agent_*` da v10;
  - novo `OtelUsageRollup` nos rollups de `/projects`, `/features` e
    `/overview`, com o mapper `mapOtelUsageRollup`;
  - endpoints `GET /metrics/otel-usage` e `GET /metrics/otel-cost-over-time`
    (filtros `project`, `feature`, `period`), e `otelCostSeries` no
    `/overview` — dias sem telemetria são **omitidos**, não viram zero;
  - UI: KPI "Custo · real" na Visão Geral (substitui o proxy de `tool_calls`
    quando há medição — `$` e "proxy" nunca no mesmo card), coluna `Custo` na
    linha do tempo de ondas com breakdown da onda selecionada, painel e KPI em
    Métricas, e rollup em Projeto e Feature.
- Componente `OtelUsage` com os estados honestos da fonte: `fmtUsd` preserva
  ordem de grandeza abaixo de 1 centavo (`$0.0006`, não `$0.00`), ausência de
  telemetria vira `—` (nunca `$0`) e todo total vem com a cobertura
  `N de M ondas medidas`.

### Corrigido

- O tip do KPI de tokens citava `cstk ≥ 5.28.0` para o schema v11; a versão
  que **indexa** o dado na knowledge.db é a 5.30.0 (a 5.28.0 só o grava no
  `state.json`). Uma base ingerida por 5.28.0/5.29.0 fica em v10.

## [0.18.0] - 2026-07-26

### Adicionado

- **Consumo medido de subagentes (schema v10 da knowledge.db)**: o cstk
  5.25.0 (feature `wave-token-metrics`) passou a persistir o uso reportado
  pelo harness em cada spawn, agregado por onda — 9 colunas `agent_*` em
  `waves` (tokens total/input/output/cache read/cache creation, tool uses,
  duração e a contagem de spawns com e sem dado). O painel passa a exibir
  esse número em **quatro lugares**: coluna `Tokens` na linha do tempo de
  ondas (com breakdown da onda selecionada), seção
  "Consumo de subagentes · medido" na tela de Métricas (KPI, série diária,
  ondas mais caras), KPI no Overview e rollup em Projeto e Feature.
- **Endpoints** `GET /metrics/agent-usage`, `GET /metrics/tokens-over-time`
  e `GET /metrics/tokens-by-wave` (filtros `project`, `feature`, `period`).
  Os rollups de `/projects`, `/features` e `/overview` ganham o objeto
  `agentUsage`.
- `WaveDTO` ganha os 9 campos `agent*` e o novo `AgentUsageRollup` (interface
  manual + schema Zod).

### Corrigido

- **Painel voltava degradado (`schema-mismatch`) contra qualquer base
  atualizada pelo cstk ≥ 5.25.0**: `DEFAULT_SCHEMA_VERSIONS` parava em `'9'`
  e a migração v9→v10 é automática no primeiro `cstk recall --ingest`. Agora
  aceita `'10'`.

### Alterado

- **Constituição do projeto emendada para 1.1.0** (Princípio III —
  Honestidade de Métrica). A proibição original de exibir "tokens" estava
  ancorada num fato que deixou de valer ("o harness não expõe consumo de
  tokens"). O princípio foi reancorado, não afrouxado: token medido pode
  ser exibido; continua proibido `$`/USD, estimativa e métrica inventada; e
  passou a ser **obrigatório** exibir a cobertura da amostra
  (`spawns_with_usage / spawns_total`), porque spawns em background não
  reportam uso e um total sem denominador apresentaria parcial como
  completo. O tooltip do Overview que afirmava "o harness não expõe tokens"
  foi reescrito.
- `NULL` das colunas `agent_*` **nunca** vira `0` em nenhuma camada. Os três
  estados da fonte são preservados até a UI: não coletado (`—`), coletado
  sem dado de uso (`s/ dado`) e medido (número, com `*` quando a amostra é
  parcial). Bases v<10 degradam para "não coletado nesta fonte" em vez do
  vazio genérico "sem dados para este período".

## [0.17.0] - 2026-07-24

### Adicionado

- **Briefing e constitution no painel de documentação da feature**: o
  doc-viewer só enxergava `docs/specs/<feature>/`, então os dois artefatos
  que governam todas as features do projeto não tinham como aparecer. A
  listagem agora declara o **escopo** de cada artefato (`project` |
  `feature`), que define a raiz a que `fileName` é relativo — e a que a
  leitura fica confinada. Os caminhos seguem a ordem de descoberta
  declarada pelas próprias skills que geram os arquivos:
  `docs/01-briefing-discovery/briefing.md` com fallback `docs/briefing.md`,
  e `docs/constitution.md` com fallback `constitution.md`; o primeiro
  candidato existente vence e, sem nenhum, a entrada aparece
  `produced:false` no caminho canônico (FR-007 — ausência nunca é erro).
  Briefings datados/alternativos do diretório de discovery entram como
  lista dinâmica, mesmo tratamento de `contracts/` e `checklists/`.
- **Navegação de docs agrupada por escopo** (`Projeto` / `Feature`, com
  `optgroup` no modo estreito). A seleção default passa a preferir a spec
  da própria feature em vez do briefing que abre a lista; sem nada
  produzido na feature, cai no primeiro doc de projeto disponível.

### Alterado

- `FeatureDocDTO` ganha o campo obrigatório `scope` e `FeatureDocStage`
  passa a incluir `briefing` e `constitution` (interface manual + schema
  Zod, dual-def). O confinamento anti-traversal/anti-symlink não afrouxou:
  passou a ser aplicado na raiz **do escopo do artefato** — raiz do projeto
  para briefing/constitution, `docs/specs/<feature>/` para o resto — e
  `fileName` continua saindo do mapa do servidor, nunca do cliente. IDs
  colidentes são desambiguados (um `constitution.md` solto dentro da
  feature vira `feature-constitution`), já que a rota de conteúdo resolve
  por `artifactId`.

## [0.16.1] - 2026-07-22

### Corrigido

- **Watcher não via projetos/features recém-iniciados** (ovo-e-galinha da
  descoberta): o ingest-watcher descobria execuções apenas pela tabela
  `executions` da knowledge.db, mas a linha só nasce na primeira ingestão —
  um `state.json` recém-criado no disco ficava invisível até o próprio
  agente rodar `cstk recall --ingest`. O tick agora também varre o
  filesystem das raízes conhecidas (`CSTK_PROJECT_PATHS` +
  `executions.target_project_path` de qualquer status, validadas
  anti-traversal) pelos dois layouts canônicos
  (`agente-00c-state/state.json` e `feature-00c-state/*/state.json`),
  deduplicado e passando pelo mesmo pipeline (assinatura mtime, in-flight,
  backoff, cap de concorrência).
- **Db vazia/ausente não bloqueia mais a descoberta**: `openDb` degrada com
  `table-empty`/`db-missing` numa knowledge.db recém-criada — o tick
  abortava e o painel novo nunca saía do zero. Como `cstk recall --ingest`
  cria e popula a db (verificado empiricamente, cstk 5.21.0), o tick agora
  prossegue com a descoberta via filesystem nesses dois casos;
  `schema-mismatch`/`db-corrupt` seguem com tick ocioso (Princípio II).
- **Sem tempestade de re-ingestões no boot**: state-dir cuja(s)
  execução(ões) na db são todas terminais é apenas "semeado" na primeira
  vista (assinatura registrada sem subprocesso); uma re-execução da mesma
  feature (mtime do `state.json` muda) volta a disparar normalmente.

## [0.16.0] - 2026-07-17

### Adicionado

- **Breadcrumb hierárquico no detalhe de execução**: o topo agora mostra
  `cstk-panel / projeto / feature / execução` com projeto e feature
  clicáveis. Como a rota `/executions/:id` não carrega projeto/feature na
  URL, os crumbs vêm do DTO da própria execução (mesma queryKey da tela —
  o cache do TanStack Query deduplica, sem fetch extra); enquanto a query
  não resolve, degrada para o caminho genérico (`Execuções / <id>`). Na
  árvore de decisões, o crumb da execução vira link de volta para ela.
- **Volta à feature de dentro da execução**: botão "voltar à feature" no
  header do detalhe de execução (mesmo padrão do "voltar à execução" da
  árvore de decisões) e feature clicável na linha de proveniência
  (padrão `.prov` da FeatureDetail). Ambos ausentes graciosamente quando
  a execução não tem feature associada.

### Corrigido

- **Crumb do projeto no detalhe de feature**: apontava para
  `/features/<projeto>`, rota inexistente (caía na página 404); agora o
  breadcrumb é `cstk-panel / projeto / feature` e o crumb do projeto leva
  a `/projects/<projeto>`.
- **Truncamento do breadcrumb**: com a cadeia mais longa, o excedente era
  pintado por baixo das abas de período; agora cada crumb encolhe com
  ellipsis (o crumb-raiz nunca trunca) e o nome completo fica no tooltip.

### Removido

- **Botão "abrir no recall"** no detalhe de execução — decorativo,
  permanentemente desabilitado e sem função.

## [0.15.1] - 2026-07-17

### Corrigido

- **Watcher de ingestão tolerante a ingestões longas**: o painel ficava
  permanentemente em "Base degradada — watcher-ingestion-failed" porque o
  timeout do subprocesso `cstk recall --ingest` (20s, calibrado sobre um
  state.json de 49KB / ~11.6s) matava ingestões reais de ~52.5s
  (state.json de 122KB, cstk 5.21.0). O default sobe para 90s (~1.7x de
  folga sobre o medido) e passa a ser configurável sem rebuild via
  `CSTK_INGEST_TIMEOUT_MS` (espelha `CSTK_WATCH_INTERVAL_MS`).
- **Guarda de in-flight no watcher**: os ticks (5s) não se serializam e o
  cache de assinatura só é gravado ao fim do subprocesso — ingestões mais
  longas que a cadência disparavam subprocessos `cstk` concorrentes para
  o mesmo state-dir, disputando a mesma knowledge.db. O tick agora pula
  state-dirs com ingestão ainda em voo.

## [0.15.0] - 2026-07-16

### Adicionado

- **Diagramas Mermaid no doc-viewer**: blocos de código `mermaid` dos
  artefatos de documentação (spec/plan/tasks/...) agora renderizam como
  diagrama SVG no card de Documentação, mantendo a postura de segurança
  para conteúdo de agente (UNTRUSTED, Princípio V) em três camadas
  independentes: `securityLevel: 'strict'` (sanitização da própria lib e
  interações de click desabilitadas), `htmlLabels: false` (labels em
  `<text>` SVG puro — o SVG final não carrega `<foreignObject>` com HTML
  embutido) e DOMPurify com profile SVG-only sobre o SVG gerado, injetado
  via `replaceChildren` de `DocumentFragment` — nenhum uso de
  `innerHTML`/`dangerouslySetInnerHTML`. A lib (~2 MB) entra por
  `import()` dinâmico (chunk lazy do Vite, baixado só quando o documento
  contém diagrama); o tema do diagrama acompanha o toggle claro/escuro do
  painel; diagrama inválido degrada para o código-fonte em bloco `<pre>`
  com aviso, sem derrubar o doc-viewer.

## [0.14.1] - 2026-07-15

### Corrigido

- **Tabelas markdown no doc-viewer**: tabelas GFM renderizavam como texto
  corrido com pipes — o `react-markdown` não suporta a extensão de tabelas
  sem o plugin `remark-gfm`. Plugin adicionado no nível do parser
  (não reintroduz HTML bruto: `rehype-sanitize` segue como segunda camada
  e a allowlist de esquemas de URL cobre links dentro de células e os
  autolinks novos do GFM). Strikethrough e task-lists também passam a
  renderizar.
- **Navegação de artefatos responsiva**: as tabs horizontais no topo do
  card de Documentação não comportavam os 12+ artefatos de uma feature.
  Substituídas por um painel vertical à esquerda do conteúdo no desktop
  (item ativo destacado, artefatos ausentes esmaecidos) e um select
  full-width em telas estreitas (≤768px).

## [0.14.0] - 2026-07-15

### Adicionado

- **Watchers de execuções em andamento (status em tempo quase-real)**: o
  server passa a observar o `state.json` das execuções `em_andamento`/
  `aguardando_humano` dos projetos configurados (fs.watch + debounce) e a
  disparar a ingestão canônica `cstk recall --ingest` via subprocesso com
  binário pinado, cap de concorrência e backoff — novas ondas, decisões e
  mudanças de status aparecem no painel pouco depois de acontecerem, sem
  esperar o fechamento da onda pelo orquestrador. Degradação graciosa
  sinalizada em `meta.degraded`/`meta.reason` no
  `GET /executions/:executionId`. O mapeamento projeto→caminho segue a
  cadeia de resolução descrita no item de zero-config abaixo; sem
  resolução, o projeto fica "não observável" e o painel segue
  funcionando como antes.
- **Documentação da feature no painel (doc-viewer)**: novos endpoints
  `GET /features/:project/:feature/docs` (listagem com mapeamento fixo
  etapa-SDD→artefato e `produced:false` para "ainda não produzido" —
  nunca 404) e `GET /features/:project/:feature/docs/:artifact`
  (conteúdo), com leitura confinada à subárvore do projeto
  (realpath + rejeição de symlink + fronteira de path + cap de tamanho).
  No front, a visão da feature ganha o painel "Documentação" com abas por
  artefato e renderização markdown segura (`react-markdown` +
  `rehype-sanitize` + allowlist de esquemas de URL
  http/https/mailto/relativo), acompanhando os artefatos SDD durante a
  execução.
- **Resolução automática do caminho do projeto (zero-config, knowledge.db
  v9)**: com cstk ≥ 5.19 (schema v9), a ingestão persiste o
  `target_project_path` do próprio `state.json` em `executions`, e o
  painel resolve o caminho automaticamente — cadeia
  `CSTK_PROJECT_PATHS` (override do operador, sempre vence) →
  `executions.target_project_path` da execução mais recente (valor
  UNTRUSTED validado: realpath, diretório existente, zonas sensíveis do
  sistema rejeitadas) → degradação graciosa. Watchers e doc-viewer
  passam a funcionar em todos os projetos ingeridos sem nenhuma env; o
  painel aceita o schema v9 na abertura da base.

### Modificado

- **Guard `lint:readonly-check`**: regex refinada para exigir whitespace
  após o verbo SQL, eliminando falso-positivo com strings legítimas como
  `'create-tasks'` sem perder a detecção de mutações SQL reais.

## [0.13.1] - 2026-07-11

### Adicionado

- **Assets verificáveis na release (CI)**: novo workflow `release.yml`,
  disparado no push de tags `v*`, gera `cstk-panel-<versão>.tar.gz` via
  `git archive` (um único diretório de topo, mesma estrutura que o
  `cstk serve` extrai com `--strip-components 1`) e o checksum sibling
  `cstk-panel-<versão>.tar.gz.sha256`, anexando ambos à GitHub Release da
  tag — criando a release se ainda não existir, ou apenas anexando os
  assets (idempotente com o fluxo manual de `gh release create`). Com o
  par publicado, o guard de integridade fail-closed do
  `cstk serve --update` (cstk ≥ 5.18.0) passa a atingir outcome
  `verified`, e o painel atualiza sem `--allow-unverified`.

## [0.13.0] - 2026-07-11

### Modificado

- **Projetos em lista no desktop**: a tela de Projetos troca a grade de
  cartões por uma tabela no mesmo padrão visual das demais listas do
  painel, com colunas de features, concluídas, em andamento, abortadas,
  tool calls, wallclock, decisões, alertas e última atividade — mais
  projetos visíveis por tela e comparação direta entre linhas; o clique
  na linha segue navegando ao detalhe do projeto. Abaixo de 768px (o
  mesmo ponto de quebra do drawer da barra lateral) os cartões originais
  permanecem, mais adequados ao toque e a telas estreitas; a alternância
  é feita por CSS, com as linhas computadas uma única vez e renderizadas
  nas duas variantes.

### Removido

- **Cartão "Todas as features" da tela de Projetos**: o conteúdo era
  idêntico ao da tela Features do menu lateral (mesma tabela e mesmos
  filtros), tornando o cartão redundante. A tela de Projetos passa a
  mostrar apenas o rollup por projeto.

## [0.12.1] - 2026-06-20

### Corrigido

- **Lista de execuções deixa de duplicar chaves de linha**: o `execution_id`
  não é único globalmente na knowledge.db — a mesma feature é registrada em
  projetos distintos (ex.: `personal-do-zero` e `personal-do-zero-dynamic-forms`,
  ambas com `feat-dynamic-forms-...`). A tabela de execuções usava apenas o id
  como chave de linha do React, disparando o aviso "Encountered two children
  with the same key" e arriscando linhas duplicadas ou omitidas no render. A
  chave passou a ser o par canônico `(project, execution_id)`; o painel segue
  read-only e exibe as duas execuções, agora com chaves distintas. Um teste
  trava o contrato.

## [0.12.0] - 2026-06-20

### Adicionado

- **Layout responsivo (mobile/tablet)**: abaixo de 768px a barra lateral
  vira um drawer off-canvas, acionado por um botão de menu no cabeçalho,
  com fundo escurecido (backdrop) e fechamento por clique fora, tecla `Esc`
  ou ao navegar; no desktop o comportamento permanece idêntico. O cabeçalho
  passa a refluir em várias linhas em telas estreitas (cada filtro em sua
  própria linha abaixo de 480px) e a grade de KPIs e demais grades colapsam
  de 6→3→2→1 colunas conforme a largura. Antes havia um único ponto de
  quebra (1200px) e, abaixo de ~700px, a barra lateral fixa consumia a
  viewport, o cabeçalho transbordava e os cartões ficavam cortados. A
  detecção de mobile usa um hook `useMediaQuery`, evitando conflito com a
  preferência de colapso da barra lateral (não aplicada no mobile).

### Corrigido

- **Cabeçalho alinhado aos limites do conteúdo**: o cabeçalho ocupava 100%
  da largura disponível enquanto o conteúdo era restrito por `max-width`,
  deixando busca e filtros desalinhados da grade em telas largas. A largura
  máxima passou a ser um token compartilhado (`--content-max`) aplicado
  tanto ao conteúdo quanto ao cabeçalho, fazendo as bordas coincidirem.

## [0.11.2] - 2026-06-06

### Corrigido

- **Clicar num resultado da Busca de Conhecimento abre a execução certa**:
  o resultado navegava para `/executions/{source_id}` usando o id da decisão
  (ex.: `dec-024`) como se fosse um `execution_id`, e a tela de detalhe
  respondia "Execucao nao encontrada". A tabela `knowledge_fts` não guarda
  `execution_id` — apenas `source_id` —, então o backend passa a resolver a
  execução de origem pela chave única `(project, feature, wave, source_id)`
  na tabela-fonte de cada tipo (`decisions`/`blocks`/`skills`/`suggestions`)
  e a expor um campo `executionId` no resultado da busca. O frontend navega
  por esse `executionId` (preservando o filtro de onda); resultados de tipos
  sem vínculo de execução (ex.: `memory`) deixam de ser clicáveis. Um teste
  de rota trava o contrato, exigindo que o `executionId` resolvido exista de
  fato em `/executions/:id`.

## [0.11.1] - 2026-06-06

### Corrigido

- **Busca de Conhecimento volta a retornar resultados**: a rota `GET /search`
  montava o objeto `pagination` sem o campo `hasMore`, enquanto o schema Zod
  do front (`PaginationMetaSchema`) o exige como booleano obrigatório. A
  validação falhava no cliente, o TanStack Query descartava a resposta e a
  busca nunca exibia resultados — mesmo quando havia ocorrências no banco —
  acompanhada do erro `invalid_type` em `data.pagination.hasMore`. O campo
  passa a ser calculado como `offset + results.length < total` (mesmo padrão
  de `/executions`, `/alerts` e `/memories`) e `false` no caminho degradado.
  O teste de rota agora trava o contrato, exigindo `pagination.hasMore`
  booleano no envelope.

## [0.11.0] - 2026-06-05

### Adicionado

- **Proveniência de sessão de worktree (schema v8)**: as execuções e ondas
  que rodaram dentro de uma sessão de worktree do cstk (`cstk session start`)
  passam a exibir a sessão de origem — um selo na lista de execuções e um chip
  no cabeçalho do detalhe, mostrados apenas quando a execução tem sessão. A
  coluna `session` (adicionada pelo cstk 5.11, feature `recall-worktree-identity`)
  é lida ponta a ponta (queries, DTOs, schemas Zod e mappers), degradando para
  vazio em bases anteriores ao v8.

### Corrigido

- **Schema v8 da knowledge.db deixa de ser rejeitado**: o painel aceitava
  apenas até o schema v7, então recusava abrir uma `knowledge.db` no schema v8
  com `schema-mismatch` (tela degradada). As versões de schema aceitas por
  padrão passam a incluir o `'8'`. Além disso, havia um segundo conjunto de
  versões aceitas, desatualizado (parado em `['2','3','4']`), usado como
  fallback em chamadas diretas/de teste de abertura do banco; ele agora reusa
  a mesma fonte de verdade da configuração, eliminando o risco de divergência
  entre os dois padrões em releases futuras.

## [0.10.1] - 2026-06-05

### Corrigido

- **Métricas: cards de duração e profundidade voltam a renderizar**: os
  cards "Duração das execuções" e "Profundidade de subagentes" ficavam em
  branco porque o frontend ainda lia as chaves em português (`duracaoSegundos`,
  `profundidadeMax`, `subagentesSpawned`) enquanto o backend já serializa as
  colunas canonizadas em inglês do schema v7 (`durationSeconds`, `maxDepth`,
  `subagentsSpawned`). Com a chave inexistente, a agregação devolvia vazio e
  o conteúdo nem chegava ao estado "Sem dados". As chaves lidas foram
  alinhadas ao payload do backend.
- **Versão no cabeçalho deixa de ser hardcoded**: a tag do menu lateral
  estava fixada em `v3.19`, divergindo da versão real. Passa a ser injetada
  a partir do `package.json` em build/dev (`__APP_VERSION__` via `define` do
  Vite), acompanhando automaticamente cada release.

## [0.10.0] - 2026-06-04

### Adicionado

- **Auto-refresh periódico do conteúdo (10s)**: as telas do painel passam a
  se atualizar sozinhas a cada 10 segundos, sem intervenção do operador.
  Em vez de um reload completo do navegador (que pisca, reseta o scroll e
  re-baixa o bundle/reinicia o router), o `queryClient` ganhou
  `refetchInterval` global (`AUTO_REFRESH_MS = 10_000`): todas as queries
  ativas re-buscam no intervalo e o React Query reconcilia apenas o que
  mudou. Como é um único ponto nos `defaultOptions`, vale para todas as
  telas (Visão Geral, Execuções, Detalhe, Métricas, etc.). O `staleTime`
  de 60s segue governando refetches por navegação/montagem — o intervalo
  é independente. `refetchIntervalInBackground: false` pausa o polling
  quando a aba está oculta, evitando carga inútil sobre o SQLite read-only.

## [0.9.2] - 2026-05-31

### Corrigido

- **Cabeçalho da execução — card "Ondas" defasado**: o card `ONDAS` lia
  `exec.wavesTotal` (coluna denormalizada `executions.waves_total`), um
  contador que o orquestrador agente-00c nem sempre incrementa — ondas em
  modelos sonnet/haiku pulam o fechamento de onda. Resultado: o cabeçalho
  mostrava `18` enquanto a "Linha do tempo de ondas" e a aba — ambas baseadas
  no `COUNT` real das linhas da tabela `waves` — mostravam `40`. Agora o card
  deriva de `waves.length` (mesma fonte da timeline), com fallback para
  `exec.wavesTotal` enquanto a query de ondas ainda não resolveu e `—` sem
  dados. Cabeçalho e timeline passam a bater; o painel deixa de propagar o
  defeito de bookkeeping da origem.

## [0.9.1] - 2026-05-30

### Corrigido

- **Árvore de decisões — escolha com namespace duplicava a opção**: quando a
  `escolha` vinha com prefixo de namespace (ex.: `model:sonnet`) e a lista de
  opções já continha o token sem prefixo (`["haiku","sonnet","opus","manter-atual"]`),
  o `deriveOptions` casava por igualdade crua, não encontrava `model:sonnet` entre
  as opções e **anexava uma 5ª opção fantasma** (`model:sonnet`, marcada como
  escolhida) — deixando `sonnet` aparecendo duas vezes na árvore. Agora
  `deriveOptions` reusa o `chosenOptionIndex` (mesmo matcher tolerante a
  caixa/espaço, prefixo de namespace e elaborações já usado no painel de
  detalhe): `model:sonnet` casa com a opção `sonnet`, nada é anexado e a opção
  real é destacada. Fecha o drift entre os dois caminhos de render.

## [0.9.0] - 2026-05-30

### Adicionado

- **Filtro de projeto no dashboard (Visão Geral)**: o seletor de projeto da
  topbar agora é um **filtro global** — selecionar um projeto escopa todas as
  métricas da Visão Geral (KPIs, execuções em andamento, alertas, funil, mix de
  modelos, atividade recente, leaderboard de custo) ao projeto escolhido. Antes
  o seletor **navegava** para a página do projeto.
- Endpoint `GET /overview` aceita o parâmetro opcional **`?project=<nome>`**
  (aditivo/retrocompatível): todas as agregações passam a filtrar por projeto
  via parâmetro nomeado `@project` (guarda `@project IS NULL OR project = @project`).

### Corrigido

- Card **"Execuções em andamento"** lia 3 campos pt-BR remanescentes que o
  servidor já emitia em EN (`wallclockSegundos`→`wallclockTotalSeconds`,
  `ondasTotal`→`wavesTotal`, `iniciadaEm`→`startedAt`) — apareciam como `—`.

## [0.8.2] - 2026-05-30

### Corrigido

- **Árvore de decisões — painel de detalhe fixo (sticky)**: o painel lateral que
  abre ao clicar num nó era clipado pelo ancestral `.card { overflow: hidden }` e
  rolava junto com a página; clicar num nó no fim da árvore exigia rolar de volta
  ao topo para ler o conteúdo. Agora o painel permanece **fixo logo abaixo da
  topbar** (`top: 60px`) enquanto a árvore rola, mantendo o detalhe sempre
  visível. Fix: `overflow: visible` no card do mapa (o SVG já trata o próprio
  scroll horizontal) + ajuste do `top` do sticky para limpar a topbar (52px).
  Verificado via Playwright contra a `knowledge.db` v7 real (árvore de 215
  decisões, scroll a ~20,6k px → painel fixo e visível).

## [0.8.1] - 2026-05-30

Patch de qualidade pós-0.8.0.

### Corrigido

- **Aba Tarefas da execução** (`/executions/:id?tab=tasks`): tarefas com status de
  lint **não registrado** (`lint_ok = null`) eram exibidas como **"✕ falhou"**,
  sugerindo falha de lint inexistente. Agora renderizam **"—"** (igual à tela
  global *Tarefas*). O *mapper* já preservava o `null`; só o componente
  `ExecutionDetail` não tratava o caso. Nenhuma tarefa de fato falhou lint.
- **`npm run lint`** voltou a passar (`exit 0`): removida diretiva
  `eslint-disable` morta para a regra `react-hooks/exhaustive-deps` (não
  configurada), que fazia o eslint sair com 1 erro ("rule not found").

### Testes / Infra

- Zerados os 10 *warnings* de `@typescript-eslint/no-unused-vars`: imports/vars
  mortos removidos e `varsIgnorePattern: '^_'` adicionado ao config (par do
  `argsIgnorePattern` já existente). `npm run lint` = 0 problemas.

## [0.8.0] - 2026-05-30

Adaptação ao **schema v7 (EN canônico)** da `knowledge.db` do cstk. O cstk
normalizou colunas e funções que misturavam português e inglês para o inglês
canônico (`execucao_id → execution_id`, `motivo_termino → termination_reason`,
`etapa_corrente → current_stage`, tabela `bloqueios → blocks`, …). O painel —
consumidor primário da `knowledge.db` — foi migrado de ponta a ponta para os
nomes canônicos, mantendo retrocompatibilidade com bases **v6**.

> Verificado por roundtrip empírico real contra `~/.claude/cstk/knowledge.db`
> v7: `/api/v1/{overview,features,events,tasks,alerts}` retornam zero chaves
> pt-BR. `tsc` do monorepo = 0 erros; suíte `vitest` completa = 328/328.

### Modificado

- **BREAKING (contrato de resposta da API)**: todos os campos dos DTOs e do
  payload renomeados pt-BR → EN canônico — `executionId`, `terminationReason`,
  `currentStage`, `startedAt`/`finishedAt`, `title`, `testsRun`/`testsPassed`,
  `type`/`subtype`, `consumedValue`/`thresholdValue`, `description`, `stage`,
  `choice`, `options`, `rationale`, `model`, `totalWaves`/`totalBlocks`.
- Camadas migradas: `shared-types` (DTOs + schemas Zod) → server (Row
  interfaces, SQL, guards `hasColumn`/`hasTable`) → mappers → rotas →
  `apps/web` (hooks + componentes/telas React).
- Tabela `bloqueios` renomeada para `blocks` (queries, mapper, guard `hasTable`).
- `config`: schema **v7** adicionado às versões aceitas por padrão.

### Adicionado

- Retrocompatibilidade com bases **v6**: colunas renomeadas degradam
  graciosamente via `hasColumn` (projeta `NULL` em vez de quebrar) e tabelas
  ausentes via `hasTable`.

### Corrigido

- Telas que liam campos pt-BR enquanto a API já emitia EN (renderizavam
  `—`/`undefined`): **Incidentes**, **Tarefas**, **Visão Geral**
  (alertas/atividade/em-andamento/leaderboard) e **Métricas** (latência).
- Filtro de **Alertas** por tipo: parâmetro de query `tipo` → `type` (alinhado
  ao que o servidor lê).

### Testes / Infra

- Cenário de **roundtrip real** contra a `knowledge.db` v7 (não-mock) e testes
  de back-compat v6 (`blocks-backcompat`, degradação `hasColumn`).
- Fixtures de teste alinhadas ao shape EN real do payload.

## [0.7.1] - 2026-05-29

### Corrigido

#### Árvore de decisões — layout, página e container
- **Árvore real com galhos** (antes era uma cadeia linear): cada decisão é um nó
  arredondado (ponto de decisão) que ramifica para suas **opções consideradas**
  (retângulos). A **opção escolhida** é destacada (✓ + borda de acento) e dela
  parte o galho que desce para a próxima decisão, terminando num nó "Fim".
- **Página própria**: o botão "árvore de decisões" agora abre uma página dedicada
  (`/executions/:id/decision-map`) em vez de substituir a tabela de decisões na
  aba. A aba **Decisões** volta a sempre exibir a tabela.
- **Ocupa o container de conteúdo**: a árvore não fica mais presa num box de
  altura fixa (64vh) com scrollbars internas — cresce com a árvore e a própria
  página rola verticalmente. O painel lateral de detalhe acompanha a rolagem
  (sticky). Mantidos: read-only, conteúdo UNTRUSTED via TextRaw, navegação por
  teclado.

## [0.7.0] - 2026-05-29

### Adicionado

#### Mapa de decisões (árvore de decisões) na execução
- O botão **"árvore de decisões"** no detalhe da execução agora está **funcional**:
  alterna entre a tabela de decisões e um **mapa visual** em SVG, montado
  programaticamente a partir das decisões já carregadas — sem depender de skill
  externa nem de nova fonte de dados. Cada **nó** representa uma decisão, exibe a
  **opção escolhida** destacada e conecta-se ao próximo nó pela sequência da
  cadeia de decisões. Ao **clicar num nó**, abre-se um **painel lateral à direita**
  com os detalhes completos da decisão (todos os campos textuais).
- **100% read-only**: nenhum endpoint novo no back-end (consome os dados já
  disponíveis em memória, via a API existente). O painel detalhe abre sem request
  adicional. Verificado por diff do servidor (SC-007) e pelo gate
  `lint:readonly-check`.
- **Segurança de conteúdo (UNTRUSTED):** todo campo textual de decisão é
  renderizado como **texto literal** via `TextRaw` (tags HTML, scripts e
  diretivas de agente não são interpretados) — coberto por testes com payloads
  adversariais (XSS, SQL injection, HTML).
- **Acessível por teclado:** navegação entre nós por setas/Tab, abrir com
  Enter/Espaço, fechar painel/mapa com Escape, com retorno de foco e
  `aria-label`/`aria-pressed` apropriados. `aria-label` tem fallback para
  decisões sem escolha registrada.
- **Estados robustos:** o mapa trata explicitamente os estados fechado, vazio,
  carregando, erro e degradado, e respeita o filtro de onda ativo na tela. O
  estado de visibilidade do mapa é resetado ao trocar de aba ou de execução.

#### Frontend (`@cstk-panel/web`)
- Novo motor de layout puro `lib/decision-map-layout.ts` (determinístico,
  `computeLayout` < 10ms para 100 decisões) e componentes `DecisionMapPanel`,
  `DecisionMapSvg`, `DecisionMapNode` e `DecisionDetailPane`. Integração no
  `ExecutionDetail` (botão habilitado, toggle, reset por aba/execução).

## [0.6.0] - 2026-05-28

### Adicionado

#### Tema claro + alternância de tema
- Novo **tema claro** além do tema escuro existente, alternável pelo botão de
  sol/lua no rodapé da sidebar. A preferência persiste em `localStorage`
  (`cstk-theme`) e é aplicada **antes do primeiro paint** por um script inline
  anti-FOUC no `index.html` (sem flash do tema na carga). Sem preferência salva,
  cai em `prefers-color-scheme` (`try/catch` → fallback `dark` se `localStorage`
  estiver bloqueado).
- Paleta de superfícies, bordas e texto dedicada ao tema claro. As cores
  semânticas (`success`/`warning`/`critical`/`info`/`inprogress`/`score-*`) e o
  dourado de marca (`accent`) são recalibrados sob `[data-theme="light"]` para
  atender **contraste WCAG AA** sobre fundos claros (auditoria: 0 falhas AA nas
  10 telas). O tema escuro permanece inalterado (overrides escopados).

#### Sidebar retrátil
- A sidebar agora **recolhe para um modo fino (52px)** exibindo apenas os ícones,
  com transição suave. O estado persiste em `localStorage`
  (`cstk-sidebar-collapsed`). No modo recolhido: cada item exibe **tooltip** (CSS
  puro) no hover, o indicador âmbar do item ativo continua visível, e o rodapé
  reduz ao botão de tema. A área de conteúdo se expande automaticamente via
  `:has()` (sem prop-drilling).
- Botão recolher/expandir acessível — `aria-label`/`aria-expanded` dinâmicos e
  ativação por teclado (Enter/Space) com retorno de foco.

### Corrigido
- **Sidebar — ativação por teclado:** o botão de recolher (`<button>` nativo)
  tinha um `onKeyDown` redundante que fazia Enter/Space dispararem o toggle duas
  vezes (cancelando-se). Handler removido; teclado volta a funcionar (WCAG 2.1.1).
- **Métricas — card "Decisões por score":** decisões com `score` nulo (linha do
  `GROUP BY score` com `score=null`) colidiam a `key` do React com o score 0 e
  eram rotuladas erroneamente como "0". O bucket sem-score agora usa key estável,
  exibe "—" e cor neutra.

## [0.5.0] - 2026-05-28

### Adicionado

#### Opções consideradas nas decisões (schema v6)
- A aba **Decisões** do detalhe da execução agora exibe, na linha expandida, as
  **opções consideradas** antes da escolha — uma lista de chips em que a opção
  escolhida aparece destacada (cor de acento + ✓). Espelha a coluna
  `decisions.opcoes` introduzida no **schema v6** da `knowledge.db`
  (JSON array cru de `state.json.decisoes[].opcoes_consideradas`). Antes só era
  possível ver a escolha e a justificativa; agora dá para auditar o leque de
  alternativas que a IA avaliou. **Read-only** — a fonte canônica é o `state.json`.

#### Backend (`@cstk-panel/server`)
- `config`/`open` passam a aceitar `schema_version='6'` (mantendo v2..v5). O
  default de `CSTK_SCHEMA_VERSIONS` agora é `2,3,4,5,6`.
- `db/queries/decisions` projeta `opcoes` de forma tolerante a schema
  (Princípio II): bases v<6 sem a coluna **degradam para `opcoes=null`** via
  `hasColumn` (`NULL as opcoes`), sem quebrar o `SELECT`. O valor é estruturado
  (JSON cru, sem scrub) e repassado intacto pelo mapper. Continua só `SELECT`
  (passa no `lint:readonly-check`).

#### Tipos compartilhados (`@cstk-panel/shared-types`)
- `DecisionDTO`/`DecisionDTOSchema` ganham `opcoes: string | null`.

#### Frontend (`@cstk-panel/web`)
- Novo helper `lib/decision-options` (`decisionOptions` reaproveita o parser
  defensivo de `stack-display`; `chosenOptionIndex` faz match best-effort da
  escolha contra as opções — exato, prefixo de namespace como `model:sonnet`, ou
  elaboração por prefixo com fronteira de token — destacando **no máximo uma**
  opção, para não marcar a alternativa errada). Conteúdo renderizado via
  `textContent` (nunca `innerHTML`).

## [0.4.0] - 2026-05-28

### Adicionado

#### Aba "Sugestões" no detalhe da execução (schema v5)
- Nova aba **Sugestões** no detalhe da execução (ao lado de Decisões, Tarefas,
  Eventos, Alertas e Bloqueios) que exibe a tabela `suggestions` introduzida no
  **schema v5** da `knowledge.db` (feature `recall-suggestions` do cstk):
  espelho de `state.json.sugestoes[]` — as melhorias que a IA propõe a alguma
  skill durante a orquestração (`diagnóstico`, `proposta`, `referencias`,
  `severidade` ∈ `informativa|aviso|impeditiva`, `skill_afetada`,
  `issue_aberta`). Escopo por execução; chave natural `(execucao_id, source_id)`.
  **Read-only** — o painel apenas exibe; a fonte canônica é o `state.json`.

#### Backend (`@cstk-panel/server`)
- `config`/`open` passam a aceitar `schema_version='5'` (mantendo v2/v3/v4). O
  default de `CSTK_SCHEMA_VERSIONS` agora é `2,3,4,5`.
- Novo `GET /executions/:execucaoId/suggestions` (`db/queries/suggestions` +
  `mappers/suggestion`): apenas `SELECT` (passa no `lint:readonly-check`).
  Tolerante a schema (Princípio II) — bases v<5 sem a tabela `suggestions`
  **degradam para lista vazia** via `hasTable`, em vez de quebrar (`degraded=false`).
  O mapper divide `referencias` (CSV) em array, coage `severidade` desconhecida
  para `null` e normaliza `''`→`null`. `diagnóstico`/`proposta`/`referencias`
  viajam crus (UNTRUSTED — defesa de XSS é do front-end).

#### Tipos compartilhados (`@cstk-panel/shared-types`)
- `SuggestionDTO` + `SuggestionDTOSchema` (Zod): `severidade` como enum
  `informativa|aviso|impeditiva` (nullable); `diagnóstico`/`proposta`/
  `referencias` marcados `@untrusted`; `referencias` como `string[]`.

#### Front-end (`@cstk-panel/web`)
- `useSuggestions(execucaoId)` (TanStack Query) + `SuggestionListSchema`.
- `SuggestionsPanel`: cartões com badge de severidade (cor por nível), skill
  afetada, diagnóstico/proposta e chips de referências. Todo campo livre é
  renderizado via `TextRaw` (textContent — Princípio V, nunca `innerHTML`).
  Estado vazio explica também o caso de base em schema < v5.

#### Testes
- `apps/server/test/lib/suggestions.test.ts`: base v5 mínima (listagem em ordem
  cronológica, split de `referencias`, severidade conhecida, `issue_aberta`,
  conteúdo UNTRUSTED cru) + base v3 sem a tabela (degradação para `[]` sem
  `degraded`).

## [0.3.1] - 2026-05-27

### Corrigido

#### Front-end (`@cstk-panel/web`)
- **Stack sugerida renderizada como fragmentos quebrados** nas telas de execução
  e de feature. O agente-00c grava `executions.stack_sugerida` como **JSON** —
  ora array de strings (`["react 19","vite","nodejs"]`), ora objeto chave/valor
  (`{"language":"TypeScript 5.4",…}`) — mas `ExecutionDetail` e `FeatureDetail`
  faziam `split(',')`, tratando-o como CSV. Um objeto JSON estilhaçava em chips
  inúteis (`{ "language": …`, `"runtime": …`, … `… }`) e arrays carregavam `[`,
  `"` e `]` literais.
- Novo helper **defensivo** `stackDisplayItems` (`lib/stack-display`): array →
  um chip por item; objeto → chips `chave: valor`; _fallback_ para CSV no
  formato legado; JSON malformado não lança. O painel segue **read-only** — a
  normalização ocorre apenas na exibição (mesmo princípio de `memory-display`),
  sem reescrever a base. Inclui 8 testes unitários.

## [0.3.0] - 2026-05-27

### Adicionado

#### Tela "Memórias" (auto-memórias do Claude Code, schema v4)
- Nova tela **Memórias** que exibe a tabela `memories` introduzida no **schema
  v4** da `knowledge.db` (feature `recall-memory-mirror` do cstk/claude-ai-tips):
  espelho dos arquivos `.md` de auto-memória que o harness persiste por projeto.
  **Read-only e best-effort** — o painel apenas exibe; a fonte canônica são os
  `.md` no disco. Filtro por projeto (server-side) ou exibição de todas, além de
  filtro por tipo e busca textual (client-side). O corpo do `.md` é expansível,
  renderizado via `children` do React (textContent — Princípio V, nunca
  `innerHTML`).

#### Backend (`@cstk-panel/server`)
- `config`/`open` passam a aceitar `schema_version='4'` (mantendo v2/v3). O
  default de `CSTK_SCHEMA_VERSIONS` agora é `2,3,4`.
- Novo `hasTable()` (cacheado por conexão) em `db/columns`: bases v2/v3 sem a
  tabela `memories` **degradam para lista vazia** em vez de quebrar (Princípio
  II) — ausência da feature não é defeito da base, então `degraded=false`.
- Novo `GET /memories?project=` (`db/queries/memories` + `routes/memories`):
  apenas `SELECT` (passa no `lint:readonly-check`). Retorna as memórias
  paginadas, a **lista completa de projetos** para o seletor (independente do
  filtro corrente) e metadados de paginação. `description`/`body` viajam crus
  (UNTRUSTED — defesa de XSS é do front-end).
- `GET /health` passa a contar a tabela `memories`.

#### Tipos compartilhados (`@cstk-panel/shared-types`)
- `MemoryDTO` + `MemoryDTOSchema` (Zod): `type` como enum
  `index|feedback|project|reference|user`; `description`/`body` marcados
  `@untrusted`.

#### Front-end (`@cstk-panel/web`)
- `useMemories(project)` (TanStack Query) + `MemoriesPageSchema`.
- `memory-display`: derivação **defensiva** do rótulo de descrição. O produtor
  define `description` como a 1ª linha não-vazia do `.md`; como os `.md` começam
  com frontmatter YAML, isso captura o delimitador `---` na maioria dos casos
  (~86% da base real observada). No display (sem reescrever o índice) caímos para
  o campo `description:` do frontmatter, depois 1ª linha de prosa, depois slug
  humanizado.
- Item **Memórias** na Sidebar + rota `/memories`; a tela **Fonte de dados**
  lista a tabela `memories`. O rodapé da Sidebar e o Source passam a refletir o
  `schema_version` **real** (antes fixo em "v2").

### Testes / Infra
- Rota `/memories` com base v4 real construída em tmpdir (listagem, filtro por
  projeto, `projects` completo, `body` UNTRUSTED cru, projeto inexistente) +
  degradação graciosa em base v3 (sem a tabela). Unit de `memory-display`
  cobrindo o caso `description='---'` e os fallbacks. Suíte: **218 testes**.

## [0.2.2] - 2026-05-27

### Corrigido

#### Front-end (`@cstk-panel/web`)
- A visão da execução (`ExecutionDetail`) exibia o pipeline com **todas as
  etapas apagadas** para execuções concluídas. Execuções terminais gravam
  `etapa_corrente='concluida'` — marcador fora de `SDD_STAGES` (`idx=-1`) — e o
  modo rotulado do `PipelineProgress` acendia por `i < idx`, deixando tudo
  cinza. Mesmo defeito já corrigido na listagem (modo compacto), agora
  replicado na visão de detalhe.
- A classificação das etapas foi extraída para `stageStates()` (função pura,
  fonte única consumida pelos dois modos de render): a decisão acende pelo
  **status** — já normalizado no servidor (`concluido`→`concluida`) — e não
  pelo índice da etapa. Concluída acende todas; abortada marca da etapa
  corrente em diante.
- Adicionado o estilo `.pipeline-labeled .stage.aborted` (a variante rotulada
  não possuía, ao contrário da compacta), para paridade de renderização.

### Testes / Infra
- Novo teste de `stageStates` cobrindo `concluida`/`abortada` com `idx=-1`,
  `em_andamento`, `aguardando_humano` e `null`.
- Registrado o alias `@` na config Vitest raiz para que a suíte de componentes
  resolva `@/lib/...` (antes só existia no `vite.config` do web).

## [0.2.1] - 2026-05-27

### Corrigido

#### Backend (`@cstk-panel/server`)
- O front-end quebrava por inteiro (`invalid_enum_value` na validação Zod) quando
  a `knowledge.db` continha um status fora do contrato — ex.: `concluido` em vez
  de `concluida`. Como o `status` é parcialmente escrito por um LLM
  (orquestrador), variantes assim podem ocorrer. As rotas de _rollup_
  (features/projects/overview) emitiam `latestStatus` **cru**, derrubando a lista
  inteira (violando o Invariante II — _degradação nunca quebra_).
- Novo normalizador `normalizeStatus` (fonte única) no limite de leitura:
  remapeia _aliases_ conhecidos (`concluido`→`concluida`, `abortado`→`abortada`)
  e degrada qualquer valor desconhecido para `null` — o servidor nunca mais
  emite um enum inválido. `mapExecution` passou a reutilizá-lo (sem duplicação).
  O filtro de `GET /features?status=` também normaliza, de modo que filtrar por
  `concluida` captura linhas cujo valor cru é uma variante conhecida.

## [0.2.0] - 2026-05-27

### Adicionado

#### Backend (`@cstk-panel/server`)
- `npm run start` agora sobe **API + front-end** num único processo e porta: o
  servidor Fastify serve o SPA buildado (`apps/web/dist`) via `@fastify/static`,
  além dos endpoints `GET /api/v1`. Antes o `start` subia apenas a API e a raiz
  devolvia o envelope JSON 404 — por isso o `cstk serve` precisava recorrer ao
  `npm run dev` (Vite + proxy em duas portas). Diretório do front-end
  configurável via `CSTK_WEB_DIR` (default: `apps/web/dist`).

### Modificado

#### Backend (`@cstk-panel/server`)
- O header `Content-Type: application/json` passou a ser **escopado às rotas
  `/api/v1`**. O hook global de resposta mantém apenas os headers de segurança
  (`X-Content-Type-Options`, `X-Frame-Options`, `Cache-Control`), evitando
  corromper o `Content-Type` de HTML/CSS/JS servidos estaticamente.
- `notFoundHandler`: rotas `/api/*` continuam retornando 404 JSON estruturado;
  demais paths caem em _fallback_ SPA (`index.html`) quando o front-end está
  habilitado, para o `HashRouter` resolver a rota no cliente.
- Degradação graciosa (Invariante II): se o build do web estiver ausente, o
  servidor sobe **apenas a API** e registra um aviso — nunca falha o boot.

## [0.1.2] - 2026-05-27

### Modificado

#### Tooling e dependências
- Migração do ESLint 8 → 9 com _flat config_ (`eslint.config.mjs`, substituindo
  `.eslintrc.cjs`), trocando `@typescript-eslint/{eslint-plugin,parser}` v7 pelo
  pacote unificado `typescript-eslint` v8. As regras constitucionais permanecem
  idênticas (proibição de `innerHTML`/`dangerouslySetInnerHTML`, `no-unused-vars`,
  `no-explicit-any`).
- Removida a flag `--ext .ts,.tsx` dos scripts de _lint_ (não suportada em _flat
  config_; o casamento de arquivos passa a ser definido na própria config).
- Eliminados **6 dos 7** _warnings_ de dependência depreciada na instalação
  (`inflight`, `glob@7`, `rimraf@3`, `@humanwhocodes/config-array`,
  `@humanwhocodes/object-schema`, `eslint@8`), todos provenientes da cadeia do
  ESLint 8. O _warning_ remanescente (`prebuild-install`) vem de `better-sqlite3`
  e não tem correção por versão — persiste até no _release_ mais recente da lib.

### Removido

#### Frontend (`@cstk-panel/web`)
- Diretiva `eslint-disable` obsoleta em `api.ts` (`no-unsafe-return` nunca esteve
  ativa; o ESLint 9 passou a sinalizá-la).

## [0.1.1] - 2026-05-27

### Corrigido

#### Frontend (`@cstk-panel/web`)
- Barras do _pipeline_ ficavam totalmente cinzas para execuções concluídas: o
  orquestrador grava `etapa_corrente='concluida'` (marcador terminal, fora de
  `SDD_STAGES`), e os renderizadores _inline_ preenchiam segmentos apenas com
  `i <= idx` — com `idx=-1` nenhuma barra era pintada.
- Corrigidas `keys` de React no `DecisionsPanel` (uso de `Fragment` com `key`).

### Modificado

#### Frontend (`@cstk-panel/web`)
- Renderização do _pipeline_ consolidada no componente compartilhado
  `PipelineProgress` (_single source of truth_ para a lógica de etapas
  done/current/aborted), eliminando cópias duplicadas em `Executions` e
  `ExecutionDetail`. As telas agora usam coloração por etapa, consistente com
  Overview/Features.

## [0.1.0] - 2026-05-26

Primeira versão do **cstk-panel** — dashboard de observabilidade _read-only_ para
execuções dos orquestradores `agente-00c` / `feature-00c`, lido diretamente da
`~/.claude/cstk/knowledge.db`.

### Adicionado

#### Backend (`@cstk-panel/server`)
- Servidor HTTP _read-only_ sobre a `knowledge.db` expondo 29 endpoints `GET`.
- Abertura do banco em modo somente-leitura (`readonly: true` + `pragma query_only = 1`),
  com _retry_ tolerante a _torn read_ transitório.
- Envelope de resposta padrão `{ data, meta: { degraded, reason, freshness, schema_version } }`.
- Degradação graciosa (Invariante II): nenhum caminho lança exceção — falhas retornam
  `{ ok: false }` com motivo.
- Frescor de _snapshot_ via `freshness` + `ETag` em todas as rotas.
- Suporte ao schema v3 da `knowledge.db` (campos `titulo` e `recall_consulted`).
- Sanitização de _payload_ FTS5 contra _queries_ hostis.

#### Tipos compartilhados (`@cstk-panel/shared-types`)
- DTOs centralizados com schemas Zod correspondentes e testes de paridade _round-trip_
  (payloads sintéticos e reais da API).

#### Frontend (`@cstk-panel/web`)
- SPA React 19 com `HashRouter` e TanStack Query.
- Telas Overview, Projetos, Features, Tarefas e Incidentes (visões _cross-execução_).
- Conteúdo UNTRUSTED renderizado via `<TextRaw>` — sem `dangerouslySetInnerHTML` (Invariante V).
- Custo exibido apenas como `tool calls` (proxy honesto, sem `$`/USD/tokens — Invariante III).
- Identidade visual alinhada ao protótipo (logo e mix de modelos).

#### Qualidade e governança
- 189 testes automatizados (shared-types + integração E2E do servidor).
- Invariantes constitucionais I–VI verificáveis por scripts de _lint_.
- `npm run lint:readonly-check` garante zero verbos de mutação SQL em `apps/server/src`.

[0.27.0]: https://github.com/JotJunior/cstk-panel/compare/v0.26.0...v0.27.0
[0.26.0]: https://github.com/JotJunior/cstk-panel/compare/v0.25.0...v0.26.0
[0.25.0]: https://github.com/JotJunior/cstk-panel/compare/v0.24.0...v0.25.0
[0.24.0]: https://github.com/JotJunior/cstk-panel/compare/v0.23.1...v0.24.0
[0.23.1]: https://github.com/JotJunior/cstk-panel/compare/v0.23.0...v0.23.1
[0.23.0]: https://github.com/JotJunior/cstk-panel/compare/v0.22.1...v0.23.0
[0.22.1]: https://github.com/JotJunior/cstk-panel/compare/v0.22.0...v0.22.1
[0.22.0]: https://github.com/JotJunior/cstk-panel/compare/v0.21.1...v0.22.0
[0.21.1]: https://github.com/JotJunior/cstk-panel/compare/v0.21.0...v0.21.1
[0.21.0]: https://github.com/JotJunior/cstk-panel/compare/v0.20.0...v0.21.0
[0.20.0]: https://github.com/JotJunior/cstk-panel/compare/v0.19.2...v0.20.0
[0.19.2]: https://github.com/JotJunior/cstk-panel/compare/v0.19.1...v0.19.2
[0.19.1]: https://github.com/JotJunior/cstk-panel/compare/v0.19.0...v0.19.1
[0.19.0]: https://github.com/JotJunior/cstk-panel/compare/v0.18.0...v0.19.0
[0.18.0]: https://github.com/JotJunior/cstk-panel/compare/v0.17.0...v0.18.0
[0.17.0]: https://github.com/JotJunior/cstk-panel/compare/v0.16.1...v0.17.0
[0.16.1]: https://github.com/JotJunior/cstk-panel/compare/v0.16.0...v0.16.1
[0.16.0]: https://github.com/JotJunior/cstk-panel/compare/v0.15.1...v0.16.0
[0.15.1]: https://github.com/JotJunior/cstk-panel/compare/v0.15.0...v0.15.1
[0.15.0]: https://github.com/JotJunior/cstk-panel/compare/v0.14.1...v0.15.0
[0.14.1]: https://github.com/JotJunior/cstk-panel/compare/v0.14.0...v0.14.1
[0.14.0]: https://github.com/JotJunior/cstk-panel/compare/v0.13.1...v0.14.0
[0.13.1]: https://github.com/JotJunior/cstk-panel/compare/v0.13.0...v0.13.1
[0.13.0]: https://github.com/JotJunior/cstk-panel/compare/v0.12.1...v0.13.0
[0.12.1]: https://github.com/JotJunior/cstk-panel/compare/v0.12.0...v0.12.1
[0.12.0]: https://github.com/JotJunior/cstk-panel/compare/v0.11.2...v0.12.0
[0.11.2]: https://github.com/JotJunior/cstk-panel/compare/v0.11.1...v0.11.2
[0.11.1]: https://github.com/JotJunior/cstk-panel/compare/v0.11.0...v0.11.1
[0.11.0]: https://github.com/JotJunior/cstk-panel/compare/v0.10.1...v0.11.0
[0.10.1]: https://github.com/JotJunior/cstk-panel/compare/v0.10.0...v0.10.1
[0.10.0]: https://github.com/JotJunior/cstk-panel/compare/v0.9.2...v0.10.0
[0.9.2]: https://github.com/JotJunior/cstk-panel/compare/v0.9.1...v0.9.2
[0.9.1]: https://github.com/JotJunior/cstk-panel/compare/v0.9.0...v0.9.1
[0.9.0]: https://github.com/JotJunior/cstk-panel/compare/v0.8.2...v0.9.0
[0.8.2]: https://github.com/JotJunior/cstk-panel/compare/v0.8.1...v0.8.2
[0.8.1]: https://github.com/JotJunior/cstk-panel/compare/v0.8.0...v0.8.1
[0.8.0]: https://github.com/JotJunior/cstk-panel/compare/v0.7.1...v0.8.0
[0.7.1]: https://github.com/JotJunior/cstk-panel/compare/v0.7.0...v0.7.1
[0.7.0]: https://github.com/JotJunior/cstk-panel/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/JotJunior/cstk-panel/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/JotJunior/cstk-panel/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/JotJunior/cstk-panel/compare/v0.3.1...v0.4.0
[0.3.1]: https://github.com/JotJunior/cstk-panel/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/JotJunior/cstk-panel/compare/v0.2.2...v0.3.0
[0.2.2]: https://github.com/JotJunior/cstk-panel/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/JotJunior/cstk-panel/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/JotJunior/cstk-panel/compare/v0.1.2...v0.2.0
[0.1.2]: https://github.com/JotJunior/cstk-panel/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/JotJunior/cstk-panel/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/JotJunior/cstk-panel/releases/tag/v0.1.0
