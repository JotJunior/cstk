# Contrato: tool MCP `ask_operator` (human-bridge, superficie 1)

Tool MCP **bloqueante** que faz uma pergunta ao operador e espera a resposta
chegar pelo painel (`cstk-panel`). Nao usa `elicitation/create` e nao usa hook.

**Legenda de veracidade (Principio VI)**: `[MEDIDO]` = medido empiricamente
nesta linha de trabalho (evidencia em [`../spikes/README.md`](../spikes/README.md));
`[VERIFICADO]` = citacao literal de fonte no repo; `[PROPOSTA]` = desenho novo,
ainda nao medido.

---

## 1. Identidade e escopo

Nome MCP: `mcp__cstk-state__ask_operator`. Seria a **9a** `registerTool` de
`mcp/state-server/src/index.ts` (hoje ha 8) `[VERIFICADO]`.

Esta e a **superficie 1** da human-bridge: pergunta que o AGENTE faz, cuja
resposta vem do painel. Fora do escopo deste contrato:

| # | Superficie | Mecanismo | Por que nao esta aqui |
|---|-----------|-----------|-----------------------|
| 2 | Gate de `PreToolUse` (comando perigoso) | hook | Ja existe portador: `pretooluse-bash-guard.sh` |
| 3 | Elicitation levantada por OUTRO servidor MCP | hook `Elicitation` | Nao passa pelo `cstk-state` |

**Por que nao `elicitation/create`**: o cliente Claude Code nao suporta url
mode, e form mode renderiza na TUI — que e o oposto do requisito. Detalhe e
evidencia medida em [`../spikes/README.md`](../spikes/README.md).

---

## 2. Request

| Campo | Tipo | Obrig. | Notas |
|-------|------|--------|-------|
| `session_id` | string | **sim** | Roteamento. Resolucao exclusivamente pelo id da PROPRIA chamada `[VERIFICADO: contracts/server-session-resolution.md A-1/A-4 da feature mcp-direct-transport]`. `execution_id` NAO serve — nao e unico entre projetos. |
| `question` | string | **sim** | Texto exibido ao operador. |
| `kind` | `"choice"` \| `"confirm"` \| `"text"` | **sim** | Enum fechado. |
| `options` | array\<string\> | so em `choice` | Enum fechado das respostas aceitas. |
| `default_value` | string | **sim** | Valor seguro aplicado em TODO desfecho != `answered`. Sem ele a tool vira trava. |
| `timeout_ms` | number | nao | Validado contra a faixa **derivada** da R-CLOCK-4, cujo piso nesta superficie e `ASK_MIN_TIMEOUT_MS` (R-CLOCK-7). Valor fora da faixa cai no **default**, nunca clampado para a borda. |

---

## 3. Response (envelope de tool)

Mesma forma das tools existentes `[VERIFICADO: interface GetStatusResponse,
mcp/state-server/src/tools/get_status.ts:56-62 — campos outcome/reason/stage/result]`.

```
{ outcome: "accepted" | "rejected",
  reason:  string | null,
  stage:   "precondition" | "delegation" | null,
  result:  ResultAskOperator | null }
```

`ResultAskOperator` `[PROPOSTA]`:

| Campo | Tipo | Descricao |
|-------|------|-----------|
| `channel` | `"panel"` | Ver invariante C-5. |
| `outcome` | `answered`\|`declined`\|`timeout`\|`unavailable`\|`failed` | Ver §5. |
| `applied_value` | string | Valor efetivamente gravado (token fechado). |
| `question_id` | string | Correlator, gerado pelo servidor. |
| `untrusted_text` | string \| null | SOMENTE em `kind:"text"`. Ver §6. |

`rejected` e reservado a falha de pre-condicao:

| `reason` (prefixo) | Quando |
|--------------------|--------|
| `SESSION_MISMATCH` | token ausente/divergente/execucao terminal `[VERIFICADO: fail-closed, session/resolve.ts:40-46, "NUNCA cai em fallback para 'a execucao ativa mais provavel'"]` |
| `TOOL_CALL_LIMIT_EXCEEDED` | teto de chamadas do processo `[VERIFICADO: index.ts:209-218]` |

