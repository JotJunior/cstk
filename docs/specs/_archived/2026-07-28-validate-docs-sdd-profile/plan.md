# Implementation Plan: validate-docs-sdd-profile

**Feature**: `validate-docs-sdd-profile` | **Date**: 2026-07-10 | **Spec**: [./spec.md](./spec.md)

## Summary

Adicionar dois perfis de validacao — spec-profile e plan-profile — a skill
`validate-documentation`, cobrindo os artefatos do proprio pipeline SDD
(`spec.md` e a familia `/plan`: `plan.md`, `research.md`, `data-model.md`,
`quickstart.md`, `contracts/*.md`), hoje sem checklist nativo (a skill so
conhece o perfil UC e o `--runbook`). Abordagem tecnica (Phase 0): um NOVO
script POSIX deterministico `global/skills/validate-documentation/scripts/validate-sdd.sh`
como motor, com a prosa do `SKILL.md` documentando acionamento e gotchas —
espelhando o arranjo ja existente em `create-tasks` e `validate-docs-rendered`
(script + SKILL.md). Acionamento por deteccao automatica de path
(`docs/specs/<feature>/...`) + flags explicitas `--sdd-spec`/`--sdd-plan`,
com fail-safe "perfil indeterminado" (exit 2) fora da convencao. Severidade
reusa a taxonomia canonica Erro/Aviso/Info da skill (so Erro bloqueia → exit
1). Os checks derivam dos criterios JA documentados em `specify`
(`examples/spec-bad.md`) e `plan` (templates + convencao
`[PROPOSTA — a validar na implementacao]`) — a feature nao inventa criterios,
so os torna nativamente verificaveis. Fronteira de nao-duplicacao com
`analyze` (cross-artifact) e `validate-docs-rendered` (renderizacao/links no
disco) documentada como checklist (SC-005).

## Technical Context

**Language/Version**: POSIX sh (Constitution II — sh puro, sem bashismos)
**Primary Dependencies**: nenhuma obrigatoria — apenas coreutils/grep/sed ja
usados pelos scripts existentes do toolkit. `jq` NAO e necessario (o motor
opera sobre texto Markdown, nao JSON).
**Storage**: N/A (motor stateless; sem persistencia — ver `data-model.md`)
**Testing**: harness POSIX do projeto (`tests/run.sh`), novo
`tests/test_validate-sdd.sh` (convencao `global/skills/*/scripts/<n>.sh` →
`tests/test_<n>.sh`, gateado por `./tests/run.sh --check-coverage`)
**Target Platform**: CLI local (macOS/zsh dev + Ubuntu CI), invocado por
operador e pelos orquestradores `agente-00c`/`feature-00c`
**Project Type**: extensao de skill (single-layer tooling)
**Performance Goals**: N/A — validacao de UM arquivo texto, sincrona, sub-segundo
**Constraints**: POSIX sh puro; zero dependencia externa obrigatoria
(Constitution II); nao alterar os perfis UC/`--runbook` existentes
**Scale/Scope**: 1 script novo + prosa no `SKILL.md` + 1 arquivo de teste; ~2
perfis, ~13 finding codes

Nenhum `[NEEDS CLARIFICATION]` remanescente — FR-013 foi resolvido na fase
clarify (dec-004); as demais decisoes de implementacao estao em `research.md`.

## Constitution Check

*GATE: Deve passar antes do Phase 0. Re-checar apos Phase 1.*

Constitution v1.2.0 (6 principios; VI = Veracidade de Dados / Zero Fabricacao).

| Principio | Status | Notas |
|-----------|--------|-------|
| I. SDD recursivo (NON-NEGOTIABLE) | PASS | A propria feature segue o pipeline SDD (spec → clarify → plan → …); alem disso ENTREGA mais SDD-enforcement (checklist nativo para artefatos SDD). |
| II. Scripts POSIX sh puros, zero dep externa (NON-NEGOTIABLE) | PASS | Motor e POSIX sh puro; `jq` nao requerido; sem dependencia obrigatoria (nem o carve-out de "optional deps with fallback" e necessario). |
| III. Formato canonico de skill (progressive disclosure, gotchas, description-trigger) | PASS | Script e o motor; `SKILL.md` continua a interface em prosa com gotchas e triggers, como `create-tasks`/`validate-docs-rendered`. |
| IV. Zero coleta remota (NON-NEGOTIABLE) | PASS | Validacao 100% local; nenhuma telemetria, nenhuma chamada de rede. |
| V. Profundidade e reducao de retrabalho | PASS | Substitui grep ad-hoc por gate deterministico reusavel (SC-006), reduzindo retrabalho dos orquestradores. |
| VI. Veracidade de dados — zero fabricacao (NON-NEGOTIABLE) | PASS | O plan-profile ENFORCA o Principio VI (FR-010: contrato deve ser rotulado real-vs-proposto). Os artefatos deste plano nao afirmam contrato real inventado — a CLU do script e marcada `[PROPOSTA — a validar na implementacao]`; fixtures citam artefato REAL verificado (`enforced-guards`). |

