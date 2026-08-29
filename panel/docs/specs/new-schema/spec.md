# Feature Spec: new-schema

> **Status**: Draft
> **Created**: 2026-05-30
> **Short name**: `new-schema`
> **Source of truth for column mapping**: `../cstk/docs/specs/schema-en-migration/migration-map.md` (FROZEN)

---

## Context

The `cstk` toolkit (repo sibling at `../cstk`) released schema v7 of `knowledge.db`
in commit `c004ff3`, normalising all column names from pt-BR to English
(`snake_case` EN canonical, pt-BR accepted on read as deprecated aliases).
The `cstk-panel` is the primary consumer of `knowledge.db` and currently
references the old pt-BR column names everywhere — in SQL queries, TypeScript
types, Zod schemas, and mappers. Without this adaptation, `cstk-panel` will
silently return `NULL` or crash against a v7 database.

The migration-map at `../cstk/docs/specs/schema-en-migration/migration-map.md`
is the **single source of truth** for every pt→EN rename. This spec does NOT
re-list every mapping — it references that frozen document.

> **Decisões de infraestrutura**: N/A — feature stateless, sem scheduling,
> sem key rotation, sem token externo, sem multi-replica.

---

## User Scenarios & Testing

### P1 — Operator views dashboard against a v7 database without data loss

**As** an operator running `cstk-panel` against a freshly-ingested
`knowledge.db` produced by `cstk` v7,  
**I want** every page — Overview, Executions, Waves, Decisions, Tasks,
Events, Alerts, Blocks, Skills, Suggestions, Metrics — to display data
correctly,  
**so that** I can observe pipeline executions without missing fields or
blank sections caused by renamed columns.

**Acceptance scenarios**:
- Opening the Overview page shows non-null KPIs drawn from `executions`
  (total executions, waves, decisions, tool_calls proxy).
- The Executions list renders each row with status, current stage,
  started-at and termination reason — all non-null for executed runs.
- The Waves timeline for an execution shows `started_at`, `finished_at`,
  `stages`, `termination_reason`, `n_stages`, `n_skills` — with no blank
  columns that used to show data.
- The Decisions page shows `agent`, `stage`, `choice`, `context`,
  `rationale`, `evidence` with paging working end-to-end.
- The Tasks page shows `title`, `outcome`, `tests_run`, `tests_passed`,
  `lint_ok`, `touched_files` (count).
- The Blocks page shows `question`, `context_for_answer`, `answer`,
  `decision_id`, `triggered_at`, `answered_at`, `latency_seconds`.
- The Events page shows `description` (not the old `descricao`).
- Alert signals show `type`, `subtype`, `consumed_value`,
  `threshold_value`, `description`.
- Suggestions show `affected_skill`, `severity`, `diagnosis`, `proposal`.
- The `execution_id` join key works across all tables (no orphaned rows).

**Edge cases**:
- A column referenced in the query that was renamed and not yet migrated
  returns `NULL` — the test must fail with the old column name and pass
  with the new one.
- The `bloqueios` table was renamed to `blocks`; querying `bloqueios`
  against a v7 database must degrade gracefully (zero rows), not throw.

---

### P2 — Operator views dashboard against a v6 database without regression

**As** an operator who has not yet re-indexed with `cstk recall --reindex`
and therefore has a v6 `knowledge.db` (pt-BR column names),  
**I want** the panel to degrade gracefully — showing data where columns
exist, empty/null where they have been renamed — without a crash,  
**so that** I am not forced to immediately re-index before the panel is
usable.

**Acceptance scenarios**:
- Against a v6 database, pages load with `200` (no `5xx`).
- `meta.degraded` in the API envelope may be `false` (the panel does not
  know the DB version), but the UI shows empty rows rather than throwing.
- `hasColumn` / `hasTable` guards produce `NULL AS <col>` projections for
  absent columns, exactly as they do today for schema v2→v3 columns
  (`tasks.title`, `decisions.options`).
- No TypeScript compile error is introduced; the type system reflects the
  canonical column names used in v7.

