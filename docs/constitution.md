<!--
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
- MUST NOT: exibir `$`, `USD` ou qualquer valor monetario, derivado ou
  convertido. O painel nao conhece preco de token e nao o estima.
- MUST NOT: inventar, estimar ou derivar campos que nao existem nas tabelas
  da knowledge.db (`executions`, `waves`, `decisions`, `tasks`, `events`,
  `alert_signals`, `blocks`, `skills`, `retros`, `suggestions`, `memories`,
  `knowledge_fts`).
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

**Why**: honestidade de instrumentacao e pre-requisito de confianca numa
ferramenta de observabilidade; metrica inventada e pior que metrica ausente —
e uma metrica real apresentada como mais completa do que e tem o mesmo efeito.
**Testavel**: grep da UI/API por "USD"/"$" como rotulo de custo retorna zero;
todo numero exibido mapeia a uma coluna real do schema; nenhum caminho de
codigo coalesce as colunas `agent_*` para 0 (coberto por
`apps/server/test/lib/agent-usage.test.ts` e
`apps/web/src/lib/agent-usage.test.ts`).

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

**Version**: 1.1.0 | **Ratified**: 2026-05-24 | **Last Amended**: 2026-07-26
