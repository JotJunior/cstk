/**
 * 7.4 Testes de paridade de tipos — shared-types ↔ payload real da API.
 * Ref: plan.md §Convencoes de Borda; quickstart.md §Cenario 1
 * Tasks 7.4.1 – 7.4.4
 * Updated: schema v7 EN canonical (feature new-schema)
 *
 * Para cada DTO, fixtures de payload real (copiadas diretamente de
 * respostas reais da API) sao parseadas com safeParse(...).
 *
 * 7.4.2: TaskDTO — touchedFilesCount e number (nao array), lintOk e boolean
 * 7.4.3: WaveDTO — stages e string (nao array)
 * 7.4.4: Teste de regressao — modificar campo para snake_case → safeParse falha
 *
 * Estes fixtures foram copiados de respostas reais da API (fixture DB real).
 * Ref: execucao 'exec-20260506T125546Z' da fixture knowledge-fixture.db.
 */
import { describe, it, expect } from 'vitest';
import {
  ExecutionDTOSchema,
  WaveDTOSchema,
  TaskDTOSchema,
  FtsHitDTOSchema,
  DecisionDTOSchema,
  AlertSignalDTOSchema,
  ModelUsageEntrySchema,
  ModelUsageByStageSchema,
  ModelUsageCoverageSchema,
  ModelUsageResultSchema,
} from '../schemas/entities.js';
import { RawApiEnvelopeSchema } from '../schemas/envelope.js';

// ─── Fixtures reais (shape capturado da API) ───────────────────────────────────
// Todos os campos em camelCase EN (convencao de borda: snake_case DB → camelCase EN DTO)

const ISO = '2026-05-06T12:57:32Z';

// ExecutionDTO real (shape da rota GET /executions/:id) — schema v8 EN
const REAL_EXECUTION_PAYLOAD = {
  project: 'cad-poc',
  feature: 'unknown',
  executionId: 'exec-20260506T125546Z',
  status: 'concluida' as const,
  terminationReason: 'concluido',
  currentStage: 'review-task',
  startedAt: ISO,
  finishedAt: '2026-05-06T20:00:00Z',
  durationSeconds: 25900,
  suggestedStack: null,
  wavesTotal: 10,
  toolCallsTotal: 320,
  wallclockTotalSeconds: 9600,
  subagentsSpawned: null,
  maxDepth: null,
  decisionsTotal: 42,
  humanBlocksTotal: null,
  skillSuggestionsTotal: null,
  toolkitIssuesOpened: null,
  session: null,             // schema v8 — execucao fora de sessao de worktree
};

// WaveDTO real (shape da rota GET /executions/:id/waves)
// CRITICO: stages e string, NAO array (convencao borda v7)
const REAL_WAVE_PAYLOAD = {
  wave: 'onda-001',
  executionId: 'exec-20260506T125546Z',
  stages: 'execute-task',     // string unica — NAO array
  startedAt: ISO,
  finishedAt: '2026-05-06T13:16:15Z',
  wallclockSeconds: 1123,
  toolCalls: 0,
  terminationReason: 'etapa_concluida_avancando',
  nStages: 0,
  nSkills: 0,
  session: null,             // schema v8 — onda fora de sessao de worktree
  // schema v10 — onda anterior a feature wave-token-metrics: TODOS os campos
  // de uso null (nem a contagem de spawns existe). Nao e "consumo zero".
  agentSpawnsTotal: null,
  agentSpawnsWithUsage: null,
  agentTotalTokens: null,
  agentInputTokens: null,
  agentOutputTokens: null,
  agentCacheReadTokens: null,
  agentCacheCreationTokens: null,
  agentToolUseCount: null,
  agentDurationMs: null,
  // schema v11 — servido sobre base v<11 o servidor projeta NULL nas 5
  // colunas (verificado empiricamente: GET /executions/:id/waves sobre uma
  // knowledge.db v10 devolve exatamente estes cinco nulls).
  otelCostUsd: null,
  otelCostMainUsd: null,
  otelCostSubagentUsd: null,
  otelTotalTokens: null,
  otelSubagentTokens: null,
};

