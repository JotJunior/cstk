# REQUIREMENTS Checklist: Resumo Deterministico de Fechamento de Onda

**Purpose**: Validar a qualidade dos requisitos de `wave-close-summary` (spec.md
+ plan.md) antes de `/create-tasks` — completude, clareza, consistencia,
mensurabilidade dos criterios de aceite, cobertura de cenarios/edge cases e
ambiguidades residuais.
**Created**: 2026-09-22
**Feature**: [spec.md](../spec.md)

## Completude de Requisitos

- [x] CHK001 - Os 4 modos de execucao (projeto completo/feature individual ×
  primeira invocacao/retomada) estao cobertos pelo requisito que dispara o
  resumo? [Completude, Spec §FR-001] {auto}
- [x] CHK002 - A fonte dos indicadores de volume de trabalho (FR-006) esta
  definida, evitando instrumentacao nova? [Completude, Spec §Clarifications Q1, FR-006] {auto}
- [x] CHK003 - A fonte do indicador de custo/consumo opcional (FR-007) esta
  definida? [Completude, Spec §Clarifications Q2, FR-007] {auto}
- [x] CHK004 - O mecanismo de filtragem de conteudo sensivel esta definido
  (reuso, nao filtro novo)? [Completude, Spec §Clarifications Q3, FR-012] {auto}
- [x] CHK005 - Esta definido se o resumo inclui texto livre cru de
  decisoes/bloqueios? [Completude, Spec §Clarifications Q4, FR-012] {auto}
- [x] CHK006 - Esta definido onde vive a logica de composicao do resumo
  (helper dedicado vs prosa inline por comando)? [Completude, Spec §Clarifications Q5, Key Entities] {auto}
- [x] CHK007 - Existe requisito cobrindo o caso de a onda encerrar por
  execucao concluida (nao so avanco/limite/bloqueio)? [Completude, Spec §FR-003] {auto}
- [ ] CHK008 - A lista minima de indicadores de volume (FR-006: chamadas de
  ferramenta + duracao) e suficiente para o operador avaliar o trabalho da
  onda, ou o apetite do produto pede mais sinais (ex.: skills invocadas,
  gates rodados)? [Completude, Risco] {humano}

## Clareza de Requisitos

- [x] CHK009 - FR-010 define de forma nao-ambigua a distincao entre "nao
  medido" e "medido como zero"? [Clareza, Spec §FR-010, US2 Acceptance Scenarios] {auto}
- [x] CHK010 - O termo "best-effort" (FR-011) e operacionalizado com
  criterio verificavel (nunca impede/atrasa reconciliacao ou agendamento)?
  [Clareza, Spec §FR-011] {auto}
- [x] CHK011 - Os motivos de termino de onda citados em FR-003 tem
  enumeracao fechada e nao-ambigua em algum artefato do design? [Clareza,
  Spec §FR-003; Contract §Rotulos de motivo (mapeamento fechado)] {auto}
- [ ] CHK012 - FR-005 usa a expressao "quando existirem" para a contagem de
  bloqueios pendentes — isso poderia ser lido como "omitir o campo se
  zero", o que colidiria com SC-004 (operador precisa identificar ausencia
  de pendencia so lendo a mensagem)? A redacao do FR em si nao fecha a
  leitura; o contrato de Phase 1 resolve mostrando "Bloqueios pendentes: 0"
  explicitamente, mas a wording da spec permanece ambigua isoladamente.
  [Clareza, Ambiguity, Spec §FR-005 vs Contract §Saida Markdown] {auto}

## Consistencia de Requisitos

- [x] CHK013 - FR-014 (paridade de comportamento entre os dois modos de
  execucao) e consistente com a Key Entity "Resumo de Onda" (helper unico
  reusado pelos dois comandos pai)? [Consistencia, Spec §FR-014, §Key Entities] {auto}
- [x] CHK014 - A garantia de nunca gatear a execucao (FR-011, US3) e
  consistente com a garantia de sempre entregar algo ao operador (FR-013,
  SC-001, que inclui "ou um aviso explicito")? [Consistencia, Spec §FR-011,
  §FR-013, §SC-001] {auto}
- [x] CHK015 - O requisito de nunca expor texto livre cru (FR-012) e
  consistente com o edge case de conteudo potencialmente sensivel embutido
  em decisoes/bloqueios? [Consistencia, Spec §FR-012, §Edge Cases] {auto}

## Qualidade de Criterios de Aceite

- [x] CHK016 - SC-001 e mensuravel objetivamente (100% das mensagens finais
  contendo resumo ou aviso explicito)? [Mensurabilidade, Spec §SC-001] {auto}
- [x] CHK017 - SC-002 e mensuravel e auditavel (nenhum indicador de
  custo/consumo indisponivel aparece como valor numerico, incluindo zero)?
  [Mensurabilidade, Spec §SC-002] {auto}
- [x] CHK018 - SC-003 e mensuravel (falha na composicao nunca atrasa/
  interrompe a onda seguinte, em 100% dos casos observados)? [Mensurabilidade,
  Spec §SC-003] {auto}
