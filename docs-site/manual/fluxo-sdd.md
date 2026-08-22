---
title: Fluxo SDD
---

# Fluxo Spec-Driven Development

O **Spec-Driven Development** (SDD) e o fluxo principal do toolkit:
transforma uma ideia em codigo passando por 11 etapas auditaveis, cada uma
materializada como uma skill independente. O `agente-00C` orquestra essas
etapas autonomamente; voce tambem pode rodar cada uma manualmente via slash
command.

## Diagrama do pipeline

```
   ideia
     |
     v
[1] briefing ----------> docs/briefing.md
     |                   (discovery por entrevista estruturada)
     v
[2] constitution ------> docs/constitution.md
     |                   (principios MUST imutaveis da feature/projeto)
     v
[3] specify -----------> docs/specs/<feature>/spec.md
     |                   (user stories, FRs, success criteria)
     v
[4] clarify -----------> spec.md (atualizada com Resolved Ambiguities)
     |                   (Q&A estruturado resolve ambiguidades)
     v
[5] plan --------------> docs/specs/<feature>/plan.md
     |                   (arquitetura, data model, contratos, research)
     v
[6] checklist ---------> docs/specs/<feature>/checklists/*.md
     |                   (quality gates por dominio: ux/api/security/...)
     v
[7] create-tasks ------> docs/specs/<feature>/tasks.md
     |                   (decomposicao em FASES com [C]/[A]/[M])
     v
[8] execute-task ------> codigo + testes + checkbox [x] em tasks.md
     |                   (1 tarefa por invocacao, com fluxo de 9 etapas)
     v
[9] converge -----------> gaps acionaveis apendados como nova fase de tasks
     |                   (reconcilia spec/plan/tasks contra o codigo real)
     v
[10] review-task ------> dashboard de progresso + proxima tarefa sugerida
     |
     v
[11] review-features --> relatorio de portfolio (so no agente-00C)
     |                   (sugere arquivar/abandonar/priorizar entre features)
     v
   pronto
```

`analyze` **nao** e uma etapa sequencial numerada — e um **cross-check
read-only lateral** (spec/plan/tasks/constitution), disponivel a qualquer
momento a partir de `create-tasks`, do mesmo jeito que o `CONTRIBUTING.md`
diagrama (`analyze -. read-only cross-check .-> specify`).

## Etapas em detalhe

### 1. [`briefing`](../skills/briefing/) — Discovery

Entrevista estruturada que captura visao, usuarios, restricoes, prioridades,
stack e qualidade. Saida: `docs/briefing.md` (projetos antigos usam o
caminho legado `docs/01-briefing-discovery/briefing.md`, ainda aceito por
todo o pipeline). Esse
documento alimenta TODAS as etapas seguintes — pular esta etapa significa
inventar premissas no meio do pipeline.

### 2. [`constitution`](../skills/constitution/) — Principios imutaveis

Lista de principios MUST (e.g. "Auditabilidade Total", "Blast Radius
Confinado") que governam a feature/projeto. Quando ha uma constitution
global (raiz) E uma feature-delta, a feature referencia a raiz com header
`Predecessor:` e adiciona um Sync Impact Report.

### 3. [`specify`](../skills/specify/) — User stories e FRs

Transforma a descricao livre em spec SDD: user stories em formato
"As a / I want / So that", FR-NNN (Functional Requirements), success
criteria mensuraveis. Esta e a base da auditabilidade — todo trabalho
posterior referencia FRs.

### 4. [`clarify`](../skills/clarify/) — Resolver ambiguidades

Roda em formato Q&A estruturado: o asker gera perguntas, o answerer
responde com score 0-3 (0 = pause humano, 3 = decide sem clarificar com
evidencia empirica). Cada resposta vira uma Decisao auditavel registrada
em `state.json` (no caso do `agente-00C`).

### 5. [`plan`](../skills/plan/) — Plano tecnico

Arquitetura, data model, contratos de API, decisoes de tecnologia. Esta
e a primeira etapa que pode introduzir tecnologias especificas — o
briefing e a spec ficam intencionalmente agnosticos.

### 6. [`checklist`](../skills/checklist/) — Quality gates

"Unit tests for English". Checklists por dominio (ux, api, security,
performance, a11y) validam a QUALIDADE DO REQUISITO antes de virar
codigo. Adia trabalho que ainda esta ambiguo.

### 7. [`create-tasks`](../skills/create-tasks/) — Backlog

Decomposicao em FASES numeradas, com criticidade `[C]` (critical),
`[A]` (alta), `[M]` (media). Inclui Matriz de Dependencias, Resumo
Quantitativo, Escopo Coberto e Escopo Excluido.

### 8. [`execute-task`](../skills/execute-task/) — Implementar

Uma tarefa por invocacao, com 9 etapas obrigatorias (analise, localizacao,
planejamento, implementacao, testes, validacao, lint, conclusao,
atualizacao). Marca `[x]` no `tasks.md` ao final — gate critico contra
drift documental.

### 9. [`converge`](../skills/converge/) — Reconciliar spec com codigo

Compara a intencao documentada (spec/plan/tasks) contra o estado ATUAL do
codigo nos paths declarados, classifica cada divergencia
(missing/partial/contradicts/unrequested) e apenda os gaps acionaveis como
nova fase de `tasks.md`. Roda ao final de `execute-task`, antes de
`review-task` — anti-drift entre o que foi pedido e o que foi de fato
implementado.

### 10. [`review-task`](../skills/review-task/) — Status + proxima tarefa

Dashboard de progresso (concluidas / pendentes / bloqueadas), proxima
tarefa sugerida com base em dependencias resolvidas, alerta sobre drift
entre `git diff` e checkboxes do `tasks.md`.

### 11. [`review-features`](../skills/review-features/) — Portfolio de features

So no `agente-00C` (fora do escopo do `feature-00c`, que cobre uma unica
feature). Relatorio de portfolio entre features do mesmo projeto, com
sugestoes de arquivar/abandonar/priorizar.

`analyze` (auditoria cross-artifact read-only de `spec.md`/`plan.md`/
`tasks.md`/`constitution.md`) nao entra nessa contagem — ver nota logo
apos o diagrama.

## Quando usar o agente-00C

Voce pode rodar as 11 etapas manualmente (via slash commands / skills)
ou delegar tudo ao `agente-00C` — um orquestrador autonomo que executa o
pipeline em **ondas**, persistindo estado em `state.json` e fazendo commit
local apos cada onda. Ideal para POCs/MVPs longos ou quando voce quer
rodar em background entre suspends de laptop. Ver
[`/agente-00c`](../commands/agente-00c.md).
