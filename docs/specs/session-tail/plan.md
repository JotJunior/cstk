# Implementation Plan: Session Tail

**Feature**: `session-tail` | **Date**: 2026-08-27 | **Spec**: [spec.md](./spec.md)

## Summary

Dar ao operador do painel visibilidade das sessoes do Claude Code que estao
rodando agora e permitir acompanhar o trecho mais recente do transcript de uma
delas — tudo estritamente somente-leitura.

Abordagem tecnica: uma trilha **autocontida**, que descobre sessoes varrendo
`~/.claude/projects/<slug>/<sessionId>.jsonl` no filesystem e **nao abre a
`knowledge.db` em nenhum caminho de codigo**. Um watcher novo e independente
(mesmo padrao do `ingest-watcher`, instancia separada) mantem um indice em
memoria alimentado por `readdirSync` + `statSync`; duas rotas `GET` servem a
listagem e o tail. A leitura do tail e posicional a partir do fim do arquivo,
com teto duplo de linhas e bytes, porque uma unica linha `.jsonl` pode ter
megabytes. Todo texto de transcript e tratado como conteudo hostil e renderizado
literalmente.

O ponto de maior risco tecnico nao e a leitura: e a **borda de tipos**. Este
repo define cada DTO em dois arquivos (interface manual + schema Zod) e ja
carregou um drift `snake_case`/`camelCase` por 40 ondas com a suite verde. Por
isso o plano trata o roundtrip empirico contra o servidor real como gate de
aceite, nao como formalidade.

## Technical Context

**Language/Version**: TypeScript 5.x (ESM, `node:` imports), Node.js 20+
**Primary Dependencies**: Fastify (servidor), Zod (validacao de borda), React 18
+ React Router v6 (HashRouter) + `@tanstack/react-query` (front-end). Nenhuma
dependencia nova e introduzida por esta feature.
**Storage**: filesystem somente-leitura (`~/.claude/projects/**/*.jsonl`) +
indice volatil em memoria do processo. **Nenhum banco** — `knowledge.db` nao e
aberta por esta feature; nao ha `bridge.db`; nada e persistido.
**Testing**: Vitest (`npm test` na raiz); rotas testadas com `server.inject()`
do Fastify em `apps/server/test/lib/`
**Target Platform**: processo Node local, bind em `localhost` (macOS/Linux de
desenvolvimento)
**Project Type**: web app monorepo (npm workspaces: `apps/*`, `packages/*`)
**Performance Goals**: listagem servida do indice em memoria, alvo << 5 s
(SC-001); tail limitado por janela de leitura, independente do tamanho do
arquivo (ha transcripts de 3,7 MB em disco)
**Constraints**: zero rotas nao-`GET`; zero escrita em qualquer arquivo
observado; **nenhum byte de transcript sai do servidor sem passar por scrub de
segredos** (ver §Seguranca de Conteudo); teto duplo obrigatorio na resposta do tail (FR-006); nenhuma palavra
`insert|update|delete|create|drop|alter` seguida de espaco sob
`apps/server/src`, nem em comentario (gate `lint:readonly-check`)
**Scale/Scope**: escala medida na maquina de referencia (comandos em
`research.md` Decisions 1 e 8) — 69 diretorios de projeto, 299 arquivos
`.jsonl`, maior transcript com 3.710.915 bytes

**NEEDS CLARIFICATION restantes**: 0. Nenhum eixo estrutural
(linguagem/runtime, stack, arquitetura, persistencia, ambiente-alvo, tier) e
**fixado** por esta feature — todos ja estavam decididos pelo projeto, e a
feature nao introduz persistencia nova (indice em memoria e volatil, nao e
store). Nao ha, portanto, decisao de classe estrutural a submeter a bloqueio
humano.

## Constitution Check

*GATE: Deve passar antes do Phase 0. Re-checado apos Phase 1 — ver §Re-check.*

