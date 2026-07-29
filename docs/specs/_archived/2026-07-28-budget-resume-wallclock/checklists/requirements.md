# Requirements Checklist: budget-resume-wallclock

**Purpose**: Quality gate dos requisitos (spec.md + plan.md) antes de
`create-tasks` — valida completude, clareza, consistencia, mensurabilidade
e cobertura de cenarios do bugfix de falso breach de wallclock na retomada
`feature-00c`. Nao valida implementacao (ainda nao existe).
**Created**: 2026-07-09
**Feature**: [spec.md](../spec.md) · [plan.md](../plan.md)

## Completude de Requisitos

- [x] CHK001 - O comportamento esperado quando a execucao esta na PRIMEIRA
  onda (sem onda anterior encerrada) esta definido? [Completude, Spec
  §Edge Cases "O que acontece na primeira onda de uma execucao nova?"]
  {auto}
- [x] CHK002 - A localizacao exata da correcao (arquivo + passo do Loop)
  esta definida sem ambiguidade? [Completude, Plan §Summary "reordenar o
  Loop principal de uma onda em `agente-00c-feature-orchestrator.md`" +
  §Causa raiz linha `passo 4 = budget.sh check (~linha 248) sem um
  state-ondas.sh start antes dele"] {auto}
- [x] CHK003 - Os arquivos que NAO devem ser tocados pela correcao estao
  listados explicitamente? [Completude, Plan §Project Structure —
  `agente-00c-orchestrator.md`, `state-ondas.sh`, `budget.sh` marcados
  "REFERENCIA — NAO alterar"] {auto}
- [x] CHK004 - O criterio de teste automatizado (FR-004) nomeia os
  arquivos de teste alvo em vez de deixar a verificacao generica?
  [Completude, Spec §FR-004 + Plan §Technical Context "Testing: ...
  alvos relevantes `tests/test_budget.sh` e `tests/test_state-ondas.sh`"]
  {auto}

## Clareza de Requisitos

- [x] CHK005 - O termo "onda corrente" (FR-001) e distinguivel sem
  ambiguidade de "onda anterior ja encerrada"? [Clareza, Spec §Visao
  geral — descreve `current_wave_start` como timestamp que "so e definido
  no inicio de uma onda e nunca e reaberto ate a proxima onda comecar"]
  {auto}
- [x] CHK006 - "Estouro genuino"/"breach legitimo" (FR-002) tem definicao
  operacional citavel (nao e so um adjetivo vago)? [Clareza, Plan §Causa
  raiz — `budget.sh check` "dispara breach quando wc >= wc_max (default
  5400s)"] {auto}
- [x] CHK007 - O sub-caso "retomada apos responder um bloqueio humano"
  (User Story 1) que ocorre com a onda AINDA ABERTA (nao encerrada, sem
  `state-ondas.sh end` chamado) esta distinguido do sub-caso "retomada por
  agendamento entre ondas" (onda ja fechada)? **Resolvido**: esse sub-caso
  nao existe — toda retomada ocorre com a onda anterior JA FECHADA. Toda
  pausa por bloqueio humano fecha a onda via `state-ondas.sh end
  --motivo-termino bloqueio_humano` (passo 10 do Loop, obrigatorio antes
  de qualquer relatorio terminal — "Contrato de conclusao de turno"), e
  `feature-00c-resume.md` chama `state-ondas.sh reconcile-wave` SEMPRE
  antes de delegar ao orquestrador (rede de seguranca que fecha qualquer
  onda deixada aberta). Os dois gatilhos de retomada reduzem ao MESMO
  caso — ver nota "Invariante: retomada sempre segue onda fechada" em
  `agente-00c-feature-orchestrator.md` (apos o Loop principal) e em
  `plan.md` §Invariante. [Resolved, `agente-00c-feature-orchestrator.md`
  §Invariante + `feature-00c-resume.md` linha ~181-195] {auto}

## Consistencia de Requisitos

- [x] CHK008 - FR-001 ("avaliar somente apos o start") e FR-002
  ("continuar interrompendo apos iniciada") sao consistentes entre si,
  sem sobreposicao conflitante? [Consistencia, Spec §FR-001, §FR-002]
  {auto}
- [x] CHK009 - As alternativas de design rejeitadas (reset em
  `_so_cmd_end`; silenciar `wallclock=0` no check) sao justificadas por
  violarem FR-002/FR-003, e nao por preferencia estetica? [Consistencia,
  research.md §Alternatives considered "(a)" e "(b)"] {auto}
- [x] CHK010 - O Constitution Check do plan.md confirma PASS sem violacao
  para todos os principios aplicaveis (incluindo Principio VI —
  rastreabilidade de dados factuais)? [Consistencia, Plan §Constitution
  Check] {auto}

## Qualidade de Criterios de Aceite (Mensurabilidade)

- [x] CHK011 - SC-001 e mensuravel objetivamente (100% das retomadas com
  ultima onda encerrada, sem estouro reportado antes do inicio da nova
  onda)? [Mensurabilidade, Spec §SC-001] {auto}
- [x] CHK012 - SC-002 e mensuravel objetivamente (100% dos casos de onda
  aberta que excede o limite continua sendo interrompida)? [Mensurabilidade,
  Spec §SC-002] {auto}
- [x] CHK013 - SC-003 e mensuravel objetivamente (suite 100% verde
  cobrindo ambos os cenarios) e aponta os arquivos de teste concretos?
  [Mensurabilidade, Spec §SC-003 + Plan §Technical Context] {auto}

## Cobertura de Cenarios e Edge Cases

- [x] CHK014 - O cenario "BUG corrigido" (retomada com onda anterior
  fechada nao gera falso breach) esta mapeado a um teste concreto, com
  passos e resultado esperado? [Cobertura, quickstart.md §Scenario 1]
  {auto}
- [x] CHK015 - O cenario "PRESERVADO" (onda aberta que excede o limite
  ainda dispara breach — FR-002/SC-002) esta mapeado a um teste concreto?
  [Cobertura, quickstart.md §Scenario 2] {auto}
- [x] CHK016 - O edge case "retomada imediata apos encerramento (delta
  ~zero)" esta mapeado a um teste concreto? [Cobertura, Spec §Edge Cases
  + quickstart.md §Scenario 3] {auto}
- [x] CHK017 - Os gatilhos de encerramento fora de escopo desta feature
  (numero de tentativas, movimento circular, desvio de finalidade) estao
  explicitamente excluidos, para que create-tasks nao gere trabalho fora
  do escopo pretendido? [Cobertura, Spec §Edge Cases "Esses gatilhos ficam
  fora do escopo desta feature"] {auto}

## Confinamento de Escopo (FR-003)

- [x] CHK018 - `agente-00c-orchestrator.md` esta explicitamente marcado
  como referencia que NAO deve ser alterado, com a evidencia de por que
  ja e imune (inicia onda no passo 2 antes do budget check do passo 8)?
  [Confinamento, Spec §FR-003 + Plan §Causa raiz linha
  `agente-00c-orchestrator.md`] {auto}
- [x] CHK019 - Os scripts POSIX compartilhados (`state-ondas.sh`,
  `budget.sh`) estao explicitamente marcados como inalterados, para que
  create-tasks nao gere uma tarefa de edicao desses arquivos por engano?
  [Confinamento, Plan §Project Structure + §Structure Decision "os
  scripts POSIX compartilhados... permanecem intactos"] {auto}

## Dependencias e Premissas

- [x] CHK020 - A causa raiz esta aterrada em leitura direta do
  codigo-fonte citado (arquivo + linha aproximada), nao em suposicao?
  [Dependencias, Plan §Causa raiz (tabela com 4 linhas citando arquivo e
  numero de linha) + Constitution Check "Principio VI: PASS"] {auto}
- [x] CHK021 - As dependencias tecnicas (`jq`, `date`) sao premissas
  pre-existentes do runtime, nao introduzidas por esta feature?
  [Dependencias, Plan §Technical Context "Primary Dependencies: `jq` (ja
  usado pelo runtime; dependencia existente, nao introduzida por esta
  feature)"] {auto}

## Ambiguidades, Conflitos e Julgamento de Negocio

- [ ] CHK022 - A estrategia de simular passagem de tempo nos testes
  automatizados (ex.: sobrescrever `current_wave_start` via `jq`/`date`
  em vez de aguardar o threshold real de 5400s) e adequada ao apetite de
  velocidade de CI do time, ou o dono do produto prefere um teste com
  threshold reduzido/configuravel para exercitar o tempo real? [Risco,
  sem evidencia em spec/plan/quickstart sobre a tecnica exata de
  simulacao a ser usada nos testes] {humano}
- [x] CHK023 - O gap CHK007 (comportamento indefinido de `start` sobre
  onda ainda aberta ao retomar apos bloqueio humano) deve ser resolvido
  dentro do escopo desta feature (nova regra de requisito) ou tratado
  como fora de escopo explicito, analogo aos outros gatilhos ja excluidos
  em §Edge Cases? **Resolvido**: nao precisa de nova regra nem de exclusao
  de escopo — o gap era uma premissa incorreta (existiria um sub-caso de
  onda ainda aberta ao retomar). A leitura do runtime confirma que esse
  sub-caso nao ocorre (ver CHK007): retomada SEMPRE segue onda fechada,
  entao o passo 3.bis (`wave-status` != "open" -> `start`) cobre o unico
  caso real sem ambiguidade. [Resolved, mesma evidencia de CHK007] {auto}

## Notes

- Items `{auto}` ja vem resolvidos pelo agente (`[x]` com citacao, ou
  marcador `[Gap]`/`[Ambiguity]`).
- Items `{humano}` ficam `[ ]` aguardando decisao do dono do produto.
- CHK007 e CHK023 sao a MESMA lacuna vista de dois angulos (definicao do
  requisito vs decisao de escopo) — resolver CHK023 resolve CHK007.
- Marcar items concluidos com `[x]`.
- Items numerados sequencialmente para referencia.