/**
 * WaveDTO real de base v10 — payload capturado VERBATIM de
 * `GET /executions/:id/waves` servido sobre uma knowledge.db gerada pelo
 * proprio `cstk recall --ingest` (cstk 5.25.0) a partir de um state.json com
 * `.waves[].agent_usage`. Fixture escrita a mao nao valeria: ela so provaria
 * que o schema aceita o que o schema espera.
 */
const REAL_WAVE_V10_PAYLOAD = {
  wave: 'onda-001',
  executionId: 'token-demo-20260726T090000Z',
  stages: 'specify,clarify',
  startedAt: '2026-07-26T09:00:00Z',
  finishedAt: '2026-07-26T10:00:00Z',
  wallclockSeconds: 3600,
  toolCalls: 90,
  terminationReason: 'etapa_concluida_avancando',
  nStages: 2,
  nSkills: 1,
  session: null,
  agentSpawnsTotal: 4,
  agentSpawnsWithUsage: 3,        // amostra parcial: 1 spawn sem dado de uso
  agentTotalTokens: 248500,
  agentInputTokens: 9800,
  agentOutputTokens: 21400,
  agentCacheReadTokens: 198300,
  agentCacheCreationTokens: 19000,
  agentToolUseCount: 41,
  agentDurationMs: 512000,
  otelCostUsd: null,
  otelCostMainUsd: null,
  otelCostSubagentUsd: null,
  otelTotalTokens: null,
  otelSubagentTokens: null,
};

/**
 * WaveDTO real de base v11 — payload capturado VERBATIM de
 * `GET /executions/:id/waves` servido sobre uma knowledge.db gerada pelo
 * proprio `cstk recall --ingest` (cstk 5.30.0) a partir de um state.json com
 * `.waves[].otel_usage`. Repare no custo FRACIONARIO: 0.098485 nao sobrevive
 * a um schema que assuma inteiro, e $0.00 na UI seria indistinguivel de
 * "onda que nao custou nada".
 */
const REAL_WAVE_V11_PAYLOAD = {
  wave: 'onda-001',
  executionId: 'exec-otel-panel',
  stages: 'plan',
  startedAt: '2026-07-26T10:00:00Z',
  finishedAt: '2026-07-26T10:05:00Z',
  wallclockSeconds: 300,
  toolCalls: 90,
  terminationReason: '',
  nStages: 1,
  nSkills: 0,
  session: null,
  agentSpawnsTotal: 4,
  agentSpawnsWithUsage: 3,
  agentTotalTokens: 248500,
  agentInputTokens: 9800,
  agentOutputTokens: 21400,
  agentCacheReadTokens: 198300,
  agentCacheCreationTokens: 19000,
  agentToolUseCount: 41,
  agentDurationMs: 512000,
  otelCostUsd: 0.229038,
  otelCostMainUsd: 0.130553,
  otelCostSubagentUsd: 0.098485,
  otelTotalTokens: 648,
  otelSubagentTokens: 648,
};

/** Onda da MESMA execucao sem telemetria coletada — as 5 colunas vem null. */
const REAL_WAVE_V11_NO_OTEL_PAYLOAD = {
  ...REAL_WAVE_V11_PAYLOAD,
  wave: 'onda-002',
  stages: 'execute-task',
  startedAt: '2026-07-26T11:00:00Z',
  finishedAt: '2026-07-26T11:04:00Z',
  wallclockSeconds: 240,
  toolCalls: 40,
  agentSpawnsTotal: null,
  agentSpawnsWithUsage: null,
  agentTotalTokens: null,
  agentInputTokens: null,
  agentOutputTokens: null,
  agentCacheReadTokens: null,
  agentCacheCreationTokens: null,
  agentToolUseCount: null,
  agentDurationMs: null,
  otelCostUsd: null,
  otelCostMainUsd: null,
  otelCostSubagentUsd: null,
  otelTotalTokens: null,
  otelSubagentTokens: null,
};

