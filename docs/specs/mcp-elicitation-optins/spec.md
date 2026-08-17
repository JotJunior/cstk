# Feature Specification: Opt-ins iniciais via MCP elicitation (com fallback de prosa)

**Feature**: `mcp-elicitation-optins`
**Created**: 2026-08-16
**Status**: Draft

## Clarifications

### Session 2026-08-17

- Q: O formulario estruturado dispara antes da inicializacao do estado
  (como os blocos de prosa hoje) ou apenas depois, quando o servidor MCP
  de estado ja esta ativo para a execucao? → A: apenas depois — o
  pre-requisito do mecanismo (FR-001) exige servidor de estado ativo, que
  so existe apos `state-rw.sh init`; a arquitetura documentada torna
  estruturalmente inviavel dispara-lo antes do init (dec-014). Isso exige
  um modelo de init em duas etapas para preservar a garantia de "nenhuma
  onda opera sob valor nao confirmado" (ver decisao seguinte).
- Q: Quando a tentativa de usar o formulario estruturado falha NO MEIO da
  chamada (servidor marcado ativo, mas `elicitation/create` falha), o
  fallback de prosa deve ser totalmente silencioso (como e hoje) ou
  avisar o operador? → A: aviso minimo — uma linha em stderr informando
  que o formulario falhou e que a execucao seguiu com os defaults
  seguros, SOMENTE quando o mecanismo estava ativo e falhou (US3
  Acceptance Scenario 2); permanece silencioso quando o mecanismo nunca
  esteve disponivel (US3 Acceptance Scenario 1). Justificativa do
  operador: silencio total reproduziria a patologia que esta linha de
  trabalho combateu — o MCP reportou `status=active` servindo zero tools
  por meses sem que nada avisasse (dec-015, resposta ao bloqueio
  block-001).
- Q: O que acontece quando o tempo-limite de resposta ao formulario se
  esgota (sessao interativa presente, mas sem resposta do operador)? →
  A: a execucao aplica os mesmos valores-padrao seguros do cenario
  sem-operador e prossegue; o tempo-limite e imposto pelo lado SERVIDOR
  da chamada `elicitation/create`, entao deixa de ser necessario medir se
  o cliente/modelo pendura o formulario indefinidamente — isso desbloqueia
  o item antes marcado `[NEEDS CLARIFICATION]` em US2 Acceptance Scenario
  2 (dec-016).
- Q: O que acontece se o mesmo formulario for disparado mais de uma vez
  na mesma execucao (ex: numa retomada)? → A: reusa a resposta ja
  registrada no estado, em vez de perguntar de novo — paridade com o
  comportamento ja vigente dos opt-ins de prosa, cujos commands de resume
  nao re-promptam e leem o valor do state (dec-017).