---

## 4. Politica de relogios

Ha **tres** relogios independentes; o menor vence. Os dois do cliente sao hard
wall-clock e **progress notifications NAO estendem**
`[VERIFICADO: descricao literal do campo `timeout` por servidor no cliente —
"Hard wall-clock limit per call; progress notifications do not extend it"]`.

| Relogio | Onde | Valor |
|---------|------|-------|
| Teto do servidor | `MCP_ASK_TIMEOUT_MS` | default **240000** ms `[PROPOSTA]` |
| Teto total do cliente | `timeout` por servidor no `.mcp.json` | **300000** ms `[PROPOSTA]` |
| Ociosidade do cliente | `CLAUDE_CODE_MCP_TOOL_IDLE_TIMEOUT` | default stdio **1800000** ms `[MEDIDO]` |

Sem provisionamento nenhum, quem governa e a **ociosidade**: o teto total
default e efetivamente sem teto e nunca morde `[MEDIDO: tool bloqueante
dormindo 31,7 min abortou aos 1815s com "sent no response or progress for
1815s; aborting"]`. A combinacao proposta cabe dentro dessa janela mesmo se
ninguem provisionar nada — mas **provisione assim mesmo**: 30 min e default
NAO DOCUMENTADO do cliente e pode mudar entre versoes sem aviso.

### R-CLOCK-1 (obrigatoria) — ordem dos tetos

`MCP_ASK_TIMEOUT_MS` MUST ser estritamente MENOR que o `timeout` por servidor
do cliente.

### R-CLOCK-2 (obrigatoria) — folga minima de 60000 ms

A folga entre os dois MUST ser >= **60000** ms.

**Motivo — e ele precisa sobreviver a refactor**: o watchdog de ociosidade do
cliente tem granularidade de ~30s e so aborta no primeiro tique DEPOIS de
estourar. `[MEDIDO em duas escalas: configurado 10000 ms => abortou aos 30s;
default 1800000 ms => abortou aos 1815s]`. A mensagem de erro reporta o
silencio DECORRIDO, nao o valor configurado — o que faz um debug ingenuo
concluir o valor errado. Logo todo teto do cliente tem overshoot de ate ~30s.
`60000 = 30000 de overshoot + 30000 de margem`. **Otimizar essa folga para um
valor menor reintroduz o modo de falha da R-CLOCK-3.**

### R-CLOCK-3 — por que a ordem importa

Se o CLIENTE matar primeiro, a chamada vira **erro** no contexto do modelo, o
servidor nunca chega a aplicar `default_value` nem a persistir, e a invariante
C-1 e violada exatamente no caso que ela existe para cobrir. Com o servidor
desistindo primeiro, ele aplica o default, grava, e devolve `accepted` — o
modelo nunca ve erro.

### R-CLOCK-4 — faixa DERIVADA, nunca fixada

A faixa valida de `MCP_ASK_TIMEOUT_MS` e:

```
[ ASK_MIN_TIMEOUT_MS , client_timeout_ms - 60000 ]
```

Com `ASK_MIN_TIMEOUT_MS = 60000` (R-CLOCK-7) e `client_timeout_ms = 300000`, isso
da **[60000, 240000]** — e o default 240000 e o **topo** da faixa, o que e
coerente por construcao.

**Os dois extremos sao derivados, nenhum e literal.** O piso vem da constante
nomeada da R-CLOCK-7; o teto, de `client_timeout_ms` menos a folga da R-CLOCK-2.
Fixar qualquer um dos dois como numero escrito no codigo reintroduz o modo de
falha descrito abaixo.

A faixa MUST ser **derivada** de `client_timeout_ms`, nunca escrita como
constante literal. Motivo: uma faixa fixada permite configuracao ILEGAL pela
letra do proprio contrato (um teto de servidor dentro da faixa mas com folga
< 60000 viola a R-CLOCK-2), e qualquer mudanca futura no `timeout` do
`.mcp.json` reintroduziria a inconsistencia silenciosamente.

Valor fora da faixa cai no **default**, nao e clampado para a borda `[PROPOSTA;
espelha o precedente VERIFICADO de parseElicitTimeoutMs, collect_optins.ts:196-205]`.

