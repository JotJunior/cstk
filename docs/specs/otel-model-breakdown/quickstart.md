# Quickstart: OTel Model Breakdown na knowledge.db

**Feature**: `otel-model-breakdown` | **Date**: 2026-07-28 | **Phase**: 1

Cenarios de validacao contra o **corpus real** em disco. Todos os valores
abaixo foram lidos dos `state.json` reais e conferidos aritmeticamente — nao sao
exemplos ilustrativos (Principio VI).

Testes automatizados vivem em `tests/cstk/test_recall.sh`.

Pre-condicao comum: `sqlite3` e `jq` disponiveis. Sem eles, todo cenario degrada
para "ingestao pulada com aviso, exit 0" (FR-008) — ver Cenario 6.

---

## Cenario 1 — Custo e tokens por modelo, onda com 2 modelos (US1, SC-001, FR-006)

Fonte: `.claude/feature-00c-state/otel-model-breakdown/state.json`, `onda-001`.

1. Ingerir a execucao: `cstk recall --ingest --state-dir <este state-dir>`
2. Consultar: `SELECT model, cost_usd, total_tokens FROM wave_model_usage
   WHERE wave='onda-001' ORDER BY model;`

**Expected**: exatamente 2 linhas, com os valores do `state.json`:

| model | cost_usd | total_tokens |
|-------|----------|--------------|
| `claude-fable-5` | 0.475915 | 375623 |
| `claude-sonnet-5` | 1.21024 | 2143401 |

**Invariantes verificadas** (conferem no corpus):
- `SUM(cost_usd)` = 1.686155 = `otel_usage.total_cost_usd` da onda
- `SUM(total_tokens)` = 2519024 = `otel_usage.total_tokens` da onda
- ambas batem com `waves.otel_cost_usd` / `waves.otel_total_tokens` da mesma onda

**Paridade ingest vs reindex (FR-006)**: este cenario roda pelo caminho
`--ingest` (incremental, o mesmo invocado ao fim de cada onda pelos
orquestradores). O Cenario 7 roda o mesmo corpus por `--reindex`. Os valores
das duas tabelas novas DEVEM ser identicos nos dois caminhos — a assercao de
paridade e o que garante FR-006.

---

## Cenario 2 — Breakdown por fonte com `main` presente (US2, Acceptance 1)

Mesma onda do Cenario 1 (unica no corpus com `by_source.main` populado).

1. Consultar as 8 colunas novas de `waves` para `onda-001`.

**Expected**:

| coluna | valor |
|--------|-------|
| `otel_main_input_tokens` | 3 |
| `otel_main_output_tokens` | 907 |
| `otel_main_cache_read_tokens` | 371775 |
| `otel_main_cache_creation_tokens` | 2938 |
| `otel_subagent_input_tokens` | 31 |
| `otel_subagent_output_tokens` | 30143 |
| `otel_subagent_cache_read_tokens` | 2077276 |
| `otel_subagent_cache_creation_tokens` | 35951 |

**Invariante**: a soma das 4 colunas `otel_subagent_*` = 2143401 =
`otel_subagent_tokens` (coluna pre-existente), confirmando FR-009 — a coluna
antiga continua correta e coerente com as novas.

Taxa de acerto de cache do `main` (objetivo da US2), agora calculavel:
`371775 / (3 + 907 + 371775 + 2938)` = 371775 / 375623.

---

## Cenario 3 — `by_source` sem `main`: NULL, nunca zero (US2, Acceptance 2 / FR-004)

Fonte: `/Users/jot/Projects/_lab/Jot/my-music-match/.claude/feature-00c-state/foundation/state.json`,
`onda-004` — `by_source` contem SOMENTE a chave `subagent`.

1. Ingerir esse state-dir.
2. Consultar as 8 colunas novas para `onda-004`.

**Expected**:
- as 4 colunas `otel_main_*` retornam **NULL** (nao `0`)
- as 4 colunas `otel_subagent_*` retornam: input 108, output 97555,
  cache_read 6756551, cache_creation 221551

Assercao explicita de nao-fabricacao:
`SELECT count(*) FROM waves WHERE wave='onda-004' AND otel_main_input_tokens IS NULL;`
deve retornar `1`.

---

## Cenario 4 — Modelo com sufixo de tier preservado (FR-001 / Decision 5)

Mesma onda do Cenario 3 (unica no corpus com `claude-opus-5[1m]`).

1. `SELECT model, cost_usd, total_tokens FROM wave_model_usage WHERE wave='onda-004' ORDER BY model;`

**Expected**: 2 linhas, com a string bruta preservada literalmente:

| model | cost_usd | total_tokens |
|-------|----------|--------------|
| `claude-opus-5[1m]` | 6.1439 | 6864604 |
| `claude-sonnet-5` | 0.635093 | 211161 |

**Expected (negativo)**: nenhuma linha com `model = 'opus'` ou `model =
'sonnet'` — a ingestao nao normaliza para alias canonico.

**Invariante**: `SUM(cost_usd)` = 6.778993 = `by_source.subagent.cost_usd` da
onda (unica fonte ativa) = `otel_usage.total_cost_usd`.

---

## Cenario 5 — Onda sem telemetria: zero linhas (US1 Acceptance 2 / SC-002)

Fonte: o mesmo `state.json` do Cenario 3 contem ondas com `otel_usage` ausente
(duas, no corpus atual). A onda corrente de qualquer execucao em andamento
tambem esta nesse estado (ainda aberta, `otel_usage` so e escrito no
fechamento).

1. Ingerir a execucao.
2. Consultar `wave_model_usage` para uma dessas ondas.

**Expected**:
- **zero** linhas em `wave_model_usage` para essa onda
- a linha correspondente em `waves` EXISTE (a onda e ingerida normalmente), com
  as 8 colunas novas em NULL
- exit code 0, sem erro nem aviso de falha

---

## Cenario 6 — Degradacao graciosa sem `sqlite3`/`jq` (FR-007, FR-008)

1. Executar `cstk recall --ingest --state-dir <dir>` com `sqlite3` ausente do PATH.

**Expected**: aviso emitido, ingestao pulada, **exit 0** — a onda do
orquestrador nunca aborta. Comportamento identico ao ja existente; as guardas
`recall_have_sqlite3`/`recall_have_jq` (`recall.sh:343`, `:346`) rodam antes de
qualquer codigo novo.

**Expected (confinamento)**: `grep -rl 'sqlite3' cli/lib/` continua retornando
apenas `cli/lib/recall.sh` — nenhum novo ponto de acoplamento (Principio II,
amendment 1.1.0).

---

## Cenario 7 — Reindex reconstroi historico (US3, SC-003)

1. `cstk recall --reindex --states-root ~/Projects`
2. Registrar o resultado de `SELECT count(*), SUM(cost_usd) FROM wave_model_usage;`
3. Rodar `--reindex` uma segunda vez.
4. Repetir a consulta.

**Expected**:
- apos o passo 1, `wave_model_usage` contem linhas para ondas de execucoes
  ANTERIORES a esta feature (o dado vem do `otel_usage` ja gravado no
  `state.json` em disco, nao de estado da knowledge.db anterior — FR-005)
- os resultados dos passos 2 e 4 sao **identicos** (contagem e soma), sem
  duplicacao — garantido pelo `rm -f` do banco em `recall.sh:2398` mais o
  UNIQUE + upsert

---

## Cenario 8 — Migracao aditiva sobre banco v11 existente (FR-003, FR-009)

1. Partir de uma knowledge.db real ja em v11 (com dados).
2. Rodar qualquer comando que abra o banco (ex.: `cstk recall "algo"`).

**Expected**:
- `SELECT value FROM schema_meta WHERE key='schema_version';` retorna `12`
- as 8 colunas novas existem em `waves` (via `PRAGMA table_info(waves)`)
- a tabela `wave_model_usage` existe e esta vazia (nenhuma ingestao ainda)
- **todas** as linhas e colunas pre-existentes continuam intactas e
  consultaveis: contagem de `decisions`, `waves`, `tasks` etc. inalterada
- rodar o mesmo comando uma segunda vez nao falha nem duplica coluna
  (idempotencia do bloco `case`/`PRAGMA table_info`)

---

## Cenario 9 — Suite de regressao (SC-004)

1. `./tests/run.sh test_recall`

**Expected**: 100% verde, incluindo os cenarios anteriores a esta feature.
Lembrete de manutencao: as **12** assercoes de `schema_version = "11"` em
`tests/cstk/test_recall.sh` (linhas 611, 656, 678, 1879, 2195, 2285, 3035,
3161, 3216, 3265, 3337, 3474) precisam ir para `"12"` no mesmo commit do bump,
senao a suite quebra.

---

## Nota de release (GOTCHA)

`cstk install` / `cstk update` atualizam apenas o catalogo (`~/.claude`) e
**nao** tocam `cli/lib/`. Como esta feature altera `cli/lib/recall.sh`, a copia
instalada so muda com:

```sh
cstk self-update --from "file://$PWD/dist/cstk-X.Y.Z-dev.tar.gz"
```

Validar o efeito real rodando `cstk recall` a partir do binario instalado, nao
so do repo.
