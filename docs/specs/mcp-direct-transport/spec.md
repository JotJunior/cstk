# Feature Specification: Transporte MCP direto (sem container, resolucao por chamada)

**Feature**: `mcp-direct-transport`
**Created**: 2026-08-16
**Status**: Draft

## Clarifications

### Session 2026-08-16

- Q: Sem motor de containers instalado, o `mcp-launch.sh` deve manter um
  caminho de stub em shell para quando o token de capacidade ainda nao
  existe, ou sempre fazer `exec` no processo node real (que resolve
  idle-vs-autorizado por chamada)? → A: sempre `exec` no processo node
  real, repassando `MCP_SESSION_TOKEN`/`CSTK_MCP_PROJECT_PATH`; o servidor
  decide idle-vs-autorizado por chamada (FR-001/FR-002); elimina o stub em
  shell (dec-010).
- Q: A coordenacao cross-feature de injecao do token pelos commands
  `/agente-00c`/`/feature-00c` (dec-043, hoje condicionada a
  `mode == "docker"`) entra no escopo desta feature, ou continua fora dela
  apos o cutover? → A: entra no escopo. `feature-00c.md:728` e o par
  equivalente em `agente-00c.md:487` condicionam a injecao a
  `mode == "docker"`; apos o cutover o modo deixa de ser `docker`, e sem
  ajuste o orquestrador nunca receberia `session_id` — toda chamada
  morreria em `SESSION_MISMATCH` (dec-014).
- Q: Sem daemon/container de longa duracao, o que `cstk mcp
  start`/`stop`/`gc` devem fazer? → A: `start` so grava/atualiza o
  descritor (token+metadados, sem `mode=docker`/`container_name`); `stop`
  so marca `stopped_at`; `gc` seria no-op documentado, sem
  processo/container orfao a limpar (dec-011).
- Q: Apos o cutover, como tratar descritores legados `mode=docker` (e
  containers Docker eventualmente ainda vivos) e o `gc`? Sobrescrever em
  silencio, recusar, ou detectar-e-avisar? → A: `cstk mcp start` detecta
  descritor legado `mode=docker`, avisa em stderr e sobrescreve; `cstk mcp
  gc` passa a recolher containers `cstk-mcp-state-*` remanescentes —
  ajusta dec-011: `gc` NAO vira no-op puro. Sobrescrever em silencio
  deixaria containers orfaos permanentes; recusar travaria execucao nova
  por causa de estado antigo (dec-015).

## User Scenarios & Testing

### User Story 1 - Tools MCP disponiveis assim que a sessao abre (Priority: P1)

Como operador do Claude Code trabalhando no repositorio, ao abrir qualquer
sessao (interativa ou nao-interativa) eu quero ver as tools do servidor de
estado listadas e utilizaveis, mesmo que nenhuma execucao autonoma
(agente-00c/feature-00c) esteja em andamento naquele momento — hoje a sessao
mostra "connected - no tools / Capabilities: none" porque o servidor recusa
subir (e nunca registra tool alguma) sem um token de capacidade que so passa
a existir DEPOIS que uma execucao autonoma ja comecou.

**Why this priority**: E o sintoma que motivou a feature — sem isso, o
mecanismo MCP nunca chega a ser util em nenhum cenario, incluindo o
cenario-alvo original (orquestradores autonomos usando tools em vez do
fallback Bash).

**Independent Test**: Abrir uma sessao nova do Claude Code no repositorio,
sem nenhuma execucao 00c ativa, e confirmar que o servidor de estado aparece
conectado com a lista completa de tools (nao um stub vazio).

**Acceptance Scenarios**:

1. **Given** nenhuma execucao 00c ativa no projeto, **When** uma sessao do
   Claude Code e aberta, **Then** o servidor MCP de estado conecta e expoe
   todas as suas tools (introspectáveis via listagem), sem exigir qualquer
   configuracao manual previa.
