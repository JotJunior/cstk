<!--
Sync Impact Report (emenda 2026-08-10)
- Version: 1.2.0 → 1.3.0
- Bump rationale: MINOR — terceira expansao material do Principio III, mesmo
  padrao das emendas 1.1.0 e 1.2.0, agora cobrindo DOIS dados novos da fonte,
  mais uma correcao factual de lista.
  (a) knowledge.db v12 (cstk 5.33.0, feature otel-model-breakdown) persiste 8
  colunas `otel_{main,subagent}_{input,output,cache_read,cache_creation}_tokens`
  em `waves` — breakdown de tokens por FONTE e por TIPO. O fato novo que
  obriga a emenda: os lados main e subagente sao coletas INDEPENDENTES e
  divergem materialmente na base real (medido em 2026-08-10 sobre
  ~/.claude/cstk/knowledge.db v14: 27 ondas com `by_source.main` contra 257
  com `by_source.subagent`, de 1182). A regra de cobertura de amostra das
  emendas anteriores pressupunha UM denominador; aqui ela passa a exigir
  denominadores SEPARADOS por lado.
  (b) knowledge.db v14 (cstk 7.2.0, feature plan-usage-capture) persiste
  `plan_usage` — o gauge `rate_limits` da CONTA por janela (`five_hour`,
  `seven_day`). E uma grandeza NOVA: nao e esforco (tool_calls), nao e
  dinheiro (USD) e nao e consumo (tokens) — e quota. Entra na lista de
  grandezas que MUST NOT ser somadas entre si.
  (c) Correcao factual: a lista de tabelas da knowledge.db no MUST NOT de
  "campos que nao existem" estava defasada desde a v12 — omitia
  `wave_model_usage` (lida desde a 0.20.x), `loose_usage` e `plan_usage`.
  Lista incompleta num MUST NOT torna o gate inaplicavel: nao havia como
  distinguir "campo inventado" de "tabela que a lista esqueceu".
- Autorizacao: operador humano, 2026-08-10, em resposta ao relatorio de
  adequacao ao schema v14 ("atualize o constitution").
- Principios afetados: III. Honestidade de Metrica (expandido; nenhuma
  clausula removida — a proibicao de metrica inventada/estimada segue
  integral).
- Artefatos atualizados nesta emenda:
  - apps/server/src/config.ts (DEFAULT_SCHEMA_VERSIONS ate v14)
  - apps/server/src/db/queries/{metrics,waves,executions}.ts
  - apps/server/src/mappers/{wave,otel-usage}.ts
  - apps/server/src/routes/metrics.ts (GET /metrics/plan-usage)
  - packages/shared-types/src/{entities.ts,schemas/entities.ts}
  - apps/web/src/components/{OtelUsage,PlanUsage}.tsx
  - apps/web/src/lib/plan-usage-select.ts
  - apps/web/src/screens/{Metrics,Overview}.tsx
- Artefatos que permanecem validos sem mudanca: Principios I, II, IV, V, VI.

Sync Impact Report (emenda 2026-07-28)
- Version: 1.1.0 → 1.2.0
- Bump rationale: MINOR — segunda expansao material do Principio III, mesmo
  padrao da emenda 1.1.0. A proibicao original de "$"/USD partia da premissa
  de que "o painel nao conhece preco de token e nao o estima". Essa premissa
  ja havia deixado de valer para CONTAGEM de tokens (emenda 1.1.0); agora
  deixa de valer tambem para CUSTO MONETARIO: o cstk 5.30.0 (feature
  otel-model-breakdown) persiste `otel_cost_usd` na knowledge.db v11 — um
  valor de custo REAL MEDIDO por onda e por modelo (nao estimado, nao
  convertido a partir de preco de token pelo painel). O principio nao foi
  enfraquecido — a proibicao de valor monetario ESTIMADO/INVENTADO/
  CONVERTIDO pelo painel segue integral; abre-se excecao apenas para o dado
  MEDIDO na fonte, com a mesma logica de cobertura de amostra ja exigida
  para `agent_*`.
- Autorizacao: operador humano, via bloqueio block-001 da execucao
  feature-00c/dashboard-refactor (Decisao dec-009, respondido
  2026-07-28T12:26:28Z) — resposta C, autorizando expressamente esta
  emenda formal antes/junto da implementacao de FR-003.
