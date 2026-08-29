# Requirements Checklist: Decision Map Panel

**Purpose**: Validar qualidade geral dos requisitos — completude, clareza, mensurabilidade, consistência, cobertura de cenários e rastreabilidade — para a feature `decision-map-panel`.
**Created**: 2026-05-29
**Feature**: [spec.md](../spec.md)

> Items `{auto}` foram resolvidos pelo agente contra spec.md, plan.md e data-model.md.
> Items `{humano}` aguardam decisão do dono do produto.
> `[Gap]` = requisito ausente; `[Ambiguity]` = ambiguidade; `[Conflict]` = inconsistência.

---

## Completude de Requisitos Funcionais

- [x] CHK036 - Cada User Story possui critérios de aceite com cenários Given/When/Then específicos? [Completude, Spec §US1, US2, US3, US4] {auto}
  > spec §US1–US4: todas as 4 user stories têm cenários GWT. US1: 4 cenários; US2: 4 cenários; US3: 3 cenários; US4: 3 cenários. Completo.

- [x] CHK037 - Cada requisito funcional (FR-001 a FR-013) tem rastreabilidade para pelo menos uma User Story ou Success Criteria? [Completude, Spec §Requirements] {auto}
  > FR-001→US1 SC1; FR-002→US1; FR-003→US3 SC1; FR-004→US3 SC1; FR-005→US4; FR-006→US2; FR-007→US2 SC4; FR-008→US1 SC3; FR-009→Edge Cases; FR-010→SC-006; FR-011→SC-007; FR-012→Edge Cases; FR-013→FeatureDetail. Rastreabilidade presente.

- [x] CHK038 - Todos os 7 Success Criteria são mensuráveis e verificáveis objetivamente (sem adjetivos vagos)? [Mensurabilidade, Spec §Success Criteria] {auto}
  > SC-001: "100% das execuções com ao menos uma decisão" ✓; SC-002: "< 2 segundos, < 20 decisões, conexão local" ✓; SC-003: "< 200ms" ✓; SC-004: "100% dos casos, teste automatizado" ✓; SC-005: "mock de API" ✓; SC-006: "exclusivamente via teclado" ✓; SC-007: "verificável por diff" ✓. Todos mensuráveis.

- [x] CHK039 - Os requisitos cobrem todos os atores identificados (engenheiro que monitora execução)? [Completude, Spec §US1] {auto}
  > spec §US1: "engenheiro que acompanha uma execução autônoma". US2: mesma persona. Único ator, coberto.

- [ ] CHK040 - São os requisitos de performance para o algoritmo de layout (computeLayout) definidos — tempo máximo de execução para N=100 decisões? [Completude, Spec §SC-002] [Gap]
  > spec §SC-002 define < 2s para renderização total, mas não isola o tempo do `computeLayout` (JS puro). Com 100 nós e cálculo de posições, um budget separado para o engine seria rastreável. `[Gap]` (baixa prioridade — JS layout é instantâneo na prática).

---

## Clareza e Especificidade

- [x] CHK041 - O termo "mapa de decisões" está definido sem ambiguidade — o que é um "nó", o que é uma "aresta", qual é a relação semântica? [Clareza, Spec §Key Entities] {auto}
  > spec §Key Entities define: "Nó do mapa", "Aresta", "Painel lateral de detalhe". Relação semântica: sequência de ocorrência. Definido.

- [x] CHK042 - O escopo vs. a skill `decision-tree` está documentado para evitar reimplementação inadvertida? [Clareza, Spec §Nota de escopo] {auto}
  > spec §Nota de escopo (topo): distinção explícita entre skill `decision-tree` (state.json, offline) e esta feature (knowledge.db via API, ao vivo). Documentado.

- [x] CHK043 - "Sem travar o navegador" (SC-002, FR-012) está quantificado com um critério verificável? [Clareza, Spec §SC-002] {auto}
  > SC-002: "< 2 segundos em conexão local, sem travamentos perceptíveis". Critério quantificado. FR-012 referencia `limit` do hook. Aceitável.

