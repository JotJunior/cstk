# Requirements Checklist: Transporte MCP direto (sem container, resolucao por chamada)

**Purpose**: Unit tests para a qualidade dos requisitos de `mcp-direct-transport` —
completude, clareza, consistencia, mensurabilidade — com foco adicional nos 5
pontos levantados na retomada pos-bloqueio block-003 (mitigacao de R8, dec-034,
dec-035, dec-029).
**Created**: 2026-08-16
**Feature**: [spec.md](../spec.md)

## Completude de Requisitos

- [ ] CHK001 - A mitigacao do risco R8 (supply chain do build lazy — usar a
  flag que ignora scripts de ciclo de vida no `npm ci`, severidade HIGH,
  dec-041/dec-042) esta especificada como requisito MUST amarrado a fase que
  introduz o caminho de instalacao de dependencias no host? [Completude, Gap]
  {auto}
  - **[Gap]**: nao esta. `grep -n "ignor\|lifecycle\|postinstall\|supply chain" spec.md`
    nao retorna nenhuma linha — nenhuma das FR-001..FR-015 menciona a
    mitigacao. Ela existe SOMENTE em `plan.md:208` (tabela de Riscos, R8),
    marcada `[PROPOSTA — a validar na implementacao]`, sem correspondencia em
    requisito testavel de `spec.md`. A resposta do operador ao block-003
    (2026-08-16T20:03:14Z) exige que a mitigacao vire "task MUST/critica na
    MESMA fase que introduz o caminho de instalacao" — hoje isso so pode
    acontecer via `/create-tasks` lendo o Risco R8 do plan.md diretamente
    (nenhum FR o ancora). Destino: `/create-tasks` — task MUST na fase F2
    (`plan.md:181`, "Build lazy: resolucao de `dist/`...") aplicando
    `npm ci --ignore-scripts` (nome real da flag do `npm`, verificado por
    `npm ci --help | grep -i script`) fixado por `package-lock.json`.

- [ ] CHK002 - Existe requisito de VERIFICACAO (nao suposicao) de que nenhuma
  dependencia direta ou transitiva do servidor exige build nativo antes de
  aplicar a flag que ignora scripts de ciclo de vida? [Completude, Gap]
  {auto}
  - **[Gap]**: nao existe. `plan.md:40` lista `@modelcontextprotocol/sdk
  ^1.30.0` e `zod ^4.4.3` como as duas dependencias diretas, e `plan.md:208`
  qualifica isso como "**a validar** que nenhuma dep transitiva exige build
  nativo" — termo explicito de suposicao ainda nao verificada, nao de fato
  estabelecido. Nenhuma FR exige rodar essa verificacao (ex.: inspecionar
  `package-lock.json` por pacotes com `scripts.install`/`scripts.postinstall`
  que compilam binario nativo, tipicamente via `node-gyp`/`prebuild-install`).
  Destino: `/create-tasks` — task MUST na mesma fase F2, ANTES de aplicar a
  flag: auditar a arvore de dependencias resolvida em
  `mcp/state-server/package-lock.json` por scripts de build nativo; se
  algum pacote exigir, a mitigacao MUST tratar esse caso (allowlist pontual
  ou alternativa) em vez de aplicar a flag cegamente.

- [ ] CHK003 - O requisito FR-015 (`gc` continua removendo containers
  Docker orfaos `cstk-mcp-state-*`) delimita de forma verificavel qual
  codigo do `mcp-docker.sh` atual sobrevive a remocao do arquivo (FR-005 +
  F3 do plan)? [Completude, Spec §FR-015, Gap] {auto}
  - **[Gap]** (ja conhecido e registrado, nao novo): `plan.md:206`, Risco R6,
    marca esse recorte como `[PROPOSTA]` em
    `contracts/cli-mcp-lifecycle.md §5.1`, "MUST ser validado com o codigo em
    maos antes de executar F3" — o proprio plan.md ja declara a lacuna;
    citado aqui apenas para manter rastreabilidade no checklist, sem gap
    novo a acrescentar.

## Clareza de Requisitos

