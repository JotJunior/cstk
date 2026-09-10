# Feature Specification: Reabertura incremental de feature concluida

**Feature**: `feature-reopen`
**Created**: 2026-08-11
**Status**: Draft

## Contexto

Hoje o toolkit sabe abrir uma feature e sabe fecha-la, mas nao sabe
reabri-la. Uma feature concluida e um beco sem saida: o estado terminal
fica no disco para sempre e qualquer nova invocacao com o mesmo
`short-name` aborta.

Evidencia observada no proprio repo do cstk (2026-08-11): as 26 execucoes
sob `.claude/feature-00c-state/` estao todas com status `concluida` —
21 persistidas em `state.json`, 5 em `state.db`. Para qualquer uma delas,
uma re-invocacao percorre todo o pre-flight (briefing, constitution,
lock, diagnostico de hooks) e so entao morre no init, em
`plugins/cstk/skills/agente-00c-runtime/scripts/state-rw.sh` linha 417
(`init: state.json ja existe em <dir>. Use /agente-00c-abort ou
/agente-00c-resume.`) ou linha 412, no caso do backend SQLite.

Duas consequencias praticas:

1. **Falha tardia e com instrucao errada.** A mensagem cita comandos do
   escopo de projeto (`/agente-00c-*`), nao os do escopo de feature, e
   nenhum dos dois resolve — `/feature-00c-resume` sequer rejeita status
   terminal, mas tambem nao tem semantica de escopo novo: retomaria a
   mesma pipeline sem incrementar nada.
2. **Um caminho oferecido que nao existe.** O pre-flight de
   `plugins/cstk/commands/feature-00c.md` (secao 2, item 6 / FR-006)
   oferece ao operador *"(a) retomar a partir da spec existente (entra
   direto em clarify)"*. Essa opcao e inalcancavel: o init morre logo
   depois. E para feature ja arquivada ela nem chega a aparecer — a spec
   foi para `docs/specs/_archived/`, entao o item 6 nao dispara, mas o
   diretorio de estado continua no lugar. O caso mais comum e justamente
   o que perde o unico aviso amigavel.

O resultado e que incrementar uma feature fechada exige hoje edicao
manual de estado ou a criacao de uma feature paralela — que fragmenta a
spec e perde a identidade do que e, conceitualmente, a mesma capacidade.

### Restricoes de entrada (decisoes ja tomadas pelo operador)

Estas nao sao alternativas em aberto; sao entrada fixa desta spec:

- **Modelo de estado = rotacao em rounds.** O estado terminal e movido
  para um round numerado e preservado imutavel; a nova execucao comeca
  limpa, com ponteiro para o round anterior. Estado terminal nunca e
  mutado in-place.
- **Spec = delta na spec existente.** O incremento e expresso como
  `## Delta Requirements` na spec da propria feature, nao como spec
  paralela.
- **Triagem = advisory com bloqueio humano.** O sistema recomenda
  reabrir ou criar feature nova, com justificativa, e para esperando o
  operador. Nao decide sozinho.
- **Escopo = somente `/feature-00c`.** A pipeline de projeto
  (`/agente-00c`) tem semantica diferente e fica de fora.

## Clarifications

### Session 2026-08-11

- Q: Qual mecanismo de lock deve cobrir a rotacao (mover round anterior + iniciar execucao nova)? → A: Reusar o lock existente por short-name (mesmo do ciclo normal de execucao), mantido adquirido do inicio ao fim da rotacao antes de liberar.
- Q: Onde o ponteiro para o round anterior (`.previous_round`) deve ser persistido? → A: Campo novo dentro do estado transacional da execucao nova (state.json/state.db), coerente com a paridade entre backends.
- Q: Qual o formato de numeracao dos diretorios de round (`rounds/r<N>/`)? → A: Inteiro sequencial com zero-padding de largura fixa (ex.: `r01`, `r02`, ...), garantindo ordenacao lexicografica correta em scripts POSIX sem parsing numerico.
- Q: O que exatamente e movido para o round preservado alem do estado transacional? → A: Somente o estado transacional (state.json ou state.db + arquivos auxiliares do backend); demais artefatos do diretorio de estado (ex.: `enforcement-log.jsonl`) permanecem no lugar e continuam sendo escritos pela execucao nova.
- Q: Como o sistema detecta e identifica "trabalho pendente nao integrado" do round anterior antes da confirmacao? → A: Verificacao observavel via git (branch associada ainda nao mesclada na branch default) e, quando disponivel, status de proposta de merge aberta — cada afirmacao cita a fonte checada, nunca suposicao.

