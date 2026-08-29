# Quickstart / Test Scenarios: Decision Map Panel

**Feature**: `decision-map-panel`
**Data**: 2026-05-29

---

## Cenário 1 — Abrir o mapa de decisões (happy path)

**Pré-condição**: execução com 3+ decisões registradas.

1. Navegar para `/executions/:execucaoId`
2. No card de header, localizar o botão `árvore de decisões`
3. Verificar que o botão NÃO está `disabled` (FR-001)
4. Clicar no botão
5. **Expected**: o mapa SVG é exibido abaixo das tabs, na coluna esquerda
   (~60% da largura). Cada decisão aparece como um nó com `escolha`, `score`
   (com cor semântica) e rótulo da onda. Nós de ondas consecutivas são
   conectados por arestas com seta direcional.
6. O botão muda para indicar estado ativo (ex: borda ou fundo diferente).

---

## Cenário 2 — Inspecionar uma decisão individual

**Pré-condição**: mapa aberto com nós visíveis.

1. Clicar em qualquer nó do mapa
2. **Expected**: painel lateral direito (~40%) aparece com os campos da decisão:
   - `escolha` (via TextRaw)
   - `opcoes` como chips com a escolhida destacada (usando `chosenOptionIndex`)
   - `contexto`, `justificativa` (via TextRaw)
   - `evidencia` em bloco mono (via `TextRaw mono`)
   - `etapa`, `wave`, `agente`, `score` (ScoreChip)
3. Nenhuma request adicional ao servidor é feita ao clicar (dado já em memória).
4. Clicar em outro nó — painel atualiza com dados do novo nó sem fechar.
5. Clicar fora do painel (ou em botão de fechar do painel) — painel fecha,
   mapa permanece visível e expande para 100%.

---

## Cenário 3 — Fechar o mapa

**Pré-condição**: mapa aberto.

1. Clicar novamente no botão `árvore de decisões` (toggle), OU no botão de
   fechar dentro do mapa.
2. **Expected**: mapa desaparece. A aba `Decisoes` volta ao estado anterior
   (tabela paginada). O estado do mapa NÃO é preservado ao reabrir (sem memory
   leak — `selectedKey` é resetado).

---

## Cenário 4 — Estado vazio (sem decisões)

**Pré-condição**: execução com 0 decisões.

1. Clicar em `árvore de decisões`.
2. **Expected**: mapa exibe `EmptyState` com mensagem
   "Nenhuma decisão registrada para esta execução." — sem nós, sem arestas,
   sem erro.

---

## Cenário 5 — Estado de erro (falha de API)

**Pré-condição**: simular falha na request `/decisions` (mock em vitest ou
network off).

1. Abrir o mapa com servidor indisponível.
2. **Expected**: mapa exibe `ErrorState` com mensagem de erro e possibilidade
   de retry. A tela principal (tabs, header da execução) permanece funcional.

---

## Cenário 6 — Estado degradado (`meta.degraded = true`)

**Pré-condição**: API retorna 200 com `meta.degraded = true`.

1. Abrir o mapa com dados parciais.
2. **Expected**: mapa renderiza os dados disponíveis e exibe banner degradado
   (usando o mecanismo de `DegradedBanner` já existente ou equivalente inline).

---

## Cenário 7 — Filtro de onda ativo

**Pré-condição**: execução com decisões em 3 ondas; filtro `waveFilter` ativo
para `onda-002`.

1. Selecionar onda `onda-002` no `WavesTimeline`.
2. Abrir o mapa (ou o mapa já estar aberto).
3. **Expected**: mapa exibe apenas decisões de `onda-002`. Ao remover o filtro,
   mapa re-renderiza com todas as ondas.

---

## Cenário 8 — Navegação por teclado (FR-010)

**Pré-condição**: mapa aberto com 3+ nós.

1. Pressionar `Tab` — foco avança entre nós do mapa.
2. Pressionar `Enter` ou `Espaço` em nó focado — painel de detalhe abre.
3. Pressionar `Escape` — painel de detalhe fecha.
4. **Expected**: todo o fluxo realizável sem mouse.

---

## Cenário 9 — Segurança: conteúdo adversarial (SC-004)

**Pré-condição**: decisão com `escolha = "<script>alert(1)</script>"` e
`contexto = "<img src=x onerror=alert(1)>"`.

1. Abrir o mapa; clicar no nó com conteúdo adversarial.
2. **Expected**: o conteúdo é renderizado como texto literal — sem execução de
   script, sem inserção de HTML ativo. Verificável via inspeção do DOM:
   `textContent` correto, nenhum elemento `<script>` ou `<img>` injetado.

---

## Cenário 10 — FeatureDetail mantém botão desabilitado (FR-013)

1. Navegar para `/features/:feature`.
2. Verificar o botão `árvore de decisões` na tela `FeatureDetail`.
3. **Expected**: botão permanece `disabled` — o mapa é exclusivo do contexto
   de execução individual.

---

## Cenário 11 — Mapa com >100 decisões (corte com aviso)

**Pré-condição**: execução com 150 decisões.

1. Abrir o mapa.
2. **Expected**: 100 nós são renderizados; banner de aviso indica
   "Exibindo 100 de 150 decisões. Use o filtro de onda para restringir a
   visualização."

---

## Roundtrip End-to-End

**Objetivo**: verificar que o shape da resposta real da API corresponde ao
contrato `DecisionDTO` declarado em shared-types.

```typescript
// apps/server/test/lib/roundtrip.test.ts (estender teste existente)
// OU novo arquivo apps/server/test/lib/decisions-map-roundtrip.test.ts

it('GET /executions/:id/decisions retorna shape DecisionDTO', async () => {
  const res = await fetch(`${BASE_URL}/api/v1/executions/${TEST_EXEC_ID}/decisions?limit=5`);
  const body = await res.json();
  // Validar com Zod
  const parsed = DecisionsPageSchema.safeParse(body);
  expect(parsed.success).toBe(true);
  if (parsed.success) {
    const { decisions } = parsed.data.data;
    // Verificar campos presentes no mapa
    for (const d of decisions) {
      expect(typeof d.wave).toBe('string');
      expect(typeof d.execucaoId).toBe('string');
      // score: 0|1|2|3|null
      expect([0, 1, 2, 3, null]).toContain(d.score);
    }
  }
});
```

Razão: o roundtrip empírico detecta divergências snake_case vs camelCase no
mapeamento server→DTO antes que se acumulem (lição da execução-fonte, 40 ondas
de drift).
