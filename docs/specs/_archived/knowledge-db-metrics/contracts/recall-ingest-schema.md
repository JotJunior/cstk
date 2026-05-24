# Contract: recall.sh ingest schema v2

**Feature**: `knowledge-db-metrics` | **Component**: `cli/lib/recall.sh`

Contrato da extensao de esquema e do comportamento de ingestao das entidades
novas (camada A). Define o que muda em `recall.sh` sem alterar o contrato CLI
externo de `cstk recall`.

## 1. Contrato de versionamento de schema

| Item | Antes | Depois |
|------|-------|--------|
| `RECALL_SCHEMA_VERSION` (linha ~54) | `1` | `2` |
| Tabelas em `recall_schema_ddl()` | decisions, bloqueios, retros, skills, knowledge_fts, schema_meta | + executions, waves, alert_signals (A) + tasks, events (B) |

**Invariante**: aplicacao de schema permanece idempotente
(`CREATE TABLE IF NOT EXISTS` + `INSERT ... ON CONFLICT DO UPDATE` no
`schema_meta`). Encontrar DB v1 → cria tabelas ausentes, bumpa para 2, zero perda
de dado (FR-007 + Edge Case "schema antigo").

## 2. Contrato de chave natural (idempotencia — FR-008)

Toda tabela nova declara `UNIQUE(project, feature, wave, source_id)` e escreve via
`INSERT ... ON CONFLICT(project, feature, wave, source_id) DO UPDATE SET ...`.

| Entidade | wave | source_id |
|----------|------|-----------|
| executions | `'-'` | `execucao_id` |
| waves | `<wave_id>` | `<wave_id>` |
| alert_signals | `<wave_id>` ou `'-'` | `<tipo>:<wave_id>:<ordinal>` |
| tasks | `<wave_id da task>` | `task_id` |
| events | `<wave_id>` ou `'-'` | `<event_type>:<timestamp>` |

**Garantia (SC-004)**: re-ingestao N vezes → delta de linhas = 0.

## 3. Contrato do ponto de ingestao

Toda a logica nova vive em `recall_ingest_state_json(STATE_JSON_PATH, DB_PATH)` —
a unica funcao chamada por AMBOS:
- `recall_mode_ingest` (`--ingest --state-dir DIR`, ~linha 776)
- loop de `recall_mode_reindex` (`--reindex`, ~linha 1165)

**Garantia (SC-002)**: como `--ingest` e `--reindex` compartilham a funcao, o
conjunto de linhas produzido e identico → 0 divergencias (indice derivado FR-001).

Contadores estendidos para o sumario impresso:
`RECALL_TOTAL_EXEC`, `RECALL_TOTAL_WAVE`, `RECALL_TOTAL_ALERT` (+ camada B:
`RECALL_TOTAL_TASK`, `RECALL_TOTAL_EVENT`).

## 4. Contrato best-effort (FR-002, FR-003)

Preambulo de guardas (ja existente, inalterado):

| Condicao | Comportamento | Exit |
|----------|---------------|------|
| `sqlite3` ausente | `log_warn` + return | `$RECALL_EXIT_OK` (0) |
| `jq` ausente | `log_warn` + return | `0` |
| `secrets-filter.sh` ausente | `log_warn` + return (melhor pular que vazar) | `0` |
| dir do DB nao-gravavel | `log_warn` + return | `0` |
| `state.json` ausente/corrompido | pula aquele arquivo c/ aviso; reindex continua | `0` |

**Garantia (SC-003)**: ingestao/reindex nunca abortam a onda do orquestrador.
**Garantia (FR-002)**: somente `jq` de LEITURA sobre `state.json`; nenhuma escrita.

## 5. Contrato de filtro de segredos (FR-006, SC-007)

`secrets-filter.sh` (resolvido via `recall_secrets_filter_path`) aplicado APENAS
a campos de texto livre: `motivo_termino`, `descricao` (alertas/eventos).
Campos estruturados/numericos (status, timestamps, contagens, ids, scores,
booleanos) ingeridos SEM filtro.

**Garantia (SC-007)**: nenhum padrao de segredo conhecido presente no indice apos
ingestao de fixture com segredos plantados em campos de texto livre.

## 6. Contrato de reuso do mix de modelos (FR-017, SC-006)

A entidade MetricaDerivada (mix de roteamento) NAO e reimplementada. Fonte unica:
`global/skills/agente-00c-runtime/scripts/model-routing-report.sh aggregate
--state-dir DIR [--json]`. `recall.sh`/consulta derivada invoca `aggregate --json`.

**Garantia (SC-006)**: numeros consultados = numeros de `aggregate`, 0 divergencias.

## 7. Contrato CLI externo (inalterado)

`cstk recall <query>`, `cstk recall --ingest`, `cstk recall --reindex`,
`cstk recall --context` mantem assinatura e exit codes. As entidades novas sao
transparentes ao usuario de CLI; o sumario de `--ingest`/`--reindex` ganha as
novas contagens. Modo `--context` (read-back) NAO consome as tabelas de metricas
(elas nao alimentam `knowledge_fts`).
