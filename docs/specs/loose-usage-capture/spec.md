# Feature Specification: Captura de Consumo Avulso de Uso (Loose Usage Capture)

**Feature**: `loose-usage-capture`
**Created**: 2026-08-06
**Status**: Draft

## Clarifications

### Session 2026-08-06

- Q: Onde os registros de consumo avulso sao persistidos? → A: reusar o
  `knowledge.db` global (`~/.claude/cstk/knowledge.db`, mesma base do `cstk
  recall`), numa tabela nova de grao processo/projeto — distinta de
  `wave_model_usage` (grao onda x modelo), conforme constraint ja registrada
  na etapa specify.
- Q: Qual mecanismo dispara a captura periodica e como o FR-004 exclui
  janelas de pipeline ativas? → A: um hook `PostToolUse` dedicado (mesmo
  padrao operacional do hook de tick ja existente), que so grava quando
  NENHUMA execucao de pipeline `agente-00c`/`feature-00c` esta ativa no
  projeto — a mesma checagem serve simultaneamente como gatilho periodico e
  como exclusao do FR-004 (sem filtro pos-hoc separado por janela de tempo).
- Q: Qual e a interface pela qual o operador obtem a comparacao avulso-vs-
  pipeline (FR-009/SC-005)? → A: subcomando novo do `cstk` CLI (mesmo
  padrao de superficie ja usado por `cstk recall`/`cstk session`); exposicao
  no painel web fica fora do escopo desta feature.
- Q: O hook de captura avulsa e provisionado junto dos hooks obrigatorios de
  guarda (`pretooluse-bash-guard` etc.) ou por caminho de opt-in separado? →
  A: caminho de opt-in separado — nunca bundlado automaticamente junto dos
  guard hooks (que sao obrigatorios/fail-closed); a captura so e provisionada
  quando o operador habilita explicitamente, preservando FR-006.

## User Scenarios & Testing

### User Story 1 - Visibilidade do consumo avulso por modelo (Priority: P1)

Como operador que usa o Claude Code tanto em sessoes avulsas (fora de qualquer
execucao das pipelines SDD `agente-00c`/`feature-00c`) quanto atraves dessas
pipelines, eu quero enxergar quanto token/custo o uso avulso consumiu, com o
mesmo recorte por modelo que ja existe para o uso dentro das pipelines, para
poder comparar os dois de forma justa (mix de modelos e custo blended por
milhao de tokens).

**Why this priority**: sem essa visibilidade, o operador so conhece o custo
do que passa pela pipeline SDD — a maior parte do uso diario (exploracao,
debug, conversas avulsas) fica invisivel, mesmo ja sendo medido nativamente
pela telemetria local do Claude Code. Esta e a capacidade minima que entrega
valor sozinha.

**Independent Test**: com telemetria local habilitada num projeto com os
hooks provisionados, realizar uma sessao avulsa (sem iniciar nenhuma
execucao de pipeline) e, ao final, obter um resumo do consumo dessa sessao
por modelo (tokens e custo), sem qualquer intervencao manual de coleta.

**Acceptance Scenarios**:

1. **Given** um projeto com hooks provisionados e telemetria local
   habilitada (opt-in do operador), **When** o operador conduz uma sessao
   avulsa que usa dois modelos diferentes, **Then** o resumo de consumo
   avulso do projeto reflete os dois modelos separadamente, com tokens e
   custo correspondentes a cada um.
2. **Given** um projeto ja com historico de execucoes de pipeline SDD
   registrado, **When** o operador solicita a comparacao de mix de modelos
   e custo blended entre uso avulso e uso de pipeline, **Then** o sistema
   apresenta as duas categorias lado a lado para o mesmo projeto.

---

### User Story 2 - Nenhuma contagem dupla entre avulso e pipeline (Priority: P2)

Como operador comparando gasto avulso com gasto de pipeline, eu quero que o
consumo que ja aconteceu **dentro** de uma execucao de pipeline (onda de
`agente-00c`/`feature-00c`) nunca apareca tambem como consumo avulso, para
que a soma das duas categorias nao infle o total real gasto no projeto.

**Why this priority**: sem essa discriminacao, a comparacao da Story 1 fica
enviesada — o mesmo token pago uma vez apareceria contado duas vezes,
tornando qualquer conclusao sobre mix de modelos ou custo blended nao
confiavel. Depende da captura basica da Story 1 existir, mas e verificavel
de forma isolada.

**Independent Test**: com uma execucao de pipeline ativa (onda em
andamento) rodando simultaneamente a uma sessao avulsa no mesmo projeto,
verificar que o consumo da janela em que a onda esteve ativa e atribuido
somente ao registro de pipeline ja existente, nunca somado ao total avulso.

**Acceptance Scenarios**:

1. **Given** uma execucao de pipeline em andamento (onda aberta) num
   projeto, **When** consumo de tokens acontece durante a janela de tempo
   em que a onda esta ativa, **Then** esse consumo nao e somado ao total de
   consumo avulso do mesmo projeto.
