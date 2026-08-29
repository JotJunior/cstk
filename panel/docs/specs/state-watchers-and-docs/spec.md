# Feature Specification: Watchers de Execução em Andamento e Visualização de Documentação

**Feature**: `state-watchers-and-docs`
**Created**: 2026-07-15
**Status**: Draft

## Clarifications

### Session 2026-07-15

- Q: Qual é a fonte de verdade para resolver o caminho absoluto de um projeto
  no sistema de arquivos a partir do nome lógico (`project`) já armazenado na
  `knowledge.db`? → A: Configuração mantida pelo operador do painel — um
  mapeamento nome lógico → caminho absoluto — seguindo o mesmo padrão de
  resolução já adotado para o caminho da `knowledge.db` (flag/config
  explícita > variável de ambiente > default). A `knowledge.db` não ganha
  coluna nova nesta feature; o gap #7 de `docs/specs/cstk-panel/data-gaps.md`
  segue documentado.
- Q: O back-end do painel aciona proativamente o processo de ingestão
  canônico para execuções em andamento, ou apenas consome o resultado já
  produzido pelo hook fim-de-onda existente? → A: Aciona proativamente, em
  cadência recorrente e somente enquanto houver execução em andamento —
  sempre delegando ao processo de ingestão canônico já existente, nunca
  escrevendo diretamente na `knowledge.db`, nunca tocando `state.json` e
  nunca reconstruindo o índice (`--reindex`, cujo dono é externo ao painel).
- Q: O painel conhece de antemão um mapeamento fixo etapa-SDD → artefato(s)
  esperado(s), ou descobre dinamicamente qualquer arquivo presente na árvore
  de documentação? → A: Mapeamento fixo por etapa do pipeline SDD, que
  habilita o estado "ainda não produzido" exigido por FR-007; arquivos
  adicionais presentes na árvore de documentação da feature continuam
  listáveis e visualizáveis (SC-002 exige 100% dos artefatos já produzidos).

## User Scenarios & Testing

### User Story 1 - Acompanhar execuções em andamento quase em tempo real (Priority: P1)

Um usuário mantém o painel aberto enquanto uma execução `agente-00c` ou
`feature-00c` está rodando em um dos seus projetos. Hoje, o status exibido só
muda quando o orquestrador termina uma onda e roda a ingestão para a
`knowledge.db` — o que pode levar minutos ou mais, dependendo da duração da
onda corrente. O usuário quer que o painel reflita o progresso (novas ondas,
decisões, mudança para "aguardando humano" ou "concluída") pouco depois de
acontecer, sem precisar recarregar a página manualmente nem esperar a onda
inteira terminar para ver qualquer sinal de vida.

**Why this priority**: é o ponto de frustração citado em primeiro lugar e com
mais ênfase — a demora entre o que realmente aconteceu na execução e o que o
painel mostra é o problema central que motiva esta feature. Sem resolver
isso, o painel continua sendo consultado "às cegas" durante execuções longas.

**Independent Test**: a partir do estado "execução com status em andamento",
provocar uma mudança observável (nova onda concluída, nova decisão registrada,
transição para aguardando humano) e verificar que o painel passa a refletir
essa mudança dentro do prazo definido em SC-001, sem ação manual do usuário.

**Acceptance Scenarios**:

1. **Given** uma execução com status "em andamento", **When** uma nova onda é
   concluída nessa execução, **Then** o painel reflete o novo estado (contagem
   de ondas, última decisão, etapa corrente) sem que o usuário precise
   recarregar a página.
2. **Given** uma execução em andamento passa a "aguardando humano", **When** o
   usuário está com o painel aberto, **Then** essa transição de status aparece
   refletida dentro do mesmo prazo de atualização.
3. **Given** nenhuma execução em andamento em nenhum projeto observado,
   **When** o painel está aberto, **Then** o mecanismo de observação permanece
   ocioso, sem gerar verificação contínua desnecessária.
4. **Given** uma execução em andamento conclui ou é abortada, **When** a
   próxima verificação ocorre, **Then** o sistema para de observá-la
   ativamente (ela passa a ser tratada como dado histórico, não mais
   monitorado).

---

### User Story 2 - Visualizar artefatos de documentação da feature dentro do painel (Priority: P2)

Um usuário quer acompanhar o conteúdo escrito durante a execução — a
especificação, o plano técnico, o backlog de tarefas e demais documentos
gerados pela pipeline — sem sair do painel para abrir o editor ou o
terminal. Hoje essa visão só existe fora do painel, direto nos arquivos do
projeto.

