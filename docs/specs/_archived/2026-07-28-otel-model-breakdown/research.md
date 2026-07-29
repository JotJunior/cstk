# Research: OTel Model Breakdown na knowledge.db

**Feature**: `otel-model-breakdown` | **Date**: 2026-07-28 | **Phase**: 0

Todas as decisoes abaixo foram tomadas contra a fonte real (`cli/lib/recall.sh`,
`global/skills/agente-00c-runtime/scripts/state-ondas.sh`, `tests/cstk/test_recall.sh`
e o corpus de `state.json` em disco). Cada afirmacao concreta cita o anchor de onde
foi lida — Principio VI (Veracidade de Dados).

## Decision 1 — Grao da nova dimensao exige loop de extracao proprio

**Decision**: `wave_model_usage` recebe um bloco de extracao jq + loop `for`
independente, no padrao dos loops de `tasks` (`recall.sh:1620`) e `events`
(`recall.sh:1657`) — NAO uma extensao do array posicional de `waves`.

**Rationale**: o loop atual de ondas monta `_isj_wave_lines` como um array
base64 de ESCALARES, uma linha por onda, e le os campos por indice posicional
(`.[0]`..`.[22]`, `recall.sh:1145-1167`). Esse formato e estruturalmente
incapaz de carregar uma colecao de tamanho variavel: `by_model` tem N chaves
por onda (1 a 2 no corpus observado). Tentar acomodar N modelos num array
posicional exigiria serializacao aninhada e quebraria o contrato de leitura
por indice que o loop inteiro assume.

Os loops de `tasks` e `events` ja resolvem exatamente esse formato
(colecao interna -> N linhas), incluindo o idioma `to_entries[]` para iterar
um OBJETO com chaves dinamicas — que e a forma de `by_model` (chave = nome do
modelo). O idioma `to_entries[]` ja e usado no proprio arquivo para
`circular_movement_history` (`recall.sh:1206`).

**Alternatives considered**:
- *Estender o array posicional de waves com um campo JSON serializado*:
  rejeitado — guardaria JSON opaco numa coluna, impedindo `GROUP BY model`,
  que e literalmente o objetivo da US1.
- *Tabela com colunas fixas por modelo* (`cost_opus`, `cost_sonnet`...):
  rejeitado — o conjunto de modelos nao e fechado (`claude-fable-5` e
  `claude-opus-5[1m]` ja aparecem no corpus) e cada modelo novo viraria
  migracao de schema.

## Decision 2 — Idempotencia por UNIQUE + upsert, sem DELETE-then-INSERT

**Decision**: `wave_model_usage` usa `UNIQUE(project, feature, wave, source_id)`
com `ON CONFLICT ... DO UPDATE SET`, identico a todas as demais tabelas de
metrica. NAO adota o padrao DELETE-then-INSERT.

**Rationale**: a preocupacao com linha orfa (modelo que some do conjunto de uma
onda entre duas ingestoes) foi investigada e NAO se materializa, por duas
razoes verificadas:

1. `.otel_usage` e escrito UMA unica vez, em `state-ondas.sh:676`
   (`.otel_usage = $otel`, aplicado sobre `.waves[-1]` no fechamento da onda).
   Nao ha nenhum outro ponto de escrita desse campo no runtime — `grep
   'otel_usage'` em `state-ondas.sh` retorna essa unica linha. Uma vez fechada,
   a onda tem seu `by_model` imutavel; reingerir o mesmo `state.json` produz
   exatamente o mesmo conjunto de chaves.
2. `--reindex` apaga o arquivo do banco inteiro antes de repopular
   (`rm -f -- "$_rx_db" "$_rx_db-wal" "$_rx_db-shm"`, `recall.sh:2398`), entao
   o caminho de reconstrucao total nasce limpo por construcao.

O padrao DELETE-then-INSERT existe no arquivo (`recall.sh:1374`, `1440`, `1568`)
mas serve a um caso diferente: `knowledge_fts` e uma tabela FTS5 virtual SEM
constraint UNIQUE, logo nao suporta `ON CONFLICT` — o DELETE previo e a unica
forma de evitar duplicata la. Aplicar esse padrao a uma tabela relacional com
UNIQUE seria copiar a solucao sem o problema.

**Alternatives considered**:
- *DELETE das linhas da onda antes de reinserir*: rejeitado — adiciona uma
  operacao de escrita por onda para cobrir um cenario que a imutabilidade do
  `otel_usage` ja torna impossivel, e diverge do padrao das outras 9 tabelas.

## Decision 3 — `source_id` = string bruta do modelo

