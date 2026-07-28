# Feature Specification: OTel Model Breakdown na knowledge.db

**Feature**: `otel-model-breakdown`
**Created**: 2026-07-28
**Status**: Draft

## Clarifications

### Session 2026-07-28

- Q: Qual o escopo da coluna `otel_session_id`, dado que o valor observado no snapshot OTel nao discrimina sessao/projeto (o mesmo `session_id` aparece associado a execucoes distintas) e a causa raiz do desalinhamento nao foi investigada? → A: Remover `otel_session_id` do escopo desta feature. Evidencia (scrape cru de `http://localhost:9464/metrics`, 2026-07-27): as series de `claude_code_cost_usage_total`/`claude_code_token_usage_total` carregam `session_id=7fa7b962-0e4b-413f-897e-25fc8b64fceb`, que corresponde a um arquivo de sessao do projeto `my-music-match` (nao do `cstk`); `claude_code_session_count_total` carrega um terceiro id (`ac374e36-0c5b-4ad0-ab06-76dc33347496`); e a sessao corrente do `cstk` (`8eb1ff1c-fcec-484b-82d4-047961961814`) nao aparece em nenhuma serie — embora os CONTADORES (custo/tokens) reflitam corretamente a atividade corrente. A causa raiz desse desalinhamento nao foi determinada; a spec nao afirma causa, apenas remove a coluna do escopo. Achado registrado como sugestao de investigacao futura, fora desta feature.
- Q: O guard de invalidacao de delta do `otel-usage.sh` (compara `session_id` entre snapshots de inicio/fim de onda para descartar o delta quando o processo Claude Code troca), que a investigacao acima sugere nunca disparar no ambiente observado, deve ser corrigido dentro desta feature ou tratado separadamente? → A: Bugfix separado, fora do escopo desta feature — registrado como sugestao priorizada. Nao vira requisito nem task aqui, para nao misturar correcao de coleta de telemetria com a migracao de schema da knowledge.db.
- Q: O nome do modelo persistido em `wave_model_usage` deve ser a string bruta do snapshot OTel ou normalizada para o alias canonico (`opus`/`sonnet`/`haiku`) usado pelo model-routing, para garantir join exato entre as duas dimensoes? → A: String bruta do snapshot OTel, sem normalizacao na ingestao. Valores reais observados no endpoint incluem `claude-fable-5` (sem alias no mapa fase→modelo de `references/phase-model-map.txt`) e `claude-opus-5[1m]` (variante de contexto 1M, com custo distinto do opus normal) — normalizar apagaria ambas as distincoes e alteraria dado observado durante a ingestao. O join com as `DecisaoDeRoteamentoPorOnda` permanece best-effort/indireto (mesmo modelo, mesma onda), como ja descrito em Key Entities.

## User Scenarios & Testing

### User Story 1 - Custo e tokens por modelo, por onda (Priority: P1)

Como mantenedor do toolkit, quero consultar quanto de custo (USD) e de
tokens cada modelo (`opus`, `sonnet`, `haiku`, etc.) consumiu em cada onda
de uma execucao, para poder responder "quanto do gasto de uma feature foi
opus vs sonnet" e cruzar esse dado com as decisoes de roteamento de
modelo ja registradas (sugerido vs aplicado vs custo real observado).

**Why this priority**: hoje essa dimensao existe no snapshot bruto da
telemetria (`.waves[].otel_usage.by_model` do `state.json`) mas se perde
por completo na ingestao — sem ela, nenhuma auditoria de custo por modelo
e possivel a partir da knowledge.db, so lendo state.json onda a onda.

**Independent Test**: ingerir uma onda cujo `state.json` tenha
`otel_usage.by_model` com 2+ modelos populados e consultar a knowledge.db
agrupando por modelo — os valores retornados devem bater com a soma dos
campos `cost_usd`/`total_tokens` de cada modelo no `state.json` de origem.

**Acceptance Scenarios**:

1. **Given** uma onda com `otel_usage.by_model` contendo `claude-sonnet-5`
   e `claude-opus-5`, **When** a onda e ingerida, **Then** a knowledge.db
   passa a ter uma linha por modelo com o custo e os tokens daquele
   modelo naquela onda.
2. **Given** uma onda cujo `otel_usage` e `null` (sem snapshot valido,
   ex.: telemetria indisponivel ou `session_id` divergente entre
   inicio/fim da onda), **When** a onda e ingerida, **Then** nenhuma
   linha e criada para essa onda nesta dimensao — ausencia de dado, nunca
   zero fabricado.

