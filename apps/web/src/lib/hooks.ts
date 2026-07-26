/**
 * Hooks TanStack Query para cada recurso principal da API.
 * Cada hook usa fetchApi<T> com schema Zod do shared-types.
 */
import { useQuery } from '@tanstack/react-query';
import { fetchApi } from './api.js';
import {
  ExecutionDTOSchema,
  WaveDTOSchema,
  DecisionDTOSchema,
  TaskDTOSchema,
  EventDTOSchema,
  AlertSignalDTOSchema,
  BlockDTOSchema,
  SkillDTOSchema,
  ProjectRollupSchema,
  FeatureRollupSchema,
  FtsHitDTOSchema,
  MemoryDTOSchema,
  SuggestionDTOSchema,
  FeatureDocsListDTOSchema,
  FeatureDocDTOSchema,
  type PeriodParam,
} from '@cstk-panel/shared-types';
import { z } from 'zod';

// ---- Schemas de arrays (sub-recursos de execucao retornam array puro) ----
const WaveListSchema = z.array(WaveDTOSchema);
const EventListSchema = z.array(EventDTOSchema);
const AlertListSchema = z.array(AlertSignalDTOSchema);
const BlockListSchema = z.array(BlockDTOSchema);
const SkillListSchema = z.array(SkillDTOSchema);
const SuggestionListSchema = z.array(SuggestionDTOSchema);
const ProjectListSchema = z.array(ProjectRollupSchema);
const FeatureListSchema = z.array(FeatureRollupSchema);

// ---- Schemas de objetos paginados/embrulhados ----
// Endpoints paginados retornam `data: { <chave>: [...], pagination }`
// (ver apps/server/src/routes/*.ts) — NAO sao arrays puros.
const PaginationMetaSchema = z.object({
  total: z.number(),
  limit: z.number(),
  offset: z.number(),
  hasMore: z.boolean(),
});
export const DecisionsPageSchema = z.object({
  decisions: z.array(DecisionDTOSchema),
  pagination: PaginationMetaSchema,
});
export const TasksResultSchema = z.object({
  passRate: z.number().nullable(),
  tasks: z.array(TaskDTOSchema),
});
export const AlertsPageSchema = z.object({
  alerts: z.array(AlertSignalDTOSchema),
  pagination: PaginationMetaSchema,
});
export const SearchPageSchema = z.object({
  results: z.array(FtsHitDTOSchema),
  pagination: PaginationMetaSchema,
});
export const ExecutionsPageSchema = z.object({
  executions: z.array(ExecutionDTOSchema),
  pagination: PaginationMetaSchema,
});
export const MemoriesPageSchema = z.object({
  memories: z.array(MemoryDTOSchema),
  projects: z.array(z.string()),
  pagination: PaginationMetaSchema,
});
// Listas cross-execucao (tasks/events globais) carregam project/feature alem
// do DTO base — passthrough para nao descartar a proveniencia.
const TasksListPageSchema = z.object({
  tasks: z.array(z.object({}).passthrough()),
  pagination: z.object({}).passthrough(),
});
const EventsListPageSchema = z.object({
  events: z.array(z.object({}).passthrough()),
  pagination: z.object({}).passthrough(),
});

// Overview KPI — schema livre (endpoint retorna objeto ad-hoc)
const OverviewDataSchema = z.object({}).passthrough();

// Detalhe de projeto/feature — objetos compostos (rollup + listas aninhadas).
// Passthrough: o shape e validado nas bordas de cada sub-recurso; aqui so
// garantimos objeto (ou null quando inexistente).
const ProjectDetailSchema = z.object({}).passthrough().nullable();
const FeatureDetailSchema = z.object({}).passthrough().nullable();

// Metrics — schema livre por endpoint
const MetricDataSchema = z.unknown();

/** Visao geral com KPIs, alertas recentes, leaderboard. Filtro opcional por project. */
export function useOverview(period: PeriodParam = '7d', project = '') {
  const projectQ = project ? `&project=${encodeURIComponent(project)}` : '';
  return useQuery({
    queryKey: ['overview', period, project],
    queryFn: () => fetchApi(`/overview?period=${period}${projectQ}`, OverviewDataSchema),
  });
}

