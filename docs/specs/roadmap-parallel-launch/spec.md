# Feature Specification: Lançamento Paralelo de Features do Roadmap

**Feature**: `roadmap-parallel-launch`
**Created**: 2026-08-17
**Status**: Draft

## Clarifications

### Session 2026-08-17

- Q: Qual o teto padrão de features lançadas simultaneamente numa leva quando o operador não especifica um valor (FR-003)? → A: 2 — default conservador, coerente com risco de rate-limit e conflitos de merge no hub.
- Q: Qual o multiplexador de terminal alvo primário da abertura automática de painéis (FR-005/FR-007/US3)? → A: tmux — único multiplexador com integração oficial do Claude Code (detecção de pane, agent teams) e já em uso pelo operador; na ausência de tmux, degrada para US3 (imprimir comandos exatos).
- Q: Qual a fonte de verdade para o status iniciada/concluída de uma entrada do roadmap (FR-001/SC-004)? → A: reusar o contrato já existente em `docs/specs/roadmap-mode/contracts/roadmap-artifact.md` §5 (derivação via `review-features/scripts/roadmap-status.sh --json`, a partir de `docs/specs/<feature>/`); nunca um campo `status` persistido dentro de `docs/roadmap.md` (proibido pela §2.2 do mesmo contrato).
- Q: Qual a fonte para detectar sobreposição de artefatos entre candidatas ainda não iniciadas (FR-014)? → A: o texto descritivo de cada entrada em `docs/roadmap.md` — única documentação disponível antes do `/specify` de cada candidata; quando insuficiente para determinar com confiança, o sistema segue oferecendo o lançamento sem bloquear (AC2 da US4).
- Q: Qual o timing da notificação à sessão coordenadora ao a sessão-filha alcançar um estado terminal (FR-008/FR-015)? → A: imediato, sem intervalo/timeout configurável — best-effort do lado da sessão-filha; ausência de confirmação de entrega não impede o ciclo de vida normal da sessão-filha.

## User Scenarios & Testing

### User Story 1 - Lançar a primeira leva paralela após o modo roadmap (Priority: P1)

Ao concluir o modo roadmap (`docs/roadmap.md` gerado e ratificado), o
operador quer, sem trabalho manual de setup, colocar para rodar em
paralelo as features do roadmap que já estão prontas para começar —
isto é, que ainda não foram iniciadas e cujas dependências declaradas já
estão concluídas. O sistema calcula essa fronteira, pergunta ao operador
quantas rodar de uma vez (um teto configurável) e quais delas escolher
quando houver mais candidatas do que o teto permite, e então abre, para
cada feature escolhida, um ambiente de trabalho isolado executando a
pipeline de feature individual.

**Why this priority**: é o valor central da feature — sem isto, o
operador continua lançando cada feature do roadmap manualmente, uma de
cada vez, mesmo quando várias já estão prontas para começar
simultaneamente.

**Independent Test**: com um `docs/roadmap.md` contendo pelo menos duas
entradas sem dependências pendentes entre si, confirmar que o sistema
oferece as duas como candidatas da leva, respeita o teto quando
configurado abaixo de 2, e que cada feature escolhida termina com um
ambiente de trabalho isolado e independente das demais rodando sua
própria pipeline.

**Acceptance Scenarios**:

1. **Given** um `docs/roadmap.md` ratificado com 3 entradas, sendo 2
   sem nenhuma dependência declarada e 1 dependente de uma das outras
   duas, **When** o modo roadmap termina, **Then** o sistema identifica
   as 2 entradas sem dependência pendente como a fronteira elegível e a
   terceira como não-elegível ainda.
2. **Given** a fronteira elegível tem mais entradas do que o teto
   configurado, **When** o operador é consultado, **Then** o sistema
   apresenta todas as candidatas da fronteira e permite ao operador
   escolher, dentro do teto, quais lançar nesta leva.
3. **Given** o operador confirmou a leva, **When** o lançamento ocorre,
   **Then** cada feature escolhida passa a rodar em um ambiente de
   trabalho isolado próprio (sem compartilhar working tree com as
   demais features da mesma leva nem com a sessão que orquestrou o
   lançamento).
