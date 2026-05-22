# Implementation Plan: cstk CLI

**Feature**: `cstk-cli` | **Date**: 2026-04-22 | **Spec**: [spec.md](spec.md)

## Summary

A feature introduz `cstk` — CLI POSIX sh para instalar, atualizar e auditar skills
do toolkit em escopo global (`~/.claude/skills/`) ou de projeto (`./.claude/skills/`),
com self-update do proprio binario. Abordagem tecnica: shell script unico orquestrando
`curl` + `tar` + `sha256sum` + `awk`, consumindo GitHub Releases como fonte de verdade
(tarball versionado + checksum), com manifest TSV plain-text para rastrear o estado
instalado. Dependencia opcional em `jq` apenas para o fluxo de hooks em escopo de
projeto (com fallback manual-paste). Arquitetura alinhada com Principios I (SDD
recursivo), II (POSIX puro), IV (zero telemetria) e V (profundidade) da constituicao.

## Technical Context

**Language/Version**: POSIX sh (`#!/bin/sh`, `set -eu`) — compatibilidade com
dash/ash/bash-em-modo-POSIX. Nao usa bash-isms (sem arrays, sem `[[ ]]`, sem `<<<`).
**Primary Dependencies**: Ferramentas POSIX canonicas (`curl`, `tar`, `awk`, `grep`,
`sed`, `mv`, `find`, `mkdir`, `sort`, `date`). SHA: `sha256sum` (linux) ou `shasum -a
256` (macOS) — CLI detecta no boot. Dep OPCIONAL: `jq` (apenas para merge de
`settings.json` em perfis language-*, com fallback).
**Storage**: Filesystem local. Nao ha DB. Manifest em `<scope>/.cstk-manifest` (TSV),
catalog embedded no tarball de release, CLI binario em `~/.local/bin/cstk` +
biblioteca em `~/.local/share/cstk/lib/`.
**Testing**: Suite `tests/` ja existente no repo (POSIX sh puro, ver
`docs/specs/shell-scripts-tests/`). Novo diretorio `tests/cstk/` com scenarios do
`quickstart.md` como testes automatizados. Principio de "um `.sh` novo = um
`test_<nome>.sh` novo" aplica (ver CLAUDE.md).
**Target Platform**: Desktop dev (macOS, Linux). Nao ha plataforma server. Shell
POSIX garante portabilidade; sem dep em GNU extensions alem das ja documentadas em
`cli/lib/compat.sh`.
**Project Type**: CLI (single binary user-space, sem daemon, sem servidor).
**Performance Goals**: Instalacao inicial < 30s em banda larga tipica (SC-001).
Update sem mudancas = zero writes (SC-002). Hash de skill < 100ms por skill em HDD
padrao (20 skills = < 2s total, aceitavel para `doctor` e `update`).
**Constraints**:
- Zero toolchain de build (nao compilar nada) — distribuicao = tarball + `chmod +x`.
- Zero telemetria (Principio IV).
- Zero dependencia obrigatoria fora do POSIX canonico + `curl` + `sha256sum`.
- `jq` e a UNICA dep opcional aceita, exclusivamente para merge de JSON na feature
  de hooks (documentada como Constitution Exception abaixo).
**Scale/Scope**: Single-user, single-machine. Catalog atual = ~20 skills global +
skills language-related (Go, .NET). Ordem de magnitude de crescimento esperado:
< 100 skills ao longo da vida do toolkit. Nada exige otimizacao alem do POSIX
naive.

## Constitution Check

*GATE: Deve passar antes do Phase 0. Re-checar apos Phase 1.*

### First pass (pre Phase 0)

| Principio | Status | Notas |
|-----------|--------|-------|
| I. SDD recursivo | PASS | Esta feature esta no pipeline SDD: spec → clarify → plan (aqui). Create-tasks e analyze virao antes da execucao. |
| II. POSIX sh puro, zero deps | PASS | CLI em POSIX sh; dep obrigatoria apenas em POSIX canonico + `curl`/`tar`/`sha256sum`. `jq` opcional — ver secao Complexity Tracking. |
| III. Formato canonico de skill | N/A | `cstk` e CLI, nao skill. Nao carrega SKILL.md. |
| IV. Zero coleta remota | PASS | Trafego HTTP apenas para GitHub (fetch iniciado pelo usuario); zero analytics/telemetria. |
| V. Profundidade > adocao | PASS | Feature reduz retrabalho documentado no CLAUDE.md (drift source vs installed) — objetivo direto do Principio V. |

