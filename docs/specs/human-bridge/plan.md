# Implementation Plan: Human Bridge (Intervencoes)

**Feature**: `human-bridge` | **Spec**: [`spec.md`](spec.md) | **Data**: 2026-08-29
**Status**: Draft | **Fase**: plan (Phase 0 + Phase 1 concluidas)

## Legenda de veracidade (Principio VI) — vale para TODOS os artefatos desta feature

| Rotulo | Significado |
|--------|-------------|
| `[MEDIDO]` | Medido empiricamente; comando e saida literal citados |
| `[VERIFICADO]` | Citacao literal de fonte no repo, com `arquivo:linha` |
| `[PROPOSTA — a validar na implementacao]` | Desenho novo; **nao** existe ainda |

Herdada de [`contracts/mcp-tool-ask-operator.md`](contracts/mcp-tool-ask-operator.md)
e preservada em `research.md`, `data-model.md`, `contracts/panel-bridge-api.md` e
`quickstart.md`. **Nenhuma afirmacao factual aparece sem rotulo.**

---

## Summary

Uma sessao autonoma que precisa de decisao humana hoje **para** — e o operador so
descobre por acaso, visitando o projeto. Esta feature cria a **Ponte**: uma fila
unica, cross-projeto, no painel (`cstk-panel`), onde toda pergunta pendente de
qualquer sessao aparece e pode ser respondida; e uma 9a tool MCP bloqueante
(`ask_operator`) que faz a pergunta e espera a resposta chegar.

**Abordagem tecnica**: a tool MCP gera a intervencao via `POST` HTTP no painel,
faz **polling curto** (1500 ms) ate `answered` ou ate seu proprio teto de relogio,
e em **todo** desfecho `!= answered` aplica o `default_value` — nunca trava. O
painel persiste em store proprio (`bridge.db`, conexao rw separada) e **so
transporta**: o registro canonico da decisao continua sendo do agente, em
`.operator_answers[]`, escrito pela primitiva generica que ja existe.

**O que este plano acrescenta ao que ja estava fechado**: o contrato
`mcp-tool-ask-operator.md` cobre a superficie 1 (tool <-> agente) e declara na sua
secao 10 que a fronteira **painel <-> servidor** ficou sem cobertura. Este plano
fecha exatamente esse buraco (novo contrato
[`contracts/panel-bridge-api.md`](contracts/panel-bridge-api.md)), desenha os
quatro itens que o operador deferiu de proposito (nome do endpoint, nome da env
var, intervalo de polling, shape do payload) — todos rotulados `[PROPOSTA]` — e
registra **duas** correcoes factuais e **um** achado de seguranca que mudam o
desenho.

### Os tres achados que mudaram o desenho