/** Onda v10 com spawns observados mas NENHUM dado de uso (background). */
const REAL_WAVE_V10_NO_USAGE_PAYLOAD = {
  ...REAL_WAVE_V10_PAYLOAD,
  wave: 'onda-003',
  stages: 'create-tasks,execute-task',
  agentSpawnsTotal: 2,
  agentSpawnsWithUsage: 0,
  agentTotalTokens: null,
  agentInputTokens: null,
  agentOutputTokens: null,
  agentCacheReadTokens: null,
  agentCacheCreationTokens: null,
  agentToolUseCount: null,
  agentDurationMs: null,
};

// TaskDTO real (shape da rota GET /executions/:id/tasks)
// CRITICO: touchedFilesCount e number, lintOk e boolean
const REAL_TASK_PAYLOAD = {
  wave: 'onda-005',
  executionId: 'exec-20260506T125546Z',
  title: 'Implementar ingestao de metricas',  // schema v7 EN
  outcome: 'pass' as const,
  testsRun: 12,
  testsPassed: 12,
  lintOk: true,               // boolean (nao 0/1)
  touchedFilesCount: 5,       // number (nao array de paths)
};

// DecisionDTO real (shape da rota GET /executions/:id/decisions)
const REAL_DECISION_PAYLOAD = {
  wave: 'onda-003',
  executionId: 'exec-20260506T125546Z',
  stage: 'execute-task',
  agent: 'agente-00c-orchestrator',
  choice: 'manter-tipo',
  options: '["manter-tipo","refatorar","ignorar"]',
  score: 2 as const,
  context: 'Tipo incompativel em src/foo.ts',
  rationale: 'tsc indica TS2322',
  evidencia: 'npx tsc --noEmit: src/foo.ts:12 error TS2322',
};

// FtsHitDTO real (shape da rota GET /search)
const REAL_FTS_HIT_PAYLOAD = {
  body: 'execute-task executar a tarefa 4.1 conforme o plano',
  type: 'decision',
  project: 'cad-poc',
  feature: 'unknown',
  wave: 'onda-007',
  sourceId: 'dec-001',
  sourceTs: ISO,
  rank: -1.234,
};

// AlertSignalDTO real
const REAL_ALERT_SIGNAL_PAYLOAD = {
  executionId: 'exec-20260506T125546Z',
  type: 'budget_breach' as const,
  subtype: 'tool_calls',
  consumedValue: 320,
  thresholdValue: 300,
  description: 'tool_calls excedeu threshold',
  wave: 'onda-009',
};

// Envelope real (wrapper em torno de qualquer data)
const REAL_ENVELOPE_PAYLOAD = {
  data: { totalExecutions: 14 },
  meta: {
    degraded: false,
    reason: null,
    freshness: {
      mtime: '2026-05-24T10:47:02.000Z',
      maxIngestedAt: '2026-05-24T10:47:02Z',
    },
    schemaVersion: '2',
  },
};

// ─── 7.4.1 Parse de cada DTO com fixture real ─────────────────────────────────

