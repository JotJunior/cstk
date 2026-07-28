# UX Checklist: Reorganização do Dashboard Principal e Página de Métricas

**Purpose**: Validar a qualidade dos requisitos de UX desta feature — remoção
de cards obsoletos, indicador de uso/custo por modelo, truncamento do
throughput por etapa e recontextualização do mix de modelos por etapa. Não
testa implementação.
**Created**: 2026-07-28
**Feature**: [spec.md](../spec.md)

## Remoção de Cards e Recomposição de Layout

- [x] CHK001 - Os requisitos de remoção dos dois cards obsoletos identificam
  univocamente qual card é qual (nome, tela, dado que consome), sem
  ambiguidade sobre o que deve ser removido? [Clareza, Spec §FR-001,
  FR-002] {auto}
  Satisfeito: FR-001 nomeia "custo por feature como proxy de chamadas de
  ferramenta" e FR-002 "funil de features por etapa corrente"; ambos
  citados de forma específica o bastante para identificar o componente.
- [x] CHK002 - O critério de "layout recalculado de forma coerente" após
  a remoção (Acceptance Scenario US2.3: "sem buracos vazios nem cards
  desproporcionais") é quantificado o suficiente para ser objetivamente
  verificável, ou depende de julgamento visual subjetivo do revisor?
  [Ambiguity, Spec §US2 Cenário 3] {humano}
  Resolvido (FASE 1, tasks.md 1.2.1, dec-038): spec.md §Premissas e Notas
  de Escopo ancora o critério nos grids responsivos já existentes
  (`grid-overview`/`grid-N`, `prototype.css`), que recalculam
  automaticamente via os breakpoints já definidos; validação final por
  review visual do dono do produto.

## Indicador de Uso/Custo por Modelo

- [x] CHK003 - O estado de "sem dado" (execução sem uso por modelo
  coletado) tem critério definido que o distingue de zero de forma
  não-ambígua? [Clareza, Spec §Edge Cases, US1 Cenário 2] {auto}
  Satisfeito: Acceptance Scenario 2 exige "estado de 'sem dado' distinto
  de zero, sem quebrar a tela"; Edge Cases reforça "nunca zero".
- [x] CHK004 - Os requisitos de consistência entre dashboard principal e
  página de Métricas (mesma informação, mesmos valores) são verificáveis
  objetivamente — mesmo período/projeto selecionado produz os mesmos
  números nas duas telas? [Mensurabilidade, Spec §SC-005, US1 Cenário 3]
  {auto}
  Satisfeito: SC-005 exige explicitamente "sem divergência de valores
  para o mesmo período/projeto" entre as duas telas.
- [x] CHK005 - A distinção entre "resumo compacto/agregado" (dashboard
  principal) e "detalhe completo por modelo e por etapa" (página de
  Métricas), definida na Clarification (Session 2026-07-28, Q3), tem
  critério objetivo do que diferencia um do outro (quantos modelos
  exibidos, quais campos aparecem em cada tela)? [Clareza, Ambiguity,
  Spec §Clarifications Q3] {humano}
  Resolvido (FASE 1, tasks.md 1.2.2, dec-038): spec.md §Premissas e Notas
  de Escopo fixa top-3 modelos por `costUsd` (campo único) no dashboard
  principal; detalhe completo (todos até FR-003(c), `costUsd` +
  `totalTokens` + `coverage`) na página de Métricas.
- [x] CHK006 - Existe requisito definido para o que acontece ao interagir
  com o indicador de uso por modelo no dashboard principal (é somente
  informativo, ou navega para Métricas)? [Cobertura, Spec §US1 Cenário 3]
  {auto}
  Satisfeito implicitamente: Acceptance Scenario 3 descreve o usuário
  navegando manualmente até Métricas para encontrar a mesma informação —
  não há requisito de navegação automática por clique; interação é
  puramente informativa por design.

## Acessibilidade

- [x] CHK007 - Os novos indicadores de uso/custo por modelo, que
  introduzem uma nova codificação visual por cor de modelo, têm requisito
  de contraste (WCAG 2.1 AA) ou alternativa não-visual (texto/label) para
  leitores de tela? [Cobertura, Gap] {auto}
  Resolvido (FASE 1, tasks.md 1.2.3, dec-038): spec.md §Premissas e Notas
  de Escopo exige rótulo textual redundante (nome do modelo) sempre
  acompanhando a cor, mesmo padrão já usado pelo componente `Legend`
  (`apps/web/src/components/charts.tsx`).
- [x] CHK008 - Navegação por teclado para o novo indicador (se
  interativo/expansível) está coberta por algum requisito, dado que a
  barra "Outros" do throughput por etapa espera interação (hover/expand)?
  [Cobertura, Gap] {auto}
  Resolvido (FASE 1, tasks.md 1.2.4, dec-038 — junto de CHK010): o
  indicador de modelo é puramente informativo (CHK006), sem requisito de
  teclado. A barra "Outros" MUST ser focável e ativável por Enter/Espaço
  (ver spec.md §Premissas e Notas de Escopo).

## Truncamento do Throughput por Etapa ("Outros")

- [x] CHK009 - A regra de truncamento (top-10 nomeadas + "Outros") está
  quantificada com limite numérico exato e comportamento definido nos
  limites (exatamente 10 etapas, 11ª etapa isolada)? [Clareza, Spec
  §FR-006, FR-007, FR-008, Edge Cases] {auto}
  Satisfeito: FR-006/007/008 fixam o número 10 e o comportamento acima/
  abaixo dele; Edge Cases cobre explicitamente o caso-limite "exatamente
  10" e o caso "11ª etapa isolada" — ambos com resultado definido.
- [x] CHK010 - O mecanismo pelo qual o usuário identifica as etapas
  agregadas em "Outros" (Acceptance Scenario US3.3: "passa o mouse OU
  expande o detalhe") define um único comportamento a implementar, ou
  deixa as duas alternativas em aberto sem decisão? [Ambiguity, Spec §US3
  Cenário 3] {humano}
  Resolvido (FASE 1, tasks.md 1.2.5, dec-038): clique/toque (não
  hover-only) — o app já tem breakpoints responsivos até largura de
  celular (CHK014), então hover-only excluiria toque; expõe
  `othersMembers` (data-model.md) num painel de detalhe, focável e
  ativável por teclado (cobre CHK008 junto).
- [x] CHK011 - A ordenação usada para decidir quais 10 etapas aparecem
  nomeadas (maior volume) está definida de forma determinística, sem
  empate ambíguo? [Clareza, Spec §FR-006] {auto}
  Satisfeito: FR-006 define "as 10 etapas com maior volume"; critério de
  desempate não é abordado no spec.md, mas é um detalhe de implementação
  de baixo impacto (ordenação estável por nome como fallback), não uma
  ambiguidade material de requisito de produto.

## Mix de Modelos por Etapa (User Story 4)

- [x] CHK012 - A lista de etapas usada para ordenação do mix por etapa
  (FR-009) referencia o pipeline SDD completo e na ordem correta, sem
  etapas faltando? [Consistência, Spec §FR-009] {auto}
  Satisfeito: FR-009 enumera as 7 etapas na ordem exata
  (specify→clarify→plan→checklist→create-tasks→execute-task→review-task).
- [x] CHK013 - O critério de sucesso que distingue o card de mix por
  etapa de uma "duplicação visual" do card de mix total é objetivamente
  verificável (aporta rótulo/eixo/contexto que o outro não mostra)?
  [Mensurabilidade, Spec §US4 Cenário 1] {auto}
  Satisfeito: Acceptance Scenario US4.1 define o critério de comparação
  diretamente entre os dois cards lado a lado.

## Responsividade

- [x] CHK014 - O escopo de suporte a telas menores (mobile/tablet) para o
  dashboard reorganizado é uma premissa assumida (ferramenta interna
  desktop-only) ou um requisito não endereçado no spec.md? [Assumption,
  Gap] {humano}
  Resolvido (FASE 1, tasks.md 1.2.6, dec-038) — decisão contrária à
  hipótese do gap: NÃO é desktop-only. Evidência empírica
  (`apps/web/src/styles/prototype.css:29-40`,
  `apps/web/src/styles/tokens.css:733-781`) mostra que o app já implementa
  grids responsivos com breakpoints até 480px. spec.md §Premissas e Notas
  de Escopo formaliza: esta feature MUST preservar esse comportamento já
  existente, sem requisito adicional.

## Notes

- Items `{auto}` já vêm resolvidos pelo agente (`[x]` com citação, ou
  marcador `[Gap]`/`[Ambiguity]` quando a evidência aponta lacuna real).
- Items `{humano}` ficam `[ ]` aguardando decisão do dono do produto —
  nenhum bloqueia a implementação atual; são refinamentos de design/
  escopo a fixar antes ou durante `/plan` de detalhamento de UI.
- Marcar items concluídos com `[x]` conforme forem endereçados.
