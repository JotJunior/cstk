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

- **Resolvido (clarify)**: quando o servidor MCP esta ativo mas retorna
  erro para uma chamada especifica (nao indisponibilidade total), o
  orquestrador NAO tenta novamente — aplica fallback imediato uniforme
  para o caminho nativo, no mesmo contrato de queda mid-onda ja vigente
  em `plugins/cstk/commands/feature-00c.md:738` e
  `plugins/cstk/commands/agente-00c.md:497` (ver `## Clarifications`).
  A orientacao de uso (Story 3 / FR-005/FR-006) cobre este caso
  explicitamente, nao apenas "servidor ausente".
- **Resolvido (clarify)**: o guard (Story 1) reage a um terceiro arquivo
  de agente orquestrador futuro por deteccao de padrao de nome (sufixo
  `-orchestrator.md`) em `plugins/cstk/agents/`, nunca por lista
  hardcodeada dos dois arquivos atuais (ver `## Clarifications` e
  FR-002).
- O que acontece quando o conjunto de tools exposto pelo servidor MCP
  mudar (uma operacao for renomeada ou removida) e o frontmatter ainda
  referenciar o nome antigo? A chamada deve degradar para o caminho
  nativo, nunca travar a onda.

## Clarifications

### Session 2026-08-16

- Q: Como o guard deve identificar quais arquivos de agente sao
  "orquestradores autonomos" sujeitos a regra (allowlist nunca
  vazia/nunca somente-MCP), de forma que generalize para um terceiro
  orquestrador futuro sem edicao manual do guard? → A: deteccao por
  padrao de nome (sufixo `-orchestrator`) em `plugins/cstk/agents/`.
  Verificacao empirica (`ls plugins/cstk/agents/ | grep 'orchestrator\.md$'`):
  o padrao casa exatamente 2 dos 7 arquivos de agente
  (`agente-00c-orchestrator.md`, `agente-00c-feature-orchestrator.md`) e
  nenhum outro (`agente-00c-clarify-asker.md`,
  `agente-00c-clarify-answerer.md`, `feature-00c-clarify-asker.md`,
  `feature-00c-clarify-answerer.md`, `data-veracity-verifier.md`).
  Generaliza para um terceiro orquestrador futuro sem edicao manual do
  guard.
- Q: Onde e em que formato a orientacao de uso MCP-vs-nativo (Story 3)
  deve viver dentro da definicao de cada orquestrador? → A: secao
  dedicada autocontida em CADA um dos 2 arquivos de orquestrador
  (`plugins/cstk/agents/agente-00c-orchestrator.md` e
  `plugins/cstk/agents/agente-00c-feature-orchestrator.md`), nao um
  ponteiro para doc externo — o agente le a propria definicao no spawn e
  um ponteiro custaria um Read adicional, podendo ser ignorado em
  runtime. A duplicacao (~10 linhas x2) e mitigada por um teste de
  paridade entre os dois blocos (novo requisito FR-011).
- Q: Quando o servidor MCP esta ativo mas uma chamada especifica retorna
  erro (nao indisponibilidade total), o orquestrador deve tentar
  novamente antes de cair para o caminho nativo, ou tratar como
  qualquer outra forma de indisponibilidade? → A: fallback imediato
  uniforme, sem retry — alinhado ao contrato ja vigente no repo, nao uma
  preferencia nova. Fonte literal:
  `plugins/cstk/commands/feature-00c.md:738` e
  `plugins/cstk/commands/agente-00c.md:497` especificam, ambos, o mesmo
  texto: "em erro de transporte, contrato de queda mid-onda (0 retries +
  1 confirmacao via `cstk mcp status --live`) e comutacao para Bash no
  resto da onda." Retry exigiria emendar os dois commands e
  contradiria o contrato ja documentado.