Avaliado contra `docs/constitution.md` **v2.0.0** (emenda de 2026-08-26, lida
na integra nesta onda — o Principio I foi redefinido de "Read-Only Absoluto"
para "Read-Only sobre o Corpus", com a excecao da Ponte).

| Principio | Status | Notas |
|-----------|--------|-------|
| **I. Read-Only sobre o Corpus** (NON-NEGOTIABLE) | **PASS** | A feature nao abre a `knowledge.db` em caminho algum, logo nao ha conexao a validar quanto a `mode=ro`. Nao toca `state.json` nem reindexa. Todas as rotas sao `GET` sob `/api/v1/sessions*`. **A excecao da Ponte NAO e usada**: nenhuma rota nao-`GET`, nenhuma conexao read-write, nenhum `bridge.db`. Acesso ao filesystem e `open`/`read`/`stat` — nunca `write`/`unlink`. Verificavel por `lint:readonly-check` + Scenario 11 do quickstart. |
| **II. Degradar, Nunca Quebrar** | **PASS** | Raiz ausente, ilegivel, sessao inexistente e path rejeitado respondem `200` com `meta.degraded=true` e `reason` tipado — nunca `5xx` (contrato §Response degradada). Diretorio vazio e estado **vazio** (`degraded=false`), distinto de degradado. Um tick do watcher nunca lanca. As quatro telas obrigatorias (carregando/vazio/erro/degradado) sao requisito das telas novas. |
| **III. Honestidade de Metrica** | **PASS** | Nenhum valor monetario, nenhum token, nenhuma metrica derivada da `knowledge.db` — a feature nao exibe metrica do corpus. Onde ha parcialidade, ela e **explicita**: `skippedLines` (FR-003a), `truncatedByBytes` e `windowTruncated` distinguem "acabou" de "nao coube", em vez de apresentar parcial como completo. `live` e rotulado como atributo derivado e volatil. `meta.freshness` fica vazio em vez de ser preenchido com o `mtime` do `.jsonl` — seria apresentar o frescor de uma coisa como o de outra. **Campo ausente por honestidade**: nenhum vinculo sessao→execucao e exibido, porque nenhum join verificado existe (research.md Decision 3). |
| **IV. Nao Reimplementar o que Tem Dono** | **PASS** | Reusa o envelope (`wrap`/`wrapDegraded`) em vez de montar `meta` a mao; reusa o **padrao** do `ingest-watcher` (FR-011) em instancia separada, com justificativa de por que a instancia nao e compartilhada; nao reimplementa `cstk recall`, model-routing nem arvore de decisoes. `TextBlockRaw` nao duplica logica de `TextRaw`: e a mesma politica de escaping em forma de bloco, para um caso (texto multi-linha) que o componente atual nao cobre. |
| **V. Conteudo de Agente e UNTRUSTED** | **PASS** (com scrub obrigatorio) | O transcript e o conteudo mais hostil que o painel ja consumiu — saida bruta de LLM que **nao passou pelo scrub de ingestao do corpus**, porque esta feature le o `.jsonl` direto do disco. Esse PASS **nao e herdado** das features que leem da `knowledge.db`: ele so vale porque a feature aplica scrub proprio no servidor (§Seguranca de Conteudo). Apos o scrub, o texto e servido como string literal e renderizado por `TextBlockRaw` (children React, jamais `dangerouslySetInnerHTML`). Diretivas embutidas sao dado, nunca comando. Nao ha FTS aqui, logo a regra de escaping em dois niveis nao se aplica. Coberto por SC-005, Scenario 10 e Scenario 12. |
| **VI. Snapshot que Muda** | **PASS** | O `.jsonl` e o "snapshot que muda" desta feature, e a mesma disciplina se aplica: nenhum descritor de longa duracao e mantido — cada requisicao abre, mede com `fstat` e le a janela; o watcher reconsulta `statSync` a cada ciclo. Um append concorrente simplesmente nao entra na resposta corrente, sem travar nem corromper. O frescor e exposto ao operador como `lastActivityAt`. `meta.freshness` (frescor **do indice**) permanece vazio porque nao ha indice por tras destas rotas. |
| **Padroes de Seguranca e Qualidade** | **PASS** | Sem autenticacao (localhost). **Path traversal confinado**: guard proprio com raiz unica em `~/.claude/projects`, `realpathSync` e rejeicao de escape — e a raiz vem de config do servidor (`CSTK_SESSIONS_ROOT`), **nunca** do cliente. Headers pelo hook `onSend` existente. Limite obrigatorio nas duas rotas (`limit` na listagem, `lines` + tetos de byte no tail) — nenhuma resposta despeja tudo. **Rate-limit leve** nas duas rotas novas (achado MEDIUM do gate — a rota de tail faz I/O de arquivo por requisicao sob auto-refresh), ainda que N/A pela regra original de FTS5. Envelope padrao preservado. **Ha subprocesso**, um so: a invocacao de `secrets-filter.sh scrub` do cstk, sem shell, com argumentos fixos e timeout — ver §Seguranca de Conteudo. |
| **Fidelidade de Design e Estados de Tela** | **PASS** | Telas novas seguem os tokens do prototipo (dark-mode-first, Inter + JetBrains Mono para ids/valores) e implementam os quatro estados. Drill-down: `/sessions` → `/sessions/:sessionId`, coerente com a navegacao existente. |

