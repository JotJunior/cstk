# Feature Specification: Human Bridge (Intervencoes)

**Feature**: `human-bridge`
**Created**: 2026-08-29
**Status**: Draft

## User Scenarios & Testing

### User Story 1 - Fila unica de intervencoes pendentes (Priority: P1)

Como operador que acompanha varias execucoes autonomas ao mesmo tempo (em
projetos diferentes), quero ver, num unico lugar, tudo que qualquer sessao
esta parada esperando minha resposta — sem precisar abrir cada projeto
separadamente para descobrir que uma sessao esta travada havas horas.

**Why this priority**: Sem uma fila unica, o operador so descobre que uma
sessao esta esperando por acaso (voltando a checar aquele projeto
especifico). Isso e o problema central que a feature resolve; sem ele nao
ha razao para as demais stories existirem.

**Independent Test**: Com duas ou mais sessoes de projetos diferentes
paradas esperando resposta, o operador abre uma unica tela e ve as duas
pendencias, cada uma identificada pelo projeto/sessao de origem.

**Acceptance Scenarios**:

1. **Given** duas sessoes autonomas em dois projetos diferentes estao cada
   uma parada esperando uma resposta humana, **When** o operador abre a
   tela de intervencoes, **Then** ambas aparecem na mesma lista, cada uma
   identificada pelo projeto e pela sessao de origem.
2. **Given** nenhuma sessao esta esperando resposta no momento, **When** o
   operador abre a tela de intervencoes, **Then** a tela mostra
   explicitamente que a fila esta vazia (nao uma tela em branco ou erro).
3. **Given** uma intervencao pendente na fila, **When** o operador informa
   a resposta correspondente aquela pendencia, **Then** apenas a sessao
   que originou aquela pendencia especifica e destravada — nenhuma outra
   sessao e afetada.

---

### User Story 2 - Responder por tipo de pergunta (Priority: P2)

Como operador, quero que a forma de responder combine com o tipo de
pergunta feita pela sessao (escolher entre opcoes fechadas, confirmar
sim/nao, ou digitar um valor livre), para nao ter que adivinhar o formato
esperado nem correr risco de dar uma resposta que a sessao nao consiga
interpretar.

**Why this priority**: Depende da fila existir (US1), mas sem ela a fila
so mostra pendencias sem meio de responde-las corretamente. E o que torna
a fila acionavel, nao so informativa.

**Independent Test**: Apresentar tres intervencoes pendentes, uma de cada
tipo (escolha fechada, confirmacao, texto livre), e confirmar que cada uma
oferece o controle de resposta adequado ao seu tipo.

**Acceptance Scenarios**:

1. **Given** uma intervencao do tipo escolha fechada com um conjunto
   definido de opcoes, **When** o operador responde, **Then** so e
   possivel escolher entre as opcoes oferecidas — nenhum valor fora do
   conjunto e aceito.
2. **Given** uma intervencao do tipo confirmacao, **When** o operador
   responde, **Then** a resposta e reduzida a sim/nao.
3. **Given** uma intervencao do tipo texto livre (por exemplo, corrigir um
   valor que a sessao suspeitou estar errado), **When** o operador digita
   um valor e envia, **Then** o valor digitado e entregue a sessao de
   origem como um DADO corrigido, nunca como uma instrucao que a sessao
   passa a executar.

---

### User Story 3 - Nunca travar para sempre, mesmo sem resposta (Priority: P3)

Como operador que pode estar ausente (dormindo, em reuniao, sem acesso ao
painel), quero que uma sessao parada esperando minha resposta eventualmente
prossiga com um comportamento seguro pre-definido, em vez de ficar
travada indefinidamente consumindo uma sessao inteira por minha causa.

**Why this priority**: Trata o caso de degradacao — importante para a
feature ser confiavel em producao, mas a fila (US1) e a resposta tipada
(US2) ja entregam valor no caminho feliz sem isso. Pode ser adicionado por
cima sem redesenhar as duas primeiras.

**Independent Test**: Deixar uma intervencao pendente sem resposta ate o
prazo maximo esgotar e confirmar que a sessao de origem prossegue com um
valor seguro pre-definido, e que a fila reflete que aquela pendencia nao
foi respondida ativamente (nao aparece como se o operador tivesse decidido
algo).

**Acceptance Scenarios**:

1. **Given** uma intervencao pendente sem resposta do operador, **When** o
   prazo maximo de espera se esgota, **Then** a sessao de origem prossegue
   automaticamente com um valor seguro pre-definido para aquela pergunta.
