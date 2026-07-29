# Implementation Plan: Specs Vivas — Corpus Canonico, Delta Specs no Archive e Staging Explicito

**Feature**: `living-specs` | **Date**: 2026-07-23 | **Spec**: [spec.md](./spec.md)

## Summary

Tres entregas acopladas ao mesmo momento do ciclo de vida (o archive) mais um
hardening independente: (1) secao opcional `## Delta Requirements` no
`spec.md` (ADDED/MODIFIED/REMOVED/RENAMED + Skip auditavel), parseavel
deterministicamente; (2) corpus canonico `docs/specs/current/<capability>.md`
atualizado por `delta-merge.sh` na acao de archive ja existente da skill
`review-features` (merge atomico, bloqueio em conflito, nunca
last-write-wins); (3) gate `delta-gate.sh` no padrao FINDING/RESULT dos
gates v5.22.0 — archive sem delta e invalido salvo skip explicito; (4)
staging por allowlist derivada (`commit-mode.sh snapshot` +
`stage-derived`) substituindo os 3 sites reais de staging amplo (prosa
`git add -A` nos 2 orquestradores + `git add -- .` em
`state-ondas.sh::_so_cmd_git_commit`), com regressao do incidente `.pptx`.

## Technical Context

**Language/Version**: POSIX sh puro (`#!/bin/sh`, `set -eu`) — Constitution II; prosa de skills/agents em Markdown pt-br
**Primary Dependencies**: ferramentas POSIX canonicas (`awk`, `grep`, `sed`, `sort`, `comm`, `mktemp`) + `git` (ja dependencia dura do modo atomic-commit e de `state-ondas.sh git-commit`); zero deps novas
**Storage**: arquivos Markdown (`docs/specs/current/`), sidecar `commit-baseline.txt` no state dir (padrao `tool-call-ticks.log`); nenhum banco
**Testing**: harness `tests/run.sh` (~1678 cenarios); novos `tests/test_delta-gate.sh`, `tests/test_delta-merge.sh`; extensoes em `tests/test_commit-mode.sh` e `tests/test_state-ondas.sh`; `--check-coverage` gateia
**Target Platform**: macOS/zsh + Linux CI (dash) — mesma matriz dos scripts atuais
**Project Type**: toolkit de documentacao/CLI (skills + runtime POSIX)
**Performance Goals**: gate/merge O(tamanho da spec + corpus da capability); sem requisito de latencia formal (acao de archive e rara)
**Constraints**: determinismo byte-a-byte (gate e merge); merge atomico sem mutacao parcial; fail-closed no staging (untracked sem baseline nunca entram); nenhum `git add -A`/`add .` remanescente em codigo ou prosa dos caminhos automaticos
**Scale/Scope**: corpus inicial vazio; ~15 features arquivadas fora de escopo (backfill opcional); 7 features abertas herdarao o gate no archive

## Constitution Check

*GATE: passou antes do Phase 0; re-checado apos Phase 1 (ETAPA 7).*

| Principio | Status | Notas |
|-----------|--------|-------|
| I. SDD recursivo (NON-NEG) | PASS | feature roda o pipeline completo via feature-00c; muda contrato de skills (template specify, review-features, commit-mode) => exige spec + CHANGELOG bump (MINOR; sem BREAKING — secao delta e opcional e subcomandos sao aditivos) |
| II. POSIX sh puro (NON-NEG) | PASS | 3 scripts novos/alterados todos `#!/bin/sh set -eu`; sem jq/bash-isms; `comm`/`sort`/`awk` canonicos; nenhuma dep opcional nova |
| III. Formato canonico de skill | PASS | mudancas em SKILL.md (review-features, specify) mantem progressive disclosure; conteudo pesado vai para `scripts/` e `templates/`; Gotchas atualizadas |
| IV. Zero coleta remota (NON-NEG) | PASS | nenhuma requisicao de rede em nenhum artefato |
| V. Profundidade > adocao | PASS | fecha retrabalho real (corpus evaporando + incidente de staging) |
| VI. Veracidade de dados (NON-NEG) | PASS | todos os fatos do plan verificados no repo nesta sessao (sites de `add -A`, secoes exigidas pelos gates, fluxo de archive); contratos novos marcados [PROPOSTA]; algoritmo de merge NAO copiado do OpenSpec por falta de fonte (clarify) |