/** Lista de projetos (rollup) */
export function useProjects() {
  return useQuery({
    queryKey: ['projects'],
    queryFn: () => fetchApi('/projects', ProjectListSchema),
  });
}

/** Detalhe de um projeto */
export function useProject(project: string) {
  return useQuery({
    queryKey: ['projects', project],
    queryFn: () => fetchApi(`/projects/${encodeURIComponent(project)}`, ProjectDetailSchema),
    enabled: Boolean(project),
  });
}

/** Lista de features (filtravel) */
export function useFeatures(project?: string, status?: string) {
  const params = new URLSearchParams();
  if (project) params.set('project', project);
  if (status) params.set('status', status);
  const qs = params.toString() ? `?${params.toString()}` : '';
  return useQuery({
    queryKey: ['features', project, status],
    queryFn: () => fetchApi(`/features${qs}`, FeatureListSchema),
  });
}

/** Detalhe de uma feature */
export function useFeature(project: string, feature: string) {
  return useQuery({
    queryKey: ['features', project, feature],
    queryFn: () => fetchApi(`/features/${encodeURIComponent(project)}/${encodeURIComponent(feature)}`, FeatureDetailSchema),
    enabled: Boolean(project) && Boolean(feature),
  });
}

/**
 * Doc-viewer (task 4.2): listagem + conteudo de artefatos de documentacao
 * SDD de uma feature. Usa `fetchApi` diretamente — MESMO padrao de todos os
 * demais hooks deste arquivo (nenhum recurso tem uma camada de funcoes
 * nomeadas separada em `api.ts`; `fetchApi` ja E a funcao de fetch tipada
 * com parse Zod do envelope que a task 4.2.1 pede, so que compartilhada).
 * Contrato: contracts/docs-api.md; DTOs (dual-def) de 1.2.
 */

/** Path da listagem de docs de uma feature — extraida para teste unitario
 *  direto do encoding (segmentos com `/`, espaco, etc.) sem precisar
 *  invocar o hook (regra de hooks do React impede chamar `use*` fora de
 *  render — ver hooks-docs.test.ts). */
export function featureDocsPath(project: string, feature: string): string {
  return `/features/${encodeURIComponent(project)}/${encodeURIComponent(feature)}/docs`;
}

/** Path do conteudo de UM artefato de documentacao. */
export function featureDocPath(project: string, feature: string, artifactId: string): string {
  return `${featureDocsPath(project, feature)}/${encodeURIComponent(artifactId)}`;
}

/** Lista de artefatos de documentacao de uma feature (metadados, sem `content`) */
export function useFeatureDocs(project: string, feature: string) {
  return useQuery({
    queryKey: ['feature-docs', project, feature],
    queryFn: () => fetchApi(featureDocsPath(project, feature), FeatureDocsListDTOSchema),
    enabled: Boolean(project) && Boolean(feature),
  });
}

/** Conteudo (markdown bruto, UNTRUSTED) de UM artefato de documentacao.
 *  `data: null` quando `artifactId` nao reconhecido (nem mapa fixo nem
 *  extra); `data.produced: false` + `content: null` quando "ainda nao
 *  produzido" (FR-007) — em nenhum dos dois casos e erro. */
export function useFeatureDocContent(project: string, feature: string, artifactId: string) {
  return useQuery({
    queryKey: ['feature-doc-content', project, feature, artifactId],
    queryFn: () => fetchApi(featureDocPath(project, feature, artifactId), FeatureDocDTOSchema.nullable()),
    enabled: Boolean(project) && Boolean(feature) && Boolean(artifactId),
  });
}

/** Lista paginada de execucoes */
export function useExecutions(limit = 20, offset = 0) {
  return useQuery({
    queryKey: ['executions', limit, offset],
    queryFn: () => fetchApi(`/executions?limit=${limit}&offset=${offset}`, ExecutionsPageSchema),
  });
}

/** Detalhe de uma execucao */
export function useExecution(execucaoId: string) {
  return useQuery({
    queryKey: ['executions', execucaoId],
    queryFn: () => fetchApi(`/executions/${encodeURIComponent(execucaoId)}`, ExecutionDTOSchema.nullable()),
    enabled: Boolean(execucaoId),
  });
}

