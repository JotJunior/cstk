# Feature Specification: Convergência obrigatória no pipeline SDD

**Feature**: `pipeline-converge`
**Created**: 2026-08-21
**Status**: Draft

## Clarifications

### Session 2026-08-21

- Q: Como registrar o aceite explícito de risco ao pular a correção de
  divergências apontadas pela convergência? → A: Como decisão auditável no
  histórico de execução (não apenas um campo flag simples).
- Q: O escopo da exigência de convergência obrigatória entre `execute-task`
  e `review-task` se aplica a quais modos de execução? → A: A ambos os
  orquestradores autônomos (`agente-00c` e `feature-00c`) e também à
  execução manual pelo operador.
- Q: O histórico de execução precisa distinguir uma convergência disparada
  como gate obrigatório de uma convergência invocada avulsamente pelo
  operador? → A: Sim — o registro da invocação carrega a proveniência (gate
  obrigatório vs. avulsa), no mesmo padrão usado por `record-skill --kind
  gate`.
- Q: Quando a convergência não está limpa, a etapa de revisão de tarefas
  deve bloquear (hard gate) ou apenas avisar (soft gate)? → A: Soft gate —
  a revisão de tarefas reporta as divergências como finding e exige uma
  decisão auditável de aceite de risco para prosseguir; nunca bloqueia a
  execução por si só.

## User Scenarios & Testing

### User Story 1 - Operador manual é guiado à convergência antes de revisar tarefas (Priority: P1)

Um operador que conduz o pipeline SDD manualmente (sem orquestrador autônomo),
ao concluir a última tarefa pendente do backlog de uma feature, é orientado a
rodar a reconciliação spec-vs-código antes de seguir para a revisão de
tarefas — hoje essa orientação só existe para execuções autônomas.

**Why this priority**: é o núcleo do pedido — "emancipar" a convergência
significa deixar de ser um comportamento exclusivo do modo autônomo e passar
a fazer parte do caminho que qualquer operador percorre.

**Independent Test**: concluir manualmente (via skills, sem orquestrador)
todas as tarefas do backlog de uma feature e verificar que a orientação de
próximos passos aponta para a convergência antes da revisão de tarefas.

**Acceptance Scenarios**:

1. **Given** um backlog de tarefas totalmente concluído, **When** o operador
   consulta os próximos passos sugeridos ao final da execução de tarefas,
   **Then** a convergência aparece como etapa recomendada antes da revisão
   de tarefas.
2. **Given** um backlog de tarefas totalmente concluído, **When** o operador
   consulta o relatório de status do backlog, **Then** o relatório indica se
   a convergência mais recente já rodou e se apontou pendências.

---

### User Story 2 - Convergência reconhecida como etapa oficial da pipeline SDD (Priority: P1)

A sequência oficial da pipeline SDD (hoje descrita como `specify → clarify →
plan → checklist → create-tasks → execute-task → review-task`) passa a
incluir a convergência como etapa própria, nomeada e ordenada, entre
`execute-task` e `review-task` — em vez de aparecer apenas como capacidade
complementar "usável a qualquer momento" ou como comportamento embutido só
na prosa dos orquestradores autônomos.

**Why this priority**: sem isso a convergência continua sendo, na prática,
um recurso invisível para quem não lê a fundo o comportamento interno dos
orquestradores — a formalização é o que sustenta a garantia da User Story 1
de forma consistente em toda execução (manual ou autônoma).

**Independent Test**: consultar a lista oficial de etapas da pipeline SDD em
qualquer ponto onde ela é documentada ou usada para determinar a próxima
etapa, e confirmar que a convergência aparece entre `execute-task` e
`review-task`.

**Acceptance Scenarios**:

1. **Given** a lista oficial de etapas da pipeline SDD, **When** consultada,
   **Then** contém a convergência posicionada entre `execute-task` e
   `review-task`.
2. **Given** uma execução autônoma que acabou de concluir `execute-task`,
   **When** o sistema determina a próxima etapa, **Then** a próxima etapa
   resolvida é a convergência, não diretamente `review-task`.

