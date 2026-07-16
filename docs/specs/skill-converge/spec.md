# Feature Specification: Skill Converge — Reconciliação Spec-vs-Código

**Feature**: `skill-converge`
**Created**: 2026-07-16
**Status**: Draft

## Visão geral

O pipeline SDD deste toolkit (`briefing → constitution → specify → clarify →
plan → checklist → create-tasks → analyze → execute-task → review-task`) tem
hoje uma lacuna entre a intenção documentada e o código de fato entregue.
`analyze` compara artefatos entre si (spec vs plan vs tasks vs constitution)
mas é estritamente artefato-vs-artefato — nunca abre um arquivo de código.
`execute-task` (Etapa 9.3) faz um cross-check parcial, mas seu escopo é a
sessão corrente (`git diff HEAD~1..HEAD`) e uma única tarefa-alvo, não uma
auditoria completa do estado presente de todos os paths declarados em
`plan.md`/`tasks.md` de uma feature. O resultado observado: execuções longas
de `execute-task` (autônomas ou manuais) podem parar no meio, deixar código
parcialmente implementado, ou implementar algo diferente do que a spec pediu
— e nada no pipeline audita esse desvio antes do relatório final de
`review-task`.

Esta feature adiciona a skill `converge`: uma etapa de reconciliação que lê
`spec.md`/`plan.md`/`tasks.md` como fonte de intenção (o QUE foi pedido),
`constitution.md` como fonte de restrição (o que NÃO pode ser violado), e
avalia o estado presente do código nos paths declarados por `plan`/`tasks` —
sem depender de histórico de git ou diff de sessão. Cada divergência
encontrada é classificada em um de quatro tipos (`missing`, `partial`,
`contradicts`, `unrequested`) e, quando acionável, vira uma tarefa residual
apendada a uma fase de convergência no `tasks.md` — sempre no final,
append-only, sem jamais renumerar fases ou tarefas pré-existentes. Rodar a
skill duas vezes sobre o mesmo código sem nenhuma mudança produz o mesmo
`tasks.md`, byte a byte (idempotência).

A skill funciona tanto em modo standalone (invocada diretamente por um
desenvolvedor que quer auditar uma feature) quanto integrada aos
orquestradores autônomos `agente-00c`/`feature-00c`, rodando automaticamente
entre `execute-task` e `review-task`.

