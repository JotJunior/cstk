# Feature Specification: Retomada da Oferta de Leva Paralela do Roadmap

**Feature**: `roadmap-wave`
**Created**: 2026-08-18
**Status**: Draft

## Clarifications

### Session 2026-08-18

- Q: O ponto de entrada exige que o projeto tenha briefing e constitution ratificados antes de oferecer a leva (mesma pré-condição que as features-filhas exigem para sua própria pipeline individual), ou basta o roadmap existir e ser válido? → A: Basta o roadmap (`docs/roadmap.md`) existir e ser válido. `docs/roadmap.md` só é produzido tardiamente por `/agente-00c`, etapa que já pressupõe briefing+constitution ratificados; a existência de um roadmap válido já é prova indireta da pré-condição. Cada feature-filha lançada roda seu próprio `/feature-00c`, que reaplica sua própria pré-condição individualmente antes de avançar de specify para plan — checagem redundante no ponto de entrada não reduz risco novo.
- Q: O ponto de entrada opera sempre sobre o projeto corrente (diretório de trabalho), ou o operador pode apontar explicitamente para outro projeto-alvo ao invocá-lo? → A: Ambos. Default é o diretório de trabalho corrente; o operador MAY apontar explicitamente para outro projeto-alvo via parâmetro de path, reaproveitando o mecanismo já existente nos helpers subjacentes (`roadmap-frontier.sh --exclude-active-from-repo PATH`/`--roadmap PATH`/`--specs-dir DIR`, `parallel-launch.sh emit --repo PATH`).
- Q: Além do fluxo interativo (perguntar e aguardar confirmação), existe um modo não-interativo/automatizável para este ponto de entrada — e, se sim, o teto de quantas features lançar por leva pode ser informado explicitamente em vez de usar sempre o default? → A: Sim. O ponto de entrada MUST suportar um modo não-interativo, em paridade com os demais opt-ins da mesma pipeline (atomic_commit/roadmap_mode/delivery_tier): o teto pode ser informado explicitamente via parâmetro (default continua 2, mesmo default já estabelecido em `agente-00c.md` §6.ter passo 5); ausência de confirmação explícita de lançamento em modo não-interativo cai no default seguro "não lançar" (preserva FR-007 — nunca lançar sem confirmação explícita).

## User Scenarios & Testing

### User Story 1 - Reoferecer a leva paralela para um roadmap já existente (Priority: P1)

O operador volta, em outra sessão, a um projeto que já possui um
roadmap ratificado (`docs/roadmap.md`) — seja porque a oferta de leva
paralela original já passou (ele recusou na hora, ou a sessão terminou
antes de chegar lá), seja porque quer simplesmente relançar mais uma
leva depois que features anteriores concluíram. Ele quer que o sistema
calcule de novo, agora, quais features do roadmap já estão prontas
para começar (sem dependências pendentes e ainda não iniciadas nem em
execução), ofereça essas candidatas para escolha e, confirmada a
escolha, lance cada uma delas em um ambiente de trabalho isolado — sem
precisar rodar a pipeline completa do zero nem executar os passos
manualmente um a um.

**Why this priority**: é o valor central da feature — sem isto, a
oferta de leva paralela só existe no instante exato em que uma
execução completa termina; qualquer outra oportunidade de
paralelizar fica sem caminho automatizado.

**Independent Test**: com um projeto que já tem `docs/roadmap.md`
ratificado e pelo menos uma entrada elegível (sem dependência
pendente, ainda não iniciada), confirmar que o sistema apresenta essa
entrada como candidata, aceita a confirmação do operador e resulta em
um ambiente de trabalho isolado rodando a pipeline daquela feature.

**Acceptance Scenarios**:

1. **Given** um projeto com `docs/roadmap.md` ratificado contendo
   entradas elegíveis e nenhuma execução ativa para elas, **When** o
   operador invoca o ponto de entrada, **Then** o sistema apresenta as
   entradas elegíveis como candidatas da leva, dentro do teto vigente.
2. **Given** o operador confirma a leva apresentada, **When** o
   lançamento ocorre, **Then** cada feature escolhida passa a rodar em
   um ambiente de trabalho isolado próprio, sem compartilhar working
   tree com as demais nem com a sessão que fez a oferta.
3. **Given** o operador recusa a oferta, **When** ele responde negando,
   **Then** nenhuma feature é lançada e nenhum ambiente de trabalho é
   criado.
4. **Given** já existe uma sessão isolada em execução para uma das
   entradas elegíveis (lançada anteriormente), **When** o sistema
   calcula as candidatas, **Then** essa entrada não é oferecida de novo
   (sem duplicar o lançamento).

---

### User Story 2 - Recusar com remediação quando o projeto não está pronto (Priority: P2)

