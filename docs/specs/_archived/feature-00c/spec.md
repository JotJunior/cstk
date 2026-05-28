# Feature Specification: Feature-00C — Orquestrador Autonomo de Feature Individual

**Feature**: `feature-00c`
**Created**: 2026-05-20
**Status**: Draft

## Clarifications

### Session 2026-05-20

- Q: `review-task` ao fim da pipeline — uma vez ao final ou apos cada subtask?
  → A: Uma vez ao final (sobre toda a feature; alinhado com a skill `review-task` atual).
- Q: Como o `state.json` registra progresso dentro do loop de `execute-task` para retomada granular?
  → A: Campos granulares (`tasks_concluidas[]` + `task_corrente`) — retomada contínua exata.
- Q: Politica de retencao de backups por onda?
  → A: Todas as ondas (audit perfeito) em `feature-00c-state/<short-name>/backups/wave-NNN.json`.
- Q: Pre-flight constitution-conflict check entre `spec` e `plan` (commit e457dfa) — reuso ou check próprio?
  → A: Reusar o check do agente-00c via runtime compartilhado (FR explicito adicionado).
- Q: Filtro de secrets (FR-030 herdado) deve aplicar aos backups por onda (FR-034)?
  → A: Sim — estender filtro a backups (FR-034 atualizado).
- Q: Conteúdo detalhado das 6 seções do relatório — IN-SPEC ou via /plan?
  → A: Delegar para `/plan` gerar `contracts/report-format.md` (mesmo padrão do agente-00c). FR-018 referencia o contrato futuro.
- Q: Definições delegadas ("progresso mensurável", "aspectos-chave normalizados") — duplicar ou referência cruzada?
  → A: Aceitar referência cruzada explícita ao agente-00c (FRs atualizados com pointer auditável).
- Q: Valores de threshold de onda (tool calls, wallclock, tamanho de estado) — onde fixar?
  → A: FR explícito reusando thresholds do agente-00c research.md Decision 2 (FR-015A adicionado).
- Q: Filtro de secrets em casos ambíguos (string que parece token mas é commit SHA, UUID, etc) — default?
  → A: Fail-safe (redact em dúvida) — privacidade > usabilidade. FR-029 §filtro atualizado.
- Q: `gh issue create` como única exceção a "zero comunicação externa" — explícita ou implícita?
  → A: FR-035 novo declarando explicitamente.
- Q: Race entre `/feature-00c-abort` e onda corrente em execução — como tratar?
  → A: SIGTERM + grace period 60s antes do force-acquire. FR-025 atualizado + Contract.
- Q: Logs stderr do orquestrador podem vazar secrets/state — como tratar?
  → A: FR-036 novo estendendo filtro de secrets a TODOS os outputs (stderr/stdout/logs), não só arquivos.

---

> **Contexto**: paralelo ao `agente-00c` (orquestracao no escopo de projeto
> inteiro, da pipeline `briefing → constitution → ... → review-features`),
> esta feature introduz um orquestrador autonomo focado em **uma unica feature
> dentro de um projeto ja existente**. A pipeline coberta e o bloco
> `specify → clarify → plan → checklist → create-tasks → execute-task →
> review-task`. As fases de governanca de projeto (`briefing` e `constitution`)
> e a fase agregadora cross-feature (`review-features`) estao FORA de escopo —
> precisam estar pre-existentes no projeto antes da invocacao. Decisao
> arquitetural pre-spec: NOVO agente dedicado (`agente-00c-feature-orchestrator`),
> NOVO slash command (`/feature-00c`), compartilhando o runtime POSIX
> (`agente-00c-runtime`) com o orquestrador raiz para evitar duplicacao de
> codigo de estado/lock/backup.

---

## User Scenarios & Testing

### User Story 1 — Entregar feature implementada com relatorio auditavel (Priority: P1)

Joao trabalha em projeto existente (com `docs/01-briefing-discovery/briefing.md`
e `docs/constitution.md` ja ratificados) e quer adicionar uma feature nova.
Em vez de conduzir manualmente cada fase do SDD (spec, clarify, plan,
checklist, tasks, execucao das tasks, review final), invoca
`/feature-00c "<descricao curta da feature>"` e se afasta. Quando volta,
encontra a feature implementada (codigo + testes + artefatos SDD completos
em `docs/specs/<short-name>/`) **e** um relatorio auditavel descrevendo
cada decisao tomada por cada subagente em cada fase, onde a execucao parou
ou foi pausada, e quais aprendizados/sugestoes emergiram.

**Why this priority**: este e o entregavel-mor da feature. Sem relatorio
auditavel + feature minimamente executavel ao fim, a feature nao tem razao
de existir — o usuario poderia ter rodado as skills manualmente. P1 garante
que mesmo a execucao mais simples produz valor de cabo a rabo.

**Independent Test**: invocar `/feature-00c` com descricao curta em projeto
que ja tem briefing+constitution; deixar rodar ate o fim (ou abortar
voluntariamente em qualquer fase); abrir o relatorio e verificar que
contem decisoes rastreaveis para cada fase atravessada, e que os artefatos
SDD esperados (`spec.md`, `plan.md`, `tasks.md`, etc) existem em
`docs/specs/<short-name>/`.

**Acceptance Scenarios**:

1. **Given** um projeto com `briefing.md` e `constitution.md` presentes e
   uma feature nova invocada via `/feature-00c "<descricao>"`, **When** a
   execucao corre ate o fim sem bloqueios, **Then** existem todos os
   artefatos da pipeline (`spec.md`, `plan.md`, `checklists/*.md`,
   `tasks.md`) em `docs/specs/<short-name>/`, a feature foi implementada
   (pelo menos a P1 story), e ha relatorio em
   `<projeto-alvo>/.claude/feature-00c-report.md` contendo todas as secoes
   obrigatorias.
