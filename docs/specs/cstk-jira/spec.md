# Feature Specification: Integracao CSTK-Jira

**Feature**: `cstk-jira`
**Created**: 2026-09-24
**Status**: Draft

## Clarifications

### Session 2026-09-24

- Q: FR-002 — o board dedicado do Jira e um unico board compartilhado por
  todos os projetos-alvo que instalarem o plugin, ou cada projeto-alvo
  recebe seu proprio board/projeto Jira na propria instancia do usuario?
  → A: cada projeto-alvo que instala o plugin recebe seu proprio
  board/projeto Jira dedicado, configurado durante a instalacao/
  configuracao guiada (FR-007), na instancia Jira que o mantenedor
  daquele projeto configurar. Nao existe um board unico compartilhado
  entre diferentes projetos-alvo/usuarios do plugin.
- Q: FR-006 — MCP e API REST do Jira sao mecanismos alternativos
  equivalentes configuraveis pelo usuario, ou um e o caminho principal
  e o outro e fallback? → A: MCP e o caminho preferencial quando um MCP
  de Jira (generico ou dedicado) estiver disponivel e cobrir as
  operacoes necessarias (ver FR-010); a API REST do Jira e o fallback
  universal, usado quando nenhum MCP de Jira estiver disponivel ou
  suficiente no ambiente do usuario. O mecanismo tecnico concreto (qual
  MCP Jira existe, quais operacoes cobre, detalhes de autenticacao) fica
  adiado para a fase de pesquisa do `/plan` (research.md), no mesmo
  padrao ja usado em FR-019-INFRA-REFRESH desta spec — por exigencia do
  Principio VI da constitution (Zero Fabricacao: sem fonte oficial do
  Jira, nao supor mecanismo/capacidades).

## User Scenarios & Testing

### User Story 1 - Converter feature em Epic/Tasks/Subtasks no Jira (Priority: P1)

Como mantenedor de um projeto que usa o toolkit, quero que uma feature
documentada (spec, plano tecnico e backlog de tarefas) seja convertida
automaticamente em um Epic no Jira com suas Tasks e Subtasks
correspondentes, para nao precisar recriar manualmente no Jira o que ja
esta documentado localmente.

**Why this priority**: e a capacidade fundadora do plugin — sem ela nao
ha "integracao com Jira", apenas configuracao vazia. Todo o resto (board,
sincronizacao de status, MCP exclusivo) depende de existir uma
representacao inicial no Jira para atuar sobre.

**Independent Test**: com uma feature existente (spec.md + tasks.md
preenchidos) e credenciais Jira configuradas, disparar a conversao e
verificar que o Epic e as Tasks/Subtasks aparecem no projeto Jira alvo
com titulos e hierarquia correspondentes ao backlog local — sem depender
de nenhuma outra capacidade do plugin.

**Acceptance Scenarios**:

1. **Given** uma feature com `spec.md` e `tasks.md` completos e nenhuma
   representacao previa no Jira, **When** o mantenedor dispara a
   conversao para essa feature, **Then** o sistema cria um Epic no Jira
   e uma Task/Subtask para cada item do backlog local, preservando a
   hierarquia de fases e dependencias declarada em `tasks.md`.
2. **Given** uma feature ja convertida anteriormente, **When** o
   `tasks.md` local ganha uma tarefa nova, **Then** o sistema cria
   apenas a Task nova associada ao Epic existente, sem duplicar as
   Tasks ja sincronizadas.
3. **Given** credenciais Jira ausentes ou invalidas, **When** o
   mantenedor dispara a conversao, **Then** o sistema recusa a operacao
   com um diagnostico claro do que falta configurar, sem criar
   artefatos parciais no Jira.

---

### User Story 2 - Board dedicado do CSTK no Jira (Priority: P2)

Como mantenedor, quero um board no Jira dedicado ao pipeline de
features do toolkit, para acompanhar visualmente o progresso (o que
esta em specify, plan, em execucao, convergido etc.) sem precisar abrir
o `state.json` ou o terminal.

**Why this priority**: da valor de visualizacao imediato assim que a
User Story 1 existe, mas depende dela (nao ha o que colocar num board
sem Epics/Tasks jah criados).

**Independent Test**: com pelo menos uma feature ja convertida (US1),
abrir o board do Jira e confirmar que os cards aparecem organizados por
estagio/coluna reconhecivel (equivalente ao estagio do pipeline SDD da
feature), sem necessidade de nenhuma acao manual de organizacao.

**Acceptance Scenarios**:

1. **Given** uma ou mais features convertidas para o Jira, **When** o
   mantenedor abre o board dedicado do CSTK, **Then** ve todos os Epics
   e Tasks das features convertidas organizados em colunas que
   correspondem ao estagio atual de cada item.