- Q: Como reconciliar o pre-requisito estrutural do mecanismo (servidor
  ativo, que so existe apos o init) com o requisito vigente em
  `docs/specs/delivery-tier/spec.md` (Draft, ainda nao mergeado no corpus
  canonico) de que a pergunta de finalidade seja respondida "antes da
  inicializacao do estado"? → A: init em duas etapas — o init cria o
  estado minimo (com os defaults seguros de todos os opt-ins aplicaveis),
  o servidor MCP sobe, o formulario pergunta, e as respostas sao gravadas
  ANTES de qualquer onda comecar. Preserva o requisito MATERIAL ("nenhuma
  onda opera sob valor nao confirmado") mesmo alterando a letra ("antes
  do init"). Descartada a opcao pos-init-puro, que abriria uma janela em
  que `.delivery_tier` afirma `cloud-public` sem o operador ter
  respondido — e ele governa a matriz tier x gate de seguranca (dec-018).

## User Scenarios & Testing

### User Story 1 - Operador respondendo dita o valor sem passar pelo texto do modelo (Priority: P1)

Um operador inicia `/agente-00c` ou `/feature-00c` numa sessao interativa
com o servidor MCP de estado ativo. Em vez de ler um bloco de prosa e
digitar uma resposta em texto livre, o operador ve um formulario
estruturado (com os campos e opcoes ja tipados) para os opt-ins de inicio
de execucao, responde, e o valor digitado vai direto para o estado da
execucao — sem que o modelo precise interpretar a resposta em texto e
montar a flag correspondente manualmente.

> Nota de ordenacao (dec-014, dec-018): o formulario dispara apos o
> servidor de estado subir — nunca antes do init do estado, que e
> estruturalmente impossivel para uma tool MCP. Para preservar a
> garantia de que nenhuma onda opera sob valor nao confirmado, o init
> passa a ocorrer em duas etapas: o estado minimo e criado primeiro (com
> os defaults seguros de todos os opt-ins aplicaveis), o servidor de
> estado sobe, o formulario pergunta, e as respostas sao gravadas antes
> de qualquer onda comecar (ver FR-012, FR-013).

**Why this priority**: e o nucleo do problema que a feature resolve —
elimina os tres pontos de nao-determinismo hoje existentes (o modelo le
prosa livre e decide qual flag montar), sobre dados que **governam
gates** (o tier de entrega decide a matriz tier x gate de seguranca).

**Independent Test**: iniciar uma execucao com o servidor de estado ativo
e sessao interativa disponivel; responder ao formulario; verificar que o
estado da execucao reflete exatamente o valor escolhido, sem qualquer
etapa intermediaria de interpretacao de texto livre.

**Acceptance Scenarios**:

1. **Given** sessao interativa com servidor de estado ativo, **When** o
   operador responde afirmativamente ao campo de commit atomico, **Then**
   o estado da execucao registra o modo de commit atomico habilitado, com
   o registro de auditoria apontando a resposta estruturada do operador
   como origem (nao uma linha de prosa interpretada).
2. **Given** sessao interativa com servidor de estado ativo (somente no
   orquestrador que oferece o campo de finalidade de entrega), **When** o
   operador seleciona uma das opcoes do campo de finalidade de entrega,
   **Then** o estado da execucao registra exatamente o token
   correspondente a opcao escolhida, sem qualquer mapeamento feito pelo
   modelo em texto.
3. **Given** o operador recusa explicitamente um dos campos (acao
   distinta de simplesmente nao responder), **When** a execucao processa
   a resposta, **Then** o estado da execucao registra uma recusa
   explicita para aquele campo, distinta do caso "sem operador presente".

---

### User Story 2 - Sem operador presente, a execucao segue com os defaults seguros de hoje (Priority: P1)

Uma execucao inicia sem sessao interativa (execucao agendada, headless,
ou disparada por retomada automatica) ou com sessao interativa mas sem
ninguem para responder ao formulario. A execucao NAO fica parada
esperando uma resposta que nunca vira — ela segue adiante aplicando os
mesmos valores-padrao seguros que a captura em prosa aplica hoje.

**Why this priority**: e a garantia que evita que o mecanismo novo
introduza um jeito novo de travar uma execucao autonoma — requisito
inegociavel tanto para o mecanismo antigo quanto para o novo.

**Independent Test**: iniciar uma execucao sem operador disponivel para
responder (execucao nao-interativa) e confirmar que a execucao prossegue
sem pausa alguma, com os mesmos valores-padrao hoje documentados nos
blocos de prosa (commit atomico desabilitado, modo roadmap desabilitado,
finalidade de entrega no nivel mais restritivo).

**Acceptance Scenarios**:

1. **Given** execucao disparada sem sessao interativa, **When** a
   inicializacao do estado ocorre, **Then** todos os opt-ins recebem seus
   valores-padrao seguros e a execucao prossegue sem qualquer pausa
   aguardando resposta.
2. **Given** sessao interativa presente mas sem resposta do operador
   dentro do tempo-limite que o SERVIDOR aplica a chamada
   `elicitation/create`, **When** o tempo-limite se esgota, **Then** a
   execucao aplica os mesmos valores-padrao seguros do cenario
   sem-operador e prossegue. O tempo-limite e imposto pelo lado servidor
   da propria chamada, portanto nao depende de o cliente/modelo
   orquestrador ter ou nao um mecanismo proprio de timeout — resolvido,
   dec-016 (ver Clarifications; FR-010).

---

### User Story 3 - Servidor de estado indisponivel, a captura por texto continua funcionando (Priority: P1)

O servidor de estado nao esta disponivel para esta execucao (por
qualquer motivo — nao inicializado, sessao sem suporte ao mecanismo
estruturado, falha de qualquer natureza). A execucao usa exatamente o
mesmo caminho de hoje: os tres blocos de prosa perguntam ao operador em
texto, o modelo le a resposta e monta a flag correspondente.

**Why this priority**: garante zero regressao — o mecanismo novo e
estritamente aditivo sobre um caminho que ja funciona e continua sendo a
unica opcao quando o pre-requisito do mecanismo novo nao esta satisfeito.

**Independent Test**: iniciar uma execucao com o servidor de estado
indisponivel (ou indicando que o mecanismo estruturado nao pode ser
usado) e confirmar que os tres opt-ins sao perguntados e respondidos
exatamente como sao hoje, sem qualquer erro ou pausa adicional
introduzidos pela tentativa de usar o mecanismo novo primeiro.

**Acceptance Scenarios**:

1. **Given** servidor de estado indisponivel para a execucao corrente,
   **When** a inicializacao do estado chega ao ponto de perguntar os
   opt-ins, **Then** o comportamento observado e identico ao bloco de
   prosa hoje documentado, sem qualquer tentativa visivel ao operador de
   usar o mecanismo novo.
2. **Given** o servidor de estado esta marcado como ativo mas a tentativa
   de usar o mecanismo estruturado falha por qualquer motivo durante a
   propria pergunta, **When** a falha ocorre, **Then** a execucao cai
   para o bloco de prosa correspondente sem repetir a pergunta ao
   operador duas vezes e sem travar.

---

### Edge Cases

- O que acontece quando o operador recusa explicitamente (acao distinta
  de "nao respondeu") um campo do formulario estruturado? A execucao
  registra essa recusa como um estado proprio (nao equivalente a
  "ausencia de operador"), e aplica o valor-padrao seguro do campo (US1
  Acceptance Scenario 3, US2).
- O que acontece se o campo de finalidade de entrega for oferecido por um
  orquestrador que hoje NAO pergunta esse campo (o orquestrador de
  feature individual, por decisao ja tomada em feature anterior)? O
  formulario estruturado NAO deve introduzir esse campo onde ele nao
  existe hoje — a paridade de escopo entre os dois orquestradores para
  esse campo especifico e preservada.
- O que acontece se a mesma execucao tentar disparar o formulario
  estruturado mais de uma vez (ex: em uma retomada)? Resolvido (dec-017):
  reusa a resposta ja registrada no estado, sem re-perguntar — mesma
  garantia hoje aplicada aos blocos de prosa. A checagem acontece ANTES
  do dispatch da tool estruturada: se o campo ja tem uma
  `RespostaDeOptIn` registrada no estado (por qualquer canal, estruturado
  ou prosa), o formulario NAO MUST ser invocado de novo para aquele campo
  (FR-011).
- O que acontece se o servidor MCP falhar ao subir (ex: Docker
  indisponivel, `mode=bash-fallback`) DEPOIS que a etapa 1 do init em
  duas etapas (FR-012) ja criou o estado minimo? A execucao cai para o
  caminho de prosa de FR-005, agora necessariamente executado apos o
  init minimo (em vez de antes, como no caminho single-step legado sem o
  mecanismo estruturado envolvido) — a garantia que FR-005 protege
  (mesmas perguntas, mesmos valores-padrao, zero pausa adicional) MUST
  permanecer intacta; o que muda e apenas a posicao relativa ao init, uma
  consequencia estrutural do bash-fallback ja documentado (`cstk mcp
  start`: "Docker indisponivel ... start grava mode=bash-fallback e os
  commands pai seguem pelo caminho Bash existente — zero regressao
  funcional"), nao uma decisao nova desta feature (dec-020, engenharia).
- Elicitation disparada a partir de um subagente orquestrador (sem
  operador humano presente) permanece **Deferred, fora do escopo desta
  feature** — tratado em `docs/specs/orchestrator-mcp-allowlist/spec.md`
  FR-010 ("Deferred — fonte pendente"). Esta feature nao assume nenhum
  comportamento para esse cenario e nao o resolve.

## Requirements

### Functional Requirements

- **FR-001**: O sistema MUST oferecer, quando o pre-requisito do
  mecanismo estruturado estiver satisfeito (sessao com suporte ao
  mecanismo + servidor de estado ativo para a execucao corrente), um
  UNICO formulario estruturado no inicio da execucao contendo os campos
  hoje capturados pelos blocos de prosa aplicaveis ao orquestrador
  corrente: campo booleano para o opt-in de commit atomico e campo
  booleano para o opt-in de modo roadmap (ambos oferecidos por qualquer
  um dos dois orquestradores autonomos), mais um campo de selecao entre 4
  valores fixos para a finalidade de entrega (oferecido apenas pelo
  orquestrador de projeto completo, nunca pelo orquestrador de feature
  individual — paridade de escopo preservada, ver Edge Cases).
- **FR-002**: Cada campo do formulario estruturado MUST expor ao operador
  o mesmo texto explicativo e as mesmas opcoes hoje descritas nos blocos
  de prosa correspondentes (mesmo enunciado de consequencias, mesmas 4
  opcoes de finalidade de entrega com o mesmo texto).
- **FR-003**: A resposta do operador ao formulario estruturado MUST ser
  gravada no estado da execucao sem que o texto de resposta passe pelo
  contexto conversacional do modelo orquestrador como texto livre a ser
  interpretado — o modelo NAO MUST decidir, a partir de uma leitura de
  texto, qual flag corresponde a resposta.
- **FR-004**: O sistema MUST distinguir, no registro de auditoria da
  execucao, tres desfechos possiveis para o formulario estruturado: o
  operador respondeu e aceitou (valor aplicado = resposta), o operador
  recusou explicitamente (valor aplicado = default seguro, registrado
  como recusa), e nao houve operador disponivel para responder (valor
  aplicado = default seguro, registrado como ausencia). Os ultimos dois
  desfechos MUST permanecer distinguiveis um do outro no registro.
- **FR-005**: Quando o pre-requisito do mecanismo estruturado nao estiver
  satisfeito (servidor de estado indisponivel para a execucao, ou sessao
  sem suporte ao mecanismo), o sistema MUST usar o caminho de blocos de
  prosa hoje existente para os tres opt-ins, sem alteracao de
  comportamento em relacao ao que esta documentado atualmente.
- **FR-006**: Nenhum valor-padrao seguro MUST mudar em relacao ao
  comportamento hoje documentado: opt-in de commit atomico e opt-in de
  modo roadmap MUST defaultar para desabilitado quando nao respondidos
  (por qualquer motivo); a finalidade de entrega MUST defaultar para o
  nivel mais restritivo/seguro da escala quando nao respondida (por
  qualquer motivo).
- **FR-007**: O sistema MUST NUNCA permitir que uma execucao fique parada
  indefinidamente aguardando resposta ao formulario estruturado — ausencia
  de resposta (por ausencia de operador, por indisponibilidade do
  mecanismo em qualquer etapa da pergunta, ou por qualquer outro motivo)
  MUST sempre resolver para o valor-padrao seguro do campo dentro de um
  tempo limitado, nunca bloqueando a execucao de forma permanente.
- **FR-008**: Uma execucao retomada (apos pausa/agendamento) MUST NUNCA
  re-perguntar um opt-in cuja resposta ja esta registrada no estado da
  execucao — mesma garantia hoje aplicada aos blocos de prosa, preservada
  independentemente de qual dos dois mecanismos (estruturado ou prosa) foi
  usado na resposta original.
- **FR-009**: Quando o pre-requisito do mecanismo estruturado estava
  satisfeito no INICIO da chamada (servidor de estado marcado ativo) mas
  a chamada `elicitation/create` falhar durante a propria pergunta (US3
  Acceptance Scenario 2), o sistema MUST emitir exatamente UMA linha de
  aviso em stderr informando que o formulario estruturado falhou e que a
  execucao seguiu com os valores-padrao seguros, antes de cair no bloco
  de prosa correspondente. Este aviso MUST NUNCA ser emitido quando o
  mecanismo estruturado nunca esteve disponivel desde o inicio (US3
  Acceptance Scenario 1, FR-005) — os dois casos MUST permanecer
  distinguiveis na experiencia observada pelo operador (dec-015).
- **FR-010**: O tempo-limite de espera por resposta ao formulario
  estruturado MUST ser imposto pelo lado SERVIDOR da chamada
  `elicitation/create`, nunca por uma medicao de quanto tempo o
  cliente/modelo orquestrador tolera aguardar — ao esgotar, o sistema
  MUST aplicar os mesmos valores-padrao seguros do cenario sem-operador
  (FR-006) e prosseguir, sem depender de o cliente possuir mecanismo de
  timeout proprio (dec-016).
- **FR-011**: Antes de disparar o formulario estruturado para um campo
  especifico, o sistema MUST checar se ja existe uma `RespostaDeOptIn`
  registrada para aquele campo na execucao corrente (por qualquer canal,
  estruturado ou prosa); se existir, o sistema MUST reusar o valor ja
  registrado e MUST NOT invocar a tool estruturada de novo para aquele
  campo — vale tanto para retomadas quanto para qualquer outra tentativa
  de disparo repetido dentro da mesma execucao (dec-017, refina FR-008).
- **FR-012**: A inicializacao do estado da execucao MUST ocorrer em duas
  etapas quando o pre-requisito de FR-001 estiver satisfeito: (1) o
  estado minimo e criado com os valores-padrao seguros de todos os
  opt-ins aplicaveis (equivalente ao `state-rw.sh init` hoje existente,
  sem aguardar nenhuma resposta — `--atomic-commit`/`--roadmap-mode`/
  `--delivery-tier` omitidos defaultam para `false`/`cloud-public`); (2)
  o servidor de estado sobe, o formulario estruturado e oferecido, e as
  respostas (aceitas, recusadas, ou resolvidas por timeout via FR-010)
  sao persistidas. A etapa (2) MUST concluir — com resposta do operador
  ou com o timeout resolvendo para o default — ANTES de qualquer onda da
  pipeline comecar. Nenhuma onda MUST operar sob um opt-in cujo valor
  ainda nao foi confirmado (aceito, recusado ou defaultado) (dec-018). Se
  o servidor falhar ao subir apos a etapa (1) (`mode=bash-fallback`), o
  sistema MUST cair para o caminho de prosa de FR-005 (ver Edge Cases).
- **FR-013**: A persistencia da etapa (2) de FR-012 MUST usar as
  primitivas de escrita pos-init ja existentes no runtime para cada
  opt-in — `commit-mode.sh set-enabled`, `roadmap-mode.sh set-enabled` e
  `delivery-tier.sh set` (esta ultima apenas no orquestrador de projeto
  completo, ver FR-001) — em vez do caminho hoje usado de flags passadas
  ao `state-rw.sh init` no momento da criacao do estado. Essas primitivas
  ja existem no runtime instalado (`plugins/cstk/skills/
  agente-00c-runtime/scripts/`) mas ate esta feature nao tinham chamador
  ativo; esta feature MUST ser o primeiro caller de fato de cada uma
  delas para o caminho estruturado (dec-018, implicacao de escrita).

> Decisoes de infraestrutura: N/A (feature nao introduz scheduling, key
> rotation, refresh de token externo, lock multi-pod, backup ou
> idempotencia de request — e uma troca de canal de captura de resposta
> humana ja existente, sobre um servidor de estado ja provisionado por
> outra feature).

### Key Entities

- **RespostaDeOptIn**: representa o desfecho de um campo do formulario
  (estruturado ou de prosa) apos a inicializacao de uma execucao.
  Atributos conceituais: qual campo (commit atomico / modo roadmap /
  finalidade de entrega), qual canal produziu a resposta (formulario
  estruturado ou bloco de prosa), qual desfecho (aceito com valor
  explicito / recusado explicitamente / ausente-aplicou-default), e o
  valor final efetivamente aplicado ao estado da execucao.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Em sessoes com o mecanismo estruturado disponivel, 100% das
  respostas aos opt-ins de inicio de execucao chegam ao estado da
  execucao sem qualquer etapa de interpretacao de texto livre pelo
  modelo orquestrador entre a resposta do operador e o valor gravado.
- **SC-002**: Em qualquer combinacao de disponibilidade do mecanismo
  (disponivel ou nao) e presenca do operador (presente, ausente, ou
  recusando explicitamente), 0% das execucoes ficam paradas
  indefinidamente aguardando resposta a um opt-in — todas prosseguem
  dentro de um tempo limitado.
- **SC-003**: Em sessoes sem o mecanismo estruturado disponivel, 100% das
  execucoes capturam os tres opt-ins pelo caminho de hoje (blocos de
  prosa), com o mesmo comportamento observavel documentado antes desta
  feature.
- **SC-004**: 100% das recusas explicitas do operador ficam registradas
  no historico de auditoria da execucao de forma distinguivel de uma
  ausencia de operador, para qualquer um dos campos do formulario.
- **SC-005**: Em 100% das ocorrencias em que o mecanismo estruturado
  estava ativo e falhou no meio da chamada (US3 Acceptance Scenario 2),
  exatamente UMA linha de aviso e emitida em stderr; em 100% das
  ocorrencias em que o mecanismo nunca esteve disponivel (US3 Acceptance
  Scenario 1), nenhuma linha de aviso e emitida — os dois casos permanecem
  distinguiveis na saida observada pelo operador.

## Delta Requirements

**Skip**: feature aditiva que introduz um novo canal de captura de resposta humana sem alterar nenhum FR ativo do corpus canonico — os blocos de prosa existentes permanecem intocados como fallback, e a unica capability tematicamente proxima em docs/specs/current/ (atomic-commit-staging.md, FR-014/015) cobre staging de arquivos, nao captura de opt-in — agente-00c-feature-orchestrator, 2026-08-16

**Delta**: sessao de clarify (2026-08-17) resolveu o ovo-e-galinha entre
o pre-requisito estrutural do mecanismo (servidor de estado ativo, que so
existe apos `state-rw.sh init`) e o requisito vigente, ainda em
`docs/specs/delivery-tier/spec.md` (Draft, NAO mergeado em
`docs/specs/current/`), de que a pergunta de finalidade seja respondida
"antes da inicializacao do estado" (US1 daquela feature). Decisao do
operador (dec-018): init em duas etapas — o init cria o estado minimo com
os defaults seguros, o servidor de estado sobe, o formulario estruturado
pergunta, e as respostas sao gravadas ANTES de qualquer onda comecar
(FR-012). Isso preserva o requisito MATERIAL de delivery-tier ("nenhuma
onda opera sob valor nao confirmado") sem preservar a letra ("antes do
init"); NAO ha edicao a `delivery-tier/spec.md` nesta sessao — aquela
feature ainda esta em Draft e nao mergeada no corpus canonico, entao nao
ha capability ativa para deltar formalmente ali; a reconciliacao textual
fica marcada como trabalho pendente para quando `delivery-tier` avancar
de fase. A persistencia pos-init passa a usar primitivas ja existentes no
runtime, ate esta feature sem chamador ativo (`commit-mode.sh
set-enabled`, `roadmap-mode.sh set-enabled`, `delivery-tier.sh set` —
FR-013) — agente-00c-feature-orchestrator, 2026-08-17
