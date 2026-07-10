# Research: budget-resume-wallclock

Documento produzido no Phase 0 do `/plan`. A spec entrou em `plan` sem
`NEEDS CLARIFICATION` pendente (bugfix de runtime com causa raiz confirmada
por leitura de codigo). A unica decisao de design em aberto era **onde**
aplicar a correcao. Todas as alternativas abaixo estao aterradas em leitura
real dos arquivos citados (Principio VI).

## Decision 1: Onde corrigir o falso breach de wallclock na retomada

**Decision**: **Reordenar o "Loop principal de uma onda"** em
`global/agents/agente-00c-feature-orchestrator.md` para que
`state-ondas.sh start` (inicio de onda, que grava
`.budgets.current_wave_start = now`) seja executado **antes** do primeiro
`budget.sh check` no fluxo de retomada — alinhando o orquestrador de feature
ao `agente-00c-orchestrator.md`, que ja inicia a onda (passo 2) antes do
budget check (passo 8) e por isso nao apresenta o defeito.

**Rationale**:

- **Nao toca contrato compartilhado**: `state-ondas.sh start/end` e
  `budget.sh check` sao usados tambem pelo `agente-00c`. Mudar a ordem
  APENAS no documento do orquestrador de feature mantem os helpers POSIX
  intactos, respeitando FR-003 (nao alterar o `agente-00c`) sem risco de
  regressao em outros consumidores.
- **Preserva deteccao de breach real (FR-002)**: apos o `start`, o
  `current_wave_start` reflete o inicio da onda que esta de fato comecando;
  o `budget.sh check` subsequente continua medindo o wallclock da onda
  aberta e ainda dispara breach legitimo quando `wc >= wc_max`.
- **Consistencia de arquitetura**: torna os dois orquestradores simetricos
  no ponto sensivel (iniciar onda antes de medir orcamento), reduzindo a
  chance de o defeito reaparecer por divergencia entre os fluxos.
- **Menor blast radius**: a correcao e uma reordenacao de passos num unico
  documento de orquestrador; nao ha mudanca de schema de `state.json`, de
  assinatura de comando, nem de semantica de calculo.

**Alternatives considered**:

- **(a) Resetar `current_wave_start = null` no `_so_cmd_end`** — *Rejeitada*.
  `_so_cmd_end` (`state-ondas.sh` ~296-316) e chamado por AMBOS os
  orquestradores. Zerar o campo no fechamento mudaria o contrato
  compartilhado e afetaria o `agente-00c` (violando FR-003) e qualquer
  leitor de budget que inspecione o estado ENTRE ondas (ex: relatorios,
  auditoria de metricas). Alem disso, um `budget.sh check` chamado com
  `current_wave_start` vazio cai no ramo `_bd_wc=0` — mascarando
  silenciosamente qualquer verificacao antes do proximo `start`, o que
  degrada a semantica do helper em vez de corrigir a ordem no orquestrador.

- **(b) Tratar `wallclock=0` no `budget.sh check` quando
  `termination_reason != null`** — *Rejeitada*. Introduziria no `check` a
  responsabilidade de inferir se a onda esta aberta a partir do
  `termination_reason` da ultima onda, misturando a logica de medicao com a
  logica de ciclo de vida da onda. Pior: o `check` passaria a **silenciar**
  a medicao em estados que tambem podem ocorrer com uma onda de fato aberta
  em cenarios de reentrancia, arriscando enfraquecer a deteccao de breach
  real — exatamente o que FR-002 proibe. A causa raiz e de **ordem de
  chamada** no orquestrador, nao de calculo no helper; corrigir no helper
  seria tratar o sintoma no lugar errado.

**Fonte** (leitura direta, Principio VI):
`global/skills/agente-00c-runtime/scripts/state-ondas.sh` (`start` ~219,
`_so_cmd_end` ~296-316); `global/skills/agente-00c-runtime/scripts/budget.sh`
(`_bd_collect` ~89-96, breach ~119-121);
`global/agents/agente-00c-feature-orchestrator.md` (Loop, passo 4 ~248);
`global/agents/agente-00c-orchestrator.md` (passos 2 e 8).
