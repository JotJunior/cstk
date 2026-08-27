# Security Checklist: Session Tail

**Purpose**: Validar a qualidade (completude/clareza/testabilidade) dos
requisitos de seguranca da feature — nao a implementacao. Foco especial nos 9
achados de gate ja levantados (dec-027/dec-033, plan.md §Achados residuais e
§Re-check) e na cobertura combinada do scrub (secrets-filter.sh + redactor
interno), confirmada empiricamente nesta onda.
**Created**: 2026-08-27
**Feature**: `docs/specs/session-tail/spec.md`, `plan.md`, `contracts/sessions-api.md`

## Scrub de segredos — requisito nao pode depender so do filtro externo

- [x] CHK001 - O requisito de scrub declara explicitamente que a cobertura do `secrets-filter.sh` do cstk e **parcial** (nao cobre `password=`/`token=`/`secret=`/`api_key=` com valor curto, nem blocos `BEGIN...PRIVATE KEY`), em vez de assumir cobertura total do filtro externo? [Clareza, plan.md §Cobertura medida do filtro do cstk] {auto}
- [x] CHK002 - Existe requisito exigindo um segundo estagio de scrub (redactor interno) que rode **sempre**, encadeado apos o filtro externo — nao apenas como fallback de sua ausencia? [Completude, plan.md §Cadeia de scrub linha "O passo 2 nao e apenas o fallback"] {auto}
- [ ] CHK003 - O criterio de aceite do scrub cobre casos concretos e testaveis para os quatro padroes exigidos (AWS key, Bearer token, atribuicao curta tipo `password=hunter2`, bloco de chave privada PEM), com uma amostra de entrada e saida esperada por padrao — nao apenas a lista de padroes em prosa? [Mensurabilidade, Ambiguity] {humano}
- [x] CHK004 - O requisito declara qual campo(s) do payload recebem scrub e a regra e "por origem do dado" (texto derivado do transcript) em vez de "por nome de campo" — cobrindo automaticamente um futuro campo de preview sem exigir nova decisao? [Clareza, plan.md §Superficie coberta] {auto}
- [ ] CHK005 - Ha um criterio de aceite explicito no quickstart/contract testando a cadeia de scrub **combinada** (cstk ausente + presente) contra os quatro padroes concretos citados no CHK003 — ou o Scenario 12 citado no plan cobre apenas o caminho feliz (HIGH mitigado) sem exercitar as lacunas MEDIUM/LOW? [Cobertura de Cenarios, Gap] {humano}

## Ordem scrub-vs-truncamento (achado MEDIUM residual)

- [x] CHK006 - O requisito fixa explicitamente que o scrub roda **antes** do truncamento por bytes/linhas (FR-006), com a consequencia aceita documentada (texto truncado e o texto ja redigido; `[REDACTED]` conta para o teto de bytes)? [Clareza, plan.md §Ordem em relacao ao truncamento] {auto}
- [ ] CHK007 - A alternativa de inverter a ordem (truncar primeiro, para reduzir custo/superficie do subprocesso) foi avaliada e descartada com justificativa registrada (risco de cortar um segredo/bloco multi-linha ao meio e escapar das regras) — ou essa reavaliacao pedida pelo operador nesta sessao ainda nao tem requisito/decisao formal registrando o trade-off e a conclusao? [Ambiguity, Assumption] {humano}
- [x] CHK008 - O requisito declara que a entrada do subprocesso de scrub e limitada pela **janela de leitura** (linhas/bytes solicitados), nunca pelo arquivo inteiro, mitigando a amplificacao de spawn sob auto-refresh? [Completude, plan.md achado MEDIUM "Amplificacao de spawn"] {auto}

## ReDoS no redactor interno (achado MEDIUM residual)

- [ ] CHK009 - O requisito para o redactor interno especifica uma restricao de implementacao verificavel (padroes ancorados, sem quantificador aninhado, casamento do bloco de chave privada linha-a-linha via maquina de estados) em vez de apenas "deve ser seguro contra ReDoS" — termo vago sem criterio de aceite mensuravel? [Mensurabilidade, Clareza] {auto}
- [ ] CHK010 - Existe criterio de aceite/cenario de teste com entrada patologica (ex.: texto adversarial multi-megabyte projetado para maximizar backtracking) e um teto de tempo esperado, ou o requisito apenas menciona "teste com entrada patologica" sem definir o que conta como aprovado/reprovado? [Mensurabilidade, Gap] {humano}

## Vazamento por log no modo de falha do scrub (achado LOW residual)

- [x] CHK011 - O requisito de log em falha do subprocesso de scrub e especifico e restritivo (loga **apenas** codigo de saida e se houve timeout; nunca conteudo de entrada, saida parcial ou stderr bruto) — nao apenas "nao logar segredos"? [Clareza, plan.md achado LOW "Vazamento por log"] {auto}
- [ ] CHK012 - Ha um cenario de aceite testavel que force a falha do subprocesso (exit != 0, timeout) e verifique o conteudo exato do log resultante, ou essa restricao fica so em prosa no plano sem rastreamento ate um cenario de teste? [Cobertura de Cenarios, Gap] {humano}

## Resolucao do executavel por PATH (achado LOW residual)