**Nenhum FAIL em principio MUST.** Gate liberado para Phase 0/1.

## Project Structure

### Documentation (this feature)

```
docs/specs/session-tail/
├── spec.md
├── plan.md          # This file
├── research.md      # Phase 0 output — 14 decisoes, cada uma com evidencia
├── data-model.md    # Phase 1 output — DTOs (definicao DUPLA obrigatoria)
├── quickstart.md    # Phase 1 output — 11 cenarios, roundtrip empirico no #9
└── contracts/
    └── sessions-api.md
```

### Source Code (repository root)

Arvore real do repositorio; **[NOVO]** marca o que esta feature acrescenta.

```
cstk-panel/
├── package.json                      # scripts: test, typecheck, lint:readonly-check
├── apps/
│   ├── server/
│   │   ├── src/
│   │   │   ├── index.ts              # registro /api/v1 + startup do watcher  [EDITADO]
│   │   │   ├── config.ts             # env vars do servidor                    [EDITADO]
│   │   │   ├── lib/
│   │   │   │   ├── envelope.ts       # wrap / wrapDegraded  (reuso, sem edicao)
│   │   │   │   ├── project-root.ts   # guard existente — NAO afrouxar
│   │   │   │   ├── sessions-root.ts  # guard proprio, raiz ~/.claude/projects  [NOVO]
│   │   │   │   ├── session-scan.ts   # descoberta + liveness                   [NOVO]
│   │   │   │   ├── session-tail.ts   # leitura por janela + parse tolerante    [NOVO]
│   │   │   │   └── secret-scrub.ts   # scrub obrigatorio antes de servir       [NOVO]
│   │   │   ├── routes/
│   │   │   │   ├── tasks.ts          # rota de referencia (padrao Fastify)
│   │   │   │   └── sessions.ts       # GET /sessions, GET /sessions/:id/tail   [NOVO]
│   │   │   └── watchers/
│   │   │       ├── ingest-watcher.ts # padrao de referencia — instancia intocada
│   │   │       └── sessions-watcher.ts                                        [NOVO]
│   │   └── test/
│   │       ├── lib/
│   │       │   ├── routes.test.ts    # harness paralelo — registrar a rota nova [EDITADO]
│   │       │   ├── readonly.test.ts  # invariante read-only
│   │       │   ├── sessions-root.test.ts                                       [NOVO]
│   │       │   ├── session-tail.test.ts                                        [NOVO]
│   │       │   └── secret-scrub.test.ts                                        [NOVO]
│   │       └── watchers/
│   │           └── sessions-watcher.test.ts                                    [NOVO]
│   └── web/
│       └── src/
│           ├── App.tsx               # <Route path="/sessions" ...>             [EDITADO]
│           ├── lib/
│           │   ├── api.ts            # fetchApi (reuso, sem edicao)
│           │   ├── query.ts          # AUTO_REFRESH_MS global (sem edicao)
│           │   └── hooks.ts          # useSessions / useSessionTail             [EDITADO]
│           ├── components/
│           │   ├── TextRaw.tsx       # single-line (sem edicao)
│           │   └── TextBlockRaw.tsx  # variante multi-linha <pre>               [NOVO]
│           └── screens/
│               ├── Sessions.tsx      # listagem (US1)                           [NOVO]
│               └── SessionDetail.tsx # tail (US2)                               [NOVO]
└── packages/
    └── shared-types/
        └── src/
            ├── entities.ts           # interfaces manuais dos DTOs novos        [EDITADO]
            ├── envelope.ts           # + 4 literais em DegradedReason           [EDITADO]
            ├── index.ts              # re-export de tipo E de schema            [EDITADO]
            ├── schemas/
            │   └── entities.ts       # schemas Zod gemeos dos DTOs novos        [EDITADO]
            └── __tests__/
                └── parity.test.ts    # paridade interface <-> schema            [EDITADO]
```

