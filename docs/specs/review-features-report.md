# Relatorio Global de Features

**Data:** 2026-05-19
**Diretorio:** `docs/specs/`
**Features analisadas:** 8
**Gerado por:** skill `review-features` (onda-016 do agente-00c, exec `github-pages-cstk-manual`)

---

## Sumario executivo

O portfolio do toolkit `claude-ai-tips` (este repositorio) esta em estado
saudavel: **7 de 8 features estao 100% concluidas** e prontas para arquivar;
a unica feature ativa e exatamente o alvo desta execucao 00C
(`github-pages-cstk-manual`), em 68% com criticidade C pendente — todas
as 61 subtarefas restantes sao inerentemente humanas (GitHub UI, browser,
deploy real). A feature `agente-00c` aparece em 98% com criticidade A
pendente (3 subtarefas), mas isso e residual de execucoes anteriores e
nao bloqueia novas execucoes do orquestrador.

Nenhuma feature foi detectada como **ABANDONAR** (sem progresso ha 90+
dias) — todas tem `mtime_days = 0` porque foram tocadas no mesmo dia
desta execucao (sinal de `git clone` recente OU repositorio ativo). Nao
ha feature em estado **PRIORIZAR** (criticidade C com < 50% feito).

---

## Tabela comparativa

| Feature | Descricao | % Concluida | Criticidade Pendente | Sugestao |
|---------|-----------|-------------|----------------------|----------|
| `agente-00c` | Orquestrador autonomo da pipeline SDD do toolkit | 98% | A | CONTINUAR |
| `agente-00c-evolucao` | Evolucao do agente-00c (sem descricao explicita no spec.md) | 100% | - | ARQUIVAR |
| `constitution-amend-optional-deps` | Amend da constitution 1.0.0 para permitir deps opcionais nao-POSIX | 100% | - | ARQUIVAR |
| `cstk-cli` | CLI `cstk` que distribui skills do toolkit (substitui `cp -r`) | 100% | - | ARQUIVAR |
| `cstk-session` | Subcomando `cstk session` para sessoes paralelas via git worktree | 100% | - | ARQUIVAR |
| `fix-validate-stderr-noise` | Bugfix: validate-docs-rendered/scripts/validate.sh emitia ruido em stderr | 100% | - | ARQUIVAR |
| `github-pages-cstk-manual` | Site estatico para GitHub Pages — manual do cstk + docs de skills/agentes/comandos | **68%** | **C** | CONTINUAR |
| `shell-scripts-tests` | Suite de testes para scripts shell POSIX distribuidos pelas skills | 100% | - | ARQUIVAR |

### Resumo agregado

| Sugestao | Quantidade | Features |
|----------|-----------:|----------|
| ARQUIVAR (100% done) | 6 | `agente-00c-evolucao`, `constitution-amend-optional-deps`, `cstk-cli`, `cstk-session`, `fix-validate-stderr-noise`, `shell-scripts-tests` |
| CONTINUAR | 2 | `agente-00c` (98%, 3 pendentes A), `github-pages-cstk-manual` (68%, 61 pendentes C) |
| PRIORIZAR | 0 | — |
| ABANDONAR | 0 | — |
| INDEFINIDO | 0 | — |

---

## Destaques

### Quase prontas (push final)

- **`agente-00c`** — 98% concluida, 3 subtasks pendentes (criticidade A).
  Provavelmente itens residuais de polish/observabilidade. Acao sugerida:
  `/review-task` no `docs/specs/agente-00c/tasks.md` para identificar
  exatamente quais 3 itens faltam e decidir se vale fechar ou se sao
  "deixa pra proxima evolucao".

### Em andamento ativo (a feature-alvo desta execucao)

- **`github-pages-cstk-manual`** — 68% concluida (150/218 subtasks), 61
  pendentes + 7 em andamento, criticidade C pendente. **Esta e a feature
  desta execucao 00C** (16 ondas). Os 68% representam o trabalho
  automatizado que o agente-00c conseguiu executar autonomamente
  (briefing → constitution → spec → clarify → plan → checklist →
  tasks → ate FASE 8 do tasks.md). As 61 subtarefas pendentes sao
  inerentemente humanas:
  - **GitHub UI** (criar repo public, configurar Settings → Pages,
    adicionar secrets do GitHub Actions, configurar GITHUB_TOKEN scope)
  - **Browser interactions** (testes Lighthouse manuais, visual QA
    cross-browser, validacao de Mermaid renderizando ao vivo)
  - **Deploy real** (push para `gh-pages` branch real, validar URL
    `https://<user>.github.io/<repo>/`, configurar custom domain se
    aplicavel)

  Esse handoff esta documentado em
  `docs/specs/github-pages-cstk-manual/runbook-deploy.md` (passo-a-passo
  para o operador).

