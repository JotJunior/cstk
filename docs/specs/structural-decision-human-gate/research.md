# Research: Decisoes estruturais exigem gate humano

Documento produzido no Phase 0 do `/plan`. Resolve os unknowns tecnicos do
Technical Context antes do design.

Toda afirmacao factual abaixo sobre o codigo atual foi verificada por leitura
direta do arquivo citado (Constitution VI — zero fabricacao). Onde o achado e
uma AUSENCIA, a verificacao foi feita por grep exaustivo e esta declarada como
tal.

## Decision 1: Onde persistir a classe da Decisao

**Decision**: coluna dedicada `decision_class TEXT` (e `structural_axis TEXT`,
vide Decision 4) na tabela `decision` do `state.db`, campo homonimo em
`.decisions[]` do `state.json`, flag `--classe` / `--eixo` no helper POSIX e
campo `decision_class` / `structural_axis` no schema zod da tool MCP.

**Rationale**: a tabela `decision`
(`plugins/cstk/skills/agente-00c-runtime/references/state-db-schema.sql:135-165`)
projeta os 14 campos da entidade em colunas nomeadas e **nao possui coluna
`extra_fields`** — o catch-all JSON existe apenas em `execution`
(linha 65) e `wave` (linha 102). Introduzir um catch-all so para esta feature
criaria um segundo padrao de leitura exatamente no ponto onde todos os leitores
hoje projetam colunas nomeadas (`_state-rw-db.sh:294-308`,
`cli/lib/recall.sh:2313`). Coluna dedicada mantem um unico padrao.

**Alternatives considered**:
- *Reusar `originating_artifact`*: rejeitado — a semantica ja esta ocupada pelo
  par de invalidacao append-only (`state-decisions.sh mark-invalid`, detectado
  em `report.sh` pelo par `originating_artifact == dec-NNN` +
  `choice == "invalidar-dec-NNN"`). Sobrecarregar o campo quebraria essa
  deteccao.
- *Adicionar `extra_fields TEXT` a `decision`*: rejeitado — mesmo custo de
  migracao (Decision 3) com pior legibilidade e sem CHECK constraint possivel
  sobre o enum.
- *Derivar a classe do texto de `context` por heuristica*: rejeitado — nao
  deterministico. E precisamente o modo de falha da #146: confiar que o texto
  livre carregue a semantica de governanca.

## Decision 2: Idioma dos identificadores e dos valores do enum

**Decision**: nomes de campo/coluna em **ingles** (`decision_class`,
`structural_axis`); flags do helper em **portugues** (`--classe`, `--eixo`);
valores do enum em **portugues** (`estrutural` | `operacional`).

**Rationale**: e a convencao ja vigente e verificavel neste runtime, nao uma
escolha nova. As 14 colunas de `decision` sao inglesas (`agent`, `stage`,
`choice`, `rationale`, `justification_score`, `originating_artifact`) enquanto
as 11 flags correspondentes de `state-decisions.sh register` sao portuguesas
(`--agente`, `--etapa`, `--escolha`, `--justificativa`, `--score`,
`--artefato-originador`) — o mapeamento flag-pt/coluna-en ja e explicito na
constante `FIELD_TO_FLAG_TABLE` de `mcp/state-server/src/runtime/exec.ts:299`.
Para os VALORES, o precedente literal esta na mesma camada transacional: a
coluna `termination_reason` armazena os tokens portugueses
`etapa_concluida_avancando | threshold_proxy_atingido | bloqueio_humano |
aborto | concluido`. A regra global "enums em ingles" cede aqui pela clausula
que ela mesma prevê (manter consistencia local); divergir produziria dois
dialetos de enum no mesmo `state.json`.

**Alternatives considered**: `structural` | `operational` — rejeitado por
divergir de `termination_reason`, dos tokens ja usados pela spec ratificada e
das opcoes canonicas ja gravadas em `options_considered` (`bloqueio-humano`,
`pause-humano`).

## Decision 3: Migracao de schema do `state.db` (risco central da feature)

