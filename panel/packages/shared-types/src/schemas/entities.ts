/**
 * Schemas Zod para DTOs de dominio.
 * Ref: plan.md §Convencoes de Borda; spec.md FR-012
 */
import { z } from 'zod';

// ---------------------------------------------------------------------------
// ExecutionDTO schema
// ---------------------------------------------------------------------------
export const ExecutionDTOSchema = z.object({
  project: z.string(),
  feature: z.string(),
  executionId: z.string(),
  status: z.enum(['em_andamento', 'aguardando_humano', 'concluida', 'abortada']).nullable(),
  terminationReason: z.string().nullable(),
  currentStage: z.string().nullable(),
  startedAt: z.string().nullable(),
  finishedAt: z.string().nullable(),
  durationSeconds: z.number().nullable(),
  suggestedStack: z.string().nullable(),
  wavesTotal: z.number().nullable(),
  toolCallsTotal: z.number().nullable(),
  wallclockTotalSeconds: z.number().nullable(),
  subagentsSpawned: z.number().nullable(),
  maxDepth: z.number().nullable(),
  decisionsTotal: z.number().nullable(),
  humanBlocksTotal: z.number().nullable(),
  skillSuggestionsTotal: z.number().nullable(),
  toolkitIssuesOpened: z.number().nullable(),
  session: z.string().nullable(),
});

// ---------------------------------------------------------------------------
// WaveDTO schema
// ---------------------------------------------------------------------------
export const WaveDTOSchema = z.object({
  wave: z.string(),
  executionId: z.string(),
  stages: z.string(), // string unica — NAO array (schema v7)
  startedAt: z.string().nullable(),
  finishedAt: z.string().nullable(),
  wallclockSeconds: z.number().nullable(),
  toolCalls: z.number().nullable(),
  terminationReason: z.string().nullable(),
  nStages: z.number().nullable(),
  nSkills: z.number().nullable(),
  session: z.string().nullable(),
  // Consumo de subagentes (schema v10). Nullable em toda base; `.default(null)`
  // NAO e usado de proposito: um payload de base v<10 traz os campos
  // explicitamente null (o mapper projeta NULL), e um payload que os omitisse
  // deve falhar a paridade em vez de virar 0/undefined silencioso.
  agentSpawnsTotal: z.number().nullable(),
  agentSpawnsWithUsage: z.number().nullable(),
  agentTotalTokens: z.number().nullable(),
  agentInputTokens: z.number().nullable(),
  agentOutputTokens: z.number().nullable(),
  agentCacheReadTokens: z.number().nullable(),
  agentCacheCreationTokens: z.number().nullable(),
  agentToolUseCount: z.number().nullable(),
  agentDurationMs: z.number().nullable(),
  // Consumo medido por telemetria OTel (schema v11). Custo e REAL (fracionario,
  // ex: 0.098485) — z.number() sem .int() de proposito. Mesma politica do
  // bloco acima: nullable obrigatorio, nunca .default(null).
  otelCostUsd: z.number().nullable(),
  otelCostMainUsd: z.number().nullable(),
  otelCostSubagentUsd: z.number().nullable(),
  otelTotalTokens: z.number().nullable(),
  otelSubagentTokens: z.number().nullable(),
  // Breakdown de tokens por fonte x tipo (schema v12). Contagem de token e
  // inteira, mas seguimos sem .int(): a borda nao deve rejeitar a leitura de
  // uma base por causa do TIPO de um numero — a degradacao util aqui e null.
  otelMainInputTokens: z.number().nullable(),
  otelMainOutputTokens: z.number().nullable(),
  otelMainCacheReadTokens: z.number().nullable(),
  otelMainCacheCreationTokens: z.number().nullable(),
  otelSubagentInputTokens: z.number().nullable(),
  otelSubagentOutputTokens: z.number().nullable(),
  otelSubagentCacheReadTokens: z.number().nullable(),
  otelSubagentCacheCreationTokens: z.number().nullable(),
});

// ---------------------------------------------------------------------------
// AgentUsageRollup schema (schema v10 — agregado de projeto/feature/metrica)
// ---------------------------------------------------------------------------
export const AgentUsageRollupSchema = z.object({
  spawnsTotal: z.number().nullable(),
  spawnsWithUsage: z.number().nullable(),
  totalTokens: z.number().nullable(),
  inputTokens: z.number().nullable(),
  outputTokens: z.number().nullable(),
  cacheReadTokens: z.number().nullable(),
  cacheCreationTokens: z.number().nullable(),
  toolUseCount: z.number().nullable(),
  durationMs: z.number().nullable(),
  wavesWithUsage: z.number().nullable(),
  wavesTotal: z.number().nullable(),
});