- Principios afetados: III. Honestidade de Metrica (expandido; nenhuma
  clausula removida — proibicao de valor monetario estimado/inventado
  segue integral).
- Artefatos atualizados nesta emenda:
  - docs/specs/dashboard-refactor/spec.md (FR-003, Clarifications)
- Artefatos que permanecem validos sem mudanca: Principios I, II, IV, V, VI.

Sync Impact Report (emenda 2026-07-26)
- Version: 1.0.0 → 1.1.0
- Bump rationale: MINOR — expansao material do Principio III. A premissa
  factual da proibicao original ("o harness nao expoe consumo de tokens")
  deixou de valer: o cstk 5.25.0 (feature wave-token-metrics) persiste o uso
  MEDIDO de cada spawn de subagente na knowledge.db v10
  (waves.agent_total_tokens e 8 colunas irmas). O principio nao foi
  enfraquecido — foi reancorado: continua proibido inventar, estimar ou
  monetizar; passa a ser obrigatorio exibir a cobertura da amostra.
- Principios afetados: III. Honestidade de Metrica (expandido; nenhuma
  clausula removida — a proibicao de "$"/USD e de metrica inventada segue
  integral).
- Artefatos atualizados nesta emenda:
  - apps/web/src/screens/Overview.tsx (tip "o harness nao expoe tokens" —
    obsoleto, reescrito)
  - apps/web/src/screens/{Metrics,ProjectDetail,FeatureDetail,ExecutionDetail}.tsx
  - apps/web/src/components/AgentUsage.tsx (regra de cobertura centralizada)
  - apps/server/src/db/queries/{metrics,waves,executions}.ts
- Artefatos que permanecem validos sem mudanca: Principios I, II, IV, V, VI.

Sync Impact Report (ratificacao inicial)
- Version: (none) → 1.0.0
- Bump rationale: ratificacao inicial (MAJOR baseline) — constituicao criada do zero a partir do briefing consolidado.
- Principios adicionados (Core):
  - I. Read-Only Absoluto (NON-NEGOTIABLE)
  - II. Degradar, Nunca Quebrar
  - III. Honestidade de Metrica
  - IV. Nao Reimplementar o que Tem Dono
  - V. Conteudo de Agente e UNTRUSTED
  - VI. Snapshot que Muda
- Secoes adicionadas:
  - Padroes de Seguranca e Qualidade (deriva da secao 12 do briefing)
  - Fidelidade de Design e Estados de Tela (deriva das secoes 3.3, 6, 11 do briefing)
  - Governance
- Secoes removidas: nenhuma
- Artefatos que precisam atualizacao manual:
  - docs/specs/cstk-panel/spec.md (status: a criar — etapa specify; deve referenciar Principios I-VI)
  - docs/specs/cstk-panel/plan.md (status: a criar — Constitution Check como gate)
  - CLAUDE.md local do projeto (status: ausente; SHOULD criar refletindo Principios I, III, IV)
- TODOs pendentes: nenhum (todos os placeholders resolvidos)
- Fonte: docs/01-briefing-discovery/briefing.md (secoes 4, 5, 9, 12)
-->

# cstk-panel Constitution

> **cstk-panel** e um dashboard de observabilidade **read-only** sobre a
> `knowledge.db` (indice SQLite + FTS5, schema v2) das execucoes dos
> orquestradores autonomos `agente-00c` / `feature-00c`. A fonte da verdade
> e o `state.json` transacional de cada execucao; a `knowledge.db` e um
> indice derivado e reconstruivel. Este documento governa toda decisao de
> arquitetura, qualidade, seguranca e UX do projeto.

## Core Principles

### I. Read-Only Absoluto (NON-NEGOTIABLE)

O painel e seu back-end **APENAS observam**. Nenhum caminho de codigo emite
`INSERT`, `UPDATE`, `DELETE`, `CREATE`, `DROP` ou qualquer mutacao.

- MUST: a conexao SQLite e aberta com `mode=ro&immutable=1`
  (DSN: `file:/abs/path/knowledge.db?mode=ro&immutable=1&_busy_timeout=5000`).
- MUST NOT: tocar `state.json` (fonte da verdade transacional) nem
  reconstruir o indice (`cstk recall --reindex` tem dono fora do painel).
