# Feature Specification: Knowledge DB Metrics Ingestion

**Feature**: `knowledge-db-metrics`
**Created**: 2026-05-24
**Status**: Draft

> **Triagem (specify ETAPA 0)**: Classificacao = **Feature nova**. Sinais que
> justificam o pipeline SDD completo: (a) tres user stories independentes e
> testaveis (camadas A-derivada, A-derivada-cruzada, B-instrumentacao); (b) duas
> personas distintas (operador do painel, mantenedor do recall.sh); (c)
> invariantes nao-triviais (indice derivado, confinamento de deps, degradacao
> graciosa, schema versionado); (d) backlog multi-sessao com caminho incremental
> obrigatorio (camada A antes de camada B). O SDD se paga.

## Contexto

O toolkit `cstk` mantem uma **memoria de conhecimento cross-feature**:
um indice SQLite global (`~/.claude/cstk/knowledge.db`, FTS5) alimentado por um
hook best-effort no fim de cada onda dos orquestradores autonomos `agente-00c` e
`feature-00c`. Hoje o indice tem **4 tabelas textuais** (`decisions`,
`bloqueios`, `retros`, `skills`) + a virtual table `knowledge_fts` + a tabela de
metadados `schema_meta` (schema_version = 1). Essas tabelas sao otimizadas para
**busca full-text**, nao para **metricas de dashboard**.

Um futuro projeto separado, **`cstk-panel`** (dashboard read-only, **FORA DE
ESCOPO desta feature**), vai consumir essas metricas. Esta feature garante que
**este repositorio seja a fonte da verdade**: a camada de ingestao deve emitir
todas as metricas que o painel precisa, deixando-as ingeridas e consultaveis. O
painel apenas le; nada nesta feature cria o painel.

O `state.json` transacional de cada execucao carrega muito mais dado do que o
indice captura hoje (metricas acumuladas, ciclo de vida de ondas, orcamentos vs
consumo, historico de movimento circular, latencia de bloqueios humanos). Esta
feature expande a ingestao para derivar metricas desse dado **sem nunca tocar o
`state.json`** (somente leitura) e **sem quebrar a propriedade de indice
derivado** (tudo reconstruivel via `cstk recall --reindex`).

> **Decisoes de infraestrutura**: N/A para scheduling/key-rotation/refresh/
> multi-pod/backup — a feature e uma extensao de ingestao local, stateless, sem
> runtime de longo prazo proprio. **Idempotencia** SIM (FR-008): toda escrita no
> indice e idempotente por chave natural, herdando o padrao existente.

## Clarifications

### Session 2026-05-24 (mediacao inline — orquestrador feature-00c)

> O orquestrador roda como subagente sem a tool Agent disponivel; a fase
> clarify degradou para **mediacao inline** (decisao dec-002): as perguntas
> foram geradas e respondidas pelo proprio orquestrador aplicando a heuristica
> de score 0..3, sem spawn de subagente. Cada resposta abaixo virou Decisao
> auditavel no state.json.

- **Q1 — Custo em tokens e obtenivel pelo orquestrador? (FR-021)**
  **R (score 3, empirico):** Nao. O orquestrador roda como subagente do Claude
  Code; a harness nao expoe contabilidade de tokens a scripts/env
  (`env | grep -i token` => vazio). Confirma o caminho de fallback de FR-021:
  documentar a impossibilidade, manter `tool_calls` como proxy de custo, **nao
  inventar** valor de custo em tokens/$.

- **Q2 — Grao exato e campos minimos da entidade Task? (FR-019)**
  **R (score 2):** Grao = uma linha por task por execucao. Campos minimos:
  identificador da task, outcome (pass/fail), testes_rodados, testes_passados,
  lint_ok (booleano), arquivos_tocados (contagem e/ou lista). Chave natural de
  idempotencia = (projeto, feature, execucao_id, task_id), espelhando o padrao
  `UNIQUE(project, feature, wave, source_id)` ja existente. O DDL completo das
  colunas e detalhado na fase plan.