2. **Given** uma intervencao que expirou sem resposta, **When** o operador
   olha o historico da fila depois, **Then** o registro mostra claramente
   que ninguem respondeu (nao registra como se fosse uma decisao humana
   ativa).
3. **Given** a fila de intervencoes esta temporariamente inacessivel
   (painel fora do ar, por exemplo), **When** uma sessao precisa de
   resposta humana, **Then** a sessao detecta a indisponibilidade e segue
   o mesmo caminho seguro pre-definido, em vez de esperar por algo que
   nunca vai chegar.

---

### Edge Cases

- O que acontece se duas pessoas tentarem responder a mesma intervencao ao
  mesmo tempo? A primeira resposta valida vence; a segunda tentativa
  recebe um aviso claro de que a pendencia ja foi resolvida.
- O que acontece se a sessao de origem for encerrada/travada antes da
  resposta chegar? A resposta e descartada sem erro visivel ao operador
  (a pendencia deixa de fazer sentido, mas o operador nao fica com uma
  acao pendurada).
- O que acontece se o texto livre enviado pelo operador ultrapassar o
  tamanho maximo aceito? O excesso e cortado antes de ser entregue a
  sessao, nunca rejeitado silenciosamente sem aviso.
- O que acontece se a mesma sessao abrir uma segunda intervencao antes da
  primeira ser respondida? Ambas aparecem na fila como pendencias
  distintas, com a origem (sessao) claramente identificada em cada uma.
- O que acontece se o operador responder uma intervencao que ja expirou
  (o prazo maximo ja passou)? A resposta tardia e rejeitada com aviso
  claro — a sessao ja seguiu pelo caminho seguro pre-definido e nao pode
  ser "desfeita".
- O que acontece com uma intervencao cuja sessao de origem pertence a um
  projeto que nao existe mais / foi removido do disco? A pendencia
  continua visivel na fila (para nao esconder historico), mas marcada como
  organicamente inalcancavel se uma resposta for tentada.

## Requirements

### Functional Requirements

- **FR-001**: O sistema MUST manter uma fila unica, visivel num so lugar,
  com todas as intervencoes pendentes de qualquer sessao autonoma de
  qualquer projeto monitorado.
- **FR-002**: O sistema MUST permitir que o operador responda uma
  intervencao pendente diretamente da fila, sem precisar navegar para uma
  tela especifica de projeto ou sessao antes.
- **FR-003**: Uma resposta enviada pelo operador MUST afetar exclusivamente
  a sessao que originou aquela intervencao especifica — nunca outra
  sessao, mesmo que esteja esperando uma pergunta parecida.
- **FR-004**: O sistema MUST suportar pelo menos tres tipos de intervencao:
  escolha entre um conjunto fechado de opcoes, confirmacao sim/nao, e
  texto livre.
- **FR-005**: Para intervencoes de escolha fechada, o sistema MUST recusar
  qualquer resposta que nao esteja entre as opcoes oferecidas para aquela
  pendencia especifica.
- **FR-006**: Toda resposta em texto livre MUST ser tratada, em todo o
  sistema, como dado a ser entregue a sessao de origem — nunca como uma
  instrucao que qualquer parte do sistema executa, encaminha para outra
  etapa automatizada, ou usa para decidir o proximo passo por conta
  propria.
- **FR-007**: O sistema MUST limitar o tamanho de uma resposta em texto
  livre a um teto fixo, cortando o excesso antes de armazenar ou exibir o
  valor em qualquer lugar.
- **FR-008**: O sistema MUST aplicar uma filtragem best-effort de conteudo
  obviamente sensivel em respostas de texto livre antes de armazena-las ou
  exibi-las — reconhecendo que esse filtro tem lacunas conhecidas e nao
  substitui a responsabilidade do operador ao colar informacao vinda de
  sistemas externos.
- **FR-009**: Toda intervencao MUST ter um prazo maximo de espera; quando
  esse prazo se esgota sem resposta, o sistema MUST aplicar automaticamente
  um valor seguro pre-definido para aquela pergunta, permitindo que a
  sessao de origem prossiga.
- **FR-010**: Quando a fila de intervencoes estiver inacessivel no momento
  em que uma sessao precisa de resposta humana, o sistema MUST detectar a
  indisponibilidade e aplicar o mesmo valor seguro pre-definido de FR-009,
  em vez de aguardar indefinidamente.
- **FR-011**: O sistema MUST distinguir, no registro de cada intervencao,
  entre uma resposta ativamente dada pelo operador e um valor
  automaticamente aplicado por esgotamento de prazo ou indisponibilidade —
  as duas situacoes nunca podem ser confundidas no historico.