**Edge cases**:
- `blocks` table absent (v6 used `bloqueios`) → `hasTable` returns false
  → Blocks endpoint returns `[]`, not an exception.
- Columns like `termination_reason` absent in a v6 `executions` table →
  `hasColumn` projects `NULL AS termination_reason`.

---

### P3 — Operator observes metrics derived from renamed columns

**As** an operator viewing the Metrics pages,  
**I want** metrics that reference renamed columns (`iniciada_em` →
`started_at`, `etapa_corrente` → `current_stage`, `duracao_segundos` →
`duration_seconds`, etc.) to be computed correctly after the rename,  
**so that** time-series charts, pass-rate series, and duration queries
continue to produce accurate results.

**Acceptance scenarios**:
- `cost-over-time` metric groups by `date(started_at)` (was
  `date(iniciada_em)`) — produces the same shape of results.
- `execution-duration` and `depth-subagents` queries reference
  `duration_seconds`, `max_depth`, `subagents_spawned` (EN names).
- `test-pass-rate-series` JOIN between `tasks` and `executions` uses
  `execution_id` (EN) on both sides.
- `clarify-resolution` filters by `stage = 'clarify'` (was `etapa`);
  `model-mix` queries use `choice` (was `escolha`).
- `throughput-by-stage` groups by `stage` (was `etapa`).
- `human-latency` references `human_blocks_total` (was
  `bloqueios_humanos_total`) and `duration_seconds`.

---

### P4 — Developer finds a single consistent vocabulary across the codebase

**As** a developer maintaining `cstk-panel`,  
**I want** every layer — SQL queries, TypeScript interfaces, Zod schemas,
mappers and frontend hooks — to use the same canonical EN naming
(column name → `snake_case` EN in SQL; DTO field → `camelCase` EN in TS),  
**so that** tracing a field from the database to the UI requires no
mental translation between pt-BR and EN names.

**Acceptance scenarios**:
- No TypeScript type or Zod schema field uses a pt-BR name for a column
  that has been renamed in v7 (verified by grep / type-check).
- No SQL query in `apps/server/src/db/queries/` references a v7-renamed
  column by its old pt-BR name without a `hasColumn` fallback.
- Mapper functions translate `snake_case` EN (DB row) to `camelCase` EN
  (TS DTO) consistently — no mix of `etapa` (old) and `stage` (new) in
  the same mapper.
- Running `tsc --noEmit` on the full monorepo produces zero errors after
  the migration.

---

## Requirements

### FR-001 — Rename SQL column references to EN canonical names

The server-side SQL queries (`apps/server/src/db/queries/*.ts`) MUST
reference column names using the EN canonical names defined in the
migration-map §3 (e.g., `execution_id`, `termination_reason`,
`current_stage`, `started_at`, `finished_at`, `duration_seconds`,
`suggested_stack`, `waves_total`, `wallclock_total_seconds`,
`subagents_spawned`, `max_depth`, `decisions_total`,
`human_blocks_total`, `skill_suggestions_total`,
`toolkit_issues_opened`; `stages`, `started_at`, `finished_at`,
`termination_reason`, `n_stages`; `agent`, `stage`, `choice`, `options`,
`context`, `rationale`, `evidence`; `title`, `tests_run`, `tests_passed`,
`touched_files`; `question`, `context_for_answer`, `answer`,
`decision_id`, `triggered_at`, `answered_at`, `latency_seconds`;
`type`, `subtype`, `consumed_value`, `threshold_value`, `description`;
`affected_skill`, `severity`, `diagnosis`, `proposal`).

### FR-002 — Rename table `bloqueios` → `blocks`

All queries that reference the `bloqueios` table MUST be updated to
`blocks`. The `hasTable` guard MUST be applied so that v6 databases
(where `blocks` is absent) produce an empty result and `200` response,
not an exception.

### FR-003 — Update TypeScript interfaces (Row types) in query files