// ---------------------------------------------------------------------------
// OtelUsageRollup schema (schema v11 — agregado de projeto/feature/metrica)
// Custo em USD e fracionario: nada de z.number().int() aqui.
// ---------------------------------------------------------------------------
export const OtelUsageRollupSchema = z.object({
  costUsd: z.number().nullable(),
  costMainUsd: z.number().nullable(),
  costSubagentUsd: z.number().nullable(),
  totalTokens: z.number().nullable(),
  subagentTokens: z.number().nullable(),
  wavesWithOtel: z.number().nullable(),
  wavesTotal: z.number().nullable(),
  // Breakdown por fonte x tipo (schema v12) + as DUAS coberturas separadas.
  mainInputTokens: z.number().nullable(),
  mainOutputTokens: z.number().nullable(),
  mainCacheReadTokens: z.number().nullable(),
  mainCacheCreationTokens: z.number().nullable(),
  subagentInputTokens: z.number().nullable(),
  subagentOutputTokens: z.number().nullable(),
  subagentCacheReadTokens: z.number().nullable(),
  subagentCacheCreationTokens: z.number().nullable(),
  wavesWithMainBreakdown: z.number().nullable(),
  wavesWithSubagentBreakdown: z.number().nullable(),
});

// ---------------------------------------------------------------------------
// ModelUsage DTOs schema (schema v12, `wave_model_usage`)
// Ref: contracts/model-usage-endpoint.md; data-model.md Parte B.
// Sem `.default(null)` nos campos nulos (mesmo padrao de WaveDTOSchema
// acima) — ausencia de campo deve falhar o parse, nao virar silenciosamente
// 0/undefined na UI.
// ---------------------------------------------------------------------------
export const ModelUsageEntrySchema = z.object({
  model: z.string(),
  costUsd: z.number().nullable(),
  totalTokens: z.number().nullable(),
  waves: z.number(),
});

export const ModelUsageByStageSchema = z.object({
  stage: z.string(),
  model: z.string(),
  costUsd: z.number().nullable(),
  totalTokens: z.number().nullable(),
});

export const ModelUsageCoverageSchema = z.object({
  wavesTotal: z.number().nullable(),
  wavesWithModelUsage: z.number().nullable(),
  wavesWithOtelCost: z.number().nullable(),
});

export const ModelUsageResultSchema = z.object({
  byModel: z.array(ModelUsageEntrySchema),
  byStage: z.array(ModelUsageByStageSchema),
  coverage: ModelUsageCoverageSchema,
});

// ---------------------------------------------------------------------------
// LooseUsage DTOs schema (schema v13, `loose_usage`, cstk 6.6.0) — consumo
// avulso fora de pipeline. Mesmo padrao dos demais: sem `.default(null)` —
// ausencia de campo falha o parse, nunca vira 0/undefined silencioso.
// ---------------------------------------------------------------------------
export const LooseUsageProjectEntrySchema = z.object({
  project: z.string(),
  projectPath: z.string().nullable(),
  costUsd: z.number().nullable(),
  totalTokens: z.number().nullable(),
  processes: z.number(),
  segments: z.number(),
  openSegments: z.number(),
  lastCapturedAt: z.string().nullable(),
});

export const LooseUsageModelEntrySchema = z.object({
  model: z.string(),
  costUsd: z.number().nullable(),
  totalTokens: z.number().nullable(),
  segments: z.number(),
});

export const LooseUsageComparisonSideSchema = z.object({
  costUsd: z.number().nullable(),
  totalTokens: z.number().nullable(),
  blendedCostPerMtok: z.number().nullable(),
});

export const LooseUsageComparisonSchema = z.object({
  loose: LooseUsageComparisonSideSchema,
  pipeline: LooseUsageComparisonSideSchema,
});

export const LooseUsageCoverageSchema = z.object({
  rowsTotal: z.number().nullable(),
  segmentsTotal: z.number().nullable(),
  segmentsOpen: z.number().nullable(),
  processes: z.number().nullable(),
  projects: z.number().nullable(),
  lastCapturedAt: z.string().nullable(),
});

export const LooseUsageResultSchema = z.object({
  byProject: z.array(LooseUsageProjectEntrySchema),
  byModel: z.array(LooseUsageModelEntrySchema),
  comparison: LooseUsageComparisonSchema,
  coverage: LooseUsageCoverageSchema,
});

