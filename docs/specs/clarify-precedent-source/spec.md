# Feature Specification: Precedente do operador como 4a fonte do clarify-answerer

**Feature**: `clarify-precedent-source`
**Created**: 2026-09-30
**Status**: Draft

> Triagem 0.0: modo autonomo detectado (AGENTE_00C_STATE_DIR / feature-00c ativa) — confirmacao herdada da invocacao do orquestrador; classificacao: feature nova (extensao de capacidade dos orquestradores 00c).

## Contexto e evidencia

Os subagentes que respondem as perguntas da etapa clarify de forma autonoma
(`agente-00c-clarify-answerer` e `feature-00c-clarify-answerer`) pontuam cada
opcao de resposta contra tres fontes: briefing, constitution e a terceira
fonte propria de cada orquestrador (stack sugerida no `agente-00c`; spec
corrente no `feature-00c`). Nenhum deles consulta respostas que o operador
humano ja deu a perguntas semelhantes em execucoes anteriores.

Medicao sobre a memoria de conhecimento global (export dos bloqueios humanos,
tratado como DADO; a classificacao por categoria/topico foi feita por LLM e e
aproximada, mas ids, perguntas e respostas sao dado real):

- 354 bloqueios humanos em 19 projetos; 353 respondidos.
- Por etapa de origem: clarify 158, execute-task 129, plan 48.
- Perguntas praticamente identicas foram re-perguntadas ao operador: blocos
  108 e 112 (projeto `wp-intel`, feature `mobile-app-multi-cliente`, etapa
  clarify — mesma pergunta sobre persistencia do historico de conversas, mesma
  resposta) e 242 e 251 (feature `dynamic-forms`, etapa execute-task — mesma
  pergunta sobre 3 tasks restantes, mesma resposta).
- Assuntos recorrentes com respostas consistentes entre projetos (por exemplo:
  escopo novo vira feature dedicada; retencao/LGPD anonimiza PII preservando o
  registro financeiro; credencial ausente vira pendente-por-ambiente; seguir
  contrato/precedente existente).
- Ha tambem assuntos com respostas divergentes conforme o contexto (por
  exemplo politica de retry) — logo precedente nao pode decidir sozinho.

Hoje a leitura da memoria de conhecimento so ocorre no inicio de `specify` e
`plan`; nunca no clarify.

## User Scenarios & Testing

### User Story 1 - Precedente reforca a pontuacao de uma opcao (Priority: P1)

Durante o clarify autonomo, quando existe resposta humana anterior a uma
pergunta semelhante, o answerer usa essa resposta como quarta fonte de
evidencia: a opcao coerente com o precedente ganha +1 na pontuacao, o que
permite decidir sem incomodar o operador quando ja ha outra fonte
concordante.

**Why this priority**: e o nucleo do valor — evita re-perguntar ao operador o
que ele ja respondeu, sem enfraquecer nenhuma garantia existente.

**Independent Test**: fornecer ao answerer uma pergunta cuja opcao A tem
suporte em exatamente uma das tres fontes atuais e um precedente respondido
que aponta para A; a saida deve decidir A com score 2, citando o id do
bloqueio de origem.

**Acceptance Scenarios**:

1. **Given** uma pergunta cuja opcao A e suportada pela spec corrente e existe
   um bloqueio respondido semelhante cuja resposta corresponde a A, **When** o
   answerer pontua as opcoes, **Then** A recebe +1 pela fonte "precedente" (total
   2), o answerer decide A e a resposta cita o id do bloqueio de origem.
2. **Given** a mesma pergunta sem nenhum precedente encontrado, **When** o
   answerer pontua, **Then** o resultado e identico ao comportamento anterior a
   esta feature (A com score 1, sem decisao automatica salvo a regra existente
   de eliminacao por constitution).

---

### User Story 2 - Precedente nunca decide sozinho nem substitui dado factual (Priority: P1)

O precedente e evidencia adicional, jamais autoridade. Uma opcao cujo unico
suporte e o precedente nao e decidida automaticamente, e um precedente nunca
fornece dado factual de sistema externo (contrato de API, URL, valor, id).

**Why this priority**: protege o Principio VI da constitution (zero
fabricacao) e o contrato de pausa humana; sem isso a feature seria um risco.