- [ ] CHK044 - O termo "progressivamente" (Edge Cases: "carregar progressivamente ou paginado") é definido com um mecanismo concreto — virtual scroll, paginação de nós, ou lazy load? [Clareza, Spec §Edge Cases] [Ambiguity]
  > spec §Edge Cases usa "progressivamente ou paginado" como alternativas abertas. plan §Estados define `pagination.hasMore` com banner de aviso, o que sugere paginação por `limit=100` como solução escolhida. Mas "progressivamente" não é explicitamente descartado. `[Ambiguity]` (baixa — plan já decide, mas spec fica inconsistente).

- [x] CHK045 - Os campos UNTRUSTED estão explicitamente listados nos requisitos (não apenas no data model)? [Clareza, Spec §FR-007] {auto}
  > spec §FR-007: lista explícita: `contexto`, `justificativa`, `evidência`, `escolha`, `agente`. data-model.md confirma com marcação UNTRUSTED em cada campo. Definido.

---

## Consistência de Requisitos

- [x] CHK046 - FR-002 (SVG manual, sem deps externas) é consistente com o research.md que descartou bibliotecas de grafo? [Consistência, Spec §FR-002, Plan §Technical Context] {auto}
  > plan §Technical Context: "Deps de grafo: Nenhuma — SVG manual (Research D1)". research.md referenciado. Consistente.

- [x] CHK047 - FR-011 (zero endpoints novos) é consistente com o plano de implementação que não modifica o backend? [Consistência, Spec §FR-011, Plan §Technical Context] {auto}
  > plan §Technical Context: "Backend (modificações): Nenhuma — endpoint GET /decisions já existe". SC-007: "verificável por diff". Consistente.

- [x] CHK048 - A chave sintética `${wave}::${index}` para identificação de nós é usada consistentemente em todos os artefatos (spec, plan, data-model)? [Consistência, Spec §FR-005] {auto}
  > spec §FR-005 e §Clarificações: chave `${wave}::${index}`. plan §Arquitetura: `n.key`. data-model §Entity MapNode: `key = "${wave}::${index}"`. Consistente nos três artefatos.

- [ ] CHK049 - O estado `mapVisible` é gerenciado em `DecisionMapPanel` ou em `ExecutionDetail` — a spec e o plan são consistentes sobre o dono deste estado? [Consistência, Spec §FR-001, Plan §Modificação em ExecutionDetail] [Conflict]
  > plan §Arquitetura §DecisionMapPanel: "state: mapVisible, selectedKey" (sugere no componente). plan §Modificação em ExecutionDetail: "Estado `mapVisible`: `useState(false)` em `ExecutionDetail` (ou delegado ao componente)". Duas opções abertas sem resolução explícita. `[Conflict]` (baixa — ambas funcionam, mas cria inconsistência de rastreabilidade).

- [x] CHK050 - FR-013 (botão disabled em FeatureDetail) é consistente com US1 que foca exclusivamente em ExecutionDetail? [Consistência, Spec §FR-013, US1] {auto}
  > spec §FR-013: "botão na tela `FeatureDetail` DEVE permanecer desabilitado". US1: foca em "tela de detalhe da execução". Consistente — esclarece que FeatureDetail não é escopo.

---

## Cobertura de Cenários

- [x] CHK051 - O cenário de erro de API está coberto nos requisitos com comportamento definido? [Cobertura, Spec §US1 SC3, FR-008] {auto}
  > spec §US1 SC3: "o mapa exibe estado de erro com possibilidade de retry, sem travar a tela principal". FR-008 inclui estado de erro. Coberto.

- [x] CHK052 - O cenário de execução sem decisões (count=0) está coberto com estado vazio definido? [Cobertura, Spec §US1 SC2, FR-008] {auto}
  > spec §US1 SC2: "mapa exibe estado vazio com mensagem explicativa ('Nenhuma decisão registrada para esta execução.')". Coberto com mensagem específica.

- [x] CHK053 - O cenário de dados parciais (meta.degraded) está coberto nos requisitos? [Cobertura, Spec §FR-008] {auto}
  > spec §FR-008 e plan §Estados: "degradado (dados parciais com `meta.degraded=true`): Banner degradado + mapa parcial". Coberto.

