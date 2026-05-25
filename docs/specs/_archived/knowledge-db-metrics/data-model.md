# Data Model: Knowledge DB Metrics Ingestion

**Feature**: `knowledge-db-metrics` | **Phase**: 1 | **Date**: 2026-05-24

Entidades novas no indice `~/.claude/cstk/knowledge.db` (schema_version 1 → 2).
Todas relacionais, idempotentes por chave natural `(project, feature, wave,
source_id)` — espelhando o padrao das 4 tabelas existentes
(`decisions`/`bloqueios`/`retros`/`skills`). Colunas estruturais comuns a todas:
`project`, `feature`, `execucao_id`, `source_ts`, `source_id`, `ingested_at`.

> DDL e ilustrativo do contrato (Phase 1, sem implementacao). A implementacao
> concreta entra via `/execute-task` em `recall_schema_ddl()`.

---

## Entity: Execucao (camada A — US1)

Grao mais grosso: uma linha por execucao do orquestrador. Derivada de `.execucao`
+ `.metricas_acumuladas` + `.etapa_corrente` do `state.json`.

| Campo | Tipo | Origem (jq path) | Filtro segredo | Notas |
|-------|------|------------------|----------------|-------|
| project | TEXT NOT NULL | derivado do path/`.execucao.projeto_alvo_path` | nao | proveniencia |
| feature | TEXT NOT NULL | `.short_name` | nao | proveniencia |
| wave | TEXT NOT NULL | constante `'-'` | nao | grao = execucao |
| execucao_id | TEXT NOT NULL | `.execucao.id` | nao | |
| source_id | TEXT NOT NULL | `.execucao.id` | nao | = chave natural |
| status | TEXT | `.execucao.status` | nao | em_andamento/concluido/abortada/... |
| motivo_termino | TEXT | `.execucao.motivo_termino` | **sim** (texto livre) | |
| etapa_corrente | TEXT | `.etapa_corrente` | nao | |
| iniciada_em | TEXT | `.execucao.iniciada_em` | nao | ISO |
| terminada_em | TEXT | `.execucao.terminada_em` | nao | ISO, nulo se em andamento |
| duracao_segundos | INTEGER | derivado (terminada−iniciada) | nao | nulo se aberto |
| stack_sugerida | TEXT | `.execucao.stack_sugerida` | nao | tipicamente null em feature-00c |
| ondas_total | INTEGER | `.metricas_acumuladas.ondas_total` | nao | |
| tool_calls_total | INTEGER | `.metricas_acumuladas.tool_calls_total` | nao | proxy de custo (FR-021) |
| wallclock_total_segundos | INTEGER | `.metricas_acumuladas.tempo_wallclock_total_segundos` | nao | |
| subagentes_spawned | INTEGER | `.metricas_acumuladas.subagentes_spawned` | nao | |
| profundidade_max | INTEGER | `.metricas_acumuladas.profundidade_max_atingida` | nao | |
| decisoes_total | INTEGER | `.metricas_acumuladas.decisoes_total` | nao | |
| bloqueios_humanos_total | INTEGER | `.metricas_acumuladas.bloqueios_humanos_total` | nao | |
| sugestoes_skills_total | INTEGER | `.metricas_acumuladas.sugestoes_skills_globais_total` | nao | |
| issues_toolkit_abertas | INTEGER | `.metricas_acumuladas.issues_toolkit_abertas` | nao | |
| ingested_at | TEXT NOT NULL | `now()` | nao | |

**Chave natural**: `UNIQUE(project, feature, wave, source_id)`.
**Relacionamentos**: 1 Execucao → N Onda (via `execucao_id`).

