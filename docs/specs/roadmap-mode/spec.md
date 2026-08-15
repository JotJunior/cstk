# Feature Specification: Modo roadmap do agente-00c (briefing + constitution + roadmap de features)

**Feature**: `roadmap-mode`
**Created**: 2026-08-14
**Status**: Draft

## Contexto

Hoje o `/agente-00c` trata o projeto-alvo inteiro como UMA feature: apos
briefing e constitution, a pipeline segue direto para specify e o
produto completo vira uma unica spec/plan/backlog. Para projetos com
mais de uma capacidade real, isso produz uma feature inicial gigante,
dificil de revisar e de entregar incrementalmente.

O fluxo que funciona na pratica (ja exercitado manualmente pelo autor do
toolkit): usar o agente-00c para compor o briefing e a constitution e
gerar um ROADMAP do projeto — a lista ordenada de features consideradas
necessarias — e entao o operador inicia cada feature individualmente via
`/feature-00c`, na ordem sugerida. O toolkit ja tem toda a infraestrutura
da segunda metade (feature-00c exige exatamente briefing + constitution
ratificados como pre-condicao); falta a primeira metade ser um modo
oficial de execucao em vez de um uso improvisado.

Esta feature introduz o **modo roadmap**: uma variante opt-in do
`/agente-00c` em que a pipeline executa briefing → constitution →
geracao do roadmap e ENCERRA como execucao concluida com sucesso — sem
specify, sem plan, sem backlog, sem execute-task do projeto inteiro.

Relacao com a feature `delivery-tier` (spec irma, mesmo ciclo): quando
ambas existirem, o tier de entrega declarado influencia o tamanho e o
escopo do roadmap sugerido (um produto `local` tende a gerar menos
features que um `cloud-public`). As duas features sao independentes —
nenhuma depende da outra para entregar valor.

## User Scenarios & Testing

### User Story 1 - Gerar o roadmap e encerrar (Priority: P1)

O operador inicia o `/agente-00c` em modo roadmap. A pipeline conduz o
briefing (entrevista de discovery), ratifica a constitution e entao gera
o roadmap do projeto: a lista de features consideradas necessarias, cada
uma com nome curto, descricao, ordem sugerida e dependencias. A execucao
encerra como concluida com sucesso — nenhum artefato de implementacao
(spec de feature, plano, backlog) e criado.

**Why this priority**: e o modo em si — sem ele nada muda. Sozinho ja
entrega o valor central: transformar a "feature inicial gigante" em um
portfolio planejado de features menores.

**Independent Test**: iniciar execucao em modo roadmap num projeto
limpo; ao final, existem briefing, constitution e roadmap; NAO existe
diretorio de spec de implementacao criado pela execucao; o estado da
execucao e terminal com sucesso (FR-001, FR-002, FR-004).

**Acceptance Scenarios**:

1. **Given** projeto-alvo limpo, **When** o operador inicia
   `/agente-00c` em modo roadmap e conclui briefing + constitution,
   **Then** a pipeline gera o artefato de roadmap e encerra a execucao
   como concluida, sem passar por specify/plan/create-tasks/execute-task
   (FR-001, FR-002, FR-004).
2. **Given** execucao em modo roadmap concluida, **When** o operador
   abre o relatorio final, **Then** o roadmap completo (features,
   ordem, dependencias) consta no relatorio (FR-004).
3. **Given** operador inicia `/agente-00c` e responde Enter (ou executa
   em modo nao-interativo) a pergunta do modo, **When** a pipeline
   executa, **Then** o comportamento e o atual (pipeline completa ate
   review-features) — o modo e opt-in com default no fluxo existente
   (FR-001).

---

### User Story 2 - Consumir o roadmap via feature-00c (Priority: P2)

Com o roadmap gerado, o operador inicia a primeira feature sugerida via
`/feature-00c`, aproveitando a descricao ja escrita no roadmap. Cada
entrada do roadmap carrega o suficiente (nome curto valido + descricao
acionavel) para iniciar a feature sem reescrever contexto.

**Why this priority**: fecha o ciclo do fluxo — o roadmap so vale se for
consumivel sem atrito pela pipeline de feature individual.

**Independent Test**: gerar roadmap, copiar o nome curto e a descricao
da primeira entrada para `/feature-00c <descricao>`, e verificar que a
pre-condicao (briefing + constitution ratificados) passa e a feature
inicia normalmente (FR-003, FR-005).

**Acceptance Scenarios**:

1. **Given** roadmap gerado com N features, **When** o operador inicia
   `/feature-00c` com a descricao da primeira entrada, **Then** a
   pre-condicao de briefing + constitution ratificados e satisfeita
   pelos artefatos da execucao roadmap e a feature inicia sem retrabalho
   (FR-003, FR-005).
2. **Given** entrada do roadmap, **When** seu nome curto e usado como
   short-name da feature, **Then** o nome e um kebab-case valido aceito
   pelo `/feature-00c` (FR-005).

