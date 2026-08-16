# Feature Specification: Allowlist MCP para orquestradores 00c

**Feature**: `orchestrator-mcp-allowlist`
**Created**: 2026-08-15
**Status**: Draft

## User Scenarios & Testing

### User Story 1 - Guard protege a garantia real, nao a premissa errada (Priority: P1)

Hoje a suite de testes do toolkit proibe qualquer tool `mcp__*` no
frontmatter `tools:` dos dois orquestradores autonomos, sob a premissa de
que listar essas tools quebraria a garantia de degradacao graciosa quando
o servidor MCP de estado esta indisponivel. Uma sondagem empirica mostrou
que essa premissa esta errada: o que de fato quebra a garantia e uma
allowlist composta **somente** por tools `mcp__*` (sem nenhuma tool nativa
de fallback) — nesse caso o subagente e recusado antes mesmo de ser
spawnado. Uma allowlist mista (tools nativas + `mcp__*`) e segura mesmo
com o servidor ausente: a tool MCP nao-resolvida e descartada em
silencio e o caminho nativo continua funcionando.

**Why this priority**: sem revogar a premissa errada, nenhuma outra story
desta feature pode avancar — a suite atual bloqueia qualquer tentativa de
listar `mcp__*` no frontmatter.

**Independent Test**: rodar a suite de testes do toolkit antes e depois da
mudanca; confirmar que os dois scenarios antigos (que falhavam ao
encontrar `mcp__*` no frontmatter) deixam de existir e que um guard novo
falha quando, e somente quando, a allowlist de um orquestrador resolve
para conjunto vazio ou e composta exclusivamente por tools `mcp__*`.

**Acceptance Scenarios**:

1. **Given** a suite de testes do toolkit, **When** executada apos a
   mudanca, **Then** nao existe mais nenhum teste que falhe pela mera
   presenca de uma entrada `mcp__*` no frontmatter `tools:` de um
   orquestrador.
2. **Given** o guard novo, **When** o frontmatter `tools:` de um
   orquestrador e composto exclusivamente por entradas `mcp__*` (sem
   nenhuma tool nativa), **Then** o guard falha e reporta a violacao.
3. **Given** o guard novo, **When** o frontmatter `tools:` de um
   orquestrador contem uma mistura de tools nativas e `mcp__*`, **Then**
   o guard passa.

---

### User Story 2 - Orquestradores ganham acesso as operacoes de estado via MCP (Priority: P1)

Os dois orquestradores autonomos (raiz e de feature individual) devem
poder chamar as operacoes de estado (abrir onda, registrar decisao,
registrar skill invocada, registrar task, registrar bloqueio humano,
fechar onda, consultar status da execucao) atraves do servidor MCP de
estado quando ele estiver disponivel — sem perder a capacidade de fazer
exatamente as mesmas operacoes via linha de comando quando o servidor nao
estiver.

**Why this priority**: e o proposito central da feature — sem isso, o
servidor MCP de estado (ja implementado e rodando com
`mode=docker`/`status=active`) permanece inacessivel aos unicos agentes
que deveriam consumi-lo.

**Independent Test**: com o servidor MCP de estado ativo, spawnar cada um
dos dois orquestradores e confirmar que cada uma das operacoes de estado
esta disponivel para chamada; com o servidor MCP ausente/parado, repetir
e confirmar que a execucao continua identica via o caminho nativo.

**Acceptance Scenarios**:

1. **Given** o servidor MCP de estado ativo e autenticado para a execucao
   corrente, **When** um orquestrador precisa registrar uma decisao,
   **Then** a operacao de registrar decisao esta acessivel a ele via MCP.
2. **Given** o servidor MCP de estado indisponivel, **When** o mesmo
   orquestrador precisa registrar a mesma decisao, **Then** a operacao e
   concluida via o caminho nativo, sem erro visivel ao operador e sem
   pausa da execucao.
3. **Given** os dois orquestradores (raiz e de feature), **When** cada um
   e inspecionado individualmente, **Then** ambos expoem as mesmas sete
   operacoes de estado da mesma forma.

---

### User Story 3 - Orientacao clara sobre quando usar MCP vs. caminho nativo (Priority: P2)