---

### User Story 3 - Loop de convergência incremental até a feature convergir (Priority: P2)

Quando a convergência encontra divergências acionáveis entre o que foi
documentado e o que o código realmente faz, o sistema conduz o operador de
volta à execução de tarefas (na fase residual apendada) antes de liberar a
revisão de tarefas — repetindo o ciclo até não haver mais divergências
acionáveis, ou até o operador registrar explicitamente que aceita o risco
de prosseguir sem corrigir.

**Why this priority**: fecha o ciclo — sem isso a convergência vira uma
etapa "obrigatória" apenas de nome, que pode ser rodada e ignorada sem
consequência.

**Independent Test**: introduzir de propósito uma divergência entre código e
spec numa feature com backlog concluído, rodar o ciclo até o fim, e
confirmar que a revisão de tarefas só passa a ser o próximo passo
recomendado depois que a fase residual é executada e uma nova convergência
não aponta mais divergências acionáveis.

**Acceptance Scenarios**:

1. **Given** divergências acionáveis apontadas pela convergência, **When** o
   operador consulta os próximos passos, **Then** é orientado a executar a
   fase residual apendada antes da revisão de tarefas.
2. **Given** uma convergência que não aponta divergências acionáveis,
   **When** o operador consulta os próximos passos, **Then** a revisão de
   tarefas é o próximo passo recomendado.
3. **Given** divergências acionáveis que o operador decide não corrigir,
   **When** ele registra explicitamente, como decisão auditável no
   histórico de execução, a decisão de aceitar o risco, **Then** o
   pipeline segue liberado para a revisão de tarefas sem exigir nova
   convergência.

---

### User Story 4 - Execuções autônomas tratam convergência como etapa regular do histórico (Priority: P3)

Nas execuções autônomas (`agente-00c`/`feature-00c`), a convergência deixa
de ser reportada como um caso à parte da máquina de etapas e passa a
aparecer no histórico de execução como qualquer outra etapa nomeada
(`specify`, `plan`, ...), com o mesmo nível de rastreabilidade.

**Why this priority**: melhora a auditabilidade e a consistência de
relatórios, mas o valor para o usuário final já está coberto pelas stories
P1/P2 — esta é uma consequência de bastidor da formalização.

**Independent Test**: revisar o histórico de etapas de uma execução autônoma
concluída e confirmar que a convergência aparece como etapa nomeada, sem
marcação especial que a distinga das demais.

**Acceptance Scenarios**:

1. **Given** uma execução autônoma concluída que passou por convergência,
   **When** o histórico de etapas executadas é consultado, **Then** a
   convergência aparece na mesma estrutura das demais etapas (nome, ordem,
   evidências associadas).

---

### Edge Cases

- O que acontece quando a feature não declara nenhum caminho de código
  associado (feature puramente documental)? A convergência deve concluir
  sem achados acionáveis e sem bloquear a progressão para a revisão de
  tarefas.
- O que acontece quando uma feature nunca passou por criação/execução de
  tarefas (o operador foi direto de `plan` para implementação fora do
  pipeline)? A exigência de convergência não se aplica — não há tarefas nem
  artefato de backlog para reconciliar.
- Como o sistema trata a reabertura de uma feature já concluída (novo
  round de trabalho sobre uma feature arquivada)? O novo round também
  precisa passar por uma convergência sem divergências acionáveis
  pendentes antes de ser considerado encerrado — a exigência não é
  exclusiva do primeiro round.
- O que acontece se o operador roda a convergência avulsamente, fora da
  fronteira entre execução de tarefas e revisão de tarefas? Continua
  permitido e útil a qualquer momento — a obrigatoriedade se aplica apenas
  ao ponto de transição execute-task → review-task, não restringe uso
  avulso.

## Requirements

### Functional Requirements

- **FR-001**: Sistema MUST reconhecer a convergência como etapa nomeada e
  ordenada da pipeline SDD, posicionada entre `execute-task` e
  `review-task`, em qualquer mecanismo ou documentação que determine ou
  descreva a sequência oficial de etapas.