// ---------------------------------------------------------------------------
// PlanUsage DTOs schema (schema v14, `plan_usage`, cstk 7.2.0) — gauge
// `rate_limits` da CONTA. Mesmo padrao dos demais: sem `.default(null)`.
// ---------------------------------------------------------------------------
export const PlanUsageScopeStateSchema = z.object({
  // `scope` fica como z.string() e NAO como z.enum(['five_hour','seven_day']):
  // o CHECK vive na origem, e um escopo novo do cstk deve aparecer na tela em
  // vez de derrubar o parse da resposta inteira (Principio II).
  scope: z.string(),
  usedPercentage: z.number().nullable(),
  // epoch em SEGUNDOS — nao converter para Date/ISO na borda de validacao.
  resetsAt: z.number().nullable(),
  capturedAt: z.string().nullable(),
  peakUsedPercentage: z.number().nullable(),
  captures: z.number(),
});

export const PlanUsagePointSchema = z.object({
  scope: z.string(),
  capturedAt: z.string(),
  usedPercentage: z.number().nullable(),
});

export const PlanUsageCoverageSchema = z.object({
  rowsTotal: z.number().nullable(),
  scopes: z.number().nullable(),
  sessions: z.number().nullable(),
  projects: z.number().nullable(),
  firstCapturedAt: z.string().nullable(),
  lastCapturedAt: z.string().nullable(),
});

export const PlanUsageResultSchema = z.object({
  byScope: z.array(PlanUsageScopeStateSchema),
  series: z.array(PlanUsagePointSchema),
  coverage: PlanUsageCoverageSchema,
  seriesTruncated: z.boolean(),
});

// ---------------------------------------------------------------------------
// DecisionDTO schema
// ---------------------------------------------------------------------------
export const DecisionDTOSchema = z.object({
  wave: z.string(),
  executionId: z.string(),
  stage: z.string().nullable(),
  agent: z.string().nullable(),
  choice: z.string().nullable(),
  options: z.string().nullable(),
  score: z.union([z.literal(0), z.literal(1), z.literal(2), z.literal(3)]).nullable(),
  context: z.string().nullable(),
  rationale: z.string().nullable(),
  evidencia: z.string().nullable(),
  decisionClass: z.string().nullable(),
  structuralAxis: z.string().nullable(),
  humanConsentBlockId: z.string().nullable(),
});

// ---------------------------------------------------------------------------
// TaskDTO schema
// ---------------------------------------------------------------------------
export const TaskDTOSchema = z.object({
  wave: z.string(),
  executionId: z.string(),
  title: z.string(),
  outcome: z.enum(['pass', 'fail']).nullable(),
  testsRun: z.number().nullable(),
  testsPassed: z.number().nullable(),
  lintOk: z.boolean().nullable(),
  touchedFilesCount: z.number().nullable(),
});

// ---------------------------------------------------------------------------
// EventDTO schema
// ---------------------------------------------------------------------------
export const EventDTOSchema = z.object({
  executionId: z.string(),
  eventType: z.enum(['lock_contention', 'validation_failed', 'wave_retry', 'schedule_wait', 'recall_consulted']),
  timestamp: z.string(),
  description: z.string().nullable(),
});

// ---------------------------------------------------------------------------
// AlertSignalDTO schema
// ---------------------------------------------------------------------------
export const AlertSignalDTOSchema = z.object({
  executionId: z.string(),
  type: z.enum(['circular', 'budget_breach']),
  subtype: z.string().nullable(),
  consumedValue: z.number().nullable(),
  thresholdValue: z.number().nullable(),
  description: z.string().nullable(),
  wave: z.string(),
});

// ---------------------------------------------------------------------------
// BlockDTO schema
// ---------------------------------------------------------------------------
export const BlockDTOSchema = z.object({
  executionId: z.string(),
  status: z.string().nullable(),
  question: z.string().nullable(),
  contextForAnswer: z.string().nullable(),
  answer: z.string().nullable(),
  decisionId: z.string().nullable(),
  triggeredAt: z.string().nullable(),
  answeredAt: z.string().nullable(),
  latencySeconds: z.number().nullable(),
});

// ---------------------------------------------------------------------------
// SkillDTO schema
// ---------------------------------------------------------------------------
export const SkillDTOSchema = z.object({
  executionId: z.string(),
  skillName: z.string(),
  decisionId: z.string().nullable(),
  wave: z.string(),
});

// ---------------------------------------------------------------------------
// RetroDTO schema
// ---------------------------------------------------------------------------
export const RetroDTOSchema = z.object({
  executionId: z.string(),
  text: z.string().nullable(),
  wave: z.string(),
});

