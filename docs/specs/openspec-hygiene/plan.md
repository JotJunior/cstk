# Implementation Plan: Higiene OpenSpec — Gate de Cenarios, Guia de Triagem, Archive Datado, Envelope Diagnostico

**Feature**: `openspec-hygiene`
**Branch**: `feat/openspec-hygiene`
**Date**: 2026-07-23
**Spec**: [spec.md](./spec.md)
**Input**: spec com 17 FRs, zero NEEDS CLARIFICATION (clarify Session 2026-07-23)

## Summary

Quatro entregas independentes de higiene documental derivadas do
benchmark OpenSpec: (1) gate deterministico POSIX
`requirement-coverage.sh` (novo, em `checklist/scripts/`) que bloqueia
specs com Functional Requirement sem cenario associado, via fast-path
de ID literal + correspondencia heuristica textual (clarify FR-005),
invocado por `specify` e `checklist`; (2) triagem "atualizar spec
existente vs feature nova" como prosa na ETAPA 0 de `specify` e nota
em `clarify`; (3) convencao `docs/specs/_archived/<YYYY-MM-DD>-<feature>/`
para arquivamentos futuros, doc-only em `review-features` (zero
consumidores dinamicos a ajustar — verificado); (4) envelope
diagnostico `DIAG|severity|code|message|fix` emitido ADITIVAMENTE por
helper sourceable `_diag.sh` num escopo-piloto de 4 primitivas de
estado do runtime (`state-rw.sh`, `state-lock.sh`, `state-ondas.sh`,
`bloqueios.sh`). Decisoes e sondas em [research.md](./research.md).

## Technical Context

| Campo | Valor |
|-------|-------|
| **Language/Version** | POSIX sh puro (Constitution II); prosa Markdown nas SKILL.md |
| **Primary Dependencies** | utilitarios POSIX apenas: `grep`, `awk`, `tr`, `sort`, `cut`, `find` — zero `jq` no caminho de emissao (spec FR-016) |
| **Storage** | N/A — nenhuma persistencia; saidas sao linhas parseaveis (FINDING/RESULT/DIAG) e convencao de filesystem no archive |
| **Testing** | harness `tests/run.sh` (~1100 cenarios); novos: `tests/test_requirement-coverage.sh`, `tests/test__diag.sh`; extensao dos testes dos 4 scripts-piloto; `--check-coverage` gateia orfaos (spec FR-017) |
| **Target Platform** | macOS + Linux (CI Ubuntu), shells `sh`/`dash`/`zsh`-as-sh |
| **Project Type** | toolkit de documentacao (skills + scripts POSIX) — single-layer |
| **Performance Goals** | gate roda em < 1s sobre spec tipica (puro grep/awk local) |
| **Constraints** | emissao aditiva (nao quebrar testes de mensagem literal — SC-006); sem migracao retroativa de `_archived/` (FR-010); sintaxe/identificadores em ingles |
| **Scale/Scope** | 1 script novo, 1 helper novo, 4 scripts-piloto tocados, 4 SKILL.md tocadas (`specify`, `clarify`, `checklist`, `review-features`), 2+ arquivos de teste novos |

## Constitution Check

*GATE: docs/constitution.md v1.2.0 — checado pre-Phase 0, re-checado pos-Phase 1.*

| Principio | Status | Notas |
|-----------|--------|-------|
| I. SDD recursivo (NON-NEGOTIABLE) | PASS | feature segue pipeline completa (spec clarificada → este plan → checklist → tasks) |
| II. POSIX sh puro, zero dep externa (NON-NEGOTIABLE) | PASS | gate e `_diag.sh` usam so utilitarios POSIX; FR-016 proibe jq na emissao; nenhum fallback opcional necessario |
| III. Formato canonico de skill | PASS | mudancas em SKILL.md sao prosa aditiva nas etapas existentes; nenhuma skill nova (sem impacto no count do README) |
| IV. Zero coleta remota (NON-NEGOTIABLE) | PASS | tudo local; nenhuma rede |
| V. Profundidade > metricas de adocao | PASS | gate fecha lacuna real de retrabalho (requisito sem validacao descoberto tarde) |
| VI. Veracidade de dados (NON-NEGOTIABLE) | PASS | todos os fatos do plan verificados por sonda no repo (research.md cita comandos); contratos novos marcados [PROPOSTA] |

**Re-check pos-Phase 1**: PASS — o design nao introduziu camadas,
servicos ou dependencias alem do escopo-piloto; nenhuma violacao a
justificar.

