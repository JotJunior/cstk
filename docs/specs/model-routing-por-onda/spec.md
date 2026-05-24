# Feature Specification: Model-routing aplicado por onda

**Feature**: `model-routing-por-onda`
**Created**: 2026-05-24
**Status**: Clarified

## Clarifications

### Session 2026-05-24

- **FR-014 (mapa fase→modelo)**: adotado o recorte "3 faixas balanceado" — opus
  para plan/analyze/arquitetura; sonnet para specify/clarify/checklist/create-tasks;
  haiku/sonnet para execute-task raso/validate-docs/review-task.
- **FR-015 (escalonamento mid-onda)**: terminar a onda corrente no modelo atual e
  escalar a PRÓXIMA onda para opus (não abortar, não trocar modelo mid-run).
- **FR-016 (override do operador)**: via Decisão manual pré-onda lida pelo resume,
  com precedência sobre a sugestão automática.
- **FR-001/FR-014 (mecanismo primário)**: o mapa fase→modelo é o mecanismo
  PRIMÁRIO de seleção; model-selector é refinamento, não a fonte principal.
- **FR-018/US4 (expansão do catálogo)**: o catálogo MVP (15 verbos de tarefa) será
  expandido com sinais de fase/complexidade para o refinamento valer na prática.
- **Papel do model-selector (catálogo MVP)**: descoberto empiricamente nesta
  sessão que o catálogo atual do `model-selector` tem só 15 termos (verbos
  imperativos de TAREFA: rode/liste/grep/refatore/arquitete...), casados por token
  exato. Ele NÃO classifica nomes de fase nem descrições livres de onda. Decisão:
  o **mapa fase→modelo (FR-014) é o mecanismo PRIMÁRIO** de economia; o
  model-selector é camada de **refinamento** sobre `execute-task` quando o texto
  da tarefa contém sinais do catálogo. Adotada também a expansão do catálogo com
  sinais de fase/complexidade (User Story 4) para o refinamento valer na prática.

## Contexto e Problema

O model-routing atual (feature `agente-00c-model-routing`, v3.15.0) é
**audit-only**: o `model-selector` sugere um modelo, o orquestrador registra uma
Decisão auditável, mas o modelo escolhido **nunca é aplicado** — a cláusula
FR-017 da feature original determina que a escolha é "auditoria pura" e "não é
passada à tool Agent", justificada por uma premissa de que "o harness não aceita
`model` como parâmetro de spawn".

Essa premissa está **obsoleta**: o harness atual aceita `model` no spawn de
subagente (com precedência sobre o frontmatter). Além disso, o único gatilho do
routing é o pré-spawn de subagentes `clarify-asker`/`clarify-answerer` — o
caminho mais raro do pipeline, que ainda degrada para mediação inline quando o
orquestrador roda como subagente e não consegue spawnar subagentes aninhados.

Evidência empírica (base real, 8 projetos): 859 decisões, 3 invocações de
`model-selector`, **0** com escolha aplicável (`model:%`) — todas foram fallback
`skill-not-found`. Economia real de tempo/tokens entregue até hoje: **zero**.

> **Decisões de infraestrutura**: esta feature toca política de seleção de
> runtime (modelo por onda) — declarada como FR explícito (FR-001, FR-014). Não
> introduz scheduling novo, criptografia, nem token externo: a granularidade de
> agendamento entre ondas (ScheduleWakeup) já existe e não muda.

## User Scenarios & Testing

### User Story 1 - Orquestrador roda modelo barato em ondas mecânicas (Priority: P1)

Como operador que dispara `/agente-00c` ou `/feature-00c` numa feature longa
(muitas ondas), eu quero que cada onda seja conduzida pelo modelo mais barato
que dê conta da fase daquela onda, para que execuções mecânicas (ex.:
`execute-task` de tarefa simples, `validate-docs`, `review-task`) terminem mais
rápido e gastem menos, reservando o modelo caro (Opus) para as fases de
raciocínio pesado (`plan`, decisões de arquitetura, `analyze`).

**Why this priority**: é o grosso da economia. O custo dominante do pipeline é o
orquestrador conduzindo fase após fase, onda após onda, no modelo da sessão. Como
cada onda é uma nova invocação do orquestrador (via slash command no início e via
resume entre ondas), a fronteira de onda é o único ponto onde o modelo pode de
fato ser trocado — e é onde mora o maior tempo acumulado.

**Independent Test**: disparar uma feature cujo plano tenha ondas de fases
distintas; verificar que a onda classificada como mecânica é conduzida por
haiku/sonnet e a onda de planejamento por opus, e que cada troca tem uma Decisão
auditável correspondente com o modelo **efetivamente aplicado**.

