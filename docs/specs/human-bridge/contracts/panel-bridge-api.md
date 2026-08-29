# Contrato: HTTP `/api/v1/bridge/*` (human-bridge, fronteira painel <-> servidor)

Fecha o buraco declarado na secao 10 de
[`mcp-tool-ask-operator.md`](mcp-tool-ask-operator.md): *"o caminho
painel<->servidor pertence ao `cstk-panel` e permanece sem medicao nesta linha de
trabalho"*. Este documento **complementa** aquele contrato; nao o reescreve.

**Legenda de veracidade (Principio VI)** — herdada e preservada:
`[MEDIDO]` = medido empiricamente | `[VERIFICADO]` = citacao literal de fonte no
repo, com `arquivo:linha` | `[PROPOSTA — a validar na implementacao]` = desenho
novo, ainda nao implementado.

> **Este contrato inteiro e `[PROPOSTA — a validar na implementacao]`**, exceto
> onde uma linha traz `[VERIFICADO]` explicito. Nenhum endpoint descrito aqui
> existe hoje: `panel/apps/server/src/routes/` contem 13 modulos e **nenhum**
> deles e `bridge` `[VERIFICADO]`, e todas as rotas de sessoes sao `.get()`
> `[VERIFICADO: panel/apps/server/src/routes/sessions.ts:114, :149]`.

---

## 1. Escopo e autorizacao constitucional

Primeira superficie **nao-`GET`** do painel. Autorizada exclusivamente pela
emenda 2.0.0 da constitution do painel (`panel/docs/constitution.md`,
Principio I, "A excecao da Ponte"), sob quatro MUST vinculantes:

1. escrita confinada a store proprio (`bridge.db`), conexao SEPARADA e read-write;
2. rotas nao-`GET` existem apenas sob `/api/v1/bridge/*`;
3. a Ponte MUST NOT gravar decisao/bloqueio/onda/estado de execucao no corpus —
   o registro canonico e do **agente**;
4. resposta roteada por `session_id`, nunca por `execution_id`.

**Como (4) e honrado sem o token atravessar HTTP**: ver `../data-model.md`
§"Achado de seguranca". O roteamento ocorre dentro da chamada MCP, antes de
qualquer HTTP; o painel e caixa-postal indexada por `questionId` e nao roteia nada.

**Registro**: as quatro rotas sao registradas por um unico `bridgeRoutes(server)`,
adicionado a lista do plugin `v1` ja existente
`[VERIFICADO: panel/apps/server/src/index.ts:74-92, `await server.register(async (v1) => { ... }, { prefix: '/api/v1' })`]`.
As rotas declaram caminho relativo (`/bridge/interventions`); o prefixo vem do plugin.

---

## 2. Convencao de case — a fronteira que precisa estar escrita

Ha **duas** convencoes nesta feature e elas se encontram no cliente HTTP do
servidor MCP. Declarar isso e o unico jeito de nao repetir o drift
snake_case/camelCase que custou 40 ondas numa execucao anterior deste toolkit.

| Camada | Case | Fonte da verdade |
|--------|------|------------------|
| Colunas de `bridge.db` | `snake_case` | `apps/server/src/db/bridge.ts` |
| Payload HTTP `/api/v1/bridge/*` (req **e** res) | `camelCase` | **este documento** |
| Envelope da tool MCP (`ResultAskOperator`) | `snake_case` | `mcp-tool-ask-operator.md` §3 |
| `.operator_answers[]` no state | `snake_case` | `../data-model.md` |

**Precedente do `camelCase` no HTTP** `[VERIFICADO: panel/apps/server/src/routes/tasks.ts]`
— o mapper de rota converte explicitamente: `executionId: r.execution_id`,
`testsRun: r.tests_run`, `lintOk: ...`, `touchedFilesCount: r.touched_files`.
A Ponte adota a MESMA convencao, sem excecao, para o cliente web ter um unico dialeto.

**Onde vivem os dois mappers** `[PROPOSTA]`:

| Fronteira | Arquivo | Responsabilidade |
|-----------|---------|------------------|
| `bridge.db` (snake) <-> HTTP (camel) | `panel/apps/server/src/routes/bridge.ts` | mesmo idioma de `routes/tasks.ts` |
| HTTP (camel) <-> envelope MCP + state (snake) | `mcp/state-server/src/bridge/client.ts` | **unico** arquivo que fala HTTP no servidor MCP |

