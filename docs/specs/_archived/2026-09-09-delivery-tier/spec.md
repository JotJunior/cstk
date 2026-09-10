# Feature Specification: Pergunta de finalidade (tier de entrega) no inicio do agente-00c

**Feature**: `delivery-tier`
**Created**: 2026-08-14
**Status**: Draft

## Contexto

Feedback recorrente de usuarios do toolkit: o orquestrador `agente-00c`
desenvolve o produto solicitado com profundidade UNIFORME — arquitetura,
gates de seguranca e backlog dimensionados como se toda entrega fosse um
sistema publico em nuvem. Muitas vezes o cliente quer uma aplicacao
simples, de uso local, sem necessidades profundas; a pipeline atual gasta
horas ou dias de execucao (ondas, tokens, tarefas) num rigor que o
objetivo nao pede.

A informacao que falta e barata de obter: UMA pergunta ao operador no
inicio da execucao, sobre a finalidade do produto. O toolkit ja tem o
padrao pronto para isso — o opt-in interativo do modo atomic-commit,
respondido uma vez antes do init do estado, persistido em campo proprio
(`.atomic_commit_enabled`) e relido pelos resumes sem re-prompt.

Esta feature introduz o **tier de entrega** (delivery tier): a resposta
do operador a pergunta de finalidade, persistida no estado da execucao e
propagada como sinal de calibracao de profundidade para as etapas da
pipeline (briefing/specify/plan, quality gates, create-tasks).

Restricao inviolavel: o tier calibra PROFUNDIDADE e ESCOPO. Ele NUNCA
relaxa o Principio VI da constitution (zero fabricacao de dados) nem as
guardas enforced (bash-guard, path-guard, secrets-filter) — essas valem
identicas em todos os tiers.

Fora do escopo (decisao do operador, 2026-08-14): o tier NAO influencia
o model-routing — o roteamento de modelo segue exclusivamente seu
mecanismo proprio (mapa fase→modelo + refino model-selector). Economia
de modelo por tier pode virar sugestao futura, fora desta feature.

Tambem fora do escopo (decisao do operador, 2026-08-15): o tier fica
RESTRITO ao `/agente-00c` nesta feature. `/feature-00c` NAO pergunta
nem le o `delivery_tier` — FR-001/FR-002 permanecem exatamente como
escritos, aplicaveis somente ao init do `/agente-00c`. Extensao do tier
ao `/feature-00c` fica fora do escopo desta feature, candidata a
feature futura.

## Clarifications

### Session 2026-08-15

- Q: O tier de entrega (delivery_tier) se aplica tambem ao orquestrador `/feature-00c`, ou fica restrito a `/agente-00c` nesta feature? → A: restrito a `/agente-00c` nesta feature; FR-001/FR-002 permanecem exatamente como estao; `/feature-00c` nao pergunta nem le o tier; extensao futura fica fora do escopo (dec-011).
- Q: A matriz tier×gate desta feature cobre explicitamente algum gate alem da revisao de seguranca, ou os demais gates ficam sob o fail-safe (sempre completos, em todos os tiers)? → A: cobre APENAS `owasp-security`; os demais gates complementares (`checklist`, `validate-documentation`, `validate-docs-rendered`, `analyze`) nao tem celula na matriz e ficam sob o fail-safe do FR-005, rodando completos nos 4 tiers (dec-012).
- Q: A omissao de fases de infraestrutura de producao no backlog (FR-006) vale so para o tier `local`, ou cada tier intermediario (`internal-network`, `cloud-internal`) tem sua propria lista de fases omitidas? → A: divisao BINARIA nuvem/nao-nuvem — `local` e `internal-network` omitem do backlog as fases de infra de producao (deploy em nuvem, escalabilidade, observabilidade de producao); `cloud-internal` e `cloud-public` geram backlog completo. Nao ha lista por-tier alem dessa divisao (dec-013).

## User Scenarios & Testing

### User Story 1 - Operador informa a finalidade no inicio (Priority: P1)

Ao iniciar `/agente-00c`, antes da inicializacao do estado, o operador
responde UMA pergunta objetiva sobre a finalidade do produto, com 4
opcoes: (1) uso local para resolver problemas rapidamente; (2) sistema
compartilhado na rede interna para poucos colegas; (3) sistema publicado
em nuvem somente para uso interno; (4) sistema publicado em nuvem para
uso publico. A escolha e persistida no estado e vale para a execucao
inteira; retomadas nao re-perguntam.

