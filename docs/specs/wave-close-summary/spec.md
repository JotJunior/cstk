# Feature Specification: Resumo Deterministico de Fechamento de Onda

**Feature**: `wave-close-summary`
**Created**: 2026-09-22
**Status**: Draft

## Clarifications

### Session 2026-09-22

- Q: FR-006 exige indicadores de volume de trabalho (chamadas de ferramenta,
  duracao) — a fonte deve ser os campos ja capturados por onda ou uma
  instrumentacao nova? → A: Reusar os campos ja registrados por onda
  (mecanismo existente de metricas por onda); nenhuma instrumentacao nova.
- Q: FR-007 (SHOULD) exige indicador de custo/consumo quando disponivel no
  ambiente — a fonte deve ser OTel/`wave_model_usage` existente ou um
  mecanismo separado? → A: Reusar OTel/`wave_model_usage` existente como
  unica fonte quando disponivel; nenhum mecanismo de medicao de custo
  separado ou novo.
- Q: FR-012 exige filtragem de conteudo sensivel em texto livre de decisoes/
  bloqueios — o mecanismo deve reusar `secrets-filter.sh scrub` (ja usado no
  projeto) ou um filtro novo dedicado? → A: Reusar `secrets-filter.sh
  scrub` — mesmo mecanismo ja usado em `enforcement-log.jsonl` e no
  `recall`/knowledge.db; nenhum filtro novo dedicado (decisao humana,
  block-001/dec-014).
- Q: O resumo deve incluir trechos de texto livre cru de decisoes/bloqueios
  (mesmo filtrado) ou apenas contagens/metadados estruturados? → A: Apenas
  contagens e metadados estruturados; nenhum trecho de texto livre cru (nem
  filtrado) e incluido no resumo.
- Q: A composicao do resumo deve viver em um helper POSIX dedicado e
  testavel, ou em logica/prosa inline em cada comando pai? → A: Helper
  POSIX dedicado e testavel em `agente-00c-runtime/scripts`, reusado pelos
  dois comandos pai (`agente-00c` e `feature-00c`), com cobertura em
  `tests/`.

## User Scenarios & Testing

### User Story 1 - Ver o que aconteceu na onda que acabou de fechar (Priority: P1)

Um operador humano inicia (ou retoma) uma execucao autonoma de pipeline SDD
sobre um projeto ou sobre uma feature individual. A execucao roda por uma
onda inteira dentro de um subagente orquestrador, cuja saida nunca chega a
conversa do operador — apenas o comando pai que o invocou escreve na
conversa. Quando a onda termina e o controle volta ao comando pai, o
operador quer, sem precisar abrir arquivos de estado nem rodar comandos
manuais, entender de forma objetiva o que aconteceu: em que etapa a
execucao parou, quanto trabalho foi feito, quantas decisoes auditaveis
foram tomadas, se ha algo pendente de resposta humana, e o que vai
acontecer a seguir.

**Why this priority**: Sem isso, o operador fica cego ao final de cada
onda — precisa inspecionar arquivos de estado manualmente ou confiar
apenas na inferencia indireta do que o comando pai reporta. Essa e a dor
concreta que motiva a feature: e o unico cenario que, sozinho, ja
justifica a mudanca.

**Independent Test**: Pode ser testada isoladamente rodando uma execucao
autonoma completa (uma onda) e verificando que a mensagem final entregue
ao operador contem um resumo legivel da onda que acabou de fechar, sem
exigir nenhuma outra capacidade da feature.

**Acceptance Scenarios**:

1. **Given** uma onda de execucao autonoma terminou normalmente (etapa
   concluida, avancando para a proxima), **When** o comando pai retoma o
   controle apos a reconciliacao de estado da onda, **Then** a mensagem
   entregue ao operador inclui um resumo objetivo contendo, no minimo: a
   etapa em que a onda terminou, a proxima instrucao planejada, e a
   contagem de decisoes auditaveis registradas na onda.