Nao ha ORM nem auto-mapping em nenhum dos dois lados — a conversao e explicita e
grepavel, de proposito.

---

## 3. Envelope de resposta

Toda resposta usa o envelope padrao do painel
`{ data, meta: { degraded, reason, freshness, schemaVersion } }`, montado por
`wrapBridge()` `[PROPOSTA]`.

**`wrapBridge()` e distinto de `wrap()` de proposito**: a assinatura existente e
`wrap<T>(data, opts, dbPath, db)` e `computeFreshness` le `mtime` do corpus +
`max(ingested_at)` da `knowledge.db`
`[VERIFICADO: panel/apps/server/src/lib/envelope.ts]`. Chamar `wrap()` numa rota
de Ponte obrigaria a abrir a `knowledge.db` so para preencher frescor — acoplando
os dois stores e violando FR-017. `wrapBridge()` preserva a **forma** e troca a
**fonte**: `freshness` vem do `mtime` do `bridge.db` + `max(updated_at)` das
intervencoes.

**Degradacao (Principio II do painel, MUST)**: `bridge.db` ausente, ilegivel ou
com `quick_check` falhando responde **`200`** com `meta.degraded=true` e `reason`
proprio. **Nunca `5xx` por condicao de dado.** Erro de *validacao de request*
(`4xx`) continua sendo `4xx` — nao e condicao de dado.

**Headers**: `Content-Type: application/json` + `X-Content-Type-Options: nosniff`,
ja aplicado globalmente `[VERIFICADO: panel/apps/server/src/index.ts:54,
`void reply.header('X-Content-Type-Options', 'nosniff');`]`.

---

## 4. `POST /api/v1/bridge/interventions` — criar (chamador: servidor MCP)

Cria a intervencao **e** e o unico detector de indisponibilidade (FR-021).

### Request

```jsonc
{
  "projectPath":   "/abs/path/do/projeto",   // string, obrigatorio
  "project":       "cstk",                    // string, obrigatorio (basename, exibicao)
  "shortName":     "human-bridge",            // string|null (null em agente-00c)
  "executionKind": "feature-00c",             // "agente-00c" | "feature-00c"
  "kind":          "choice",                  // "choice" | "confirm" | "text"
  "question":      "texto exibido ao operador",
  "options":       ["a", "b"],                // array<string>, obrigatorio sse kind="choice"
  "defaultValue":  "a",                       // string, obrigatorio (C-4)
  "timeoutMs":     240000                     // number, obrigatorio — teto JA clampado pelo servidor MCP
}
```

**`sessionId` NAO existe neste payload.** Ausencia deliberada — ver §1.

Validacao por Zod na borda, no mesmo idioma das rotas existentes
`[VERIFICADO: panel/apps/server/src/routes/tasks.ts, `const QuerySchema = z.object({...})` + `safeParse`]`.
Payload invalido -> `400` com `reason` descritivo (nao e condicao de dado).

### Response `201`

```jsonc
{
  "data": { "questionId": "<CSPRNG>", "expiresAt": "2026-08-29T18:34:00Z", "state": "open" },
  "meta": { "degraded": false, "reason": null, "freshness": {...}, "schemaVersion": "1" }
}
```

`questionId` e gerado **pelo painel** (contrato §3 do `mcp-tool-ask-operator.md`:
"Correlator, gerado pelo servidor"), com CSPRNG. `expiresAt = now + timeoutMs`.

### FR-021 — esta chamada E o healthcheck

Falha de conexao, `5xx`, ou timeout desta chamada produz, **por si so**, o outcome
`unavailable` na tool. **MUST NOT** existir healthcheck dedicado, e
**MUST NOT** reusar `GET /api/v1/health` — ele mede a `knowledge.db`
`[VERIFICADO: panel/apps/server/src/routes/health.ts:2, "Rota GET /health — saude
do servidor e DB"; :20, "Caminho do arquivo knowledge.db"]`, que e o corpus, nao a
Ponte. Um painel com corpus saudavel e `bridge.db` quebrado responderia saudavel a
`/health` e a sessao esperaria por algo que nunca chega.

