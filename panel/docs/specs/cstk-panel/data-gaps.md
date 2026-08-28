# data-gaps.md — Dados que o painel precisa mas a fonte não fornece

**Data:** 2026-05-25
**Origem:** auditoria card-a-card (`tasks-cards.md`) + varredura de marcadores no
servidor (`proxy`/`aproxima`/`indisponível`/`derivado`/`não tem`).
**Fonte atual:** `knowledge.db` (SQLite + FTS5, schema v2), índice **derivado e
read-only** das execuções `agente-00c` / `feature-00c`.

> Propósito: lista acionável do que os orquestradores precisariam **gravar na
> knowledge.db** (ou expor) para o painel deixar de usar mock/proxy/aproximação.
> Cada item indica: o que a UI quer · o que existe hoje · sugestão de instrumentação.

Legenda de prioridade: **P1** alto valor / **P2** médio / **P3** baixo ·
*by-design* = decisão consciente, não corrigir sem rever a constituição.

---

## P1 — Lacunas de alto valor

### 1. Latência humana real (Métricas · CARD-MT-06)
- **UI quer:** tempo real entre o disparo de um bloqueio humano e sua resposta.
- **Hoje:** **aproximação** `duracao_segundos / bloqueios_humanos_total`
  (`metrics.ts:170-171` — "timestamps de bloqueio não estão no schema v2").
- **Instrumentar:** por bloqueio, gravar `disparado_em` e `respondido_em` (ISO 8601).
  Latência = diff. Permite p50/p95 reais no histograma.
- **Tabela alvo:** `bloqueios` (+ colunas `disparado_em`, `respondido_em`).

### 2. Timestamp por task (Métricas · CARD-MT-03 série 14d)
- **UI quer:** série diária de test-pass-rate.
- **Hoje:** `tasks` não tem timestamp próprio; a série agrupa por
  `date(executions.iniciada_em)` (`metrics.ts:118`) — todas as tasks de uma
  execução caem no mesmo dia.
- **Instrumentar:** gravar `executed_at` (ou `concluded_at`) por task.
- **Tabela alvo:** `tasks` (+ coluna `executed_at`).

### 3. Título / identidade de task (Tarefas) — ✅ RESOLVIDO (schema v3, cstk ≥ 4.2.0)
- **UI quer:** título legível da tarefa.
- **~~Hoje~~ (v2):** `tasks` não tinha título; a UI usava `feature · onda`.
- **Resolvido:** o schema **v3** adicionou `tasks.titulo` (heading do `tasks.md`,
  via `secrets-filter`). O painel expõe `titulo` ponta-a-ponta e a UI o usa como
  identidade primária (fallback `feature · onda` em bases v2 ou título vazio).
  Ver `docs/specs/panel-schema-v3/`. `task_id` segue não instrumentado (a chave
  natural da ingestão é `wave + source_id`).

### 4. Timestamp por alerta — coluna "Quando" (Alertas · CARD-AL-02)
- **UI quer:** quando o alerta disparou (prototipo: coluna "Quando").
- **Hoje:** `alert_signals` **não tem timestamp próprio**
  (`cross.ts:124` — "usar executions.iniciada_em"). A UI mostra "Onda" no lugar.
- **Instrumentar:** gravar `disparado_em` por sinal de alerta.
- **Tabela alvo:** `alert_signals` (+ coluna `disparado_em`).

---

## P2 — Lacunas de médio valor

### 5. Mix de modelos *confirmado* (Visão Geral CARD-OV-05 · Métricas MT-05/07)
- **UI quer:** distribuição do modelo **efetivamente executado** (incl. fallback).
- **Hoje:** ✅ o mix **derivado da intenção** já é exibido (Overview + Métricas:
  donut total + empilhado por etapa), a partir de `decisions.escolha='model:%'`,
  rotulado "intenção do roteador · derivado · canônico: model-routing-report.sh"
  e `meta.approximate=true` *(D3 revisado 2026-05-25)*. **O que ainda falta** é a
  **confirmação pós-hoc**: a harness não retorna, por invocação, o modelo que de
  fato rodou (ex.: fallback silencioso quando o alvo está indisponível).
- **Instrumentar (para fechar o gap):** logar `modelo_confirmado` por onda/decisão
  (o modelo realmente usado, não só a sugestão do roteador). Aí o mix deixa de ser
  "intenção/derivado" e vira confirmado; pode-se remover o `approximate=true`.
