# Implementation Plan: Tema Claro e Menu Retrátil

**Feature**: `tema-claro-menu-retratil` | **Date**: 2026-05-28 | **Spec**: [spec.md](spec.md)

## Summary

Três entregas ortogonais, todas puramente front-end, zero impacto no back-end:

1. **Tema claro funcional** — adicionar bloco `[data-theme="light"]` em `tokens.css` sobrescrevendo as variáveis de superfície, texto e borda. O mecanismo de troca já existe em `Sidebar.tsx`; o único gap é a ausência dos valores CSS. Adicionar script inline no `<head>` do `index.html` para prevenir FOUC.

2. **Switch funcional** — o botão já existe e já chama `setTheme()`; o problema é que `tokens.css` não tinha a contraparte `[data-theme="light"]`. Com a entrega 1, o switch automaticamente se torna funcional.

3. **Sidebar retrátil** — adicionar estado `collapsed: boolean` no `Sidebar.tsx` (persistido em `localStorage`), classe `.sidebar--collapsed` no `<aside>`, tokens CSS para o estado colapsado (largura 52px, labels ocultos, ícones centralizados), botão de colapso/expansão e tooltips via CSS puro. O layout `App.tsx` se adapta via CSS `:has(.sidebar--collapsed)` sem prop-drilling.

## Technical Context

**Language/Version**: TypeScript 5.4 + React 19
**Primary Dependencies**: React Router DOM v6, @tanstack/react-query v5, Zod v3, Vite 5
**Storage**: localStorage (tema e estado de colapso) — sem impacto em back-end
**Testing**: vitest (unitário, `PipelineProgress.test.ts` como referência existente); sem E2E framework configurado
**Target Platform**: SPA no browser (hash routing via HashRouter)
**Project Type**: web-app (front-end SPA)
**Performance Goals**: troca de tema < 100ms (SC-002); sem reload
**Constraints**: dark-mode-first; cores semânticas e de modelo são fixas (Constitution + FR-005, FR-006)
**Scale/Scope**: aplicação local single-user; sem multi-tenant

## Constitution Check

*GATE: Verificado antes do Phase 0. Re-checado após Phase 1.*

| Princípio | Status | Notas |
|-----------|--------|-------|
| I. Read-Only Absoluto | PASS | Feature é puramente front-end (CSS + React state); zero chamadas à API; zero mutações no banco. |
| II. Degradar, Nunca Quebrar | PASS | localStorage bloqueado → fallback para `prefers-color-scheme` sem exceção (FR-004, Dec 5). |
| III. Honestidade de Métrica | PASS | Feature não exibe nem altera métricas; não adiciona campos inventados. |
| IV. Não Reimplementar o que Tem Dono | PASS | Feature não reimplementa decision-tree, model-routing-report.sh nem reindex. |
| V. Conteúdo de Agente é UNTRUSTED | PASS | Feature não toca campos textuais de agentes; não altera renderização de TextRaw. |
| VI. Snapshot que Muda | PASS | Feature não altera a conexão com a knowledge.db nem o DataFreshnessIndicator. |
| Fidelidade de Design | PASS | Paleta light derivada do sistema de tokens existente; sidebar mantém identidade visual âmbar. |
| Quatro estados por tela | PASS | Feature não afeta os estados loading/empty/error/degraded — são independentes do tema. |

**Resultado**: PASS em todos os princípios. Sem violações de MUST. Sem Complexity Tracking necessário.

## Project Structure

### Documentation (this feature)

```
docs/specs/tema-claro-menu-retratil/
├── spec.md           ✓ Criado
├── plan.md           ✓ Este arquivo
├── research.md       ✓ Criado (Phase 0)
├── data-model.md     N/A — feature stateless, sem entidades persistidas no backend
├── quickstart.md     ✓ Criado (Phase 1)
└── contracts/        N/A — feature single-layer (front-end puro, sem API nova)
```

> `data-model.md` e `contracts/` omitidos: feature é puramente front-end
> (CSS + React state), sem entidades de banco nem endpoints novos.

### Source Code (arquivos afetados)

```
apps/web/
├── index.html                           ← [MODIFICAR] script anti-FOUC no <head>
└── src/
    ├── styles/
    │   └── tokens.css                   ← [MODIFICAR] bloco [data-theme="light"]
    │                                       + variáveis do estado colapsado da sidebar
    └── components/
        └── Sidebar.tsx                  ← [MODIFICAR] collapsed state + botão colapso
                                            + tooltips + ARIA + persistência localStorage
```

**Regra**: nenhum outro arquivo precisa ser modificado. `App.tsx` adapta o layout via CSS `:has(.sidebar--collapsed)` sem receber props adicionais. Não criar arquivos novos além dos artefatos de documentação.

## Convencoes de Borda

N/A — single-layer (front-end puro). Feature não atravessa fronteiras backend↔frontend,
DB↔backend nem broker↔consumer. Toda a lógica vive em CSS custom properties +
React state local + localStorage. Nenhum endpoint novo, nenhum tipo compartilhado novo.

## Phase 0 — Research Summary

Cinco decisões tomadas (ver `research.md` para detalhes completos):

