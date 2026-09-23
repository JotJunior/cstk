# Implementation Plan: Resumo Deterministico de Fechamento de Onda

**Feature**: `wave-close-summary` | **Date**: 2026-09-22 | **Spec**: [spec.md](./spec.md)

## Summary

Ao retomar o controle apos cada onda, o command pai (`/agente-00c`,
`/agente-00c-resume`, `/feature-00c`, `/feature-00c-resume`) passa a entregar ao
operador um resumo objetivo da onda recem-fechada. A composicao vive num helper
POSIX unico e testavel — `wave-summary.sh emit` [PROPOSTA] em
`plugins/cstk/skills/agente-00c-runtime/scripts/` — que le SO campos ja gravados
no estado (materializado por `_state-read.sh` [EXISTENTE], backend JSON ou
SQLite), aplica a regra "nao medido" campo a campo, nunca expoe texto livre de
decisoes/bloqueios e falha de forma best-effort (1 linha em stderr, exit != 0);
o pai substitui o bloco por um aviso e segue o fluxo (schedule, lock, ingestao)
inalterado. Nenhuma instrumentacao, persistencia ou dependencia nova.

## Technical Context

**Language/Version**: POSIX sh (`#!/bin/sh`, `set -eu`) — herdado do runtime `agente-00c-runtime`
**Primary Dependencies**: `jq` (obrigatorio na camada de estado — Constitution II amendment 1.3.0); `sqlite3` so indireto, via `state-rw.sh read` quando backend = `state.db`; helpers irmaos [EXISTENTE]: `_state-read.sh`, `secrets-filter.sh scrub`, `guard-hooks-status.sh tick-mode`
**Storage**: N/A (read-only sobre o estado existente; nada novo e persistido)
**Testing**: harness POSIX `tests/run.sh`; novo `tests/test_wave-summary.sh`; extensao de `tests/test_state-parity-sweep.sh`; teste estatico interno `tests/test_command-wave-summary.sh`
**Target Platform**: macOS + Linux (sem GNU-only: nada de `timeout`, `sed -i`, `stat -c`) — fonte: constitution Principio II (POSIX portavel) + CI Linux do repo
**Project Type**: helper CLI interno do runtime + prosa dos 4 slash commands
**Performance Goals**: < 2 s por invocacao (1 materializacao + 1 `jq` + 1 `tick-mode` + 1 `scrub`)
**Constraints**: best-effort absoluto (nunca gateia reconcile/schedule/lock); saida deterministica; <= 14 linhas em Markdown; zero rede
**Scale/Scope**: 1 onda por invocacao; estado tipico de dezenas a centenas de decisoes

Nenhum `NEEDS CLARIFICATION` — detalhes em [research.md](./research.md).

## Constitution Check

*GATE: Deve passar antes do Phase 0. Re-checar apos Phase 1.*

| Principio | Status | Notas |
|-----------|--------|-------|
| I. SDD recursivo | PASS | spec + clarify concluidos; plan → checklist → create-tasks seguem. Sem mudanca de contrato de skill publica (helper interno do runtime) — bump MINOR no CHANGELOG na entrega |
| II. POSIX sh puro | PASS | `#!/bin/sh` + `set -eu`, sem bash-isms; `jq` coberto pelo carve-out 1.3.0 (camada de estado); consumidor derivado degrada gracioso pelo pai (item c) — ver research Decision 7 |
| III. Formato canonico de skill | N/A | nenhum SKILL.md novo/alterado (script em skill interna existente) |
| IV. Zero coleta remota | PASS | helper sem rede; saida vai so para a conversa local do operador |
| V. Profundidade > adocao | PASS | reusa fontes/filtros existentes; nenhum mecanismo paralelo |
| VI. Veracidade de dados | PASS | todo campo vem do estado; ausencia = `nao medido`/`null`, nunca `0` (FR-010); rotulo de motivo desconhecido sai cru, sem inventar |