Nenhum dos dois orquestradores documenta hoje como decidir entre chamar
uma operacao de estado via MCP ou via o caminho nativo, nem como detectar
que o servidor MCP esta indisponivel. Sem essa orientacao, um orquestrador
autonomo pode tentar repetidamente a via MCP mesmo apos ela falhar, ou
nunca tentar usa-la mesmo quando disponivel.

**Why this priority**: instrumental para a Story 2 ter efeito pratico —
acesso as tools sem orientacao de uso gera comportamento inconsistente
entre execucoes.

**Independent Test**: revisar a definicao de cada orquestrador e confirmar
que a orientacao descreve explicitamente quando preferir cada caminho,
como detectar indisponibilidade, e que o caminho nativo e sempre uma
alternativa segura que nunca interrompe a execucao.

**Acceptance Scenarios**:

1. **Given** a definicao de um orquestrador, **When** revisada, **Then**
   contem orientacao explicita de quando preferir a via MCP e quando cair
   para o caminho nativo.
2. **Given** essa orientacao, **When** o servidor MCP fica indisponivel no
   meio de uma execucao, **Then** o orquestrador segue a orientacao para
   comutar para o caminho nativo sem pausar a onda.

---

### User Story 4 - Roteamento por sessao validado no caminho real (Priority: P2)

O mecanismo que garante que cada execucao autonoma so consegue mutar o
proprio estado (nunca o de uma execucao concorrente) via MCP depende de
cada chamada apresentar o token de sessao correto. Esse mecanismo ja foi
implementado, mas nunca foi validado com uma chamada de fato originada de
um subagente orquestrador — apenas por testes que simulam a chamada.

**Why this priority**: e uma validacao de seguranca, nao um novo
comportamento — prioridade menor que expor e documentar o acesso, mas
necessaria antes de considerar o acesso MCP confiavel em producao.

**Independent Test**: com dois state-dirs de execucoes diferentes ativos
simultaneamente, fazer um orquestrador chamar uma operacao de estado via
MCP com o proprio token e confirmar que ela afeta somente o proprio
state-dir; repetir com um token de outra execucao (ou ausente) e confirmar
rejeicao.

**Acceptance Scenarios**:

1. **Given** um orquestrador com o token de sessao correto para sua
   propria execucao, **When** ele chama uma operacao de estado via MCP,
   **Then** a operacao e aceita e afeta somente o state-dir da propria
   execucao.
2. **Given** uma chamada de operacao de estado via MCP com token ausente
   ou pertencente a outra execucao, **When** ela chega ao servidor,
   **Then** e rejeitada e nenhum state-dir e afetado.

---

### Edge Cases

- O que acontece quando o servidor MCP esta ativo mas retorna erro para
  uma chamada especifica (nao indisponibilidade total, mas falha de uma
  operacao)? A orientacao de uso (Story 3) deve cobrir esse caso, nao
  apenas "servidor ausente".
- Como o guard (Story 1) deve reagir se um terceiro arquivo de agente
  orquestrador for adicionado no futuro com uma allowlist somente-MCP?
  Deve generalizar para qualquer agente que siga o mesmo padrao, nao
  hardcodear apenas os dois arquivos atuais.
- O que acontece quando o conjunto de tools exposto pelo servidor MCP
  mudar (uma operacao for renomeada ou removida) e o frontmatter ainda
  referenciar o nome antigo? A chamada deve degradar para o caminho
  nativo, nunca travar a onda.

## Requirements

### Functional Requirements

- **FR-001**: A suite de testes do toolkit MUST NOT conter nenhum teste
  que falhe apenas pela presenca de uma entrada `mcp__*` no frontmatter
  `tools:` de um orquestrador autonomo.
- **FR-002**: O sistema MUST fornecer um guard automatizado e
  deterministico que falha quando, e somente quando, o frontmatter
  `tools:` de um orquestrador resolve para conjunto vazio OU e composto
  exclusivamente por entradas `mcp__*` (nenhuma tool nativa de fallback
  presente).
- **FR-003**: Os dois orquestradores autonomos (raiz e de feature
  individual) MUST listar, no proprio frontmatter `tools:`, as operacoes
  de estado expostas pelo servidor MCP de estado, em adicao as (nunca em
  substituicao das) tools nativas ja listadas.
