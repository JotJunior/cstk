-- state-db-schema.sql — DDL definitivo do state.db (feature state-db-foundation).
--
-- Fonte de contrato: docs/specs/state-db-foundation/data-model.md (9 entidades).
-- Idempotente: toda CREATE usa IF NOT EXISTS; aplicavel repetidas vezes sem
-- efeito colateral sobre um banco ja criado (task 2.1.8).
--
-- Consumido por: global/skills/agente-00c-runtime/scripts/state-db-schema.sh
-- (subcomando `create`), que aplica PRAGMA journal_mode=WAL uma unica vez na
-- criacao (dec-014 — WAL nativo) e chama este arquivo via `sqlite3 <db> < schema`.
--
-- NAO editar constraints aqui sem atualizar data-model.md correspondente —
-- este arquivo E a materializacao de contrato, nao uma copia solta.

PRAGMA foreign_keys = ON;

-- ============================================================
-- Entity: execution
-- ============================================================
CREATE TABLE IF NOT EXISTS execution (
  id                                  TEXT PRIMARY KEY,
  schema_version                      TEXT NOT NULL,
  short_name                          TEXT,
  target_project_path                 TEXT NOT NULL,
  target_project_description          TEXT NOT NULL,
  suggested_stack                     TEXT,
  status                              TEXT NOT NULL,
  termination_reason                  TEXT,
  started_at                          TEXT NOT NULL,
  finished_at                         TEXT,
  canonical_project                   TEXT,
  session_name                        TEXT,
  current_stage                       TEXT NOT NULL,
  next_instruction                    TEXT NOT NULL,
  atomic_commit_enabled               INTEGER,
  initial_key_aspects                 TEXT,
  subagent_depth                      INTEGER NOT NULL DEFAULT 1,
  max_recursion                       INTEGER NOT NULL DEFAULT 3,
  cycles_consumed_current_stage       INTEGER NOT NULL DEFAULT 0,
  max_cycles_per_stage                INTEGER NOT NULL DEFAULT 5,
  retro_executions_consumed           INTEGER NOT NULL DEFAULT 0,
  max_retro_executions_per_feature    INTEGER NOT NULL DEFAULT 2,

  -- Colunas [PROPOSTA] — decisao de granularidade dec-047 (task 2.1.7):
  -- cardinalidade 1:1 com execution, sem consumidor que precise de acesso
  -- relacional por elemento; persistidas como blob JSON, tal qual
  -- suggested_stack/initial_key_aspects acima.
  tool_calls_threshold_wave           INTEGER NOT NULL DEFAULT 80,
  wallclock_threshold_seconds         INTEGER NOT NULL DEFAULT 5400,
  state_size_threshold_bytes          INTEGER NOT NULL DEFAULT 1048576,
  external_urls_whitelist             TEXT,   -- JSON array
  circular_movement_history           TEXT,   -- JSON array (FIFO 6)
  prerequisites                       TEXT,   -- JSON object (briefing/constitution)
  briefing_cache                      TEXT,   -- JSON
  constitution_cache                  TEXT,   -- JSON
  push_pr_result                      TEXT,   -- JSON

  -- Constraint 1: enum de status
  CHECK (status IN ('em_andamento','aguardando_humano','abortada','concluida')),

  -- Constraint 2: consistencia status x finished_at
  CHECK (
    (status IN ('abortada','concluida') AND finished_at IS NOT NULL)
    OR
    (status IN ('em_andamento','aguardando_humano') AND finished_at IS NULL)
  ),

  -- Constraint 3: teto de profundidade de subagente (_ST_MAX=3 em spawn-tracker.sh)
  CHECK (subagent_depth >= 1 AND subagent_depth <= max_recursion),

  -- Constraint 4: tetos de ciclo e retro
  CHECK (cycles_consumed_current_stage <= max_cycles_per_stage),
  CHECK (retro_executions_consumed <= max_retro_executions_per_feature)
);

