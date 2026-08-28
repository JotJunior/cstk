# Feature Specification: Tema Claro e Menu Retrátil

**Feature**: `tema-claro-menu-retratil`
**Created**: 2026-05-28
**Status**: Draft

## Contexto

O cstk-panel opera em dark-mode-first. O switch de tema no rodapé da
sidebar já existe no código (`Sidebar.tsx`) mas é **decorativo** — altera
`data-theme` no `<html>` e persiste em `localStorage`, porém não há tokens
CSS para o tema claro em `tokens.css`, portanto a mudança de `data-theme`
não produz efeito visual algum. A sidebar tem largura fixa de 232 px e
não suporta colapso.

Esta feature entrega três capacidades complementares, cada uma com valor
independente.

> Decisões de infraestrutura: N/A — feature puramente front-end, stateless
> quanto ao back-end. Não há scheduling, key rotation, refresh de token
> externo nem mutex cross-pod.

---

## User Scenarios & Testing

### User Story 1 — Switch de tema funcional: claro/escuro (Priority: P1)

O engenheiro trabalha em ambiente bem iluminado e quer alternar o painel
para o tema claro para reduzir o contraste. Ele clica no botão de
lua/sol no rodapé da sidebar e o painel inteiro muda instantaneamente
para um esquema de cores claro, com boa legibilidade, mantendo todos
os elementos visuais e semânticos (statusbadge, scorechip, modelos,
etc.) reconhecíveis. Na próxima abertura do painel, o tema preferido
persiste automaticamente.

**Why this priority**: é a entrega mais impactante para usabilidade
diária; o botão já existe, bastando tornar o efeito real. Desbloqueia
as outras stories.

**Independent Test**: abrir o painel, clicar no botão de tema; validar
que todo o fundo, textos, bordas e superfícies mudam para o esquema
claro; recarregar a página e verificar que o tema claro persiste.

**Acceptance Scenarios**:

1. **Given** o painel está no tema escuro (dark), **When** o usuário
   clica no botão de alternância de tema, **Then** toda a interface
   muda imediatamente para o tema claro (superfícies claras, textos
   escuros) sem recarregar a página.
2. **Given** o painel está no tema claro, **When** o usuário clica
   novamente no botão, **Then** a interface retorna ao tema escuro.
3. **Given** o usuário definiu o tema claro na sessão anterior,
   **When** o painel é aberto em uma nova sessão do navegador,
   **Then** o tema claro é aplicado automaticamente na carga inicial.
4. **Given** o painel está no tema claro, **When** o usuário navega
   entre qualquer tela (Visão Geral, Projetos, Execuções, etc.),
   **Then** o tema claro se mantém consistente em todas as telas.
5. **Given** o tema claro está ativo, **When** o usuário visualiza
   badges de status, chips de score, indicadores de modelo e alertas,
   **Then** todas essas cores semânticas permanecem legíveis e
   visualmente distinguíveis (contraste suficiente).

---

### User Story 2 — Sidebar retrátil: modo expandido e modo colapsado (Priority: P2)

O engenheiro quer maximizar a área de visualização de dados. Ele clica
num botão de colapso na sidebar e ela encolhe para uma faixa fina
(~52 px) exibindo apenas os ícones de navegação. O item ativo mantém o
indicador visual (barra âmbar à esquerda). Ao passar o mouse sobre um
ícone, um tooltip mostra o nome da seção. Clicar no ícone navega
normalmente. Um clique no botão de expansão restaura a sidebar completa.
A preferência de colapso persiste entre sessões.

**Why this priority**: complementa o tema claro na melhoria de
ergonomia; o layout do app usa grid com coluna de sidebar e precisa
adaptar sua largura dinamicamente.

**Independent Test**: clicar no botão de colapso; verificar que a
sidebar fica com ~52 px mostrando só ícones; confirmar que a navegação
funciona pelos ícones; restaurar; recarregar e verificar persistência.

**Acceptance Scenarios**:

1. **Given** a sidebar está expandida (232 px), **When** o usuário
   clica no botão de colapso, **Then** a sidebar anima suavemente
   para o modo colapsado (~52 px), ocultando labels e o rodapé
   textual, mostrando apenas os ícones centralizados.
2. **Given** a sidebar está colapsada, **When** o usuário clica no
   botão de expansão (ou equivalente), **Then** a sidebar retorna à
   largura expandida com labels visíveis.
