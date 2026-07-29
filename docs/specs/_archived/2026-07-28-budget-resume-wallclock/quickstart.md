# Quickstart: budget-resume-wallclock

Cenarios de teste que validam a correcao end-to-end. Dois fluxos criticos:
o defeito corrigido (retomada nao gera breach falso) e o comportamento
preservado (breach real dentro de onda aberta ainda dispara). Ambos
mapeados para o harness POSIX (`tests/test_budget.sh`,
`tests/test_state-ondas.sh`).

> Roundtrip End-to-End backend↔frontend: **N/A** — feature single-layer
> (runtime shell + doc de orquestrador), sem borda de serializacao.

## Scenario 1: BUG corrigido — retomada com onda anterior fechada nao gera falso breach

Reproduz o defeito: na retomada, o `current_wave_start` da onda anterior
JA FECHADA persiste; se o delta desde entao ultrapassa o threshold, o
`budget.sh check` chamado ANTES do `start` da nova onda dispara breach de
wallclock que nunca ocorreu.

1. Preparar um `state.json` de execucao `feature-00c` com a ultima onda
   ENCERRADA (`termination_reason != null`, `finished_at` preenchido) e
   `.budgets.current_wave_start` apontando para um instante cujo delta ate
   agora **excede** `.budgets.wallclock_threshold_seconds` (ex: threshold
   5400s, `current_wave_start` ha 2h).
2. Simular a retomada seguindo a ordem CORRIGIDA do Loop: primeiro
   `state-ondas.sh start --state-dir <SD>` (inicia a nova onda e regrava
   `current_wave_start = now`), **depois** `budget.sh check --state-dir <SD>`.
3. **Expected**: `budget.sh check` retorna exit 0 (sem breach) — o wallclock
   e medido a partir do `current_wave_start` recem-gravado pelo `start`, nao
   do timestamp herdado da onda anterior. A retomada avanca para a proxima
   fase sem reportar estouro de orcamento (SC-001).

### Guard de regressao (ordem antiga)

4. Com o MESMO `state.json` do passo 1, chamar `budget.sh check` **sem** o
   `start` antes (ordem antiga do Loop).
5. **Expected**: o check dispara breach `wallclock` (linha `wallclock\t<wc>\t<max>`
   com `wc >= max`, exit 1). Este passo documenta o comportamento defeituoso
   que a reordenacao elimina — util como teste de nao-regressao para provar
   que a diferenca esta na ORDEM, nao no helper.

## Scenario 2: PRESERVADO — onda aberta que excede o limite ainda dispara breach

Garante que a correcao NAO enfraquece a deteccao de estouro genuino (FR-002 / SC-002).

1. Preparar um `state.json` com uma onda ABERTA (apos `state-ondas.sh start`,
   sem `end`) cujo `.budgets.current_wave_start` esteja ha mais tempo que
   `.budgets.wallclock_threshold_seconds` (ex: threshold 5400s,
   `current_wave_start` ha 2h — simulando uma onda que de fato consumiu
   tempo demais).
2. Chamar `budget.sh check --state-dir <SD>`.
3. **Expected**: o check dispara breach `wallclock` (exit 1, linha
   `wallclock\t<wc>\t<max>` com `wc >= max`). A onda em andamento e
   encerrada e o estouro e reportado normalmente — comportamento identico
   ao de hoje (SC-002).

## Scenario 3: Edge — retomada imediata apos encerramento (delta ~zero)

1. Preparar `state.json` com a ultima onda encerrada ha poucos segundos.
2. Executar a ordem corrigida: `state-ondas.sh start` seguido de `budget.sh check`.
3. **Expected**: nova onda inicia, `budget.sh check` retorna exit 0. Sem
   diferenca de comportamento em relacao a uma retomada tardia — o orcamento
   sempre e avaliado a partir do novo inicio (Edge Cases da spec).

## Cobertura no harness

| Cenario | Arquivo de teste | O que exercita |
|---------|------------------|----------------|
| 1 (BUG corrigido + guard) | `tests/test_state-ondas.sh` + `tests/test_budget.sh` | ordem `start`→`check` nao gera falso breach; ordem antiga (check sozinho) ainda estouraria |
| 2 (breach real preservado) | `tests/test_budget.sh` | onda aberta com wallclock >= threshold dispara breach (exit 1) |
| 3 (edge delta ~zero) | `tests/test_state-ondas.sh` | start regrava `current_wave_start`; check subsequente exit 0 |

> Rodar: `./tests/run.sh test_budget` e `./tests/run.sh test_state-ondas`
> (ver `tests/README.md`). O gate de release roda `./tests/run.sh` inteiro.