**Why this priority**: sem a captura do tier nada mais existe — e o dado
de entrada de toda a calibracao downstream. Sozinha, ja entrega valor de
auditoria (a finalidade declarada fica registrada na execucao).

**Independent Test**: iniciar uma execucao nova, responder a pergunta,
verificar o campo persistido no estado; retomar a execucao e verificar
que nao houve novo prompt (FR-001, FR-002).

**Acceptance Scenarios**:

1. **Given** operador inicia `/agente-00c` num projeto limpo, **When** a
   pergunta de finalidade e exibida e o operador escolhe a opcao 1 (uso
   local), **Then** o estado da execucao registra `delivery_tier=local`
   antes da onda-001 (FR-001, FR-002).
2. **Given** execucao com `delivery_tier=local` persistido, **When** o
   operador roda `/agente-00c-resume`, **Then** nenhuma nova pergunta de
   finalidade e exibida e o tier em vigor continua `local` (FR-002).
3. **Given** operador pressiona Enter ou responde entrada invalida a
   pergunta, **When** o init prossegue, **Then** o tier registrado e o
   default `cloud-public` (profundidade plena — comportamento identico ao
   atual, zero regressao) (FR-003).

---

### User Story 2 - Pipeline calibra profundidade pelo tier (Priority: P2)

Com o tier persistido, as etapas da pipeline recebem o sinal e ajustam a
profundidade: briefing/specify/plan dimensionam escopo e arquitetura
proporcionais a finalidade; os quality gates complementares rodam
conforme uma matriz tier×gate (ex.: revisao de seguranca completa
somente para tiers de nuvem; tier local roda versao leve ou pula com
registro); create-tasks gera backlog sem fases desnecessarias ao tier
(ex.: sem fase de deploy/observabilidade de producao em tier local).

**Why this priority**: e onde a economia de horas/dias acontece — mas
depende da captura (US1) existir primeiro.

**Independent Test**: executar duas pipelines do mesmo produto-exemplo,
uma `local` e uma `cloud-public`, e comparar artefatos: o backlog do
tier `local` tem menos fases e os gates de nuvem nao rodaram — cada gate
pulado com Decisao registrada (FR-004, FR-005, FR-006).

**Acceptance Scenarios**:

1. **Given** execucao com `delivery_tier=local`, **When** a pipeline
   atinge os quality gates complementares, **Then** os gates marcados
   como exclusivos de nuvem na matriz tier×gate nao executam e cada skip
   gera uma Decisao auditavel com o tier citado como justificativa
   (FR-005, FR-008).
2. **Given** execucao com `delivery_tier=cloud-public`, **When** a
   pipeline atinge os mesmos gates, **Then** todos os gates rodam
   completos — identico ao comportamento atual (FR-005).
3. **Given** execucao com `delivery_tier=local`, **When** create-tasks
   gera o backlog, **Then** o tasks.md nao contem fases de infraestrutura
   de publicacao (deploy em nuvem, escalabilidade, observabilidade de
   producao) (FR-006).
4. **Given** etapa specify/plan em execucao com tier registrado, **When**
   a skill correspondente e invocada, **Then** o contexto passado a skill
   inclui o tier vigente e a instrucao de calibrar profundidade (FR-004).
5. **Given** o mesmo produto-exemplo executado sob `delivery_tier=local`
   e sob `delivery_tier=cloud-public`, **When** `spec.md`/`plan.md` sao
   gerados em cada execucao, **Then** a execucao `local` produz
   `spec.md`/`plan.md` com contagem mensuravelmente menor de secoes de
   arquitetura e de NFRs detalhados que a execucao `cloud-public` do
   mesmo produto — medido no CONTEUDO do artefato, independente da
   contagem de tarefas/fases/ondas do backlog que SC-003 ja mede
   (FR-004, SC-005).

---

### User Story 3 - Tier auditavel e ajustavel conscientemente (Priority: P3)