**Structure Decision**: a feature adota a estratificacao ja estabelecida do
servidor — `lib/` para logica pura e testavel isoladamente, `routes/` apenas
para borda HTTP (validacao de query, envelope, degradacao), `watchers/` para
trabalho periodico. A logica de leitura de tail fica em `lib/session-tail.ts`,
sem dependencia de Fastify, para ser exercitada por teste unitario direto sem
subir servidor. Nenhum diretorio novo e criado; nenhuma camada nova e
introduzida.

**Ponto de atencao no registro da rota**: registrar em
`apps/server/src/index.ts` nao basta — `apps/server/test/lib/routes.test.ts`
monta um servidor minimo **paralelo** com sua propria lista de rotas. Esquecer
o segundo produz um teste que passa sem exercitar a rota nova.

## Convencoes de Borda

A feature atravessa tres fronteiras: arquivo `.jsonl` → backend, backend →
payload HTTP, payload → front-end.

| Camada | Case style | Validacao | Fonte da verdade |
|--------|------------|-----------|------------------|
| Arquivo `.jsonl` (origem, **nao controlada por nos**) | misto — contem `sessionId` **e** `session_id` na mesma linha | nenhuma; conteudo hostil | harness do Claude Code (externo) |
| Leitura/normalizacao no backend | converte para camelCase no ponto de leitura | `JSON.parse` por linha em try/catch | `apps/server/src/lib/session-tail.ts` |
| Backend DTO (TS) | **camelCase** | tipos de `@cstk-panel/shared-types` | `packages/shared-types/src/entities.ts` |
| Payload da API (response) | **camelCase** | envelope `wrap()` | `docs/specs/session-tail/contracts/sessions-api.md` |
| Frontend DTO (TS) | **camelCase** | `ApiEnvelopeSchema(...).parse()` no `fetchApi` | `packages/shared-types/src/schemas/entities.ts` |
| Query params | **camelCase** curto (`live`, `limit`, `lines`) | Zod `safeParse` + clamp | `apps/server/src/routes/sessions.ts` |
| Path params | **camelCase** (`:sessionId`) | guard de confinamento | `apps/server/src/routes/sessions.ts` |

**O risco especifico desta feature**: a fonte contem **as duas convencoes** —
`sessionId` e `session_id` coexistem no mesmo arquivo, com valor identico.
Sonda (`head -400 <arquivo>.jsonl | jq -r 'keys[]' | sort | uniq -c`): das 400
primeiras linhas, 391 carregam a chave `sessionId` e 227 carregam `session_id`. Um acesso descuidado (`raw.session_id`) propagaria a forma
snake para o DTO e passaria batido em qualquer teste que use fixture. A
conversao acontece em **um unico lugar** (`lib/session-tail.ts`), e o Scenario 9
do quickstart existe precisamente para detectar o vazamento no payload real.