**Acceptance Scenarios**:

1. **Given** uma feature com próxima onda na fase `execute-task` de uma tarefa
   rasa, **When** o resume vai spawnar o orquestrador para essa onda, **Then** o
   **mapa fase→modelo** define o piso (execute-task→sonnet) e o `model-selector`
   refina via o texto da tarefa (sinais de tarefa rasa podem baixar para haiku); o
   spawn usa o modelo resultante e uma Decisão registra o modelo aplicado.
2. **Given** uma feature com próxima onda na fase `plan`, **When** o resume vai
   spawnar o orquestrador, **Then** a classificação resulta em manter o modelo
   caro (opus) e o spawn reflete isso.
3. **Given** o `model-selector` indisponível ou retornando score < 2, **When** o
   resume vai spawnar, **Then** o sistema mantém o modelo atual (sem aplicar
   override), registra fallback auditável, e a onda prossegue normalmente.

---

### User Story 2 - Modelo aplicado nos subagentes clarify quando eles ocorrem (Priority: P2)

Como operador, quando o pipeline de fato spawna os subagentes
`clarify-asker`/`clarify-answerer` (caminho não-degradado), eu quero que o modelo
sugerido pelo `model-selector` seja **aplicado** ao spawn — não apenas auditado —
para que esses subagentes mecânicos rodem no modelo barato em vez de herdar o
modelo caro do pai.

**Why this priority**: fecha a lacuna conceitual do FR-017 (audit-only → aplicado)
no ponto onde o routing já existe hoje. Valor menor que P1 porque o spawn de
clarify é raro e frequentemente degrada para inline, mas é coerência necessária e
de baixo custo. Independe de P1 (é outro ponto de spawn).

**Independent Test**: forçar um cenário onde o spawn de clarify ocorre de fato
(não degrada); verificar que o subagente roda no modelo sugerido pela Decisão, e
não no modelo do orquestrador-pai.

**Acceptance Scenarios**:

1. **Given** o pré-spawn de `clarify-asker` com sugestão de modelo barato e spawn
   real disponível, **When** o orquestrador spawna o subagente, **Then** o
   subagente é spawnado com o modelo sugerido aplicado.
2. **Given** a sugestão de fallback (`manter-atual`), **When** o spawn ocorre,
   **Then** nenhum override é aplicado e o subagente herda o modelo do pai.
3. **Given** que o spawn degrada para mediação inline (subagente não pode ser
   spawnado), **Then** nenhum override de modelo é tentado e o comportamento atual
   de degradação é preservado, sem Decisão órfã.

---

### User Story 3 - Auditoria distingue modelo sugerido de modelo aplicado (Priority: P3)

Como operador revisando uma execução via `review-task`, eu quero ver não só qual
modelo o `model-selector` **sugeriu** mas qual foi **efetivamente aplicado** ao
spawn (e quando os dois divergem por override do operador ou fallback), para
saber se a economia esperada de fato aconteceu.

**Why this priority**: transforma o routing de "intenção registrada" em "efeito
verificável". Sem isso, não há como medir se a feature entregou economia (o
problema central que motivou a feature). Depende de P1/P2 existirem para ter o que
auditar.

**Independent Test**: executar uma feature com routing aplicado; rodar o agregador
de auditoria; verificar que ele reporta, por onda, o par (modelo sugerido, modelo
aplicado) e sinaliza divergências (override/fallback) e quaisquer registros
parciais.

**Acceptance Scenarios**:

1. **Given** uma onda onde o modelo aplicado = sugerido, **When** o operador
   audita, **Then** o relatório mostra os dois iguais e conta como aplicação
   bem-sucedida.
2. **Given** uma onda onde o operador fez override manual, **When** o operador
   audita, **Then** o relatório mostra sugerido ≠ aplicado com a marca de override.
3. **Given** uma onda com fallback (sem aplicação), **When** o operador audita,
   **Then** o relatório contabiliza como "mantido atual / não aplicado".

---

### User Story 4 - Catálogo do model-selector classifica sinais de fase/complexidade (Priority: P2)

Como mantenedor da feature, eu quero que o catálogo de sinais do `model-selector`
cubra termos de fase e de complexidade que apareçam de fato em descrições de onda
e de tarefa, para que a camada de refinamento (FR-001) realmente ajuste a faixa em
vez de quase sempre retornar `manter-atual` — caso contrário o refinamento é
inerte e só o mapa determinístico (FR-014) opera.