Timeout desta chamada `[PROPOSTA]`: `BRIDGE_CREATE_TIMEOUT_MS = 5000`, via
`AbortSignal.timeout(5000)`. Curto de proposito — e uma chamada loopback; 5 s ja
e ordens de grandeza acima do normal, e o custo de errar para o lado longo e a
sessao esperando enquanto o painel esta morto.

---

## 5. `GET /api/v1/bridge/interventions/:questionId` — polling (chamador: servidor MCP)

Polling curto, cadencia `BRIDGE_POLL_INTERVAL_MS = 1500` `[PROPOSTA]` (FR-019 —
"ordem de 1-2 segundos"; derivacao em `../research.md` Decision 5).
**Long-poll e proibido na v1** (FR-019, decisao do operador).

### Response `200`

```jsonc
{
  "data": {
    "questionId":    "<id>",
    "state":         "open",     // "open" | "answered" | "declined" | "expired"
    "appliedValue":  null,       // string|null — nao-null sse state em {answered, declined}
    "untrustedText": null,       // string|null — nao-null so em kind="text" + answered
    "resolvedAt":    null        // ISO 8601|null
  },
  "meta": { ... }
}
```

`404` se `questionId` desconhecido — o cliente MCP trata como `failed` (nao como
`unavailable`: o painel respondeu, so nao conhece o id).

**`state` e DERIVADO, nao coluna**: `resolution IS NOT NULL -> answered|declined`;
`now >= expires_at -> expired`; senao `open`. Nenhum `UPDATE` e disparado por este
`GET` — ver `../data-model.md` §"Estados derivados". FR-020 (sem expurgo, sem
scheduling) fica satisfeito sem nenhuma rotina periodica.

### Mapeamento `state` HTTP -> `outcome` do envelope MCP

| `state` (HTTP) | `outcome` (`ResultAskOperator`) | `applied_value` aplicado |
|----------------|----------------------------------|--------------------------|
| `answered` | `answered` | valor do operador |
| `declined` | `declined` | `default_value` (C-4) |
| `expired` **ou** teto do servidor estourou | `timeout` | `default_value` (C-4) |
| criacao falhou/expirou | `unavailable` | `default_value` (C-4) |
| qualquer outra excecao | `failed` + **1** linha em stderr | `default_value` (C-4) |

**C-1 (herdada, intacta)**: nenhum destes e erro de tool. Todos retornam
`outcome:"accepted"` no envelope, com o desfecho dentro de `result`.

**Nao existe `absent` nesta superficie** (contrato §5) — diferenca deliberada em
relacao a `collect_optins`, registrada para nao ser lida como esquecimento.

---

## 6. `GET /api/v1/bridge/interventions` — a fila (chamador: painel/UI)

Atende US1/FR-001/FR-014/FR-015.

**Query params** `[PROPOSTA]`: `state=open|resolved|all` (default `open`),
`project=<nome>`, `limit`/`offset` — paginacao **obrigatoria** pelos Padroes de
Seguranca do painel, reusando `safeParsePagination`
`[VERIFICADO: panel/apps/server/src/lib/pagination.ts, usado em routes/tasks.ts]`.

```jsonc
{
  "data": {
    "interventions": [{
      "questionId": "<id>", "project": "cstk", "shortName": "human-bridge",
      "executionKind": "feature-00c", "kind": "choice",
      "question": "texto UNTRUSTED", "options": ["a","b"], "defaultValue": "a",
      "state": "open", "reachable": true,
      "createdAt": "...", "expiresAt": "...", "waitingMs": 43000,
      "appliedValue": null, "untrustedText": null, "resolvedAt": null
    }],
    "pagination": { "limit": 50, "offset": 0 }
  },
  "meta": { ... }
}
```