| # | Decisão | Escolha |
|---|---------|---------|
| D1 | Mecanismo de troca de tema | `data-theme` + CSS custom properties (já implementado) |
| D2 | Paleta do tema claro | Inversão semântica da paleta dark; cores fixas mantidas |
| D3 | Sidebar retrátil — controle de layout | `.sidebar--collapsed` + CSS `:has()` sem prop-drilling |
| D4 | Tooltip no modo colapsado | CSS puro com `::after` + `data-tooltip` |
| D5 | Prevenção de FOUC | Script inline síncrono no `<head>` do `index.html` |

## Phase 1 — Design

### tokens.css — Bloco `[data-theme="light"]`

Adicionar imediatamente após o bloco `:root { ... }` em `tokens.css`.
Sobrescreve apenas as variáveis de superfície, texto, borda e scrollbar.
Cores semânticas, de modelo e de score permanecem no `:root` (invariantes por tema).

Variáveis a sobrescrever (todas definidas em `:root`):
- Superfícies: `--bg-0` a `--bg-4`, `--bg-hover`, `--bg-active`
- Bordas: `--border`, `--border-strong`, `--border-soft`
- Textos: `--text-0` a `--text-3`
- Scrollbar: `--bg-3` aplicado ao thumb (adaptado via `[data-theme="light"]`)

Valores completos documentados em `research.md §Decision 2`.

### tokens.css — Estado colapsado da sidebar

Adicionar bloco `.sidebar--collapsed` nas regras de sidebar existentes:

```
.sidebar--collapsed              → width: var(--sidebar-width-collapsed, 52px)
.sidebar--collapsed .nav-label   → display: none
.sidebar--collapsed .nav-item span → opacity: 0; width: 0; overflow: hidden
.sidebar--collapsed .nav-item    → justify-content: center; padding: 8px 0
.sidebar--collapsed .brand-name  → display: none
.sidebar--collapsed .brand-tag   → display: none
.sidebar--collapsed .sidebar-foot → padding: 8px 6px
```

CSS `:has()` para o grid da app (em `.app`):
```
.app:has(.sidebar--collapsed) {
  grid-template-columns: var(--sidebar-width-collapsed, 52px) 1fr;
}
```

Transição de largura:
```
.sidebar {
  transition: width 0.2s ease;
  width: var(--sidebar-width); /* expande para var value */
}
.sidebar--collapsed {
  width: var(--sidebar-width-collapsed, 52px);
}
```

### tokens.css — Tooltip CSS puro

```css
.nav-item[data-tooltip] {
  position: relative;
}
.nav-item[data-tooltip]::after {
  content: attr(data-tooltip);
  position: absolute;
  left: calc(100% + 10px);
  top: 50%;
  transform: translateY(-50%);
  background: var(--bg-4);
  color: var(--text-0);
  border: 1px solid var(--border);
  padding: 4px 8px;
  border-radius: var(--r-sm);
  font-size: 12px;
  white-space: nowrap;
  pointer-events: none;
  opacity: 0;
  transition: opacity 0.15s;
  z-index: 100;
}
/* Só exibir tooltip quando colapsada */
.sidebar--collapsed .nav-item[data-tooltip]:hover::after {
  opacity: 1;
}
```

### Sidebar.tsx — Collapsed state e botão

Estado a adicionar:
```typescript
const [collapsed, setCollapsed] = useState<boolean>(
  () => localStorage.getItem('cstk-sidebar-collapsed') === 'true'
);
```

`useEffect` para persistir:
```typescript
useEffect(() => {
  document.documentElement.dataset.theme = theme;
  localStorage.setItem('cstk-theme', theme);
}, [theme]);

useEffect(() => {
  localStorage.setItem('cstk-sidebar-collapsed', String(collapsed));
}, [collapsed]);
```

No JSX:
- `<aside className={`sidebar${collapsed ? ' sidebar--collapsed' : ''}`}>`
- Atributo `data-tooltip={route.label}` em cada `NavItem` (passado via prop)
- Botão de toggle no topo ou rodapé (icon: `chevron-left`/`chevron-right`)
- Em modo colapsado, o `sidebar-foot` exibe apenas o ícone de tema (sem texto)

### index.html — Script anti-FOUC

Inserir no `<head>`, antes de qualquer `<link>`:
```html
<script>
  (function(){
    try {
      var t = localStorage.getItem('cstk-theme');
      if (!t) t = window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
      document.documentElement.dataset.theme = t;
    } catch(e) {}
  })();
</script>
```

> `try/catch` envolvendo todo o bloco: `localStorage.getItem` pode lançar
> em navegadores com storage bloqueado (Safari ITP, modo privado). O
> `catch` é intencionalmente vazio — sem tema aplicado, o fallback é o
> dark-mode-first definido no CSS base.

## Quickstart

Ver `quickstart.md` para cenários de teste completos.

## Constitution Check Pós-Design

Verificação após Phase 1 — nenhuma mudança em relação ao check inicial:

| Princípio | Status Pós-Design |
|-----------|-------------------|
| I. Read-Only Absoluto | PASS — zero mutações de dado; apenas CSS + localStorage |
| II. Degradar, Nunca Quebrar | PASS — localStorage bloqueado tem fallback silencioso |
| III. Honestidade de Métrica | PASS — feature não toca métricas |
| IV. Não Reimplementar o que Tem Dono | PASS — não toca decision-tree nem model-routing |
| V. Conteúdo UNTRUSTED | PASS — feature não altera TextRaw nem renderização de campos de agentes |
| VI. Snapshot que Muda | PASS — feature não afeta a lógica de frescor |
| Fidelidade de Design | PASS — paleta light é derivação coerente; sidebar mantém identidade visual |
