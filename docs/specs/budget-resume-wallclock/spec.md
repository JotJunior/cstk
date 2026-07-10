# Feature Specification: budget-resume-wallclock

**Feature**: `budget-resume-wallclock`
**Created**: 2026-07-09
**Status**: Draft

## Visao geral

O orquestrador `feature-00c` (e seu par `agente-00c`) protege cada onda de
trabalho autonomo com um orcamento de wallclock: se a onda corrente
consome tempo demais, a execucao encerra a onda e devolve controle ao
operador em vez de continuar indefinidamente. Essa protecao depende de um
timestamp de inicio de onda (`current_wave_start`) que so e definido no
inicio de uma onda e nunca e reaberto ate a proxima onda comecar.

Hoje, na retomada de uma execucao `feature-00c` pausada (`/feature-00c-resume`),
a checagem de orcamento roda **antes** de a nova onda ser iniciada. Como o
timestamp da onda anterior (ja encerrada) permanece gravado, a checagem
mede o tempo decorrido desde o fim daquela onda ate o momento da retomada
— um intervalo que inclui a espera do agendamento (schedule) entre ondas e
que nao tem relacao com trabalho ativo. Quando essa espera ultrapassa o
limite configurado, a retomada e barrada por um estouro de orcamento que
nunca aconteceu de fato: nenhuma onda estava em andamento consumindo esse
tempo.

Esta feature corrige a ordem das operacoes na retomada para que o
orcamento de wallclock seja medido apenas a partir do inicio real da onda
corrente, preservando integralmente a deteccao de estouro genuino —
quando uma onda realmente em andamento excede o tempo configurado, a
execucao deve continuar sendo interrompida como hoje.

> Decisoes de infraestrutura: **N/A** — a feature ajusta a ordem de duas
> operacoes ja existentes dentro do runtime de orquestracao (inicio de
> onda e checagem de orcamento); nao introduz scheduling novo, sessao
> persistente, chave criptografica, mutex multi-processo ou politica de
> refresh de token.

## User Scenarios & Testing

### User Story 1 - Retomada apos pausa nao e barrada por espera entre ondas (Priority: P1)

Como operador que retoma uma execucao `feature-00c` pausada (por
agendamento entre ondas ou apos responder um bloqueio humano), eu quero
que a retomada avalie o orcamento de tempo da onda que esta prestes a
comecar — nao o tempo que passou esperando a retomada acontecer — para
que a execucao nao seja interrompida por um estouro que nunca ocorreu.

**Why this priority**: e o defeito relatado. Sem essa correcao, qualquer
retomada que aconteca depois de o intervalo entre ondas (agendamento +
tempo humano de resposta a um bloqueio) ultrapassar o limite configurado e
barrada incondicionalmente, mesmo que nenhuma onda tenha de fato excedido
o tempo permitido — inutilizando a retomada em execucoes de longa duracao
ou com bloqueios respondidos fora do horario comercial.

**Independent Test**: retomar uma execucao cuja ultima onda ja esta
encerrada e cujo tempo decorrido desde o encerramento (nao desde o inicio
de uma onda aberta) ultrapassa o limite de orcamento configurado; a
retomada deve prosseguir normalmente para a proxima onda, sem relatar
estouro de orcamento.

**Acceptance Scenarios**:

1. **Given** uma execucao `feature-00c` com a ultima onda encerrada ha
   mais tempo que o limite de orcamento configurado, **When** o operador
   retoma a execucao, **Then** a retomada avanca para a proxima onda sem
   reportar estouro de orcamento de tempo.
2. **Given** uma execucao `feature-00c` recem-retomada e com a onda
   corrente ja iniciada, **When** essa onda em andamento excede o limite
   de orcamento configurado, **Then** a execucao encerra a onda e reporta
   o estouro normalmente, do mesmo jeito que reporta hoje.

---

### Edge Cases

- O que acontece quando a retomada ocorre imediatamente apos o
  encerramento da onda anterior (intervalo praticamente zero)? A nova onda
  deve iniciar e o orcamento deve ser avaliado a partir do novo inicio, sem
  diferenca de comportamento em relacao a uma retomada tardia.
- O que acontece na primeira onda de uma execucao nova (sem onda anterior
  encerrada)? Deve continuar funcionando como hoje — sem regressao.
- O que acontece se, durante a propria retomada, outro gatilho de
  encerramento (numero de tentativas, movimento circular, desvio de
  finalidade) tambem seria disparado pelo estado herdado da onda anterior?
  Esses gatilhos ficam fora do escopo desta feature — apenas o orcamento de
  tempo (wallclock) esta sob correcao; nenhum outro gatilho deve mudar de
  comportamento.

## Requirements

### Functional Requirements

- **FR-001**: Ao retomar uma execucao `feature-00c` pausada, o sistema
  MUST avaliar o orcamento de tempo da onda corrente somente apos o inicio
  dessa onda ser registrado — nunca antes.
- **FR-002**: O sistema MUST continuar interrompendo uma onda que, apos
  iniciada, excede o limite de orcamento de tempo configurado — o
  comportamento de deteccao de estouro genuino dentro de uma onda aberta
  NAO MUST ser enfraquecido ou removido por esta correcao.
- **FR-003**: A correcao MUST se aplicar exclusivamente ao fluxo de
  retomada do orquestrador de feature individual (`feature-00c`); o fluxo
  equivalente do orquestrador de projeto completo (`agente-00c`), que ja
  inicia a onda antes de avaliar o orcamento, NAO MUST ter seu
  comportamento alterado.
- **FR-004**: O sistema MUST permitir verificar, de forma automatizada,
  tanto o cenario corrigido (retomada apos onda encerrada ha muito tempo
  nao gera estouro falso) quanto o cenario preservado (onda aberta que
  excede o limite continua gerando estouro).

## Success Criteria

### Measurable Outcomes

- **SC-001**: Em 100% das retomadas de uma execucao `feature-00c` cuja
  ultima onda ja esta encerrada, nenhum estouro de orcamento de tempo e
  relatado antes do inicio da nova onda, independentemente de quanto
  tempo passou desde o encerramento da onda anterior.
- **SC-002**: Em 100% dos casos em que uma onda em andamento excede o
  limite de orcamento de tempo configurado, o sistema continua
  interrompendo essa onda e relatando o estouro, sem excecao.
- **SC-003**: A suite de testes automatizados do runtime de orquestracao
  cobre ambos os cenarios (retomada sem estouro falso; estouro legitimo
  dentro de onda aberta) e permanece 100% verde apos a correcao.
