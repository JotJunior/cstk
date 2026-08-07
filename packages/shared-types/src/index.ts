/**
 * @cstk-panel/shared-types — ponto de entrada unico.
 * Reexporta todos os tipos e schemas Zod.
 *
 * Principio V: campos UNTRUSTED marcados com @untrusted nos DTOs.
 * Principio III: `toolCallsTotal` / `toolCalls` sao proxies — rotular na UI.
 */

// Tipos de envelope
export type { Freshness, Meta, ApiEnvelope, DegradedReason } from './envelope.js';

// DTOs de dominio
export type {
  ExecutionDTO,
  WaveDTO,
  DecisionDTO,
  TaskDTO,
  EventDTO,
  AlertSignalDTO,
  BlockDTO,
  SkillDTO,
  RetroDTO,
  FtsHitDTO,
  MemoryDTO,
  MemoryType,
  SuggestionDTO,
  SuggestionSeveridade,
  FeatureDocDTO,
  FeatureDocStage,
  FeatureDocScope,
  FeatureDocsListDTO,
  ProjectRollup,
  FeatureRollup,
  AgentUsageRollup,
  OtelUsageRollup,
  ModelUsageEntry,
  ModelUsageByStage,
  ModelUsageCoverage,
  ModelUsageResult,
  LooseUsageProjectEntry,
  LooseUsageModelEntry,
  LooseUsageComparisonSide,
  LooseUsageComparison,
  LooseUsageCoverage,
  LooseUsageResult,
  PaginationParams,
  PeriodParam,
  ScoreParam,
  SearchParams,
} from './entities.js';

// Schemas Zod — envelope
export {
  FreshnessSchema,
  MetaSchema,
  ApiEnvelopeSchema,
  RawApiEnvelopeSchema,
} from './schemas/envelope.js';

// Schemas Zod — entidades
export {
  ExecutionDTOSchema,
  WaveDTOSchema,
  DecisionDTOSchema,
  TaskDTOSchema,
  EventDTOSchema,
  AlertSignalDTOSchema,
  BlockDTOSchema,
  SkillDTOSchema,
  RetroDTOSchema,
  FtsHitDTOSchema,
  MemoryDTOSchema,
  SuggestionDTOSchema,
  FeatureDocStageSchema,
  FeatureDocScopeSchema,
  FeatureDocDTOSchema,
  FeatureDocsListDTOSchema,
  ProjectRollupSchema,
  FeatureRollupSchema,
  AgentUsageRollupSchema,
  OtelUsageRollupSchema,
  ModelUsageEntrySchema,
  ModelUsageByStageSchema,
  ModelUsageCoverageSchema,
  ModelUsageResultSchema,
  LooseUsageProjectEntrySchema,
  LooseUsageModelEntrySchema,
  LooseUsageComparisonSideSchema,
  LooseUsageComparisonSchema,
  LooseUsageCoverageSchema,
  LooseUsageResultSchema,
} from './schemas/entities.js';

// Schemas Zod — params
export {
  PaginationParamsSchema,
  PeriodParamSchema,
  ScoreParamSchema,
  SearchParamsSchema,
} from './schemas/params.js';