**Why this priority**: complementa a User Story 1 (status) com o conteúdo por
trás do status. É valiosa por si só e testável de forma independente, mas
depende de o painel conseguir localizar os arquivos do projeto no sistema de
arquivos (ver FR-008), por isso vem em seguida à P1.

**Independent Test**: a partir do estado "uma feature já tem `spec.md`
gerado", abrir a visão dessa feature no painel e verificar que o conteúdo do
`spec.md` aparece renderizado, sem precisar abrir o arquivo em outra
ferramenta.

**Acceptance Scenarios**:

1. **Given** uma feature com `spec.md` já gerado, **When** o usuário abre a
   visão dessa feature no painel, **Then** o conteúdo do `spec.md` é exibido
   formatado (não como texto bruto) dentro do painel.
2. **Given** uma feature que ainda não passou pela etapa de plano técnico,
   **When** o usuário tenta visualizar o artefato "plano", **Then** o painel
   indica claramente que esse artefato ainda não foi produzido, sem exibir
   erro.
3. **Given** uma feature com múltiplos artefatos já gerados (spec, plano,
   tarefas, pesquisas), **When** o usuário está na visão da feature, **Then**
   consegue navegar entre os diferentes artefatos disponíveis.

---

### Edge Cases

- O que acontece quando o caminho do projeto observado no sistema de arquivos
  fica temporariamente inacessível (removido, permissão negada, disco não
  montado) enquanto está sendo observado?
- Como o sistema se comporta quando o mecanismo que mantém a `knowledge.db`
  atualizada falha ou está temporariamente indisponível no momento em que uma
  mudança deveria ser propagada?
- O que acontece quando um artefato de documentação solicitado ainda não foi
  produzido para a etapa corrente da pipeline (ex.: tarefas antes de o
  backlog existir)?
- Como o sistema trata o conteúdo de um artefato de documentação que contém
  markup ativo ou instruções embutidas (documentos são gerados por agentes e
  não são confiáveis por padrão)?
- Como o sistema lida com múltiplas execuções em andamento simultaneamente —
  seja em features diferentes do mesmo projeto, seja em projetos diferentes?

## Requirements

### Functional Requirements

- **FR-001**: O sistema MUST detectar, sem exigir intervenção manual do
  operador, quando uma execução com status "em andamento" ou "aguardando
  humano" tem novidade (onda concluída, nova decisão, mudança de status).
- **FR-002**: O sistema MUST refletir uma mudança detectada nas telas do
  painel dentro do prazo definido em SC-001, sem exigir recarregamento manual
  da página pelo usuário.
- **FR-003**: O sistema MUST limitar a observação ativa a execuções com
  status "em andamento" ou "aguardando humano"; MUST NOT continuar
  verificando, de forma contínua, execuções já concluídas ou abortadas.
- **FR-004**: O mecanismo que mantém a `knowledge.db` atualizada MUST
  delegar ao processo de ingestão canônico já existente, em vez de
  reimplementar a leitura de `state.json` ou a escrita no banco dentro do
  painel; nenhum caminho de código do painel MUST realizar escrita direta na
  `knowledge.db`. Esse mecanismo MUST acionar a ingestão canônica de forma
  proativa e recorrente enquanto houver execução em andamento (ver
  Clarifications), e MUST NOT reconstruir o índice completo (`--reindex`,
  dono externo ao painel) nem modificar `state.json`.
- **FR-005**: Usuários MUST conseguir visualizar, dentro da visão de uma
  feature no painel, os artefatos de documentação já produzidos para ela pela
  pipeline de especificação (por exemplo: especificação, plano, backlog de
  tarefas, pesquisas e demais documentos gerados).
- **FR-006**: O sistema MUST exibir o conteúdo de um artefato de
  documentação formatado (renderizado), não como texto bruto sem formatação.
- **FR-007**: O sistema MUST indicar claramente quando um artefato de
  documentação específico ainda não foi produzido para a feature, em vez de
  apresentar isso como erro; a expectativa de quais artefatos existem por
  etapa vem do mapeamento fixo etapa-SDD → artefato(s) (ver Clarifications),
  sem impedir a exibição de arquivos adicionais já presentes na árvore de
  documentação.
