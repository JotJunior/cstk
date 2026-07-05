# Implementation Plan: Recall Memory Mirror

**Feature**: `recall-memory-mirror` | **Date**: 2026-05-27 | **Spec**: [spec.md](./spec.md)

## Summary

Espelhar as auto-memorias do Claude Code (arquivos `.md` per-projeto em
`~/.claude/projects/<encoded-path>/memory/`) numa tabela DEDICADA `memories` do
`knowledge.db` (SQLite + FTS5), tornando-as buscaveis cross-projeto via `cstk recall`. A
fonte `.md` permanece canonica/imutavel; o indice e copia DERIVADA, scrubbed na ingestao,
reconstruivel via `--reindex` a partir dos proprios `.md`. Toda a logica e aditiva e
confinada a `cli/lib/recall.sh` (carve-out de deps opcionais 1.1.0). Abordagem tecnica:
reuso maximo da maquinaria existente (FTS5 `knowledge_fts`, `recall_scrub`, `sql_escape`,
guardas de degradacao graciosa, padrao de upsert), bump idempotente de schema v3→v4, e
um passo de ingestao de memorias aditivo dentro do `recall_mode_ingest`/`recall_mode_reindex`
existentes.

## Technical Context

**Language/Version**: POSIX sh (`#!/bin/sh`, `set -eu`) — Principio II
**Primary Dependencies**: `sqlite3` + `jq` + `secrets-filter.sh` (opcionais sob carve-out
1.1.0, confinadas a `cli/lib/recall.sh`; degradacao graciosa quando ausentes)
**Storage**: SQLite single-file global `~/.claude/cstk/knowledge.db` (FTS5); fonte de
leitura = arquivos `.md` em `~/.claude/projects/<encoded-path>/memory/` (read-only)
**Testing**: harness POSIX `tests/run.sh` + `tests/cstk/test_recall.sh` (~72 cenarios
existentes + M1-M18 novos)
**Target Platform**: ambiente local do usuario (macOS/Linux POSIX); zero rede (Principio IV)
**Project Type**: CLI tool (single-layer) sobre indice SQLite local
**Performance Goals**: N/A — ingestao de dezenas de `.md` por projeto, busca FTS5 sub-ms
**Constraints**: scripts POSIX puros; deps opcionais com fallback testado; nenhuma escrita
no `.md` fonte; nenhuma coleta remota; nenhuma mistura telemetria↔memorias (C-003)
**Scale/Scope**: dezenas de projetos × dezenas de memorias = milhares de linhas em
`memories` — trivial para SQLite FTS5

## Constitution Check

*GATE: Deve passar antes do Phase 0. Re-checado apos Phase 1 (ver §Re-check).*

| Principio | Status | Notas |
|-----------|--------|-------|
| I. SDD recursivo (NON-NEGOTIABLE) | PASS | Feature entrou via specify→clarify→plan; spec.md + (futuro) tasks.md em `docs/specs/recall-memory-mirror/`. Contrato de skill nao muda (mesma sintaxe `cstk recall`). |
| II. POSIX sh puro (NON-NEGOTIABLE) | PASS | Toda edicao em `cli/lib/recall.sh` (ja `#!/bin/sh set -eu`). `case` POSIX p/ derivar type; `sed`/`find`/`basename` POSIX. `sqlite3`/`jq`/`secrets-filter` ja sob carve-out 1.1.0 — ver bloco abaixo. |
| II.carve-out 1.1.0 | PASS | (a) uso opcional c/ fallback graceful testado (M9, SC-004); (b) deps confinadas a `cli/lib/recall.sh` (grep `sqlite3`/`secrets-filter` so casa esse arquivo — FR-014); (c) declaradas neste plan.md + spec.md (C-001). Memorias NAO introduzem dep nova: reusam as ja confinadas. |
| III. Formato canonico de skill | N/A | Feature mexe em `cli/lib` + `cli/cstk` (runtime do binario cstk), nao em uma skill SKILL.md. Sem novo SKILL.md. |
| IV. Zero coleta remota (NON-NEGOTIABLE) | PASS | Apenas leitura de arquivos locais + escrita em SQLite local. Nenhum fetch HTTP, nenhuma telemetria. |
| V. Profundidade sobre adocao | PASS | Feature refina capacidade existente (recall) reduzindo retrabalho de "lembrar em qual projeto anotei X"; nao e feature de marketing. |

**Resultado do gate**: PASS em todos os MUST. Nenhuma violacao → §Complexity Tracking vazia.

## Project Structure

### Documentation (this feature)

```
docs/specs/recall-memory-mirror/
├── spec.md                          # specify + clarify (CQ1/CQ2)
├── plan.md                          # This file
├── research.md                      # Phase 0: 9 decisoes resolvidas
├── data-model.md                    # Phase 1: schema `memories` + FTS mapping
├── quickstart.md                    # Phase 1: cenarios M1-M18
└── contracts/
    └── cstk-recall-memories.md      # Phase 1: CLI surface (5 comandos)
```

### Source Code (repository root)

```
cli/
├── cstk                             # dispatch + help (mudanca minima: nota no help recall)
└── lib/
    └── recall.sh                    # ÚNICO arquivo de logica (FR-014). Mudancas:
                                     #   - RECALL_SCHEMA_VERSION 3 -> 4
                                     #   - RECALL_TYPE_ENUM + "memory"
                                     #   - recall_schema_ddl: + CREATE TABLE memories
                                     #   - recall_ingest_memories (NOVA): ingest aditivo
                                     #   - recall_ingest_memories_dir (NOVA): p/ reindex
                                     #   - recall_mode_ingest: chamar recall_ingest_memories
                                     #   - recall_mode_reindex: varrer */memory/ + ingest
                                     #   - recall_mode_list_memories (NOVA): --list-memories
                                     #   - recall_main: dispatch --list-memories
                                     #   - recall_usage: linha --list-memories + nota
tests/cstk/
└── test_recall.sh                   # + cenarios M1-M18 (FR-015)
docs/specs/_archived/cstk-knowledge-db/contracts/cstk-recall.md  # cross-ref (read-only)
```