**Why this priority**: sem isso o model-selector não agrega valor de
discriminação ao routing (validado nesta sessão: catálogo MVP de 15 verbos
imperativos não casa nomes de fase nem descrições livres). É P2 porque o mapa
(FR-014) já entrega a economia base; a expansão eleva a precisão do refinamento.
Independe das demais stories (é mudança isolada no catálogo + cobertura de teste).

**Independent Test**: alimentar o classificador com descrições realistas de
tarefas de execute-task (rasas e profundas) e confirmar que ele discrimina a
faixa corretamente acima de um piso de cobertura medido.

**Acceptance Scenarios**:

1. **Given** uma descrição de tarefa mecânica realista, **When** classificada,
   **Then** o resultado é faixa rasa/média com modelo barato sugerido.
2. **Given** uma descrição de tarefa de raciocínio profundo realista, **When**
   classificada, **Then** o resultado é faixa profunda com opus sugerido.
3. **Given** o catálogo expandido, **When** rodada a suíte de testes, **Then** a
   taxa de `indeterminado` sobre um corpus de descrições realistas fica abaixo do
   teto definido (ver SC-008).

---

### Edge Cases

- **Onda subestimada (escalonamento mid-onda)**: uma onda spawnada num modelo
  barato revela-se mais complexa do que a classificação previu. Como o modelo é
  fixado no spawn e **não pode ser trocado mid-run**, a política é: **terminar a
  onda corrente no modelo atual e escalar a PRÓXIMA onda para opus** (decisão
  2026-05-24). Não desperdiça o trabalho parcial, respeita a restrição
  can't-remodel e mantém degradação controlada. O orquestrador sinaliza a
  subestimação para que a classificação da próxima onda parta de opus.
- **Override do operador**: o operador discorda da classificação automática para
  uma onda específica. Ele força um modelo via **Decisão manual pré-onda que o
  resume lê antes de spawnar** (decisão 2026-05-24); essa Decisão tem
  **precedência sobre a sugestão automática**, mantendo o contrato suggest-only e
  a auditabilidade pelo mesmo mecanismo de Decisões já existente.
