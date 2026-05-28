# Implementation Plan: Constitution Amendment — Optional Dependencies

**Feature**: `constitution-amend-optional-deps` | **Date**: 2026-04-24 | **Spec**: [spec.md](spec.md)

## Summary

Feature documental de governanca: amendment da constitution (1.0.0 → 1.1.0,
MINOR) adicionando subsecao "Optional dependencies with graceful fallback" sob
Principio II que disciplina deps nao-POSIX em tres condicoes cumulativas, alem
de ratificar retroativamente o caso concreto do `jq` em `cli/lib/hooks.sh` da
feature `cstk-cli`. Implementacao = edicao coordenada de dois arquivos Markdown
(`docs/constitution.md` e `docs/specs/cstk-cli/plan.md`) mais re-analise
verificatoria do cstk-cli. Nao envolve codigo executavel, sem build, sem testes
automatizados — apenas edicao textual verificavel por `diff` e `grep`.

## Technical Context

**Language/Version**: Markdown (GitHub-flavored). Nao aplica linguagem de
programacao.
**Primary Dependencies**: nenhuma. Apenas editor de texto e ferramentas de
verificacao POSIX basicas (`grep`, `diff`) para validar SCs.
**Storage**: filesystem local. Arquivos versionados via git; amendment vira
commit + bump de versao.
**Testing**: verificacao manual via checklist do `quickstart.md` (Scenarios 1-6).
Sem suite automatizada — a feature em si e a docs, e os SCs sao observaveis
sobre arquivos estaticos.
**Target Platform**: repositorio git local, renderizacao Markdown em GitHub + VS
Code + mdbook. Links relativos precisam funcionar em todos os tres — Decision 6
do research cobre.
**Project Type**: amendment/governance artifact.
**Performance Goals**: N/A (edicao documental).
**Constraints**:
- SC-005: bloco MUST original do Principio II preservado byte-a-byte — Decision 4
  do research operacionaliza verificacao via `diff` entre snapshot e pos-edit.
- FR-004: amendment e EXPANSAO, nao SUBSTITUICAO — subsecao nova entra entre MUST
  e Rationale, sem tocar texto existente.
- SC-006: exatamente 3 condicoes cumulativas (nem 2, nem 4).
**Scale/Scope**: impacto em 2 arquivos editados + 1 arquivo novo (esta feature).
Re-analise em 1 feature ativa (cstk-cli) expectavelmente elimina 1 finding
CRITICAL.

## Constitution Check

*GATE: Deve passar antes do Phase 0. Re-checar apos Phase 1.*

### First pass (pre Phase 0)

| Principio | Status | Notas |
|-----------|--------|-------|
| I. SDD recursivo | PASS | Esta feature segue o pipeline (`/specify` feito, `/plan` agora). Constitution §Governance manda justamente isso: amendments entram via `docs/specs/constitution-amend-{topico}/`. |
| II. POSIX sh puro | N/A | Feature e edicao documental, nao executa codigo. |
| III. Formato canonico de skill | N/A | Nao e skill. |
| IV. Zero coleta remota | N/A | Edicao local, sem rede. |
| V. Profundidade > adocao | PASS | Reduz retrabalho futuro (SC-001: contribuidor decide em < 5min). Nao persegue adocao externa. |

### Second pass (pos Phase 1)

| Principio | Status | Notas |
|-----------|--------|-------|
| I. SDD recursivo | PASS | Todos os artefatos SDD produzidos: spec, research, data-model, contracts, quickstart, plan. |
| II. POSIX sh puro | N/A | Idem. O design nao introduz codigo. |
| III. Formato canonico de skill | N/A | Idem. |
| IV. Zero coleta remota | N/A | Idem. |
| V. Profundidade > adocao | PASS | Design enxuto (1 subsecao, 3 condicoes, 2 edicoes downstream); resiste a inchar com tabelas prematuras (data-model §Non-entities explicita isso). |

## Project Structure

### Documentation (this feature)

```
docs/specs/constitution-amend-optional-deps/
├── spec.md              # criado (user stories, 10 FRs, 7 SCs)
├── plan.md              # este arquivo
├── research.md          # 6 decisions de Phase 0
├── data-model.md        # 3 entities (Constitution Document, Subsection, Case Registry)
├── contracts/
│   └── amendment-text.md  # texto literal das 4 insertions + Edits A/B downstream
└── quickstart.md        # 6 scenarios de verificacao manual
```