2. **Given** o servidor MCP ja esta conectado com as tools listadas,
   **When** uma tool de mutacao (ex.: registrar decisao, abrir onda) e
   chamada sem que exista execucao 00c ativa correspondente, **Then** a
   chamada e rejeitada com motivo explicito — a disponibilidade da tool
   NUNCA implica permissao de mutacao sem sessao valida.

---

### User Story 2 - Sessao MCP acompanha a execucao autonoma sem depender de container (Priority: P2)

Como operador que inicia uma execucao `agente-00c`/`feature-00c`, eu quero
que o comando que prepara a sessao MCP (`cstk mcp start`) funcione mesmo em
uma maquina sem motor de containers instalado, e que consultar o status
(`cstk mcp status`) reflita a situacao real da sessao sem depender de um
health-check de container.

**Why this priority**: E o pre-requisito operacional para a US1 funcionar de
ponta a ponta durante uma execucao real — sem isso, o gargalo apenas migra
do bootstrap do servidor para o `start`/`status` do CLI.

**Independent Test**: Em um ambiente sem motor de containers disponivel,
rodar `cstk mcp start` para uma execucao valida, confirmar que a sessao fica
disponivel para chamadas de tool, depois `cstk mcp status` reportando o
estado correto, e `cstk mcp stop` encerrando de forma limpa.

**Acceptance Scenarios**:

1. **Given** uma execucao 00c valida e nenhum motor de containers instalado
   na maquina, **When** o operador roda `cstk mcp start`, **Then** o comando
   conclui com sucesso e a sessao fica pronta para receber chamadas de tool.
2. **Given** uma sessao MCP preparada, **When** o operador roda
   `cstk mcp status`, **Then** o resultado reflete o estado real da sessao
   (ativa/parada) sem depender de inspecionar um container.
3. **Given** uma sessao MCP ativa, **When** o operador roda `cstk mcp stop`,
   **Then** a sessao e encerrada de forma limpa e chamadas de tool
   subsequentes com aquele token passam a ser rejeitadas.

---

### User Story 3 - Nenhuma exposicao do token de capacidade via inspecao de processos do sistema (Priority: P3)

Como responsavel por seguranca do toolkit, eu quero que o token de
capacidade de uma sessao MCP nunca apareca em identificadores observaveis
por outros processos/usuarios da mesma maquina (ex.: nome de processo,
listagem de containers), para eliminar o vetor de vazamento hoje conhecido
onde o token e usado como sufixo do nome de um container Docker.

**Why this priority**: E um endurecimento de seguranca com issue ja
registrada (achado da feature anterior, ainda nao corrigido) — importante,
mas nao bloqueia o funcionamento basico das duas stories acima; e
consequencia natural de remover o container do caminho, nao um trabalho
adicional independente.

**Independent Test**: Iniciar uma sessao MCP e, a partir de outro processo
com acesso normal de listagem de processos do sistema operacional, confirmar
que nenhum identificador observavel contem o token de capacidade em texto
claro.

**Acceptance Scenarios**:

1. **Given** uma sessao MCP ativa, **When** qualquer processo da mesma
   maquina lista processos ou recursos em execucao, **Then** nenhum
   identificador observavel (nome de processo, nome de recurso) contem o
   token de capacidade em texto claro.

---

### Edge Cases

- O que acontece quando uma chamada de tool chega com `session_id` ausente,
  vazio, ou que nao corresponde a nenhuma sessao conhecida? Deve ser
  rejeitada com motivo explicito, sem mutar nenhum estado — comportamento ja
  existente hoje e que esta feature preserva integralmente.
- O que acontece quando uma chamada de tool chega com `session_id` de uma
  execucao ja concluida/abortada (status terminal)? Deve ser rejeitada da
  mesma forma que um `session_id` invalido — sessao terminal nunca autoriza
  mutacao.