## User Scenarios & Testing

### User Story 1 - Reabrir uma feature concluida para um incremento (Priority: P1)

O operador percebe que uma feature ja entregue precisa de um acrescimo:
um caso que ficou de fora, uma regra que mudou, um comportamento que a
realidade pediu depois. Ele invoca a pipeline de feature informando a
descricao do incremento e o `short-name` da feature ja concluida. O
sistema preserva a execucao anterior como historico, abre uma execucao
nova sobre a mesma feature e segue a pipeline normalmente, sem que o
operador precise mexer em nenhum arquivo de estado a mao.

**Why this priority**: e a capacidade inexistente que motiva a feature.
Sem ela nada mais importa — as outras duas stories qualificam e auditam
um caminho que hoje simplesmente aborta.

**Independent Test**: pegar qualquer feature com execucao terminal,
reabrir com uma descricao de incremento e verificar que a pipeline chega
a primeira onda de trabalho, que a execucao anterior continua legivel
integra, e que a spec da feature recebeu o incremento como delta.

**Acceptance Scenarios**:

1. **Given** uma feature com execucao concluida e estado persistido em
   arquivo unico, **When** o operador reabre informando a descricao do
   incremento, **Then** a execucao anterior e preservada intacta como
   round numerado e uma execucao nova e iniciada apontando para ela.
2. **Given** uma feature com execucao concluida e estado persistido em
   banco, **When** o operador reabre, **Then** o comportamento observavel
   e identico ao do arquivo unico, inclusive quanto aos arquivos
   auxiliares que o banco mantem ao lado do principal.
3. **Given** uma feature cuja spec foi arquivada no fechamento anterior,
   **When** o operador reabre, **Then** a spec volta ao caminho ativo
   para receber o incremento e o diretorio de arquivo do round anterior
   permanece onde esta.
4. **Given** a especificacao existente da feature no caminho ativo,
   **When** o incremento e incorporado, **Then** ele aparece como secao
   de requisitos delta dentro dessa mesma especificacao e nenhuma
   especificacao paralela e gerada para a feature.
5. **Given** uma feature ja reaberta uma vez, **When** o operador reabre
   de novo, **Then** um segundo round e criado sem sobrescrever o
   primeiro.
6. **Given** um `short-name` que nunca teve execucao, **When** o operador
   tenta reabrir, **Then** a invocacao e recusada com mensagem que aponta
   a forma normal de abrir a feature, sem criar nada no disco.
7. **Given** uma feature com execucao ainda em andamento ou pausada
   aguardando resposta humana, **When** o operador tenta reabrir,
   **Then** a invocacao e recusada apontando os caminhos de retomada ou
   aborto, sem tocar o estado vivo.

---

### User Story 2 - Ser aconselhado antes de contaminar uma spec fechada (Priority: P2)

Nem todo pedido que menciona uma feature existente e um incremento dela.
As vezes e uma capacidade nova que so parece proxima. Antes de mexer em
qualquer coisa, o operador quer um parecer: vale reabrir esta feature ou
vale abrir outra? O sistema compara o pedido com a spec existente, diz o
que achou e por que, e para — a palavra final e do operador.

**Why this priority**: reabrir errado e caro (contamina a spec de uma
feature fechada e mistura escopos no historico), enquanto perguntar custa
segundos. Mas a story so faz sentido depois que reabrir e possivel, entao
vem depois da P1.

**Independent Test**: reabrir com uma descricao claramente aderente a
spec existente e com outra claramente estranha a ela, e verificar que o
parecer distingue os dois casos com justificativa citando o que foi
comparado, e que em ambos a execucao aguarda confirmacao.

**Acceptance Scenarios**:

1. **Given** uma descricao de incremento aderente ao objetivo da spec
   existente, **When** o operador reabre, **Then** o sistema recomenda
   reabrir, apresenta a justificativa apontando os pontos de aderencia e
   aguarda confirmacao explicita antes de qualquer escrita em disco.
2. **Given** uma descricao que introduz atores ou objetivo estranhos a
   spec existente, **When** o operador reabre, **Then** o sistema
   recomenda abrir feature nova e instrui como faze-lo, sem criar a
   feature nova por conta propria.
3. **Given** um parecer que recomenda feature nova, **When** o operador
   ainda assim confirma a reabertura, **Then** a reabertura prossegue e a
   divergencia entre o recomendado e o escolhido fica registrada.
4. **Given** qualquer parecer emitido, **When** a execucao nova e
   iniciada, **Then** o parecer e a escolha do operador constam como
   decisao auditavel dessa execucao.

---

### User Story 3 - Auditar a linhagem de uma feature reaberta (Priority: P3)

Meses depois, alguem pergunta por que a feature tem duas rodadas de
trabalho e o que mudou entre elas. O operador precisa conseguir ler a
historia completa — o que foi feito no round anterior, o que o incremento
acrescentou, e quando cada coisa aconteceu — sem garimpar arquivos soltos
nem confundir as duas rodadas em relatorios agregados.

**Why this priority**: valor de longo prazo, nao bloqueia o uso. Mas se
for deixado para depois, os relatorios passam a contar a mesma feature
duas vezes e a metrica fica errada silenciosamente.

**Independent Test**: apos uma reabertura, gerar os relatorios de status
e reconstruir o indice de conhecimento do zero, verificando que as duas
execucoes aparecem distintas, ligadas entre si, e que nenhuma contagem
duplica.

**Acceptance Scenarios**:

1. **Given** uma feature reaberta, **When** o operador consulta o relato
   de status da feature, **Then** as execucoes aparecem distinguiveis
   entre si e ligadas pela ordem dos rounds.
2. **Given** rounds anteriores preservados no disco, **When** o indice de
   conhecimento e reconstruido do zero, **Then** cada round e contado
   exatamente uma vez e nenhum round arquivado e tratado como execucao
   ativa.
3. **Given** o backlog de tarefas da feature, **When** o incremento gera
   trabalho novo, **Then** as tarefas novas sao acrescentadas preservando
   as tarefas ja concluidas do round anterior.

---

### Edge Cases

- Feature concluida cujo diretorio de spec ja foi arquivado — o caso mais
  comum no repo hoje: a spec nao esta no caminho ativo, mas o estado
  esta. O que o sistema restaura, e o que ele deixa onde esta?
- Feature cuja execucao anterior terminou **abortada** em vez de
  concluida: e um estado terminal legitimo e a reabertura vale, mas o
  parecer precisa dizer ao operador que o round anterior nao chegou ao
  fim.
- Reabertura interrompida no meio da rotacao (queda de sessao entre mover
  o estado antigo e inicializar o novo): o que o operador encontra ao
  voltar, e como ele sai desse limbo sem editar arquivo a mao?
- Reabertura enquanto outra sessao ja segura o mesmo `short-name`.
- Reabertura de uma feature cujo trabalho do round anterior ainda nao foi
  integrado — ha uma branch ou proposta de merge aberta esperando.
- Spec ativa editada a mao entre o fechamento e a reabertura: o
  incremento se aplica sobre o que esta no disco, nao sobre o que foi
  arquivado.
- Descricao de incremento vazia, longa demais, ou apontando um
  `short-name` que existe como diretorio de spec mas nunca teve execucao.
- Muitas reaberturas sucessivas da mesma feature ao longo do tempo.

## Requirements

### Functional Requirements

- **FR-001**: A pipeline de feature MUST aceitar um modo de reabertura
  que recebe a descricao de um incremento e o identificador curto de uma
  feature ja existente, iniciando trabalho novo sobre ela sem exigir
  edicao manual de estado.
- **FR-002**: O modo de reabertura MUST recusar, sem escrever nada no
  disco, um identificador que nao possua execucao anterior registrada,
  instruindo o operador a usar a abertura normal de feature.