2. **Given** uma sessao avulsa que, no meio de sua execucao, da origem a uma
   execucao de pipeline (o operador inicia `agente-00c`/`feature-00c`
   durante a sessao), **When** a onda de pipeline se encerra e a sessao
   avulsa continua, **Then** somente a janela de tempo fora da onda ativa
   volta a contar como consumo avulso.

---

### User Story 3 - Captura resiliente a encerramento abrupto (Priority: P3)

Como operador de sessoes avulsas longas, eu quero que o consumo capturado
sobreviva a um encerramento abrupto da sessao (crash, fechamento forcado do
terminal, queda de energia), para que uma sessao que de fato consumiu
orcamento nao fique com consumo zerado ou ausente so porque nao houve um
encerramento limpo.

**Why this priority**: encerramentos abruptos sao rotina em uso avulso
(diferente das ondas de pipeline, que tem ciclo de vida controlado); depender
apenas de um evento de fim de sessao limpo perderia dados exatamente nas
sessoes mais longas e potencialmente mais caras. Refinamento sobre a Story 1,
testavel isoladamente ao simular a ausencia do evento de encerramento.

**Independent Test**: iniciar uma sessao avulsa, deixar transcorrer mais de
um intervalo de captura periodica, e entao encerrar o processo de forma
abrupta (sem o evento de fim de sessao ser disparado); verificar que o
consumo ate a ultima captura periodica permanece registrado.

**Acceptance Scenarios**:

1. **Given** uma sessao avulsa em andamento, **When** o intervalo de
   captura periodica transcorre pelo menos uma vez, **Then** existe um
   registro de consumo correspondente aquele intervalo, independente de a
   sessao ainda estar aberta.
2. **Given** uma sessao avulsa encerrada de forma abrupta (sem evento de
   fim de sessao), **When** o operador consulta o consumo avulso do
   projeto, **Then** o consumo capturado ate a ultima janela periodica
   antes do encerramento abrupto esta presente no total.

---

### Edge Cases

- O que acontece quando o operador nunca habilitou a telemetria local
  (opt-in ausente)? O sistema MUST reportar "nao medido" para esse
  projeto/sessao, nunca um valor zero fabricado (Principio VI).
- Como o sistema se comporta quando duas sessoes avulsas rodam
  simultaneamente no mesmo projeto (duas janelas/terminais abertos)? Cada
  processo e atribuido e contabilizado separadamente; a agregacao do
  projeto soma os processos, sem misturar identificadores de sessao entre
  eles (label de sessao do OTel nao e confiavel para desambiguar).
- O que acontece quando os hooks de captura nao estao provisionados no
  projeto (escopo `project` nunca instalado)? Nenhum dado avulso e
  capturado para esse projeto; o sistema MUST distinguir "nao medido por
  falta de cobertura" de "medido e zero".
- Como o sistema trata uma janela de captura em que o processo de
  exportacao local de telemetria fica temporariamente inacessivel (porta
  fechada, processo reiniciado)? A captura falha de forma silenciosa para
  aquela janela (nunca bloqueia a sessao do operador) e a lacuna fica
  visivel como dado ausente, nao como zero.
- O que acontece se o evento de inicio de sessao nao disparar (ex.: hook
  instalado no meio de uma sessao ja aberta)? A primeira captura periodica
  disponivel assume o papel de baseline; consumo anterior a essa captura
  nao e reconstruido retroativamente.

## Requirements

### Functional Requirements

- **FR-001**: O sistema MUST capturar, para sessoes avulsas (fora de
  qualquer execucao de pipeline SDD) em projetos com cobertura habilitada,
  o consumo de tokens e custo por modelo, usando a mesma fonte de
  telemetria local ja emitida nativamente durante o uso do Claude Code.
- **FR-002**: O sistema MUST atribuir cada registro de consumo avulso a um
  processo e a um projeto (diretorio de trabalho), nunca a um identificador
  de sessao — o identificador de sessao da telemetria nativa e conhecido
  por nao representar a sessao de forma confiavel.
- **FR-003**: O sistema MUST capturar o consumo em intervalos periodicos ao
  longo da sessao avulsa, e nao apenas no encerramento dela, de modo que um
  encerramento abrupto preserve o consumo ja acumulado ate a ultima
  captura.
- **FR-004**: O sistema MUST excluir do total de consumo avulso qualquer
  janela de tempo em que uma execucao de pipeline SDD (`agente-00c` ou
  `feature-00c`) esteve ativa no mesmo projeto, para que o mesmo consumo
  nunca seja contado tanto como avulso quanto como pipeline.
- **FR-005**: O sistema MUST reportar "consumo nao medido" (nunca um valor
  zero) para qualquer projeto ou janela de tempo em que a captura de
  telemetria nao estava habilitada ou nao estava coberta por hooks
  provisionados.
- **FR-006**: A captura de consumo avulso MUST ser opt-in do operador
  (habilitada pela mesma configuracao nativa de telemetria local do Claude
  Code) e MUST nunca transmitir dados para fora do ambiente local do
  operador.
