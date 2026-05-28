# Implementation Plan: agente-00c model-routing

**Feature**: `agente-00c-model-routing` | **Date**: 2026-05-22 | **Spec**: [spec.md](./spec.md)

## Summary

Integrar a skill standalone `model-selector` (entregue em feature
anterior) aos orquestradores autonomos `agente-00c-orchestrator` e
`agente-00c-feature-orchestrator` nos pontos de delegacao via tool
Agent (atualmente: fase clarify, com spawn de asker e answerer).
Cada spawn passa a registrar Decisao auditavel + entrada em
`skills_invoked[]` com a sugestao de modelo da skill, preservando
contrato "suggest-only" (sem troca automatica).

Abordagem tecnica resultante do research (Phase 0):

- Helper POSIX novo `~/.claude/skills/agente-00c-runtime/scripts/model-routing.sh`
  com 3 subcomandos (`template`, `invoke`, `idempotent-check`)
  confina toda logica de templates por subagent_type, parseamento de
  output da skill via `awk`, idempotencia via jq sobre `.decisoes[]`,
  e truncagem do esquema 2000+marker+2000 chars.
- Patches documentais em `agente-00c-orchestrator.md` e
  `agente-00c-feature-orchestrator.md` documentando sequencia
  pre-spawn obrigatoria (FR-010 + FR-011 + FR-016).
- Mapeamento score 0..2 (skill) -> 0..3 (runtime) deterministico
  com tabela fixa `{0->0, 1->2, 2->3}` (dec-003), satisfazendo
  trava de `--evidencia >=20 chars` via citacao literal do bloco
  `## Sinais detectados` (dec-006 da skill, FR-006).
- Fallback gracioso (FR-008 + FR-009) sempre exit 0 do helper;
  skill ausente, output mal-formado ou exit nao-zero produz JSON
  com `fallback: true` e a integracao prossegue sem bloqueio.
- Compatibilidade total com `agente-00c-artifact-cache` por
  construcao (templates inline; nao consomem cache de
  briefing/constitution).

## Technical Context

**Language/Version**: POSIX sh (`#!/bin/sh` com `set -eu`). Nenhuma
outra linguagem introduzida.
**Primary Dependencies**: `awk`, `wc`, `head`, `tail`, `tr` (POSIX
canonicos); `jq` herdado do runtime ja existente (Principio II
§carve-out 1.1.0, dep declarada).
**Storage**: `state.json` ja gerenciado pelo `agente-00c-runtime`
(estruturas `.decisoes[]` e `.ondas[N].skills_invoked[]`). Nenhum
arquivo novo de estado.
**Testing**: harness `tests/run.sh` do toolkit (POSIX puro). Novo
arquivo `tests/test_model-routing.sh` cobre os 3 subcomandos do
helper.
**Target Platform**: Claude Code CLI no host do operador (Darwin,
Linux). Mesmo target dos demais scripts do `agente-00c-runtime`.
**Project Type**: toolkit-cli (library de skills + scripts POSIX).
Single-layer — sem REST API nem frontend.
**Performance Goals**: invocacao do helper `invoke` < 2s por
spawn (SC-006). Skill `model-selector` ja roda em <500ms; overhead
do helper (template + parseamento + jq) ~ 200ms.
**Constraints**: POSIX puro (Principio II MUST), zero coleta
remota (Principio IV MUST, FR-020), zero alteracao de contrato
da skill (Principio III, FR-017).
**Scale/Scope**: ~50 LOC novas em `model-routing.sh` + ~30
linhas documentais em cada orchestrator + ~80 linhas de teste.
Volume tipico em runtime: 2-4 invocacoes por feature (asker +
answerer em 1-2 ondas de clarify).

## Constitution Check

*GATE: Deve passar antes do Phase 0. Re-checar apos Phase 1.*

Constitution lida em `docs/constitution.md` v1.1.0 (ratified
2026-04-20, amended 2026-04-24).

### Passada inicial (antes do Phase 0)

| Principio | Status | Notas |
|-----------|--------|-------|
| I. SDD recursivo (MUST) | PASS | Feature segue pipeline completo: spec (done) -> clarify (done) -> plan (este artefato) -> checklist -> create-tasks -> execute-task. Todos os artefatos vivem em `docs/specs/agente-00c-model-routing/`. |
| II. POSIX sh puro (MUST) | PASS | Helper novo segue `#!/bin/sh` + `set -eu`, sem bash-isms. Deps externas confinadas a POSIX (`awk`, `wc`, `head`, `tail`, `tr`) + `jq` ja declarado como dep opcional do runtime sob carve-out 1.1.0. Nenhuma dep nova introduzida. |
| II §carve-out (dep opcional `jq`) | PASS | (a) helper funciona sem `jq` para subcomando `template` (puro); `invoke` e `idempotent-check` exigem `jq` mas degradam para `fallback-default` documentado se `jq` estiver ausente. (b) toda dep em `jq` confinada a `model-routing.sh` UM arquivo. (c) declarado nesta secao + Phase 0 Decision 4. |
| III. Formato canonico de skill (MUST) | PASS | Feature NAO altera a skill `model-selector` em si (FR-017, Out-of-Scope item 4). Contrato I/O da skill permanece imutavel. Skill continua progressive-disclosure. |
| IV. Zero coleta remota (MUST) | PASS | FR-020 explicito: toda persistencia em `state.json` local. Helper nao faz network. Skill `model-selector` ja e offline (validada em feature anterior). |
| V. Profundidade sobre adocao (SHOULD) | PASS | Feature prefere registro auditavel + fallback robusto a "automacao magica". FR-017 protege contrato suggest-only. Decisao 7 do research (granularidade 1-por-spawn) prioriza profundidade sobre conveniencia. |