- **FR-002**: Sistema MUST, ao esgotar o backlog de tarefas de uma feature
  (todas as tarefas concluídas), orientar o operador — em execução
  autônoma (`agente-00c` e `feature-00c`) ou manual — a rodar a
  convergência antes de prosseguir para a revisão de tarefas.
- **FR-003**: Quando a convergência apontar divergências acionáveis entre o
  documentado e o código atual, Sistema MUST apender uma fase de tarefas
  residual e reconduzir o fluxo à execução de tarefas antes de permitir
  nova tentativa de convergência.
- **FR-004**: Sistema MUST só apresentar a revisão de tarefas como próximo
  passo recomendado quando a convergência mais recente não apontar
  divergências acionáveis pendentes, ou quando o operador tiver registrado
  explicitamente, como decisão auditável no histórico de execução, a
  decisão de aceitar o risco de prosseguir sem corrigi-las. Esta exigência
  é soft gate: a etapa de revisão de tarefas reporta as divergências
  pendentes como finding e exige essa decisão auditável para prosseguir,
  mas nunca bloqueia a execução por si só.
- **FR-005**: Sistema MUST manter, para features sem artefato de backlog de
  tarefas (fluxo que nunca passou por criação/execução de tarefas), o
  comportamento atual sem exigir convergência artificialmente.
- **FR-006**: Sistema MUST tratar a convergência, em execuções autônomas,
  como etapa regular do histórico de execução — com o mesmo nível de
  rastreabilidade/auditoria das demais etapas — em vez de um caso especial
  fora da máquina de etapas.
- **FR-007**: Sistema MUST aplicar a exigência de convergência também à
  reabertura de uma feature já concluída (novo round de trabalho), antes de
  esse round poder ser considerado encerrado.
- **FR-008**: Sistema MUST continuar permitindo a invocação avulsa da
  convergência a qualquer momento, independente da fronteira execute-task →
  review-task.
- **FR-009**: Sistema MUST documentar a convergência, na documentação
  voltada ao usuário do toolkit, como etapa da sequência oficial do
  pipeline SDD — não mais apenas como capacidade complementar "usável a
  qualquer momento".
- **FR-010**: Sistema MUST registrar, no histórico de execução de cada
  invocação da convergência, a proveniência da invocação — etapa
  obrigatória do gate `execute-task → review-task` ou invocação avulsa
  pelo operador — permitindo distinguir os dois casos na auditoria.

> Decisoes de infraestrutura: N/A (feature normativa/de fluxo de pipeline;
> nao introduz scheduling, rotacao de chaves, refresh de token externo,
> mutex multi-pod, backup/restore ou idempotencia de request novos).

## Success Criteria

### Measurable Outcomes

- **SC-001**: Um operador que conclui todas as tarefas de uma feature
  identifica, numa única leitura da orientação de próximos passos
  apresentada, que o próximo passo é a convergência — não a revisão de
  tarefas.
- **SC-002**: 100% das execuções autônomas concluídas registram uma
  convergência final sem divergências acionáveis pendentes (ou uma decisão
  explícita de aceite de risco) antes de encerrar a feature.
- **SC-003**: 100% das reaberturas de feature só são consideradas encerradas
  após uma convergência sem divergências acionáveis pendentes (ou aceite de
  risco explícito) no round reaberto.
- **SC-004**: A lista documentada das etapas do pipeline SDD é idêntica —
  mesma ordem, mesmos nomes — em todos os pontos do toolkit onde é
  referenciada para o usuário.

## Delta Requirements

**Skip**: nenhum capability doc em `docs/specs/current/` cobre hoje a
máquina de etapas do pipeline SDD ou o comportamento do gate de
convergência — o comportamento existente vive apenas na prosa dos agentes
orquestradores (`agente-00c-orchestrator.md` /
`agente-00c-feature-orchestrator.md`), fora do corpus canônico de
capabilities ativas. Esta feature formaliza e estende esse comportamento
como capability nova, sem alvo de delta identificável. — feature-00c
orchestrator, 2026-08-21
