# Implementation Plan: recall-autoconsume

**Feature**: `recall-autoconsume` | **Date**: 2026-05-23 | **Spec**: [spec.md](./spec.md)

## Summary

Fechar o **read-back loop** da memoria de conhecimento cross-feature
(`cstk-knowledge-db`, arquivada). Hoje os orquestradores so ESCREVEM no indice
(`cstk recall --ingest`); a leitura e manual. Esta feature adiciona um **passo
PRE-DECISAO** que, no inicio das fases `specify` e `plan`, deriva termos da
feature corrente, consulta o indice FTS5/bm25 e injeta os top-N achados (com
proveniencia) no contexto do orquestrador ANTES de decidir.

**Abordagem tecnica** (da research): estender `cli/lib/recall.sh` com um novo
modo `recall_mode_context` (`cstk recall --context`), reaproveitando o caminho
FTS5+bm25+`recall_resolve_db`+`fts_phrase_escape` existente. Diferenca-chave vs
modo busca: composicao **OR** dos termos (decidida com evidencia empirica —
AND-implicito da 0 matches sobre keywords kebab; OR da 43), saida markdown
enxuta (1 linha/achado) com teto de bytes, e filtro anti-eco
(`--exclude-feature`). Camada ESTRITAMENTE ADITIVA: busca/`--ingest`/`--reindex`
inalterados. Best-effort/no-op (sem deps, db ausente/corrompido, zero match) e
read-only (FR-012/FR-014). Integracao nos dois orquestradores (`agente-00c-*`)
limitada a specify+plan (FR-010), com Decisao auditavel por consumo efetivo
(FR-016).

## Technical Context

**Language/Version**: POSIX sh puro (shebang `#!/bin/sh`, `set -eu`, sem
bash-isms) — Principio II NON-NEGOTIABLE.
**Primary Dependencies**: nenhuma obrigatoria. Deps **opcionais** sob carve-out
1.1.0: `sqlite3` (FTS5+bm25), `jq` (derivar termos no orquestrador). Reusadas
dos modos existentes — sem dep nova.
**Storage**: SQLite FTS5 read-only (`~/.claude/cstk/knowledge.db`, herdado da
spec arquivada). Sem mudanca de schema.
**Testing**: harness do repo (`tests/run.sh`); cenarios novos em
`tests/cstk/test_recall.sh`. Convencao: script em `cli/lib/recall.sh` mapeia para
`tests/cstk/test_recall.sh`. HOME falso + `CSTK_LIB` (licao v3.17.0); fixtures
octais `\NNN`.
**Target Platform**: CLI local (toolkit `cstk`), macOS/Linux POSIX sh.
**Project Type**: cli / library (extensao de modo em script shell existente).
**Performance Goals**: <=1 invocacao de leitura por fase consumidora; <=2 por
feature (SC-006). Query LIMIT N pequeno, sem rede.
**Constraints**: read-only sobre indice e state.json (FR-014); no-op em 100% das
falhas (SC-003); bloco <= max-bytes em 100% (SC-004); zero coleta remota
(Principio IV).
**Scale/Scope**: ~150-250 linhas novas em `recall.sh` (`recall_mode_context` +
helper OR + usage), ~15 cenarios novos de teste, ~2 blocos de instrucao nos
agents. Indice da ordem de centenas-milhares de rows.

## Constitution Check

*GATE: Deve passar antes do Phase 0. Re-checar apos Phase 1.*

| Principio | Status | Notas |
|-----------|--------|-------|
| I. SDD recursivo (NON-NEGOTIABLE) | PASS | Feature passou por specify -> clarify -> plan (este). Pipeline completo via feature-00c. |
| II. POSIX sh puro (NON-NEGOTIABLE) | PASS | `recall_mode_context` e POSIX sh, `set -eu`, sem bash-isms. Identificadores em ingles. |
| II.bis Deps opcionais (carve-out 1.1.0) | PASS | (a) fallback no-op testado (Cenarios 7-10); (b) confinado em `cli/lib/recall.sh`; (c) declarado aqui + research D9. `sqlite3`/`jq` ja usados pelos modos existentes — sem dep nova. |
| III. Formato canonico de skill | N/A | Feature estende script CLI + agents, nao cria/altera SKILL.md. |
| IV. Zero coleta remota (NON-NEGOTIABLE) | PASS | Estritamente local; leitura de DB local; sem rede (FR-015/FR-021). |
| V. Profundidade sobre adocao | PASS | Fecha o loop existente (read-back) com confinamento de custo (specify+plan apenas); nao adiciona superficie de marketing. |

**Resultado**: PASS em todos os MUST. Prosseguir.

## Project Structure

### Documentation (this feature)

```
docs/specs/recall-autoconsume/
├── spec.md                          # (existente, Clarified)
├── plan.md                          # This file
├── research.md                      # Phase 0 — 10 decisoes
├── data-model.md                    # Phase 1 — entidades de leitura
├── quickstart.md                    # Phase 1 — 15 cenarios de teste
└── contracts/
    └── cstk-recall-context.md       # Phase 1 — contrato do modo --context
```