2. **Given** um board do CSTK ja existente para o projeto, **When** uma
   nova feature e convertida, **Then** os cards dessa feature aparecem
   no MESMO board, sem criar um board duplicado.

---

### User Story 3 - Sincronizacao automatica de status durante execucao autonoma (Priority: P1)

Como mantenedor rodando o orquestrador autonomo (`agente-00c`/
`feature-00c`), quero que o card do Jira correspondente a uma tarefa
mude de coluna/status automaticamente quando essa tarefa e concluida
(sucesso ou falha) localmente, para o board refletir o andamento real
da execucao autonoma sem sincronizacao manual.

**Why this priority**: e o que torna o board (US2) *vivo* durante
execucoes longas e autonomas — sem isso o board fica desatualizado
assim que a primeira onda termina, perdendo o valor central do pedido
original ("o orquestrador... crie, edite, mova os cards").

**Independent Test**: com uma feature convertida (US1) e o orquestrador
executando uma tarefa do backlog, observar que, ao a tarefa mudar de
outcome localmente, o card correspondente no Jira muda de coluna/status
dentro do mesmo ciclo de execucao, sem interacao manual.

**Acceptance Scenarios**:

1. **Given** uma Task no Jira vinculada a uma tarefa local ainda nao
   iniciada, **When** o orquestrador comeca a executar essa tarefa,
   **Then** o card correspondente muda para o status/coluna de "em
   andamento".
2. **Given** uma tarefa local concluida com sucesso, **When** o
   orquestrador registra o outcome, **Then** o card correspondente no
   Jira muda para o status/coluna de "concluido" ate o fim da mesma
   onda que produziu o outcome.
3. **Given** uma tarefa local concluida com falha, **When** o
   orquestrador registra o outcome, **Then** o card correspondente
   reflete um status distinto de "concluido com sucesso" (ex.: coluna
   de bloqueio/atencao), permitindo distinguir falha de sucesso olhando
   so para o board.

---

### User Story 4 - Instalacao e configuracao guiada (Priority: P2)

Como mantenedor que nunca usou o plugin, quero instalar o cstk-jira a
partir do marketplace de plugins do toolkit e configurar minhas
credenciais/projeto Jira atraves de um fluxo guiado, para comecar a
usar a integracao sem precisar descobrir manualmente quais arquivos ou
variaveis configurar.

**Why this priority**: sem instalacao/configuracao acessivel, as demais
stories so servem a quem ja tem o ambiente montado manualmente — mas a
capacidade central (conversao) ja entrega valor mesmo com configuracao
manual inicial, entao fica em P2.

**Independent Test**: em um projeto que nunca teve cstk-jira instalado,
rodar a instalacao a partir do marketplace e o fluxo de configuracao, e
confirmar que, ao final, uma tentativa de conversao (US1) funciona sem
nenhum passo de configuracao adicional nao coberto pelo fluxo guiado.

**Acceptance Scenarios**:

1. **Given** um projeto sem o plugin instalado, **When** o mantenedor
   instala o cstk-jira pelo marketplace de plugins do toolkit,
   **Then** o plugin fica disponivel com suas skills, comandos e
   (quando aplicavel) MCP dedicado, do mesmo jeito que qualquer outro
   plugin do toolkit.
2. **Given** o plugin instalado sem configuracao Jira ainda feita,
   **When** o mantenedor roda o fluxo de configuracao guiada,
   **Then** o sistema coleta o necessario para autenticar e identificar
   o projeto/board alvo no Jira, e confirma sucesso ou reporta
   diagnostico especifico em caso de falha.
3. **Given** um projeto sem qualquer configuracao Jira, **When** o
   mantenedor usa normalmente as demais funcionalidades do toolkit
   (specify, plan, execute-task etc.) sem nunca configurar o Jira,
   **Then** nao ha nenhuma mudanca de comportamento ou erro nessas
   funcionalidades por causa do plugin estar instalado e inativo.

---

### Edge Cases

- O que acontece quando uma tarefa local e removida ou renumerada apos
  ja ter sido sincronizada para o Jira? (o card correspondente nao pode
  ser apagado silenciosamente — ver FR-012)
- Como o sistema se comporta quando um card e movido/editado
  manualmente dentro do proprio Jira, fora do fluxo do orquestrador,
  e depois o orquestrador tenta sincronizar aquele mesmo card?
- O que acontece se as credenciais Jira expirarem ou forem revogadas no
  meio de uma execucao autonoma que ja fez parte da sincronizacao?
- Como o sistema se comporta se o Jira estiver indisponivel (erro de
  rede, rate limit) durante uma sincronizacao disparada pelo
  orquestrador autonomo — a execucao da feature deve parar ou apenas a
  sincronizacao deve ser adiada?
