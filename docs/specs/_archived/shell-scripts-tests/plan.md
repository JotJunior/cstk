# Implementation Plan: shell-scripts-tests

**Feature**: `shell-scripts-tests` | **Date**: 2026-04-19 | **Spec**: [./spec.md](spec.md)

## Summary

Construir uma suite de testes automatizada para os 5 scripts `.sh` que
compoem as skills deste repositorio, com entry point unico (`tests/run.sh`),
isolamento por tmpdir, regressao explicita para o bug historico de
`metrics.sh`, e deteccao de scripts orfaos sem teste.

Abordagem tecnica (ver `research.md`): harness proprio em POSIX sh puro,
zero dependencias externas, execucao local-only nesta iteracao. Cada test
case e um arquivo `tests/test_<script>.sh` que faz `source tests/lib/harness.sh`,
define funcoes `scenario_*` e delega ao harness a descoberta, execucao em
subshell com tmpdir dedicado, e consolidacao em saida TAP-like.

## Technical Context

**Language/Version**: POSIX sh (alvo: `/bin/sh` do sistema — em macOS resolve
para bash em modo POSIX, em Debian para dash; ambos sao contratos POSIX validos)
**Primary Dependencies**: nenhuma externa. Usa apenas `find`, `grep`, `awk`,
`mktemp`, `diff` — todos disponiveis em qualquer sistema POSIX que ja roda
os scripts sob teste.
**Storage**: filesystem. Fixtures em `tests/fixtures/` (versionadas). Tmpdirs
efemeros via `mktemp -d`, limpos por trap.
**Testing**: o harness E o proprio sujeito. Self-test minimo garante que os
assertion helpers funcionam (caso trivial: `assert_exit 0 true` passa,
`assert_exit 1 true` falha).
**Target Platform**: macOS (darwin 25.3) e Linux POSIX. Execucao exclusivamente
local nesta iteracao (FR-012).
**Project Type**: test suite para shell tooling (meta-tooling)
**Performance Goals**: suite completa < 30s (SC-003), considerando ~20-30
scenarios entre 5 scripts, cada invocacao de script em ms.
**Constraints**: zero dependencia externa (FR-002, FR-010); zero efeito
colateral fora de `$TMPDIR_TEST` (FR-005); determinismo entre execucoes
consecutivas (FR-007).
**Scale/Scope**: 5 scripts hoje. Expansao esperada linear — cada nova skill
com script adiciona 1 arquivo `test_*.sh` com 3-5 scenarios.

## Constitution Check

Nao existe `docs/constitution.md` neste projeto. Gate pulado. Registrado como
not-applicable; se uma constituicao for adicionada no futuro, este plano
devera ser revalidado.

## Project Structure

### Documentation (this feature)

```
docs/specs/shell-scripts-tests/
├── spec.md
├── plan.md              # Este arquivo
├── research.md          # Phase 0 — 5 decisoes tecnicas
├── data-model.md        # Phase 1 — entidades conceituais (Test Case, Scenario, Fixture, Run Report)
├── quickstart.md        # Phase 1 — 9 cenarios de validacao end-to-end
└── contracts/
    └── runner-cli.md    # Phase 1 — contrato do tests/run.sh e do harness
```

### Source Code (repository root)

Estrutura atual relevante:

```
/Users/jot/Projects/_lab/Jot/misc/cstk/
├── CLAUDE.md
├── README.md
├── CHANGELOG.md
├── global/
│   ├── commands/
│   └── skills/
│       ├── create-tasks/scripts/next-task-id.sh       # alvo
│       ├── create-use-case/scripts/next-uc-id.sh       # alvo
│       ├── initialize-docs/scripts/scaffold.sh         # alvo
│       ├── review-task/scripts/metrics.sh              # alvo
│       └── validate-docs-rendered/scripts/validate.sh  # alvo
└── docs/
    └── specs/
        └── shell-scripts-tests/        # esta feature
```

Estrutura a ser adicionada por esta feature:

```
tests/
├── run.sh                  # Entry point unico — descoberta, execucao, sumario
├── lib/
│   └── harness.sh          # source'ado pelos test_*.sh: assert_*, run_all_scenarios, gestao de tmpdir
├── fixtures/
│   ├── tasks-md/
│   │   ├── empty.md                # sem checkboxes (regressao do bug metrics)
│   │   ├── only-done.md            # so [x]
│   │   ├── mixed.md                # [ ] [x] [~] [!] em proporcoes conhecidas
│   │   └── with-phases-tasks.md    # fases e tarefas numeradas
│   ├── ucs/
│   │   ├── empty/                  # dir sem UCs
│   │   └── with-auth/              # UCs existentes para dominio AUTH
│   └── docs-site/
│       ├── valid/                  # md valido para validate.sh
│       └── broken-mermaid/         # mermaid com sintaxe quebrada
├── test_metrics.sh         # 1:1 com global/skills/review-task/scripts/metrics.sh
├── test_next-task-id.sh    # 1:1
├── test_next-uc-id.sh      # 1:1
├── test_scaffold.sh        # 1:1
└── test_validate.sh        # 1:1
```

**Structure Decision**: `tests/` na raiz do repositorio (central), nao
colocalizado em cada skill.

Razao: o runner precisa de um entry point unico (FR-002) e a deteccao de
orfaos (FR-009) fica trivial quando `tests/` tem todos os `test_*.sh` num
lugar so. Colocalizar em `global/skills/<name>/tests/` espalharia a suite
por 5 diretorios e exigiria que `tests/run.sh` crawlaesse o repo — overhead
sem beneficio. Alem disso, fixtures sao compartilhadas entre test cases
(ex: `tasks-md/empty.md` serve tanto `test_metrics.sh` quanto um futuro teste
de skill que consuma tasks.md), e um diretorio central as torna reutilizaveis.

Convencao de nome `test_<basename>.sh` casando com o script-alvo mantem a
governanca de FR-009 simples: comparar `find global/skills -name '*.sh'`
com `find tests -name 'test_*.sh'` e reportar o delta.

## Complexity Tracking

Nao aplicavel. Sem constitution para violar e nenhuma decisao introduzida
foi "fora do padrao". A unica escolha nao-obvia foi harness proprio em vez
de bats-core; essa decisao e justificada em `research.md` (Decision 1) e
nao constitui complexidade adicional — ao contrario, evita uma dependencia
externa.

## Re-check pos-design

Sem constitution → nada a re-checar. Design final:

- Mantem zero dependencias externas (alinhado ao estilo do repo: scripts
  POSIX sh sem toolchain exotico).
- Mantem a feature inteira local e reproduzivel offline.
- Mantem o escopo dentro do que a spec pediu (5 FRs de testes + 1 FR de
  governanca + 1 de isolamento + requisitos nao-funcionais).
- Nao introduz servico, processo, cron, ou dependencia de rede.