- [x] CHK013 - O requisito exige caminho **absoluto** para `CSTK_SECRETS_FILTER` e trata qualquer valor nao-absoluto como indisponivel (degradando para `scrubMode: 'internal'`), em vez de permitir resolucao implicita via `PATH`? [Clareza, plan.md achado LOW "Resolucao do executavel por PATH"] {auto}
- [ ] CHK014 - Esse requisito de validacao de caminho absoluto esta refletido no contrato (`contracts/sessions-api.md` §Configuracao) com a mesma forca normativa que no plano, ou so aparece no plano? [Consistencia] {humano}

## Resolucao de sessionId (achados MEDIUM/LOW do gate anterior)

- [ ] CHK015 - O contrato declara explicitamente que a resolucao de `sessionId → <slug>/<sessionId>.jsonl` na rota de tail usa o **indice em memoria** mantido pelo watcher (mesma fonte que sustenta a listagem, research.md Decision 7), em vez de reconstruir o path a partir de dado enviado pelo cliente — ou essa decisao, tomada para a listagem, nao foi propagada explicitamente ao requisito da rota de tail? [Consistencia, Gap] {humano}
- [ ] CHK016 - Existe requisito exigindo validacao de formato (UUID) do `sessionId` **antes** de qualquer path-join/resolucao de arquivo, com biblioteca de validacao (ex. Zod) citada como mecanismo, ou o contrato apenas descreve o tipo como "string" com "Validation: UUID" em prosa sem amarrar isso a um passo obrigatorio antes do path-join? [Clareza, contracts/sessions-api.md linha `sessionId` Validation] {auto}
- [ ] CHK017 - O requisito de leitura do arquivo de transcript exige abrir o arquivo **uma unica vez pelo path ja resolvido** (evitando TOCTOU entre a checagem de existencia/confinamento e a leitura), ou essa exigencia consta apenas como achado residual sem estar refletida como requisito verificavel na secao de guard de path do contrato? [Gap] {humano}
- [ ] CHK018 - Ha requisito de normalizacao de caixa para o `sessionId` (e, se aplicavel, para o slug) antes da comparacao/resolucao — relevante porque o filesystem local pode ser case-insensitive (macOS) mas o guard de confinamento precisa de uma unica forma canonica para nao abrir ambiguidade de matching? [Clareza, Gap] {humano}

## Rate-limit leve (achado MEDIUM do gate original)

- [ ] CHK019 - O contrato (`contracts/sessions-api.md`) reflete o requisito de rate-limit leve nas duas rotas citado no plan.md (Padroes de Seguranca e Qualidade) — ou o contrato afirma "Nao ha respostas de erro / 4xx nunca por condicao de dado" sem esclarecer se um 429 por rate-limit e uma excecao explicita a essa regra (nao e "condicao de dado") ou se o mecanismo escolhido nao usa status HTTP de erro? [Conflict, contracts/sessions-api.md "Nao ha respostas de erro" vs plan.md "Rate-limit leve"] {humano}
- [ ] CHK020 - Existe criterio de aceite mensuravel para o rate-limit (limite numerico, janela de tempo, escopo por IP/sessao) ou o requisito permanece apenas como "rate-limit leve" sem parametro verificavel? [Mensurabilidade, Gap] {humano}

## Guard de confinamento de path (positivo, ja coberto — nao reabrir)

- [x] CHK021 - O requisito de confinamento de path declara raiz unica confiavel (config de servidor, nunca do cliente), `realpathSync` no candidato e na raiz, e rejeicao de qualquer escape via `..` ou symlink? [Completude, contracts/sessions-api.md "Guard de path (obrigatorio)", research.md Decision 5] {auto}
- [x] CHK022 - O requisito distingue claramente as condicoes degradadas `session-not-found` (nao resolve) e `session-rejected` (guard rejeitou) com respostas `200`/`degraded` distintas, mensuraveis por teste? [Clareza, Mensurabilidade, contracts/sessions-api.md "Response 200 — degradada"] {auto}

## Conteudo UNTRUSTED / anti-injecao (positivo, ja coberto)

- [x] CHK023 - O requisito de renderizacao de `text` como conteudo UNTRUSTED especifica o mecanismo exato (componente de escaping `TextBlockRaw`, nunca `dangerouslySetInnerHTML`) tornando-o verificavel por revisao de codigo, nao apenas "tratar como dado"? [Mensurabilidade, contracts/sessions-api.md linha `text` UNTRUSTED] {auto}

## Notes

- Items `{auto}` ja vem resolvidos pelo agente (`[x]` com citacao, ou marcador `[Gap]`/`[Conflict]`/`[Ambiguity]`).
- Items `{humano}` ficam `[ ]` aguardando decisao do dono do produto — a maioria aqui e follow-up direto dos 9 achados ja levantados (nao re-auditados, apenas rastreados ate um item de checklist).
- Marcar items concluidos com `[x]` apos a decisao humana.
- CHK003, CHK005, CHK009, CHK010, CHK012 pedem criterio de aceite/cenario mensuravel explicito para os achados residuais — hoje eles existem como linha de tabela em prosa no plan.md, nao como cenario de teste rastreavel; isso e o principal risco de os 9 achados "evaporarem" ao chegar no create-tasks.
- CHK015/CHK019 sao os dois `[Conflict]`/`[Gap]` de maior risco: um aponta ausencia de propagacao de uma decisao ja tomada (indice em memoria) da listagem para o tail; o outro aponta tensao textual entre "nunca 4xx" e "rate-limit leve" que precisa de resolucao explicita antes do create-tasks gerar a tarefa errada.