- MUST NOT: existir formulario de mutacao, endpoint nao-`GET`, ou rota que
  altere dado. A superficie de API e exclusivamente `GET /api/v1/*`.

**Why**: o painel e um consumidor derivado. Qualquer escrita corromperia a
separacao fonte-da-verdade ↔ indice e violaria o contrato com `cstk recall`.
**Testavel**: grep do codebase por verbos de mutacao SQL retorna zero
ocorrencias em caminhos de dados; toda rota HTTP responde a `GET`.

### II. Degradar, Nunca Quebrar

Banco ausente, vazio, parcial ou corrompido e um **estado de primeira
classe**, nunca um erro de servidor.

- MUST: responder `200` com sinal de degradacao no envelope
  (`meta.degraded=true`, `meta.reason="..."`) quando o dado nao esta
  disponivel ou esta degradado.
- MUST NOT: retornar `5xx` por condicao de dado (banco faltando,
  `quick_check` falhando, tabela vazia).
- MUST: toda tela do front-end implementar os quatro estados obrigatorios —
  carregando (skeleton), vazio, erro e degradado.
- SHOULD: executar `PRAGMA quick_check` na inicializacao e no endpoint de
  saude, surfaceando o resultado como degradacao e nao como falha.

**Why**: a `knowledge.db` e best-effort e pode nao existir; um observador
nunca deve "quebrar" porque o que observa ainda nao foi populado.
**Testavel**: com banco removido/corrompido, `GET /api/v1/*` retorna `200`
com `meta.degraded=true`; nenhuma resposta `5xx` por estado de dado.

### III. Honestidade de Metrica

O painel reporta apenas o que existe no schema, com a natureza de cada numero
explicita: **proxy**, **derivado/aproximado** ou **medido**. Esforco do
orquestrador continua sendo medido pelo proxy `tool_calls`, jamais inventado.

- MUST: rotular `tool_calls` explicitamente como "proxy" — ele conta chamadas
  de ferramenta, nao consumo.
- MUST NOT: exibir `$`, `USD` ou qualquer valor monetario ESTIMADO,
  derivado ou convertido pelo proprio painel a partir de preco de token. O
  painel nao conhece preco de token e nao o estima. **Excecao (emenda
  1.2.0)**: valor monetario MEDIDO na fonte (`otel_cost_usd`, schema v11)
  PODE ser exibido em USD absoluto, sob as mesmas tres regras da secao
  "Consumo de subagentes" abaixo (cobertura de amostra, NULL != 0, nao
  somar com outro proxy/medida).
- MUST NOT: inventar, estimar ou derivar campos que nao existem nas tabelas
  da knowledge.db (`executions`, `waves`, `decisions`, `tasks`, `events`,
  `alert_signals`, `blocks`, `skills`, `retros`, `suggestions`, `memories`,
  `wave_model_usage`, `loose_usage`, `plan_usage`, `knowledge_fts`).
  A lista acompanha o schema da fonte: tabela nova aceita pelo guard de
  abertura (`DEFAULT_SCHEMA_VERSIONS`) MUST entrar aqui na mesma emenda —
  lista defasada torna este MUST NOT inaplicavel, porque deixa de distinguir
  "campo inventado" de "tabela que a lista esqueceu" (emenda 1.3.0).
- SHOULD: metricas aproximadas/derivadas (ex: clarify-resolution rate) sao
  rotuladas como derivadas/aproximadas no envelope ou na UI.

**Consumo de subagentes (schema v10 — emenda 1.1.0)**: desde o cstk 5.25.0
(feature `wave-token-metrics`) o harness reporta o uso de cada spawn e o
`cstk recall --ingest` agrega em `waves.agent_*`. Esse numero e MEDIDO — nao
e proxy nem estimativa — e por isso PODE ser exibido como "tokens", sob tres
regras inegociaveis:

- MUST: exibir a cobertura da amostra sempre que houver total. Spawns em
  background nao reportam uso, entao todo total vem acompanhado de
  `spawns_with_usage / spawns_total` (ex: "3 de 4 spawns medidos"). Um total
  sem denominador apresenta parcial como completo.