```sql
CREATE TABLE IF NOT EXISTS executions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  project TEXT NOT NULL,
  feature TEXT NOT NULL,
  wave TEXT NOT NULL,
  execucao_id TEXT NOT NULL,
  source_ts TEXT NOT NULL,
  source_id TEXT NOT NULL,
  status TEXT,
  motivo_termino TEXT,
  etapa_corrente TEXT,
  iniciada_em TEXT,
  terminada_em TEXT,
  duracao_segundos INTEGER,
  stack_sugerida TEXT,
  ondas_total INTEGER,
  tool_calls_total INTEGER,
  wallclock_total_segundos INTEGER,
  subagentes_spawned INTEGER,
  profundidade_max INTEGER,
  decisoes_total INTEGER,
  bloqueios_humanos_total INTEGER,
  sugestoes_skills_total INTEGER,
  issues_toolkit_abertas INTEGER,
  ingested_at TEXT NOT NULL,
  UNIQUE(project, feature, wave, source_id)
);
```

---

## Entity: Onda (camada A — US1)

Grao = onda, uma linha por entrada de `.ondas[]`.

| Campo | Tipo | Origem (jq path) | Filtro segredo | Notas |
|-------|------|------------------|----------------|-------|
| wave_id | TEXT NOT NULL | `.ondas[].id` | nao | = source_id |
| etapas | TEXT | `.ondas[].etapas_executadas | join(",")` | nao | csv |
| inicio | TEXT | `.ondas[].inicio` | nao | ISO |
| fim | TEXT | `.ondas[].fim` | nao | ISO, nulo se onda aberta |
| wallclock_seconds | INTEGER | `.ondas[].wallclock_seconds` | nao | |
| tool_calls | INTEGER | `.ondas[].tool_calls` | nao | |
| motivo_termino | TEXT | `.ondas[].motivo_termino` | **sim** | |
| n_etapas | INTEGER | `.ondas[].etapas_executadas | length` | nao | derivado |
| n_skills | INTEGER | `.ondas[].skills_invoked | length` | nao | derivado |

**Chave natural**: `UNIQUE(project, feature, wave, source_id)` com
`wave = source_id = wave_id`.
**Relacionamentos**: N Onda → 1 Execucao.

```sql
CREATE TABLE IF NOT EXISTS waves (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  project TEXT NOT NULL,
  feature TEXT NOT NULL,
  wave TEXT NOT NULL,
  execucao_id TEXT NOT NULL,
  source_ts TEXT NOT NULL,
  source_id TEXT NOT NULL,
  etapas TEXT,
  inicio TEXT,
  fim TEXT,
  wallclock_seconds INTEGER,
  tool_calls INTEGER,
  motivo_termino TEXT,
  n_etapas INTEGER,
  n_skills INTEGER,
  ingested_at TEXT NOT NULL,
  UNIQUE(project, feature, wave, source_id)
);
```

---

## Entity: SinalDeAlerta (camada A — US2)

Indicador de saude operacional derivado: entrada de movimento circular (FR-013)
OU breach de orcamento (FR-014). Uma linha por sinal.

| Campo | Tipo | Origem | Filtro segredo | Notas |
|-------|------|--------|----------------|-------|
| tipo | TEXT NOT NULL | `circular` \| `budget_breach` | nao | discriminador |
| subtipo | TEXT | ex: `tool_calls`, `wallclock`, `ciclos`, `profundidade` | nao | so para budget_breach |
| valor_consumido | INTEGER | `.ondas[].tool_calls` etc | nao | nulo para circular |
| valor_threshold | INTEGER | `.orcamentos.*` | nao | nulo para circular |
| descricao | TEXT | texto do `historico_movimento_circular[]` | **sim** | so para circular |
| source_id | TEXT NOT NULL | `<tipo>:<wave_id>:<ordinal>` | nao | chave natural |

**Derivacao budget_breach** (FR-014): para cada onda, comparar
`tool_calls > tool_calls_threshold_onda`, `wallclock_seconds >
wallclock_threshold_segundos`; por execucao, `ciclos_consumidos_etapa_corrente`
proximo de `ciclos_max_por_etapa`, `profundidade_corrente >= recursividade_max`,
tamanho de state vs `estado_size_threshold_bytes`. Cada cruzamento excedido gera
um sinal.
**Derivacao circular** (FR-013): uma linha por entrada de
`.historico_movimento_circular[]`.

