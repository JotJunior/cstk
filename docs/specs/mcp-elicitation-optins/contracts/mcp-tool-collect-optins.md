# Contract: tool MCP `collect_optins`

Contrato da 8a tool do servidor `cstk-state`. Nome MCP exposto ao orquestrador:
`mcp__cstk-state__collect_optins`.

> **Estado deste contrato (Constitution VI)**: a tool **nao existe ainda** —
> todo o bloco de request/response abaixo e
> **[PROPOSTA — a validar na implementacao]**. O que e **VERIFICADO** e (a) o
> padrao de registro e envelope das 7 tools existentes, (b) a superficie do SDK
> (`elicitInput`, `ElicitResult`, `RequestOptions`), (c) os contratos dos
> helpers POSIX chamados, (d) desde `quickstart.md` Scenario 0 (dec-071), o
> **comportamento de renderizacao no cliente** — `message` integral, `title`
> como rotulo, `description` como subtexto, `default` pre-aplicado, `required`
> so visivel sem `default`, `enum` colapsado atras de seta — via um stub
> minimo do formulario, medido fora do schema final. Cada bloco esta rotulado.

---

## Registro da tool

**[PROPOSTA]** — segue o padrao VERIFICADO em `mcp/state-server/src/index.ts`
(`registerTool` com `title` / `description` / `inputSchema`, sequencia
`checkCallLimit` → `resolveCallSession` → handler → `toCallToolResult`,
`index.ts:220-240`):

```
server.registerTool("collect_optins", {
  title: "Collect execution opt-ins",
  description: "Oferece UM formulario estruturado com os opt-ins de inicio de
    execucao aplicaveis ao orquestrador corrente e persiste as respostas via os
    helpers POSIX de escrita. Idempotente por campo.",
  inputSchema: collectOptinsInputShape,
}, handler)
```

### Request

**[PROPOSTA]** — mesma forma minima de `get_status`
(VERIFICADO: `tools/get_status.ts:37-39`, `session_id: z.string().min(1)`).

| Field | Type | Required | Validation |
|-------|------|----------|------------|
| `session_id` | string | yes | `min(1)`; token de capacidade da execucao (SEC-H3) |

**Nenhum outro parametro.** Deliberado: quais campos entram no formulario e
derivado **server-side** de `ResolvedSession.executionKind`
(VERIFICADO: `session/resolve.ts:29-38`, `:150`; valores
`agente-00c` \| `feature-00c` em `mcp-session.sh:68`). Se o modelo pudesse
escolher os campos, FR-003 (nenhuma interpretacao pelo modelo) estaria
comprometido na propria borda de entrada.

### Escopo de campos por `executionKind`

**[PROPOSTA]**, derivado de FR-001 + Edge Cases da spec:

| `executionKind` | `atomic_commit` | `roadmap_mode` | `delivery_tier` |
|-----------------|-----------------|----------------|-----------------|
| `agente-00c` | sim | sim | **sim** |
| `feature-00c` | sim | **nao** (exclusivo de `agente-00c`; contrato vigente, `tests/test_command-spawn-roadmap-mode.sh` `scenario_ausente_em_feature_00c`, dec-010/dec-083) | **nao** |

### Response (envelope de tool)

**[PROPOSTA]** — mesma forma das tools existentes
(VERIFICADO: `get_status.ts:56-61`, `interface GetStatusResponse` — campos
`outcome` / `reason` / `stage` / `result`).

| Field | Type | Description |
|-------|------|-------------|
| `outcome` | `"accepted"` \| `"rejected"` | `rejected` apenas para falha de pre-condicao (sessao/limite) |
| `reason` | string \| null | diagnostico saneado; `null` em sucesso |
| `stage` | `"precondition"` \| `"delegation"` \| null | etapa em que parou |
| `result` | objeto \| null | ver abaixo |

`result` **[PROPOSTA]**:

| Field | Type | Description |
|-------|------|-------------|
| `mechanism` | `"structured"` \| `"unavailable"` \| `"failed"` | estado do mecanismo nesta chamada |
| `fields` | array de `FieldOutcome` | um item por campo aplicavel |
| `reused` | array de string | campos que ja tinham registro e nao foram perguntados (FR-011) |

`FieldOutcome` **[PROPOSTA]** (espelha `RespostaDeOptIn` de `data-model.md`):

| Field | Type | Description |
|-------|------|-------------|
| `field` | `"atomic_commit"` \| `"roadmap_mode"` \| `"delivery_tier"` | |
| `outcome` | `accepted`\|`declined`\|`absent`\|`timeout`\|`unavailable`\|`failed` | |
| `applied_value` | string | valor efetivamente gravado |

> Nota FR-003: o envelope carrega apenas **tokens fechados** de enum e valores
> ja normalizados — nenhum texto livre do operador retorna ao contexto do
> modelo para ser interpretado.

### Error Responses

| `outcome` | `stage` | `reason` (prefixo) | Quando |
|-----------|---------|--------------------|--------|
| `rejected` | `precondition` | `SESSION_MISMATCH` | token ausente/divergente/execucao terminal (VERIFICADO: fail-closed em `session/resolve.ts:41-44`) |
| `rejected` | `precondition` | `TOOL_CALL_LIMIT_EXCEEDED` | teto de chamadas do processo (VERIFICADO: `index.ts:203-217`) |
| `accepted` | `null` | `null` | inclui os casos degradados — ver invariante abaixo |

**Invariante contratual C-1 [PROPOSTA]**: `unavailable`, `timeout`, `absent`,
`declined` e `failed` **NAO** sao erros de tool. Retornam `outcome: "accepted"`
com o `mechanism`/`FieldOutcome` correspondente. Motivo: FR-007 e SC-002
exigem que a execucao **nunca** trave; transformar degradacao em erro de tool
faria o orquestrador tratar como falha e potencialmente reter/repetir.

---

## Chamada de elicitation (server → client)

### Parametros

**VERIFICADO** — superficie do SDK instalado
(`@modelcontextprotocol/sdk` 1.30.0):

- `server/index.d.ts:158`
  `elicitInput(params: ElicitRequestFormParams | ElicitRequestURLParams, options?: RequestOptions): Promise<ElicitResult>`
- `server/mcp.d.ts:18` `readonly server: Server` (acesso via `server.server`)
- `server/index.d.ts:121` `getClientCapabilities(): ClientCapabilities | undefined`
- `types.d.ts:4966-5000` `ElicitRequestFormParamsSchema`:
  `{ mode?: "form", message: string, requestedSchema: { type: "object", properties: Record<string, ...> }, task?: { ttl?: number }, _meta? }`
- Propriedade string aceita: `type`, `title`, `description`, `enum`,
  `enumNames`, `default` (`types.d.ts:4984-4999`)
- `shared/protocol.d.ts:73-77` `RequestOptions.timeout?: number` — "If exceeded,
  an `McpError` with code `RequestTimeout` will be raised from `request()`"

### Formulario proposto

**[PROPOSTA]** para a montagem; os **nomes de campo** e o **texto** MUST ser
derivados dos blocos de prosa existentes (FR-002), nao redigidos do zero.

**Ajuste de contrato pos-Scenario 0 (dec-071)**: `delivery_tier` **NAO** carrega
`default` no `requestedSchema` — diferente de `atomic_commit`/`roadmap_mode`,
que mantem `default: "nao"` (desmarcado/negativo ja e a resposta segura).
Racional: separa "valor seguro quando ninguem responde" (aplicado pelo
**servidor** em cancel/decline/timeout — ver §Persistencia) de "valor
pre-selecionado na tela" (schema). Para o dado que governa gate de seguranca,
o segundo nao deve existir — sem `default`, `delivery_tier` nasce com
`required` **visivel** (`* not set`, vermelho — medido no Scenario 0),
forcando escolha explicita em vez de deixar `accept` no default passar
despercebido como se fosse escolha.