/** Ondas de uma execucao */
export function useWaves(execucaoId: string) {
  return useQuery({
    queryKey: ['waves', execucaoId],
    queryFn: () => fetchApi(`/executions/${encodeURIComponent(execucaoId)}/waves`, WaveListSchema),
    enabled: Boolean(execucaoId),
  });
}

/** Decisoes paginadas de uma execucao */
export function useDecisions(
  execucaoId: string,
  opts?: { wave?: string; etapa?: string; score?: number; limit?: number; offset?: number }
) {
  const params = new URLSearchParams();
  if (opts?.wave) params.set('wave', opts.wave);
  if (opts?.etapa) params.set('etapa', opts.etapa);
  if (opts?.score != null) params.set('score', String(opts.score));
  if (opts?.limit) params.set('limit', String(opts.limit));
  if (opts?.offset) params.set('offset', String(opts.offset));
  const qs = params.toString() ? `?${params.toString()}` : '';
  return useQuery({
    queryKey: ['decisions', execucaoId, opts],
    queryFn: () => fetchApi(`/executions/${encodeURIComponent(execucaoId)}/decisions${qs}`, DecisionsPageSchema),
    enabled: Boolean(execucaoId),
  });
}

/** Tarefas de uma execucao */
export function useTasks(execucaoId: string) {
  return useQuery({
    queryKey: ['tasks', execucaoId],
    queryFn: () => fetchApi(`/executions/${encodeURIComponent(execucaoId)}/tasks`, TasksResultSchema),
    enabled: Boolean(execucaoId),
  });
}

/** Eventos de uma execucao */
export function useEvents(execucaoId: string) {
  return useQuery({
    queryKey: ['events', execucaoId],
    queryFn: () => fetchApi(`/executions/${encodeURIComponent(execucaoId)}/events`, EventListSchema),
    enabled: Boolean(execucaoId),
  });
}

/** Alertas de uma execucao */
export function useAlertsByExecution(execucaoId: string) {
  return useQuery({
    queryKey: ['alerts-exec', execucaoId],
    queryFn: () => fetchApi(`/executions/${encodeURIComponent(execucaoId)}/alerts`, AlertListSchema),
    enabled: Boolean(execucaoId),
  });
}

/** Bloqueios de uma execucao */
export function useBloqueios(execucaoId: string) {
  return useQuery({
    queryKey: ['bloqueios', execucaoId],
    queryFn: () => fetchApi(`/executions/${encodeURIComponent(execucaoId)}/bloqueios`, BlockListSchema),
    enabled: Boolean(execucaoId),
  });
}

/** Skills de uma execucao */
export function useSkills(execucaoId: string) {
  return useQuery({
    queryKey: ['skills', execucaoId],
    queryFn: () => fetchApi(`/executions/${encodeURIComponent(execucaoId)}/skills`, SkillListSchema),
    enabled: Boolean(execucaoId),
  });
}

/** Sugestoes de melhoria da IA de uma execucao (schema v5). [] em bases v<5. */
export function useSuggestions(execucaoId: string) {
  return useQuery({
    queryKey: ['suggestions', execucaoId],
    queryFn: () => fetchApi(`/executions/${encodeURIComponent(execucaoId)}/suggestions`, SuggestionListSchema),
    enabled: Boolean(execucaoId),
  });
}

// Distribuicao de score (0..3) de uma execucao (card lateral)
const ScoreDistSchema = z.array(z.object({ score: z.number(), count: z.number() }));

/** Distribuicao de decisoes por score de uma execucao */
export function useScoreDistribution(execucaoId: string) {
  return useQuery({
    queryKey: ['score-dist', execucaoId],
    queryFn: () => fetchApi(`/executions/${encodeURIComponent(execucaoId)}/score-distribution`, ScoreDistSchema),
    enabled: Boolean(execucaoId),
  });
}

/** Alertas cross-execucao */
export function useAlerts(opts?: { type?: string; project?: string; feature?: string; period?: PeriodParam }) {
  const params = new URLSearchParams();
  if (opts?.type) params.set('type', opts.type);
  if (opts?.project) params.set('project', opts.project);
  if (opts?.feature) params.set('feature', opts.feature);
  if (opts?.period) params.set('period', opts.period);
  const qs = params.toString() ? `?${params.toString()}` : '';
  return useQuery({
    queryKey: ['alerts', opts],
    queryFn: () => fetchApi(`/alerts${qs}`, AlertsPageSchema),
  });
}