- [x] CHK004 - FR-007 ("`cstk mcp status` MUST reportar o estado real da
  sessao") define o dominio fechado de estados possiveis, evitando
  ambiguidade de "estado real"? [Clareza, Spec §FR-007] {auto}
  - Satisfeito: `spec.md:182` qualifica explicitamente
    "(ativa/parada/indisponivel)" — enum fechado de 3 valores, sem termo
    vago solto.

- [x] CHK005 - FR-009 ("deixar de expor o token... como parte de qualquer
  identificador observavel") enumera exemplos concretos do que conta como
  "identificador observavel", evitando interpretacao aberta? [Clareza,
  Spec §FR-009] {auto}
  - Satisfeito: `spec.md:187-189` cita exemplos entre parenteses "(ex.: nome
    de processo, nome de recurso do sistema operacional)" e SC-004 repete a
    mesma qualificacao — consistente e concreto.

## Consistencia de Requisitos

- [x] CHK006 - A lacuna de gate de CI ja conhecida (dec-034, onda-005: os
  `.test.ts` de `mcp/state-server` nao rodam em nenhum workflow) esta
  declarada de forma rastreavel e mensuravel, mesmo que fora de `spec.md`?
  [Consistencia, Gap] {auto}
  - Satisfeito EM `plan.md`, ausente em `spec.md` (julgamento: aceitavel).
    `plan.md:202`, Risco R2, declara a lacuna e amarra a mitigacao a um
    passo mensuravel e executavel: "`npm test` local vira passo
    **obrigatorio** (quickstart cenario 0) e criterio de aceite de cada
    fase" — `plan.md:193-195` reforca "Gate de aceite de cada fase: cenario
    0 do quickstart.md (`npm test` + `tests/run.sh --check-coverage`)". E
    testavel (comando concreto, exit code). Nao ha SC correspondente em
    `spec.md` porque a lacuna e de PROCESSO de release (nao comportamento
    do produto) — dentro do escopo normal de `plan.md`, nao um requisito
    ausente de `spec.md`.

- [x] CHK007 - A ordem de corte por fases (dec-035, onda-005: F1..F7 com
  cutover isolado em F5, para nao existir estado intermediario em que o
  operador ache que funciona e nao funcione) esta refletida em criterio
  verificavel, mesmo que fora de `spec.md`? [Consistencia, Gap] {auto}
  - Satisfeito EM `plan.md`, ausente em `spec.md` (julgamento: aceitavel).
    `plan.md:172-191` declara a tabela de fases F1-F7 e a "Invariante de
    sequenciamento": "nenhuma fase antes de F5 muda o comportamento
    observado pelo operador" — verificavel por inspecao do diff de cada
    commit (F1-F4 nao tocam o launcher). Este e um requisito de SEQUENCIAMENTO
    DE ENTREGA (ordem de commits/fases), nao de comportamento observavel do
    produto em regime permanente — os FRs (FR-001..FR-015) ja descrevem o
    estado FINAL correto; o risco que dec-035 mitiga e sobre o caminho ATE
    la, que e natural pertencer a `plan.md`/`tasks.md`, nao a `spec.md`.

- [ ] CHK008 - A regressao de seguranca SEC-H2 (dec-029, onda-004: perda do
  confinamento por montagens do container quando o processo passa a rodar
  direto no host) esta declarada em `spec.md` com o mesmo peso que em
  `plan.md`, ou e aceitavel que fique somente no plano tecnico? [Consistencia,
  Risco] {humano}
  - Nao resolvido por evidencia — depende de apetite de risco/produto: hoje
    `plan.md:212-223` e `plan.md:225-259` (tabela "ganho e perda lado a
    lado" + resultado do gate `owasp-security`) declaram a regressao SEM
    alegar paridade, mas nenhuma FR/SC de `spec.md` menciona explicitamente
    que a superficie de confinamento por filesystem MUDA (User Story 3/
    FR-009 cobre so o GANHO — token deixar de vazer por nome de processo —
    nao a PERDA do confinamento por montagens). Decisao de negocio: essa
    troca (elimina vazamento por nome de container, perde sandboxing de
    processo) e aceitavel sem virar um Edge Case/SC explicito em `spec.md`,
    ou o dono do produto quer essa regressao visivel no nivel de requisito
    (nao so de design), dado que e uma mudanca MATERIAL de postura de
    seguranca em producao?

## Qualidade de Criterios de Aceite

- [x] CHK009 - SC-001 a SC-005 sao todos objetivamente mensuraveis (sem
  adjetivo vago tipo "rapido"/"robusto"), com metrica ou condicao binaria
  clara? [Mensurabilidade, Spec §Success Criteria] {auto}
  - Satisfeito: `spec.md:246-262` — SC-001 "em 100% das tentativas", SC-002
    "em 100% dos casos testados", SC-003 "completam com sucesso" (binario,
    3 operacoes nomeadas), SC-004 "em nenhum momento do ciclo de vida"
    (universal quantificavel), SC-005 comportamento binario (nao produz
    segundo processo / nao interrompe). Nenhum termo vago sem quantificador.

- [x] CHK010 - Cada Success Criteria tem pelo menos um cenario executavel
  correspondente em `quickstart.md`? [Cobertura, Spec §Success Criteria]
  {auto}
  - Satisfeito: matriz de rastreabilidade em `quickstart.md:228-241` cobre
    SC-001 (cenarios 1, 9), SC-002 (cenarios 2, 7), SC-003 (cenario 3),
    SC-004 (cenario 8), SC-005 (cenario 4) — 5/5 SCs com >=1 cenario.

## Cobertura de Cenarios / Edge Cases

- [x] CHK011 - Todas as Functional Requirements (FR-001..FR-015) tem pelo
  menos um cenario associado na matriz de rastreabilidade? [Cobertura, Gate]
  {auto}
  - Satisfeito por gate deterministico:
    `plugins/cstk/skills/checklist/scripts/requirement-coverage.sh
    docs/specs/mcp-direct-transport/spec.md` →
    `RESULT|docs/specs/mcp-direct-transport/spec.md|requirements=15|covered=15|errors=0`
    (exit 0, zero FINDING).

- [x] CHK012 - Os 6 Edge Cases de `spec.md` cobrem tanto o caminho de
  rejeicao (`session_id` invalido/ausente/terminal) quanto o de concorrencia
  (multiplas execucoes simultaneas) e o de ciclo de vida (start idempotente,
  processo morre com a sessao, stop idempotente)? [Cobertura, Spec
  §Edge Cases] {auto}
  - Satisfeito: `spec.md:136-157` — 2 edge cases de rejeicao, 1 de
    concorrencia multi-execucao, 3 de ciclo de vida (idempotencia de start,
    morte do processo com a sessao do harness, stop idempotente). Nenhuma
    lacuna evidente nas 3 categorias.

- [x] CHK013 - O contrato L-5 (launcher degrada para idle, nunca falha a
  sessao, quando `npm`/rede estao indisponiveis para o build lazy — Risco
  R7) tem cenario de aceite dedicado? [Cobertura, Spec §Risco R7] {auto}
  - Satisfeito: `quickstart.md:195-209`, Cenario 9, exercita exatamente essa
    degradacao ("simular indisponibilidade... launcher degrada para idle
    com motivo explicito... NAO Expected: falha da sessao do harness").

## Requisitos Nao-Funcionais (Seguranca)

- [x] CHK014 - O finding HIGH do gate `owasp-security` (R8) tem severidade
  e evidencia rastreaveis, sem citacao invertida remanescente? [Seguranca,
  Spec/Plan consistencia] {auto}
  - Satisfeito apos correcao: `plan.md:208` e `plan.md:240-252` documentam
    a correcao dec-041/dec-042 com evidencia de grep literal
    (`cli/lib/mcp-docker.sh:169` como unica ocorrencia real da flag no
    repo) — sem mais citar `cli/lib/serve.sh:574` como precedente de
    protecao (essa linha NAO usa a flag). Severidade HIGH confirmada,
    consistente entre `plan.md` e as Decisoes dec-041/dec-042 do state.

- [ ] CHK015 - Existe requisito MUST fixando a instalacao das dependencias
  do servidor pelo `package-lock.json` ja versionado (segunda metade da
  mitigacao de R8, alem da flag que ignora scripts)? [Seguranca, Gap] {auto}
  - **[Gap]**: mesmo problema do CHK001 — `plan.md:208` cita "fixar a
    instalacao pelo `package-lock.json` ja versionado" como parte da
    mitigacao proposta, mas nao ha FR correspondente. Destino: mesma task
    MUST de `/create-tasks` do CHK001 (usar `npm ci`, que ja exige lockfile
    presente e sincronizado — nao `npm install`).

## Dependencias e Premissas

- [x] CHK016 - A premissa "as duas dependencias diretas do servidor sao JS
  puro, sem build nativo" esta identificada como premissa NAO VALIDADA
  (nao como fato estabelecido) em todos os artefatos que a citam? [Premissa,
  Spec/Plan §R8] {auto}
  - Satisfeito quanto a honestidade do texto: `plan.md:208` usa
    consistentemente "**a validar**" (nao afirma como fato). O gap real e a
    AUSENCIA da tarefa de validacao em si (ja coberto por CHK002), nao a
    forma como a premissa esta redigida.

## Ambiguidades e Conflitos

- [x] CHK017 - As 4 perguntas da secao `## Clarifications` (dec-010,
  dec-014, dec-011, dec-015) tem cada uma uma resposta unica e sem
  contradicao entre si? [Ambiguidade, Spec §Clarifications] {auto}
  - Satisfeito: `spec.md:11-38` — 4 perguntas, cada uma com exatamente uma
    resposta "→ A:", sem afirmacoes conflitantes entre elas (a 4a
    explicitamente ajusta/supera a 3a: "ajusta dec-011: `gc` NAO vira
    no-op puro", tratado como refinamento declarado, nao contradicao
    silenciosa).

## Notes

- Items `{auto}` ja vem resolvidos pelo agente (`[x]` com citacao, ou
  marcador `[Gap]` citando o que falta).
- Items `{humano}` ficam `[ ]` aguardando decisao do dono do produto.
- Gate deterministico `requirement-coverage.sh` rodado sobre `spec.md`:
  15/15 FRs cobertos por cenario, 0 findings (ver CHK011).