**Mapper layer (arquivo ↔ DTO)**: `apps/server/src/lib/session-tail.ts`
(normalizacao de linha) e `apps/server/src/lib/session-scan.ts` (metadados de
sessao). **Nao ha ORM e nao ha auto-mapping** — a conversao e explicita, campo a
campo. Nao ha camada de banco nesta feature.

**Validacao Zod**:
- **Borda de resposta**: sim, no front-end, via `fetchApi` →
  `ApiEnvelopeSchema(dataSchema).parse()`.
- **Borda de request**: sim, no backend, `safeParse` sobre `request.query` com
  clamp em vez de `4xx` (Principio II).
- **Entrada do arquivo `.jsonl`**: **deliberadamente NAO validada por Zod**. A
  fonte e externa, heterogenea e de conjunto aberto (17 valores de `.type`
  observados); um schema estrito transformaria "o harness mudou" em tela
  quebrada. A tolerancia e a estrategia correta aqui — parse por linha,
  extracao defensiva de campos conhecidos, contagem do que falhou.
- **Schema compartilhado**: sim, `packages/shared-types/` — os DTOs sao
  definidos uma vez e consumidos pelos dois lados.

## Seguranca de Conteudo: scrub de segredos antes de servir

> Origem: achado **HIGH** do gate `owasp-security` na onda-004 (`dec-027`),
> escalado como `block-004` e **respondido pelo operador** — Opcao C com
> fallback. Esta secao e a forma normativa daquela resposta.

### A justificativa do Principio V que NAO se aplica a esta feature

O painel vinha sustentando o Principio V ("Conteudo de Agente e UNTRUSTED") com
uma justificativa herdada: **"o conteudo ja passou por scrub de segredos na
ingestao"**. Essa afirmacao e verdadeira para tudo que chega pela
`knowledge.db`, cuja ingestao aplica `secrets-filter.sh` antes de gravar.

**Ela nao vale aqui.** Esta feature le os arquivos `.jsonl` **direto do disco**
(`~/.claude/projects/**`), contornando inteiramente o pipeline de ingestao do
cstk. No caminho `arquivo → rota → navegador` nao ha, por construcao, nenhum
ponto onde o scrub da ingestao tenha rodado. Foi exatamente essa premissa
quebrada que o gate `owasp-security` detectou: um PASS concedido sob uma
condicao que esta feature nao satisfaz.

**Regra que fica escrita, e nao apenas decidida** (motivo pelo qual esta secao
existe): *toda feature que leia conteudo de agente fora do pipeline de ingestao
do cstk NAO herda o PASS de Principio V das features que leem da `knowledge.db`.
Ela precisa de scrub proprio, no servidor, e deve declarar isso no seu plano.*
Sem esse registro, a proxima feature que abrir arquivo cru herda um PASS que nao
vale para ela e repete este mesmo erro.

### Onde o scrub roda

**No servidor, antes de o conteudo sair pela rota** — nunca no cliente. Um
scrub no front-end e cosmetico: o navegador ja teria recebido o segredo, e ele
ja estaria no cache do `react-query`, no devtools e no trafego. O ponto de
aplicacao e `apps/server/src/lib/secret-scrub.ts`, chamado pela rota
imediatamente antes do `wrap()`.

### Cadeia de scrub (Opcao C com fallback)

| Etapa | O que roda | Quando |
|-------|-----------|--------|
| 1 | `secrets-filter.sh scrub` do cstk, via subprocesso sem shell | quando o script existe e e executavel |
| 2 | redactor **interno** minimo, em TypeScript puro | **sempre** |

O passo 2 nao e apenas o fallback do passo 1: ele roda **encadeado apos** o
passo 1 tambem quando o cstk esta presente. Essa e a unica forma de cobrir a
lista de padroes exigida pela resposta ao `block-004`, porque o filtro do cstk
demonstravelmente nao cobre a lista inteira — ver a tabela de cobertura abaixo.
Quando o cstk esta ausente, o passo 1 e pulado e **a qualidade do scrub
degrada; o scrub nunca e desativado** (Principio II). Em nenhum caminho, em
nenhuma condicao de erro, conteudo cru e servido.