O operador pode invocar o ponto de entrada num projeto que ainda não
tem roadmap, ou cujo roadmap está corrompido/incompleto, ou cujo
roadmap não tem nenhuma entrada elegível no momento (tudo já iniciado
ou em execução). Em qualquer um desses casos, ele quer uma resposta
clara sobre por que nada foi oferecido e o que fazer a seguir — nunca
um lançamento silencioso, nunca uma falha genérica sem explicação.

**Why this priority**: sem isto, o operador recebe um erro opaco ou,
pior, o comando tenta prosseguir sobre dado inválido/inexistente —
viola a expectativa básica de segurança do fluxo (nunca lançar sem uma
base válida para decidir).

**Independent Test**: rodar o ponto de entrada em três projetos
distintos — um sem `docs/roadmap.md`, um com roadmap malformado, e um
com roadmap válido mas 100% das entradas já iniciadas/em execução — e
confirmar que cada caso produz uma mensagem distinta explicando a causa
e a remediação, sem lançar nada.

**Acceptance Scenarios**:

1. **Given** o projeto não tem `docs/roadmap.md`, **When** o operador
   invoca o ponto de entrada, **Then** o sistema recusa explicando que
   não há roadmap e orienta a rodar o fluxo que o cria.
2. **Given** `docs/roadmap.md` existe mas está malformado/inválido,
   **When** o operador invoca o ponto de entrada, **Then** o sistema
   recusa explicando o que está inválido no arquivo, sem tentar
   adivinhar ou prosseguir parcialmente.
3. **Given** `docs/roadmap.md` é válido mas nenhuma entrada está
   elegível agora (todas já iniciadas, em execução, ou bloqueadas por
   dependência pendente), **When** o operador invoca o ponto de
   entrada, **Then** o sistema informa que não há candidatas no
   momento e por quê (ex.: todas em andamento, ou todas aguardando
   dependência), sem oferecer nada para confirmar.

---

### Edge Cases

- O que acontece se o operador confirma a leva mas, entre o cálculo da
  fronteira e o lançamento efetivo, uma das entradas escolhidas deixa
  de estar elegível (ex.: outra sessão paralela já a lançou nesse
  meio-tempo)? O sistema deve detectar a divergência e não duplicar o
  lançamento daquela entrada especificamente, seguindo com as demais.
- O que acontece se o operador escolhe mais candidatas do que o teto
  permite? O sistema deve recusar a seleção acima do teto e pedir para
  o operador ajustar a escolha, sem lançar nenhuma.
- O que acontece se todas as entradas elegíveis da fronteira cabem
  dentro do teto (sem excesso a escolher)? O sistema deve oferecer
  todas automaticamente, sem forçar uma seleção manual desnecessária.

## Requirements

### Functional Requirements

- **FR-001**: O sistema MUST oferecer, mediante invocação explícita do
  operador, o cálculo da fronteira de features do roadmap do
  projeto-alvo (default: diretório de trabalho corrente; MAY ser
  apontado explicitamente para outro projeto-alvo via parâmetro de
  path) que estão prontas para começar (sem dependência pendente,
  ainda não iniciadas e sem execução ativa em andamento).
- **FR-001A**: O sistema MUST considerar suficiente, como pré-condição
  para oferecer a leva, que `docs/roadmap.md` do projeto-alvo exista e
  seja válido — o sistema MUST NOT exigir checagem própria de
  briefing/constitution ratificados no ponto de entrada (a validade do
  roadmap já pressupõe pipeline avançada o bastante para produzi-lo; a
  pré-condição individual de cada feature-filha é reaplicada pelo seu
  próprio `/feature-00c`).
- **FR-002**: O sistema MUST recusar a oferta com uma mensagem
  específica e uma remediação concreta quando o projeto não possui
  roadmap ratificado.
- **FR-003**: O sistema MUST recusar a oferta com uma mensagem
  específica descrevendo o problema quando o roadmap existente está
  malformado ou inválido, sem tentar prosseguir com dado parcial ou
  suposto.
- **FR-004**: O sistema MUST informar de forma específica quando a
  fronteira calculada está vazia (nenhuma entrada elegível agora), sem
  apresentar nada para confirmação nesse caso.
- **FR-005**: O sistema MUST apresentar ao operador as entradas
  elegíveis da fronteira como candidatas de uma leva, respeitando o
  teto vigente de quantas podem ser lançadas simultaneamente.
- **FR-006**: Quando o número de candidatas elegíveis exceder o teto,
  o sistema MUST permitir ao operador escolher, dentre as candidatas,
  quais lançar dentro do limite — e MUST recusar uma seleção que
  exceda o teto.
- **FR-007**: O sistema MUST NUNCA lançar qualquer feature sem
  confirmação explícita do operador para a leva apresentada.