describe('7.4.1 Paridade shared-types ↔ payload real', () => {
  it('ExecutionDTOSchema.safeParse(payload_real) === true', () => {
    const r = ExecutionDTOSchema.safeParse(REAL_EXECUTION_PAYLOAD);
    expect(r.success, `falhou: ${JSON.stringify(r.error?.issues?.slice(0, 3))}`).toBe(true);
  });

  it('WaveDTOSchema.safeParse(payload_real_v10) === true', () => {
    const r = WaveDTOSchema.safeParse(REAL_WAVE_V10_PAYLOAD);
    expect(r.success).toBe(true);
  });

  it('WaveDTO v10: onda com spawns mas sem dado de uso mantem tokens null', () => {
    const r = WaveDTOSchema.safeParse(REAL_WAVE_V10_NO_USAGE_PAYLOAD);
    expect(r.success).toBe(true);
    if (r.success) {
      // Invariante de honestidade: 2 spawns observados, 0 com uso — os tokens
      // NAO podem ser 0 (seria afirmar "medido e deu zero").
      expect(r.data.agentSpawnsTotal).toBe(2);
      expect(r.data.agentSpawnsWithUsage).toBe(0);
      expect(r.data.agentTotalTokens).toBeNull();
    }
  });

  it('WaveDTOSchema.safeParse(payload_real_v11) === true', () => {
    const r = WaveDTOSchema.safeParse(REAL_WAVE_V11_PAYLOAD);
    expect(r.success, `falhou: ${JSON.stringify(r.error?.issues?.slice(0, 3))}`).toBe(true);
    if (r.success) {
      // Custo em USD e FRACIONARIO: um schema com .int() ou um mapper que
      // arredondasse mataria a metrica (0.098485 -> 0). Trava aqui.
      expect(r.data.otelCostUsd).toBeCloseTo(0.229038, 6);
      expect(r.data.otelCostSubagentUsd).toBeCloseTo(0.098485, 6);
      // As duas fontes coexistem e NAO se somam: agent* (por spawn) e otel*
      // (por API request, incluindo o proprio orquestrador).
      expect(r.data.agentTotalTokens).toBe(248500);
      expect(r.data.otelTotalTokens).toBe(648);
    }
  });

  it('WaveDTO v11: onda sem telemetria mantem os 5 campos null, jamais 0', () => {
    const r = WaveDTOSchema.safeParse(REAL_WAVE_V11_NO_OTEL_PAYLOAD);
    expect(r.success).toBe(true);
    if (r.success) {
      expect(r.data.otelCostUsd).toBeNull();
      expect(r.data.otelCostMainUsd).toBeNull();
      expect(r.data.otelCostSubagentUsd).toBeNull();
      expect(r.data.otelTotalTokens).toBeNull();
      expect(r.data.otelSubagentTokens).toBeNull();
    }
  });

  it('WaveDTO: payload sem os campos v11 e REJEITADO (drift de borda)', () => {
    // Mesma regra do bloco v10: ausencia != null. Se a query parar de projetar
    // as colunas, isto falha aqui em vez de virar `undefined` -> "$0" na UI.
    const { otelCostUsd: _omit, ...semCampoV11 } = REAL_WAVE_V11_PAYLOAD;
    const r = WaveDTOSchema.safeParse(semCampoV11);
    expect(r.success).toBe(false);
  });

  it('WaveDTO: payload sem os campos v10 e REJEITADO (drift de borda)', () => {
    // Ausencia != null. Se o mapper parar de projetar as colunas, o schema
    // precisa falhar aqui em vez de deixar `undefined` virar 0 na UI.
    const { agentTotalTokens: _omit, ...semCampoV10 } = REAL_WAVE_V10_PAYLOAD;
    const r = WaveDTOSchema.safeParse(semCampoV10);
    expect(r.success).toBe(false);
  });

  it('WaveDTOSchema.safeParse(payload_real) === true', () => {
    const r = WaveDTOSchema.safeParse(REAL_WAVE_PAYLOAD);
    expect(r.success, `falhou: ${JSON.stringify(r.error?.issues?.slice(0, 3))}`).toBe(true);
  });

  it('TaskDTOSchema.safeParse(payload_real) === true', () => {
    const r = TaskDTOSchema.safeParse(REAL_TASK_PAYLOAD);
    expect(r.success, `falhou: ${JSON.stringify(r.error?.issues?.slice(0, 3))}`).toBe(true);
  });

  it('DecisionDTOSchema.safeParse(payload_real) === true', () => {
    const r = DecisionDTOSchema.safeParse(REAL_DECISION_PAYLOAD);
    expect(r.success, `falhou: ${JSON.stringify(r.error?.issues?.slice(0, 3))}`).toBe(true);
  });

  it('FtsHitDTOSchema.safeParse(payload_real) === true', () => {
    const r = FtsHitDTOSchema.safeParse(REAL_FTS_HIT_PAYLOAD);
    expect(r.success, `falhou: ${JSON.stringify(r.error?.issues?.slice(0, 3))}`).toBe(true);
  });

  it('AlertSignalDTOSchema.safeParse(payload_real) === true', () => {
    const r = AlertSignalDTOSchema.safeParse(REAL_ALERT_SIGNAL_PAYLOAD);
    expect(r.success, `falhou: ${JSON.stringify(r.error?.issues?.slice(0, 3))}`).toBe(true);
  });

  it('RawApiEnvelopeSchema.safeParse(envelope_real) === true', () => {
    const r = RawApiEnvelopeSchema.safeParse(REAL_ENVELOPE_PAYLOAD);
    expect(r.success, `falhou: ${JSON.stringify(r.error?.issues?.slice(0, 3))}`).toBe(true);
  });
});

