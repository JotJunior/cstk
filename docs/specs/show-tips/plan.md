# Implementation Plan: Show Tips

**Feature**: `show-tips` | **Date**: 2026-05-27 | **Spec**: [spec.md](./spec.md)

## Summary

Mecanismo de exibicao de dicas curtas (com exemplos) sobre as skills do toolkit,
exibidas em bloco destacado no inicio de onda do pipeline 00c e sob demanda. O
catalogo e um arquivo unico `tips/catalog.md` (Markdown + frontmatter YAML),
parseado por `awk`/`grep` POSIX. A selecao da dica e pseudoaleatoria via
`/dev/urandom` + `awk` (POSIX — substitui o `$RANDOM` da spec, que e bash-ism).
O mecanismo vive em `cli/lib/show-tip.sh` e e despachado por `cstk show-tip`,
paralelo a `cstk recall`. Tudo fail-silent: nenhuma falha do mecanismo interrompe
uma onda (FR-006/SC-003).

## Technical Context

**Language/Version**: POSIX sh (`#!/bin/sh`, `set -eu`) — alvo `dash`/`sh`
**Primary Dependencies**: nenhuma externa. Ferramentas POSIX: `awk`, `grep`,
`od`, `find`, `printf`, `sed`. (`od`+`/dev/urandom` para entropia; ambos POSIX.)
**Storage**: arquivo de texto `tips/catalog.md` (sem DB, sem estado entre sessoes)
**Testing**: `tests/cstk/test_show-tip.sh` despachado por `tests/run.sh`; lint
estatico via `shellcheck -s sh` (`.github/workflows/shellcheck.yml`)
**Target Platform**: qualquer ambiente POSIX (macOS, Linux/CI ubuntu com `dash`)
**Project Type**: cli / library (script POSIX dentro do `cstk`)
**Performance Goals**: < 1s por invocacao (SC-002)
**Constraints**: zero dependencia externa, zero rede, sem bash-isms (Principio II),
fail-silent total (FR-006)
**Scale/Scope**: 38 skills cobertas (23 global + 15 language-related); >= 2 dicas
cada → catalogo inicial de >= 76 entradas

> **NEEDS CLARIFICATION resolvidos no Phase 0** (research.md): mecanismo de RNG
> POSIX (Decision 1), parsing do catalogo (Decision 2), ponto de integracao
> (Decision 3), descoberta do universo de skills (Decision 4), bloco visual
> (Decision 5). Zero unknowns restantes.

## Constitution Check

*GATE: Deve passar antes do Phase 0. Re-checado apos Phase 1 (ETAPA 7).*

| Principio | Status | Notas |
|-----------|--------|-------|
| I. SDD recursivo (NON-NEGOTIABLE) | PASS | Feature passa por specify→clarify→plan→...; artefatos em `docs/specs/show-tips/` |
| II. POSIX sh puro, zero dep (NON-NEGOTIABLE) | PASS (apos resolucao) | **Tensao resolvida**: spec dec-008 citava `$RANDOM % N` (bash-ism). Phase 0 (research.md Decision 1, dec-012) substitui por `/dev/urandom`+`awk srand` — POSIX puro. Sonda: `shellcheck -s sh` flagou `$RANDOM` como SC3028; alternativa POSIX nao gera warning. Zero dep externa; `od`/`awk` sao POSIX |
| III. Formato canonico de skill | N/A | show-tips e um mecanismo CLI (`cli/lib/show-tip.sh`), nao uma skill SKILL.md. Nao se aplica a anatomia de skill. O catalogo descreve AS skills, mas nao e uma skill |
| IV. Zero coleta remota (NON-NEGOTIABLE) | PASS | Sem rede, sem telemetria. Leitura local de `tips/catalog.md`. SC-002 exige "sem dependencia de rede" |
| V. Profundidade > adocao | PASS | Feature reduz retrabalho (descoberta de skills); sem metrica de adocao remota |
| Quality: scripts POSIX (shellcheck -s sh) | PASS (alvo) | `cli/lib/show-tip.sh` lintado com dialeto sh; meta zero warnings (RNG POSIX evita SC3028) |
| Quality: scripts com teste automatizado | PASS (alvo) | `tests/cstk/test_show-tip.sh` cobre 9 cenarios do quickstart |
| Quality: feature nao-trivial tem spec | PASS | spec.md + plan.md + research.md + data-model.md + contracts + quickstart |
| Quality: SemVer + CHANGELOG | PASS (alvo) | novo subcomando `cstk show-tip` → entrada MINOR no CHANGELOG (adiciona contrato, nao quebra) |
| Quality: nenhum secret em repo | PASS | catalogo so contem dicas publicas sobre skills |

