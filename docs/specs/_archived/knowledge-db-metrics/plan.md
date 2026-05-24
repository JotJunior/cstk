# Implementation Plan: Knowledge DB Metrics Ingestion

**Feature**: `knowledge-db-metrics` | **Date**: 2026-05-24 | **Spec**: [spec.md](./spec.md)

## Summary

Expandir a camada de ingestao do indice de conhecimento global
(`~/.claude/cstk/knowledge.db`, FTS5) para derivar **metricas estruturadas** do
`state.json` transacional — alem da busca full-text atual. O futuro `cstk-panel`
(dashboard read-only, **fora de escopo**) consumira essas metricas; esta feature
garante que o repositorio seja a fonte da verdade dos dados ingeridos.

Abordagem tecnica: **estender o esquema SQLite** (bump `RECALL_SCHEMA_VERSION`
1 → 2) com novas tabelas relacionais (`executions`, `waves`, `alert_signals` na
camada A; `tasks`, `events` na camada B), todas alimentadas pela mesma funcao de
ingestao por arquivo (`recall_ingest_state_json`) e reconstruiveis via
`cstk recall --reindex`. O `state.json` e lido somente; nunca escrito. A camada A
(US1+US2) mexe **apenas em `cli/lib/recall.sh`** (baixo risco) e e concluida e
validada antes da camada B (US3), que adiciona instrumentacao de escrita nos
orquestradores `agente-00c`/`feature-00c` (alto risco). O mix de roteamento de
modelos **reusa** `model-routing-report.sh aggregate` (FR-017) sem reimplementar.

## Technical Context

**Language/Version**: POSIX sh puro (`#!/bin/sh`, `set -eu`), conforme Principio II
da constitution. Orquestradores camada B sao agent files Markdown (instrucoes).
**Primary Dependencies**: `sqlite3` (dep opcional confinada, fallback graceful) +
`jq` (dep opcional confinada) + `secrets-filter.sh` (runtime do toolkit) — todas
ja confinadas em `cli/lib/recall.sh`. Camada B reusa `model-routing-report.sh`.
**Storage**: SQLite global em `~/.claude/cstk/knowledge.db` (indice derivado).
Fonte primaria = `state.json` por execucao (lido, nunca tocado).
**Testing**: harness POSIX `tests/run.sh`; cobertura da feature em
`tests/cstk/test_recall.sh` (FR-009). Fixtures de `state.json` sinteticos.
**Target Platform**: ambiente local POSIX do usuario (macOS/Linux); zero rede.
**Project Type**: CLI / biblioteca shell (single-layer — sem backend/frontend).
**Performance Goals**: ingestao best-effort no fim de cada onda; sem SLA rigido.
Reindex O(n) sobre arquivos `state.json` descobertos via `find`.
**Constraints**: indice puramente DERIVADO (FR-001); `state.json` somente leitura
(FR-002); best-effort — ausencia de `sqlite3`/`jq` = exit 0 + aviso (FR-003);
deps confinadas em `recall.sh` (FR-004); texto livre scrubbed (FR-006);
idempotencia por chave natural (FR-008).
**Scale/Scope**: dezenas a centenas de execucoes/ondas por maquina; escala local.

## Constitution Check

*GATE: Deve passar antes do Phase 0. Re-checar apos Phase 1.*

| Principio | Status | Notas |
|-----------|--------|-------|
| I. SDD recursivo (MUST) | PASS | Feature entra pelo pipeline completo: spec → clarify → plan → checklist → create-tasks → analyze → execute-task. Artefatos em `docs/specs/knowledge-db-metrics/`. |
| II. POSIX sh puro (MUST) | PASS | Edicoes em `cli/lib/recall.sh` permanecem `#!/bin/sh` + `set -eu`, sem Bash-isms. `sqlite3`/`jq` sao deps opcionais com fallback graceful (carve-out 1.1.0): (a) feature funciona sem elas → no-op exit 0 (FR-003) coberto por teste; (b) confinadas a UM arquivo (`recall.sh`, FR-004); (c) declaradas neste plan.md (§Optional-dep registry). |
| III. Formato canonico de skill (MUST) | N/A | Feature nao cria/altera skill nova; estende helper de runtime (`recall.sh`) e instrumenta agent files existentes. Sem novo SKILL.md. |
| IV. Zero coleta remota (MUST) | PASS | Toda ingestao e local; indice em `~/.claude/cstk/`. Nenhuma requisicao de rede; nenhum upload. O `cstk-panel` (consumidor remoto potencial) esta explicitamente fora de escopo (FR-005). |
| V. Profundidade > adocao (SHOULD) | PASS | Feature aprofunda capacidade existente (memoria cross-feature) reduzindo retrabalho de auditoria/observabilidade; nao e feature de marketing. |

**Resultado do gate**: PASS em todos os MUST. Prosseguir para Phase 0.

## Optional-dep registry (Principio II, carve-out 1.1.0)

Conformidade cumulativa com as tres condicoes (a)(b)(c) do amendment 1.1.0:

| Dep | (a) Fallback graceful + testado | (b) Confinada em 1 arquivo | (c) Declarada |
|-----|----------------------------------|----------------------------|---------------|
| `sqlite3` | Ausente → `log_warn` + `return $RECALL_EXIT_OK` (exit 0); onda nunca aborta. Coberto por cenario "sem sqlite3" em `tests/cstk/test_recall.sh`. | `cli/lib/recall.sh` (verificavel: `grep -rln 'sqlite3' cli/`). Esta feature NAO espalha a dep para outros arquivos. | Aqui + spec FR-003/FR-004. |
| `jq` | Ausente → `log_warn` + exit 0; ingestao pulada. Coberto por cenario "sem jq". | `cli/lib/recall.sh`. | Aqui + spec FR-003/FR-004. |

