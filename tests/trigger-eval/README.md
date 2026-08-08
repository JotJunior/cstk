# trigger-eval — harness de disparo de skills

Mede **se a `description` de cada skill dispara na hora certa** — e, mais
importante, **quando uma skill é confundida com outra** (matriz de confusão
entre clusters de overlap). Complementa o `tests/run.sh`, que cobre os
**scripts** POSIX mas nunca o *triggering* das skills.

Inspirado no loop de disparo do `skill-creator` da Anthropic (queries
should-trigger / should-not, melhor `description` escolhida por score em
held-out). Ver análise em CLAUDE.md / memória `reference_superpowers_benchmark`.

## Natureza: periódico, NÃO é gate de CI

Decidir disparo é **comportamento de modelo**, não script — então o runner
precisa de um LLM no loop (um Workflow). Roda **sob demanda / pré-release**,
não a cada push. O `tests/run.sh` continua sendo o gate determinístico.

## Como rodar

```sh
# 1. monta o payload (descriptions vivas + queries) — requer jq
sh tests/trigger-eval/collect.sh > /tmp/trigger-payload.json

# 2. roda o juiz (via Claude Code, tool Workflow):
#    Workflow({ scriptPath: "tests/trigger-eval/run.workflow.js",
#               args: <conteúdo de /tmp/trigger-payload.json> })
```

O runner devolve `{accuracy, byExpect, confusionPairs, misfires}`. O sinal
mais útil é `confusionPairs` (`esperado → escolhido`) e `misfires` (com a
justificativa do juiz) — é onde mora o problema de description.

## Formato do dado

Cada skill é dona das suas queries em `plugins/cstk/skills/<nome>/evals/triggers.jsonl`
(espelha a convenção `tests/test_<n>.sh`). Casos que **não** devem disparar
nada ficam em `tests/trigger-eval/negatives.jsonl`. Uma query por linha:

```json
{"query": "texto que o usuário digitaria", "expect": "<slug-da-skill|none>"}
```

`expect` é o ground-truth: o slug que **deveria** disparar, ou `none`.

## Princípio anti-circular (importante)

Não gere as queries parafraseando a `description` e depois teste a
`description` contra elas — isso mede a skill contra ela mesma e infla o
score. Regras:

- **Queries fundadas no PROPÓSITO** (o que um usuário real digitaria), com
  near-misses propositais nas fronteiras entre skills irmãs.
- O **juiz vê só as descriptions**; quem escreve a query conhece o propósito.
- O seed atual é **hand-authored** nos clusters de overlap conhecidos
  (`specify↔clarify`, `plan↔create-tasks↔execute-task`,
  `validate-documentation↔validate-docs-rendered↔analyze`, `bugfix↔e2e`,
  `advisor↔bugfix`, `review-task↔review-features`) + negativos. Cobertura das
  23 skills é incremental.

## Próximos passos

- Geração assistida de drafts para as skills ainda sem `evals/` (com revisão
  humana antes de confiar nos números — passo `eval_review` do skill-creator).
- Sweep multi-modelo (haiku/sonnet/opus): a Anthropic recomenda testar
  disparo nos três tiers. O runner aceita `model` por fase.
- Loop de otimização de `description`: quando um cluster tiver acurácia baixa,
  gerar variantes da description e escolher a melhor por score held-out.
