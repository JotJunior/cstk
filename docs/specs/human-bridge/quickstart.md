# Quickstart / Cenarios de Teste: Human Bridge

**Feature**: `human-bridge` | **Fase**: Phase 1 | **Data**: 2026-08-29

Todos os cenarios sao `[PROPOSTA — a validar na implementacao]`: descrevem o
comportamento a construir, nao um comportamento ja medido. O rotulo cai para
`[MEDIDO]` na task que de fato executar o cenario e colar a saida literal.

Convencao: `1. Passo -> 2. Passo -> **Expected**: resultado.`

---

## Cenario 1 (OBRIGATORIO) — Roundtrip End-to-End com chamada REAL

> **Este cenario nao aceita mock, stub nem fixture.** Ele existe porque 40 ondas
> historicas deste toolkit mascararam um drift `snake_case` vs `camelCase` — os
> testes parseavam mocks, nao o payload real do backend. So o roundtrip empirico
> expoe esse tipo de divergencia antes de ela se acumular. A feature atravessa
> **cinco** camadas (MCP/Node -> HTTP -> Fastify -> SQLite -> React), e duas
> convencoes de case se encontram no meio (ver `contracts/panel-bridge-api.md` §2).

1. Subir o painel de verdade: `cstk serve` -> anotar a porta efetiva.
   **Expected**: painel respondendo em `http://127.0.0.1:5173`
   (`cli/lib/serve.sh:897`, `_serve_port="${PORT:-5173}"`).
2. `curl -s http://127.0.0.1:5173/api/v1/bridge/interventions | jq .`
   **Expected**: `200`, envelope `{data,meta}`, `data.interventions == []`,
   `meta.degraded == false`. **Nao** `404` (rota registrada) e **nao** `5xx`.
3. Criar uma intervencao pelo caminho real do servidor MCP (nao por `curl`
   direto): invocar `mcp__cstk-state__ask_operator` com
   `kind:"choice"`, `options:["a","b"]`, `default_value:"a"` numa sessao com token
   valido. **Expected**: a tool **bloqueia**; a fila passa a listar 1 item.
4. `curl -s .../api/v1/bridge/interventions | jq '.data.interventions[0]'` e
   **comparar chave a chave** contra a tabela de `contracts/panel-bridge-api.md` §6.
   **Expected**: as chaves sao **exatamente** `questionId`, `project`, `shortName`,
   `executionKind`, `kind`, `question`, `options`, `defaultValue`, `state`,
   `reachable`, `createdAt`, `expiresAt`, `waitingMs`, `appliedValue`,
   `untrustedText`, `resolvedAt` — todas em `camelCase`. **Zero** chave em
   `snake_case` no payload HTTP. Qualquer `question_id`/`applied_value` vazando
   aqui e o drift que este cenario existe para pegar.
5. Responder pela **UI real** (nao por `curl`): abrir a tela de intervencoes,
   escolher `"b"`, submeter.
   **Expected**: `200`; o item sai da fila de abertas em <= 10 s (FR-013, cadencia
   `AUTO_REFRESH_MS`).
6. Observar a sessao bloqueada no passo 3.
   **Expected**: a tool retorna em <= 10 s apos o clique (SC-002), com envelope
   `{outcome:"accepted", result:{channel:"panel", outcome:"answered",
   applied_value:"b", question_id:"<id>", untrusted_text:null}}` — note que o
   envelope da tool esta em `snake_case`, e o payload HTTP em `camelCase`. **As
   duas convencoes coexistindo e o comportamento correto**, desde que o mapper de
   `mcp/state-server/src/bridge/client.ts` seja o unico lugar onde elas se cruzam.
7. `state-rw.sh get --state-dir <SD> --field '.operator_answers'`
   **Expected**: 1 entrada com os 7 campos de `data-model.md`, `channel:"panel"`,
   `outcome:"answered"`, `applied_value:"b"`. E `.optin_responses[]` **intacto**.
8. `grep -c mcp-ask-operator <projeto-alvo>/.claude/enforcement-log.jsonl`
   **Expected**: exatamente `1`.

---

## Cenario 2 — Fila cross-projeto (US1 / SC-001)

1. Iniciar duas execucoes autonomas em **projetos diferentes**.
2. Cada uma chama `ask_operator` e bloqueia.
3. Abrir a tela de intervencoes uma unica vez.
   **Expected**: **ambas** aparecem na mesma lista, cada uma com `project` e
   `executionKind`/`shortName` distintos; ordenadas por `createdAt ASC` (quem
   espera ha mais tempo primeiro). Nenhuma navegacao para tela de projeto foi
   necessaria.