2. **Given** uma onda terminou porque atingiu um limite operacional (ex.:
   orcamento de chamadas/tempo da onda), **When** o resumo e composto,
   **Then** o resumo reflete o motivo real do termino da onda (nao apenas
   "etapa concluida"), permitindo ao operador distinguir termino normal de
   termino por limite.
3. **Given** uma onda terminou com um bloqueio pendente de resposta
   humana, **When** o resumo e composto, **Then** o resumo evidencia que
   ha pendencia aguardando o operador, incluindo a contagem de bloqueios
   pendentes.

---

### User Story 2 - Confiar que numeros ausentes nunca aparecem como zero (Priority: P2)

O mesmo operador, ao ler o resumo de uma onda, precisa poder distinguir
"esta metrica foi medida e o valor e zero" de "esta metrica nao pode ser
medida nesta execucao" (por exemplo, quando uma dependencia opcional de
medicao de custo nao esta disponivel no ambiente). Um resumo que
apresenta silenciosamente `0` para uma metrica nao medida levaria o
operador a tirar conclusoes erradas sobre o custo ou volume real da onda.

**Why this priority**: Depende da existencia do resumo (US1), mas e
essencial para a confiabilidade do que e mostrado — sem essa garantia, o
resumo pode ser pior que a ausencia de resumo, por induzir o operador ao
erro com numeros fabricados.

**Independent Test**: Pode ser testada isoladamente simulando um estado
de execucao em que uma fonte de medicao opcional (ex.: custo/tokens) nao
esta disponivel, e verificando que o resumo apresenta essa metrica de
forma explicitamente distinta de zero, sem exigir as demais capacidades
da feature.

**Acceptance Scenarios**:

1. **Given** uma onda cuja medicao de custo/tokens nao esta disponivel no
   ambiente da execucao, **When** o resumo e composto, **Then** o campo
   correspondente indica explicitamente que a metrica nao foi medida, em
   vez de apresentar um valor numerico.
2. **Given** uma onda cuja medicao de custo/tokens esta disponivel e o
   valor medido e efetivamente zero, **When** o resumo e composto,
   **Then** o campo correspondente apresenta o valor zero medido,
   distinguivel textualmente do caso "nao medido".

---

### User Story 3 - Resumo nunca impede a execucao de prosseguir (Priority: P3)

O mesmo operador roda execucoes autonomas de longa duracao, muitas vezes
sem supervisao continua (a execucao pode ser retomada por agendamento).
Se a composicao do resumo falhar por qualquer motivo (dado ausente,
formato inesperado, ambiente incompleto), a execucao autonoma nao pode
travar por causa disso — a informacao de progresso e complementar, nao
critica para o funcionamento da pipeline.

**Why this priority**: E uma garantia de robustez sobre as duas stories
anteriores. Tem prioridade mais baixa porque so importa quando algo da
composicao do resumo falha — o caminho feliz (US1 e US2) e o que entrega
valor na maioria das execucoes.

**Independent Test**: Pode ser testada isoladamente forcando uma falha na
composicao do resumo (ex.: dado de estado corrompido ou ausente) e
verificando que a execucao autonoma prossegue normalmente para a etapa
seguinte, apenas com um aviso visivel de que o resumo nao pode ser
gerado.

**Acceptance Scenarios**:

1. **Given** a composicao do resumo falha por qualquer motivo durante o
   fechamento de uma onda, **When** o comando pai prossegue seu fluxo
   normal (reconciliacao de estado, e, quando aplicavel, o agendamento da
   proxima onda), **Then** a execucao autonoma continua sem interrupcao, e
   o operador recebe um aviso objetivo de que o resumo nao pode ser
   composto naquela onda.

---

### Edge Cases

- O que acontece quando a onda que acabou de fechar e a PRIMEIRA onda da
  execucao (sem onda anterior para comparar)? O resumo deve refletir
  apenas o que aconteceu nesta unica onda, sem presumir historico.