Nenhum FAIL em principio MUST → **gate liberado**. Sem entradas em Complexity
Tracking (nenhuma violacao a justificar).

## Project Structure

### Documentation (this feature)

```
docs/specs/validate-docs-sdd-profile/
├── spec.md          # WHAT/WHY (pronto; FR-013 resolvido em clarify)
├── plan.md          # This file
├── research.md      # Phase 0 output — 6 decisoes de design
├── data-model.md    # Phase 1 output — N/A persistente (tooling)
├── quickstart.md    # Phase 1 output — 12 cenarios de aceitacao
└── contracts/
    └── validate-sdd-cli.md   # Contrato da CLI do motor [PROPOSTA]
```

### Source Code (repository root — arvore real, alvos da implementacao)

```
global/skills/validate-documentation/
├── SKILL.md                       # EDITAR: documentar spec-profile + plan-profile,
│                                  #   acionamento (--sdd-spec/--sdd-plan + auto-path),
│                                  #   catalogo de findings, gotchas, §Fronteira
├── evals/                         # (existente; possivel eval nova — opcional)
└── scripts/                       # CRIAR (diretorio ainda nao existe)
    └── validate-sdd.sh            # CRIAR: motor POSIX (contrato em contracts/)

tests/
└── test_validate-sdd.sh          # CRIAR: cobre validate-sdd.sh (gate --check-coverage)
                                   #   fixtures boas = docs/specs/enforced-guards/{spec,plan}.md
```

Skills de fronteira (NAO alteradas — apenas referenciadas pela §Fronteira):
`global/skills/analyze/`, `global/skills/validate-docs-rendered/`.

**Structure Decision**: seguir o padrao script+SKILL.md ja usado por
`create-tasks` e `validate-docs-rendered`. Criar `scripts/` sob
`validate-documentation` (hoje inexistente) e um teste-irmao em `tests/`,
satisfazendo a "Regra de ouro" do `CLAUDE.md`. Os perfis UC e `--runbook`
permanecem prosa-apenas e intocados.

### §Fronteira de responsabilidade (SC-005)

Checklist canonico de quem-faz-o-que (reproduzido no `SKILL.md` na
implementacao). Detalhe e rationale em `research.md` Decision 4:

- **validate-documentation (spec/plan-profile — esta feature)**: secoes
  obrigatorias de UM artefato; anti-padroes de conteudo de `spec.md`;
  placeholder/rotulo/`[NEEDS CLARIFICATION]` residual em `/plan`; existencia
  SEMANTICA de ID `FR-`/`SC-` citado (FR-012).
- **validate-docs-rendered**: resolucao de link/anchor no DISCO (arquivo
  existe, header casa — §2.2), Mermaid, frontmatter YAML, code-block sem
  linguagem (FR-013/FR-018).
- **analyze**: cobertura cross-artifact (tasks vs requisitos, duplicacao,
  gaps, drift de terminologia, alinhamento com constitution), Pass G
  (convencoes de borda) (FR-018/Out of Scope).

## Convencoes de Borda

**N/A — single-layer.** Feature de tooling POSIX que le um arquivo de texto e
emite achados em stdout. Nao atravessa fronteira backend↔frontend, DB↔backend
nem broker↔consumer; nao ha DTO, payload de API, coluna de banco nem
serializacao cross-camada onde uma convencao de case (snake vs camel)
pudesse divergir. O unico "contrato de borda" e o formato de saida
machine-readable (`FINDING|...`/`RESULT|...`), definido em
`contracts/validate-sdd-cli.md`.

## Complexity Tracking

> Preencher APENAS se Constitution Check tem violacoes que precisam justificativa.

Nenhuma violacao de constitution — tabela vazia.

## Re-check pos-design (ETAPA 7)

Design Phase 1 nao introduziu complexidade nova: continua 1 script POSIX puro
+ prosa + 1 teste, zero dependencia externa, zero rede, zero persistencia. Os
6 principios MUST/SHOULD permanecem PASS. O plan-profile reforca o Principio
VI em vez de tensiona-lo. **Re-check: PASS.**

## Artefatos

| Arquivo | Status |
|---------|--------|
| docs/specs/validate-docs-sdd-profile/plan.md | Criado |
| docs/specs/validate-docs-sdd-profile/research.md | Criado |
| docs/specs/validate-docs-sdd-profile/data-model.md | Criado (N/A documentado) |
| docs/specs/validate-docs-sdd-profile/quickstart.md | Criado |
| docs/specs/validate-docs-sdd-profile/contracts/validate-sdd-cli.md | Criado ([PROPOSTA]) |

## Proximos Passos

1. `/checklist` — quality gate dos requisitos antes de decompor.
2. `/create-tasks` — decompor em backlog (criar `validate-sdd.sh`, editar
   `SKILL.md`, criar `tests/test_validate-sdd.sh`, afinar wordlist contra
   `spec-bad.md` ate SC-002).
3. `/analyze` — apos tasks, validar consistencia spec ↔ plan ↔ tasks.
