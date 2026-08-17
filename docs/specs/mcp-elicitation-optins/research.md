# Research: mcp-elicitation-optins

Documento produzido no Phase 0 do `/plan`. Consolida as decisoes de pesquisa
registradas na execucao autonoma (`dec-025`..`dec-038` em
`.claude/feature-00c-state/mcp-elicitation-optins/state.json`), todas com
evidencia literal citada. Este documento e a **consolidacao formal** daquela
pesquisa, acrescida de **releituras pontuais** feitas nesta fase e marcadas
caso a caso como "VERIFICADO nesta consolidacao" (Decisions 8, 9 e 11) — a
fundacao nao foi re-pesquisada em bloco.

> **Nota de veracidade (Constitution VI)**: cada Decision abaixo distingue o
> que foi **VERIFICADO** (citacao literal de arquivo:linha) do que e
> **[PROPOSTA — a validar na implementacao]** (desenho novo, ainda nao medido).
> Nenhum comportamento de terceiro e afirmado sem fonte.

---

## Decision 1: Quem dispara o formulario estruturado

**Decision**: o **orquestrador** (subagente) dispara o formulario como seu
**primeiro ato**, antes de abrir a onda-001 (`state-ondas.sh start`). O command
pai NAO dispara.

**Rationale** (dec-030, score 3): o portador comprovado das tools MCP e o
orquestrador — sua frontmatter declara as 7 tools
(`agente-00c-feature-orchestrator.md:4`: `tools: Agent, Skill, Bash, Read,
Write, Edit, Glob, Grep, mcp__cstk-state__open_wave, ...
mcp__cstk-state__get_status`). Os 4 commands pai declaram
`allowed-tools: Agent/Read/Write/Bash/Glob/ScheduleWakeup` — **nenhuma tool
MCP**. Atribuir o disparo ao command pai exigiria comprovar que o main loop
enxerga as tools do `.mcp.json`, o que NAO foi verificado — seria suposicao.