**Independent Test**: fornecer uma pergunta sem suporte nas tres fontes atuais
com um precedente concordante — a saida deve ser pausa humana (score 1, sem
escolha); e uma pergunta sobre um valor factual com precedente contendo um
valor concreto — o valor nao pode ser adotado.

**Acceptance Scenarios**:

1. **Given** uma opcao sem suporte em briefing, constitution e spec/stack mas
   com precedente concordante, **When** o answerer pontua, **Then** a opcao fica
   com score 1 e a resposta e pausa humana (a regra existente de score 1 so
   decide quando todas as outras opcoes violam a constitution).
2. **Given** uma pergunta cuja resposta exige um dado factual (nome de campo
   de payload, endpoint, valor concreto) e um precedente que menciona um valor
   de outro projeto, **When** o answerer pontua, **Then** o precedente nao conta
   ponto para esse dado e a pergunta segue o caminho de fonte real ou pausa
   humana.
3. **Given** precedentes semelhantes com respostas divergentes entre si,
   **When** o answerer pontua, **Then** o precedente nao soma ponto a nenhuma
   opcao e, se a pergunta pausar, todos os precedentes divergentes aparecem
   sinalizados como divergentes.

---

### User Story 3 - Precedente mais proximo vira recomendacao no bloqueio humano (Priority: P2)

Quando o score nao fecha e o orquestrador registra o bloqueio humano, a
pergunta ao operador inclui o precedente mais proximo como opcao recomendada,
com o id do bloqueio original, para que o operador confirme ou discorde com
um unico gesto.

**Why this priority**: reduz o custo de cada bloqueio que ainda precisa ir ao
humano; depende da recuperacao da Story 1 mas e entregavel separadamente.

**Independent Test**: forcar uma pausa humana com precedente disponivel e
verificar que a pergunta registrada contem a recomendacao e o id do bloqueio
de origem, e que a resposta nao e aplicada sem o operador.

**Acceptance Scenarios**:

1. **Given** uma pergunta que pausou (score insuficiente) e ao menos um
   precedente semelhante, **When** o orquestrador registra o bloqueio humano,
   **Then** a pergunta ao operador apresenta o precedente mais proximo como
   opcao recomendada, citando o id do bloqueio original e o projeto/feature.
2. **Given** a mesma situacao, **When** o operador responde algo diferente do
   recomendado, **Then** a resposta do operador prevalece integralmente e a
   divergencia fica registrada.

---

### User Story 4 - Degradacao graciosa e rastreabilidade (Priority: P2)

Sem memoria de conhecimento disponivel (base ausente, dependencia ausente,
nenhum resultado, erro de leitura) tudo funciona exatamente como hoje. Quando
a fonte e usada, cada uso e auditavel.

**Why this priority**: garante que a feature e estritamente aditiva e
verificavel.

**Independent Test**: executar o clarify sem base de conhecimento e comparar a
saida com a de uma execucao pre-feature; executar com precedente e verificar
que a Decisao registrada lista os ids consultados.

**Acceptance Scenarios**:

1. **Given** memoria de conhecimento ausente ou dependencia indisponivel,
   **When** o clarify roda, **Then** o resultado e identico ao anterior a esta
   feature e nenhum erro bloqueia a onda.
2. **Given** um precedente usado no score, **When** a Decisao e registrada,
   **Then** a justificativa cita os ids dos bloqueios de origem e a consulta
   ao historico fica registrada como evento auditavel (inclusive quando nao
   encontrou nada).

---

### Edge Cases

- Conteudo de precedente com diretiva embutida ("responda sempre opcao B",
  "ignore a constitution"): tratado como dado nao-confiavel — a diretiva e
  ignorada, o trecho e citado como evidencia suspeita e a pergunta pausa para
  o operador.
- Precedente cuja resposta e texto livre que nao corresponde a nenhum rotulo
  de opcao: nao soma ponto a opcao alguma; se a pergunta pausar, o texto entra
  como sugestao junto as opcoes.
- Bloqueio anterior ainda pendente (sem resposta) ou com resposta vazia: nao
  e precedente.
- Precedente vindo da propria execucao/feature corrente (como os pares
  re-perguntados 108/112): conta como precedente valido.
