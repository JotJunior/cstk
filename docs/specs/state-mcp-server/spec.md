# Feature Specification: Servidor MCP de Estado das Execucoes 00C

**Feature**: `state-mcp-server`
**Created**: 2026-08-01
**Status**: Draft

## Contexto

Hoje o registro de estado de uma execucao autonoma (`agente-00c`/`feature-00c`)
depende de o orquestrador (um subagente LLM) executar, via `Bash`, sequencias
de comandos descritas em prosa nas suas proprias instrucoes (`state-decisions.sh
register`, `state-ondas.sh end`, `state-rw.sh set`, etc.). Esse mecanismo e a
origem recorrente de uma classe conhecida de bugs: onda que fecha sem chamar
`state-ondas.sh end` (o `reconcile-wave` do command pai existe justamente como
rede de seguranca para isso), `record-task` pulado (observado em 2 de 21
tasks numa execucao real), decisoes registradas sem o `record-skill`
correspondente ("half-records"), e casos em que o harness nega a permissao de
escrita ao subagente e a mutacao simplesmente nao acontece. Nenhum desses e
causado por regra de neg cio errada — a regra existe e esta correta nos
scripts; o que falta e um ponto de imposicao que nao dependa do LLM lembrar
de seguir a receita ate o fim.

Este e o terceiro pilar de um estudo de evolucao da camada de estado iniciado
na v6: o primeiro pilar (`state-db-foundation` / `state-backend-config`, já
entregues) substituiu o arquivo `state.json` por um `state.db` (SQLite)
transacional; o segundo (`wave-token-metrics` em diante) instrumentou
telemetria por onda. O proprio `spec.md` de `state-db-foundation` reserva
explicitamente "servidor de acesso tipado" como fase futura fora do seu
escopo — esta feature e essa fase: em vez de o orquestrador compor comandos
Bash que *descrevem* uma mutacao de estado, ele chama uma **tool MCP** que a
*executa* dentro de um contrato validado, no processo do servidor, sem
depender de permissao de `Bash` nem da disciplina de seguir uma sequencia de
passos escrita em prosa.

**Decisoes ja tomadas pelo operador (fora de escopo desta spec/clarify)**:
stack **Node** (nao Go — o `cstk serve` ja traz Node ao toolkit; a
referencia externa `mcp-project-scafold` serve so de inspiracao de desenho de
tools, nao de stack) e **Docker-first** (precedente: `cstk serve --docker`,
v5.17.0, container alpine multi-stage). O servidor MCP e, portanto, um
processo de servico como o `cstk-panel` — nao um "script auxiliar de skill"
sob a disciplina POSIX sh do Principio II da constitution, da mesma forma que
`cli/cstk` (Go) e o `cstk-panel` (Node) ja nao estao sob essa disciplina hoje.

## Clarifications

### Session 2026-08-01

- Q: FR-010 — o servidor MCP permanece ativo durante uma pausa longa entre
  ondas (`Schedule intent`), ou e encerrado a cada pausa e reiniciado a cada
  `-resume`? → A: Permanece ativo. A sessao do servidor e coextensiva com a
  execucao autonoma inteira (do inicio ate um estado terminal), nao com cada
  onda; o command pai so verifica saude a cada `-resume` (paridade FR-011).
  E encerrado somente quando a execucao atinge estado terminal (`concluida`/
  `abortada`) — ja afirmado literalmente por User Story 2 Acceptance
  Scenario 2.
- Q: FR-012 — quando Docker esta ausente/indisponivel no host, o sistema
  bloqueia a inicializacao do servidor MCP (caindo direto no fallback Bash
  da FR-007), ou tenta um modo alternativo sem container (processo Node
  local) antes de cair no fallback? → A: Bloqueia direto para o fallback
  Bash; nenhum modo Node-local intermediario nesta feature. O fallback Bash
  ja satisfaz integralmente o carve-out de dependencia opcional (Principio
  II, amendment 1.1.0) — um segundo caminho de execucao so multiplicaria
  superficie de auditoria/isolamento sem ser exigido. Extensao futura
  possivel, fora de escopo aqui.
