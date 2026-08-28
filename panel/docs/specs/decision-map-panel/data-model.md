# Data Model: Decision Map Panel

**Feature**: `decision-map-panel`
**Data**: 2026-05-29

> Esta feature é **stateless** e **read-only** — não há persistência própria,
> não há tabelas novas, não há mutações. O modelo de dados descreve as
> estruturas de **estado de UI** (em memória, em React state) e o **DTO
> existente** consumido da API.

---

## Entity: DecisionDTO (existente, read-only)

Fonte: `packages/shared-types/src/entities.ts`. Consumido via
`GET /api/v1/executions/:execucaoId/decisions`.

| Campo | Tipo | Nullable | Notas |
|-------|------|----------|-------|
| `wave` | `string` | não | Identificador da onda (ex: `onda-001`) |
| `execucaoId` | `string` | não | Foreign key da execução |
| `etapa` | `string \| null` | sim | Nome da etapa (ex: `clarify`) |
| `agente` | `string \| null` | sim | Identificador do agente. UNTRUSTED |
| `escolha` | `string \| null` | sim | Opção escolhida. UNTRUSTED |
| `opcoes` | `string \| null` | sim | JSON array cru de opções. UNTRUSTED |
| `score` | `0\|1\|2\|3\|null` | sim | Score de decisão |
| `contexto` | `string \| null` | sim | Contexto da decisão. UNTRUSTED |
| `justificativa` | `string \| null` | sim | Justificativa. UNTRUSTED |
| `evidencia` | `string \| null` | sim | Evidência empírica. UNTRUSTED |

**Campos UNTRUSTED**: renderizados via `<TextRaw>` (textContent puro, nunca
innerHTML). Princípio V da constitution.

---

## Entity: MapNode (estado de UI, em memória)

Representa um nó do mapa SVG derivado de um `DecisionDTO`.

| Campo | Tipo | Derivação |
|-------|------|-----------|
| `key` | `string` | `${wave}::${index}` onde index = posição 0-based no array flat |
| `decision` | `DecisionDTO` | referência ao DTO original |
| `x` | `number` | calculado pelo layoutEngine |
| `y` | `number` | calculado pelo layoutEngine |
| `waveIndex` | `number` | índice da onda no array de ondas únicas |
| `nodeIndexInWave` | `number` | índice do nó dentro da onda |

**Chave natural**: `key = ${wave}::${index}` — estável dentro de uma request.

**Estado do nó**: `'neutral' | 'selected' | 'focused'` — gerenciado por
`selectedKey: string | null` no componente `DecisionMapPanel`.

---

## Entity: LayoutConfig (constantes, não persistidas)

Configurações determinísticas do algoritmo de layout. Definidas como constantes
no módulo `decision-map-layout.ts`.

| Constante | Valor | Significado |
|-----------|-------|-------------|
| `NODE_WIDTH` | `200` | Largura do nó em px |
| `NODE_HEIGHT` | `72` | Altura do nó em px |
| `COL_GAP` | `48` | Espaço horizontal entre colunas de onda |
| `ROW_GAP` | `12` | Espaço vertical entre nós da mesma onda |
| `HEADER_Y` | `28` | Espaço reservado para rótulo da onda no topo |
| `PADDING` | `16` | Padding externo do SVG |

---

## Entity: DecisionMapState (React state, em memória)

Estado local do componente `DecisionMapPanel`.

| Campo | Tipo | Inicial | Descrição |
|-------|------|---------|-----------|
| `selectedKey` | `string \| null` | `null` | Chave do nó selecionado (clique ou teclado) |
| `mapVisible` | `boolean` | `false` | Controla visibilidade do mapa (botão toggle) |

O painel lateral de detalhe é derivado: renderizado quando
`selectedKey !== null && mapVisible === true`.

---

## Fluxo de dados

```
useDecisions(execucaoId, { limit: 100, wave?: waveFilter })
  → DecisionDTO[]
    → layoutEngine(items)      // JS puro, determinístico
      → MapNode[]              // com x, y calculados
        → <DecisionMapSvg>     // renderiza SVG com nós + arestas
          → on node click      // atualiza selectedKey
            → <DecisionDetailPane>  // renderiza painel lateral
```

**Invariantes**:
- `items[i].key === "${items[i].decision.wave}::${i}"` para todo i
- Nenhuma request adicional ao clicar em nó (dado já em memória)
- SVG não usa innerHTML nem dangerouslySetInnerHTML

---

## Restrições de fonte de dados

| Restrição | Origem |
|-----------|--------|
| Nenhum endpoint novo no backend | FR-011, Constitution I |
| Não consultar state.json diretamente | FR-011 |
| Não invocar skill decision-tree | FR-011, Constitution IV |
| Somente `GET` sobre API existente | Constitution I |
| `limit=100` máximo (teto backend) | pagination.ts SC-008 |