### Cobertura medida do filtro do cstk (evidencia, nao suposicao)

Sonda executada nesta onda contra
`~/.claude/skills/agente-00c-runtime/scripts/secrets-filter.sh` (12038 bytes,
executavel), subcomando `scrub`, que le **stdin** e escreve **stdout**:

```sh
printf 'x AKIAIOSFODNN7EXAMPLE y\npassword=hunter2\nBearer abc.def.ghi\nnormal line\n' \
  | secrets-filter.sh scrub
# exit 0
# x [REDACTED-AWS-KEY] y
# password=hunter2        <-- NAO redigido
# Bearer [REDACTED]
# normal line
```

Leitura das regras do script (linhas 151-205) explica o resultado:

| Padrao exigido pela resposta ao `block-004` | Coberto pelo cstk? | Evidencia |
|---|---|---|
| Chaves AWS | **sim** | `sed -E 's/AKIA[A-Z0-9]{16,}/[REDACTED-AWS-KEY]/g'` |
| Bearer tokens | **sim** | `sed -E 's/Bearer[[:space:]]+[A-Za-z0-9._=+\/-]+/Bearer [REDACTED]/g'` |
| Basic auth em URL | sim (extra) | regra de `https?://user:pass@host` |
| `password=` / `token=` / `secret=` / `api_key=` | **parcial** | a regra exige valor com **20+ caracteres** (`{20,}`); `password=hunter2` (7 chars) sobreviveu na sonda |
| Blocos `BEGIN ... PRIVATE KEY` | **nao** | `grep -n REDACTED` no script nao retorna nenhuma regra de chave privada |

O redactor interno cobre, no minimo, as duas lacunas: **blocos
`-----BEGIN ... PRIVATE KEY-----` inteiros** e **atribuicoes
`password=`/`token=`/`secret=`/`api_key=` sem piso de comprimento** — alem de
repetir AWS e Bearer, para que o caminho sem cstk continue cobrindo os quatro
padroes exigidos.

### Superficie coberta

Scrub e aplicado a **todo campo de texto derivado do transcript**, nas duas
rotas — nao apenas ao corpo do tail:

| Rota | Campo | Origem no transcript | Scrub |
|------|-------|----------------------|-------|
| `/sessions/:id/tail` | `entries[].text` | `.message.content` | **sim** |
| `/sessions` | `sessions[].projectPath` | `.cwd` | **sim** |
| `/sessions` | `sessions[].projectSlug` | nome de diretorio | **sim** |

`sessionId`, `type`, `role`, `uuid`, `timestamp` e os campos numericos/booleanos
nao sao texto livre de conteudo de agente e ficam de fora. A listagem **nao
possui hoje campo de preview do transcript**; se um for adicionado, ele entra
nesta tabela e passa pela mesma cadeia — a regra e sobre a origem do dado, nao
sobre o nome do campo.

### Ordem em relacao ao truncamento

O scrub roda **antes** do corte de `textTruncated` (FR-006). Cortar primeiro
poderia deixar meio segredo visivel e ainda por cima quebrar a ancora de um
padrao multi-linha (o caso do bloco de chave privada). Consequencia aceita: o
texto truncado e o texto **ja redigido**, e `[REDACTED]` conta para o teto de
bytes.

### Modos de falha (Principio II — nunca quebra, nunca vaza)

| Falha | Comportamento |
|-------|---------------|
| script do cstk ausente / nao-executavel | pula o passo 1; passo 2 roda; resposta normal com `scrubMode: 'internal'` |
| subprocesso falha, sai != 0 ou estoura o timeout | descarta a saida parcial, usa a **entrada original** como insumo do passo 2; nunca serve o que o passo 1 produziu pela metade |
| passo 2 lanca (nao deveria: e regex puro) | a rota responde degradada com `data: null`; **jamais** o texto cru |