Referência conceitual: `/speckit.converge` do projeto
[github/spec-kit](https://github.com/github/spec-kit) (PR #3001), origem
comum da linhagem SDD deste toolkit — adaptado aqui ao domínio de skills
POSIX e aos artefatos/convenções já estabelecidos neste repositório (não é
uma tradução 1:1: o modelo de fases numeradas do `tasks.md`, a integração
com `agente-00c`/`feature-00c` e a derivação de severidade a partir da
`constitution.md` local são específicos deste toolkit).

> **Decisões de infraestrutura**: majoritariamente **N/A** — a skill não
> introduz scheduling, sessão persistente, refresh de token externo, rotação
> de chaves nem mutex multi-processo (execução local, síncrona, sob demanda
> do usuário ou do orquestrador que a invoca). Uma decisão de infraestrutura
> se aplica: **idempotência** — chave de idempotência é o par (paths
> declarados em `plan.md`/`tasks.md`, conteúdo presente desses paths no
> momento da execução); escopo é a execução completa da skill sobre uma
> feature; sem TTL — o resultado é determinístico e não expira, dado que
> deriva inteiramente do estado atual do código, não de um cache temporal.
> Ver FR-011.

## Clarifications

### Session 2026-07-16

- Q: Qual chave a skill usa para reconhecer que um Gap encontrado numa nova
  execução já corresponde a uma tarefa residual existente numa fase de
  convergência anterior (evitando duplicação, FR-012)? → A: Combinação
  (path do arquivo + tipo do Gap + requisito/task de origem) — mesma
  granularidade de atributos já exigida por FR-007/FR-016 em todo achado.
- Q: Além de `CRITICAL` (violação de `MUST`/`NON-NEGOTIABLE`), quais níveis
  de severidade a skill usa e com que critério para achados que não violam
  a constitution? → A: Escala de quatro níveis (`CRITICAL`/`HIGH`/`MEDIUM`/
  `LOW`): `HIGH` para achados `missing`/`contradicts` associados a uma User
  Story `P1`, `MEDIUM` para `P2`/`P3`, `LOW` para achados `unrequested` —
  derivado da `Priority` já usada nas User Stories da spec.
- Q: Para determinar se uma capacidade está "de fato implementada"
  (FR-004), a skill deve rodar a suite de testes/build do projeto-alvo, ou
  basear-se exclusivamente em leitura semântica estática do código-fonte
  pelo agente? → A: Leitura semântica estática do código-fonte (sem
  executar testes/build) — mesmo padrão read-only de `analyze`/`checklist`,
  sem side-effects no projeto-alvo.
- Q: Onde o `ConvergenceReport` fica registrado para consumo posterior
  (pelo orquestrador em execuções autônomas, ou por revisão humana em modo
  standalone)? → A: Registrado como Decisão auditável no `state.json` da
  execução — mesmo padrão dos demais quality gates já em uso
  (`validate-documentation`, `owasp-security`) — sem novo arquivo de
  artefato dedicado.
- Q: A execução automática de `converge` entre `execute-task` e
  `review-task` (FR-015) é incondicional ou configurável pelo operador
  (opt-in/opt-out)? → A: Incondicional — roda sempre em toda execução
  autônoma, sem flag de desabilitar, conforme a redação `MUST` literal de
  FR-015.

## User Scenarios & Testing

### User Story 1 - Detectar divergência entre o que foi pedido e o que existe no código (Priority: P1)

Como desenvolvedor que acabou de concluir tarefas de uma feature via
`execute-task`, quero rodar `converge` sobre essa feature para saber se o
código realmente implementado bate com o que `spec.md`/`plan.md`/`tasks.md`
prometeram, para não descobrir divergências apenas quando outra pessoa
revisar o trabalho (ou pior, em produção).

**Why this priority**: é o valor central da feature — sem detecção
confiável de divergência, nada mais na feature tem sentido. Sozinha já
entrega valor completo: um desenvolvedor pode rodar `converge` e obter um
relatório honesto do estado real, mesmo sem nenhuma das demais stories.

**Independent Test**: rodar `converge` standalone contra uma feature cujo
`tasks.md` está parcialmente marcado `[x]` e cujo código só implementa parte
do que as tasks descrevem; verificar que o relatório aponta exatamente os
paths que faltam ou estão incompletos.

**Acceptance Scenarios**:

1. **Given** uma feature com `spec.md`, `plan.md` e `tasks.md` existentes e
   código que implementa fielmente todas as tasks marcadas `[x]`, **When**
   `converge` é executada, **Then** o relatório indica zero divergências
   acionáveis para essas tasks.
2. **Given** uma feature cujo `tasks.md` referencia um path de arquivo que
   não existe no repositório, **When** `converge` é executada, **Then** o
   relatório aponta esse path como divergência, citando o path exato e a
   task/requisito de origem.
3. **Given** uma feature sem `tasks.md` (ou sem `spec.md`) no diretório
   informado, **When** `converge` é executada, **Then** a skill aborta com
   mensagem indicando qual artefato está faltando e qual comando gera o
   artefato ausente — sem tentar adivinhar o conteúdo.

---

### User Story 2 - Classificar cada divergência por tipo e por severidade (Priority: P1)

Como desenvolvedor, quero que cada divergência encontrada seja classificada
em um tipo preciso (`missing`, `partial`, `contradicts`, `unrequested`) e
receba uma severidade derivada dos princípios `MUST` da constitution do
projeto, para saber imediatamente o que é bloqueante e o que pode esperar.

**Why this priority**: classificação é o que transforma "lista de
diferenças" em informação acionável — sem tipo e severidade, o
desenvolvedor teria que reinterpretar cada achado manualmente, o que anula
boa parte do valor de automatizar a auditoria.

**Independent Test**: apresentar à skill um código que viola explicitamente
um princípio `MUST` da constitution do projeto (ex.: um script nos paths
declarados que não é POSIX sh puro) e verificar que o achado correspondente
recebe severidade `CRITICAL`, distinta dos demais achados sem violação de
`MUST`.

**Acceptance Scenarios**:

1. **Given** um path declarado em `tasks.md` cujo arquivo não existe,
   **When** `converge` avalia esse path, **Then** o achado é classificado
   como tipo `missing`.
2. **Given** um arquivo que implementa apenas parte do comportamento descrito
   na task correspondente, **When** `converge` avalia esse path, **Then** o
   achado é classificado como tipo `partial`.
3. **Given** um arquivo cujo comportamento observável contradiz
   explicitamente o que a task/requisito descreve, **When** `converge`
   avalia esse path, **Then** o achado é classificado como tipo
   `contradicts`.
4. **Given** um path com código que implementa capacidade não descrita em
   nenhuma story/requisito da `spec.md` nem justificada como suporte
   incidental (config, boilerplate, wiring), **When** `converge` avalia esse
   path, **Then** o achado é classificado como tipo `unrequested`.
5. **Given** um achado cuja causa é a violação de um princípio marcado
   `NON-NEGOTIABLE`/`MUST` na `constitution.md` do projeto, **When** a
   severidade é atribuída, **Then** o achado recebe severidade `CRITICAL`
   independente do tipo de gap.

---

### User Story 3 - Apendar tasks residuais em fase de convergência, sem tocar o backlog existente (Priority: P2)

Como desenvolvedor, quero que divergências acionáveis virem tarefas novas,
apendadas ao final do `tasks.md` numa fase de convergência dedicada, para
poder simplesmente rodar `execute-task` nelas sem precisar reorganizar o
backlog manualmente nem arriscar renumerar tarefas que outras pessoas já
referenciam (em commits, PRs, comentários).

**Why this priority**: fecha o ciclo de "detectar → agir" — sem isso, o
desenvolvedor ainda precisaria transformar o relatório em tarefas à mão.
Depende de US1/US2 (precisa haver algo classificado para apendar), por isso
é P2.

**Independent Test**: rodar `converge` duas vezes sobre a mesma feature após
uma mudança de código entre as execuções; verificar que a segunda execução
cria uma nova fase de convergência (numerada em sequência) sem alterar uma
vírgula das fases/tarefas anteriores, incluindo a primeira fase de
convergência já apendada.

**Acceptance Scenarios**:

1. **Given** um relatório de `converge` com ao menos um achado do tipo
   `missing`, `partial` ou `contradicts`, **When** a skill finaliza a
   análise, **Then** uma fase nova (`## FASE {N} - Convergência`, seguindo a
   numeração sequencial já em uso no `tasks.md`) é apendada ao final do
   arquivo, contendo uma tarefa por achado acionável.
2. **Given** um `tasks.md` com fases e tarefas pré-existentes, **When**
   `converge` apenda a fase de convergência, **Then** nenhum número de fase,
   número de tarefa ou texto de tarefa pré-existente é alterado (apenas
   conteúdo novo é adicionado ao final do arquivo).
3. **Given** um achado do tipo `unrequested` (código presente que a spec não
   pediu), **When** a tarefa residual correspondente é apendada, **Then**
   ela é marcada explicitamente como item de revisão (decidir manter,
   documentar retroativamente ou remover) e não como "implementar
   capacidade", já que o código já existe.
4. **Given** um relatório de `converge` sem nenhum achado acionável (feature
   já convergida), **When** a skill finaliza, **Then** nenhuma fase de
   convergência vazia é apendada ao `tasks.md`.

---

### User Story 4 - Confiar na skill para rodar repetidamente sem gerar ruído (Priority: P2)

Como operador que roda `converge` rotineiramente (manualmente ou via
orquestrador), quero que execuções repetidas sem nenhuma mudança de código
no intervalo não alterem o `tasks.md`, para poder rodar a skill livremente
— inclusive dentro de uma pipeline autônoma — sem gerar diffs espúrios que
poluam o histórico ou confundam quem revisa.

**Why this priority**: sem idempotência garantida, a skill não pode ser
usada com confiança dentro de execuções autônomas (US5) nem em rotina — cada
execução viraria um commit ruidoso mesmo sem nada de novo para reportar.

**Independent Test**: rodar `converge` duas vezes em sequência, sem
qualquer alteração de código entre as duas execuções; comparar o `tasks.md`
resultante byte a byte (`diff`/`cmp`) e confirmar que é idêntico.

**Acceptance Scenarios**:

1. **Given** uma feature já convergida (última execução de `converge` não
   deixou achados acionáveis pendentes), **When** `converge` roda de novo
   sem qualquer mudança de código no intervalo, **Then** o `tasks.md`
   resultante é byte-for-byte idêntico ao anterior.
2. **Given** uma feature cuja última fase de convergência já contém uma
   tarefa para um achado específico ainda não resolvido, **When** `converge`
   roda de novo sobre o mesmo estado de código, **Then** a skill reconhece o
   achado como já registrado e não duplica a tarefa numa nova fase.

---

### User Story 5 - Rodar automaticamente antes de review-task nos orquestradores (Priority: P3)

Como operador de uma execução autônoma `agente-00c`/`feature-00c`, quero que
a etapa de convergência rode automaticamente entre `execute-task` e
`review-task`, para que a auditoria spec-vs-código aconteça sempre, sem
depender de eu lembrar de invocá-la manualmente a cada feature.

**Why this priority**: é uma automação sobre uma capacidade que já existe e
já entrega valor sozinha (US1-4). Sem US5 a skill continua plenamente útil
em modo standalone — por isso é P3, não P1.

**Independent Test**: rodar uma execução `feature-00c` completa até o fim
de `execute-task` e observar, sem intervenção manual, que a etapa de
convergência dispara antes de `review-task` e que seu resultado (achados
`CRITICAL`) fica registrado de forma auditável na execução.

**Acceptance Scenarios**:

1. **Given** uma execução `feature-00c` que concluiu todas as tasks da onda
   corrente em `execute-task`, **When** o orquestrador avança de etapa,
   **Then** a etapa `converge` é executada antes de `review-task`, sem
   exigir invocação manual.
2. **Given** um achado `CRITICAL` (violação de `MUST` da constitution)
   reportado por `converge` dentro de uma execução autônoma, **When** o
   orquestrador processa o resultado, **Then** o achado é registrado como
   decisão auditável e tratado com o mesmo rigor dos demais quality gates
   já existentes na execução (reporta e permite ao orquestrador decidir
   escalar para bloqueio humano — `converge` não trava o processo sozinha).

---

### Edge Cases

- O que acontece quando `plan.md` não existe (só `spec.md` e `tasks.md`)?
  Os paths auditáveis vêm primariamente de `tasks.md` (que referencia
  arquivos concretos); `plan.md` ausente reduz contexto de intenção
  arquitetural mas não impede a execução.
- O que acontece quando um path declarado em `plan.md`/`tasks.md` aponta
  para fora do diretório do projeto-alvo? O path é reportado como achado
  `missing`/inconclusivo e a skill não o lê fora do blast radius do
  projeto-alvo — sem exceção.
- O que acontece quando a `constitution.md` do projeto não existe? A
  escalada automática a severidade `CRITICAL` por violação de `MUST` fica
  indisponível (não há `MUST` para violar); os demais critérios de
  severidade continuam se aplicando normalmente.
- O que acontece quando uma tarefa já está marcada `[x]` em `tasks.md` mas o
  código correspondente não bate com o que ela descreve? É exatamente o
  caso central desta feature — vira achado `partial` ou `contradicts`,
  independente do checkbox estar marcado.
- O que acontece quando um requisito da `spec.md` não tem nenhuma task nem
  path associado em `tasks.md`? Fora de escopo desta feature — cobertura
  requisito-sem-task já é responsabilidade de `analyze` (Gaps de
  Cobertura); `converge` avalia paths que já têm alguma referência em
  `plan`/`tasks`.
- O que acontece ao rodar `converge` uma terceira vez, quando já existem
  duas fases de convergência anteriores (uma resolvida via `execute-task`,
  outra ainda pendente)? Uma nova fase é apendada apenas para achados ainda
  não cobertos por nenhuma tarefa de convergência existente — sem duplicar
  os já registrados na fase anterior.

## Requirements

### Functional Requirements

- **FR-001**: A skill MUST ler `spec.md`, `plan.md` (quando presente) e
  `tasks.md` de uma feature como fonte de intenção (o que foi pedido e
  planejado).
- **FR-002**: A skill MUST ler `constitution.md` do projeto (quando
  presente) como fonte de restrição, extraindo os princípios marcados
  `MUST`/`NON-NEGOTIABLE`.
- **FR-003**: A skill MUST avaliar o conteúdo presente (estado atual) dos
  arquivos nos paths declarados em `plan.md`/`tasks.md`, sem depender de
  histórico de versionamento (git log/diff) ou do diff de uma sessão de
  execução específica.
- **FR-004**: A skill MUST determinar, para cada path avaliado, se a
  capacidade descrita no requisito/task correspondente está de fato
  implementada no código — não apenas se o arquivo existe. Essa
  determinação MUST ser feita por leitura semântica estática do
  código-fonte pelo agente — a skill MUST NOT executar a suite de
  testes/build do projeto-alvo como parte dessa avaliação (mesmo padrão
  read-only de `analyze`/`checklist`, sem side-effects no projeto-alvo).
- **FR-005**: A skill MUST classificar cada divergência encontrada em
  exatamente um dos quatro tipos: `missing` (esperado e ausente), `partial`
  (parcialmente implementado), `contradicts` (implementado de forma que
  contradiz a intenção documentada) ou `unrequested` (implementado sem
  pedido correspondente em nenhuma story/requisito).
- **FR-006**: A skill MUST atribuir severidade `CRITICAL` a qualquer
  divergência cuja causa envolva violação de um princípio `MUST`/
  `NON-NEGOTIABLE` da constitution do projeto, independente do tipo de
  divergência.
- **FR-007**: A skill MUST citar, para cada divergência reportada, ao menos
  um path de arquivo concreto e o requisito/task de origem — divergências
  sem localização rastreável não são reportadas como achado válido (ver
  Constitution VI, Veracidade de Dados).
- **FR-008**: Quando há divergências acionáveis (`missing`, `partial` ou
  `contradicts`), a skill MUST apendar uma nova fase ao final de
  `tasks.md`, contendo uma tarefa por divergência acionável, seguindo o
  mesmo formato (numeração, checkboxes, tag de criticidade) já usado pelas
  demais fases do arquivo.
- **FR-009**: A skill MUST NEVER modificar, renumerar ou remover conteúdo
  de fases ou tarefas pré-existentes em `tasks.md` — toda escrita é adição
  ao final do arquivo (append-only).
- **FR-010**: Quando não há nenhuma divergência acionável, a skill MUST NOT
  apendar uma fase de convergência vazia nem qualquer conteúdo a
  `tasks.md`.
- **FR-011**: Rodar a skill duas vezes sobre o mesmo estado de código
  (nenhuma mudança nos paths avaliados entre as execuções) MUST produzir um
  `tasks.md` byte-for-byte idêntico ao da execução anterior (idempotência).
- **FR-012**: Ao reavaliar uma feature que já possui fase(s) de convergência
  de execuções anteriores, a skill MUST reconhecer divergências já
  registradas como tarefa residual pendente e MUST NOT duplicá-las numa
  nova fase. A chave usada para esse reconhecimento MUST ser a combinação
  (path do arquivo + tipo do Gap + requisito/task de origem) — a mesma
  granularidade de atributos já exigida por FR-007/FR-016 para todo achado.
- **FR-013**: Divergências do tipo `unrequested` MUST ser apendadas como
  item de revisão (decisão: manter/documentar/remover), nunca como tarefa
  de "implementar", já que o código correspondente já existe.
- **FR-014**: A skill MUST funcionar em modo standalone, invocável
  diretamente por um usuário sobre uma feature específica, sem exigir uma
  execução `agente-00c`/`feature-00c` ativa.
- **FR-015**: Quando invocada dentro de uma execução `agente-00c`/
  `feature-00c`, a skill MUST rodar automaticamente entre a conclusão de
  `execute-task` e o início de `review-task`. Essa execução automática
  MUST ser incondicional — a skill MUST NOT expor flag de opt-out/opt-in
  para pular essa etapa dentro de uma execução autônoma.
- **FR-016**: A skill MUST produzir um relatório estruturado com a lista de
  achados (tipo, severidade, path, requisito/task de origem) e um resumo
  quantitativo (contagem por tipo e por severidade).
- **FR-017**: A skill MUST abortar com mensagem indicando o artefato
  ausente quando `spec.md` ou `tasks.md` da feature não existirem — MUST
  NOT inferir ou gerar conteúdo desses artefatos.
- **FR-018**: A skill MUST NOT avaliar paths que resolvam para fora do
  diretório do projeto-alvo da feature.
- **FR-019**: Achados `CRITICAL` reportados dentro de uma execução autônoma
  MUST ficar disponíveis para o orquestrador decidir escalada (ex.: bloqueio
  humano) — a skill em si reporta severidade e MUST NOT travar o processo
  autonomamente. Essa disponibilização MUST ocorrer via registro do
  `ConvergenceReport` como Decisão auditável no `state.json` da execução —
  mesmo padrão já usado pelos demais quality gates (`validate-documentation`,
  `owasp-security`) — sem exigir novo arquivo de artefato dedicado.
- **FR-020**: A skill MUST atribuir severidade a partir de uma escala de
  quatro níveis: `CRITICAL` (violação de `MUST`/`NON-NEGOTIABLE` da
  constitution, conforme FR-006), `HIGH` (achado `missing`/`contradicts`
  associado a uma User Story `P1`), `MEDIUM` (achado `missing`/`contradicts`
  associado a uma User Story `P2`/`P3`) e `LOW` (achado `unrequested`),
  derivando a prioridade da User Story de origem já declarada em `spec.md`.
  A atribuição de severidade para achados `partial` dentro dessa escala de
  quatro níveis fica deferida para `/plan` (detalhe de algoritmo, não altera
  a arquitetura da escala em si).

### Key Entities

- **Gap**: uma divergência única entre a intenção documentada e o código
  presente. Atributos: tipo (`missing`/`partial`/`contradicts`/
  `unrequested`), severidade (`CRITICAL`/`HIGH`/`MEDIUM`/`LOW` — ver
  FR-006/FR-020), path de arquivo, requisito/task de origem, descrição.
- **ConvergencePhase**: a fase apendada ao final de `tasks.md` numa
  execução da skill que produziu ao menos um achado acionável. Contém uma
  ou mais tarefas residuais, uma por `Gap` acionável (`missing`, `partial`,
  `contradicts`) ou item de revisão (`unrequested`).
- **ConvergenceReport**: o resultado apresentado ao final de uma execução —
  lista de `Gap`s encontrados e resumo quantitativo por tipo e severidade.
  Dentro de uma execução autônoma, MUST ser registrado como Decisão
  auditável no `state.json` (ver FR-019).

## Success Criteria

### Measurable Outcomes

- **SC-001**: Em uma feature cujo backlog está 100% concluído e o código
  implementa fielmente todas as tasks, a execução da skill reporta zero
  achados de severidade `CRITICAL` ou `HIGH`.
- **SC-002**: 100% dos achados cuja causa é violação de um princípio `MUST`
  da constitution do projeto são classificados com severidade `CRITICAL` —
  nenhum rebaixado por outro critério.
- **SC-003**: Duas execuções consecutivas da skill sem qualquer mudança de
  código entre elas produzem um `tasks.md` byte-for-byte idêntico,
  verificável por comparação direta de arquivo.
- **SC-004**: 100% dos achados reportados citam ao menos um path de arquivo
  concreto e um requisito/task de origem — zero achados sem localização
  rastreável.
- **SC-005**: Após qualquer número de execuções que apendem fase de
  convergência, todas as fases e tarefas pré-existentes preservam número e
  conteúdo originais — uma comparação do `tasks.md` antes/depois mostra
  apenas conteúdo adicionado, nunca removido ou editado em texto
  pré-existente.
- **SC-006**: A skill completa sua execução em modo standalone sem exigir
  que qualquer orquestrador autônomo esteja em execução.