- **Q3 — Conjunto minimo de eventos da timeline para o MVP? (FR-020)**
  **R (score 2):** Conjunto minimo fechado para o MVP: `wave_retry`
  (falha+retry de onda), `lock_contention`, `validation_failed`,
  `schedule_wait`. Cada Evento carrega: event_type (deste conjunto), timestamp,
  proveniencia (execucao/onda). Tipos adicionais sao pos-MVP; o conjunto e
  extensivel sem mudanca de schema (event_type e coluna textual restrita por
  convencao).

## User Scenarios & Testing

### User Story 1 - Metricas estruturais de execucao e onda (camada A) (Priority: P1)

Como **operador do toolkit que vai abrir o cstk-panel**, quero que cada execucao
do orquestrador e cada onda dentro dela sejam ingeridas como **registros
estruturados** (status, motivo de termino, etapa corrente, duracoes, contagens
acumuladas, wallclock e tool calls por onda), para que o painel possa exibir
saude e progresso de execucoes sem reprocessar o `state.json` cru.

**Why this priority**: E o MVP. Sem grao estruturado de execucao e onda, o painel
nao tem o que mostrar alem de busca textual. E a fatia de **menor risco** —
mexe somente em `recall.sh` (camada A), nao toca os orquestradores. Entrega valor
isolado: mesmo que P2 e P3 nunca sejam implementadas, o painel ja consegue
dashboards de status/progresso/duracao.

**Independent Test**: Rodar a ingestao (`cstk recall --ingest`) sobre um
`state.json` fixture com 1 execucao concluida e N ondas; consultar o indice e
verificar que existe **1 linha** na entidade Execucao com status/duracao/metricas
acumuladas corretos e **N linhas** na entidade Onda com wallclock/tool_calls/
etapas corretos. Rodar `cstk recall --reindex` do zero e confirmar que as mesmas
linhas sao reconstruidas identicamente.

**Acceptance Scenarios**:

1. **Given** um `state.json` de execucao concluida com `metricas_acumuladas`
   populadas, **When** a ingestao roda, **Then** existe exatamente uma linha de
   Execucao com status, motivo_termino, etapa_corrente, iniciada_em,
   terminada_em, duracao derivada (terminada_em − iniciada_em) e todas as
   contagens de `metricas_acumuladas`.
2. **Given** um `state.json` com 3 ondas em `.ondas[]`, **When** a ingestao roda,
   **Then** existem 3 linhas de Onda, cada uma com wave_id, etapa(s), inicio/fim,
   wallclock_seconds, tool_calls, motivo_termino, n_etapas e n_skills corretos.
3. **Given** uma execucao ainda `em_andamento` (sem terminada_em), **When** a
   ingestao roda, **Then** a linha de Execucao existe com duracao nula/aberta e
   nao ha erro nem aborto.
4. **Given** uma execucao ja ingerida, **When** a ingestao roda de novo (re-run),
   **Then** o numero de linhas de Execucao/Onda nao muda (idempotencia por chave
   natural) e os valores refletem o estado mais recente.

---

### User Story 2 - Sinais de alerta e metricas derivadas (camada A) (Priority: P2)

Como **operador do painel**, quero que sinais de saude operacional sejam
derivados do dado ja existente — **breach de orcamento** (consumo vs thresholds),
**movimento circular** (loop/struggle), **latencia humana** (tempo entre
disparo e resposta de bloqueios), **taxa de auto-resolucao de clarify** e o
**mix de roteamento de modelos** — para que o painel possa destacar execucoes
problematicas sem que eu precise ler o `state.json`.

**Why this priority**: Entrega o "alerta" do dashboard (o que precisa de atencao).
Depende conceitualmente de P1 (precisa do grao de execucao/onda para cruzar), por
isso P2. Ainda e camada A (somente `recall.sh`, baixo risco). Reusa logica
existente em vez de duplica-la (model routing).

