# Feature Specification: Session Tail

**Feature**: `session-tail`
**Created**: 2026-08-27
**Status**: Draft

## Clarifications

### Session 2026-08-27

- Q: Qual a unidade e o tamanho-default do tail retornado por `GET /api/v1/sessions/:id/tail`? → A: Linhas, com default de 200 linhas, mais um teto de bytes obrigatorio na resposta como guarda adicional (mesmo modelo mental de `tail -n`; janela de tempo retornaria vazio para sessao parada ha horas; corte por bytes cortaria no meio de uma linha).
- Q: Qual o comportamento do tail ao encontrar uma linha malformada/parcial no arquivo `.jsonl` (por exemplo, escrita concorrente em andamento)? → A: Pular a linha invalida e continuar processando as demais, sinalizando ao operador quantas linhas foram puladas — nunca truncar silenciosamente nem interromper o processamento.
- Q: A listagem de sessoes vivas deve se auto-atualizar ou exigir refresh manual do operador? → A: Auto-atualizacao via `refetchInterval` do `@tanstack/react-query` (mecanismo ja presente no painel); SSE rejeitado por introduzir superficie nova sem ganho proporcional, refresh manual rejeitado por poder mostrar estado velho como se fosse atual.
- Q: O endpoint de tail deve servir conteudo mesmo se a sessao deixou de estar "viva" entre a listagem e a solicitacao? → A: Sim — o tail e servido sob demanda a partir do conteudo do arquivo, independente do atributo derivado de liveness (que muda por conta propria e nao gateia leitura de conteudo ja gravado).
- Q: O reuso exigido pelo edge case do watcher (FR-011) significa a MESMA instancia do watcher existente (`apps/server/src/watchers/ingest-watcher.ts`) ou um modulo novo seguindo o mesmo padrao? → A: Modulo novo seguindo o MESMO PADRAO de `ingest-watcher.ts` (nao estender a mesma instancia) — as raizes observadas, ciclos de vida e modos de falha sao diferentes, e compartilhar instancia acoplaria a ingestao da knowledge-db a uma falha na descoberta de sessoes.

## User Scenarios & Testing

### User Story 1 - Ver sessoes ativas do Claude Code (Priority: P1)

Um operador abre o painel e quer saber, de relance, quais sessoes do Claude
Code estao rodando agora, em quais projetos, sem precisar abrir um terminal
ou vasculhar arquivos manualmente.

**Why this priority**: E o valor central da feature — sem visibilidade de
"o que esta vivo agora", nao ha o que aprofundar. Sozinha ja entrega um MVP
util (um painel de presenca).

**Independent Test**: Com pelo menos uma sessao de Claude Code em execucao
em qualquer projeto local, o operador abre a trilha de sessoes e ve essa
sessao listada com o projeto a que pertence, sem nenhuma outra capacidade
da feature implementada.

**Acceptance Scenarios**:

1. **Given** existem sessoes do Claude Code com atividade recente em um ou
   mais projetos, **When** o operador abre a trilha de sessoes, **Then** o
   painel lista cada sessao ativa junto do projeto (e execucao, quando
   aplicavel) a que pertence.
2. **Given** nenhuma sessao esta ativa no momento, **When** o operador abre
   a trilha de sessoes, **Then** o painel mostra um estado vazio claro, sem
   erro.
3. **Given** uma sessao parou de ter atividade ha mais tempo que a janela de
   "vivo" definida, **When** o operador consulta a trilha, **Then** essa
   sessao NAO aparece mais como ativa.

---

### User Story 2 - Acompanhar o transcript de uma sessao especifica (Priority: P2)

A partir da lista de sessoes vivas, o operador quer abrir uma sessao
especifica e ver a atividade mais recente dela (o "tail" do transcript),
para entender o que o agente esta fazendo agora.

**Why this priority**: Complementa a US1 — a lista sozinha diz "o que esta
vivo", mas o valor de acompanhamento em tempo real vem de ver o conteudo.
Depende de uma sessao ja ter sido identificada pela US1 (ou de um link
direto), por isso vem em segundo lugar.

**Independent Test**: Com o identificador de uma sessao conhecida, o
operador consegue recuperar e visualizar a porcao mais recente do
transcript daquela sessao, mesmo sem a tela de listagem da US1 estar
presente.

**Acceptance Scenarios**:

1. **Given** uma sessao ativa e conhecida pelo seu identificador unico,
   **When** o operador solicita o tail dessa sessao, **Then** o painel
   exibe as ultimas 200 linhas (default) da atividade registrada nela,
   sob demanda, independente de a sessao ainda estar "viva" no momento do
   pedido (FR-003).