- Q: FR-016 — quando duas execucoes autonomas concorrentes rodam no mesmo
  projeto-alvo, cada uma recebe sua propria instancia/porta de servidor MCP
  isolada, ou uma unica instancia multiplexa chamadas por sessao/execucao?
  → A: Cada execucao recebe sua propria instancia/porta isolada — sem
  multiplexacao por processo compartilhado. Isolamento fisico e a forma
  mais direta de garantir o confinamento ja exigido por FR-008 e pela
  definicao de "Orchestrator Server Session" nas Key Entities.

## User Scenarios & Testing

### User Story 1 - Mutacao de estado por contrato em vez de prosa Bash (Priority: P1)

Como orquestrador autonomo (`agente-00c-orchestrator` ou
`agente-00c-feature-orchestrator`) executando uma onda, preciso registrar
decisoes, abrir/fechar a onda, registrar o resultado de uma task e registrar
a invocacao de uma skill chamando uma ferramenta com contrato validado — em
vez de montar e executar uma sequencia de comandos `Bash` — para que erros de
sequenciamento (esquecer um passo, parar no meio, registrar so metade de um
par obrigatorio) deixem de ser fisicamente possiveis: a ferramenta ou aplica
a mutacao completa e valida, ou rejeita a chamada inteira com um motivo
acionavel.

**Why this priority**: e o nucleo do problema que motiva a feature — sem essa
troca, as demais user stories (auditoria, ciclo de vida, fallback) nao tem o
que servir.

**Independent Test**: numa execucao de teste, rodar uma onda completa (abrir,
registrar >=1 decisao com score 3 e evidencia, registrar >=1 task, fechar)
exclusivamente atraves das ferramentas; ao final, o estado persistido deve
estar tao integro quanto o caminho `Bash` atual (mesmas invariantes: onda
fechada tem `termination_reason`, toda task tem outcome, toda decisao com
score 3 tem evidencia) e zero comando `Bash` de escrita de estado deve ter
sido necessario.

**Acceptance Scenarios**:

1. **Given** uma onda aberta sem decisoes registradas, **When** o
   orquestrador chama a ferramenta de registrar decisao com score 3 mas sem
   evidencia, **Then** a chamada e rejeitada antes de qualquer persistencia,
   com um motivo que identifica exatamente a regra violada.
2. **Given** uma onda aberta com todas as tasks do backlog concluidas,
   **When** o orquestrador chama a ferramenta de fechar a onda, **Then** o
   fechamento e atomico — a onda so aparece fechada no estado se **todas**
   as pos-condicoes hoje exigidas (motivo de termino, hash atualizado,
   backup gerado) tiverem sido aplicadas; qualquer falha no meio do processo
   nao deixa a onda em estado parcialmente fechado.
3. **Given** uma task ja registrada com um `task_id`, **When** a mesma task e
   registrada de novo com o mesmo `task_id` (retry do orquestrador apos uma
   falha de rede, por exemplo), **Then** o resultado e um upsert idempotente
   — nao uma segunda entrada duplicada.

---

### User Story 2 - Ciclo de vida do servidor por sessao de execucao (Priority: P1)

Como command pai (`/agente-00c`, `/feature-00c` e seus `-resume`), preciso
subir o servidor MCP (por padrao, em container Docker) no inicio de uma
execucao autonoma e encerra-lo de forma limpa quando a execucao termina ou
pausa, para que cada execucao tenha um servidor dedicado ao seu escopo, sem
processos orfaos sobrevivendo entre sessoes nem um servidor de uma execucao
alcancando o estado de outra.