4. **Given** o operador não quer paralelismo desta vez, **When** ele
   recusa a oferta de leva paralela, **Then** o comportamento atual
   (lançamento manual, um de cada vez) permanece disponível e nada é
   aberto automaticamente.

---

### User Story 2 - Fechar o ciclo: notificação de conclusão e próxima leva (Priority: P2)

Depois que uma leva é lançada, o operador não deveria precisar checar
manualmente, de tempos em tempos, se alguma das features paralelas já
terminou. Quando uma feature em execução paralela chega a um estado
terminal — concluída, abortada, ou parada aguardando decisão humana
(o próprio ato de registrar o bloqueio humano já é o estado terminal;
não há uma janela de espera anterior) —, a sessão que a executa avisa
a sessão coordenadora. A sessão
coordenadora recalcula a fronteira do DAG — que pode ter crescido, já
que features que dependiam da que acabou de terminar podem agora estar
prontas — e oferece ao operador a próxima leva.

**Why this priority**: sem isto, o ganho da User Story 1 é pontual (uma
leva só); o valor composto de rodar o roadmap inteiro com paralelismo
depende de encadear levas sem retrabalho manual de "ficar checando".

**Independent Test**: com uma leva de 1 feature em execução e outra
feature no roadmap que depende exclusivamente dela, provocar a conclusão
da primeira e confirmar que a sessão coordenadora recebe o aviso, refaz
o cálculo da fronteira e passa a listar a segunda feature como elegível
para a próxima leva — sem que o operador precise consultar nada
manualmente.

**Acceptance Scenarios**:

1. **Given** uma feature em execução paralela chega a um estado
   terminal, **When** isso acontece, **Then** a sessão coordenadora
   recebe uma notificação identificando qual feature terminou e com que
   desfecho (concluída / abortada / aguardando decisão humana).
2. **Given** a sessão coordenadora recebeu a notificação, **When** ela
   recalcula a fronteira, **Then** qualquer feature do roadmap cuja
   única pendência era a que acabou de concluir passa a aparecer como
   elegível para a próxima leva.
3. **Given** a feature terminou abortada ou parada em
   `aguardando_humano` com bloqueio humano ainda sem resposta (não
   concluída), **When** a fronteira é recalculada, **Then** as
   features que dependem dela continuam
   marcadas como não-elegíveis (conclusão de uma dependência é
   pré-requisito; um término não-concluído não libera dependentes).
4. **Given** o mecanismo de notificação automática entre sessões, que é
   externo a este sistema e cujo comportamento de "acordar" uma sessão
   coordenadora ociosa nunca foi comprovado empiricamente antes desta
   feature, **When** a primeira leva é lançada em qualquer ambiente,
   **Then** o sistema inclui uma validação inicial dedicada que comprova
   (ou refuta, registrando o resultado) se a sessão coordenadora de fato
   retoma o processamento ao receber a notificação, e oferece ao
   operador uma forma manual de verificar o status das sessões-filha
   independentemente desse mecanismo funcionar.

---

### User Story 3 - Degradar sem travar quando não há multiplexador de terminal (Priority: P3)

Nem todo ambiente do operador tem um multiplexador de terminal (para
abrir os painéis paralelos automaticamente) disponível. Quando não há,
o operador ainda quer poder rodar o paralelismo — só que abrindo cada
sessão manualmente, seguindo instruções exatas que o sistema fornece.

**Why this priority**: sem isto, a feature simplesmente não funciona
para uma fração desconhecida — mas plausivelmente grande — dos
ambientes dos operadores, e falhar silenciosamente ou travar seria pior
do que nunca ter oferecido paralelismo.

**Independent Test**: num ambiente sem o multiplexador de terminal
disponível, confirmar que a oferta de leva paralela ainda resulta em
instruções completas e corretas o suficiente para o operador copiar e
rodar manualmente cada sessão, sem nenhuma falha silenciosa nem
travamento à espera de um recurso que não existe.

**Acceptance Scenarios**:

1. **Given** o multiplexador de terminal não está disponível no
   ambiente, **When** o operador confirma uma leva paralela, **Then** o
   sistema imprime, para cada feature escolhida, o comando exato que o
   operador precisaria rodar para abrir aquela sessão manualmente — em
   vez de tentar abrir um painel e falhar.
