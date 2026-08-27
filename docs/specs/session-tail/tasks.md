# Tarefas Session Tail - Implementacao completa (US1+US2+US3)

Escopo: implementar as duas rotas GET (`/api/v1/sessions`,
`/api/v1/sessions/:sessionId/tail`), o watcher de sessoes, a cadeia de scrub
de segredos, os DTOs compartilhados e as duas telas novas do painel
(`Sessions`, `SessionDetail`), conforme `spec.md` (FR-001..FR-011, SC-001..
SC-005), `plan.md` e `contracts/sessions-api.md`.

**Legenda de status:**
- `[ ]` Pendente
- `[~]` Em andamento
- `[x]` Concluido
- `[!]` Bloqueado

**Legenda de criticidade:**
- `[C]` Critico - Impacto financeiro direto ou bloqueante
- `[A]` Alto - Funcionalidade essencial
- `[M]` Medio - Necessario mas sem urgencia imediata

---

## FASE 0 - Especificacao de requisitos pendentes (Gaps do checklist)

> Estas 5 tarefas resolvem `[Gap]`s de **requisito** identificados nos
> checklists (`docs/specs/session-tail/checklists/security.md`,
> `checklists/api.md`) — CHK015, CHK009, CHK010, CHK012, CHK005/CHK003. Cada
> uma produz um artefato de criterio de aceite (edicao em `contracts/
> sessions-api.md` e/ou `quickstart.md`) **antes** de qualquer tarefa de
> implementacao que dependa dela. Nenhuma delas escreve codigo de producao.

### 0.1 Amarrar resolucao de `sessionId` ao indice em memoria do watcher `[A]`

Ref: CHK015 (checklists/security.md), research.md Decision 7, contracts/
sessions-api.md linha `sessionId`

- [x] 0.1.1 Editar `contracts/sessions-api.md` (secao `GET .../tail` →
      Request) declarando explicitamente que a resolucao de `sessionId` usa
      `getSessionsIndex()` do `sessions-watcher` (a mesma fonte que alimenta
      `GET /api/v1/sessions`) — nunca reconstroi o path `<slug>/<sessionId>
      .jsonl` a partir de dado enviado pelo cliente sem passar pelo indice
- [x] 0.1.2 Teste (revisao de artefato): confirmar por `grep` que o texto
      editado cita `getSessionsIndex` e que nenhuma frase remanescente sugere
      reconstrucao de path direto do request

### 0.2 Definir criterio verificavel anti-ReDoS do redactor interno `[A]`

Ref: CHK009/CHK010 (checklists/security.md), plan.md achado MEDIUM "ReDoS no
redactor interno"

