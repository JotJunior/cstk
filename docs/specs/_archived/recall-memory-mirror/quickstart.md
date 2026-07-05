# Quickstart & Test Scenarios: Recall Memory Mirror

**Feature**: `recall-memory-mirror` | **Date**: 2026-05-27 | **Phase**: 1 (Design)

Cenarios de teste para `tests/cstk/test_recall.sh` (FR-015). Cada cenario usa um `--db`
temporario (isolamento) e fixtures de `memory/` controladas via `--state-dir` apontando
para state.json sintetico + dir de memoria sintetico. Mapeiam diretamente os Acceptance
Scenarios da spec e os SC-001..SC-005.

> **Convencao de teste** (herdada de test_recall.sh): cada cenario e uma funcao
> `scenario_mN_<nome>()`; fixtures via `mktemp -d`; bytes crus em fixture usam `\NNN`
> octal (nunca `\xHH` — MEMORY.md feedback_test_printf_octal). Para fixtures de memoria,
> criar `~/.claude/projects/<enc>/memory/` controlando `HOME` apontado para o tmp.

## Cenario M1 — Criacao da tabela `memories` (schema v4)

1. Criar `--db` temporario novo.
2. Rodar `cstk recall --ingest --state-dir <fixture>` (fixture com projeto_alvo_path
   apontando para um HOME tmp com `memory/` populado).
3. **Expected**: `sqlite3 <db> ".tables"` lista `memories`; `SELECT value FROM schema_meta
   WHERE key='schema_version'` retorna `4`.

## Cenario M2 — Ingestao popula `memories` com proveniencia correta (US2 cenario 1)

1. Fixture `memory/` com 3 arquivos: `MEMORY.md`, `feedback_foo.md`, `project_bar.md`.
2. Rodar ingest.
3. **Expected**: `SELECT count(*) FROM memories` = 3; tipos derivados corretos
   (`index`, `feedback`, `project`); `project` = basename do projeto_alvo_path.

## Cenario M3 — Busca unificada retorna memorias sem flag (SC-001, US1 cenario 1)

1. DB com memorias de 2 projetos diferentes (`projA`, `projB`), ambas contendo o termo
   "install".
2. Rodar `cstk recall "install" --db <db>`.
3. **Expected**: stdout inclui linhas `[memory]` de AMBOS os projetos; proveniencia
   (project, slug) visivel.

## Cenario M4 — `--type memory` filtra so memorias (FR-012, US1 cenario 2)

1. DB com memorias E decisions (ambas com termo comum "lock").
2. Rodar `cstk recall "lock" --type memory --db <db>`.
3. **Expected**: stdout contem so linhas `[memory]`; nenhuma `[decision]`.
4. **Negativo**: `cstk recall "lock" --type invalido` → exit 2, msg do enum extendido.

## Cenario M5 — `--project P --type memory` (US1 cenario 3)

1. DB com memorias de `projA` e `projB`.
2. Rodar `cstk recall "termo" --project projA --type memory --db <db>`.
3. **Expected**: so memorias de `projA`.

## Cenario M6 — Idempotencia: re-ingest nao duplica (FR-006, SC-003, US2 cenario 2)

1. Fixture com 3 `.md`. Rodar ingest 2x.
2. **Expected**: `SELECT count(*) FROM memories` = 3 (nao 6); `knowledge_fts` com
   `type='memory'` tambem = 3 (upsert via DELETE+INSERT, sem duplicata em FTS).

## Cenario M7 — Upsert atualiza body quando .md muda (Edge Case)

1. Ingest com `feedback_x.md` body "v1". Reescrever `.md` para "v2". Re-ingest.
2. **Expected**: `SELECT body_scrubbed FROM memories WHERE slug='feedback_x'` contem "v2",
   nao "v1"; ainda 1 unica linha.

## Cenario M8 — Scrub aplica no body (FR-005, US1 cenario 4)