**Achado verificado (ausencia)**: o `state.db` **nao possui nenhum mecanismo de
migracao de schema**. `state-db-schema.sh` expoe unicamente `create --db PATH`
(subcomando unico, dispatch na linha 85), que aplica um DDL inteiramente
`CREATE TABLE IF NOT EXISTS` — no-op sobre banco existente. `create` e invocado
em apenas dois pontos: `state-rw.sh:553` (durante `init`) e
`state-db-migrate.sh:260` (migracao de DADOS json->db, nao de schema). Grep por
`ALTER TABLE`, `user_version` e `PRAGMA table_info` em `plugins/`, `cli/`,
`mcp/` e `tests/` nao retorna hit algum na camada de estado transacional. Os unicos hits reais
sao `cli/lib/recall.sh` e seu teste — indice DERIVADO e reconstruivel, nao
fonte de verdade — mais prosa do perfil Go
(`plugins/cstk-language-go/skills/go-add-migration/SKILL.md`), fora desta camada.

Consequencia direta e concreta: uma execucao ja em andamento (inclusive a que
esta produzindo este plano) tem um `state.db` criado antes da coluna existir.
Sem tratamento explicito, o primeiro `register --classe` falharia com
`no such column` e o `_sr_db_read` quebraria o export.

**Decision**: novo subcomando `state-db-schema.sh ensure --db PATH`, idempotente
e **fail-hard**, que consulta `PRAGMA table_info(decision)` e aplica
`ALTER TABLE decision ADD COLUMN ...` somente para as colunas ausentes.
Invocado nos dois pontos de contato com a coluna nova: no ramo sqlite de
`_sd_db_register` (antes do `BEGIN IMMEDIATE`) e em `_sr_db_read` (antes da
projecao). Custo: um `PRAGMA` por operacao que ja paga o spawn de um processo
`sqlite3` — irrelevante frente ao custo existente (SC-005).

**Rationale**: o padrao `PRAGMA table_info` + `ALTER TABLE ADD COLUMN`
idempotente ja e o precedente do repo (`recall_apply_schema`,
`cli/lib/recall.sh:738-880`, incluindo um ALTER sobre a propria tabela
`decisions` na migracao v5->v6). O que muda aqui e a **postura de erro**: em
`recall.sh` a degradacao e best-effort porque o indice e descartavel; no
`state.db` a fonte de verdade e transacional, logo a falha do `ensure` MUST
propagar (contrato de `_state_db_exec_with_retry`), nunca silenciar.

**Alternatives considered**:
- *Exigir `cstk state migrate` manual do operador*: rejeitado — quebraria
  execucoes em andamento no meio, e a feature e explicitamente nao-retroativa
  (spec, Edge Cases), nao "nao-instalavel a quente".
- *Introduzir `user_version` e um migrador versionado completo*: rejeitado
  neste escopo — e uma feature propria (divida tecnica ja conhecida do
  `state.db`), e resolve-la aqui triplicaria o blast radius. Registrada como
  divida explicita na secao Complexity Tracking do `plan.md`.
- *Coluna opcional lida com `SELECT ... FROM pragma_table_info` condicional em
  cada leitura*: rejeitado — SQL dinamico por leitura, muito mais fragil que um
  ALTER idempotente unico.

## Decision 4: Representacao do eixo estrutural (lista fechada)

**Decision**: arquivo de referencia versionado
`plugins/cstk/skills/agente-00c-runtime/references/structural-axis-map.txt`,
formato de linha `eixo|rotulo`, lido por parser POSIX-puro **sem jq**; a lista
de 6 eixos vem da tabela ja ratificada na spec (linguagem/runtime, stack,
arquitetura, persistencia, ambiente-alvo, tier-de-entrega).

**Rationale**: precedente literal duplo no mesmo diretorio —
`references/tier-gate-map.txt` consumido por `delivery-tier.sh gate-mode` e
`references/phase-model-map.txt` consumido por
`model-routing.sh phase-model-lookup`, ambos POSIX-puros sem jq, ambos com a
versao do mapa declarada na primeira linha. A lista precisa ser citavel por
tres consumidores distintos (helper, prosa dos dois orquestradores, tool MCP);
um arquivo unico evita tres copias divergentes.

**Alternatives considered**: hardcode no `.sh` (duplicaria a lista em 2 agentes
+ 1 arquivo TS); JSON (exigiria jq num caminho hoje jq-free).

## Decision 5: Parser dos "Itens a Definir" do briefing (FR-007)

