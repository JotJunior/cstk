# Implementation Plan: Recall Worktree Identity

**Feature**: `recall-worktree-identity` | **Date**: 2026-06-05 | **Spec**: [spec.md](./spec.md)

## Summary

Execucoes de orquestradores dentro de worktrees de `cstk session` gravam
projeto FANTASMA (`cstk-minha-feature`) na knowledge.db, fragmentando busca,
anti-eco e reindex. Correcao em duas frentes (abordagem B+A do operador):
**(B)** o command pai detecta worktree no init (`.git` ARQUIVO +
`git rev-parse --git-common-dir`) e CONGELA `execution.canonical_project` +
`execution.session_name` no state.json via flags novas opcionais do
`state-rw.sh init`; **(A)** a ingestao (`cli/lib/recall.sh`) deriva `project`
(e `feature` no layout agente-00c) em 3 camadas: campo congelado → resolucao
git ao vivo → basename atual (comportamento preservado). Schema knowledge.db
v7→v8 adiciona coluna `session` a `executions`/`waves` via ALTER idempotente;
FTS intocada. Anti-eco `EXCLUDE_FEATURE` dos 2 orquestradores atualizado na
mesma entrega para manter paridade com a ingestao (invariante do bug v4.7.2).

## Technical Context

**Language/Version**: POSIX sh puro (`#!/bin/sh`, `set -eu`) — macOS (BSD userland) + Linux
**Primary Dependencies**: `jq` (dep estabelecida do runtime 00C); `sqlite3` (confinada em `cli/lib/recall.sh`); `git` (invocacao OPCIONAL com fallback graceful — amendment 1.1.0, research Decision 9)
**Storage**: `state.json` transacional (por state-dir) + `~/.claude/cstk/knowledge.db` (SQLite, indice derivado/reconstruivel; schema v7→v8)
**Testing**: harness POSIX `tests/run.sh` — `tests/cstk/test_recall.sh` (ingest/schema/anti-eco), `tests/test_state-rw.sh` (init), fixtures em `/tmp` com `CSTK_KNOWLEDGE_DB` isolado
**Target Platform**: CLI local (toolkit clonado/instalado); zero rede
**Project Type**: cli + runtime de orquestracao (markdown agents + scripts sh)
**Performance Goals**: deteccao de worktree O(1) no caminho comum (`test -f` curto-circuita; git so roda quando `.git` e arquivo); ingest permanece best-effort sem latencia perceptivel por onda
**Constraints**: ingest read-only sobre state.json; degradacao graciosa NUNCA aborta onda (FR-008); sem DROP de dados no schema bump (FR-009); zero regressao para projetos normais (FR-010)
**Scale/Scope**: 2 scripts sh tocados (`state-rw.sh`, `recall.sh`), 2 commands (init), 2 agents (derivacao EXCLUDE_FEATURE), 2 suites de teste; schema bump em DB unico global

## Constitution Check

*GATE (constitution v1.1.0): passou pre-Phase 0; re-checado pos-Phase 1 (Etapa 7) — sem violacoes introduzidas pelo design.*

| Principio | Status | Notas |
|-----------|--------|-------|
| I. SDD recursivo (NON-NEGOTIABLE) | PASS | Feature nao-trivial com pipeline completo: spec.md (clarify C1-C5) → este plan → checklist/create-tasks a seguir. Muda contrato de `state-rw.sh init` (flags ADITIVAS opcionais) e schema do knowledge.db → exige bump de versao + CHANGELOG na entrega (MINOR: aditivo, sem breaking). |
| II. POSIX sh puro (NON-NEGOTIABLE) | PASS | Nenhum bash-ism novo. `git` entra como dep OPCIONAL sob amendment 1.1.0 — condicoes (a) fallback graceful coberto por teste (quickstart 2b/2d), (b) confinamento identificavel por arquivo (research Decision 9), (c) declarada em spec §Decisoes de Infraestrutura + research. `sqlite3` permanece confinada em `cli/lib/recall.sh`. |
| III. Formato canonico de skill | N/A | Nenhuma skill nova/renomeada; mudancas em scripts de runtime, agents (markdown) e lib do cstk. |
| IV. Zero coleta remota (NON-NEGOTIABLE) | PASS | Nenhuma chamada de rede; `git rev-parse` e operacao local de filesystem. Dados permanecem no filesystem do usuario. |
| V. Profundidade sobre adocao | PASS | Correcao de corretude do indice de conhecimento existente — reducao direta de retrabalho (anti-eco quebrado polui contexto de decisao dos orquestradores). |

**Re-check pos-Phase 1**: design nao introduziu camada/servico novo; a unica
funcao nova (`recall_derive_canonical`) CONSOLIDA derivacao hoje duplicada
(ingest state + ingest memories) em uma fonte de verdade — complexidade
liquida reduzida. PASS mantido em todos os principios.

## Project Structure

### Documentation (this feature)

```
docs/specs/recall-worktree-identity/
├── spec.md              # Spec + Clarifications C1-C5 (C5 com erratum — ver research Decision 4)
├── plan.md              # Este arquivo
├── research.md          # Phase 0 — 9 decisoes com rationale + validacao empirica da C5
├── data-model.md        # Phase 1 — campos novos do state.json + schema v8
├── quickstart.md        # Phase 1 — 8 cenarios (roundtrip real, fallbacks, migracao, anti-eco)
└── contracts/
    ├── state-rw-init.md       # init estendido (--canonical-project/--session-name) + contrato do chamador
    └── ingest-derivation.md   # derivacao 3 camadas + schema v8 + paridade anti-eco
```

