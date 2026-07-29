# Implementation Plan: budget-resume-wallclock

**Feature**: `budget-resume-wallclock` | **Date**: 2026-07-09 | **Spec**: [spec.md](./spec.md)

## Summary

Corrigir o **falso breach de wallclock na retomada** do orquestrador
`feature-00c`. Requisito primario (FR-001/FR-002/FR-003): ao retomar uma
execucao pausada, o orcamento de tempo da onda corrente deve ser avaliado
somente **apos** o inicio real dessa onda ser registrado, preservando
integralmente a deteccao de estouro genuino dentro de uma onda ja aberta e
sem alterar o comportamento do orquestrador de projeto (`agente-00c`).

**Abordagem tecnica** (aterrada em leitura do runtime — ver `research.md`):
**reordenar** o "Loop principal de uma onda" em
`global/agents/agente-00c-feature-orchestrator.md` para que o passo
`state-ondas.sh start` (inicio de onda) ocorra **antes** do primeiro
`budget.sh check`, tornando o fluxo de feature analogo ao do
`agente-00c-orchestrator.md` (que ja inicia a onda no passo 2, antes do
budget check do passo 8, e por isso e imune ao defeito).

A correcao e **localizada no documento do orquestrador de feature**: NAO
toca a semantica compartilhada de `state-ondas.sh start/end` nem de
`budget.sh check` (usadas tambem pelo `agente-00c`), e NAO silencia o
check (nao trata `wallclock=0` quando ha `termination_reason`), preservando
a deteccao de breach real (FR-002).

### Causa raiz (confirmada por leitura de codigo)

| Arquivo | Fato observado |
|---------|----------------|
| `global/skills/agente-00c-runtime/scripts/state-ondas.sh` | `start` grava `.budgets.current_wave_start = now` (bloco `jq`, ~linha 219). `_so_cmd_end` (~296-316) fecha a onda mas **NAO reseta** `.budgets.current_wave_start`. |
| `global/skills/agente-00c-runtime/scripts/budget.sh` | `_bd_collect` le `.budgets.current_wave_start`; `check` calcula `wallclock = now - current_wave_start` (~89-96) e dispara breach quando `wc >= wc_max` (default 5400s, ~119-121). |
| `global/agents/agente-00c-feature-orchestrator.md` | "Loop principal de uma onda": passo 4 = `budget.sh check` (~linha 248) sem um `state-ondas.sh start` antes dele no fluxo de retomada. Na retomada, o `current_wave_start` da onda **anterior ja fechada** persiste, entao o check mede o tempo desde o fim daquela onda + a espera de schedule/humano -> breach falso. |
| `global/agents/agente-00c-orchestrator.md` | passo 2 chama `state-ondas.sh start` **antes** do budget check do passo 8 -> **imune**. NAO alterar (FR-003). |

## Technical Context

**Language/Version**: POSIX sh (runtime `agente-00c-runtime`) + Markdown de
orquestrador (documento de agente consumido pelo harness).
**Primary Dependencies**: `jq` (ja usado pelo runtime; dependencia existente,
nao introduzida por esta feature), `date` (GNU/BSD com fallback portavel ja
presente em `state-ondas.sh`/`budget.sh`).
**Storage**: `state.json` por execucao em
`.claude/feature-00c-state/<short-name>/` — **schema inalterado** por esta feature.
**Testing**: harness POSIX `tests/run.sh` (ver `tests/README.md`);
alvos relevantes `tests/test_budget.sh` e `tests/test_state-ondas.sh`.
**Target Platform**: qualquer ambiente POSIX (macOS/zsh + Linux/CI).
**Project Type**: toolkit interno (runtime shell + docs de orquestrador) — single-layer.
**Performance Goals**: N/A (mudanca de ordem de duas operacoes ja existentes).
**Constraints**: nao enfraquecer deteccao de breach real (FR-002); nao alterar
o `agente-00c` (FR-003); zero mudanca de contrato/schema.
**Scale/Scope**: mudanca cirurgica — reordenacao no doc do orquestrador de
feature + cobertura de teste dos dois cenarios (falso-breach evitado / breach
real preservado).

## Constitution Check

*GATE: Deve passar antes do Phase 0. Re-checar apos Phase 1.*

