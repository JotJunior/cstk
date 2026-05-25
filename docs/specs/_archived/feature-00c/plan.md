# Implementation Plan: Feature-00C

**Feature**: `feature-00c` | **Date**: 2026-05-20 | **Spec**: [spec.md](./spec.md)

## Summary

Feature-00C e um orquestrador autonomo da pipeline SDD do toolkit
`claude-ai-tips`, focado em **uma feature individual** dentro de um
projeto que ja possui briefing + constitution ratificados. Paralelo
ao `agente-00c` (escopo de projeto inteiro), reusa o mesmo runtime
POSIX e o mesmo padrao asker/answerer mediado, mas opera sobre a
pipeline `specify → clarify → plan → checklist → create-tasks →
execute-task → review-task` (sem briefing/constitution/review-features).

**Abordagem tecnica derivada da pesquisa (research.md)**:

- **Forma**: 1 slash command primario (`/feature-00c`) + 2 auxiliares
  (`-resume`, `-abort`) + 1 agente orquestrador + 2 agentes
  asker/answerer dedicados, totalizando 6 arquivos novos sob `global/`.
- **Reuso de runtime**: parametrizacao dos 21 scripts POSIX do
  `agente-00c-runtime` via variavel `AGENTE_00C_STATE_DIR` ou primeiro
  argumento. Refactor retrocompativel — `/agente-00c` continua usando
  default path. Decision 1.
- **Asker/answerer**: arquivos de agente separados
  (`feature-00c-clarify-asker`, `feature-00c-clarify-answerer`) com
  scoring 0..3 identico ao 00c, escopo declarado no system prompt.
  Decision 2.
- **Pre-flight constitution-conflict**: extracao da logica existente
  do `pipeline.sh` (commit e457dfa) para script dedicado
  `feature-00c-preflight.sh`, invocado entre `clarify` e `plan`.
  Decision 4.
- **Persistencia**: `state.json` + `state.json.sha256` em
  `<projeto-alvo>/.claude/feature-00c-state/<short_name>/`, com
  backups por onda em `backups/wave-NNN.json` (todas as ondas,
  filtradas por secrets-filter). Decisions 3 + 6.
- **Continuacao cross-sessao**: orquestrador retorna intent de schedule
  ao slash command pai, que invoca `ScheduleWakeup`. Resume valida
  lock → state hash → briefing/constitution hash antes de delegar.
  Decision 5.
- **Thresholds de onda**: reuso direto dos valores do agente-00c
  research.md Decision 2 (80 tool calls, 90min wallclock, 1MB state).
  FR-015A sincroniza mudancas futuras entre os dois specs.

## Technical Context

**Language/Version**: instrucoes em markdown (frontmatter YAML) para
slash commands e agentes custom. Scripts auxiliares em POSIX sh
(`#!/bin/sh` + `set -eu`). Sem linguagem de programacao tradicional.

**Primary Dependencies**: Claude Code Opus 4.x ou Sonnet 4.6 (Auto
mode recomendado). Harness com tools `ScheduleWakeup`, `Skill`,
`Agent`, `Bash`, `Read`, `Write`, `Edit` disponiveis. `gh` CLI
autenticado localmente (para abrir issues no toolkit). `git` no PATH.
`jq` como **dependencia opcional** com fallback POSIX (constitution
amendment 1.1.0).

**Storage**: arquivos planos sob
`<projeto-alvo>/.claude/feature-00c-state/<short_name>/`:
- `state.json`, `state.json.sha256`, `.lock`
- `feature-00c-report.md`
- `backups/wave-NNN.json` (todas as ondas)

Suggestions compartilhadas no projeto:
`<projeto-alvo>/.claude/feature-00c-suggestions.md`.

Artefatos SDD da feature em `<projeto-alvo>/docs/specs/<short_name>/`
(spec.md, plan.md, tasks.md, etc — gerados pelas skills do toolkit).

**Testing**: testes manuais via cenarios em `quickstart.md` (11
cenarios cobrindo happy path, pre-flight, clarify autonomo, resume,
abort, coexistencia, paralelismo, loop trigger, **roundtrip empirico
de secrets**, constitution drift). Testes automatizados POSIX em
`tests/test_feature-00c-*.sh` integrados a `tests/run.sh` do toolkit
(infraestrutura `shell-scripts-tests`).

