# Feature Specification: Specs Vivas — Corpus Canonico, Delta Specs no Archive e Staging Explicito no Commit Atomico

**Feature**: `living-specs`
**Created**: 2026-07-23
**Status**: Draft

## Visao geral

Continuacao do benchmark do concorrente [OpenSpec](https://github.com/Fission-AI/OpenSpec)
(Fission-AI, ver memoria `reference-openspec-benchmark` e a feature irma
`openspec-hygiene`, que absorveu os quatro itens de higiene mais baratos e
deixou explicitamente fora de escopo o item estrutural mais caro). Esta
feature trata esse item estrutural — o corpus de specs vivas + delta specs
no archive — e, em paralelo, endurece o modo `atomic-commit` contra o
incidente real observado durante a execucao da `openspec-hygiene`
(sug-001): um commit automatico por etapa usou staging amplo e varreu um
arquivo `.pptx` untracked alheio para dentro do commit.

Hoje `docs/specs/<feature>/spec.md` descreve uma MUDANCA e, ao ser
arquivada em `docs/specs/_archived/<data>-<feature>/`, o conhecimento
"como o sistema se comporta AGORA" para aquela capacidade evapora junto —
o unico jeito de reconstitui-lo e reabrir cada spec arquivada. O sintoma
observado no proprio toolkit e o `CLAUDE.md` gigante fazendo papel de spec
viva improvisada (secoes de "estado atual" mantidas a mao, fora do fluxo
SDD, sem rastreabilidade a nenhuma feature especifica).

> **Decisoes de infraestrutura**: N/A — esta feature nao introduz
> scheduling, sessao persistente, refresh de token externo, rotacao de
> chaves, mutex multi-pod, backup/restore nem idempotencia de request. O
> merge de delta no corpus e sincrono e disparado sob demanda pela acao de
> arquivamento (ja hoje manual/sob demanda, conforme `review-features`).

## Clarifications

### Session 2026-07-23

- Q: Onde o Living Spec Corpus vive fisicamente — novo diretorio dedicado
  (ex. `docs/specs/current/`), evolucao de `docs/02-requisitos-casos-uso/`,
  ou outro layout? → A: `docs/specs/current/`, novo diretorio dedicado,
  paralelo a `docs/specs/_archived/`. `docs/02-requisitos-casos-uso` nao
  existe neste repositorio — e a estrutura de UC-* que `initialize-docs`
  cria para PROJETOS-ALVO (formato de casos de uso), distinta do formato
  FR/SC ja usado pelas specs do proprio toolkit em
  `docs/specs/<feature>/spec.md`. Um dir novo mantem o corpus no mesmo
  formato SDD homogeneo, sem misturar UC com FR no mesmo diretorio.
- Q: Qual a politica de resolucao quando duas features tocam o mesmo
  identificador do corpus de forma incompativel no merge (ou quando
  REMOVED/MODIFIED referencia um identificador inexistente/nunca criado
  no corpus)? → A: Bloqueio automatico com diagnostico, exigindo
  resolucao humana explicita — estende uniformemente o padrao ja adotado
  por FR-010/FR-013/US3 desta mesma spec (sinalizar em vez de aplicar
  silenciosamente; bloquear salvo skip explicito auditavel) para os 3
  subcasos. Sem merge automatico (last-write-wins arriscaria perda
  silenciosa de informacao); sem fonte externa suficiente sobre o
  algoritmo exato do OpenSpec para adotar como suposicao (Principio VI).

## User Scenarios & Testing

### User Story 1 - Declarar o que mudou via secoes delta na spec da feature (Priority: P1)

Como autor de uma feature spec, ao escrever ou evoluir `spec.md` eu
declaro explicitamente, numa secao dedicada, quais Requisitos Funcionais
foram ADICIONADOS, MODIFICADOS, REMOVIDOS ou RENOMEADOS em relacao ao
comportamento atual do sistema — em vez de deixar essa informacao
implicita, espalhada em prosa, ou perdida quando a feature for arquivada.

**Why this priority**: sem um formato declarado para "o que mudou", nao
ha dado estruturado nenhum para aplicar no corpus no momento do archive —
e o pre-requisito de dados de todo o resto da feature.

**Independent Test**: escrever uma spec de teste com uma secao de Delta
Requirements contendo pelo menos um item de cada tipo (ADDED/MODIFIED/
REMOVED/RENAMED) e verificar que a secao e reconhecida e extraivel de
forma deterministica (sem depender de merge/gate ja estarem prontos).

**Acceptance Scenarios**:

1. **Given** uma spec nova sendo escrita para uma feature que introduz
   capacidade inedita, **When** o autor preenche a secao de Delta
   Requirements, **Then** cada requisito novo aparece listado sob ADDED
   com o mesmo identificador (`FR-NNN`) usado na secao de Requirements
   da propria spec.
2. **Given** uma spec que altera o comportamento de um requisito ja
   existente no corpus, **When** o autor preenche a secao delta,
   **Then** o requisito aparece sob MODIFIED referenciando o
   identificador do corpus que esta sendo substituido.
3. **Given** uma spec que torna obsoleto um comportamento hoje ativo,
   **When** o autor preenche a secao delta, **Then** o requisito aparece
   sob REMOVED referenciando o identificador do corpus a ser retirado.

---

### User Story 2 - Corpus canonico atualizado no momento do archive (Priority: P1)

Como qualquer pessoa (operador humano ou orquestrador autonomo) que
precisa responder "como o sistema se comporta hoje" para uma dada
capacidade, eu consulto um unico corpus canonico e encontro a resposta —
sem precisar abrir `docs/specs/_archived/` feature por feature nem
reconstituir historico manualmente.

**Why this priority**: e a entrega de valor central da feature — sem o
corpus sendo de fato escrito/atualizado, as secoes delta da US1 nao tem
destino e o problema original (conhecimento evaporando) continua intacto.

**Independent Test**: arquivar uma feature de teste com secao delta
preenchida e verificar que o corpus reflete os requisitos ADDED/MODIFIED/
REMOVED/RENAMED apos a acao de archive, sem exigir nenhuma outra feature
desta spec.

**Acceptance Scenarios**:

1. **Given** uma feature com Delta Requirements do tipo ADDED sendo
   arquivada, **When** a acao de archive e executada, **Then** o corpus
   ganha uma nova entrada para cada requisito ADDED, rastreavel ate a
   feature de origem.
2. **Given** uma feature com Delta Requirements do tipo MODIFIED
   referenciando um identificador ja existente no corpus, **When** a
   acao de archive e executada, **Then** a entrada correspondente no
   corpus e substituida pelo novo texto, preservando o identificador.
3. **Given** uma feature com Delta Requirements do tipo REMOVED, **When**
   a acao de archive e executada, **Then** a entrada correspondente
   deixa de valer como comportamento atual, com um registro rastreavel
   de que foi removida (nao um desaparecimento silencioso).
4. **Given** o corpus ainda nao existe (primeiro archive apos esta
   feature entrar em vigor), **When** a acao de archive e executada,
   **Then** o corpus e criado com as entradas daquela feature.
5. **Given** um archive concluido, **When** o fluxo hoje existente de
   mover a feature para `_archived/<data>-<feature>/` roda, **Then** ele
   continua funcionando exatamente como antes — o corpus e um destino
   ADICIONAL do conteudo, nunca uma substituicao do archive.

---

### User Story 3 - Gate deterministico: archive sem delta e invalido salvo skip explicito (Priority: P2)

Como mantenedor do toolkit, eu quero que arquivar uma feature sem secao
de Delta Requirements seja bloqueado por padrao — para que o corpus nunca
fique desatualizado por simples esquecimento — a menos que eu registre
explicitamente por que aquele archive nao precisa de delta (ex.: feature
puramente doc-only ou meta, sem impacto em comportamento do sistema).

**Why this priority**: fecha a lacuna que faria a US1+US2 degradarem
lentamente pelo mesmo motivo que o `CLAUDE.md` virou spec-viva-improvisada
— disciplina que nao e enforced por um gate tende a nao ser seguida.

**Independent Test**: tentar arquivar (a) uma feature sem secao delta e
sem skip — deve bloquear; (b) a mesma feature com um skip explicito
registrado — deve prosseguir; (c) uma feature com secao delta valida —
deve prosseguir sem exigir skip.

**Acceptance Scenarios**:

1. **Given** uma feature sem secao de Delta Requirements na sua spec,
   **When** a acao de archive e tentada sem nenhum skip registrado,
   **Then** o archive e bloqueado com diagnostico apontando exatamente o
   que falta.
2. **Given** a mesma situacao, **When** o operador registra um skip
   explicito com justificativa, **Then** o archive prossegue e o skip
   fica auditavel (quem, quando, por que) em qualquer relatorio/trilha
   que liste aquele archive.
3. **Given** uma feature com secao de Delta Requirements valida (mesmo
   que so com entradas REMOVED, por exemplo), **When** a acao de archive
   e tentada, **Then** ela prossegue sem exigir skip.
4. **Given** uma entrada MODIFIED/REMOVED/RENAMED cujo identificador
   referenciado nao existe no corpus atual, **When** o gate roda,
   **Then** ele sinaliza a inconsistencia em vez de aplicar
   silenciosamente um no-op.

---

### User Story 4 - Staging explicito por allowlist no commit atomico, nunca "add tudo" (Priority: P2)

Como operador rodando `agente-00c`/`feature-00c` com o modo atomic-commit
habilitado, eu quero que cada commit automatico (por etapa ou por task)
inclua apenas os arquivos de fato pertencentes aquele passo da pipeline —
para que um arquivo untracked alheio presente no repositorio nunca seja
varrido para dentro de um commit que eu nao pedi para incluir.

**Why this priority**: e um bug de seguranca/correcao ja materializado em
producao (incidente real na execucao `openspec-hygiene`, corrigido so em
follow-up manual apos o fato) — independente do resto da feature, e uma
fonte de risco toda vez que o modo atomic-commit roda.

**Independent Test**: com um arquivo untracked alheio presente no
working tree, rodar um commit automatico de etapa e de task e verificar
que o arquivo alheio nunca aparece no commit gerado, em nenhum dos dois
caminhos.

**Acceptance Scenarios**:

1. **Given** um arquivo untracked que nao pertence a etapa corrente
   presente no working tree, **When** o commit atomico de etapa
   (`specify`/`plan`/`clarify`/`checklist`/`create-tasks`) e disparado,
   **Then** o commit gerado contem somente os artefatos daquela etapa —
   o arquivo alheio permanece untracked.
2. **Given** o mesmo cenario durante `execute-task`, **When** o commit
   atomico agrupado por task e disparado, **Then** o commit contem
   somente os arquivos tocados pelas tasks com `outcome=pass` daquela
   onda — o arquivo alheio permanece untracked.
3. **Given** uma etapa/task que nao tocou nenhum arquivo (no-op),
   **When** o commit automatico seria disparado, **Then** nenhum commit
   vazio e criado.

---

### Edge Cases

- Duas features arquivadas em momentos diferentes com Delta Requirements
  que tocam o MESMO identificador do corpus de formas incompativeis (uma
  MODIFICA o que a outra REMOVEU, por exemplo) — politica de resolucao:
  bloqueio automatico com diagnostico exigindo resolucao humana explicita,
  na mesma linha de FR-010/FR-013 (nunca last-write-wins silencioso, nunca
  merge automatico sem fonte suficiente sobre o algoritmo — ver
  `## Clarifications`).
- Feature cuja spec foi escrita ANTES desta feature entrar em vigor
  (todas as features hoje abertas em `docs/specs/*`, fora `_archived/`)
  chega ao momento de archive sem nunca ter tido a secao delta pensada
  durante specify/plan — o gate da US3 ainda se aplica: o autor precisa
  retroceder e preencher a secao delta na hora do archive, ou registrar
  skip explicito.
- Entrada RENAMED cujo identificador antigo e referenciado por uma
  entrada MODIFIED de outra feita em outra feature ainda nao arquivada —
  o gate deve sinalizar a inconsistencia de referencia, nao aplicar
  silenciosamente.
- Colisao de identificador: duas features declaram ADDED com o mesmo
  `FR-NNN` para entradas de corpus diferentes — deve ser sinalizado, nao
  sobrescrito silenciosamente.
- Allowlist do commit atomico calculada como vazia porque a etapa/task
  gerou arquivos fora do projeto-alvo (ex.: escrita acidental fora do
  blast radius) — nao deve resultar em fallback para staging amplo; o
  comportamento correto e nao commitar esses arquivos.
- O gate de delta obrigatorio roda como script deterministico, nao como
  julgamento de modelo: duas execucoes do gate sobre a mesma spec e o
  mesmo estado de corpus MUST produzir sempre o mesmo veredito (bloquear
  ou liberar o archive), sem variacao entre chamadas.
- Fase `review-features` do orquestrador autonomo (`agente-00c`) encontra
  `delta-gate.sh` bloqueado (exit 1) para uma feature candidata a archive
  durante execucao SEM supervisao — o orquestrador MUST registrar
  `bloqueios.sh register` ESCOPADO aquela feature especifica (pergunta
  citando os `FINDING`/`RESULT` literais emitidos pelo gate), nunca
  falhar silenciosamente nem pular o archive sem rastro; as demais
  features do portfolio sem bloqueio de gate continuam sendo processadas
  normalmente na mesma onda (research.md Decision 8).

## Requirements

### Functional Requirements

- **FR-001**: Autores de spec MUST ser capazes de declarar, dentro da
  spec da feature, uma secao de Delta Requirements com quatro tipos de
  entrada — ADDED, MODIFIED, REMOVED e RENAMED — usando o mesmo esquema
  de identificador (`FR-NNN`) ja usado na secao de Requirements da propria
  spec.
- **FR-002**: Uma entrada ADDED MUST, ao a feature ser arquivada, se
  tornar uma nova entrada no corpus canonico.
- **FR-003**: Uma entrada MODIFIED MUST, ao a feature ser arquivada,
  substituir a entrada correspondente do corpus (casada por
  identificador) pelo novo texto, preservando o identificador.
- **FR-004**: Uma entrada REMOVED MUST, ao a feature ser arquivada,
  retirar a entrada correspondente do corpus como comportamento atual,
  preservando um registro rastreavel da remocao (nunca um desaparecimento
  silencioso do historico).
- **FR-005**: Uma entrada RENAMED MUST, ao a feature ser arquivada,
  aposentar o identificador antigo e registrar o novo identificador para
  a mesma entrada do corpus, sem perder a rastreabilidade historica da
  entrada.
- **FR-006**: System MUST manter um corpus canonico descrevendo o
  comportamento ATUAL do sistema, distinto do historico de mudancas por
  feature preservado sob `_archived/` — o corpus e ADICIONAL, nunca
  substitui o archive existente.
- **FR-007**: Cada entrada do corpus MUST ser rastreavel ate a(s)
  feature(s) que a introduziu ou modificou por ultimo (proveniencia).
- **FR-008**: A atualizacao do corpus MUST acontecer como parte da acao
  de archive ja existente, sem exigir um passo manual adicional alem do
  que o archive ja requer hoje.
- **FR-009**: Consultar o corpus MUST responder "como o sistema se
  comporta hoje" para qualquer capacidade coberta, sem exigir abrir
  nenhum diretorio sob `_archived/`.
- **FR-010**: A acao de archive MUST ser bloqueada, por padrao, para
  qualquer feature que nao tenha secao de Delta Requirements — salvo
  quando um skip explicito for registrado.
- **FR-011**: Um skip de delta MUST ser um registro auditavel (quem,
  quando, por que), distinguivel de uma aplicacao normal de delta em
  qualquer relatorio ou trilha de auditoria que liste aquele archive.
- **FR-012**: O gate da FR-010 MUST ser deterministico (script, nao
  julgamento de modelo), no mesmo padrao ja adotado pelo toolkit para
  outros gates de qualidade estrutural (ex.: `requirement-coverage.sh`).
- **FR-013**: O gate MUST sinalizar (nao aplicar silenciosamente)
  qualquer entrada MODIFIED, REMOVED ou RENAMED cujo identificador
  referenciado nao exista no corpus atual.
- **FR-014**: O staging de commits automaticos do modo atomic-commit
  (por etapa e por task, em execucao autonoma) MUST usar uma allowlist
  explicita de caminhos derivada dos artefatos tocados pelo passo/task
  corrente — MUST NOT usar staging amplo (equivalente a "adicionar tudo
  do working tree").
- **FR-015**: Quando um arquivo untracked alheio ao passo/task corrente
  estiver presente no working tree no momento do commit automatico, ele
  MUST NOT ser incluido no commit gerado, independentemente do tipo de
  arquivo.
- **FR-016**: Quando a allowlist de um passo/task for vazia, nenhum
  commit MUST ser criado para aquele passo/task (sem commits vazios, sem
  fallback para staging amplo).
- **FR-017**: O cenario que causou o incidente original (arquivo
  untracked alheio presente durante commit atomico de etapa) MUST ter
  cobertura de teste de regressao automatizada.

### Key Entities

- **Living Spec Corpus**: local canonico que descreve o comportamento
  ATUAL do sistema-alvo, organizado por requisito rastreavel; distinto do
  historico de mudancas por feature preservado em `_archived/`. Vive em
  `docs/specs/current/`, novo diretorio dedicado, paralelo a
  `docs/specs/_archived/`, mantendo o formato SDD (FR/SC) homogeneo com
  as specs de origem — ver `## Clarifications`.
- **Delta Requirements Section**: bloco dentro da spec de uma feature que
  declara requisitos ADICIONADOS, MODIFICADOS, REMOVIDOS ou RENOMEADOS em
  relacao ao comportamento atual, usando o mesmo esquema de identificador
  `FR-NNN` da propria spec.
- **Corpus Entry**: unidade individual do corpus — um requisito de
  comportamento atual, com proveniencia (feature de origem) e
  identificador estavel.
- **Archive Skip Record**: registro auditavel (quem, quando, por que)
  que autoriza arquivar uma feature sem secao de Delta Requirements.
- **Commit Allowlist**: conjunto explicito de caminhos, derivado dos
  artefatos tocados pelo passo/task corrente da pipeline, usado para
  staging de um commit automatico em vez de "adicionar tudo".

## Success Criteria

### Measurable Outcomes

- **SC-001**: 100% das features arquivadas apos esta feature entrar em
  vigor tem, no momento do archive, ou uma atualizacao aplicada ao corpus
  ou um registro de skip auditavel — zero features desaparecem sem deixar
  rastro de "o que mudou no comportamento atual".
- **SC-002**: Para qualquer capacidade ja tocada por uma feature
  arquivada, um leitor consegue responder "como o sistema se comporta
  hoje" consultando um unico local canonico, sem abrir nenhum
  subdiretorio de `_archived/`.
- **SC-003**: 0% dos commits automaticos gerados durante execucao
  autonoma com atomic-commit habilitado incluem um arquivo untracked
  alheio ao passo/task corrente, verificado pela suite de regressao.
- **SC-004**: Toda entrada do corpus permite identificar sua feature de
  origem em uma unica consulta (campo de proveniencia), para 100% das
  entradas.

## Out of Scope

- Migrar retroativamente as features ja hoje em `docs/specs/_archived/`
  (aprox. 15) para o corpus canonico. Pode existir uma task OPCIONAL de
  backfill incremental no backlog desta feature, mas nao e criterio de
  aceite — nao bloqueia a conclusao.
- Stores/worksets multi-repo do OpenSpec (mecanismo de agregacao entre
  multiplos repositorios) — nao ha fonte suficiente sobre esse mecanismo
  no material ja lido do benchmark, e esta feature trata de um unico
  projeto-alvo por vez, em paridade com o restante do toolkit.

## Delta Requirements

### Capability: spec-delta-requirements

#### ADDED

- **FR-001**: Autores de spec MUST ser capazes de declarar, dentro da
  spec da feature, uma secao de Delta Requirements com quatro tipos de
  entrada — ADDED, MODIFIED, REMOVED e RENAMED — usando o mesmo esquema
  de identificador (`FR-NNN`) ja usado na secao de Requirements da propria
  spec.
- **FR-002**: Uma entrada ADDED MUST, ao a feature ser arquivada, se
  tornar uma nova entrada no corpus canonico.
- **FR-003**: Uma entrada MODIFIED MUST, ao a feature ser arquivada,
  substituir a entrada correspondente do corpus (casada por
  identificador) pelo novo texto, preservando o identificador.
- **FR-004**: Uma entrada REMOVED MUST, ao a feature ser arquivada,
  retirar a entrada correspondente do corpus como comportamento atual,
  preservando um registro rastreavel da remocao (nunca um desaparecimento
  silencioso do historico).
- **FR-005**: Uma entrada RENAMED MUST, ao a feature ser arquivada,
  aposentar o identificador antigo e registrar o novo identificador para
  a mesma entrada do corpus, sem perder a rastreabilidade historica da
  entrada.

### Capability: spec-corpus

#### ADDED

- **FR-006**: System MUST manter um corpus canonico descrevendo o
  comportamento ATUAL do sistema, distinto do historico de mudancas por
  feature preservado sob `_archived/` — o corpus e ADICIONAL, nunca
  substitui o archive existente.
- **FR-007**: Cada entrada do corpus MUST ser rastreavel ate a(s)
  feature(s) que a introduziu ou modificou por ultimo (proveniencia).
- **FR-008**: A atualizacao do corpus MUST acontecer como parte da acao
  de archive ja existente, sem exigir um passo manual adicional alem do
  que o archive ja requer hoje.
- **FR-009**: Consultar o corpus MUST responder "como o sistema se
  comporta hoje" para qualquer capacidade coberta, sem exigir abrir
  nenhum diretorio sob `_archived/`.

### Capability: delta-archive-gate

#### ADDED

- **FR-010**: A acao de archive MUST ser bloqueada, por padrao, para
  qualquer feature que nao tenha secao de Delta Requirements — salvo
  quando um skip explicito for registrado.
- **FR-011**: Um skip de delta MUST ser um registro auditavel (quem,
  quando, por que), distinguivel de uma aplicacao normal de delta em
  qualquer relatorio ou trilha de auditoria que liste aquele archive.
- **FR-012**: O gate da FR-010 MUST ser deterministico (script, nao
  julgamento de modelo), no mesmo padrao ja adotado pelo toolkit para
  outros gates de qualidade estrutural (ex.: `requirement-coverage.sh`).
- **FR-013**: O gate MUST sinalizar (nao aplicar silenciosamente)
  qualquer entrada MODIFIED, REMOVED ou RENAMED cujo identificador
  referenciado nao exista no corpus atual.

### Capability: atomic-commit-staging

#### ADDED

- **FR-014**: O staging de commits automaticos do modo atomic-commit
  (por etapa e por task, em execucao autonoma) MUST usar uma allowlist
  explicita de caminhos derivada dos artefatos tocados pelo passo/task
  corrente — MUST NOT usar staging amplo (equivalente a "adicionar tudo
  do working tree").
- **FR-015**: Quando um arquivo untracked alheio ao passo/task corrente
  estiver presente no working tree no momento do commit automatico, ele
  MUST NOT ser incluido no commit gerado, independentemente do tipo de
  arquivo.
- **FR-016**: Quando a allowlist de um passo/task for vazia, nenhum
  commit MUST ser criado para aquele passo/task (sem commits vazios, sem
  fallback para staging amplo).
- **FR-017**: O cenario que causou o incidente original (arquivo
  untracked alheio presente durante commit atomico de etapa) MUST ter
  cobertura de teste de regressao automatizada.