- Q: O guard novo (FR-002) deve ser implementado como teste automatizado
  em `tests/` (harness) ou script separado? → A: teste em `tests/`,
  integrado a `./tests/run.sh` e ao gate de release — convergencia entre
  briefing.md ("Testes para scripts shell") e constitution.md v1.3.0
  ("Scripts tem teste automatizado ... detectavel via
  `tests/run.sh --check-coverage`").

## Requirements

### Functional Requirements

- **FR-001**: A suite de testes do toolkit MUST NOT conter nenhum teste
  que falhe apenas pela presenca de uma entrada `mcp__*` no frontmatter
  `tools:` de um orquestrador autonomo.
- **FR-002**: O sistema MUST fornecer um guard automatizado e
  deterministico que falha quando, e somente quando, o frontmatter
  `tools:` de um orquestrador resolve para conjunto vazio OU e composto
  exclusivamente por entradas `mcp__*` (nenhuma tool nativa de fallback
  presente). O guard MUST identificar "orquestrador" por deteccao de
  padrao de nome (arquivo `*-orchestrator.md` em `plugins/cstk/agents/`),
  nunca por lista hardcodeada dos dois arquivos atuais — generaliza sem
  edicao manual para um terceiro orquestrador futuro que siga o mesmo
  padrao (ver `## Clarifications`).
- **FR-003**: Os dois orquestradores autonomos (raiz e de feature
  individual) MUST listar, no proprio frontmatter `tools:`, as operacoes
  de estado expostas pelo servidor MCP de estado, em adicao as (nunca em
  substituicao das) tools nativas ja listadas.
- **FR-004**: Os dois orquestradores autonomos MUST manter pelo menos uma
  tool nativa de fallback (no minimo, a tool de execucao de comandos) no
  proprio frontmatter `tools:` a qualquer momento, de forma que um
  subagente nunca seja recusado por allowlist somente-MCP nem spawnado
  sem nenhuma tool utilizavel.
- **FR-005**: A definicao de cada um dos dois orquestradores MUST incluir,
  em uma secao dedicada e autocontida DENTRO do proprio arquivo de
  definicao do agente (nunca uma referencia/ponteiro a um doc externo
  compartilhado — ver `## Clarifications`), orientacao explicita sobre
  quando preferir uma chamada via MCP e quando usar o caminho nativo
  equivalente para a mesma operacao de estado.
- **FR-006**: Essa orientacao MUST descrever como o orquestrador detecta
  que uma operacao via MCP nao esta disponivel (servidor ausente, tool
  nao resolvida, sessao nao autenticada, OU erro pontual de uma chamada
  especifica com o servidor ativo) e confirmar que o caminho nativo
  permanece disponivel como alternativa em todos esses casos. Para erro
  pontual de chamada (servidor ativo, uma operacao falha), a orientacao
  MUST prescrever fallback imediato para o caminho nativo, sem retry —
  o mesmo contrato de queda mid-onda ja documentado em
  `plugins/cstk/commands/feature-00c.md:738` e
  `plugins/cstk/commands/agente-00c.md:497` (0 retries + 1 confirmacao
  via `cstk mcp status --live` + comutacao para Bash no resto da onda).
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
- **FR-009**: Resolvido por sondagem empirica (claude-code 2.1.233):
  nenhum teto foi observado ate 25 tools `mcp__*` coexistindo com uma tool
  nativa (`Bash`) na mesma allowlist — o subagente enxergou as 25 sem
  lacunas e uma chamada real (`mcp__many__t17`) foi recebida e respondida
  pelo servidor. As sete operacoes do servidor MCP de estado (~28% dessa
  margem observada, folga de ~3,5x) MUST coexistir na allowlist sem
  necessidade de mecanismo de rodizio/particionamento. Esta MUST NOT ser
  lida como "sem limite" — 25 foi o maximo efetivamente testado, nao um
  teto teorico do harness.
- **FR-010**: **Deferred — fonte pendente.** O comportamento de uma tool
  MCP do tipo elicitation/create invocada por um subagente orquestrador
  sem operador humano presente para responder (timeout? fallback
  automatico para o caminho nativo? bloqueio humano?) MUST ser definido
  antes da implementacao desta requisito especifico, mas NAO MUST bloquear
  as demais FRs desta feature — a sondagem empirica que mediria esse
  comportamento esta em curso, fora do escopo desta execucao. Nenhum
  comportamento MUST ser suposto sem essa fonte (Principio VI); quando a
  medicao concluir, este FR MUST ser atualizado com a fonte e removido do
  estado Deferred antes de `plan` assumir um comportamento concreto para
  ele. Ate la, a orientacao de uso (FR-005/FR-006) MUST tratar
  elicitation/create como fora de escopo de uso ativo pelos orquestradores
  autonomos (eles nao devem invocar operacoes que dependam de elicitation
  sem essa definicao).
- **FR-011**: O sistema MUST fornecer um teste automatizado de PARIDADE
  entre a secao de orientacao MCP-vs-nativo (FR-005/FR-006) dos dois
  arquivos de orquestrador, garantindo que a duplicacao deliberada
  (ver `## Clarifications`) nao diverge silenciosamente entre
  `agente-00c-orchestrator.md` e `agente-00c-feature-orchestrator.md`.
- **FR-012**: O guard de FR-002 MUST ser implementado como teste
  automatizado dentro de `tests/` (nao um script separado fora do
  harness), integrado a `./tests/run.sh` e ao `--check-coverage`
  (ver `## Clarifications`, convergente com dec-011).
- **FR-013**: Numa execucao autonoma normal (`/feature-00c` ou
  `/agente-00c`) cujo servidor MCP de estado esteja ativo, as sete
  operacoes de estado MUST estar efetivamente disponiveis como tools no
  contexto do orquestrador, **sem nenhuma intervencao manual do
  operador** — sem exportar variavel de ambiente a mao, sem editar
  `.mcp.json` por execucao e sem qualquer passo fora do fluxo ja
  executado pelos commands pai. "Disponivel" MUST ser medido no
  servidor registrado em `.mcp.json`, por um `tools/list` que devolva as
  sete tools; um servidor que apenas figure como conectado, devolvendo
  lista vazia, MUST NOT ser contado como disponivel.
- **FR-014**: A ordem causal do bloqueio MUST ser tratada como parte do
  requisito, nesta ordem: **(1)** enquanto o processo do launcher servir
  zero tools, o caminho MCP e inalcancavel para **todos** os
  consumidores — main loop inclusive —, e **(2)** so entao a allowlist
  do frontmatter (FR-003) passa a decidir se um subagente orquestrador
  enxerga aquelas tools. Consequencia que MUST constar sem eufemismo: o
  trabalho de FR-001 a FR-012 (guard, revogacao do guard antigo,
  allowlist, bloco de orientacao) esta correto e e **necessario**, mas
  **nao e suficiente** — sozinho ele nao produz nenhuma mudanca
  observavel, porque a causa (1) o precede. Enquanto (1) nao for
  resolvida, SC-002 e SC-004 MUST NOT ser declarados satisfeitos com
  base na conclusao de FR-003.
  Evidencia direta da causa (1), colhida nesta feature (onda-010):
  o `.mcp.json` do projeto registra o launcher com `"args": []` e **sem
  bloco `env`**; `mcp-launch.sh:128` (`if [ -z "${MCP_SESSION_TOKEN:-}"
  ]; then` / `_ml_idle_serve "nenhuma execucao 00c ativa nesta sessao
  (sem token)"`) testa **apenas** a variavel de ambiente antes de cair em
  modo idle; e o handshake manual do launcher, invocado como o
  `.mcp.json` o invoca, respondeu
  `"serverInfo":{"name":"cstk-state-idle","version":"idle"}` seguido de
  `"result":{"tools":[]}` — com a execucao corrente **ativa**
  (`cstk mcp status --live` => `status=active`, `mode=docker`,
  `stopped_at: null`).
- **FR-015**: [NEEDS CLARIFICATION: qual canal entrega o token de
  capacidade ao processo do launcher?] Para satisfazer FR-013, o token
  da execucao corrente precisa alcancar o processo que serve o stdio do
  MCP. Qualquer resposta MUST preservar **simultaneamente** os dois
  invariantes abaixo, e nenhuma reconciliacao entre eles MUST ser
  suposta sem fonte:
  1. **SEC-H3** (`docs/specs/_archived/2026-08-03-state-mcp-server/
     contracts/mcp-session-lifecycle.md` §SEC-H3): o roteamento de
     mutacao e por **posse de token de capacidade**, "**nunca** por
     precedencia" e "**sem** fallback para 'a execucao ativa mais
     provavel'". Um launcher que descubra sozinho a execucao ativa e se
     auto-autorize reintroduz exatamente o confused deputy (ASI03) que
     SEC-H3 existe para impedir — com duas execucoes ativas, ele teria
     de eleger uma, violando FR-008.
  2. **Momento de existencia do token**: o servidor stdio e conectado
     pelo harness no **boot da sessao**, e o token so passa a existir
     quando `cstk mcp start` roda, ja dentro de uma sessao em pe. O
     mesmo contrato SEC-H3 preve, na linha "Entrega", que "o **command
     pai** injeta o token no prompt de spawn do orquestrador" — canal
     que entrega o token ao **orquestrador**, mas **nao** ao processo do
     launcher, que nao e spawnado pelo command pai. Essa lacuna de canal
     e reconhecida na fonte: `mcp-launch.sh:21-25` registra (dec-043)
     que "a geracao/injecao REAL do token pelos commands pai
     (/agente-00c, /feature-00c) fica FORA do escopo desta feature" e que
     ate la um "token SINTETICO exportado na mesma env" cobre o
     roteamento.
  Nota factual relevante para quem responder (nao e a resposta):
  `mcp-session.sh resolve` ja aceita o token por tres fontes — `--token`,
  `--token-file` e a env `MCP_SESSION_TOKEN`, nessa precedencia —
  enquanto `mcp-launch.sh:128` consulta somente a env antes de cair em
  idle.

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

**Delta**: expansao de escopo (FR-013, FR-014, FR-015) decidida pelo operador apos a validacao empirica da FASE 6 provar que a feature, como especificada em FR-001..FR-012, nao torna o caminho MCP alcancavel: o launcher serve zero tools para todos os consumidores porque so le o token da env, ausente no processo que o harness conecta no boot. MODIFICA o alcance desta feature (o escopo passa a incluir a alcancabilidade do caminho MCP, antes pressuposta), NAO substitui nem revoga FR-001..FR-012, que permanecem corretos e necessarios. FR-015 fica com [NEEDS CLARIFICATION] em aberto: o canal de entrega do token ao processo do launcher nao pode ser definido sem violar SEC-H3 ou sem fonte nova, e nenhuma reconciliacao foi suposta — agente-00c-feature-orchestrator, 2026-08-16