- [x] 0.2.1 Editar `plan.md` §Achados residuais (ou `quickstart.md`)
      substituindo "deve ser seguro contra ReDoS" por um criterio
      implementavel: padroes ancorados (`^`/`$` ou limites explicitos), zero
      quantificadores aninhados (`(a+)+`), e o bloco `BEGIN...PRIVATE KEY`
      casado **linha-a-linha** via maquina de estados (flag "dentro do
      bloco"), nunca por um regex guloso multi-linha
- [x] 0.2.2 Acrescentar a `quickstart.md` um cenario de entrada patologica:
      texto adversarial multi-megabyte (gerar localmente, ex. repeticao de
      `"a"` seguida de sufixo que force backtracking num regex ingenuo) e
      **medir** o tempo de execucao do redactor contra ele nesta maquina de
      referencia, documentando o numero medido (nao suposto) como teto de
      regressao
- [x] 0.2.3 Teste (revisao de artefato): confirmar que o teto de tempo
      documentado tem o comando/medicao que o gerou citado ao lado (Principio
      VI — zero fabricacao de valor numerico)

### 0.3 Definir cenario de aceite do log em falha do subprocesso de scrub `[A]`

Ref: CHK012 (checklists/security.md), plan.md achado LOW "Vazamento por log"

- [x] 0.3.1 Acrescentar a `quickstart.md` um cenario que force a falha do
      subprocesso `secrets-filter.sh` (ex.: apontar `CSTK_SECRETS_FILTER`
      para um binario que sai com `exit 1`, e outro cenario com um script que
      dorme alem do timeout) e especificar o conteudo **exato** esperado do
      log resultante: apenas codigo de saida e uma flag booleana de timeout —
      nunca stdin, stdout parcial ou stderr bruto
- [x] 0.3.2 Teste (revisao de artefato): confirmar que o cenario novo cita os
      dois campos exatos do log esperado e nenhum campo de conteudo

### 0.4 Definir matriz de teste do scrub — positivos E negativos `[C]`

Ref: CHK003/CHK005 (checklists/security.md), plan.md §Cobertura medida do
filtro do cstk, orientacao do operador desta onda (onda-007)

O `{20,}` na regra de atribuicao do `secrets-filter.sh` existe para evitar
falso-positivo em prosa comum. O redactor interno encadeado tem o mesmo
dilema, agravado por servir transcript **e** prosa de conversa no mesmo
campo `text`. Sem um conjunto de casos negativos, um teste que so mede
cobertura passa com um redactor que destroi o transcript.

- [x] 0.4.1 Acrescentar a `quickstart.md` (junto ao Scenario 12) uma tabela
      de casos que **DEVEM** ser redigidos: `password=hunter2` (segredo
      curto, sem piso de 20 chars), bloco `-----BEGIN PRIVATE KEY-----`
      completo, `Bearer <token-longo>`, chave `AKIA...` (AWS)
- [x] 0.4.2 Acrescentar, na mesma tabela, os casos que **NAO PODEM** ser
      redigidos: uma linha de prosa dizendo "o campo password e obrigatorio
      neste formulario", uma linha mencionando "o token de acesso expira em
      1 hora" sem valor de segredo ao lado, e uma linha citando a palavra
      "secret" em sentido comum ("nao existe segredo aqui")
- [x] 0.4.3 Teste (revisao de artefato): confirmar que os dois conjuntos
      (positivo e negativo) estao lado a lado no mesmo cenario, com entrada e
      saida esperada explicitas para cada linha — este e o criterio de aceite
      que a tarefa 3.1 (redactor interno) e o Scenario 12 devem satisfazer

### 0.5 Resolver a tensao "nunca 4xx" vs "rate-limit leve" no contrato `[A]`

Ref: CHK019/CHK020 (checklists/api.md), plan.md §Custo e mitigacao ("Padroes
de Seguranca e Qualidade"), contracts/sessions-api.md secoes "Nao ha respostas
de erro"

A tensao e aparente, nao real — sao duas categorias distintas de resposta:

| Categoria | Causa | Resposta | Viola Principio II? |
|-----------|-------|----------|----------------------|
| Ausencia de dado | raiz de sessoes ausente/vazia, sessao sumida, arquivo ilegivel | `200` com `data` vazio/`null` + `meta.degraded=true` + `reason` tipado | Violaria se fosse `4xx`/`5xx` — por isso e sempre `200` |
| Excesso de requisicao | cliente excede o rate-limit leve nas duas rotas | `429 Too Many Requests` | **Nao.** O Principio II protege o operador de o painel quebrar quando a **fonte** esta ausente ou degradada; ele nao obriga o servidor a se autodestruir sob carga. `429` e uma resposta honesta e acionavel para excesso de requisicao, categoria ortogonal a "condicao de dado" |

- [x] 0.5.1 Editar `contracts/sessions-api.md` nas duas secoes "Nao ha
      respostas de erro" acrescentando uma linha explicita: "`429` **e**
      permitido — e a resposta ao rate-limit leve, categoria distinta de
      'condicao de dado'; ver tabela em tasks.md §0.5 / plan.md §Custo e
      mitigacao. Nao remover o rate-limit citando o Principio II — a
      distincao esta registrada aqui precisamente para isso."
- [x] 0.5.2 Definir criterio de aceite mensuravel do rate-limit (CHK020):
      limite numerico e janela de tempo por IP/sessao para as duas rotas,
      registrado em `contracts/sessions-api.md` §Configuracao junto das
      demais variaveis de ambiente (ex.: nova variavel de config, valor
      default a escolher na tarefa 5.4 — nao inventar o numero aqui, apenas o
      mecanismo e onde ele e configurado)
- [x] 0.5.3 Teste (revisao de artefato): confirmar que a tabela de distincao
      acima foi copiada/citada no contrato e que nenhuma tarefa downstream
      (5.4) pode "corrigir" o 429 para 200 sem violar esta Decisao

---

## FASE 1 - Fundacao: DTOs compartilhados

Ref: plan.md §Project Structure (packages/shared-types), §Convencoes de
Borda, data-model.md

### 1.1 Definir DTOs de sessao em `packages/shared-types` `[C]`

- [x] 1.1.1 Adicionar `SessionSummaryDTO` e `SessionTailEntryDTO` (interface
      manual) em `packages/shared-types/src/entities.ts`, campos exatos por
      `data-model.md` e `contracts/sessions-api.md` (`sessionId`,
      `projectPath`, `projectSlug`, `lastActivityAt`, `live`, `sizeBytes` /
      `uuid`, `type`, `timestamp`, `role`, `text`, `textTruncated`)
- [x] 1.1.2 Adicionar os schemas Zod gemeos em
      `packages/shared-types/src/schemas/entities.ts`, mesmos campos e tipos
- [x] 1.1.3 Adicionar os 4 literais novos de `DegradedReason`
      (`sessions-root-missing`, `sessions-root-unreadable`,
      `session-not-found`, `session-rejected`, `session-scrub-failed` — 5 no
      total) em `packages/shared-types/src/envelope.ts`
- [x] 1.1.4 Re-exportar tipo e schema em `packages/shared-types/src/index.ts`
- [x] 1.1.5 Teste: estender
      `packages/shared-types/src/__tests__/parity.test.ts` cobrindo os 2 DTOs
      novos (paridade interface↔schema, mesmo padrao dos DTOs existentes)
- [x] 1.1.6 Fechar fresta de campo OPCIONAL escapando da paridade (achado da
      revisao onda-010): a amostra tipada normal de 1.1.5 so cobre a direcao
      "campo existe hoje nos dois lados". Um campo adicionado **opcional** a
      interface no futuro compila omitido na amostra, nao entra em
      `sampleKeys` e, se o schema Zod tambem nao o declarar, o
      `toEqual(sampleKeys)` passa mesmo havendo drift — exatamente o caso
      "codigo seta o campo, Zod remove no parse (`.parse()` descarta chave
      nao declarada)" que a FASE quis impedir. Acrescentar, para os 2 DTOs
      novos, uma amostra tipada como `Required<SessionSummaryDTO>` /
      `Required<SessionTailEntryDTO>` (forca TODAS as propriedades a
      estarem presentes no literal, inclusive as que a interface vier a
      declarar opcionais) e comparar `Object.keys(sample).sort()` contra
      `Object.keys(Schema.shape).sort()`

---

## FASE 2 - Backend: guard de path, descoberta e leitura de tail

Ref: plan.md §Project Structure (apps/server/src/lib), research.md Decision
5, contracts/sessions-api.md "Guard de path (obrigatorio)"

### 2.1 Guard de confinamento de path `sessions-root.ts` `[C]`

Depende de: 0.1 (resolucao via indice), 1.1 (DTOs)

- [x] 2.1.1 Criar `apps/server/src/lib/sessions-root.ts`: raiz unica
      `CSTK_SESSIONS_ROOT` (config do servidor, nunca do cliente),
      `realpathSync` no candidato e na raiz, rejeicao de escape via `..` ou
      symlink — modelo do guard existente `project-root.ts`, **sem
      reutiliza-lo** (ele lista `~/.claude` como zona proibida — dec-024)
- [x] 2.1.2 Validar `sessionId` como UUID via Zod **antes** de qualquer
      path-join (CHK016) — rejeitar formato invalido com `session-rejected`,
      nunca deixar chegar ao `realpathSync` com string arbitraria
- [x] 2.1.3 Normalizar caixa do `sessionId` (e do slug, se aplicavel) antes
      da comparacao/resolucao — filesystem local pode ser case-insensitive
      (CHK018)
- [x] 2.1.4 Garantir abertura do arquivo **uma unica vez** pelo path ja
      resolvido (evitar TOCTOU entre checagem de existencia/confinamento e
      leitura — CHK017): um unico `fd`/stream reaproveitado, nunca
      `existsSync` seguido de `readFileSync` em duas chamadas separadas
- [x] 2.1.5 Teste: `apps/server/test/lib/sessions-root.test.ts` — escape via
      `..`, symlink apontando para fora, UUID invalido rejeitado antes do
      path-join, caixa mista resolvendo ao mesmo arquivo, raiz ausente

### 2.2 Descoberta e liveness `session-scan.ts` `[A]`

- [x] 2.2.1 Criar `apps/server/src/lib/session-scan.ts`: `readdirSync` +
      `statSync` sobre `CSTK_SESSIONS_ROOT`, deriva `SessionSummaryDTO[]` sem
      abrir a `knowledge.db` (FR-001, FR-011)
- [x] 2.2.2 Aplicar `CSTK_SESSION_LIVE_WINDOW_MS` (default 300000) para
      derivar `live` (FR-007) — sessao sem atividade alem da janela nunca e
      apresentada como "vivo"
- [x] 2.2.3 Diretorio ausente ⇒ retorno degradado (`sessions-root-missing`);
      diretorio vazio ⇒ retorno **nao-degradado** com lista vazia (FR-008,
      distincao do Constitution Check Principio II)
- [x] 2.2.4 Teste: cenario de raiz ausente, raiz vazia (nao-degradada), raiz
      com sessoes viva/nao-viva conforme a janela

### 2.3 Leitura de tail por janela `session-tail.ts` `[A]`

Depende de: 0.1 (fonte de resolucao), 0.2 (criterio de teste patologico)

- [x] 2.3.1 Criar `apps/server/src/lib/session-tail.ts`: leitura posicional a
      partir do fim do arquivo, teto duplo de linhas (default 200, clamp
      1..1000) e bytes (FR-006)
- [x] 2.3.2 `JSON.parse` por linha em try/catch; linha malformada e pulada e
      contabilizada em `skippedLines`, nunca aborta a requisicao (FR-003a)
- [x] 2.3.3 Conversao explicita `sessionId`/`session_id` → `sessionId`
      (camelCase) no ponto de leitura — unico lugar de normalizacao (plan.md
      §Convencoes de Borda)
- [x] 2.3.4 Teste: `apps/server/test/lib/session-tail.test.ts` — transcript
      grande respeitando os dois tetos, linha malformada pulada e contada,
      fixture com `sessionId` e `session_id` coexistindo confirmando que o
      DTO final usa sempre `sessionId`

---

## FASE 3 - Scrub de segredos obrigatorio

Ref: plan.md §Seguranca de Conteudo (integral), block-004/dec-030/dec-032/
dec-033

Depende de: 0.2 (criterio anti-ReDoS), 0.3 (criterio de log de falha), 0.4
(matriz positiva/negativa)

### 3.1 Redactor interno (`secret-scrub.ts`, passo 2 — sempre roda) `[C]`

- [x] 3.1.1 Criar `apps/server/src/lib/secret-scrub.ts` com o redactor
      interno minimo em TypeScript puro: padroes ancorados, sem quantificador
      aninhado, bloco `BEGIN...PRIVATE KEY` casado linha-a-linha via maquina
      de estados (conforme 0.2.1) — cobre no minimo `password=`/`token=`/
      `secret=`/`api_key=` sem piso de comprimento, e blocos de chave privada
- [x] 3.1.2 Repetir cobertura de AWS key e Bearer token no redactor interno
      (para que o caminho sem cstk continue cobrindo os 4 padroes exigidos)
- [x] 3.1.3 Teste: `apps/server/test/lib/secret-scrub.test.ts` — exercitar a
      matriz completa da tarefa 0.4 (casos que DEVEM e que NAO PODEM ser
      redigidos), mais o cenario de entrada patologica de 0.2.2 contra o teto
      de tempo documentado

### 3.2 Cadeia com `secrets-filter.sh` (passo 1, quando disponivel) `[C]`

- [x] 3.2.1 Invocar `secrets-filter.sh scrub` via subprocesso **sem shell**
      (`execFile`-style), conteudo por stdin, argumentos fixos, timeout
      `CSTK_SECRETS_FILTER_TIMEOUT_MS` (default 2000)
- [x] 3.2.2 Exigir caminho **absoluto** em `CSTK_SECRETS_FILTER`; valor nao
      absoluto ou ausente ⇒ tratar como indisponivel e cair direto no passo 2
      (`scrubMode: 'internal'`) — nunca resolver por `PATH` (CHK013)
- [x] 3.2.3 Falha do subprocesso (exit != 0 ou timeout) ⇒ descartar saida
      parcial, usar a **entrada original** como insumo do passo 2 (nunca
      servir a saida do passo 1 pela metade)
- [x] 3.2.4 Em falha, logar **apenas** codigo de saida e flag de timeout
      (conforme criterio de 0.3.1) — nunca stdin, stdout parcial ou stderr
      bruto
- [x] 3.2.5 Detectar disponibilidade do script **uma vez no startup** do
      servidor (nao por requisicao) — mitigacao de amplificacao de spawn
      citada em plan.md §Custo e mitigacao
- [x] 3.2.6 Entrada do subprocesso e limitada pela **janela de leitura**
      (FR-006), nunca pelo arquivo inteiro — declarar isso explicitamente no
      codigo (comentario) e verificar por teste
- [x] 3.2.7 Teste: subprocesso ausente/nao-executavel degrada para
      `scrubMode: 'internal'`; subprocesso falha (exit!=0, timeout) preserva
      o log restrito de 3.2.4 (fixture do cenario 0.3.1); caminho relativo em
      `CSTK_SECRETS_FILTER` e tratado como indisponivel

### 3.3 Ordem scrub-vs-truncamento `[A]`

- [x] 3.3.1 Aplicar a cadeia de scrub (3.1+3.2) **antes** do corte de
      `textTruncated` em `session-tail.ts` — nunca truncar primeiro (risco de
      cortar um segredo/bloco multi-linha ao meio e escapar das regras,
      conforme plan.md §Ordem em relacao ao truncamento)
- [x] 3.3.2 Teste: fixture com segredo posicionado exatamente na fronteira do
      teto de bytes, confirmando que o texto truncado e o texto **ja
      redigido** e que `[REDACTED]` conta para o teto

### 3.4 Superficie coberta por origem do dado, nao por rota `[A]`

- [x] 3.4.1 Aplicar a mesma cadeia de scrub a `sessions[].projectPath` e
      `sessions[].projectSlug` (rota de listagem), nao apenas a
      `entries[].text` (rota de tail) — regra e "por origem do dado", nao por
      campo/rota (plan.md §Superficie coberta)
- [x] 3.4.2 Teste: fixture com segredo embutido em `.cwd` (que vira
      `projectPath`) confirmando scrub tambem na rota de listagem

---

## FASE 4 - Watcher de sessoes

Ref: FR-011, contracts/sessions-api.md "Contrato do watcher (interno, nao
HTTP)", plan.md §Structure Decision

