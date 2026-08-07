# Research: Loose Usage Capture

Documento produzido no Phase 0 do `/plan`. Resolve os `NEEDS CLARIFICATION` do
Technical Context antes do design.

**Regra de veracidade (Constitution VI)**: cada decisao abaixo cita a fonte
real consultada (arquivo + linha, ou saida de comando de fato executada).
Interfaces que ainda NAO existem estao marcadas `[PROPOSTA — a validar na
implementacao]`. Inferencias estao rotuladas como inferencia, nunca como fato.

---

## Decision 1: Fonte da metrica de consumo avulso

**Decision**: reusar a telemetria OTel nativa do Claude Code (exporter
Prometheus local) pelo MESMO caminho ja usado por
`global/skills/agente-00c-runtime/scripts/otel-usage.sh` — sem nova fonte,
sem nova dependencia de rede, sem API remota.

**Rationale**: a fonte ja esta em producao e documentada no cabecalho do
proprio script (linhas 31-38): pre-requisito `CLAUDE_CODE_ENABLE_TELEMETRY=1`
+ `OTEL_METRICS_EXPORTER=prometheus`; o exporter sobe um HTTP local em
`127.0.0.1:9464/metrics` (override por `CSTK_OTEL_ENDPOINT`, linha 127) e
"nada trafega para fora da maquina". O formato das linhas consumidas
(`claude_code_cost_usage_total{...}` / `claude_code_token_usage_total{...}`)
esta declarado como "verificado empiricamente contra Claude Code 2.1.220"
(linhas 159-161).

**Alternatives considered**:
- *Usage & Cost Admin API da Anthropic*: rejeitada — o cabecalho do
  `otel-usage.sh` (linhas 16-19) registra que exige Admin key
  (`sk-ant-admin01-...`), e indisponivel para contas individuais e nao tem
  dimensao de sessao. Alem disso violaria o Principio IV (rede para fora).
- *Parsing de transcripts JSONL de sessao*: rejeitada — e o caminho de
  BACKFILL retroativo ja implementado em `wave-usage-report.sh backfill`
  (cabecalho, subcomando `backfill --transcript PATH`), adequado a
  reconstrucao historica, nao a captura periodica ao vivo exigida por FR-003.

---

## Decision 2: Ancora de identidade — processo + projeto, nunca `session_id`

**Decision**: a chave de atribuicao e `(endpoint do exporter do processo,
diretorio de trabalho do projeto)`, com o PID dono da porta como reforco
quando obtenivel. O `session_id` emitido pelo exporter NAO e usado como
identidade.

**Rationale**: o bloco `MULTIPLAS SESSOES NO MESMO EXPORTER` do
`otel-usage.sh` (linhas 81-103) registra o incidente real de 2026-07-28 e
conclui textualmente: *"o session_id do OTel nao serve como IDENTIDADE da
sessao corrente (label ja observado apontando para outra sessao/projeto), por
isso NAO ha match contra env — apenas deteccao de crescimento por sessao"*.
A spec ratificou isso em FR-002.

Evidencia empirica coletada nesta onda (probe de ambiente executado no
projeto-alvo): `CSTK_OTEL_ENDPOINT=http://127.0.0.1:55525/metrics` — porta
DINAMICA por processo, atribuida pelo wrapper `claude()` de `~/.zshrc`
(linhas 16-21: `OTEL_EXPORTER_PROMETHEUS_PORT=$_otel_port` +
`CSTK_OTEL_ENDPOINT="http://127.0.0.1:${_otel_port}/metrics"`). Com porta por
processo, o endpoint E um discriminador de processo estavel enquanto o
processo vive.

**Alternatives considered**:
- *`session_id` do exporter*: rejeitada pela evidencia acima (FR-002).
- *PID isolado como chave*: rejeitada — PID e reciclado pelo SO; sozinho nao
  distingue sessoes sequenciais. Usado apenas como reforco/desempate.
- *Somente o `cwd`*: rejeitada — nao separa duas sessoes simultaneas no mesmo
  projeto (Edge Case explicito da spec: "duas janelas/terminais abertos").

---

## Decision 3: `OTEL_METRICS_EXPORTER` NAO e observavel no contexto do hook