---

### User Story 3 - Acompanhar progresso do portfolio (Priority: P3)

Conforme as features do roadmap vao sendo executadas, o operador
consulta o progresso: quais features sugeridas ja foram iniciadas (tem
spec no portfolio), quais concluiram e quais ainda nao comecaram — na
ordem sugerida pelo roadmap.

**Why this priority**: visibilidade de longo prazo; valioso, mas o fluxo
funciona sem isso (o operador pode conferir docs/specs/ manualmente).

**Independent Test**: gerar roadmap com 3 features, executar 1 via
feature-00c, rodar o relatorio de portfolio e verificar a classificacao
das 3 entradas (1 iniciada, 2 nao iniciadas) (FR-006).

**Acceptance Scenarios**:

1. **Given** roadmap com features sugeridas e ao menos uma ja executada
   via feature-00c, **When** o operador roda o relatorio de portfolio
   (review-features), **Then** cada entrada do roadmap aparece
   classificada como nao-iniciada, em-andamento ou concluida, cruzando o
   roadmap com as specs existentes no portfolio (FR-006).

---

### Edge Cases

- Projeto ja tem briefing e constitution ratificados de execucao
  anterior: o modo roadmap reaproveita os artefatos existentes (mesmo
  comportamento de atualizacao/reuso das skills briefing e constitution)
  e segue direto para a geracao do roadmap — nao re-entrevista do zero
  (FR-002).
- Roadmap resultaria em UMA unica feature (produto trivial): roadmap com
  1 entrada e valido; o relatorio deve sugerir explicitamente que o
  operador considere a pipeline completa atual (a feature unica ja e o
  projeto) (FR-007).
- Ja existe um roadmap de execucao anterior (re-execucao do modo):
  a geracao MUST atualizar o roadmap existente preservando o status e a
  identidade das features ja iniciadas — nunca sobrescrever
  silenciosamente nem duplicar entradas (FR-007).
- Nomes de features sugeridos que colidem com specs ja existentes no
  portfolio: a geracao reusa a entrada existente (marca como ja
  iniciada) em vez de sugerir nome duplicado (FR-005, FR-007).
- Constitution VI: as features do roadmap sao PROPOSTAS de escopo
  (julgamento de design, permitido); qualquer dado factual citado nas
  descricoes (endpoints, contratos, valores) segue exigindo fonte
  rastreavel — sem fonte, a descricao fica em termos de capacidade, sem
  afirmar fatos externos (FR-008).

## Requirements

### Functional Requirements

- **FR-001**: `/agente-00c` MUST oferecer o modo roadmap via pergunta
  interativa no inicio da execucao (mesmo padrao do opt-in
  atomic-commit), com default = pipeline completa atual; execucao
  nao-interativa MUST cair no default sem bloquear (zero regressao).
- **FR-002**: Em modo roadmap, a pipeline MUST executar somente
  briefing → constitution → geracao do roadmap, reaproveitando briefing
  e constitution ja ratificados quando existirem; as etapas de
  implementacao (specify, clarify, plan, checklist, create-tasks,
  execute-task, review-task) MUST NOT executar nesta execucao.
- **FR-003**: O roadmap MUST ser persistido como artefato canonico do
  projeto-alvo (`docs/roadmap.md`), contendo por entrada: nome curto
  kebab-case, descricao acionavel, ordem sugerida de execucao,
  dependencias entre features e justificativa da necessidade.
- **FR-004**: Apos gerar o roadmap, a execucao MUST encerrar em estado
  terminal de sucesso, com o roadmap incluso no relatorio final — o
  encerramento e o resultado esperado do modo, nao um aborto. O
  encerramento MUST ser distinguivel de uma conclusao de pipeline
  completa por um `termination_reason` de execucao proprio e normativo
  (`concluido_roadmap`, `contracts/cli-roadmap-mode.md` §5.2) — sem essa
  distincao, SC-001 nao e mensuravel por consumidores derivados.
- **FR-005**: Cada entrada do roadmap MUST ser consumivel diretamente
  pelo `/feature-00c`: nome curto valido como short-name e descricao
  suficiente para iniciar a feature sem reescrever contexto; nomes MUST
  NOT colidir com specs ja existentes no portfolio (entrada existente e
  reusada e marcada como iniciada).
- **FR-006**: O relatorio de portfolio (review-features) MUST cruzar o
  roadmap com as specs existentes em docs/specs/ e classificar cada
  entrada como nao-iniciada, em-andamento ou concluida, na ordem
  sugerida.
- **FR-007**: Re-execucao do modo roadmap com roadmap preexistente MUST
  atualizar o artefato preservando identidade e status das entradas ja
  iniciadas — sem sobrescrita silenciosa e sem duplicacao; roadmap de
  entrada unica e valido e MUST vir acompanhado de sugestao explicita de
  usar a pipeline completa.