### Second pass (pos Phase 1)

| Principio | Status | Notas |
|-----------|--------|-------|
| I. SDD recursivo | PASS | Plan + research + data-model + contracts + quickstart produzidos. Artefatos SDD-completos. |
| II. POSIX sh puro, zero deps | PASS | Design concreto (research Decision 1-3, 7, 8) nao introduz nenhuma violacao. `jq` segue como UNICA exception, escopo confinado, documentada abaixo. Merge de JSON sem `jq` explicitamente REJEITADO em vez de mal-implementado. |
| III. Formato canonico de skill | N/A | Nenhum artefato do design e uma skill. |
| IV. Zero coleta remota | PASS | Todas as chamadas HTTP do design sao fetch explicito de release pelo usuario; nenhuma no background; nenhum metrics endpoint. |
| V. Profundidade > adocao | PASS | Design prioriza semantica solida (manifest versionado, atomic self-update, lock) sobre features "vistosas". Dry-run e doctor existem para reduzir retrabalho, alinhado com Principio V. |

## Project Structure

### Documentation (this feature)

```
docs/specs/cstk-cli/
├── spec.md
├── plan.md              # This file
├── research.md          # Phase 0: 10 decisions
├── data-model.md        # Phase 1: 5 entities
├── contracts/
│   └── cli-commands.md  # Phase 1: 7 commands
└── quickstart.md        # Phase 1: 12 scenarios
```

### Source Code (repository root)

Estrutura-alvo apos implementacao. Paths marcados (NEW) nao existem hoje.

```
/Users/jot/Projects/_lab/Jot/misc/claude-ai-tips/
├── CHANGELOG.md
├── CLAUDE.md
├── README.md
├── docs/
│   ├── 01-briefing-discovery/
│   ├── constitution.md
│   └── specs/
│       ├── cstk-cli/                # (NEW — esta feature)
│       ├── fix-validate-stderr-noise/
│       └── shell-scripts-tests/
├── global/
│   └── skills/                       # (catalog fonte — nao muda nesta feature)
│       ├── advisor/
│       ├── analyze/
│       └── ...
├── language-related/
│   ├── go/
│   │   ├── skills/
│   │   ├── hooks/
│   │   └── settings.json
│   └── dotnet/
├── tests/                             # suite POSIX ja existente
│   ├── run.sh
│   ├── test_<...>.sh                  # tests existentes
│   └── cstk/                          # (NEW) tests do CLI
│       ├── test_install.sh
│       ├── test_update.sh
│       ├── test_self-update.sh
│       ├── test_doctor.sh
│       ├── test_list.sh
│       └── fixtures/                  # releases mockadas, tarballs de teste
└── cli/                               # (NEW) codigo do CLI
    ├── cstk                            # (NEW) script principal, chmod +x
    ├── lib/
    │   ├── common.sh                   # logging, exit codes, util
    │   ├── compat.sh                   # detect sha256sum vs shasum, date formats
    │   ├── http.sh                     # curl wrappers, error mapping
    │   ├── tarball.sh                  # extract, validate, hash-dir (determ. tar)
    │   ├── manifest.sh                 # read/write/update manifest TSV
    │   ├── profiles.sh                 # resolve profile → skill set
    │   ├── lock.sh                     # mkdir lock + trap cleanup
    │   ├── install.sh                  # cmd: install
    │   ├── update.sh                   # cmd: update
    │   ├── self-update.sh              # cmd: self-update
    │   ├── doctor.sh                   # cmd: doctor
    │   ├── list.sh                     # cmd: list
    │   ├── hooks.sh                    # detect jq, merge settings.json or print
    │   └── ui.sh                       # interactive selector
    ├── install.sh                      # (NEW) bootstrap / one-liner target: baixa ultima
    │                                   # release, copia cstk + lib/ para ~/.local/bin e
    │                                   # ~/.local/share/cstk/
    └── README.md                       # (NEW) desenvolvedor-facing, nao user-facing
```

