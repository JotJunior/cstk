# UX Checklist: Decision Map Panel

**Purpose**: Validar qualidade dos requisitos de experiência do usuário — hierarquia visual, estados de interação, acessibilidade, feedback e edge cases de UI — para a feature `decision-map-panel`.
**Created**: 2026-05-29
**Feature**: [spec.md](../spec.md)

> Items `{auto}` foram resolvidos pelo agente contra spec.md, plan.md e data-model.md.
> Items `{humano}` aguardam decisão do dono do produto.
> `[Gap]` = requisito ausente na spec; `[Ambiguity]` = ambiguidade identificada.

---

## Hierarquia Visual e Layout

- [x] CHK001 - São os requisitos de layout do mapa (proporção mapa/painel, comportamento ao fechar painel) definidos para o estado principal? [Completude, Spec §FR-006, Clarificações] {auto}
  > spec §Clarificações: "coluna esquerda (~60%), coluna direita (~40%), ao fechar o painel o mapa expande para largura total"; plan §DecisionMapPanel confirma `grid-template-columns`.

- [x] CHK002 - É "~60%" e "~40%" da proporção split quantificado com valores concretos usados na implementação? [Clareza, Spec §FR-006] {auto}
  > plan.md §DecisionMapPanel: `3fr 2fr` (= 60%/40%) quando painel aberto; `1fr` quando fechado. Suficientemente concreto para implementação.

- [x] CHK003 - São os requisitos de agrupamento visual de nós por onda definidos (como ondas são visualmente distinguidas no mapa)? [Completude, Spec §FR-002, US4 SC1] {auto}
  > spec §FR-002: "layout vertical (top→bottom) agrupado por onda"; plan §DecisionMapSvg: rótulos de onda via `<text>` e constantes `HEADER_Y=28`. Agrupamento documentado.

- [x] CHK004 - São os requisitos de dimensão dos nós (largura, altura, espaçamento) especificados e não deixados ao arbítrio da implementação? [Clareza, Spec §FR-002, DataModel §LayoutConfig] {auto}
  > data-model.md §LayoutConfig: NODE_WIDTH=200, NODE_HEIGHT=72, COL_GAP=48, ROW_GAP=12, HEADER_Y=28, PADDING=16. Totalmente especificado.

- [x] CHK005 - É o conteúdo mínimo de cada nó (campos obrigatórios) definido sem ambiguidade? [Completude, Spec §FR-003] {auto}
  > spec §FR-003: "escolha feita, score (com cor semântica) e onda de origem". plan §DecisionMapNode confirma os três campos. Definido.

- [ ] CHK006 - São os requisitos de altura máxima do mapa SVG definidos para evitar scroll vertical excessivo quando há muitas ondas? [Completude, Spec §FR-012] [Gap]
  > spec §FR-012 menciona "sem travar a interface" e limit=100, mas não define altura máxima do SVG nem comportamento de scroll interno. Risco: mapa cresce indefinidamente verticalmente com muitas ondas.

- [ ] CHK007 - É o comportamento de scroll do mapa (scroll interno no SVG vs. scroll da página) definido para execuções com > N ondas? [Clareza, Spec §Edge Cases] [Gap]
  > spec §Edge Cases menciona "carregar progressivamente ou paginado" para centenas de decisões, mas não define o mecanismo de scroll do SVG. `[Gap]`

---

## Estados de Interação e Feedback

- [x] CHK008 - São todos os quatro estados obrigatórios do mapa (carregando, vazio, erro, degradado) definidos com comportamento de renderização especificado? [Completude, Spec §FR-008] {auto}
  > spec §FR-008 e plan §Estados do mapa: tabela com 7 estados (incluindo Fechado e Corte >100). Completo.

- [x] CHK009 - É o estado visual do botão toggle "Árvore de decisões" (normal, ativo/pressionado, disabled em FeatureDetail) definido para todos os contextos de uso? [Completude, Spec §FR-001, FR-013] {auto}
  > spec §FR-001: botão habilitado em ExecutionDetail; §FR-013: permanece disabled em FeatureDetail. Dois estados definidos. Porém:

- [ ] CHK010 - É o estado visual "ativo" do botão toggle (quando o mapa está aberto) definido — cor, ícone, label — para diferenciar do estado "fechado"? [Clareza, Spec §FR-001, US1 SC1] [Gap]
  > US1 SC1 menciona "o botão muda de estado para indicar modo ativo", mas spec §FR-001 e plan §Modificação em ExecutionDetail não definem como visualmente (cor de fundo, label alterado, ícone diferente). `[Gap]`

- [x] CHK011 - É o estado selecionado de um nó (após clique) visualmente diferenciado do estado neutro? [Completude, Spec §FR-006, DataModel §Entity MapNode] {auto}
  > data-model.md §Entity MapNode: estado `'neutral' | 'selected' | 'focused'` gerenciado por `selectedKey`. plan §DecisionMapNode não detalha a diferenciação visual, mas o padrão de seleção está definido.