---

### User Story 2 - Breakdown de tokens por fonte, incluindo cache (Priority: P2)

Como mantenedor do toolkit, quero ver o breakdown de tokens de entrada,
saida, leitura de cache e criacao de cache, separado por fonte (execucao
principal vs subagentes), para calcular a taxa de acerto de cache por
onda e entender onde o consumo de tokens realmente acontece.

**Why this priority**: o snapshot bruto ja separa isso
(`otel_usage.by_source.main` e `otel_usage.by_source.subagent`, cada um
com `input`/`output`/`cache_read`/`cache_creation`), mas a ingestao hoje
so guarda o total de tokens do subagent — o breakdown do `main` some por
completo e o do `subagent` fica reduzido a um unico numero.

**Independent Test**: ingerir uma onda com `otel_usage.by_source.main` e
`by_source.subagent` totalmente populados e confirmar que os 4 tipos de
token de cada fonte aparecem como colunas distintas e consultaveis na
knowledge.db.

**Acceptance Scenarios**:

1. **Given** uma onda com `by_source.main.cache_read = 50000` e
   `by_source.subagent.cache_read = 1500000`, **When** a onda e
   ingerida, **Then** a knowledge.db armazena os dois valores em colunas
   distintas, permitindo calcular a razao cache_read / (input + output +
   cache_read + cache_creation) por fonte.
2. **Given** uma onda cujo `by_source` so tem a chave `subagent` (nenhuma
   atividade de `main` medida pela telemetria naquela onda), **When** a
   onda e ingerida, **Then** as colunas de breakdown do `main` ficam NULL
   (nao zero) nessa linha.

---

### User Story 3 - Historico reconstruivel via reindex (Priority: P3)

Como mantenedor do toolkit, quero que rodar `cstk recall --reindex`
reconstrua essas novas dimensoes a partir do `state.json` ja existente no
disco de execucoes passadas, para nao perder visibilidade sobre custo por
modelo em features ja concluidas antes desta migracao.

**Why this priority**: a knowledge.db e um indice puramente derivado
(reconstruivel do zero); sem o backfill, todo o historico anterior a
esta feature ficaria com as novas colunas/tabela vazias mesmo havendo
dado real disponivel em `.waves[].otel_usage` nos `state.json` no disco.

**Independent Test**: rodar `--reindex` sobre um corpus com execucoes
reais que ja tem `otel_usage` gravado (`my-music-match/foundation`,
`mcp-project-scafold`) e confirmar que a tabela nova e as colunas
aditivas de `waves` sao populadas para essas ondas.

**Acceptance Scenarios**:

1. **Given** um `state.json` de execucao passada com `.waves[N].otel_usage.by_model`
   preenchido, **When** `cstk recall --reindex` roda, **Then** a linha
   correspondente em `wave_model_usage` existe apos o reindex, com os
   mesmos valores do `state.json`.
2. **Given** o mesmo corpus, **When** `--reindex` roda uma segunda vez,
   **Then** o resultado e identico ao da primeira execucao (idempotente,
   sem linhas duplicadas nem valores acumulados incorretamente).

---

### Edge Cases

- Onda sem qualquer telemetria OTel disponivel (`otel_usage: null` no
  `state.json`, ex.: `otel-usage.sh available` retornou nao-disponivel
  durante a execucao) — nenhuma linha em `wave_model_usage` e todas as
  colunas aditivas de `waves` ficam NULL para essa onda.
- Onda com escalada mid-onda de modelo (2+ modelos observados na mesma
  onda) — uma linha em `wave_model_usage` por modelo distinto observado.
- `session_id` do OTel divergente entre o snapshot de inicio e fim da
  onda (processo do Claude Code trocou no meio) — `otel-usage.sh delta`
  ja descarta o delta inteiro nesse caso (retorna `null`); a ingestao
  reflete isso como ausencia total de dado OTel para essa onda em todas
  as dimensoes novas desta feature. Nota (Clarifications Session
  2026-07-28): investigacao empirica indica que este guard, na pratica,
  nunca dispara no ambiente observado, porque o `session_id` do OTel
  permanece estavel entre reinicios do processo Claude Code — tratar
  esse defeito e bugfix separado, fora do escopo desta feature.