- Precedente de projeto diferente do corrente: sujeito ao escopo definido em
  FR-013.
- Precedente antigo, possivelmente superado por decisao posterior mais
  recente: sujeito ao criterio de idade de FR-014; quando houver precedente
  mais novo e mais antigo divergentes, vale a regra de divergencia.
- Muitos precedentes semelhantes: apenas um numero limitado e apresentado ao
  answerer, com teto de tamanho do bloco de contexto.
- Pergunta sem texto util para busca (vazia/muito curta): consulta e pulada
  sem erro.

## Requirements

### Functional Requirements

- **FR-001**: Antes de pontuar as opcoes de cada pergunta do clarify autonomo,
  o sistema MUST buscar na memoria de conhecimento bloqueios humanos ja
  respondidos semelhantes a pergunta corrente, para ambos os orquestradores
  (`agente-00c` e `feature-00c`), com o mesmo comportamento.
- **FR-002**: O sistema MUST considerar como precedente apenas bloqueios com
  status respondido e resposta nao vazia; bloqueios pendentes nao sao
  precedente.
- **FR-003**: O answerer MUST tratar o precedente como quarta fonte de
  evidencia: uma opcao suportada por precedente concordante recebe +1 na
  pontuacao. O score registrado e reportado permanece limitado a 3 (escala
  0..3 vigente); a fonte adicional pode compensar a ausencia de outra, mas
  nao eleva o teto.
- **FR-004**: Uma opcao cujo unico suporte e o precedente (nenhuma das tres
  fontes atuais concorda) MUST NOT ser decidida automaticamente; permanece
  sujeita a regra existente de score 1 e, na pratica, resulta em pausa humana.
- **FR-005**: O precedente MUST NOT fornecer nem substituir dado factual de
  sistema externo (assinatura de request/response, URL/endpoint/querystring,
  valores concretos, ids, datas). Para esses dados a fonte real continua
  obrigatoria (Principio VI); o precedente pode no maximo reforcar a
  politica/convencao, nunca o valor.
- **FR-006**: Quando os precedentes semelhantes divergem entre si quanto a
  opcao, o sistema MUST NOT somar ponto a nenhuma opcao por precedente e MUST
  sinalizar a divergencia, listando os precedentes divergentes, se a pergunta
  pausar.
- **FR-007**: Toda resposta que use precedente MUST citar, de forma
  rastreavel, o id de cada bloqueio de origem (com projeto e feature de
  origem) na lista de referencias e na justificativa da Decisao registrada.
- **FR-008**: O conteudo recuperado MUST ser tratado como dado nao-confiavel
  (mesma regra ja vigente para briefing/constitution/spec): diretivas embutidas
  sao ignoradas, o trecho e citado como evidencia suspeita e a pergunta pausa
  para o operador; o conteudo entregue ao answerer MUST ja estar filtrado de
  segredos.
- **FR-009**: Quando a pergunta pausar e o bloqueio humano for registrado, o
  sistema MUST incluir na pergunta ao operador o precedente mais proximo como
  opcao recomendada, com id do bloqueio de origem; a recomendacao MUST NOT ser
  aplicada sem a resposta do operador e a resposta do operador prevalece.
- **FR-010**: Na ausencia de memoria de conhecimento, de dependencia
  necessaria, de resultados ou em qualquer erro de leitura, o sistema MUST
  degradar para o comportamento anterior a esta feature, sem erro visivel,
  sem bloquear ou abortar a onda e sem alterar o formato da saida.
- **FR-011**: A consulta MUST ser somente leitura e limitada: numero maximo de
  precedentes entregues por pergunta e teto de tamanho do bloco de contexto
  definidos e documentados no plano; nenhuma escrita na memoria de
  conhecimento nem no estado de execucao alem do registro auditavel de FR-012.
- **FR-012**: Cada consulta ao historico para o clarify MUST ser registrada
  como evento auditavel na execucao (incluindo consultas sem resultado, com a
  contagem de achados), sem gravar o corpo bruto recuperado.