2. **Given** o transcript de uma sessao contem conteudo com formatacao ou
   comandos embutidos (por exemplo, texto que parece uma instrucao), **When**
   o operador visualiza o tail, **Then** esse conteudo e exibido como texto
   literal, nunca interpretado ou executado.
3. **Given** duas sessoes de projetos diferentes compartilham o mesmo
   identificador de execucao, **When** o operador abre uma delas a partir
   da lista, **Then** o painel abre exatamente a sessao clicada (nunca a
   sessao do outro projeto) — o roteamento usa o identificador unico da
   propria sessao, nunca o identificador de execucao (FR-004).

---

### User Story 3 - Confiar que a trilha nunca quebra nem suja dados (Priority: P3)

Um operador (ou um revisor tecnico) quer ter certeza de que, mesmo em
condicoes adversas — diretorio de sessoes ausente, arquivo de transcript
gigante, conteudo malicioso embutido — a feature nunca derruba o painel nem
altera qualquer dado do corpus observado.

**Why this priority**: E uma garantia transversal de qualidade/seguranca,
nao uma jornada de descoberta de valor novo — por isso vem por ultimo, mas
e testavel isoladamente e condiciona a confianca no uso das duas stories
anteriores.

**Independent Test**: Simulando cada condicao adversa (diretorio ausente,
arquivo muito grande, conteudo com marcacao ativa) isoladamente, o painel
permanece funcional (sem erro 5xx) e nenhum arquivo de sessao, indice de
conhecimento ou estado de execucao e alterado.

**Acceptance Scenarios**:

1. **Given** o diretorio local de sessoes do Claude Code nao existe ou esta
   vazio, **When** o operador abre a trilha de sessoes, **Then** o painel
   sinaliza um estado degradado/vazio, nunca um erro de servidor (FR-008) —
   e essa sessao, por nao ter atividade recente, tambem nao e apresentada
   como "vivo" (FR-007).
2. **Given** o transcript de uma sessao e muito grande, **When** o operador
   solicita o tail, **Then** o painel retorna apenas a porcao mais recente
   (200 linhas por default, sujeita tambem a um teto de bytes obrigatorio),
   nunca o arquivo inteiro (FR-006).
3. **Given** qualquer numero de consultas de listagem ou tail foi feito
   atraves das capacidades somente-leitura desta feature, **When** se
   inspeciona o sistema de arquivos de sessoes e o indice de conhecimento
   apos essas consultas, **Then** nenhum deles foi escrito, alterado ou
   removido (FR-009), pois nenhuma dessas consultas expoe qualquer
   operacao alem de leitura (FR-010).

---

### Edge Cases

- O que acontece quando o diretorio de sessoes existe mas nao tem permissao
  de leitura? Mesmo tratamento do diretorio ausente: degradar, nunca erro
  5xx.
- Como o sistema lida com um arquivo de transcript sendo escrito no exato
  momento da leitura (sessao realmente ativa, escrita concorrente)? A
  leitura deve considerar apenas o conteudo ja gravado no momento da
  consulta, sem travar nem corromper a exibicao. Se a escrita concorrente
  deixar uma linha `.jsonl` malformada/parcial, essa linha e pulada e o
  processamento continua com as demais, sinalizando ao operador quantas
  linhas foram puladas (FR-003a) — nunca truncar silenciosamente nem
  interromper a resposta.
- O que acontece se duas sessoes, de projetos diferentes, tiverem o mesmo
  identificador de execucao? A identificacao/roteamento usa o identificador
  proprio da sessao, nunca o identificador de execucao isoladamente.
- Como o sistema se comporta se um transcript contiver conteudo desenhado
  para se passar por uma instrucao ao operador ou ao painel (tentativa de
  injecao)? O conteudo e sempre tratado como dado exibido, nunca como
  comando.
- O que acontece quando uma sessao que estava viva para de ter atividade
  enquanto o operador a observa? Ela deixa de ser sinalizada como "vivo" no
  proximo ciclo de atualizacao da tela, sem exigir acao do operador.
- O que acontece se ja existir, no painel, um mecanismo de descoberta/
  monitoramento de atividade em segundo plano equivalente ao que esta
  feature precisaria (`apps/server/src/watchers/ingest-watcher.ts`)? Esta
  feature reusa o PADRAO desse mecanismo — um modulo novo, com o mesmo
  desenho — em vez de estender a mesma instancia ou introduzir um segundo
  watcher concorrente sobre os mesmos dados (FR-011). Raizes observadas
  (state dirs de execucao vs `~/.claude/projects/**`), ciclos de vida e
  modos de falha sao diferentes; compartilhar a instancia acoplaria a
  ingestao da knowledge-db a uma eventual falha na descoberta de sessoes.

## Requirements

### Functional Requirements