2. **Given** uma execucao abortada por gatilho automatico, **When** joao
   abre o relatorio, **Then** o motivo do aborto esta na primeira pagina,
   a fase em que parou e visivel, e as decisoes tomadas ate o aborto estao
   completas no formato auditavel.
3. **Given** uma execucao pausada por bloqueio humano (clarify nao decidivel,
   path invalido, conflito de constitution, etc), **When** joao abre o
   relatorio parcial, **Then** encontra o ponto exato onde foi pedida
   decisao humana com contexto suficiente para responder sem reler
   artefatos.

---

### User Story 2 — Decisoes autonomas no clarify reusando o padrao asker/answerer (Priority: P2)

Quando a pipeline atinge a fase `clarify`, dois subagentes especializados
sao acionados pelo orquestrador-de-feature. O asker (mesma logica do
`agente-00c-clarify-asker`) carrega a skill `clarify` e gera as perguntas
mais relevantes da spec corrente. O answerer (mesma logica do
`agente-00c-clarify-answerer`) recebe perguntas + spec corrente + briefing
do projeto + constitution + decisoes anteriores, e escolhe uma opcao para
cada pergunta com justificativa explicita. Comunicacao entre eles e mediada
pelo orquestrador, nao direta — espelhando o contrato do agente-00c.

**Why this priority**: o clarify e o gargalo classico de qualquer pipeline
SDD. Se cada feature exigisse intervencao humana no clarify, a feature
perderia seu proposito. P2 garante que feature-00c herda exatamente o
mesmo padrao de decisao autonoma com auditabilidade ja validado pelo
agente-00c, sem reinventar.

**Independent Test**: rodar a pipeline ate `clarify` em isolamento
(invocar `/feature-00c` em uma feature com spec.md ja existente e ambigua,
forcando entrada direta no clarify), verificar que perguntas sao geradas
e respondidas automaticamente, e que cada par pergunta-resposta aparece
no relatorio com justificativa em briefing/constitution/spec/decisao-prior.

**Acceptance Scenarios**:

1. **Given** uma spec com ambiguidades, **When** o orquestrador-de-feature
   executa a fase clarify, **Then** o asker gera entre 1 e 5 questoes e o
   answerer escolhe uma opcao para cada uma sem invocar humano, registrando
   contexto + opcoes + escolha + justificativa + agente.
2. **Given** uma questao para a qual o answerer nao consegue justificar
   escolha em termos de briefing/constitution/spec/decisao-anterior, **When**
   o orquestrador recebe o retorno, **Then** a questao e convertida em
   bloqueio humano e a pipeline pausa graciosamente (com persistencia +
   relatorio parcial).
3. **Given** uma execucao concluida, **When** joao examina a secao "Decisoes"
   do relatorio, **Then** cada decisao do answerer aparece com os 5 campos
   obrigatorios preenchidos (mesmo contrato do agente-00c).

---

### User Story 3 — Retomada cross-sessao via schedule/clear/continue (Priority: P3)

Features nao-triviais ultrapassam o limite de uma sessao do Claude Code. Ao
final de cada onda, o orquestrador-de-feature serializa o estado da
execucao em disco (fase atual, decisoes ate o momento, proxima instrucao
explicita), faz commit local, agenda a proxima onda e libera a sessao.
Quando a proxima onda dispara via `/feature-00c-resume`, o orquestrador
le o estado, valida o hash de integridade e retoma a pipeline exatamente
de onde parou.

**Why this priority**: a duracao tipica esperada de uma feature ja excede
uma sessao quando `execute-task` rola por multiplas tarefas. Sem retomada,
features-00c viraria sinonimo de "feature trivial". Mas P1 + P2 ja
produzem valor em uma sessao para features curtas; por isso P3, nao P1.

**Independent Test**: forcar interrupcao (clear de contexto, ou estouro de
80% do orcamento de onda) durante uma fase intermediaria; aguardar disparo
da proxima onda; verificar que a pipeline continua na mesma fase, com
mesmas decisoes, sem regressao.

**Acceptance Scenarios**:

1. **Given** uma execucao na metade da fase `create-tasks`, **When** a onda
   corrente atinge qualquer threshold de orcamento, **Then** o orquestrador
   grava estado, faz commit local, agenda nova execucao via mecanismo
   herdado do runtime do agente-00c, e a onda encerra graciosamente.
2. **Given** estado serializado de uma execucao pausada, **When** uma nova
   onda dispara via `/feature-00c-resume`, **Then** o orquestrador valida
   o hash do estado, le o estado, reconstroi contexto a partir de artefatos
   em disco, e continua a partir da proxima instrucao registrada — sem
   perda de decisoes.
3. **Given** um arquivo de estado corrompido ou com schema desconhecido,
   **When** o orquestrador tenta retomar, **Then** detecta a corrupcao
   antes de qualquer acao, registra como bloqueio humano obrigatorio e
   gera relatorio parcial pedindo decisao.

---

### User Story 4 — Gatilhos de aborto graceful + abort manual com relatorio parcial (Priority: P4)

Quando o feature-00c entra em situacao insustentavel (loop em fase,
movimento circular, orcamento estourado, impossibilidade tecnica, desvio
de finalidade da feature original, bug impeditivo em skill global) ou o
operador decide interromper manualmente via `/feature-00c-abort`, o
orquestrador para imediatamente, gera relatorio parcial e libera a sessao.

**Why this priority**: gatilhos protegem P1 — sem eles, loop drena tokens
sem entregar relatorio. Mas como P1 ja garante relatorio mesmo em sucesso,
gatilhos sao a borda do contrato. Por isso P4. Abort manual entra junto
porque compartilha o caminho de saida graciosa.

**Independent Test**: induzir cada gatilho separadamente (forcar 6 ciclos
na mesma fase sem progresso, simular movimento circular fix-bug-fix-mesmo-bug,
estourar orcamento de onda); separadamente invocar `/feature-00c-abort`
durante execucao em andamento; verificar que o aborto dispara, relatorio
parcial e gerado em <60s, e o motivo aparece claro.