- **FR-004**: Os dois orquestradores autonomos MUST manter pelo menos uma
  tool nativa de fallback (no minimo, a tool de execucao de comandos) no
  proprio frontmatter `tools:` a qualquer momento, de forma que um
  subagente nunca seja recusado por allowlist somente-MCP nem spawnado
  sem nenhuma tool utilizavel.
- **FR-005**: A definicao de cada um dos dois orquestradores MUST incluir
  orientacao explicita sobre quando preferir uma chamada via MCP e quando
  usar o caminho nativo equivalente para a mesma operacao de estado.
- **FR-006**: Essa orientacao MUST descrever como o orquestrador detecta
  que uma operacao via MCP nao esta disponivel (servidor ausente, tool
  nao resolvida, sessao nao autenticada) e confirmar que o caminho nativo
  permanece disponivel como alternativa em todos esses casos.
- **FR-007**: O sistema MUST preservar, sem enfraquecer, a garantia de
  que a indisponibilidade do servidor MCP de estado nunca degrada a
  funcionalidade da execucao autonoma nem exige intervencao manual — esta
  feature muda apenas o mecanismo que protege essa garantia (de "proibir
  `mcp__*` no frontmatter" para "guard anti-allowlist-somente-MCP"),
  nunca a garantia em si.
- **FR-008**: O sistema MUST ser validado, por pelo menos uma chamada real
  originada de um subagente orquestrador, de que o roteamento por token de
  sessao aceita chamadas com o token correto da propria execucao e
  rejeita chamadas com token ausente ou pertencente a outra execucao.
- **FR-009**: Sistema MUST [NEEDS CLARIFICATION: existe um teto pratico
  recomendado para o numero de tools `mcp__*` que podem coexistir na
  allowlist `tools:` de um subagente sem degradar a resolucao/spawn? Se
  existir, qual e como as sete operacoes do servidor de estado devem
  respeita-lo?]
- **FR-010**: Sistema MUST [NEEDS CLARIFICATION: qual e o comportamento
  esperado de uma tool MCP do tipo elicitation/create quando invocada por
  um subagente orquestrador dentro de uma execucao autonoma sem operador
  humano presente para responder — timeout, fallback automatico para o
  caminho nativo, ou bloqueio humano?]

> Decisoes de infraestrutura: N/A (feature nao introduz scheduling, key
> rotation, refresh de token externo, mutex multi-pod, backup/restore ou
> idempotencia novos — reusa o mecanismo de sessao ja existente do
> servidor MCP de estado).

## Success Criteria

### Measurable Outcomes

- **SC-001**: 100% das execucoes autonomas (agente-00c e feature-00c)
  completam a onda corrente sem bloqueio humano nem falha, independente
  de o servidor MCP de estado estar disponivel ou nao — preserva o
  invariante registrado como SC-004 em
  `docs/specs/_archived/2026-08-03-state-mcp-server/spec.md`; o mecanismo
  de protecao muda, a garantia nao.
- **SC-002**: As sete operacoes de estado do servidor MCP (abrir onda,
  registrar decisao, registrar skill invocada, registrar task, registrar
  bloqueio humano, fechar onda, consultar status) ficam acessiveis a
  partir de dentro de uma execucao autonoma quando o servidor MCP esta
  ativo, cada uma verificavel por uma chamada real bem-sucedida.
- **SC-003**: Um guard automatizado bloqueia 100% das configuracoes de
  allowlist que deixem um orquestrador sem nenhuma tool de fallback
  nativo, antes que a mudanca seja aceita.
- **SC-004**: Uma chamada de operacao de estado feita com o token de
  sessao correto e aceita, e uma chamada com token ausente ou divergente
  e rejeitada — validado por pelo menos um caso real de cada categoria.
- **SC-005**: A suite de testes do toolkit permanece 100% verde apos a
  mudanca de guard, sem perda de cobertura sobre o comportamento que
  continua valido (allowlist nunca vazia, fallback nativo sempre
  presente).

## Delta Requirements

**Skip**: nenhuma capability documentada em docs/specs/current/ cobre a allowlist tools: dos orquestradores 00c ou o guard que a protege; feature introduz capability nova sem substituir comportamento hoje registrado no corpus canonico — agente-00c-feature-orchestrator, 2026-08-15