**Why this priority**: sem um ciclo de vida bem definido, a feature nao e
operavel de forma autonoma — o command pai precisa de uma resposta
determinista para "o servidor esta no ar?" antes de delegar ao orquestrador.

**Independent Test**: iniciar uma execucao de teste e confirmar que o
servidor sobe e fica saudavel antes da primeira chamada de ferramenta;
abortar a execucao (`/feature-00c-abort` equivalente de teste) e confirmar
que o servidor e encerrado como parte do abort, sem processo/container
remanescente.

**Acceptance Scenarios**:

1. **Given** uma execucao autonoma nova sendo iniciada, **When** o command
   pai prepara o ambiente antes de invocar o orquestrador, **Then** o
   servidor MCP fica saudavel e pronto para receber chamadas antes da
   primeira mutacao de estado ser tentada.
2. **Given** um servidor MCP em execucao para uma sessao, **When** essa
   execucao chega a um estado terminal (concluida ou abortada), **Then** o
   servidor correspondente e encerrado sem exigir passo manual do operador.
3. **Given** duas execucoes autonomas distintas ativas no mesmo projeto (ex.:
   `agente-00c` e uma `feature-00c` de short-name diferente), **When** ambas
   tem servidor MCP ativo, **Then** cada uma so consegue mutar o estado da
   propria execucao — nenhuma ferramenta de uma sessao alcanca o `state.db`/
   `state.json` de outra sessao (paridade com o confinamento de blast radius
   ja exigido dos orquestradores).

---

### User Story 3 - Trilha de auditoria propria para chamadas de ferramenta (Priority: P2)

Como operador investigando o comportamento de uma execucao autonoma, preciso
que toda chamada de ferramenta MCP de mutacao de estado — aceita ou
rejeitada — fique registrada num historico auditavel e revisavel em disco,
para que eu consiga reconstruir o que o orquestrador tentou fazer mesmo
quando uma chamada foi rejeitada pelo contrato (hoje o `bash-guard` cobre
apenas comandos `Bash`; chamadas de ferramenta MCP nao passam por esse
caminho e ficariam sem rastro equivalente).

**Why this priority**: auditabilidade total e principio nao-negociavel do
toolkit (Principio I); sem essa trilha, a feature reduziria a
auditabilidade em vez de aumenta-la, ao mover mutacoes para fora do caminho
hoje coberto pelo `enforcement-log.jsonl`.

**Independent Test**: chamar uma ferramenta com payload que viola uma
invariante conhecida (ex.: fechar uma onda que ja esta fechada) e confirmar
que a rejeicao aparece no historico auditavel do projeto, com timestamp,
nome da ferramenta e motivo — sem exigir a leitura do transcript da
conversa.

**Acceptance Scenarios**:

1. **Given** o servidor MCP ativo para uma sessao, **When** qualquer
   ferramenta de mutacao de estado e chamada (sucesso ou rejeicao),
   **Then** uma entrada correspondente e persistida no historico auditavel
   do projeto-alvo, sobrevivendo ao encerramento do servidor.
2. **Given** uma entrada de auditoria contendo texto potencialmente sensivel
   (ex.: um payload com dado do usuario), **When** a entrada e persistida,
   **Then** ela passa pela mesma disciplina de filtragem de segredos ja
   aplicada aos demais logs do toolkit.

---

### User Story 4 - Degradacao graciosa quando o servidor MCP nao esta disponivel (Priority: P2)

Como orquestrador autonomo rodando num ambiente headless/cron onde o
servidor MCP nao pode subir (Docker ausente, ambiente restrito, falha de
inicializacao), preciso continuar registrando estado pelo caminho `Bash`
hoje existente, sem regressao funcional, para que a introducao do servidor
MCP seja estritamente aditiva e nunca um novo ponto unico de falha para
execucoes que hoje funcionam.

**Why this priority**: o toolkit ja documenta cenarios headless/cron como
uso real; tornar o MCP um requisito rigido quebraria esse uso existente.