- Execucao ja ingerida ANTES desta migracao (schema < v12) — reingestao
  incremental ou `--reindex` preenchem retroativamente as novas colunas
  a partir do `otel_usage` ja presente no `state.json`, sem exigir
  reprocessamento manual.
- `sqlite3` ou `jq` ausentes no ambiente — comportamento identico ao
  hoje: ingestao inteira degrada com aviso, nunca aborta a onda em
  execucao.

## Limitacoes Conhecidas

- **Subcontagem silenciosa por falha do guard de invalidacao de
  delta**: `otel-usage.sh delta` descarta o delta inteiro quando o
  `session_id` do snapshot OTel diverge entre inicio e fim da onda
  (ver Edge Cases acima). Investigacao empirica (Clarifications Session
  2026-07-28) indica que, no ambiente observado, esse guard nunca
  dispara — o `session_id` permanece estavel entre reinicios do
  processo Claude Code, mesmo quando o processo de fato trocou. Risco
  residual, nao reproduzido mas nao descartado: se o guard falhar em
  disparar QUANDO deveria, o delta calculado poderia misturar
  custo/tokens de execucoes distintas sob o mesmo `session_id`,
  produzindo dado silenciosamente incorreto nas dimensoes desta
  feature (`wave_model_usage` e as 8 colunas de breakdown por fonte).
  Corrigir o guard e bugfix separado, deliberadamente fora do escopo
  desta feature (para nao misturar correcao de coleta de telemetria
  com migracao de schema) — rastreado como `sug-002` na knowledge.db
  (ver `checklists/schema-migration.md` CHK021).

## Requirements

### Functional Requirements

- **FR-001**: Sistema MUST persistir, por onda ingerida, uma linha por
  modelo observado no snapshot OTel daquela onda (grao onda x modelo),
  contendo ao menos o identificador do projeto, da feature, da onda, o
  nome do modelo, o custo em USD e o total de tokens daquele modelo
  naquela onda. O nome do modelo MUST ser persistido como a string
  bruta do snapshot OTel, sem normalizacao para alias canonico
  (`opus`/`sonnet`/`haiku`) — ver Clarifications Session 2026-07-28
  (variantes observadas sem alias no mapa fase→modelo, ou com sufixo de
  contexto estendido e custo distinto, teriam a distincao apagada por
  uma normalizacao).
- **FR-002**: Sistema MUST persistir o breakdown de tokens de entrada,
  saida, leitura de cache e criacao de cache, separadamente para a fonte
  principal (`main`) e para subagentes (`subagent`), por onda.
- **FR-003**: A migracao de schema MUST ser aditiva (nao remove nem
  renomeia coluna/tabela existente) e idempotente (reexecutar a migracao
  ou a ingestao nao duplica dado nem falha).
- **FR-004**: Ausencia de dado OTel para uma onda ou para uma dimensao
  especifica MUST resultar em valor NULL nos campos correspondentes —
  jamais um valor zero fabricado quando o dado simplesmente nao foi
  medido ou nao esta disponivel.
- **FR-005**: `--reindex` MUST reconstruir a nova tabela de custo por
  modelo e as novas colunas aditivas de onda inteiramente a partir do
  `otel_usage` presente nos `state.json` no disco, sem depender de
  nenhum estado intermediario da knowledge.db anterior.
- **FR-006**: A ingestao incremental (`--ingest`, chamada ao final de
  cada onda dos orquestradores) MUST popular as mesmas dimensoes novas
  ao processar uma onda recem-concluida, com o mesmo comportamento de
  `--reindex` para essa onda.
- **FR-007**: O acesso a dependencias externas (`sqlite3`, `jq`)
  necessarias para estas novas dimensoes MUST permanecer confinado ao
  mesmo modulo que ja concentra essas dependencias hoje, sem introduzir
  novo ponto de acoplamento.
- **FR-008**: A ausencia de `sqlite3` ou `jq` no ambiente MUST continuar
  degradando graciosamente (ingestao pulada, aviso emitido), sem abortar
  a onda do orquestrador em execucao — mesmo comportamento ja garantido
  para as demais dimensoes da knowledge.db.
- **FR-009**: As consultas e tabelas ja existentes sobre ondas (ex.:
  colunas escalares de custo/tokens ja ingeridas hoje) MUST continuar
  funcionando sem alteracao apos a migracao — as novas dimensoes sao
  estritamente aditivas.
