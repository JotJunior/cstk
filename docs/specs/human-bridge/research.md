# Research: Human Bridge (Intervencoes)

**Feature**: `human-bridge` | **Fase**: Phase 0 | **Data**: 2026-08-29

## Legenda de veracidade (Principio VI — obrigatoria)

Herdada de [`contracts/mcp-tool-ask-operator.md`](contracts/mcp-tool-ask-operator.md)
e preservada integralmente em todos os artefatos desta feature:

| Rotulo | Significado |
|--------|-------------|
| `[MEDIDO]` | Medido empiricamente; comando e saida literal citados |
| `[VERIFICADO]` | Citacao literal de fonte no repo, com `arquivo:linha` |
| `[PROPOSTA]` | Desenho novo, ainda nao medido nem implementado — **a validar na implementacao** |

Nenhuma afirmacao factual neste documento aparece sem um destes tres rotulos.

---

## Decision 0 — Correcao factual: as duas lacunas do scrub citadas no contrato estao FECHADAS

**Decision**: A afirmacao `[VERIFICADO]` da secao R-TEXT-3 do contrato — de que
`printf 'password=hunter2' | scrub` devolve o valor em claro e de que blocos PEM
atravessam intactos — **nao e mais verdadeira** no runtime atual. As tres defesas
complementares (teto de 2048 bytes, rotulo estrutural `untrusted_text`, R-TEXT-4)
**permanecem obrigatorias**, mas por um motivo diferente do escrito la.

**Evidencia** `[MEDIDO 2026-08-29, `plugins/cstk/skills/agente-00c-runtime/scripts/secrets-filter.sh`]`:

```
$ printf 'password=hunter2\n' | sh secrets-filter.sh scrub
password=[REDACTED]

$ printf -- '-----BEGIN PRIVATE KEY-----\nMIIBVgIBADANBgkqhkiG9w0BAQ\n-----END PRIVATE KEY-----\n' \
    | sh secrets-filter.sh scrub
[REDACTED-PEM-BLOCK]
```

