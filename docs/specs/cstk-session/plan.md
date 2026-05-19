# Implementation Plan — cstk-session

**Feature**: `cstk-session`
**Spec**: [`spec.md`](spec.md)
**Branch**: TBD (criada por `cstk session start cstk-session` apos
implementacao, ironicamente — meta-uso)
**Status**: Draft

## Summary

Adicionar subcomando `cstk session` ao CLI `cstk` com 4 verbos
(`start`, `list`, `pr`, `end`) que orquestram `git worktree` + `gh`
para permitir sessoes paralelas de desenvolvimento isoladas. Toda a
logica fica em um unico arquivo `cli/lib/session.sh` (~400 LoC POSIX
sh) e e dispatchada pelo padrao ja estabelecido em `cli/cstk`. Zero
state proprio — derivado de `.git/worktrees/`. Zero deps alem de
git (obrigatoria) + gh (opcional para `start`/`list`/`end`; obrigatoria
apenas para `pr`).

Abordagem tecnica resumida da Phase 0:
- **Branch ja mergeada**: `git merge-base --is-ancestor`.
- **Default branch detection**: `git symbolic-ref refs/remotes/origin/HEAD`.
- **Stale worktree**: campo `prunable` em `git worktree list --porcelain`.
- **IDLE days**: `git log -1 --format=%ct` (commit time).
- **`.claude/` filtrado**: `cp -R` seguido de `rm -rf` (POSIX puro).
- **`gh` opcional**: detectado em 2 passos (`command -v gh` +
  `gh auth status`).

## Technical Context

| Campo | Valor |
|-------|-------|
| Linguagem | POSIX sh (shebang `#!/bin/sh`, `set -eu`, sem bash-isms) |
| Build | Nenhum — distribuido como tarball + bootstrap |
| Test | `tests/cstk/test_session.sh` integrado em `tests/run.sh` |
| Storage | Nenhum (state derivado de `.git/worktrees/`) |
| Deps obrigatorias | `git` (>=2.36 — Feb-2022; necessario para campo `prunable` em `git worktree list --porcelain` usado por FR-007), `find`, `grep`, `awk`, `sed`, `date`, `cp`, `rm`, `mkdir`, `printf`, `cat` |
| Deps opcionais | `gh` (>=2.0 — confinado em `cli/lib/session.sh`, conformidade Constitution II amendment 1.1.0; ver Decision 9 do research) |
| Platform | macOS + Linux. Validar `date` portavel (BSD vs GNU). |
| Performance | SC-001: `start` <=3s em repos <=500MB. SC-005: `pr` <=10s incluindo push + gh. |
| Observability | Stdout para resultado, stderr para warnings/erros, exit codes documentados em `contracts/cli-session.md` |
| Security | Validacao de nome rejeita path traversal (regex `^[a-z0-9][a-z0-9-]{0,62}$`); blocklist hardcoded. Sem `eval` de input. |

## Constitution Check

**Constitution version**: 1.1.0 (`docs/constitution.md`).

| Principio | Status | Notas |
|-----------|--------|-------|
| I. SDD recursivo | PASS | Estamos seguindo o pipeline (briefing implicito via discussao, spec+clarify+plan+(tasks pendente)+execute). Feature nao-trivial — artefatos formais obrigatorios. |
| II. POSIX sh, zero deps | PASS com carve-out | `gh` e dep OPCIONAL satisfazendo as 3 condicoes do amendment 1.1.0: (a) fallback graceful em `start`/`list`/`end`, exit code claro em `pr`; (b) confinada em `cli/lib/session.sh`; (c) declarada nesta secao + research §9 + spec §FR-005/FR-009. |
| III. Formato canonico de skill | N/A | Feature e subcomando CLI, nao skill. Padrao aplicavel e o do `cstk` (cli + cli/lib) ja estabelecido. |
| IV. Zero coleta remota | PASS | `gh pr create` faz fetch ao GitHub do usuario para criar PR sob comando explicito. Nao envia telemetria. Demais subcomandos sao 100% locais. |
| V. Profundidade > adocao | PASS | Feature reduz retrabalho real (colisao de sessoes) que afeta o autor. Sem badges, marketing ou polish gratuito. |

**Gate**: PASS. Prosseguir.

## Project Structure

### Documentation

```
docs/specs/cstk-session/
├── spec.md          # User stories, FRs, success criteria + Clarifications
├── plan.md          # Este documento
├── research.md      # Phase 0 — 10 decisoes tecnicas
├── data-model.md    # Entidade Session + invariantes
├── contracts/
│   └── cli-session.md   # Contrato dos 4 subcomandos + exit codes
├── quickstart.md    # 14 cenarios E2E (manual + automatizado)
└── tasks.md         # (criado por /create-tasks)
```

### Source code (mudancas)

```
cli/
├── cstk                       # MODIFICAR: adicionar 'session' ao dispatch
└── lib/
    └── session.sh             # NOVO: ~400 LoC com session_main + helpers

tests/cstk/
└── test_session.sh            # NOVO: cobre cenarios 1-13 do quickstart
                               #       (cenario 11 marcado manual — exige rede)
```

### Source code (NAO modificar)

- `global/skills/` — toolkit de skills, nao afetado.
- `global/agents/` — agentes do agente-00c, nao afetados.
- `tests/` (fora de `tests/cstk/`) — testes de skills, nao afetados.
- `cli/lib/*.sh` (existentes) — install/update/doctor/etc nao mudam.