- **FR-010**: O bump de schema desta feature (v11 -> v12) MUST ter
  rastreabilidade formal do impacto de compatibilidade cross-repo com o
  `cstk-panel`: o painel instalado valida `schema_version` contra uma
  allowlist fechada (`DEFAULT_SCHEMA_VERSIONS` em
  `apps/server/src/config.ts:31`, hoje `['2'..'11']`) e degrada com
  `schema-mismatch` em toda rota quando o banco esta em `12`. O bump
  MUST vir acompanhado de uma Sugestao registrada (`suggestions.sh
  register`) documentando a necessidade de bump correspondente no
  repo `cstk-panel`, para que o agendamento nao se perca apos o merge
  (ver Checklist CHK001/CHK003).
- **FR-011**: `wave_model_usage` MUST NUNCA alimentar `knowledge_fts` —
  mesma fronteira de seguranca ja aplicada as tabelas `tasks` e
  `events`. Nenhuma linha dessa tabela, nem o valor do campo `model`
  (unico dado de origem externa introduzido por esta feature), MUST
  alcancar o indice de busca full-text nem o read-back loop (`cstk
  recall --context`) consumido pelos orquestradores no passo
  PRE-DECISAO — fechando por construcao a superficie de prompt
  injection indireta (LLM01) e envenenamento de memoria (ASI06) via
  label de modelo (fecha CHK013/CHK014).

> **Nota de escopo (Clarifications Session 2026-07-28)**: um FR
> anterior desta secao (`otel_session_id`) foi REMOVIDO do escopo —
> ver Clarifications acima. A coluna nao entra nesta migracao.

### Key Entities

- **WaveModelUsage**: registro no grao onda x modelo, representando
  quanto custo (USD) e quantos tokens um modelo especifico consumiu
  dentro de uma unica onda de uma execucao. O campo `model` armazena a
  string bruta do snapshot OTel, sem normalizacao (Clarifications
  Session 2026-07-28). Relaciona-se com a onda (mesma chave natural
  projeto+feature+onda ja usada pelas demais tabelas de metrica) e,
  indiretamente, com as decisoes de roteamento de modelo daquela onda
  (mesmo modelo, mesma onda) — join best-effort, nao garantido exato.
- **Wave (extensao)**: a entidade de onda ja existente ganha o
  breakdown de tokens por tipo (entrada, saida, cache-leitura,
  cache-criacao), separado por fonte (execucao principal vs
  subagentes). NAO ganha identificador de sessao do OTel — removido do
  escopo (Clarifications Session 2026-07-28).

## Success Criteria

### Measurable Outcomes

- **SC-001**: Para uma onda com dado OTel completo, uma consulta que
  agrega custo e tokens por modelo na knowledge.db retorna valores que
  batem exatamente com a soma dos mesmos campos no `state.json` de
  origem daquela onda, validado contra o corpus real de execucoes
  passadas.
- **SC-002**: 100% das ondas sem snapshot OTel disponivel (execucoes
  antigas ou telemetria indisponivel) sao ingeridas sem erro, com as
  novas colunas e sem nenhuma linha na nova tabela para essas ondas —
  zero valores fabricados.
- **SC-003**: Rodar `--reindex` duas vezes seguidas sobre o mesmo corpus
  produz exatamente o mesmo resultado nas novas dimensoes (sem
  duplicacao nem divergencia de valores).
- **SC-004**: A suite de testes existente que cobre a ingestao da
  knowledge.db permanece 100% verde apos a migracao, incluindo os
  cenarios das dimensoes ja existentes anteriores a esta feature.
- **SC-005**: Com a variavel de ambiente
  `CSTK_SCHEMA_VERSIONS=2,3,4,5,6,7,8,9,10,11,12` setada, `cstk serve`
  continua servindo todas as rotas do painel sem erro `schema-mismatch`
  mesmo com o banco da knowledge.db em schema `v12` — mitigacao valida
  ANTES da publicacao do fix definitivo (bump de
  `DEFAULT_SCHEMA_VERSIONS`) no repo `cstk-panel` (fecha CHK002).

## Delta Requirements

**Skip**: nao ha corpus `docs/specs/current/` com capability documentada
sobre a knowledge.db/ingestao OTel neste projeto (diretorio inexistente
no momento desta spec) — feature aditiva sobre schema versionado, sem
capability ativa documentada para dar delta. — agente-00c-feature-orchestrator, 2026-07-28
