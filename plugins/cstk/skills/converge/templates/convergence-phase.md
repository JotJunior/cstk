<!--
  Template da fase de convergencia apendada ao final de um tasks.md
  existente pela skill `converge` (ETAPA 6 do SKILL.md desta skill).

  Uso: preencha UMA copia deste bloco por execucao que produziu >=1 Gap
  acionavel (missing/partial/contradicts) ou de revisao (unrequested).
  O bloco inteiro e o "phase-file" passado para:

    scripts/converge-tasks.sh append-phase --tasks <tasks.md> --phase-file <este-arquivo-preenchido>

  Reusa o formato canonico de `create-tasks/templates/tasks.md`
  (numeracao hierarquica, checkboxes, tag de criticidade) — NAO reinventa
  um formato novo. Diferenca: aqui e so UMA fase (a que sera apendada),
  nunca o cabecalho/legenda do documento inteiro (isso ja existe no
  tasks.md pre-existente, append-only nunca o toca — FR-009).

  Mapeamento severity -> criticality_tag (data-model.md §ConvergenceTask,
  tarefa 3.2.2):
    CRITICAL -> [C]
    HIGH     -> [C]
    MEDIUM   -> [A]
    LOW      -> [M]

  {N}          = numero da fase, de `converge-tasks.sh next-phase`
  {N}.{M}      = id de cada tarefa, de `next-task-id.sh {N} <phase-file-em-construcao>`
                 chamado ITERATIVAMENTE (1a tarefa -> {N}.1, 2a -> {N}.2, ...)
  {gap_key}    = de `converge-tasks.sh gap-key --path <p> --type <t> --origin <o>`
-->

## FASE {N} - Convergência

> Fase gerada automaticamente pela skill `converge` (reconciliação
> spec-vs-código). Cada tarefa abaixo corresponde a um achado (`Gap`)
> entre o que `spec.md`/`plan.md`/`tasks.md` descreveram e o estado
> presente do código. Tarefas sem o prefixo `[Revisar]` são acionáveis
> (`missing`/`partial`/`contradicts`); tarefas com `[Revisar]` são item de
> revisão (`unrequested`, FR-013) — nunca "implementar", o código já
> existe. Append-only: esta fase nunca reescreve fases/tarefas anteriores
> do arquivo (FR-009).

### {N}.{M} {Nome curto do achado, sem o prefixo "[Revisar]" quando acionável} `[{C|A|M}]`

Ref: {origin} · tipo: `{missing|partial|contradicts|unrequested}` · severidade: `{CRITICAL|HIGH|MEDIUM|LOW}`

{Descrição do achado — o que a intenção documentada (origin) esperava vs.
o que o código presente em `{path}` de fato faz. Cite o path exato.}

- [ ] {N}.{M}.1 {Ação: para acionável, "Implementar/corrigir `{path}` conforme `{origin}`"; para `unrequested`, "Revisar `{path}`: decidir manter, documentar retroativamente ou remover"}

<!-- converge-key: {gap_key} -->

### {N}.{M+1} [Revisar] {Nome curto do achado unrequested} `[M]`

Ref: {origin} · tipo: `unrequested` · severidade: `LOW`

{Descrição: capacidade presente em `{path}` sem pedido correspondente em
nenhuma story/requisito da spec, e não justificável como suporte
incidental (config, boilerplate, wiring).}

- [ ] {N}.{M+1}.1 Revisar `{path}`: decidir manter, documentar retroativamente ou remover

<!-- converge-key: {gap_key} -->

<!--
  Repita um bloco "### {N}.{M} ..." por Gap NOVO (gap-key inédita —
  ETAPA 6 do SKILL.md ja filtrou os ja registrados via `existing-keys`).
  Nunca gere um bloco para uma gap-key que ja existe em `tasks.md`
  (idempotencia, FR-011/FR-012) e nunca gere a fase inteira se sobrou
  ZERO Gap novo (FR-010 — nunca apendar fase vazia).
-->
