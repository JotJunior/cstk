# Data Model: OTel Model Breakdown na knowledge.db

**Feature**: `otel-model-breakdown` | **Date**: 2026-07-28 | **Phase**: 1

Schema da knowledge.db: **v11 -> v12**. Toda mudanca e aditiva: nenhuma coluna
ou tabela existente e removida, renomeada ou tem tipo alterado (FR-003, FR-009).

Banco: SQLite em `~/.claude/cstk/knowledge.db` (indice derivado e
reconstruivel). Fonte: `.waves[].otel_usage` do `state.json`, escrito uma unica
vez no fechamento da onda (`state-ondas.sh:676`).

## Entity: WaveModelUsage (tabela NOVA)

Grao: **projeto x feature x onda x modelo**. Uma linha por modelo distinto
observado no snapshot OTel de uma onda. Onda sem `otel_usage` ou com
`by_model` vazio nao gera nenhuma linha (FR-004, SC-002).

Nome da tabela: `wave_model_usage`.

| Campo | Tipo | Nulo? | Origem | Notas |
|-------|------|-------|--------|-------|
| `id` | INTEGER | nao | auto | `PRIMARY KEY AUTOINCREMENT` — padrao das demais tabelas |
| `project` | TEXT | nao | derivado da execucao | mesmo valor das outras tabelas de metrica |
| `feature` | TEXT | nao | derivado da execucao | idem |
| `wave` | TEXT | nao | `.waves[].id` | fallback `onda-<indice>`, como em `recall.sh:1104` |
| `execution_id` | TEXT | nao | derivado da execucao | idem demais tabelas |
| `source_ts` | TEXT | nao | `.waves[].started_at` | timestamp da onda; ordenacao cronologica |
| `source_id` | TEXT | nao | chave do objeto `by_model` | = nome bruto do modelo (Decision 3) |
| `model` | TEXT | sim | chave do objeto `by_model` | string BRUTA, sem normalizacao (FR-001) |
| `cost_usd` | REAL | sim | `by_model[<m>].cost_usd` | fracionario; `recall_real_or_null` |
| `total_tokens` | INTEGER | sim | `by_model[<m>].total_tokens` | `recall_int_or_null` |
| `ingested_at` | TEXT | nao | `now` da ingestao | padrao das demais tabelas |

**Constraint**: `UNIQUE(project, feature, wave, source_id)` — identica as demais
tabelas de metrica (`recall.sh:494`, `528`, `544`, `561`, `575`, `602`). Como
`source_id` = modelo, a constraint expressa exatamente o grao onda x modelo.

**Idempotencia**: `ON CONFLICT(project, feature, wave, source_id) DO UPDATE SET`
atualizando `source_ts`, `model`, `cost_usd`, `total_tokens`, `ingested_at`
(Decision 2). Reingerir a mesma onda sobrescreve os mesmos valores; nao
duplica (SC-003).

**Sem indice secundario** (Decision 8) — nenhuma das 11 tabelas existentes tem.

### Consequencia da string bruta

`model` guarda o identificador exatamente como emitido pela telemetria. No
corpus real ha 4 valores distintos: `claude-fable-5`, `claude-opus-5`,
`claude-opus-5[1m]`, `claude-sonnet-5`. `claude-opus-5` e `claude-opus-5[1m]`
sao linhas SEPARADAS mesmo compartilhando o modelo-base — decisao deliberada
(tiers de contexto tem custo por token distinto). Agregar por modelo-base e
responsabilidade da query consumidora.

### Relacionamentos

- **-> `waves`**: por `(project, feature, wave)`. Nao ha foreign key declarada —
  consistente com o resto do schema, que nao usa FK em nenhuma tabela.
  Invariante esperada: `SUM(cost_usd)` das linhas de uma onda deve bater com
  `waves.otel_cost_usd` da mesma onda (validado no quickstart).
- **-> decisoes de roteamento de modelo**: join best-effort e indireto (mesmo
  modelo, mesma onda), como ja descrito nas Key Entities da spec. Nao garantido
  exato, porque o roteamento registra alias canonico e esta tabela registra
  string bruta.

## Entity: Wave (extensao — colunas aditivas em `waves`)

A tabela `waves` (`recall.sh:496-529`) ganha **8 colunas INTEGER**, todas
nullable, com o breakdown de tokens por tipo separado por fonte (FR-002).
Nenhuma coluna existente e tocada.