**Decision**: na nova tabela, `wave` = id da onda e `source_id` = nome bruto do
modelo. A constraint `UNIQUE(project, feature, wave, source_id)` passa a
expressar exatamente o grao desejado (projeto x feature x onda x modelo), sem
inventar uma constraint nova.

**Rationale**: todas as tabelas de metrica compartilham o mesmo preambulo de 6
colunas (`project, feature, wave, execution_id, source_ts, source_id`) e a
mesma constraint (`recall.sh:494`, `528`, `544`, `561`, `575`, `602`). O
`source_id` e a chave natural da entidade dentro da onda: `tasks` usa o
`task_id` (`recall.sh:1621`), `events` usa `<event_type>:<timestamp>`
(`recall.sh:1656`). Para `wave_model_usage` a chave natural dentro da onda e o
proprio nome do modelo. Reusar o preambulo mantem a tabela consultavel pelos
mesmos joins das demais.

A coluna `model` e mantida ALEM de `source_id` (mesmo valor) por legibilidade
de consulta — precedente direto em `events`, que guarda `event_type` e
`timestamp` como colunas proprias mesmo compondo `source_id` a partir delas
(`recall.sh:1659`).

**Alternatives considered**:
- *`source_id = <wave_id>:<model>`*: rejeitado — redundante, ja que `wave` e
  coluna da constraint.
- *Chave primaria composta explicita*: rejeitado — divergiria do padrao
  `id INTEGER PRIMARY KEY AUTOINCREMENT` + `UNIQUE(...)` das outras tabelas.

## Decision 4 — Nomenclatura das colunas de breakdown por fonte

**Decision**: 8 colunas aditivas em `waves`, no padrao
`otel_<source>_<token_type>_tokens`:
`otel_main_input_tokens`, `otel_main_output_tokens`,
`otel_main_cache_read_tokens`, `otel_main_cache_creation_tokens`,
`otel_subagent_input_tokens`, `otel_subagent_output_tokens`,
`otel_subagent_cache_read_tokens`, `otel_subagent_cache_creation_tokens`.

**Rationale**: preserva o prefixo `otel_` que ja distingue a origem
telemetrica das colunas `agent_*` (origem: hook de spawn) na mesma tabela
(`recall.sh:513-526`), e o sufixo `_tokens` ja usado em
`otel_total_tokens`/`otel_subagent_tokens`. O infixo de fonte replica a
distincao `main`/`subagent` que ja existe em
`otel_cost_main_usd`/`otel_cost_subagent_usd`.

Nao ha colisao: `otel_subagent_tokens` (existente, total agregado) e
`otel_subagent_input_tokens` (nova, parcela) sao nomes distintos e a antiga
permanece intacta, satisfazendo FR-009.

**Nota de mapeamento**: o JSON de origem usa `cache_read`/`cache_creation`
(snake_case, sem sufixo `_tokens`) — ver a projecao existente em
`recall.sh:1137`, que ja soma `.cache_read` e `.cache_creation` do
`by_source.subagent`. O sufixo `_tokens` e adicionado apenas no nome da coluna,
para coerencia interna do schema; o campo lido do JSON permanece o nome real.

**Alternatives considered**:
- *Espelhar o nome do JSON sem prefixo* (`main_cache_read`): rejeitado —
  perderia o agrupamento visual `otel_*` e colidiria semanticamente com as
  colunas `agent_cache_read_tokens`, que medem outra coisa (agregado de spawns).

## Decision 5 — String bruta de modelo: consequencia documentada

**Decision**: persistir sem normalizacao, conforme ja fechado no clarify
(spec, Clarifications Session 2026-07-28). Esta pesquisa apenas CONFIRMA
empiricamente a consequencia.

**Rationale**: varredura do corpus de `state.json` em
`/Users/jot/Projects/_lab/Jot` retorna 4 strings distintas de modelo:
`claude-fable-5`, `claude-opus-5`, `claude-opus-5[1m]`, `claude-sonnet-5`.

Consequencia concreta e aceita: `claude-opus-5` e `claude-opus-5[1m]` produzem
DUAS linhas distintas na mesma onda, apesar de serem o mesmo modelo-base em
tiers de contexto diferentes. Isso e intencional (tem custo por token distinto);
qualquer agregacao por modelo-base e responsabilidade do CONSUMIDOR da query,
nao da ingestao. Nenhum mapeamento de alias e aplicado — `claude-fable-5` sequer
tem alias no mapa fase->modelo (`references/phase-model-map.txt`).

## Decision 6 — `--reindex` nao precisa de estrategia de limpeza