### R-CLOCK-5 — validacao na subida, nao no leitor do contrato

O servidor MUST validar a combinacao no boot e **recusar-se a subir** quando
ela for ilegal, em vez de confiar em quem leu este documento.

Para validar, o servidor precisa CONHECER `client_timeout_ms` — e ele nao tem
como ler o `.mcp.json` de forma confiavel. Logo o valor e **declarado ao
servidor pelo mesmo provisionamento que configura o cliente** `[PROPOSTA]`:

```jsonc
"cstk-state": {
  "type": "stdio",
  "command": "<launcher>",
  "args": [],
  "timeout": 300000,                                  // relogio do CLIENTE
  "env": { "CSTK_CLIENT_TOOL_TIMEOUT_MS": "300000" }  // o MESMO valor, para o SERVIDOR
}
```

Os dois campos MUST ser escritos juntos, a partir de **um unico valor-fonte**
em `cli/lib/mcp.sh`, para que nao possam divergir.

Degradacao quando `CSTK_CLIENT_TOOL_TIMEOUT_MS` esta ausente (servidor
registrado a mao, ou `.mcp.json` de instalacao anterior): o servidor **NAO**
recusa subir — ele assume o teto conservador `240000` e emite **1** linha de
aviso em stderr. Recusar subir por ausencia de uma variavel opcional
transformaria um upgrade em outage; recusar subir por combinacao explicitamente
ilegal e o comportamento correto. A distincao e deliberada.

### R-CLOCK-6 — `0` nao e solucao

`CLAUDE_CODE_MCP_TOOL_IDLE_TIMEOUT=0` (desliga a ociosidade) MUST NOT ser
documentado como remedio. Remove a unica defesa contra servidor travado — uma
chamada fica pendurada para sempre e a sessao junto. E e desnecessario: o
`timeout` por servidor da janela longa E limitada, com erro legivel quando
estoura `[MEDIDO: "timeout":60000 sobrepos CLAUDE_CODE_MCP_TOOL_IDLE_TIMEOUT=10000
hostil e a tool de 45s completou]`.

### R-CLOCK-7 (obrigatoria) — `ASK_MIN_TIMEOUT_MS`, o piso desta superficie

```
ASK_MIN_TIMEOUT_MS = 60000   // ms  [PROPOSTA]
```

Constante nomeada, **propria da superficie `ask_operator`**. `timeout_ms` abaixo
dela e tratado como fora da faixa (R-CLOCK-4): cai no **default** (`240000`),
**nunca** e clampado para a borda `[PROPOSTA; espelha o precedente VERIFICADO de
parseElicitTimeoutMs, collect_optins.ts:196-205]`.

**Justificativa propria — e ela e o conteudo da regra, nao enfeite**: 60000 ms e
a janela minima plausivel para um humano notar a fila, ler a pergunta com a
procedencia exigida pelo §11.7 do contrato do painel, e responder. Abaixo disso a
espera nao e consulta, e formalidade: o desfecho `timeout` fica praticamente
garantido e o agente colhe o proprio `default_value` deixando trilha que **parece**
consulta humana. Esse e exatamente o achado **F1 (HIGH)** do gate `owasp-security`
sobre o `plan` — a defesa e temporal, nao textual.

**NAO derivar dos `60000` da R-CLOCK-2.** A coincidencia numerica e coincidencia:
la o numero significa *overshoot de ~30s do watchdog de ociosidade + 30s de
margem*, e muda se o comportamento do watchdog do cliente mudar; aqui significa
*janela minima de resposta humana*, e muda se a ergonomia da fila mudar. Sao duas
grandezas sem relacao causal. Acoplar as duas por um `const` compartilhado — ou
por um comentario dizendo "mesmo valor da R-CLOCK-2" — faz o primeiro ajuste
legitimo de uma delas corromper a outra em silencio. **Duas constantes, dois
porques, duas vidas.**

**Piso separado do `collect_optins`, tambem de proposito.** `MIN_ELICIT_TIMEOUT_MS
= 5000` continua valendo intacto na sua superficie `[VERIFICADO: collect_optins.ts]`
— la o portador e um formulario nativo que ja esta na frente do operador, e 5 s e
plausivel. Aqui o portador e uma fila que o operador pode nem estar olhando.
Superficies com ergonomia diferente MUST ter pisos diferentes; unifica-los seria
escolher o piso errado para uma das duas.