2. **Given** essa degradação ocorreu, **When** o operador roda os
   comandos impressos manualmente, **Then** o resultado é equivalente
   ao caminho automático (mesmo ambiente de trabalho isolado, mesma
   feature sendo executada).

---

### User Story 4 - Alertar sobre risco de conflito antes de lançar a leva (Priority: P4)

Features independentes no grafo de dependências do roadmap não são
necessariamente independentes em termos de quais arquivos do projeto
elas tocam — duas features sem relação de dependência declarada podem,
mesmo assim, editar os mesmos arquivos, gerando conflito quando ambas
tentarem consolidar seu trabalho depois. O operador quer ser avisado
desse risco antes de confirmar a leva, para poder decidir com
informação.

**Why this priority**: é uma mitigação de risco importante mas não
bloqueia o valor central (US1/US2) — o paralelismo funciona sem isto;
isto só o torna mais seguro de usar em portfolios maiores.

**Independent Test**: com duas features candidatas da mesma leva cujas
especificações declaram tocar os mesmos artefatos do projeto, confirmar
que o operador recebe um aviso explícito citando quais features e,
quando determinável, quais artefatos se sobrepõem, antes de confirmar o
lançamento.

**Acceptance Scenarios**:

1. **Given** duas features candidatas da mesma leva têm sobreposição de
   artefatos conhecida, **When** o sistema apresenta a oferta de leva,
   **Then** ele inclui um aviso identificando o par de features em
   risco antes de pedir confirmação.
2. **Given** o sistema não consegue determinar com confiança se há
   sobreposição (informação insuficiente), **When** apresenta a leva,
   **Then** ele segue oferecendo o lançamento normalmente, sem bloquear
   por uma suposição não verificável.
3. **Given** o operador foi avisado do risco, **When** ele decide
   prosseguir mesmo assim, **Then** o sistema respeita a decisão e
   lança a leva normalmente — o aviso é informativo, não um bloqueio.

---

### Edge Cases

- O que acontece quando `docs/roadmap.md` não existe ou está mal
  formado no momento em que a leva seria oferecida? O sistema não deve
  oferecer paralelismo nem falhar de forma confusa — deve informar que
  não há roadmap válido para calcular a fronteira.
- O que acontece quando a fronteira elegível está vazia (nada pronto
  para rodar, ou todas as entradas já concluídas)? O sistema informa
  isso claramente e não oferece leva nenhuma.
- O que acontece quando o teto de paralelismo configurado é maior do
  que o número de candidatas na fronteira? O sistema lança todas as
  candidatas disponíveis, sem exigir que o teto seja atingido.
- O que acontece se o operador pedir paralelismo mas todas as
  candidatas da fronteira já estiverem, de alguma forma, em execução
  (uma leva anterior ainda não terminou)? O sistema não deve lançar uma
  segunda sessão duplicada para a mesma feature.
- O que acontece se uma sessão-filha travar ou for encerrada
  abruptamente sem conseguir notificar a sessão coordenadora (nunca
  chega a um estado terminal observável)? O operador precisa de uma
  forma de verificar isso manualmente, já que a notificação automática
  não vai disparar. A worktree dessa feature persiste e, por si só,
  mantém a feature indefinidamente não-elegível na fronteira (ver
  FR-016) — o operador precisa encerrar explicitamente a worktree para
  a feature voltar a ser candidata.
- O que acontece se a sessão coordenadora não estiver mais ativa quando
  uma sessão-filha tenta notificá-la (janela fechada, sessão encerrada)?
  A perda dessa notificação não pode deixar a feature-filha presa nem
  causar comportamento indefinido nela — a notificação é best-effort do
  ponto de vista da sessão-filha.
- O que acontece quando duas features da mesma leva declaram tocar os
  mesmos arquivos do projeto (risco de conflito de consolidação
  posterior)? Coberto pela User Story 4 — aviso antes do lançamento,
  nunca um bloqueio automático.
- Este sistema pressupõe que a feature individual já tem seus
  pré-requisitos de execução autônoma (contexto de descoberta e
  princípios de governança do projeto já ratificados) satisfeitos —
  essa garantia é dada pelo próprio modo roadmap ter concluído antes
  desta feature entrar em ação, não é responsabilidade desta feature
  verificar de novo.

## Requirements

### Functional Requirements

