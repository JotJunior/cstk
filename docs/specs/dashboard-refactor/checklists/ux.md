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
- [ ] CHK002 - O critério de "layout recalculado de forma coerente" após
  a remoção (Acceptance Scenario US2.3: "sem buracos vazios nem cards
  desproporcionais") é quantificado o suficiente para ser objetivamente
  verificável, ou depende de julgamento visual subjetivo do revisor?
  [Ambiguity, Spec §US2 Cenário 3] {humano}
  O critério é qualitativo por natureza (grid responsivo); não há
  referência a número de colunas/breakpoint. Aceitável como requisito de
  UX de alto nível, mas quem valida o "coerente" é o dono do produto no
  review visual, não um teste automatizado.

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
- [ ] CHK005 - A distinção entre "resumo compacto/agregado" (dashboard
  principal) e "detalhe completo por modelo e por etapa" (página de
  Métricas), definida na Clarification (Session 2026-07-28, Q3), tem
  critério objetivo do que diferencia um do outro (quantos modelos
  exibidos, quais campos aparecem em cada tela)? [Clareza, Ambiguity,
  Spec §Clarifications Q3] {humano}
  A resposta da clarificação fixa a direção (resumo vs. detalhe) mas não
  quantifica limites (ex: top-N modelos no resumo, quais dos 3 campos
  `costUsd`/`totalTokens`/`waves` aparecem no compacto). Decisão de design
  a confirmar antes de `/plan` de UI detalhado.
- [x] CHK006 - Existe requisito definido para o que acontece ao interagir
  com o indicador de uso por modelo no dashboard principal (é somente
  informativo, ou navega para Métricas)? [Cobertura, Spec §US1 Cenário 3]
  {auto}
  Satisfeito implicitamente: Acceptance Scenario 3 descreve o usuário
  navegando manualmente até Métricas para encontrar a mesma informação —
  não há requisito de navegação automática por clique; interação é
  puramente informativa por design.

## Acessibilidade

- [ ] CHK007 - Os novos indicadores de uso/custo por modelo, que
  introduzem uma nova codificação visual por cor de modelo, têm requisito
  de contraste (WCAG 2.1 AA) ou alternativa não-visual (texto/label) para
  leitores de tela? [Cobertura, Gap] {auto}
  Gap: nenhum FR ou Success Criterion menciona contraste de cor ou
  suporte a leitor de tela para a nova codificação por modelo. O gate de
  segurança (Invariante 10) trata apenas do risco de prototype pollution
  na função de cor, não de acessibilidade.
- [ ] CHK008 - Navegação por teclado para o novo indicador (se
  interativo/expansível) está coberta por algum requisito, dado que a
  barra "Outros" do throughput por etapa espera interação (hover/expand)?
  [Cobertura, Gap] {auto}
  Gap: Acceptance Scenario US3.3 define a necessidade de identificar
  etapas agregadas via "mouse ou expande o detalhe", mas não menciona
  equivalente por teclado.

## Truncamento do Throughput por Etapa ("Outros")

- [x] CHK009 - A regra de truncamento (top-10 nomeadas + "Outros") está
  quantificada com limite numérico exato e comportamento definido nos
  limites (exatamente 10 etapas, 11ª etapa isolada)? [Clareza, Spec
  §FR-006, FR-007, FR-008, Edge Cases] {auto}
  Satisfeito: FR-006/007/008 fixam o número 10 e o comportamento acima/
  abaixo dele; Edge Cases cobre explicitamente o caso-limite "exatamente
  10" e o caso "11ª etapa isolada" — ambos com resultado definido.
- [ ] CHK010 - O mecanismo pelo qual o usuário identifica as etapas
  agregadas em "Outros" (Acceptance Scenario US3.3: "passa o mouse OU
  expande o detalhe") define um único comportamento a implementar, ou
  deixa as duas alternativas em aberto sem decisão? [Ambiguity, Spec §US3
  Cenário 3] {humano}
  O "ou" na redação do cenário não resolve entre tooltip (hover) e
  expansão (click/detail), que têm implicações distintas em mobile/touch
  (hover não existe). Decisão de design a fixar antes da implementação.
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

- [ ] CHK014 - O escopo de suporte a telas menores (mobile/tablet) para o
  dashboard reorganizado é uma premissa assumida (ferramenta interna
  desktop-only) ou um requisito não endereçado no spec.md? [Assumption,
  Gap] {humano}
  O spec.md não menciona breakpoints nem responsividade; dado o contexto
  de ferramenta local single-user (mesma premissa da seção de segurança),
  é plausível que responsividade mobile esteja fora de escopo — mas isso
  não está declarado explicitamente como premissa no artefato de
  requisitos.

## Notes

- Items `{auto}` já vêm resolvidos pelo agente (`[x]` com citação, ou
  marcador `[Gap]`/`[Ambiguity]` quando a evidência aponta lacuna real).
- Items `{humano}` ficam `[ ]` aguardando decisão do dono do produto —
  nenhum bloqueia a implementação atual; são refinamentos de design/
  escopo a fixar antes ou durante `/plan` de detalhamento de UI.
- Marcar items concluídos com `[x]` conforme forem endereçados.