**Acceptance Scenarios**:

1. **Given** uma execucao no 5o ciclo da mesma fase sem progresso mensuravel
   (mesma definicao de "progresso mensuravel" do agente-00c), **When** o 6o
   ciclo iniciaria, **Then** o orquestrador aborta com motivo "tendencia
   a loop" e gera relatorio parcial.
2. **Given** uma execucao detectou padrao "fix bug A → bug B → fix B →
   bug A volta" via inspecao do historico de decisoes, **When** o padrao e
   confirmado, **Then** orquestrador aborta com motivo "movimento circular".
3. **Given** uma execucao em andamento, **When** operador invoca
   `/feature-00c-abort`, **Then** o comando le o estado corrente, marca
   como abortada com motivo "aborto manual", gera relatorio parcial e
   libera a sessao em <60s.
4. **Given** o orquestrador encontrou bug impeditivo em skill global,
   **When** confirma o bug pelos mesmos criterios do agente-00c, **Then**
   abre issue no GitHub do toolkit `JotJunior/cstk` com template
   estruturado, registra a issue no relatorio e aborta.

---

### User Story 5 — Coexistencia com agente-00c no mesmo projeto sem conflito (Priority: P5)

Um projeto pode ter sido criado via `/agente-00c` (orquestracao de projeto
inteiro). Apos a entrega inicial, novas features sao adicionadas via
`/feature-00c`. Ambos podem ter estado persistente em
`<projeto-alvo>/.claude/`, mas operam em namespaces de arquivo distintos
e em diferentes escopos. O sistema deve permitir essa coexistencia
explicitamente, recusando apenas execucoes concorrentes que se sobrepoem
(mesmo projeto + mesma feature, ou agente-00c ativo que ainda nao terminou
a feature-alvo).

**Why this priority**: a coexistencia e o caso comum de adocao incremental
(usuario primeiro experimenta agente-00c, depois quer estender features
sem rodar projeto-inteiro novamente). Mas a feature funciona sem essa
garantia explicita — bastaria proibir uso simultaneo. P5 transforma um
caso de uso desejavel em invariante validada.

**Independent Test**: em projeto que tem `agente-00c-state/` historico (execucao
encerrada), invocar `/feature-00c` para nova feature; verificar que a
execucao corre normalmente sem ler/modificar artefatos do agente-00c.
Separadamente: invocar `/feature-00c` em projeto com `agente-00c-state/`
indicando status `em_andamento` ou `aguardando_humano` — verificar que
e rejeitado com mensagem explicativa.

**Acceptance Scenarios**:

1. **Given** projeto com `agente-00c-state/` em estado terminal (concluida
   ou abortada), **When** operador invoca `/feature-00c "<nova feature>"`,
   **Then** a execucao inicia normalmente em namespace dedicado
   (`feature-00c-state/<short-name>/`), sem ler ou modificar
   `agente-00c-state/`.
2. **Given** projeto com `agente-00c-state/` indicando execucao ainda ativa
   (status `em_andamento` ou `aguardando_humano`), **When** operador invoca
   `/feature-00c`, **Then** a invocacao e rejeitada com mensagem
   identificando o conflito e instrucoes para resolver (aguardar termino,
   abortar via `/agente-00c-abort`, ou retomar via `/agente-00c-resume`).
3. **Given** duas invocacoes de `/feature-00c` no mesmo projeto mas com
   features distintas (short-names diferentes) executando em paralelo,
   **When** ambas correm em ondas concorrentes, **Then** cada uma opera
   em seu proprio diretorio de estado e relatorio, sem interferencia mutua.

---

### Edge Cases