- **FR-001**: O sistema MUST, ao término do modo roadmap, calcular a
  fronteira de features elegíveis para uma leva paralela: entradas do
  roadmap ainda não iniciadas cujas dependências declaradas estejam
  todas concluídas. O status iniciada/concluída de cada entrada MUST ser
  derivado exclusivamente pelo contrato já existente em
  `docs/specs/roadmap-mode/contracts/roadmap-artifact.md` §5
  (`review-features/scripts/roadmap-status.sh --json`, a partir de
  `docs/specs/<feature>/`) — nunca um campo `status` persistido dentro
  de `docs/roadmap.md` (proibido pela §2.2 desse contrato).
- **FR-002**: O sistema MUST perguntar ao operador se deseja lançar a
  leva paralela calculada, sem impor esse fluxo — recusar mantém o
  comportamento de lançamento manual, um de cada vez.
- **FR-003**: O sistema MUST oferecer um teto configurável de quantas
  features rodam simultaneamente numa leva, com um valor padrão de **2**
  quando o operador não especifica um (default conservador quanto a
  risco de rate-limit e conflitos de merge no hub).
- **FR-004**: Quando a fronteira elegível excede o teto, o sistema MUST
  permitir ao operador escolher quais candidatas específicas entram
  nesta leva, dentro do limite.
- **FR-005**: Para cada feature escolhida numa leva, o sistema MUST
  abrir um ambiente de trabalho isolado (sem compartilhamento de working
  tree ou branch corrente com as demais features da mesma leva ou com a
  sessão coordenadora) executando a pipeline de feature individual para
  aquela feature. O multiplexador de terminal alvo primário para
  abertura automática dos painéis é o **tmux** (única integração
  oficial do Claude Code — detecção de pane, agent teams — e já em uso
  pelo operador); na ausência de tmux, aplica-se a degradação de FR-007.
- **FR-006**: O sistema MUST nomear ou identificar de forma unívoca cada
  sessão lançada, de modo que a sessão coordenadora consiga distinguir
  de qual feature — e de qual repositório, cobrindo o caso de duas
  execuções distintas usando o mesmo short-name em repositórios
  diferentes na mesma máquina — veio uma notificação de conclusão
  recebida posteriormente. A identificação MUST ser o par (short-name,
  nome-do-repo): o nome da sessão-filha (`cstk-feature/<SHORT>`)
  identifica a feature dentro do repositório que a lançou, e o campo
  `repo=<nome-do-repo>` do payload de notificação (FR-008) carrega o
  segundo componente. Como cada sessão coordenadora só recebe
  notificações endereçadas ao seu próprio nome
  (`cstk-coord/<nome-do-repo>`), ela nunca precisa desambiguar
  notificações vindas de features de outro repositório — a colisão de
  short-name entre repos nunca produz ambiguidade do lado de quem
  recebe.
- **FR-007**: Quando o tmux (recurso de multiplexação de terminal alvo
  primário — ver FR-005) não estiver disponível no ambiente, o sistema
  MUST degradar para imprimir os comandos exatos que o operador
  executaria manualmente para alcançar o mesmo resultado — nunca falhar
  silenciosamente nem aguardar indefinidamente por um recurso ausente.
- **FR-008**: Quando uma feature lançada em paralelo alcança um estado
  terminal — `.execution.status` transiciona para `concluida`,
  `abortada`, ou `aguardando_humano` —, o sistema MUST notificar a
  sessão coordenadora identificando a feature e o desfecho,
  imediatamente no instante em que essa transição ocorre — sem
  intervalo ou timeout configurável. Para `aguardando_humano`
  especificamente: é o próprio ato de registrar o bloqueio humano que
  já constitui o estado terminal notificável; a notificação MUST NOT
  aguardar decorrer algum tempo sem resposta do operador — não existe
  janela de espera antes do disparo.
- **FR-009**: Ao receber uma notificação de conclusão, a sessão
  coordenadora MUST recalcular a fronteira de features elegíveis e
  oferecer ao operador a próxima leva, se houver novas candidatas.
- **FR-010**: Uma feature cujo término não foi "concluída" (abortada, ou
  parada em `aguardando_humano` com o bloqueio humano ainda sem
  resposta do operador) MUST NOT liberar as features que dependem dela
  na fronteira — apenas conclusão efetiva libera dependentes.
