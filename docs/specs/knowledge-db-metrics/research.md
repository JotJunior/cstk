# Research: Knowledge DB Metrics Ingestion

**Feature**: `knowledge-db-metrics` | **Phase**: 0 | **Date**: 2026-05-24

Resolve as incognitas tecnicas antes do design (Phase 1). Cada decisao tem
**Decision / Rationale / Alternatives considered**. Ancoragens verificadas
empiricamente em `cli/lib/recall.sh` (1181 linhas) na revisao corrente do repo.

## Decision 1 — Estrategia de schema: estender o DDL existente vs DB separado

**Decision**: Estender `recall_schema_ddl()` em `cli/lib/recall.sh` com novas
tabelas relacionais no MESMO `knowledge.db`; bump `RECALL_SCHEMA_VERSION` de `1`
para `2` (linha 54). Schema aplicado idempotentemente via `recall_apply_schema()`
(~linha 405), que ja roda sob retry/backoff por causa de `database is locked`.

**Rationale**: O DDL atual (decisions/bloqueios/retros/skills + `knowledge_fts` +
`schema_meta`) usa `CREATE TABLE IF NOT EXISTS`, entao adicionar tabelas e
idempotente e nao perde dado (Edge Case "schema antigo encontrado"). O
`schema_meta` ja faz `INSERT ... ON CONFLICT DO UPDATE` do `schema_version`,
entao bumpar para 2 e uma mudanca de uma linha (FR-007). Um DB separado violaria
o confinamento (FR-004) e fragmentaria a fonte da verdade.

**Alternatives considered**:
- *DB separado `metrics.db`*: rejeitado — duplica conexao, espalha dep `sqlite3`,
  complica `--reindex`.
- *Reusar tabelas FTS existentes*: rejeitado — FTS5 e para busca textual, nao
  para metricas estruturadas/numericas com agregacao (US1 quer contagens/duracoes).

## Decision 2 — Chave natural de idempotencia das entidades novas

**Decision**: Espelhar a chave `UNIQUE(project, feature, wave, source_id)` ja usada
nas 4 tabelas existentes. Mapeamento por entidade:
- `executions`: `wave = '-'` (grao = execucao, sem onda), `source_id = execucao_id`.
- `waves`: `wave = <wave_id>` (ex: `onda-001`), `source_id = wave_id`.
- `alert_signals`: `source_id` = `<tipo>:<wave_id>:<ordinal>` (ex:
  `budget_breach:onda-002:1`, `circular:onda-003:1`).
- `tasks` (B): `source_id = task_id`, `wave = <wave_id da execucao da task>`.
- `events` (B): `source_id = <event_type>:<timestamp>` (ordem cronologica).

Escrita via `INSERT ... ON CONFLICT(project,feature,wave,source_id) DO UPDATE`
(upsert) — re-ingestao reflete o estado mais recente sem duplicar (FR-008,
SC-004).

**Rationale**: Reusa o padrao verificado nas 4 tabelas atuais (todas declaram a
mesma constraint nas linhas 329/344/356/369). Mantem `--ingest` (incremental) e
`--reindex` (do zero) convergentes — SC-002 (0 divergencias) sai de graca porque
ambos chamam a mesma `recall_ingest_state_json`.

**Alternatives considered**:
- *PK autoincrement sem UNIQUE*: rejeitado — re-ingestao duplicaria linhas,
  viola FR-008/SC-004.
- *Hash do registro como chave*: rejeitado — opaco, dificil de consultar por
  proveniencia; a tupla natural ja e suficiente e legivel.

## Decision 3 — Ponto unico de ingestao (`--ingest` e `--reindex` convergem)

**Decision**: Adicionar o parsing das entidades novas DENTRO de
`recall_ingest_state_json()` — a funcao por-arquivo chamada tanto por
`recall_mode_ingest` (~linha 776) quanto pelo loop de `recall_mode_reindex`
(~linha 1165). Nao criar funcao paralela por modo.

