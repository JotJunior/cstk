# Feature Specification: Escopar backups/ na rotacao de round

**Feature**: `round-scoped-backups`
**Created**: 2026-08-21
**Status**: Draft

## User Scenarios & Testing

### User Story 1 - Preservar snapshots de onda de rounds anteriores (Priority: P1)

Um operador reabre uma feature ja concluida (`--reopen`) para um segundo
incremento de trabalho. Ao final do primeiro round, o sistema ja tinha
gravado varios snapshots de onda (auditoria por onda) durante a execucao.
Quando a nova execucao comeca, ela reinicia a numeracao de onda a partir de
1. O operador espera poder consultar, depois, os snapshots de onda tanto do
round mais recente quanto de todos os rounds anteriores, sem que um
sobrescreva o outro.

**Why this priority**: E o proprio defeito relatado na issue #150 — hoje os
snapshots do round novo sobrescrevem silenciosamente os do round anterior,
destruindo trilha de auditoria (ondas 1-11 de um round real foram perdidas).
Sem isso corrigido, cada reabertura degrada a auditabilidade da execucao
anterior.

**Independent Test**: Reabrir uma feature que ja tem pelo menos um round
rotacionado com snapshots de onda gravados; fechar pelo menos uma onda na
execucao nova; verificar que os snapshots do round anterior continuam
presentes e distintos dos da execucao corrente.

**Acceptance Scenarios**:

1. **Given** uma execucao terminal com N snapshots de onda gravados,
   **When** a execucao e rotacionada para um round preservado,
   **Then** os N snapshots aparecem dentro do round preservado, junto do
   estado transacional daquele round.
2. **Given** um round ja rotacionado contendo snapshots de onda,
   **When** uma nova execucao (pos-reabertura) fecha novas ondas
   reiniciando a numeracao a partir de 1,
   **Then** os snapshots do round anterior permanecem inalterados e
   acessiveis, sem colisao de nome com os snapshots da execucao corrente.

---

### User Story 2 - Purge de backups nao afeta rounds ja preservados (Priority: P2)

Um operador aborta uma execucao ativa usando a opcao de descartar os
snapshots de onda acumulados (situacao em que eles nao tem mais valor,
por exemplo apos um erro de configuracao logo no inicio). A feature ja
foi reaberta antes, entao ja existe pelo menos um round preservado com seus
proprios snapshots.

**Why this priority**: Sem esta garantia explicita, a correcao da User
Story 1 criaria um risco novo: um purge mal-escopado poderia apagar
auditoria de rounds que ja estavam seguros, transformando uma correcao de
perda de dados em uma fonte de perda de dados mais ampla.

**Independent Test**: Com um round ja preservado contendo snapshots,
abortar a execucao corrente pedindo para descartar os snapshots
acumulados; verificar que so os snapshots da execucao corrente (ainda nao
rotacionada) desaparecem e os do round preservado continuam intactos.

**Acceptance Scenarios**:

1. **Given** um round preservado com snapshots de onda e uma execucao
   corrente ativa com seus proprios snapshots,
   **When** o operador aborta a execucao corrente pedindo o descarte dos
   snapshots acumulados,
   **Then** somente os snapshots da execucao corrente sao removidos; os
   snapshots do round preservado permanecem presentes.

---

### User Story 3 - Rotacao sem nenhum snapshot de onda ainda continua funcionando (Priority: P3)

Um operador conclui e rotaciona uma execucao que nunca chegou a fechar
nenhuma onda (por exemplo, abortada logo no inicio, antes de qualquer
snapshot ser gravado).

**Why this priority**: Garante que a correcao nao introduz uma
pre-condicao nova e obrigatoria (presenca de snapshots) onde antes nao
havia — evita quebrar o caminho ja existente de execucoes curtas ou
abortadas cedo.

**Independent Test**: Rotacionar uma execucao terminal cujo diretorio de
snapshots de onda esta ausente ou vazio; verificar que a rotacao conclui
com sucesso, sem erro por causa da ausencia.

**Acceptance Scenarios**:

1. **Given** uma execucao terminal sem nenhum snapshot de onda gravado,
   **When** a execucao e rotacionada para um round preservado,
   **Then** a rotacao conclui com sucesso e o round preservado nao contem
   um diretorio de snapshots vazio ou ausente (comportamento equivalente
   ao de hoje para o estado transacional).

---

### Edge Cases

- O que acontece quando a rotacao e interrompida (falha de processo) no
  meio do deslocamento dos snapshots de onda, com alguns arquivos ja
  movidos e outros nao? A recuperacao precisa devolver o conjunto inteiro
  (estado transacional + snapshots) a um estado consistente — todo
  movido ou nenhum movido — com uma unica tentativa de recuperacao,
  igual ao que ja e garantido hoje so para o estado transacional.