### Source Code (repository root — paths reais conferidos)

```
cli/lib/recall.sh                                  # (A) derivacao 3 camadas, coluna session, v8
global/skills/agente-00c-runtime/scripts/
├── state-rw.sh                                    # (B) flags --canonical-project/--session-name no init
└── state-validate.sh                              # aceitar chaves novas como opcionais
global/commands/
├── feature-00c.md                                 # (B) deteccao de worktree no init (contrato do chamador)
└── agente-00c.md                                  # (B) idem
global/agents/
├── agente-00c-orchestrator.md                     # EXCLUDE_FEATURE = canonical // basename (paridade)
└── agente-00c-feature-orchestrator.md             # nota de paridade atualizada (short_name inalterado)
tests/
├── cstk/test_recall.sh                            # cenarios quickstart 1-5, 7-8
└── test_state-rw.sh                               # cenario quickstart 6
```

**Structure Decision**: nenhum arquivo novo de codigo — toda mudanca pousa em
arquivos existentes, respeitando o confinamento de deps (sqlite3/git-opcional
so em `recall.sh`) e a fronteira command↔orquestrador (deteccao no command
pai, CRUD burro no `state-rw.sh` — research Decision 3). Entrega dupla:
`cstk self-update` (runtime `cli/lib`) + `cstk update` (catalogo
commands/agents/skills) — divergencia parcial quebra a paridade anti-eco,
documentado como regra dura no contrato de derivacao.

## Convencoes de Borda

Feature atravessa 3 fronteiras: command pai ↔ state.json ↔ ingestao ↔
knowledge.db (+ contrato cruzado com os agents de orquestracao).

| Camada | Convencao | Validacao | Fonte da verdade |
|--------|-----------|-----------|------------------|
| state.json (chaves novas) | EN snake_case: `canonical_project`, `session_name` sob `.execution` (padrao schema-en-migration) | `state-validate.sh` (opcionais); `tests/test_state-rw.sh` | [contracts/state-rw-init.md](./contracts/state-rw-init.md) |
| Flags CLI do init | kebab-case: `--canonical-project`, `--session-name` | parser do `_sr_cmd_init` (exit 2 em uso invalido) | idem |
| knowledge.db v8 | coluna `session TEXT` (NULL = sem sessao) em `executions`/`waves`; FTS sem mudanca | `PRAGMA table_info` no teste de migracao (quickstart 4) | [contracts/ingest-derivation.md §3](./contracts/ingest-derivation.md) |
| Derivacao project/feature | 3 camadas, funcao unica `recall_derive_canonical` | roundtrip real (quickstart 1-2) | [contracts/ingest-derivation.md §1-2](./contracts/ingest-derivation.md) |
| Anti-eco (agents ↔ ingest) | `EXCLUDE_FEATURE` agente-00c = `canonical // basename`; feature-00c = `short_name` | quickstart 5 (roundtrip de exclusao) | [contracts/ingest-derivation.md §4](./contracts/ingest-derivation.md) |
| Naming de worktree | `<parent>/<repo>-<name>` (leitura apenas; inversao para session_name) | quickstart 6 | `cli/lib/session.sh:237-243` (`_session_worktree_path`) |

**Mapper layer**: a funcao `recall_derive_canonical` (recall.sh) e o unico
mapper state.json → colunas do DB para proveniencia; o command pai e o unico
writer dos campos congelados. Sem ORM/auto-mapping (SQL direto via sqlite3,
padrao existente).

## Complexity Tracking

> Sem violacoes de constitution — tabela vazia. A dep opcional `git` NAO e
> excecao: e conformidade via subsecao de carve-out do Principio II
> (amendment 1.1.0), com as tres condicoes demonstradas em research Decision 9.

| Violacao | Por Que Necessario | Alternativa Simples Rejeitada Porque |
|----------|-------------------|--------------------------------------|
| — | — | — |

## Riscos e fronteiras declaradas

- **Erratum C5** (research Decision 4): `feature-00c-state` NAO esta nos
  EXCLUDES do session.sh — states de feature pre-existentes sao copiados para
  a worktree. Nao piora com esta feature; correcao dos EXCLUDES e escopo de
  outra feature. `/analyze` deve promover a correcao textual da C5 na spec.
- **Fronteira do `--reindex`**: nunca reindexara states que viviam apenas em
  worktrees ja removidas (arquivo inexistente). Robustez pos-remocao = ingest
  ao vivo por onda + campo congelado em states sobreviventes (FR-006/SC-003
  lidos sob esta luz — quickstart 7).
- **Registros antigos do DB**: linhas ja ingeridas com nome fantasma NAO sao
  reescritas pelo bump (sem migracao de dados retroativa); `--reindex` sobre
  states ainda existentes corrige na reconstrucao.

## Proximos passos

1. `/checklist` — quality gate dos requisitos
2. `/create-tasks` — decompor em backlog executavel
3. `/analyze` — consistencia cross-artifact (incluir promocao do erratum C5)