- Como o sistema se comporta quando nao ha nenhuma decisao auditavel
  registrada na onda (onda muito curta ou que terminou cedo por um
  gatilho de aborto)? O resumo deve mostrar contagem zero de decisoes de
  forma legivel, sem tratar isso como erro.
- Como o sistema se comporta quando ha texto livre potencialmente
  sensivel embutido no conteudo bruto de decisoes ou bloqueios da onda
  (ex.: um valor de configuracao ou segredo citado por engano num
  contexto de decisao)? O resumo nao pode expor esse conteudo em texto
  claro.
- O que acontece quando a execucao autonoma e sobre uma feature individual
  versus sobre um projeto inteiro (dois modos de execucao distintos do
  sistema)? O resumo deve funcionar identicamente para os dois modos, sem
  exigir que o operador saiba qual modo esta em uso.
- O que acontece quando a onda termina por um motivo que exige atencao
  imediata do operador (bloqueio humano) versus um motivo que so pausa a
  execucao ate a proxima janela agendada (limite operacional atingido)?
  O resumo deve deixar essa distincao clara em vez de tratar ambos como
  "pausado".

## Requirements

### Functional Requirements

- **FR-001**: O sistema MUST produzir, ao final de cada onda de execucao
  autonoma (tanto no modo de execucao de projeto completo quanto no modo
  de execucao de uma unica feature, incluindo os fluxos de primeira
  invocacao e de retomada), um resumo textual legivel por humanos
  descrevendo o que aconteceu nessa onda especifica.
- **FR-002**: O resumo MUST identificar a onda a que se refere e a etapa
  do pipeline em que a execucao se encontrava ao final dessa onda.
- **FR-003**: O resumo MUST indicar o motivo pelo qual a onda terminou
  (por exemplo: etapa concluida e avancando, limite operacional atingido,
  bloqueio humano pendente, ou execucao concluida), de forma que o
  operador consiga distinguir um termino normal de um termino que exige
  sua atencao. Quando `termination_reason` assumir um valor fora do
  conjunto conhecido acima (enum desconhecido), o sistema MUST exibir o
  valor cru como recebido, sem inventar rotulo equivalente.
- **FR-004**: O resumo MUST apresentar uma contagem de decisoes
  auditaveis registradas durante a onda.
- **FR-005**: O resumo MUST apresentar a contagem de bloqueios pendentes
  de resposta humana, quando existirem.
- **FR-006**: O resumo MUST apresentar indicadores de volume de trabalho
  realizado na onda (ao menos: numero de chamadas de ferramenta e duracao
  decorrida da onda). A fonte desses indicadores MUST ser os campos ja
  registrados por onda pelo mecanismo existente de metricas por onda —
  nenhuma instrumentacao de captura nova e introduzida por esta feature.
- **FR-007**: O resumo SHOULD apresentar, quando a informacao estiver
  disponivel no ambiente da execucao, indicadores de custo/consumo
  medido (ex.: tokens) associados a onda. A fonte desse indicador, quando
  disponivel, MUST ser exclusivamente o mecanismo OTel/`wave_model_usage`
  ja existente — nenhum mecanismo de medicao de custo separado ou novo e
  introduzido por esta feature.
- **FR-008**: O resumo MUST apresentar, quando a execucao envolveu
  execucao de tarefas de um backlog, a contagem de tarefas concluidas com
  sucesso e a contagem de tarefas que falharam durante a onda.
- **FR-009**: O resumo MUST apresentar a proxima instrucao planejada para
  a execucao (o que sera feito na proxima onda ou ao ser retomada).
- **FR-010**: Qualquer indicador do resumo cuja fonte de medicao nao
  esteja disponivel no ambiente da execucao MUST ser apresentado com uma
  indicacao explicita e textualmente distinguivel de "nao medido" — o
  sistema MUST NOT apresentar um valor numerico (incluindo zero) para uma
  metrica que nao pode ser efetivamente medida.