### 4.1 `sessions-watcher.ts` — instancia propria e independente `[A]`

- [x] 4.1.1 Criar `apps/server/src/watchers/sessions-watcher.ts` seguindo o
      **padrao** de `ingest-watcher.ts` (nao a instancia): `
      startSessionsWatcher`, `SessionsWatcherHandle`,
      `runSessionsWatcherTick`, `getSessionsIndex`,
      `resetSessionsIndexForTests` (assinaturas de contracts/sessions-api.md)
- [x] 4.1.2 Timer `.unref()`'d (nao segura o processo); instancia
      **independente** do `ingest-watcher` — falha de um nao afeta o outro
      (FR-011)
- [x] 4.1.3 Um tick nunca lanca: diretorio ausente vira indice vazio + flag
      de degradacao, nunca excecao nao capturada
- [x] 4.1.4 Teste: `apps/server/test/watchers/sessions-watcher.test.ts` —
      tick com raiz ausente nao lanca, `getSessionsIndex` reflete o ultimo
      tick, `stop()` encerra o timer, instancia isolada do `ingest-watcher`
      (falha simulada de um nao contamina o outro)

---

## FASE 5 - Rotas HTTP e configuracao

Ref: contracts/sessions-api.md (rotas completas), plan.md §Padroes de
Seguranca e Qualidade