**Resultado do gate**: PASS. A unica tensao (Principio II vs `$RANDOM` da spec)
foi resolvida no Phase 0 sem violar nenhum MUST. Nenhum FAIL em principio MUST.

> **Nota carve-out 1.1.0 (deps opcionais)**: NAO acionado. A feature nao
> introduz dep opcional (sem `jq`/`sqlite3`). `od`+`awk`+`/dev/urandom` sao
> POSIX base, nao deps opcionais. Logo as 3 condicoes cumulativas do amendment
> 1.1.0 sao irrelevantes aqui.

## Project Structure

### Documentation (this feature)

```
docs/specs/show-tips/
├── spec.md          # Existente (onda-001 specify + onda-002 clarify)
├── plan.md          # This file (onda-003 plan)
├── research.md      # Phase 0 output
├── data-model.md    # Phase 1 output
├── quickstart.md    # Phase 1 output
└── contracts/
    └── cli-show-tip.md  # Phase 1 output — contrato CLI
```

### Source Code (repository root — arvore REAL verificada)

```
claude-ai-tips/
├── cli/
│   ├── cstk                 # dispatcher (ADICIONAR case `show-tip` + help)
│   └── lib/
│       ├── recall.sh        # padrao de referencia (recall_main)
│       ├── common.sh        # logging sourced (log_info/warn/error)
│       ├── ui.sh            # helpers de apresentacao (bloco visual)
│       └── show-tip.sh      # NOVO — show_tip_main; mecanismo de exibicao
├── tips/
│   └── catalog.md           # NOVO — catalogo de dicas (>= 76 entradas)
├── global/skills/           # 23 skills (universo de cobertura, parte 1)
├── language-related/
│   ├── go/skills/           # 7 skills (parte 2)
│   └── dotnet/skills/       # 8 skills (parte 3)
└── tests/
    ├── run.sh               # runner (ADICIONAR/auto-descobrir test_show-tip)
    └── cstk/
        └── test_show-tip.sh # NOVO — 9 cenarios do quickstart
```

**Structure Decision**: seguir o padrao estabelecido por `cstk recall`
(dec-009): script unico em `cli/lib/show-tip.sh` despachado por `cli/cstk` via
`show_tip_main`. Catalogo em `tips/catalog.md` na raiz (nova pasta `tips/`),
fora de `cli/` para deixar claro que e conteudo editavel por mantenedor, nao
codigo. Testes em `tests/cstk/` seguindo a convencao `test_<nome>.sh`.

## Convencoes de Borda

N/A — single-layer. A feature e um script CLI POSIX puro que le um arquivo de
texto local e emite texto em stdout. Nao ha fronteira backend↔frontend, DB↔
backend, nem broker↔consumer. Sem serializacao cross-camada, sem case-style
divergente, sem mapper. A unica "borda" e o contrato stdout/exit-code
documentado em `contracts/cli-show-tip.md`, ja explicitado (stdout=dados,
stderr=diagnostico, exit 0 sempre no modo exibicao por FR-006).

## Complexity Tracking

> Sem violacoes de constitution que exijam justificativa. A tensao `$RANDOM` foi
> RESOLVIDA no Phase 0 (nao e uma violacao aceita, e uma substituicao por
> mecanismo POSIX-compliant). Tabela vazia por design.

| Violacao | Por Que Necessario | Alternativa Simples Rejeitada Porque |
|----------|-------------------|--------------------------------------|
| (nenhuma) | — | — |

## Re-check pos-Phase 1 (ETAPA 7)

O design (Phase 1) NAO introduziu complexidade nova:
- Sem 4o componente, sem camada extra, sem dep adicional.
- `show-tip.sh` e um unico arquivo confinado (paralelo a `recall.sh`).
- Catalogo e texto plano; parsing em `awk` (sem novo parser/lib).
- Principios MUST (I, II, IV) permanecem PASS apos design.

**Re-check: PASS.** O plano esta pronto para `/checklist` e `/create-tasks`.

## Artefatos

| Arquivo | Status |
|---------|--------|
| docs/specs/show-tips/plan.md | Criado |
| docs/specs/show-tips/research.md | Criado |
| docs/specs/show-tips/data-model.md | Criado |
| docs/specs/show-tips/contracts/cli-show-tip.md | Criado |
| docs/specs/show-tips/quickstart.md | Criado |

## Proximos Passos

1. `/checklist` — quality gate de requisitos antes de decompor (proxima etapa: checklist)
2. `/create-tasks` — decompor o plano em backlog executavel
3. `/analyze` — validar consistencia spec↔plan↔tasks apos tasks
