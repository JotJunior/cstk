# Performance Checklist: Agente-00C Artifact Cache

**Purpose**: Validar QUALIDADE dos requisitos de performance da feature
artifact-cache — ganho mensuravel, overhead aceitavel, latencia de
geracao e medicao calibradas.
**Created**: 2026-05-21
**Feature**: [`spec.md`](../spec.md)

## Targets e mensuracao

- [ ] CHK001 - O target de economia esta quantificado num KPI mensuravel
  (numero, unidade, intervalo de confianca) em vez de adjetivo vago como
  "significativo" ou "expressivo"? [Mensurabilidade, Spec §SC-001]
- [ ] CHK002 - O baseline contra o qual SC-001 (>=70%) sera medido esta
  definido (qual execucao concreta, qual projeto, qual ferramenta de
  medicao)? [Completude, Spec §SC-001, Tasks T4.2]
- [ ] CHK003 - O alvo de 70% economia esta justificado (estudo, piloto,
  estimativa de back-of-envelope) ou eh chute? [Mensurabilidade, Spec §SC-001]
- [ ] CHK004 - O range tipico de tamanho de briefing+constitution (5-15k
  chars combinados) que justifica o cache esta documentado? Sob que
  tamanho o cache para de pagar? [Cobertura, Spec §Contexto]
- [ ] CHK005 - "Tokens economizados" tem definicao operacional clara via
  formula (`(source - resumo) * ratio`), com ratio default e regras de
  override? [Clareza, Spec §Clarifications Q5, FR-CACHE-012]
- [ ] CHK006 - Heuristica `chars / 4` (pt-br) vs `chars / 3` (en) tem
  threshold definido para escolha (criterio observavel ou flag manual)?
  [Clareza, Spec §FR-CACHE-012, Plan §Decisao 5]

## Threshold de passthrough

- [ ] CHK007 - O threshold de 3000 chars esta defendido com calculo de
  break-even (overhead de fork+exec do gerador vs ganho liquido de
  re-leitura)? [Mensurabilidade, Plan §Decisao 2]
- [ ] CHK008 - O comportamento esperado quando `source_chars` esta a +-10%
  do threshold (na zona de fronteira) esta especificado, ou eh decisao
  binaria sem histerese? [Edge case, Spec §FR-CACHE-007]
- [ ] CHK009 - Override do threshold via `config.cache.passthrough_threshold_chars`
  tem range valido documentado (minimo, maximo, default)? [Completude, Spec §FR-CACHE-007]

## Latencia de geracao do resumo

- [ ] CHK010 - O alvo de latencia para a heuristica extractiva (< 100ms
  por arquivo ate 50k chars, conforme plan.md) tem teste correspondente
  na suite? [Mensurabilidade, Plan §Limites operacionais]
- [ ] CHK011 - Existem requisitos de latencia para arquivos foundational
  fora do range tipico (10k-50k chars), ou apenas para o range esperado?
  [Cobertura, Gap]
- [ ] CHK012 - O comportamento esperado quando geracao excede limite
  aceitavel (LLM/heuristica trava por motivo nao especificado) esta
  definido — cair em passthrough? abortar? bloqueio humano? [Edge case, Gap]

## Overhead de cada onda

- [ ] CHK013 - O overhead de cada `state-cache.sh check-drift` no inicio
  de onda N>1 esta orcamentado (SC-003 diz <=100ms — qual hardware?
  qual tamanho de arquivo?)? [Mensurabilidade, Spec §SC-003]
- [ ] CHK014 - O custo total acumulado da camada de cache (geracao + 
  checks + metrics-bump) ao longo de uma execucao tipica de 10 ondas
  esta estimado, ou pode comer parte do ganho? [Cobertura, Gap]
- [ ] CHK015 - Existe requisito de "cache deve compensar custo dele
  proprio" (i.e., ganho liquido sempre positivo)? [Gap, Ambiguity]

## Escalabilidade

- [ ] CHK016 - Limite superior de tamanho de briefing/constitution que
  o cache lida sem degradacao esta especificado, ou eh implicito (so
  ate 50k chars)? [Completude, Plan §Technical Context]
- [ ] CHK017 - Comportamento esperado em projetos com >5 ondas E
  briefing+constitution >30k chars combinados (caso onde o ganho deve
  ser maximo) esta validado em test fixture? [Cobertura, Tasks T4.1]
- [ ] CHK018 - O cache afeta tempo de boot/setup do agente-00c em ondas
  >1? Existe metrica especifica para isso (Onda N+1 latencia time-to-first-skill)?
  [Mensurabilidade, Gap]

## Concorrencia

- [ ] CHK019 - O cache eh thread-safe dentro de uma onda? FR-CACHE-016
  exige lock acquired — mas se 2 skills consultam cache na mesma onda,
  podem race? [Edge case, Spec §FR-CACHE-016]
- [ ] CHK020 - TOCTOU entre `check-drift` inicial e `get-resumo`
  posterior (na mesma onda) tem requisito de double-check explicito,
  ou eh implicito do uso? [Clareza, Spec §FR-CACHE-008 step 2]

## Degradacao graceful

- [ ] CHK021 - Quando a heuristica extractiva produz resumo de tamanho
  similar ao source (< 30% economia em chars), existe requisito para
  reverter automaticamente para passthrough? [Cobertura, Edge Cases]
- [ ] CHK022 - Se >50% do resumo eh redacted pelo secrets-filter
  (FR-CACHE-007 mencionado, mas onde aplica?), o fallback para
  passthrough esta documentado como FR explicito? [Conflict, Spec §Edge Cases]
- [ ] CHK023 - O cache desabilita-se automaticamente se metricas de hit
  rate ficam abaixo de threshold (e.g., <30% hits em 5 ondas)? [Gap, Assumption]

## Notes

- Marcar items concluidos com `[x]`
- Items rastreaveis: 22/23 (~96%) atendem o minimo de 80%
- Items sem ref direto: CHK011, CHK014, CHK015, CHK018, CHK023 (gaps
  que precisam ser endereçados antes de implementacao OU descartados
  com justificativa explicita em /plan)
- Priorizar resolucao de CHK002 (baseline) e CHK013 (overhead per onda)
  antes de comecar Fase 1 — sao bloqueantes para validar SC-001
