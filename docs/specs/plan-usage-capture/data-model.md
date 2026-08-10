# Data Model: Plan Usage Capture

Camada unica de persistencia (ao contrario de `loose-usage-capture`, que
tem sidecar + indice): o dado ja chega pronto no stdin da statusline a
cada render (research.md Decision 4), entao nao ha necessidade de uma
camada de captura intermediaria em arquivo — a tabela `plan_usage` do
`knowledge.db` **e** a fonte persistida.

Schema marcado `[PROPOSTA — a validar na implementacao]` ainda nao existe
no codigo. Citado com arquivo e linha o que ja existe hoje.

---

## Entity: Captura de Uso do Plano (tabela `plan_usage`) `[PROPOSTA]`

Grao: uma linha por (escopo, momento de captura) — apos o throttle de
FR-010 ja ter descartado repeticoes identicas. Append-only (nunca UPDATE
nem UPSERT — ao contrario de `loose_usage`, nao ha chave natural
mutavel a atualizar; cada linha e um ponto imutavel da serie temporal,
FR-008/User Story 2).

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| `id` | INTEGER | PK AUTOINCREMENT | Padrao das demais tabelas do `knowledge.db` |
| `project` | TEXT | NOT NULL | Basename de `project_path`; paridade com `loose_usage.project` |
| `project_path` | TEXT | — | `workspace.current_dir` ou `workspace.project_dir` do payload (memoria linha 21) |
| `session_id` | TEXT | NOT NULL | Copiado verbatim de `session_id` no topo do payload (memoria linha 19) — ver research.md Decision 5 para o porque do nome divergir de `session` |
| `scope` | TEXT | NOT NULL, CHECK IN ('five_hour','seven_day') | FR-005: escopos tratados como series distintas, nunca mesclados |
| `used_percentage` | REAL | — | **NULL quando `rate_limits` ausente** — jamais `0` fabricado (FR-002/FR-004/Principio VI). Persistido sem arredondar (FR-004), inclusive com ruido de float (`7.000000000000001`, memoria linha 32) |
| `resets_at` | INTEGER | — | Epoch em SEGUNDOS (FR-003), **NULL quando `rate_limits` ausente**. Distinto de `captured_at`/`ingested_at` (ver abaixo) |
| `captured_at` | TEXT | NOT NULL | ISO 8601 (`2026-08-07T04:38:14Z`) — momento em que o hook processou o render (FR-014) |
| `ingested_at` | TEXT | NOT NULL | ISO 8601 — momento da escrita no `knowledge.db` (FR-014); pode ser identico a `captured_at` porque nao ha camada intermediaria de sidecar (diferente de `loose_usage`, onde `captured_at` vem do sidecar e `ingested_at` do momento de leitura posterior) |

**Sem `UNIQUE` de chave natural** — ao contrario de `loose_usage`
(`UNIQUE(process_key, segment_id, model)`), nao ha upsert aqui: o throttle
(FR-010, research.md Decision 4) e uma leitura **antes** do INSERT
(`SELECT ... ORDER BY id DESC LIMIT 1 WHERE scope = ?`), nao uma
constraint de banco. A escolha e deliberada — a chave natural candidata
(`scope` + `captured_at`) colidiria em testes que geram fixtures no mesmo
segundo, e o requisito real (FR-010) e sobre o VALOR anterior, nao sobre
timestamp duplicado.

**Colunas deliberadamente AUSENTES**: `feature`, `wave`, `execution_id`
(mesma logica de `loose_usage` — a captura acontece fora de qualquer
execucao `agente-00c`/`feature-00c`, preencher esses campos seria
fabricar dado, Constitution VI); `seven_day_opus`, `seven_day_sonnet`,
`extra_usage` (FR-006 — exigem OAuth, fora de escopo; nenhuma coluna e
criada para campos que a fonte nunca emite).

### Relationships

- Sem FK declarada para `executions`/`waves`/`loose_usage` — `plan_usage`
  e um indice independente, capturado fora de qualquer execucao de
  pipeline (mesmo racional de independencia de `loose_usage`, ver plan.md
  arquivado de `loose-usage-capture` §Relationships).
- `plan_usage.project_path` pode coincidir com `loose_usage.project_path`
  ou `executions.target_project_path` (mesmo projeto), mas a comparacao —
  se algum dia existir — seria agregacao lado a lado, nunca JOIN linha a
  linha (granularidades e cadencias de captura diferentes).

### Migracao

`RECALL_SCHEMA_VERSION`: `13` -> `14` (valor real medido nesta onda via
`grep -n RECALL_SCHEMA_VERSION cli/lib/recall.sh`: `13`). Aditiva pura:
`CREATE TABLE IF NOT EXISTS plan_usage (...)` no corpo de
`recall_schema_ddl`, sem `ALTER TABLE` e sem `DROP` — mesmo precedente
literal de `loose_usage` na migracao v12->v13 (research.md Decision 7).

### Ausencia explicita vs valor real (SC-002, FR-002)

| Situacao | `used_percentage` | `resets_at` |
|----------|--------------------|-------------|
| `rate_limits` ausente do payload (nenhuma resposta de API completou) | `NULL` | `NULL` |
| `rate_limits.<scope>` presente com uso genuinamente `0%` (hipotetico, nunca observado) | `0.0` (valor real medido) | epoch real |
| Throttle descarta a captura (repeticao dentro de 2 casas decimais) | (nenhuma linha nova é inserida) | (idem) |

A distincao entre "sem linha nova por throttle" e "sem dado por
ausencia de `rate_limits`" e estrutural: o primeiro caso nao gera INSERT
algum (nenhuma linha, redundante por design); o segundo gera uma linha com
`NULL` explicito (User Story 3 — nunca confundir "nao medido" com "zero").