Nenhuma dep nova e introduzida por esta feature: `sqlite3`/`jq` ja sao deps
confinadas pre-existentes de `recall.sh`. O escopo apenas adiciona DDL e parsing
sob as mesmas deps ja confinadas.

## Project Structure

### Documentation (this feature)

```
docs/specs/knowledge-db-metrics/
├── spec.md          # Spec clarificada (3 Q&A inline)
├── plan.md          # This file
├── research.md      # Phase 0 output (decisoes tecnicas)
├── data-model.md    # Phase 1 output (entidades + DDL)
├── quickstart.md    # Phase 1 output (cenarios de validacao)
└── contracts/
    ├── recall-ingest-schema.md   # Contrato do DDL v2 + chaves naturais
    └── layer-b-instrumentation.md # Contrato dos campos novos no state.json
```

### Source Code (repository root)

```
claude-ai-tips/
├── cli/
│   ├── cstk                       # Dispatch CLI — wiring de `recall` (sem mudanca
│   │                              #   de contrato CLI; entidades novas sao
│   │                              #   transparentes ao usuario)
│   └── lib/
│       └── recall.sh              # *** EDIT PRINCIPAL (camada A) ***
│                                  #   - RECALL_SCHEMA_VERSION 1 → 2 (FR-007)
│                                  #   - recall_schema_ddl(): + 3 tabelas A
│                                  #     (executions, waves, alert_signals)
│                                  #     + 2 tabelas B (tasks, events)
│                                  #   - recall_ingest_state_json(): + parsing
│                                  #     das entidades novas (chamado por
│                                  #     --ingest E --reindex; ponto unico)
│                                  #   - modo --context: inalterado (entidades
│                                  #     novas nao alimentam FTS de read-back)
├── global/
│   ├── agents/
│   │   ├── agente-00c-orchestrator.md          # *** EDIT camada B (US3) ***
│   │   └── agente-00c-feature-orchestrator.md  # *** EDIT camada B (US3) ***
│   │                              #   - gravar outcome de task (FR-018) em
│   │                              #     execute-task/review-task
│   │                              #   - gravar eventos timeline (FR-020)
│   └── skills/agente-00c-runtime/scripts/
│       └── model-routing-report.sh  # REUSO (FR-017) — sem mudanca; recall.sh
│                                     #   ou consulta derivada chama `aggregate`
└── tests/cstk/
    └── test_recall.sh             # *** EDIT — cobertura entidades novas (FR-009) ***
```

**Structure Decision**: Camada A confinada a `cli/lib/recall.sh` (mais
`test_recall.sh`) — single-file, baixo risco, reversivel. Camada B toca os dois
agent files dos orquestradores (load-bearing) e so comeca apos a camada A estar
verde. Nenhum arquivo novo de codigo e criado; a feature estende artefatos
existentes para preservar o confinamento de deps (Principio II / FR-004).

## Convencoes de Borda

N/A — **single-layer**. A feature e uma extensao de biblioteca shell + DDL SQLite
local, sem fronteira backend↔frontend, sem DTO, sem payload de rede. A unica
"borda" e fonte→indice (`state.json` JSON → linhas SQLite), governada por:

| Camada | Convencao | Validacao | Fonte da verdade |
|--------|-----------|-----------|------------------|
| `state.json` (entrada) | chaves em snake_case (ex: `motivo_termino`, `wallclock_seconds`) | parsing via `jq` (best-effort) | `state-rw.sh` / schema do runtime |
| Colunas SQLite (saida) | snake_case (espelha `state.json`) | DDL idempotente + UNIQUE | `cli/lib/recall.sh::recall_schema_ddl` |
| Chave natural de idempotencia | `(project, feature, wave, source_id)` | constraint `UNIQUE` | DDL existente (espelhado nas tabelas novas) |

Mapper layer: a propria `recall_ingest_state_json` faz o mapping JSON→SQL via
`jq` + `INSERT ... ON CONFLICT`. ORM: nenhum (SQL cru via heredoc, padrao do
arquivo). Validacao Zod: N/A (sem TypeScript).

## Complexity Tracking

> Nenhuma violacao de constitution. Tabela vazia.

| Violacao | Por Que Necessario | Alternativa Simples Rejeitada Porque |
|----------|-------------------|--------------------------------------|
| — | — | — |

## Faseamento incremental (FR-010 — camada A antes de B)

| Fase | Escopo | Arquivos | Risco | Gate de saida |
|------|--------|----------|-------|---------------|
| A.1 (US1) | Tabelas `executions` + `waves`; bump schema v2; ingestao + reindex | `recall.sh`, `test_recall.sh` | Baixo | SC-001, SC-002, SC-004 verdes |
| A.2 (US2) | `alert_signals` (circular + breach); latencia humana; clarify rate; mix de modelos (reuso) | `recall.sh`, `test_recall.sh` | Baixo | SC-005, SC-006, SC-007 verdes |
| B (US3) | Instrumentacao orquestradores (tasks + events); tabelas `tasks` + `events`; ingestao retro-compativel | agent files, `recall.sh`, `test_recall.sh` | Alto | SC-008, SC-009, SC-010 verdes |

Camada B so inicia apos A.1 + A.2 validadas por teste automatizado (SC-008).