O tier escolhido aparece na Decisao auditavel da execucao, no relatorio
final e no review-task. Se o operador perceber no meio da execucao que a
finalidade mudou (ex.: o produto local vai virar publico), ele ELEVA o
tier via decisao manual pre-onda — a mudanca fica registrada e vale das
ondas seguintes em diante.

**Why this priority**: transparencia e correcao de rumo; util mas nao
bloqueia o valor central de US1+US2.

**Independent Test**: concluir uma execucao com tier e verificar
relatorio/review-task citando o tier; elevar o tier entre ondas e
verificar Decisao registrada + gates de nuvem passando a rodar (FR-008,
FR-009).

**Acceptance Scenarios**:

1. **Given** execucao concluida com `delivery_tier=internal-network`,
   **When** o relatorio final e gerado, **Then** o tier declarado e as
   consequencias aplicadas (gates pulados/rodados) constam no relatorio
   (FR-008).
2. **Given** execucao pausada com `delivery_tier=local`, **When** o
   operador registra decisao manual de elevacao para `cloud-internal` e
   retoma, **Then** as ondas seguintes aplicam a matriz do tier novo e a
   elevacao consta como Decisao auditavel (FR-009).

---

### Edge Cases

- Estado legado sem o campo de tier (execucao iniciada antes desta
  feature) retomado via resume: tratar como `cloud-public` (profundidade
  plena), sem re-prompt — mesmo default de FR-003 (FR-010).
- Operador tenta REBAIXAR o tier no meio da execucao (ex.:
  `cloud-public` para `local`): rebaixamento mid-execucao nao e aplicado
  automaticamente; requer decisao manual explicita e vale apenas para
  ondas futuras — artefatos ja gerados nao sao reduzidos retroativamente
  (FR-009).
- Tier `local` num produto que consome API externa com dados sensiveis:
  a calibracao NAO desativa o Principio VI nem as guardas enforced — a
  veracidade de dados e os bloqueios de comando valem identicos em todos
  os tiers (FR-007).
- Execucao em modo nao-interativo (sem operador presente para responder):
  aplicar o default `cloud-public` sem bloquear o init (FR-003).

## Requirements

### Functional Requirements

- **FR-001**: O inicio de `/agente-00c` MUST exibir, antes da
  inicializacao do estado, uma pergunta unica de finalidade com
  exatamente 4 opcoes canonicas, mapeadas aos tokens estaveis
  `local`, `internal-network`, `cloud-internal` e `cloud-public`.
- **FR-002**: A escolha MUST persistir em campo proprio do estado da
  execucao (`delivery_tier`) gravado no init; retomadas
  (`/agente-00c-resume`) MUST reler o campo sem re-promptar — mesmo
  padrao do opt-in atomic-commit.
- **FR-003**: Ausencia de resposta, entrada invalida ou execucao
  nao-interativa MUST resultar no default `cloud-public` (profundidade
  plena), preservando o comportamento atual da pipeline como caso base
  (zero regressao).
- **FR-004**: O orquestrador MUST propagar o tier vigente no contexto
  das etapas briefing, specify e plan, com instrucao explicita de
  calibrar escopo e profundidade de arquitetura a finalidade declarada.
  A leitura do tier propagado MUST vir de fonte coagida ao enum fechado
  de 4 tokens — nunca texto livre interpolado diretamente no prompt da
  skill.
- **FR-005**: Os quality gates complementares MUST ser resolvidos por
  uma matriz tier×gate versionada no toolkit; gate ausente da matriz
  para um tier MUST rodar completo (fail-safe na direcao da
  profundidade). O mesmo fail-safe MUST cobrir o caso de uma linha
  PRESENTE na matriz com modo malformado, corrompido ou vazio — nao
  apenas o caso de par ausente: qualquer modo lido fora do enum fechado
  `completo|leve|skip` MUST ser coagido a `completo`, nunca propagado
  verbatim. A matriz cobre EXCLUSIVAMENTE o gate `owasp-security`
  (revisao de seguranca) — matriz default: completa nos tiers
  `cloud-internal` e `cloud-public`, versao leve (checagens essenciais:
  auth, secrets, input) em `internal-network`, skip com Decisao em
  `local`. Os demais gates complementares (`checklist`,
  `validate-documentation`, `validate-docs-rendered`, `analyze`) NAO tem
  celula na matriz e MUST rodar completos nos 4 tiers, sob o mesmo
  fail-safe. Skip ou versao leve de gate MUST gerar Decisao
  auditavel citando o tier — nunca skip silencioso.