-- ============================================================
-- Entity: wave (Onda)
-- ============================================================
CREATE TABLE IF NOT EXISTS wave (
  id                       TEXT PRIMARY KEY,
  execution_id             TEXT NOT NULL REFERENCES execution(id),
  seq                      INTEGER NOT NULL,
  started_at               TEXT NOT NULL,
  finished_at              TEXT,
  wallclock_seconds        INTEGER,
  tool_calls               INTEGER NOT NULL DEFAULT 0,
  termination_reason       TEXT,
  next_wave_scheduled_for  TEXT,
  executed_stages          TEXT,   -- JSON array
  agent_usage              TEXT,   -- JSON
  agent_spawns             TEXT,   -- JSON
  otel_usage                TEXT,  -- JSON

  UNIQUE (execution_id, seq),

  CHECK (termination_reason IS NULL OR termination_reason IN (
    'etapa_concluida_avancando','threshold_proxy_atingido',
    'bloqueio_humano','aborto','concluido')),

  -- Coerencia: onda fechada tem os dois campos de fechamento preenchidos
  CHECK ((termination_reason IS NULL AND finished_at IS NULL)
      OR (termination_reason IS NOT NULL AND finished_at IS NOT NULL))
);

-- INVARIANTE CENTRAL (FR-002): no maximo UMA onda aberta por execucao.
-- Indice UNICO parcial: so indexa linhas com termination_reason IS NULL.
CREATE UNIQUE INDEX IF NOT EXISTS ux_wave_single_open
  ON wave(execution_id) WHERE termination_reason IS NULL;

-- "Uma onda fechada uma unica vez" (FR-002) — nao expressavel por CHECK
-- (que so enxerga a linha final, nao a transicao). Requer TRIGGER.
DROP TRIGGER IF EXISTS trg_wave_close_once;
CREATE TRIGGER trg_wave_close_once BEFORE UPDATE ON wave
WHEN OLD.termination_reason IS NOT NULL
     AND NEW.termination_reason IS NOT OLD.termination_reason
BEGIN
  SELECT RAISE(ABORT, 'wave already closed');
END;

-- ============================================================
-- Entity: decision (Decisao)
-- ============================================================
CREATE TABLE IF NOT EXISTS decision (
  id                    TEXT PRIMARY KEY,
  execution_id          TEXT NOT NULL REFERENCES execution(id),
  wave_id               TEXT REFERENCES wave(id),
  timestamp             TEXT NOT NULL,
  agent                 TEXT NOT NULL,
  stage                 TEXT NOT NULL,
  context                TEXT NOT NULL,
  options_considered    TEXT NOT NULL,   -- JSON array
  choice                TEXT NOT NULL,
  rationale             TEXT NOT NULL,
  justification_score   INTEGER,
  evidence              TEXT,
  "references"          TEXT,   -- JSON array
  originating_artifact  TEXT,

  -- Os 5 campos obrigatorios (Principio I)
  CHECK (length(agent)   > 0),
  CHECK (length(stage)   > 0),
  CHECK (length(choice)  > 0),
  CHECK (length(context)   >= 20),
  CHECK (length(rationale) >= 20),
  CHECK (json_valid(options_considered)
         AND json_array_length(options_considered) >= 1),
  CHECK (justification_score IS NULL
         OR justification_score BETWEEN 0 AND 3),

  -- Trava empirica do score 3: exige evidencia >= 20 chars
  CHECK (justification_score IS NULL OR justification_score < 3
         OR (evidence IS NOT NULL AND length(evidence) >= 20))
);

-- ============================================================
-- Entity: human_block (Bloqueio Humano)
-- ============================================================
CREATE TABLE IF NOT EXISTS human_block (
  id                    TEXT PRIMARY KEY,
  execution_id          TEXT NOT NULL REFERENCES execution(id),
  decision_id           TEXT NOT NULL REFERENCES decision(id),
  question              TEXT NOT NULL,
  context_for_answer    TEXT NOT NULL,
  recommended_options   TEXT,   -- JSON array
  status                TEXT NOT NULL,
  human_answer          TEXT,
  triggered_at          TEXT NOT NULL,
  answered_at           TEXT,

  CHECK (status IN ('aguardando','respondido')),
  CHECK ((status = 'aguardando'  AND answered_at IS NULL)
      OR (status = 'respondido' AND answered_at IS NOT NULL)),
  CHECK (length(question) >= 20),
  CHECK (length(context_for_answer) > 0)
);