4. Responder **apenas a primeira**.
   **Expected**: so a sessao 1 destrava. A sessao 2 continua bloqueada e seu item
   continua `open` (FR-003 / SC-005).

---

## Cenario 3 — Fila vazia nao e tela em branco (US1 cenario 2)

1. Nenhuma sessao esperando; abrir a tela.
   **Expected**: estado **vazio explicito** ("nenhuma intervencao pendente"),
   nao tela em branco nem erro. Um dos quatro estados obrigatorios do painel
   (carregando / vazio / erro / degradado).

---

## Cenario 4 — Os tres tipos de intervencao (US2 / FR-004)

1. Criar tres intervencoes, uma de cada `kind`.
   **Expected**: `choice` renderiza as opcoes fechadas; `confirm` renderiza
   sim/nao; `text` renderiza campo de texto livre.
2. Em `choice`, tentar submeter um valor **fora** de `options` por `curl` direto
   (contornando a UI):
   `curl -X POST .../interventions/<id>/answer -d '{"resolution":"answered","value":"zzz"}'`
   **Expected**: `400`. **A validacao e do servidor** — uma UI que restringe e
   sugestao; a rota e a regra (FR-005).
3. Em `text`, digitar `route.path = /v2/orders` e submeter.
   **Expected**: envelope da tool traz `untrusted_text:"route.path = /v2/orders"`
   em **campo proprio**, e `applied_value` traz o **token de desfecho**, nunca o
   texto (R-TEXT-1).

---

## Cenario 5 (ERROR CASE) — Painel fora do ar (US3 cenario 3 / FR-010 / FR-021)

1. **Nao** subir o painel (ou `kill` no processo).
2. Invocar `ask_operator` com `default_value:"a"`.
   **Expected**: a tool retorna em <= ~5 s (`BRIDGE_CREATE_TIMEOUT_MS`), **sem
   nunca esperar resposta**, com `outcome:"accepted"` e
   `result.outcome:"unavailable"`, `applied_value:"a"`.
3. **Expected**: `.operator_answers[]` tem a entrada com `outcome:"unavailable"`,
   gravada **antes** do retorno (C-4).
4. **Expected**: nenhuma chamada a `GET /api/v1/health` aparece em log/trace —
   FR-021 proibe reusa-lo, porque ele mede a `knowledge.db`, nao a Ponte.
5. **Expected (R-2)**: `unavailable` e **nao-terminal** — uma leitura posterior de
   `.operator_answers[]` nao pode trata-lo como "o operador ja respondeu isso".

---

## Cenario 6 (ERROR CASE) — Expiracao sem resposta (US3 / FR-009 / SC-003)

1. Criar intervencao com `MCP_ASK_TIMEOUT_MS` no **piso** da faixa derivada
   `[ASK_MIN_TIMEOUT_MS, clientTimeout-60000]` — isto e, `60000` (R-CLOCK-7) — e
   nao responder.
   **Expected**: a tool retorna em ~60 s com `result.outcome:"timeout"` e
   `applied_value == default_value`.
   > O cenario **nao pode** usar uma janela mais curta: valor abaixo do piso cai
   > no default `240000` (passo 1.bis), nao no valor pedido. Os ~60 s sao o custo
   > deliberado do piso — ver `plan.md` §Resolucao de F1.
1.bis **R-CLOCK-7 — abaixo do piso cai no DEFAULT, nao clampa.** Chamar a tool
   com `timeout_ms: 5000` (abaixo de `ASK_MIN_TIMEOUT_MS`).
   **Expected**: a janela efetiva e `MCP_ASK_TIMEOUT_MS` (default `240000`), **nao**
   `60000` e **nao** `5000`. Verificar em `.operator_answers[]`:
   `effective_timeout_ms == 240000`. Clampar para a borda seria a falha que este
   passo existe para pegar.
1.ter **R-AUDIT-1 — a janela efetiva e auditada.** Com a entrada de `timeout` do
   passo 1 gravada, rodar `review-task`.
   **Expected**: `effective_timeout_ms` presente em **toda** entrada de
   `.operator_answers[]`; nenhum finding `ask-operator-short-window` neste caso
   (janela `60000` **nao** e `< 60000`). O finding so dispara na conjuncao
   `outcome == "timeout"` **E** `effective_timeout_ms < 60000` — que, com o piso
   vigente, **so** e alcancavel por bug ou regressao. E esse e o ponto: ele e a
   rede que pega o afrouxamento do piso.