- **FR-006**: create-tasks MUST receber o tier e aplicar uma divisao
  BINARIA nuvem/nao-nuvem: os tiers `local` e `internal-network` MUST
  omitir do backlog as fases de infraestrutura de producao (deploy em
  nuvem, escalabilidade e observabilidade de producao — entendida aqui
  como dashboards, SLO/SLI, APM/tracing, alertas e autoescala/
  multi-regiao/CDN de escala operacional; log de autenticacao/
  autorizacao e trilha de auditoria NUNCA entram nessa omissao, em
  qualquer tier); os tiers `cloud-internal` e `cloud-public` MUST gerar
  backlog completo com essas fases. Nao ha lista de fases distinta por
  tier alem dessa divisao binaria. create-tasks MUST registrar no
  proprio tasks.md o tier usado na geracao.
- **FR-007**: O tier MUST calibrar somente profundidade e escopo; MUST
  NOT alterar, relaxar ou desativar o Principio VI (zero fabricacao de
  dados), as guardas enforced (bash-guard, path-guard, secrets-filter)
  nem qualquer invariante de seguranca do runtime — em TODOS os tiers.
- **FR-008**: A escolha do tier MUST ser registrada como Decisao
  auditavel (5 campos) na execucao, e o tier + consequencias aplicadas
  (gates pulados/versao leve) MUST constar no relatorio final e no
  review-task. O review-task MUST detectar e reportar como finding
  qualquer mudanca do tier vigente sem Decisao de operador
  correspondente na trilha de auditoria
  (`delivery-tier-unattended-change`).
- **FR-009**: Elevacao de tier mid-execucao MUST ser suportada via
  decisao manual do operador entre ondas, valendo das ondas seguintes em
  diante; rebaixamento mid-execucao MUST NOT ser aplicado sem decisao
  manual explicita **do operador** e MUST NOT reduzir retroativamente
  artefatos ja gerados.
- **FR-010**: Estado legado sem o campo `delivery_tier` MUST ser tratado
  como `cloud-public` em qualquer leitor (orquestrador, resume, report)
  — sem re-prompt, sem erro de validacao.

> Decisoes de infraestrutura: N/A (a feature adiciona um campo de estado
> e logica de calibracao; sem scheduling, criptografia, tokens externos,
> multi-pod, backup ou retry proprios).

### Key Entities

- **DeliveryTier**: finalidade declarada do produto; enum de 4 valores
  (`local`, `internal-network`, `cloud-internal`, `cloud-public`),
  ordenados por profundidade crescente de entrega.
- **Matriz tier×gate**: mapeamento versionado de quais quality gates
  complementares rodam (completo | leve | skip) em cada tier; fail-safe:
  ausencia na matriz = rodar completo.

## Success Criteria

### Measurable Outcomes

- **SC-001**: A pergunta de finalidade adiciona no maximo UMA interacao
  ao inicio da execucao; retomadas adicionam zero.
- **SC-002**: Zero regressao no caso base: execucao com default
  `cloud-public` produz pipeline identica a de antes da feature (mesmos
  gates, mesmas fases de backlog).
- **SC-003**: Para um mesmo produto-exemplo simples, a execucao em tier
  `local` gera backlog com menos tarefas e menos fases que a execucao
  `cloud-public`, e conclui em menos ondas.
- **SC-004**: 100% das execucoes novas registram o tier no estado e no
  relatorio final; 100% dos gates pulados/leves tem Decisao auditavel
  correspondente (zero skip silencioso).
- **SC-005**: Para o mesmo produto-exemplo, a execucao em tier `local`
  produz `spec.md`/`plan.md` com contagem mensuravelmente menor de
  secoes de arquitetura e de NFRs detalhados que a execucao
  `cloud-public` — medida independente da contagem de
  tarefas/fases/ondas do backlog que SC-003 ja cobre.

## Delta Requirements

### Capability: delivery-tier

#### ADDED

- **FR-001**: O inicio de `/agente-00c` MUST exibir, antes da
  inicializacao do estado, uma pergunta unica de finalidade com
  exatamente 4 opcoes canonicas, mapeadas aos tokens estaveis
  `local`, `internal-network`, `cloud-internal` e `cloud-public`.