```sql
CREATE TABLE IF NOT EXISTS alert_signals (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  project TEXT NOT NULL,
  feature TEXT NOT NULL,
  wave TEXT NOT NULL,
  execucao_id TEXT NOT NULL,
  source_ts TEXT NOT NULL,
  source_id TEXT NOT NULL,
  tipo TEXT NOT NULL,
  subtipo TEXT,
  valor_consumido INTEGER,
  valor_threshold INTEGER,
  descricao TEXT,
  ingested_at TEXT NOT NULL,
  UNIQUE(project, feature, wave, source_id)
);
```

---

## Entity: MetricaDerivada (camada A — US2, computada/materializada)

Latencia humana (FR-015), taxa de auto-resolucao de clarify (FR-016), mix de
roteamento de modelos (FR-017). NAO e fonte primaria; pode ser computada na
consulta ou materializada. Para o painel, materializar simplifica o consumo.

- **Latencia humana** (FR-015): por bloqueio em `.bloqueios_humanos[]`,
  `respondido_em − disparado_em`; bloqueio sem resposta = latencia aberta
  (NULL/pendente). Materializar como linhas em `alert_signals` de subtipo
  `human_latency` OU computar via query sobre a tabela `bloqueios` existente.
- **Clarify auto-resolution rate** (FR-016): relacao entre decisoes `score >= 2`
  na fase clarify (autonomas) e bloqueios humanos na fase clarify (escalas).
  Computavel sobre tabelas `decisions` + `bloqueios` existentes — sem nova tabela.
- **Mix de roteamento de modelos** (FR-017): **reuso** de
  `model-routing-report.sh aggregate --state-dir DIR --json`. NAO reimplementar.
  Consumo: invocar `aggregate --json` e expor o resultado; o painel le.

> Decisao de design: latencia humana e clarify rate sao computaveis sobre tabelas
> EXISTENTES (`bloqueios`, `decisions`) sem nova materializacao obrigatoria.
> Materializar e opcional (otimizacao de leitura do painel). O mix de modelos
> e sempre delegado ao `aggregate` (SC-006).

---

## Entity: Task (camada B — US3)

Grao = task por execucao. Depende de instrumentacao previa dos orquestradores
(FR-018). Campos minimos definidos em clarify Q2 (dec-006).

| Campo | Tipo | Origem (campo NOVO no state.json) | Filtro segredo | Notas |
|-------|------|-----------------------------------|----------------|-------|
| task_id | TEXT NOT NULL | `.tasks[].task_id` | nao | = source_id |
| titulo | TEXT | `.tasks[].titulo` | **sim** | adicionado em schema v3; UX do painel; unico texto livre da camada B |
| outcome | TEXT | `.tasks[].outcome` | nao | `pass` \| `fail` |
| testes_rodados | INTEGER | `.tasks[].testes_rodados` | nao | |
| testes_passados | INTEGER | `.tasks[].testes_passados` | nao | |
| lint_ok | INTEGER | `.tasks[].lint_ok` | nao | booleano 0/1 |
| arquivos_tocados | INTEGER | `.tasks[].arquivos_tocados | length` | nao | contagem |

> **Adendo schema v3** (pos-arquivamento): a coluna `titulo` foi acrescentada
> para melhorar a visualizacao no painel (`cstk-panel`). Migracao idempotente
> via `ALTER TABLE tasks ADD COLUMN titulo TEXT` em `recall_apply_schema`
> (indices v2 ganham a coluna sem reindex; DBs frescos ja nascem com ela).
> `titulo` e texto livre → passa por `secrets-filter.sh` na ingestao (FR-017).
> Retro-compat: `.tasks[].titulo` ausente → `""`.

**Chave natural**: `(project, feature, execucao_id, task_id)` mapeada para
`UNIQUE(project, feature, wave, source_id)` com `wave = <wave_id da task>`,
`source_id = task_id` (espelha clarify Q2).
**Retro-compat** (FR-022/SC-009): `.tasks` ausente → `jq '.tasks[]? // empty'` →
0 linhas, 0 erro.