**Re-check pos-Phase 1**: nenhuma camada/servico novo introduzido; 2 scripts
novos + 2 subcomandos num helper existente e o minimo para separar veredicto
(read-only) de mutacao (atomica). PASS.

## Project Structure

### Documentation (this feature)

```
docs/specs/living-specs/
├── spec.md
├── plan.md                          # este arquivo
├── research.md                      # Phase 0 — 9 decisoes
├── data-model.md                    # Phase 1 — entidades textuais
├── quickstart.md                    # Phase 1 — 7 cenarios
└── contracts/                       # Phase 1 — todos [PROPOSTA]
    ├── delta-section-format.md
    ├── corpus-format.md
    ├── delta-gate-cli.md
    ├── delta-merge-cli.md
    └── commit-staging-cli.md
```

### Source Code (repository root — paths REAIS verificados)

```
global/
├── agents/
│   ├── agente-00c-feature-orchestrator.md   # EDIT: passos 7.bis/10.qui trocam add -A por stage-derived
│   └── agente-00c-orchestrator.md           # EDIT: 2 sites equivalentes
├── skills/
│   ├── agente-00c-runtime/scripts/
│   │   ├── commit-mode.sh                   # EDIT: + snapshot, + stage-derived
│   │   └── state-ondas.sh                   # EDIT: _so_cmd_git_commit delega staging
│   ├── review-features/
│   │   ├── SKILL.md                         # EDIT: acao de archive ganha gate -> merge -> mover
│   │   └── scripts/
│   │       ├── aggregate.sh                 # (existente, intacto)
│   │       ├── _diag.sh                     # NEW: copia vendored (fonte: runtime)
│   │       ├── delta-gate.sh                # NEW
│   │       └── delta-merge.sh               # NEW
│   └── specify/
│       ├── SKILL.md                         # EDIT: prosa da secao delta (quando preencher)
│       └── templates/feature-spec.md        # EDIT: secao opcional Delta Requirements
docs/specs/current/                          # NEW (nasce vazio; criado pelo 1o merge)
tests/
├── test_delta-gate.sh                       # NEW
├── test_delta-merge.sh                      # NEW
├── test_commit-mode.sh                      # EDIT: regressao FR-017 (fixture untracked alheio)
└── test_state-ondas.sh                      # EDIT: cenario wave-commit endurecido
```

**Structure Decision**: gate+merge vivem na `review-features` porque o
archive e acao dessa skill (research Decision 3); staging vive no
`commit-mode.sh` porque os callers sao os orquestradores e o
`state-ondas.sh` (mesma skill runtime, sourcing same-dir); corpus paralelo a
`_archived/` conforme clarify da spec.

## Convencoes de Borda

N/A — single-layer: toolkit de arquivos Markdown + scripts POSIX; nenhuma
fronteira backend/frontend/DB/broker. Unica "borda" e o formato textual
delta -> corpus, coberto pelos contratos `delta-section-format.md` e
`corpus-format.md` (fonte da verdade: os contratos; parser e gerador nos
scripts derivam deles).

## Riscos e mitigacoes

| Risco | Mitigacao |
|-------|-----------|
| Drift entre a copia vendored de `_diag.sh` e a canonica | cabecalho aponta fonte canonica; contrato DIAG estavel desde v5.22.0; coberta por `tests/test__diag.sh` via mapeamento por nome |
| Baseline de untracked obsoleto (onda longa, operador cria arquivo manualmente durante execucao) | arquivo do operador criado POS-snapshot entraria na allowlist da task — mitigado por documentacao do modo atomic (operador nao deve editar o worktree durante execucao autonoma; ja e pressuposto do modo) e por scope-dirs nos commits de etapa |
| Duas features abertas declarando deltas conflitantes | conflito so materializa no archive (sequencial); o segundo archive bloqueia com `ref-not-found`/`added-collision` — exatamente a politica do clarify |
| `stage-derived` com paths contendo espacos | staging path-a-path com `git add --` e loop while-read (nao word-splitting) — cenario de teste dedicado |
| Prosa dos orquestradores nao atualizada junto (drift codigo/prosa) | tarefa explicita no backlog cobrindo os 4 sites de prosa + grep de verificacao `add -A` zerado em `global/agents/` |

## Complexity Tracking

> Sem violacoes de constitution — tabela vazia.

## Proximos passos

1. `/checklist` — quality gate dos requisitos
2. `/create-tasks` — backlog executavel
3. `/analyze` — consistencia cross-artifact