**Resultado**: PASS em todos os principios MUST. Sem violacoes.
Sem necessidade de Complexity Tracking.

### Re-check pos Phase 1 (apos design completo)

| Principio | Status | Notas pos-design |
|-----------|--------|------------------|
| I. SDD recursivo (MUST) | PASS | Artefatos completos: plan.md, research.md, data-model.md, contracts/ (2 arquivos), quickstart.md. |
| II. POSIX sh puro (MUST) | PASS | Parser do output da skill confirmado como `awk` POSIX (Decision 3). Truncagem 2000+marker+2000 via `head -c` + `tail -c` (Decision 9) — POSIX puro. |
| II §carve-out | PASS | jq permanece o unico nao-POSIX, confinado em `model-routing.sh`. Declarado e justificado. |
| III. Formato canonico (MUST) | PASS | Phase 1 nao introduz novo formato; consome formato existente da skill. |
| IV. Zero coleta (MUST) | PASS | Phase 1 confirmou: helper escreve apenas em state.json local; output do helper e stdout para o orquestrador consumir, sem rede. |
| V. Profundidade (SHOULD) | PASS | Design preferiu fallback gracioso (sempre exit 0 do helper) a tornar a integracao opaca. FR-017 mantido. |

**Re-check verdict**: NENHUMA nova violacao introduzida pelo design.
Plano apto para `/checklist` + `/create-tasks`.

## Project Structure

### Documentation (this feature)

```
docs/specs/agente-00c-model-routing/
├── spec.md                            # ja existe (onda-001 + onda-002)
├── plan.md                            # este arquivo (onda-003)
├── research.md                        # Phase 0 output (10 Decisions)
├── data-model.md                      # Phase 1 — 3 entidades-chave
├── quickstart.md                      # Phase 1 — 7 cenarios
└── contracts/
    ├── model-routing-helper.md        # Phase 1 — 3 subcomandos
    └── orchestrator-integration.md    # Phase 1 — sequencia pre-spawn + invariantes review-task
```

### Source Code (repository root)

Arvore real do projeto-alvo (`/Users/jot/Projects/_lab/Jot/misc/cstk/`):

```
cstk/
├── global/
│   ├── agents/
│   │   ├── agente-00c-orchestrator.md           # PATCH documental (FR-016)
│   │   ├── agente-00c-feature-orchestrator.md   # PATCH documental (FR-016)
│   │   ├── agente-00c-clarify-asker.md          # nao altera
│   │   ├── agente-00c-clarify-answerer.md       # nao altera
│   │   ├── feature-00c-clarify-asker.md         # nao altera
│   │   └── feature-00c-clarify-answerer.md      # nao altera
│   └── skills/
│       ├── agente-00c-runtime/
│       │   └── scripts/
│       │       ├── (existentes...)
│       │       └── model-routing.sh             # NOVO — helper POSIX (~50 LOC)
│       └── model-selector/                      # nao altera (Out-of-Scope)
│           ├── SKILL.md
│           ├── scripts/classify.sh
│           └── references/sinais.md
├── tests/
│   ├── run.sh
│   ├── (test_*.sh existentes)
│   └── test_model-routing.sh                    # NOVO — cobre 3 subcomandos
└── docs/specs/agente-00c-model-routing/         # artefatos desta feature
```

**Structure Decision**: helper novo segue convencao ja estabelecida
em `global/skills/agente-00c-runtime/scripts/` (mesma vizinhanca de
`state-decisions.sh`, `state-ondas.sh`, `spawn-tracker.sh`). Test
novo segue convencao do CLAUDE.md "Como testar scripts shell":
script em `global/skills/X/scripts/` -> test em `tests/test_X.sh`.

## Convencoes de Borda

**N/A — single-layer**.

Feature e toolkit POSIX puro manipulando exclusivamente `state.json`
local (formato canonico do `agente-00c-runtime`). NAO atravessa
fronteira backend ↔ frontend; NAO tem DTOs nem schemas Zod; NAO
expoe endpoints HTTP. A unica "borda" e o limite entre o shell do
orquestrador e a skill `model-selector` invocada como sub-processo
— borda essa ja documentada pela `contracts/skill-io.md` da skill
arquivada (formato markdown estavel com 4 secoes nomeadas).

Convencoes de naming aplicaveis a esta feature:

| Camada | Convencao | Validacao | Fonte da verdade |
|--------|-----------|-----------|------------------|
| Campos de `.decisoes[]` em state.json | snake_case (compativel com `state-decisions.sh`) | `state-validate.sh` | `data-model.md` deste plan |
| Campos do JSON de output do helper `invoke` | snake_case | parseavel por `jq` | `contracts/model-routing-helper.md` |
| Subcomandos shell e flags `--kebab-case` | kebab-case | `set -eu` + case statement | `contracts/model-routing-helper.md` |
| Rotulo de modelo na escolha (`haiku`, `sonnet`, `opus`, `manter-atual`, `fallback-default`) | lowercase, hyphen separator | enum check em data-model.md | spec da skill `model-selector` |

## Complexity Tracking

Sem violacoes registradas no Constitution Check. Tabela vazia.

| Violacao | Por Que Necessario | Alternativa Simples Rejeitada Porque |
|----------|-------------------|--------------------------------------|
| (vazio) | (vazio) | (vazio) |