**Independent Test**: rodar uma execucao de teste num ambiente sem Docker
disponivel e confirmar que a execucao completa com o mesmo resultado
funcional (mesmas invariantes de estado ao final) que produziria com o
servidor MCP ativo, usando o caminho `Bash` atual.

**Acceptance Scenarios**:

1. **Given** um ambiente onde o servidor MCP nao consegue subir, **When** o
   command pai detecta essa condicao antes de delegar ao orquestrador,
   **Then** a execucao prossegue pelo caminho de escrita `Bash` hoje
   existente, sem interromper a execucao nem exigir intervencao manual.
2. **Given** uma execucao que comecou com o servidor MCP ativo, **When** o
   servidor cai no meio de uma onda (apos algumas ferramentas chamadas,
   antes do fechamento), **Then** o estado nao fica em condicao pior do que
   uma onda interrompida no caminho `Bash` de hoje — a mesma rede de
   seguranca de reconciliacao (equivalente ao `reconcile-wave` atual)
   continua aplicavel na retomada.

---

### Edge Cases

- O que acontece quando uma ferramenta e chamada fora de ordem (ex.:
  registrar o resultado de uma task antes de a onda estar aberta)? Deve ser
  rejeitada com motivo claro, sem side-effect parcial.
- O que acontece se o operador chamar o abort manual (`/feature-00c-abort`,
  `/agente-00c` equivalente) enquanto o servidor MCP da sessao ainda esta
  processando uma chamada em andamento? O encerramento do servidor nao deve
  corromper uma mutacao em voo — ou ela completa, ou e revertida por
  inteiro.
- O que acontece com chamadas de ferramenta durante uma pausa longa entre
  ondas (`Schedule intent`)? Ver requisito FR-010 (fronteira de sessao do
  servidor) sobre manter o servidor ativo ou reinicia-lo a cada retomada.
- O que acontece se duas execucoes autonomas tentarem usar a mesma porta/
  identificador de sessao simultaneamente? A alocacao de identidade de
  sessao deve evitar colisao sem exigir coordenacao manual do operador.

## Requirements

### Functional Requirements

- **FR-001**: O sistema MUST expor, via ferramentas MCP, um contrato para
  cada categoria de mutacao de estado hoje realizada via script Bash pelo
  orquestrador: registrar decisao auditavel, abrir onda, fechar onda,
  registrar resultado de task, registrar bloqueio humano, registrar
  invocacao de skill/gate.
- **FR-002**: A ferramenta de registrar decisao MUST rejeitar, antes de
  qualquer persistencia, uma decisao de score 3 sem evidencia associada —
  paridade com a trava hoje aplicada por `state-decisions.sh register`.
- **FR-003**: A ferramenta de fechar onda MUST ser atomica: ou todas as
  pos-condicoes hoje exigidas (motivo de termino registrado, hash de
  integridade recalculado, backup da onda gerado) sao aplicadas juntas, ou
  nenhuma delas persiste — nunca uma onda parcialmente fechada.
- **FR-004**: A ferramenta de registrar resultado de task MUST ser
  idempotente por identificador de task — uma chamada repetida para o mesmo
  identificador atualiza o registro existente (upsert), nunca cria uma
  segunda entrada.
- **FR-005**: Toda chamada de ferramenta de mutacao de estado (aceita ou
  rejeitada) MUST gerar uma entrada num historico auditavel e revisavel em
  disco no projeto-alvo, contendo pelo menos: timestamp, ferramenta
  chamada, sessao/execucao de origem e resultado (aceita/rejeitada + motivo
  quando rejeitada) — papel equivalente ao `enforcement-log.jsonl` hoje
  usado para comandos `Bash`, mas para chamadas de ferramenta.
- **FR-006**: O conteudo persistido no historico de auditoria de chamadas de
  ferramenta MUST passar pela mesma disciplina de filtragem de segredos ja
  aplicada aos demais artefatos de log do toolkit antes de ser escrito em
  disco.
