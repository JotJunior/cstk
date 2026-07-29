# Data Model: budget-resume-wallclock

**N/A — sem entidade nova; schema de `state.json` inalterado.**

Esta feature nao introduz nenhuma entidade, tabela, campo ou transicao de
estado nova. Ela reordena duas operacoes ja existentes no runtime de
orquestracao (inicio de onda via `state-ondas.sh start` e checagem de
orcamento via `budget.sh check`).

Os campos ja existentes que participam do comportamento corrigido — e que
**permanecem com a mesma estrutura e semantica** — sao, apenas para
referencia (nao sao criados nem modificados por esta feature):

- `.budgets.current_wave_start` — timestamp ISO do inicio da onda corrente;
  gravado por `state-ondas.sh start`, lido por `budget.sh check`. Estrutura
  inalterada.
- `.budgets.wallclock_threshold_seconds` — limite de wallclock (default
  5400s). Inalterado.
- `.waves[-1].termination_reason` — motivo de encerramento da ultima onda;
  gravado por `state-ondas.sh end`. Inalterado.

A correcao atua na ORDEM em que essas operacoes sao invocadas pelo
documento do orquestrador de feature, nunca na forma dos dados.