Ordenacao default: `createdAt ASC` — quem espera ha mais tempo primeiro (Key
Entity "Fila de Intervencoes": "priorizada de forma a deixar claro o que esta
esperando ha mais tempo").

`waitingMs` e **derivado** (`now - createdAt`), nunca coluna — atende FR-014
("ha quanto tempo ela esta esperando") sem armazenar valor que envelhece.

`reachable` `[PROPOSTA]`: `false` quando `projectPath` nao existe mais em disco
(Edge Case "projeto removido"). A linha continua visivel — nao esconder historico —
mas a UI desabilita a acao de responder.

**Principio V do painel (UNTRUSTED)**: `question`, `options[]` e `untrustedText`
sao originados de agente/humano e MUST ser renderizados como **texto puro**, sem
interpretacao de HTML/markup ativo. A regra ja existe para os campos textuais do
corpus; a Ponte adiciona `question`/`untrustedText` ao conjunto coberto.

---

## 7. `POST /api/v1/bridge/interventions/:questionId/answer` — responder (chamador: painel/UI)

Atende US2/FR-002/FR-005/FR-006/FR-016.

### Request

```jsonc
{ "resolution": "answered", "value": "a", "text": null }
```

| Campo | Regra |
|-------|-------|
| `resolution` | `"answered"` \| `"declined"` — enum fechado |
| `value` | obrigatorio sse `resolution="answered"`. `kind="choice"`: MUST estar em `options` (FR-005). `kind="confirm"`: MUST ser `"yes"` ou `"no"` (reducao a sim/nao, FR-004). `kind="text"`: token de desfecho, **nunca o texto** (R-TEXT-1). |
| `text` | permitido **so** em `kind="text"`. Passa por strip de controle -> `secrets-filter.sh scrub` (UMA vez) -> truncamento a 2048 bytes UTF-8, **nesta ordem**, na ENTRADA. E o valor ja tratado que persiste. |

**FR-005 e validacao de servidor, nao de UI**: a rota MUST recusar `value` fora de
`options` mesmo que a UI ja restrinja. Uma UI e uma sugestao; a rota e a regra.

### Respostas

| Status | Quando |
|--------|--------|
| `200` | aplicado; devolve o estado final da intervencao |
| `400` | `value` fora de `options`; `text` presente com `kind != "text"`; shape invalida |
| `404` | `questionId` desconhecido |
| `409` | **ja resolvida** (`resolution IS NOT NULL`) **ou** ja expirada (`now >= expires_at`) — FR-016 |

### FR-016 / SC-006 — idempotencia por invariante de banco, nao por checagem

```sql
UPDATE interventions
   SET resolution = ?, applied_value = ?, untrusted_text = ?, resolved_at = ?
 WHERE question_id = ? AND resolution IS NULL AND expires_at > ?
```

O escritor verifica `changes === 1`. `changes === 0` -> `409`. Isso resolve os
dois Edge Cases de uma vez, sem `SELECT`-then-`UPDATE` (que teria janela de corrida):
- **duas pessoas respondendo simultaneamente**: a primeira vence, a segunda ve `409`;
- **resposta tardia apos expirar**: `expires_at > now` falha, `409`.

**`text` nunca vira instrucao (R-TEXT-4/FR-006)**: o painel armazena e devolve
`untrustedText` em **campo proprio** do envelope. Nenhum caminho de codigo o
concatena em prompt, mensagem de commit, corpo de PR ou qualquer texto que
descreva a proxima acao. Vira **valor de campo** num artefato — que e o caso de
uso — nunca comando.

---

## 8. Cliente web: mutacao NAO pode passar pelo `fetchApi` atual

`[VERIFICADO: panel/apps/web/src/lib/api.ts:58-113]` — `fetchApi(path, dataSchema, init)`
aceita `init?: RequestInit` (portanto aceitaria `method: 'POST'`), mas
**incondicionalmente**: le ETag armazenado e injeta `If-None-Match`; em `304`
devolve o corpo do `bodyCache`; no sucesso faz `bodyCache.set(path, data)`.

Reusa-lo para o `POST` de resposta faria o resultado de uma **mutacao** ser
cacheado por path e potencialmente devolvido de cache numa segunda submissao —
colidindo com FR-016/SC-006 exatamente no requisito que eles existem para garantir.

**Obrigatorio** `[PROPOSTA]`: funcao irma `mutateApi()` em `apps/web/src/lib/api.ts`,
sem nenhuma camada de ETag/cache, e invalidacao explicita do cache da fila apos
sucesso (`invalidateEtag('/bridge/interventions')` — funcao ja existente
`[VERIFICADO: api.ts:117]`).

Esse defeito **nao aparece** em teste com mock (mock nao tem `localStorage` nem
ETag). E por isso que o cenario "Roundtrip End-to-End" do `quickstart.md` faz
chamada real.

---

## 9. Auto-refresh da fila (FR-013)

`refetchInterval` do react-query, no padrao ja adotado pela tela de sessoes
`[VERIFICADO: panel/apps/web/src/lib/query.ts:8,26-27 — `AUTO_REFRESH_MS = 10_000`,
`refetchInterval: AUTO_REFRESH_MS`, `refetchIntervalInBackground: false`;
panel/apps/web/src/screens/Sessions.tsx:14 — "Tracking (`refetchInterval` explicito
via useSessions)"]`.

**Sem SSE, sem WebSocket**: nao existem no painel hoje, e o Principio VI da
constitution do painel desaconselha conexao de longa duracao. `AUTO_REFRESH_MS`
(10 s) e adequado para a fila — SC-002 mede o caminho de **volta** (clique ->
sessao), governado pelo polling de 1500 ms de §5, nao por esta cadencia.

---

## 10. Nao coberto (bloqueios declarados)

- **Autenticacao**: nenhuma. Herda o modelo do painel — bind em `127.0.0.1`
  `[VERIFICADO: panel/apps/server/src/config.ts:168, `host: '127.0.0.1', // FR-017: bind APENAS em localhost`]`,
  sem RBAC, sem multi-tenant. Consequencia **aceita e declarada**: qualquer
  processo local que alcance a porta pode listar e responder intervencoes. E o
  mesmo limite de confianca que ja vale para todo o painel; esta feature nao o
  estreita nem o alarga. Um modelo de auth seria mudanca de escopo do painel
  inteiro, nao desta feature.
- **Rate-limit nas rotas de Ponte**: nao proposto. `@fastify/rate-limit` hoje e
  aplicado so na busca FTS5 `[VERIFICADO: panel/apps/server/src/routes/search.ts:14,49]`,
  por ser custosa. As rotas de Ponte sao consultas por chave primaria. Se o
  polling de 1500 ms se mostrar problematico em uso real, o candidato e revisar a
  cadencia (§5), nao adicionar rate-limit contra o proprio chamador legitimo.
- **Multiplos painéis simultaneos na mesma maquina**: nao exercitado. Dois
  processos abrindo `bridge.db` rw ao mesmo tempo dependeriam de WAL + busy_timeout;
  fora do escopo da v1 e sem medicao nesta linha de trabalho.
- **Transporte nao-loopback**: nao coberto. `CSTK_PANEL_URL` permite apontar para
  outro host, mas nenhuma garantia (TLS, auth, integridade) foi desenhada ou
  medida para esse caso.

---

## 11. Achados do gate `owasp-security` incorporados (2026-08-29)

Esta secao foi acrescentada apos o gate de seguranca rodar sobre o plan. Cada
item vira MUST do contrato — nao e comentario.

### 11.1 `[VERIFICADO]` CORS global hoje permite SO `GET`/`OPTIONS` — a Ponte precisa de escopo proprio

`[VERIFICADO: panel/apps/server/src/index.ts:43-46]`:

```ts
await server.register(cors, {
  origin: config.corsOrigin,
  methods: ['GET', 'OPTIONS'],
});
```

Consequencia concreta, **nao hipotetica**: no modo dev documentado no proprio
comentario acima dessa chamada ("Vite em :5173 chamando a API em :3001"), o
preflight de um `POST` da UI para `/api/v1/bridge/*` seria **rejeitado** — a
propria tela de intervencoes nao conseguiria responder. Em producao porta-unica
(`build && start`) e mesma origem e CORS nao se aplica, entao o defeito **so
apareceria em dev**, que e o pior lugar para descobri-lo.

**MUST**: NAO alargar o `methods` global para incluir `POST`. Isso abriria
escrita CORS para toda a API, desfazendo a postura read-only que a lista restrita
expressa. **MUST**: registrar um escopo CORS proprio para o prefixo
`/bridge/*` com `methods: ['GET', 'POST', 'OPTIONS']`, no mesmo idioma do
rate-limit escopado que ja existe
`[VERIFICADO: panel/apps/server/src/routes/search.ts:49, `await scoped.register(rateLimit, {...})`]`.

### 11.2 `origin` restrito e controle de SEGURANCA, nao conveniencia de dev

Com a Ponte, o painel deixa de ser so um observador: um `POST` bem-sucedido
**dirige a decisao de um agente autonomo**. Isso eleva o valor de
`config.corsOrigin` de "detalhe de dev" para controle de seguranca
load-bearing — e a unica coisa que impede uma pagina web qualquer que o operador
visite de responder intervencoes via `fetch` para `127.0.0.1`.

- **MUST NOT**: `origin: true`, `origin: '*'`, ou reflexao do header `Origin` no
  escopo `/bridge/*`, em nenhuma circunstancia, nem "temporariamente para
  debugar". A allowlist e o controle.
- **MUST** (defesa em profundidade, CWE-352): as rotas de mutacao recusam
  (`415`) qualquer `Content-Type` que nao seja `application/json`. Corpo
  `text/plain` ou `application/x-www-form-urlencoded` e "simple request" e
  **nao dispara preflight** — sem esta regra, um parser de corpo adicionado no
  futuro reabriria o vetor CSRF em silencio.
- **SHOULD**: validar o header `Host` contra `127.0.0.1`/`localhost` no escopo
  `/bridge/*` (mitigacao de DNS rebinding).

### 11.3 `question` tambem passa por scrub — a assimetria atual e um vazamento

O desenho aplicava `secrets-filter.sh scrub` a `untrusted_text` (R-TEXT-3) mas
**nao** ao campo `question`. `question` e gerado por um agente cujo contexto pode
conter segredo (LLM02) — uma pergunta como "esta chave esta correta: <valor>?"
persistiria o valor em claro em `bridge.db` e o exibiria na fila.

**MUST**: `question` e cada elemento de `options[]` passam pelo **mesmo** pipeline
de entrada de `untrusted_text` — strip de controle -> `scrub` (UMA vez) ->
truncamento por budget de bytes — na criacao da intervencao. E o valor tratado
que persiste, e nunca dois subprocessos de scrub para o mesmo valor.

### 11.4 Permissoes de arquivo do `bridge.db`

`bridge.db` guarda texto livre digitado pelo operador. **MUST**: diretorio `700`
e arquivo `600`, best-effort, no mesmo idioma do precedente ja existente para o
corpus `[VERIFICADO: cli/lib/recall.sh:750-758, `recall_normalize_db_perms` —
"garante permissao 0600 ... Nunca bloqueia o caller"]`.

### 11.5 `CSTK_PANEL_URL` fora de loopback exige opt-in explicito

`CSTK_PANEL_URL` aceita qualquer URL. Um valor errado (typo, copy-paste de outro
ambiente) enviaria perguntas — que carregam contexto da execucao — em **texto
claro** para um host remoto, sem TLS, sem auth, silenciosamente.

**MUST**: o cliente HTTP recusa (com outcome `failed` + 1 linha em stderr) uma
base URL cujo host nao seja `127.0.0.1`, `::1` ou `localhost`, a menos que uma
segunda variavel de opt-in explicito esteja setada. **MUST NOT**: aceitar
`http://` para host nao-loopback em nenhuma hipotese.

### 11.6 Formato de `questionId` validado na borda

**MUST**: `:questionId` validado contra um formato estrito (ex.: `^[A-Za-z0-9_-]{22,64}$`)
antes de qualquer uso. E parametro de SQL (sempre via placeholder `?`, nunca
concatenacao), mas tambem compoe caminho de URL — validar na borda evita
comportamento de roteamento surpreendente e mantem a mensagem de erro uniforme.

### 11.7 Enquadramento da pergunta (ASI09) — mitigado, mas explicitamente

`question` vem de um agente que pode estar sob injecao indireta. A defesa nao e
tecnica, e de apresentacao: **MUST** a fila exibir, junto de cada pergunta, a
**procedencia** (`project`, `executionKind`, `shortName`) e o `defaultValue` que
sera aplicado se ninguem responder — os dois ja estao no payload de §6. O
operador precisa ver *quem* pergunta e *o que acontece se ele ignorar*, nao so o
texto da pergunta.