**Independent Test**: Sobre um fixture com `orcamentos` (thresholds) e ondas que
excedem `tool_calls_threshold_onda`, mais `historico_movimento_circular[]`
populado e `bloqueios_humanos[]` com timestamps de disparo e resposta, consultar
o indice e verificar: (a) flag/contagem de breach de orcamento correta; (b)
sinais de movimento circular ingeridos; (c) latencia humana = respondido_em −
disparado_em por bloqueio; (d) clarify auto-resolution rate derivado de bloqueios
vs decisoes score>=2; (e) mix de roteamento de modelos identico ao que
`model-routing-report.sh aggregate` ja produz (sem duplicar a logica).

**Acceptance Scenarios**:

1. **Given** uma onda cujo `tool_calls` excede `tool_calls_threshold_onda` (ou
   wallclock excede o threshold, ou ciclos perto de `ciclos_max_por_etapa`, ou
   profundidade perto de `recursividade_max`), **When** a ingestao roda, **Then**
   um sinal de breach de orcamento e registrado/consultavel com o tipo de breach
   e os valores consumido vs threshold.
2. **Given** `historico_movimento_circular[]` com entradas, **When** a ingestao
   roda, **Then** cada entrada de movimento circular e ingerida como sinal
   consultavel (proveniencia: execucao/onda/data).
3. **Given** bloqueios humanos com `disparado_em` e `respondido_em`, **When** a
   ingestao roda, **Then** a latencia humana por bloqueio e derivavel
   (respondido_em − disparado_em) e bloqueios sem resposta aparecem como
   pendentes (latencia aberta).
4. **Given** uma execucao com X bloqueios humanos e Y decisoes score>=2 na fase
   clarify, **When** a ingestao roda, **Then** a taxa de auto-resolucao de
   clarify e derivavel da relacao entre decisoes autonomas e escalas humanas.
5. **Given** decisoes de selecao de modelo (`model-selector`/model-routing),
   **When** o mix de roteamento e consultado, **Then** os numeros sao consistentes
   com `model-routing-report.sh aggregate` (a logica de agregacao e **reusada**,
   nao reescrita).

---

### User Story 3 - Instrumentacao nova: tasks e timeline de eventos (camada B) (Priority: P3)

Como **operador do painel**, quero ver o **resultado de cada task** executada
(pass/fail, testes rodados vs passados, lint ok, arquivos tocados) e uma
**timeline de eventos/incidentes** (falha+retry de onda, lock contention,
validacao reprovada, esperas de schedule), para que o painel mostre granularidade
de execucao e uma narrativa cronologica do que aconteceu.

**Why this priority**: E a fatia de **maior risco e maior blast radius** — exige
que os orquestradores `agente-00c`/`feature-00c` (codigo load-bearing) **gravem
campos novos no `state.json`** antes que a ingestao possa derива-los. Deve vir
**depois** das camadas A (P1+P2) estarem solidas. Tem valor isolado: granularidade
de task e timeline sao dashboards distintos dos de execucao/onda.

**Independent Test**: (Pre-condicao: instrumentacao dos orquestradores gravando
outcome de task e eventos no `state.json`.) Sobre um fixture com tasks de
execute-task/review-task e uma sequencia de eventos, rodar a ingestao e verificar
que existem linhas de Task com outcome/testes/lint/arquivos e linhas de Evento
com tipo/timestamp/proveniencia, na ordem cronologica. Confirmar reconstrucao via
`--reindex`.

**Acceptance Scenarios**:

1. **Given** um `state.json` instrumentado com outcome de task (pass/fail,
   testes rodados/passados, lint ok, arquivos tocados), **When** a ingestao roda,
   **Then** existe uma linha de Task por task com esses campos.
