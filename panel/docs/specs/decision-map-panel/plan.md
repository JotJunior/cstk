# Implementation Plan: Decision Map Panel

**Feature**: `decision-map-panel`
**Data**: 2026-05-29
**Status**: Draft

---

## Summary

Habilitar o botão "árvore de decisões" na tela `ExecutionDetail` para exibir
um mapa visual interativo das decisões de uma execução. O mapa é construído
programaticamente (sem dependência da skill `decision-tree`) sobre dados já
disponíveis via endpoint GET existente. Implementado como SVG manual com
`<foreignObject>` para nós React, layout determinístico em JS puro e painel
lateral de detalhe em split horizontal. Zero endpoints novos, zero dependências
externas.

---

## Technical Context

| Campo | Valor |
|-------|-------|
| Linguagem | TypeScript 5.4 + React 19 |
| Framework | React Router v6, TanStack Query v5 |
| Bundler | Vite 5 |
| Testes | Vitest 2, environment: node |
| CSS | tokens.css + prototype.css (dark-mode-first, design tokens) |
| Deps de grafo | **Nenhuma** — SVG manual (Research D1) |
| Backend (modificações) | **Nenhuma** — endpoint GET `/decisions` já existe |
| Novos endpoints | **Nenhum** (FR-011, Constitution I) |
| Teto de decisões/request | 100 (limit= máx do backend, pagination.ts) |

---

## Constitution Check

*Gate: deve passar antes do Phase 0. Re-checado após Phase 1.*

| Principio | Status | Notas |
|-----------|--------|-------|
| I. Read-Only Absoluto | PASS | Somente GET sobre API existente; zero mutações |
| II. Degradar, Nunca Quebrar | PASS | FR-008 define 4 estados; implementados no mapa |
| III. Honestidade de Métrica | PASS | Score exibido como valor real; nenhum campo inventado |
| IV. Não Reimplementar o que Tem Dono | PASS | Opera sobre knowledge.db via API, não sobre state.json; distinção documentada na spec |
| V. Conteúdo de Agente é UNTRUSTED | PASS | FR-007; todos os campos textuais via TextRaw |
| VI. Snapshot que Muda | PASS | Consome API existente com ETag/freshness; sem conexão direta ao DB |

---

## Convencoes de Borda

Esta feature é **single-layer no front-end** — não adiciona camada de backend.
O backend existente já serve os dados via `GET /api/v1/executions/:id/decisions`.

| Camada | Case style | Validacao | Fonte da verdade |
|--------|------------|-----------|------------------|
| API payload (response) | camelCase | Zod (`DecisionsPageSchema`) no frontend | `apps/web/src/lib/hooks.ts` (fetchApi) |
| Frontend DTO | camelCase | Zod parse no fetch | `packages/shared-types/src/entities.ts` |
| Frontend state (MapNode) | camelCase | TypeScript types | `decision-map-layout.ts` (novo) |
| Chave de nó | formato misto `wave::index` | TypeScript (string template) | `decision-map-layout.ts` |

**Mapper layer**: N/A — backend mapeia DB→DTO; o frontend consome o DTO direto.
**Validação Zod**: response boundary (fetchApi → DecisionsPageSchema). Compartilhado via `shared-types`.
**ORM auto-mapping**: N/A — frontend puro.

---

## Project Structure

### Documentação da feature

```
docs/specs/decision-map-panel/
  spec.md          ✓ existente + clarificado
  research.md      ✓ criado
  data-model.md    ✓ criado
  plan.md          ← este arquivo
  quickstart.md    ✓ criado
```

### Código-fonte (arquivos a criar/modificar)

```
apps/web/src/
  screens/
    ExecutionDetail.tsx         [MODIFICAR] — habilitar botão, integrar DecisionMapPanel
  components/
    DecisionMapPanel.tsx        [CRIAR] — componente principal (toggle + SVG + painel)
    DecisionMapSvg.tsx          [CRIAR] — renderização SVG (nós + arestas)
    DecisionMapNode.tsx         [CRIAR] — nó individual via foreignObject
    DecisionDetailPane.tsx      [CRIAR] — painel lateral de detalhe
  lib/
    decision-map-layout.ts      [CRIAR] — engine de layout determinístico
    decision-map-layout.test.ts [CRIAR] — testes unitários do engine
```

---

## Arquitetura de Componentes

### DecisionMapPanel (componente orquestrador)