- **Mapeamento fase→modelo (default versionado)**: piso por fase quando não há
  sinal de complexidade por tarefa (decisão 2026-05-24, recorte "3 faixas
  balanceado"):
  - **opus**: `plan`, `analyze`, decisões de arquitetura.
  - **sonnet**: `specify`, `clarify`, `checklist`, `create-tasks`.
  - **haiku/sonnet**: `execute-task` (tarefa rasa), `validate-docs`, `review-task`.
  A classificação por tarefa (rasa/média/profunda) continua a cargo do
  `model-selector`; este mapa é o piso quando não há sinal de tarefa.
- **Resume idempotente**: retomada no meio de uma onda já spawnada não deve
  re-classificar nem inflar Decisões para a mesma onda (espelha INV de
  idempotência da feature original).
- **model-selector ausente** (`skill-not-found`): mantém atual, registra fallback,
  nunca aborta — igual ao comportamento gracioso atual.
- **Modelo sugerido inválido/desconhecido** pelo harness: tratar como fallback
  `manter-atual` em vez de propagar erro ao spawn.
- **Sessão já barata**: se o operador já disparou tudo numa sessão Sonnet, uma
  sugestão "opus para a onda de plan" deve poder **subir** o modelo, não só descer
  (o routing é bidirecional dentro do conjunto haiku/sonnet/opus).

## Requirements

### Functional Requirements

- **FR-001**: O sistema MUST selecionar um modelo para cada onda na **fronteira de
  onda** (no momento em que o orquestrador é spawnado pela slash command inicial
  ou pelo resume). A seleção é determinada PRIMARIAMENTE pelo mapa fase→modelo
  (FR-014); o `model-selector` atua como camada de refinamento que pode ajustar a
  faixa quando o texto da tarefa da onda contém sinais de complexidade
  reconhecíveis (ver FR-018).
- **FR-002**: O sistema MUST **aplicar** o modelo selecionado ao spawn do
  orquestrador (parâmetro de modelo do spawn), não apenas registrá-lo. Esta é a
  revogação explícita da cláusula audit-only do FR-017 da feature original no
  ponto de spawn do orquestrador.
- **FR-003**: O sistema MUST aplicar o modelo sugerido ao spawn dos subagentes
  `clarify-asker`/`clarify-answerer` quando esse spawn de fato ocorrer (caminho
  não-degradado), revogando audit-only também nesse ponto.
- **FR-004**: Quando o spawn de clarify degradar para mediação inline, o sistema
  MUST NOT tentar aplicar override de modelo e MUST preservar o comportamento de
  degradação atual sem gerar Decisão órfã.
- **FR-005**: O sistema MUST tratar a seleção em camadas: o **mapa (FR-014) define
  e aplica um modelo SEMPRE** (mesmo com score 0 / sem sinal); o `model-selector`
  apenas **refina** automaticamente a faixa quando score ≥ 2; o operador MUST poder
  fazer override manual a qualquer momento, com **precedência sobre mapa e refino**.
  Suggest-only: o sistema nunca troca modelo sem Decisão auditável.
- **FR-006**: Quando o `model-selector` estiver ausente (`skill-not-found`),
  retornar score < 2, ou sugerir um modelo não reconhecido pelo harness, o sistema
  MUST cair em `manter-atual` (nenhum override aplicado), registrar o fallback de
  forma auditável, e **nunca** abortar a onda.
- **FR-007**: O sistema MUST registrar, por onda, uma Decisão auditável contendo o
  modelo **sugerido**, o modelo **aplicado**, o score, e a origem da aplicação
  (`mapa` | `refino` | `override-operador` | `fallback`). Sugerido e aplicado podem
  divergir somente com origem ∈ {override-operador, fallback}.
- **FR-008**: O sistema MUST manter a idempotência por onda: retomada via resume no
  meio de uma onda já classificada/spawnada MUST NOT re-classificar nem registrar
  uma segunda Decisão de modelo para a mesma onda.
- **FR-009**: O routing MUST ser bidirecional dentro de {haiku, sonnet, opus}:
  pode tanto reduzir (de opus para haiku numa onda mecânica) quanto elevar (de
  sonnet para opus numa onda de raciocínio) o modelo em relação ao modelo corrente
  da sessão.
- **FR-010**: O `model-selector` MUST permanecer uma heurística puramente local
  (Princípio IV): nenhuma consulta a billing API, tabela de preços remota, ou
  serviço externo para decidir o modelo.
- **FR-011**: Qualquer helper novo ou alterado que suporte a seleção MUST ser POSIX
  sh puro conforme Princípio II (sem Bash-isms, deps externas confinadas e opcionais
  com fallback se houver).
- **FR-012**: O agregador de auditoria consumido por `review-task` MUST reportar,
  por execução: total de ondas roteadas, distribuição do modelo **aplicado** por
  faixa, taxa de fallback (`manter-atual`), taxa de override do operador, e
  registros parciais pendentes (deve ser 0).
- **FR-013**: O sistema MUST preservar a auditoria de meia-gravação (Decisão sem
  record-skill correspondente ou vice-versa) com o mesmo mecanismo de reconciliação
  no resume já existente na feature original.
- **FR-014**: O mapeamento fase→faixa-de-modelo MUST ser o mecanismo PRIMÁRIO de
  seleção: explícito e documentado como default versionado, com o recorte "3
  faixas balanceado": opus para plan/analyze/decisões de arquitetura; sonnet para
  specify/clarify/checklist/create-tasks; haiku/sonnet para execute-task
  raso/validate-docs/review-task (ver Edge Case "Mapeamento fase→modelo"). Toda
  onda tem um modelo definido por este mapa mesmo sem nenhum sinal do
  model-selector.
- **FR-015**: Ao detectar que uma onda spawnada em modelo barato excede a
  complexidade prevista, o sistema MUST concluir a onda corrente no modelo atual e
  escalar a próxima onda para opus (sem abortar a onda corrente nem trocar modelo
  mid-run), sinalizando a subestimação à classificação da onda seguinte.
- **FR-016**: O operador MUST poder forçar o modelo de uma onda via Decisão manual
  pré-onda lida pelo resume antes do spawn; essa Decisão de override MUST ter
  precedência sobre a sugestão automática do model-selector.
- **FR-017**: A documentação da feature original (`agente-00c-model-routing`) e o
  CLAUDE.md MUST ser atualizados para refletir que a aplicação deixou de ser
  audit-only, removendo a premissa obsoleta ("harness não aceita model no spawn")
  e marcando a mudança de contrato (BREAKING em relação ao FR-017 original →
  bump MAJOR no CHANGELOG).
- **FR-018**: O catálogo de sinais do `model-selector` MUST ser expandido além do
  MVP de 15 termos para cobrir vocabulário de fase e de complexidade que ocorra em
  descrições reais de onda/tarefa, mantendo o formato de tabela e o casamento por
  token já existentes (Princípio II preservado). A expansão MUST vir com cobertura
  de teste sobre um corpus de descrições realistas.
- **FR-019**: A camada de refinamento MUST ser estritamente aditiva e segura: o
  refinamento só pode AJUSTAR a faixa derivada do mapa (FR-014) quando houver sinal
  com score ≥ 2; na ausência de sinal, o modelo do mapa prevalece sem alteração, e
  nenhuma indisponibilidade do model-selector pode abortar a onda (degradação
  graciosa preservada, FR-006).
- **FR-020** (versionamento do mapa — CHK006): o arquivo `phase-model-map` MUST
  declarar uma versão explícita; o lookup MUST tolerar evolução do mapa (linha/fase
  desconhecida → `manter-atual`, nunca erro), de modo que adicionar/remover fases
  não quebre execuções nem o agregador.
- **FR-021** (coexistência com Decisões legadas — CHK007): o agregador de auditoria
  MUST reportar sem erro tanto Decisões novas (com `modelo_aplicado`/`origem`)
  quanto Decisões legadas audit-only (`escolha=fallback-default`, sem aplicado),
  distinguindo as duas gerações.
- **FR-022** (untrusted task-text — CHK019/020/021): a entrada `--task-text` que
  alimenta o refino MUST ser tratada como UNTRUSTED — sanitização contra injeção de
  shell/FTS (reuso das mitigações F-001/F-002 da feature original), remoção de NUL,
  e truncamento a um teto de bytes documentado ANTES de chegar ao classificador.
- **FR-023** (validação do override — CHK022/023/024): o valor de override do
  operador MUST ser validado contra o enum `{haiku, sonnet, opus}`; override
  inválido MUST cair em fallback (mapa/`manter-atual`) com registro auditável e
  NUNCA ser propagado ao spawn; o override MUST ter escopo de UMA única onda (não
  vaza para ondas subsequentes).
- **FR-024** (confinamento de path — CHK026): a resolução do caminho do
  `phase-model-map` MUST ser confinada ao diretório do runtime (canonicalizada, sem
  path traversal, sem aceitar caminho arbitrário fornecido externamente).
- **FR-025** (dado sensível em Decisão — CHK027): texto livre derivado de descrição
  de tarefa gravado em campos de Decisão (`justificativa`/`sinais_text`) MUST seguir
  o mesmo tratamento untrusted/scrub já aplicado na ingestão do recall; o
  `state.json` MUST NOT introduzir segredos além do que a fonte já contém.

### Key Entities

- **Decisão de modelo por onda**: registro auditável associado a uma onda,
  contendo modelo sugerido, modelo aplicado, score, origem da aplicação
  (automática/override/fallback) e proveniência (projeto/feature/onda).
- **Classificação de onda**: resultado do `model-selector` para a fase/tarefa da
  onda — faixa de complexidade (rasa/média/profunda) + modelo sugerido + sinais.
- **Mapa fase→faixa-de-modelo**: tabela default versionada que dá o piso de modelo
  por fase do pipeline quando não há sinal de complexidade por tarefa.
- **Relatório de roteamento aplicado**: agregação por execução do par
  (sugerido, aplicado) e suas taxas, consumida por `review-task`.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Em features com ondas de fases mistas, o tempo de parede acumulado
  das ondas mecânicas cai pelo menos 30% frente ao baseline (tudo em Opus), sem
  regressão de qualidade nas fases de raciocínio.
- **SC-002**: 100% das ondas roteadas têm uma Decisão auditável registrando o modelo
  **efetivamente aplicado** (não apenas o sugerido).
- **SC-003**: 0 registros parciais (half-record) pendentes ao fim de qualquer
  execução, inclusive após retomadas via resume.
- **SC-004**: 100% dos casos de `model-selector` ausente/indeterminado resultam em
  onda concluída (degradação graciosa), 0 abortos causados por seleção de modelo.
- **SC-005**: Quando o operador faz override **válido** de modelo numa onda, o
  modelo aplicado corresponde ao override em 100% dos casos (precedência sobre
  mapa e refino); override inválido cai em fallback (FR-023), não no override.
- **SC-006**: O relatório de auditoria reflete, por onda, sugerido vs aplicado com
  0 divergências silenciosas (toda divergência tem origem rotulada:
  override ou fallback).
- **SC-007**: Nenhuma onda é spawnada com um modelo não reconhecido pelo harness
  (toda sugestão inválida vira fallback `manter-atual`).
- **SC-008**: Sobre um corpus de referência de descrições realistas de
  tarefa/onda, o classificador expandido retorna `indeterminado` em no máximo 25%
  dos casos (contra ~100% no catálogo MVP para inputs de fase), discriminando
  corretamente rasa vs profunda nos demais.
</content>
</invoke>