2. **Given** um `state.json` com eventos/incidentes registrados (falha+retry de
   onda, lock contention, validacao reprovada, schedule wait), **When** a
   ingestao roda, **Then** existe uma linha de Evento por ocorrencia, com tipo,
   timestamp e proveniencia, consultavel em ordem cronologica.
3. **Given** um `state.json` **nao** instrumentado (execucao antiga, sem os campos
   novos), **When** a ingestao roda, **Then** as entidades Task/Evento ficam
   vazias para aquela execucao, sem erro nem aborto (compatibilidade retroativa).

---

### Edge Cases

- **Sem `sqlite3` ou `jq` no PATH**: a ingestao e o reindex saem com status de
  sucesso emitindo apenas aviso em stderr; nenhuma onda do orquestrador e abortada
  (Principio II — graceful fallback).
- **`state.json` ausente, ilegivel ou corrompido**: ingestao daquele arquivo e
  pulada com aviso; reindex continua com os demais arquivos.
- **Execucao em andamento (campos terminais nulos)**: linhas sao criadas com os
  campos disponiveis; campos derivados que dependem de termino (ex: duracao total)
  ficam nulos/abertos sem erro.
- **Re-ingestao da mesma execucao/onda**: idempotente — sem duplicar linhas;
  valores refletem o estado mais recente.
- **Schema antigo no DB (schema_version = 1) encontrado em disco**: a aplicacao
  do schema novo e idempotente (cria tabelas ausentes) e o `schema_version` e
  atualizado; nenhuma tabela existente perde dado.
- **Texto livre com segredo**: campos de texto livre (ex: mensagens, contextos)
  passam por `secrets-filter` na ingestao; campos estruturados/numericos nao.
- **Token cost indisponivel na harness**: se a harness nao expoe uso de tokens ao
  orquestrador, o custo em tokens/$ NAO e inventado; `tool_calls` permanece como
  proxy documentado (ver FR-021).

## Requirements

### Functional Requirements

#### Guarda-corpos (invariantes — todas as camadas)

- **FR-001**: O indice de conhecimento MUST permanecer um **indice puramente
  derivado**. Toda tabela/entidade nova MUST ser inteiramente reconstruivel a
  partir do `state.json` (e do historico de estado) via `cstk recall --reindex`.
- **FR-002**: A ingestao MUST ler o `state.json` transacional somente em modo
  leitura; MUST NOT modificar o `state.json` sob nenhuma circunstancia.
- **FR-003**: A ingestao e o reindex MUST ser **best-effort**: na ausencia de
  `sqlite3` ou `jq`, ou em qualquer falha da camada de conhecimento, MUST terminar
  com status de sucesso (exit 0) + aviso em stderr, **sem abortar** a onda do
  orquestrador nem a ingestao em si.
- **FR-004**: A dependencia de `sqlite3` e de `secrets-filter` MUST permanecer
  **confinada** ao componente de ingestao do indice (`recall.sh`); nenhum outro
  componente do `cstk` pode passar a depender delas por causa desta feature.
- **FR-005**: O `cstk-panel` MUST permanecer fora de escopo. Esta feature MUST NOT
  criar painel, UI ou endpoint de leitura; entrega apenas dados ingeridos e
  consultaveis no indice.
- **FR-006**: Texto livre ingerido MUST passar pelo filtro de segredos
  (`secrets-filter`) antes de ser persistido; dado estruturado/numerico (contagens,
  timestamps, status, ids) MUST ser ingerido sem esse filtro.
- **FR-007**: O `schema_version` do indice MUST ser incrementado (de 1 para 2)
  quando as entidades novas forem introduzidas, e o caminho de `--reindex` MUST
  ser atualizado para popular as entidades novas de forma idempotente.
- **FR-008**: Toda escrita de entidade nova MUST ser **idempotente** por chave
  natural (proveniencia: projeto + feature + onda/execucao + identificador de
  origem), de modo que re-ingestao nao duplique linhas.