| Principio | Status | Notas |
|-----------|--------|-------|
| I. SDD recursivo (NON-NEGOTIABLE) | PASS | Bugfix nao-trivial de runtime entrando pela pipeline SDD completa (`specify`→`clarify`→`plan`→...); artefatos em `docs/specs/budget-resume-wallclock/`. Nao e hotfix de 1-5 linhas (envolve doc de orquestrador + testes). |
| II. Scripts POSIX puros, zero dep (NON-NEGOTIABLE) | PASS | Nenhum script novo; nenhuma dependencia nova. A correcao reordena a chamada de scripts POSIX ja existentes no doc do orquestrador. Testes seguem o harness POSIX existente. |
| III. Formato canonico de Skill | N/A | Nenhuma skill criada ou alterada em contrato (nome/trigger/output/paths). |
| IV. Zero coleta remota (NON-NEGOTIABLE) | N/A | Sem telemetria, rede ou coleta. Mudanca puramente local. |
| V. Profundidade acima de metricas de adocao | PASS | Corrige defeito que inutiliza retomadas de longa duracao — reduz retrabalho real; nao adiciona superficie so por metrica. |
| VI. Veracidade de dados — Zero fabricacao (NON-NEGOTIABLE) | PASS | Toda afirmacao factual (linhas, comportamento de `start`/`end`/`check`, imunidade do `agente-00c`) foi extraida por leitura direta do codigo-fonte citado; nenhum valor/rota/assinatura inventado. `data-model.md` e `contracts/` marcados N/A explicito em vez de preenchidos com entidades/contratos ficticios. |

**Resultado do gate**: PASS — nenhuma violacao de principio MUST. Prosseguir para Phase 0.

## Project Structure

### Documentation (this feature)

```
docs/specs/budget-resume-wallclock/
├── spec.md          # Ja existente (specify + clarify)
├── plan.md          # This file
├── research.md      # Phase 0 output (decisao reordenar vs resetar vs silenciar)
├── data-model.md    # Phase 1 output — N/A explicito (sem entidade nova)
└── quickstart.md    # Phase 1 output (cenario BUG + cenario PRESERVADO)
```

> `contracts/` **nao criado**: N/A explicito — nenhuma API/evento/contrato
> novo; o comportamento de `start`/`end`/`check` permanece inalterado, muda
> apenas a ORDEM de chamada no documento do orquestrador de feature.

### Source Code (repository root) — arquivos tocados/relevantes

```
global/agents/
├── agente-00c-feature-orchestrator.md   # ALVO: reordenar Loop (start antes do 1o budget check)
└── agente-00c-orchestrator.md           # REFERENCIA (imune) — NAO alterar (FR-003)

global/skills/agente-00c-runtime/scripts/
├── state-ondas.sh                       # REFERENCIA (start grava current_wave_start; end nao reseta) — NAO alterar
└── budget.sh                            # REFERENCIA (check le current_wave_start) — NAO alterar

tests/
├── test_budget.sh                       # cobre cenario preservado (breach real dentro de onda aberta)
└── test_state-ondas.sh                  # cobre lifecycle start/end + cenario de retomada
```

**Structure Decision**: mudanca confinada ao documento do orquestrador de
feature (`agente-00c-feature-orchestrator.md`). Os scripts POSIX
compartilhados (`state-ondas.sh`, `budget.sh`) **permanecem intactos** para
nao afetar o `agente-00c` nem outros leitores de budget — a fronteira da
correcao e a sequencia do Loop, nao a semantica dos helpers.

## Convencoes de Borda

N/A — single-layer. A feature ajusta a ordem de duas operacoes ja
existentes dentro do runtime de orquestracao (inicio de onda e checagem de
orcamento); nao atravessa fronteira backend↔frontend, DB↔backend nem
broker↔consumer. Nao ha payload, case style nem contrato de serializacao
envolvido.

## Complexity Tracking

> N/A — Constitution Check passou sem violacoes; nenhuma complexidade
> adicional introduzida. A correcao **reduz** superficie de comportamento
> anomalo em vez de adicionar camadas.

## Invariante: retomada sempre segue onda fechada (fecha CHK007/CHK023)

Toda retomada de `feature-00c` (pos-agendamento OU pos-bloqueio-humano)
ocorre com a onda anterior JA FECHADA (`termination_reason != null`) —
nunca ha um sub-caso de retomada com a onda anterior ainda ABERTA. Os dois
gatilhos de retomada citados em spec.md User Story 1 reduzem portanto ao
MESMO caso (onda fechada + wallclock acumulado), e o passo 3.bis inserido
no Loop principal (`agente-00c-feature-orchestrator.md`, secao "Invariante:
retomada sempre segue onda fechada") os cobre uniformemente, sem
tratamento especial por caminho:

- toda pausa por bloqueio humano fecha a onda via `state-ondas.sh end
  --motivo-termino bloqueio_humano` (passo 10 do Loop, obrigatorio antes de
  qualquer relatorio terminal — "Contrato de conclusao de turno" no doc do
  orquestrador); e
- `feature-00c-resume.md` chama `state-ondas.sh reconcile-wave` SEMPRE,
  antes de qualquer outra coisa (linha ~181-195), fechando qualquer onda
  deixada ABERTA (rede de seguranca do command pai) antes de delegar ao
  orquestrador.

Ver detalhe completo na nota "Invariante: retomada sempre segue onda
fechada" em `global/agents/agente-00c-feature-orchestrator.md` (logo apos
o "Loop principal de uma onda").