/** Tasks cross-execucao (tela Tarefas) */
export function useTasksList(opts?: { project?: string; feature?: string; outcome?: 'pass' | 'fail' }) {
  const params = new URLSearchParams();
  if (opts?.project) params.set('project', opts.project);
  if (opts?.feature) params.set('feature', opts.feature);
  if (opts?.outcome) params.set('outcome', opts.outcome);
  params.set('limit', '200');
  return useQuery({
    queryKey: ['tasks-list', opts],
    queryFn: () => fetchApi(`/tasks?${params.toString()}`, TasksListPageSchema),
  });
}

/** Eventos cross-execucao (tela Incidentes) */
export function useEventsList(opts?: { eventType?: string; project?: string; period?: PeriodParam }) {
  const params = new URLSearchParams();
  if (opts?.eventType) params.set('event_type', opts.eventType);
  if (opts?.project) params.set('project', opts.project);
  if (opts?.period) params.set('period', opts.period);
  params.set('limit', '200');
  return useQuery({
    queryKey: ['events-list', opts],
    queryFn: () => fetchApi(`/events?${params.toString()}`, EventsListPageSchema),
  });
}

/** Auto-memorias do Claude Code (tela Memorias, schema v4). Filtro por projeto. */
export function useMemories(project?: string) {
  const params = new URLSearchParams();
  if (project) params.set('project', project);
  params.set('limit', '100');
  const qs = params.toString() ? `?${params.toString()}` : '';
  return useQuery({
    queryKey: ['memories', project],
    queryFn: () => fetchApi(`/memories${qs}`, MemoriesPageSchema),
  });
}

/** Busca FTS5 */
export function useSearch(
  q: string,
  opts?: { type?: string; project?: string; feature?: string; limit?: number; offset?: number }
) {
  const params = new URLSearchParams({ q });
  if (opts?.type) params.set('type', opts.type);
  if (opts?.project) params.set('project', opts.project);
  if (opts?.feature) params.set('feature', opts.feature);
  if (opts?.limit) params.set('limit', String(opts.limit));
  if (opts?.offset) params.set('offset', String(opts.offset));
  return useQuery({
    queryKey: ['search', q, opts],
    queryFn: () => fetchApi(`/search?${params.toString()}`, SearchPageSchema),
    enabled: q.length >= 2,
  });
}

// ---- Health / Fonte de Dados ----
// Schema local (health e especifico do servidor, nao um DTO de dominio).
const HealthDataSchema = z.object({
  ok: z.boolean(),
  dbReachable: z.boolean(),
  quickCheck: z.boolean(),
  path: z.string(),
  sizeBytes: z.number().nullable(),
  counts: z.object({
    executions: z.number(),
    waves: z.number(),
    decisions: z.number(),
    tasks: z.number(),
    events: z.number(),
    alertSignals: z.number(),
    bloqueios: z.number(),
    skills: z.number(),
    retros: z.number(),
    memories: z.number(),
    ftsDecisoes: z.number(),
    ftsRetros: z.number(),
  }),
});

export type HealthData = z.infer<typeof HealthDataSchema>;

/** Saude do servidor + DB (tela Fonte de Dados, frescor da Sidebar). */
export function useHealth() {
  return useQuery({
    queryKey: ['health'],
    queryFn: () => fetchApi('/health', HealthDataSchema),
  });
}

/** Metrica por nome */
export function useMetric(
  name: 'cost-over-time' | 'throughput-by-stage' | 'test-pass-rate' | 'test-pass-rate-series'
       | 'human-latency' | 'clarify-resolution' | 'decisions-by-score' | 'execution-duration' | 'depth-subagents'
       | 'model-mix' | 'model-mix-by-stage' | 'recall-consultations'
       // schema v10 — consumo medido de subagentes (nao proxy)
       | 'agent-usage' | 'tokens-over-time' | 'tokens-by-wave',
  period?: PeriodParam
) {
  const qs = period ? `?period=${period}` : '';
  return useQuery({
    queryKey: ['metrics', name, period],
    queryFn: () => fetchApi(`/metrics/${name}${qs}`, MetricDataSchema),
  });
}