**Structure Decision**: codigo do CLI em `cli/` paralelo a `global/skills/` e
`language-related/`, para deixar claro que CLI e uma entidade separada do catalog.
Subdir `cli/lib/` agrupa scripts modulares — um arquivo por command + arquivos
utilitarios transversais. Isso alinha com o tarball layout da Decision 6 do research,
onde `cli/` e reempacotado inteiro em toda release.

Testes em `tests/cstk/` (novo subdiretorio do `tests/` ja existente) para manter
integracao com `tests/run.sh` e `--check-coverage` (regra do CLAUDE.md: todo `.sh`
em `global/skills/*/scripts/` exige teste; **extenderemos** essa regra para incluir
`cli/lib/*.sh` — anotar em `tasks.md` para atualizar `run.sh`).

## Complexity Tracking

### Optional-dep registry: `jq` em `cli/lib/hooks.sh` (conforme constitution 1.1.0)

**Base legal**: constitution 1.1.0 §Principio II subsecao "Optional dependencies
with graceful fallback" autoriza deps nao-POSIX quando as tres condicoes
cumulativas sao satisfeitas. Abaixo, demonstracao ponto-a-ponto de conformidade:

- **(a) Uso opcional com fallback verificavel**: CLI detecta `jq` via
  `command -v jq`. Sem `jq`, CLI imprime em stderr o bloco JSON exato para paste
  manual no `./.claude/settings.json` do projeto (FR-009d). Fallback coberto por
  teste automatizado 7.1.5 do backlog (Scenario 5 do quickstart — "install
  project sem jq").
- **(b) Confinamento em unico arquivo**: todas as referencias a `jq` residem
  exclusivamente em `cli/lib/hooks.sh`. Verificavel em qualquer momento via
  `grep -rn '\bjq\b' cli/` retornando apenas esse path. Nenhuma outra parte
  do CLI (manifest TSV, profiles, install, update, self-update, doctor, list,
  UI interativa, lock, tarball, hash) referencia `jq`.
- **(c) Declaracao explicita**: esta subsecao do plan.md (primaria), somada a
  FR-009d da [spec.md](spec.md) e a citacao recíproca na
  [constitution](../../../constitution.md) §Principio II subsecao "Optional
  dependencies with graceful fallback" que cita este caso como primeiro concreto.

**Por que o merge JSON exige `jq` quando disponivel**:

- FR-009d requer mesclar hooks da linguagem em `./.claude/settings.json` de um
  projeto sem corromper configs pre-existentes do usuario.
- Mesclagem correta de JSON arbitrario NAO e fazivel em POSIX sh puro com
  seguranca aceitavel. Tentativas com `awk`/`sed` produzem parsers parciais que
  quebram em edge cases (strings com chaves, valores multilinhas, unicode,
  nested objects).
- Sobrescrever arquivo existente foi rejeitada porque apaga configuracao
  nao-relacionada do usuario — pior que nao mesclar.
- Fallback paste-manual satisfaz condicao (a) porque mesmo sem `jq` a CLI
  entrega resultado correto (usuario aplica manualmente), apenas com UX degradada.

**Limites deste registry (nao sao sunset — sao fronteiras)**:

- O carve-out NAO se estende para outras partes do CLI (manifest, profiles,
  catalog). Estes usam TSV plain-text justamente para nao precisar de `jq`.
- Se no futuro um formato JSON for necessario em outra parte, novo caso no
  registry exige nova demonstracao das 3 condicoes naquele arquivo, nao herda
  deste.
- Caso uma solucao POSIX confiavel para merge JSON surja (ex: utility oficial em
  coreutils), considerar migrar e remover o caso do registry.

| Caso registrado | Por Que Necessario | Como satisfaz carve-out 1.1.0 |
|-----------------|-------------------|-------------------------------|
| `jq` opcional em `cli/lib/hooks.sh` | Merge seguro de JSON em settings.json pre-existente do projeto, mantendo config nao-relacionada intacta | (a) fallback paste-manual coberto por teste 7.1.5; (b) confinado em 1 arquivo, grep verificavel; (c) declarado nesta subsecao + spec.md §FR-009d + constitution §II subsecao |

## Outras notas de implementacao

### Self-update: primeira release e bootstrap

Na primeira release publicada, self-update nao tem versao anterior com que
comparar. A primeira instalacao usa um one-liner documentado no README
(`curl <url-ultima-release> | sh`) que baixa o `cli/install.sh` bootstrap. A partir
da segunda release em diante, `cstk self-update` substitui o one-liner.

### Schema versioning do manifest

Header do manifest (`# cstk manifest v1`) permite evoluir formato sem breaking. Se
uma release futura precisar de campo novo: incrementa para `v2`, CLI detecta e migra
automaticamente no primeiro write. CLI antigo lendo manifest `v2` deve abortar com
mensagem clara pedindo self-update.

### Testabilidade de self-update em CI

Scenario 6 e 7 do quickstart exigem release mock. Fixtures em
`tests/cstk/fixtures/releases/` contem tarballs pre-preparados simulando versoes
diferentes. Variavel `CSTK_RELEASE_URL` override permite apontar CLI para fixture
local em vez do GitHub real durante testes.

---

## FASE 12 — Plano do subcomando `cstk 00c <path>`

Plano da FASE 12 (delta sobre o plan original FASES 0-11). Refs:
spec.md §US-5 + FR-016*..h + SC-008/009; research.md Decisions 11-14;
data-model.md §Per-path Lock + §Bootstrap Whitelist File;
contracts/cstk-00c.md; quickstart.md Scenarios 13-16.

### Summary (FASE 12)

Adicionar subcomando `cstk 00c <path>` que cria projeto-alvo do agente-00C,
coleta parametros via prompts interativos e invoca `claude` ja com a slash
command `/agente-00c` montada (auto-submetida como primeiro turno). Atalho
para criar projeto NOVO; retomada de existente fica para `/agente-00c-resume`.

Abordagem tecnica:
- Implementacao 100% POSIX shell em `cli/lib/00c-bootstrap.sh`, dispatcher em
  `cli/cstk`. Sem novas deps de runtime do `cstk` alem das ja existentes (`jq`
  ja era opcional em FR-009d; `cstk 00c` torna obrigatorio via FR-016d).
- Reimplementacao de path-guard, sanitize e whitelist-validate em `cli/lib/`
  (espelhando `agente-00c-runtime/scripts/*.sh`) — Decisao arquitetural
  cravada em Clarifications 2026-05-09 round 2.
- Lock per-path via `mkdir <path>/.cstk-00c.lock/` atomico + trap on EXIT.
- Spawn do `claude` via `exec` com prompt como argv (auto-submit confirmado
  na Decision 11 + smoke manual em tasks 12.7.3 antes do release).

### Constitution Check (FASE 12)

cstk-cli tem governance via Constitution Exception formalizada em FASE 0.
Re-check para FASE 12:

| Principio | Status | Notas |
|-----------|--------|-------|
| **I — POSIX-first portability** | PASS | Implementacao em `sh` puro; `realpath -m` com fallback POSIX (Decision 12); `[ -t 0 ]` POSIX (Decision 13); `trap EXIT INT TERM` POSIX (Decision 14). |
| **II — Exit codes deterministicos** | PASS | Contratos de codigo cravados em contracts/cstk-00c.md (0/1/2/130) + alinhados com convencao do `cstk` existente. |
| **III — Determinismo de release** | PASS | Subcomando NAO altera build de release; tarball continua determinista. |
| **IV — Zero coleta remota** | PASS | `cstk 00c` nao chama rede para telemetria. Unica chamada de rede potencial e o `cstk install` aninhado, que ja respeita FR-010 (apenas GitHub Releases). |
| **V — Carve-outs documentadas** | PASS | `jq` torna-se obrigatorio em FR-016d (versus opcional em FR-009d). Carve-out 1.1.0 ja cobria `jq` em `cli/lib/hooks.sh`; estendemos a justificativa para `cli/lib/00c-bootstrap.sh` na nota abaixo. |

**Carve-out 1.1.0 update (FASE 12)**: `jq` segue como dep opcional do `cstk`
em geral (install/update/doctor/list/self-update/hooks merge), porem **OBRIGATORIO**
em `cstk 00c` por dois motivos: (a) validacao de stack JSON em FR-016c; (b)
o `agente-00c-runtime` que o `cstk 00c` invoca via `/agente-00c` ja precisa
de `jq` para todas as operacoes em `state.json`. Falha cedo em FR-016d (b)
e melhor UX que erro tardio. Adicionar item ao registry:

| Caso registrado | Por Que Necessario | Como satisfaz carve-out 1.1.0 |
|-----------------|-------------------|-------------------------------|
| `jq` obrigatorio em `cli/lib/00c-bootstrap.sh` | Validacao de stack JSON via `jq -e .` (FR-016c) + dep transitiva do agente-00c-runtime invocado por `/agente-00c` | (a) sem fallback porque o orquestrador downstream tambem exige; (b) confinado em 1 arquivo (`cli/lib/00c-bootstrap.sh`) + dep check em FR-016d; (c) declarado em spec.md §FR-016d + Clarifications round 2 + esta subsecao |

### Technical Context (FASE 12)

| Campo | Valor |
|-------|-------|
| Linguagem | POSIX `sh` (mesmo do resto do `cstk`) |
| Deps de build | nenhuma nova |
| Deps de runtime obrigatorias (do `cstk 00c`) | `claude`, `jq`, `realpath` (com fallback POSIX), `git` (transitivo via `agente-00c-runtime`), `mkdir`/`rmdir`/`cp`/`chmod`/`cd` (POSIX core) |
| Plataforma | macOS + Linux (testado via fixtures + smoke manual em ambos) |
| Storage | filesystem-only (lock dir + whitelist file no `<path>`) |
| Testing | `tests/cstk/test_00c-bootstrap.sh` com `claude` mockado em `PATH` (script que loga argv); validacao de scenarios 13-16 via mocks |
| Observabilidade | stderr para prompts/erros; sem logging persistente (sessao curta, debugging via re-run) |

### Project Structure (FASE 12)

Novos arquivos (todos sob `cli/lib/` ou `tests/cstk/`):

```
cli/
├── cstk                                # dispatcher: + `00c) ...`
└── lib/
    └── 00c-bootstrap.sh                # NOVO: helper principal + helpers privados

tests/
└── cstk/
    └── test_00c-bootstrap.sh           # NOVO: cenarios 13-16 + edge cases

docs/specs/cstk-cli/
├── spec.md                             # delta US-5 + FR-016*..h + SC-008/009 (FEITO)
├── tasks.md                            # delta FASE 12 (FEITO)
├── plan.md                             # esta secao (delta FASE 12)
├── research.md                         # Decisions 11-14 (FEITO)
├── data-model.md                       # +2 entities (FEITO)
├── quickstart.md                       # +Scenarios 13-16 (FEITO)
├── contracts/
│   └── cstk-00c.md                     # NOVO: contrato do subcomando (FEITO)
└── checklists/
    └── requirements.md                 # CHK041..065 (FEITO)
```

