# Requirements Checklist: Ranking Composto no cstk recall

**Purpose**: Validar a qualidade (completude, clareza, consistencia,
mensurabilidade, cobertura de cenarios e rastreabilidade) dos requisitos de
`spec.md` antes de decompor em backlog — nao valida a implementacao.
**Created**: 2026-08-20
**Feature**: [spec.md](../spec.md)

## Completude

- [x] CHK001 - Todos os Functional Requirements tem pelo menos um Acceptance Scenario ou Edge Case associado? [Completude, gate `requirement-coverage.sh`] {auto} — gate rodou sobre `spec.md`: `RESULT|docs/specs/recall-ranking/spec.md|requirements=12|covered=12|errors=0`, exit 0, zero FINDING.
- [x] CHK002 - Requisitos nao-funcionais centrais da feature (compatibilidade retroativa, determinismo) estao documentados como FR proprios? [Completude, Spec §FR-007, §FR-009] {auto} — FR-007 ("funcionar imediatamente ... sem exigir reindexacao") e FR-009 ("ordem MUST ser deterministica") sao FRs dedicados, nao notas soltas.
- [x] CHK003 - Exclusoes explicitas de escopo estao documentadas (o que a feature NAO faz)? [Completude, Spec §Edge Cases + §FR-011/FR-012] {auto} — Edge Cases lista RRF/grafo como fora de escopo (deferido a `recall-hybrid-rrf`); FR-011 e FR-012 sao MUST NOT dedicados (RRF/grafo e exposicao via MCP).
- [x] CHK004 - Premissas de infraestrutura (dependencias novas, migracao, scheduling) estao declaradas mesmo quando o resultado e "nenhuma"? [Completude, Spec §Requirements] {auto} — nota explicita apos FR-012: "Decisoes de infraestrutura: N/A (feature e computacao stateless sobre um indice ja existente; nao introduz scheduling, rotacao de chaves, refresh de token externo, lock cross-processo ou backup/restore novos)".

## Clareza

- [x] CHK005 - O termo "relevancia textual comparavel" (usado em FR-001/FR-003) e tratado com a camada correta de abstracao — spec define o QUE, plano define o QUANTO? [Clareza, Spec §FR-001/FR-003; Plan §Summary] {auto} — spec.md nao quantifica "comparavel" (correto para uma spec funcional); `plan.md` fecha a lacuna com calibracao medida (spread de autoridade 0.30, teto de recencia 0.10, research.md M3/D4) — separacao WHAT/HOW preservada, nao e ambiguidade nao-resolvida.
- [x] CHK006 - FR-008 ("sinal de recencia mais baixo possivel") tem valor concreto definido em algum artefato do conjunto (spec+plan), mesmo que nao no proprio texto do FR? [Clareza, Spec §FR-008; Plan §Summary] {auto} — `data-model.md` e `plan.md` definem o valor concreto (bonus de recencia = 0.0 no limite inferior do intervalo `[0, 0.10]`); a spec abstrai corretamente o numero, delegando ao plano.
- [x] CHK007 - Marcacoes `[NEEDS CLARIFICATION]` ou placeholders (TODO/TKTK) foram todos resolvidos no `spec.md`? [Clareza] {auto} — `grep -c 'NEEDS CLARIFICATION\|TODO\|TKTK' spec.md` = 0; a unica sessao de Clarifications (Q sobre tier de `memory`) esta resolvida com resposta registrada (dec-012) e refletida em FR-010.

## Consistencia

- [x] CHK008 - A hierarquia de autoridade por tipo (decisao/bloqueio > memoria > retro/skill) e consistente entre FR-001, FR-010 e a User Story 1? [Consistencia, Spec §FR-001/§FR-010/§US1] {auto} — FR-001 estabelece decisao/bloqueio > retro/skill; FR-010 insere `memory` no tier intermediario entre os dois; US1 so testa o extremo (decisao vs skill, bloqueio vs retro) sem contradizer o tier de `memory` — as tres fontes descrevem a MESMA hierarquia de 3 niveis.
- [x] CHK009 - A terminologia de tipos de achado (decisao, bloqueio, retrospectiva, skill, memoria) e usada de forma identica entre `Key Entities` e os FRs? [Consistencia] {auto} — os 5 tipos citados em "Resultado de Busca" (Key Entities) sao exatamente os mesmos 5 tipos referenciados em FR-001/FR-010, sem sinonimo divergente (ex: nunca "nota" no lugar de "memoria").
- [x] CHK010 - Os requisitos respeitam os principios MUST da constitution do projeto (VI - veracidade de dados; II - POSIX sh puro)? [Constitution Alignment] {auto} — `plan.md` §Constitution Check registra PASS explicito nos 4 principios MUST aplicaveis (I, II, IV, VI), com evidencia por principio (ex: VI — "toda calibracao vem de medicao reproduzivel... nenhum peso foi arbitrado").