The `*Row` TypeScript interfaces in every query file MUST use EN
`snake_case` field names matching the new DB column names (e.g.,
`BloqueioRow` becomes `BlockRow`; fields `pergunta` → `question`,
`contexto_para_resposta` → `context_for_answer`, etc.). No pt-BR field
name may remain in a `Row` interface for columns that were renamed in v7.

### FR-004 — Update DTOs in shared-types

The `*DTO` interfaces in
`packages/shared-types/src/entities.ts` MUST reflect the EN naming
convention. Fields sourced from renamed columns MUST be renamed in
`camelCase` EN (e.g., `BloqueioDTO` → `BlockDTO`; `pergunta` →
`question`, `contextoParaResposta` → `contextForAnswer`,
`disparadoEm` → `triggeredAt`, `respondidoEm` → `answeredAt`,
`latenciaSegundos` → `latencySeconds`; `ExecutionDTO`: `etapaCorrente`
→ `currentStage`, `motivoTermino` → `terminationReason`,
`iniciadaEm` → `startedAt`, `terminadaEm` → `finishedAt`,
`duracaoSegundos` → `durationSeconds`, `stackSugerida` → `suggestedStack`,
`ondasTotal` → `wavesTotal`, `wallclockTotalSegundos` →
`wallclockTotalSeconds`, `subagentesSpawned` → `subagentsSpawned`,
`profundidadeMax` → `maxDepth`, `decisoesTotal` → `decisionsTotal`,
`bloqueiosHumanosTotal` → `humanBlocksTotal`,
`sugestoesSkillsTotal` → `skillSuggestionsTotal`,
`issuesToolkitAbertas` → `toolkitIssuesOpened`;
`WaveDTO`: `etapas` → `stages`, `inicio` → `startedAt`,
`fim` → `finishedAt`, `motivoTermino` → `terminationReason`,
`nEtapas` → `nStages`;
`DecisionDTO`: `etapa` → `stage`, `agente` → `agent`,
`escolha` → `choice`, `contexto` → `context`,
`justificativa` → `rationale`;
`TaskDTO`: `titulo` → `title`, `testesRodados` → `testsRun`,
`testesPassados` → `testsPassed`, `arquivosTocadosCount` →
`touchedFilesCount`;
`EventDTO`: `descricao` → `description`;
`AlertSignalDTO`: `tipo` → `type`, `subtipo` → `subtype`,
`valorConsumido` → `consumedValue`, `valorThreshold` → `thresholdValue`,
`descricao` → `description`;
`RetroDTO`: `texto` → `text`;
`SuggestionDTO`: `skillAfetada` → `affectedSkill`,
`severidade` → `severity`, `diagnostico` → `diagnosis`,
`proposta` → `proposal`, `issueAberta` → `issueOpened`,
`criadaEm` → `createdAt`).

### FR-005 — Update Zod schemas to match renamed DTOs

All Zod schemas in `packages/shared-types/src/schemas/entities.ts` MUST
be updated to match the renamed DTO fields (FR-004). The field names in
`z.object({…})` must be identical to the TS interface fields.

### FR-006 — Update server mappers to bridge renamed Row → renamed DTO

All mapper functions in `apps/server/src/mappers/*.ts` MUST map the new
EN `snake_case` Row field names to the new EN `camelCase` DTO field names
(FR-003 → FR-004). No mapper may reference a pt-BR Row field for a
renamed column.

### FR-007 — Apply hasColumn / hasTable guards for v6 back-compat

For every column that was renamed in v7 and that cstk-panel projects
explicitly (i.e., not via `SELECT *`), a `hasColumn` guard MUST be added
projecting `NULL AS <new_name>` when the column is absent — mirroring the
existing pattern for `tasks.titulo`/`decisions.opcoes`. For the `blocks`
table (renamed from `bloqueios`), a `hasTable` guard MUST be applied
returning `[]` when absent — mirroring the existing pattern for
`suggestions`.

### FR-008 — Update metric queries referencing renamed columns