**Decision**: o hook de captura NAO pode gatear o opt-in por
`OTEL_METRICS_EXPORTER`; deve gatear por presenca de `CSTK_OTEL_ENDPOINT` +
probe do endpoint (`otel-usage.sh available`). Por consequencia,
`otel-usage.sh preflight` NAO serve como gate no contexto de hook.

**Rationale**: probe empirico executado nesta onda, em subprocesso do harness
(mesmo tipo de contexto em que um hook roda):

```
CSTK_OTEL_ENDPOINT=[http://127.0.0.1:55525/metrics]
CLAUDE_CODE_ENABLE_TELEMETRY=[1]
OTEL_METRICS_EXPORTER=[<unset>]
OTEL_EXPORTER_PROMETHEUS_PORT=[<unset>]
```

E, na sequencia, `otel-usage.sh preflight` respondeu
`status=disabled endpoint=http://127.0.0.1:55525/metrics` (exit 0) — um
falso "desabilitado", ja que `~/.zshrc` linhas 9-10 de fato exporta
`CLAUDE_CODE_ENABLE_TELEMETRY=1` e `OTEL_METRICS_EXPORTER=prometheus`.
O gate de `_ou_cmd_preflight` (otel-usage.sh linhas 479-483) exige as DUAS
variaveis e retorna `disabled` quando qualquer uma falta.

*Inferencia (rotulada como tal, nao afirmada como fato)*: as duas variaveis
ausentes sao exatamente as de prefixo `OTEL_*`, enquanto as duas presentes
nao tem esse prefixo — o padrao sugere que o harness remove variaveis
`OTEL_*` do ambiente dos subprocessos de tool/hook. A CAUSA nao foi
confirmada em fonte oficial; o que esta confirmado e a OBSERVACAO acima.
Task de implementacao deve reconfirmar o probe no contexto real do hook
(`PostToolUse`), nao apenas no de tool call.

**Alternatives considered**:
- *Gatear por `preflight`*: rejeitada pela evidencia — produziria zero
  captura para operadores com telemetria de fato ligada.
- *Gatear so por `CLAUDE_CODE_ENABLE_TELEMETRY`*: insuficiente — indica
  intencao, nao disponibilidade do endpoint por processo (a spec exige nunca
  fabricar; endpoint indisponivel = "nao medido", Edge Case explicito).

---

## Decision 4: Cadencia — throttle por intervalo dentro de um hook `PostToolUse`

**Decision**: o hook dispara em `PostToolUse` com matcher `*` (dec-006), mas
so executa scrape quando transcorreu o intervalo minimo desde a ultima
captura do processo (default proposto: **300 s**, override por env
`CSTK_LOOSE_USAGE_INTERVAL_S` `[PROPOSTA]`). Fora do intervalo: no-op de
custo O(1) (um `stat`/teste de arquivo), sem rede.

**Rationale**: o hook `posttooluse-tool-call-tick.sh` dispara a cada tool
call (settings.snippet.json, matcher `*`). Um scrape HTTP por tool call seria
custo desproporcional; `_ou_scrape` usa `--max-time 3` (otel-usage.sh linha
150), logo o pior caso por tick e 3 s — inaceitavel a cada call. O throttle
converte o gatilho "por tool call" no gatilho "periodico" que FR-003 pede,
e a durabilidade de US3 vem de cada captura ja persistir em disco.

O default de 300 s e **politica de design**, nao dado factual — escolhido
por analogia ao granularidade util de custo (5 min) e por limitar a perda
maxima por encerramento abrupto a um intervalo. Ajustavel sem mudanca de
contrato.

**Alternatives considered**:
- *Hook `SessionEnd` apenas*: rejeitada pela spec (US3 / FR-003) — perde
  exatamente as sessoes longas encerradas de forma abrupta.
- *Agendador externo (cron/launchd)*: rejeitada por FR-003-INFRA-SCHED, que
  determina cadencia por eventos do harness.
- *Hook em matcher restrito (ex. so `Bash`)*: rejeitada — sessoes avulsas de
  leitura/exploracao usariam poucas `Bash` e ficariam sub-amostradas.

---

## Decision 5: Polaridade invertida da deteccao de execucao ativa (FR-004)

**Decision**: reusar `_hook-active-exec.sh` com a semantica INVERTIDA
(dec-006): `exit 1` (inativa) e o unico caso que captura; `exit 0` (ativa),
`exit 2` (indeterminada) e `exit 3` (uso incorreto) sao todos no-op.