## Mensurabilidade

- [x] CHK011 - SC-001 e SC-003 definem threshold percentual objetivamente verificavel por teste? [Mensurabilidade, Spec §SC-001/§SC-003] {auto} — SC-001: "em pelo menos 95% dos cenarios de teste com relevancia comparavel"; SC-003: "pelo menos 90% dos cenarios de teste" — ambos com denominador e limiar explicitos.
- [x] CHK012 - SC-002 e SC-006 (nao-regressao) definem o criterio de "o que conta como regressao" sem depender de julgamento subjetivo? [Mensurabilidade, Spec §SC-002/§SC-006] {auto} — SC-002 amarra a "suite de regressao do contrato existente" passando "sem alteracao nas asercoes de formato"; SC-006 amarra a "suite de testes existente" passando "sem exigir mudanca de comportamento fora das asercoes que tratam especificamente de ordem de resultados" — ambos apontam para um artefato de teste concreto, nao para opiniao.
- [x] CHK013 - SC-004 (100% dos resultados com `--explain` exibem componentes) e verificavel automaticamente sem inspecao manual? [Mensurabilidade, Spec §SC-004] {auto} — criterio e "exibem visivelmente o detalhamento dos componentes" por resultado retornado, testavel via contagem de linhas de explicacao == contagem de resultados (mesmo padrao do Acceptance Scenario 1 da US3).
- [x] CHK014 - SC-005 (zero passos manuais de migracao) tem um teste que a diferencie de "funciona so apos reindex manual"? [Mensurabilidade, Spec §SC-005; Plan §Summary] {auto} — FR-007 exige funcionamento imediato "sobre os dados ja indexados hoje"; `plan.md` §Summary reforca "sem coluna nova, sem migracao e sem reindex" — o teste natural e rodar a busca sobre o indice de producao existente sem nenhum comando extra antes.

## Cobertura de Cenarios

- [x] CHK015 - Cada uma das 3 user stories tem pelo menos um Acceptance Scenario no formato Given/When/Then? [Cobertura] {auto} — US1: 2 cenarios; US2: 2 cenarios; US3: 2 cenarios — todas cobertas.
- [x] CHK016 - O caso de achado legado sem sinal de recencia (pre-rastreio de data) esta coberto tanto no Edge Case quanto em um Acceptance Scenario formal? [Cobertura, Spec §Edge Cases + §US2 AS2] {auto} — coberto duas vezes: Edge Cases ("indexado antes do rastreio de data existir... nunca excluido, nunca erro") e US2 Acceptance Scenario 2 (mesmo caso, formalizado Given/When/Then).
- [x] CHK017 - O caso de empate total (mesma relevancia, tipo e data) tem comportamento definido e testavel (determinismo)? [Cobertura, Spec §Edge Cases; FR-009] {auto} — Edge Cases: "a ordem entre esses resultados deve ser deterministica e reproduzivel entre execucoes identicas (FR-009)" — FR-009 e a fonte normativa citada diretamente no proprio edge case.
- [x] CHK018 - A interacao entre a flag de explicacao (US3) e o modo `--context` (consumido por sistema, nao humano) esta explicitamente resolvida? [Cobertura, Spec §Edge Cases] {auto} — Edge Cases resolve o caso: "a explicacao e uma capacidade de busca interativa; o modo `--context` preserva seu formato... inalterados (FR-004) — a explicacao nao se aplica a esse modo".

## Edge Cases

- [x] CHK019 - O comportamento para achado sem sinal de recencia utilizavel esta definido sem excluir o achado nem causar erro? [Edge Case, Spec §FR-008] {auto} — FR-008 e explicito: "MUST continuar sendo retornados e ranqueados — nunca excluidos nem causando erro — recebendo o sinal de recencia mais baixo possivel".
- [ ] CHK020 - Existe um requisito ou edge case, no proprio `spec.md`, que bound o efeito de um `source_ts` anomalo (ex: timestamp futuro por clock skew) sobre o bonus de recencia? [Edge Case, Gap] {auto} — **[Gap]**: nao ha FR nem Edge Case em `spec.md` cobrindo esse caso; o tratamento (clamp `max(0.0, ...)`) so aparece em `plan.md` §Riscos ("F2, HIGH... sem ele, `-89.99d` produz bonus `~900` e fixa o achado em 1o lugar em qualquer consulta") e no `contracts/cstk-recall-ranking.md`. E um comportamento ja MITIGADO tecnicamente (nao e um requisito faltante que bloqueie a implementacao), mas fica como requisito implicito-apenas-no-plano em vez de explicito na spec — destino: `/create-tasks` pode registrar a tarefa de teste do clamp citando o FR-009 (determinismo) como base normativa, ou aceitar como decisao de camada (spec=comportamento observavel, plano=garantia de robustez) sem mudanca de artefato.