- O que acontece quando duas execucoes autonomas distintas estao ativas ao
  mesmo tempo no mesmo projeto (ex.: `agente-00c` e uma ou mais
  `feature-00c`)? Cada chamada de tool deve ser resolvida e autorizada
  apenas contra a sessao cujo `session_id` foi apresentado — nunca contra
  "a sessao ativa mais provavel".
- O que acontece se `cstk mcp start` for chamado quando ja existe uma
  sessao ativa para a mesma execucao? Deve ser idempotente — nao duplicar
  processos nem invalidar a sessao ja em curso.
- O que acontece com o processo do servidor MCP quando a sessao do Claude
  Code (que o hospeda) e encerrada? Deve encerrar junto, sem deixar processo
  orfao consumindo recursos indefinidamente.
- O que acontece quando o operador chama `cstk mcp stop` para uma sessao que
  ja nao esta ativa? Deve ser idempotente — reportar que ja esta parada, sem
  erro.

## Requirements

### Functional Requirements

- **FR-001**: O servidor MCP de estado MUST registrar todas as suas tools
  (listagem/introspeccao) na inicializacao do processo, independentemente de
  existir um token de capacidade disponivel naquele momento.
- **FR-002**: O servidor MUST resolver e validar a sessao (token de
  capacidade + identificador de sessao) individualmente a cada chamada de
  tool, nao mais uma unica vez na inicializacao do processo.
- **FR-003**: O servidor MUST rejeitar (fail-closed) qualquer chamada de
  tool cujo identificador de sessao esteja ausente, nao corresponda a
  sessao resolvida, ou pertenca a uma execucao em status terminal —
  preservando integralmente o comportamento de rejeicao ja existente hoje.
- **FR-004**: O mecanismo que inicia o processo do servidor MCP (launcher)
  MUST conseguir subi-lo sem exigir que um token de capacidade ja exista
  naquele momento.
- **FR-005**: O mecanismo que inicia o processo do servidor MCP MUST parar
  de depender de um motor de containers para servir o transporte — o
  transporte deve funcionar como processo direto do sistema operacional.
- **FR-006**: `cstk mcp start` MUST concluir com sucesso em uma maquina sem
  motor de containers instalado, preparando a sessao (descritor + token)
  necessaria para chamadas de tool subsequentes.
- **FR-007**: `cstk mcp status` MUST reportar o estado real da sessao
  (ativa/parada/indisponivel) sem depender de inspecionar um container.
- **FR-008**: `cstk mcp stop` MUST encerrar a sessao de forma limpa sem
  depender de parar um container, e MUST ser idempotente quando chamado
  para uma sessao ja parada.
- **FR-009**: O sistema MUST deixar de expor o token de capacidade como
  parte de qualquer identificador observavel por outros processos da mesma
  maquina (ex.: nome de processo, nome de recurso do sistema operacional).
- **FR-010**: `cstk mcp start` MUST ser idempotente — chamado novamente
  para uma execucao que ja tem sessao ativa, MUST reutilizar a sessao
  existente em vez de duplicar processos ou invalidar a sessao em curso.
- **FR-011**: O sistema MUST resolver cada chamada de tool exclusivamente
  contra a sessao cujo identificador foi apresentado na propria chamada,
  mesmo quando multiplas execucoes autonomas estiverem ativas
  simultaneamente no mesmo projeto.
- **FR-012**: O processo do servidor MCP MUST ser encerrado junto com a
  sessao do Claude Code que o hospeda, sem permanecer ativo como processo
  orfao apos o encerramento dessa sessao.
- **FR-013**: Os commands `/agente-00c` e `/feature-00c` MUST injetar o
  token de capacidade no prompt de spawn do orquestrador sempre que o
  descritor de sessao (`mcp-server.json`) existir e tiver um `session_id`
  valido, independentemente do valor de `mode` — a condicao anterior
  restrita a `mode == "docker"` (`feature-00c.md:728` e
  `agente-00c.md:487`) MUST ser removida/generalizada, pois apos o cutover
  desta feature nenhuma sessao nova grava `mode=docker`.