**Override**: se uma variavel de ambiente para ajustar este piso vier a existir,
seu nome e comportamento sao `[PROPOSTA]` ainda **nao decididos** — este contrato
NAO os fixa. Ate que sejam decididos, `ASK_MIN_TIMEOUT_MS` e constante do
servidor, sem override.

**Contrapartida aceita e declarada**: um piso de 60 s torna impossivel uma
pergunta legitimamente curta (ex.: confirmacao que o operador ja esta esperando).
O operador aceitou esse custo — a alternativa (permitir janela curta e detectar
abuso so depois) foi rejeitada como defesa unica. A auditoria da §7 e o
**segundo** anel, nao o primeiro.

---

## 5. Mapeamento sinal -> desfecho

| Sinal observado | `outcome` |
|-----------------|-----------|
| painel entrega resposta | `answered` |
| painel entrega recusa explicita | `declined` |
| teto do SERVIDOR estoura (excecao lancada) | `timeout` `[MEDIDO: McpError code -32001, "MCP error -32001: Request timed out"]` |
| painel inalcancavel, detectado ANTES de esperar | `unavailable` |
| qualquer outra excecao | `failed` + **1** linha em stderr |

**Nao existe `absent` nesta superficie.** `absent` e o envelope `cancel` do
protocolo de elicitation; aqui nao ha envelope — ou o painel responde, ou e
`timeout`. Diferenca **deliberada** entre as superficies, registrada para nao
ser lida como esquecimento.

A discriminacao continua sendo pelo **mecanismo** (envelope retornado x
excecao lancada), nunca por tempo decorrido `[VERIFICADO: research.md
Decision 6 da feature mcp-elicitation-optins]`.

---

## 6. `kind:"text"` — conteudo UNTRUSTED

`text` esta **na v1** (decisao do operador). Motivo de existir: sem ele a tela
de validacao de dados so sabe **aprovar ou bloquear**, nao sabe **CORRIGIR** —
e corrigir e o Principio VI virando acao em vez de parada.

### R-TEXT-1 — rotulo ESTRUTURAL

O texto livre volta em campo PROPRIO do envelope (`untrusted_text`), NUNCA
embutido em `applied_value` e NUNCA como prefixo de string. Em `kind:"text"`,
`applied_value` carrega o token de desfecho, nao o texto.

*Motivo*: prefixo de string o modelo ignora ou reinterpreta; campo estrutural
ele nao consegue confundir com o valor. Mesma disciplina do `recall --context`
e do TextRaw do painel.

### R-TEXT-2 — tamanho

Teto de **2048 bytes UTF-8**, truncado por budget de bytes. Reusa o orcamento
ja existente `[VERIFICADO: REASON_MAX_BYTES = 2048, audit/log.ts:66]` em vez
de introduzir numero novo.

### R-TEXT-3 — scrub na entrada

`secrets-filter.sh scrub` aplicado **uma unica vez**, na entrada, antes de
qualquer uso. E o valor **escrubado** que persiste, que volta no envelope e
que alimenta a linha de log — nunca o cru, e nunca dois subprocessos de scrub
`[VERIFICADO: mesma disciplina L1 do campo reason, collect_optins.ts:394-408]`.
Strip de caracteres de controle + truncamento aplicados junto.