// ─── 7.4.2 TaskDTO: touchedFilesCount e number, lintOk e boolean ──────────────

describe('7.4.2 TaskDTO — campos criticos', () => {
  it('touchedFilesCount e number (nao array)', () => {
    const r = TaskDTOSchema.safeParse(REAL_TASK_PAYLOAD);
    expect(r.success).toBe(true);
    if (r.success) {
      expect(typeof r.data.touchedFilesCount).toBe('number');
      expect(Array.isArray(r.data.touchedFilesCount)).toBe(false);
    }
  });

  it('lintOk e boolean (nao 0 nem 1)', () => {
    const r = TaskDTOSchema.safeParse(REAL_TASK_PAYLOAD);
    expect(r.success).toBe(true);
    if (r.success) {
      expect(typeof r.data.lintOk).toBe('boolean');
    }
  });

  it('lintOk=false tambem passa (nao apenas true)', () => {
    const payload = { ...REAL_TASK_PAYLOAD, lintOk: false };
    const r = TaskDTOSchema.safeParse(payload);
    expect(r.success).toBe(true);
  });

  it('TaskDTO rejeita touchedFilesCount como array (schema nao aceita)', () => {
    const badPayload = { ...REAL_TASK_PAYLOAD, touchedFilesCount: ['src/foo.ts', 'src/bar.ts'] };
    const r = TaskDTOSchema.safeParse(badPayload);
    expect(r.success).toBe(false);
  });

  it('TaskDTO rejeita lintOk como inteiro 0/1 (boolean obrigatorio)', () => {
    const badPayload = { ...REAL_TASK_PAYLOAD, lintOk: 1 };
    const r = TaskDTOSchema.safeParse(badPayload);
    expect(r.success).toBe(false);
  });
});

// ─── 7.4.3 WaveDTO: stages e string, NAO array ───────────────────────────────

describe('7.4.3 WaveDTO — stages e string (nao array)', () => {
  it('stages como string passa', () => {
    const r = WaveDTOSchema.safeParse(REAL_WAVE_PAYLOAD);
    expect(r.success).toBe(true);
    if (r.success) {
      expect(typeof r.data.stages).toBe('string');
    }
  });

  it('stages como array FALHA (nao e array em schema v7)', () => {
    const badPayload = { ...REAL_WAVE_PAYLOAD, stages: ['execute-task', 'review-task'] };
    const r = WaveDTOSchema.safeParse(badPayload);
    expect(r.success).toBe(false);
  });

  it('stages como string vazia passa (onda sem etapas registradas)', () => {
    const emptyPayload = { ...REAL_WAVE_PAYLOAD, stages: '' };
    const r = WaveDTOSchema.safeParse(emptyPayload);
    expect(r.success).toBe(true);
  });
});

// ─── 7.4.4 Teste de regressao: snake_case → safeParse falha ──────────────────