- **FR-011**: O sistema MUST NUNCA lançar uma segunda sessão paralela
  para uma feature que já esteja em execução (seja de uma leva anterior
  ainda ativa, seja por lançamento manual concorrente).
- **FR-012**: A decisão de quais features rodar e o efetivo lançamento
  dos ambientes/sessões paralelas MUST sempre partir da sessão
  coordenadora que interage diretamente com o operador — nunca de uma
  sessão-filha, que só executa a feature atribuída a ela e notifica ao
  final.
- **FR-013**: Antes de depender do mecanismo de notificação automática
  entre sessões em uso real, o sistema MUST incluir uma validação
  inicial dedicada que comprove empiricamente se uma sessão coordenadora
  ociosa de fato retoma o processamento ao receber uma notificação — o
  resultado dessa validação (funciona / não funciona / parcialmente)
  MUST ficar registrado, e o sistema MUST oferecer ao operador uma forma
  manual de checar o status das sessões-filha independentemente do
  resultado dessa validação.
- **FR-014**: Quando o sistema conseguir determinar, a partir da
  documentação disponível de cada feature candidata, que duas ou mais
  delas provavelmente tocam os mesmos artefatos do projeto, o sistema
  MUST avisar o operador desse risco antes de confirmar o lançamento da
  leva, sem bloquear o lançamento por causa disso. A fonte dessa
  documentação disponível é o texto descritivo de cada entrada em
  `docs/roadmap.md` — única documentação existente antes do `/specify`
  de cada candidata ainda não iniciada; quando esse texto for
  insuficiente para determinar com confiança, aplica-se o AC2 da US4
  (segue oferecendo o lançamento sem bloquear).
- **FR-015**: O sistema MUST tratar o mecanismo de notificação entre
  sessão-filha e sessão coordenadora como best-effort do lado da
  sessão-filha: a notificação é disparada imediatamente ao estado
  terminal ser alcançado (ver FR-008), e a ausência de confirmação de
  entrega MUST NOT impedir a sessão-filha de concluir seu próprio ciclo
  de vida normalmente.
- **FR-016**: Uma feature cuja sessão-filha for encerrada abruptamente
  sem alcançar um estado terminal observável (worktree criada, mas
  nenhuma notificação jamais chega — edge case de sessão travada ou
  morta) MUST permanecer não-elegível na fronteira (efeito da guarda de
  FR-011: a worktree ainda ativa é o próprio sinal de "em execução").
  O sistema MUST NOT inferir automaticamente que a ausência de
  notificação equivale a um término — essa decisão é sempre do
  operador. A retomada MUST exigir que o operador rode
  `cstk session end <SHORT>` (comando já existente, também descrito
  como kill switch — ver `contracts/parallel-launch.md` §8.bis) para
  encerrar a worktree; só então o short-name deixa de aparecer em
  `git worktree list --porcelain` e volta a ser candidato elegível em
  `roadmap-frontier.sh` (mesma guarda de FR-011, sem lógica adicional).
- **FR-017**: O sistema MUST implementar as quatro mitigações de
  segurança ratificadas pelo gate `owasp-security` (findings HIGH/MEDIUM,
  decisão `block-004` / Decisão `dec-027`) como comportamento exigido,
  não apenas como decisão de design confinada a plan/contracts:
  1. **Parse fail-closed da notificação de conclusão**: toda mensagem
     recebida pela sessão coordenadora MUST ser validada contra um
     schema estrito antes de qualquer uso; conteúdo excedente ou
     malformado é descartado, nunca lido (`contracts/parallel-launch.md`
     §6).
  2. **Prosa do roadmap como conteúdo não-confiável**: todo token
     extraído do bloco de prosa de `docs/roadmap.md` (FR-014) MUST
     passar por allowlist, truncamento e rótulo explícito de
     não-confiável antes de aparecer em qualquer saída
     (`contracts/roadmap-frontier.md` §6/§7.1).
  3. **Quoting e allowlist na composição da linha de comando**: todo
     valor interpolado nos comandos de lançamento (FR-005) MUST ser
     emitido entre aspas e revalidado por allowlist no ponto de uso,
     nunca confiando em uma única camada de validação a montante
     (`contracts/parallel-launch.md` §4.1/§4.2).
  4. **Limite de isolamento explícito**: o sistema MUST declarar, para o
     operador, o que é de fato compartilhado entre sessão coordenadora e
     sessões-filha (não apenas o que é isolado) — ver FR-018
     (`contracts/parallel-launch.md` §8.bis).