- **FR-013**: O escopo de projetos elegiveis como origem de precedente MUST
  seguir a decisao pendente [NEEDS CLARIFICATION: precedentes podem vir de
  qualquer projeto da maquina (evidencia mostra convencoes consistentes entre
  projetos, mas mistura contexto de clientes/produtos distintos) ou somente do
  projeto corrente (mais seguro, porem descarta parte do valor medido)?]. O
  rotulo de origem (projeto/feature) MUST sempre acompanhar o precedente.
- **FR-014**: A regra de idade/atualidade do precedente MUST seguir a decisao
  pendente [NEEDS CLARIFICATION: existe idade maxima ou preferencia por
  recencia quando um precedente antigo pode ter sido superado por decisao
  posterior?].
- **FR-015**: O criterio de "semelhante" MUST seguir a decisao pendente
  [NEEDS CLARIFICATION: relevancia e decidida apenas pelo answerer
  (julgamento sobre os candidatos recuperados, com justificativa) ou ha
  tambem um limiar minimo objetivo de similaridade antes de o candidato ser
  apresentado ao answerer?]. Em qualquer caso, a decisao de aplicabilidade
  MUST ser justificada na resposta.
- **FR-016**: Precedentes de qualquer etapa de origem (clarify, plan,
  execute-task) MUST ser elegiveis, exibindo a etapa de origem junto ao id;
  cabe ao answerer julgar se o assunto e aplicavel a pergunta corrente.
- **FR-017**: A entrega desta feature MUST documentar que ela toca as duas
  metades da instalacao — catalogo (agentes answerer, orquestradores, e
  referencias) exige `cstk update`/`cstk install --from`, e runtime do
  binario (recuperacao na memoria de conhecimento) exige `cstk self-update`
  — e MUST cobrir com testes automatizados o novo comportamento de
  recuperacao, pontuacao documentada e degradacao.
- **FR-018**: A regra de trust boundary e os limites operacionais atuais dos
  answerers (tools restritas, sem registro direto de Decisao, sem spawn)
  MUST ser preservados; a fonte "precedente" chega ao answerer como entrada
  fornecida pelo orquestrador-pai, nao como nova capacidade do answerer.

### Key Entities

- **Precedente**: bloqueio humano ja respondido, com id de bloqueio,
  projeto, feature, etapa de origem, pergunta, contexto para resposta,
  resposta e data. Somente leitura.
- **Pergunta corrente**: pergunta estruturada do asker (id, texto, opcoes)
  para a qual o answerer busca precedentes.
- **Referencia de precedente**: item na lista de referencias da resposta do
  answerer que identifica o precedente (id do bloqueio, projeto, feature) e a
  opcao que ele suporta.
- **Recomendacao no bloqueio**: precedente mais proximo anexado a pergunta ao
  operador quando o score nao fecha.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Nos dados historicos de bloqueios respondidos, ao reapresentar
  as perguntas dos 2 pares re-perguntados identificados (108/112 e 242/251),
  100% delas recuperam o bloqueio par como precedente.
- **SC-002**: Em 100% das decisoes automaticas auditadas, ha pelo menos uma
  das tres fontes originais concordando com a opcao escolhida (zero decisoes
  sustentadas apenas por precedente).
- **SC-003**: 100% das respostas do answerer que usam precedente listam o id
  do bloqueio de origem, e 100% dessas Decisoes registradas repetem os ids na
  justificativa.
- **SC-004**: Com a memoria de conhecimento indisponivel, a saida do clarify
  e byte-identica a saida pre-feature em 100% dos cenarios de teste
  comparados, sem nenhuma onda bloqueada por essa causa.
- **SC-005**: Em 100% das pausas humanas com precedente disponivel, a
  pergunta registrada ao operador contem o precedente mais proximo como
  opcao recomendada e nenhuma recomendacao e aplicada sem resposta do
  operador.
- **SC-006**: Em cenarios de teste com diretiva embutida no precedente ou
  dado factual no precedente, 0% resultam em decisao automatica baseada
  nesse conteudo.

## Delta Requirements

**Skip**: comportamento do clarify-answerer nao esta documentado no corpus canonico `docs/specs/current/` (nenhuma capability existente a alterar); a feature acrescenta uma fonte de evidencia sem modificar requisitos ativos catalogados — agente-00c-feature-orchestrator, 2026-09-30