- **FR-007**: Quando o servidor MCP nao estiver disponivel para uma execucao
  (falha de inicializacao, ambiente sem Docker, execucao headless/cron), o
  sistema MUST permitir que a execucao prossiga pelo caminho de escrita
  `Bash` hoje existente, sem regressao funcional e sem exigir intervencao
  manual do operador.
- **FR-008**: Uma sessao de servidor MCP MUST estar confinada a exatamente
  uma execucao autonoma (um `agente-00c` ou um `feature-00c`/short-name) —
  nenhuma ferramenta chamada numa sessao MUST conseguir mutar o estado de
  uma execucao diferente (paridade com o confinamento de blast radius ja
  exigido dos orquestradores, Principio III herdado).
- **FR-009**: O sistema MUST rejeitar, no nivel do contrato, qualquer
  chamada de ferramenta cujo payload viole uma invariante ja imposta pela
  primitiva Bash equivalente (ex.: fechar uma onda que nao esta aberta,
  registrar task referenciando uma onda inexistente), com um motivo
  acionavel equivalente em clareza ao erro hoje produzido pelo script
  manual.
- **FR-010**: O sistema MUST definir uma fronteira clara de sessao para o
  servidor: a sessao do servidor MCP e coextensiva com a execucao autonoma
  inteira (do inicio ate um estado terminal), NAO com cada onda individual.
  O servidor MUST permanecer ativo durante pausas longas entre ondas
  (`Schedule intent`) — o command pai apenas verifica saude (paridade com
  FR-011) a cada `-resume`, sem parar/reiniciar o processo/container a cada
  pausa. O servidor MUST ser encerrado somente quando a execucao atinge
  estado terminal (`concluida` ou `abortada`), conforme User Story 2
  Acceptance Scenario 2.
- **FR-011**: Quando Docker e o modo de inicializacao selecionado, o sistema
  MUST verificar que o container esta saudavel antes de o orquestrador
  emitir a primeira chamada de ferramenta, e MUST expor um erro claro e
  acionavel caso o container nao fique saudavel dentro de um tempo limite.
- **FR-012**: Quando Docker esta ausente/indisponivel no host, o sistema
  MUST bloquear a inicializacao do servidor MCP e cair diretamente no
  fallback Bash existente (FR-007) — sem tentar um modo alternativo sem
  container (processo Node local) nesta feature. O fallback Bash ja
  satisfaz o requisito de funcionamento sem a ferramenta do carve-out de
  dependencia opcional (Principio II da constitution, amendment 1.1.0); um
  segundo caminho de execucao multiplicaria superficie de auditoria/
  health-check/isolamento de sessao (FR-008, FR-016) sem ser exigido. Pode
  ser reavaliado como extensao futura fora desta feature.
- **FR-013**: O `knowledge.db` (indice cross-feature) MUST permanecer unico
  e somente-leitura — nenhuma ferramenta MCP introduzida por esta feature
  MUST escrever nele; ele continua populado exclusivamente pelo mecanismo
  de ingestao best-effort ja existente.
- **FR-014**: O sistema MUST NOT enfraquecer nenhuma garantia de
  auditabilidade, confinamento de blast radius ou aterramento de evidencia
  ja fornecida pelas primitivas Bash atuais — as ferramentas MCP sao uma
  interface aditiva sobre as mesmas invariantes, nunca uma substituicao que
  as relaxa.
- **FR-015**: O sistema MUST permitir que o operador (ou o command pai)
  consulte o status do servidor MCP de uma execucao especifica (ativo /
  parado / indisponivel) sem precisar inspecionar Docker diretamente.