| Property | `type` | `enum` | Default seguro no schema |
|----------|--------|--------|---------------------------|
| `atomic_commit` | string | `["nao", "sim"]` | `nao` |
| `roadmap_mode` | string | `["nao", "sim"]` | `nao` |
| `delivery_tier` | string | `["local","internal-network","cloud-internal","cloud-public"]` | **nenhum** (aplicado pelo servidor, nao pelo schema) |

Uso de `enum` de string (nao `boolean`) para os tres, preservando a escolha
original: **medido** (Scenario 0, dec-071) que `enum` vira picker, porem
**colapsado** — exige a seta (`→ to expand`) para o operador ver as opcoes.
Isso alimenta o novo requisito do `message` abaixo.

### Campo `message` — aviso de risco de rebaixamento (H1, dec-047)

**Obrigatorio quando `delivery_tier` entra no formulario** (portanto:
`executionKind === "agente-00c"`) — **renderizacao confirmada** (dec-071,
ver abaixo).

O texto que adverte sobre o efeito de escolher um tier **menor** MUST viver no
campo `message` do `ElicitRequestFormParams`, **nao** em `title`/`description`
das propriedades. Razao (dec-047):

- **VERIFICADO**: `message` e campo **obrigatorio e nao-opcional** do schema —
  `message: z.ZodString` em `types.d.ts:4983`, dentro de
  `ElicitRequestFormParamsSchema` (`:4966`). Nao ha formulario valido sem ele.
- **MEDIDO (dec-071, Scenario 0)**: o cliente **renderiza** `message`
  integralmente, como primeira linha do formulario — ver bloco "Medido" abaixo.

O argumento que sustentava a escolha antes da medicao permanece valido a
fortiori agora que ambos os pontos estao confirmados: `message` e ao mesmo
tempo o campo que o protocolo **obriga** a existir e o campo cuja renderizacao
foi **medida** — o portador mais confiavel do aviso, frente a `title`/
`description` (opcionais, tambem medidos, mas nao carregam a obrigatoriedade
do schema).

Requisitos do texto (o conteudo exato e derivado da prosa existente, FR-002):

1. nomear o tier **vigente** no estado (`delivery-tier.sh get`) e o eixo do
   enum (menor ordinal = menos rigor de gate — `data-model.md` §Ordinal);
2. dizer explicitamente que escolher um tier menor **reduz a profundidade dos
   gates** que auditam a propria execucao;
3. nao conter instrucao ao modelo — e texto para o **operador**, transportado
   pelo servidor, nunca reinterpretado pelo orquestrador (FR-003);
4. **[NOVO — dec-071, requisito derivado do Scenario 0]** avisar
   explicitamente que o campo `delivery_tier` tem opcoes a **expandir**
   (`enum` colapsado atras da seta `→ to expand`). Motivo: com o ajuste (b)
   acima (`delivery_tier` sem `default`), o campo nasce `* not set`/vermelho
   quando colapsado — sem o aviso, o operador pode nao perceber que ha 4
   opcoes navegaveis atras da seta e simplesmente dar `Accept` deixando o
   campo sem valor, caindo no default seguro do servidor **por omissao**, em
   vez de fazer a escolha informada que o formulario existe para coletar.

