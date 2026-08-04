# Feature Specification: Fundação state.db

**Feature**: `state-db-foundation`
**Created**: 2026-07-30
**Status**: Draft

## Contexto

Hoje o estado transacional de uma execução autônoma 00c (agente-00c ou
feature-00c) vive inteiro num único arquivo `state.json` por projeto,
escrito por uma família de scripts POSIX via leitura-modificação-escrita
(RMW) protegida por um lock de diretório não-reentrante. Esse mecanismo é
rigoroso onde há regra determinística de script, mas frágil exatamente na
fronteira em que um agente autônomo *declara* um resultado (ex.: "task
concluída", "onda fechada") que o script então persiste como fato, sem
verificação estrutural equivalente a uma constraint de banco de dados.

Esta feature é a **Fase 1 (fundação)** de uma linha de evolução maior: um
banco `state.db` (SQLite) por projeto substitui o `state.json` como fonte
de verdade transacional. Fases futuras (servidor de acesso tipado,
inversão de verificação, telemetria ao vivo) estão **fora de escopo**
deste documento.

## Clarifications

### Session 2026-07-30

- Q: Como reconciliar o uso obrigatório de `sqlite3` pelo `state.db` com o
  Princípio II (POSIX puro) da constitution? → A: `sqlite3` passa a ser
  reconhecido como dependência obrigatória da camada de estado
  transacional via **amendment dedicado da constitution** (MINOR bump),
  distinto do carve-out opcional 1.1.0 — sem exigência de fallback
  POSIX-puro para esta camada específica. **Dependência externa a esta
  feature**: o amendment da constitution está fora do escopo do pipeline
  `feature-00c` (que não inclui a etapa `constitution`) e precisa ser
  conduzido separadamente antes de `plan` assumir `sqlite3` como
  mandatório sem ressalva.
- Q: A migração de um projeto existente para `state.db` deve ser
  automática/transparente na próxima invocação do orquestrador, ou exigir
  comando explícito do operador? → A: **Explícita via comando dedicado do
  operador**, executada apenas fora de uma execução ativa (nunca sobre um
  projeto com `status=em_andamento`).
- Q: O backup por onda fechada deve continuar sendo um snapshot
  serializado ou usar mecanismo nativo do SQLite? → A: **Continuar
  gerando snapshot em `state-history/` por onda fechada**, agora
  serializado a partir do `state.db` reaproveitando o export já exigido
  por FR-007 — sem introduzir mecanismo de backup novo.
- Q: Quando `state.json` e `state.db` coexistem no mesmo projeto, o que
  determina qual é a fonte de verdade corrente? → A: **A presença de
  `state.db` com migração verificada (FR-006 concluída) sempre vence** —
  um `state.json` remanescente passa a ser tratado como export/legado,
  nunca como fonte independente.
- Q: Qual mecanismo de concorrência do `state.db` substitui/complementa o
  lock de diretório atual para serializar escritores e permitir leitores
  concorrentes sem bloqueio (FR-011)? → **A: WAL mode nativo do SQLite**
  (`PRAGMA journal_mode=WAL`) resolve FR-011 diretamente — passa a ser o
  mecanismo primário de concorrência do `state.db`, liberando leitores
  durante uma escrita em andamento sem bloqueio nem leitura parcial. O
  lock de diretório hoje vigente deixa de ser o único serializador entre
  orquestradores; é **mantido apenas como camada extra opcional**,
  acionável quando se justificar por melhoria de robustez/segurança
  adicional (ex.: coordenação cross-processo além do que o WAL cobre
  sozinho), nunca como requisito para leitores nem como mecanismo
  primário de FR-011. Resolução do bloqueio `block-001` — decisão
  registrada em `dec-014` (respondida pelo operador em 2026-07-30).

## User Scenarios & Testing

### User Story 1 - Persistência íntegra e atômica das mutações de estado (Priority: P1)

Como orquestrador autônomo (agente-00c ou feature-00c) executando uma
onda, preciso que cada mutação de estado — abrir/fechar uma onda,
registrar uma decisão, registrar um bloqueio humano, registrar o
resultado de uma task, registrar a invocação de uma skill/gate, entrar ou
sair de um nível de subagente — seja aplicada de forma atômica e com as
mesmas invariantes de integridade hoje garantidas por convenção nos
scripts (nunca duas ondas abertas simultaneamente, todo bloqueio humano
referenciando uma decisão existente, profundidade de subagente nunca
excedendo o teto configurado), mesmo que uma mutação seja interrompida no
meio (crash, timeout, sinal).

**Why this priority**: é o núcleo da fundação — sem persistência íntegra
e atômica, nenhuma das fases seguintes (migração, export, ingestão) tem
uma base confiável para se apoiar. Resolve a fragilidade central
identificada no runtime atual (race de leitura-modificação-escrita,
`start` de onda não-idempotente, invariantes checadas só por prosa).

**Independent Test**: criar um projeto novo (sem `state.json` prévio),
inicializar uma execução, e exercitar cada primitiva de escrita (abrir
onda, registrar decisão, registrar bloqueio, registrar task, registrar
skill, entrar/sair de spawn) — inclusive disparando duas tentativas
concorrentes da mesma mutação (ex.: duas tentativas de abrir a mesma
onda) — e verificar que o estado final é íntegro e que a mutação
duplicada é rejeitada ou idempotente, nunca corrompe o registro existente.

**Acceptance Scenarios**:

1. **Given** uma execução recém-iniciada sem nenhuma onda aberta,
   **When** o orquestrador abre uma onda,
   **Then** exatamente uma onda fica registrada como aberta e uma
   segunda tentativa de abrir onda antes de fechar a primeira é
   rejeitada ou tratada como no-op, nunca cria uma segunda onda aberta.
2. **Given** uma decisão sendo registrada sem um dos seis campos
   obrigatórios (agente, etapa, contexto, opções consideradas, escolha,
   justificativa),
   **Then** o registro é rejeitado antes de ser persistido — a
   invariante de auditabilidade é garantida pela própria camada de
   armazenamento, não apenas pelo script chamador.
3. **Given** duas mutações concorrentes tentando escrever no mesmo
   projeto ao mesmo tempo (ex.: registrar decisão e fechar onda em
   paralelo),
   **When** ambas são submetidas,
   **Then** nenhuma atualização é perdida — cada mutação aplica
   integralmente ou não aplica nada, e o estado final reflete as duas
   mudanças.
4. **Given** um bloqueio humano sendo registrado referenciando um ID de
   decisão que não existe,
   **Then** o registro é rejeitado (a referência é validada na
   persistência, não só na convenção de quem chama).

---

### User Story 2 - Migração de execuções existentes sem perda de auditoria (Priority: P2)

Como operador do toolkit, preciso converter uma execução existente
(`state.json` no formato atual) para `state.db`, preservando **100%**
dos registros de auditoria — cada decisão, onda, task, evento, bloqueio
humano e invocação de skill/gate, com seus identificadores e timestamps
originais intactos — para que nenhuma execução em andamento ou já
concluída perca histórico ao adotar o novo mecanismo.

**Why this priority**: sem uma rota de migração, a fundação fica
inutilizável em qualquer projeto que já tenha execuções — que é o caso
comum. Depende da User Story 1 (o destino da migração precisa já
existir e ser íntegro).

**Independent Test**: pegar um `state.json` real (de uma execução
concluída ou em andamento), rodar a migração, e comparar campo-a-campo
cada registro do resultado contra o original — sem depender de nenhuma
outra capacidade da feature (export ou ingestão).

**Acceptance Scenarios**:

1. **Given** um `state.json` existente com N decisões, M ondas, K tasks,
   J eventos e L bloqueios humanos,
   **When** a migração é executada,
   **Then** o `state.db` resultante contém exatamente N decisões, M
   ondas, K tasks, J eventos e L bloqueios humanos, cada um com os
   mesmos identificadores, timestamps e conteúdo do original.
2. **Given** uma migração concluída com sucesso,
   **When** a mesma migração é executada novamente sobre o mesmo
   projeto,
   **Then** nenhum dado é duplicado ou corrompido (a operação é
   idempotente).
3. **Given** um `state.json` que falha na validação de schema/invariantes
   hoje aplicada (ex.: bloqueio humano referenciando decisão
   inexistente),
   **When** a migração é tentada,
   **Then** a migração é recusada com diagnóstico claro apontando o
   registro problemático, em vez de migrar dados inconsistentes.
4. **Given** uma migração interrompida no meio (processo morto,
   máquina reiniciada),
   **When** o operador inspeciona o projeto,
   **Then** o projeto continua operável com o `state.json` original
   intacto (a migração não deixa o projeto num estado sem fonte de
   verdade válida).

---

### User Story 3 - Compatibilidade retroativa via export derivado (Priority: P3)

Como consumidor já existente do `state.json` (o painel cstk-panel e o
hook de ingestão do knowledge.db), preciso continuar lendo um
`state.json` estruturalmente equivalente ao de hoje, gerado a partir do
`state.db`, para continuar funcionando sem precisar ser reescrito durante
o período de transição.

**Why this priority**: protege os consumidores existentes contra ruptura
imediata, mas só faz sentido depois que existe uma fonte (`state.db`,
User Story 1) e dados migrados (User Story 2) para exportar.

**Independent Test**: gerar o export de um projeto já em `state.db` e
verificar que um consumidor existente (ex.: o próprio `state-validate.sh`
usado hoje para validar `state.json`) aceita o resultado sem alterações.

**Acceptance Scenarios**:

1. **Given** um projeto operando em `state.db`,
   **When** o export é gerado,
   **Then** o `state.json` resultante passa na validação de schema e
   invariantes hoje aplicada a um `state.json` nativo.
2. **Given** uma nova mutação de estado aplicada ao `state.db` (ex.:
   nova decisão registrada),
   **When** o export é regenerado,
   **Then** o `state.json` exportado reflete a nova mutação.
3. **Given** um consumidor que só sabe ler `state.json` (ex.: um script
   de auditoria de terceiros ainda não adaptado),
   **When** ele lê o export derivado,
   **Then** ele não percebe diferença estrutural em relação a um
   `state.json` escrito diretamente pelo mecanismo atual.

---

### User Story 4 - Ingestão do knowledge.db direto do state.db (Priority: P4)

Como mantenedor da memória cross-feature (`knowledge.db` global), preciso
que a ingestão leia diretamente do `state.db` de cada projeto via SQL, em
vez de reconstruir os mesmos dados a partir do `state.json` exportado
usando `jq` e `sqlite3` em shell script, para eliminar uma camada de
serialização/desserialização redundante e reduzir a superfície de
divergência entre os dois formatos.

**Why this priority**: é uma otimização/simplificação do mecanismo de
ingestão que só faz sentido depois que `state.db` é a fonte de verdade
confiável (User Story 1) — é a story de menor risco/urgência, adiável sem
bloquear a adoção da fundação.

**Independent Test**: rodar a ingestão de um projeto em `state.db` e
comparar o resultado no `knowledge.db` contra o resultado da ingestão do
mecanismo atual (via `state.json` exportado do mesmo projeto) — as
entidades resultantes (decisões, ondas, tasks, eventos, bloqueios,
skills) devem ser equivalentes.

**Acceptance Scenarios**:

1. **Given** um projeto com `state.db` populado,
   **When** a ingestão do knowledge.db é executada para esse projeto,
   **Then** as mesmas entidades (decisões, ondas, tasks, eventos,
   bloqueios, skills invocadas) aparecem no knowledge.db, com a mesma
   proveniência (projeto/feature/onda/data) que a ingestão via
   `state.json` produziria.
2. **Given** um projeto ainda não migrado (só `state.json`),
   **When** a ingestão é executada,
   **Then** o mecanismo atual (via JSON) continua funcionando sem
   alteração — a ingestão SQL-para-SQL é aditiva, não substitui o
   caminho legado enquanto ele for necessário.
3. **Given** a ingestão SQL-para-SQL de um projeto,
   **When** ela é executada,
   **Then** o `knowledge.db` global permanece o único banco agregado,
   derivado e somente-leitura do ponto de vista dos projetos — nenhum
   projeto grava diretamente nele.

---

### Edge Cases

- O que acontece quando um projeto tem `state.json` **e** `state.db`
  presentes simultaneamente (migração interrompida ou reexecutada)? A
  presença de `state.db` com migração verificada (FR-006 concluída)
  sempre vence como fonte de verdade; um `state.json` remanescente é
  tratado como export/legado, nunca como fonte independente (ver
  Clarifications, Session 2026-07-30).
- O que acontece quando duas instâncias de orquestrador (ex.: agente-00c
  e feature-00c) tentam escrever no mesmo `state.db` ao mesmo tempo? WAL
  mode nativo do SQLite (`PRAGMA journal_mode=WAL`) serializa escritores
  automaticamente e libera leitores concorrentes sem bloqueio — resolvido
  via `block-001` (ver Clarifications, Session 2026-07-30). O lock de
  diretório hoje vigente deixa de ser o serializador exigido; pode ser
  mantido como camada extra opcional se uma necessidade concreta de
  robustez/segurança adicional justificar, mas não é requisito desta
  feature.
- O que acontece quando a geração do export falha (ex.: disco cheio,
  processo interrompido) no meio do fechamento de uma onda? O
  fechamento da onda no `state.db` não pode ficar condicionado ao
  sucesso do export — a falha de export degrada, não bloqueia a fonte
  de verdade.
- O que acontece quando a migração é tentada sobre um `state.json` que já
  está corrompido ou com hash de integridade divergente? A migração deve
  recusar e reportar, nunca "consertar" silenciosamente dados suspeitos.
- O que acontece com os backups por onda que hoje existem
  (`state-history/`) depois da migração — eles continuam sendo gerados,
  agora a partir do `state.db`, ou são substituídos por um mecanismo de
  backup nativo do banco?
- O que acontece quando a ingestão do knowledge.db roda enquanto o
  `state.db` do projeto está no meio de uma transação de escrita? A
  ingestão deve enxergar um estado consistente (a última transação
  concluída), nunca uma leitura parcial de uma transação em andamento.

## Requirements

### Functional Requirements

- **FR-001**: System MUST persistir todo o estado transacional de uma
  execução 00c (ondas, decisões, tasks, eventos, bloqueios humanos,
  invocações de skill/gate, uso de spawn de subagente) num banco de
  dados relacional por projeto (`state.db`), em vez de um único arquivo
  JSON.
- **FR-002**: System MUST impedir, na própria camada de armazenamento,
  os estados inválidos que hoje dependem só de convenção de script — no
  mínimo: duas ondas abertas simultaneamente, uma onda fechada mais de
  uma vez, uma decisão sem os seis campos obrigatórios de auditoria
  (agente, etapa, contexto, opções consideradas, escolha, justificativa),
  um bloqueio humano referenciando uma decisão inexistente, e
  profundidade de subagente excedendo o teto configurado.
- **FR-003**: System MUST aplicar cada mutação individual de estado
  (abrir/fechar onda, registrar decisão, registrar bloqueio, registrar
  resultado de task, registrar invocação de skill/gate, entrar/sair de
  spawn) de forma atômica — a mutação aplica integralmente ou não deixa
  rastro parcial, mesmo sob acesso concorrente ou interrupção no meio.
- **FR-004**: System MUST expor primitivas de acesso cobrindo os mesmos
  verbos que os orquestradores usam hoje em todo caminho de escrita:
  inicializar execução (projeto ou feature), ler um campo, atualizar um
  campo, registrar decisão, abrir/fechar onda, registrar invocação de
  skill/gate, registrar resultado de task, registrar/listar/contar/
  responder bloqueio humano, entrar/checar/sair de profundidade de
  spawn.
- **FR-005**: System MUST prover uma operação de migração que converte um
  `state.json` existente (formato atual) para `state.db`, preservando
  cada registro (decisões, ondas, tasks, eventos, bloqueios humanos,
  invocações de skill) com seus identificadores e timestamps originais,
  sem perda nem reordenação do rastro de auditoria. A migração MUST ser
  disparada apenas por comando explícito do operador, nunca automática
  ou transparente numa invocação do orquestrador — e MUST recusar rodar
  sobre um projeto com execução ativa (`status=em_andamento`), exigindo
  que a execução seja concluída, abortada ou pausada antes da conversão
  (ver Clarifications, Session 2026-07-30).
- **FR-006**: System MUST verificar, imediatamente após a migração, que
  nenhum dado foi perdido ou alterado (contagem de registros e
  correspondência campo-a-campo entre origem e destino) e MUST recusar
  considerar a migração concluída se essa verificação falhar.
- **FR-007**: System MUST gerar, a partir do `state.db`, um export
  equivalente ao `state.json` de hoje, estruturalmente compatível com os
  consumidores atuais (painel, ingestão do knowledge.db), para que esses
  consumidores continuem funcionando sem reescrita durante a transição.
- **FR-008**: System MUST permitir que o processo de ingestão do
  knowledge.db leia diretamente do `state.db` de um projeto (não do JSON
  exportado) para popular as mesmas entidades de conhecimento que popula
  hoje.
- **FR-009**: System MUST preservar a separação de responsabilidade já
  vigente do knowledge.db global — ele continua único, independente de
  projeto, derivado e somente-leitura; esta feature muda apenas o
  mecanismo pelo qual ele é populado (SQL a partir do `state.db`), nunca
  seu escopo, propriedade ou modelo de acesso de escrita.
- **FR-010**: System MUST continuar oferecendo uma operação de
  verificação de integridade equivalente à checagem de hash usada hoje
  antes de confiar numa leitura — expressa, para `state.db`, como uma
  operação executável antes de cada uso que detecta corrupção/adulteração
  silenciosa.
- **FR-011**: System MUST permitir que leitores (ex.: painel, comando de
  inspeção) acessem os dados do `state.db` enquanto uma escrita está em
  andamento, sem bloquear a escrita nem produzir leitura corrompida ou
  parcial. O mecanismo primário é WAL mode nativo do SQLite (`PRAGMA
  journal_mode=WAL`); o lock de diretório hoje vigente deixa de ser
  exigido para este fim e pode ser mantido apenas como camada extra
  opcional quando justificar melhoria de robustez/segurança (ver
  Clarifications, Session 2026-07-30 — `block-001`).
- **FR-012**: Um projeto que ainda não foi migrado MUST continuar
  operando exatamente como hoje (lendo/escrevendo `state.json`) até que a
  migração seja executada — a introdução do `state.db` não pode quebrar
  nem exigir migração forçada de projetos ainda não convertidos.

**Decisões de infraestrutura auditáveis:**

- **FR-013-INFRA-BACKUP**: System MUST suportar backup/restauração do
  `state.db` com granularidade pelo menos equivalente à disponível hoje
  (um snapshot recuperável por onda fechada), reaproveitando o export
  `state.json` já exigido por FR-007 como mecanismo de snapshot — sem
  introduzir um mecanismo de backup nativo do SQLite separado nesta fase
  (ver Clarifications, Session 2026-07-30) — com a restauração validada
  por teste antes de ser considerada disponível.
- **FR-014-INFRA-IDEMP**: A operação de migração MUST ser idempotente —
  reexecutá-la contra um projeto já migrado não pode duplicar nem
  corromper dados (chave de idempotência: identidade do projeto/execução
  de origem).

> Demais categorias do checklist de infraestrutura: N/A explícito.
> Scheduling — feature não introduz job periódico novo (execução
> continua disparada pelos mesmos gatilhos de onda de hoje). Rotação de
> chave — nenhum dado novo passa a ser criptografado nesta fase. Refresh
> de token externo — não há integração com IdP/OAuth nesta feature.
> Mutex multi-réplica — o toolkit roda como processo local
> single-instance por projeto; a serialização entre orquestradores
> concorrentes passa a ser resolvida primariamente pelo WAL mode nativo
> do `state.db` (ver `block-001`, Clarifications Session 2026-07-30); o
> lock de diretório hoje vigente deixa de ser o único mecanismo e é
> mantido apenas como camada extra opcional, quando justificar melhoria
> de robustez/segurança — não é reintroduzido como requisito desta
> feature.

### Key Entities

- **StateDatabase**: o banco `state.db` por projeto — a nova fonte de
  verdade transacional de uma execução 00c, substituindo o `state.json`.
- **Wave (Onda)**: um ciclo de execução do orquestrador; tem início, fim,
  etapas executadas, motivo de término e as invocações de skill/gate
  ocorridas dentro dela.
- **Decision (Decisão)**: um registro auditável de uma escolha tomada
  durante uma onda, com os seis campos obrigatórios de auditoria mais
  score/evidência opcionais.
- **HumanBlock (Bloqueio Humano)**: uma pausa da execução aguardando
  resposta humana, sempre vinculada a uma Decision existente.
- **TaskOutcome (Resultado de Task)**: o resultado (sucesso/falha) da
  execução de uma task do backlog dentro de uma onda, com métricas de
  teste/lint associadas.
- **Event (Evento)**: um marco cronológico da execução (ex.: consulta ao
  histórico, contenção de lock, validação falha) usado para reconstruir
  a linha do tempo de uma execução.
- **SkillInvocation (Invocação de Skill/Gate)**: o registro de que uma
  skill ou gate determinístico rodou dentro de uma onda, associado
  opcionalmente à decisão que motivou sua invocação.
- **SpawnUsage (Uso de Spawn)**: o registro de profundidade de subagente
  consumida/liberada dentro de uma execução, usado para impedir
  recursão além do teto configurado.
- **MigrationRun (Execução de Migração)**: o registro de uma tentativa de
  converter um `state.json` existente em `state.db`, com seu resultado de
  verificação (sucesso/recusa) e diagnóstico.
- **ExportSnapshot (Export Derivado)**: a representação `state.json`
  gerada a partir do `state.db`, consumida por quem ainda não lê o banco
  diretamente.

## Success Criteria

### Measurable Outcomes

- **SC-001**: 100% dos registros de auditoria (decisões, ondas, tasks,
  eventos, bloqueios humanos, invocações de skill/gate) de uma execução
  existente são preservados após a migração, verificado por comparação
  campo-a-campo entre o export pós-migração e o `state.json` original.
- **SC-002**: Sob escrita concorrente (duas mutações de estado
  simultâneas no mesmo projeto), a taxa de atualização perdida é 0% —
  nenhuma mutação aplicada com sucesso desaparece do estado final,
  medido em teste de carga concorrente.
- **SC-003**: Um projeto que já operava com `state.json` continua
  funcionando (leitura e escrita) sem qualquer alteração de
  comportamento observável, até o momento em que é migrado — 0
  regressões na suíte de testes existente do toolkit atribuíveis a esta
  feature.
- **SC-004**: O export do `state.json` a partir do `state.db` reflete uma
  mutação de estado em até 5 segundos após ela ser aplicada, medido em
  teste automatizado.
- **SC-005**: A ingestão do knowledge.db a partir do `state.db` produz o
  mesmo conjunto de entidades (mesma proveniência projeto/feature/onda)
  que a ingestão a partir do `state.json` exportado do mesmo projeto, com
  100% de equivalência num conjunto de projetos de amostra.
- **SC-006**: Uma tentativa de migração sobre um projeto com dados
  inconsistentes (ex.: bloqueio humano órfão) é recusada em 100% dos
  casos, nunca produzindo um `state.db` com a mesma inconsistência.

## Delta Requirements

**Skip**: nenhuma capability documentada em `docs/specs/current/` (`atomic-commit-staging`, `bash-guard-enforcement`, `delta-archive-gate`, `guards-defense-in-depth`, `serve-integrity`, `spec-corpus`, `spec-delta-requirements`, `trusted-release-hosts`) descreve o mecanismo de persistência transacional do `state.json`/scripts de runtime - esse comportamento hoje vive nos scripts de runtime e nos arquivos de agente, não no corpus de specs vivas. Nada a alterar no corpus nesta fase; uma capability nova (`state-db-foundation` ou equivalente) poderá ser declarada quando esta feature for arquivada, seguindo o processo padrão de `delta-merge`. — agente-00c-feature-orchestrator, 2026-07-30