- **FR-014**: `cstk mcp start` MUST detectar um descritor de sessao
  existente com `mode=docker` (formato legado, pre-cutover), emitir um
  aviso explicito em stderr, e sobrescreve-lo com o novo descritor de
  transporte direto — nunca falhar nem recusar por causa de estado legado.
- **FR-015**: `cstk mcp gc` MUST continuar detectando e removendo
  containers Docker orfaos com o padrao de nome `cstk-mcp-state-*`
  remanescentes de sessoes criadas antes do cutover — `gc` NAO se torna
  no-op apos esta feature; apenas deixa de ter containers NOVOS para
  gerenciar (toda sessao criada apos o cutover usa transporte direto).

> Decisoes de infraestrutura: a unica politica aplicavel e idempotencia de
> `cstk mcp start`/`stop` (FR-010, FR-008) — chamadas repetidas nao devem
> duplicar processos nem corromper o estado da sessao. Demais categorias
> (scheduling periodico, rotacao de chave de criptografia, refresh de token
> externo, mutex multi-pod, backup/restore) sao N/A: a sessao MCP e um
> processo local de vida curta, sem estado persistente proprio alem do
> descritor de sessao, e sem coordenacao entre replicas. Excecao: FR-015
> mantem uma rotina de limpeza (`gc`) para o passivo Docker legado deixado
> pela feature anterior — nao e um mecanismo novo, e a continuidade de um
> ja existente ate os containers remanescentes serem coletados.

### Key Entities

- **Sessao MCP**: representa o vinculo entre um processo do servidor de
  estado e uma execucao autonoma especifica (`agente-00c`/`feature-00c`);
  contem o identificador da execucao, o token de capacidade e o estado
  atual (ativa/parada).
- **Token de capacidade**: credencial de curta duracao que autoriza chamadas
  de mutacao de estado; apresentado a cada chamada de tool (nao mais so no
  boot do processo) e nunca exposto por identificadores observaveis do
  sistema operacional.
- **Chamada de tool**: unidade de interacao com o servidor MCP; carrega o
  identificador de sessao e e aceita ou rejeitada de forma independente,
  com motivo explicito quando rejeitada.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Uma sessao nova do Claude Code aberta no projeto, sem nenhuma
  execucao autonoma ativa, mostra o servidor de estado conectado com sua
  lista completa de tools, em 100% das tentativas — sem edicao manual de
  configuracao.
- **SC-002**: Toda chamada de tool com identificador de sessao ausente,
  invalido ou pertencente a execucao terminal e rejeitada, com mensagem de
  motivo, em 100% dos casos testados.
- **SC-003**: As tres operacoes de ciclo de vida da sessao MCP (iniciar,
  consultar status, encerrar) completam com sucesso em uma maquina sem
  motor de containers instalado.
- **SC-004**: Nenhum identificador observavel por outros processos da
  mesma maquina (listagem de processos ou de recursos do sistema
  operacional) contem o token de capacidade em texto claro, em nenhum
  momento do ciclo de vida da sessao.
- **SC-005**: Chamar `cstk mcp start` duas vezes seguidas para a mesma
  execucao nao produz um segundo processo nem interrompe chamadas de tool
  que ja estivessem em curso contra a sessao existente.

## Delta Requirements

**Skip**: nao ha entrada correspondente em `docs/specs/current/` para o
ciclo de vida do servidor MCP — a feature-base (`state-mcp-server`,
arquivada) e o pre-requisito lógico ainda nao-mergeado
(`orchestrator-mcp-allowlist`) nunca chegaram a compor o corpus canonico
`docs/specs/current/`. Sem capability ativa documentada para herdar/alterar,
esta spec nao preenche blocos `### Capability:`. — agente-00c-feature-orchestrator, 2026-08-16