- **FR-016**: Quando duas execucoes autonomas concorrentes rodam no mesmo
  projeto-alvo (ex.: um `agente-00c` e uma `feature-00c`), cada uma MUST
  receber sua propria instancia/porta de servidor MCP isolada — nenhuma
  instancia unica MUST multiplexar chamadas por sessao/execucao. Isolamento
  fisico por processo/container e a forma mais direta de garantir o
  confinamento de FR-008 sem depender de isolamento logico dentro de um
  processo compartilhado (defesa em profundidade, Principio III herdado).
- **FR-017**: Quando tanto o caminho de ferramenta MCP quanto o caminho
  `Bash` legado puderem, em tese, mutar o mesmo estado na mesma janela
  (ex.: fallback acionado no meio de uma onda), o sistema MUST preservar
  exclusao mutua equivalente ao lock de diretorio nao-reentrante hoje
  vigente — nenhuma escrita intercalada MUST produzir estado corrompido.

> Decisoes de infraestrutura — checklist aplicado: **scheduling** N/A (o
> servidor nao dispara trabalho periodico proprio; e invocado por sessao
> pelo command pai, ver FR-010); **key rotation** N/A (o servidor nao
> introduz criptografia de dados persistidos alem do que ja existe);
> **refresh policy de token externo** N/A (nenhum IdP/OAuth envolvido);
> **mutex multi-pod** coberto por FR-017; **backup/restore** reusa o
> mecanismo de backup por onda ja exigido (parte das pos-condicoes de
> FR-003, nenhum mecanismo novo); **idempotencia** coberta por FR-004
> (task) e pela atomicidade de FR-003 (fechamento de onda).

### Key Entities

- **MCP Tool Call**: uma invocacao de ferramenta de mutacao de estado pelo
  orquestrador — nome da ferramenta, payload, resultado (aceita/rejeitada),
  timestamp, sessao de origem.
- **Tool Invocation Audit Record**: entrada persistida em disco por cada
  MCP Tool Call, sobrevivendo ao encerramento do servidor; base do
  historico auditavel exigido por FR-005/FR-006.
- **Orchestrator Server Session**: janela de vida do servidor MCP associada
  a exatamente uma execucao autonoma (um `agente-00c` ou um
  `feature-00c`/short-name); delimita o escopo de confinamento de FR-008.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Em execucoes autonomas que usam o caminho de ferramentas MCP
  para toda mutacao de estado, a taxa de registros de estado incompletos
  (onda fechada sem motivo de termino, bloqueio humano sem decisao
  associada, task concluida sem registro correspondente) cai a zero,
  medida sobre um conjunto de execucoes completas de teste.
- **SC-002**: 100% das tentativas de registrar uma decisao de score 3 sem
  evidencia sao rejeitadas no momento da chamada, nunca chegando a
  persistir no estado.
- **SC-003**: 100% das chamadas de ferramenta de mutacao de estado (aceitas
  ou rejeitadas) aparecem no historico auditavel do projeto, verificavel
  sem acesso ao transcript da conversa.
- **SC-004**: Execucoes headless/cron sem servidor MCP disponivel completam
  com o mesmo resultado funcional que produziriam com o servidor ativo —
  zero regressao observavel no caminho de fallback.
- **SC-005**: O operador consegue determinar o status do servidor MCP de
  uma execucao especifica numa unica consulta, sem inspecionar Docker
  diretamente.

## Delta Requirements

**Skip**: feature inteiramente nova — nenhuma capability hoje ativa em
`docs/specs/current/` e adicionada, alterada, removida ou renomeada por
este documento; o servidor MCP e uma interface aditiva sobre a camada de
estado transacional ja existente, sem tocar o comportamento documentado das
capabilities correntes (`bash-guard-enforcement`, `guards-defense-in-depth`,
`serve-integrity`, `trusted-release-hosts`, `atomic-commit-staging`,
`delta-archive-gate`, `spec-corpus`, `spec-delta-requirements`). — feature-00c
orchestrator (state-mcp-server), 2026-08-01.