- MUST NOT: converter `NULL` em `0`. A fonte distingue tres estados —
  nao coletado (sem contagem de spawn), coletado sem dado de uso (spawns
  contados, tokens nulos) e medido — e a UI MUST manter os tres distintos.
  "Nao medido" exibido como zero e fabricacao.
- MUST NOT: somar token medido com `tool_calls` num unico indicador de
  "custo", nem apresentar um como substituto do outro: contam coisas
  diferentes (consumo dos subagentes x chamadas do orquestrador).

**Custo monetario medido (schema v11 — emenda 1.2.0)**: desde o cstk 5.30.0
(feature `otel-model-breakdown`) a fonte persiste `otel_cost_usd` por onda e
por modelo, um valor de custo REAL MEDIDO na instrumentacao (nao estimado
nem convertido a partir de preco de token pelo painel). Esse numero PODE ser
exibido em USD absoluto, sob as mesmas tres regras inegociaveis da secao
"Consumo de subagentes":

- MUST: exibir a cobertura da amostra sempre que houver total agregado
  (ex: "3 de 4 ondas com custo medido"). Total sem denominador apresenta
  parcial como completo.
- MUST NOT: converter `NULL` em `0`. "Nao medido" exibido como zero e
  fabricacao — a UI MUST distinguir nao coletado de coletado-e-zero.
- MUST NOT: somar `otel_cost_usd` com `tool_calls` ou com token medido
  (`agent_*`) num unico indicador; sao tres grandezas distintas (custo
  monetario medido, esforco-proxy do orquestrador, consumo de tokens
  medido dos subagentes) e cada uma mantem seu proprio rotulo.

**Breakdown de tokens por fonte (schema v12 — emenda 1.3.0)**: desde o cstk
5.33.0 a fonte persiste 8 colunas
`otel_{main,subagent}_{input,output,cache_read,cache_creation}_tokens` em
`waves`, abrindo o total ja permitido pela emenda 1.2.0 por FONTE (loop
principal x subagente) e por TIPO de token. O dado e MEDIDO e PODE ser
exibido, sob as regras acima MAIS duas especificas desta grandeza:

- MUST: usar denominadores de cobertura SEPARADOS por fonte. `main` e
  `subagent` sao coletas independentes e divergem na base real (27 ondas
  com main contra 257 com subagente, de 1182 — medicao de 2026-08-10). Um
  denominador unico apresentaria como medido um lado que nunca foi coletado,
  que e a mesma fabricacao que a regra de cobertura existe para impedir.
- MUST NOT: usar `otel_total_tokens` como denominador ao derivar proporcoes
  DENTRO de um lado (ex.: fatia de cache read do loop principal). Aquele
  total mistura as duas fontes e existe mesmo quando o breakdown do lado nao
  foi coletado — o denominador correto e a soma dos 4 tipos daquele lado.
  Na pratica isto muda o numero pela metade, nao na terceira casa.
- SHOULD: rotular cache read como contexto RELIDO, nao token novo. Uma onda
  de milhoes de tokens sendo ~95% cache read e uma onda LONGA, nao uma onda
  cara; apresentar o total sem essa distincao induz erro de leitura de uma
  ordem de grandeza.

**Cota do plano (schema v14 — emenda 1.3.0)**: desde o cstk 7.2.0 (feature
`plan-usage-capture`) a fonte persiste `plan_usage` — o percentual da cota da
CONTA ja consumido em duas janelas (`five_hour`, `seven_day`), capturado pelo
hook `statusLine.command`. E uma QUARTA grandeza, distinta das tres acima:

- MUST NOT: somar, mediar ou comparar `used_percentage` com custo, token ou
  tool_calls — e quota de conta, nao consumo de execucao. Um projeto pode
  custar pouco em USD e ainda assim esgotar a janela de 5h.
- MUST NOT: mesclar os dois escopos num unico numero. `five_hour` e
  `seven_day` sao series independentes por construcao na fonte (FR-005 do
  cstk); a media entre elas nao descreve nada.
- MUST NOT: renderizar ausencia de captura como `0%`. A captura e OPT-IN
  (`cstk statusline install`) e a tabela vazia significa "hook desligado",
  nunca "plano intocado" — os dois estados MUST permanecer distinguiveis na
  tela, assim como `NULL` != `0` nas demais metricas.