All metric queries in `apps/server/src/db/queries/metrics.ts` and
`apps/server/src/db/queries/overview.ts` MUST use EN column names:
`started_at` (was `iniciada_em`), `duration_seconds` (was
`duracao_segundos`), `max_depth` (was `profundidade_max`),
`subagents_spawned` (was `subagentes_spawned`),
`human_blocks_total` (was `bloqueios_humanos_total`),
`termination_reason` (was `motivo_termino`), `current_stage` (was
`etapa_corrente`), `waves_total` (was `ondas_total`),
`wallclock_total_seconds` (was `wallclock_total_segundos`),
`decisions_total` (was `decisoes_total`),
`stage` in `decisions` (was `etapa`), `choice` (was `escolha`),
`started_at` in `waves` (was `inicio`), `finished_at` in `waves`
(was `fim`), `n_stages` (was `n_etapas`), `stages` (was `etapas`),
`title` in `tasks` (was `titulo`), `tests_run` (was `testes_rodados`),
`tests_passed` (was `testes_passados`), `touched_files` (was
`arquivos_tocados`), and `execution_id` in JOIN conditions everywhere
(was `execucao_id`).

### FR-009 — Update frontend type consumption

The web app (`apps/web/`) MUST compile without TypeScript errors after
the DTO rename. Any component, hook, or utility that destructures a
renamed DTO field MUST be updated to use the EN name. The frontend MUST
NOT reference deprecated pt-BR field names after this migration.

### FR-010 — Update `tituloSelect` helper and equivalent guards

The `tituloSelect` helper in `tasks.ts` (and any equivalent column-probe
helpers) MUST be updated to reference `title` (new column name) instead
of `titulo`. The back-compat projection for absent column becomes
`'' AS title`.

### FR-011 — Rollup queries use EN column names

`getRollupByProject` and `getRollupByFeature` in `executions.ts` MUST
reference all columns by their EN names after the rename.

### FR-012 — FTS query and search layer unaffected

The FTS layer (`knowledge_fts`, `lib/fts.ts`) uses the columns `body`,
`type`, `project`, `feature`, `wave`, `source_id`, `source_ts` — none of
which are renamed in v7. No change required in this layer; FR-012 serves
as explicit confirmation of the unchanged scope.

### FR-013 — Zero TypeScript compile errors after migration

Running `tsc --noEmit` on the monorepo MUST succeed with zero errors
after all changes are applied. This is the primary integration gate.

### FR-014 — Zero functional regressions on existing vitest suites

All existing tests that pass before this migration MUST continue to pass
after. New tests MAY be added for back-compat scenarios (v6 database
without the new columns/table), but existing coverage must not regress.

---

## Key Entities

### Column rename surface (what changes in `knowledge.db` v7)

