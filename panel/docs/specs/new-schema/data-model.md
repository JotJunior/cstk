# Data Model — new-schema

> Rename surface of `knowledge.db` v7 (EN canonical). Every row below traces 1:1 to
> the FROZEN migration-map §3.11 (`../cstk/docs/specs/schema-en-migration/migration-map.md`).
> No column is invented. `(keep)` = unchanged in v7.
>
> Three columns per layer:
> - **DB column (v7)** — `snake_case` EN, projected by `apps/server/src/db/queries/*.ts`.
> - **Row field** — TS interface field, mirrors the DB column (`snake_case`).
> - **DTO field / Zod** — `camelCase` EN, the panel/API contract.
>
> The mapper (`apps/server/src/mappers/<entity>.ts`) is the sole snake↔camel bridge.

---

## Entity: executions (`executions` table — name unchanged)

| Old (v6 pt-BR) | DB column (v7 EN) | DTO field (camelCase) | Notes |
|---|---|---|---|
| `execucao_id` | `execution_id` | `executionId` | JOIN key — renamed on EVERY table |
| `motivo_termino` | `termination_reason` | `terminationReason` | |
| `etapa_corrente` | `current_stage` | `currentStage` | |
| `iniciada_em` | `started_at` | `startedAt` | |
| `terminada_em` | `finished_at` | `finishedAt` | |
| `duracao_segundos` | `duration_seconds` | `durationSeconds` | |
| `stack_sugerida` | `suggested_stack` | `suggestedStack` | |
| `ondas_total` | `waves_total` | `wavesTotal` | |
| `wallclock_total_segundos` | `wallclock_total_seconds` | `wallclockTotalSeconds` | |
| `subagentes_spawned` | `subagents_spawned` | `subagentsSpawned` | |
| `profundidade_max` | `max_depth` | `maxDepth` | |
| `decisoes_total` | `decisions_total` | `decisionsTotal` | |
| `bloqueios_humanos_total` | `human_blocks_total` | `humanBlocksTotal` | |
| `sugestoes_skills_total` | `skill_suggestions_total` | `skillSuggestionsTotal` | |
| `issues_toolkit_abertas` | `toolkit_issues_opened` | `toolkitIssuesOpened` | |
| `tool_calls_total` | `tool_calls_total` (keep) | `toolCallsTotal` | cost PROXY — Principle III |
| `status` | `status` (keep) | `status` | value pt-BR, NOT renamed |

**Relationships**: 1 execution → N waves, N decisions, N tasks, N blocks, N events,
N alert_signals, N suggestions — all via `execution_id`.

---

## Entity: waves (`waves` table)

| Old | DB column (v7) | DTO field | Notes |
|---|---|---|---|
| `execucao_id` | `execution_id` | `executionId` | FK |
| `etapas` | `stages` | `stages` | |
| `inicio` | `started_at` | `startedAt` | |
| `fim` | `finished_at` | `finishedAt` | |
| `motivo_termino` | `termination_reason` | `terminationReason` | |
| `n_etapas` | `n_stages` | `nStages` | |
| `n_skills` | `n_skills` (keep) | `nSkills` | |
| `wallclock_seconds` | `wallclock_seconds` (keep) | `wallclockSeconds` | |
| `tool_calls` | `tool_calls` (keep) | `toolCalls` | proxy |

---

## Entity: decisions (`decisions` table — paginated)

| Old | DB column (v7) | DTO field | Notes |
|---|---|---|---|
| `execucao_id` | `execution_id` | `executionId` | FK |
| `etapa` | `stage` | `stage` | |
| `agente` | `agent` | `agent` | |
| `escolha` | `choice` | `choice` | |
| `opcoes` | `options` | `options` | v2→v3 additive — keep hasColumn guard |
| `contexto` | `context` | `context` | UNTRUSTED — Principle V |
| `justificativa` | `rationale` | `rationale` | UNTRUSTED |
| `evidencia` | `evidence` | `evidence` | UNTRUSTED |
| `score` | `score` (keep) | `score` | |

---

## Entity: tasks (`tasks` table)

| Old | DB column (v7) | DTO field | Notes |
|---|---|---|---|
| `execucao_id` | `execution_id` | `executionId` | FK |
| `titulo` | `title` | `title` | `titleSelect` helper; `'' AS title` when absent |
| `testes_rodados` | `tests_run` | `testsRun` | |
| `testes_passados` | `tests_passed` | `testsPassed` | |
| `arquivos_tocados` | `touched_files` | `touchedFilesCount` | DTO exposes COUNT, not raw paths |
| `lint_ok` | `lint_ok` (keep) | `lintOk` | |
| `outcome` | `outcome` (keep) | `outcome` | enum pass\|fail |