**Rationale**: o contrato do helper esta declarado no seu cabecalho (linhas
31-36): `0 = ativa` com stdout `"<execution_kind>\t<state_dir>\t<backend>"`,
`1 = inativa`, `2 = indeterminada`, `3 = uso incorreto`, com "stderr SEMPRE
vazio". Tratar `indeterminada` como se fosse `inativa` fabricaria consumo
avulso a partir de incerteza — violacao direta do Principio VI. A assimetria
e deliberada: na duvida, **subconta**, nunca superconta (SC-002 exige 100% de
exclusao das janelas de pipeline; nao exige 100% de captura do avulso).

Consequencia sobre o pre-check inline do molde: em
`posttooluse-tool-call-tick.sh` (linhas 85-106) o pre-check
`_ptt_precheck_active_scope` existe para SAIR barato quando nao ha nenhum
state dir. Sob polaridade invertida, "nenhum state dir" e justamente o caso
que DEVE capturar — o pre-check nao pode ser copiado como esta. Ele vira o
atalho oposto: ausencia total de `state.json`/`state.db` sob
`.claude/agente-00c-state/` e `.claude/feature-00c-state/*/` conclui
`inativa` sem sequer resolver/sourcear o helper (mais barato ainda que o
molde).

**Alternatives considered**:
- *Filtro pos-hoc por janela de tempo* (comparar timestamps de onda contra
  timestamps de captura): rejeitada na etapa clarify (registrada em
  Clarifications da spec) — exigiria correlacao temporal entre relogios de
  duas fontes e produziria zona cinzenta na fronteira; a checagem de execucao
  ativa ja e o discriminador exato.
- *Tratar `indeterminada` como `inativa`*: rejeitada por Constitution VI.

---

## Decision 6: Segmentacao — descartar o trecho aberto na transicao para "ativa"

**Decision**: o consumo de um processo e modelado como uma sequencia de
**segmentos avulsos**. Cada segmento tem um snapshot inicial e um snapshot
corrente, e e persistido a cada tick. Ao detectar execucao de pipeline ativa,
o segmento corrente e FECHADO no ultimo valor ja persistido e o trecho ainda
nao persistido (do ultimo tick ate a deteccao) e **descartado**. Quando a
execucao termina, o proximo tick abre um segmento novo (FR-010).