```sql
CREATE TABLE IF NOT EXISTS tasks (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  project TEXT NOT NULL,
  feature TEXT NOT NULL,
  wave TEXT NOT NULL,
  execucao_id TEXT NOT NULL,
  source_ts TEXT NOT NULL,
  source_id TEXT NOT NULL,
  titulo TEXT,                 -- schema v3 (pos-arquivamento)
  outcome TEXT,
  testes_rodados INTEGER,
  testes_passados INTEGER,
  lint_ok INTEGER,
  arquivos_tocados INTEGER,
  ingested_at TEXT NOT NULL,
  UNIQUE(project, feature, wave, source_id)
);
```

---

## Entity: Evento (camada B — US3)

Timeline cronologica. Conjunto minimo de tipos definido em clarify Q3
(dec-007): `wave_retry`, `lock_contention`, `validation_failed`, `schedule_wait`.
Extensivel sem mudanca de schema (event_type e coluna textual restrita por
convencao; a ingestao NAO valida allowlist).

> **Adendo pos-arquivamento — `recall_consulted`**: tipo adicionado para
> instrumentar o read-back loop (`cstk recall --context`). Os orquestradores
> gravam um evento `recall_consulted` a CADA consulta ao historico no inicio
> de specify/plan — inclusive quando nada e retornado (`hits=0`), caso que a
> Decisao `read-back PRE-DECISAO` NAO cobre (so registrada com K>0, FR-017).
> Metrica "quantas vezes o historico foi consultado pelo orquestrador":
>
> ```sql
> -- total por projeto/feature/execucao
> SELECT project, feature, execucao_id, count(*) AS consultas
> FROM events WHERE event_type='recall_consulted'
> GROUP BY project, feature, execucao_id;
> -- produtivas vs vazias (descricao carrega "etapa=... hits=N")
> SELECT count(*) FILTER (WHERE descricao LIKE '%hits=0') AS vazias,
>        count(*) FILTER (WHERE descricao NOT LIKE '%hits=0') AS produtivas
> FROM events WHERE event_type='recall_consulted';
> ```

| Campo | Tipo | Origem (campo NOVO no state.json) | Filtro segredo | Notas |
|-------|------|-----------------------------------|----------------|-------|
| event_type | TEXT NOT NULL | `.eventos[].event_type` | nao | conjunto MVP fechado |
| timestamp | TEXT NOT NULL | `.eventos[].timestamp` | nao | ISO, ordem cronologica |
| descricao | TEXT | `.eventos[].descricao` | **sim** | texto livre opcional |
| source_id | TEXT NOT NULL | `<event_type>:<timestamp>` | nao | chave natural |

**Retro-compat** (FR-022/SC-009): `.eventos` ausente → 0 linhas, 0 erro.

```sql
CREATE TABLE IF NOT EXISTS events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  project TEXT NOT NULL,
  feature TEXT NOT NULL,
  wave TEXT NOT NULL,
  execucao_id TEXT NOT NULL,
  source_ts TEXT NOT NULL,
  source_id TEXT NOT NULL,
  event_type TEXT NOT NULL,
  timestamp TEXT NOT NULL,
  descricao TEXT,
  ingested_at TEXT NOT NULL,
  UNIQUE(project, feature, wave, source_id)
);
```

---

## Schema versioning

`schema_meta.schema_version`: `1` → `2`. Aplicacao idempotente
(`CREATE TABLE IF NOT EXISTS` + `INSERT ... ON CONFLICT DO UPDATE` no
`schema_meta`). Encontrar v1 em disco => cria as 5 tabelas ausentes, bumpa para 2,
nenhuma tabela existente perde dado (Edge Case + FR-007).

## State transitions

Entidades sao **derivadas e idempotentes** — nao tem maquina de estado propria.
O unico "estado" e o upsert: re-ingestao com `state.json` mais recente atualiza
os campos (ex: execucao `em_andamento` → `concluido`; onda aberta → fechada),
sem mudar a contagem de linhas (SC-004).