**Decision**: novo helper `briefing-items.sh` com subcomando
`list-high --briefing PATH`, POSIX puro (awk/sed, sem jq), saida uma linha por
item no formato `item<TAB>dimensao`, **exit 0 sempre** exceto uso incorreto (2).

**Rationale — regras derivadas de dados REAIS, nao do template**: o template
(`plugins/cstk/skills/briefing/templates/briefing.md:88-92`) declara heading
`## Itens a Definir` e cabecalho `| Item | Dimensao | Impacto |`. Mas os
briefings reais divergem do placeholder `[Alto/Medio/Baixo]` de tres formas ja
observadas no repo:
1. `docs/01-briefing-discovery/briefing.md:124-126` — impacto com prosa anexada:
   `Medio (ambicao de 12 meses fica nao-verificavel sem isso)`,
   `Baixo hoje, sobe conforme base de usuarios cresce`.
2. `docs/specs/_archived/agente-00c/briefing.md:219-221` — separador em travessao:
   `Alto — define a interface de retomada`.
3. `docs/specs/_archived/github-pages-cstk-manual/briefing.md:128-131` — mesma
   heading, porem **lista numerada, sem tabela alguma**.

Logo o parser casa o impacto pelo **token inicial** da celula
(case-insensitive, ancorado no inicio, ignorando espacos), e nao pela celula
inteira; e trata ausencia de tabela como "zero itens + aviso em stderr",
conforme a spec (Edge Cases) manda — degradar para zero itens e o
comportamento atual e nunca falha a onda.

**Verificacao adicional de escopo**: o briefing deste proprio repo tem 3 itens,
todos `Medio`/`Baixo` e **nenhum `Alto`** — ou seja, ativar o gate FR-008 nao
auto-bloqueia esta propria execucao. Fato relevante para o rollout.

**Alternatives considered**: exigir formato estrito e falhar em divergencia —
rejeitado por contradizer a spec e por quebrar 3 dos briefings existentes;
parser em jq apos converter markdown — rejeitado (dependencia desnecessaria).

## Decision 6: Onde ancorar o gate de ambiente alvo (FR-010)

**Decision**: dois checks novos dentro de `validate_plan_profile()` em
`plugins/cstk/skills/validate-documentation/scripts/validate-sdd.sh`, guardados
por `_is_plan_md` (so `plan.md`): codigo `target-platform-unresolved`
(severidade `error`) e `target-platform-unsourced` (severidade `warning`).

**Lacuna verificada que justifica o check proprio**: o check FR-011 ja existente
conta `count_matches '\[NEEDS CLARIFICATION'` (linha 323). A linha do template
e `**Target Platform**: [ex: Kubernetes, Vercel, mobile ou NEEDS CLARIFICATION]`
— o marcador aparece **sem** o colchete imediatamente antes, portanto o regex
atual **nao casa**. Um `plan.md` com o Technical Context inteiro por preencher
passa o gate hoje nesse campo. Alem disso o plan-profile so verifica que a
secao `Technical Context` **existe** (linha 295); nao ha nenhum check de campo
individual. O gate novo e aditivo e nao altera nenhum finding existente.

**Rationale**: manter o check no mesmo script preserva o contrato de saida ja
consumido pelos orquestradores (`FINDING|<severity>|<code>|<msg>` +
`RESULT|<file>|profile=<spec|plan>|errors=N|warnings=M`, exit 0/1/2) e reusa a
tabela de gates existente, que ja converte finding critico em bloqueio humano no
modo autonomo — nenhuma fiacao nova de orquestracao e necessaria.

**Alternatives considered**: script novo dedicado — rejeitado (fragmentaria o
gate pos-plan em dois e exigiria nova fiacao na prosa dos dois orquestradores).

## Decision 7: Definicao deterministica de "fonte rastreavel" (FR-010, aviso)

**Decision**: considera-se o ambiente alvo **com fonte** quando a secao
`Technical Context` do `plan.md` contem, na linha do campo ou em linha
imediatamente adjacente, ao menos um destes marcadores: `briefing`,
`constitution`, ou uma referencia de Decisao no formato `dec-NNN`.