O subprocesso e invocado com argumentos fixos e **sem shell**
(`execFile`-style, nunca `exec` com string): o conteudo do transcript vai por
**stdin**, jamais como argumento de linha de comando. O caminho do script vem de
configuracao do servidor (`CSTK_SECRETS_FILTER`), **nunca** do cliente.

### Custo e mitigacao

Um spawn por requisicao de tail, sob auto-refresh, e o custo real desta decisao
— e a razao pela qual a linha "Sem subprocesso" saiu do Constitution Check. Duas
mitigacoes ficam registradas para o backlog: detectar a disponibilidade do
script **uma vez** no startup (nao por requisicao) e o rate-limit leve ja
exigido pelo achado MEDIUM do mesmo gate.

### Achados residuais da reconfirmacao do gate (onda-005)

O gate `owasp-security` foi re-rodado sobre esta secao e sobre o §Scrub de
segredos do contrato. **O achado HIGH esta mitigado** — o design agora tem
scrub obrigatorio no servidor, sem caminho que sirva cru, com cenario de aceite
executavel (quickstart Scenario 12, ramos A-E). A mitigacao, porem, introduz
superficie nova. Nenhum achado novo e `critical`/`high`, logo nenhum deles
bloqueia; todos seguem para o `/create-tasks` como tarefas:

| Sev | Achado | Acao exigida na implementacao |
|-----|--------|-------------------------------|
| MEDIUM | **ReDoS no redactor interno** (CWE-1333). O redactor e regex sobre conteudo hostil de ate megabytes; o padrao de bloco `BEGIN ... PRIVATE KEY` e multi-linha e o candidato natural a backtracking catastrofico | Padroes ancorados, sem quantificador aninhado; casar o bloco linha-a-linha (maquina de estado entre `BEGIN`/`END`) em vez de um regex guloso que atravessa o texto inteiro; teste com entrada patologica |
| MEDIUM | **Amplificacao de spawn + entrada nao limitada no subprocesso.** Um `execFile` por requisicao de tail sob auto-refresh; e como o scrub roda **antes** do truncamento, o subprocesso recebe a janela inteira, nao o texto ja cortado | Declarar explicitamente que a entrada do scrub e limitada pela **janela de leitura** (FR-006), nunca pelo arquivo inteiro; deteccao de disponibilidade do script **uma vez no startup**; o rate-limit leve do achado MEDIUM anterior cobre o resto |
| LOW | **Vazamento por log no modo de falha** (LLM02). "Descarta a saida parcial" nao diz nada sobre o que e logado; logar stdin/stdout/stderr do subprocesso em caso de falha colocaria o segredo no log do servidor e anularia o controle inteiro | Em falha, logar **apenas** codigo de saida e se houve timeout. Nunca o conteudo de entrada, nunca a saida parcial, nunca o stderr bruto |
| LOW | **Resolucao do executavel por `PATH`** (A03/A08). `CSTK_SECRETS_FILTER` e configuracao de servidor (mesmo nivel de confianca de `CSTK_KNOWLEDGE_DB`), mas um caminho relativo resolvido via `PATH` seria sequestravel | Exigir caminho **absoluto**; nunca resolver por `PATH`; se o valor nao for absoluto, tratar como indisponivel e cair em `scrubMode: 'internal'` |

Confirmacoes positivas do gate, para nao serem desfeitas por engano: subprocesso
**sem shell** com conteudo por **stdin** (fecha CWE-78); fail-closed quando o
passo 2 lanca (degrada, jamais serve cru); aplicacao **no servidor** e nao no
cliente; e cobertura definida por **origem do dado**, nao por nome de campo —
e essa ultima que impede a classe de erro de voltar quando um campo novo
aparecer.

`scrubMode` no payload revela postura de seguranca ao cliente. Aceito: servidor
local, usuario unico, e o valor e exigido pelo Principio III.

## Complexity Tracking

> Preencher APENAS se Constitution Check tem violacoes que precisam justificativa

**Nenhuma violacao de constitution.** Todos os principios avaliaram PASS e a
tabela fica vazia por esse motivo, nao por omissao.