### Concluidas (arquivar — acao manual do operador)

6 features estao em 100% e sao candidatas a `docs/specs/_archived/`:

1. `agente-00c-evolucao` (63/63)
2. `constitution-amend-optional-deps` (18/18)
3. `cstk-cli` (180/180)
4. `cstk-session` (110/110)
5. `fix-validate-stderr-noise` (29/29)
6. `shell-scripts-tests` (113/113)

**IMPORTANTE:** esta skill e read-only. NAO movemos nada. O operador
decide se arquivar agora ou manter na pasta atual como referencia viva
(util quando ha bugs recorrentes que se beneficiam de consultar a spec
original).

### Provavelmente mortas (confirmar abandono)

Nenhuma. Todas as features tem `mtime_days = 0` (atividade recente).

### Stuck (bloqueadas)

Nenhuma feature tem subtasks com marca `[!]` (blocked).

---

## Caveats

### Risco: criticidade `A` em `agente-00c` apos 98%

Subtasks pendentes em criticidade A (e nao M) sinaliza que ha trabalho
nao-cosmetico ainda. Recomenda-se rodar `/review-task` na feature
`agente-00c` para inspecionar exatamente quais sao essas 3 subtasks
antes de assumir que sao polish.

### `mtime_days = 0` para TODAS as features

Sinal de que o checkout deste repo foi recente OU que houve atividade
hoje em todas as features. Em ambos os casos, a coluna `mtime_days` nao
e util para detectar abandono nesta rodada. Se duvida sobre staleness
real, usar:

```bash
git log -1 --format=%cd docs/specs/<feature>/tasks.md
```

### Trabalho restante na feature-alvo NAO e drift

As 61 subtasks pendentes em `github-pages-cstk-manual` foram registradas
desde o inicio como dependentes de operador (sao chamadas a `gh` CLI
para criar repos, configuracoes de UI no GitHub, validacoes via browser).
Conforme `dec-038` desta execucao (registrada em `state.json`), continuar
autonomamente apenas geraria bloqueios em loop sem progresso real. O
runbook-deploy.md cobre o handoff.

---

## Acoes recomendadas (ordenadas por prioridade)

1. **Executar `runbook-deploy.md` (operador, ~30 min)** — passos manuais
   para criar repo, ativar GitHub Pages e fazer o primeiro deploy do
   site `cstk-manual`. Path:
   `/Users/jot/Projects/_lab/Jot/misc/claude-ai-tips-github-pages/docs/specs/github-pages-cstk-manual/runbook-deploy.md`

2. **Validar `agente-00c` (98%)** — rodar
   `/review-task docs/specs/agente-00c/tasks.md` para inspecionar as 3
   subtasks pendentes (criticidade A) e decidir se fechar nesta sprint
   ou consolidar com proxima feature de evolucao.

3. **Arquivar 6 features 100%** (decisao do operador) — mover para
   `docs/specs/_archived/<feature>/` quando quiser limpar o portfolio
   ativo. Sugestao: deixar como esta enquanto refatorar para v2 das
   skills (specs viram referencia para `validate-documentation`).

---

## JSON (para integracoes)

```json
{"name":"agente-00c","pct_done":98,"criticality":"A","mtime_days":0,"suggestion":"CONTINUAR","total":253,"done":250,"pending":3,"in_progress":0,"blocked":0}
{"name":"agente-00c-evolucao","pct_done":100,"criticality":"-","mtime_days":0,"suggestion":"ARQUIVAR","total":63,"done":63,"pending":0,"in_progress":0,"blocked":0}
{"name":"constitution-amend-optional-deps","pct_done":100,"criticality":"-","mtime_days":0,"suggestion":"ARQUIVAR","total":18,"done":18,"pending":0,"in_progress":0,"blocked":0}
{"name":"cstk-cli","pct_done":100,"criticality":"-","mtime_days":0,"suggestion":"ARQUIVAR","total":180,"done":180,"pending":0,"in_progress":0,"blocked":0}
{"name":"cstk-session","pct_done":100,"criticality":"-","mtime_days":0,"suggestion":"ARQUIVAR","total":110,"done":110,"pending":0,"in_progress":0,"blocked":0}
{"name":"fix-validate-stderr-noise","pct_done":100,"criticality":"-","mtime_days":0,"suggestion":"ARQUIVAR","total":29,"done":29,"pending":0,"in_progress":0,"blocked":0}
{"name":"github-pages-cstk-manual","pct_done":68,"criticality":"C","mtime_days":0,"suggestion":"CONTINUAR","total":218,"done":150,"pending":61,"in_progress":7,"blocked":0}
{"name":"shell-scripts-tests","pct_done":100,"criticality":"-","mtime_days":0,"suggestion":"ARQUIVAR","total":113,"done":113,"pending":0,"in_progress":0,"blocked":0}
```
