# UX + Requirements Checklist: Tema Claro e Menu Retrátil

**Purpose**: Validar qualidade, completude e mensurabilidade dos requisitos de
UX para as três entregas: tema claro funcional, switch operacional e sidebar
retrátil.
**Created**: 2026-05-28
**Feature**: [spec.md](../spec.md) | [plan.md](../plan.md)

---

## Completude de Requisitos — Tema Claro

- [x] CHK001 — Todos os tokens CSS de superfície, texto e borda são listados
  como escopo do tema claro? [Completude, Spec §FR-001]
  > Spec FR-001 lista: variáveis de superfície, texto, borda, hover, active
  > e scrollbar. plan.md §Decision 2 tabela completa com 13 variáveis. Coberto. {auto}

- [x] CHK002 — O requisito de "efeito visual imediato" (FR-002) é quantificado
  com um critério mensurável? [Clareza, Spec §SC-002]
  > SC-002 quantifica: "menos de 100 ms, sem reload". Critério verificável. {auto}

- [x] CHK003 — O requisito de persistência de tema (FR-003) especifica o
  momento em que o tema deve ser aplicado (antes vs. após a primeira pintura)?
  [Clareza, Spec §FR-003]
  > FR-003 especifica "antes da primeira pintura (sem flash)". plan.md Dec 5
  > mapeia para script inline anti-FOUC. Coberto. {auto}

- [x] CHK004 — O fallback de tema quando `localStorage` está bloqueado está
  definido com comportamento específico (sem ambiguidade entre "dark padrão" e
  "system preference")? [Clareza, Spec §FR-004, Edge Cases]
  > FR-004 especifica `prefers-color-scheme` como fallback. Edge cases confirmam
  > "sem lançar exceção". plan.md Dec 5 formaliza try/catch. Coberto. {auto}

- [x] CHK005 — Estão definidos quais tokens de cor são INVARIANTES por tema
  (não mudam) vs. variáveis por tema? [Completude, Spec §FR-005, FR-006]
  > FR-005 cobre cores semânticas e de modelo (fixas). FR-006 cobre score (fixo).
  > plan.md §Decision 2 reforça na tabela. Coberto. {auto}

---

## Completude de Requisitos — Sidebar Retrátil

- [x] CHK006 — Os dois estados da sidebar (expandido/colapsado) estão definidos
  com dimensões concretas? [Clareza, Spec §FR-007, SC-004]
  > FR-007: expandido ~232 px, colapsado ~52 px. SC-004 precisa "máximo 56 px".
  > Leve inconsistência (~52 vs ≤56): ambas as fontes apontam para o mesmo intervalo
  > aceitável. Coberto. {auto}

- [x] CHK007 — O requisito de animação (FR-008) especifica tipo e duração da
  transição? [Clareza, Spec §FR-008, plan.md §Phase 1]
  > plan.md §tokens.css colapsado especifica `transition: width 0.2s ease`.
  > Spec FR-008 diz "animada suavemente" — qualificação técnica está no plan.
  > Verificável. {auto}

- [x] CHK008 — O comportamento do tooltip no modo colapsado está definido com
  especificidade suficiente (trigger, conteúdo, posição)? [Clareza, Spec §FR-009]
  > FR-009: trigger = cursor sobre ícone, conteúdo = nome da seção.
  > plan.md §Tooltip: posição = à direita do ícone. Coberto. {auto}

- [x] CHK009 — O indicador de item ativo (barra âmbar) está explicitamente
  requerido para o modo colapsado? [Completude, Spec §FR-010]
  > FR-010 e US2/SC5 explicitam: "barra lateral âmbar permanece visível
  > no modo colapsado". Coberto. {auto}

- [x] CHK010 — A persistência do estado de colapso está definida com o mesmo
  nível de detalhe que a persistência do tema? [Consistência, Spec §FR-011, FR-003]
  > FR-011 replica o padrão de FR-003 ("da mesma forma"). Key Entities define a
  > chave `cstk-sidebar-collapsed`. Consistente. {auto}

- [x] CHK011 — O requisito de adaptação dinâmica do layout (FR-012) é verificável
  sem ambiguidade (área de conteúdo expande ou muda apenas a coluna CSS)? [Clareza, Spec §FR-012]
  > plan.md §Decision 3 especifica: CSS `:has(.sidebar--collapsed)` altera
  > `grid-template-columns` dinamicamente. Verificável. {auto}