- **FR-003**: O modo de reabertura MUST recusar uma feature cuja execucao
  anterior nao esteja em estado terminal, instruindo o operador aos
  caminhos de retomada ou aborto, e MUST NOT alterar o estado dessa
  execucao viva.
- **FR-004**: Antes de qualquer escrita em disco, o sistema MUST comparar
  a descricao do incremento com a especificacao da feature-alvo e
  apresentar ao operador um parecer recomendando reabrir ou abrir feature
  nova, acompanhado da justificativa que cita os pontos comparados.
- **FR-005**: O sistema MUST aguardar confirmacao explicita do operador
  apos o parecer, MUST prosseguir com a escolha dele mesmo quando ela
  contraria a recomendacao, e MUST NOT criar uma feature nova por conta
  propria quando o parecer recomenda isso.
- **FR-006**: O parecer emitido, a escolha do operador e a eventual
  divergencia entre os dois MUST ser registrados como decisao auditavel
  da execucao nova.
- **FR-007**: O estado terminal da execucao anterior — o arquivo
  transacional (state.json ou state.db, com os auxiliares de backend
  citados em FR-010) — MUST ser preservado integro como round numerado e
  MUST NOT ser alterado em nenhum campo durante ou depois da reabertura.
  Demais artefatos do diretorio de estado que nao fazem parte do estado
  transacional (ex.: log de enforcement) MUST permanecer no lugar e
  continuar sendo escritos pela execucao nova, sem entrar na rotacao.
- **FR-008**: A execucao nova MUST comecar a partir de estado limpo e
  MUST registrar um ponteiro rastreavel para o round imediatamente
  anterior, persistido como campo no proprio estado transacional da
  execucao nova (nao em arquivo auxiliar separado).
- **FR-009**: A numeracao dos rounds MUST ser monotonica e derivada dos
  rounds ja existentes, de modo que reaberturas sucessivas nunca
  sobrescrevam historico anterior. A numeracao MUST ser expressa como
  inteiro sequencial com zero-padding de largura fixa (ex.: `r01`,
  `r02`, ...), garantindo ordenacao lexicografica correta sem depender
  de parsing numerico em scripts POSIX.
- **FR-010**: O comportamento observavel da reabertura MUST ser identico
  independentemente da forma de persistencia do estado, incluindo o
  tratamento dos arquivos auxiliares que a persistencia em banco mantem
  ao lado do arquivo principal.
- **FR-011**: A rotacao de estado MUST ser observavelmente tudo-ou-nada:
  ou o round foi preservado e a execucao nova iniciada, ou nada mudou —
  e uma interrupcao no meio MUST deixar o operador em um estado do qual
  ele sai por comando, nunca por edicao manual de arquivo.
- **FR-012**: A exclusao mutua por identificador de feature MUST cobrir
  toda a rotacao — reusando o mesmo lock por short-name ja usado pelo
  ciclo normal de execucao, mantido adquirido do inicio ao fim da
  rotacao antes de liberar — de modo que duas sessoes nao possam reabrir
  a mesma feature simultaneamente.
- **FR-013**: Quando a especificacao da feature-alvo estiver arquivada, o
  sistema MUST restaura-la para o caminho ativo antes de aplicar o
  incremento, MUST preservar o diretorio de arquivo do round anterior
  onde ele esta, e MUST informar ao operador que a restauracao ocorreu.
- **FR-014**: O incremento MUST ser expresso como secao de requisitos
  delta na especificacao existente da feature, e MUST NOT gerar uma
  especificacao paralela para a mesma feature.
- **FR-015**: O backlog de tarefas da feature MUST receber o trabalho
  novo por acrescimo, preservando as tarefas ja concluidas em rounds
  anteriores e sua marcacao de conclusao.
- **FR-016**: O caminho oferecido no pre-flight de "retomar a partir da
  especificacao existente" MUST levar a uma execucao de fato — nenhuma
  opcao apresentada ao operador pode terminar em aborto do proprio fluxo
  que a ofereceu.