> **CORRECAO (2026-08-29) — as duas lacunas citadas aqui estao FECHADAS.** A
> redacao anterior deste bloco afirmava, como `[VERIFICADO]` com medicao de
> 2026-08-27, que `printf 'password=hunter2' | scrub` devolvia o valor em claro
> (quantificador `{20,}`) e que blocos PEM atravessavam intactos. **As duas
> afirmacoes sao falsas hoje** — a issue #169 as fechou na v9.4.0. Medido agora,
> no script do repo:
>
> | Entrada | Saida `[MEDIDO 2026-08-29]` |
> |---------|------------------------------|
> | `printf 'password=hunter2' \| scrub` | `password=[REDACTED]` |
> | bloco `-----BEGIN PRIVATE KEY-----` ... `-----END PRIVATE KEY-----` | `[REDACTED-PEM-BLOCK]` |
>
> Mecanismo, no script: a **regra 4b** replica a forma da regra 4 com limiar
> `{4,}` sobre uma lista separada de palavras-chave de alta confianca
> `[VERIFICADO: secrets-filter.sh:228, quantificador `{4,}`; comentario :214-215
> nomeia a issue #169 e o caso `password=hunter2`]`; a **regra 0** detecta blocos
> PEM por RFC 7468 (marcador sozinho na linha) e vem PRIMEIRO
> `[VERIFICADO: secrets-filter.sh:167 e :181, `print "[REDACTED-PEM-BLOCK]"`]`.
>
> **O requisito NAO muda — mudou o motivo.** As tres defesas restantes (teto de
> 2048 bytes R-TEXT-2, rotulo estrutural R-TEXT-1, fronteira valor-vs-instrucao
> R-TEXT-4) **permanecem obrigatorias**, e nao como redundancia.
>
> **A cobertura do filtro segue sendo o PISO, nao a garantia** — agora por
> principio, nao por uma lacuna especifica que se possa "esperar ser corrigida".
> O proprio script declara isso na sua fonte: *"Cobertura e PISO, nao garantia:
> um segredo curto sob palavra-chave nao listada continua passando"*
> `[VERIFICADO: secrets-filter.sh:226-227]` — e `pwd`, `key`, `token` e `auth`
> genericos ficam **deliberadamente de fora** da lista `{4,}` para nao redigir
> prosa comum `[VERIFICADO: secrets-filter.sh:221-224]`. Um filtro de segredos e
> uma allowlist de formatos conhecidos; ele nunca reconhece o formato que ainda
> nao viu. O desenho **NAO PODE** tratar "passou pelo scrub" como "nao contem
> segredo" — em `untrusted_text` o valor vem de humano colando de sistema
> externo, que e exatamente o cenario que motiva a regra.

### R-TEXT-4 — VALOR sim, INSTRUCAO nao

A fronteira nao e "vai ou nao vai ao artefato". E **valor versus instrucao**:

| Uso | Permitido? |
|-----|-----------|
| virar **valor de um campo** num artefato (spec, plan, contrato, tasks) | **SIM** — e o caso de uso |
| virar **instrucao**: concatenado em prompt de etapa seguinte, mensagem de commit, corpo de PR, ou qualquer texto que descreva o que fazer a seguir | **NAO** |

O caminho permitido e seguro porque o texto foi digitado por um humano que o
viu na tela, esta limitado a 2048 bytes (R-TEXT-2), ja passou por scrub
(R-TEXT-3), e o artefato ainda atravessa os gates de review que ja existem.