**Rationale**: Garante a invariante de indice derivado (FR-001/SC-002): qualquer
linha que o `--ingest` cria, o `--reindex` recria identicamente, porque e o mesmo
codigo. Os contadores globais (`RECALL_TOTAL_*`) sao estendidos com
`RECALL_TOTAL_EXEC`, `RECALL_TOTAL_WAVE`, `RECALL_TOTAL_ALERT` (+ camada B) para
o sumario impresso.

**Alternatives considered**:
- *Funcao separada por modo*: rejeitado — duplica logica, abre brecha de
  divergencia ingest vs reindex (o exato risco que SC-002 protege).

## Decision 4 — Best-effort e leitura somente do state.json

**Decision**: Manter o preambulo de guardas ja presente no `recall_mode_ingest`
(linhas 759-777): se `sqlite3` ausente → `log_warn` + `return $RECALL_EXIT_OK`;
se `jq` ausente → idem; se `secrets-filter.sh` ausente → idem; se diretorio do DB
nao-gravavel → idem. Nenhuma escrita no `state.json` (so `jq` de leitura).

**Rationale**: FR-002 (somente leitura), FR-003 (best-effort, exit 0). A natureza
no-op de toda degradacao significa que pular a ingestao jamais aborta a onda do
orquestrador (SC-003). Verificado: `sqlite3` em `/usr/bin/sqlite3`, `jq` em
`/opt/homebrew/bin/jq` no ambiente atual, mas o codigo nao assume presenca.

**Alternatives considered**:
- *Falhar ruidosamente sem deps*: rejeitado — violaria FR-003 e degradaria a
  experiencia do orquestrador (onda abortaria por causa de indice opcional).

## Decision 5 — Texto livre vs dado estruturado e o filtro de segredos

**Decision**: Aplicar `secrets-filter.sh` (ja resolvido via
`recall_secrets_filter_path`, linha 768) APENAS em campos de texto livre das
entidades novas: `motivo_termino`, descricoes/contextos de alertas, mensagens de
eventos. Campos estruturados/numericos (status, timestamps ISO, contagens,
ids, scores, booleanos) sao ingeridos SEM o filtro.

**Rationale**: FR-006 + SC-007. Espelha o tratamento ja dado aos campos de texto
das tabelas existentes (ex: `contexto`/`justificativa`/`evidencia` em decisions).
Numeros e timestamps nao carregam segredo e o filtro sobre eles so adicionaria
custo.

**Alternatives considered**:
- *Scrubbar tudo*: rejeitado — desperdicio e poderia corromper timestamps/ids.
- *Scrubbar nada*: rejeitado — viola FR-006 (texto livre pode vazar segredo).

## Decision 6 — Mix de roteamento de modelos: reuso de `model-routing-report.sh`

**Decision**: O mix de roteamento (FR-017) NAO e reimplementado em `recall.sh`.
A logica de agregacao vive em
`global/skills/agente-00c-runtime/scripts/model-routing-report.sh aggregate
--state-dir DIR [--json]` (verificado: subcomando `aggregate` em `_mrr_cmd_aggregate`,
linha 198; programa jq em `_mrr_jq_program`, linha 115). A entidade
`MetricaDerivada` para model routing e **computada na consulta** (ou materializada
chamando `aggregate --json`), nunca duplicando o programa `jq`.

**Rationale**: FR-017 exige reuso, MUST NOT duplicar. SC-006 (0 divergencias com
a ferramenta existente) so e garantido se a mesma logica for a fonte. A camada A
de `recall.sh` apenas referencia/invoca `aggregate --json`; nao reescreve a
agregacao.

**Alternatives considered**:
- *Reimplementar agregacao em SQL/jq dentro de recall.sh*: rejeitado — viola
  FR-017 e arrisca drift (SC-006).

## Decision 7 — Breach de orcamento: derivacao por cruzamento de thresholds