- **FR-009**: Todo script `.sh` novo introduzido por esta feature MUST ter um
  teste correspondente (convencao `--check-coverage` do repo); a cobertura da
  ingestao das entidades novas MUST viver no harness de teste do indice
  (test do `recall`).
- **FR-010**: A entrega MUST seguir caminho incremental: a **camada A** (US1 + US2,
  somente `recall.sh`, baixo risco) MUST ser concluida e validada **antes** da
  **camada B** (US3, instrumentacao dos orquestradores, alto risco).

#### Camada A — ingestao derivada (US1 + US2)

- **FR-011**: O sistema MUST ingerir uma entidade **Execucao** (grao = execucao)
  com: status, motivo_termino, etapa_corrente, iniciada_em, terminada_em, duracao
  derivada, e as contagens de `metricas_acumuladas` (ondas_total,
  tool_calls_total, tempo_wallclock_total_segundos, subagentes_spawned,
  profundidade_max_atingida, decisoes_total, bloqueios_humanos_total,
  sugestoes_skills_globais_total, issues_toolkit_abertas) e stack_sugerida.
- **FR-012**: O sistema MUST ingerir uma entidade **Onda** (grao = onda, de
  `.ondas[]`) com: wave_id, etapa(s) executadas, inicio, fim, wallclock_seconds,
  tool_calls, motivo_termino, n_etapas e n_skills (numero de skills invocadas).
- **FR-013**: O sistema MUST ingerir cada entrada de
  `historico_movimento_circular[]` como **sinal de alerta** consultavel, com
  proveniencia (execucao/onda/data).
- **FR-014**: O sistema MUST derivar **sinais de breach de orcamento** cruzando os
  thresholds de `orcamentos` (tool_calls_threshold_onda,
  wallclock_threshold_segundos, estado_size_threshold_bytes, ciclos_max_por_etapa,
  recursividade_max) com o consumo real por onda/execucao, registrando o tipo de
  breach e os valores consumido vs threshold.
- **FR-015**: O sistema MUST tornar derivavel a **latencia humana** por bloqueio
  (tempo entre disparo e resposta de cada bloqueio em `bloqueios_humanos[]`),
  incluindo bloqueios sem resposta como latencia aberta/pendente.
- **FR-016**: O sistema MUST tornar derivavel a **taxa de auto-resolucao de
  clarify** a partir da relacao entre decisoes autonomas (score >= 2) e escalas a
  humano (bloqueios) na fase clarify.
- **FR-017**: O sistema MUST expor o **mix de roteamento de modelos** **reusando**
  a logica de agregacao existente (`model-routing-report.sh`); MUST NOT duplicar
  essa logica de agregacao.

#### Camada B — instrumentacao nova (US3)

- **FR-018**: Os orquestradores `agente-00c`/`feature-00c` MUST gravar no
  `state.json` o **outcome de cada task** (pass/fail, testes rodados, testes
  passados, lint ok, arquivos tocados) durante execute-task/review-task, **antes**
  que a ingestao possa deriva-lo.
- **FR-019**: O sistema MUST ingerir uma entidade **Task** (grao = task) a partir
  dos campos gravados em FR-018.
- **FR-020**: Os orquestradores MUST gravar e o sistema MUST ingerir uma entidade
  **Evento** (timeline cronologica) cobrindo no minimo: falha+retry de onda, lock
  contention, validacao reprovada e espera de schedule; cada evento com tipo,
  timestamp e proveniencia.
- **FR-021**: Se a harness expoe uso de tokens ao orquestrador, o sistema SHOULD
  ingerir custo em tokens; **se nao expoe**, o sistema MUST documentar a
  impossibilidade explicitamente e manter `tool_calls` como proxy — **sem
  inventar dado de custo**.
