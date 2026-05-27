# Contract: `cstk recall` — Memory Operations

CLI surface das operacoes de memoria adicionadas ao `cstk recall`. Aditivo ao contrato
existente em `docs/specs/_archived/cstk-knowledge-db/contracts/cstk-recall.md`. Toda a
logica confinada em `cli/lib/recall.sh` (C-001/FR-014). Dispatch em `cli/cstk`.

## Comando 1 — Busca unificada inclui memorias (FR-011, SC-001)

**Command**: `cstk recall <query> [--project P] [--type T] [--limit N] [--db PATH]`
**Mudanca**: NENHUMA mudanca de sintaxe. O comportamento existente passa a incluir
resultados de `type='memory'` automaticamente (a FTS5 `knowledge_fts` agora contem
linhas de memoria).

### Input

| Flag | Tipo | Obrigatorio | Validacao |
|------|------|-------------|-----------|
| `<query>` | string posicional | sim | nao-NUL; escapada FTS5 (fts_query_escape) + SQL |
| `--type` | enum | nao | `decision\|bloqueio\|retro\|skill\|memory` (enum extendido — FR-012) |
| `--project` | string | nao | filtra `AND project = ?` |
| `--limit` | int>0 | nao | default 20 |

### Output (stdout)

Mesma renderizacao de busca existente, agora com linhas `[memory]`:
```
[memory] claude-ai-tips / memory / - / 2026-05-27T18:00:00Z (feedback_code_in_english)
  Codigo em ingles obrigatorio — identificadores em ingles; comentarios podem ser pt
```

> **Trust label (owasp ASI09/LLM01)**: o body de `type='memory'` e conteudo
> UNTRUSTED (notas `.md` autoradas pelo operador, ja scrubbed no ingest). Ele NAO
> e tier de confianca superior aos demais tipos indexados. Consumidores que injetam
> resultados em prompt (read-back loop) DEVEM rotular como UNTRUSTED/nao-autoritativo,
> identico ao rotulo ja aplicado pelo modo `--context`.

### Exit codes

| Exit | Quando |
|------|--------|
| 0 | sucesso (incl. "nenhum resultado", incl. sqlite3 ausente — degradacao graciosa) |
| 2 | uso incorreto (query ausente, --type fora do enum, NUL no input) |

## Comando 2 — Filtro `--type memory` (FR-012, US1 cenario 2)

**Command**: `cstk recall <query> --type memory`
**Comportamento**: retorna APENAS entradas de `memories` (nenhuma decision/bloqueio/
retro/skill). Implementado via `validate_type` aceitando `memory` + filtro `AND type =
'memory'` ja generico no SELECT.

### Validacao

| Caso | Resultado |
|------|-----------|
| `--type memory` | aceito (enum extendido); filtra so memorias |
| `--type invalido` | exit 2, msg `--type fora do enum (decision\|bloqueio\|retro\|skill\|memory)` |

## Comando 3 — Ingestao aditiva de memorias (FR-004/FR-005/FR-006, CQ2)

**Command**: `cstk recall --ingest --state-dir DIR [--db PATH]`
**Mudanca**: NENHUMA mudanca de sintaxe. Ao final do ingest do `state.json`, as memorias
do projeto sao ingeridas automaticamente (passo aditivo via `recall_ingest_memories`).

### Fluxo interno

```
recall_mode_ingest
  ├─ guardas de deps (sqlite3, jq, secrets-filter) — ja existentes
  ├─ recall_apply_schema (agora cria `memories` tambem — v4)
  ├─ recall_ingest_state_json (telemetria — inalterado)
  └─ recall_ingest_memories "$STATE_DIR" "$DB"   ← NOVO (aditivo)
       ├─ le projeto_alvo_path de $STATE_DIR/state.json (jq)
       ├─ project = basename(projeto_alvo_path)
       ├─ encoded = forward-encoding(projeto_alvo_path)
       ├─ memdir = ~/.claude/projects/<encoded>/memory/
       ├─ para cada *.md em memdir:
       │    slug = basename sem .md; type = derive(slug)
       │    description = 1a linha nao-vazia (scrubbed)
       │    body = recall_scrub(conteudo do .md)
       │    upsert memories(project,slug) + upsert knowledge_fts(type='memory')
       └─ acumula RECALL_TOTAL_MEMORY
```

### Output (stdout) — linha de status extendida (impacto CQ2)

