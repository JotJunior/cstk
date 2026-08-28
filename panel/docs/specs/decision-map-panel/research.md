# Research: Decision Map Panel

**Feature**: `decision-map-panel`
**Data**: 2026-05-29
**Status**: Completo — zero NEEDS CLARIFICATION remanescentes

---

## Decision 1 — Estratégia de renderização do grafo (sem lib externa)

**Decisão**: SVG manual com `<foreignObject>` para nós React.

**Rationale**: O projeto tem zero dependências de grafo (verificado em
`apps/web/package.json` — nenhum reactflow, d3, elk, cytoscape). Adicionar
~200-300KB de bundle para uma feature de observabilidade viola o princípio de
lean SPA. `<foreignObject>` dentro de `<svg>` permite renderizar componentes
React ricos (ScoreChip, TextRaw, chips de opções) dentro dos nós sem
comprometer acessibilidade (tabIndex, role, aria funcionam normalmente em
elementos dentro de foreignObject). Arestas são `<path>` com atributo
`marker-end` apontando para `<marker>` de seta SVG definido em `<defs>`.

**Alternativas consideradas**:
- ReactFlow/xyflow: ~250KB min; overkill para grafo linear; requer CSS global
  próprio que conflitaria com tokens.css do projeto.
- D3-dag / d3-force: ~150KB; algoritmo de força é excessivo para sequência
  linear de 20-100 nós; curvatura de arestas sem valor de UX aqui.
- `<g>` com `<text>` SVG puro: sem deps, mas impossibilita uso de ScoreChip e
  TextRaw existentes — exigiria re-implementar rendering de score/texto,
  violando DRY.

**Evidência**: `cat apps/web/package.json | grep -E "flow|d3|graph|dag"` → zero
matches.

---

## Decision 2 — Algoritmo de layout de nós

**Decisão**: Layout vertical determinístico em JS puro — groupby onda, pilha
vertical por onda.

**Rationale**: As decisões já chegam da API ordenadas por `wave` + posição.
O grafo de decisões é uma sequência linear (não uma DAG arbitrária): cada
decisão conecta à próxima em ordem cronológica. Um layout baseado em física
(force-directed) seria imprevisível e desnecessário. O layout correto para
este domínio é uma grade de ondas × posições: coluna = onda, linha = posição
dentro da onda.

**Cálculo**:
```
// Constantes de layout
NODE_WIDTH  = 200    // px
NODE_HEIGHT = 72     // px
COL_GAP     = 48     // horizontal entre colunas de onda
ROW_GAP     = 12     // vertical entre nós da mesma onda
HEADER_Y    = 24     // espaço para rótulo da onda

// Para cada nó i na onda w (0-based):
x[i] = waves.indexOf(w) * (NODE_WIDTH + COL_GAP)
y[i] = HEADER_Y + nodeIndexInWave * (NODE_HEIGHT + ROW_GAP)

// Dimensões do SVG:
svgWidth  = uniqueWaves.length * (NODE_WIDTH + COL_GAP) - COL_GAP + PADDING*2
svgHeight = max(nodesPerWave) * (NODE_HEIGHT + ROW_GAP) - ROW_GAP + HEADER_Y + PADDING
```

**Alternativas consideradas**:
- ELK.js (Eclipse Layout Kernel): ~3MB WASM; absurdamente excessivo para
  sequência linear.
- Layout horizontal (nós em linha): coloca centenas de nós fora do viewport
  horizontal sem scroll útil.

---

## Decision 3 — Volume máximo de decisões no mapa

**Decisão**: `limit=100` (teto do backend) em request única; exibir aviso
quando `pagination.hasMore = true`.

**Rationale**: O `DecisionsPanel` usa paginação de 20 porque é uma tabela onde
o usuário navega página por página. O mapa de grafo precisa de todos os nós
carregados para desenhar as conexões corretamente — uma request paginada
produziria arestas truncadas. O teto `limit=100` está documentado em
`apps/server/src/lib/pagination.ts` (SC-008 do servidor). Para execuções com
>100 decisões, exibir banner: "Exibindo 100 de N decisões. Use o filtro de
onda para restringir a visualização."

**Alternativa considerada**: buscar todas as páginas em paralelo (fetch-all).
Rejeitada: N requests para N/100 páginas viola o princípio de simplicidade e
pode sobrecarregar o servidor para execuções longas.

---

## Decision 4 — Chave de identidade de nó e navegação anterior/próxima

**Decisão**: Chave sintética `${wave}::${index}` onde `index` é a posição
0-based no array flat retornado pela API.

**Rationale**: `DecisionDTO` não tem campo `id` (confirmado em
`packages/shared-types/src/entities.ts`). A API retorna decisões já ordenadas
por `wave` + posição de ingestão. A chave `wave::index` é estável dentro de
uma request (a API é determinística para o mesmo conjunto de filtros). A
navegação anterior/próxima (US4 SC3) usa o índice no array flat para `items[i-1]`
e `items[i+1]`.

**Evidência**: `grep -A 20 "DecisionDTO\b" packages/shared-types/src/entities.ts`
confirma ausência de campo `id`; campos: `wave`, `execucaoId`, `etapa`,
`agente`, `escolha`, `opcoes`, `score`, `contexto`, `justificativa`, `evidencia`.

---

## Resumo de unknowns

| Unknown | Status | Referência |
|---------|--------|------------|
| Lib de grafo disponível | Resolvido: nenhuma → SVG manual | D1 |
| Algoritmo de layout | Resolvido: determinístico JS puro | D2 |
| Volume máximo do mapa | Resolvido: limit=100, banner se hasMore | D3 |
| Identidade de nó | Resolvido: chave sintética wave::index | D4 |
