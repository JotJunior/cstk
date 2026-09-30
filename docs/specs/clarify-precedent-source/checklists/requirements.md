# Requirements Checklist: clarify-precedent-source

**Purpose**: Qualidade geral dos requisitos FR-001..FR-018 e SC-001..SC-006
**Created**: 2026-09-30
**Feature**: [spec.md](../spec.md)

> Modo autonomo (feature-00c, onda-006). Gate deterministico
> `requirement-coverage.sh spec.md`: `requirements=18 covered=18 errors=0`.

## Completude

- [x] CHK001 - Ambos os orquestradores (agente-00c e feature-00c) estao no escopo com o mesmo comportamento? [Completude, Spec §FR-001] {auto}
- [x] CHK002 - A elegibilidade de precedente (status respondido, resposta nao vazia, qualquer projeto, qualquer etapa, sem idade maxima) esta definida? [Completude, Spec §FR-002, §FR-013, §FR-014, §FR-016] {auto}
- [x] CHK003 - O comportamento para pergunta sem texto util para busca esta definido? [Edge Case, Spec §Edge Cases; Contract cli-recall-precedents "< 3 tokens distintos"] {auto}
- [x] CHK004 - A entrega documenta as duas metades da instalacao (catalogo x runtime)? [Completude, Spec §FR-017; Plan §Duas metades da instalacao] {auto}

## Clareza

- [x] CHK005 - "Semelhante" esta quantificado (limiar objetivo + julgamento justificado)? [Clareza, Spec §FR-015; Research §Decision 2 = 0.55] {auto}
- [x] CHK006 - "Mais recente" e o desempate por empate de data estao definidos? [Clareza, Spec §FR-006 (empate → nenhum pontua, decisao do operador dec-027)] {auto}
- [x] CHK007 - A divergencia com suporte positivo ausente na opcao do precedente mais recente tem resultado definido (nenhum precedente pontua)? [Clareza, Contract answerer-precedents regra 2 "sujeito ao item 1"] {auto}
- [x] CHK008 - "Precedente mais proximo" (FR-009) tem criterio objetivo? [Clareza, Contract answerer-precedents `recommended_precedent` = maior similaridade] {auto}

## Consistencia

- [x] CHK009 - US1 (reforco) e FR-003/FR-004 sao consistentes apos a alteracao de suporte positivo? [Consistencia, Spec §US1 cenarios 1-3, §FR-003, §FR-004] {auto}
- [x] CHK010 - FR-006, FR-009 e FR-014 sao consistentes sobre recencia afetar so o score e nunca a recomendacao? [Consistencia, Spec §Clarifications "recencia so no score"] {auto}
- [x] CHK011 - O edge case "limite nunca exclui divergente ja identificado" e compativel com o descarte por teto de bytes? [Consistencia, Research §Decision 5 "Divergencia x teto"] {auto}
- [x] CHK012 - Plan, research, contracts e spec citam a mesma decisao para S-1/P-1/P-2? [Consistencia, Plan §Premissas; Research §Decision 8; Spec §Clarifications gate] {auto}

## Criterios de aceite

- [x] CHK013 - SC-001 e mensuravel com os pares identificados e o limiar? [Mensurabilidade, Spec §SC-001; Research §Decision 2 margem 0.177] {auto}
- [x] CHK014 - SC-004 ("saida byte-identica") e verificavel deterministicamente para a parte LLM do answerer? [Ambiguity, Research §Decision 7 "Limite honesto": so o contrato no-op e a omissao do campo sao testaveis de forma gateante] {auto}
- [x] CHK015 - SC-005/SC-006 cobrem recomendacao, divergencia, diretiva embutida e dado factual? [Cobertura, Spec §SC-005, §SC-006] {auto}

## Dependencias e premissas

- [x] CHK016 - Dependencias (sqlite3 opcional confinado, knowledge.db somente leitura) estao declaradas com fallback? [Dependencias, Plan §Technical Context, §Constitution Check II] {auto}
- [x] CHK017 - A sincronizacao da branch com v10.11.0 esta resolvida e fora do backlog? [Dependencias, Plan §Sequencia de implementacao (merge 178c5ac, dec-028)] {auto}
- [ ] CHK018 - O ganho reduzido do precedente sob suporte positivo (reforco/desempate + recomendacao, nao nova decisao automatica) atende a expectativa de valor da feature? [Assumption, Research §Decision 8 "Consequencia declarada"] {humano}

## Notes

- CHK014 (`[Ambiguity]`): nao reabre clarify — o plan ja declara o limite; vai para `/create-tasks` como tarefa de teste que separa a parte gateante (contrato no-op + omissao do campo) da parte eval (saida do answerer).
- CHK014 — separacao gateante x eval (tasks 1.2.x):
  - Gateante (deterministica): (G1) contrato no-op do `--precedents` — exit 0 e stdout vazio em sqlite3 ausente, indice ausente/invalido e pergunta < 3 tokens (Cenarios 5, `precedents_degradation`); (G2) prosa das referencias omite o campo `precedents` quando todas as perguntas tem K=0 (Cenario 7, teste estatico 4.3.2).
  - Nao-gateante (eval): (E1) comparacao da saida do answerer LLM com e sem o campo `precedents` quando K=0 e (E2) comportamento ponta a ponta incluindo o caso "so constitution + precedente" → `scored: false` (Cenarios 8 e 9, task 5.1).
- CHK018 (`{humano}`): informativo, nao bloqueia o backlog.