- **FR-018**: O sistema MUST NOT apresentar o paralelismo ao operador
  como mecanismo de sandbox ou isolamento de segurança — o ambiente de
  trabalho isolado de FR-005 separa working tree/branch, não processo,
  filesystem, credenciais nem `$HOME` (ver limites declarados em
  `contracts/parallel-launch.md` §8.bis). Critério verificável: a prosa
  do command pai que oferece a leva paralela (passo 4 do fluxo de
  `contracts/parallel-launch.md` §3, "perguntar ao operador se deseja
  lançar leva paralela") MUST incluir, nessa mesma interação, a
  declaração explícita de que o teto de concorrência (FR-003) também é
  um limite de blast radius, e não uma fronteira de isolamento de
  segurança.

> Decisões de infraestrutura: majoritariamente N/A — não há scheduler
> nem estado persistido além do já existente em `docs/roadmap.md` e nas
> pastas de spec por feature. A única política de concorrência
> aplicável é o teto configurável de paralelismo, coberta por FR-003 e
> FR-004.

### Key Entities

- **Fronteira do DAG (elegibilidade)**: o subconjunto de entradas do
  roadmap que ainda não foram iniciadas e cujas dependências declaradas
  já estão todas concluídas — recalculado a cada notificação de
  conclusão recebida.
- **Leva de execução paralela**: um lote de até N features lançadas
  simultaneamente numa mesma rodada, cada uma em seu próprio ambiente de
  trabalho isolado.
- **Sessão coordenadora**: a sessão que calcula a fronteira, interage
  com o operador, lança as sessões-filha e recebe as notificações de
  conclusão delas.
- **Sessão-filha**: uma sessão isolada dedicada a executar a pipeline de
  exatamente uma feature, do início ao seu estado terminal, notificando
  a sessão coordenadora ao final.
- **Notificação de conclusão**: o aviso enviado por uma sessão-filha à
  sessão coordenadora, identificando a feature e o desfecho terminal
  alcançado.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Um operador com um roadmap contendo features prontas para
  começar confirma o lançamento de uma leva paralela em, no máximo, uma
  única rodada de perguntas quando o número de candidatas está dentro
  do teto (cenário mapeado: `quickstart.md` C1 — candidatas
  apresentadas e teto perguntado numa única interação, teto assumido
  por Enter) — mais uma rodada adicional apenas quando FR-004 exigir
  seleção explícita porque as candidatas excedem o teto. Em nenhum caso
  o operador monta manualmente comandos ou ambientes por feature.
- **SC-002**: 100% das features lançadas em paralelo que alcançam um
  estado terminal geram uma tentativa de notificação à sessão
  coordenadora, sem exigir que o operador verifique manualmente cada
  uma delas para descobrir que terminou.
- **SC-003**: Em um ambiente sem o recurso de multiplexação de
  terminal, 100% das tentativas de lançamento de leva paralela ainda
  resultam em instruções completas e executáveis pelo operador — zero
  falhas silenciosas e zero travamentos aguardando o recurso ausente.
- **SC-004**: A fronteira recalculada após qualquer conclusão reflete
  exatamente as dependências declaradas no roadmap — nenhuma feature
  com dependência pendente é oferecida como elegível, e nenhuma feature
  com todas as dependências concluídas fica retida incorretamente.
- **SC-005**: Antes do primeiro uso do lançamento paralelo em um
  ambiente novo, existe um registro claro (comprovado ou refutado) de
  se a notificação automática entre sessões efetivamente acorda uma
  sessão coordenadora ociosa — nenhuma execução depende cegamente dessa
  suposição sem essa comprovação ter sido tentada.

## Delta Requirements

**Skip**: feature inteiramente nova — introduz o conceito de "leva
paralela" sobre o modo roadmap já existente (`roadmap-mode`), mas o modo
roadmap ainda não foi arquivado no corpus canônico
(`docs/specs/current/`) e nenhuma capability existente descreve
lançamento paralelo de sessões; não há comportamento ativo documentado
para alterar via delta. — agente-00c-feature-orchestrator, 2026-08-17