**Rationale**: e a unica politica que satisfaz SC-002 literalmente ("100% do
consumo que ocorreu durante janelas de execucao de pipeline ativa e excluido
do total avulso"). Fechar o segmento COM um scrape no momento da deteccao
seria mais preciso para o avulso, mas o primeiro tick com execucao ativa
acontece necessariamente DEPOIS de a onda ja ter consumido tokens — parte do
consumo de pipeline entraria no avulso e SC-002 falharia. O erro da politica
escolhida e sempre no sentido seguro: subconta o avulso em no maximo um
intervalo de captura por transicao.

**Alternatives considered**:
- *Fechar com scrape na deteccao*: rejeitada (viola SC-002, acima).
- *Um unico segmento por processo, com subtracao posterior do consumo de
  pipeline*: rejeitada — exigiria subtrair `wave_model_usage` do total do
  processo, e as duas fontes tem granularidade e guardas de atribuicao
  diferentes; subtracao entre bases heterogeneas produz numero sem fonte
  unica rastreavel (Principio VI).

---

## Decision 7: Persistencia em duas camadas — sidecar de arquivo + indice SQLite

**Decision**: o hook escreve APENAS arquivos (snapshots TSV + metadados) sob
`~/.claude/cstk/loose-usage/`. A insercao no `knowledge.db` acontece na
camada CLI (ingest-on-read), nunca no hook.

**Rationale**: tres motivos, todos com fonte:
1. **Confinamento de dependencia (Constitution II)**: `sqlite3` no CLI esta
   confinado a `cli/lib/recall.sh` (condicao (b) do carve-out 1.1.0). Um hook
   que abrisse o `knowledge.db` espalharia a dep para um segundo arquivo.
2. **Nao-interferencia**: o cabecalho de `posttooluse-tool-call-tick.sh`
   (linhas 22-35) impoe a REGRA DURA de o hook nunca fazer read-modify-write
   de estado compartilhado, justamente porque `PostToolUse` dispara
   concorrente as tool calls; o padrao prescrito e sidecar append-only e
   agregacao posterior. Aqui vale o mesmo, com o `knowledge.db` global no
   lugar do state.
3. **Durabilidade (FR-008)**: arquivo em disco sobrevive ao processo por
   construcao; a ingestao pode ocorrer arbitrariamente depois, inclusive
   apos encerramento abrupto (US3).

Reuso literal: `otel-usage.sh snapshot --state-dir DIR --phase start|end`
grava `DIR/otel-<phase>.tsv` (linhas 265-270) e `delta --state-dir DIR` le
`DIR/otel-start.tsv` + `DIR/otel-end.tsv` (linhas 296-297). Apontando
`--state-dir` para o diretorio do segmento, os dois subcomandos servem a
captura avulsa **sem nenhuma alteracao** — inclusive herdando as guardas de
atribuicao (mais de uma sessao cresceu, processo do exporter trocou, formato
antigo) que imprimem `null` em vez de numero duvidoso (linhas 355-366).

**Alternatives considered**:
- *Hook grava direto no `knowledge.db`*: rejeitada pelos 3 motivos acima.
- *Sidecar JSONL append-only com deltas incrementais* (molde de
  `wave-agent-usage.jsonl`): rejeitada — somar incrementos exige que nenhum
  tick se perca; com snapshots cumulativos, um tick perdido nao corrompe o
  acumulado (o proximo tick recupera).

---

## Decision 8: Migracao de schema v12 -> v13, aditiva, tabela nova

**Decision**: bump de `RECALL_SCHEMA_VERSION` de 12 para 13 e uma tabela nova
no DDL de `recall_schema_ddl`. Nenhum `ALTER TABLE`, nenhum `DROP`, nenhuma
alteracao em tabela existente.

**Rationale**: fontes diretas em `cli/lib/recall.sh` — `RECALL_SCHEMA_VERSION=12`
(linha 128); o DDL usa `CREATE TABLE IF NOT EXISTS` para todas as tabelas
(linhas 417-637) e grava a versao em `schema_meta` (linhas 648-653); as
migracoes v7->v12 em `recall_apply_schema` (linhas 695-827) usam
`ALTER TABLE ADD COLUMN` guardado por `PRAGMA table_info` apenas para colunas
novas em tabela EXISTENTE. O precedente literal para tabela nova esta no
comentario da v11->v12 (linhas 810-811): *"`wave_model_usage` NAO precisa de
ALTER: e tabela nova, coberta pelo `CREATE TABLE IF NOT EXISTS` do DDL"* — a
tabela de consumo avulso segue exatamente esse caminho.

Estado real verificado nesta onda: `sqlite3 ~/.claude/cstk/knowledge.db
"SELECT value FROM schema_meta WHERE key='schema_version';"` retornou `12`, e
`.tables` listou `wave_model_usage` entre as tabelas existentes — a base do
operador esta em v12, sem a tabela nova.

**Alternatives considered**:
- *Reusar `wave_model_usage`*: rejeitada na etapa clarify (dec-005). Fonte do
  impedimento: DDL em `cli/lib/recall.sh` linhas 625-637 — `feature TEXT NOT
  NULL`, `wave TEXT NOT NULL`, `execution_id TEXT NOT NULL` e
  `UNIQUE(project, feature, wave, source_id)`. Consumo avulso nao tem
  feature, onda nem execucao; preenche-los exigiria valores sentinela
  inventados (Principio VI).
- *Base SQLite separada so para uso avulso*: rejeitada — quebraria a
  comparacao avulso-vs-pipeline (FR-009/SC-005), que precisa das duas
  categorias na mesma base para um unico `SELECT`.

---

## Decision 9: Superficie de consulta — subcomando `cstk usage` `[PROPOSTA]`

**Decision**: subcomando novo `cstk usage`, com lib propria em
`cli/lib/usage.sh` que delega TODO acesso a SQLite aos helpers ja existentes
de `cli/lib/recall.sh`.

**Rationale**: dec-007 fixou "subcomando do `cstk` CLI"; a lista de
subcomandos atuais (dispatch em `cli/cstk`) e `install|update|self-update|
list|doctor|session|serve|recall|show-tip|hooks|state|mcp` — `usage` esta
livre. A delegacao a `recall.sh` preserva a condicao (b) do carve-out do
Principio II (dep confinada a um unico arquivo identificavel): `grep -l
sqlite3 cli/lib/*.sh` deve continuar retornando apenas `recall.sh`.

**Alternatives considered**:
- *Flag nova em `cstk recall`*: rejeitada — `recall` e busca de conhecimento
  (FTS sobre decisoes/bloqueios/memorias); consumo agregado e outra intencao
  de uso e polui a superficie ja documentada em `contracts/cstk-recall.md`.
- *Exposicao no painel web*: fora de escopo por decisao de clarify (dec-007).

---

## Decision 10: Provisionamento opt-in separado dos guard hooks

**Decision**: flag nova `cstk hooks install --with-loose-usage` `[PROPOSTA]`,
default DESLIGADA, com snippet de registro em arquivo separado. O hook de
captura NUNCA entra em `apply_guard_hooks()` por default.

**Rationale**: dec-008. Fonte do estado atual: `apply_guard_hooks()`
(`cli/lib/hooks.sh` linha ~197) copia `pretooluse-bash-guard.sh` +
`posttooluse-tool-call-tick.sh` + `posttooluse-agent-usage.sh` e mescla
`global/skills/agente-00c-runtime/hooks/settings.snippet.json`, cujo conteudo
registra exatamente esses tres hooks. Os tres sao obrigatorios/fail-closed ou
metricas internas da pipeline; a captura avulsa observa a sessao do operador
FORA da pipeline e por isso precisa de consentimento explicito (FR-006).

**Alternatives considered**:
- *Bundlar no snippet existente*: rejeitada por FR-006 + dec-008 — tornaria a
  captura efeito colateral de instalar guardas de seguranca.
- *Variavel de ambiente como unico gate*: insuficiente — sem o hook
  provisionado nao ha gatilho; e a spec exige distinguir "sem cobertura" de
  "medido e zero" (FR-005), o que pede um estado de provisionamento
  inspecionavel.

---

## Decision 11: Restricao operacional conhecida — `bash-guard` bloqueia o scrape via tool `Bash`

**Decision**: registrar como restricao de AMBIENTE DE IMPLEMENTACAO (nao de
runtime da feature): durante uma execucao 00c ativa, o hook `PreToolUse`
bloqueia comandos de rede cuja URL nao esteja na whitelist do projeto.

**Rationale**: observado empiricamente nesta onda. Duas tentativas de scrape
do endpoint dinamico via tool `Bash` foram bloqueadas:

```
REGRA_VIOLADA: bash-guard: BLOQUEADO — URL fora da whitelist: http://127.0.0.1:55525/metrics;
  comando: [... linha do comando, elidida ...]
  whitelist: /Users/jot/Projects/_lab/Jot/misc/cstk/.claude/agente-00c-whitelist
```

(Transcricao com a linha `comando:` elidida por concisao; o restante e
literal.)

O arquivo `.claude/agente-00c-whitelist` lista apenas a porta FIXA
(`http://127.0.0.1:9464/metrics` e `http://localhost:9464/metrics`, linhas
6-7), enquanto o endpoint real do operador usa porta dinamica.

Escopo do impacto (importante nao exagerar): o guard e `PreToolUse`/`Bash` —
avalia a STRING do comando da tool call. **Hooks nao sao tool calls**, e
scripts que fazem o scrape internamente (como `otel-usage.sh`) passam pelo
guard porque a URL nao aparece na linha de comando. Logo o runtime da feature
NAO e afetado; o que e afetado e a verificacao manual/automatizada via `Bash`
durante `execute-task`. Mitigacao para a fase de implementacao: exercitar o
caminho por fixture local (`--endpoint file://...`, ja suportado pelo
comentario de `_OU_DEFAULT_ENDPOINT`, linhas 125-127) ou acrescentar o
endpoint dinamico a whitelist do projeto — decisao do operador, fora do
escopo desta feature.

**Alternatives considered**:
- *Alterar a whitelist como parte desta feature*: rejeitada — mexer em
  superficie de seguranca por conveniencia de teste e mudanca de escopo nao
  especificada.