- **FR-001**: System MUST discover active Claude Code sessions by
  observando a atividade recente (recencia) dos registros de sessao
  presentes no armazenamento local do Claude Code, sem exigir configuracao
  manual de quais sessoes existem.
- **FR-002**: System MUST provide a way to list all currently-live
  sessions, informando a qual projeto (e, quando disponivel, a qual
  execucao de agente autonomo) cada sessao pertence. The listing MUST
  keep itself current via automatic re-fetch (`refetchInterval` of the
  panel's existing `@tanstack/react-query` mechanism) rather than
  requiring a manual refresh from the operator.
- **FR-003**: System MUST provide a way to retrieve the most recent portion
  ("tail") of a specific session's activity on demand, measured in lines
  (default: 200 lines), and MUST serve this content regardless of whether
  the session is still considered "live" at request time — tail reads are
  never gated by the derived liveness attribute, only by the session's own
  identifier existing.
- **FR-003a**: System MUST skip malformed/partial lines encountered while
  parsing a session's `.jsonl` transcript (e.g., concurrent write in
  progress) and continue processing the remaining lines, surfacing to the
  caller how many lines were skipped — it MUST NOT silently truncate the
  tail nor abort the request because of a malformed line.
- **FR-004**: System MUST route session-detail/tail requests by the
  session's own unique identifier, never solely by execution identifier
  (execution identifiers are not guaranteed unique across projects).
- **FR-005**: System MUST treat all session activity/transcript content as
  untrusted data: rendered as literal text, with no interpretation of
  embedded markup or instructions as commands.
- **FR-006**: System MUST bound the amount of content returned per tail
  request to a recent slice (default 200 lines), rather than transmitting
  a session's entire history, AND MUST additionally enforce a mandatory
  byte-size cap on the response regardless of line count — a single
  `.jsonl` line can itself contain megabytes of embedded content (e.g., a
  file dump), so the line-based bound alone is not a sufficient guard.
- **FR-007**: System MUST distinguish sessions that are currently live from
  sessions that have gone stale, and MUST NOT present a stale session as
  ongoing.
- **FR-008**: System MUST degrade to an empty/informative result (never an
  error) when the underlying sessions storage is absent, empty, or
  unreadable.
- **FR-009**: System MUST NOT write, modify, or delete any session
  activity record, the derived knowledge index, or any execution state as
  part of discovering or displaying sessions.
- **FR-010**: Every capability introduced by this feature MUST be exposed
  exclusively through read operations — none of them may alter any data.
- **FR-011**: System MUST NOT introduce a second, redundant discovery/
  monitoring mechanism for session or execution activity when an
  equivalent mechanism already exists for that class of problem. This
  reuse applies at the level of the PATTERN established by the existing
  watcher (`apps/server/src/watchers/ingest-watcher.ts`) — the feature
  MUST implement a new module following that same pattern, not extend or
  share the existing watcher's own instance/lifecycle (different watch
  roots, different failure modes; sharing the instance would couple
  knowledge-db ingestion availability to session discovery failures).

> Decisoes de infraestrutura: N/A (feature stateless do ponto de vista do
> painel — nao ha scheduling novo, criptografia, rotacao de chaves, refresh
> de token externo ou lock multi-pod introduzidos por ela).

### Key Entities

- **Live Session**: representa uma sessao do Claude Code em atividade
  recente; identificada por um identificador proprio unico, associada a um
  projeto e, quando aplicavel, a uma execucao de agente autonomo; carrega o
  instante de ultima atividade usado para decidir se ainda esta "viva".
- **Session Activity Tail**: a porcao mais recente do historico de eventos
  de uma sessao; conteudo de origem nao confiavel (agente), exibido como
  texto literal.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Um operador consegue ver todas as sessoes atualmente ativas
  em todos os projetos em ate 5 segundos apos abrir a trilha de sessoes.
- **SC-002**: Um operador consegue abrir qualquer sessao viva e ver sua
  atividade mais recente sem precisar conhecer previamente identificadores
  internos.
- **SC-003**: Quando nao ha nenhuma sessao ativa, o operador ve um estado
  vazio claro, com 0% de paginas de erro nessa condicao.
- **SC-004**: Uma sessao que para de ter atividade por mais que a janela de
  "vivo" definida (default: 5 minutos de inatividade) deixa de ser exibida
  como "vivo" em ate um ciclo de atualizacao da tela.
- **SC-005**: 100% do conteudo de transcript exibido e renderizado como
  texto puro — zero ocorrencias de marcacao/script embutido sendo
  interpretado ou executado no navegador.

## Delta Requirements

**Skip**: nao ha corpus canonico em `docs/specs/current/` no repositorio
ainda (diretorio inexistente) e a feature nao altera nenhum comportamento
ja documentado ali — e capacidade inteiramente nova. — agente-00c-feature-orchestrator, 2026-08-27