2. Olhar a fila depois.
   **Expected**: o item aparece como `expired`, com `appliedValue: null` e
   `resolvedAt: null` — **visualmente distinto** de uma resposta humana
   (FR-011 / US3 cenario 2). Nao ha coluna `timeout` no banco: `expired` e
   derivado de `expires_at`, logo e estruturalmente impossivel confundi-lo com
   decisao humana.
3. Tentar responder o item expirado pela UI.
   **Expected**: `409` com aviso claro ("ja encerrada"). A sessao ja seguiu pelo
   caminho seguro e nao pode ser desfeita.

---

## Cenario 7 (ERROR CASE) — Duas respostas simultaneas (Edge Case / FR-016 / SC-006)

1. Uma intervencao `open`. Disparar **dois** `POST .../answer` concorrentes com
   valores diferentes.
   **Expected**: exatamente **um** `200` e exatamente **um** `409`. O
   `UPDATE ... WHERE resolution IS NULL AND expires_at > ?` com `changes === 1`
   garante que o segundo nunca aplique.
2. **Expected**: a sessao de origem recebe **um unico** desfecho, com o valor do
   vencedor. `.operator_answers[]` tem **uma** entrada, nao duas.

---

## Cenario 8 (ERROR CASE) — Degradacao isolada do `bridge.db` (FR-017 / Principio II)

1. Remover ou corromper `~/.claude/cstk/bridge.db` com o painel no ar.
2. `curl -s .../api/v1/bridge/interventions`
   **Expected**: `200` com `meta.degraded:true` e `reason` proprio. **Nunca `5xx`.**
3. `curl -s .../api/v1/overview` e `.../api/v1/executions`
   **Expected**: continuam `200` e **nao-degradados** — a queda da Ponte nao toca
   nenhuma tela de observabilidade. Essa e a prova de que as conexoes sao mesmo
   separadas, e nao so declaradas separadas.
4. Restaurar `bridge.db`. **Expected**: a fila volta sem reiniciar o painel.

---

## Cenario 9 — Isolamento do corpus (FR-018) — guard de regressao

1. Executar uma feature ate ter `.operator_answers[]` populado e `bridge.db` com
   linhas.
2. `cstk recall --ingest --state-dir <SD>` e depois
   `cstk recall --reindex --states-root <raiz>`.
3. Buscar o `question_id`, o texto da pergunta e o `untrusted_text` na
   `knowledge.db` (todas as tabelas + FTS).
   **Expected**: **zero** ocorrencias. Nenhuma tabela do corpus contem qualquer
   dado da Ponte.
4. **Expected**: `cstk recall "<texto da pergunta>"` retorna zero resultados
   originados da Ponte.

> Este cenario nao verifica uma feature — verifica que uma **nao-feature**
> continua nao acontecendo. E frageis por natureza (hoje o isolamento e
> propriedade acidental do codigo, ver `data-model.md` §FR-018), por isso ele e
> teste automatizado, nao inspecao manual.

---

## Cenario 10 — Gate de read-only e o commit unico (Principio I do painel)

