# Contract: tool MCP `collect_optins`

Contrato da 8a tool do servidor `cstk-state`. Nome MCP exposto ao orquestrador:
`mcp__cstk-state__collect_optins`.

> **Estado deste contrato (Constitution VI)**: a tool **nao existe ainda** —
> todo o bloco de request/response abaixo e
> **[PROPOSTA — a validar na implementacao]**. O que e **VERIFICADO** e (a) o
> padrao de registro e envelope das 7 tools existentes, (b) a superficie do SDK
> (`elicitInput`, `ElicitResult`, `RequestOptions`), (c) os contratos dos
> helpers POSIX chamados. Cada bloco esta rotulado.

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
| `feature-00c` | sim | sim | **nao** (paridade de escopo preservada) |

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
derivados dos blocos de prosa existentes (FR-002), nao redigidos do zero:

| Property | `type` | `enum` | Default seguro |
|----------|--------|--------|----------------|
| `atomic_commit` | string | `["nao", "sim"]` | `nao` |
| `roadmap_mode` | string | `["nao", "sim"]` | `nao` |
| `delivery_tier` | string | `["local","internal-network","cloud-internal","cloud-public"]` | `cloud-public` |

Uso de `enum` de string (nao `boolean`) para os dois primeiros: o que esta
**medido** e que `enum` vira picker. `boolean` → checkbox **nao** esta medido.

**Nao medido — marcar como [PROPOSTA — a validar na implementacao]**:

- `title` virar label do campo na UI
- `description` virar subtexto/ajuda
- `required` marcar asterisco de obrigatoriedade
- `default` ser pre-aplicado no widget

O desenho **nao depende** de nenhum dos quatro: os defaults seguros sao
aplicados pelo **servidor** (nao pelo widget), e a ausencia de resposta cai em
`absent`/`timeout`. Se a validacao empirica mostrar que `title`/`description`
nao renderizam, o texto explicativo de FR-002 MUST migrar integralmente para o
campo `message` do formulario (que **e** medido como renderizado).

### Teto de tempo

**[PROPOSTA]**: `{ timeout: MCP_ELICIT_TIMEOUT_MS }`, default `120000` ms.

- Satisfaz FR-010 **literalmente**: quem arma o relogio e quem envia a
  requisicao — o servidor.
- Override por env, espelhando o precedente VERIFICADO `MCP_MAX_TOOL_CALLS`
  (`index.ts:200`).
- O valor `120000` e **politica de design** (Constitution VI permite default
  razoavel para politica; nao para dado factual externo).

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
| `delivery_tier` | `delivery-tier.sh set --state-dir <SD> --value <token> --allow-downgrade` | `delivery-tier.sh:22-27` |

**Invariante contratual C-2 (dec-037)**: a flag `--allow-downgrade` e
**obrigatoria** na chamada do tier. Sem ela, toda resposta diferente de
`cloud-public` e rebaixamento e retorna exit 2 **sem escrever**
(`delivery-tier.sh:22-27`).

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