- **Tabela alvo:** `decisions` (+ coluna `modelo_confirmado`) ou nova `model_usage`.

### 6. Clarify auto-resolution exato (Métricas)
- **UI quer:** % de decisões de clarify resolvidas autonomamente vs escaladas.
- **Hoje:** **estimativa** = decisões com `score>=2` em `etapa=clarify`;
  `meta.approximate=true` (`metrics.ts:202-203` — "não há dado exato").
- **Instrumentar:** marcar explicitamente cada decisão de clarify como
  `auto_resolvida` (bool) vs `escalada_humano`.
- **Tabela alvo:** `decisions` (+ coluna `auto_resolvida`) ou `bloqueios`.

### 7. Metadados de projeto: descrição e repo (Projetos · CARD-PRJ-01)
- **UI quer:** descrição curta e caminho/URL do repositório no card do projeto
  (o protótipo usa **mock**; mantido como mock por ora).
- **Hoje:** `ProjectRollup` não tem `description` nem `repo` (não rastreado).
- **Instrumentar:** gravar `description` e `repo` por projeto.
- **Tabela alvo:** nova `projects` (metadados) ou colunas em `executions`.

---

## P3 — Lacunas de baixo valor / cosméticas

### 8. Tamanho por tabela (Fonte de Dados · CARD-SC-02)
- **UI quer:** bytes por tabela (protótipo mostrava coluna "Tamanho").
- **Hoje:** só o **tamanho total** do arquivo (`fs.statSync`); por-tabela omitido.
- **Instrumentar:** opcional — usar `dbstat` (PRAGMA) no servidor para estimar
  bytes por tabela. Não exige mudança no orquestrador.

### 9. Severidade de alerta explícita (Alertas)
- **UI quer:** severidade (critical/warning/info).
- **Hoje:** **derivada** client-side de `valorConsumido/valorThreshold`
  (≥100% = critical, ≥80% = warning). Funciona, mas é heurística da UI.
- **Instrumentar (opcional):** gravar `severity` calculada na origem para
  consistência entre consumidores.
- **Tabela alvo:** `alert_signals` (+ coluna `severity`).

---

## Não-lacunas (decisões conscientes — *by-design*, não instrumentar)

- **Custo = "tool calls" (proxy), nunca $/tokens** — a harness não expõe tokens.
  Princípio III (Honestidade de Métrica). Rotulado como proxy em toda a UI.
- **Botões "árvore de decisões" / "abrir no recall"** — não são dados: são
  integrações externas (skill `decision-tree`, CLI `recall`). Mantidos
  **decorativos** no painel read-only (CARD-EX-02/FTD-03). Ação real exigiria um
  endpoint que invoque/baixe artefatos — fora do escopo read-only.
- **Detalhe de decisão inline (sem modal)** — CARD-EX-08: expand na linha já mostra
  contexto/justificativa/evidência; modal considerado redundante.
- **`knowledge.db` é índice derivado/best-effort** — reconstruível via
  `cstk --reindex`; a verdade transacional é o `state.json` de cada execução.

---

## Resumo para o orquestrador (agente-00c / feature-00c)

Colunas/campos sugeridos para futuras gravações na `knowledge.db`:

> **Schema v3 (cstk ≥ 4.2.0)** já entregou `tasks.titulo` (P1·#3 ✅) e o evento
> `recall_consulted` (métrica de consultas ao histórico). Demais itens abaixo
> seguem pendentes de instrumentação no cstk.

| Tabela | Coluna sugerida | Destrava |
|--------|-----------------|----------|
| `bloqueios` | `disparado_em`, `respondido_em` | Latência humana real (P1·#1) |
| `tasks` | `executed_at` | Série diária de pass-rate (P1·#2) |
| ~~`tasks` · `titulo`~~ | ✅ entregue em v3 | Identidade de task (P1·#3) |
| `alert_signals` | `disparado_em` | Coluna "Quando" (P1·#4) |
| `alert_signals` | `severity` | Severidade canônica (P3·#9) |
| `decisions` | `modelo_confirmado` | Mix de modelos real (P2·#5) |
| `decisions` | `auto_resolvida` | Clarify auto-resolution exato (P2·#6) |
| `projects` (nova) | `description`, `repo` | Metadados de projeto (P2·#7) |

Ao instrumentar qualquer item, o ajuste no painel é pequeno (já existe o card/coluna):
expor o campo no DTO + schema correspondente e remover a aproximação/mock.