- O que acontece com rounds que ja foram rotacionados **antes** desta
  correcao existir, e que portanto nao tem snapshots de onda dentro de
  si (o caso real relatado na issue #150, com ondas 1-11 ja perdidas)?
  [NEEDS CLARIFICATION: os rounds ja rotacionados sem snapshots (perda
  historica pre-existente) devem ganhar algum mecanismo de backfill/
  reparo, ou o gap fica documentado como perda irrecuperavel e fora de
  escopo desta correcao?]
- O que acontece se o operador pedir purge dos snapshots acumulados numa
  execucao que ainda nao foi rotacionada nenhuma vez (sem nenhum round
  preservado ainda)? Deve continuar removendo apenas os snapshots da
  execucao corrente, sem erro por ausencia de rounds.

## Requirements

### Functional Requirements

- **FR-001**: O sistema MUST mover o diretorio inteiro de snapshots de
  onda (hoje `backups/`) para dentro do round preservado, na MESMA
  operacao de rotacao que move o estado transacional (state.json/
  state.db) — nunca como uma operacao separada, para preservar
  atomicidade.
- **FR-002**: O sistema MUST preservar os snapshots de onda de todos os
  rounds anteriores sem sobrescrita, mesmo quando uma execucao nova
  reinicia a numeracao de onda a partir de 1.
- **FR-003**: O contrato que descreve o conjunto de itens movidos pela
  rotacao MUST ser atualizado para refletir que o diretorio de snapshots
  de onda passa a ser movido junto do estado transacional (deixando de
  fazer parte do conjunto "nunca movido").
- **FR-004**: O mecanismo de recuperacao de rotacao interrompida (roll-
  forward / roll-back) MUST suportar mover um diretorio inteiro de
  snapshots de onda, alem dos arquivos individuais ja suportados hoje,
  preservando as mesmas garantias de atomicidade e de resolucao por um
  unico comando que ja existem para o estado transacional.
- **FR-005**: A operacao de descarte (purge) de snapshots de onda
  acionada no abort de uma execucao MUST continuar restrita aos
  snapshots da execucao CORRENTE (ainda nao rotacionada); MUST NEVER
  remover ou alterar snapshots ja movidos para dentro de rounds
  preservados.
- **FR-006**: Quando o diretorio de snapshots de onda estiver ausente ou
  vazio no momento da rotacao (execucao que nunca fechou nenhuma onda), o
  sistema MUST concluir a rotacao normalmente, sem tratar a ausencia como
  erro.
- **FR-007**: Os pontos do sistema que gravam um novo snapshot de onda
  (durante a execucao normal de uma feature) MUST continuar gravando na
  mesma localizacao relativa de hoje (diretorio de snapshots na raiz do
  state-dir da execucao corrente); esta correcao muda apenas o que
  acontece com esses snapshots NO MOMENTO da rotacao, nao onde/como sao
  escritos durante a execucao.
- **FR-008**: A rotacao MUST permanecer atomica mesmo quando o diretorio
  de snapshots contem multiplos arquivos — uma falha no meio do
  deslocamento nao pode deixar snapshots divididos entre a raiz do
  state-dir e o round preservado sem que a recuperacao (FR-004) consiga
  resolver isso.

> Decisoes de infraestrutura: N/A — esta feature ajusta uma primitiva de
> rotacao/backup ja existente (sem scheduler, sessao persistente, refresh
> de token externo ou rotacao de chave de criptografia novos).

## Success Criteria

### Measurable Outcomes

- **SC-001**: Apos reabrir uma feature 3 vezes seguidas, os snapshots de
  onda de todos os rounds anteriores continuam acessiveis, com 0%
  de colisao ou sobrescrita de nome entre rounds diferentes.
- **SC-002**: Uma rotacao interrompida no meio do deslocamento dos
  snapshots de onda e resolvida por uma unica tentativa de recuperacao,
  sem intervencao manual, deixando o conjunto (estado + snapshots)
  totalmente movido ou totalmente intacto.
- **SC-003**: Um descarte de snapshots acionado apos qualquer numero de
  reaberturas afeta somente os snapshots da execucao corrente; 100% dos
  snapshots de rounds ja preservados permanecem intactos.
- **SC-004**: Rotacionar uma execucao que nunca fechou nenhuma onda
  conclui com sucesso, sem erro relacionado a ausencia de snapshots.

## Delta Requirements

**Skip**: a capacidade de rotacao de round (`state-rounds.sh`) ainda vive
inteiramente dentro da spec ativa `feature-reopen` (nao arquivada em
`docs/specs/current/`) — nao existe corpus canonico a emendar via Delta
Requirements. O contrato afetado
(`docs/specs/feature-reopen/contracts/state-rounds.md`) e atualizado
diretamente como parte da implementacao desta feature. — agente-00c-feature-orchestrator, 2026-08-21