> **Decisão 0.1.1 (dec-012)**: `mapVisible` é gerenciado em `ExecutionDetail`
> (state elevado), não em `DecisionMapPanel`. Isso facilita reset ao trocar
> de aba e ao trocar de execução. `DecisionMapPanel` recebe `mapVisible` e
> `onToggle` como props.

```
DecisionMapPanel
  props: execucaoId, waveFilter, mapVisible, onToggle
  state: selectedKey (apenas)

  query: useDecisions(execucaoId, { limit: 100, wave?: waveFilter })

  render:
    [botão toggle "árvore de decisões"] ← modifica ExecutionDetail
    if mapVisible:
      <div style="display: grid; grid-template-columns: {selectedKey ? '3fr 2fr' : '1fr'}">
        <DecisionMapSvg nodes={nodes} selectedKey={selectedKey}
                        onNodeSelect={setSelectedKey} />
        {selectedKey &&
          <DecisionDetailPane decision={selectedDecision}
                              onClose={() => setSelectedKey(null)}
                              prevKey={...} nextKey={...} />}
      </div>
```

### DecisionMapSvg (SVG puro)

```
DecisionMapSvg
  props: nodes, selectedKey, onNodeSelect

  render:
    <svg width={layout.svgWidth} height={layout.svgHeight}
         role="img" aria-label="Mapa de decisões">
      <defs>
        <marker id="arrow" ...> <path d="M0,0 L10,5 L0,10 Z" /> </marker>
      </defs>
      // Rótulos de onda
      {waves.map(w => <text ...>{w}</text>)}
      // Arestas (renderizadas antes dos nós — z-order)
      {edges.map(e => <path d={...} marker-end="url(#arrow)" />)}
      // Nós
      {nodes.map(n =>
        <g key={n.key} transform={`translate(${n.x}, ${n.y})`}
           tabIndex={0} role="button" aria-label={n.decision.escolha}
           onClick={() => onNodeSelect(n.key)}
           onKeyDown={e => (e.key==='Enter'||e.key===' ') && onNodeSelect(n.key)}>
          <foreignObject width={NODE_WIDTH} height={NODE_HEIGHT}>
            <DecisionMapNode decision={n.decision}
                             selected={n.key === selectedKey} />
          </foreignObject>
        </g>
      )}
    </svg>
```

### DecisionMapNode (nó visual)

Conteúdo do `<foreignObject>`:
- `escolha` via `<TextRaw maxLength={40}>`
- `<ScoreChip score={decision.score} />`
- Rótulo da onda (mono, text-3)

### DecisionDetailPane (painel lateral)

- Título: escolha (TextRaw)
- Chips de opções com `chosenOptionIndex` (padrão do DecisionsPanel existente)
- `contexto`, `justificativa` via TextRaw
- `evidencia` via TextRaw mono em bloco
- `etapa`, `wave`, `agente`, score (ScoreChip)
- Navegação: botão ← decisão anterior / decisão próxima →
- Botão fechar (Escape também fecha — FR-010)

### decision-map-layout.ts (engine)

```typescript
export interface MapNode { key: string; decision: DecisionDTO;
  x: number; y: number; waveIndex: number; nodeIndexInWave: number; }
export interface MapEdge { from: string; to: string; }
export interface MapLayout { nodes: MapNode[]; edges: MapEdge[];
  svgWidth: number; svgHeight: number; }

export function computeLayout(items: DecisionDTO[]): MapLayout
// Constantes: NODE_WIDTH=200, NODE_HEIGHT=72, COL_GAP=48,
//             ROW_GAP=12, HEADER_Y=28, PADDING=16
```

---

## Estados do mapa (FR-008)

| Estado | Trigger | Renderização |
|--------|---------|--------------|
| Fechado | `mapVisible = false` | Apenas botão toggle |
| Carregando | `query.isLoading` | `<LoadingState />` dentro do mapa |
| Vazio | `items.length === 0` | `<EmptyState title="Nenhuma decisão..." />` |
| Erro | `query.isError` | `<ErrorState message={...} />` |
| Degradado | `meta.degraded = true` | Banner degradado + mapa parcial |
| Normal | `items.length > 0` | SVG com nós e arestas |
| Corte (>100) | `pagination.hasMore` | SVG + banner de aviso |

---

## Acessibilidade (FR-010)