> Formulacao anterior desta regra ("nenhum consumidor pode concatena-lo (...)
> ou em qualquer texto que o modelo va executar" + "se precisar ir para um
> artefato, vai citado e rotulado") era **larga demais** e neutralizava o
> proprio `kind:"text"`: uma correcao de `route.path` que nunca chega ao
> artefato, ou chega "citada", nao corrige nada — reintroduzia o `text` que
> relata mas nao conserta, que e a opcao que o operador rejeitou.

### Motivo dos quatro requisitos

**O risco nao e o operador ser hostil.** E que, na validacao de dados, a pessoa
esta **colando valores vindos de sistemas externos** — que e precisamente onde
conteudo injetado entra. O que impede isso de virar ataque nao e nunca usar o
valor; e **nunca deixar o valor virar comando** (ASI09/LLM01).

Requisito sem o porque e requisito que morre no primeiro refactor — por isso o
motivo esta escrito aqui, e nao no commit.

---

## 7. Persistencia

Array irmao top-level **`.operator_answers[]`**, append-only.

**NUNCA** `.optin_responses[]`: aquele tem chave natural `(execution, field)`
com enum fechado de 3 campos e e lido pela guarda que recusa abrir a onda-001
`[VERIFICADO: Invariante I-2, state-ondas.sh:687-690]`. Polui-lo com perguntas
arbitrarias quebra a guarda.

Shape — os **mesmos 6 campos** de `StoredOptinResponse`
`[VERIFICADO: collect_optins.ts:328-334]`, com `field` -> `question_id`:

```
{ question_id, channel, outcome, applied_value, recorded_at, reason }
```

Mais **dois** campos adicionais:

- `untrusted_text` — ja escrubado, sujeito a R-TEXT-2.
- `effective_timeout_ms` — **numero**, obrigatorio. A janela que de fato
  vigorou nesta pergunta, ja resolvida pela R-CLOCK-4/R-CLOCK-7 (ou seja: o
  `timeout_ms` pedido quando dentro da faixa, ou `MCP_ASK_TIMEOUT_MS` quando o
  pedido caiu fora dela). **Nao** e o valor pedido pelo agente — e o que o
  operador realmente teve para responder.

### R-AUDIT-1 (obrigatoria) — a janela efetiva e auditavel, e auditada

Registrar `effective_timeout_ms` e o **segundo** anel de defesa do achado F1
(HIGH) do gate `owasp-security`; o primeiro e o piso da R-CLOCK-7. O piso impede
a janela curta; a auditoria detecta o caso em que ela acontece assim mesmo — por
bug, por refactor que afrouxe o piso, ou por um caminho de configuracao que
ninguem previu.

`review-task` MUST reportar finding para **toda** entrada de `.operator_answers[]`
com `outcome = "timeout"` **e** `effective_timeout_ms < 60000`. Detalhe da regra
em [`../data-model.md`](../data-model.md) §"Auditoria da janela efetiva".

Por que o gatilho e a conjuncao das duas condicoes, e nao cada uma sozinha:
`timeout` com janela adequada e desfecho legitimo (o operador nao estava);
janela curta com `answered` significa que o humano respondeu mesmo assim, e a
trilha e verdadeira. So a **conjuncao** descreve o padrao que F1 nomeia — espera
curta demais colhendo o proprio default e passando por consulta.

Primitiva de escrita: a generica ja existente, **sem script novo** —
`state-rw.sh set --state-dir <SD> --field '.operator_answers' --value <json-array>`
(le `.operator_answers // []`, concatena, reescreve). Sob backend SQLite cai no
catch-all `execution.extra_fields`, reconciliado no `read` — mesmo precedente
de `.suggestions` `[VERIFICADO]`. Logo **nenhuma** edicao em `_state-rw-db.sh`,
e o Principio II segue PASS (nenhum script POSIX novo, nenhuma dep nova).

Regras de leitura, **identicas** as de `.optin_responses[]` para nao criar um
segundo dialeto:

- **R-1 (precedencia)**: vence o registro de maior `recorded_at`.
- **R-2 (terminalidade)**: `unavailable` e `failed` sao NAO-terminais (ninguem
  chegou a ser perguntado de fato); `answered`, `declined` e `timeout` sao
  terminais.

Trilha de auditoria: **1** linha em `enforcement-log.jsonl` por resposta
persistida, `source: "mcp-ask-operator"`, best-effort, **nunca lanca**
`[VERIFICADO: mesmo contrato de appendOptinDecisionRecord, audit/log.ts]`.

---

## 8. Invariantes contratuais

**C-1 (herdada, intacta)** — `declined`, `timeout`, `unavailable` e `failed`
**NAO** sao erro de tool: retornam `outcome:"accepted"` com o desfecho dentro
de `result`. Transformar degradacao em erro faria o orquestrador tratar como
falha e potencialmente reter ou repetir.

**C-4 (nova)** — `default_value` e aplicado em TODO desfecho != `answered`, e o
registro e gravado ANTES do retorno. Nunca trava, nunca fica sem rastro.

**C-5 (nova)** — `channel` = `panel` nesta superficie (resposta vem do painel
direto, sem portador local). `panel-hook` fica **reservado** as superficies 2 e
3, onde o portador e mesmo o hook. Dois valores, cada um dizendo a verdade
sobre a procedencia. Reciclar `structured` faria o campo perder a unica funcao
que tem.

---

## 9. Provisionamento e cobertura

**Provisionamento**: `cli/lib/mcp.sh` monta o bloco `mcpServers.cstk-state`
com payload **estatico** (`type`/`command`/`args`), hoje **sem** `timeout` e
sem `env` `[VERIFICADO: cli/lib/mcp.sh:995-1005]`. Acrescentar ali o par
`timeout` + `CSTK_CLIENT_TOOL_TIMEOUT_MS` (R-CLOCK-5) faz `cstk mcp install`
entregar a janela correta sem exigir nada do operador.

**Cobertura**: `tests/test_orchestrator-allowlist-guard.sh` verifica **presenca
nominal** das tools obrigatorias numa lista `_required` — hoje ja com as 8
`[VERIFICADO: scenario_allowlist_declara_as_8_tools_mcp, :317 e :323-330]`. Uma
9a tool que nao entre na `_required` **e** nao seja declarada na frontmatter
dos DOIS orquestradores passa despercebida pelo teste, ficando sem cobertura
justamente na superficie nova.

---

## 10. Nao coberto (bloqueios declarados)

- **Teto do clamp de `MCP_TOOL_TIMEOUT` no cliente**: NAO medido. Irrelevante
  para este contrato — o `timeout` por servidor e o botao, e e explicito.
- **Transporte nao-stdio (http/sse)**: os defaults de ociosidade sao outros
  (300000 ms lido no binario do cliente, nao medido). Este contrato cobre
  stdio, que e o transporte do `cstk-state`
  `[VERIFICADO: mode=direct, execFile de node]`.
- **Long-poll ponta-a-ponta contra o painel**: `[MEDIDO]` (task 5.1.1,
  onda-012 do feature-00c, `human-bridge`). `mcp/state-server/test/
  bridge-e2e-real.test.ts` sobe `panel/apps/server/dist/index.js` como
  processo real (`node dist/index.js`, nao `server.inject()`) escutando
  numa porta real, com `bridge.db` sqlite real em arquivo tmp isolado, e
  chama `handleAskOperator` com `createBridgeClient` REAL (HTTP real via
  `fetch`, sem `bridgeClient` mockado). "Responder via painel" e simulado
  pela MESMA chamada `POST /api/v1/bridge/interventions/:id/answer` que a
  UI do painel usa. Resultado: `outcome=answered`, `applied_value` correto,
  e `.operator_answers[]` gravado via `state-rw.sh` REAL instalado
  (`~/.claude/skills/agente-00c-runtime/scripts/state-rw.sh`), confirmado
  por `state-rw.sh get --field .operator_answers`. Evidencia literal:
  `node --test dist/test/bridge-e2e-real.test.js` -> `tests 1 / pass 1 /
  fail 0` (~1.1s).

  Este teste tambem revelou (e corrigiu, mesmo commit) um defeito de boot
  REAL antes invisivel: `routes/bridge.ts` registrava `@fastify/cors` de
  novo num escopo aninhado, colidindo com o `@fastify/cors` global de
  `index.ts` (`FastifyError: FST_ERR_DEC_ALREADY_PRESENT
  ('corsPreflightEnabled')`, `@fastify/cors` decora `corsPreflightEnabled`
  incondicionalmente a cada registro, e Fastify nao permite redeclarar um
  decorator ja presente em qualquer ancestral da cadeia de encapsulamento).
  `test/routes/bridge.test.ts` nunca detectou isso porque registra
  `bridgeRoutes` ISOLADO, sem o cors global — exatamente a fronteira que
  este bloqueio ja apontava como nunca exercitada. Fix: `hasRequestDecorator
  ('corsPreflightEnabled')` detecta se ha cors ja ativo no ancestral; se
  sim, usa o mecanismo OFICIAL de override por rota do proprio
  `@fastify/cors` (`req.routeOptions.config?.cors`) via 2 rotas `OPTIONS`
  explicitas (mais especificas que a wildcard `'*'` do plugin) so para os 2
  endpoints POST da Ponte — o CORS global do resto da API nunca e alargado.
  Ainda **nao coberto**: automacao de browser real (a UI Web de fato
  clicando "responder") — fora do orcamento desta tarefa; o contrato HTTP
  exercitado e identico ao que a UI usa, mas o clique em si nao foi
  automatizado.