// ---------------------------------------------------------------------------
// FtsHitDTO schema
// ---------------------------------------------------------------------------
export const FtsHitDTOSchema = z.object({
  body: z.string(),
  type: z.string(),
  project: z.string(),
  feature: z.string(),
  wave: z.string(),
  sourceId: z.string(),
  sourceTs: z.string(),
  rank: z.number(),
  // Execucao de origem resolvida a partir de (project, feature, wave, source_id)
  // na tabela-fonte do tipo. Ausente para tipos sem vinculo de execucao (ex.: memory).
  executionId: z.string().optional(),
});

// ---------------------------------------------------------------------------
// MemoryDTO schema (schema v4 — feature recall-memory-mirror)
// ---------------------------------------------------------------------------
export const MemoryDTOSchema = z.object({
  project: z.string(),
  slug: z.string(),
  type: z.enum(['index', 'feedback', 'project', 'reference', 'user']),
  description: z.string().nullable(),
  body: z.string().nullable(),
  path: z.string().nullable(),
  indexedAt: z.string().nullable(),
});

// ---------------------------------------------------------------------------
// SuggestionDTO schema (schema v7 EN — feature recall-suggestions)
// ---------------------------------------------------------------------------
export const SuggestionDTOSchema = z.object({
  executionId: z.string(),
  sourceId: z.string(),
  affectedSkill: z.string().nullable(),
  severity: z.enum(['informativa', 'aviso', 'impeditiva']).nullable(),
  diagnosis: z.string().nullable(),
  proposal: z.string().nullable(),
  referencias: z.array(z.string()),
  issueOpened: z.string().nullable(),
  createdAt: z.string().nullable(),
});

// ---------------------------------------------------------------------------
// FeatureDocDTO / FeatureDocsListDTO schema (feature state-watchers-and-docs)
// Espelha EXATAMENTE os campos de entities.ts (task 1.2.1) — dual-def.
// ---------------------------------------------------------------------------
export const FeatureDocStageSchema = z.enum([
  'briefing', 'constitution', 'roadmap', 'specify', 'plan', 'checklist',
  'create-tasks', 'converge',
]);

export const FeatureDocScopeSchema = z.enum(['project', 'feature']);

export const FeatureDocDTOSchema = z.object({
  stage: FeatureDocStageSchema,
  artifactId: z.string(),
  scope: FeatureDocScopeSchema,
  fileName: z.string(),
  produced: z.boolean(),
  extra: z.boolean(),
  content: z.string().nullable().optional(),
});

export const FeatureDocsListDTOSchema = z.object({
  project: z.string(),
  feature: z.string(),
  artifacts: z.array(FeatureDocDTOSchema),
});

// ---------------------------------------------------------------------------
// Rollup schemas
// ---------------------------------------------------------------------------
export const ProjectRollupSchema = z.object({
  project: z.string(),
  totalExecutions: z.number(),
  activeExecutions: z.number(),
  completedExecutions: z.number(),
  abortedExecutions: z.number(),
  totalDecisions: z.number(),
  totalToolCalls: z.number().nullable(),
  totalWallclock: z.number().nullable().optional(),
  openAlerts: z.number().optional(),
  latestExecutionAt: z.string().nullable(),
  agentUsage: AgentUsageRollupSchema.nullable().optional(),
  otelUsage: OtelUsageRollupSchema.nullable().optional(),
});

export const FeatureRollupSchema = z.object({
  project: z.string(),
  feature: z.string(),
  totalExecutions: z.number(),
  activeExecutions: z.number(),
  completedExecutions: z.number(),
  abortedExecutions: z.number(),
  totalToolCalls: z.number().nullable().optional(),
  totalWallclock: z.number().nullable().optional(),
  totalDecisions: z.number().optional(),
  totalWaves: z.number().nullable().optional(),
  totalBlocks: z.number().optional(),
  currentStage: z.string().nullable().optional(),
  openAlerts: z.number().optional(),
  latestStatus: z.enum(['em_andamento', 'aguardando_humano', 'concluida', 'abortada']).nullable(),
  latestExecutionAt: z.string().nullable(),
  agentUsage: AgentUsageRollupSchema.nullable().optional(),
  otelUsage: OtelUsageRollupSchema.nullable().optional(),
});

// ---------------------------------------------------------------------------
// Params schemas
// ---------------------------------------------------------------------------
export const PaginationParamsSchema = z.object({
  limit: z.number().int().min(1).max(200),
  offset: z.number().int().min(0),
});

export const PeriodParamSchema = z.enum(['24h', '7d', '30d', 'all']);

export const ScoreParamSchema = z.union([
  z.literal(0), z.literal(1), z.literal(2), z.literal(3),
]);