- **FR-002**: A escolha MUST persistir em campo proprio do estado da
  execucao (`delivery_tier`) gravado no init; retomadas
  (`/agente-00c-resume`) MUST reler o campo sem re-promptar — mesmo
  padrao do opt-in atomic-commit.
- **FR-003**: Ausencia de resposta, entrada invalida ou execucao
  nao-interativa MUST resultar no default `cloud-public` (profundidade
  plena), preservando o comportamento atual da pipeline como caso base
  (zero regressao).
- **FR-004**: O orquestrador MUST propagar o tier vigente no contexto
  das etapas briefing, specify e plan, com instrucao explicita de
  calibrar escopo e profundidade de arquitetura a finalidade declarada.
  A leitura do tier propagado MUST vir de fonte coagida ao enum fechado
  de 4 tokens — nunca texto livre interpolado diretamente no prompt da
  skill.
- **FR-005**: Os quality gates complementares MUST ser resolvidos por
  uma matriz tier×gate versionada no toolkit; gate ausente da matriz
  para um tier MUST rodar completo (fail-safe na direcao da
  profundidade). O mesmo fail-safe MUST cobrir o caso de uma linha
  PRESENTE na matriz com modo malformado, corrompido ou vazio — nao
  apenas o caso de par ausente: qualquer modo lido fora do enum fechado
  `completo|leve|skip` MUST ser coagido a `completo`, nunca propagado
  verbatim. A matriz cobre EXCLUSIVAMENTE o gate `owasp-security`
  (revisao de seguranca) — matriz default: completa nos tiers
  `cloud-internal` e `cloud-public`, versao leve (checagens essenciais:
  auth, secrets, input) em `internal-network`, skip com Decisao em
  `local`. Os demais gates complementares (`checklist`,
  `validate-documentation`, `validate-docs-rendered`, `analyze`) NAO tem
  celula na matriz e MUST rodar completos nos 4 tiers, sob o mesmo
  fail-safe. Skip ou versao leve de gate MUST gerar Decisao
  auditavel citando o tier — nunca skip silencioso.
- **FR-006**: create-tasks MUST receber o tier e aplicar uma divisao
  BINARIA nuvem/nao-nuvem: os tiers `local` e `internal-network` MUST
  omitir do backlog as fases de infraestrutura de producao (deploy em
  nuvem, escalabilidade e observabilidade de producao — entendida aqui
  como dashboards, SLO/SLI, APM/tracing, alertas e autoescala/
  multi-regiao/CDN de escala operacional; log de autenticacao/
  autorizacao e trilha de auditoria NUNCA entram nessa omissao, em
  qualquer tier); os tiers `cloud-internal` e `cloud-public` MUST gerar
  backlog completo com essas fases. Nao ha lista de fases distinta por
  tier alem dessa divisao binaria. create-tasks MUST registrar no
  proprio tasks.md o tier usado na geracao.
- **FR-007**: O tier MUST calibrar somente profundidade e escopo; MUST
  NOT alterar, relaxar ou desativar o Principio VI (zero fabricacao de
  dados), as guardas enforced (bash-guard, path-guard, secrets-filter)
  nem qualquer invariante de seguranca do runtime — em TODOS os tiers.
- **FR-008**: A escolha do tier MUST ser registrada como Decisao
  auditavel (5 campos) na execucao, e o tier + consequencias aplicadas
  (gates pulados/versao leve) MUST constar no relatorio final e no
  review-task. O review-task MUST detectar e reportar como finding
  qualquer mudanca do tier vigente sem Decisao de operador
  correspondente na trilha de auditoria
  (`delivery-tier-unattended-change`).
- **FR-009**: Elevacao de tier mid-execucao MUST ser suportada via
  decisao manual do operador entre ondas, valendo das ondas seguintes em
  diante; rebaixamento mid-execucao MUST NOT ser aplicado sem decisao
  manual explicita **do operador** e MUST NOT reduzir retroativamente
  artefatos ja gerados.
- **FR-010**: Estado legado sem o campo `delivery_tier` MUST ser tratado
  como `cloud-public` em qualquer leitor (orquestrador, resume, report)
  — sem re-prompt, sem erro de validacao.