- [ ] CHK012 - São os requisitos visuais dos estados de nó (neutro, selecionado, em foco por teclado) quantificados — cor de borda, sombra, opacidade? [Clareza, Spec §FR-010, DataModel §Entity MapNode] [Gap]
  > data-model.md define os três estados em enum, mas nem spec nem plan definem os tokens CSS para cada estado. Risco: implementação inconsistente com design system existente. `[Gap]`

- [x] CHK013 - É o comportamento de substituição de conteúdo no painel lateral ao clicar em nó diferente (sem fechar o mapa) definido? [Completude, Spec §US2 SC2] {auto}
  > spec §US2 SC2: "o painel exibe os dados de B sem fechar o mapa". plan §DecisionMapPanel: `setSelectedKey` atualiza a referência. Definido.

- [x] CHK014 - São os requisitos de feedback do estado degradado (banner + mapa parcial) definidos — posição do banner, conteúdo mínimo? [Completude, Spec §FR-008, Plan §Estados] {auto}
  > plan §Estados do mapa: "Banner degradado + mapa parcial". Posição não especificada, mas comportamento definido. Aceitável para este nível.

- [x] CHK015 - É o estado de corte de paginação (> 100 decisões) definido com aviso ao usuário? [Completude, Spec §FR-012, Plan §Estados] {auto}
  > plan §Estados: "SVG + banner de aviso" quando `pagination.hasMore`. Definido.

---

## Acessibilidade e Teclado

- [x] CHK016 - São os requisitos de navegação por teclado entre nós definidos com as teclas específicas? [Completude, Spec §FR-010] {auto}
  > spec §FR-010: "Tab/setas" para navegação. plan §Acessibilidade: "Tab normal" via `tabIndex={0}`. Porém "setas" — ver CHK017.

- [ ] CHK017 - É "navegação por setas" entre nós especificada — setas movem entre nós adjacentes (up/down/left/right) ou é apenas Tab? [Ambiguidade, Spec §FR-010] [Ambiguity]
  > spec §FR-010 menciona "Tab/setas" mas plan §Acessibilidade implementa apenas `tabIndex={0}` (Tab normal). Se setas arrow forem requisito, precisam de `onKeyDown` com Arrow keys. `[Ambiguity]`

- [x] CHK018 - É a ativação de nó por teclado (Enter/Espaço) especificada? [Completude, Spec §FR-010] {auto}
  > spec §FR-010 e plan §Acessibilidade: `onKeyDown`: Enter ou Space → `onNodeSelect`. Definido.

- [x] CHK019 - É o fechamento do painel lateral por Escape especificado? [Completude, Spec §FR-010] {auto}
  > spec §FR-010 e plan §Acessibilidade: "fechamento do painel lateral por Escape". plan §DecisionDetailPane: "Escape também fecha". Definido.

- [x] CHK020 - São os atributos ARIA mínimos para o SVG e nós definidos? [Completude, Spec §FR-010, Plan §DecisionMapSvg] {auto}
  > plan §DecisionMapSvg: `role="img"` + `aria-label="Mapa de decisões"` no SVG; `role="button"` + `aria-label={decision.escolha}` nos nós `<g>`. Definido.

- [ ] CHK021 - É o foco inicial ao abrir o mapa definido — onde o foco do teclado vai após abrir o mapa? [Completude, Spec §FR-010] [Gap]
  > spec §FR-010 e plan §Acessibilidade não definem onde o foco vai ao abrir o mapa (primeiro nó? botão toggle? container do mapa?). Sem isso, usuários de teclado não têm ponto de entrada claro. `[Gap]`

- [ ] CHK022 - É o gerenciamento de foco ao fechar o painel lateral definido — o foco retorna ao nó que estava selecionado ou ao botão toggle? [Completude, Spec §FR-010] [Gap]
  > spec §US2 SC3 define que o painel fecha, mas não especifica retorno de foco. `[Gap]`

- [ ] CHK023 - São os requisitos de ordem de tabulação (Tab order) entre elementos interativos (botão toggle, nós do mapa, painel lateral, botão fechar) definidos? [Completude, Spec §FR-010] [Gap]
  > spec §FR-010 não define a ordem de Tab entre os elementos interativos. `[Gap]`

---

## Segurança de Conteúdo e Renderização

- [x] CHK024 - É o requisito de renderização de texto puro (TextRaw) para campos UNTRUSTED definido com os campos específicos listados? [Completude, Spec §FR-007, US2 SC4] {auto}
  > spec §FR-007: lista todos os campos UNTRUSTED (`contexto`, `justificativa`, `evidência`, `escolha`, `agente`). data-model.md confirma UNTRUSTED em cada campo. Definido.