describe('7.4.4 Regressao — snake_case causa falha em safeParse (teste nao e trivial)', () => {
  it('ExecutionDTOSchema rejeita execution_id (snake_case) — deve ser executionId', () => {
    const snakeCasePayload = {
      project: 'cad-poc',
      feature: 'unknown',
      execution_id: 'exec-001',          // snake_case — schema espera executionId
      status: 'concluida',
      termination_reason: null,          // snake_case
      current_stage: null,
      started_at: null,
      finished_at: null,
      duration_seconds: null,
      suggested_stack: null,
      waves_total: null,
      tool_calls_total: null,
      wallclock_total_seconds: null,
      subagents_spawned: null,
      max_depth: null,
      decisions_total: null,
      human_blocks_total: null,
      skill_suggestions_total: null,
      toolkit_issues_opened: null,
    };
    const r = ExecutionDTOSchema.safeParse(snakeCasePayload);
    // Schema exige executionId (camelCase EN) — snake_case deve falhar
    expect(r.success).toBe(false);
  });

  it('WaveDTOSchema rejeita tool_calls (snake_case) — deve ser toolCalls', () => {
    const snakeWave = {
      wave: 'onda-001',
      execution_id: 'exec-001',   // snake_case
      stages: 'execute-task',
      started_at: ISO,
      finished_at: null,
      wallclock_seconds: 1123,  // snake_case
      tool_calls: 0,             // snake_case
      termination_reason: null,
      n_stages: 0,
      n_skills: 0,
    };
    const r = WaveDTOSchema.safeParse(snakeWave);
    // snake_case deve falhar — schema exige executionId, wallclockSeconds, toolCalls
    expect(r.success).toBe(false);
  });

  it('FtsHitDTOSchema rejeita source_id (snake_case) — deve ser sourceId', () => {
    const snakeHit = {
      body: 'texto',
      type: 'decision',
      project: 'proj',
      feature: 'feat',
      wave: 'onda-001',
      source_id: 'dec-001',  // snake_case — deve ser sourceId
      source_ts: ISO,        // snake_case — deve ser sourceTs
      rank: -1.0,
    };
    const r = FtsHitDTOSchema.safeParse(snakeHit);
    // sourceId e sourceTs obrigatorios — snake_case deve falhar
    expect(r.success).toBe(false);
  });

  it('TaskDTOSchema rejeita touched_files_count (snake_case) — deve ser touchedFilesCount', () => {
    const snakeTask = {
      wave: 'onda-005',
      execution_id: 'exec-001',       // snake_case
      outcome: 'pass',
      tests_run: 12,                  // snake_case
      tests_passed: 12,               // snake_case
      lint_ok: true,                  // snake_case
      touched_files_count: 5,         // snake_case
    };
    const r = TaskDTOSchema.safeParse(snakeTask);
    // touchedFilesCount obrigatorio — snake_case deve falhar
    expect(r.success).toBe(false);
  });
});

// ─── Validacao de enums (status, outcome, eventType, type) ───────────────────

describe('7.4 Enums — valores fora do enum rejeitados', () => {
  it('ExecutionDTOSchema rejeita status desconhecido', () => {
    const r = ExecutionDTOSchema.safeParse({ ...REAL_EXECUTION_PAYLOAD, status: 'pausada' });
    expect(r.success).toBe(false);
  });

  it('TaskDTOSchema rejeita outcome desconhecido', () => {
    const r = TaskDTOSchema.safeParse({ ...REAL_TASK_PAYLOAD, outcome: 'skip' });
    expect(r.success).toBe(false);
  });

  it('AlertSignalDTOSchema rejeita type desconhecido', () => {
    const r = AlertSignalDTOSchema.safeParse({ ...REAL_ALERT_SIGNAL_PAYLOAD, type: 'warning' });
    expect(r.success).toBe(false);
  });
});

// ─── 2.4.9 Paridade de chaves — ModelUsage DTOs (schema v12, wave_model_usage) ─
//
// TS interfaces nao existem em runtime — nao ha `keyof` reflexivo disponivel
// aqui. A paridade e garantida mantendo, a mao, um array de chaves espelhando
// EXATAMENTE `entities.ts` (comentado com o nome da interface), comparado
// contra `Object.keys(Schema.shape)`. Se um dos dois lados esquecer um campo
// (a interface ganha um campo novo sem o Zod, ou vice-versa), o teste falha.
// Ref: tasks.md 2.4.9; contracts/model-usage-endpoint.md Invariante 5.

/** Espelha `ModelUsageEntry` (entities.ts). */
const MODEL_USAGE_ENTRY_KEYS = ['model', 'costUsd', 'totalTokens', 'waves'];
/** Espelha `ModelUsageByStage` (entities.ts). */
const MODEL_USAGE_BY_STAGE_KEYS = ['stage', 'model', 'costUsd', 'totalTokens'];
/** Espelha `ModelUsageCoverage` (entities.ts). */
const MODEL_USAGE_COVERAGE_KEYS = ['wavesTotal', 'wavesWithModelUsage', 'wavesWithOtelCost'];
/** Espelha `ModelUsageResult` (entities.ts). */
const MODEL_USAGE_RESULT_KEYS = ['byModel', 'byStage', 'coverage'];