export const SearchParamsSchema = PaginationParamsSchema.extend({
  q: z.string().min(1),
  type: z.string().optional(),
  project: z.string().optional(),
  feature: z.string().optional(),
});

// ---------------------------------------------------------------------------
// SessionSummaryDTO schema (feature session-tail, data-model.md)
// ---------------------------------------------------------------------------
export const SessionSummaryDTOSchema = z.object({
  sessionId: z.string(),
  projectPath: z.string().nullable(),
  projectSlug: z.string(),
  lastActivityAt: z.string(),
  live: z.boolean(),
  sizeBytes: z.number(),
});

// ---------------------------------------------------------------------------
// SessionTailEntryDTO schema (feature session-tail, data-model.md)
// ---------------------------------------------------------------------------
export const SessionTailEntryDTOSchema = z.object({
  uuid: z.string().nullable(),
  type: z.string(), // conjunto ABERTO (harness do Claude Code) — NUNCA z.enum()
  timestamp: z.string().nullable(),
  role: z.string().nullable(),
  text: z.string(),
  textTruncated: z.boolean(),
  // FECHADO de proposito: quem define `kind` e o painel, nao o harness.
  kind: z.enum(['text', 'tool_use', 'tool_result']),
  toolName: z.string().nullable(),
});

// ---------------------------------------------------------------------------
// Intervention* schemas (feature human-bridge, contracts/panel-bridge-api.md)
// ---------------------------------------------------------------------------
export const InterventionKindSchema = z.enum(['choice', 'confirm', 'text']);
export const InterventionExecutionKindSchema = z.enum(['agente-00c', 'feature-00c']);
export const InterventionStateSchema = z.enum(['open', 'answered', 'declined', 'expired']);

// Base sem `.superRefine()` — exportada A PARTE so para introspeccao de
// CHAVES (`.shape`) por testes de paridade (`.superRefine()` devolve um
// `ZodEffects` que nao expoe `.shape`). Uso normal de validacao MUST
// continuar via `CreateInterventionRequestDTOSchema` (com o refine).
export const CreateInterventionRequestDTOBaseSchema = z.object({
  projectPath: z.string().min(1),
  project: z.string().min(1),
  shortName: z.string().nullable(),
  executionKind: InterventionExecutionKindSchema,
  kind: InterventionKindSchema,
  question: z.string().min(1),
  options: z.array(z.string()).nullable(),
  defaultValue: z.string().min(1),
  timeoutMs: z.number().int().positive(),
});

export const CreateInterventionRequestDTOSchema = CreateInterventionRequestDTOBaseSchema.superRefine((val, ctx) => {
    if (val.kind === 'choice' && (!val.options || val.options.length === 0)) {
      ctx.addIssue({
        code: 'custom',
        path: ['options'],
        message: "options obrigatorio (>=1 item) quando kind='choice' (contrato §4)",
      });
    }
  });

export const CreateInterventionResponseDTOSchema = z.object({
  questionId: z.string(),
  expiresAt: z.string(),
  state: z.literal('open'),
});

export const PollInterventionResponseDTOSchema = z.object({
  questionId: z.string(),
  state: InterventionStateSchema,
  appliedValue: z.string().nullable(),
  untrustedText: z.string().nullable(),
  resolvedAt: z.string().nullable(),
});

export const InterventionQueueItemDTOSchema = z.object({
  questionId: z.string(),
  project: z.string(),
  shortName: z.string().nullable(),
  executionKind: InterventionExecutionKindSchema,
  kind: InterventionKindSchema,
  question: z.string(),
  options: z.array(z.string()).nullable(),
  defaultValue: z.string(),
  state: InterventionStateSchema,
  reachable: z.boolean(),
  createdAt: z.string(),
  expiresAt: z.string(),
  waitingMs: z.number(),
  appliedValue: z.string().nullable(),
  untrustedText: z.string().nullable(),
  resolvedAt: z.string().nullable(),
});

export const InterventionsQueueResultDTOSchema = z.object({
  interventions: z.array(InterventionQueueItemDTOSchema),
  pagination: PaginationParamsSchema,
});

export const AnswerInterventionRequestDTOSchema = z
  .object({
    resolution: z.enum(['answered', 'declined']),
    value: z.string().nullable().optional(),
    text: z.string().nullable().optional(),
  })
  .superRefine((val, ctx) => {
    if (val.resolution === 'answered' && (val.value === undefined || val.value === null || val.value === '')) {
      ctx.addIssue({
        code: 'custom',
        path: ['value'],
        message: "value obrigatorio quando resolution='answered' (contrato §7)",
      });
    }
  });