```
ingested: 3 decisions, 0 bloqueios, 1 retros, 5 skills, 1 executions, 1 waves, 0 alerts, 0 tasks, 2 events, 5 memories
```
> Apenas `, N memories` e acrescido ao final. Campos existentes inalterados.

### Degradacao graciosa (FR-008, SC-004)

| Condicao | Resultado |
|----------|-----------|
| `sqlite3` ausente | exit 0, aviso stderr, NENHUMA escrita (guarda ja existente) |
| `jq` ausente | exit 0, aviso stderr (guarda ja existente) |
| `secrets-filter.sh` ausente | exit 0, aviso (melhor pular que vazar — guarda existente) |
| `~/.claude/projects/` inexistente | no-op silencioso de memorias, exit 0 (Edge Case) |
| `memory/` dir inexistente p/ o projeto | 0 memorias ingeridas, exit 0 |
| `.md` vazio | entrada criada com `body_scrubbed=''`, sem erro (US2 cenario 4) |

## Comando 4 — Reindex preserva memorias (FR-009/FR-010, C-004, US3)

**Command**: `cstk recall --reindex [--states-root DIR] [--db PATH]`
**Mudanca**: apos reconstruir a telemetria dos `state.json`, varre TODOS os
`~/.claude/projects/*/memory/*.md` e reconstroi a tabela `memories` dos `.md` (NUNCA do
state.json — FR-010).

### Fluxo interno (adicionado a `recall_mode_reindex`)

```
recall_mode_reindex
  ├─ rm -f db (ja existente)
  ├─ recall_apply_schema (cria memories — v4)
  ├─ loop find */state.json -> recall_ingest_state_json (telemetria — inalterado)
  └─ loop find ~/.claude/projects/*/memory/ -> recall_ingest_memories_dir  ← NOVO
       (project = reverse-derivation do encoded-path; ver limitacao CQ1)
```

### Output (stdout) — linha de status extendida

```
reindexed: 4 state files (... , 12 memories)
```

### Invariantes (C-004, SC-002)

| Invariante | Garantia |
|------------|----------|
| reindex reconstroi memorias dos `.md` | varredura de `*/memory/*.md`, nao do state.json |
| reindex NAO apaga memorias permanentemente | recria do disco; contagem identica (SC-002) |
| reindex nao mistura telemetria em `memories` | `memories` so populada por `recall_ingest_memories*` |
| projeto sem `memory/` dir | reindex termina normal, 0 memorias p/ esse projeto (US3 cenario 3) |

### Degradacao graciosa

Mesmas guardas de deps do reindex existente (sqlite3/jq/secrets-filter ausente → exit 0).
O gotcha do `find` exit!=0-com-matches (`|| :`, recall.sh L1698-1707) DEVE ser replicado na
varredura de memorias.

## Comando 5 — Listar memorias (FR-013, US4)

**Command**: `cstk recall --list-memories [--project P] [--db PATH]`
**Comportamento**: lista `slug` + `description` (SEM body) de todas as memorias, ou apenas
do projeto `P`. Modo proprio (`recall_mode_list_memories`), nao busca FTS.

### Input

| Flag | Tipo | Obrigatorio | Notas |
|------|------|-------------|-------|
| `--list-memories` | flag de modo | sim | dispara o modo (detectado em recall_main) |
| `--project` | string | nao | filtra `WHERE project = ?`; sem ela = todos |
| `--db` | path | nao | indice |

### Output (stdout)

Uma linha por memoria: `<project> / <type> / <slug> — <description>`
```
claude-ai-tips / feedback / feedback_code_in_english — Codigo em ingles obrigatorio
claude-ai-tips / index / MEMORY — Indice de memorias do projeto
```

### Exit codes

| Exit | Quando |
|------|--------|
| 0 | sucesso, incl. nenhuma memoria (stdout vazio — US4 cenario 2), incl. sqlite3 ausente |
| 2 | uso incorreto (flag invalida combinada) |

## Help / usage (`cli/cstk` + `recall_usage`)

`recall_usage` (recall.sh) ganha as linhas:
```
  cstk recall --list-memories [--project P] [--db PATH]
```
e a nota sobre `--type memory` e ingestao aditiva de memorias. `cli/cstk` (help dispatch)
nao precisa de mudanca estrutural — o ponteiro para o contrato cobre o detalhe.