## Dependencias e Premissas

- [x] CHK021 - A dependencia existente (`sqlite3`) e seu comportamento de fallback em ausencia estao documentados nos requisitos e/ou plano tecnico? [Completude, Plan §Technical Context/§Constraints] {auto} — Plan §Technical Context declara a versao minima medida e "dependencia existente, nenhuma nova"; §Constraints reforca "degradacao graciosa e invariante: todo caminho de falha de infraestrutura retorna `exit 0` com aviso" — coerente com FR-007/FR-008 (nunca erro).
- [x] CHK022 - A premissa de que o indice ja contem os campos necessarios ao ranking (`type`, `source_ts`) esta validada contra o schema real, nao apenas assumida? [Premissa, Plan §Technical Context; data-model.md] {auto} — `data-model.md` §"Estrutura existente consumida" cita o schema real; `plan.md` §Scale/Scope reporta contagem medida por tipo no indice de producao (8699 linhas, breakdown por tipo) — validacao empirica, nao suposicao.

## Rastreabilidade

- [x] CHK023 - Cada user story se liga a pelo menos um FR correspondente? [Traceability] {auto} — US1 -> FR-001/FR-002/FR-010; US2 -> FR-003/FR-008/FR-009; US3 -> FR-005/FR-006.
- [x] CHK024 - Cada Success Criterion se liga a pelo menos um FR que o sustenta? [Traceability] {auto} — SC-001->FR-001; SC-002->FR-004; SC-003->FR-003; SC-004->FR-005; SC-005->FR-007; SC-006->FR-006/FR-011/FR-012 (nao-regressao de escopo).

## Ambiguidades e Conflitos

- [x] CHK025 - A pergunta de clarificacao registrada (tier de `memory`) foi de fato resolvida com uma escolha registrada, e nao apenas levantada? [Ambiguity, Spec §Clarifications] {auto} — a sessao de 2026-08-20 registra pergunta, as 3 opcoes A/B/C e a resposta escolhida ("C — tier intermediario proprio", dec-012), refletida em FR-010. Nenhuma ambiguidade aberta remanescente.

## Decisoes de Risco/Negocio (dono do produto)

- [ ] CHK026 - A calibracao de pesos do plano (spread de autoridade 0.30; teto de recencia 0.10) reflete o apetite de risco do produto para promover `memory` acima de `retro`/`skill`? [Risco, Plan §Summary] {humano}
- [ ] CHK027 - O risco aceito F6 do plano (bonus de autoridade podendo amplificar memory poisoning via `type=memory` forjavel, severidade MEDIUM) e aceitavel para esta feature sem mitigacao adicional de proveniencia? [Risco, Plan §Riscos F6] {humano}
- [ ] CHK028 - A ordem de prioridade P1/P2/P3 entre as 3 user stories reflete corretamente a sequencia de valor desejada para entrega incremental? [Priorizacao] {humano}

## Notes

- Items `{auto}` ja vem resolvidos pelo agente (`[x]` com citacao, ou marcador `[Gap]`).
- Items `{humano}` ficam `[ ]` aguardando decisao do dono do produto.
- Rastreabilidade: 27/28 items citam `[Spec §X]`/`[Plan §X]`/marcador — 96% (acima do minimo de 80%).

### Resolucao

- **{auto} resolvidos**: 24 (`[x]` com evidencia citada)
- **{humano} aguardando decisao**: 3 (CHK026, CHK027, CHK028)
- **Gaps abertos**: 1 (CHK020 — `[Gap]`)

### Proximos Passos

- CHK026/CHK027/CHK028 — decisao do dono do produto antes de `/execute-task` (ou aceitar tacitamente via ratificacao do plano, ja que F6/pesos ja foram objeto de gate de seguranca no plan e o risco foi formalmente aceito la).
- CHK020 (`[Gap]`) — `/create-tasks` pode registrar como tarefa de teste do clamp de recencia (ja mitigado no plano/contrato; apenas nao explicito como FR/Edge Case da spec).
- `/create-tasks` — decompor este plano em backlog executavel.
