# Feature Specification: Reorganização do Dashboard Principal e Página de Métricas

**Feature**: `dashboard-refactor`
**Created**: 2026-07-28
**Status**: Draft

## Clarifications

### Session 2026-07-28

- Q: Como resolver o conflito entre a proibição literal de $/USD (Princípio
  III da constitution v1.1.0) e o requisito FR-003 de exibir o custo real
  medido por modelo (`otel_cost_usd`, schema v11)? → A: exibir o valor
  monetário absoluto em USD — `otel_cost_usd` é custo MEDIDO real (não
  estimado, não inventado). O operador humano autorizou emenda formal da
  constitution (Princípio III) para abrir exceção equivalente à já aberta
  para tokens medidos (emenda 1.1.0), cobrindo agora valor monetário medido;
  a emenda foi ratificada antes do `/plan` (ver Sync Impact Report da versão
  1.2.0 em `docs/constitution.md`).
- Q: Qual a direção final para o card de mix de modelos por etapa na página
  de Métricas (User Story 4), hoje relatado como duplicando visualmente o
  donut de mix total? → A: manter o card, adicionando o contexto de etapa
  que hoje falta — rótulos/eixo claros por etapa e ordenação pela ordem do
  pipeline. Não remover, não substituir por outra visualização.
- Q: Qual a profundidade do indicador de uso/custo por modelo no dashboard
  principal vs. página de Métricas (resolvido autonomamente, score 2 —
  briefing e constitution já davam base suficiente sem ambiguidade
  material)? → A: resumo compacto/agregado no dashboard principal; detalhe
  completo por modelo e por etapa na página de Métricas.

## User Scenarios & Testing

### User Story 1 - Ver uso e custo por modelo nas telas de observabilidade (Priority: P1)

Como engenheiro/tech-lead que dispara execuções autônomas, quero ver, tanto no
dashboard principal quanto na página de Métricas, os novos dados de uso e
custo por modelo que o índice de conhecimento passou a coletar — hoje esses
dados existem na fonte mas não aparecem em nenhuma tela.