**Rationale**: os tres sao exatamente as fontes humanas rastreaveis que a spec
admite (US3: "briefing, constitution, resposta minha"), e `dec-NNN` e o formato
literal de id gerado por `state-decisions.sh` (`'dec-' || printf('%03d',...)`).
O check e textual e deterministico — jamais tenta julgar se a fonte e "boa",
apenas se foi declarada; e por isso e `warning`, nunca `error` (o gate nao pode
fabricar uma fonte nem presumir ma-fe).

**Alternatives considered**: resolver o link e validar que o documento citado de
fato contem a informacao — rejeitado: `validate-sdd.sh` tem fronteira declarada
de nao resolver link/anchor (FR-013 do proprio validador).

## Decision 8: FR-009 (plan Phase 0) e FR-011 (create-tasks) sao mudanca de prosa

**Decision**: FR-009 e FR-011 sao implementados como regra de prosa em
`plugins/cstk/skills/plan/SKILL.md` (ETAPA 4) e
`plugins/cstk/skills/create-tasks/SKILL.md`, **sem** gate deterministico
proprio.

**Rationale**: e a leitura honesta do que a spec ja assume. `plan/SKILL.md` ja
detecta modo autonomo (linha 48, `AGENTE_00C_STATE_DIR` / `state.json` do
agente-00c ou feature-00c) — para consumo de cache — logo o ramo de deteccao
existe e nao precisa ser inventado; o que se acrescenta e a regra de nao
resolver por inferencia um unknown de classe estrutural nesse modo, contra os
anti-patterns atuais ("NEEDS CLARIFICATION devem morrer no Phase 0", linha 382).
Em `create-tasks/SKILL.md` **nao existe hoje o conceito "gate humano de
dependencias"** (verificado: a unica ocorrencia de "humano" e sobre itens
`{humano}` de checklist, linha 118); a ordenacao e expressa pela
`### Matriz de Dependencias` (linha 274). A spec reconhece explicitamente essa
limitacao ("parcialmente dependente da honestidade do agente") e delega a
garantia dura aos gates deterministicos de US2/US3.

**Alternatives considered**: criar gate deterministico para ordenacao de tasks —
rejeitado neste escopo: exigiria formalizar "task de gate de dependencias" como
entidade tipada no backlog, o que e feature propria e nao esta na spec.

## Decision 9: Propagacao aos leitores (FR-012)

**Decision**: tres leitores recebem os campos novos, cada um pelo seu caminho ja
existente:
1. `report.sh` `_rp_render_secao_3` — exibe `**Classe**` / `**Eixo estrutural**`
   e marca **anomalia de governanca** de forma **derivada** (nunca gravada),
   pelo mesmo padrao ja usado para INVALIDADA.
2. `review-task/SKILL.md` — nova secao de contagens (estruturais, anomalias),
   ao lado das secoes de model-routing ja existentes.
3. `cli/lib/recall.sh` — `RECALL_SCHEMA_VERSION` de 14 para 15, com
   `ALTER TABLE decisions ADD COLUMN` idempotente nos dois caminhos de ingestao
   (JSON->SQL linha 1763 e SQL->SQL linha 2313), que hoje compartilham o mesmo
   tuple de colunas.

**Rationale**: anomalia derivada, nunca persistida, e a mesma escolha
arquitetural ja validada para a invalidacao de Decisao — mantem `.decisions[]`
append-only e imune a reescrita retroativa. A migracao da knowledge.db segue o
precedente literal ja existente naquele arquivo.

**Alternatives considered**: gravar um booleano `governance_anomaly` — rejeitado:
seria estado derivado persistido, que envelhece mal e permite divergencia entre
o campo e a regra.

## Decision 10: Esta propria mudanca de persistencia e estrutural?

**Decision**: **nao** — e operacional, pela definicao da propria spec.

**Rationale**: dogfooding honesto da regra que a feature institui. O eixo
"persistencia principal" cobre *SQLite vs banco externo vs arquivos*; aqui a
persistencia ja esta fixada por decisao humana anterior (constitution,
amendment 1.3.0, carve-out da camada de estado transacional). Acrescentar duas
colunas dentro de um backend ja decidido e, textualmente, "detalhe de
implementacao / escolha DENTRO de uma stack ja decidida por humano" — o exemplo
que a spec da para decisao operacional. Registrado aqui porque a alternativa
(classificar tudo que toca schema como estrutural) transformaria o gate em ruido
e destruiria SC-006.
