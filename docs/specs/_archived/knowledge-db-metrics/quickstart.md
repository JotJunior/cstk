# Quickstart: Knowledge DB Metrics Ingestion

**Feature**: `knowledge-db-metrics` | **Phase**: 1 | **Date**: 2026-05-24

Cenarios de validacao por fluxo critico (happy path + error cases). Cada cenario
mapeia a um Success Criterion. Single-layer (CLI/shell) — sem roundtrip
backend↔frontend (N/A).

## Cenario 1 — Ingestao estrutural execucao + ondas (US1, SC-001)

1. Preparar fixture `state.json` com 1 execucao concluida e 3 ondas em `.ondas[]`.
2. Rodar `cstk recall --ingest --state-dir <fixture-dir>`.
3. Consultar `sqlite3 ~/.claude/cstk/knowledge.db "SELECT count(*) FROM executions"`.
   → **Expected**: `1`.
4. `SELECT count(*) FROM waves` → **Expected**: `3`.
5. `SELECT status, duracao_segundos, ondas_total FROM executions` →
   **Expected**: status/duracao derivada (terminada−iniciada)/contagens de
   `metricas_acumuladas` corretos.
6. `SELECT wave_id, wallclock_seconds, tool_calls, n_skills FROM waves` →
   **Expected**: 3 linhas com valores corretos por onda.

## Cenario 2 — Reconstrucao do zero == ingestao incremental (US1, SC-002)

1. Com o indice ja populado pelo Cenario 1, rodar `cstk recall --reindex`.
2. Comparar o conjunto de linhas de `executions`/`waves`/`alert_signals` antes e
   depois.
   → **Expected**: conjuntos identicos, 0 divergencias (indice derivado FR-001).

## Cenario 3 — Idempotencia (US1, SC-004)

1. Rodar `cstk recall --ingest --state-dir <fixture-dir>` 3 vezes seguidas.
2. `SELECT count(*) FROM executions; SELECT count(*) FROM waves`.
   → **Expected**: contagens inalteradas entre runs (delta = 0); valores refletem
   o estado mais recente.

## Cenario 4 — Execucao em andamento (US1, Edge Case)

1. Fixture `state.json` com `.execucao.status = "em_andamento"` e
   `terminada_em = null`.
2. Rodar a ingestao.
   → **Expected**: 1 linha de Execucao com `duracao_segundos = NULL`, sem erro nem
   aborto.

## Cenario 5 — Breach de orcamento (US2, SC-005)

1. Fixture com uma onda cujo `tool_calls` excede `tool_calls_threshold_onda`.
2. Rodar a ingestao.
3. `SELECT tipo, subtipo, valor_consumido, valor_threshold FROM alert_signals
   WHERE tipo='budget_breach'`.
   → **Expected**: >= 1 linha com `subtipo='tool_calls'`, consumido > threshold.

## Cenario 6 — Movimento circular (US2, FR-013)

1. Fixture com `historico_movimento_circular[]` populado (2 entradas).
2. Rodar a ingestao.
3. `SELECT count(*) FROM alert_signals WHERE tipo='circular'`.
   → **Expected**: `2`, com proveniencia (execucao/onda/data).

## Cenario 7 — Latencia humana + clarify rate (US2, FR-015/FR-016)

1. Fixture com 2 bloqueios (1 respondido com `disparado_em`+`respondido_em`, 1
   pendente) e decisoes score>=2 na fase clarify.
2. Consultar latencia humana (sobre tabela `bloqueios` existente).
   → **Expected**: latencia = respondido−disparado para o respondido; aberta/NULL
   para o pendente.
3. Derivar clarify auto-resolution rate (decisoes autonomas vs escalas).
   → **Expected**: valor consistente com a relacao no fixture.

## Cenario 8 — Mix de modelos == aggregate (US2, SC-006)

1. Fixture com decisoes de selecao de modelo.
2. Comparar o mix consultado a partir do indice com
   `model-routing-report.sh aggregate --state-dir <dir> --json`.
   → **Expected**: numeros identicos, 0 divergencias (reuso, nao duplicacao).

## Cenario 9 — Segredos filtrados (US2, SC-007)

1. Fixture com segredo plantado em `motivo_termino` / `descricao` de alerta.
2. Rodar a ingestao.
3. Buscar o padrao de segredo no DB:
   `sqlite3 ... "SELECT motivo_termino FROM executions"`.
   → **Expected**: segredo NAO presente (scrubbed por `secrets-filter`); campos
   numericos intactos.

## Cenario 10 — Degradacao sem deps (SC-003)

1. Simular `sqlite3` ausente do PATH (ou `jq` ausente).
2. Rodar `cstk recall --ingest --state-dir <dir>`.
   → **Expected**: `log_warn` em stderr + exit 0; nenhuma onda abortada.
3. Fixture `state.json` corrompido (JSON invalido).
   → **Expected**: arquivo pulado com aviso, reindex continua, exit 0.

## Cenario 11 — Camada B: tasks + eventos (US3, SC-008/SC-009)

1. (Pre-condicao: camada A verde — SC-008.) Fixture `state.json` instrumentado
   com `.tasks[]` e `.eventos[]`.
2. Rodar a ingestao.
3. `SELECT outcome, testes_rodados, testes_passados, lint_ok FROM tasks` →
   **Expected**: 1 linha por task com campos corretos.
4. `SELECT event_type, timestamp FROM events ORDER BY timestamp` →
   **Expected**: 1 linha por evento, ordem cronologica.
5. Fixture NAO instrumentado (sem `.tasks`/`.eventos`).
   → **Expected**: 0 linhas de Task/Evento, 0 erro (SC-009, retro-compat).

## Cenario 12 — Custo em tokens nao inventado (SC-010)

1. Verificar que nenhuma tabela/coluna persiste custo em tokens/$.
2. Confirmar que `tool_calls_total` (executions) e `tool_calls` (waves) sao o
   proxy documentado.
   → **Expected**: ausencia de campo de custo; decisao registrada em
   `contracts/layer-b-instrumentation.md` §6 + research.md D8.

## Cobertura de teste (FR-009)

Todos os cenarios acima sao automatizados em `tests/cstk/test_recall.sh`.
`tests/run.sh --check-coverage` deve permanecer verde (nenhum `.sh` novo sem
teste — esta feature nao cria script novo, estende `recall.sh`).