**Why this priority**: é o pedido central do usuário ("novos valores para
ajudar nas métricas, como os custos por modelo") e a razão de ser desta
feature — sem isso as outras stories são só limpeza de UI.

**Independent Test**: com um projeto que tenha execuções recentes com dado
de uso por modelo disponível na fonte, o dashboard principal e a página de
Métricas exibem o breakdown por modelo sem exigir nenhuma outra mudança desta
spec.

**Acceptance Scenarios**:

1. **Given** uma execução com dado de uso por modelo disponível na fonte,
   **When** o usuário abre o dashboard principal, **Then** ele vê um
   indicador de uso/custo por modelo com rótulo explícito da natureza do
   número (medido vs. proxy vs. derivado).
2. **Given** uma execução cuja fonte ainda não coletou esse dado (execução
   antiga, ou spawn sem uso reportado), **When** o usuário abre a mesma tela,
   **Then** o sistema mostra estado de "sem dado" distinto de zero, sem
   quebrar a tela.
3. **Given** o mesmo dado exibido no dashboard principal, **When** o usuário
   navega até a página de Métricas, **Then** encontra a mesma informação de
   uso/custo por modelo, de forma consistente com o que viu no dashboard
   principal.

---

### User Story 2 - Dashboard principal sem cards obsoletos (Priority: P2)

Como usuário do dashboard principal, quero que cards que hoje não agregam
valor prático sejam removidos, para que a tela fique focada no que realmente
importa para acompanhar as execuções.

**Why this priority**: é uma limpeza de baixo risco, independente da User
Story 1, que já melhora a tela imediatamente.

**Independent Test**: abrir o dashboard principal e confirmar que os dois
cards identificados como desnecessários não aparecem mais, sem que nenhuma
outra tela dependa deles.

**Acceptance Scenarios**:

1. **Given** o dashboard principal, **When** o usuário o abre, **Then** o
   card que mostra custo por feature como proxy de chamadas de ferramenta não
   está mais presente.
2. **Given** o dashboard principal, **When** o usuário o abre, **Then** o
   card que mostra o funil de features por etapa corrente não está mais
   presente.
3. **Given** a remoção dos dois cards, **When** o layout é recalculado,
   **Then** os cards remanescentes ocupam o espaço de forma coerente (sem
   buracos vazios nem cards desproporcionais).

---

### User Story 3 - Throughput por etapa legível com muitas etapas (Priority: P2)

Como usuário da página de Métricas, quero que o gráfico de throughput por
etapa mostre no máximo as etapas mais relevantes e agregue o restante numa
única barra "Outros", para não perder a leitura do gráfico quando há muitas
etapas distintas.

**Why this priority**: mudança de contrato pontual e objetiva, com critério
de aceite claro; distinta e independente do trabalho de custo por modelo.

**Independent Test**: com um conjunto de dados que tenha mais de 10 etapas
distintas registradas, o gráfico mostra exatamente 10 barras nomeadas mais
uma barra "Outros" com a soma do restante.

**Acceptance Scenarios**:

1. **Given** mais de 10 etapas distintas com decisões registradas,
   **When** o usuário abre o gráfico de throughput por etapa, **Then** vê as
   10 etapas de maior volume nomeadas individualmente e uma barra "Outros"
   com a soma das demais.
2. **Given** 10 ou menos etapas distintas registradas, **When** o usuário
   abre o mesmo gráfico, **Then** todas aparecem nomeadas individualmente e
   nenhuma barra "Outros" é exibida.
3. **Given** a barra "Outros", **When** o usuário passa o mouse ou expande o
   detalhe, **Then** consegue identificar quais etapas foram agregadas nela.

---

### User Story 4 - Repensar o gráfico de mix de modelos por etapa (Priority: P3)

Como usuário da página de Métricas, quero que o gráfico de mix de modelos por
etapa deixe de duplicar visualmente a mesma informação do gráfico de mix de
modelos total ao lado, apresentando algo que realmente ajude a entender a
distribuição por etapa — ou seja removido, se não houver forma de o tornar
útil.

**Why this priority**: é a mudança mais aberta a interpretação de design,
priorizada por último para não travar as demais entregas enquanto a direção
final é definida.

**Independent Test**: revisar a tela de Métricas isoladamente e confirmar que
o card de mix de modelos por etapa deixou de ser uma barra empilhada sem
contexto de etapa, OU que foi removido — conforme decisão tomada na
clarificação desta spec.

**Acceptance Scenarios**:

1. **Given** a página de Métricas, **When** o usuário compara o card de mix
   de modelos total com o card de mix por etapa, **Then** o segundo aporta
   informação adicional clara (rótulo/eixo/contexto de etapa) que o primeiro
   não mostra — ou o card não existe mais.

---

### Edge Cases

- O que acontece quando uma execução não tem nenhum dado de uso por modelo
  disponível na fonte (execução anterior à coleta desse dado)? O sistema
  degrada mostrando "sem dado para este período/projeto", nunca zero.
- O que acontece quando o total de etapas distintas no throughput por etapa é
  exatamente 10? Nenhuma barra "Outros" aparece (regra: "Outros" só existe
  quando há excedente real).
- O que acontece quando a soma agregada em "Outros" é de uma única etapa
  excedente (a 11ª)? A barra "Outros" ainda aparece, representando essa
  única etapa remanescente, para manter o comportamento previsível
  independente da quantidade exata de excedentes.
- O que acontece com o card de mix de modelos por etapa após a clarificação
  (User Story 4, resolvida em Clarifications → Session 2026-07-28)? O card é
  mantido, passando a exibir rótulos/eixo claros por etapa e ordenação pela
  ordem do pipeline — deixa de ser uma repetição visual sem contexto do
  donut de mix total ao lado.

## Requirements

### Functional Requirements

- **FR-001**: O dashboard principal MUST deixar de exibir o card que mostra
  custo por feature como proxy de chamadas de ferramenta.
- **FR-002**: O dashboard principal MUST deixar de exibir o card de funil de
  features por etapa corrente.
- **FR-003**: O dashboard principal e a página de Métricas MUST exibir um
  indicador de uso/custo por modelo, cobrindo pelo menos: (a) o valor
  monetário MEDIDO (`otel_cost_usd`, schema v11 do knowledge.db) via
  instrumentação de custo por modelo, exibido em USD absoluto, e (b) a
  contagem de tokens por modelo, quando disponíveis na fonte para o
  projeto/período selecionado. Resolvido em Clarifications (Session
  2026-07-28, Q1): a constitution do projeto foi emendada (v1.1.0 → v1.2.0)
  para abrir, no Princípio III, a mesma exceção já concedida a tokens
  medidos (emenda 1.1.0) também a valor monetário MEDIDO — permanece
  proibido qualquer valor $/USD estimado, derivado ou inventado. (c)
  cardinalidade do `byModel` MUST ser limitada a 10 modelos nomeados
  (maior `costUsd` primeiro) + 1 linha agregada rotulada `'(outros)'` somando
  o restante, quando a fonte tiver mais de 10 modelos distintos no
  período — mesmo padrão numérico de truncamento de FR-006/007/008.
  Resolvido em FASE 1 (checklists/api.md CHK003).
- **FR-004**: Todo valor de uso/custo por modelo exibido MUST indicar
  explicitamente sua natureza (medido, proxy ou derivado) e MUST NOT ser
  somado ou confundido com o proxy de chamadas de ferramenta já existente
  (são grandezas diferentes: esforço do orquestrador vs. uso dos modelos).
- **FR-005**: Quando o dado de uso/custo por modelo for parcial (nem toda
  execução do período tem esse dado coletado), o sistema MUST exibir a
  cobertura da amostra (quantas execuções/ondas têm o dado vs. total),
  nunca apresentar parcial como completo.
- **FR-006**: O gráfico de throughput por etapa da página de Métricas MUST
  exibir, no máximo, as 10 etapas com maior volume nomeadas individualmente.
- **FR-007**: Quando existirem mais de 10 etapas distintas com volume
  registrado, o sistema MUST agregar as etapas excedentes (a partir da 11ª
  em volume) numa única barra rotulada "Outros", representando a soma do
  volume restante.
- **FR-008**: Quando existirem 10 ou menos etapas distintas com volume
  registrado, o sistema MUST NOT exibir a barra "Outros".
- **FR-009**: O card de mix de modelos por etapa na página de Métricas MUST
  ser mantido, ganhando o contexto de etapa hoje ausente: rótulos/eixo
  claros identificando cada etapa e ordenação das etapas conforme a ordem
  do pipeline SDD (specify→clarify→plan→checklist→create-tasks→
  execute-task→review-task). Resolvido em Clarifications (Session
  2026-07-28, Q2) — opção B (manter + contextualizar), não remover nem
  substituir por outra visualização.
- **FR-010**: Todas as métricas novas ou reorganizadas por esta feature
  MUST seguir o mesmo padrão de degradação já adotado nas demais métricas do
  painel: ausência ou erro na fonte de dados nunca resulta em erro de
  sistema (nunca `5xx`), apenas em estado explícito de "sem dado".
  Referência: Princípio II da constitution do projeto ("Degradar, Nunca
  Quebrar").
- **FR-011**: O painel MUST permanecer somente leitura — nenhuma mudança
  desta feature introduz escrita, edição ou mutação de dados na fonte.

> **Decisões de infraestrutura**: N/A (feature stateless, somente leitura,
> sem scheduling, sem criptografia, sem refresh de token externo, sem
> mutex multi-pod, sem backup/restore, sem idempotência de escrita — o
> painel não escreve nada).

### Premissas e Notas de Escopo (Checklist)

Resolvidas na FASE 1 do backlog (`tasks.md`), a partir dos 11 gaps
identificados nos checklists `checklists/api.md` e `checklists/ux.md`.

- **`NULL` ≠ `0` em `costUsd`/`totalTokens` (api CHK007)**: já coberto pelo
  nível de abstração deste spec (Edge Cases: "nunca zero") e por FR-005; não
  vira um FR numerado novo — o detalhe técnico dos três estados vive no
  contrato (`contracts/model-usage-endpoint.md` Invariante 1), que é o
  artefato correto para esse nível de detalhe.
- **Assimetria de filtro entre `model-usage` e `model-mix-by-stage` (api
  CHK008)**: aceita como está. FR-009 só exige contexto de etapa
  (rótulos/eixo/ordenação) no card de mix por etapa, não paridade de filtro
  com o card novo; estender `model-mix-by-stage` para aceitar
  `project`/`period` está fora do escopo desta feature.
- **Escopo de Segurança (api CHK012)**: esta feature herda, sem alteração,
  a premissa já ratificada em `docs/constitution.md` §Padrões de Segurança
  e Qualidade: bind em `localhost`, sem autenticação real, sem
  RBAC/multi-tenant no MVP. Nenhum endpoint desta feature introduz
  autenticação ou rate-limit novos.
- **Campo legado `modelo` (pt-BR) (api CHK014)**: `model-mix`/
  `model-mix-by-stage` mantêm o campo `modelo` inalterado por esta feature
  (`contracts/existing-endpoints.md`); não é uma inconsistência a corrigir
  aqui.
- **Critério de layout coerente pós-remoção (ux CHK002)**: critério
  objetivo — os grids responsivos já existentes (`grid-overview`, `grid-N`
  em `apps/web/src/styles/prototype.css`) recalculam automaticamente via os
  breakpoints já definidos (1200/900/600/480px) quando 2 cards saem da
  grade; validação final por review visual do dono do produto (critério
  qualitativo, mas ancorado em CSS existente, não em regra nova).
- **Quantificação resumo vs. detalhe (ux CHK005)**: o dashboard principal
  exibe um resumo compacto com os top-3 modelos por `costUsd` (apenas o
  campo `costUsd`, com rótulo de natureza); a página de Métricas exibe o
  detalhe completo — todos os modelos até o limite de cardinalidade de
  FR-003(c), com `costUsd` e `totalTokens`, mais `coverage`.
- **Acessibilidade de cor por modelo (ux CHK007)**: a codificação por cor de
  modelo MUST sempre vir acompanhada de rótulo textual redundante (nome do
  modelo) — mesmo padrão já usado pelo componente `Legend`
  (`apps/web/src/components/charts.tsx`); nenhuma informação nova depende
  de cor isolada.
- **Navegação por teclado / mecanismo da barra "Outros" (ux CHK008,
  CHK010)**: o indicador de uso por modelo é puramente informativo (CHK006,
  já resolvido) — sem interação, sem requisito de teclado adicional. Para a
  barra "Outros" do throughput por etapa (FR-007), o mecanismo escolhido é
  clique/toque (não apenas hover): o app já possui breakpoints responsivos
  até largura de celular (CHK014 abaixo), então um mecanismo hover-only
  excluiria toque. O elemento MUST ser focável (nativamente ou via
  `tabIndex`) e ativável por teclado (Enter/Espaço), expondo
  `othersMembers` (já modelado em `data-model.md`) num painel de detalhe.
- **Responsividade mobile/tablet (ux CHK014)**: não é premissa de exclusão
  de escopo — o app já implementa grids responsivos com breakpoints até
  480px (`apps/web/src/styles/prototype.css:29-40`,
  `apps/web/src/styles/tokens.css:733-781`). Esta feature MUST preservar
  esse comportamento responsivo já existente, sem introduzir requisito
  adicional de responsividade além do que já está implementado.

### Key Entities

- **Uso por Modelo em uma Execução**: representa o custo e o volume de
  tokens atribuídos a um modelo específico, dentro de uma onda/execução.
  Já é coletado pela fonte de dados do painel, mas ainda não é exposto em
  nenhuma tela — é o dado central desta feature. Tem granularidade por
  onda x modelo (uma execução pode ter usado mais de um modelo ao longo do
  pipeline).
- **Etapa do Pipeline SDD**: uma das etapas nomeadas do fluxo
  specify→clarify→plan→checklist→create-tasks→execute-task→review-task,
  usada tanto no throughput por etapa quanto no mix de modelos por etapa.
- **Cobertura da Amostra**: proporção entre quantas execuções/ondas de um
  período têm um dado medido coletado vs. o total de execuções/ondas do
  mesmo período — usada para não apresentar dado parcial como completo.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Um usuário consegue identificar, a partir do dashboard
  principal, qual foi o modelo de maior custo/uso em uma execução recente
  em menos de 10 segundos, sem precisar navegar para outra tela.
- **SC-002**: O gráfico de throughput por etapa nunca exibe mais de 11
  barras (10 etapas nomeadas + 1 barra "Outros"), independente de quantas
  etapas distintas existam nos dados.
- **SC-003**: Após a mudança, 0 dos 2 cards identificados como obsoletos
  ("custo por feature - proxy" e "funil do pipeline") permanecem visíveis
  no dashboard principal.
- **SC-004**: 100% dos valores de uso/custo por modelo exibidos em qualquer
  tela trazem um rótulo indicando a natureza do dado (medido, proxy ou
  derivado), sem exceção.
- **SC-005**: A informação de uso/custo por modelo aparece de forma
  consistente em pelo menos 2 telas (dashboard principal e página de
  Métricas), sem divergência de valores para o mesmo período/projeto.

## Delta Requirements

**Skip**: o corpus canônico `docs/specs/current/` ainda não existe neste
projeto (nenhum arquivo encontrado) — não há capability já registrada para
reusar ou alterar via bloco `### Capability:`. Esta feature altera telas já
implementadas (Overview e Metrics) mas sem um corpus living-specs para
registrar o delta formalmente ainda — dashboard-refactor, 2026-07-28.