### Mudancas em `cli/cstk` (dispatcher)

Adicionar `session` na lista de subcomandos validos:

```sh
# Antes (linha ~196 atual):
install|update|self-update|list|doctor)

# Depois:
install|update|self-update|list|doctor|session)
```

Convencao `<cmd>_main` em `cli/lib/<cmd>.sh` ja resolve dispatch
automatico — `session_main` em `cli/lib/session.sh`.

Tambem atualizar `_cmd_help` e mensagem de comandos validos para
incluir `session`.

## Convencoes de Borda

Esta feature e single-layer (CLI tool puramente shell, sem
backend/frontend/DB). Aplicando a diretriz do template:

**N/A — single-layer**.

Nao ha mappers, nao ha API payload, nao ha schema DB. Unica
"convencao de borda" relevante e o **formato JSON do `--json`**
em `list`:

| Campo (JSON) | Tipo | Origem |
|--------------|------|--------|
| `name` | string | derivado |
| `branch` | string | git |
| `path` | string (abs) | git |
| `idleDays` | int (>=0 ou -1 se sem commits) | git log |
| `dirty` | bool | git status |
| `stale` | bool | git worktree prunable |
| `current` | bool | derivado (`git rev-parse --show-toplevel` == path) |

camelCase no JSON (FR-008). Schema validado por
`tests/cstk/test_session.sh::scenario_list_json` parsing campo a
campo (sem jq — POSIX grep ou shell built-in matching).

## Phase 0: Research

Concluida — ver [`research.md`](research.md). 10 decisoes resolvidas:

1. Detectar branch mergeada → `git merge-base --is-ancestor`
2. Detectar gh ausente vs unauth → `command -v` + `gh auth status`
3. Derivar default branch → `git symbolic-ref refs/remotes/origin/HEAD`
4. Detectar stale worktree → campo `prunable`
5. IDLE days → commit time epoch
6. Copiar `.claude/` filtrado → `cp -R` + `rm -rf`
7. Storage de metadados → ZERO (derivado de git)
8. Estrutura do `cli/lib/session.sh` → arquivo unico com 4 funcoes + helpers
9. `gh` como dep opcional → conformidade amendment 1.1.0
10. Validacao de nome → regex + blocklist via case/esac

Zero NEEDS CLARIFICATION pendentes apos Phase 0.

## Phase 1: Design

### 1.1 Data Model
[`data-model.md`](data-model.md) — Entidade `Session` com 9 atributos
derivados, 4 invariantes (INV-1 a INV-4), 4 operacoes (create/read_all/
delete/open_pr). Storage zero.

### 1.2 Contracts
[`contracts/cli-session.md`](contracts/cli-session.md) — 4 subcomandos
+ 1 help. Exit codes: 0,1,2 do cstk + 5,6,7,8,9,10,11,12,13 especificos
da feature (declarados no contrato).

### 1.3 Quickstart
[`quickstart.md`](quickstart.md) — 14 cenarios E2E. Cenario 11 (PR
com rede) marcado manual; cenarios 1-10 e 12-14 automatizados em
`tests/cstk/test_session.sh`.

### 1.4 Re-check Constitution apos Design
**PASS** — design nao introduziu complexidade que viole principios:
- Continua POSIX puro (cp/rm/find/grep — todos POSIX).
- `gh` continua opcional para 3/4 subcomandos.
- Zero coleta remota (gh fetch para repo do usuario sob comando direto).
- Single-layer mantido (sem novas camadas).

## Complexity Tracking

Vazio — nenhuma violacao de constitution requer justificativa.

(Esta secao seria preenchida se algum design choice fosse complexo
o suficiente para precisar de defesa explicita contra Principio II
ou similar. Como `gh` cabe no amendment 1.1.0 carve-out e nao no
Complexity Tracking, esta secao fica vazia.)

## Risks / Open Questions

| # | Risco | Mitigacao |
|---|-------|-----------|
| R1 | `date` em macOS vs Linux: `date -d <iso>` (GNU) nao funciona em BSD/macOS. | Calcular epoch via `date -u +%s` (presente em ambos); diff manual sem `date -d`. Ja eh padrao no projeto. |
| R2 | `cp -R` preserva mtime e symlinks de forma diferente em BSD vs GNU. | Aceitar comportamento padrao de cada plataforma; `.claude/` nao tem symlinks criticos. |
| R3 | `gh auth status` muda formato de output entre versoes. | Usar apenas exit code (0 = auth OK), nao parsear output. |
| R4 | `git worktree list --porcelain` campo `prunable` exige Git >=2.36. | Cravado como minimo na Technical Context. Boot do subcomando valida via `git --version`; <2.36 = exit 1 com mensagem orientando upgrade. |
| R5 | Repo com sub-modulos pode confundir `git worktree add`. | Fora de escopo MVP; documentar como limitacao conhecida na quickstart. |

## Progress Tracking

- [x] Phase 0 — Research (research.md)
- [x] Phase 1 — Design (data-model.md, contracts/, quickstart.md)
- [x] Constitution Check inicial
- [x] Constitution Re-check pos-design
- [ ] Phase 2 — `/create-tasks` para decompor em backlog
- [ ] Phase 3 — `/checklist` para quality gate
- [ ] Phase 4 — `/execute-task` por subcomando