Estrutura de `cli/lib/00c-bootstrap.sh` (esboco — NAO codigo, apenas
organizacao logica):

```
00c-bootstrap.sh
├── 00c_bootstrap_main      # publico — entry point
├── _00c_parse_args          # parse posicional + --yes/--help
├── _00c_check_tty           # FR-016a — `[ -t 0 ] && [ -t 1 ]`
├── _00c_realpath            # Decision 12 — wrapper portavel
├── _00c_validate_path       # FR-016b — traversal, zonas (espelha path-guard.sh)
├── _00c_acquire_lock        # FR-016h — mkdir atomico + trap
├── _00c_release_lock        # FR-016h — rmdir idempotente
├── _00c_check_dir_empty     # FR-016b — abort se nao-vazio
├── _00c_check_deps          # FR-016d (a)(b)(c) em ordem
├── _00c_prompt_install      # FR-016d (c) — prompt + nested cstk install
├── _00c_read_descricao      # FR-016c (a) — 10-500 chars, sanitize
├── _00c_read_stack          # FR-016c (b) — opcional, jq -e .
├── _00c_read_whitelist      # FR-016c (c) — multi-linha, regex (espelha whitelist-validate.sh)
├── _00c_persist_whitelist   # FR-016f — escrita atomica + chmod 600
├── _00c_dry_run_preview     # FR-016e — resumo formatado
├── _00c_confirm_final       # FR-016e — prompt [Y/n] (--yes pula)
├── _00c_escape_sq           # FR-016g — '` -> `'\''` (espelha sanitize.sh)
└── _00c_exec_claude         # FR-016f — release lock explicito + cd + exec
```

### Phase 0 — Research (FASE 12)

Resolvido em research.md Decisions 11-14:
- D11: spawn do `claude` via `exec` + auto-submit (validado em smoke manual no
  GATE de release)
- D12: `realpath -m` com fallback POSIX (`cd -P` + `dirname/basename`)
- D13: TTY via `[ -t 0 ] && [ -t 1 ]`; stderr explicitamente fora do check
- D14: lock + cleanup via `trap EXIT INT TERM`; release explicito antes do `exec`

Sem unknowns abertos para a FASE 12. Todos os `[NEEDS CLARIFICATION]` foram
resolvidos via 2 rodadas de clarify (sessions 2026-05-09 round 1 e round 2).

### Phase 1 — Design (FASE 12)

| Artefato | Status |
|----------|--------|
| `data-model.md` §Per-path Lock + §Bootstrap Whitelist File | Adicionado |
| `contracts/cstk-00c.md` | Adicionado (sintaxe, args, exit codes, prompts, efeitos colaterais, anti-affordances) |
| `quickstart.md` Scenarios 13-16 (incluindo variantes 16b/c/d) | Adicionado |
| Esboco de `cli/lib/00c-bootstrap.sh` | Documentado em "Project Structure" acima |

### Re-check Constitution (pos-design FASE 12)

Pos-design, sem novas violacoes. Carve-out 1.1.0 atualizada com 1 caso novo
(`jq` obrigatorio em `cli/lib/00c-bootstrap.sh`), justificativa registrada
acima. Outros principios continuam PASS.

### Outstanding (Deferred ao plan ou implementacao)

Items do checklist que ficaram Outstanding (CHK042-045, 047-051, 057, 060, 065)
sao decisoes pequenas que serao resolvidas durante a implementacao:

- **CHK042/043/044** (medicao de SC): operacionalizado em scripts de teste
  do `tests/cstk/test_00c-bootstrap.sh` e no GATE manual da tasks.md 12.7.3.
- **CHK045** (stderr nao-TTY): resolvido em Decision 13 (allowed).
- **CHK047** (zonas inexistentes no host): fallback POSIX do `realpath` em
  Decision 12 ja lida graciosamente — comparacao por prefixo funciona mesmo
  se zona nao existe.
- **CHK048** (unicode/control chars): aceitar printable unicode incluindo
  acentos/emojis; rejeitar bytes < 0x20 exceto LF (que ja esta na blocklist
  explicita). Implementar via verificacao de classe POSIX `[:print:]`.
- **CHK049** (drift regex URL): adotar exatamente o regex e a lista de
  patterns overly-broad de `whitelist-validate.sh` (Clarifications round 2 Q1).
- **CHK050** (versao minima jq): aceitar `jq` 1.5+ (suporte a `jq -e .`
  exit code documentado desde 1.4 oficialmente; 1.5 e baseline universal em
  distros suportadas pelo cstk).
- **CHK051** (`[Y/n]` chars aceitos): `Y/y/yes/sim/s/S/Enter` = sim;
  `n/N/no/nao/Ctrl+D` = nao. Documentar em `cstk 00c --help`.
- **CHK057** (AS dedicado para Ctrl+C): scenario quickstart pode ser
  estendido com Scenario 17 se durante implementacao surgir necessidade;
  por ora, edge case + Variante 16d cobrem.
- **CHK060** (zero bytes exhaustivo): tasks.md 12.5.5 testa via
  comparacao filesystem antes/depois com `find`; gate suficiente.
- **CHK065** (`--help` documenta TTY): tasks.md 12.6.1 ja cravou — texto
  do help inclui pre-requisito TTY explicito.
