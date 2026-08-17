# Feature Specification: Opt-ins iniciais via MCP elicitation (com fallback de prosa)

**Feature**: `mcp-elicitation-optins`
**Created**: 2026-08-16
**Status**: Draft

## User Scenarios & Testing

### User Story 1 - Operador respondendo dita o valor sem passar pelo texto do modelo (Priority: P1)

Um operador inicia `/agente-00c` ou `/feature-00c` numa sessao interativa
com o servidor MCP de estado ativo. Em vez de ler um bloco de prosa e
digitar uma resposta em texto livre, o operador ve um formulario
estruturado (com os campos e opcoes ja tipados) para os opt-ins de inicio
de execucao, responde, e o valor digitado vai direto para o estado da
execucao — sem que o modelo precise interpretar a resposta em texto e
montar a flag correspondente manualmente.

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
   dentro do tempo em que a execucao pode aguardar, **When** a ausencia de
   resposta e detectada, **Then** a execucao aplica os mesmos
   valores-padrao seguros do cenario sem-operador e prossegue — este
   comportamento fica sujeito ao item `[NEEDS CLARIFICATION: sessao
   interativa com formulario pendurado sem operador — ver observacao
   abaixo]`.

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
  estruturado mais de uma vez (ex: em uma retomada)? Fica sujeito ao
  item `[NEEDS CLARIFICATION: retomada re-pergunta ou reusa a resposta ja
  registrada — ver observacao abaixo]` — o comportamento de hoje (blocos
  de prosa) e reusar a resposta ja gravada no estado sem re-perguntar em
  retomadas; o mecanismo novo deve preservar essa mesma garantia, mas o
  ponto exato onde a checagem acontece nao foi coberto pela medicao desta
  linha de trabalho.

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

## Delta Requirements

**Skip**: feature aditiva que introduz um novo canal de captura de resposta humana sem alterar nenhum FR ativo do corpus canonico — os blocos de prosa existentes permanecem intocados como fallback, e a unica capability tematicamente proxima em docs/specs/current/ (atomic-commit-staging.md, FR-014/015) cobre staging de arquivos, nao captura de opt-in — agente-00c-feature-orchestrator, 2026-08-16