**Target Platform**: Claude Code rodando localmente em macOS/Linux.
Continuacao via wakeup (curtas) ou `/schedule` Routines (longas,
fallback — mesmo padrao do agente-00c research.md Decision 1).

**Project Type**: meta-tool dentro do toolkit `claude-ai-tips`. Nao
e biblioteca nem servico. Colecao de slash commands + agentes custom
+ scripts POSIX no skill compartilhado `agente-00c-runtime`.

**Performance Goals**:
- Onda tipica: 30-90 minutos wallclock, 30-80 tool calls.
- Pre-flight validation: <2s (briefing + constitution + locks).
- Geracao de relatorio parcial pos-aborto: <60s (SC-005).
- Validacao de schema na retomada: <2s.

**Constraints**:
- Subordinada a constitution v1.1.0 do toolkit (SDD recursivo, POSIX
  sh puro, zero coleta remota, profundidade > adocao).
- Sem push, sem deploy externo, sem sudo. Docker apenas dentro do
  projeto-alvo. `gh` apenas para issues no toolkit (excecao
  documentada).
- Filtro de secrets aplicado a report, suggestions, issue body E
  backups por onda (Decision 6).

**Scale/Scope**:
- 1 operador (jot). N features por projeto-alvo. Features paralelas
  no mesmo projeto (FR-028).
- 6 arquivos novos sob `global/` + 1 script novo no runtime + refactor
  retrocompativel dos 21 scripts existentes.

## Constitution Check

*GATE: deve passar antes do Phase 0. Re-checar apos Phase 1.*

### Toolkit Constitution v1.1.0 (`docs/constitution.md`)

| Principio | Status | Notas |
|-----------|--------|-------|
| I. SDD recursivo (NON-NEGOTIABLE) | PASS | Feature segue SDD a si propria: briefing pre-existe, constitution pre-existe, specify→clarify→checklist completos, agora `/plan`. Pipeline gera as proximas etapas (create-tasks, execute-task) sobre si mesma. |
| II. POSIX sh puro (NON-NEGOTIABLE) | PASS | Reuso de scripts ja-POSIX do runtime + 1 script novo (`feature-00c-preflight.sh`) escrito em POSIX. Sem Bash-isms. `jq` como dep opcional ja registrada. |
| III. Formato canonico de skill | N/A | Feature nao introduz skill nova. Agentes custom seguem padrao YAML frontmatter dos agentes existentes do agente-00c. |
| IV. Zero coleta remota (NON-NEGOTIABLE) | PASS | Sem telemetria. `gh issue create` no toolkit e excecao ja documentada (Principio II §"`gh` para issues"). Nenhum upload de relatorio/state/backup. |
| V. Profundidade > adocao | PASS | Feature aprofunda capacidade existente (agente-00c) reusando codigo validado em vez de marketing. Reduz retrabalho em projetos que ja tem briefing+constitution. |

**Resultado**: PASS em todos os principios MUST. Phase 0 e Phase 1
liberados.

### Re-check pos-Phase 1 (apos design)

| Principio | Status | Justificativa pos-design |
|-----------|--------|--------------------------|
| I. SDD recursivo | PASS | Artefatos `research.md`, `data-model.md`, `contracts/*.md`, `quickstart.md` gerados conforme padrao. |
| II. POSIX sh puro | PASS | Decisions 1, 4, 6 confirmam reuso/extensao POSIX-compliant. Nenhum novo Bash-ism introduzido. |
| III. Formato skill | N/A | Confirmado: nenhum SKILL.md novo. |
| IV. Zero coleta | PASS | Confirmado: hash registrado em state.json fica local; backups locais; report local. |
| V. Profundidade | PASS | Confirmado: 6 arquivos novos + parametrizacao de runtime existente. Sem features "legais de anunciar" sem valor de uso. |

## Project Structure

### Documentation (this feature)

```
docs/specs/feature-00c/
├── spec.md                          # ja existe
├── plan.md                          # este arquivo
├── research.md                      # Phase 0 — Decisions 1..7
├── data-model.md                    # Phase 1 — entidades + invariants
├── quickstart.md                    # Phase 1 — 11 cenarios manuais
├── checklists/
│   └── requirements.md              # ja existe (25/35 atendido)
└── contracts/                       # Phase 1
    ├── report-format.md             # 6 secoes do feature-00c-report.md
    └── cli-invocation.md            # interface dos 3 slash commands
```