| Entity (table) | Old name (pt-BR / v6) | New name (EN / v7) |
|---|---|---|
| `executions` (→ same name) | `execucao_id` | `execution_id` |
| `executions` | `motivo_termino` | `termination_reason` |
| `executions` | `etapa_corrente` | `current_stage` |
| `executions` | `iniciada_em` | `started_at` |
| `executions` | `terminada_em` | `finished_at` |
| `executions` | `duracao_segundos` | `duration_seconds` |
| `executions` | `stack_sugerida` | `suggested_stack` |
| `executions` | `ondas_total` | `waves_total` |
| `executions` | `wallclock_total_segundos` | `wallclock_total_seconds` |
| `executions` | `subagentes_spawned` | `subagents_spawned` |
| `executions` | `profundidade_max` | `max_depth` |
| `executions` | `decisoes_total` | `decisions_total` |
| `executions` | `bloqueios_humanos_total` | `human_blocks_total` |
| `executions` | `sugestoes_skills_total` | `skill_suggestions_total` |
| `executions` | `issues_toolkit_abertas` | `toolkit_issues_opened` |
| `waves` | `etapas` | `stages` |
| `waves` | `inicio` | `started_at` |
| `waves` | `fim` | `finished_at` |
| `waves` | `motivo_termino` | `termination_reason` |
| `waves` | `n_etapas` | `n_stages` |
| `decisions` | `etapa` | `stage` |
| `decisions` | `agente` | `agent` |
| `decisions` | `escolha` | `choice` |
| `decisions` | `opcoes` | `options` |
| `decisions` | `contexto` | `context` |
| `decisions` | `justificativa` | `rationale` |
| `decisions` | `evidencia` | `evidence` |
| `tasks` | `titulo` | `title` |
| `tasks` | `testes_rodados` | `tests_run` |
| `tasks` | `testes_passados` | `tests_passed` |
| `tasks` | `arquivos_tocados` | `touched_files` |
| `bloqueios` (TABLE) | `bloqueios` | `blocks` |
| `blocks` | `pergunta` | `question` |
| `blocks` | `contexto_para_resposta` | `context_for_answer` |
| `blocks` | `resposta` | `answer` |
| `blocks` | `decisao_id` | `decision_id` |
| `blocks` | `disparado_em` | `triggered_at` |
| `blocks` | `respondido_em` | `answered_at` |
| `blocks` | `latencia_segundos` | `latency_seconds` |
| `events` | `descricao` | `description` |
| `alert_signals` | `tipo` | `type` |
| `alert_signals` | `subtipo` | `subtype` |
| `alert_signals` | `valor_consumido` | `consumed_value` |
| `alert_signals` | `valor_threshold` | `threshold_value` |
| `alert_signals` | `descricao` | `description` |
| `retros` | `texto` | `text` |
| `skills` | `decisao_id` | `decision_id` |
| `suggestions` | `skill_afetada` | `affected_skill` |
| `suggestions` | `severidade` | `severity` |
| `suggestions` | `diagnostico` | `diagnosis` |
| `suggestions` | `proposta` | `proposal` |
| `suggestions` | `issue_aberta` | `issue_opened` |
| All tables | `execucao_id` | `execution_id` |

### Provenance columns (UNCHANGED — no action needed)
`project`, `feature`, `wave`, `source_ts`, `source_id`, `ingested_at`,
`tool_calls_total`, `wallclock_seconds`, `tool_calls`, `n_skills`,
`lint_ok`, `outcome`, `event_type`, `timestamp`, `status`, `score`,
`skill_name`, `body`, `type` (FTS), `source_id` (FTS).

### Back-compat strategy
The `hasColumn` / `hasTable` pattern (already used for `tasks.titulo` and
`decisions.opcoes` and `suggestions`) is extended to every renamed column
in every table. A v6 database presents a graceful degradation (nulls /
empty lists), not a crash. No cstk-panel code path attempts to detect the
DB schema version explicitly — capability is probed per-column.

---

## Success Criteria

1. **Full data visibility on v7**: every page in the panel displays
   non-null data for all fields that were renamed, when queried against a
   `knowledge.db` produced by `cstk` v7 with at least one ingested
   execution. No field that used to show data silently shows blank after
   the migration.

2. **Graceful degradation on v6**: with a v6 `knowledge.db` (pt-BR
   columns), every endpoint returns `200` and no uncaught exception is
   thrown. Empty/null values are acceptable; crashes are not.

3. **Zero compile errors**: `tsc --noEmit` succeeds across the full
   monorepo (`shared-types`, `apps/server`, `apps/web`) with zero
   TypeScript errors.

4. **Zero test regressions**: all vitest suites that pass before this
   migration continue to pass after. Pass rate does not decrease.

5. **Single vocabulary**: a grep for the 10 most common old pt-BR column
   names (`execucao_id`, `motivo_termino`, `etapa_corrente`,
   `iniciada_em`, `etapas`, `escolha`, `justificativa`, `descricao` in
   event/alert context, `pergunta`, `testes_rodados`) in
   `apps/server/src/` and `packages/shared-types/src/` returns zero
   results that are not inside a back-compat `hasColumn` guard or a
   comment.

6. **No new schema invented**: the migration adds no column that does not
   exist in the migration-map §3. Every change is traceable to a row in
   that frozen document.