- **FR-022**: As entidades de camada B MUST ser retro-compativeis: um `state.json`
  nao-instrumentado (execucao antiga) MUST produzir entidades Task/Evento vazias
  para aquela execucao, sem erro.

### Key Entities

- **Execucao**: uma execucao completa do orquestrador (grao mais grosso).
  Atributos: status, motivo de termino, etapa corrente, instantes de inicio/fim,
  duracao derivada, contagens acumuladas (ondas, tool calls, wallclock,
  subagentes, profundidade, decisoes, bloqueios, sugestoes, issues), stack
  sugerida. Proveniencia: projeto, feature, execucao_id.
- **Onda**: uma onda dentro de uma execucao. Atributos: identificador da onda,
  etapas executadas, instantes de inicio/fim, wallclock, tool calls, motivo de
  termino, contagem de etapas e de skills invocadas. Relaciona-se a uma Execucao.
- **SinalDeAlerta**: um indicador de saude operacional derivado — entrada de
  movimento circular OU breach de orcamento (tipo + consumido vs threshold).
  Relaciona-se a uma Execucao/Onda.
- **Task** (camada B): resultado de uma task executada. Atributos: outcome
  (pass/fail), testes rodados, testes passados, lint ok, arquivos tocados.
  Relaciona-se a uma Execucao/Onda. Depende de instrumentacao previa.
- **Evento** (camada B): uma ocorrencia na timeline da execucao. Atributos: tipo
  (falha+retry, lock contention, validacao reprovada, schedule wait), timestamp,
  proveniencia. Depende de instrumentacao previa.
- **MetricaDerivada**: valor calculado a partir do dado existente — latencia
  humana por bloqueio, taxa de auto-resolucao de clarify, mix de roteamento de
  modelos. Pode ser materializada ou computada na consulta; nao e fonte primaria.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Apos a ingestao de uma execucao concluida com N ondas, o indice
  contem exatamente 1 registro de Execucao e N registros de Onda, com 100% dos
  campos estruturais de US1 preenchidos a partir do `state.json`.
- **SC-002**: Reconstruir o indice do zero (`cstk recall --reindex`) produz
  exatamente o mesmo conjunto de registros de Execucao, Onda e SinalDeAlerta que a
  ingestao incremental — 0 divergencias (propriedade de indice derivado).
- **SC-003**: A ingestao e o reindex terminam com status de sucesso e nao abortam
  nenhuma onda do orquestrador em 100% dos cenarios de dependencia ausente
  (`sqlite3` e/ou `jq` indisponiveis) e de `state.json` corrompido.
- **SC-004**: Re-ingerir a mesma execucao qualquer numero de vezes nao altera a
  contagem de registros de nenhuma entidade (idempotencia: delta de linhas = 0).
- **SC-005**: 100% das execucoes que excedem qualquer threshold de orcamento
  produzem ao menos um SinalDeAlerta de breach consultavel, com o valor consumido
  e o threshold correspondente.
- **SC-006**: O mix de roteamento de modelos consultado a partir do indice e
  identico ao produzido pela ferramenta de agregacao existente (0 divergencias),
  confirmando reuso e nao duplicacao de logica.
- **SC-007**: Toda string de texto livre persistida nas entidades novas passou
  pelo filtro de segredos (verificavel: nenhum padrao de segredo conhecido
  presente no indice apos ingestao de um fixture com segredos plantados).
- **SC-008**: A camada A (US1+US2) e entregue e validada por testes automatizados
  antes de qualquer alteracao nos orquestradores (camada B), comprovavel pela
  ordem de conclusao do backlog.
- **SC-009**: Para um `state.json` nao-instrumentado, a ingestao das entidades de
  camada B produz 0 registros e 0 erros (retro-compatibilidade).
- **SC-010**: A decisao sobre custo em tokens e registrada de forma explicita no
  artefato da feature (obtenivel + ingerido, OU impossivel + `tool_calls` como
  proxy documentado); em nenhum caso ha valor de custo inventado.