- [ ] CHK054 - O cenário de retry após erro de API está especificado — o que "possibilidade de retry" (US1 SC3) significa concretamente (botão, auto-retry, link)? [Clareza, Spec §US1 SC3] [Ambiguity]
  > spec §US1 SC3 menciona "possibilidade de retry" sem definir o mecanismo. É um botão "Tentar novamente"? É o padrão de retry do `useDecisions`? `[Ambiguity]`

- [ ] CHK055 - O cenário de troca de execução com mapa aberto (navegação SPA sem reload) está especificado — o mapa fecha automaticamente? [Cobertura, Spec §Edge Cases] [Gap]
  > spec §Edge Cases: "ao retornar" sugere navegação de ida e volta, mas não cobre o caso de troca de execução direta (ex: breadcrumb → outra execução) sem reload. plan §Modificação cita "Reset ao trocar de aba ou de execução" — mas a spec não especifica o gatilho de reset. `[Gap]`

---

## Dependências e Premissas

- [x] CHK056 - As dependências do endpoint existente (`GET /api/v1/executions/:id/decisions`) estão documentadas — versão da API, contrato de paginação? [Completude, Spec §FR-002, Plan §Technical Context] {auto}
  > plan §Convencoes de Borda: endpoint documentado; §Technical Context: `pagination.ts`. data-model §Restrições confirma `limit=100`. Documentado.

- [x] CHK057 - A dependência do componente `<TextRaw>` e `<ScoreChip>` (reutilização do design system existente) está documentada como premissa? [Completude, Plan §DecisionMapNode, §DecisionDetailPane] {auto}
  > plan §DecisionMapNode: `<TextRaw maxLength={40}>`, `<ScoreChip score={decision.score} />`. plan §DecisionDetailPane: padrão do `DecisionsPanel` existente. Reutilização documentada.

- [x] CHK058 - A dependência do hook `useDecisions` (existente) está documentada como premissa, incluindo o parâmetro `wave?`? [Completude, Plan §DecisionMapPanel] {auto}
  > plan §DecisionMapPanel: `useDecisions(execucaoId, { limit: 100, wave?: waveFilter })`. Dependência documentada com assinatura.

- [ ] CHK059 - A premissa de que `useDecisions` retorna os itens já ordenados por wave + posição está documentada explicitamente? [Completude, Spec §FR-005, DataModel §Fluxo] {auto}
  > spec §FR-005: "array flat ordenado carregado pelo hook `useDecisions`". Mas não está claro se a API retorna ordenado ou se o hook precisa ordenar. Se a API retornar em ordem diferente, a chave `${wave}::${index}` seria instável. [Gap]

- [ ] CHK060 - A premissa de compatibilidade com modo claro (feature `tema-claro-menu-retratil` recém implementada) está documentada para os novos componentes? [Completude, Plan §Technical Context] [Gap]
  > plan §Technical Context menciona "tokens.css + prototype.css (dark-mode-first)" mas não referencia explicitamente a feature tema-claro já implementada. Os novos componentes precisarão funcionar em ambos os modos. `[Gap]`

---

## Notes

- Items `{auto}` foram resolvidos pelo agente com evidência citada da spec/plan/data-model
- Items `{humano}` aguardando decisão: 0
- Gaps abertos (`[Gap]`): CHK040, CHK055, CHK059, CHK060
- Ambiguidades (`[Ambiguity]`): CHK044, CHK054
- Conflitos (`[Conflict]`): CHK049

### Resolução

- **{auto} resolvidos**: 18 (`[x]`)
- **{humano} aguardando decisão**: 0
- **Gaps abertos** (`[Gap]`): 4
- **Ambiguidades** (`[Ambiguity]`): 2
- **Conflitos** (`[Conflict]`): 1

### Próximos Passos

- `/clarify` — resolver CHK044 (mecanismo de scroll/paginação), CHK054 (retry UI), CHK049 (dono de mapVisible)
- `/create-tasks` — CHK040, CHK055, CHK059, CHK060 viram tarefas ou refinamentos de spec