## Project Structure

### Documentation (this feature)

```
docs/specs/openspec-hygiene/
├── spec.md
├── plan.md                              # este arquivo
├── research.md                          # 6 decisoes + sondas
├── data-model.md                        # 3 entidades transientes
├── quickstart.md                        # 12 cenarios
└── contracts/
    ├── requirement-coverage-cli.md      # CLI do gate [PROPOSTA]
    └── diagnostic-envelope.md           # formato DIAG + escopo-piloto [PROPOSTA]
```

### Source Code (paths reais verificados no repo)

```
global/skills/
├── checklist/
│   ├── SKILL.md                         # MODIFICA: passo de invocacao do gate (FR-002)
│   └── scripts/
│       └── requirement-coverage.sh      # NOVO: gate FR-001..FR-005
├── specify/
│   └── SKILL.md                         # MODIFICA: ETAPA 0 triagem update-vs-nova (FR-006/FR-008) + ETAPA 4 invoca gate (FR-002)
├── clarify/
│   └── SKILL.md                         # MODIFICA: nota de triagem na ETAPA 2 (FR-007)
├── review-features/
│   └── SKILL.md                         # MODIFICA: passo de archive com prefixo YYYY-MM-DD (FR-009/FR-011)
└── agente-00c-runtime/scripts/
    ├── _diag.sh                         # NOVO: helper sourceable do envelope (FR-012/FR-016)
    ├── state-rw.sh                      # MODIFICA (piloto): + linhas DIAG aditivas
    ├── state-lock.sh                    # MODIFICA (piloto)
    ├── state-ondas.sh                   # MODIFICA (piloto)
    └── bloqueios.sh                     # MODIFICA (piloto)

tests/
├── test_requirement-coverage.sh         # NOVO (FR-017)
├── test__diag.sh                        # NOVO (FR-017; precedente test__hash.sh)
├── test_state-rw.sh                     # ESTENDE: assercoes DIAG + legado intacto
├── test_state-lock.sh                   # ESTENDE
├── test_state-ondas.sh                  # ESTENDE
└── test_bloqueios.sh                    # ESTENDE
```

Sem mudanca em: `cli/`, `templates/feature-spec.md` (proibido pelo
clarify FR-005), diretorios ja arquivados (FR-010),
`validate-sdd.sh`/`validate-tasks-template.sh` (padrao apenas seguido,
nao tocado).

## Convencoes de Borda

N/A — single-layer (scripts POSIX locais + prosa de SKILL.md; sem
DB/backend/frontend). Unica "borda" e o formato de linha
FINDING/RESULT/DIAG, cuja fonte da verdade sao os contratos em
`contracts/` desta feature.

## Ordem de implementacao sugerida (para create-tasks)

1. **US1 (P1)**: `requirement-coverage.sh` + `test_requirement-coverage.sh`
   + calibracao da stoplist contra specs reais (quickstart Cenario 4)
   → integracao na prosa de `specify` (ETAPA 4) e `checklist` (FR-002).
2. **US2 (P2)**: prosa de triagem em `specify` ETAPA 0 + `clarify`
   ETAPA 2 (sem script).
3. **US3 (P3)**: prosa do archive datado em `review-features` (sem
   script).
4. **US4 (P4)**: `_diag.sh` + `test__diag.sh` → migracao piloto dos 4
   scripts + extensao dos testes existentes (aditivo, um script por
   task para confinar blast radius).

Itens 1-4 sao independentes entre si (podem ser paralelos), exceto a
integracao de prosa do item 1 que depende do script existir.

## Complexity Tracking

Nenhuma violacao de constitution a justificar — tabela omitida
conforme template (preencher apenas se houver violacao).

## Riscos e mitigacoes

| Risco | Mitigacao |
|-------|-----------|
| Heuristica FR-005 gera falso-negativo (bloqueia spec legitima) | threshold via `--min-match`; calibracao obrigatoria contra specs reais do repo antes do merge (quickstart Cenario 4); stoplist embutida revisavel |
| Linha DIAG quebra parser downstream que le stderr | emissao ADITIVA em linha propria prefixada `DIAG\|` — consumidores atuais que fazem match literal continuam casando a mensagem legada |
| Testes literais quebram com scripts-piloto | contrato exige mensagem legada INTACTA + assercao explicita disso nos testes estendidos (SC-006) |
| Gate retroativo bloqueia pipelines de specs antigas em `checklist` | comportamento intencional (Edge Case da spec); mensagem de fix acionavel orienta adicionar cenarios |