- **FR-017**: A mensagem emitida ao encontrar estado pre-existente MUST
  citar os comandos do escopo de feature e MUST apontar o modo de
  reabertura como caminho aplicavel.
- **FR-018**: Rounds preservados MUST NOT ser interpretados como
  execucoes ativas por nenhum leitor de estado, e a reconstrucao do
  indice de conhecimento MUST contar cada round exatamente uma vez.
- **FR-019**: O modo de reabertura MUST se aplicar somente a pipeline de
  feature individual, MUST NOT alterar o comportamento da pipeline de
  projeto.
- **FR-020**: Quando a execucao anterior terminou abortada em vez de
  concluida, a reabertura MUST ser permitida e o parecer MUST declarar
  que o round anterior nao chegou ao fim.
- **FR-021**: Quando houver trabalho do round anterior ainda nao
  integrado, o sistema MUST avisar o operador antes da confirmacao,
  identificando o trabalho pendente, e MUST prosseguir com a reabertura
  se o operador confirmar — o aviso informa, nao bloqueia. A
  identificacao MUST se basear em verificacao observavel (branch
  associada ainda nao mesclada na branch default e, quando disponivel,
  status de proposta de merge aberta), citando a fonte checada — nunca
  uma afirmacao sem verificacao.
- **FR-022**: A execucao nova MUST herdar a politica de commit automatico
  registrada no round anterior, sem reapresentar a escolha ao operador; a
  ausencia de registro no round anterior MUST equivaler a politica
  desabilitada.

> Decisoes de infraestrutura: aplicavel apenas ao item de exclusao mutua
> (FR-012), ja coberto pelo mecanismo de lock por identificador de
> feature existente. Feature sem scheduling proprio, sem criptografia de
> dados persistentes e sem consumo de recurso externo com validade.

### Key Entities

- **Round**: uma rodada completa de trabalho sobre uma feature. Guarda o
  estado terminal daquela rodada de forma imutavel, sua posicao na
  ordem (primeiro, segundo, ...) e o vinculo com a rodada anterior.
- **Execucao corrente**: a rodada ativa, iniciada limpa a cada
  reabertura, portando o ponteiro para o round anterior.
- **Parecer de reabertura**: veredito (reabrir ou abrir nova),
  justificativa citando os pontos comparados entre o pedido e a spec
  existente, e a escolha final do operador.
- **Especificacao da feature**: documento unico e continuo da feature,
  que acumula os incrementos como requisitos delta ao longo dos rounds.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Reabrir uma feature ja concluida e chegar ao inicio do
  trabalho sem nenhuma edicao manual de arquivo de estado — hoje esse
  numero de passos manuais e infinito, porque o caminho nao existe.
- **SC-002**: Apos qualquer numero de reaberturas, 100% dos rounds
  anteriores permanecem byte a byte identicos ao que eram no momento em
  que foram preservados.
- **SC-003**: Apos uma reabertura seguida de reconstrucao completa do
  indice de conhecimento, o numero de execucoes contadas para a feature e
  exatamente o numero de rounds — zero duplicatas, zero rounds tratados
  como ativos.
- **SC-004**: A reabertura funciona para as 26 execucoes ja concluidas do
  repositorio de referencia, independentemente de como o estado de cada
  uma foi persistido.
- **SC-005**: O operador decide entre reabrir e abrir feature nova a
  partir do parecer apresentado, sem precisar abrir a especificacao
  existente para conferir.
- **SC-006**: Uma reabertura interrompida no meio e resolvida por comando
  em uma unica tentativa, sem edicao manual de arquivo.
- **SC-007**: Nenhuma opcao apresentada ao operador em todo o fluxo
  termina em aborto do proprio fluxo — a lacuna que existe hoje no
  pre-flight cai para zero.

## Delta Requirements

### Capability: spec-corpus

#### ADDED

- **FR-013**: Uma especificacao ja arquivada MUST poder retornar ao
  caminho ativo para receber um incremento, sem que o diretorio de
  arquivo do round anterior seja movido, alterado ou removido — o
  historico sob o arquivo permanece a trilha do que foi entregue naquela
  rodada, e a especificacao ativa passa a ser a rodada em curso.
