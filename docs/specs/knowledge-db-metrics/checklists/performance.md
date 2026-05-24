# Performance / Derivabilidade Checklist: Knowledge DB Metrics Ingestion

**Purpose**: Validar a QUALIDADE dos requisitos nao-funcionais desta feature.
Como nao ha endpoint/SLA de latencia (ingestao local, best-effort), o foco
do dominio "performance" desliza para as propriedades NAO-FUNCIONAIS que SAO
load-bearing aqui: derivabilidade/reconstrutibilidade do indice, degradacao
graciosa (best-effort), ordem incremental camada A->B e custo proxy. NAO
valida implementacao — valida clareza/completude/mensurabilidade dos
requisitos.
**Created**: 2026-05-24
**Feature**: [spec.md](../spec.md)

## Derivabilidade / Reconstrutibilidade (propriedade central)

- [ ] CHK001 - FR-001 define "indice puramente derivado" com criterio verificavel — toda entidade nova reconstruivel via `--reindex` a partir de `state.json` + state-history? Existe item que confirma que NENHUM dado primario vive so no indice? [Clareza, Spec §FR-001]
- [ ] CHK002 - SC-002 ("reindex do zero produz o MESMO conjunto que ingestao incremental, 0 divergencias") e mensuravel para Execucao, Onda E SinalDeAlerta? E definido COMO se compara (diff de linhas, hash do dump)? [Mensurabilidade, Spec §SC-002]
- [ ] CHK003 - Os requisitos cobrem a fonte de `--reindex` para entidades de camada B: se Task/Evento dependem de campos gravados no `state.json` corrente, o `state-history` preserva esses campos para reconstrucao identica? [Gap, Spec §FR-001 / §FR-010 / §FR-018]
- [ ] CHK004 - SinalDeAlerta de breach (FR-014) e DERIVADO no momento da ingestao cruzando thresholds com consumo — a spec garante que reindex recalcula o mesmo breach a partir dos mesmos `orcamentos`+consumo (determinismo)? [Consistencia, Spec §FR-014 / §SC-002]

## Degradacao Graciosa (best-effort)

- [ ] CHK005 - FR-003 quantifica "best-effort" de forma testavel: exit 0 + aviso em stderr, sem abortar onda, em 100% dos cenarios de dep ausente (SC-003)? O conjunto de "deps" (sqlite3, jq) e fechado e nomeado? [Mensurabilidade, Spec §FR-003 / §SC-003]
- [ ] CHK006 - Os cenarios de degradacao sao COMPLETOS: sqlite3 ausente, jq ausente, ambos ausentes, state.json corrompido, state.json ausente — cada um tem comportamento especificado (pular vs continuar)? [Cobertura, Spec §Edge Cases / §SC-003]
- [ ] CHK007 - A spec define que uma falha de ingestao de UM `state.json` durante `--reindex` NAO interrompe o processamento dos demais (resiliencia de lote)? [Completude, Spec §Edge Cases]

## Ordem Incremental Camada A -> B (gestao de risco)

- [ ] CHK008 - FR-010 / SC-008 definem criterio OBJETIVO de "camada A concluida e validada antes da camada B" (ex: tasks de US1+US2 com testes verdes antes de qualquer task que toque orquestrador)? [Mensurabilidade, Spec §FR-010 / §SC-008]
- [ ] CHK009 - A spec deixa claro que a camada A (so `recall.sh`) entrega valor isolado mesmo que camada B nunca seja implementada (independencia de fatias)? [Clareza, Spec §User Story 1 / §FR-010]

## Custo / Proxy (FR-021)

- [ ] CHK010 - FR-021 / SC-010 / Clarif Q1 definem de forma inequivoca a decisao de custo: token nao obtenivel (confirmado empiricamente) => `tool_calls` como proxy documentado, SEM inventar valor — e essa decisao esta registrada no artefato da feature como SC-010 exige? [Mensurabilidade, Spec §FR-021 / §SC-010 / §Clarifications Q1]
- [ ] CHK011 - O requisito SHOULD/MUST condicional de FR-021 ("se a harness expoe tokens, SHOULD ingerir") tem criterio de deteccao de disponibilidade definido, evitando ambiguidade futura? [Ambiguity, Spec §FR-021]

## Escala / Volume (limites do indice)

- [ ] CHK012 - A spec considera o crescimento do indice ao ingerir N ondas x M execucoes x K eventos por execucao — existe requisito (ou nao-requisito explicito) sobre limite de volume / retencao do indice derivado? [Gap, Spec §FR-001]
- [ ] CHK013 - Latencia de ingestao por execucao: ha algum requisito implicito de que a ingestao no fim de onda (hook best-effort) nao adicione latencia perceptivel ao orquestrador, e isso e mensuravel? [Gap, Spec §FR-003]

## Notes

- Marcar items concluidos com `[x]`.
- "Performance" reinterpretado para os NFRs reais: derivabilidade, best-effort,
  ordem incremental, proxy de custo, volume. Sem SLA de latencia HTTP (feature
  e ingestao local stateless).
- CHK012/CHK013 sao gaps potenciais de baixo impacto — agregados, candidatos a
  `/clarify` so se o operador do painel precisar de garantia de volume.