- **FR-008**: As descricoes do roadmap MUST respeitar o Principio VI:
  propostas de escopo sao julgamento de design permitido; dado factual
  concreto (endpoints, assinaturas, valores) so aparece com fonte
  rastreavel — sem fonte, a entrada descreve a capacidade sem afirmar
  fatos externos.
- **FR-009**: A producao/escrita de `docs/roadmap.md` MUST ser
  responsabilidade de um componente dedicado (`roadmap-write.sh`),
  acionado pelo `agente-00c-orchestrator` ao concluir a redacao do
  conteudo do roadmap dentro da etapa `roadmap`, ANTES do encerramento
  terminal da execucao. O conteudo MUST passar pelo filtro de segredos
  do runtime (`secrets-filter.sh`) imediatamente antes da escrita, com
  politica fail-closed: se o filtro estiver ausente, a escrita MUST ser
  abortada — nunca escrever sem filtrar.

> Decisoes de infraestrutura: N/A (o modo produz artefatos de
> documentacao e encerra; sem scheduling, criptografia, tokens externos,
> multi-pod, backup ou retry proprios).

### Key Entities

- **Roadmap**: artefato canonico do projeto (`docs/roadmap.md`) com a
  lista ordenada de features sugeridas; irmao de briefing.md e
  constitution.md no nivel de projeto (nao pertence a nenhuma feature).
- **Entrada de roadmap**: uma feature sugerida — nome curto kebab-case,
  descricao acionavel, ordem, dependencias, justificativa, status
  derivado (nao-iniciada | em-andamento | concluida).

## Success Criteria

### Measurable Outcomes

- **SC-001**: Uma execucao em modo roadmap nunca registra
  `current_stage` posterior a `roadmap` — nenhuma onda avanca para
  `specify`, `clarify`, `plan`, `checklist`, `create-tasks`,
  `execute-task` ou `review-task`. Criterio observavel diretamente no
  `state.json`/`state.db` da execucao, sem exigir uma execucao de
  baseline da pipeline completa do mesmo projeto para comparacao.
- **SC-002**: 100% das entradas de roadmap geradas sao aceitas pelo
  `/feature-00c` sem edicao de nome (short-name valido) e sem pedido de
  descricao adicional na pre-condicao.
- **SC-003**: Zero regressao no default: execucao sem opt-in do modo
  produz pipeline identica a atual.
- **SC-004**: Re-execucoes do modo roadmap preservam a identidade
  (`short-name`) e a prosa (`Descricao`/`Justificativa`) de entradas ja
  existentes: zero entradas duplicadas para o mesmo `short-name`, e zero
  sobrescrita silenciosa de `Descricao`/`Justificativa` de entrada
  preexistente (alteracao deliberada e permitida, mas MUST ser reportada
  no relatorio final, conforme `contracts/roadmap-artifact.md` §8). O
  campo `status` e derivado na leitura (nunca persistido) e portanto
  fica fora do escopo deste criterio.

## Delta Requirements

### Capability: roadmap-mode

#### ADDED

- **FR-001**: `/agente-00c` MUST oferecer o modo roadmap via pergunta
  interativa no inicio da execucao (mesmo padrao do opt-in
  atomic-commit), com default = pipeline completa atual; execucao
  nao-interativa MUST cair no default sem bloquear (zero regressao).
- **FR-002**: Em modo roadmap, a pipeline MUST executar somente
  briefing → constitution → geracao do roadmap, reaproveitando briefing
  e constitution ja ratificados quando existirem; as etapas de
  implementacao (specify, clarify, plan, checklist, create-tasks,
  execute-task, review-task) MUST NOT executar nesta execucao.
- **FR-003**: O roadmap MUST ser persistido como artefato canonico do
  projeto-alvo (`docs/roadmap.md`), contendo por entrada: nome curto
  kebab-case, descricao acionavel, ordem sugerida de execucao,
  dependencias entre features e justificativa da necessidade.
- **FR-004**: Apos gerar o roadmap, a execucao MUST encerrar em estado
  terminal de sucesso, com o roadmap incluso no relatorio final — o
  encerramento e o resultado esperado do modo, nao um aborto. O
  encerramento MUST ser distinguivel de uma conclusao de pipeline
  completa por um `termination_reason` de execucao proprio e normativo
  (`concluido_roadmap`, `contracts/cli-roadmap-mode.md` §5.2) — sem essa
  distincao, SC-001 nao e mensuravel por consumidores derivados.
- **FR-009**: A producao/escrita de `docs/roadmap.md` MUST ser
  responsabilidade de um componente dedicado (`roadmap-write.sh`),
  acionado pelo `agente-00c-orchestrator` ao concluir a redacao do
  conteudo do roadmap dentro da etapa `roadmap`, ANTES do encerramento
  terminal da execucao. O conteudo MUST passar pelo filtro de segredos
  do runtime (`secrets-filter.sh`) imediatamente antes da escrita, com
  politica fail-closed: se o filtro estiver ausente, a escrita MUST ser
  abortada — nunca escrever sem filtrar.
