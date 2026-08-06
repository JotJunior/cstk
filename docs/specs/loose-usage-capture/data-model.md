# Data Model: Loose Usage Capture

Duas camadas de persistencia (research.md Decision 7):

- **Camada de captura (fonte)**: arquivos sob `~/.claude/cstk/loose-usage/`,
  escritos exclusivamente pelo hook. Sobrevivem ao processo (FR-008).
- **Camada de indice (derivada)**: tabela nova no `knowledge.db`
  (`~/.claude/cstk/knowledge.db`), populada por ingest-on-read do CLI.
  Reconstruivel a partir da camada de captura.

Todos os schemas marcados `[PROPOSTA — a validar na implementacao]` ainda nao
existem no codigo. O que ja existe esta citado com arquivo e linha.

---

## Entity: LooseUsageProcess (camada de captura) `[PROPOSTA]`

Um processo local do Claude Code observado num projeto. Grao: processo x
projeto (FR-002). Materializado como um diretorio:

```
~/.claude/cstk/loose-usage/<process_key>/
├── meta.tsv                    # metadados do processo
└── seg-<NNN>/                  # um diretorio por segmento avulso
    ├── otel-start.tsv          # snapshot inicial do segmento
    ├── otel-end.tsv            # snapshot mais recente do segmento
    └── closed                  # marcador; presente = segmento encerrado
```

Os nomes `otel-start.tsv` / `otel-end.tsv` **nao sao escolha desta feature**:
sao os nomes que `otel-usage.sh` escreve e le (`snapshot` linha 265,
`delta` linhas 296-297). Mante-los permite reusar os dois subcomandos sem
alteracao.

### Campos de `meta.tsv` (formato `chave<TAB>valor`, uma linha por chave)

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| `schema` | int | NOT NULL | Versao do layout do sidecar; inicia em `1` |
| `project_path` | string | NOT NULL | `cwd` recebido do payload do hook |
| `endpoint` | string | NOT NULL | Valor de `CSTK_OTEL_ENDPOINT` do processo |
| `owner_pid` | int \| `unknown` | — | PID dono da porta; `unknown` quando indeterminavel (nunca 0) |
| `created_at` | ISO 8601 UTC | NOT NULL | Primeira captura do processo |
| `updated_at` | ISO 8601 UTC | NOT NULL | Ultima captura bem-sucedida; base do throttle |
| `current_segment` | string | NOT NULL | Id do segmento aberto (ex: `seg-002`) |

**Derivacao de `process_key`**: funcao estavel do par
(`endpoint`, `project_path`), com `owner_pid` como componente adicional
quando obtenivel. `[PROPOSTA]` — o algoritmo exato (hash vs composicao
literal saneada) e detalhe de implementacao; o requisito e ser deterministico
dentro de um processo e nao colidir entre processos simultaneos no mesmo
projeto (Edge Case "duas janelas/terminais abertos").

> **Constitution VI**: `owner_pid` ausente e gravado como `unknown`, jamais
> como `0` ou PID chutado.

### Formato de `otel-start.tsv` / `otel-end.tsv` (JA EXISTENTE)

Escrito por `otel-usage.sh snapshot`. Cabecalho `# session_id<TAB><valor>`
seguido de linhas de 5 colunas separadas por TAB
(`_ou_parse`, linhas 170-197):

| Coluna | Conteudo |
|--------|----------|
| 1 | `session_id` (informativo; NAO usado como identidade — Decision 2) |
| 2 | `query_source` (`main` \| `subagent` \| `auxiliary` \| `sdk`) |
| 3 | `model` |
| 4 | `type` (`cost` na linha de custo; senao `input`/`output`/`cacheRead`/`cacheCreation`) |
| 5 | `value` (numerico) |

Labels de PII (`user_id`, `user_email`, `user_account_uuid`,
`user_account_id`, `organization_id`) sao descartados por construcao no parse
e reconferidos por defesa em profundidade (linhas 276-281) — nunca alcancam
estes arquivos.

### State Transitions — segmento avulso

```
(sem segmento) --tick com execucao INATIVA--> aberto
aberto --tick com execucao INATIVA--> aberto (otel-end.tsv reescrito)
aberto --tick com execucao ATIVA--> fechado (marcador `closed`; trecho nao persistido e descartado)
fechado --tick com execucao INATIVA--> novo segmento aberto (seg-N+1)
```