- **FR-012**: O registro final e auditavel de cada intervencao (a fonte
  da verdade sobre o que foi decidido) MUST continuar sendo de
  responsabilidade da sessao/agente que fez a pergunta, nunca da fila em
  si — a fila entrega a resposta ate o agente, mas nao se torna a fonte de
  verdade sobre a decisao.
- **FR-013**: A fila MUST atualizar automaticamente a lista de pendencias
  sem exigir que o operador recarregue a tela manualmente.
- **FR-014**: O sistema MUST exibir, para cada intervencao pendente, pelo
  menos o projeto e a sessao de origem e ha quanto tempo ela esta
  esperando.
- **FR-015**: O sistema MUST distinguir visualmente, na fila, intervencoes
  ainda abertas de intervencoes ja resolvidas (respondidas ou expiradas),
  de forma que o operador nunca tente responder algo que ja foi encerrado.
- **FR-016**: Uma tentativa de responder a uma intervencao que ja foi
  resolvida (por outra resposta, por expiracao, ou por indisponibilidade)
  MUST ser rejeitada com um aviso claro, e MUST NOT ser aplicada em
  duplicidade.
- **FR-017**: A indisponibilidade ou perda do armazenamento de
  intervencoes MUST degradar de forma isolada (a fila fica vazia/
  indisponivel) sem afetar nenhuma outra area do sistema de observabilidade
  usado pelo operador.
- **FR-018**: Registros de intervencoes (perguntas, respostas, textos
  livres) MUST NOT se tornar parte do acervo de conhecimento analisado
  entre projetos (o corpus historico usado para buscas e relatorios) — sao
  dados operacionais de curto prazo, nao material de analise de longo
  prazo.

> Decisoes de infraestrutura: FR-009/FR-010 cobrem a politica de prazo
> maximo + fallback seguro (equivalente a uma politica de timeout); FR-016
> cobre idempotencia de resposta (uma intervencao resolvida nao pode ser
> resolvida de novo). Nao ha scheduling periodico, rotacao de chave,
> refresh de token externo, mutex multi-pod nem backup/restore aplicavel a
> esta feature — o dado e operacional e de curta duracao por natureza
> (FR-018).

### Key Entities

- **Intervencao**: uma pergunta que uma sessao autonoma levantou e para a
  qual esta esperando resposta humana. Tem um tipo (escolha fechada,
  confirmacao ou texto livre), um estado (aberta, respondida, expirada ou
  nao-respondida por indisponibilidade), a identificacao do projeto/sessao
  de origem, e um valor seguro pre-definido para quando ninguem responde a
  tempo.
- **Fila de Intervencoes**: a listagem cross-projeto de todas as
  intervencoes, priorizada de forma a deixar claro o que esta esperando ha
  mais tempo.
- **Resposta**: o valor que o operador submete para uma intervencao
  especifica; seu formato deve corresponder ao tipo da intervencao (opcao
  escolhida, sim/nao, ou texto livre).
- **Desfecho**: o resultado final registrado para uma intervencao —
  respondida ativamente, recusada, expirada, ou nao-alcancada — sempre
  distinguindo decisao humana de aplicacao automatica do valor seguro
  pre-definido.

## Success Criteria

### Measurable Outcomes

- **SC-001**: O operador localiza e responde qualquer intervencao pendente
  de qualquer projeto monitorado a partir de uma unica tela, sem precisar
  visitar telas especificas de projeto antes.
- **SC-002**: Uma resposta enviada pelo operador reflete como resolvida
  para a sessao de origem em ate 10 segundos, sem exigir acao manual de
  atualizacao por parte do operador.
- **SC-003**: 100% das intervencoes que esgotam o prazo maximo sem resposta
  aplicam o valor seguro pre-definido automaticamente — nenhuma sessao
  fica esperando alem do prazo maximo configurado.
- **SC-004**: 100% das respostas em texto livre respeitam o teto de
  tamanho definido e passam pela filtragem de conteudo sensivel antes de
  se tornarem visiveis em qualquer tela.
- **SC-005**: Em testes com multiplas sessoes concorrentes esperando
  respostas, 0% das respostas enviadas pelo operador sao aplicadas a uma
  sessao diferente daquela para a qual foram destinadas.
- **SC-006**: Apos uma intervencao ser resolvida (respondida ou expirada),
  0% das tentativas subsequentes de responde-la produzem um segundo efeito
  sobre a sessao de origem.

## Delta Requirements

**Skip**: feature puramente nova (fila de intervencoes cross-projeto e tela do painel inexistentes hoje); nenhuma capacidade documentada em `docs/specs/current/` e alterada, removida ou renomeada por esta feature — agente-00c-feature-orchestrator, 2026-08-29.
