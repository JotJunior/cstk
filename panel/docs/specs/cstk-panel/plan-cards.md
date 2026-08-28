# plan-cards.md — Plano de correção dos cards (protótipo vs implementação)

**Data:** 2026-05-25
**Origem:** auditoria `tasks-cards.md` (this dir)
**Decisões do usuário:**
- Filtro de projeto (CARD-SHELL-08, já feito) → **fica como navegação**, sem reescopar todas as telas.
- Gráficos de Métricas/Incidentes → **restaurar fidelidade ao protótipo** (não manter grids numéricos).
- Modo de trabalho → **plano aprovado, executar na sequência A → B → E → C → D → F**.

Legenda de esforço: **P** pequeno · **M** médio · **G** grande · 🖥️ frontend · ⚙️ backend

## Dependências de backend confirmadas (2026-05-25)

- ✅ `ExecutionDTO` já tem `sugestoesSkillsTotal`, `issuesToolkitAbertas`, `stackSugerida` → EX-06 / FTD-02 são frontend puro.
- ✅ `/health` já expõe contagens de tabelas + frescor → tela Fonte de Dados quase toda client-side.
- ⚠️ `RetroDTO` existe como tipo, mas **não há rota nem query** → Retrospectivas (FTD-06) exige endpoint novo.
- ⚠️ `getTestPassRate` retorna agregado (`pass/fail/rate`), **não série diária** → área 14d (MT-03) exige query nova.

---

## Lote A — Filtros de tabela  ·  100% 🖥️  ·  risco baixo  ·  ✅ CONCLUÍDO (2026-05-25)

| Card | Trabalho | Esforço | Status |
|------|----------|---------|--------|
| CARD-PRJ-03 | Busca + select projeto + select status na tabela "Todas as features" (Projetos) | P | [x] |
| CARD-FT-02 | Mesmos filtros na lista Features | P | [x] |
| CARD-TK-04 | Select de projeto na tela Tarefas (já tem tabs de outcome) | P | [x] |

Implementação: `lib/features-filter.ts` (`filterFeatures`, `distinctProjects`, `STATUS_OPTIONS`)
+ `components/FeaturesFilterBar.tsx` (controlado), reusados em Projetos e Features;
Tarefas usa select inline. Typecheck/lint/180 testes OK.

---

## Lote B — Tela Fonte de Dados + Sidebar  ·  fecha 1 tela inteira  ·  ✅ CONCLUÍDO (2026-05-25)

| Card | Trabalho | Esforço | Status |
|------|----------|---------|--------|
| CARD-SC-01/02 | Nova `screens/Source.tsx` + rota `/source` (consome `/health`) | M 🖥️ | [x] |
| CARD-SHELL-04 | Link "fonte de dados" na Sidebar | P 🖥️ | [x] |
| CARD-SHELL-03 | Fiar `freshness` + `alertCount` no `<Sidebar/>` (App.tsx) | P 🖥️ | [x] |
| CARD-SHELL-01 | Versão no brand-tag | P 🖥️ | [x] |
| CARD-SHELL-05 | Toggle de tema (sun/moon) — presente, `data-theme`, "decorativo" | P 🖥️ | [x] |
| backend | Expandido `/health` com `path`, `sizeBytes` + 11 contagens (bloqueios/skills/retros/fts_*) | P ⚙️ | [x] |

Implementação: `useHealth` + `HealthDataSchema` local (não toca parity tests).
Typecheck (3 workspaces) / 180 testes OK. Aviso de lint `ApiEnvelopeSchema unused` é pré-existente.

---

## Lote E — Restaurar gráficos  ·  decisão: fidelidade  ·  ✅ CONCLUÍDO (2026-05-25)

Criadas 3 primitivas em `charts.tsx`: **StackedBars**, **Histogram**, **ScatterChart** (+ `Legend`).