- O que acontece se duas execucoes (ex.: dois projetos-alvo distintos)
  tentarem sincronizar para o mesmo board do Jira ao mesmo tempo?
- Como o sistema decide entre usar a conexao MCP do Jira ou a API REST
  do Jira quando ambos os mecanismos estao disponiveis no ambiente do
  usuario?
- O que acontece se algum componente da integracao tentar enviar dados
  de rede para um dominio diferente do dominio Jira configurado pelo
  usuario?

## Requirements

### Functional Requirements

- **FR-001**: O sistema MUST converter a documentacao de uma feature
  (spec, plano tecnico e backlog de tarefas) num Epic do Jira com Tasks
  e Subtasks que espelhem a estrutura do backlog local (fases,
  dependencias e criticidade quando existirem).
- **FR-002**: O sistema MUST disponibilizar um board dedicado no Jira
  representando o pipeline de features do projeto que usa o plugin.
  Cada projeto-alvo que instala o plugin MUST ter seu proprio board/
  projeto Jira dedicado, configurado durante a instalacao/configuracao
  guiada (FR-007) na instancia Jira daquele projeto — nao existe um
  board unico compartilhado entre diferentes projetos-alvo/usuarios do
  plugin (ver Clarifications, sessao 2026-09-24).
- **FR-003**: O sistema MUST atualizar os issues Jira (Epic/Task/
  Subtask) ja existentes quando o artefato local correspondente mudar,
  em vez de criar issues duplicados para a mesma feature/tarefa.
- **FR-004**: O sistema MUST refletir mudancas de outcome de uma tarefa
  local (ex.: iniciada, concluida com sucesso, concluida com falha)
  como mudanca de status/coluna no card Jira correspondente.
- **FR-005**: O sistema MUST permitir que o orquestrador autonomo
  (execucao `agente-00c`/`feature-00c`) crie, edite e mova cards no
  Jira como parte normal da sua execucao, sem exigir confirmacao manual
  a cada sincronizacao individual.
- **FR-006**: O sistema MUST suportar a conexao com o Jira por pelo
  menos um dos dois mecanismos citados pelo pedido original — uma
  conexao MCP com o Jira ou a API REST do Jira. MCP e o caminho
  preferencial quando um MCP de Jira (generico ou dedicado) estiver
  disponivel e cobrir as operacoes necessarias (ver FR-010); a API REST
  do Jira e o fallback universal quando nenhum MCP de Jira estiver
  disponivel/suficiente no ambiente do usuario. O mecanismo tecnico
  concreto (qual MCP existe, quais operacoes cobre, autenticacao) fica
  adiado para a pesquisa do `/plan`, no mesmo padrao de
  FR-019-INFRA-REFRESH (ver Clarifications, sessao 2026-09-24).
- **FR-007**: O sistema MUST guiar o usuario por uma configuracao
  inicial (autenticacao e identificacao do projeto/board Jira alvo)
  antes da primeira sincronizacao, e MUST falhar com diagnostico claro
  quando a configuracao estiver incompleta, em vez de pular a
  sincronizacao silenciosamente.
- **FR-008**: O sistema MUST ser distribuivel como plugin instalavel
  atraves do marketplace de plugins do toolkit, seguindo o mesmo fluxo
  de instalacao dos demais plugins existentes.
- **FR-009**: O sistema MUST expor suas capacidades (conversao
  feature-para-Jira, sincronizacao de board) como skills/comandos
  descobriveis dentro do toolkit, consistentes com o formato de skill
  ja usado pelas demais capacidades do toolkit.
- **FR-010**: O sistema SHOULD expor um servidor MCP dedicado ao Jira
  quando isso oferecer capacidades alem do que skills/comandos
  genericos conseguem prover (ex.: chamadas estruturadas para criar/
  mover cards); o sistema MUST NOT introduzir um servidor MCP dedicado
  redundante quando um MCP de Jira generico ja cobrir as operacoes
  necessarias.
- **FR-011**: O sistema MUST detectar quando um card do Jira foi
  alterado diretamente no Jira (fora do fluxo do orquendrador) desde a
  ultima sincronizacao, e MUST NOT sobrescrever essa alteracao manual
  silenciosamente sem sinalizar o conflito.
- **FR-012**: O sistema MUST NOT apagar automaticamente um card do
  Jira quando a tarefa/feature local correspondente for removida ou
  renumerada — MUST sinalizar a divergencia (card orfao) para decisao
  humana em vez de excluir.
- **FR-013**: O sistema MUST ser idempotente: repetir a sincronizacao
  de uma mesma feature/tarefa nao MUST criar issues duplicados no Jira.
