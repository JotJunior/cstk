# Feature Specification: Paridade Backend-Agnostica dos Hooks 00C

**Feature**: `hooks-db-parity`
**Created**: 2026-08-03
**Status**: Draft

> Origem: sugestao formal `sug-001` + bloqueio `block-002`/decisao `dec-069`
> (score 3, escolha `priorizar-feature-de-hooks`) da feature
> `state-db-runtime-parity` (v6.3.0) — registrados em
> `docs/specs/state-db-runtime-parity/checklists/operational.md` (CHK031) e
> `docs/specs/state-db-runtime-parity/tasks.md` (task 6.4.3). Ver tambem
> `.claude/agente-00c-suggestions.md` (entrada `hooks-db-parity`).

## User Scenarios & Testing

### User Story 1 - Guarda fail-closed continua ativa sob backend SQLite (Priority: P1)

Um operador roda uma execucao autonoma (`agente-00c` ou `feature-00c`) num
projeto configurado com o backend de estado SQLite (`state.db`). Durante essa
execucao, um comando Bash perigoso (fora da whitelist, ou de categoria
bloqueada) e submetido pelo orquestrador. O sistema precisa continuar
bloqueando esse comando, exatamente como ja faz hoje quando o backend e
`state.json` — a mudanca de backend de persistencia nao pode abrir uma
janela de execucao sem guarda.

**Why this priority**: e a mais critica das tres — hoje, sob backend
SQLite, o hook de guarda (`pretooluse-bash-guard.sh`) nunca encontra
`state.json` (o arquivo simplesmente nao existe nesse backend), conclui que
nao ha execucao ativa e libera o comando sem checagem alguma. Isso e uma
regressao de seguranca silenciosa: a protecao fail-closed vira, na pratica,
fail-open para todo projeto que adotou o backend SQLite (`cstk state
enable-sqlite`).

**Independent Test**: com uma execucao `agente-00c`/`feature-00c` ativa
(`status: em_andamento`) e backend SQLite, submeter um comando Bash
sabidamente bloqueado pela whitelist/blocklist vigente e confirmar que o
hook nega a execucao (`permissionDecision: deny`) com o mesmo tipo de motivo
que produziria sob backend JSON.

**Acceptance Scenarios**:

1. **Given** uma execucao `feature-00c` ativa com backend SQLite e um
   comando Bash fora da whitelist de rede, **When** o comando e submetido,
   **Then** o hook bloqueia a execucao com `permissionDecision: deny` e
   categoria de bloqueio identica a que ocorreria sob backend JSON.
2. **Given** uma execucao `agente-00c` ativa com backend SQLite, **When** um
   comando permitido (dentro da whitelist/nao-bloqueado) e submetido,
   **Then** o hook permite a execucao sem atraso perceptivel adicional.
3. **Given** backend SQLite com `state.db` corrompido ou `sqlite3` ausente
   do host durante uma execucao que deveria estar ativa, **When** o hook
   tenta determinar o status da execucao, **Then** o sistema trata a falha
   do proprio mecanismo como bloqueio (fail-closed), nunca como "nenhuma
   execucao ativa".

---

### User Story 2 - Metrica de tool calls por onda deixa de ficar zerada sob SQLite (Priority: P2)

Durante uma onda de execucao autonoma com backend SQLite, cada tool call
real (Bash, Read, Edit, ...) deveria incrementar o contador de tool calls da
onda corrente (`tool_calls_current_wave`), usado como proxy de custo pelo
gate de orcamento (`budget.sh check`). Hoje, sob SQLite, esse contador fica
sempre zerado — o hook de metrica nunca encontra `state.json` e nunca grava
o sidecar de ticks, entao ondas fecham reportando zero tool calls mesmo
apos dezenas de chamadas reais.

**Why this priority**: nao e um risco de seguranca (a metrica e so um proxy
de custo, nunca uma guarda), mas compromete a auditabilidade do orcamento
por onda e a qualidade dos dados agregados na knowledge.db para qualquer
projeto no backend SQLite.

**Independent Test**: com uma execucao ativa sob backend SQLite, executar N
tool calls dentro de uma onda e confirmar, ao fechar a onda
(`state-ondas.sh end`), que o campo de tool calls contabilizados reflete as
N chamadas (dentro da mesma tolerancia de fronteira start/end ja aceita
hoje sob JSON).

**Acceptance Scenarios**:

1. **Given** uma onda aberta (`state-ondas.sh start`) numa execucao com
   backend SQLite, **When** M tool calls sao executadas durante a onda,
   **Then** o sidecar de ticks da onda acumula M linhas (ou M menos a
   tolerancia de fronteira ja documentada), do mesmo jeito que ocorreria sob
   backend JSON.
2. **Given** nenhuma execucao ativa no projeto (nem `agente-00c` nem
   `feature-00c`, em qualquer backend), **When** uma tool call qualquer
   ocorre, **Then** o hook nao grava nada e nao produz nenhum efeito
   colateral (paridade com o comportamento atual sob JSON).

---

### User Story 3 - Detector de execucao ativa unificado tambem cobre o hook de uso de subagente (Priority: P3)

O terceiro hook da mesma familia, `posttooluse-agent-usage.sh` (que grava
metricas de tokens/duracao por spawn de subagente), usa o identico
algoritmo de deteccao de execucao ativa dos outros dois hooks — e portanto
sofre exatamente da mesma classe de bug sob backend SQLite: nunca
encontrando `state.json`, nunca contabiliza o uso de nenhum spawn.

**Why this priority**: mesma classe de bug que a User Story 2 (metrica,
nao guarda), mas afeta um dado usado apenas na agregacao pos-onda
(`state-ondas.sh end`) e no futuro dashboard de custo — menor urgencia
imediata que US1/US2, porem deixar de fora perpetuaria o mesmo bug
conhecido num terceiro arquivo.

**Independent Test**: com uma execucao ativa sob backend SQLite, spawnar um
subagente (`tool_name: Agent`) e confirmar que o sidecar
`wave-agent-usage.jsonl` recebe uma linha para o spawn.

**Acceptance Scenarios**:

1. **Given** uma execucao ativa sob backend SQLite, **When** um subagente e
   spawnado, **Then** o sidecar de uso de agente recebe uma linha
   correspondente a esse spawn.

---

### Edge Cases

- O que acontece quando `state.db` esta ausente e `state.json` tambem esta
  ausente (execucao nunca inicializada, ou state-dir removido) no momento
  em que um hook dispara? Deve continuar equivalente a "nenhuma execucao
  ativa" (fail-open nos hooks de metrica, e no bash-guard: ausencia de
  qualquer state e igual a "fora de escopo", nao a "mecanismo falhou" —
  precisa distinguir de um `state.db` presente porem corrompido).
- Como o sistema se comporta quando ha multiplas execucoes ativas
  simultaneas (ex: uma `feature-00c` sob `state.json` e outra `feature-00c`
  sob `state.db`, se o backend padrao global mudou entre as duas
  inicializacoes)? A precedencia deterministica existente (agente-00c
  vence; entre feature-00c, menor short-name lexicografico) precisa
  continuar valendo atraves dos dois backends combinados.
- O que acontece quando o hook de metrica ou de guarda roda concorrente a
  uma escrita transacional do orquestrador no `state.db` (busy/lock do
  SQLite)? A leitura do status nao pode travar nem falhar de forma a violar
  os requisitos de fail-open/fail-closed de cada hook (FR-003/FR-004).

## Requirements

### Functional Requirements

- **FR-001**: O sistema MUST detectar execucao ativa (`agente-00c` ou
  `feature-00c`, status `em_andamento` ou `aguardando_humano`) de forma
  equivalente independente do backend de persistencia configurado para o
  state-dir (`state.json` ou `state.db`), nos tres hooks:
  `pretooluse-bash-guard.sh`, `posttooluse-tool-call-tick.sh` e
  `posttooluse-agent-usage.sh`.
- **FR-002**: A deteccao de execucao ativa sob backend SQLite MUST
  preservar a mesma precedencia deterministica ja em vigor sob backend
  JSON: `agente-00c` vence sobre `feature-00c`; entre multiplas
  `feature-00c` ativas, a de menor short-name em ordem lexicografica
  byte-wise (`LC_ALL=C`) vence.
- **FR-003**: O hook `pretooluse-bash-guard.sh` MUST manter comportamento
  fail-closed sob backend SQLite: qualquer falha ao determinar o status da
  execucao a partir do `state.db` (dependencia ausente, arquivo corrompido,
  erro de leitura) MUST ser tratada como bloqueio do comando
  (`MECANISMO_FALHOU`), nunca como ausencia de execucao ativa.
- **FR-004**: Os hooks `posttooluse-tool-call-tick.sh` e
  `posttooluse-agent-usage.sh` MUST manter comportamento fail-open sob
  backend SQLite: qualquer falha na deteccao (dependencia ausente, erro de
  leitura do `state.db`) MUST resultar em no-op silencioso (sem stdout,
  sem stderr de erro, sem interferencia na tool call), nunca em bloqueio ou
  mensagem visivel ao operador.