## Project Structure

### Documentation (this feature)

```
docs/specs/wave-close-summary/
├── spec.md
├── plan.md                      # este arquivo
├── research.md                  # Phase 0
├── data-model.md                # Phase 1 (WaveSummary — projecao efemera)
├── quickstart.md                # Phase 1 (10 cenarios)
└── contracts/
    └── wave-summary-cli.md      # Phase 1 (contrato CLI [PROPOSTA])
```

### Source Code (repository root)

```
plugins/cstk/skills/agente-00c-runtime/scripts/
├── _state-read.sh               # [EXISTENTE] materializacao backend-agnostica
├── secrets-filter.sh            # [EXISTENTE] scrub stdin→stdout
├── guard-hooks-status.sh        # [EXISTENTE] tick-mode (oraculo de tool_calls)
└── wave-summary.sh              # [PROPOSTA] NOVO — emit --state-dir [--wave] [--json]

plugins/cstk/commands/
├── feature-00c.md               # [EXISTENTE] §5 Pos-orquestrador → + chamada apos reconcile-wave
├── feature-00c-resume.md        # [EXISTENTE] §4 → + chamada apos reconcile-wave
├── agente-00c.md                # [EXISTENTE] §5.pre → + chamada; §6 apresenta o bloco
└── agente-00c-resume.md         # [EXISTENTE] §6.bis → + chamada; §9 apresenta o bloco

tests/
├── test_wave-summary.sh         # [PROPOSTA] NOVO — obrigatorio (--check-coverage)
├── test_state-parity-sweep.sh   # [EXISTENTE] + entrada no manifest dinamico
├── test_command-wave-summary.sh # [PROPOSTA] NOVO interno — ordem reconcile→summary→schedule nos 4 commands
└── run.sh                       # [EXISTENTE] + registro do teste interno em _is_internal_test

CHANGELOG.md                     # [EXISTENTE] entrada MINOR + link-ref da versao
```

**Structure Decision**: um unico script no diretorio de scripts do runtime (mesmo
local e convencoes de `wave-usage-report.sh`), consumido pelos 4 commands com
um bloco de prosa identico. Satisfaz Q5/FR-014 por construcao: nao ha logica de
composicao nos commands, so a chamada + fallback.

## Convencoes de Borda

N/A — single-layer (helper CLI local, sem fronteira de rede/DB/UI). Unica
convencao relevante: chaves do `--json` em snake_case ingles (regra global);
rotulos do Markdown em pt-BR (mensagens permitidas em portugues).

## Riscos e mitigacoes

| Risco | Mitigacao |
|-------|-----------|
| Parity-sweep reprovar o helper (literal do arquivo de estado em prosa/erro) | Usar so `_state-read.sh`; nao escrever o nome literal do arquivo em mensagens — se inevitavel, entrada `wave-summary.sh:prosa` na allowlist com justificativa no MESMO commit |
| `tick-mode` lento/indisponivel | Falha do `tick-mode` ⇒ `tool_calls=0` vira `nao medido` (conservador); `>0` sai medido sem depender dele |
| `secrets-filter.sh` indisponivel | campo `next_instruction` = `nao disponivel (filtro indisponivel)`; resto do resumo segue (fail-closed so no campo) |
| Teste de "jq ausente" falso-verde (macOS tem `/usr/bin/jq`) | shim de PATH com allowlist explicita de utilitarios (padrao ja usado no repo), nunca so prefixar PATH |
| Drift catalogo instalado vs repo | entrega exige `cstk install --from` (catalogo: script + commands); nenhum `cli/lib` tocado ⇒ sem `self-update` |

## Complexity Tracking

Sem violacoes de constitution — secao vazia.

## Re-check pos-design (ETAPA 7)

Design manteve 1 script + prosa; nenhuma camada, dependencia ou persistencia
nova; Principio VI reforcado (tabela de "medido quando" na research Decision 3).
Todos os MUST seguem PASS.