---

## Entity: blocks (TABLE RENAME `bloqueios` → `blocks`)

> `hasTable(db, 'blocks')` guard → returns `[]` against a v6 DB (where only
> `bloqueios` exists). Mirrors the existing `suggestions` hasTable pattern.

| Old | DB column (v7) | DTO field | Notes |
|---|---|---|---|
| `execucao_id` | `execution_id` | `executionId` | FK |
| `pergunta` | `question` | `question` | UNTRUSTED |
| `contexto_para_resposta` | `context_for_answer` | `contextForAnswer` | UNTRUSTED |
| `resposta` | `answer` | `answer` | UNTRUSTED |
| `decisao_id` | `decision_id` | `decisionId` | |
| `disparado_em` | `triggered_at` | `triggeredAt` | |
| `respondido_em` | `answered_at` | `answeredAt` | |
| `latencia_segundos` | `latency_seconds` | `latencySeconds` | |
| `status` | `status` (keep) | `status` | value pt-BR |

**Type rename**: `BloqueioRow → BlockRow`, `BloqueioDTO → BlockDTO`,
`mapBloqueio → mapBlock`, `listBloqueiosByExecution → listBlocksByExecution`.

---

## Entity: events (`events` table)

| Old | DB column (v7) | DTO field | Notes |
|---|---|---|---|
| `execucao_id` | `execution_id` | `executionId` | FK |
| `descricao` | `description` | `description` | UNTRUSTED |
| `event_type` | `event_type` (keep) | `eventType` | |
| `timestamp` | `timestamp` (keep) | `timestamp` | |

---

## Entity: alert_signals (`alert_signals` table)

| Old | DB column (v7) | DTO field | Notes |
|---|---|---|---|
| `execucao_id` | `execution_id` | `executionId` | FK |
| `tipo` | `type` | `type` | |
| `subtipo` | `subtype` | `subtype` | |
| `valor_consumido` | `consumed_value` | `consumedValue` | |
| `valor_threshold` | `threshold_value` | `thresholdValue` | |
| `descricao` | `description` | `description` | UNTRUSTED |

---

## Entity: retros (`retros` table)

| Old | DB column (v7) | DTO field | Notes |
|---|---|---|---|
| `execucao_id` | `execution_id` | `executionId` | FK |
| `texto` | `text` | `text` | UNTRUSTED |

---

## Entity: skills (`skills` table)

| Old | DB column (v7) | DTO field | Notes |
|---|---|---|---|
| `execucao_id` | `execution_id` | `executionId` | FK |
| `decisao_id` | `decision_id` | `decisionId` | |
| `skill_name` | `skill_name` (keep) | `skillName` | |

---

## Entity: suggestions (`suggestions` table — hasTable-guarded already)

| Old | DB column (v7) | DTO field | Notes |
|---|---|---|---|
| `execucao_id` | `execution_id` | `executionId` | FK |
| `skill_afetada` | `affected_skill` | `affectedSkill` | |
| `severidade` | `severity` | `severity` | value pt-BR (informativa\|aviso\|impeditiva) |
| `diagnostico` | `diagnosis` | `diagnosis` | UNTRUSTED |
| `proposta` | `proposal` | `proposal` | UNTRUSTED |
| `issue_aberta` | `issue_opened` | `issueOpened` | |
| `criada_em` | `created_at` | `createdAt` | |

---

## Provenance & FTS columns — UNCHANGED (no action)

`project`, `feature`, `wave`, `source_ts`, `source_id`, `ingested_at`,
`tool_calls_total`, `wallclock_seconds`, `tool_calls`, `n_skills`, `lint_ok`,
`outcome`, `event_type`, `timestamp`, `status`, `score`, `skill_name`;
FTS (`knowledge_fts`): `body`, `type`, `project`, `feature`, `wave`, `source_id`,
`source_ts`.

---

## Mapper-layer invariant (the snake↔camel bridge)

For each entity above, the mapper file
(`apps/server/src/mappers/<entity>.ts`) is the ONLY place a `snake_case` Row field
becomes a `camelCase` DTO field. A mapper MUST NOT reference an old pt-BR Row field
for a renamed column. Validation: `tsc --noEmit` (a stale pt-BR reference becomes a
type error once the Row interface is renamed) + grep for the 10 pt-BR names
(Success Criterion 5).