- [x] CHK019 - SC-004 e verificavel sem ferramentas adicionais (operador le
  so a mensagem final para saber se ha pendencia)? [Mensurabilidade, Spec
  §SC-004] {auto}

## Cobertura de Cenarios

- [x] CHK020 - Os 3 motivos de termino de maior interesse operacional
  (avanco normal, limite operacional, bloqueio humano) tem cada um pelo
  menos um Acceptance Scenario dedicado na User Story 1? [Cobertura, Spec
  §US1 Acceptance Scenarios 1-3] {auto}
- [x] CHK021 - O caso "metrica opcional indisponivel" e o caso "metrica
  opcional disponivel e igual a zero" tem cenarios distintos e comparaveis?
  [Cobertura, Spec §US2 Acceptance Scenarios 1-2] {auto}
- [x] CHK022 - O gate deterministico de cobertura FR→cenario
  (requirement-coverage.sh) confirma que todos os FRs tem pelo menos um
  cenario associado? [Cobertura, Gate requirement-coverage.sh: requirements=14 covered=14 errors=0] {auto}

## Cobertura de Edge Cases

- [x] CHK023 - O caso de primeira onda (sem onda anterior para comparar)
  esta coberto? [Edge Case, Spec §Edge Cases item 1] {auto}
- [x] CHK024 - O caso de zero decisoes auditaveis na onda (onda curta/abortada
  cedo) esta coberto, distinguindo "zero legivel" de erro? [Edge Case, Spec
  §Edge Cases item 2] {auto}
- [x] CHK025 - O caso de dois modos de execucao (projeto vs feature) exigindo
  comportamento identico sem o operador precisar saber qual modo esta em uso
  esta coberto? [Edge Case, Spec §Edge Cases item 4] {auto}
- [x] CHK026 - O caso de distincao entre motivo que exige atencao imediata
  (bloqueio humano) e motivo que so pausa ate a proxima janela agendada
  (limite operacional) esta coberto, evitando tratar ambos como "pausado"?
  [Edge Case, Spec §Edge Cases item 5] {auto}

## Requisitos Nao-Funcionais

- [x] CHK027 - Ha requisito de robustez/degradacao graciosa explicito para
  falha na composicao do resumo (nao trava a pipeline)? [NFR, Spec §FR-011,
  §US3] {auto}
- [x] CHK028 - Ha requisito de protecao de dados sensiveis (nao vazar
  segredo/config embutido em texto livre)? [NFR, Spec §FR-012, §Edge Cases
  item 3] {auto}
- [ ] CHK029 - Ha requisito explicito de orcamento de latencia da composicao
  do resumo na spec (nao so no plan)? A spec nao enumera um teto de tempo;
  o teto de performance (< 2s) e definido apenas em plan.md §Technical
  Context, fora do escopo formal de FRs/SC. [NFR, Gap, Spec §Requirements
  vs Plan §Technical Context] {auto}

## Dependencias e Premissas

- [x] CHK030 - A dependencia do mecanismo OTel/`wave_model_usage` existente
  para custo/consumo esta declarada como premissa (sem introduzir medicao
  nova)? [Dependencias, Spec §FR-007, §Clarifications Q2] {auto}
- [x] CHK031 - A dependencia do mecanismo existente de metricas por onda
  (chamadas de ferramenta/duracao) esta declarada, sem introduzir
  instrumentacao nova? [Dependencias, Spec §FR-006, §Clarifications Q1] {auto}

## Ambiguidades e Conflitos

- [ ] CHK032 - O comportamento esperado quando `termination_reason` assume
  um valor fora do enum conhecido (nem `etapa_concluida_avancando`, nem
  `threshold_proxy_atingido`, nem `bloqueio_humano`, nem `aborto`, nem
  `concluido`) esta definido na spec, ou so no contrato de design? A spec
  usa "por exemplo" (lista aberta) em FR-003; o comportamento para enum
  desconhecido (exibir valor cru, sem inventar rotulo) so aparece em
  contracts/wave-summary-cli.md, nao no proprio FR. [Ambiguity, Spec §FR-003
  vs Contract §Rotulos de motivo] {auto}

## Notes

- Items `{auto}` ja vem resolvidos pelo agente (`[x]` com citacao, ou
  marcador `[Gap]`/`[Ambiguity]`).
- Items `{humano}` ficam `[ ]` aguardando decisao do dono do produto.
- Gate deterministico `requirement-coverage.sh` rodou sobre `spec.md`:
  `requirements=14 covered=14 errors=0` (exit 0) — nenhum FR sem cenario
  associado; nenhum item `[Gap]` adicional exigido pela secao 4.2.1 da
  skill.
- CHK029 e CHK032 sao gaps de fronteira spec-vs-design (Principio I SDD
  recursivo: spec define O QUE, plan/contract define COMO) — nao bloqueiam
  o pipeline, mas ficam registrados para quem revisar a rastreabilidade
  formal FR→SC.
