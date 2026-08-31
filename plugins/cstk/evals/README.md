# evals/ — suite nativa `claude plugin eval`

**Conteudo derivado.** Todo `case.yaml` aqui e GERADO a partir das queries que
cada skill mantem em `plugins/cstk/skills/<n>/evals/triggers.jsonl` (mais os
casos should-not-trigger de `tests/trigger-eval/negatives.jsonl`). Nao edite
nada deste diretorio a mao — edite o `.jsonl` da skill e regenere:

```sh
sh tests/trigger-eval/gen-eval-cases.sh          # (re)gera
sh tests/trigger-eval/gen-eval-cases.sh --check  # exit 1 se fora de sync
```

## Como rodar

```sh
claude plugin eval plugins/cstk --ablation none            # suite inteira
claude plugin eval plugins/cstk --ablation none --tag specify
claude plugin eval plugins/cstk --ablation none --case 'none-*'
```

`--ablation none` **importa**: sob o default (`with-without`) um grader
`tool_used: Skill` e tratado como indicador de "o plugin disparou" e sai do
score — que e justamente o que estes cases medem. Com `--ablation none` o
grader volta a ser pontuado.

`plugin eval` esta em **early access**; sem a habilitacao na conta o comando
responde `plugin eval is currently in early access` e nao roda nada.

## O que cada case mede

| Grupo | Grader | Passa quando |
|-------|--------|--------------|
| `<skill>/NNN` | `tool_used` `tool: Skill`, `input_match: <skill>`, `min: 1` | a skill esperada disparou |
| `none/NNN` | `tool_used` `tool: Skill`, `max: 0` | nenhuma skill disparou |

`runs: 1` por case (110 cases). Suba com `--runs N` quando quiser sinal
estatistico em vez de smoke.

## Relacao com `tests/trigger-eval/`

O harness proprio (`collect.sh` + `run.workflow.js`) continua existindo e
mede outra coisa: a **matriz de confusao** entre skills (qual skill foi
escolhida no lugar da esperada). Esta suite nativa mede disparo binario por
case e produz o relatorio/JSON oficial. Os dois consomem o MESMO `.jsonl`.