**Structure Decision**: confinamento total em `cli/lib/recall.sh` (FR-014 / C-001). Nenhum
arquivo novo de runtime — `memories` reusa a maquinaria de `knowledge_fts`, scrub, escaping
e guardas de deps ja presentes. `cli/cstk` recebe apenas ajuste cosmetico de help (o
contrato detalhado fica no doc). Teste no arquivo existente (`test_recall.sh`), preservando
a convencao de cobertura 1:1 (`--check-coverage`).

## Convencoes de Borda

N/A — single-layer. A feature e um CLI tool POSIX sobre um indice SQLite local + leitura de
arquivos `.md`. Nao ha borda backend↔frontend, nem DTO, nem payload de rede, nem case-style
a reconciliar. A unica "fonte da verdade" relevante e o arquivo `.md` no disco (imutavel,
C-002); o indice `memories` e copia derivada e reconstruivel. O equivalente ao teste de
roundtrip e o Cenario M11 (reindex reconstroi do disco; contagem/conteudo batem — SC-002).

## Faseamento de implementacao (ordem sugerida p/ create-tasks)

1. **Schema (v4)**: bump `RECALL_SCHEMA_VERSION`, `RECALL_TYPE_ENUM`, DDL `memories`. Teste
   M1, M4-negativo. Risco baixo (idempotente, aditivo).
2. **Ingestao aditiva**: `recall_ingest_memories` + hook no `recall_mode_ingest` + status
   line. Helpers de derivacao (encoded-path, type, description, scrub). Testes M2, M6-M8,
   M10, M16, M17.
3. **Busca/filtro**: validar busca unificada + `--type memory`. Testes M3, M5 (em grande
   parte ja funciona via FTS; valida e fecha gaps).
4. **Reindex**: varredura `*/memory/*.md` + `recall_ingest_memories_dir` (reverse-derivation
   do project) + gotcha `find || :`. Testes M11-M13.
5. **List**: `recall_mode_list_memories` + dispatch `--list-memories` + help. Testes M14-M15.
6. **Degradacao + regressao**: M9, M18; rodar suite completa.

## Riscos & mitigacoes

| Risco | Mitigacao |
|-------|-----------|
| `find` sob `~/.claude/projects/` retorna exit!=0 com matches validos e zera o indice no reindex (perda de dados) | replicar o padrao `|| :` (nao `|| _x=""`) — recall.sh L1698-1707; coberto por M11 |
| `.md` adversarial (FTS5 injection / SQLi) | body via `recall_scrub` + `sql_escape`; conteudo indexado e documento (nao query), nao precisa fts_phrase_escape; coberto por reuso do pipeline existente |
| Vazamento de secret no indice | `recall_scrub` obrigatorio em description+body ANTES do INSERT; M8 verifica; `.md` original intacto (C-002). NOTA (owasp low): `project`/`slug`/`path` sao estruturados e NAO scrubbed — `path` e absoluto e poderia conter nome de dir sensivel; aceito por paridade c/ telemetria (mitigacao basename), mas registrado. |
| Memory poisoning / indirect prompt injection (ASI06/ASI09/LLM01) | conteudo `.md` e UNTRUSTED e flui p/ prompts via read-back. Mitigacao: (a) scrub no ingest; (b) consumidor rotula como UNTRUSTED/nao-autoritativo (mesmo rotulo do `--context`). Memory NAO e tier de confianca superior aos demais tipos indexados — busca/`--type memory` herdam a mesma postura de rotulagem. |
| NUL / byte de controle em `.md` | `strip_nul` (politica de ingestao ja existente) reusado no caminho de memorias; recomendado cobrir em M8/M10 um `.md` com NUL embutido sem corromper a linha |
| PATH-stub de teste nao esconde sqlite3 de /usr/bin | desacoplar PATH interno do SUT (MEMORY.md feedback_test_path_stub); M9 |
| Inconsistencia de `project` no reindex (underscore) | limitacao documentada e aceita (CQ1); ingest e o caminho principal |

## Complexity Tracking

> Nenhuma violacao de constitution. Tabela vazia.

| Violacao | Por Que Necessario | Alternativa Simples Rejeitada Porque |
|----------|-------------------|--------------------------------------|
| (nenhuma) | — | — |

## Re-check de Constitution (pos-Phase 1)

Re-validado apos o design (data-model + contracts + quickstart):

- **Principio II (POSIX + carve-out)**: o design NAO introduz dep nova nem Bash-ism. As 3
  funcoes novas (`recall_ingest_memories`, `recall_ingest_memories_dir`,
  `recall_mode_list_memories`) usam so `case`, `sed`, `find`, `basename`, `printf`,
  `sqlite3`/`jq`/`secrets-filter` ja confinados. Confinamento (b) preservado: grep dos
  executaveis continua casando so `recall.sh`. PASS mantido.
- **Principio IV (zero rede)**: design e 100% local (arquivos + SQLite). PASS mantido.
- **C-003 (separacao de tabelas)**: tabela dedicada `memories`, populada SO por
  `recall_ingest_memories*`; reindex re-le `.md`, nunca state.json (C-004). PASS.
- **Complexidade**: nenhuma camada/servico novo; 3 funcoes + ajustes de constantes. Sem
  complexidade injustificada. PASS.

Gate final: PASS. Pronto para `/checklist` → `/create-tasks`.