- **FR-011**: A composicao do resumo MUST ser best-effort: qualquer falha
  na composicao (dado ausente, formato inesperado, ferramenta de medicao
  indisponivel) MUST NOT impedir nem atrasar a continuidade da execucao
  autonoma (reconciliacao de estado da onda e, quando aplicavel, o
  agendamento da proxima onda) — a falha resulta apenas em um aviso
  visivel ao operador de que o resumo nao pode ser composto.
- **FR-012**: O resumo MUST NOT incluir trechos de texto livre cru
  proveniente de conteudo de decisoes ou bloqueios da onda — apenas
  contagens e metadados estruturados (ex.: identificadores, contagens,
  status) sao apresentados. Caso uma futura extensao do resumo venha a
  incluir texto livre de decisoes/bloqueios, esse texto MUST passar pelo
  mesmo mecanismo de filtragem de conteudo sensivel ja usado no projeto
  (`secrets-filter.sh scrub` — o mesmo aplicado em `enforcement-log.jsonl`
  e no `recall`/knowledge.db) antes de ser apresentado ao operador; nenhum
  filtro novo e dedicado e introduzido por esta feature.
- **FR-013**: O resumo MUST ser entregue ao operador como parte da mesma
  mensagem final que o comando pai ja produz ao retomar o controle apos
  uma onda — sem exigir uma acao adicional do operador para visualiza-lo.
- **FR-014**: O comportamento de composicao do resumo (fontes
  consultadas, regra de "nao medido", filtragem de conteudo sensivel)
  MUST ser identico entre o modo de execucao de um projeto completo e o
  modo de execucao de uma unica feature.

### Key Entities

- **Resumo de Onda**: Representa o relato objetivo de uma unica onda de
  execucao autonoma apos seu fechamento. Atributos-chave: identificador
  da onda, etapa do pipeline ao final da onda, motivo de termino,
  contagem de decisoes auditaveis, contagem de bloqueios pendentes,
  indicadores de volume de trabalho (chamadas de ferramenta, duracao),
  indicador de custo/consumo (quando medido), contagem de tarefas
  concluidas/falhas (quando aplicavel), proxima instrucao planejada. A
  composicao deste resumo MUST viver em um helper POSIX dedicado e
  testavel (`agente-00c-runtime/scripts`), reusado identicamente pelos
  dois comandos pai (`agente-00c` e `feature-00c`) — nao replicado como
  logica/prosa inline em cada comando (satisfaz FR-014).

## Success Criteria

### Measurable Outcomes

- **SC-001**: Apos o fechamento de qualquer onda de uma execucao
  autonoma, 100% das mensagens finais entregues ao operador contêm um
  resumo da onda que acabou de fechar (ou um aviso explicito de que o
  resumo nao pôde ser composto).
- **SC-002**: Em nenhuma execucao observada um indicador de custo/consumo
  nao disponivel no ambiente e apresentado ao operador como um valor
  numerico (incluindo zero) — sempre como "nao medido" ou equivalente
  explicito.
- **SC-003**: Uma falha na composicao do resumo nunca resulta em atraso
  ou interrupcao da execucao autonoma — a onda seguinte (ou o
  agendamento da retomada) prossegue normalmente em 100% dos casos
  observados.
- **SC-004**: Um operador consegue identificar, apenas lendo a mensagem
  final da onda (sem abrir nenhum outro arquivo ou rodar nenhum outro
  comando), se ha algo pendente que exige sua resposta.
- **SC-005**: A composicao do resumo (helper `wave-summary.sh emit`) leva
  menos de 2 segundos por invocacao, medido do inicio da materializacao
  do estado ate a emissao do resumo formatado, em 100% das invocacoes
  observadas.

## Delta Requirements

**Skip**: Feature inteiramente nova; nenhuma capacidade ativa hoje documentada em `docs/specs/current/` cobre resumo de fechamento de onda para o operador — agente-00c-feature-orchestrator, 2026-09-22