describe('2.4.9 Paridade de chaves — ModelUsage DTOs (interface manual == Schema.shape)', () => {
  it('ModelUsageEntry', () => {
    expect(Object.keys(ModelUsageEntrySchema.shape).sort()).toEqual([...MODEL_USAGE_ENTRY_KEYS].sort());
  });

  it('ModelUsageByStage', () => {
    expect(Object.keys(ModelUsageByStageSchema.shape).sort()).toEqual([...MODEL_USAGE_BY_STAGE_KEYS].sort());
  });

  it('ModelUsageCoverage', () => {
    expect(Object.keys(ModelUsageCoverageSchema.shape).sort()).toEqual([...MODEL_USAGE_COVERAGE_KEYS].sort());
  });

  it('ModelUsageResult', () => {
    expect(Object.keys(ModelUsageResultSchema.shape).sort()).toEqual([...MODEL_USAGE_RESULT_KEYS].sort());
  });
});

// ─── ModelUsageResultSchema — payload representativo ─────────────────────────
//
// Os valores abaixo (byModel/coverage) sao os mesmos citados em
// contracts/model-usage-endpoint.md §Response 200 — capturados por sondagem
// direta (S3/S5) sobre `~/.claude/cstk/knowledge.db` real na epoca do plano.
// Nao sao um "payload real desta execucao" (a contagem de linhas em
// `wave_model_usage` cresce a cada onda ingerida), mas SAO valores medidos
// reais, nao inventados — o contrato ja rotula isso explicitamente.

describe('ModelUsageResultSchema — payload representativo do contrato', () => {
  it('aceita o shape documentado (contracts/model-usage-endpoint.md §Response 200)', () => {
    const payload = {
      byModel: [
        { model: 'claude-sonnet-5', costUsd: 465.3943, totalTokens: 1127119533, waves: 36 },
        { model: 'claude-fable-5', costUsd: 23.5946, totalTokens: 13884110, waves: 7 },
        { model: 'claude-opus-5[1m]', costUsd: 6.1439, totalTokens: 6864604, waves: 1 },
      ],
      byStage: [],
      coverage: { wavesTotal: 920, wavesWithModelUsage: 36, wavesWithOtelCost: 46 },
    };
    const r = ModelUsageResultSchema.safeParse(payload);
    expect(r.success, `falhou: ${JSON.stringify(r.error?.issues?.slice(0, 3))}`).toBe(true);
  });

  it('estado degradado (tabela ausente, Decision 4): coverage com os 3 campos null, nunca 0', () => {
    const payload = {
      byModel: [],
      byStage: [],
      coverage: { wavesTotal: null, wavesWithModelUsage: null, wavesWithOtelCost: null },
    };
    const r = ModelUsageResultSchema.safeParse(payload);
    expect(r.success).toBe(true);
  });

  it('model IS NULL na origem vira rotulo (desconhecido) — model e sempre string, nunca null', () => {
    const r = ModelUsageEntrySchema.safeParse({
      model: '(desconhecido)', costUsd: null, totalTokens: null, waves: 3,
    });
    expect(r.success).toBe(true);
  });

  it('rejeita snake_case (total_tokens) — regressao de borda', () => {
    const badPayload = { model: 'claude-sonnet-5', cost_usd: 1, total_tokens: 2, waves: 1 };
    const r = ModelUsageEntrySchema.safeParse(badPayload);
    expect(r.success).toBe(false);
  });

  it('ModelUsageByStage: aceita etapa + modelo com custo fracionario', () => {
    const r = ModelUsageByStageSchema.safeParse({
      stage: 'execute-task', model: 'claude-sonnet-5', costUsd: 158.8716, totalTokens: 389180262,
    });
    expect(r.success).toBe(true);
  });
});