Depende de: 0.5 (criterio de rate-limit), 1.1, 2.1, 2.2, 2.3, 3.*, 4.1

### 5.1 `GET /api/v1/sessions` `[C]`

- [x] 5.1.1 Criar `apps/server/src/routes/sessions.ts` (rota de listagem):
      Zod `safeParse` sobre `live`/`limit` com clamp/default silenciosos
      (Principio II — nunca `4xx` por query invalida)
- [x] 5.1.2 Montar resposta via `wrap()`/`wrapDegraded()` existentes
      (`sessions`, `total`, `scannedAt`, `scrubMode`) — reuso do envelope,
      sem montar `meta` a mao. Resolucao do ponto em aberto da onda-015:
      `getSessionsIndex()` (sessions-watcher.ts) passou a devolver um
      SNAPSHOT unico `{ sessions, scannedAt, degradedReason, scrubMode }` em
      vez de getters separados por campo (atomicidade — nunca misturar
      `sessions` de um tick com `scannedAt` de outro). `scannedAt: ''`
      (nunca fabricado) se o watcher jamais ticou — mitigado na pratica por
      um tick de priming sincrono em `index.ts` antes do `server.listen`
      (5.3.1). `scrubMode` da listagem vem do lote de scrub de
      `projectPath`/`projectSlug` (`session-scan.ts`, antes descartado —
      corrigido nesta task)
- [x] 5.1.3 Teste: `server.inject()` cobrindo happy path, `live=false`,
      clamp de `limit` fora de 1..500, raiz ausente (`sessions-root-missing`)
      — `apps/server/test/routes/sessions.test.ts`

### 5.2 `GET /api/v1/sessions/:sessionId/tail` `[C]`

- [x] 5.2.1 Criar handler de tail na mesma rota: `lines` com clamp/default
      (1..1000, default 200), path resolvido exclusivamente via guard 2.1 +
      indice do watcher (0.1) — nunca por `executionId` (FR-004)
- [x] 5.2.2 Aplicar cadeia de scrub (FASE 3) sobre `entries[].text` antes do
      `wrap()`; `session-scrub-failed` responde `200`/`data: null` (nunca
      texto cru) — capturado via try/catch em torno de `readSessionTail`
      (defesa em profundidade; a cadeia de scrub em si nunca lanca).
      `scrubMode` da resposta de tail vem do PROPRIO lote de `entries`
      (`session-tail.ts` `scrubAndTruncateDrafts`, antes descartado —
      corrigido nesta task), nunca do `scrubMode` da listagem (lotes
      independentes)
- [x] 5.2.3 `session-not-found` e `session-rejected` respondem `200`/
      `degraded:true` com o `reason` correto (nunca `404`) — distinguir os
      dois motivos por teste. Mapeamento: UUID malformado ou guard de
      confinamento pos-indice -> `session-rejected`; ausente do indice ou
      arquivo confinado que deixou de existir/ler -> `session-not-found`