Estados `indeterminada` (exit 2) e `uso incorreto` (exit 3) do helper NAO
provocam transicao: o tick e ignorado por completo (Decision 5).

---

## Entity: LooseUsageRecord (camada de indice — tabela `loose_usage`) `[PROPOSTA]`

Grao: processo x segmento x modelo. Uma linha por modelo usado num segmento.

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| `id` | INTEGER | PK AUTOINCREMENT | Padrao das demais tabelas do `knowledge.db` |
| `project` | TEXT | NOT NULL | Nome canonico do projeto (basename de `project_path`) |
| `project_path` | TEXT | — | Path absoluto; paridade com `executions.target_project_path` (v9) |
| `process_key` | TEXT | NOT NULL | Ver LooseUsageProcess |
| `segment_id` | TEXT | NOT NULL | Ex: `seg-002` |
| `model` | TEXT | — | Rotulo de modelo vindo do exporter; NULL se ausente |
| `cost_usd` | REAL | — | **NULL quando nao medido** — jamais 0 fabricado |
| `total_tokens` | INTEGER | — | **NULL quando nao medido** — jamais 0 fabricado |
| `segment_open` | INTEGER | — | `1` segmento aberto, `0` fechado |
| `captured_at` | TEXT | NOT NULL | `updated_at` do segmento (ultima captura) |
| `ingested_at` | TEXT | NOT NULL | Momento da ingestao |
| — | — | `UNIQUE(process_key, segment_id, model)` | Chave natural; ingestao e UPSERT idempotente |

**Colunas deliberadamente AUSENTES** (fundamento de dec-005): `feature`,
`wave`, `execution_id`. Nao existem para consumo avulso; preenche-las com
sentinela seria fabricar dado (Constitution VI). E exatamente por serem
`NOT NULL` em `wave_model_usage` (`cli/lib/recall.sh` linhas 625-637) que
aquela tabela nao pode ser reusada.

### Relationships

- `LooseUsageProcess` 1:N `LooseUsageRecord` via `process_key`.
- `loose_usage` N:1 (logico) `executions.target_project_path` via
  `project_path` — **sem FK declarada**: as duas tabelas sao indices
  derivados independentes e uma FK quebraria `--reindex` parcial.
- `loose_usage` x `wave_model_usage`: sem relacao de chave; a comparacao de
  FR-009 e uma agregacao lado a lado por `project`, nunca um JOIN linha a
  linha (granularidades diferentes por construcao).

### Migracao

`RECALL_SCHEMA_VERSION`: `12` -> `13`. Aditiva pura: `CREATE TABLE IF NOT
EXISTS loose_usage (...)` no corpo de `recall_schema_ddl`, sem `ALTER TABLE`
e sem `DROP` (precedente literal da v11->v12 para tabela nova —
`cli/lib/recall.sh` linhas 810-811). Base v12 existente do operador ganha a
tabela vazia na proxima escrita; bases pre-v12 seguem o caminho de migracao
ja existente sem interferencia.

---

## Entity: ProjectUsageComparison (derivada, sem persistencia)

Visao calculada em tempo de consulta por `cstk usage compare` `[PROPOSTA]`.
Nao e tabela.

| Field | Type | Origem |
|-------|------|--------|
| `project` | string | Parametro/agrupador |
| `category` | enum `loose` \| `pipeline` | Conjunto fechado |
| `model` | string | `loose_usage.model` / `wave_model_usage.model` |
| `total_tokens` | integer \| `null` | SUM por categoria+modelo; `null` se nao medido |
| `cost_usd` | number \| `null` | SUM por categoria+modelo; `null` se nao medido |
| `share_pct` | number \| `null` | Participacao do modelo no total da categoria |
| `blended_cost_per_mtok` | number \| `null` | `SUM(cost_usd) / SUM(total_tokens) * 1e6` |

**Regra de ausencia (FR-005 / SC-004)**: quando uma categoria nao tem
nenhuma linha para o projeto, o campo e `null` e a renderizacao textual e
`nao medido`. Zero so aparece se houver linha com valor `0` de fato medido.
`blended_cost_per_mtok` e `null` quando `SUM(total_tokens)` e `0` ou `NULL`
(divisao indefinida nunca vira `0`).