| Card | Trabalho | Esforço | Status |
|------|----------|---------|--------|
| CARD-MT-06 | Histograma de latência humana (dado disponível) | M 🖥️ | [x] |
| CARD-MT-08 | Scatter profundidade × subagentes (dado disponível) | M 🖥️ | [x] |
| CARD-IN-02 | StackedBars "Incidentes ao longo do tempo" (agregar `/events` por dia/tipo) | M 🖥️ | [x] |
| CARD-MT-03 | Área 14d test pass rate → query nova `/metrics/test-pass-rate-series` + AreaChart | M ⚙️ + P 🖥️ | [x] |

Mantidos 🔵 (não restaurar): CARD-MT-05/07 mix de modelos = "indisponível nesta fonte" (dec-020 / Princípio IV).
Typecheck (3 workspaces) / lint / 180 testes OK. **Pendência leve:** o novo endpoint
`test-pass-rate-series` não tem teste dedicado (espelha `getCostOverTime`, que é testado).

---

## Lote C — Detalhe de Execução  ·  layout 2 colunas  ·  ✅ CONCLUÍDO (2026-05-25)

| Card | Trabalho | Esforço | Status |
|------|----------|---------|--------|
| CARD-EX-04 | Card lateral "Decisões por score" → query+rota `/executions/:id/score-distribution` | M 🖥️+⚙️ | [x] |
| CARD-EX-06 | Card lateral "Sugestões/Issues" (DTO já tem campos) | P 🖥️ | [x] |
| CARD-EX-05 | **Decidido: card lateral.** Skills voltou a card (BarH); aba removida | P 🖥️ | [x] |
| CARD-EX-02 | **Decidido: decorativos.** Botões `disabled` + tooltip | P 🖥️ | [x] |
| — | Layout `.exec-grid` (gantt 1fr + coluna 280px, responsivo) | M 🖥️ | [x] |

Typecheck (3 workspaces) / 180 testes OK.

---

## Lote D — Detalhe de Feature  ·  ✅ CONCLUÍDO (2026-05-25)

| Card | Trabalho | Esforço | Status |
|------|----------|---------|--------|
| CARD-FTD-02 | Chips de stack (lê `stackSugerida` da 1ª execução com stack) | P 🖥️ | [x] |
| CARD-FTD-03 | Botões de header ("Ver execução" navega; "Árvore" decorativo) | P 🖥️ | [x] |
| CARD-FTD-06 | Card Retrospectivas → query `retros.ts` + embutido em `/features/:p/:f` | M ⚙️ + P 🖥️ | [x] |

Typecheck (3 workspaces) / 180 testes OK.

---

## Lote F — Polimento e decisões  ·  ✅ CONCLUÍDO (2026-05-25)

| Card | Trabalho | Esforço | Status |
|------|----------|---------|--------|
| CARD-AL-02 | Filtro projeto → select (`useProjects`); coluna "Onda" aceita (DTO sem timestamp) | P 🖥️ | [x] |
| CARD-EX-08 | **Decidido: manter expand inline** (modal redundante) — divergência aceita | — | [x] |
| CARD-PRJ-01 | **Decidido: manter mock**; lacuna registrada em `data-gaps.md` (P2·#7) | — | [x] |

## Resultado final

Todos os 6 lotes concluídos. Placar: ✅ 45 · ⚠️ 0 · ❌ 0 · 🔵 8 (decisões conscientes).
Build de produção OK (shared-types + server + web). 180 testes verdes.
Lacunas de dados (mock/proxy/aproximação) catalogadas em **`data-gaps.md`** para
instrumentação futura no orquestrador.

---

## Decisões pendentes (resolver ao chegar nos lotes C/D/F)

1. **CARD-EX-05** — Skills: card lateral (fiel) vs aba (mais informação)?
2. **CARD-EX-02 / FTD-03** — botões "árvore de decisões" / "abrir no recall": decorativo, link externo ou ação real?
3. **CARD-FTD-06 / CARD-MT-03** — confirmar trabalho de backend (endpoint de retros + série diária de pass-rate).

## Convenção de progresso

Ao concluir cada card: marcar `[x]` aqui **e** atualizar o status correspondente em `tasks-cards.md`.
Rodar `npm run typecheck`, `npm run lint` e `npm test` ao fim de cada lote.