**Medido (Constitution VI) — Scenario 0 executado pelo operador, dec-071**:
`message` **e exibido integralmente** ao operador, como primeira linha do
formulario ("MESSAGE_FIELD: ... ATENCAO: escolher um tier abaixo de
cloud-public reduz os gates de seguranca."). A premissa de H1 esta
**confirmada** — o consentimento informado de FR-002 tem portador no campo
obrigatorio do schema, sem depender de `title`/`description`.

**Medido — os quatro itens antes `[PROPOSTA]` (dec-071, Scenario 0)**:

| Item | Resultado medido |
|------|-------------------|
| `title` | vira **rotulo** do campo na UI (ex.: `TITLE_tier`) |
| `description` | vira **subtexto** (ex.: `DESC_tier`) |
| `default` | **pre-aplicado** no widget (campo aparece com valor inicial + check verde) |
| `required` | **so fica visivel** (`* not set`, em vermelho) quando o campo **nao** tem `default`; campos com `default` nao sinalizam obrigatoriedade mesmo se `required` |

**Consequencia de desenho nova, derivada da medicao (nao estava prevista)**:
`enum` renderiza **colapsado** — exige a seta (`→ to expand`) para o operador
ver as opcoes; o operador reportou dificuldade de usabilidade nesse passo.
Isso implica dois ajustes de contrato aplicados na FASE 3 (ver §Formulario
proposto e §Campo `message` abaixo): (a) o `message` passa a avisar
explicitamente que ha opcoes a expandir; (b) `delivery_tier` **nao** carrega
`default` no schema — assim ele nasce visivelmente obrigatorio (`* not set`),
e o default seguro `cloud-public` e aplicado pelo **servidor** em
cancel/decline/timeout, nunca pre-marcado na tela.

### Teto de tempo

`{ timeout: MCP_ELICIT_TIMEOUT_MS }`, default `300000` ms / 5 min
(dec-058, decisao do operador — CHK029; substitui a proposta original de
`120000` ms deste contrato).

- Satisfaz FR-010 **literalmente**: quem arma o relogio e quem envia a
  requisicao — o servidor.
- Override por env, espelhando o precedente VERIFICADO `MCP_MAX_TOOL_CALLS`
  (`index.ts:200`).
- O valor `300000` e **politica de design** (Constitution VI permite default
  razoavel para politica; nao para dado factual externo). Ao esgotar, os
  defaults seguros se aplicam e a execucao segue (dec-016) — nunca trava.

### Mapeamento resultado → desfecho

**VERIFICADO** (`types.d.ts:5394-5397`): `ElicitResult.action` e o enum fechado
`{ accept, decline, cancel }` e `content?: Record<string, string|number|boolean|string[]>`.

| Sinal observado | `outcome` |
|-----------------|-----------|
| capability `elicitation` ausente em `getClientCapabilities()` (**antes** da chamada) | `unavailable` (sem aviso) |
| `action === "accept"`, campo presente em `content` | `accepted` |
| `action === "accept"`, campo **ausente** em `content` | `absent` (default seguro) |
| `action === "decline"` | `declined` |
| `action === "cancel"` (envelope **retornado**) | `absent` |
| `McpError` code `RequestTimeout` (**excecao lancada**) | `timeout` |
| qualquer outra excecao | `failed` (**1** linha em stderr) |

---

## Persistencia (delegacao a helpers POSIX)

**VERIFICADO** — assinaturas lidas dos proprios scripts. Executadas por
`runHelper` (`runtime/exec.ts`), que usa `execFile` com `shell: false`
(`exec.ts:165-170`) — argv array, nenhum texto passa por shell (SEC-H1).

| Campo | Comando | Fonte |
|-------|---------|-------|
| `atomic_commit` | `commit-mode.sh set-enabled --state-dir <SD> --value <true\|false>` | `commit-mode.sh:184` |
| `roadmap_mode` | `roadmap-mode.sh set-enabled --state-dir <SD> --value <true\|false>` | `roadmap-mode.sh:15` |
| `delivery_tier` | `delivery-tier.sh set --state-dir <SD> --value <token> [--allow-downgrade]` | `delivery-tier.sh:22-27` |

**Invariante contratual C-2 (dec-037, emendada por dec-047 / H1)**: a flag
`--allow-downgrade` e **condicional**, nunca incondicional. Regra exata:

```
passa --allow-downgrade  ⟺  outcome === "accepted"
                         E  ordinal(resposta) < ordinal(tier vigente)
```

- **Necessaria** no caso majoritario: como a etapa (1) do init grava o maior
  ordinal (`cloud-public`), toda resposta diferente de `cloud-public` e
  rebaixamento e, **sem** a flag, retorna exit 2 **sem escrever**
  (`delivery-tier.sh:22-27`) — o defeito silencioso de R2.
- **Proibida** fora desse caso: resposta de ordinal igual (no-op idempotente)
  ou maior (elevacao) grava **sem** a flag; e para
  `outcome ∈ {declined, absent, timeout, unavailable, failed}` **nenhuma**
  chamada de escrita e emitida (C-3), logo nao ha flag a passar.

Consequencia de seguranca (dec-047): **os defaults seguros nao sao
rebaixamento**. Cancelamento por ausencia de operador, cancelamento por teto de
tempo e recusa explicita jamais produzem um `set` de rebaixamento — o unico
caminho que rebaixa o tier e a **escolha explicita** do operador no formulario.
O tier vigente para a comparacao de ordinal e lido de
`delivery-tier.sh get --state-dir <SD>` (nunca do campo cru — mesma disciplina
de `cli-delivery-tier.md`), imediatamente antes da escrita.

**Invariante contratual C-3 (I-3 de `data-model.md`)**: para
`outcome != accepted`, **nenhuma** chamada de escrita e emitida — o default
seguro ja foi gravado pela etapa (1) do init. Evita, entre outras coisas,
disparar a guarda write-once de `roadmap-mode.sh:142` sem necessidade.

**Exit codes relevantes dos helpers** (VERIFICADO):

| Helper | Exit | Significado |
|--------|------|-------------|
| `commit-mode.sh set-enabled` | 2 | `--value` fora de `true\|false` (`:201`) |
| `roadmap-mode.sh set-enabled` | 2 | write-once violado — ja ha onda posterior a `constitution` (`:142`) |
| `delivery-tier.sh set` | 2 | token fora do enum, ou rebaixamento sem `--allow-downgrade` (`:44-46`) |
| todos | 1 | falha de escrita no estado |

Exit != 0 em qualquer escrita ⇒ `outcome = failed` para aquele campo, `reason`
saneado via `sanitizeForLlmContext` (padrao VERIFICADO em
`get_status.ts:31-34`, teto `MAX_REASON_BYTES = 2048`).

---

## [PROPOSTA — emenda a `cli-delivery-tier.md` INV-4] (H2, dec-048)

> **Escopo**: isto e mudanca em contrato de **outra** feature
> (`docs/specs/delivery-tier/contracts/cli-delivery-tier.md` §2.2). Nada dela
> foi aplicado nesta onda — a edicao do arquivo alheio e **tarefa de
> `execute-task`**, e MUST ir junto do ajuste do teste no **mesmo commit**
> (ver `plan.md` §Resultado dos gates).

**Texto vigente** (`cli-delivery-tier.md:141-142`, regra 1 do MUST):

> 1. O orquestrador **nunca** invoca `delivery-tier.sh set` por conta propria
>    — nem para elevar, nem para rebaixar.

**Problema**: a regra proibe o **ato de invocar**, mas o invariante material
que o finding F5 (ASI03 Privilege Abuse + ASI01 Goal Hijack) protege e outro —
que o orquestrador **nao escolha o valor** do tier. Esta feature poe o
orquestrador como *chamador* de uma coleta em que o valor nasce **fora** do
contexto do modelo: a tool pede, o servidor emite `elicitation/create`, o
**cliente** renderiza, o **operador** escolhe, o **servidor** grava. O vetor
que o proprio §2.2 nomeia (injecao indireta por texto plantado em artefato
lido) pode, no maximo, fazer o orquestrador **disparar a pergunta** — nunca
**responde-la**.

**Reescrita proposta** da regra 1:

> 1. O orquestrador **nunca escolhe** o valor do tier, e **nunca** invoca
>    `delivery-tier.sh set` com um valor de origem propria — nem para elevar,
>    nem para rebaixar. Permitido: **disparar coleta mediada pelo operador**
>    (`collect_optins` → `elicitation/create`), em que o valor e escolhido pelo
>    operador no cliente e gravado pelo servidor. O que a regra proibe e o
>    **set direto**; nao o pedido de decisao ao humano.

**As regras 2-4 NAO seguem todas inalteradas** — duas entram em tensao com
este desenho e a emenda MUST trata-las, sob pena de deixar o contrato
emendado auto-contraditorio:

- **Regra 2** ("mudanca de tier so ocorre **entre ondas**, por acao do
  operador via `/agente-00c-resume`, sempre precedida de Decisao auditavel"):
  o caminho estruturado grava o tier **no init, antes da onda-001**, e **nao**
  via `/agente-00c-resume`. Emenda proposta: admitir explicitamente a **coleta
  de inicio de execucao** como segunda janela legitima, ao lado de "entre
  ondas" — ambas mantendo o requisito de que a escolha seja do operador e
  fique registrada.
- **Regra 3** (`review-task` reporta `delivery-tier-unattended-change` para
  "qualquer alteracao do tier sem Decisao de operador correspondente"): no
  caminho estruturado nao existe a Decisao classica de operador registrada
  pelo resume — o registro de consentimento e a entrada em
  `.optin_responses[]` com `channel: "structured"` e `outcome: "accepted"`.
  Emenda proposta: nomear essa entrada como evidencia de consentimento
  **aceita** pela regra 3.

> **Por que isto importa mais do que parece**: a regra 3 e o **controle de
> deteccao** que o proprio §2.1 aponta como o controle real do F5 ("o plano nao
> deve prometer que o rebaixamento e impedido; ele e **detectavel**"). Deixar
> a regra 3 sem reconhecer a nova evidencia produz alarme falso em **toda**
> captura estruturada — e a saida provavel sob pressao seria **afrouxar a
> regra 3**, que e exatamente o controle que nao pode ser afrouxado. A emenda
> preserva o alarme e apenas ensina a ele qual evidencia conta.

**Regra 4 segue inalterada**: elevacao nao-solicitada continua proibida — a
coleta mediada nao e "nao-solicitada", e o operador escolhe a direcao.

**Por que esta emenda nao afrouxa F5**: sob o caminho mediado, um texto
plantado em artefato so consegue induzir uma **pergunta ao operador** — e uma
pergunta a mais e visivel, auditavel (`.optin_responses[]` com
`channel: "structured"`) e reversivel. O caminho que F5 barra — o modelo
resolvendo sozinho para `local` a partir de texto lido — continua barrado, e
inclusive **mais** barrado que no caminho de prosa atual, onde o modelo
interpreta texto livre do operador.

**Entregaveis acoplados** (mesmo commit, senao a emenda vira texto sem gate):

1. reescrita das regras **1, 2 e 3** em `cli-delivery-tier.md` §2.2 (regra 4
   inalterada);
2. ajuste do cenario que a assere hoje —
   `tests/test_command-spawn-delivery-tier.sh:87-90`
   (`scenario_resume_documenta_inv4_operador`, assercao textual
   `'por iniciativa do proprio orquestrador'`) — para cobrir a distincao
   **escolha/set direto** x **disparo de coleta mediada**, em vez de casar so
   a frase antiga.

---

## Gate de composicao (dec-029)

**VERIFICADO**: `tests/test_orchestrator-allowlist-guard.sh:281-287` lista
`_required=` com as 7 tools atuais e `:307` falha com `mcp_tools_missing`. O
cenario se chama `scenario_allowlist_declara_as_7_tools_mcp` (`:275`).

Entregavel obrigatorio ao introduzir a tool:

1. `collect_optins` entra em `_required`.
2. Cenario renomeado para refletir 8 tools.
3. `mcp__cstk-state__collect_optins` entra na frontmatter `tools:` dos **dois**
   orquestradores.
4. `:317` `scenario_allowlist_preserva_bash` continua verde (`Bash` preservado).

Sem o passo 1, a tool nova nasce **fora de qualquer gate** — o guard verifica
presenca, nao cardinalidade.