- **FR-007**: A falha ou indisponibilidade temporaria do mecanismo de
  captura (ex.: endpoint de telemetria local inacessivel numa janela)
  MUST NUNCA interromper, atrasar ou degradar a sessao avulsa do operador
  — a captura e estritamente melhor-esforco.
- **FR-008**: O sistema MUST persistir o consumo avulso capturado de forma
  que sobreviva ao encerramento do processo que o originou, permitindo
  consulta posterior independente da sessao ainda estar ativa.
- **FR-009**: Usuarios MUST ser capazes de obter, para um projeto, uma
  comparacao entre o mix de modelos e o custo blended por milhao de tokens
  do consumo avulso e do consumo de execucoes de pipeline SDD do mesmo
  projeto, via um subcomando do `cstk` CLI (exposicao em painel web fica
  fora do escopo desta feature — ver Clarifications).
- **FR-010**: Quando o mesmo processo de sessao avulsa dá origem, no meio
  de sua execucao, a uma execucao de pipeline SDD, o sistema MUST voltar a
  contabilizar consumo avulso normalmente assim que a execucao de pipeline
  se encerra, sem exigir reinicio da sessao avulsa.

> Decisoes de infraestrutura: aplica-se apenas cadencia de captura (ver
> FR-003) — **FR-003-INFRA-SCHED**: a cadencia de captura e determinada por
> eventos do harness (inicio de sessao como baseline + capturas periodicas
> subsequentes), nao por um agendador externo (cron); o sistema MUST
> tolerar a ausencia do evento de fim de sessao, dependendo das capturas
> periodicas como mecanismo de durabilidade. O gatilho periodico e um hook
> `PostToolUse` dedicado que so grava quando nenhuma execucao de pipeline
> esta ativa no projeto — a mesma checagem serve como exclusao do FR-004
> (ver Clarifications). Esse hook MUST ser provisionado por um caminho de
> opt-in separado dos guard hooks obrigatorios (nunca bundlado junto de
> `pretooluse-bash-guard`/`posttooluse-tool-call-tick`), preservando o
> opt-in do operador exigido por FR-006. Demais itens do checklist
> (rotacao de chave, refresh de token externo, mutex multi-pod, backup)
> N/A — a feature nao persiste segredos, nao depende de token externo com
> TTL, e roda em processo unico local por sessao.

### Key Entities

- **Registro de Consumo Avulso**: uma medicao (baseline ou periodica) do
  consumo de tokens e custo de um processo local, por modelo, atribuida a
  um projeto — nunca a um identificador de sessao. Persistido no mesmo
  indice global de conhecimento (`knowledge.db`) ja usado pelo `cstk
  recall`, numa tabela de grao processo/projeto — nao reutiliza o grao
  onda x modelo da tabela de consumo de pipeline (ver Clarifications).
- **Janela de Consumo de Pipeline**: o intervalo de tempo em que uma
  execucao de pipeline SDD esteve ativa para um projeto; usado para excluir
  consumo ja contabilizado do total avulso (evita dupla contagem).
- **Comparativo de Uso do Projeto**: visao agregada que contrasta mix de
  modelos e custo blended por milhao de tokens entre consumo avulso e
  consumo de pipeline, para o mesmo projeto.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Em um projeto com cobertura habilitada, apos o encerramento
  (limpo ou abrupto) de uma sessao avulsa, o consumo por modelo dessa
  sessao fica disponivel para consulta sem nenhuma acao manual de coleta
  por parte do operador.
- **SC-002**: 100% do consumo que ocorreu durante janelas de execucao de
  pipeline ativa e excluido do total de consumo avulso do mesmo projeto —
  nenhum token e contado nas duas categorias simultaneamente.
- **SC-003**: Para uma sessao avulsa interrompida de forma abrupta apos
  pelo menos um intervalo de captura periodica ter transcorrido, o consumo
  acumulado ate essa ultima captura permanece disponivel — nenhuma sessao
  com pelo menos uma captura periodica registrada fica com consumo
  totalmente ausente.
- **SC-004**: Para 100% dos projetos ou janelas sem cobertura de telemetria
  habilitada, o consumo avulso reportado e explicitamente "nao medido",
  nunca um valor numerico fabricado.
- **SC-005**: Um operador consegue visualizar, para um projeto com
  historico de ambas as categorias, o mix de modelos e o custo blended por
  milhao de tokens do uso avulso lado a lado com o do uso em pipeline, sem
  precisar cruzar manualmente dados de fontes separadas.

## Delta Requirements

**Skip**: feature adiciona uma capacidade inteiramente nova (captura de
consumo avulso fora das execucoes de pipeline SDD); nao ha nenhuma
capability documentada em `docs/specs/current/` referente a captura ou
comparacao de telemetria de uso a ser alterada, removida ou renomeada — o
corpus canonico atual cobre apenas atomic-commit-staging, guards e gates de
delta/spec, sem sobreposicao com este escopo. — agente-00c-feature-orchestrator, 2026-08-06