- [x] 5.2.4 Teste: `server.inject()` cobrindo tail de sessao viva/nao-viva
      (FR-003), path traversal rejeitado, `sessionId` de outro `executionId`
      nao vaza sessao de outro projeto (CHK034 — fixture com dois
      `sessionId` reais e `executionId` identico, se disponivel na maquina de
      referencia; senao, fixture sintetica citando a fonte) — resolucao e
      EXCLUSIVA por `sessionId` (nunca `executionId`, FR-004), entao a
      fixture cobre duas sessoes de dois `projectSlug` distintos e confirma
      que o conteudo de uma nunca vaza na resposta da outra —
      `apps/server/test/routes/sessions.test.ts`

### 5.3 Registro da rota nos dois pontos `[C]`

- [x] 5.3.1 Registrar a rota em `apps/server/src/index.ts` (startup do
      watcher incluido). Adicionalmente: tick de priming (`await
      runSessionsWatcherTick()`) ANTES de `server.listen()` — fecha a
      janela de cold-start em que `setInterval` so dispara o 1o tick apos
      `CSTK_SESSIONS_WATCH_INTERVAL_MS` (default 5s), evitando que uma
      requisicao real chegue com o indice ainda vazio/nao-varrido
- [x] 5.3.2 Registrar a MESMA rota no harness paralelo `apps/server/test/
      lib/routes.test.ts` (armadilha conhecida do plan.md §Ponto de atencao —
      esquecer este passo produz teste verde sem exercitar a rota nova)
- [x] 5.3.3 Teste: rodar a suite completa (`npm test`) e confirmar que
      `routes.test.ts` falha se a rota for removida do registro paralelo
      (sanity check do proprio harness) — teste dedicado "GET /sessions —
      sanity do registro paralelo" adicionado em `routes.test.ts`

### 5.4 Configuracao e rate-limit leve `[A]`

- [x] 5.4.1 Variaveis lidas diretamente pelos modulos que as consomem —
      `CSTK_SESSIONS_ROOT`/`CSTK_SECRETS_FILTER` (`sessions-root.ts`/
      `secret-scrub.ts`, ja FASE 2/3), `CSTK_SESSION_LIVE_WINDOW_MS`
      (`session-scan.ts`, ja FASE 2), `CSTK_SECRETS_FILTER_TIMEOUT_MS`
      (`secret-scrub.ts`, ja FASE 3), `CSTK_SESSIONS_WATCH_INTERVAL_MS`
      (lido em `index.ts`, wiring do watcher, task 5.3.1) —
      DESVIO DELIBERADO do texto literal da task ("adicionar em config.ts"):
      nenhuma delas foi adicionada ao `ServerConfig`/`loadConfig()`. Mesmo
      padrao ja em producao para `CSTK_WATCH_INTERVAL_MS`/
      `CSTK_INGEST_TIMEOUT_MS` do `ingest-watcher` (lidos via
      `process.env` direto em `index.ts`, tambem fora de `ServerConfig` —
      ver `index.ts` linhas ~95-105); `CSTK_SESSIONS_RATE_LIMIT_MAX`/
      `CSTK_SESSIONS_RATE_LIMIT_WINDOW_MS` (novas desta task) seguem a
      MESMA convencao, lidas em `routes/sessions.ts`. Nao ha ganho em
      centralizar em `config.ts` variaveis que so um modulo consome, e
      duplicaria a fonte de verdade (dois lugares resolvendo o mesmo env
      var). Contrato normativo continua em `contracts/sessions-api.md`
      §Configuracao
- [x] 5.4.2 Implementar rate-limit leve nas duas rotas conforme mecanismo e
      limite definidos em 0.5.2 — resposta `429` explicita, **nao** `200`
      degradado (0.5 documenta por que isso nao viola o Principio II).
      Default 30 req/min por IP — mesmo valor ja adotado em `search.ts`
      para uma rota tambem sujeita a I/O/subprocesso por requisicao (fonte
      citada no codigo, nao um numero novo); configuravel via
      `CSTK_SESSIONS_RATE_LIMIT_MAX`/`CSTK_SESSIONS_RATE_LIMIT_WINDOW_MS`
- [x] 5.4.3 Teste: exceder o limite definido em 0.5.2 e confirmar `429` (nao
      `200`, nao `500`); dentro do limite, comportamento normal inalterado
      — `apps/server/test/routes/sessions.test.ts` describe "Rate-limit
      leve"

---

## FASE 6 - Frontend

Ref: plan.md §Project Structure (apps/web), §Complexity Tracking
(`refetchInterval` explicito, `TextBlockRaw`)

Depende de: 1.1 (DTOs), 5.* (rotas)

### 6.1 Hooks de dados `[A]`

- [x] 6.1.1 Adicionado `useSessions`/`useSessionTail` em
      `apps/web/src/lib/hooks.ts`, consumindo `fetchApi` + `SessionsListDataSchema`/
      `SessionTailDataSchema` (Zod, campos de `SessionSummaryDTOSchema`/
      `SessionTailEntryDTOSchema` de `@cstk-panel/shared-types`) — mesmo padrao
      dos hooks existentes (`useExecutions`, `useTasks`, ...)
- [x] 6.1.2 `useSessions`/`useSessionTail` usam `refetchInterval: AUTO_REFRESH_MS`
      explicito (importado de `apps/web/src/lib/query.ts`, valor 10_000) — opcoes
      extraidas em `sessionsQueryOptions`/`sessionTailQueryOptions` (task 6.1.3)