### Source Code (repository root)

```
claude-ai-tips/
├── global/
│   ├── agents/
│   │   ├── agente-00c-clarify-answerer.md           # existe
│   │   ├── agente-00c-clarify-asker.md              # existe
│   │   ├── agente-00c-orchestrator.md               # existe
│   │   ├── agente-00c-feature-orchestrator.md       # NOVO
│   │   ├── feature-00c-clarify-asker.md             # NOVO
│   │   └── feature-00c-clarify-answerer.md          # NOVO
│   ├── commands/
│   │   ├── agente-00c.md                            # existe
│   │   ├── agente-00c-abort.md                      # existe
│   │   ├── agente-00c-resume.md                     # existe
│   │   ├── feature-00c.md                           # NOVO
│   │   ├── feature-00c-resume.md                    # NOVO
│   │   └── feature-00c-abort.md                     # NOVO
│   └── skills/
│       └── agente-00c-runtime/
│           ├── SKILL.md                             # existe (atualizar Gotchas se necessario)
│           └── scripts/
│               ├── (21 scripts existentes — parametrizar AGENTE_00C_STATE_DIR)
│               └── feature-00c-preflight.sh         # NOVO
├── tests/
│   └── test_feature-00c-*.sh                        # NOVO (cobertura POSIX da nova script)
├── docs/specs/feature-00c/                          # ver acima
└── CHANGELOG.md                                     # entrada nova
```

**Structure Decision**: layout espelha exatamente o do agente-00c
(mesmas 3 categorias `agents/`, `commands/`, `skills/runtime/`),
facilitando navegacao. Estado operacional no projeto-alvo isolado em
namespace `feature-00c-state/<short_name>/` evitando colisao com
`agente-00c-state/`.

## Convencoes de Borda

**N/A — single-layer**: feature-00c e meta-tool composta de markdown
(slash commands, agentes) + POSIX sh (scripts runtime). Nao atravessa
backend↔frontend nem DB↔backend tradicionais. Os "contratos" sao:

- Interface humano↔slash command: documentada em
  `contracts/cli-invocation.md` (sintaxe, exit codes, validacoes).
- Interface slash command↔agente custom: via Claude Code harness
  (system prompt + tools disponiveis).
- Interface orquestrador↔scripts POSIX: via Bash tool + argumentos
  posicionais documentados nos scripts.
- Interface orquestrador↔skills do toolkit: via tool `Skill`
  (FR-008).
- Formato persistido: state.json em JSON; report/suggestions em
  markdown; backups em JSON. Schemas em `data-model.md`.

Como nenhuma dessas e backend-frontend boundary com case style
divergente, a secao de "Convencoes de Borda" da skill `/plan` nao
se aplica diretamente — declaracao explicita conforme orientacao da
skill.

## Phase Status

| Phase | Status | Output |
|-------|--------|--------|
| 0 — Research | COMPLETO | `research.md` com 7 decisions |
| 1 — Design | COMPLETO | `data-model.md`, `contracts/*.md`, `quickstart.md` |
| 2 — Tasks | PENDENTE | sera gerado por `/create-tasks` |

## Complexity Tracking

Nao se aplica — Constitution Check passou em todos os principios
sem violacao. Nenhuma excecao documentada necessaria.

## Artefatos Gerados

| Arquivo | Status |
|---------|--------|
| `docs/specs/feature-00c/plan.md` | Criado |
| `docs/specs/feature-00c/research.md` | Criado |
| `docs/specs/feature-00c/data-model.md` | Criado |
| `docs/specs/feature-00c/contracts/report-format.md` | Criado |
| `docs/specs/feature-00c/contracts/cli-invocation.md` | Criado |
| `docs/specs/feature-00c/quickstart.md` | Criado |

## Proximos Passos

1. `/checklist` adicional opcional — gerar dominios `security` (verificar
   filtro de secrets, sanitizacao, blast radius) e `requirements`
   (refresh para incluir items dos novos artefatos do Phase 1).
2. `/create-tasks` — decompor o plano em backlog executavel. Estimativa
   inicial: 12-18 tasks em 3 fases (refactor runtime, novos artefatos,
   testes + docs).
3. `/analyze` — apos `/create-tasks`, validar consistencia
   cross-artifact (spec ↔ plan ↔ tasks ↔ constitution).