- [x] CHK025 - É o requisito de não usar innerHTML/dangerouslySetInnerHTML para conteúdo de agente especificado explicitamente? [Completude, Spec §FR-007, DataModel §Invariantes] {auto}
  > data-model.md §Invariantes: "SVG não usa innerHTML nem dangerouslySetInnerHTML". spec §US2 SC4: "renderizado como texto puro — nunca como HTML ativo". Definido.

---

## Navegação e Cadeia de Decisões

- [x] CHK026 - É o mecanismo de navegação anterior/próxima no painel de detalhe especificado (chave sintética, array flat)? [Completude, Spec §FR-005, US4 SC3] {auto}
  > spec §FR-005: "array flat ordenado carregado pelo hook `useDecisions`". plan §DecisionDetailPane: "Navegação: botão ← decisão anterior / decisão próxima →". Definido.

- [x] CHK027 - É o comportamento de navegação nos extremos da lista (primeira e última decisão) definido — botões desabilitados ou ausentes? [Completude, Spec §FR-005] [Gap]
  > spec §FR-005 e plan §DecisionDetailPane não especificam o comportamento quando o usuário está na primeira decisão (sem "anterior") ou na última (sem "próxima"). `[Gap]`

- [x] CHK028 - É o requisito de direção das arestas (seta indicando progressão) definido? [Completude, Spec §FR-005, US4 SC2] {auto}
  > spec §FR-005: "arestas direcionadas indicando progressão". plan §DecisionMapSvg: `marker-end="url(#arrow)"`. Definido.

---

## Filtros e Integração com Contexto Existente

- [x] CHK029 - É o requisito de respeitar o filtro de onda ativo (waveFilter) definido com o mecanismo de propagação? [Completude, Spec §FR-009] {auto}
  > spec §FR-009 e plan §DecisionMapPanel: `useDecisions(execucaoId, { limit: 100, wave?: waveFilter })`. Filtro propagado via parâmetro de query. Definido.

- [x] CHK030 - É o comportamento do mapa ao resetar o filtro de onda (de filtrado para "todas as ondas") definido? [Completude, Spec §FR-009, Edge Cases] {auto}
  > spec §FR-009 define que o mapa "reflete o filtro ativo". Reset é coberto implicitamente pela reatividade do `waveFilter`. Aceitável.

- [x] CHK031 - É o requisito de reset do estado do mapa ao trocar de aba ou execução definido? [Completude, Spec §Edge Cases] {auto}
  > spec §Edge Cases: "O estado do mapa não deve ser mantido ao retornar". plan §Modificação em ExecutionDetail: "Reset ao trocar de aba ou de execução". Definido.

---

## Edge Cases de UI

- [x] CHK032 - É o comportamento do mapa com uma única decisão (um nó, sem arestas) definido sem erro de layout? [Completude, Spec §Edge Cases] {auto}
  > spec §Edge Cases: "deve exibir um nó único sem arestas, sem erro de layout". Definido.

- [x] CHK033 - É o comportamento do painel lateral quando campos opcionais são todos nulos (contexto, justificativa, evidência) definido? [Completude, Spec §Edge Cases, US2 SC4] {auto}
  > spec §Edge Cases: "o painel lateral exibe apenas os campos presentes, sem áreas vazias 'flutuando'". Definido.

- [ ] CHK034 - É o comportamento de um nó com `escolha = null` no rótulo principal do nó definido — o que é exibido quando o campo principal é nulo? [Completude, Spec §FR-003, US3 SC2] [Gap]
  > spec §FR-003 define `escolha` como rótulo principal, mas data-model.md §DecisionDTO lista `escolha` como nullable. O que o nó exibe quando `escolha = null`? `[Gap]`

- [x] CHK035 - É o comportamento do mapa ao filtrar por onda que não tem decisões (mapa vazio após filtro) definido? [Completude, Spec §FR-008, FR-009] {auto}
  > spec §FR-008: estado vazio com "Nenhuma decisão registrada para esta execução." cobriria este caso. Aceitável.

---

## Notes

- Items `{auto}` foram resolvidos pelo agente com evidência citada da spec/plan/data-model
- Items `{humano}` aguardam decisão do dono do produto
- Gaps abertos (`[Gap]`): CHK006, CHK007, CHK010, CHK012, CHK021, CHK022, CHK023, CHK027, CHK034
- Ambiguidades (`[Ambiguity]`): CHK017

### Resolução

- **{auto} resolvidos**: 25 (`[x]`)
- **{humano} aguardando decisão**: 0
- **Gaps abertos** (`[Gap]`): 9
- **Ambiguidades** (`[Ambiguity]`): 1

### Próximos Passos

- `/clarify` — resolver CHK017 (setas vs Tab na navegação)
- `/create-tasks` — CHK006, CHK007, CHK010, CHK012, CHK021, CHK022, CHK023, CHK027, CHK034 viram tarefas ou refinamentos de spec