**Decision**: nenhum tratamento especial de truncamento para a tabela nova no
caminho `--reindex`.

**Rationale**: `recall_mode_reindex` (`recall.sh:2364`) remove o arquivo do
banco e seus sidecars WAL/SHM (`recall.sh:2398`) e re-aplica o schema do zero
antes de varrer os `state.json`. Toda tabela nova nasce vazia nesse caminho,
sem codigo adicional. Reindexar duas vezes produz o mesmo resultado por
construcao — o que satisfaz SC-003 sem trabalho extra.

Esta decisao corrige uma premissa de entrada da onda (que supunha necessidade
de truncar a tabela nova no reindex): a leitura da fonte mostrou que o
comportamento ja esta garantido.

## Decision 7 — Contadores e linha de sumario

**Decision**: adicionar `RECALL_TOTAL_WAVE_MODEL` e estender as duas linhas de
sumario com um 12o contador.

**Rationale**: cada tabela ingerida tem um contador local (`_isj_n_*`)
acumulado num total global (`recall.sh:1735-1737`) e reportado em duas linhas
de sumario com format string fixo: `ingested:` (`recall.sh:2014`) e
`reindexed:` (`recall.sh:2454`). Ambas listam hoje 11 dimensoes. Omitir a nova
dimensao do sumario deixaria a ingestao silenciosa e sem observabilidade.

**Risco verificado**: `grep 'ingested:' tests/cstk/test_recall.sh` retorna ZERO
ocorrencias — nenhum teste faz match exato sobre essa string, entao estender o
formato nao quebra assercao existente.

## Decision 8 — Sem indice secundario

**Decision**: nenhum `CREATE INDEX` para a tabela nova.

**Rationale**: `grep -c 'CREATE INDEX' cli/lib/recall.sh` retorna `0` — o
arquivo nao cria nenhum indice secundario para NENHUMA das 11 tabelas
existentes, apoiando-se apenas nos indices implicitos de PRIMARY KEY e UNIQUE.
Introduzir um indice so para a tabela nova seria divergencia de padrao sem
evidencia de necessidade (o corpus tem ordem de dezenas de linhas por
execucao). O UNIQUE composto ja cobre o filtro por projeto/feature/onda.

## Decision 9 — Bump de `RECALL_SCHEMA_VERSION` e impacto em testes

**Decision**: `RECALL_SCHEMA_VERSION=11` -> `12` (`recall.sh:115`), com
atualizacao das assercoes existentes.

**Rationale**: a constante e gravada em `schema_meta` pelo DDL
(`recall.sh:617`) e usada como gate das migracoes (`recall.sh:672`).

**DOZE** assercoes de teste comparam o valor literal contra `"11"` e DEVEM ser
atualizadas para `"12"` junto do bump, senao a suite quebra (SC-004 exige suite
verde). Linhas em `tests/cstk/test_recall.sh`, obtidas via `grep -n '"11"'`:
`611`, `656`, `678`, `1879`, `2195`, `2285`, `3035`, `3161`, `3216`, `3265`,
`3337`, `3474`.

Atencao a duas armadilhas de edicao nesse conjunto:
- a linha `678` tem mensagem de falha desatualizada (`"esperado 10 apos 2x"`)
  enquanto compara contra `11` — a mensagem ja estava dessincronizada do bump
  anterior. Ao atualizar, corrigir tambem a mensagem.
- varias mensagens embutem o numero como texto (ex. `:3035` diz
  `"esperado '11' (corrente pos-v11)"`); um `sed` cego trocando `11`->`12`
  atingiria tambem esses textos e outros `11` nao relacionados. A edicao deve
  ser dirigida linha a linha, nao global.

## Decision 10 — Deps opcionais: nenhum novo ponto de acoplamento

**Decision**: toda a mudanca fica dentro de `cli/lib/recall.sh`; nenhum outro
arquivo passa a mencionar `sqlite3` ou `jq`.

**Rationale**: o Principio II (amendment 1.1.0) exige que a dep opcional fique
confinada a UM arquivo identificavel por grep. `recall.sh` ja e esse arquivo
para `sqlite3`/`jq`. As guardas de degradacao ja existem no topo dos modos
(`recall_have_sqlite3`, definida em `recall.sh:343`; `recall_have_jq`, em
`recall.sh:346`), invocadas no inicio de cada modo — no reindex em
`recall.sh:2378` e `recall.sh:2382`, no ingest em `recall.sh:1982` e
`recall.sh:1986`. Elas cobrem automaticamente o codigo novo, que roda dentro
desses modos — FR-007 e FR-008 satisfeitos sem codigo adicional.