1. Antes de qualquer codigo de `bridge/`: `cd panel && npm run lint:readonly-check`
   **Expected**: `OK: 0 verbos de mutacao em <N> arquivos sob apps/server/src`
   (o gate declara cobertura — "um gate que responde apenas OK, sem dizer o que
   leu, nao distingue 'varri tudo e nao achei' de 'nao varri nada'").
2. Adicionar `apps/server/src/db/bridge.ts` com `CREATE TABLE` **sem** tocar o gate.
   **Expected**: `FAIL` — comportamento **correto e desejado**. O gate hoje varre
   `apps/server/src` inteiro por `INSERT|UPDATE|DELETE|CREATE|DROP|ALTER`.
3. No **mesmo commit**, estreitar o escopo para `db/queries/**` e acrescentar as
   duas verificacoes exigidas pela clausula Testavel: (a) a unica conexao rw
   aponta para `bridge.db`; (b) toda rota fora de `/api/v1/bridge/*` responde so
   a `GET`.
   **Expected**: `OK`, com cobertura declarada e as duas verificacoes novas
   reportando resultado proprio.
4. **Expected (regressao)**: introduzir `.post()` em qualquer rota fora de
   `/api/v1/bridge/*` reprova o gate.

> A constitution e explicita: atualizar o gate **JUNTO** com o primeiro codigo de
> `bridge/`, **nunca antes** — "o gate nao pode afrouxar enquanto nao existe o
> que ele passa a permitir". Afrouxar em commit separado deixa uma janela em que
> o painel inteiro esta desprotegido.

---

## Cenario 11 — Provisionamento dos relogios (R-CLOCK-5)

1. `cstk mcp install --project-path <p>` e inspecionar `.mcp.json`.
   **Expected**: o bloco `cstk-state` traz **ambos** `"timeout": 300000` e
   `"env": {"CSTK_CLIENT_TOOL_TIMEOUT_MS": "300000"}`, com o **mesmo** valor.
   Hoje o heredoc nao traz nenhum dos dois
   `[VERIFICADO: cli/lib/mcp.sh:995-1005]`.
2. `grep -c '300000' cli/lib/mcp.sh` na regiao do heredoc.
   **Expected**: o literal aparece **uma unica vez**, atribuido a uma variavel de
   shell interpolada nos dois campos. Dois literais separados sao a falha que
   R-CLOCK-5 existe para impedir (eles divergem no primeiro ajuste).
3. Subir o servidor **sem** `CSTK_CLIENT_TOOL_TIMEOUT_MS` (simulando instalacao
   anterior).
   **Expected**: o servidor **sobe**, assume `240000`, e emite **1** linha de
   aviso em stderr. Recusar subir por variavel opcional ausente transformaria
   upgrade em outage.
4. Subir com `CSTK_CLIENT_TOOL_TIMEOUT_MS=30000` (ilegal: `max` ficaria negativo).
   **Expected**: o servidor **recusa subir**, com diagnostico citando a faixa
   derivada. Combinacao explicitamente ilegal e caso diferente de variavel ausente
   — a distincao e deliberada.
5. `grep -nE '\b240000\b' mcp/state-server/src/tools/ask_operator.ts`
   **Expected**: `240000` **nao** aparece como literal de faixa — e derivado
   (`clientTimeoutMs - CLOCK_SAFETY_MARGIN_MS`). R-CLOCK-4 exige os **dois**
   extremos derivados, nunca constante escrita.
6. `grep -nE 'ASK_MIN_TIMEOUT_MS|CLOCK_SAFETY_MARGIN_MS' mcp/state-server/src/`
   **Expected**: **duas** constantes distintas, cada uma com seu proprio
   comentario de justificativa — `ASK_MIN_TIMEOUT_MS` (janela minima de resposta
   humana, R-CLOCK-7) e `CLOCK_SAFETY_MARGIN_MS` (overshoot do watchdog +
   margem, R-CLOCK-2). Ambas valem `60000`, e isso e **coincidencia**: uma
   derivar da outra, ou compartilharem um `const`, e violacao da decisao do
   operador em block-005 e reprova este cenario.

---

## Cenario 12 — Cobertura da 9a tool nos tres sitios (contrato §9)

1. `./tests/run.sh test_orchestrator-allowlist-guard`
   **Expected**: passa com `_required` contendo **9** tools (hoje 8
   `[VERIFICADO: tests/test_orchestrator-allowlist-guard.sh:323-330]`).
2. Remover `mcp__cstk-state__ask_operator` do frontmatter de **um** dos
   orquestradores e rodar de novo.
   **Expected**: **FAIL** nomeando o orquestrador. Prova por mutacao — sem ela o
   guard pode estar inerte (a classe de defeito revogada em
   `orchestrator-mcp-allowlist`).
3. Repetir removendo do outro orquestrador. **Expected**: FAIL de novo.

---

## Cenario 13 — Nao-exfiltracao do `session_id` (data-model §Achado de seguranca)

1. Apos o Cenario 1 completo, buscar o token da sessao em toda a superficie
   persistida da Ponte:
   `sqlite3 ~/.claude/cstk/bridge.db 'SELECT * FROM interventions'` e o payload
   HTTP capturado no passo 4 do Cenario 1.
   **Expected**: **zero** ocorrencias do valor do `session_id`. Nenhuma coluna,
   nenhum campo de payload, nenhum log.
2. `grep -r "$SESSION_ID" ~/.claude/cstk/ <projeto-alvo>/.claude/enforcement-log.jsonl`
   **Expected**: zero ocorrencias.
3. Forcar um erro de helper dentro da tool e inspecionar o stderr.
   **Expected**: nenhum `--token <valor>` em texto claro — a redacao ja existente
   cobre tambem este caminho
   `[VERIFICADO: mcp/state-server/src/runtime/exec.ts:111 `SENSITIVE_FLAGS`, :176-179]`.
