/**
 * Schemas Zod para parametros de request — reutilizaveis no server (query params)
 * e no web (validacao de URL params).
 * Ref: plan.md §Convencoes de Borda; spec.md FR-012
 */
export {
  PaginationParamsSchema,
  PeriodParamSchema,
  ScoreParamSchema,
  SearchParamsSchema,
} from './entities.js';
