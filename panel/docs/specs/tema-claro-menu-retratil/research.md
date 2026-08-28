# Research: tema-claro-menu-retratil

Documento produzido no Phase 0 do `/plan`. Zero NEEDS CLARIFICATION —
todos os pontos foram resolvidos a partir do codebase existente.

## Decision 1: Mecanismo de troca de tema — CSS custom properties + data-theme

**Decision**: Usar o atributo `data-theme` já existente em `index.html`/`document.documentElement.dataset.theme` (já implementado em `Sidebar.tsx`) como seletor CSS. Adicionar bloco `[data-theme="light"] { ... }` em `tokens.css` sobrescrevendo as variáveis de superfície, texto e borda. Cores semânticas, de modelo e de score permanecem no `:root` (não variam por tema).

**Rationale**: A infraestrutura já existe e funciona corretamente — `Sidebar.tsx` já seta `data-theme` e persiste em `localStorage`. O único gap é a ausência do bloco CSS para o tema claro. Essa abordagem zero-JavaScript é performática e evita flash de tema incorreto se o atributo for setado antes do primeiro paint.

**Alternatives considered**:
- CSS classes no `<body>` (`body.theme-light`) — funcionaria, mas `data-theme` já está implementado; mudar criaria retrabalho sem ganho.
- CSS-in-JS / styled-components para theming — fora do contexto; projeto usa CSS puro com custom properties.
- Variáveis separadas por arquivo (`tokens-light.css`) — fragmentaria o sistema de tokens; manutenção mais difícil.

---

## Decision 2: Valores do tema claro — paleta light técnica coerente com o dark

**Decision**: Derivar a paleta claro a partir da inversão semântica do dark, mantendo a identidade âmbar e as cores fixas. Valores concretos:

| Token | Dark (atual) | Light (proposto) |
|-------|-------------|-----------------|
| `--bg-0` | `#0B0D11` | `#F4F6F9` |
| `--bg-1` | `#11141A` | `#FFFFFF` |
| `--bg-2` | `#161A22` | `#F0F2F5` |
| `--bg-3` | `#1E232D` | `#E8EBF0` |
| `--bg-4` | `#262C38` | `#DDE1EA` |
| `--bg-hover` | `rgba(255,255,255,0.04)` | `rgba(0,0,0,0.04)` |
| `--bg-active` | `rgba(255,255,255,0.06)` | `rgba(0,0,0,0.06)` |
| `--border` | `#1F242E` | `#D1D5DE` |
| `--border-strong` | `#2A3140` | `#B8BDC9` |
| `--border-soft` | `rgba(255,255,255,0.04)` | `rgba(0,0,0,0.06)` |
| `--text-0` | `#E8ECF2` | `#0F1117` |
| `--text-1` | `#A8B0BD` | `#3D4554` |
| `--text-2` | `#6C7480` | `#5E6779` |
| `--text-3` | `#4A515C` | `#8A93A2` |
| Scrollbar thumb | `--bg-3` | `--bg-3` (adaptado) |

Cores que NÃO mudam (iguais em ambos os temas): `--accent`, `--accent-soft`, `--accent-line`, todas as cores semânticas (`--success`, `--warning`, `--critical`, `--info`, `--inprogress`), todas as cores de modelo, todas as cores de score.

**Rationale**: A paleta inverte a hierarquia de luminosidade (escuro-sobre-claro ↔ claro-sobre-escuro) mantendo os mesmos deltas de contraste entre os níveis. Cores semânticas e de identidade são fixas por design (Constituição §III, FR-005, FR-006).

**Alternatives considered**:
- Replicar exatamente o tema claro do protótipo de referência — o protótipo não define tema claro; a derivação acima é consistent com o sistema de tokens existente.
- Usar `prefers-color-scheme` media query como único mecanismo — a spec exige persistência via localStorage; `prefers-color-scheme` é apenas o fallback inicial (FR-004).

---

## Decision 3: Sidebar retrátil — CSS variable + React state + CSS transition