- **FR-014**: O sistema MUST registrar a associacao entre cada
  feature/tarefa local e o issue Jira correspondente (chave/id), para
  que sincronizacoes futuras localizem e atualizem o issue certo em vez
  de inferir por nome.
- **FR-015**: O sistema MUST restringir toda comunicacao de rede da
  integracao ao dominio Jira explicitamente configurado pelo usuario —
  nenhum dado e enviado a qualquer outro servico como efeito colateral
  da integracao.
- **FR-016**: O sistema MUST detectar credenciais Jira expiradas ou
  invalidadas e MUST solicitar reconfiguracao de forma explicita, em
  vez de repetir silenciosamente tentativas de sincronizacao que falham.
- **FR-017**: Usuarios que nunca configurarem a integracao Jira MUST
  continuar usando as demais funcionalidades do toolkit sem nenhuma
  mudanca de comportamento ou erro causado pelo plugin estar instalado
  e inativo.

**Decisoes de infraestrutura**: aplicavel — a feature depende de
credenciais externas (Jira) e de sincronizacao continua durante
execucoes autonomas potencialmente longas.

- **FR-018-INFRA-SCHED**: a sincronizacao de status com o Jira MUST ser
  disparada pelos pontos de ciclo de vida ja existentes da execucao
  autonoma (por exemplo, ao registrar o outcome de uma tarefa ou ao
  fechar uma onda) — default alinhado ao modelo de execucao por ondas
  ja usado pelo toolkit, sem introduzir um agendador separado.
- **FR-019-INFRA-REFRESH**: quando a autenticacao usada exigir renovacao
  periodica (ex.: token com expiracao), o sistema MUST renovar as
  credenciais automaticamente quando possivel e, quando isso nao for
  possivel, MUST tratar a falha como credencial invalida (FR-016) em
  vez de deixar a sincronizacao falhando silenciosamente de forma
  repetida. [Resolvido no `/plan` (research.md Decision 2, fontes
  oficiais Atlassian): API token do Atlassian account, que expira em ate
  1 ano e nao tem renovacao automatica — portanto aplica-se o ramo "quando
  nao for possivel": rejeicao de autenticacao = credencial invalida
  (FR-016), com suspensao explicita da sincronizacao.]

### Key Entities

- **Feature (local)**: unidade de trabalho documentada em
  `docs/specs/{short-name}/` (spec, plano, backlog) que da origem a um
  Epic no Jira.
- **Tarefa (local)**: item do backlog de uma feature (fase, criticidade,
  outcome) que da origem a uma Task ou Subtask no Jira.
- **Board do CSTK**: representacao visual no Jira do pipeline de
  features do projeto, organizada por estagio.
- **Card do Jira**: representacao no Jira de um Epic, Task ou Subtask
  sincronizado a partir de uma feature/tarefa local.
- **Mapeamento de sincronizacao**: associacao persistida entre um
  identificador de feature/tarefa local e o issue Jira correspondente,
  usada para tornar a sincronizacao idempotente e permitir atualizacao
  (em vez de duplicacao).
- **Configuracao Jira do projeto**: credenciais e identificacao do
  projeto/board Jira alvo, definidas durante a instalacao/configuracao
  guiada do plugin para um projeto especifico.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Um mantenedor converte uma feature existente (spec +
  backlog) para sua representacao Epic/Task/Subtask no Jira sem criar
  manualmente nenhum issue no Jira.
- **SC-002**: Repetir a sincronizacao da mesma feature/tarefa 10 vezes
  seguidas resulta em zero issues duplicados no Jira.
- **SC-003**: Apos uma tarefa mudar de outcome durante uma execucao
  autonoma, o card correspondente no Jira reflete o novo status ate o
  fim da mesma onda de execucao que produziu a mudanca, em pelo menos
  95% das sincronizacoes observadas.
- **SC-004**: Um novo usuario instala o plugin pelo marketplace e
  completa a configuracao inicial de credenciais/projeto Jira numa
  unica sessao guiada, sem precisar editar arquivos de configuracao
  fora desse fluxo.
- **SC-005**: 100% das escritas automatizadas feitas pelo orquestrador
  no Jira sao rastreaveis ate uma feature/tarefa local especifica
  atraves do mapeamento de sincronizacao — nenhuma escrita orfa/
  anonima.
- **SC-006**: Usuarios que nunca configuram credenciais Jira nao
  observam nenhuma mudanca de comportamento ou erro nas demais
  funcionalidades do toolkit com o plugin instalado.

## Delta Requirements

**Skip**: feature puramente nova (novo plugin `cstk-jira`); nao altera,
remove nem renomeia nenhuma capacidade hoje documentada em
`docs/specs/current/` — o corpus canonico atual nao cobre integracao
com sistemas de rastreamento de issues. — agente-00c-feature-orchestrator, 2026-09-24