- MUST NOT: recortar o gauge por projeto. A tabela guarda de qual sessao
  partiu a captura, mas o medidor e da credencial; um recorte por projeto
  sugeriria "cota gasta por projeto", numero que a fonte nao produz.

**Why**: honestidade de instrumentacao e pre-requisito de confianca numa
ferramenta de observabilidade; metrica inventada e pior que metrica ausente —
e uma metrica real apresentada como mais completa do que e tem o mesmo efeito.
**Testavel**: grep da UI/API por "USD"/"$" como rotulo de custo ESTIMADO
retorna zero (uso de "USD"/"$" e permitido exclusivamente atrelado a
`otel_cost_usd` medido, com cobertura de amostra visivel); todo numero
exibido mapeia a uma coluna real do schema; nenhum caminho de codigo
coalesce as colunas `agent_*`, `otel_*` ou `plan_usage.used_percentage`
para 0 (coberto por `apps/server/test/lib/{agent-usage,otel-usage,
plan-usage}.test.ts` e `apps/web/src/lib/{agent-usage,otel-usage,
plan-usage-select}.test.ts`). Para a emenda 1.3.0 especificamente: os dois
denominadores de cobertura por fonte sao asseridos divergentes em
`apps/web/src/lib/otel-usage.test.ts` (`sumOtelUsage` — cada lado conta so
as ondas que mediram aquele lado), e a proibicao de `0%` fabricado em
`apps/web/src/lib/plan-usage-select.test.ts` (`fmtPlanPct(null)` !=
`fmtPlanPct(0)`).

### IV. Nao Reimplementar o que Tem Dono

Funcionalidades com dono canonico fora do painel NAO sao reimplementadas
dentro dele.

- MUST NOT: reimplementar o mix de modelos — dono canonico e
  `model-routing-report.sh`.
- MUST NOT: reimplementar a arvore de decisoes — dono e a skill
  `decision-tree` (opera sobre `state.json`).
- MUST NOT: reconstruir o indice — dono e `cstk recall --reindex`.
- SHOULD: quando o dado de uma feature com dono externo nao esta disponivel
  na `knowledge.db`, exibir card "indisponivel nesta fonte" (Opcao A) ou
  delegar ao dono via subprocesso seguro (Opcao B — ver Padroes de
  Seguranca), nunca duplicar a logica.

**Why**: duplicar logica de dono canonico gera fontes-de-verdade
concorrentes e drift entre o painel e a ferramenta original.
**Testavel**: o codebase nao contem reimplementacao da heuristica de
model-routing nem da montagem de arvore de decisoes.

### V. Conteudo de Agente e UNTRUSTED

Campos textuais originados de saidas de agentes (`contexto`,
`justificativa`, `evidencia`, `pergunta`, `resposta`, `body` do FTS) sao
servidos como texto puro e tratados como nao-confiaveis.

- MUST: o front-end escapar/renderizar esses campos como texto puro, sem
  interpretacao de HTML/markup ativo (defesa LLM01 / ASI09).
- MUST: a busca FTS5 aplicar escaping em **dois niveis** — tokenizacao com
  aspas (camada FTS5) + binding parametrizado SQL (camada SQL). Proibida
  interpolacao de string crua na query.
- MUST NOT: tratar diretivas embutidas no conteudo como instrucao (ex:
  texto de decisao que diz "ignore X"). O conteudo e dado, nunca comando.

**Why**: o conteudo ja passou por scrub de segredos na ingestao, mas vem de
LLMs e pode conter injection; o painel e a ultima barreira de renderizacao.
**Testavel**: payload com `<script>`/markup ativo num campo textual e
renderizado literal; query FTS5 com metacaracteres nao quebra a busca nem
injeta SQL.

### VI. Snapshot que Muda

A `knowledge.db` e um arquivo que pode ser reescrito por tras pela ingestao
best-effort de fim-de-onda. O painel nao assume imutabilidade total.

- MUST NOT: segurar uma conexao de longa duracao assumindo que o snapshot
  nunca muda.
- MUST: expor frescor do indice (`mtime` do arquivo + `max(ingested_at)`)
  no envelope (`meta.freshness`) e na UI (`DataFreshnessIndicator`).