**Decision**: Introduzir uma nova CSS custom property `--sidebar-width-collapsed: 52px` e controlar a largura via React state + `data-sidebar-collapsed` no elemento `<aside>` (ou via classe CSS `sidebar--collapsed`). O layout `.app` usa `grid-template-columns: var(--sidebar-width) 1fr` — a abordagem mais limpa é mudar a variável CSS dinamicamente via `sidebar.style.setProperty` ou, melhor, usar uma classe CSS e sobrescrever a variável no seletor `[data-sidebar-collapsed]`.

Fluxo de dados:
1. `Sidebar.tsx` mantém estado `collapsed: boolean` (inicializado de `localStorage`).
2. Quando `collapsed = true`, o componente adiciona classe `.sidebar--collapsed` ao `<aside>`.
3. Em `tokens.css`, `.sidebar--collapsed` (ou `[data-collapsed="true"]`) redefine `--sidebar-width` para `52px` e oculta labels via `opacity: 0; width: 0; overflow: hidden`.
4. `App.tsx` precisa ser informado do estado para ajustar o `grid-template-columns` — solução: elevar o estado `collapsed` para o `App` ou usar a mesma CSS variable/classe no `<div class="app">`.

**Solução preferida para o layout**: Aplicar `data-sidebar-collapsed` no elemento raiz (`.app` div) ou no `<html>`, de forma que o grid se adapte via CSS sem prop-drilling excessivo. Alternativa: colocar a classe no `<aside>` e usar CSS `grid-template-columns` de forma que o grid pai observe a classe da sidebar via seletor `:has(.sidebar--collapsed)` (CSS nativo, suportado em todos os browsers modernos).

**Rationale**: `:has()` elimina a necessidade de elevar estado ao `App` para o grid. Estado de `collapsed` fica encapsulado no `Sidebar.tsx`. Semântica clara, zero prop-drilling.

**Alternatives considered**:
- Elevar `collapsed` ao `App` e passar como prop — funciona mas quebra encapsulamento da sidebar.
- Usar `ref` para setar `grid-template-columns` inline — imperativo; prefere-se CSS declarativo.
- Largura via `max-width + overflow: hidden` — mais frágil com animação; `width + transition` é mais confiável.

---

## Decision 4: Tooltip no modo colapsado — CSS puro (`:hover` + `::before`/`::after`) ou React portal

**Decision**: CSS puro usando `::after` com `content: attr(data-tooltip)` no `.nav-item`. Sem biblioteca de tooltip, sem portal React.

**Rationale**: Tooltips de navegação são simples (texto fixo, posição à direita do ícone). CSS puro é suficiente, performático e não adiciona dependência. O texto do tooltip é o mesmo `route.label` já existente.

**Alternatives considered**:
- Biblioteca de tooltip (Floating UI, Tippy.js) — overkill para este caso; adicionaria dependência.
- Portal React com estado — desnecessário para tooltips de hover simples sem posicionamento dinâmico complexo.

---

## Decision 5: Prevenção de FOUC (Flash Of Unstyled Content) no tema

**Decision**: O `Sidebar.tsx` já aplica o tema no `useEffect` — isso pode causar um flash leve porque o `useEffect` roda após o primeiro render. Para prevenir FOUC, adicionar um script inline em `index.html` antes do `<body>` que lê `localStorage` e seta `document.documentElement.dataset.theme` sincronamente antes da pintura.

```html
<script>
  (function(){
    var t = localStorage.getItem('cstk-theme');
    if (!t) t = window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
    document.documentElement.dataset.theme = t;
  })();
</script>
```

**Rationale**: Script síncrono no `<head>` é o padrão da indústria para theming sem flash. Leve (~100 bytes), sem dependência, cobre também o fallback `prefers-color-scheme` (FR-004).

**Alternatives considered**:
- `data-theme="dark"` hardcoded no HTML — não honra preferência salva.
- CSS `prefers-color-scheme` somente — não permite override manual persistido.
