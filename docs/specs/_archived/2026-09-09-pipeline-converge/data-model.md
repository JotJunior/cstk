# Data Model: pipeline-converge

A feature nao introduz banco de dados nem schema persistente novo. As
"entidades" abaixo sao registros textuais em artefatos de arquivo e campos
aditivos no estado transacional ja existente.

## Entity: ConvergenceStatusRecord

Uma linha marcadora append-only em `docs/specs/<feature>/converge-report.md`.
Uma linha por invocacao da skill `converge` (gate ou avulsa) e uma linha por
aceite de risco. **A ultima linha do arquivo e o registro corrente.**

Formato literal (comentario HTML de linha unica):

```
<!-- converge-status: outcome=clean; provenance=gate; at=2026-08-21T12:00:00Z; actionable=0; tasks-digest=ab12cd34ef56 -->
```

| Campo | Tipo | Obrigatorio | Valores / formato | Notas |
|-------|------|-------------|-------------------|-------|
| `outcome` | enum | sim | `clean` \| `actionable` \| `risk-accepted` | conjunto fechado |
| `provenance` | enum | sim | `gate` \| `standalone` | FR-010; parametro explicito, nunca inferido |
| `at` | string | sim | ISO 8601 UTC (`%Y-%m-%dT%H:%M:%SZ`) | ordem cronologica = ordem de append |
| `actionable` | int | sim | `>= 0` | achados acionaveis da invocacao; `0` quando `outcome=clean`. **Decisao de definicao (fecha CHK002)**: achados classificados **so** como `unrequested` NAO contam nesta contagem nem impedem `outcome=clean` — `unrequested` e achado de revisao (SKILL.md ETAPA 6: "MUST virar tarefa `kind=revisar`", nunca "implementar"), distinto por natureza de `missing`/`partial`/`contradicts`, que sao os unicos tipos que compoem `actionable`. Uma invocacao com achados so `unrequested` registra `outcome=clean; actionable=0`, mesmo apendando fase de revisao ao `tasks.md` |
| `tasks-digest` | string | sim | 12 hex minusculos | digest do `tasks.md` no momento do registro (Decision 6) |
| `decision-id` | string | nao | `dec-NNN` | so em `outcome=risk-accepted` sob execucao autonoma |
| `note` | string | nao | texto livre sem `;` nem `-->` | justificativa curta do aceite de risco |

**Regras de integridade**:

- Append-only: registros anteriores nunca sao reescritos nem removidos.
- `outcome=clean` exige `actionable=0`; `outcome=actionable` exige
  `actionable >= 1`.
- `outcome=risk-accepted` exige `note` OU `decision-id` (nao pode ser aceite
  mudo).
- Campos com `;` ou `-->` no valor sao rejeitados (exit 2) — protegem o
  formato do marcador contra quebra.

**State transitions** (veredito de `converge-status.sh check`):

```
(sem arquivo)                                  -> exit 3  nunca convergiu
outcome=actionable                             -> exit 1  pendente
outcome=clean      + digest bate               -> exit 0  convergida
outcome=clean      + digest divergente         -> exit 1  stale (FR-003/FR-007)
outcome=risk-accepted + digest bate            -> exit 0  risco aceito
outcome=risk-accepted + digest divergente      -> exit 1  stale
```

O aceite de risco vale para o backlog **daquele** digest: mexeu no `tasks.md`
depois, o aceite caduca junto com o veredito limpo — o operador aceitou o
risco de um estado especifico, nao um passe livre permanente.

## Entity: PipelineStage (existente — alterada)

Lista ordenada em `_PL_STAGES_LIST`
(`plugins/cstk/skills/agente-00c-runtime/scripts/pipeline.sh:96`).

| Antes (10) | Depois (11) |
|-----------|-------------|
| briefing, constitution, specify, clarify, plan, checklist, create-tasks, execute-task, review-task, review-features | briefing, constitution, specify, clarify, plan, checklist, create-tasks, execute-task, **converge**, review-task, review-features |

Efeitos derivados, sem codigo adicional (todos iteram a mesma lista):

- `pipeline.sh stages` passa a imprimir 11 linhas.
- `pipeline.sh next-stage --current execute-task` passa a imprimir `converge`
  (antes: `review-task`) — e o que da lastro a US2-AS2.
- `pipeline.sh next-stage --current converge` imprime `review-task`.
- `pipeline.sh prev-stage --current review-task` imprime `converge`.
- `state-ondas.sh end --advance` (que resolve a proxima fase via
  `pipeline.sh next-stage`) passa a avancar `execute-task -> converge`
  atomicamente, sem mudanca no `state-ondas.sh`.
- A lista de `--mode roadmap` (`briefing constitution roadmap`) permanece
  literalmente inalterada.

## Entity: WaveStageRecord / SkillInvocation (existente — sem mudanca de schema)

Nao ha campo novo no `state.json`/`state.db`. A etapa `converge` e gravada
pelos mecanismos ja existentes:

- `state-ondas.sh end --add-etapa converge` — o validador aceita qualquer
  token `[A-Za-z0-9._-]` de ate 64 chars
  (`state-ondas.sh:842`), portanto `converge` ja e valido hoje, sem
  alteracao do script.
- `state-ondas.sh record-skill --skill converge --kind gate|skill` —
  proveniencia (FR-010) pelo mecanismo `--kind` ja existente.
- `state-decisions.sh register --etapa converge` — Decisoes da etapa,
  incluindo a de aceite de risco (Decision 8).

Consequencia de FR-006: a convergencia deixa de precisar do bloco especial
"Gate incondicional convergence" na prosa dos orquestradores e passa a ser
uma etapa como as demais no historico.
