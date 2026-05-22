# Implementation Plan: fix-validate-stderr-noise

**Feature**: `fix-validate-stderr-noise` | **Date**: 2026-04-20 | **Spec**: [./spec.md](spec.md)

## Summary

Corrigir as duas ocorrencias do padrao `grep -c || printf '0'` em
`global/skills/validate-docs-rendered/scripts/validate.sh` (linhas 244-245)
pelo padrao seguro `VAR=$(grep -c ...) || VAR=0` — identico ao fix
aplicado em `metrics.sh` no commit `ead1b68`. Adicionar um scenario de
regressao em `tests/test_validate.sh` que captura stderr ao processar
o fixture `docs-site/valid/` e verifica ausencia da string "integer
expression expected".

Escopo cirurgico: 2 linhas de codigo + 1 scenario novo. Contrato externo
de `validate.sh` (exit code, formato de stdout, severidades) permanece
inalterado.

## Technical Context

**Language/Version**: POSIX sh (`#!/bin/sh`), mesmo alvo dos demais scripts
do projeto (validado pela suite ja existente rodando `/bin/sh`).
**Primary Dependencies**: nenhuma nova. Continua `grep`, `awk`, `sed`,
`find`, `mktemp` — ja disponiveis no ambiente e ja exercitados pela suite.
**Storage**: N/A. Feature nao persiste dados.
**Testing**: suite `tests/` ja presente no repositorio (44 scenarios),
incluindo `tests/test_validate.sh` com 6 scenarios. Adicionamos +1.
**Target Platform**: local-only (macOS darwin + Linux POSIX). Idem suite existente.
**Project Type**: correcao cirurgica em script shell existente.
**Performance Goals**: tempo total da suite permanece < 30s (SC-003 da spec
shell-scripts-tests); impacto esperado desta feature: negligivel (<1s).
**Constraints**: preservar contrato externo de `validate.sh` (FR-007).
**Scale/Scope**: 1 arquivo de codigo afetado (`validate.sh`) + 1 arquivo
de teste afetado (`test_validate.sh`). Nenhum outro script touched.

## Constitution Check

*GATE: Deve passar antes do Phase 0. Re-checar apos Phase 1.*

| Principio | Status | Notas |
|-----------|--------|-------|
| I. SDD aplica-se recursivamente (NON-NEGOTIABLE) | PASS | Feature entrando via pipeline completo (spec → plan → create-tasks → execute). Defeito em script existente merece artefato rastreavel. |
| II. POSIX sh puro, zero dep externa (NON-NEGOTIABLE) | PASS | Fix preserva POSIX sh; nao introduz bash-isms nem deps novas. `grep -c` e POSIX. |
| III. Formato canonico de skill | N/A | Feature nao cria/modifica skill — so o script interno de uma skill existente. SKILL.md de `validate-docs-rendered` nao e tocado. |
| IV. Zero coleta remota (NON-NEGOTIABLE) | PASS | Nenhum fetch, nenhuma telemetria. Feature roda 100% local. |
| V. Profundidade > adocao | PASS | E exatamente profundidade — consertar bug latente que o uso real expos durante a entrega de `shell-scripts-tests`. |

Gate passa. Nao ha violacoes de principios MUST. Prosseguindo para design.

## Project Structure

### Documentation (this feature)

```
docs/specs/fix-validate-stderr-noise/
├── spec.md
├── plan.md          # Este arquivo
├── research.md      # Phase 0 — 2 decisoes (padrao de fix + fixture)
└── quickstart.md    # Phase 1 — 5 cenarios de validacao end-to-end
```

Artefatos omitidos por nao aplicarem:

- `data-model.md` — feature nao tem entidades.
- `contracts/` — FR-007 exige preservacao do contrato externo; nenhuma
  nova interface sendo criada.

### Source Code (repository root)

Arquivos impactados pela feature:

```
claude-ai-tips/
├── global/
│   └── skills/
│       └── validate-docs-rendered/
│           └── scripts/
│               └── validate.sh         # MODIFICADO — 2 linhas (244, 245)
└── tests/
    └── test_validate.sh                # MODIFICADO — +1 scenario
```

**Structure Decision**: modificacao in-place, sem novos diretorios.
Razao: feature e correcao de defeito em artefatos existentes, nao adicao
de capacidade. Criar estrutura nova seria ruido.

## Complexity Tracking

Nao aplicavel. Zero violacoes de constitution; fix reusa padrao ja
presente no projeto (`ead1b68` em `metrics.sh`); nenhuma abstracao nova
introduzida.

## Re-check pos-design

Re-verificacao dos 5 principios apos Phase 1:

- Nenhum artefato novo fora do padrao do projeto (spec + research +
  quickstart, omitimos data-model e contracts justificadamente).
- Zero codigo a ser escrito alem do fix de 2 linhas e 1 scenario de teste.
- Nenhum impacto em telemetria, distribuicao, ou layout geral do repo.

Gate continua PASS apos design. Seguro para `/create-tasks`.
