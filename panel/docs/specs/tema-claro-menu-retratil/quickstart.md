# Quickstart: tema-claro-menu-retratil

Cenários de teste para validar a implementação. Feature é puramente
front-end — todos os cenários são testáveis com `npm run dev` (Vite dev
server).

> N/A — Roundtrip End-to-End: feature single-layer (front-end puro);
> nenhum endpoint novo criado; nenhum contrato de API modificado.

---

## Scenario 1: Switch de tema — happy path

1. Abrir o painel em `http://localhost:5173` (ou hash equivalente)
2. Verificar que o tema padrão é **dark** (fundo `#0B0D11`)
3. Clicar no botão de sol/lua no rodapé da sidebar
4. **Expected**: toda a interface muda imediatamente para o tema claro
   — fundo branco/cinza claro, textos escuros, bordas visíveis.
   Nenhum reload. Menos de 100ms de latência visual.
5. Navegar para a tela Execuções (`#/executions`)
6. **Expected**: tema claro mantido; WavesTimeline e cards de KPI legíveis.
7. Clicar novamente no botão
8. **Expected**: retorno ao tema escuro imediato.

---

## Scenario 2: Persistência de tema entre sessões

1. Aplicar o tema claro (Scenario 1, passos 1–4)
2. Fechar e reabrir a aba (ou `Cmd+R`)
3. **Expected**: painel abre diretamente no tema claro, sem flash de
   tema escuro antes da carga. `localStorage.getItem('cstk-theme')`
   retorna `'light'`.

---

## Scenario 3: Fallback quando localStorage bloqueado

1. No DevTools, simular bloqueio de `localStorage`:
   `Object.defineProperty(window, 'localStorage', { get: () => { throw new Error('blocked'); } })`
2. Recarregar o painel
3. **Expected**: o painel carrega normalmente (sem erro de console
   relacionado ao localStorage); o tema aplicado reflete a preferência
   do sistema operacional (`prefers-color-scheme`).

---

## Scenario 4: Sidebar retrátil — happy path

1. Abrir o painel
2. Verificar sidebar expandida (232px com labels visíveis)
3. Clicar no botão de colapso (ícone chevron-left/direito)
4. **Expected**: sidebar anima suavemente para ~52px. Labels e rodapé
   textual desaparecem. Apenas ícones centralizados visíveis.
5. Passar o mouse sobre qualquer ícone de navegação
6. **Expected**: tooltip aparece à direita do ícone com o nome da seção
   (ex: "Visão Geral", "Execuções", etc.)
7. Clicar no ícone de "Execuções"
8. **Expected**: navegação para `#/executions` ocorre normalmente.
9. Verificar que o item "Execuções" tem o indicador âmbar visível
   mesmo no modo colapsado.
10. Clicar no botão de expansão (ícone invertido)
11. **Expected**: sidebar retorna a 232px com labels visíveis.

---

## Scenario 5: Persistência do estado colapsado

1. Colapsar a sidebar (Scenario 4, passos 1–4)
2. Recarregar a página
3. **Expected**: sidebar inicia no estado colapsado. `localStorage.getItem('cstk-sidebar-collapsed')` retorna `'true'`.

---

## Scenario 6: Coexistência tema claro + sidebar colapsada

1. Ativar tema claro e colapsar a sidebar (combinação dos Scenarios 1 e 4)
2. **Expected**: sidebar colapsada com ícones visíveis sobre fundo claro.
   Indicador âmbar no item ativo visível. Tooltip exibido em hover.
   Botão de toggle de tema acessível (ícone clicável no rodapé colapsado).
3. Alternar o tema para dark
4. **Expected**: sidebar permanece colapsada; transição de cores ocorre
   normalmente.

---

## Scenario 7: Layout responsivo com sidebar colapsada

1. Colapsar a sidebar
2. No DevTools, reduzir a viewport para 900px de largura
3. **Expected**: layout não quebra. Área de conteúdo ocupa o espaço
   liberado pela sidebar colapsada. Nenhum overflow horizontal visível.
   Nenhum elemento da sidebar sobrepõe o conteúdo.

---

## Scenario 8: Legibilidade do tema claro em telas com conteúdo semântico

1. Ativar tema claro
2. Navegar para uma execução com dados (`#/executions/:id`)
3. **Expected**:
   - `StatusBadge` (em_andamento, concluida, etc.) continua legível
   - `ScoreChip` (0–3) continua com as cores de score visíveis
   - `DegradedBanner` (se ativo) permanece visualmente distinto
   - Links, hover states e foco de teclado são distinguíveis
   - Nenhum texto "invisível" (texto e fundo da mesma cor)