Dois itens **nao sao violacoes**, mas introduzem padrao novo no repositorio e
ficam registrados para revisao consciente:

| Padrao novo | Por que | Alternativa rejeitada porque |
|-------------|---------|------------------------------|
| `refetchInterval` explicito por hook | A trilha e "ao vivo"; o default global de 10 s foi calibrado para telas de historico | Herdar o global satisfaz FR-002, mas entrega uma trilha ao vivo menos reativa que a expectativa da US1 |
| `TextBlockRaw` (variante multi-linha) | Transcript e multi-linha; `TextRaw` renderiza em `<span>` e trunca com reticencias, destruindo a estrutura | Reusar `TextRaw` como esta tornaria o tail ilegivel; usar `<pre>` cru sem componente perderia a garantia de escaping centralizada do Principio V |
| Subprocesso no caminho de uma requisicao (`secrets-filter.sh`) | Reusar o filtro que **tem dono** no cstk, em vez de manter uma segunda lista de regras divergindo da primeira (Principio IV) | Redactor 100% interno seria mais rapido e sem spawn, mas congelaria as regras nesta feature: melhorias no filtro do cstk deixariam de chegar ao painel |

## Re-check (pos-Phase 1)

Reavaliacao apos o design estar completo, conforme ETAPA 7 do `/plan`:

- **O design introduziu complexidade nao justificada?** Nao. Nenhum servico
  novo, nenhuma dependencia nova, nenhuma camada nova, nenhum banco. Tres
  modulos de `lib/`, um watcher, uma rota, duas telas e um componente —
  todos dentro da estratificacao existente.
- **Algum principio MUST foi comprometido pelo design?** Nao. Ao contrario:
  a decisao de **nao** abrir a `knowledge.db` (research.md Decision 1) torna o
  Principio I mais facil de garantir do que em qualquer rota existente, e a
  decisao de **nao** exibir vinculo sessao→execucao (Decision 3) resolve a favor
  do Principio III e do Principio VI da constituicao global (zero fabricacao).
- **O design criou superficie de escrita?** Nao. Nenhuma rota nao-`GET`,
  nenhuma conexao read-write, nenhum uso da excecao da Ponte. O subprocesso
  introduzido pelo scrub le stdin e escreve stdout; nao toca disco.
- **O gate de seguranca foi reconciliado?** Sim. O achado HIGH
  (`transcript servido sem scrub`) esta resolvido pela §Seguranca de Conteudo,
  com a premissa quebrada do Principio V registrada por escrito para nao ser
  herdada de novo. Os achados MEDIUM/LOW do mesmo gate — resolver `sessionId`
  pelo indice em memoria em vez de path reconstruido do cliente, validar UUID
  com Zod antes do path-join, abrir o arquivo uma unica vez pelo path resolvido
  (TOCTOU), normalizar caixa e rate-limit leve — **nao** dependiam da resposta
  humana e seguem para o `/create-tasks` como tarefas de implementacao.
- **Risco residual**: o unico ponto onde um erro de implementacao passaria por
  `tsc` e `vitest` sem ser notado e a borda de tipos (definicao dupla de DTO).
  Mitigacao explicita: Scenario 9 do quickstart e o teste de paridade de
  `shared-types` como gate de aceite.

**Constitution Check pos-design: PASS** (sem alteracao na tabela).

## Artefatos

| Arquivo | Status |
|---------|--------|
| `docs/specs/session-tail/plan.md` | Criado |
| `docs/specs/session-tail/research.md` | Criado |
| `docs/specs/session-tail/data-model.md` | Criado |
| `docs/specs/session-tail/contracts/sessions-api.md` | Criado |
| `docs/specs/session-tail/quickstart.md` | Criado |

## Proximos Passos

1. `/checklist` — quality gate dos requisitos antes de implementar
2. `/create-tasks` — decompor este plano em backlog executavel
3. `/analyze` — validar consistencia spec ↔ plan ↔ tasks (apos as tasks)