- [x] CHK012 — O botão de colapso/expansão está requerido para ambos os estados
  (FR-013), com acessibilidade mínima definida? [Completude, Spec §FR-013]
  > FR-013: visível e acionável em ambos os estados. plan.md menciona ARIA
  > no Sidebar.tsx. Coberto como completude; detalhe de ARIA é affordance de
  > implementação. {auto}

- [x] CHK013 — O toggle de tema no modo colapsado está requerido como
  acessível (FR-014) com fallback se o rodapé textual for ocultado? [Completude, Spec §FR-014]
  > FR-014: "mínimo: ícone clicável, com tooltip se necessário". Edge case
  > confirma. Coberto. {auto}

---

## Consistência de Requisitos

- [x] CHK014 — Os requisitos de persistência (FR-003 para tema, FR-011 para
  colapso) usam o mesmo mecanismo de armazenamento com chaves distintas? [Consistência, Spec §Key Entities]
  > Key Entities: `cstk-theme` e `cstk-sidebar-collapsed`. Mesmo mecanismo
  > (localStorage), chaves distintas. Consistente. {auto}

- [x] CHK015 — O requisito FR-015 (coexistência tema claro + colapsado) não
  conflita com nenhum dos outros FRs? [Consistência, Spec §FR-015]
  > FR-015 é um meta-requisito de não-conflito. Nenhum FR de tema interfere
  > na lógica de colapso (ambos são orthogonais: CSS class vs. data-attribute).
  > Consistente. {auto}

- [x] CHK016 — A spec diferencia claramente o que é "decorativo" (antes) do
  que é "funcional" (após a feature), evitando regressão? [Clareza, Spec §Contexto]
  > Seção Contexto declara explicitamente que o switch atual "é decorativo".
  > A feature torna funcional. A demarcação evita confusão sobre estado anterior. {auto}

---

## Qualidade dos Success Criteria

- [x] CHK017 — Todos os Success Criteria são technology-agnostic e mensuráveis
  sem conhecer detalhes de implementação? [Mensurabilidade, Spec §SC-001 a SC-007]
  > SC-001 (100% das variáveis definidas), SC-002 (<100ms), SC-003 (sem flash),
  > SC-004 (≤56px, 0 labels), SC-005 (10/10 ícones clicáveis), SC-006 (persiste),
  > SC-007 (persiste). Todos mensuráveis e verificáveis sem conhecer o código. {auto}

- [x] CHK018 — Existe pelo menos um SC para cada FR crítico (MUST)? [Completude, Spec §Requirements × §Success Criteria]
  > FR-001 → SC-001; FR-002 → SC-002; FR-003 → SC-007; FR-007 → SC-004;
  > FR-009+FR-010 → SC-005; FR-011 → SC-006. FR-004 (SHOULD) sem SC próprio,
  > mas coberto pelo fallback no Edge Cases. Cobertura adequada. {auto}

- [x] CHK019 — O SC-002 (< 100ms) é realista para uma troca de `data-theme`
  CSS? [Clareza, Spec §SC-002]
  > Troca de `data-attribute` + CSS custom properties reavalia apenas os tokens,
  > não força layout reflow. 100ms é conservador e verificável via DevTools
  > Performance tab. Critério correto. {auto}

---

## Cobertura de Edge Cases

- [x] CHK020 — O edge case de `localStorage` bloqueado está mapeado nos FRs? [Cobertura, Spec §Edge Cases → FR-004]
  > Edge Cases §1 define o comportamento; FR-004 formaliza o SHOULD. Mapeado. {auto}

- [x] CHK021 — O edge case de coexistência (colapsado + tema claro) tem
  requisito formal correspondente? [Cobertura, Spec §Edge Cases → FR-015]
  > FR-015 existe exatamente para esse caso. Mapeado. {auto}

- [x] CHK022 — O edge case de resize de janela com sidebar colapsada tem
  cobertura em US ou FR? [Cobertura, Spec §Edge Cases, US2 §SC7]
  > US2/Acceptance Scenario 7 e o Edge Cases §3 cobrem o comportamento de
  > resize. FR-012 cobre a expansão dinâmica do layout. Mapeado. {auto}