| Interação | Mecanismo |
|-----------|-----------|
| Navegar entre nós | `tabIndex={0}` em cada `<g>` de nó; Tab normal |
| Arrow keys Up/Down | navegar nós na mesma coluna de onda |
| Arrow keys Left/Right | navegar entre colunas de onda |
| Ativar nó | `onKeyDown`: `Enter` ou `Space` → `onNodeSelect` |
| Fechar painel | `onKeyDown` no painel: `Escape` → `setSelectedKey(null)` + foco retorna ao nó selecionado |
| Labels | `aria-label={escolha ?? 'decisão sem escolha'}` no `<g>` de nó |
| SVG label | `role="img"` + `aria-label="Mapa de decisões"` no `<svg>` |
| Foco inicial | ao abrir mapa (`mapVisible=true`): focar `nodes[0]` automaticamente |
| Prev/Next extremos | botões disabled (visíveis, não ocultos) na primeira/última decisão |

> Decisões: dec-014 (Arrow keys), dec-015 (foco inicial), dec-016 (foco ao fechar), dec-016 (prev/next disabled)

### SVG overflow/scroll (dec-018, CHK006, CHK007)

Container wrapper do SVG usa `max-height: 60vh; overflow: auto` para evitar que
mapas com muitas decisões quebrem o layout da tela.

---

## Modificação em ExecutionDetail.tsx

Única modificação cirúrgica:

1. **Botão**: remover `disabled` e `title` que apontava para recurso externo.
   Adicionar `onClick={() => setMapVisible(v => !v)}`. Estado `mapVisible`
   gerenciado no `DecisionMapPanel` ou elevado para `ExecutionDetail`.

2. **Renderização**: dentro do card de tabs, substituir `{activeTab === 'decisions' && <DecisionsPanel ...>}`
   por renderização condicional: quando `mapVisible`, mostrar `<DecisionMapPanel>` acima ou no lugar da tabela.

   **Estratégia de coexistência**: o mapa é um overlay dentro da tab `decisions` —
   quando `mapVisible`, ele substitui o `DecisionsPanel` (tabela); quando fechado,
   o `DecisionsPanel` volta. A tab `decisions` é o contexto natural do mapa.

3. **Estado `mapVisible`**: `useState(false)` em `ExecutionDetail` (ou delegado ao
   componente). Reset ao trocar de aba ou de execução.

---

## Plano de Implementação (fases)

### Fase 1 — Engine de layout (sem UI)
- Criar `decision-map-layout.ts` com `computeLayout`
- Criar `decision-map-layout.test.ts` (casos: array vazio, 1 nó, múltiplas ondas)
- `vitest run` deve passar antes de avançar

### Fase 2 — Componentes SVG (sem integração)
- Criar `DecisionMapSvg.tsx` + `DecisionMapNode.tsx`
- Criar `DecisionDetailPane.tsx` (reutiliza padrão do `DecisionsPanel` expandido)

### Fase 3 — Componente orquestrador
- Criar `DecisionMapPanel.tsx` (integra query + layout + SVG + painel)
- Implementar 4 estados: loading, empty, error, degradado

### Fase 4 — Integração em ExecutionDetail
- Habilitar botão (remover `disabled`)
- Conectar toggle `mapVisible` → mostrar `DecisionMapPanel`
- Verificar que FR-013 (FeatureDetail mantém `disabled`) permanece intacto

### Fase 5 — Acessibilidade e teclado
- Verificar Tab, Enter/Espaço, Escape no mapa e painel
- Teste manual + cenário 8 do quickstart

### Fase 6 — Testes
- Unitários: `decision-map-layout.test.ts`
- Roundtrip: estender `roundtrip.test.ts` ou criar `decisions-map-roundtrip.test.ts`
- `vitest run --reporter=verbose` deve estar verde

---

## Complexity Tracking

Nenhuma violação de constitution identificada. Nenhuma justificativa de complexidade necessária.

---

## Artefatos

| Arquivo | Status |
|---------|--------|
| `docs/specs/decision-map-panel/spec.md` | Existente + clarificado |
| `docs/specs/decision-map-panel/research.md` | Criado |
| `docs/specs/decision-map-panel/data-model.md` | Criado |
| `docs/specs/decision-map-panel/plan.md` | Criado (este) |
| `docs/specs/decision-map-panel/quickstart.md` | Criado |

---

## Próximos Passos

1. `/checklist` — quality gate de requisitos antes de implementar
2. `/create-tasks` — decompor fases em backlog com criticidade e dependências
3. `/analyze` — validar consistência spec/plan/tasks após create-tasks