### Source Code (repository root)

Nao ha codigo a produzir. Apenas arquivos documentais afetados:

```
/Users/jot/Projects/_lab/Jot/misc/cstk/
├── docs/
│   ├── constitution.md                          # EDITADO — Insertion Points 1-4
│   └── specs/
│       ├── cstk-cli/
│       │   └── plan.md                          # EDITADO — Edit A (§Complexity Tracking)
│       └── constitution-amend-optional-deps/    # NOVO (esta feature)
│           ├── spec.md
│           ├── plan.md
│           ├── research.md
│           ├── data-model.md
│           ├── contracts/amendment-text.md
│           └── quickstart.md
└── CHANGELOG.md                                 # opcional — linha 1.1.0 constitution amendment
```

**Structure Decision**: amendment e feature documental pura. Feature dir segue o
layout SDD padrao; downstream, apenas constitution e plan do cstk-cli sao
tocados. Evitamos sobrecarga de criar ADR separado — o proprio `spec.md` desta
feature ja e registro historico permanente da decisao (constitution §Governance
estabelece esse padrao para amendments).

## Execution Plan (resumo — detalhado em tasks.md apos /create-tasks)

Tres fases curtas:

1. **F1 — Aplicar amendment**: editar `docs/constitution.md` conforme Insertion
   Points 1-4 do contract. Verificar SC-005/006 via snapshot + diff. Commit
   local com mensagem referenciando esta spec.
2. **F2 — Ratificar primeiro caso (cstk-cli)**: aplicar Edit A em
   `docs/specs/cstk-cli/plan.md` §Complexity Tracking (reescrita para invocar o
   amendment). Verificar SC-002 via re-analise mental de cstk-cli.
3. **F3 — Propagacao e bookkeeping**: atualizar Sync Impact Report marcando o
   item "cstk-cli/plan.md" como resolvido; opcional CHANGELOG.md entry; verificar
   SC-003 contra outras specs ativas (shell-scripts-tests, fix-validate-stderr-noise)
   para garantir zero regressao.

Tres fases lineares, sem paralelismo (F2 depende de F1; F3 depende de F2).

## Complexity Tracking

> Preencher APENAS se Constitution Check tem violacoes que precisam justificativa.

Nao aplicavel — Constitution Check passa em todos os principios relevantes
(I e V como PASS; II, III, IV como N/A para feature documental).

Observacao meta-circular: uma das proprias motivacoes desta feature e permitir
que outras features (como cstk-cli) ENCERREM suas secoes Complexity Tracking
sem violacoes aparentes. Esta feature nao precisa dessa secao porque nao
violates nada; e o amendment, nao um uso do amendment.

## Riscos e mitigacoes

### Risco 1: amendment e revertido no futuro

Se opinion reversa prevalecer ("qualquer dep opcional e indisciplina"), amendment
pode ser revogado via novo amendment (MAJOR se remover subsecao). Mitigacao:
spec preserva raciocinio completo; rollback e reversivel e rastreavel.

### Risco 2: amendment e usado como cavalo de troia

Futuras features podem tentar invocar o carve-out inadequadamente (dep opcional
de fachada, fallback broken, codigo espalhado). Mitigacao: `/analyze` de
cada feature valida as tres condicoes; dependencia deve sobreviver a inspecao
adversarial.

### Risco 3: inconsistencia temporaria entre amendment e cstk-cli/plan.md

Janela entre F1 (amendment aplicado) e F2 (cstk-cli plan atualizado): constitution
cita jq como primeiro caso; cstk-cli plan ainda diz "Violacao". Mitigacao:
Decision 5 do research fixa a ordem; janela e de minutos, dentro de um unico
trabalho de edicao. Commit unico cobrindo ambos os arquivos elimina a janela.

## Notas para `/create-tasks`

- Tasks serao curtas: ~3-4 tarefas, ~10-15 subtarefas totais. Nao ha
  implementacao de codigo — apenas edicao textual verificavel.
- Criticidade majoritariamente `[A]`: amendment e ritualistico-critico para
  governanca, mas nao bloqueia operacao do toolkit.
- Toda subtarefa de edicao tem subtarefa de verificacao correspondente (via
  grep/diff). Paralela ao pattern "toda implementacao tem subtarefa de teste".