- [x] 6.1.3 Teste: `apps/web/src/lib/hooks-sessions.test.ts` — DESVIO DELIBERADO
      do enunciado literal ("testar o hook"): chamar `useSessions`/`useSessionTail`
      fora de render viola Rules of Hooks (repo sem jsdom, `environment: 'node'`
      no vitest — mesmo padrao de `hooks-docs.test.ts`). `sessionsQueryOptions`/
      `sessionTailQueryOptions` foram extraidas como funcoes puras exatamente
      para permitir este teste; verificado: `.refetchInterval === AUTO_REFRESH_MS`,
      `.enabled` por `sessionId`, e `queryFn()` parseia envelope real (inclusive
      `data:null` degradado) via Zod. `npm test` → `apps/web/src/lib/
      hooks-sessions.test.ts (14 tests)` verde (ver ETAPA 8.2 abaixo)

### 6.2 Componente de texto multi-linha `TextBlockRaw` `[A]`

- [x] 6.2.1 Criado `apps/web/src/components/TextBlockRaw.tsx`: variante de
      `TextRaw` para conteudo multi-linha, `<pre>` com escaping via children
      React — nunca `dangerouslySetInnerHTML` (FR-005, Principio V). Export em
      `apps/web/src/components/index.ts`; classe `.text-block-raw` adicionada
      a `apps/web/src/styles/tokens.css` (mono, `white-space: pre-wrap`)
- [x] 6.2.2 Teste: `apps/web/src/components/TextBlockRaw.test.ts` — mesma tecnica
      de `MarkdownView.test.ts` (`renderToStaticMarkup`, prova empirica sobre o
      HTML de fato produzido, nao so a funcao isolada): `<script>alert(1)</script>`
      sai como `&lt;script&gt;` no markup, nunca como tag interpretavel; multi-linha
      preservada dentro do `<pre>`; truncamento por `maxLength`; `null`/`undefined`
      nunca lancam excecao

### 6.3 Telas `Sessions` e `SessionDetail` `[A]`

- [x] 6.3.1 Criado `apps/web/src/screens/Sessions.tsx` (US1): lista de sessoes
      vivas (`useSessions(true)`), 4 estados obrigatorios (`LoadingState` variant
      table / `EmptyState` / `ErrorState` / `DegradedBanner` + `EmptyState` com
      `sessionsDegradedCopy`), drill-down por clique de linha para
      `/sessions/:sessionId`. NAO exibe vinculo com execucao (dec-025 — sem join
      verificado sessao↔execucao); campos exibidos restritos ao `SessionSummaryDTO`
      real. Adicionado tambem: entrada "Sessões" em `Sidebar.tsx` `NAV_ITEMS`
      (icone `eye`) — sem ela as telas ficariam inalcancaveis pela navegacao
      (plan.md linha 77 ja afirma "coerente com a navegacao existente"); fixture
      espelhada em `Sidebar.test.ts` atualizada (12→13 rotas)
- [x] 6.3.2 Criado `apps/web/src/screens/SessionDetail.tsx` (US2): tail da sessao
      via `TextBlockRaw` (uma entry por linha, `type`/`role`/`timestamp` + texto),
      indicadores de `live`/`skippedLines`/`windowTruncated`/`truncatedByBytes`.
      Roteia exclusivamente por `sessionId` de `useParams` (FR-004) — nunca
      `executionId`
- [x] 6.3.3 Registradas as duas rotas em `apps/web/src/App.tsx`
      (`<Route path="/sessions">`, `<Route path="/sessions/:sessionId">`),
      imports de `Sessions`/`SessionDetail`
- [x] 6.3.4 Teste: `apps/web/src/screens/Sessions.test.ts` +
      `apps/web/src/screens/SessionDetail.test.ts` — DESVIO DELIBERADO do
      enunciado literal ("renderizam sem excecao"): sem jsdom neste repo,
      logica de degradacao extraida como funcao pura (`sessionsDegradedCopy`/
      `sessionDetailDegradedCopy`, mesmo padrao de `pickDefaultArtifact` em
      `FeatureDetail.test.ts`) — testes cobrem EXPLICITAMENTE cada `reason` do
      contrato para cada rota (`sessions-root-missing`/`sessions-root-unreadable`
      em `GET /sessions`; `session-not-found`/`session-rejected`/
      `sessions-root-missing`/`session-scrub-failed` em `GET /sessions/:id/tail`)
      mais `default` para qualquer literal futuro nao mapeado — nunca lanca e
      sempre devolve title/subtitle nao-vazios

---

## FASE 7 - Integracao e validacao end-to-end

Ref: quickstart.md Scenarios 1-12, plan.md §Re-check, Constitution Check

Depende de: FASE 1-6 completas

### 7.1 Roundtrip e paridade de tipos (gate obrigatorio) `[C]`

- [x] 7.1.1 Executado Scenario 9 contra servidor real (`tsx apps/server/src/index.ts`,
      porta 3001 — unica permitida pela whitelist `.claude/agente-00c-whitelist`),
      `CSTK_SESSIONS_ROOT` apontado para fixture isolada em scratchpad (jamais
      `~/.claude/projects` real — confirmado sem escrita: `find ~/.claude/projects
      -name '*.jsonl' -newermt '-5 minutes'` vazio). Payload real capturado de
      `GET /sessions` e `GET /sessions/:id/tail`: chaves 100% camelCase
      (`sessionId`, nao `session_id`, apesar de a linha `.jsonl` conter as duas
      formas), tipos corretos (`sizeBytes`/`returnedLines`/`skippedLines` number,
      `live`/`textTruncated`/`truncatedByBytes` boolean), zero ocorrencia de
      `[object Promise]` em qualquer payload (funcoes de leitura assincronas
      desde onda-014)