1. Fixture `.md` contendo um padrao que `secrets-filter.sh scrub` mascara (ex: token).
2. Rodar ingest.
3. **Expected**: `SELECT body_scrubbed FROM memories WHERE slug=...` NAO contem o token
   cru (esta scrubbed); o arquivo `.md` original no disco permanece IDENTICO (C-002 —
   comparar hash/conteudo antes e depois).

## Cenario M9 — Degradacao graciosa: sqlite3 ausente (FR-008, SC-004)

1. PATH-stub desacoplado escondendo `sqlite3` do SUT (nao do /usr/bin global — ver
   MEMORY.md feedback_test_path_stub_cannot_hide_usrbin).
2. Rodar ingest (e busca, e list-memories) sem sqlite3.
3. **Expected**: exit 0 em todos; aviso em stderr; nenhuma escrita; nenhum aborto.

## Cenario M10 — `.md` vazio cria entrada sem erro (US2 cenario 4)

1. Fixture com um `.md` de 0 bytes.
2. Rodar ingest.
3. **Expected**: entrada criada com `body_scrubbed=''`; exit 0; sem stderr de erro.

## Cenario M11 — `--reindex` preserva memorias (SC-002, US3 cenario 1)

1. DB populado com N memorias (via ingest). Anotar count.
2. Apagar o DB (`rm`). Rodar `cstk recall --reindex --states-root <root tmp>`.
3. **Expected**: `SELECT count(*) FROM memories` = N novamente; conteudo (scrubbed)
   identico ao anterior.

## Cenario M12 — `--reindex` nao mistura telemetria em memories (US3 cenario 2)

1. DB com memorias + state.json's de telemetria.
2. Rodar reindex.
3. **Expected**: `SELECT DISTINCT type FROM ... ` — nenhuma entrada de `memories` veio do
   state.json; `memories` so contem linhas de origem `.md`.

## Cenario M13 — Projeto sem `memory/` dir no reindex (US3 cenario 3)

1. Root de reindex com um projeto que tem state.json mas NAO tem `~/.claude/projects/
   <enc>/memory/`.
2. Rodar reindex.
3. **Expected**: exit 0; 0 memorias p/ esse projeto; telemetria ingerida normalmente.

## Cenario M14 — `--list-memories` lista sem body (FR-013, US4 cenario 1)

1. DB com 5 memorias de `myproject`.
2. Rodar `cstk recall --list-memories --project myproject --db <db>`.
3. **Expected**: 5 linhas com slug + description; nenhuma contem o body completo.

## Cenario M15 — `--list-memories` sem memorias = vazio exit 0 (US4 cenario 2)

1. DB sem memorias do projeto consultado.
2. Rodar `cstk recall --list-memories --project vazio --db <db>`.
3. **Expected**: stdout vazio; exit 0.

## Cenario M16 — Linha de status do ingest acrescenta `N memories` (CQ2 impacto)

1. Fixture com 2 `.md`. Rodar ingest.
2. **Expected**: stdout do `ingested:` termina com `, 2 memories`; campos existentes
   (decisions, ..., events) inalterados em ordem e valor.

## Cenario M17 — `~/.claude/projects/` inexistente = no-op (Edge Case)

1. HOME tmp sem `~/.claude/projects/`.
2. Rodar ingest.
3. **Expected**: telemetria ingerida; 0 memorias; exit 0; aviso (opcional) stderr.

## Cenario M18 — Sem regressao nos cenarios existentes (SC-005)

1. Rodar a suite completa `./tests/run.sh test_recall`.
2. **Expected**: todos os ~72 cenarios pre-existentes continuam verdes; novos M1-M17
   verdes. Zero quebra.

## Roundtrip / single-layer

N/A — feature single-layer (CLI tool sobre SQLite local + leitura de arquivos). Sem
borda backend↔frontend. Nao ha payload de rede para roundtrip. A "fonte da verdade" e o
arquivo `.md` no disco; o teste de roundtrip equivalente e o **Cenario M11** (reindex
reconstroi do disco e a contagem/conteudo bate).