Isso e compativel com FR-012 ("a etapa 2 MUST concluir ANTES de qualquer onda
comecar") porque o orquestrador tem um ponto de execucao **anterior** a
abertura da onda: o passo 3.bis do Loop principal so chama
`state-ondas.sh start` depois das checagens iniciais. O formulario e disparado
antes dessa chamada, portanto nenhuma onda esta aberta.

**Alternatives considered**:
- *Command pai dispara* — rejeitada: exige premissa nao verificada (slash
  command enxergando tools do `.mcp.json`).
- *Disparar dentro da onda-001 ja aberta* — rejeitada: violaria a letra de
  FR-012 ("antes de qualquer onda comecar").

**[PROPOSTA — a validar na implementacao]**: que o harness renderize um
`elicitation/create` originado de uma tool chamada por um **subagente**. O
que esta medido e que o cliente declara a capability e que `enum` vira picker;
nao esta medido que a origem-subagente preserve esse comportamento. Task de
validacao obrigatoria antes de qualquer outra (ver `plan.md` §Riscos).

---

## Decision 2: O que `cstk mcp start` de fato faz (reformulacao da etapa 2)

**Decision**: a etapa (2) do init em duas etapas NAO e "subir o servidor" — e
**cunhar o token de capacidade**. O texto de FR-012 ("o servidor de estado
sobe") descreve o mundo pre-cutover e deve ser lido como "o token e cunhado e
a sessao passa a ser resolvivel".

**Rationale** (dec-031, score 3). Evidencia literal:
- `cli/lib/mcp.sh:22-30`: "start NAO builda/sobe container algum — apenas
  resolve o state-dir, gera/reusa o token de capacidade (session_id, CSPRNG >=
  128 bits) e grava o descritor mode=direct ... O processo do servidor MCP passa
  a ser criado pelo HARNESS ao conectar o `.mcp.json`, nunca por
  `cstk mcp start`".
- `mcp-launch.sh:204`: `exec node $_ml_entrypoint`.
- `mcp.sh:654-657`: `start` exige apenas que o DIRETORIO exista.

**Consequencia dura para o desenho**: `mcp-session.sh:25-32` afere o status
terminal da execucao em duas camadas (`.execution.status` via
`state-rw.sh get`) e "qualquer uma recusando e suficiente para
SESSION_MISMATCH". Logo **a etapa (1) do init PRECISA deixar
`.execution.status` ativo (`em_andamento`)** antes da cunhagem — senao toda
chamada de tool com elicitation retorna `SESSION_MISMATCH` e a feature nunca
opera. `state-rw.sh init` ja produz esse status, entao a exigencia e de
**ordem**, nao de codigo novo.

**Alternatives considered**: *chamar `start` antes do init* — rejeitada:
diretorio existe mas a sessao nao resolve, token nasce invalido.

---

## Decision 3: Tensao FR-006 x FR-012 — reconciliada, sem delta na spec

**Decision**: **nao ha contradicao**. FR-006 exige default no "nivel mais
restritivo"; FR-012 diz que o default omitido e `cloud-public`. No enum do
`delivery-tier` o eixo NAO e exposicao de rede, e **rigor de gate**, e
`cloud-public` e o de **maior** ordinal.

**Rationale** (dec-037, score 3). Evidencia literal:
- `delivery-tier.sh:17-20` (`get`): "Campo ausente/estado ilegivel/token fora
  do enum => `cloud-public` (INV-1, **maior profundidade** — degradar para
  MENOS rigor seria a falha insegura)".
- `_dt_ordinal:100-107`: mapa ordinal
  `local | internal-network | cloud-internal | cloud-public`.
- `state-rw.sh:353`: `_delivery_tier="cloud-public"` como default do init.

Portanto `cloud-public` **e** o nivel mais restritivo na escala que importa
(profundidade de gate de seguranca), e os dois FRs concordam. Nenhuma edicao a
`spec.md` e necessaria.

**Alternatives considered**: *emitir bloqueio humano por contradicao* —
rejeitada apos leitura da fonte; *reescrever FR-006* — desnecessario.

---

## Decision 4: `delivery-tier.sh set` exige `--allow-downgrade` no caminho estruturado

**Decision**: a chamada de persistencia do tier no caminho estruturado MUST
passar `--allow-downgrade`.

**Rationale** (dec-037, score 3, corolario da Decision 3). Evidencia literal
`delivery-tier.sh:22-27`: "`set --value <token> [--allow-downgrade]` ...
Elevacao (ordinal novo > atual) => grava, exit 0. Ordinal igual => no-op
idempotente, exit 0. **Rebaixamento (ordinal novo < atual) sem
`--allow-downgrade` => exit 2 sem escrever**".

Como a etapa (1) grava o **maior** ordinal (`cloud-public`), qualquer resposta
do operador diferente de `cloud-public` e, por construcao, um rebaixamento.
Sem a flag, a feature gravaria o tier em **1 de 4 casos** e falharia calada
nos outros 3 — exatamente a classe de defeito que esta linha de trabalho
combate.

**Alternatives considered**: *nao gravar default na etapa 1 e gravar so na
etapa 2* — rejeitada: abriria a janela em que `.delivery_tier` esta ausente,
e `get` ja resolve ausencia para `cloud-public` (mesmo efeito), sem ganho.

---

## Decision 5: Teto de tempo — `RequestOptions.timeout` do proprio SDK

**Decision**: o teto e expresso na propria chamada
`server.server.elicitInput(params, { timeout: N })`, nao num wrapper caseiro.

**Rationale** (dec-033 + dec-038, score 3). Evidencia literal do SDK instalado
(`@modelcontextprotocol/sdk` 1.30.0):
- `dist/esm/server/index.d.ts:158`:
  `elicitInput(params: ElicitRequestFormParams | ElicitRequestURLParams, options?: RequestOptions): Promise<ElicitResult>`.
- `dist/esm/shared/protocol.d.ts:73-77`: "A timeout (in milliseconds) for this
  request. If exceeded, an `McpError` with code `RequestTimeout` will be raised
  from `request()`. ... `timeout?: number`".
- `dist/esm/server/mcp.d.ts:18`: `readonly server: Server` (o `McpServer` expoe
  o `Server` que possui `elicitInput`).

Isso satisfaz **FR-010 literalmente** ("o tempo-limite MUST ser imposto pelo
lado SERVIDOR da chamada"): quem arma o relogio e quem envia a requisicao — o
servidor. Nao depende de o cliente possuir mecanismo proprio.

Contexto que torna isso codigo NOVO (dec-033): `runtime/exec.ts:165-170` chama
`execFile` com `{ shell: false, maxBuffer: MAX_BUFFER_BYTES, encoding: "utf8" }`
— **sem `timeout` nem `signal`**; o unico teto do servidor hoje e um contador
de chamadas (`index.ts:101`: `const DEFAULT_MAX_TOOL_CALLS = 2000;`).

**Alternatives considered**: *espelhar `withTimeout` de
`mcp/state-server/src/healthcheck.ts:53-72`* (convencao exit 124) — rejeitada como primaria: o SDK
ja oferece o teto na borda certa; um wrapper caseiro adicionaria codigo sem
ganho e perderia o `notifications/cancelled` que o proprio SDK emite ao
expirar.

---

## Decision 6: Discriminar `cancel` por timeout de `cancel` por ausencia de operador

**Decision**: discriminar **pelo mecanismo** (envelope retornado x excecao
lancada), nunca por tempo decorrido.

**Rationale** (dec-038, score 3). Sao dois caminhos de codigo distintos:
- **Ausencia de operador** → o CLIENTE responde um envelope `ElicitResult` com
  `action: "cancel"`. Medido: sessao headless responde `cancel` imediato.
  Schema em `types.d.ts:5394-5397`:
  `action: z.ZodEnum<{ cancel, accept, decline }>` +
  `content?: Record<string, string|number|boolean|string[]>`.
- **Teto de tempo esgotado** → `RequestOptions.timeout` faz o SDK **lancar**
  `McpError` com code `RequestTimeout` (`protocol.d.ts:73-75`) — **nunca**
  retorna envelope.

Logo: `outcome = "absent"` vem de *resposta recebida*; `outcome = "timeout"`
vem de *excecao capturada*. Zero heuristica de relogio (que seria fragil e
contrariaria FR-010, cujo teto e do servidor).

**Alternatives considered**: *medir tempo decorrido e classificar acima de um
limiar* — rejeitada: heuristica, e o `cancel` imediato do headless so e
"imediato" por observacao, nao por contrato.

---

## Decision 7: A 8a tool MCP (`collect_optins`) e seu gate de composicao

**Decision**: introduzir **uma** tool nova, `collect_optins` (nome MCP
`mcp__cstk-state__collect_optins`), declarada na frontmatter dos DOIS
orquestradores e adicionada a lista `_required` do guard de composicao.

**Rationale** (dec-029, score 3). O guard verifica **presenca** das tools
obrigatorias, nao cardinalidade: uma 8a tool adicionada sem entrar em
`_required` passaria despercebida pelo teste, ficando sem cobertura
justamente na superficie nova. Evidencia literal:
- `tests/test_orchestrator-allowlist-guard.sh:275`
  `scenario_allowlist_declara_as_7_tools_mcp()` e `:281-287`
  `_required=` `open_wave/record_decision/record_skill/record_task/register_human_block/close_wave/get_status`.
- `:307` `_fail mcp_tools_missing "$_t: faltam tools mcp__cstk-state__* =>$_missing"`.
- `:317` `scenario_allowlist_preserva_bash` garante que `Bash` permanece na lista.

O cenario se chama literalmente `as_7_tools_mcp`, entao a renomeacao para 8 faz
parte do entregavel.

**Por que uma tool nova e nao reuso**: nenhuma das 7 tools existentes tem
semantica de captura de resposta humana; todas delegam a helpers POSIX de
escrita de estado (`get_status.ts:5-10` documenta as delegacoes read-only). A
tool nova e a unica superficie que precisa acessar `server.server.elicitInput`.

**Alternatives considered**: *3 tools (uma por opt-in)* — rejeitada: FR-001
exige um **UNICO** formulario, e 3 tools produziriam 3 formularios.

---

## Decision 8: Escopo por orquestrador vem de `executionKind`, nao de heuristica de path

**Decision**: o servidor decide quais campos entram no formulario lendo
`ResolvedSession.executionKind`.

**Rationale** (VERIFICADO nesta consolidacao). Evidencia literal:
- `mcp/state-server/src/session/resolve.ts:29-38`: `interface ResolvedSession`
  expoe `readonly executionKind: string` (alem de `token`, `stateDir`,
  `shortName`, `targetProjectPath`, `mode`, `container`).
- `mcp-session.sh:68`: `execution_kind=<agente-00c|feature-00c>`.
- `resolve.ts:150`: `executionKind: fields.execution_kind`.

Portanto o campo de finalidade de entrega e incluido **se e somente se**
`executionKind === "agente-00c"`, preservando a paridade de escopo exigida por
FR-001 e pelos Edge Cases da spec sem nenhuma inspecao de string de caminho.

**Alternatives considered**: *detectar por substring do `stateDir`
(`feature-00c-state`)* — rejeitada: fragil e desnecessaria, ha campo tipado.

---

## Decision 9: Revogacao da clausula normativa — o guard NAO quebra, mas fica cego

**Decision**: reescrever o item 8 do bloco `MCP-VS-BASH` nos DOIS
orquestradores **preservando o literal `elicitation/create`**, e **reforcar a
assercao do guard no mesmo commit** para que ela passe a verificar a semantica
nova.

**Rationale** (dec-028 + dec-032, refinados por leitura direta do teste nesta
consolidacao — **correcao de nuance**, Constitution VI aplicada ao proprio
artefato):

A clausula atual e normativa e vinculante em runtime
(`agente-00c-feature-orchestrator.md:175-177`, identica em
`agente-00c-orchestrator.md:187`): "`elicitation/create` permanece FORA de
escopo de uso ativo enquanto FR-010 estiver Deferred ... nao invoque nenhuma
tool MCP que dependa dela sem essa definicao." Enquanto ela existir, um
orquestrador obediente se **recusa** a invocar a tool nova — anulando a feature
inteira. A revogacao e entregavel de primeira classe.

**Correcao a dec-032**: dec-032 afirma que editar a prosa sem tocar o teste
"quebra a suite". A leitura literal do teste mostra que isso vale **apenas se a
reescrita remover o literal**. A assercao e uma unica linha de presenca de
token (`tests/test_orchestrator-allowlist-guard.sh:489`):

```sh
printf '%s\n' "$_body" | grep -qF 'elicitation/create' || _missing_items="$_missing_items item8"
```

Os itens vizinhos (`:482-490`) seguem o mesmo padrao de presenca de string
(`'Quando preferir MCP'`, `'0 retries'`, `'NUNCA pausa a onda'`, ...).

**O risco real e o inverso do descrito**: uma reescrita que **inverta a
semantica** da clausula (de "proibido" para "permitido") e **mantenha** o
literal continua passando verde — a suite ficaria afirmando um item cujo
significado mudou, sem sinal algum. Por isso o entregavel correto nao e
"consertar um teste quebrado", e **fortalecer uma assercao que ficaria cega**:
a nova assercao MUST verificar que o bloco descreve o recorte permitido
(operador presente) **e** o recorte que permanece diferido (sem operador
presente), nos dois orquestradores.

**Alternatives considered**:
- *Deletar o item 8* — rejeitada: quebraria o guard de fato e perderia o
  registro do recorte que **permanece** Deferred (spec, Edge Cases: elicitation
  a partir de subagente **sem operador humano presente** segue fora de escopo,
  `orchestrator-mcp-allowlist` FR-010).
- *Revogar so no orquestrador de feature* — rejeitada: o bloco e duplicado e o
  guard varre os dois; assimetria = teste vermelho + comportamento divergente.

---

## Decision 10: Trilha de fallback e o comentario stale

**Decision**: descrever o fallback pelo **discriminador real** — token
vazio / descritor ausente — e listar a correcao dos comentarios stale como
defeito colateral desta feature.

**Rationale** (dec-034, score 3). Evidencia literal:
- `cli/lib/mcp.sh:100-107`: "3 indisponivel: reservado pelo contrato (S-6)
  para eventual `mode=bash-fallback` ... **nao ha caminho de codigo atual que o
  produza**".
- `mcp.sh:1076`: "3 reservado pelo contrato para bash-fallback; nenhum caminho
  de codigo".
- `mcp.sh:708-709`: `_mcp_write_descriptor` grava **sempre** `"direct"`.
- Discriminador real ja em uso: `feature-00c.md:741-742` — "`_mcp_token` vazio
  (bash-fallback / sem descritor) => NAO mencione MCP no prompt".
- Comentarios contraditorios a corrigir: `feature-00c.md:711` e
  `agente-00c.md:470`, que alegam degradacao para `mode=bash-fallback`.

Repetir o comentario stale plantaria dado falso no plano (Constitution VI) e
produziria um teste que afirma um valor que o codigo nunca emite.

**Alternatives considered**: *testar `mode=bash-fallback`* — rejeitada: seria
assercao sobre valor inexistente.

---

## Decision 11: Mecanismo de escrita pos-init — 2 helpers orfaos + 1 ja wired

**Decision**: usar `commit-mode.sh set-enabled`, `roadmap-mode.sh set-enabled` e
`delivery-tier.sh set` (FR-013). Para os dois primeiros, esta feature e o
**primeiro caller de fato**. Para o terceiro, o caminho de escrita **ja existe e
ja e usado** — ali a mudanca e de **ORDEM** (quando escreve), nao de mecanismo.

**Rationale** (dec-026 + dec-035, arbitragem). **Correcao a FR-013**: a spec
afirma que as tres primitivas "ate esta feature nao tinham chamador ativo".
Isso e verdade para duas, nao para as tres. Evidencia literal (dec-035):
- `grep -rn 'set-enabled' plugins/cstk/commands/` => **vazio** (confirma orfandade
  de `commit-mode.sh set-enabled` e `roadmap-mode.sh set-enabled`).
- `grep -rn 'delivery-tier.sh <sub>' -o` => `get`, `resolve-initial`, **`set`**
  (confirma que `set` tem chamador).
- Chamadores do tier em prosa: `agente-00c.md:433`, `agente-00c-resume.md:214/218`;
  `agente-00c.md:395` `_tier=$(delivery-tier.sh resolve-initial --source operator --answer "$_raw")`.

**Mecanismo REAL hoje** (dec-026): os 3 opt-ins sao capturados por prosa
**antes** do init e passados como **flags de init** (`state-rw.sh:371-386`
aceita `--atomic-commit` / `--roadmap-mode` / `--delivery-tier`; campos
gravados em `:536-538` como `atomic_commit_enabled`, `roadmap_mode_enabled`,
`delivery_tier`).

**Restricao adicional descoberta**: `roadmap-mode.sh set-enabled` e
**write-once** — `roadmap-mode.sh:142` recusa com exit 2 quando "ja existe onda
com etapa executada posterior a 'constitution'". Isso e **compativel** com o
desenho porque a etapa (2) roda com **zero ondas abertas**; e um argumento
adicional a favor de disparar antes de `state-ondas.sh start`.

**Delta de spec recomendado**: FR-013 deve ser corrigido para "duas das tres
primitivas nao tinham chamador ativo".

---

## Decision 12: Lacuna de gate dos testes Node — declarada, nao mascarada

**Decision**: declarar explicitamente que os testes do servidor MCP **nao rodam
em gate algum** hoje; concentrar as assercoes gateaveis na suite POSIX; tratar
"criar gate para o lado Node" como **decisao de escopo separada**.

**Rationale** (dec-027, score 3). Evidencia literal:
- `ls .github/workflows/` => `publish-site.yml`, `release.yml`, `shellcheck.yml`
  (3 arquivos).
- `grep -rin node .github/workflows/` => **zero linhas**.
- `grep -n "mcp/state-server|npm test|node --test" tests/run.sh` => **NO MATCH**.

Consequencia: toda a logica de elicitation (schema do formulario, teto de
tempo, mapeamento accept/decline/cancel) vive no lado Node — hoje a metade
**nao gateada** do repo. Existem 16 `*.test.ts` em `mcp/state-server/test/`
que rodam apenas sob `npm test` manual.

**Alternatives considered**: *presumir cobertura porque ha testes escritos* —
rejeitada: teste que nao roda em gate nao e cobertura, e intencao.

---

## Decision 13: Read-back de execucoes passadas

**Decision**: registrado por completude — `dec-025` (score 2) injetou K=4
achados do `cstk recall --context` no inicio desta fase; o mais relevante
confirmou o precedente `test_command-spawn-roadmap-mode.sh` como modelo de
teste para captura de opt-in.

**Rationale**: os precedentes da familia `test_command-spawn-*.sh` sao a base
do plano de testes (ver `plan.md` §Estrategia de Testes).