-- ============================================================
-- Entity: task_outcome (Resultado de Task — camada B)
-- ============================================================
CREATE TABLE IF NOT EXISTS task_outcome (
  execution_id     TEXT NOT NULL REFERENCES execution(id),
  task_id          TEXT NOT NULL,
  title            TEXT NOT NULL,
  wave_id          TEXT NOT NULL REFERENCES wave(id),
  outcome          TEXT NOT NULL,
  tests_run        INTEGER NOT NULL,
  tests_passed     INTEGER NOT NULL,
  lint_ok          INTEGER,
  touched_files    TEXT NOT NULL,   -- JSON array
  recorded_at      TEXT NOT NULL,
  source           TEXT,

  PRIMARY KEY (execution_id, task_id),
  CHECK (outcome IN ('pass','fail')),
  CHECK (tests_run >= 0 AND tests_passed >= 0 AND tests_passed <= tests_run),
  CHECK (lint_ok IS NULL OR lint_ok IN (0,1))
);

-- ============================================================
-- Entity: event (Evento — timeline cronologica)
-- ============================================================
CREATE TABLE IF NOT EXISTS event (
  id             INTEGER PRIMARY KEY AUTOINCREMENT,
  execution_id   TEXT NOT NULL REFERENCES execution(id),
  event_type     TEXT NOT NULL,
  timestamp      TEXT NOT NULL,
  description    TEXT,

  CHECK (length(event_type) > 0)
);

-- ============================================================
-- Entity: skill_invocation (Invocacao de Skill/Gate)
-- ============================================================
CREATE TABLE IF NOT EXISTS skill_invocation (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  wave_id       TEXT NOT NULL REFERENCES wave(id),
  skill         TEXT NOT NULL,
  timestamp     TEXT NOT NULL,
  decision_id   TEXT REFERENCES decision(id),
  kind          TEXT NOT NULL DEFAULT 'skill',

  CHECK (length(skill) > 0),
  CHECK (kind IN ('skill','gate'))
);

-- ============================================================
-- Entity: migration_run (Execucao de Migracao) — [PROPOSTA], sem
-- contrapartida no state.json atual (FR-005/FR-006/FR-014-INFRA-IDEMP)
-- ============================================================
CREATE TABLE IF NOT EXISTS migration_run (
  id               INTEGER PRIMARY KEY AUTOINCREMENT,
  execution_id     TEXT NOT NULL,
  source_path      TEXT NOT NULL,
  source_sha256    TEXT NOT NULL,
  started_at       TEXT NOT NULL,
  finished_at      TEXT,
  result           TEXT NOT NULL,
  diagnostic       TEXT,
  counts_source    TEXT,   -- JSON
  counts_target    TEXT,   -- JSON

  CHECK (result IN ('success','refused','failed'))
);

-- ============================================================
-- Indices de apoio (consultas frequentes dos scripts de runtime)
-- ============================================================
CREATE INDEX IF NOT EXISTS ix_decision_execution   ON decision(execution_id);
CREATE INDEX IF NOT EXISTS ix_decision_wave         ON decision(wave_id);
CREATE INDEX IF NOT EXISTS ix_human_block_execution ON human_block(execution_id);
CREATE INDEX IF NOT EXISTS ix_human_block_status    ON human_block(status);
CREATE INDEX IF NOT EXISTS ix_task_outcome_wave     ON task_outcome(wave_id);
CREATE INDEX IF NOT EXISTS ix_event_execution       ON event(execution_id);
CREATE INDEX IF NOT EXISTS ix_skill_invocation_wave ON skill_invocation(wave_id);
CREATE INDEX IF NOT EXISTS ix_wave_execution        ON wave(execution_id);