| Coluna nova | Tipo | Origem no `state.json` |
|-------------|------|------------------------|
| `otel_main_input_tokens` | INTEGER | `otel_usage.by_source.main.input` |
| `otel_main_output_tokens` | INTEGER | `otel_usage.by_source.main.output` |
| `otel_main_cache_read_tokens` | INTEGER | `otel_usage.by_source.main.cache_read` |
| `otel_main_cache_creation_tokens` | INTEGER | `otel_usage.by_source.main.cache_creation` |
| `otel_subagent_input_tokens` | INTEGER | `otel_usage.by_source.subagent.input` |
| `otel_subagent_output_tokens` | INTEGER | `otel_usage.by_source.subagent.output` |
| `otel_subagent_cache_read_tokens` | INTEGER | `otel_usage.by_source.subagent.cache_read` |
| `otel_subagent_cache_creation_tokens` | INTEGER | `otel_usage.by_source.subagent.cache_creation` |

**Nota de nomenclatura**: o JSON usa `cache_read`/`cache_creation` (sem sufixo
`_tokens`); o sufixo existe apenas no nome da coluna, por coerencia com
`otel_total_tokens`/`otel_subagent_tokens` ja presentes (Decision 4).

### Colunas otel PRE-EXISTENTES (inalteradas — FR-009)

`otel_cost_usd`, `otel_cost_main_usd`, `otel_cost_subagent_usd`,
`otel_total_tokens`, `otel_subagent_tokens` (`recall.sh:513-517`) permanecem
com semantica identica. Em particular `otel_subagent_tokens` (total agregado do
subagent, calculado pela soma dos 4 tipos em `recall.sh:1134-1138`) coexiste com
as 4 novas colunas de parcela do subagent. Redundancia intencional: quebrar a
coluna antiga violaria FR-009.

Invariante esperada (nao imposta por constraint):
`otel_subagent_tokens = otel_subagent_input_tokens + otel_subagent_output_tokens
+ otel_subagent_cache_read_tokens + otel_subagent_cache_creation_tokens`
quando todas forem nao-NULL.

## Regra transversal: NULL vs zero (FR-004)

Ausencia de dado -> `NULL`. Zero observado -> `0` preservado.

Mecanica ja existente e reaproveitada sem alteracao:
1. No jq, `// ""` converte ausente/null para string vazia. O operador `//` do jq
   trata apenas `false`/`null`/ausente como falsy — um `0` legitimo **sobrevive**
   e nao vira `""`.
2. No shell, `recall_int_or_null` (`recall.sh:850`) e `recall_real_or_null`
   (`recall.sh:862`) convertem string vazia ou nao-numerica no literal SQL
   `NULL`, e passam numeros adiante — inclusive `0`.

Consequencia por caso do corpus:
- onda sem `otel_usage`: as 8 colunas novas ficam NULL e nenhuma linha em
  `wave_model_usage` (SC-002);
- onda com `by_source` contendo so `subagent`: as 4 colunas `otel_main_*` ficam
  NULL (nao zero) — caso real presente no corpus e coberto pelo Acceptance
  Scenario 2 da US2;
- valor `0` de fato medido: gravado como `0`, distinguivel de ausencia.

## Migracao v11 -> v12

Dois efeitos, ambos idempotentes:

1. **DDL** (`recall_schema_ddl`): adicionar `CREATE TABLE IF NOT EXISTS
   wave_model_usage (...)` e incluir as 8 colunas novas na definicao de `waves`,
   para bancos criados do zero.
2. **ALTER idempotente** (`recall_apply_schema`): bloco novo apos o de v10->v11
   (`recall.sh:758-770`), reusando a variavel `_as_wcols` (lida em
   `recall.sh:724` via `PRAGMA table_info(waves)`, uma unica vez, antes de
   qualquer ALTER), no padrao:
   `case "$_as_wcols" in ''|*'|otel_main_input_tokens|'*) : ;; *) <8 ALTERs> ;; esac`.
   A tabela nova NAO precisa de ALTER: `CREATE TABLE IF NOT EXISTS` no DDL ja
   cobre bancos pre-existentes, porque o DDL roda em toda abertura.

`RECALL_SCHEMA_VERSION` passa de `11` para `12` (`recall.sh:115`), gravado em
`schema_meta` pelo DDL (`recall.sh:617`).

**Sem DROP**: o unico DROP do arquivo e o one-time de `schema_version < 7`
(`recall.sh:678-689`), que nao e tocado por esta migracao.