- [x] 7.1.2 `npm run typecheck` rc=0; `npm test` → Test Files 66 passed | 1
      skipped (67), Tests 886 passed | 1 skipped (887) — baseline mantido.
      Confirmacao scriptada do payload real: script Node parseou
      `/sessions` e `/sessions/:id/tail` reais com `ApiEnvelopeSchema` +
      `SessionSummaryDTOSchema`/`SessionTailEntryDTOSchema` **de producao**
      (`packages/shared-types/dist`), compondo os mesmos objetos que
      `apps/web/src/lib/hooks.ts` usa (`SessionsListDataSchema`/
      `SessionTailDataSchema`) — `safeParse` OK nos dois payloads. Confirmada
      tambem a chamada real de `fetchApi` (`apps/web/src/lib/api.ts:48`,
      `ApiEnvelopeSchema(dataSchema).parse(json)`), provando que o parse feito
      aqui e byte-a-byte o mesmo caminho que o navegador executa — cobre o
      passo 7/8 do Scenario 9 sem exigir sessao de browser separada. Paridade
      interface-manual vs schema Zod confirmada por leitura direta
      (`entities.ts:728-741`/`746-756` vs `schemas/entities.ts:469-488`, 1-para-1)
      e pela suite `packages/shared-types` (`parity.test.ts` 36 + `parity-real.test.ts`
      40, ambas verdes). NOTA (doc, nao-bloqueante): `quickstart.md` Scenario 9
      passo 5 referencia `SessionsListDTOSchema`/`SessionTailDTOSchema` como
      exportados de `shared-types` — esses nomes nao existem; a composicao real
      vive em `hooks.ts` sobre os DTOs de campo exportados. Sugerido fix de doc,
      nao afeta o codigo entregue.

### 7.2 Invariantes de seguranca e read-only `[C]`

- [x] 7.2.1 Scenario 8: `curl .../sessions/..%2F..%2F..%2F..%2Fetc%2Fpasswd/tail`
      → `200`, `data: null`, `reason: "session-rejected"`. Scenario 11: rota
      sessions sem verbo de escrita (`grep -n "'POST'\|'PUT'\|'PATCH'"
      apps/server/src/routes/sessions.ts` → vazio, exit 1) e nenhum `.jsonl`
      real tocado durante o exercicio (find `-newermt '-5 minutes'` vazio).
      Scenario 12: fixture com `AKIAIOSFODNN7EXAMPLE` + `password=hunter2`
      (valor curto, <20 chars — so o redactor interno pega) devolvida via
      `GET /tail` como `[REDACTED-AWS-KEY] e password=[REDACTED]`, `scrubMode:
      "internal"` (Ramo B, `CSTK_SECRETS_FILTER` apontado para path inexistente);
      Ramo A (cstk presente) ja coberto por `secret-scrub.test.ts` (14 testes,
      mock de subprocesso); Ramo E confirmado por `grep -rn "REDACTED"
      apps/web/src/` vazio (scrub e so do servidor)
- [x] 7.2.2 `npm run lint:readonly-check` → `OK: no mutation verbs`
- [x] 7.2.3 `npx vitest run apps/server/test/lib/secret-scrub.test.ts
      apps/server/test/lib/session-tail.test.ts` → 2 arquivos, 35 testes,
      todos verdes. Scenarios 8/11/12 documentados acima como passando
      nesta onda (onda-018)

### 7.3 Constitution re-check final `[A]`

- [x] 7.3.1 Constitution v2.0.0 lida integralmente (nao memoria de versao
      anterior); tabela de plan.md §Constitution Check reconfirmada contra o
      codigo entregue, PASS por implementacao (nao so design):
      **I. Read-Only sobre o Corpus** — nenhum arquivo novo (`sessions-root.ts`,
      `session-scan.ts`, `session-tail.ts`, `secret-scrub.ts`, `routes/sessions.ts`,
      `watchers/sessions-watcher.ts`) referencia `knowledge.db`/`openDb`/
      `better-sqlite3` fora de comentarios explicando que NAO abrem o corpus
      (grep confirmado); unica conexao SQLite do processo continua em
      `apps/server/src/db/open.ts:100` (`mode=ro&immutable=1`); `grep -rniE
      "method:\s*['\"](POST|PUT|PATCH|DELETE)|\.(post|put|patch|delete)\("
      apps/server/src` re-executado de forma independente (nao so a alegacao
      do operador) → unico hit `inFlightStateDirs.delete(stateDir)` em
      `ingest-watcher.ts:528`, confirmado `Map.delete()` em memoria (falso-positivo,
      nao verbo HTTP/SQL). **II. Degradar, Nunca Quebrar** — todo branch de
      `routes/sessions.ts` responde `200`+`DegradedReason` tipado, nunca
      lanca/4xx/5xx por condicao de dado (confirmado por leitura linha-a-linha
      da rota). **III. Honestidade de Metrica** — nenhum campo `$`/token exibido;
      `skippedLines`/`truncatedByBytes`/`windowTruncated` explicitos; nenhum
      vinculo sessao→execucao fabricado. **IV. Nao Reimplementar** — reusa
      `wrap`/`wrapDegraded`, padrao do `ingest-watcher` em instancia separada
      (justificada em `sessions-watcher.ts:4-11`). **V. UNTRUSTED** — scrub
      obrigatorio confirmado (`secret-scrub.ts`) antes de `TextBlockRaw`
      (children React, sem `dangerouslySetInnerHTML` — grep confirmado vazio em
      `Sessions.tsx`/`SessionDetail.tsx`, so comentario o menciona). **VI.
      Snapshot que muda** — leitura via `openSync`/`fstatSync`/`readSync`/
      `closeSync` num unico fd (sem TOCTOU), watcher reconsulta `statSync` por
      ciclo. **Padroes de Seguranca**: bind `127.0.0.1` hardcoded
      (`config.ts:168`, nao configuravel por env — sem exposicao LAN), rate-limit
      leve confirmado registrado em `routes/sessions.ts:106-111`. **Fidelidade
      de Design**: telas com 4 estados (Loading/Empty/Error/Degraded) — ja
      confirmado nos testes de FASE 6.