- **FR-008**: O sistema MUST resolver a localização do projeto no sistema de
  arquivos — necessária tanto para observar o estado de uma execução
  (FR-001) quanto para ler os artefatos de documentação (FR-005) — a partir
  de configuração mantida pelo operador do painel: um mapeamento do nome
  lógico (`project`, já armazenado na `knowledge.db`) para o caminho
  absoluto, resolvido no padrão já adotado para o caminho da `knowledge.db`
  (flag/config explícita > variável de ambiente > default). A `knowledge.db`
  MUST NOT ganhar coluna de caminho nesta feature; projetos sem entrada no
  mapeamento MUST ser tratados como não observáveis (degradação sinalizada,
  FR-012), nunca como erro.
- **FR-009**: O sistema MUST confinar qualquer acesso a arquivos de
  documentação à árvore de documentação do próprio projeto resolvido em
  FR-008; MUST NOT seguir caminhos que escapem dessa fronteira.
- **FR-010**: O sistema MUST tratar o conteúdo dos artefatos de documentação
  como conteúdo não confiável gerado por agente — a renderização MUST NOT
  interpretar ou executar markup ativo (HTML/script) embutido no conteúdo.
- **FR-011**: O sistema MUST continuar expondo, para cada execução
  observada, um indicador de frescor (há quanto tempo a informação exibida
  foi confirmada), de forma consistente com o indicador de frescor já
  existente no painel.
- **FR-012**: O sistema MUST degradar graciosamente — sem erro de servidor
  nem tela quebrada — quando o caminho de um projeto observado estiver
  temporariamente inacessível ou quando o mecanismo de atualização falhar;
  nesses casos MUST sinalizar o estado como degradado em vez de omitir a
  falha silenciosamente.
- **FR-013**: O sistema MUST executar a verificação de novidades de forma
  contínua em segundo plano, durante todo o tempo em que o painel estiver
  ativo — não apenas quando um usuário carrega uma página; essa verificação
  MUST ficar pausada/reduzida quando não houver nenhuma execução em
  andamento.
- **FR-014**: O sistema MUST evitar disparar trabalho de atualização
  redundante para uma execução cujo estado subjacente não mudou desde a
  última verificação.

> **Decisões de infraestrutura**: a política de agendamento está declarada em
> FR-013 (verificação contínua em segundo plano, ativa apenas com execuções
> em andamento) e a idempotência do disparo de atualização em FR-014 (evita
> trabalho duplicado quando nada mudou). O mecanismo de atualização MUST
> permanecer compatível com a arquitetura de snapshot já adotada pelo painel
> (Constitution Princípio VI — "Snapshot que Muda"): a atualização quase em
> tempo real desta feature é alcançada por verificação recorrente, não pela
> introdução de um canal de notificação persistente entre quem observa e
> quem é observado — decisão já tomada conscientemente no escopo original do
> painel. Demais categorias do checklist de infraestrutura (rotação de
> chave, refresh de token externo, mutex multi-pod, backup/restore) = N/A —
> esta feature não introduz criptografia de dado persistido, não consome
> identity provider/OAuth, não assume deploy multi-réplica e não cria novo
> dado crítico além do que já é coberto pela `knowledge.db` existente.

### Key Entities

- **Execução Observada**: uma execução `agente-00c`/`feature-00c` em
  progresso (status "em andamento" ou "aguardando humano") cujo estado é
  acompanhado para refletir mudanças no painel; associada a um projeto, a uma
  feature (quando aplicável) e a um indicador de frescor.
- **Artefato de Documentação**: um documento gerado pela pipeline de
  especificação (especificação, plano, backlog de tarefas, pesquisas,
  checklists e demais documentos relacionados) associado a uma feature
  específica, exibível dentro da visão dessa feature no painel.
- **Localização de Projeto**: a referência que permite localizar, no sistema
  de arquivos, tanto o estado transacional quanto os artefatos de
  documentação de um projeto observado (ver FR-008).

## Success Criteria

### Measurable Outcomes

- **SC-001**: mudanças de status de uma execução em andamento (onda
  concluída, nova decisão, transição para aguardando humano ou concluída)
  aparecem no painel em até 30 segundos após acontecerem, sem que o usuário
  precise recarregar a página manualmente.
- **SC-002**: usuários conseguem visualizar 100% dos artefatos de
  documentação já produzidos de uma feature (especificação, plano, tarefas e
  demais documentos da pipeline) sem sair do painel.
- **SC-003**: para os fluxos cobertos por esta feature, usuários conseguem
  acompanhar integralmente o status e a documentação de uma execução em
  andamento sem precisar abrir editor ou terminal.
- **SC-004**: o painel indica, para 100% das execuções observadas, há quanto
  tempo a informação exibida foi confirmada como válida, permitindo ao
  usuário avaliar a atualidade do que está vendo a qualquer momento.