Causa da divergencia `[VERIFICADO]`: o script ganhou (a) uma regra de blocos PEM
por RFC 7468 (`secrets-filter.sh:166` e seguintes, "Vem PRIMEIRO porque o corpo
base64 nao tem palavra-chave proxima... (issue #169)") e (b) uma regra separada de
alta confianca com quantificador `{4,}` (`secrets-filter.sh:228`), alem da regra
generica `{20,}` preexistente (`secrets-filter.sh:206`) que o contrato citou.

**Rationale**: propagar para o `plan.md` um `[VERIFICADO]` que deixou de valer
seria exatamente a classe de defeito que a constitution do painel corrigiu duas
vezes no mesmo dia (Sync Impact Reports 2.0.1 e 2.0.2: "primeiro afirmando um
mecanismo inexistente, agora omitindo o mais forte que existe"). O requisito nao
muda — muda o **porque**, e requisito com porque errado morre no primeiro refactor.

**Motivo correto para manter as tres defesas**: o scrub e um filtro por
heuristica de padrao. Ele cobre o que reconhece; **nao existe prova de que
reconheca tudo**, e o valor de `untrusted_text` vem de um humano colando de um
sistema externo — o cenario de maior variabilidade possivel. "Passou pelo scrub"
continua NAO significando "nao contem segredo". O teto de 2048 bytes limita o
volume do que vaza quando o filtro erra; o rotulo estrutural impede que o
conteudo seja reinterpretado como instrucao; R-TEXT-4 governa o uso. Nenhuma e
redundancia.

**Alternatives considered**:
- *Copiar a redacao do contrato como esta*: rejeitada — reintroduz afirmacao
  falsa num artefato novo, violando Principio VI da constitution raiz.
- *Reescrever o contrato `mcp-tool-ask-operator.md`*: rejeitada nesta fase — o
  contrato e insumo vinculante do `plan`, nao saida dele. A correcao fica
  registrada aqui e vira tarefa explicita de `create-tasks` (atualizar a nota
  R-TEXT-3 com a medicao de 2026-08-29).

---

## Decision 1 — Driver e conexao do `bridge.db`

**Decision**: `better-sqlite3` (mesmo driver do painel), em instancia
`new Database(bridgePath)` **sem** `readonly` e **sem** `query_only`, aberta em
modulo proprio `apps/server/src/db/bridge.ts` `[PROPOSTA]`.

**Evidencia da tecnologia** `[VERIFICADO]` — nao assumida, lida do codigo:
- `panel/apps/server/package.json:19` — `"better-sqlite3": "^12.4.1"`
- `panel/apps/server/src/db/open.ts:25` — `import Database from 'better-sqlite3';`
- `panel/apps/server/src/db/open.ts:100-101` — `new Database(dbPath, { readonly: true, ... })`
- `panel/apps/server/src/db/open.ts:121` — `db.pragma('query_only = 1');`

**Rationale**: a emenda 2.0.0 da constitution do painel exige "conexao SEPARADA e
read-write" para `bridge.db`. Separada quer dizer outra instancia `Database`, em
outro arquivo-fonte, sobre outro arquivo `.db` — nunca reuso da instancia de
`open.ts`, cuja unica funcao e ser somente-leitura. Introduzir um segundo driver
(node:sqlite, libsql) violaria o Principio IV da constitution raiz por adicionar
dependencia sem necessidade, e criaria dois dialetos de acesso a dados no mesmo
processo.

**Consequencia direta sobre o gate**: `panel/scripts/readonly-check.sh` varre
`apps/server/src` INTEIRO por `INSERT|UPDATE|DELETE|CREATE|DROP|ALTER`
`[VERIFICADO: readonly-check.sh, `SCOPE="${1:-apps/server/src}"` e `VERBS=`]`.
O primeiro `CREATE TABLE` de `bridge.ts` reprova o gate. O estreitamento do
escopo para `db/queries/**` + as duas verificacoes novas (unica conexao rw aponta
para `bridge.db`; toda rota fora de `/api/v1/bridge/*` responde so a `GET`) MUST
entrar no **mesmo commit** do primeiro codigo de `bridge/`, nunca antes — a
constitution e explicita ("o gate nao pode afrouxar enquanto nao existe o que ele
passa a permitir").

**Alternatives considered**:
- *Reusar a instancia de `open.ts` com um segundo `Database` interno*: rejeitada —
  acopla a Ponte a abertura do corpus; a queda de uma derrubaria a outra,
  violando FR-017 e o Principio II do painel.
- *Persistir em arquivo JSON em vez de SQLite*: rejeitada — a emenda 2.0.0 nomeia
  `bridge.db` explicitamente; e resposta concorrente (Edge Case "duas pessoas
  respondendo") exige atomicidade que arquivo JSON nao da.

---

## Decision 2 — Localizacao do `bridge.db` e descoberta

**Decision** `[PROPOSTA]`: `~/.claude/cstk/bridge.db`, override por
`CSTK_BRIDGE_DB`. Resolucao com a MESMA precedencia ja usada para o corpus:
config explicita > env var > default.

**Precedente** `[VERIFICADO: panel/apps/server/src/config.ts:6-7 e :77]` —
"1. Variavel de ambiente CSTK_KNOWLEDGE_DB (config explicita)";
`const fromEnv = process.env['CSTK_KNOWLEDGE_DB'];`.

**Rationale**: mesmo diretorio do corpus, arquivo distinto. Compartilhar o
diretorio nao compartilha o dado nem a conexao — e o diretorio ja e o lugar
canonico de estado global do cstk (`~/.claude/cstk/`), com permissao restritiva
ja normalizada pelo runtime do `recall`.

**FR-018 satisfeito por construcao, mas com guard obrigatorio**: `cstk recall
--reindex` varre raizes por `state.json`/`state-history` e por
`~/.claude/projects/*/memory/` `[VERIFICADO: cli/lib/recall.sh:235, :3456, :3521]`;
`--db` aponta explicitamente para `knowledge.db` `[VERIFICADO: recall.sh:177-188]`.
Um arquivo `.db` irmao nunca e alvo de varredura. Igualmente, `.operator_answers[]`
(Decision 5) e uma chave nova em `extra_fields` que nenhuma projecao de ingestao le.
Ambos os fatos sao verdadeiros **hoje** e frageis a mudanca futura — logo o plano
exige um **teste de regressao explicito** que asserta que nem `bridge.db` nem
`.operator_answers[]` aparecem em nenhuma tabela da `knowledge.db` apos
`--ingest` + `--reindex`.

**Alternatives considered**:
- *`bridge.db` dentro do state-dir da execucao*: rejeitada — a fila e
  CROSS-projeto (FR-001, US1); um store por execucao reintroduz exatamente o
  problema que a feature existe para resolver.

---

## Decision 3 — Nome e forma dos endpoints `/api/v1/bridge/*`

**Decision** `[PROPOSTA — a validar na implementacao]`: quatro rotas sob o
prefixo obrigatorio, registradas por um unico `bridgeRoutes(server)` no mesmo
plugin `v1` ja existente.

| Metodo | Rota | Chamador | Papel |
|--------|------|----------|-------|
| `POST` | `/api/v1/bridge/interventions` | servidor MCP | cria a intervencao; **e tambem o detector de indisponibilidade** (FR-021) |
| `GET` | `/api/v1/bridge/interventions/:questionId` | servidor MCP | polling curto ate `answered` (FR-019) |
| `GET` | `/api/v1/bridge/interventions` | painel (UI) | fila cross-projeto (FR-001) |
| `POST` | `/api/v1/bridge/interventions/:questionId/answer` | painel (UI) | resposta do operador (FR-002) |

**Evidencia do idioma de registro** `[VERIFICADO: panel/apps/server/src/index.ts:74-92]`
— `await server.register(async (v1) => { ... await v1.register(sessionRoutes); }, { prefix: '/api/v1' });`.
`bridgeRoutes` entra na mesma lista; as rotas declaram o caminho relativo
`/bridge/interventions`, e o prefixo `/api/v1` vem do plugin. Isso mantem a
clausula "rotas nao-`GET` existem apenas sob `/api/v1/bridge/*`" verificavel por
um grep unico sobre o arquivo de rotas.

**Rationale do recorte**: substantivo no plural + identificador no path + sub-recurso
`answer` para a acao — o mesmo formato de `GET /sessions/:sessionId/tail`
`[VERIFICADO: panel/apps/server/src/routes/sessions.ts:149]`, ja em producao no painel.
Nao inventa um dialeto novo de URL para a primeira superficie de escrita.

**Por que `POST` na criacao e nao `PUT`**: o `question_id` e gerado pelo servidor
(contrato §3, `ResultAskOperator.question_id` — "Correlator, gerado pelo
servidor"), logo o cliente nao conhece a URL final antes de criar. `PUT`
idempotente exigiria id gerado pelo cliente, contrariando o contrato ja fechado.

**Alternatives considered**:
- *`/api/v1/bridge/ask` + `/api/v1/bridge/answer` (verbos)*: rejeitada — quebra a
  convencao de recurso do restante da API e nao da URL estavel para o polling.
- *Long-poll em `GET /:questionId`*: **proibida por FR-019** (decisao do operador).

---

## Decision 4 — Nome da env var da base URL e o default 5173

**Decision** `[PROPOSTA — a validar na implementacao]`: `CSTK_PANEL_URL`, default
`http://127.0.0.1:5173`.

**Precedente de nomenclatura** `[VERIFICADO]`: o projeto ja usa o prefixo
`CSTK_` + substantivo para caminhos/recursos configuraveis — `CSTK_PANEL_DIR`
(diretorio de instalacao do painel), `CSTK_KNOWLEDGE_DB`
(`panel/apps/server/src/config.ts:77`), `CSTK_WEB_DIR` (`config.ts:90`),
`CSTK_PROJECT_PATHS` (`config.ts:121`). `CSTK_PANEL_URL` completa o par com
`CSTK_PANEL_DIR` sem colidir com nenhum nome existente.

**Justificativa do 5173 (nao 3001)** `[VERIFICADO — os dois lados]`:
- `cli/lib/serve.sh:897` — `_serve_port="${PORT:-5173}"`: e a porta que o
  operador de fato ve, porque `cstk serve` **exporta** `PORT` antes de subir o painel.
- `panel/apps/server/src/config.ts:167` — `port: parseInt(process.env['PORT'] ?? '3001', 10)`:
  3001 e o fallback interno do processo Node **quando ninguem exporta `PORT`** —
  condicao que nao ocorre no caminho suportado. Fixar 3001 como default do cliente
  MCP produziria `ECONNREFUSED` no fluxo normal, que o FR-021 traduziria como
  `unavailable` — falha silenciosa mascarada de degradacao correta.

**`127.0.0.1` e nao `localhost`**: o painel faz bind em `127.0.0.1` fixo
`[VERIFICADO: panel/apps/server/src/config.ts:168, `host: '127.0.0.1', // FR-017: bind APENAS em localhost`]`.
Usar o literal IPv4 elimina a dependencia de resolucao de `localhost` (que pode
resolver para `::1` e falhar contra um listener IPv4-only).

**CORS nao se aplica**: `corsOrigin` default e `http://localhost:5173`
`[VERIFICADO: config.ts:169]`, mas o chamador aqui e um processo Node
server-to-server, sem `Origin` — CORS e politica de navegador. Nenhuma mudanca em
`corsOrigin` e necessaria para a superficie MCP; ela **e** necessaria apenas se a
UI passar a chamar `/bridge/*` de uma origem diferente da ja permitida (nao e o caso).

**Alternatives considered**:
- *Ler porta de um arquivo descritor em disco*: **proibida por FR-022**
  ("MUST NOT depender de descoberta dinamica via arquivo de descritor em disco na v1").
- *`CSTK_BRIDGE_URL`*: rejeitada — a base URL e do painel inteiro, nao da Ponte;
  nomear pelo sub-recurso convidaria a uma segunda variavel para a mesma origem.

---

## Decision 5 — Intervalo de polling

**Decision** `[PROPOSTA — a validar na implementacao]`: `1500 ms` fixo, constante
nomeada `BRIDGE_POLL_INTERVAL_MS` no cliente HTTP do servidor MCP. Sem backoff,
sem jitter na v1.

**Faixa fixada pela spec**: FR-019 — "intervalo da ordem de 1-2 segundos".
1500 ms e o centro dessa faixa.

**Rationale quantitativo**: SC-002 exige que a resposta reflita na sessao de
origem em ate 10 s. Com 1500 ms, o pior caso de deteccao e 1,5 s + latencia de
uma chamada loopback — margem de ~6x sobre o criterio. No outro extremo, com o
teto de servidor default de 240000 ms (contrato §4), o numero maximo de GETs numa
espera completa e `240000 / 1500 = 160` — carga desprezivel para um Fastify local
que ja serve `refetchInterval` de 10 s por aba aberta
`[VERIFICADO: panel/apps/web/src/lib/query.ts:8, `AUTO_REFRESH_MS = 10_000`]`.

**Por que sem backoff**: backoff exponencial otimiza carga em espera longa, mas
aqui a espera longa e o caso ESPERADO (operador ausente) e a espera curta e a que
importa para a UX. Backoff degradaria exatamente o percentil que SC-002 mede.
Numa v2, se a carga se mostrar relevante, o candidato e long-poll — hoje proibido
por FR-019 — nao backoff.

**Alternatives considered**:
- *1000 ms*: aceitavel pela faixa; rejeitado por dobrar o numero de requisicoes
  (240 por espera completa) sem ganho perceptivel sobre SC-002.
- *2000 ms*: aceitavel pela faixa; rejeitado por ficar no limite superior sem
  folga se a faixa da spec for lida como inclusiva-exclusiva.
- *Reusar `AUTO_REFRESH_MS` (10 s)*: rejeitada — e a cadencia da UI, nao a do
  desbloqueio de sessao; 10 s consumiria o orcamento inteiro de SC-002.

---

## Decision 6 — Cliente HTTP no servidor MCP: `fetch` global, zero dependencia nova

**Decision** `[PROPOSTA]`: `globalThis.fetch` com `AbortSignal.timeout()`, em
modulo novo `mcp/state-server/src/bridge/client.ts`. **Nenhuma dependencia npm
nova.**

**Evidencia** `[VERIFICADO: mcp/state-server/package.json]` — `dependencies` tem
exatamente `@modelcontextprotocol/sdk` e `zod`; `engines.node` e `">=22"`.
Node >= 22 provê `fetch` e `AbortSignal.timeout` como globais estaveis, sem
polyfill nem import.

**Rationale**: o Principio II da constitution raiz (zero dependencia externa) e
NON-NEGOTIABLE para scripts POSIX e, por extensao de disciplina, o servidor MCP
manteve sua superficie de deps minima desde a origem. Adicionar `axios`/`undici`
por uma unica chamada loopback seria custo permanente por conveniencia pontual.

**Confinamento**: todo o codigo que fala HTTP com o painel vive nesse unico
arquivo — grep por `fetch(` no `mcp/state-server/src` deve retornar so ele. Isso
espelha a condicao (b) do carve-out de deps opcionais da constitution raiz
(emenda 1.1.0): dep localizavel por grep em um unico arquivo.

**Alternatives considered**:
- *`node:http` cru*: rejeitada — mais codigo para o mesmo efeito, sem `AbortSignal`
  ergonomico; `fetch` ja e o caminho suportado do runtime declarado.

---

## Decision 7 — `MCP_ASK_TIMEOUT_MS`: faixa DERIVADA (R-CLOCK-4) e o par de escrita unica (R-CLOCK-5)

**Decision** `[PROPOSTA]`: o servidor calcula a faixa em tempo de boot a partir de
`CSTK_CLIENT_TOOL_TIMEOUT_MS`, nunca de literais:

```
CLIENT_TIMEOUT_FLOOR_MS = 5000       // piso absoluto, herdado de MIN_ELICIT_TIMEOUT_MS
CLOCK_SAFETY_MARGIN_MS  = 60000      // R-CLOCK-2
min = CLIENT_TIMEOUT_FLOOR_MS
max = clientTimeoutMs - CLOCK_SAFETY_MARGIN_MS
default = max                        // topo da faixa, coerente por construcao
```

Com `clientTimeoutMs = 300000` isso rende `[5000, 240000]` e default `240000` —
os mesmos numeros do contrato §4, agora **derivados** em vez de escritos.

**Precedente do comportamento fora-da-faixa** `[VERIFICADO: mcp/state-server/src/tools/collect_optins.ts:196-205]`
— `parseElicitTimeoutMs` retorna o DEFAULT (nao clampa para a borda) quando o
valor e nao-numerico, nao-inteiro-seguro, ou fora de `[MIN, MAX]`. `parseAskTimeoutMs`
replica exatamente essa politica, so trocando as constantes por valores derivados.

**Rationale de R-CLOCK-4**: uma faixa literal permite configuracao ilegal pela
propria letra do contrato (teto dentro da faixa mas com folga < 60000), e qualquer
mudanca futura no `timeout` do `.mcp.json` reintroduziria a inconsistencia em
silencio. Derivar torna a R-CLOCK-2 estruturalmente inviolavel.

**R-CLOCK-5 — o buraco de provisionamento e real e esta localizado**
`[VERIFICADO: cli/lib/mcp.sh:995-1005]`, heredoc `MCPJSON` integral hoje:

```
{ "mcpServers": { "cstk-state": { "type": "stdio", "command": "$_mci_launcher", "args": [] } } }
```

Sem `timeout` e sem `env`. O plano exige acrescentar os DOIS a partir de **um
unico valor-fonte** — uma variavel de shell `_mci_client_timeout_ms` definida uma
vez e interpolada nos dois lugares do mesmo heredoc, de modo que divergir exija
editar um literal que nao existe.

**A env var atravessa o launcher sem trabalho adicional**
`[VERIFICADO: plugins/cstk/skills/agente-00c-runtime/scripts/mcp-launch.sh:276-279]`
— o launcher exporta duas variaveis proprias e faz `exec node "$_ml_entrypoint"`;
`exec` preserva o ambiente herdado, logo `CSTK_CLIENT_TOOL_TIMEOUT_MS` posto pelo
harness a partir de `.mcp.json` chega ao processo Node sem repasse explicito.

**Degradacao na ausencia da env var** (contrato §4, R-CLOCK-5): o servidor **nao**
recusa subir — assume `clientTimeoutMs = 300000` (portanto teto 240000) e emite
**1** linha de aviso em stderr. Recusar subir por variavel opcional ausente
transformaria todo upgrade de instalacao anterior em outage. Recusar subir por
combinacao **explicitamente ilegal** (ex.: `CSTK_CLIENT_TOOL_TIMEOUT_MS=30000`,
que torna `max = -30000`) continua sendo o comportamento correto.

**Alternatives considered**:
- *Servidor ler `.mcp.json`*: rejeitada pelo proprio contrato — o servidor nao tem
  como localizar o arquivo de forma confiavel (escopos projeto/usuario/local).

---

## Decision 8 — Envelope das rotas de Ponte: mesma forma, freshness proprio

**Decision** `[PROPOSTA]`: as rotas `/bridge/*` respondem com o envelope padrao
`{ data, meta: { degraded, reason, freshness, schemaVersion } }`, montado por um
`wrapBridge()` novo em `apps/server/src/lib/envelope.ts`, que computa `freshness`
a partir do `mtime` do **`bridge.db`** e do `max(updated_at)` das intervencoes.

**Por que nao reusar `wrap()`** `[VERIFICADO: panel/apps/server/src/lib/envelope.ts]`
— a assinatura e `wrap<T>(data, opts, dbPath, db)` e `computeFreshness(dbPath, db)`
le `mtime` do arquivo do corpus + `max(ingested_at)` da `knowledge.db`. Chamar
`wrap()` numa rota de Ponte obrigaria a abrir a `knowledge.db` so para preencher
frescor — acoplando a Ponte ao corpus e violando FR-017 (a queda de um deve
degradar o outro em separado).

**Forma preservada, fonte trocada**: o contrato de envelope do painel
(constitution, secao Padroes de Seguranca) exige `{ data, meta: {...} }` em toda
resposta. `wrapBridge()` honra a forma; so o que alimenta `freshness` e
`schemaVersion` muda de fonte. Isso mantem o cliente web com um unico parser.

**Degradacao (Principio II do painel)**: `bridge.db` ausente/ilegivel responde
`200` com `meta.degraded=true` e `reason` proprio — **nunca** `5xx`. A UI da fila
implementa os quatro estados obrigatorios (carregando, vazio, erro, degradado).

---

## Decision 9 — Mutacao no cliente web nao pode passar pelo `fetchApi` atual

**Decision** `[PROPOSTA]`: a submissao de resposta usa uma funcao nova
`mutateApi()` em `apps/web/src/lib/api.ts`, irmã de `fetchApi` e **sem** a camada
de ETag/cache.

**Defeito concreto que isso evita** `[VERIFICADO: panel/apps/web/src/lib/api.ts:58-113]`
— `fetchApi(path, dataSchema, init)` aceita `init?: RequestInit` (logo aceitaria
`method: 'POST'`), mas **incondicionalmente**: (a) le um ETag armazenado e injeta
`If-None-Match` no request; (b) em `304` devolve o corpo do cache; (c) no sucesso
grava `bodyCache.set(path, data)`. Reusa-lo para o `POST` de resposta faria a
resposta de uma mutacao ser cacheada por path e potencialmente devolvida de cache
numa segunda submissao — colidindo frontalmente com FR-016/SC-006 ("0% das
tentativas subsequentes produzem um segundo efeito").

**Rationale**: o defeito nao aparece em teste com mock (o mock nao tem `localStorage`
nem ETag), so em uso real — exatamente o tipo de drift que o cenario "Roundtrip
End-to-End" do quickstart existe para pegar.

**Alternatives considered**:
- *Passar um flag `skipCache` para `fetchApi`*: rejeitada — sobrecarrega a funcao
  de leitura com um modo que nega metade do seu corpo; duas funcoes sao mais
  legiveis e cada uma testavel isoladamente.

---

## Decision 10 — Auto-refresh da fila reusa `refetchInterval`, sem SSE

**Decision** `[PROPOSTA]`: a tela de intervencoes usa react-query com
`refetchInterval` explicito, no padrao ja adotado pela tela de sessoes.

**Evidencia do padrao existente** `[VERIFICADO]`:
- `panel/apps/web/src/lib/query.ts:8,26-27` — `AUTO_REFRESH_MS = 10_000`,
  `refetchInterval: AUTO_REFRESH_MS`, `refetchIntervalInBackground: false`.
- `panel/apps/web/src/screens/Sessions.tsx:14` — "Tracking (`refetchInterval`
  explicito via useSessions)".
- `panel/apps/server/src/routes/sessions.ts` expõe apenas `.get()` (linhas 114 e
  149) — **nao ha SSE nem WebSocket no painel hoje**.

**Rationale**: FR-013 exige atualizacao automatica sem recarregar a tela;
`refetchInterval` ja entrega isso com zero superficie nova. SSE exigiria conexao
de longa duracao — que o Principio VI da constitution do painel desaconselha
("MUST NOT: segurar uma conexao de longa duracao assumindo que o snapshot nunca
muda") e que a constitution raiz nao pediu.

**Cadencia da fila**: `AUTO_REFRESH_MS` (10 s) e adequada — o operador vendo a
pendencia 10 s depois nao viola nenhum SC (SC-002 mede o caminho de volta, do
clique ate a sessao, que e governado pelo polling de 1500 ms da Decision 5).

---

## Decision 11 — Nenhum eixo estrutural fica em aberto (FR-009 do gate)

**Decision**: os 6 eixos estruturais fechados estao todos JA decididos por fonte
vinculante anterior a este plano. Nenhum `NEEDS CLARIFICATION` estrutural resta,
portanto **nenhum bloqueio humano de eixo e devido nesta onda**.

| Eixo | Decidido por | Valor |
|------|--------------|-------|
| `linguagem-runtime` | codebase existente `[VERIFICADO]` | TypeScript/Node >= 22 (MCP `package.json` `engines`), Node 20-24 (painel `package.json` `engines`), POSIX sh (runtime cstk) |
| `stack-frameworks` | codebase existente `[VERIFICADO]` | Fastify 5 + React/react-query + `@modelcontextprotocol/sdk` |
| `arquitetura` | emenda 2.0.0 da constitution do painel | painel TRANSPORTA, agente PERSISTE; MCP fala HTTP com o painel |
| `persistencia` | emenda 2.0.0 (`bridge.db`, store proprio, conexao rw separada) | SQLite `bridge.db` + `.operator_answers[]` no state da execucao |
| `ambiente-alvo` | `config.ts:168` `[VERIFICADO]` | localhost do operador, bind `127.0.0.1` |
| `tier-entrega` | inalterado pela feature | local/ferramenta de desenvolvedor |

**Rationale**: a spec ja consumiu 5 rodadas de clarificacao com o operador e a
constitution do painel foi emendada especificamente para viabilizar esta feature.
Reabrir qualquer um destes eixos aqui seria re-perguntar algo ja respondido.
Todos os `[PROPOSTA]` deste documento sao **operacionais** (nome de rota, nome de
env var, valor de intervalo, forma de payload) — nenhum deles fixa eixo estrutural.