- [x] CHK023 — O edge case do toggle de tema com sidebar colapsada foi
  transferido para FR-014 com critério verificável? [Cobertura, Spec §Edge Cases §4 → FR-014]
  > Edge Cases §4 descreve o requisito; FR-014 o formaliza com "mínimo: ícone
  > clicável". Mapeado. {auto}

---

## Requisitos Não-Funcionais e Acessibilidade

- [ ] CHK024 — Os requisitos de acessibilidade (ARIA labels, navegação por
  teclado) para o botão de colapso/expansão da sidebar estão definidos na spec?
  [Gap, Spec §FR-013]
  > FR-013 exige que o botão seja "visível e acionável" mas não define
  > `aria-label`, `aria-expanded` ou comportamento de foco por teclado. plan.md
  > menciona "ARIA" no Sidebar.tsx sem detalhar. **Gap de requisito**: acessibilidade
  > de teclado e leitores de tela para o botão de colapso não está especificada. {auto}

- [ ] CHK025 — O requisito de contraste mínimo do tema claro segue algum padrão
  mensurável (ex: WCAG 2.1 AA — razão 4.5:1 para texto normal)? [Gap, Spec §SC-001, US3]
  > SC-001 diz "sem contraste insuficiente" e US3 diz "contraste suficiente",
  > mas nenhuma referência a um padrão (WCAG AA, ratio específico). **Gap de
  > clareza**: o critério de contraste "suficiente" não é verificável sem um
  > standard explícito. {auto}

- [x] CHK026 — O requisito de animação suave (FR-008) considera o
  `prefers-reduced-motion` do usuário? [Cobertura, Gap menor]
  > Nem a spec nem o plan mencionam `prefers-reduced-motion`. Para uma feature
  > de dashboard técnico interno (single-user, conforme briefing), omissão é
  > aceitável sem blocker. Registrado como aviso menor — não é Gap bloqueante. {auto}

---

## Dependências e Premissas

- [x] CHK027 — A premissa de que o mecanismo `data-theme` + localStorage
  já existe e funciona está documentada na spec? [Completude, Spec §Contexto]
  > Seção Contexto descreve explicitamente o estado atual do código. Premissa
  > documentada. {auto}

- [x] CHK028 — A premissa de que `CSS :has()` está disponível nos browsers-alvo
  está implícita ou explícita? [Assumption]
  > plan.md §Decision 3 usa `:has()` sem mencionar suporte de browser. `:has()`
  > tem suporte universal em browsers modernos (Chrome 105+, Firefox 121+, Safari
  > 15.4+) — razoável para uso local single-user. Premissa implícita aceitável. {auto}

- [x] CHK029 — A feature declara explicitamente zero impacto no back-end e na
  API? [Completude, Spec §Decisões de infraestrutura]
  > Seção "Decisões de infraestrutura: N/A" + plan.md §Convencoes de Borda N/A
  > confirmam. Declaração explícita presente. {auto}

---

## Notes

- Items `{auto}` foram resolvidos contra spec.md + plan.md com citação da evidência.
- Items `{humano}` ficam `[ ]` aguardando decisão.
- **CHK024** e **CHK025** ficaram `[ ]` com marcador `[Gap]` — ver seção de follow-up abaixo.

---

## Resolução

| Tipo | Quantidade |
|------|------------|
| `[x]` auto-resolvidos com evidência | 27 |
| `[ ]` humano aguardando decisão | 0 |
| `[Gap]` abertos | 2 (CHK024, CHK025) |

---

## Follow-up dos Gaps

| CHK | Marcador | Destino |
|-----|----------|---------|
| CHK024 | `[Gap]` — ARIA/teclado para botão de colapso não especificado | Adicionar FR-016 na spec ou task de requisito: "definir aria-label, aria-expanded e comportamento de foco para o botão de colapso" |
| CHK025 | `[Gap]` — critério de contraste não referencia padrão mensurável | Adicionar nota ao SC-001: "contraste mínimo WCAG 2.1 AA (4.5:1 texto normal, 3:1 texto grande)" ou registrar como premissa aceitável para uso interno |