- [x] 7.3.2 Gate `owasp-security` (skill) re-executado sobre o CODIGO final
      (nao o plano) — arquivos lidos integralmente: `secret-scrub.ts`,
      `sessions-root.ts`, `routes/sessions.ts`, `session-scan.ts`,
      `sessions-watcher.ts`, `TextBlockRaw.tsx`. Achado **HIGH** da onda-004
      (subprocesso do scrub externo) **confirmado mitigado no codigo**:
      `execFile` (nunca `exec`/shell), argumentos fixos `['scrub']`, conteudo
      via stdin (nunca argv), `timeout`/`killSignal` do proprio Node
      (`secret-scrub.ts:206-227`), path do executavel exigido **absoluto**
      (`resolveSecretsFilterPathFromEnv`, rejeita relativo → `null` → cai em
      `scrubMode: 'internal'`, nunca resolve por `PATH`). **MEDIUM ReDoS**
      mitigado: padroes ancorados (`ASSIGNMENT_PATTERN`/`BEARER_PATTERN`/
      `AWS_KEY_PATTERN`, um quantificador por grupo, zero aninhamento) +
      maquina de estados linha-a-linha para blocos `BEGIN...PRIVATE KEY`
      (`scrubPrivateKeyBlocks`) — sem regex guloso multi-linha; medicao
      empirica em quickstart.md Scenario 12.1. **MEDIUM amplificacao de
      spawn** mitigado: deteccao de disponibilidade cacheada
      (`cachedResolution`, uma vez), `scrubTextBatch` une multiplos textos em
      UM subprocesso via `BATCH_JOIN_MARKER` (fallback per-item defensivo se
      o marcador nao sobreviver 1:1), rate-limit leve 30/min por IP
      registrado nas duas rotas. **LOW vazamento por log** mitigado:
      `defaultFailureLogger` loga exclusivamente `{exitCode, timedOut}`
      (`secret-scrub.ts:131-134`), nunca stdin/stdout/stderr. **LOW resolucao
      por PATH** mitigado: path relativo/nao-absoluto tratado como
      indisponivel. **Nenhum achado NOVO critical/high**: guard de path
      traversal valida UUID via Zod ANTES do path-join + `realpathSync` +
      checagem `isUnderRoot` + leitura por fd unico (sem TOCTOU); XSS no
      transcript coberto por `TextBlockRaw` (children React puro); bind
      `127.0.0.1` hardcoded elimina exposicao de rede. Onda-018/dec-079.

---

## Matriz de Dependencias

```mermaid
flowchart TD
    F0[FASE 0 - Especificacao de Gaps]
    F1[FASE 1 - DTOs compartilhados]
    F2[FASE 2 - Guard, scan, tail]
    F3[FASE 3 - Scrub de segredos]
    F4[FASE 4 - Watcher]
    F5[FASE 5 - Rotas e config]
    F6[FASE 6 - Frontend]
    F7[FASE 7 - Integracao e validacao]

    F0 --> F1
    F0 --> F2
    F0 --> F3
    F0 --> F5
    F1 --> F2
    F1 --> F3
    F2 --> F4
    F2 --> F5
    F3 --> F5
    F4 --> F5
    F5 --> F6
    F5 --> F7
    F6 --> F7
```

## Resumo Quantitativo

| Fase | Tarefas | Subtarefas | Criticidade |
|------|---------|------------|-------------|
| 0 - Especificacao de Gaps | 5 | 14 | A/C |
| 1 - DTOs compartilhados | 1 | 5 | C |
| 2 - Guard, scan, tail | 3 | 13 | C/A |
| 3 - Scrub de segredos | 4 | 13 | C/A |
| 4 - Watcher | 1 | 4 | A |
| 5 - Rotas e config | 4 | 12 | C/A |
| 6 - Frontend | 3 | 9 | A |
| 7 - Integracao e validacao | 3 | 7 | C/A |
| **Total** | **24** | **77** | - |

## Escopo Coberto

| Item | Descricao | Fase |
|------|-----------|------|
| FR-001/FR-002 | Descoberta e listagem de sessoes vivas | 2, 4, 5 |
| FR-003/FR-003a | Tail sob demanda + linhas malformadas contadas | 2, 5 |
| FR-004 | Roteamento por `sessionId`, nunca `executionId` | 0, 2, 5 |
| FR-005 | Conteudo UNTRUSTED renderizado literal | 5, 6 |
| FR-006 | Teto duplo linhas+bytes | 2, 3 |
| FR-007/FR-008 | Liveness e degradacao nunca-erro | 2, 5 |
| FR-009/FR-010/FR-011 | Read-only e watcher independente | 2, 4 |
| Scrub obrigatorio (block-004) | Cadeia cstk+interno, 9 achados residuais | 0, 3 |
| Rate-limit leve (CHK019/020) | Distincao 429 vs degradacao, mecanismo | 0, 5 |
| DTOs e paridade | shared-types dupla definicao | 1, 7 |
| Telas US1/US2/US3 | Sessions, SessionDetail, 4 estados | 6 |

## Escopo Excluido

| Item | Descricao | Motivo |
|------|-----------|--------|
| Vinculo sessao→execucao | Exibir qual execucao autonoma corresponde a uma sessao | Nenhum join verificado existe (research.md Decision 3); exibir seria fabricar dado (Principio VI) |
| Autenticacao real | Login/token nas rotas novas | Painel roda em localhost, sem auth em nenhuma rota existente (Constitution Check) |
| Numero concreto do `refetchInterval` da trilha ao vivo (CHK038) | Intervalo mais curto que os 10s globais | Sem fonte/decisao do produto; tarefa 6.1.2 reusa o default global existente e deixa o ajuste fino como gap aberto, nao inventa o numero |
| Persistencia do indice de sessoes | Guardar o indice em disco/banco | plan.md fixa indice **volatil em memoria**; persistir seria introduzir storage novo sem justificativa (fora do Constitution Check aprovado) |