### Source Code (repository root)

```
cli/
├── cstk                             # binario despachador (ja roteia `recall`)
└── lib/
    └── recall.sh                    # ESTENDER: + recall_mode_context,
                                     #   + fts_query_escape_or (ou param de juncao),
                                     #   + deteccao de --context em recall_main,
                                     #   + entrada de usage. NAO duplicar.
tests/
└── cstk/
    └── test_recall.sh               # ESTENDER: ~15 cenarios novos (quickstart),
                                     #   cada um em HOME real + HOME falso.
global/agents/
├── agente-00c-feature-orchestrator.md  # + passo PRE-DECISAO (specify + plan)
└── agente-00c-orchestrator.md          # + passo PRE-DECISAO (specify + plan)
docs/constitution.md                 # gate (lido, nao alterado)
```

**Structure Decision**: extensao in-place de `cli/lib/recall.sh` (camada
aditiva), NAO arquivo novo — alinhado com FR-019 ("estender sem quebrar busca/
ingest") e com a convencao de teste do repo (1 script -> 1 test file; modo novo
no mesmo arquivo => cenarios no mesmo `test_recall.sh`, sem orfao). Os pontos de
integracao vivem nos dois agents existentes (markdown de instrucao), nao em codigo
shell shipado novo.

## Convencoes de Borda

**N/A — single-layer.** A feature e um modo de CLI em script shell puro (sem
backend↔frontend, sem DB↔DTO, sem broker↔consumer). A unica "borda" e
shell -> sqlite3 (FTS5), ja coberta pelas convencoes existentes de `recall.sh`:
escaping de duas camadas (`fts_phrase_escape` FTS5 + `sql_escape` SQL),
separador de colunas no `.mode list`, e a coluna `feature` UNINDEXED. Nenhuma
convencao de case-style cross-camada se aplica.

## Plano de implementacao (ordem sugerida)

1. **Helper OR**: `fts_query_escape_or` (reusa `fts_phrase_escape` por token,
   junta com ` OR `) OU parametro de juncao em `fts_query_escape` (default AND
   preservado). Teste isolado da composicao.
2. **`recall_mode_context`**: parse de flags (`--context`, `--limit` default 4,
   `--exclude-feature`, `--type`, `--project`, `--db`, `--max-bytes` default
   2000), rejeicao de NUL, validacao `--limit`/`--max-bytes`/`--type`, gates de
   degradacao (reuso), montagem do WHERE (OR + anti-eco + filtros), query via
   `recall_query_sql`, render markdown 1-linha/achado sob teto de bytes.
3. **Despacho**: adicionar `--context` a deteccao de modo em `recall_main`.
4. **Usage**: bloco MODO CONTEXT em `recall_usage`.
5. **Testes**: ~15 cenarios em `test_recall.sh`, cada um HOME real + HOME falso;
   fixtures octais; isolar DB via `--db`/`CSTK_KNOWLEDGE_DB`.
6. **Integracao agents**: bloco PRE-DECISAO em ambos os orquestradores (specify
   + plan), derivacao de termos, `--exclude-feature`, registro de Decisao.
7. **Doc**: atualizar a secao usage/README se aplicavel.

## Complexity Tracking

> Constitution Check passou sem violacoes de MUST. Nenhuma complexidade
> adicional a justificar.

A unica complexidade nova (deps opcionais `sqlite3`/`jq`) e coberta pela
carve-out 1.1.0 ja existente — NAO e violacao, e o mecanismo de conformidade
disciplinado. As tres condicoes cumulativas estao satisfeitas (Constitution
Check linha "II.bis" + research Decision 9):
- (a) fallback no-op testado (quickstart Cenarios 7-10);
- (b) confinado em `cli/lib/recall.sh` (grep por `sqlite3`/`jq` localiza tudo
  num arquivo);
- (c) declarado nesta feature (plan + research) com justificativa, caminho e
  fallback.

## Re-check pos-design (ETAPA 7)

| Principio | Status pos-Phase 1 | Notas |
|-----------|--------------------|-------|
| I/II/III/IV/V | PASS | Design nao introduziu camada/servico/dep nova alem das opcionais ja sob carve-out. Saida markdown e read-only; integracao confinada a specify+plan. |

Design confirmado conforme. NEEDS CLARIFICATION restantes: **0**.

## Artefatos

| Arquivo | Status |
|---------|--------|
| docs/specs/recall-autoconsume/plan.md | Criado |
| docs/specs/recall-autoconsume/research.md | Criado |
| docs/specs/recall-autoconsume/data-model.md | Criado |
| docs/specs/recall-autoconsume/contracts/cstk-recall-context.md | Criado |
| docs/specs/recall-autoconsume/quickstart.md | Criado |

## Proximos Passos

1. `/checklist` — quality gate dos requisitos antes de implementar.
2. `/create-tasks` — decompor este plano em backlog executavel.
3. `/analyze` — validar consistencia spec <-> plan <-> tasks (apos tasks).