- **FR-005**: A deteccao de execucao ativa sob backend SQLite MUST caber
  dentro do orcamento de latencia ja em vigor para cada hook hoje
  (aproximadamente 30ms para os hooks de metrica disparados a cada tool
  call; aproximadamente 177ms para o hook de guarda, que roda antes de
  cada comando Bash) — requisito ja registrado como bloqueante em
  `sug-001`/CHK031 da feature `state-db-runtime-parity`.
  [NEEDS CLARIFICATION: esses numeros (~30ms/~177ms) sao um teto que um
  gate automatizado deve medir e falhar caso ultrapassado, ou uma
  referencia de projeto a validar manualmente antes do merge?]
- **FR-006**: Sessoes manuais do operador (sem nenhuma execucao
  `agente-00c`/`feature-00c` ativa) MUST continuar completamente livres de
  interferencia dos tres hooks, em qualquer backend de persistencia.
- **FR-007**: Quando nenhum dos backends (nem `state.json` nem `state.db`)
  estiver presente no state-dir candidato, o sistema MUST tratar essa
  ausencia como "fora de escopo" (equivalente a "nenhuma execucao ativa"),
  distinta de uma falha de leitura de um `state.db` presente porem
  corrompido (que cai em FR-003/FR-004 conforme o hook).

### Assunções e decisões em aberto

- [NEEDS CLARIFICATION: o hook `posttooluse-agent-usage.sh` (User Story 3)
  entra no escopo desta feature — que e o que a leitura do codigo-fonte
  confirma sofrer da mesma classe de bug — ou deve ser tratado como uma
  quarta feature separada, ficando esta limitada aos 2 hooks citados na
  descricao original do operador?]
- [NEEDS CLARIFICATION: o cenario de "backend misto" (execucoes ativas
  simultaneas sob backends diferentes, descrito no segundo Edge Case) deve
  ser suportado de fato por esta feature, ou e aceitavel assumir backend
  uniforme por host — dado que `state_backend` e uma config global
  (`cstk state enable-sqlite`) e a mistura so ocorreria em janelas raras de
  transicao — deixando o comportamento sob mistura como "nao garantido,
  best-effort"?]

> Decisoes de infraestrutura: N/A (feature stateless do ponto de vista de
> scheduling/sessao/chave — os hooks sao scripts POSIX invocados
> sincronamente pelo harness a cada tool call, sem estado proprio alem do
> sidecar append-only ja existente e sem introduzir job periodico, rotacao
> de chave ou lock cross-pod novo).

## Success Criteria

### Measurable Outcomes

- **SC-001**: Comandos Bash que hoje sao bloqueados corretamente sob
  backend `state.json` continuam sendo bloqueados na mesma taxa (100% dos
  casos testados) quando o projeto usa backend `state.db`.
- **SC-002**: Ao final de uma onda de execucao autonoma sob backend
  SQLite, a contagem de tool calls registrada reflete as chamadas reais
  feitas durante a onda, com a mesma margem de tolerancia de fronteira
  start/end ja aceita sob backend JSON (hoje: perda aceitavel apenas de
  ticks exatamente na borda de abertura/fechamento da onda).
- **SC-003**: O tempo adicional introduzido pela deteccao de execucao
  ativa em cada hook permanece dentro do orcamento de latencia hoje
  praticado por esse hook (~30ms para os hooks de metrica, ~177ms para o
  hook de guarda), medido em 100% de uma amostra representativa de
  execucoes.
- **SC-004**: Sessoes manuais do operador (sem execucao autonoma ativa)
  nao apresentam nenhuma interferencia observavel dos hooks — 0 bloqueios
  e 0 escritas de sidecar fora de uma execucao ativa, em qualquer backend.

## Delta Requirements

### Capability: bash-guard-enforcement

#### MODIFIED

- **FR-006**: A interceptacao automatica MUST validar comandos Bash apenas
  quando originados de uma execucao ativa de `agente-00c`/`feature-00c`
  (deteccao via presenca de state/lock da execucao, **independente do
  backend de persistencia configurado — `state.json` ou `state.db`**) —
  sessoes interativas comuns do operador no mesmo projeto-alvo MUST NOT ser
  afetadas ou interceptadas por esta feature, mesmo apos a protecao estar
  provisionada, em qualquer backend (escopo restrito, opcao A; resolvido
  via bloqueio block-001/decisao dec-012 da feature `enforced-guards`).