**Decision**: Derivar `alert_signals` de tipo `budget_breach` cruzando os
thresholds de `.orcamentos` (`tool_calls_threshold_onda`,
`wallclock_threshold_segundos`, `estado_size_threshold_bytes`,
`ciclos_max_por_etapa`, `recursividade_max`) com o consumo real por onda
(`.ondas[].tool_calls`, `.ondas[].wallclock_seconds`) e por execucao. Cada breach
registra `tipo`, `valor_consumido`, `valor_threshold`, proveniencia.

**Rationale**: FR-014 + SC-005. Dado ja presente no `state.json` (verificado:
`.orcamentos` tem os 5 thresholds; `.ondas[]` tem `tool_calls`/`wallclock_seconds`).
Derivacao pura — nenhuma escrita de volta. `historico_movimento_circular[]` (FR-013)
vira `alert_signals` de tipo `circular`.

**Alternatives considered**:
- *Computar breach na consulta (sem materializar)*: viavel, mas materializar como
  `alert_signals` simplifica o consumo pelo painel e o teste de SC-005. Escolhido
  materializar; a propriedade derivada e preservada (reindex recria).

## Decision 8 — Custo em tokens: impossivel, `tool_calls` como proxy

**Decision**: NAO ingerir custo em tokens/$. Documentar a impossibilidade
explicitamente (este research + FR-021) e manter `.metricas_acumuladas.tool_calls_total`
+ `.ondas[].tool_calls` como **proxy de custo**.

**Rationale**: Verificado empiricamente na fase clarify (dec-005, score 3): a
harness do Claude Code nao expoe contabilidade de tokens a scripts/env
(`env | grep -i token` => vazio). Inventar valor de custo violaria FR-021/SC-010
("sem inventar dado de custo"). `tool_calls` ja e coletado por onda.

**Alternatives considered**:
- *Estimar tokens por heuristica (chars/4)*: rejeitado — seria dado inventado,
  proibido por FR-021/SC-010.
- *Deixar campo nulo sem documentar*: rejeitado — SC-010 exige decisao explicita
  registrada no artefato (este e o registro).

## Decision 9 — Camada B: retro-compatibilidade da instrumentacao

**Decision**: As tabelas `tasks`/`events` (camada B) sao alimentadas de campos
NOVOS que os orquestradores passarao a gravar (FR-018/FR-020). Quando esses campos
estao ausentes (execucao antiga, pre-instrumentacao), o parsing usa
`jq '... // empty'` e produz 0 linhas para aquela execucao, sem erro (FR-022).

**Rationale**: SC-009 (0 registros, 0 erros para state nao-instrumentado). O `jq`
com fallback `// empty` / `// []` torna a ausencia de campo um no-op natural. A
camada B so e ativada apos a camada A estar verde (FR-010/SC-008).

**Alternatives considered**:
- *Exigir migracao de states antigos*: rejeitado — states sao historicos
  imutaveis; forcar campo quebraria reindex de execucoes passadas.

## Resumo de unknowns resolvidos

| Unknown | Status | Decisao |
|---------|--------|---------|
| Esquema novo vs DB separado | RESOLVIDO | D1 — estender DDL, bump v2 |
| Chave de idempotencia | RESOLVIDO | D2 — espelhar `(project,feature,wave,source_id)` |
| Ingest vs reindex convergencia | RESOLVIDO | D3 — ponto unico `recall_ingest_state_json` |
| Best-effort/somente-leitura | RESOLVIDO | D4 — guardas existentes, exit 0 |
| Filtro de segredos | RESOLVIDO | D5 — so texto livre |
| Mix de modelos | RESOLVIDO | D6 — reuso de `model-routing-report.sh` |
| Breach de orcamento | RESOLVIDO | D7 — cruzamento threshold×consumo |
| Custo em tokens | RESOLVIDO | D8 — impossivel, proxy `tool_calls` |
| Retro-compat camada B | RESOLVIDO | D9 — `jq // empty`, 0 linhas sem erro |

**NEEDS CLARIFICATION restantes**: 0.