- **`briefing.md` ausente ou stub no projeto-alvo**: invocacao rejeitada
  ANTES de criar `state.json` ou qualquer artefato, com diagnostico
  ("feature-00c requer projeto com briefing+constitution pre-existentes
  e validados; rode `/briefing` antes ou use `/agente-00c` para
  bootstrap"). Sem fallback automatico para `/briefing`.
- **`constitution.md` ausente, rascunho ou placeholder no projeto-alvo**:
  invocacao rejeitada ANTES de criar artefatos, com diagnostico
  equivalente apontando para `/constitution` ou `/agente-00c`. Inclui
  caso de constitution sem versao ratificada (`Version: (none)` ou
  ausencia de rodape).
- **Briefing/constitution modificados durante execucao pausada**: na
  retomada, hash registrado em FR-PRE-004 nao bate com hash atual em
  disco → bloqueio humano com pergunta ("artefatos-base alterados entre
  ondas, decisoes anteriores podem estar inconsistentes — re-validar e
  prosseguir, ou abortar?").
- **Constitution evoluiu MINOR entre ondas**: aviso obrigatorio registrado
  no relatorio identificando a versao anterior e a nova, sem aborto
  automatico — opcionalmente pergunta humana antes de retomar.
- **Constitution evoluiu MAJOR entre ondas**: bloqueio humano obrigatorio
  (principios podem ter mudado semanticamente e invalidar decisoes ja
  tomadas). Sem retomada silenciosa.
- **Briefing/constitution falham checagem semantica (FR-PRE-003)**:
  invocacao rejeitada com diagnostico apontando a secao/principio
  incompleto (linha + trecho com placeholder detectado).
- **Feature ja existe** (`docs/specs/<short-name>/spec.md` ja presente
  e nao-vazio): pergunta de bloqueio humano oferecendo (a) retomar a partir
  da spec existente (entra direto em clarify), (b) abortar a invocacao.
  Sem sobrescrita silenciosa.
- **Tentativa de spawnar tataraneto (4o nivel)**: falha explicita devolvida
  ao orquestrador, registrada como decisao "limite atingido" (mesmo limite
  do agente-00c).
- **Terceira retro-execucao na mesma feature**: bloqueio humano obrigatorio
  (orcamento herdado: 2 retros por feature).
- **6o ciclo na mesma fase sem progresso mensuravel**: aborto por
  "tendencia a loop" (User Story 4).
- **Movimento circular fix-bug-fix-mesmo-bug**: aborto por "movimento
  circular" (User Story 4).
- **Bug impeditivo em skill global**: aborto + issue (User Story 4).
- **Atingir threshold de onda (tool calls, wallclock, tamanho de estado)**:
  agendar proxima onda (nao aborta).
- **URL fora da whitelist**: bloqueio com pergunta "adicionar a whitelist
  e prosseguir, ou abortar?".
- **Skill local conflitando com skill global de mesmo nome**: skill local
  vence; conflito registrado no relatorio.
- **Operador interrompe manualmente via `/feature-00c-abort`**: orquestrador
  encerra tomada de acao corrente o mais rapido possivel, salva estado,
  gera relatorio parcial.
- **Diretorio do projeto-alvo movido/renomeado durante execucao**: retomada
  detecta path quebrado e dispara bloqueio humano (sem auto-correcao).
- **Multiplas execucoes `/feature-00c` para a MESMA feature no mesmo
  projeto**: rejeitada (lock por feature).
- **Multiplas execucoes `/feature-00c` para features DIFERENTES no mesmo
  projeto**: permitida (User Story 5, AC#3).
- **Tentativa de invocar `/feature-00c` enquanto `/agente-00c` esta ativo
  no mesmo projeto**: rejeitada (User Story 5, AC#2).
- **Disco sem espaco para escrever estado/backup/artefatos**: bloqueio
  humano com diagnostico (sem auto-cleanup).
- **Permissao de escrita negada em `<projeto-alvo>/.claude/`**: bloqueia
  na invocacao com diagnostico claro.
- **Constitution define MUSTs que a spec gerada viola**: enforcement
  runtime do pre-flight constitution-conflict (mesmo mecanismo ja existente
  no agente-00c, conforme commit e457dfa) — bloqueia avanco para `plan`
  ate resolver.

---

## Requirements

### Functional Requirements

**Invocacao e parametros**

- **FR-001**: Operador MUST poder invocar o orquestrador-de-feature via
  comando dedicado `/feature-00c` passando descricao curta da feature a
  ser construida. A invocacao MUST aceitar opcionalmente um short-name
  explicito (caso contrario, o orquestrador deriva conforme regras da
  skill `specify`).
- **FR-002**: A invocacao MUST aceitar opcionalmente uma whitelist de URLs
  externas adicionais (herdando contrato do agente-00c).
- **FR-003**: A invocacao MUST aceitar opcionalmente um path de projeto
  alvo distinto do diretorio corrente. Sem este parametro, projeto-alvo =
  diretorio corrente.

**Pre-requisitos do projeto-alvo (artefatos bypassados)**

> **Rationale**: bypassar `briefing` e `constitution` sem garantir
> presenca + qualidade transformaria `/feature-00c` em armadilha silenciosa
> — o clarify-answerer tomaria decisoes "no vacuo" (sem ancoragem em
> principios), gerando specs que violam a constitution e desperdicando
> ondas em retrabalho. Pre-requisitos explicitos e verificaveis transformam
> o bypass em delegacao consciente ("esses artefatos existem e foram
> validados") em vez de omissao silenciosa. Os FRs abaixo (PRE-001 ate
> PRE-004) sao bloqueantes — falha em qualquer um rejeita a invocacao
> ANTES de criar `state.json` ou qualquer artefato em disco.

- **FR-PRE-001 — Validacao de briefing**: Sistema MUST verificar, ANTES
  de iniciar a pipeline, a existencia de `docs/01-briefing-discovery/briefing.md`
  (ou caminho equivalente registrado no projeto-alvo) com conteudo
  nao-vazio e secoes minimas preenchidas: **visao**, **usuarios-alvo**,
  **restricoes**, **prioridades**. Ausencia, arquivo vazio, ou briefing
  reconhecivel como stub (somente headers sem corpo, ou corpo composto
  apenas por placeholders) = invocacao rejeitada com mensagem direcionando
  para `/briefing` ou `/agente-00c`.
- **FR-PRE-002 — Validacao de constitution**: Sistema MUST verificar a
  existencia de `docs/constitution.md` com pelo menos UM principio
  ratificado: versao >= `1.0.0` (extraida do rodape `**Version**: X.Y.Z`),
  presenca de bloco `## Core Principles` com ao menos um `### I.` (ou
  numeracao romana equivalente) definido com corpo nao-vazio. Ausencia
  ou constitution-placeholder (arquivo somente com template sem
  ratificacao) = invocacao rejeitada com mensagem direcionando para
  `/constitution` ou `/agente-00c`.
- **FR-PRE-003 — Qualidade dos artefatos bypassados**: Sistema MUST
  executar checagens semanticas minimas em ambos os artefatos antes de
  iniciar:
  - **briefing**: nenhuma das secoes minimas (FR-PRE-001) pode conter
    apenas placeholder textual reconhecivel (`[TBD]`, `[A definir]`,
    `[FILL]`, `TODO`, `...`, ou linha unica sem conteudo substantivo).
  - **constitution**: nenhum principio do bloco `## Core Principles` com
    corpo vazio ou somente placeholder; presenca obrigatoria do `Sync
    Impact Report` no topo (formato comentario HTML conforme padrao
    1.0.0+).
  - Falha em qualquer checagem = bloqueio com diagnostico apontando a
    secao/principio incompleto.
- **FR-PRE-004 — Registro de versoes consumidas**: Sistema MUST registrar
  no `state.json` da execucao, no momento da invocacao, os campos:
  - `briefing.path` e `briefing.sha256` (hash do arquivo validado);
  - `constitution.path`, `constitution.sha256` e `constitution.version`
    (string extraida do rodape `**Version**: X.Y.Z`).

  Decisoes do clarify-answerer MUST referenciar `constitution.version`
  no campo `referencias` quando a justificativa cita constitution.
  Mudanca em `briefing.sha256` ou `constitution.sha256` detectada na
  retomada de uma onda = bloqueio humano por divergencia (ver Edge
  Cases). Se a divergencia em constitution e MAJOR (mudanca de
  `version` no primeiro digito), bloqueio obrigatorio independente de
  intervencao; MINOR ou PATCH = aviso registrado no relatorio +
  pergunta opcional ao humano antes de prosseguir.
- **FR-006**: Sistema MUST detectar feature pre-existente
  (`docs/specs/<short-name>/spec.md` nao-vazio) e converter em bloqueio
  humano oferecendo retomar-a-partir-da-spec OU abortar. Sem sobrescrita
  silenciosa.

**Execucao da pipeline**

- **FR-007**: Sistema MUST executar EXATAMENTE as fases SDD na ordem:
  `specify → clarify → plan → checklist → create-tasks → execute-task
  (loop por task) → review-task`. As fases `briefing`, `constitution` e
  `review-features` estao FORA do escopo desta feature. `review-task`
  MUST ser invocada UMA UNICA VEZ ao final do loop completo de
  `execute-task` (sobre a feature inteira), nao apos cada subtask.
- **FR-008**: Sistema MUST invocar as skills correspondentes do toolkit via
  a tool `Skill` (espelhando o requisito ja vigente no agente-00c,
  registrado em memoria `feedback_agente00c_skills_obrigatorias`).
  Invocacao manual de fluxo equivalente sem `Skill` = violacao de Principio
  I e bloqueio.
- **FR-009**: Sistema MUST mediar a fase `clarify` usando dois subagentes
  distintos: `feature-00c-clarify-asker` (gera perguntas) e
  `feature-00c-clarify-answerer` (decide). Comunicacao mediada pelo
  orquestrador, nao direta. Estes subagentes PODEM reaproveitar a
  implementacao dos subagentes equivalentes do agente-00c por composicao
  (mesmo arquivo de prompt, parametrizado por scope) OU ser arquivos
  separados — a decisao tecnica fica para `/plan`.
- **FR-010**: Sistema MUST permitir retro-execucao (volta a fase anterior)
  quando detectar incoerencia entre artefatos, ate o limite herdado de 2
  retros por feature.
- **FR-010A — Pre-flight constitution-conflict (reuso do agente-00c)**:
  Sistema MUST invocar, na transicao `spec → plan` (ou seja, ao termino
  da fase `clarify` antes de iniciar `plan`), o MESMO check de
  pre-flight constitution-conflict ja implementado no runtime do
  agente-00c (commit `e457dfa`). O check compara requisitos da spec
  corrente contra MUSTs da `constitution.md` validada em FR-PRE-002 e
  bloqueia o avanco se detectar violacao. Reuso direto do runtime
  compartilhado e mandatorio — implementacao paralela esta proibida
  para evitar divergencia de comportamento entre `/agente-00c` e
  `/feature-00c`. Violacao detectada = bloqueio humano com diagnostico
  identificando o MUST violado e a clausula da spec conflitante.

**Persistencia e retomada**

- **FR-011**: Sistema MUST persistir estado de orquestracao em
  `<projeto-alvo>/.claude/feature-00c-state/<short-name>/state.json` ao
  final de cada onda. Namespace por short-name e mandatorio para suportar
  execucoes paralelas de features distintas no mesmo projeto (User Story
  5 AC#3).
- **FR-012**: Estado MUST conter, no minimo: schema_version, short_name,
  fase corrente, decisoes acumuladas, profundidade corrente de subagentes,
  retro-execucoes consumidas, ciclos consumidos por fase, lista de skills
  invocadas com timestamp (espelhando memoria
  `project_agente00c_skills_tracking`), proxima instrucao explicita,
  timestamp da onda corrente, os campos de FR-PRE-004
  (`briefing.path`, `briefing.sha256`, `constitution.path`,
  `constitution.sha256`, `constitution.version`), e — durante a fase
  `execute-task` — os campos granulares para retomada exata:
  `tasks_concluidas` (array de IDs de subtasks ja completadas),
  `task_corrente` (ID da subtask em andamento na onda corrente, ou
  `null` entre tasks). A presenca de `tasks_concluidas` impede
  re-execucao silenciosa de subtasks ja finalizadas em retomadas
  cross-onda.
- **FR-013**: Sistema MUST validar schema do estado antes de cada retomada
  e gerar **bloqueio humano** se o `schema_version` for invalido ou
  desconhecido (mesmo contrato do agente-00c; mesmo tratamento de
  FR-014 — divergencia entre artefatos persistidos vs esperados nao
  e auto-corrigida silenciosamente). Bloqueio inclui diagnostico com
  schema_version encontrado vs esperado + path do `state.json`.
- **FR-014**: Sistema MUST gravar, ao final de cada onda, hash SHA-256 do
  `state.json` em arquivo separado `state.json.sha256` no mesmo diretorio,
  e validar o hash no inicio da proxima onda. Divergencia = bloqueio
  humano com diagnostico "estado modificado externamente entre ondas".
- **FR-015**: Sistema MUST agendar continuacao automatica ao atingir
  qualquer threshold de proxy de consumo de sessao (tool calls da onda,
  wallclock da onda, tamanho de estado serializado), retornando intent
  de schedule ao slash command pai (mesmo padrao do agente-00c — sub-agentes
  nao invocam ScheduleWakeup diretamente).
- **FR-015A — Thresholds de onda (reuso do agente-00c)**: Os valores
  numericos dos thresholds de FR-015 (tool calls, wallclock, tamanho de
  estado) MUST ser identicos aos definidos em
  `docs/specs/_archived/agente-00c/research.md` §Decision 2 (mesmo runtime,
  mesma calibracao). Decisao consciente declarada nesta spec — NAO
  delegar para descoberta posterior em `/plan` ou `execute-task`.
  Mudancas futuras nesses thresholds requerem atualizacao SINCRONIZADA
  em ambos os specs (00c e feature-00c) para evitar drift de
  comportamento entre os orquestradores.
- **FR-016**: Operador MUST poder retomar execucao pausada via
  `/feature-00c-resume <short-name>` com argumento opcional
  `--resposta-bloqueio` para responder pergunta humana pendente. O comando
  MUST validar hash de estado antes de prosseguir.

**Auditabilidade**

- **FR-017**: Sistema MUST registrar cada decisao com os mesmos 5 campos
  obrigatorios do agente-00c (contexto/fase, opcoes consideradas, escolha
  feita, justificativa, agente responsavel) mais campos auxiliares
  (timestamp obrigatorio; score_justificativa obrigatorio para decisoes
  do clarify-answerer; referencias >=1 quando cita briefing/constitution/spec;
  artefato_originador quando aplicavel). Decisao com qualquer obrigatorio
  faltando = violacao de Principio I e bloqueio.
- **FR-018**: Sistema MUST gerar relatorio final em
  `<projeto-alvo>/.claude/feature-00c-state/<short-name>/feature-00c-report.md`
  ao termino de qualquer execucao (sucesso, aborto, pausa por bloqueio
  humano), contendo as 6 secoes obrigatorias na ordem do agente-00c:
  (1) Resumo Executivo, (2) Linha do Tempo, (3) Decisoes, (4) Bloqueios
  Humanos, (5) Sugestoes para Skills Globais, (6) Licoes Aprendidas.
  O CONTEUDO DETALHADO de cada secao MUST ser definido em
  `docs/specs/feature-00c/contracts/report-format.md` (gerado pela
  fase `/plan` deste mesmo escopo, espelhando o padrao do agente-00c
  que ja possui `docs/specs/_archived/agente-00c/contracts/report-format.md`).
  A spec define APENAS o contrato externo (nomes e ordem das secoes);
  o contrato interno e responsabilidade do plan.
- **FR-019**: Sistema MUST emitir relatorio parcial em ate 60 segundos
  apos disparo de gatilho de aborto.
- **FR-020**: Sistema MUST registrar a lista de skills invocadas em cada
  onda no campo `.ondas[N].skills_invoked` do estado, auditavel
  posteriormente via `review-task` (espelhando memoria
  `project_agente00c_skills_tracking`).

**Autonomia limitada e gatilhos**

- **FR-021**: Sistema MUST limitar profundidade de subagentes a 3 niveis
  (orquestrador raiz = nivel 0; bisneto = nivel 3; tataraneto = invariante
  violada). Mesma definicao do agente-00c.
- **FR-022**: Sistema MUST abortar execucao quando detectar: (a) 6o ciclo
  na mesma fase sem progresso mensuravel; (b) movimento circular;
  (c) impossibilidade tecnica; (d) desvio de finalidade da feature
  (definido como 5 ondas consecutivas sem tocar aspectos-chave extraidos
  da `descricao_curta` original — mesmo mecanismo do FR-027 do agente-00c);
  (e) bug impeditivo em skill global.

  **Definicao de "progresso mensuravel"** (cross-reference): a definicao
  completa (4 criterios: novo artefato gerado, mudanca em artefato
  pre-existente, nova decisao registrada, teste/lint com mudanca de exit
  code) e a mesma vigente em `docs/specs/_archived/agente-00c/spec.md` §FR-014.
  Cross-reference auditavel aceita — implementacao MUST consultar essa
  definicao canonica. Mudanca na definicao requer atualizacao em ambos
  os specs.

  **Definicao de "bug impeditivo em skill global"** (cross-reference):
  ver `docs/specs/_archived/agente-00c/spec.md` §FR-014 (mesma definicao canonica).
- **FR-023**: Sistema MUST converter clarify nao-decidivel pelo answerer
  (sem justificativa em briefing/constitution/spec/decisao-anterior) em
  bloqueio humano, pausando a pipeline.
- **FR-024**: Ao entrar em bloqueio humano no meio de uma onda, sistema
  MUST finalizar a onda graciosamente: gerar relatorio parcial, persistir
  estado com status "aguardando humano" + pergunta + contexto, fazer
  commit local e liberar sessao.

**Operacao manual**

- **FR-025**: Operador MUST poder abortar manualmente via
  `/feature-00c-abort <short-name>`. Comando le o estado, marca como
  abortada (motivo "aborto manual"), gera relatorio parcial e libera
  sessao. Idempotente — execucao ja em status terminal apenas reporta.

  **Tratamento de race com onda corrente**: se onda esta ativa no
  momento do abort (lock detentor identificavel via PID em `.lock`),
  o abort MUST:
  1. Enviar SIGTERM ao processo da onda;
  2. Aguardar grace period de ate 60 segundos para a onda persistir
     `state.json` + gerar backup parcial + liberar lock graciosamente;
  3. Apenas apos o grace period (ou apos o lock ser liberado, o que
     vier primeiro), executar force-acquire do lock;
  4. Marcar status=abortada com `motivo_termino="aborto manual"` +
     gerar relatorio parcial conforme FR-019.

  Razao: force-acquire imediato pode deixar state.json em meio de
  escrita (corrupcao parcial). SIGTERM + grace da chance da onda
  encerrar limpa. Se o processo nao responde ao SIGTERM no grace
  period, force-acquire dispara como fallback.

**Coexistencia com agente-00c**

- **FR-026**: Sistema MUST rejeitar invocacao de `/feature-00c` quando
  detectar `agente-00c-state/state.json` em status `em_andamento` ou
  `aguardando_humano` no mesmo projeto. Diagnostico MUST apontar para
  `/agente-00c-abort` ou `/agente-00c-resume`.
- **FR-027**: Sistema MUST operar em namespace de arquivo distinto
  (`feature-00c-state/<short-name>/`) sem ler ou modificar artefatos em
  `agente-00c-state/`, e vice-versa. Skills compartilhadas (lib runtime)
  sao acessadas read-only.
- **FR-028**: Sistema MUST rejeitar invocacao concorrente de `/feature-00c`
  para a MESMA `<short-name>` no mesmo projeto via lock de arquivo
  (`feature-00c-state/<short-name>/.lock`). Invocacoes para short-names
  distintos no mesmo projeto sao permitidas.

**Heranca de seguranca do agente-00c**

- **FR-029**: Sistema MUST herdar TODOS os requisitos de seguranca do
  agente-00c aplicaveis ao escopo de feature: resolucao de simlinks +
  validacao de zonas proibidas (equivalente FR-024 do 00c); limite de 500
  chars em descricao_curta + sanitizacao contra injecao em Bash/git/issue
  (equivalente FR-025); tratamento de texto em artefatos como conteudo
  nao instrucao (equivalente FR-026); extracao de aspectos-chave para
  drift detection (equivalente FR-027 — ver definicao canonica em
  `docs/specs/_archived/agente-00c/spec.md` §FR-027 para "aspectos-chave
  normalizados"); bloqueio de comandos Bash que invoquem `sudo` ou
  package managers de host (equivalente FR-028); hash SHA-256 do estado
  entre ondas (equivalente FR-029, ja em FR-014); filtro de secrets na
  saida (equivalente FR-030); whitelist robusta rejeitando padroes
  excessivamente amplos (equivalente FR-031).

  **Escopo do filtro de secrets (FR-030 estendido)**: o filtro MUST
  aplicar tambem aos arquivos de backup gerados por FR-034
  (`backups/wave-NNN.json`), nao apenas a report.md / suggestions.md /
  issue body. Razao: backups por onda contem snapshot completo do state,
  incluindo decisoes com texto da spec — secrets potencialmente
  presentes. Implementacao: pre-processar `state.json` aplicando o filtro
  ANTES de gravar o backup, mantendo o `state.json` operacional
  inalterado (sem afetar hash de FR-014).

  **Comportamento em casos ambiguos (fail-safe default)**: o filtro
  MUST adotar postura **fail-safe** — quando um padrao casa parcialmente
  ou ha ambiguidade sobre se a string e um secret legitimo ou um
  identificador inofensivo (commit SHA, UUID, hash de arquivo), o
  default e REDACT. Privacidade > usabilidade. Razao: falso positivo
  (commit SHA virando `[REDACTED]` em report.md) e custo aceito
  (reviewer pode consultar git log); falso negativo (token vazando em
  artefato auditavel) e custo nao-aceito. Excecoes via whitelist
  contextual sao OUT-OF-SCOPE neste MVP (podem ser adicionadas como
  amendment futuro se relatorios ficarem ilegiveis por excesso de
  redact).
- **FR-030**: Sistema MUST restringir escrita em disco ao diretorio do
  projeto-alvo e seus subdiretorios. Skills globais permanecem read-only.
- **FR-031**: Sistema MUST nunca executar `sudo`, `git push`, deploy
  externo, ou comunicacao com URLs nao-whitelisted. Package managers
  somente dentro de container docker do projeto-alvo.
- **FR-035 — `gh issue create` como unica excecao externa**: Sistema
  MUST tratar `gh issue create` em `JotJunior/cstk` como a
  **UNICA** excecao a FR-031 ("zero comunicacao externa"). A excecao
  e disciplinada por TRES restricoes cumulativas:
  1. **Trigger**: apenas quando uma sugestao para skill global e
     classificada como severidade=`impeditiva` (Key Entities §Sugestao).
     Sugestoes `informativa` ou `aviso` NAO abrem issue.
  2. **Conteudo filtrado**: corpo da issue MUST passar por
     `secrets-filter.sh` ANTES do POST. Sem upload de
     `state.json`, `feature-00c-report.md`, `backups/`, ou qualquer
     arquivo do projeto-alvo. Apenas o template estruturado
     (skill afetada, diagnostico filtrado, proposta filtrada, link
     LOCAL ao relatorio — nao upload).
  3. **Repositorio fixo**: apenas `JotJunior/cstk`. Tentar
     abrir issue em qualquer outro repo = violacao de blast radius
     e bloqueio.

  Qualquer outra forma de comunicacao externa (HTTP fetch, npm publish,
  docker push, etc) permanece proibida sem excecao.
- **FR-036 — Filtro de secrets em outputs runtime (stderr/stdout)**:
  Sistema MUST aplicar o filtro de secrets (FR-029 §Escopo + fail-safe
  default) a **TODOS** os outputs emitidos pelo orquestrador e seus
  subagentes, nao apenas a arquivos persistidos. Inclui:
  - `stderr` (mensagens de erro, warnings, diagnosticos)
  - `stdout` (output transient para o harness do Claude Code)
  - Logs intermediarios (se introduzidos futuramente)

  Razao: state.json contem secrets potenciais (decisoes com texto da
  spec). Sem filtro em stderr, um traceback de erro pode vazar token
  em diagnostico para o operador via transcript do Claude Code. O
  filtro deve ser aplicado **antes** da emissao (nao post-hoc), via
  wrapper de print/echo nos scripts POSIX.

**Decisoes de Infraestrutura Auditaveis**

- **FR-032-INFRA-SCHED**: Politica de scheduling entre ondas = `wakeup`
  (intent de schedule retornado ao slash command pai, que invoca
  `ScheduleWakeup` — sub-agentes nao podem invocar de forma sobrevivente).
  Default herdado do contrato ja vigente no agente-00c-orchestrator.
- **FR-033-INFRA-LOCK**: Serializacao cross-pod nao se aplica (execucao
  local single-user). Mutex entre invocacoes concorrentes para mesma
  feature usa lock-file no filesystem
  (`feature-00c-state/<short-name>/.lock`), conforme FR-028. Sem
  dependencia de PostgreSQL/Redis.
- **FR-034-INFRA-BACKUP**: Sistema MUST gravar snapshot do `state.json`
  ao final de CADA onda em
  `feature-00c-state/<short-name>/backups/wave-NNN.json` (numeracao
  monotona crescente, sem rotacao automatica). Audit perfeito da
  execucao — todas as ondas ficam reconstruiveis post-mortem. O custo
  de disco e aceito explicitamente como tradeoff de auditabilidade.
  Limpeza so ocorre na exclusao manual da feature ou via
  `/feature-00c-abort --purge-backups` (parametro opcional). Hash
  SHA-256 de cada backup MUST ser registrado no proprio arquivo de
  backup (campo `state_sha256_self`) para detectar corrupcao
  retroativa.

### Key Entities

- **Execucao-de-feature**: instancia de pipeline `/feature-00c` com
  identificador estavel, projeto-alvo, short-name da feature, status
  (em_andamento, aguardando_humano, abortada, concluida), timestamp de
  inicio, timestamp de termino, motivo de termino.
- **Onda**: unidade de execucao dentro de uma sessao. Tem inicio, fim,
  consumo medido, lista de decisoes tomadas, fase em que estava,
  `skills_invoked`, proxima instrucao serializada.
- **Estado de orquestracao**: snapshot persistido entre ondas em
  `feature-00c-state/<short-name>/state.json`. Contem schema_version,
  short_name, execucao corrente, fase, decisoes acumuladas, orcamentos
  consumidos, profundidade corrente, retro-execucoes consumidas,
  skills_invoked acumuladas, proxima instrucao.
- **Decisao**: unidade audit-relevante com 5 campos obrigatorios (mesmo
  contrato do agente-00c).
- **Bloqueio humano**: tipo especial de decisao que paralisa a pipeline.
  Tem pergunta + contexto suficiente para resposta sem releitura.
- **Relatorio**: artefato em `feature-00c-state/<short-name>/feature-00c-report.md`.
- **Sugestao para skill global**: registro em
  `<projeto-alvo>/.claude/feature-00c-suggestions.md` (compartilhado entre
  execucoes de features distintas no mesmo projeto, append-only).
- **Issue no toolkit**: criada automaticamente apenas quando severidade =
  impeditiva (mesmo template estruturado do agente-00c).

---

## Success Criteria

### Measurable Outcomes

- **SC-001**: 100% das execucoes (concluidas, abortadas ou pausadas)
  produzem relatorio em
  `<projeto-alvo>/.claude/feature-00c-state/<short-name>/feature-00c-report.md`
  com todas as 6 secoes obrigatorias preenchidas.
- **SC-002**: Pelo menos 95% das decisoes registradas no relatorio
  possuem os 5 campos completos. Decisoes com campo faltando sao
  detectaveis por inspecao automatizada.
- **SC-003**: Apos interrupcao forcada (clear de contexto, sessao
  expirada, schedule disparando nova onda), 100% das execucoes retomadas
  continuam na mesma fase em que pararam, com decisoes anteriores
  preservadas e hash validado.
- **SC-004**: Nenhuma execucao excede os orcamentos cravados (3 niveis
  de recursao, 2 retro-execucoes por feature, 5 ciclos por fase,
  thresholds de onda) sem ter disparado aborto graceful ou agendamento.
- **SC-005**: Tempo entre disparo de gatilho de aborto e relatorio
  parcial salvo em disco e inferior a 60 segundos em pelo menos 95% das
  ocorrencias.
- **SC-006**: Um leitor humano consegue reproduzir mentalmente todas as
  decisoes da execucao usando exclusivamente o relatorio, sem precisar
  consultar logs externos ou contexto da sessao. Verificavel por revisao
  manual em amostragem.
- **SC-007**: Toda decisao do `feature-00c-clarify-answerer` e justificada
  por referencia explicita a briefing, constitution, spec corrente ou
  decisao anterior — nunca por "pareceu razoavel" ou texto generico.
  Verificavel por inspecao da secao "Decisoes" do relatorio.
- **SC-008**: Invocacao com `briefing.md` ou `constitution.md` ausente
  resulta em rejeicao com diagnostico acionavel em 100% das tentativas.
- **SC-PRE-001**: 100% das invocacoes com briefing ou constitution
  ausentes, incompletos, ou falhando checagem semantica (FR-PRE-001 a
  FR-PRE-003) sao rejeitadas ANTES de criar `state.json` ou qualquer
  artefato em disco. Verificavel inspecionando filesystem apos
  invocacao rejeitada — nenhum arquivo novo em
  `<projeto-alvo>/.claude/feature-00c-state/`.
- **SC-PRE-002**: 100% das execucoes registram, no momento da invocacao,
  `briefing.sha256`, `constitution.sha256` e `constitution.version` no
  `state.json`, verificavel por inspecao automatizada do estado. 100%
  das retomadas validam esses hashes contra os arquivos em disco e
  bloqueiam em caso de divergencia (MAJOR = bloqueio compulsorio; MINOR/
  PATCH = aviso + pergunta opcional).
- **SC-009**: Invocacao concorrente para a MESMA feature no mesmo
  projeto resulta em rejeicao em 100% das tentativas. Invocacao
  concorrente para features DIFERENTES no mesmo projeto sucede sem
  interferencia em 100% das tentativas (medida sobre cenario de teste
  controlado).
- **SC-010**: Invocacao com `agente-00c` ativo (status `em_andamento` ou
  `aguardando_humano`) no mesmo projeto resulta em rejeicao em 100% das
  tentativas, com diagnostico apontando comandos de resolucao.
- **SC-011**: Bug impeditivo em skill global resulta em issue no toolkit
  com template estruturado em 100% dos casos confirmados, antes do
  aborto.
- **SC-012**: Uso de `/feature-00c` em projeto previamente bootstrapado
  via `/agente-00c` nao requer migracao manual de artefatos nem
  modificacao de `agente-00c-state/` — verificavel comparando snapshot
  do diretorio `.claude/` antes e depois (somente novos arquivos sob
  `feature-00c-state/`).