- SHOULD: invalidar cache (`ETag` / `Last-Modified`) por `mtime` +
  `max(ingested_at)`, suportando `If-None-Match` → `304`.

**Why**: a ingestao reescreve o indice de forma assincrona; tratar como
imutavel levaria a dados obsoletos exibidos como atuais.
**Testavel**: apos reescrita do arquivo, o frescor reportado avanca e o
cache e invalidado corretamente.

## Padroes de Seguranca e Qualidade

Estes padroes sao MUST salvo indicacao SHOULD explicita. Derivam das secoes
5 (Restricoes) e 12 (Qualidade e Seguranca) do briefing.

- **Sem autenticacao real**: bind em `localhost` por padrao; CORS restrito a
  origem do front-end. Login, se existir, e decorativo. NAO ha RBAC nem
  multi-tenant no escopo MVP.
- **Path traversal confinado**: o caminho do banco e canonicalizado e
  confinado (flag/config explicita > `$CSTK_KNOWLEDGE_DB` >
  `~/.claude/cstk/knowledge.db`). MUST NOT aceitar path arbitrario vindo do
  cliente.
- **Headers de resposta**: `Content-Type: application/json` +
  `X-Content-Type-Options: nosniff`.
- **Paginacao obrigatoria**: endpoints `decisions` e `search` MUST paginar
  (`limit`+`offset` ou cursor); resposta nunca despeja a tabela inteira.
- **Rate-limit leve** na busca FTS5 (pode ser custosa).
- **Subprocesso seguro** (somente se Opcao B de mix-modelos for adotada):
  executar `model-routing-report.sh` com argumentos validados, **sem
  shell-string interpolada**, com timeout e captura de stderr.
- **Envelope padrao**: toda resposta carrega
  `{ data, meta: { degraded, reason, freshness, schema_version } }`.

**Why**: o painel le conteudo nao-confiavel de um arquivo local sensivel;
a superficie de ataque (FTS5 injection, path traversal, subprocesso) e
contida por defesa em profundidade.

## Fidelidade de Design e Estados de Tela

- **Pixel-perfect conforme prototipo**: a fonte da verdade visual e
  `docs/06-ui-ux-design/castk-panel/project/`. MUST recriar fielmente
  (tokens, tipografia, cores, layout) — SHOULD NOT copiar a estrutura
  interna do prototipo, mas reproduzir o resultado visual.
- **Design tokens**: dark-mode-first; tipografia Inter (UI) + JetBrains
  Mono (IDs, valores numericos, evidencias); cores semanticas, de modelo e
  de score conforme `styles.css` do prototipo.
- **Quatro estados por tela** (reforco do Principio II): carregando, vazio,
  erro, degradado — todos de primeira classe, nenhum opcional.
- **Drill-down como navegacao padrao**: hierarquia
  `Projeto → Feature → Execucao → Onda → Decisao | Tarefa | Evento | Alerta`;
  tudo clicavel ate o nivel mais granular.

**Why**: o prototipo ja foi validado como a experiencia desejada; divergir
dele e regressao de produto, nao liberdade de implementacao.

## Governance

- **Autoridade**: esta constituicao supera convencoes ad-hoc. Em conflito
  entre um principio aqui e uma decisao pontual, o principio prevalece —
  excecoes exigem justificativa documentada (ADR ou Decisao auditada).
- **Versionamento (SemVer)**:
  - MAJOR: remocao ou redefinicao incompativel de principio.
  - MINOR: novo principio ou expansao material de secao.
  - PATCH: clarificacao, correcao de texto ou refinamento nao-semantico.
- **Amendments**: toda alteracao MUST incluir Sync Impact Report (no topo
  do arquivo) listando bump, principios afetados e artefatos a atualizar.
- **Constitution Check como gate**: `plan.md` e `tasks.md` de cada feature
  MUST referenciar e respeitar os Principios I-VI; `analyze` valida
  alinhamento entre spec/plan/tasks e esta constituicao.
- **Excecoes**: uma violacao consciente de SHOULD e registrada com
  rationale; uma violacao de MUST/NON-NEGOTIABLE invalida o artefato ate
  ser corrigida ou a constituicao ser emendada via SemVer.

**Version**: 1.3.0 | **Ratified**: 2026-05-24 | **Last Amended**: 2026-08-10