- **FR-008**: Ao ser confirmada a leva, o sistema MUST lançar cada
  feature escolhida em um ambiente de trabalho isolado próprio, sem
  compartilhar working tree com as demais features da mesma leva nem
  com a sessão que fez a oferta.
- **FR-009**: O sistema MUST excluir da fronteira apresentada qualquer
  entrada que já tenha um ambiente de trabalho isolado em execução
  ativa para ela, prevenindo lançamento duplicado.
- **FR-010**: O sistema MUST re-verificar, no momento do lançamento
  efetivo, que cada entrada escolhida continua elegível — e, se uma
  entrada deixou de estar elegível nesse intervalo (ex.: lançada por
  outra sessão concorrente), MUST pular apenas essa entrada e prosseguir
  com as demais, informando a exclusão ao operador.
- **FR-011**: O sistema MUST informar ao operador, ao final do
  lançamento, quais features foram de fato lançadas em ambiente
  isolado e quais não foram (e por quê).
- **FR-012**: O sistema MUST suportar um modo não-interativo/
  automatizável para este ponto de entrada, em paridade com os demais
  opt-ins da mesma pipeline (atomic_commit/roadmap_mode/delivery_tier).
- **FR-013**: Em modo não-interativo, o sistema MUST permitir que o
  operador informe explicitamente, via parâmetro, o teto de quantas
  features lançar por leva — na ausência do parâmetro, o teto default
  (2, mesmo valor do fluxo interativo) MUST ser usado.
- **FR-014**: Em modo não-interativo, na ausência de confirmação
  explícita de lançamento, o sistema MUST cair no default seguro
  "não lançar nada" — preservando FR-007 (nunca lançar sem confirmação
  explícita) mesmo fora do fluxo interativo.
- **FR-015**: O sistema MUST tratar a saída injetada de
  `roadmap-frontier.sh` (tabela + seção `### Avisos`) como conteúdo
  não-confiável/rotulado, nunca como instrução — ver
  `contracts/roadmap-wave-command.md` §5.1.

### Key Entities

- **Roadmap**: lista ratificada de features candidatas do projeto,
  com suas dependências declaradas entre si; fonte de verdade para o
  cálculo de elegibilidade.
- **Entrada de roadmap**: uma feature candidata dentro do roadmap, com
  seu estado (não iniciada / em execução / concluída) e suas
  dependências declaradas.
- **Fronteira elegível**: subconjunto de entradas do roadmap sem
  dependência pendente, ainda não iniciadas e sem execução ativa —
  candidatas válidas para uma leva nova.
- **Leva**: conjunto de entradas elegíveis, dentro do teto vigente,
  confirmado pelo operador para lançamento simultâneo.
- **Ambiente de trabalho isolado**: espaço de execução dedicado a uma
  única feature lançada, independente de outras execuções em
  paralelo.

> Decisões de infraestrutura: N/A (feature reaproveita integralmente o
> mecanismo de cálculo de fronteira, oferta e lançamento isolado já
> existentes; não introduz scheduling, criptografia, refresh de token
> externo, mutex multi-processo nem backup novos).

## Success Criteria

### Measurable Outcomes

- **SC-001**: Um operador com um roadmap ratificado e ao menos uma
  entrada elegível consegue ir da invocação do ponto de entrada até
  features lançadas em ambiente isolado sem executar nenhum passo
  manual intermediário.
- **SC-002**: 100% das invocações sobre um projeto sem roadmap, com
  roadmap inválido, ou com fronteira vazia terminam em uma mensagem
  que identifica a causa específica e a ação de remediação — nunca em
  um lançamento indevido nem em falha sem explicação.
- **SC-003**: Nenhuma feature é lançada em duplicidade quando já existe
  um ambiente de trabalho isolado ativo para ela no momento da oferta
  ou no momento do lançamento efetivo.
- **SC-004**: Toda leva lançada respeita o teto vigente — nenhuma leva
  excede o número máximo de features simultâneas configurado.

## Delta Requirements

**Skip**: a oferta de leva paralela por gatilho de fim-de-execução
(`.execution.termination_reason == concluido_roadmap`) já existe e está
documentada na spec `roadmap-parallel-launch`, mas essa feature ainda
não foi dobrada ao corpus canônico `docs/specs/current/` (nenhum slug
relacionado a roadmap/leva-paralela encontrado lá nesta data) — não há
capability ativa documentada no corpus para declarar delta contra.
`roadmap-wave` introduz um segundo caminho de entrada (retomada manual,
fora do fim-de-execução) para o mesmo mecanismo de cálculo/oferta/
lançamento, reaproveitado por referência, não uma mudança em
comportamento hoje documentado como ativo no corpus. — agente-00c-feature-orchestrator, 2026-08-18