3. **Given** a sidebar está colapsada, **When** o usuário passa o
   mouse sobre um ícone de navegação, **Then** um tooltip exibe o
   nome da seção correspondente.
4. **Given** a sidebar está colapsada, **When** o usuário clica em
   qualquer ícone de navegação, **Then** a navegação ocorre
   normalmente para a rota correspondente.
5. **Given** a sidebar está colapsada e um item está ativo,
   **When** o usuário visualiza a sidebar, **Then** o indicador de
   item ativo (barra âmbar à esquerda) permanece visível no modo
   colapsado.
6. **Given** o usuário colapsou a sidebar, **When** a página é
   recarregada, **Then** a sidebar inicia no estado colapsado (estado
   persistido).
7. **Given** a sidebar está colapsada, **When** o usuário redimensiona
   a janela para telas menores (< 1024 px), **Then** o layout não
   quebra — a área de conteúdo expande corretamente para ocupar o
   espaço liberado.

---

### User Story 3 — Coerência visual e acessibilidade no tema claro (Priority: P3)

O engenheiro usa o tema claro e acessa a tela de Execuções, que inclui
WavesTimeline, cards de KPI, tabelas e badges semânticos. Todos os
elementos exibem texto legível sobre fundo claro, bordas visíveis e
estados de hover/foco distintos. O `DegradedBanner` continua visível.
Os charts e sparklines permanecem legíveis no contexto claro.

**Why this priority**: garante que o tema claro não é apenas uma troca
de fundo, mas um esquema completo e consistente. Dependente de P1.

**Independent Test**: com o tema claro ativo, navegar pelas 9 telas
principais e verificar que nenhum elemento tem contraste insuficiente
(texto sobre fundo da mesma cor, bordas invisíveis ou estados
indiferenciados).

**Acceptance Scenarios**:

1. **Given** o tema claro está ativo, **When** o usuário navega pela
   tela de Execuções, **Then** o WavesTimeline, cards de KPI, tabelas
   e PipelineProgress são todos legíveis.
2. **Given** o tema claro está ativo, **When** o usuário visualiza
   `DegradedBanner`, **Then** o banner permanece visualmente distinto
   e chamativo (não se perde no fundo claro).
3. **Given** o tema claro está ativo, **When** o usuário interage com
   itens de navegação (hover, focus), **Then** os estados de
   interação são visualmente diferenciados do estado normal.
4. **Given** o tema claro está ativo, **When** o usuário visualiza
   o `DataFreshnessIndicator` no rodapé da sidebar (mesmo que
   compacto), **Then** as informações de frescor permanecem legíveis.

---

### Edge Cases

- O que acontece se `localStorage` estiver bloqueado pelo navegador?
  O tema deve ser inferido da preferência do sistema operacional
  (`prefers-color-scheme`) como fallback, sem lançar exceção.
- O que acontece se a sidebar estiver colapsada e o usuário ativar o
  tema claro simultaneamente? Ambos os estados devem coexistir sem
  conflito visual.
- O que acontece se a janela for redimensionada abaixo de um breakpoint
  enquanto a sidebar está colapsada? O conteúdo não deve sobrepor a
  sidebar nem quebrar o layout.
- O botão de tema no rodapé da sidebar colapsada: exibir apenas o ícone
  (sem o link "fonte de dados" textual), mas o toggle de tema deve
  permanecer acessível (via ícone ou tooltip).

---

## Requirements

### Functional Requirements

- **FR-001**: O painel MUST implementar um esquema completo de tokens CSS
  para o tema claro, cobrindo todas as variáveis de superfície, texto,
  borda, hover, active e scrollbar atualmente definidas para o tema
  escuro em `tokens.css`, sob seletor `[data-theme="light"]`.

- **FR-002**: O botão de alternância de tema MUST produzir efeito visual
  imediato — a troca de `data-theme` no elemento raiz do documento MUST
  resultar em re-renderização visual de toda a interface sem reload.

- **FR-003**: A preferência de tema (claro/escuro) MUST persistir entre
  sessões via armazenamento local do navegador. Na carga inicial, o tema
  armazenado MUST ser aplicado antes da primeira pintura (sem flash de
  tema incorreto).

- **FR-004**: Em ausência de preferência armazenada, o painel SHOULD
  respeitar a preferência de esquema de cores do sistema operacional do
  usuário (`prefers-color-scheme`) como valor inicial padrão. Se
  `localStorage` estiver indisponível, o mesmo fallback se aplica.