1. **Correcao factual — as duas lacunas do scrub citadas no contrato estao
   FECHADAS** `[MEDIDO 2026-08-29]`. `printf 'password=hunter2' | scrub` devolve
   `password=[REDACTED]`, e blocos PEM viram `[REDACTED-PEM-BLOCK]`
   (`secrets-filter.sh:166` e `:228`, issue #169). O requisito nao muda — as tres
   defesas seguem obrigatorias — mas o **motivo** escrito no contrato ficou
   obsoleto. Detalhe em `research.md` Decision 0.
2. **Achado de seguranca — o `session_id` NAO pode atravessar HTTP.** Ele e token
   de capacidade e o toolkit ja o redige em toda fronteira
   `[VERIFICADO: exec.ts:111 `SENSITIVE_FLAGS`]`. O modelo evita a exfiltracao
   **por construcao**: o roteamento acontece dentro da chamada MCP; o painel e
   caixa-postal indexada por `questionId` e nao roteia nada. Efeito colateral
   bom: SC-005 vira invariante estrutural, nao meta de teste. Detalhe em
   `data-model.md`.
3. **Defeito latente no cliente web** `[VERIFICADO: apps/web/src/lib/api.ts:58-113]`
   — `fetchApi` aplica ETag/`If-None-Match`/`bodyCache` **incondicionalmente**.
   Reusa-lo para o `POST` de resposta cacharia uma mutacao por path, colidindo
   com FR-016/SC-006. Exige `mutateApi()` separado.

---

## Technical Context

| Campo | Valor | Fonte |
|-------|-------|-------|
| **Linguagem/Runtime** | TypeScript; Node `>=22` (servidor MCP), Node `20.x\|22.x\|23.x\|24.x` (painel); POSIX sh (runtime cstk) | `[VERIFICADO: mcp/state-server/package.json engines; panel/package.json engines]` |
| **Frameworks** | Fastify 5 (painel), React + react-query (web), `@modelcontextprotocol/sdk` (MCP) | `[VERIFICADO: panel/apps/server/package.json; mcp/state-server/package.json]` |
| **Persistencia (nova)** | SQLite via `better-sqlite3` ^12.4.1, arquivo **`bridge.db`** em conexao rw separada | `[VERIFICADO: panel/apps/server/package.json:19; open.ts:25]` |
| **Persistencia (canonica)** | `.operator_answers[]` no `state.json`/`state.db` da execucao | contrato §7 |
| **Dependencias novas** | **NENHUMA.** HTTP via `fetch` global do Node >= 22 | `research.md` Decision 6 |
| **Scripts POSIX novos** | **NENHUM.** Escrita pela primitiva generica `state-rw.sh set` | contrato §7 |
| **Ambiente-alvo** | localhost do operador; painel faz bind em `127.0.0.1` | `[VERIFICADO: panel/apps/server/src/config.ts:168]` |
| **Testing** | vitest (painel), `node --test` (MCP), harness POSIX `tests/run.sh` (cstk) | `[VERIFICADO: package.json de cada modulo]` |
| **Constraints de relogio** | teto servidor `[5000, clientTimeout-60000]` **derivado**; folga >= 60000 ms | contrato R-CLOCK-1/2/4 |
| **Escala** | 1 operador, N sessoes locais; fila esperada na ordem de dezenas de itens | spec US1 |

**Target Platform**: localhost do operador (macOS/Linux) — dois processos Node locais (painel Fastify + servidor MCP stdio) falando por HTTP loopback; sem deploy, sem container, sem host remoto.
Fonte: `panel/docs/constitution.md` §Padroes de Seguranca ("bind em `localhost` por padrao") + `[VERIFICADO: panel/apps/server/src/config.ts:168, `host: '127.0.0.1', // FR-017: bind APENAS em localhost`]` + dec-027 desta execucao.

**`NEEDS CLARIFICATION` restantes: 0.** Os 6 eixos estruturais estao todos
fechados por fonte vinculante anterior a este plano — ver `research.md`
Decision 11. Nenhum `[PROPOSTA]` deste plano fixa eixo estrutural; todos sao
operacionais (nome de rota, nome de env var, valor de intervalo, shape de payload),
que e exatamente o que o operador deferiu para ca.

---

## Constitution Check

*GATE: deve passar antes do Phase 0. Re-checado apos Phase 1 — ver §Re-check.*

**Duas governancas se aplicam.** O painel e subprojeto autocontido com constitution
propria (`panel/docs/constitution.md` v2.0.2, emendada especificamente para
viabilizar esta feature). As duas sao vinculantes; nenhuma sobrepoe a outra.

### A. `docs/constitution.md` (raiz do cstk) — v1.1.0

| Principio | Status | Notas |
|-----------|--------|-------|
| **I. SDD recursivo** (NON-NEG) | **PASS** | `spec.md` + `plan.md` + `research.md` + `data-model.md` + 2 contratos + `quickstart.md`; `tasks.md` na proxima etapa. |
| **II. POSIX sh puro, zero dep** (NON-NEG) | **PASS** | **Nenhum script POSIX novo** e **nenhuma dep npm nova**. Escrita via `state-rw.sh set --field '.operator_answers'` (primitiva generica ja existente); HTTP via `fetch` global do Node >= 22 (`research.md` Decision 6). O carve-out de deps opcionais (emenda 1.1.0) **nao precisa ser invocado**. |
| **III. Formato canonico de skill** | **N/A** | Nenhuma skill nova. |
| **IV. Zero coleta remota** (NON-NEG) | **PASS** | Todo trafego e loopback `127.0.0.1`, entre dois processos do proprio operador. Nenhum endpoint de terceiro, telemetria ou upload. `CSTK_PANEL_URL` permite apontar para fora, mas o default e loopback e nenhum caminho envia dado por iniciativa propria. |
| **V. Profundidade > adocao** | **PASS** | Fecha uma lacuna operacional real (sessao travada sem ninguem saber), nao um item de anuncio. |
| **VI. Veracidade de dados** (NON-NEG) | **PASS** | Legenda de veracidade em todos os artefatos; driver do painel **lido do codigo**, nao assumido; **duas** afirmacoes `[VERIFICADO]` do contrato de entrada foram re-medidas e uma delas **corrigida** (`research.md` Decision 0). A feature em si e infraestrutura para o Principio VI virar acao: `kind:"text"` existe para o operador **corrigir** um dado suspeito, nao so aprovar/bloquear. |

### B. `panel/docs/constitution.md` (painel) — v2.0.2

| Principio | Status | Notas |
|-----------|--------|-------|
| **I. Read-Only sobre o Corpus** (NON-NEG) | **PASS sob a excecao da Ponte** | Os 4 MUST da excecao, um a um: (1) escrita confinada a `bridge.db` em conexao **separada** rw (`db/bridge.ts`, instancia distinta de `open.ts`); (2) rotas nao-`GET` **so** sob `/api/v1/bridge/*`; (3) a Ponte **nao** grava decisao/bloqueio/onda no corpus — canonico e `.operator_answers[]` do agente (FR-012); (4) roteamento por `session_id` honrado **dentro** da chamada MCP, nunca por `execution_id` — e sem o token cruzar HTTP. **Corpus intacto**: `knowledge.db` segue `readonly:true` + `query_only=1` `[VERIFICADO: open.ts:100-101, :121]`. **Condicao de contorno obrigatoria**: `scripts/readonly-check.sh` MUST ser estreitado no **mesmo commit** do primeiro codigo de `bridge/`, nunca antes. |
| **II. Degradar, nunca quebrar** | **PASS** | `bridge.db` ausente/corrompido -> `200` + `meta.degraded=true`, nunca `5xx`. Tela com os 4 estados. Degradacao **isolada** verificada pelo Cenario 8 do quickstart (corpus segue nao-degradado). |
| **III. Honestidade de metrica** | **N/A / PASS** | A feature nao introduz metrica. `waitingMs` e derivado de `createdAt` e rotulado como tal; nenhum valor e estimado ou inventado. |
| **IV. Nao reimplementar o que tem dono** | **PASS** | `elicitation/create` tem dono no cstk (`mcp-elicitation-optins`); a Ponte **nao** o reimplementa — cobre o caso que ele nao alcanca (responder fora do cliente MCP), conforme o proprio Sync Impact Report da 2.0.0. A persistencia canonica continua com dono no agente. |
| **V. Conteudo de agente e UNTRUSTED** | **PASS** | `question`, `options[]` e `untrustedText` renderizados como **texto puro**, sem markup ativo. `untrustedText` volta em **campo estrutural proprio** (R-TEXT-1), nunca embutido em `applied_value` nem como prefixo. R-TEXT-4 governa o uso: vira **valor de campo**, nunca instrucao. |
| **VI. Snapshot que muda** | **PASS** | Sem conexao de longa duracao: `bridge.db` aberto por request e fechado no `finally`, no mesmo idioma de `routes/tasks.ts`. `freshness` do envelope da Ponte vem do `mtime` do `bridge.db` (`wrapBridge()`), nao do corpus. |
| **Padroes de Seguranca e Qualidade** | **PASS com 1 limite declarado** | Bind loopback herdado; `nosniff` global `[VERIFICADO: index.ts:54]`; paginacao obrigatoria na fila (reusa `safeParsePagination`); path do `bridge.db` canonicalizado, **nunca** vindo do cliente. **Limite declarado**: sem autenticacao — qualquer processo local que alcance a porta pode listar/responder. E o mesmo limite ja vigente para todo o painel; a feature **nao o estreita nem o alarga** (`contracts/panel-bridge-api.md` §10). |

**Resultado do gate: PASS nas duas constituicoes. Zero violacao de MUST.**
`Complexity Tracking` fica **vazio** — nao ha violacao a justificar.

---

## Project Structure

### Documentation (this feature)

```
docs/specs/human-bridge/
├── spec.md                               (existente — 22 FRs, 5 clarifications)
├── plan.md                               (este arquivo)
├── research.md                           (Phase 0 — 11 decisoes)
├── data-model.md                         (Phase 1)
├── quickstart.md                         (Phase 1 — 13 cenarios)
├── contracts/
│   ├── mcp-tool-ask-operator.md          (existente — superficie 1; NAO reescrito)
│   └── panel-bridge-api.md               (novo — fronteira painel <-> servidor)
└── spikes/                               (existente — evidencia medida)
```

### Source Code (arvore REAL do repositorio, com o que e novo marcado)

```
cstk/
├── mcp/state-server/src/
│   ├── index.ts                          MOD  8 -> 9 registerTool [VERIFICADO: 8 hoje, :228..:375]
│   ├── tools/
│   │   ├── ask_operator.ts               NOVO 9a tool
│   │   └── collect_optins.ts             (precedente de parse/persist/scrub)
│   ├── bridge/client.ts                  NOVO  UNICO arquivo que fala HTTP + mapper camel<->snake
│   ├── runtime/exec.ts                   (reuso: runHelper, SENSITIVE_FLAGS)
│   ├── session/resolve.ts                (reuso: resolucao fail-closed por token)
│   └── audit/log.ts                       MOD  + source "mcp-ask-operator" [reusa REASON_MAX_BYTES:66]
├── cli/lib/mcp.sh                        MOD  heredoc MCPJSON:995-1005 + timeout/env (R-CLOCK-5)
├── plugins/cstk/agents/
│   ├── agente-00c-orchestrator.md        MOD  frontmatter tools: +ask_operator
│   └── agente-00c-feature-orchestrator.md MOD  frontmatter tools: +ask_operator
├── tests/
│   └── test_orchestrator-allowlist-guard.sh MOD _required 8 -> 9 [:323-330]
└── panel/
    ├── apps/server/src/
    │   ├── index.ts                      MOD  + await v1.register(bridgeRoutes) [:74-92]
    │   ├── db/
    │   │   ├── open.ts                   (INTOCADO — corpus readonly + query_only)
    │   │   └── bridge.ts                 NOVO  UNICA conexao rw do processo
    │   ├── routes/bridge.ts              NOVO  4 rotas + mapper snake<->camel
    │   └── lib/envelope.ts               MOD  + wrapBridge()
    ├── apps/web/src/
    │   ├── screens/Interventions.tsx     NOVO  fila + 4 estados obrigatorios
    │   ├── lib/api.ts                    MOD  + mutateApi() SEM camada de ETag
    │   └── lib/hooks-bridge.ts           NOVO  queryOptions + refetchInterval explicito
    ├── packages/shared-types/src/        MOD  + DTOs da Ponte (camelCase)
    └── scripts/readonly-check.sh         MOD  MESMO COMMIT do 1o codigo de bridge/
```

Todos os caminhos existentes foram verificados em disco; nenhum diretorio inventado.

---

## Convencoes de Borda

**Obrigatoria**: a feature atravessa **cinco** camadas —
MCP/Node -> HTTP -> painel/Fastify -> SQLite -> React. Foi a ausencia desta secao
que custou 40 ondas de retrabalho numa execucao anterior deste toolkit (drift
`snake_case` vs `camelCase` nascido no contrato e so descoberto na FASE 8).

| Camada | Case style | Validacao | Fonte da verdade |
|--------|------------|-----------|------------------|
| Colunas de `bridge.db` (SQLite) | `snake_case` | CHECK constraints no DDL | `panel/apps/server/src/db/bridge.ts` |
| DTO do back-end (TS) | `camelCase` | Zod na borda da rota | `panel/packages/shared-types/src/` |
| Payload HTTP `/api/v1/bridge/*` (req **e** res) | `camelCase` | Zod nos **dois** lados | `docs/specs/human-bridge/contracts/panel-bridge-api.md` |
| DTO do front-end (TS) | `camelCase` | Zod no parse do envelope | `panel/apps/web/src/lib/` (re-export de `shared-types`) |
| Path params da URL | `camelCase` (`:questionId`) | router do Fastify | `panel/apps/server/src/routes/bridge.ts` |
| Envelope da tool MCP (`ResultAskOperator`) | `snake_case` | Zod no schema da tool | `contracts/mcp-tool-ask-operator.md` §3 |
| `.operator_answers[]` no state | `snake_case` | shape validada na escrita | `docs/specs/human-bridge/data-model.md` |

**As duas convencoes coexistem de proposito** e se cruzam em **exatamente um**
lugar. O `camelCase` do HTTP e imposto pelo painel — precedente literal
`[VERIFICADO: panel/apps/server/src/routes/tasks.ts]`: `executionId: r.execution_id`,
`testsRun: r.tests_run`, `touchedFilesCount: r.touched_files`. O `snake_case` do
envelope MCP e imposto pelo contrato ja fechado e pelo precedente de
`StoredOptinResponse` `[VERIFICADO: collect_optins.ts:328-334]`.

**Mapper layer** — dois, ambos explicitos e grepaveis:

| Fronteira | Arquivo | Direcao |
|-----------|---------|---------|
| `bridge.db` (snake) <-> HTTP (camel) | `panel/apps/server/src/routes/bridge.ts` | mesmo idioma de `routes/tasks.ts` |
| HTTP (camel) <-> envelope MCP + state (snake) | `mcp/state-server/src/bridge/client.ts` | **unico** arquivo com `fetch(` no servidor MCP |

**ORM / auto-mapping: NAO.** `better-sqlite3` e driver cru; toda conversao e
escrita a mao, de proposito — auto-mapping esconde exatamente a divergencia que
esta tabela existe para prevenir.

**Validacao Zod**: em **ambas** as bordas. Request validado no painel (`safeParse`,
idioma de `routes/tasks.ts`); response validado no cliente web (`parseEnvelope`,
`[VERIFICADO: apps/web/src/lib/api.ts:47-49]`) e no cliente MCP. Schemas
compartilhados vivem em `panel/packages/shared-types/`; o servidor MCP **nao**
importa esse pacote (repos/instalacoes distintas) e mantem um schema Zod proprio,
espelhado — divergencia entre os dois e detectada pelo Cenario 1 do quickstart,
que compara o payload **real** chave a chave.

---

## Sequenciamento obrigatorio (ordem que nao pode ser trocada)

Ha tres acoplamentos em que a ordem errada produz um estado quebrado ou inseguro:

1. **`readonly-check.sh` afrouxa no MESMO commit do primeiro codigo de `bridge/`.**
   Antes: o gate reprova o commit legitimo. Depois (em commit separado): existe uma
   janela em que o painel inteiro fica sem o gate. A constitution e literal —
   "nunca antes".
2. **A 9a tool entra nos TRES sitios de cobertura junto.** `_required` do
   `tests/test_orchestrator-allowlist-guard.sh` **e** o frontmatter dos **dois**
   orquestradores. Faltando qualquer um, a tool nova fica sem cobertura
   exatamente na superficie nova (contrato §9).
3. **`timeout` e `CSTK_CLIENT_TOOL_TIMEOUT_MS` entram juntos, de um unico
   valor-fonte.** Dois literais separados em `cli/lib/mcp.sh` divergem no primeiro
   ajuste, e a R-CLOCK-2 (folga >= 60000 ms) passa a ser violavel em silencio.

---

## Re-check de Constitution (pos-Phase 1)

Feito com o design fechado, nao por inercia:

- **Complexidade introduzida**: um store novo, um modulo de rotas, um cliente
  HTTP, uma tela. Todos **exigidos** pela emenda 2.0.0 (que os nomeia um a um em
  "Artefatos a atualizar"). Nenhuma camada extra alem das nomeadas.
- **Principio II da raiz (zero dep) sobreviveu ao design?** Sim — o design final
  usa `fetch` global e a primitiva `state-rw.sh set` existente. Se em algum ponto
  a implementacao concluir que precisa de um pacote npm novo no servidor MCP ou de
  um script POSIX novo, isso **reabre este gate**, nao e detalhe de implementacao.
- **Principio I do painel sobreviveu?** Sim, e ficou **mais** forte: o design
  garante que a unica conexao rw do processo aponta para `bridge.db`, o que e uma
  das duas verificacoes novas que a clausula Testavel passa a exigir.
- **Principio VI (veracidade)?** O design **produziu** correcao de duas
  afirmacoes `[VERIFICADO]` do contrato de entrada em vez de propaga-las. Isso e o
  principio funcionando, nao uma excecao a ele.
- **Regressao possivel identificada**: FR-018 (isolamento do corpus) e verdadeiro
  hoje por propriedade **acidental** do codigo, nao por invariante declarada — por
  isso o Cenario 9 do quickstart e teste automatizado obrigatorio, nao inspecao.

**Resultado: PASS mantido nas duas constituicoes apos o design.**

---

## Gate de Seguranca (`owasp-security`, 2026-08-29)

Rodado sobre `plan.md` + `contracts/panel-bridge-api.md` + `data-model.md`. Seis
achados; **cinco corrigidos nesta onda**, **um escalado ao operador**.

| # | Sev | Achado | Desfecho |
|---|-----|--------|----------|
| F1 | **HIGH** | `timeout_ms` e `default_value` sao ambos escolhidos pelo AGENTE, e a faixa derivada admite piso `5000` ms — janela curta demais para um humano. Um agente pode "perguntar" com 5 s e colher o proprio default como `timeout`, deixando trilha que parece consulta humana. | **escalar-para-humano** — ver §Bloqueio |
| F2 | MEDIUM | CORS global e `methods: ['GET','OPTIONS']` `[VERIFICADO: index.ts:43-46]` — a propria UI nao conseguiria `POST` em modo dev | corrigir-agora (contrato §11.1) |
| F3 | MEDIUM | `origin` restrito virou controle de seguranca load-bearing; faltava CSRF/Content-Type/Host | corrigir-agora (contrato §11.2) |
| F4 | MEDIUM | `question`/`options[]` persistiam **sem** scrub, enquanto `untrusted_text` era scrubado (LLM02) | corrigir-agora (contrato §11.3) |
| F5 | MEDIUM | permissoes de arquivo do `bridge.db` nao especificadas | corrigir-agora (contrato §11.4) |
| F6 | MEDIUM | `CSTK_PANEL_URL` fora de loopback sem TLS/opt-in | corrigir-agora (contrato §11.5) |

Achados menores tambem incorporados: validacao de formato de `:questionId`
(§11.6) e exibicao obrigatoria de procedencia + `defaultValue` na fila, contra
enquadramento hostil da pergunta (ASI09, §11.7).

**Nota de calibragem**: o vetor CSRF classico foi avaliado e **nao** e explorado
hoje — o `Content-Type: application/json` forca preflight e a allowlist de
`origin` o rejeita. F3 nao afirma vulnerabilidade atual; ela **fixa como
invariante** uma protecao que hoje e acidental, porque com a Ponte o custo de
relaxa-la deixou de ser "vazar leitura" e passou a ser "dirigir um agente
autonomo".

### Mudanca de postura que a feature introduz (registrar, nao minimizar)

Ate aqui o painel era um observador: comprometer a porta local rendia **leitura**
de dado derivado. Com a Ponte, um `POST` bem-sucedido **dirige a decisao de um
agente autonomo**. O limite de confianca continua o mesmo (loopback, sem auth —
`contracts/panel-bridge-api.md` §10), mas o **impacto** de atravessa-lo aumentou.
Isso e consequencia inerente da feature, nao defeito do desenho — e esta escrito
aqui para que uma revisao futura de `corsOrigin` ou de bind saiba o que esta em
jogo.

### Bloqueio humano aberto (F1)

F1 nao e corrigivel por inferencia: exige fixar uma **politica de autonomia** —
quanto tempo um agente MUST esperar antes de poder aplicar o proprio
`default_value` — e isso contradiz o piso `5000` ja fixado pelo contrato
(R-CLOCK-4, herdado de `MIN_ELICIT_TIMEOUT_MS`). Decidir sozinho seria o agente
escolhendo as regras da propria supervisao. Escalado ao operador; a etapa `plan`
so fecha apos a resposta.

---

## Complexity Tracking

*Preenchido apenas quando ha violacao de constitution que exige justificativa.*

**Vazio — nenhuma violacao de MUST em nenhuma das duas constituicoes.**

Registrado por completude, o unico **limite declarado** (nao violacao): as rotas
de Ponte nao tem autenticacao. Isso **herda** o modelo ja vigente do painel
(bind loopback, sem RBAC, sem multi-tenant, "login se existir e decorativo"),
nao o altera. Um modelo de auth seria mudanca de escopo do painel inteiro.

---

## Artefatos

| Arquivo | Status |
|---------|--------|
| `docs/specs/human-bridge/plan.md` | Criado |
| `docs/specs/human-bridge/research.md` | Criado |
| `docs/specs/human-bridge/data-model.md` | Criado |
| `docs/specs/human-bridge/contracts/panel-bridge-api.md` | Criado |
| `docs/specs/human-bridge/quickstart.md` | Criado |
| `docs/specs/human-bridge/contracts/mcp-tool-ask-operator.md` | Preservado (insumo vinculante, nao reescrito) |
| `docs/specs/human-bridge/spec.md` | Preservado |

### Proximos passos

1. `/checklist` — quality gate dos requisitos antes de implementar
2. `/create-tasks` — decompor em backlog (incluindo a task de corrigir a nota
   R-TEXT-3 do contrato com a medicao de 2026-08-29)
3. `/analyze` — consistencia cross-artifact apos as tasks