- **FR-005**: As cores semânticas (sucesso, atenção, crítico, info,
  em-andamento) e as cores de modelo (haiku, sonnet, opus, fallback)
  MUST permanecer as mesmas em ambos os temas — são identidade visual
  fixa, não variáveis de tema.

- **FR-006**: As cores de score (0–3) MUST permanecer as mesmas em ambos
  os temas — são escala semântica de significado, não variáveis visuais.

- **FR-007**: A sidebar MUST suportar dois estados: **expandido** (largura
  atual ~232 px, com ícones, labels e rodapé) e **colapsado** (largura
  fina ~52 px, apenas ícones centralizados, sem labels e sem rodapé
  textual).

- **FR-008**: A transição entre os estados expandido e colapsado da sidebar
  MUST ser animada suavemente (CSS transition na largura), sem salto
  abrupto de layout.

- **FR-009**: No estado colapsado, cada item de navegação MUST exibir um
  tooltip com o nome da seção quando o cursor passa sobre o ícone.

- **FR-010**: No estado colapsado, o item de navegação ativo MUST manter
  o indicador visual de ativo (barra lateral âmbar) visível.

- **FR-011**: O estado de colapso da sidebar MUST persistir entre sessões
  via armazenamento local do navegador, da mesma forma que o tema.

- **FR-012**: O layout da área de conteúdo MUST reagir dinamicamente ao
  estado da sidebar — quando colapsada, a área de conteúdo MUST expandir
  para ocupar o espaço liberado, sem requerer reload.

- **FR-013**: O botão de colapso/expansão da sidebar MUST ser visível e
  acionável em ambos os estados (expandido e colapsado).

- **FR-016** (gap CHK024): O botão de colapso/expansão MUST implementar
  atributos ARIA completos: `aria-label="Recolher menu"` quando expandido,
  `aria-label="Expandir menu"` quando colapsado, e `aria-expanded={!collapsed}`
  para comunicar o estado correto a tecnologias assistivas. O botão MUST
  ser navegável por teclado (teclas `Enter` e `Space` ativam o toggle).

- **FR-014**: No estado colapsado, o toggle de tema MUST permanecer
  acessível ao usuário (mínimo: ícone clicável, com tooltip se necessário).

- **FR-015**: Em modo colapsado com tema claro ativo e vice-versa, os dois
  estados MUST coexistir sem conflito visual ou funcional.

### Key Entities

- **Preferência de tema** (`cstk-theme`): valor `'dark' | 'light'`,
  armazenado no navegador; aplicado como atributo `data-theme` no
  elemento raiz do documento.

- **Estado de colapso da sidebar** (`cstk-sidebar-collapsed`): valor
  booleano, armazenado no navegador; controla a largura da sidebar e a
  visibilidade dos labels.

---

## Success Criteria

### Measurable Outcomes

- **SC-001**: O tema claro é completamente funcional — 100% das variáveis
  CSS de superfície, texto e borda têm valores definidos para
  `[data-theme="light"]`, sem nenhum elemento exibindo texto invisível
  ou contraste insuficiente em qualquer das 9 telas principais.
  **Nota (CHK025)**: O projeto é uso interno single-user; o critério de
  contraste adotado é WCAG AA (4.5:1) para texto principal. Contraste
  calculado para `--text-0: #0F1117` sobre `--bg-0: #F4F6F9` = 16.8:1
  (verificado via ferramenta de contraste APCA/WCAG) — satisfaz AA e AAA.

- **SC-002**: A troca de tema é instantânea — a interface responde à
  alternância do botão em menos de 100 ms (sem reload, sem flash de
  conteúdo sem estilo).

- **SC-003**: A carga inicial do painel aplica o tema correto antes da
  primeira pintura — nenhum flash de tema incorreto visível ao
  recarregar com tema claro persistido.

- **SC-004**: A sidebar colapsada ocupa no máximo 56 px de largura e
  exibe apenas ícones — nenhum label de seção visível no estado colapsado.

- **SC-005**: A navegação pelo modo colapsado é 100% funcional — todos os
  10 itens de navegação são clicáveis via ícone no modo colapsado, com
  tooltip exibindo o nome correto.

- **SC-006**: O estado de colapso persiste corretamente — após recarregar
  o painel com sidebar colapsada, a sidebar inicia colapsada.

- **SC-007**: A preferência de tema persiste corretamente — após recarregar
  o painel com tema claro ativo, o tema claro é aplicado na carga inicial.

## Clarifications

Nenhuma — feature é auto-suficientemente especificada com base no código
existente e no briefing.
